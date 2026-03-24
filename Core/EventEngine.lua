-- Core/EventEngine.lua
-- Owns the WoW event frame. On PLAYER_LOGIN, selects the chain provider and
-- triggers the initial cache build. On quest events, rebuilds QuestCache,
-- diffs old vs. new state at quest and objective granularity, and fires
-- AQL callbacks via CallbackHandler.
--
-- Re-entrancy guard: if QUEST_LOG_UPDATE fires while a diff is already running,
-- the second call is silently dropped. This is a known limitation — in normal
-- gameplay the next natural event will catch any missed state.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local EventEngine = {}
AQL.EventEngine = EventEngine

-- EventEngine writes reason strings here (AQL.FailReason.Timeout, AQL.FailReason.EscortDied, or nil);
-- QuestCache reads during _buildEntry to populate QuestInfo.failReason.
-- (QuestCache.failedSet is initialized in QuestCache.lua; we just write to it.)

EventEngine.diffInProgress   = false
EventEngine.initialized      = false
EventEngine.pendingTurnIn    = {}  -- questIDs currently awaiting QUEST_REMOVED after turn-in confirmation

-- Hidden event frame.
local frame = CreateFrame("Frame")
EventEngine.frame = frame

-- Number of deferred 1-second retry attempts after the initial frame-0 attempt.
-- Total checks: 1 immediate (t=0) + 5 retries (t=1s–5s) = 6 total, up to 5 s.
local MAX_DEFERRED_UPGRADE_ATTEMPTS = 5

-- QUEST_TURNED_IN does not fire in TBC Classic (Interface 20505).
-- Hook GetQuestReward instead: it fires synchronously when the player clicks
-- the confirm button, before items are transferred. GetQuestID() returns the
-- active questID at this point. This sets pendingTurnIn so that any objective
-- regression events fired during item transfer are suppressed.
-- The hook fires only on confirmation; cancelling the reward screen does not
-- call GetQuestReward, so pendingTurnIn is never set on cancel.
hooksecurefunc("GetQuestReward", function()
    local questID = GetQuestID()
    if questID and questID ~= 0 then
        EventEngine.pendingTurnIn[questID] = true
        if AQL.debug then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] pendingTurnIn set: questID=" .. tostring(questID) .. AQL.RESET)
        end
    end
end)

------------------------------------------------------------------------
-- Provider selection
------------------------------------------------------------------------

local function selectProvider()
    -- Try Questie first.
    local ok1, result1 = pcall(function()
        return AQL.QuestieProvider
            and AQL.QuestieProvider:IsAvailable()
            and AQL.QuestieProvider
    end)
    if ok1 and result1 then
        return result1, "Questie"
    end

    -- Try QuestWeaver.
    local ok2, result2 = pcall(function()
        return AQL.QuestWeaverProvider
            and AQL.QuestWeaverProvider:IsAvailable()
            and AQL.QuestWeaverProvider
    end)
    if ok2 and result2 then
        return result2, "QuestWeaver"
    end

    -- Fallback.
    return AQL.NullProvider, "none"
end

-- Retries provider selection until a real provider is found or attempts run out.
-- Called once from PLAYER_LOGIN via C_Timer.After(0, ...) so it fires after all
-- other addons' PLAYER_LOGIN handlers complete. Retries every 1 s for up to 5 s
-- to catch Questie, whose async init coroutine takes ~3 s.
-- On success, rebuilds the cache immediately so chain data is populated without
-- waiting for the next game event. The old-cache return value from Rebuild() is
-- intentionally discarded — no diff is needed, only a data refresh.
local function tryUpgradeProvider(attemptsLeft)
    if AQL.provider ~= AQL.NullProvider then return end  -- already upgraded

    local provider, providerName = selectProvider()
    if provider ~= AQL.NullProvider then
        AQL.provider = provider
        if AQL.debug then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Provider upgraded: " .. tostring(providerName) .. AQL.RESET)
        end
        AQL.QuestCache:Rebuild()
        return
    end

    if attemptsLeft > 0 then
        if AQL.debug then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Provider upgrade attempt " ..
                  tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS - attemptsLeft + 1) ..
                  "/" .. tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS) ..
                  " — still on NullProvider" .. AQL.RESET)
        end
        C_Timer.After(1, function() tryUpgradeProvider(attemptsLeft - 1) end)
    end
end

------------------------------------------------------------------------
-- Diff + dispatch logic
------------------------------------------------------------------------

local function runDiff(oldCache)
    if EventEngine.diffInProgress then
        if AQL.debug == "verbose" then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] runDiff: skipped (already in progress)" .. AQL.RESET)
        end
        return
    end
    EventEngine.diffInProgress = true
    if AQL.debug == "verbose" then
        local oldCount, newCount = 0, 0
        for _ in pairs(oldCache) do oldCount = oldCount + 1 end
        for _ in pairs(AQL.QuestCache.data) do newCount = newCount + 1 end
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] runDiff: start — old=" .. tostring(oldCount) ..
              " new=" .. tostring(newCount) .. " quests" .. AQL.RESET)
    end

    local ok, err = pcall(function()
        local newCache = AQL.QuestCache.data
        local histCache = AQL.HistoryCache

        -- Detect newly accepted quests (in new, not in old).
        for questID, newInfo in pairs(newCache) do
            if not oldCache[questID] then
                if histCache and histCache:HasCompleted(questID) then
                    -- Quest was already completed historically; ignore as a new accept.
                    -- (Can happen at login when cache first builds.)
                else
                    AQL.callbacks:Fire(AQL.Event.QuestAccepted, newInfo)
                    if AQL.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest accepted: " .. tostring(questID) ..
                              " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                    end
                end
            end
        end

        -- Detect removed quests (in old, not in new).
        for questID, oldInfo in pairs(oldCache) do
            if not newCache[questID] then
                -- Quest was removed from the log.
                EventEngine.pendingTurnIn[questID] = nil
                if AQL.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] pendingTurnIn cleared: questID=" .. tostring(questID) .. AQL.RESET)
                end
                if (histCache and histCache:HasCompleted(questID))
                   or WowQuestAPI.IsQuestFlaggedCompleted(questID) then
                    -- IsQuestFlaggedCompleted is the server-authoritative completion
                    -- flag; it returns true after turn-in, before QUEST_REMOVED fires.
                    -- HasCompleted covers quests completed in previous sessions.
                    -- MarkCompleted is idempotent; the histCache guard is defensive
                    -- (histCache is always non-nil post-login but nil-safety is kept).
                    if histCache then histCache:MarkCompleted(questID) end
                    AQL.callbacks:Fire(AQL.Event.QuestCompleted, oldInfo)
                    if AQL.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest completed: " .. tostring(questID) ..
                              " \"" .. tostring(oldInfo.title) .. "\"" .. AQL.RESET)
                    end
                else
                    -- No completion record. Infer failure from the last snapshot.
                    -- TBC Classic has no QUEST_FAILED event, so we use timer and
                    -- quest type as heuristics.
                    local failReason = nil
                    if oldInfo.timerSeconds and oldInfo.snapshotTime then
                        local remaining = oldInfo.timerSeconds - (GetTime() - oldInfo.snapshotTime)
                        if remaining <= 1 then
                            failReason = AQL.FailReason.Timeout
                        end
                    end
                    if not failReason and oldInfo.type == AQL.QuestType.Escort then
                        failReason = AQL.FailReason.EscortDied
                    end

                    if failReason then
                        oldInfo.isFailed   = true
                        oldInfo.failReason = failReason
                        AQL.callbacks:Fire(AQL.Event.QuestFailed, oldInfo)
                        if AQL.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest failed: " .. tostring(questID) ..
                                  " \"" .. tostring(oldInfo.title) .. "\" reason=" .. tostring(failReason) .. AQL.RESET)
                        end
                        for _, obj in ipairs(oldInfo.objectives or {}) do
                            if not obj.isFinished then
                                obj.isFailed = true
                                AQL.callbacks:Fire(AQL.Event.ObjectiveFailed, oldInfo, obj)
                                if AQL.debug then
                                    DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Objective failed: " .. tostring(questID) ..
                                          " \"" .. tostring(obj.text or "") .. "\"" .. AQL.RESET)
                                end
                            end
                        end
                    else
                        AQL.callbacks:Fire(AQL.Event.QuestAbandoned, oldInfo)
                        if AQL.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest abandoned: " .. tostring(questID) ..
                                  " \"" .. tostring(oldInfo.title) .. "\"" .. AQL.RESET)
                        end
                    end
                end
            end
        end

        -- Detect changes in existing quests.
        for questID, newInfo in pairs(newCache) do
            local oldInfo = oldCache[questID]
            if oldInfo then
                -- isComplete transition.
                if newInfo.isComplete and not oldInfo.isComplete then
                    AQL.callbacks:Fire(AQL.Event.QuestFinished, newInfo)
                    if AQL.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest finished (ready to turn in): " .. tostring(questID) ..
                              " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                    end
                end

                -- isFailed transition: quest newly failed.
                if newInfo.isFailed and not oldInfo.isFailed then
                    AQL.callbacks:Fire(AQL.Event.QuestFailed, newInfo)
                    if AQL.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest failed (isFailed): " .. tostring(questID) ..
                              " \"" .. tostring(newInfo.title) .. "\"" ..
                              (newInfo.failReason and (" reason=" .. tostring(newInfo.failReason)) or "") .. AQL.RESET)
                    end
                    -- Fire AQL_OBJECTIVE_FAILED for every unfinished objective
                    -- (the quest failing marks all incomplete objectives as failed).
                    for _, obj in ipairs(newInfo.objectives or {}) do
                        if not obj.isFinished then
                            -- Mark isFailed on the objective in the live snapshot.
                            obj.isFailed = true
                            AQL.callbacks:Fire(AQL.Event.ObjectiveFailed, newInfo, obj)
                            if AQL.debug then
                                DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Objective failed: " .. tostring(questID) ..
                                      " \"" .. tostring(obj.text or "") .. "\"" .. AQL.RESET)
                            end
                        end
                    end
                end

                -- isTracked transition.
                if newInfo.isTracked ~= oldInfo.isTracked then
                    if newInfo.isTracked then
                        AQL.callbacks:Fire(AQL.Event.QuestTracked, newInfo)
                        if AQL.debug == "verbose" then
                            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest tracked: " .. tostring(questID) ..
                                  " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                        end
                    else
                        AQL.callbacks:Fire(AQL.Event.QuestUntracked, newInfo)
                        if AQL.debug == "verbose" then
                            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest untracked: " .. tostring(questID) ..
                                  " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                        end
                    end
                end

                -- Objective diff.
                local newObjs = newInfo.objectives or {}
                local oldObjs = oldInfo.objectives or {}
                for i, newObj in ipairs(newObjs) do
                    local oldObj = oldObjs[i]
                    if oldObj then
                        local newN = newObj.numFulfilled
                        local oldN = oldObj.numFulfilled
                        if newN > oldN then
                            local delta = newN - oldN
                            AQL.callbacks:Fire(AQL.Event.ObjectiveProgressed, newInfo, newObj, delta)
                            if AQL.debug then
                                DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Objective progressed: " .. tostring(questID) ..
                                      " obj[" .. tostring(i) .. "] " ..
                                      tostring(newObj.numFulfilled) .. "/" .. tostring(newObj.numRequired) .. AQL.RESET)
                            end
                            -- Also fire COMPLETED if this progression crossed the threshold.
                            if newN >= newObj.numRequired and oldN < newObj.numRequired then
                                AQL.callbacks:Fire(AQL.Event.ObjectiveCompleted, newInfo, newObj)
                                if AQL.debug then
                                    DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Objective completed: " .. tostring(questID) ..
                                          " obj[" .. tostring(i) .. "]" .. AQL.RESET)
                                end
                            end
                        elseif newN < oldN then
                            -- Suppress regression during turn-in window: objective drop
                            -- is the NPC taking items, not a genuine regression.
                            if not EventEngine.pendingTurnIn[questID] then
                                local delta = oldN - newN
                                AQL.callbacks:Fire(AQL.Event.ObjectiveRegressed, newInfo, newObj, delta)
                                if AQL.debug then
                                    DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Objective regressed: " .. tostring(questID) ..
                                          " obj[" .. tostring(i) .. "] " ..
                                          tostring(newObj.numFulfilled) .. "/" .. tostring(newObj.numRequired) .. AQL.RESET)
                                end
                            else
                                if AQL.debug then
                                    DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Objective regression suppressed (pendingTurnIn): " ..
                                          tostring(questID) .. " obj[" .. tostring(i) .. "]" .. AQL.RESET)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    if AQL.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] runDiff: done" .. AQL.RESET)
    end
    EventEngine.diffInProgress = false

    if not ok then
        -- Log diff errors in debug mode; do not propagate.
        if AQL.debug then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.RED .. "[AQL] EventEngine diff error: " .. tostring(err) .. AQL.RESET)
        end
    end
end

local function handleQuestLogUpdate()
    if not EventEngine.initialized then
        if AQL.debug == "verbose" then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Event received before init, skipping" .. AQL.RESET)
        end
        return
    end

    -- Belt-and-suspenders: re-attempt provider selection if still on NullProvider.
    -- tryUpgradeProvider handles the common case via C_Timer; this is a fallback
    -- in case the upgrade window was missed. One comparison per rebuild — no cost.
    if AQL.provider == AQL.NullProvider then
        local provider, providerName = selectProvider()
        if provider ~= AQL.NullProvider then
            AQL.provider = provider
            if AQL.debug then
                DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Provider upgraded (inline): " .. tostring(providerName) .. AQL.RESET)
            end
        end
    end

    local oldCache = AQL.QuestCache:Rebuild()
    if oldCache == nil then return end  -- Rebuild failed (re-entrant guard from QuestCache side)

    runDiff(oldCache)
end

------------------------------------------------------------------------
-- WoW event handlers
------------------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, ...)
    if AQL.debug then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Event: " .. tostring(event) .. AQL.RESET)
    end
    if event == "PLAYER_LOGIN" then
        -- Select the best available provider.
        local provider, providerName = selectProvider()
        AQL.provider = provider
        if AQL.debug then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Provider selected: " .. tostring(providerName) .. AQL.RESET)
        end

        -- Load completed quest history (synchronous in TBC Classic).
        AQL.HistoryCache:Load()

        -- Build the initial snapshot (no diff on first build).
        AQL.QuestCache:Rebuild()
        EventEngine.initialized = true

        -- Register for quest events now that we're ready.
        frame:RegisterEvent("QUEST_ACCEPTED")
        frame:RegisterEvent("QUEST_REMOVED")
        frame:RegisterEvent("QUEST_LOG_UPDATE")
        frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
        frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")

        -- Deferred provider upgrade: fires after all PLAYER_LOGIN handlers complete.
        -- QuestWeaver is caught on the first attempt (its PLAYER_LOGIN handler runs
        -- before C_Timer.After(0, ...) callbacks fire). Questie may take ~3 s;
        -- retries cover up to 5 s total.
        C_Timer.After(0, function() tryUpgradeProvider(MAX_DEFERRED_UPGRADE_ATTEMPTS) end)
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        local unit = ...
        if unit ~= "player" then
            -- Fire the AQL callback so SocialQuest can do its UnitIsOnQuest sweep.
            AQL.callbacks:Fire(AQL.Event.UnitQuestLogChanged, unit)
        else
            -- Player's own log changed (e.g. item picked up that updates a quest).
            -- Run a diff. Note: QUEST_LOG_UPDATE will often fire too, but the
            -- re-entrancy guard (diffInProgress) prevents double-firing callbacks.
            handleQuestLogUpdate()
        end

    elseif event == "QUEST_WATCH_LIST_CHANGED"
        or event == "QUEST_LOG_UPDATE"
        or event == "QUEST_ACCEPTED"
        or event == "QUEST_REMOVED" then
        handleQuestLogUpdate()
    end
end)

-- Register only PLAYER_LOGIN at load time; everything else registers post-login.
frame:RegisterEvent("PLAYER_LOGIN")
