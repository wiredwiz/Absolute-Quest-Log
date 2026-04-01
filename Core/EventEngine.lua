-- Core/EventEngine.lua
-- Owns the WoW event frame. On PLAYER_LOGIN, selects the chain provider and
-- triggers the initial cache build. On quest events, rebuilds QuestCache,
-- diffs old vs. new state at quest and objective granularity, and fires
-- AQL callbacks via CallbackHandler.
--
-- Debounce: bag stack operations fire two QUEST_LOG_UPDATE events back-to-back
-- (one with an intermediate low count, one with the settled correct count).
-- Every call increments debounceGeneration and schedules a 500 ms timer; only the
-- timer whose generation still matches runs the rebuild. Rapid bursts collapse to
-- a single rebuild against the settled state. The 500 ms window covers the full
-- server round-trip for bag operations, which can produce two QUEST_LOG_UPDATE
-- events separated by up to ~400 ms depending on server latency.
--
-- Re-entrancy: if a rebuild triggers a QUEST_LOG_UPDATE, the new call schedules
-- a deferred rebuild rather than being silently dropped.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local EventEngine = {}
AQL.EventEngine = EventEngine

-- EventEngine writes reason strings here (AQL.FailReason.Timeout, AQL.FailReason.EscortDied, or nil);
-- QuestCache reads during _buildEntry to populate QuestInfo.failReason.
-- (QuestCache.failedSet is initialized in QuestCache.lua; we just write to it.)

EventEngine.diffInProgress      = false
EventEngine.initialized         = false
EventEngine.pendingTurnIn       = {}  -- questIDs currently awaiting QUEST_REMOVED after turn-in confirmation
EventEngine.pendingAcceptCount  = 0   -- number of QUEST_ACCEPTED events fired and awaiting cache diff
EventEngine.debounceGeneration  = 0   -- incremented on every QUEST_LOG_UPDATE; timer fires only when still current
-- On Retail, some WoW API calls inside QuestCache._buildEntry fire QUEST_LOG_UPDATE
-- synchronously, which re-enters handleQuestLogUpdate mid-rebuild and schedules another
-- rebuild, creating an infinite loop. After each rebuild completes we set a 100 ms
-- cooldown; subsequent QUEST_LOG_UPDATE / QUEST_WATCH_LIST_CHANGED calls within that
-- window are silently dropped. Calls triggered by real player actions (QUEST_ACCEPTED,
-- QUEST_REMOVED) pass bypassCooldown=true and are never suppressed.
EventEngine.rebuildCooldownUntil = 0

-- Hidden event frame.
local frame = CreateFrame("Frame")
EventEngine.frame = frame

-- Number of deferred 1-second retry attempts after the initial frame-0 attempt.
-- Total checks: 1 immediate (t=0) + 5 retries (t=1s–5s) = 6 total, up to 5 s.
local MAX_DEFERRED_UPGRADE_ATTEMPTS = 5

-- QUEST_TURNED_IN does not fire in TBC Classic (Interface 20505).
-- Hook GetQuestReward as the turn-in signal for TBC: it fires synchronously
-- when the player clicks the confirm button, before items are transferred.
-- WowQuestAPI.GetCurrentDisplayedQuestID() returns the active questID at this point.
-- On Classic Era, MoP, and Retail, QUEST_TURNED_IN fires and also sets
-- pendingTurnIn directly (see the event handler below). Both paths are
-- harmless on versions that fire both; the hook is kept for TBC compatibility.
-- The hook fires only on confirmation; cancelling the reward screen does not
-- call GetQuestReward, so pendingTurnIn is never set on cancel.
hooksecurefunc("GetQuestReward", function()
    local questID = WowQuestAPI.GetCurrentDisplayedQuestID()
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

-- Human-readable labels for capability buckets used in notification messages.
local CAPABILITY_LABEL = {
    [AQL.Capability.Chain]        = "quest chain",
    [AQL.Capability.QuestInfo]    = "quest info",
    [AQL.Capability.Requirements] = "requirements",
}

-- Priority-ordered provider candidates per capability.
-- Built lazily: Providers/ load *after* EventEngine.lua in the TOC, so
-- AQL.QuestieProvider etc. are nil at EventEngine load time.
-- getProviderPriority() is first called from selectProviders() inside
-- PLAYER_LOGIN, by which point all provider globals are populated.
local _PROVIDER_PRIORITY = nil
local function getProviderPriority()
    if not _PROVIDER_PRIORITY then
        _PROVIDER_PRIORITY = {
            [AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
            [AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
            [AQL.Capability.Requirements] = { AQL.QuestieProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
        }
    end
    return _PROVIDER_PRIORITY
end

-- Tracks which providers/capabilities have already received a warning this session.
-- Keyed by provider.addonName (notifiedBroken) or AQL.Capability.* (notifiedMissing).
local notifiedBroken  = {}
local notifiedMissing = {}

-- Fires once per provider.addonName when IsAvailable=true but Validate=false.
-- Always-on: never gated by AQL.debug.
local function notifyBroken(provider, err)
    if notifiedBroken[provider.addonName] then return end
    notifiedBroken[provider.addonName] = true
    DEFAULT_CHAT_FRAME:AddMessage(AQL.WARN ..
        "[AQL] WARNING: " .. provider.addonName .. "Provider could not be loaded — " ..
        provider.addonName .. " may have changed its API.\n" ..
        "      Quest data will be unavailable. (Update or disable " ..
        provider.addonName .. " to resolve.)" .. AQL.RESET)
    PlaySound(SOUNDKIT and SOUNDKIT.LEVEL_UP or "LEVELUP")
end

-- Fires once per capability when the deferred upgrade window closes with no provider found.
-- Always-on: never gated by AQL.debug.
local function notifyMissing(capability)
    if notifiedMissing[capability] then return end
    notifiedMissing[capability] = true
    local label = CAPABILITY_LABEL[capability] or capability:lower()
    local names = {}
    for _, p in ipairs(getProviderPriority()[capability] or {}) do
        if p and p.addonName then table.insert(names, p.addonName) end
    end
    local addonList = #names > 0 and table.concat(names, ", ") or "none available"
    DEFAULT_CHAT_FRAME:AddMessage(AQL.WARN ..
        "[AQL] WARNING: No " .. label .. " provider found. " ..
        "Install one of: " .. addonList .. "." .. AQL.RESET)
    PlaySound(SOUNDKIT and SOUNDKIT.LEVEL_UP or "LEVELUP")
end

-- Fills unresolved capability slots from the priority list.
-- Fires notifyBroken for providers that are available but structurally broken.
-- Called at PLAYER_LOGIN and on the final deferred upgrade attempt.
local function selectProviders(silent)
    local priority = getProviderPriority()
    for capability, candidates in pairs(priority) do
        if AQL.providers[capability] == nil then
            for _, provider in ipairs(candidates) do
                if provider and provider:IsAvailable() then
                    local ok, err = provider:Validate()
                    if ok then
                        AQL.providers[capability] = provider
                        if AQL.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG ..
                                "[AQL] Provider selected for " .. tostring(capability) ..
                                ": " .. tostring(provider.addonName) .. AQL.RESET)
                        end
                        break
                    else
                        if not silent then
                            notifyBroken(provider, err)
                        end
                    end
                end
            end
        end
    end
    -- Update backward-compatibility shim.
    AQL.provider = AQL.providers[AQL.Capability.Chain] or AQL.NullProvider
end

-- Re-runs selection for still-unresolved capabilities.
-- During intermediate retries (attemptsLeft > 0): Validate()=false is treated as
-- IsAvailable()=false — silent retry, no notification. Handles Questie's async
-- init (~3 s) without spuriously warning the user.
-- On the final attempt (attemptsLeft == 0): calls selectProviders() which fires
-- notifyBroken, then fires notifyMissing for capabilities still unresolved.
local function tryUpgradeProviders(attemptsLeft)
    local priority = getProviderPriority()

    -- Early out if all capabilities are already resolved.
    local allResolved = true
    for capability in pairs(priority) do
        if AQL.providers[capability] == nil then allResolved = false; break end
    end
    if allResolved then return end

    if attemptsLeft == 0 then
        -- Final attempt: run full selectProviders() which fires notifyBroken.
        selectProviders()
        -- Rebuild to incorporate any provider just selected.
        AQL.QuestCache:Rebuild()
        -- Notify for capabilities still unresolved after all attempts.
        for capability in pairs(priority) do
            if AQL.providers[capability] == nil then
                notifyMissing(capability)
            end
        end
        return
    end

    -- Intermediate retry: silently try each unresolved capability.
    -- Validate()=false is skipped without notification.
    local anyUpgraded = false
    for capability, candidates in pairs(priority) do
        if AQL.providers[capability] == nil then
            for _, provider in ipairs(candidates) do
                if provider and provider:IsAvailable() then
                    local ok = provider:Validate()
                    if ok then
                        AQL.providers[capability] = provider
                        anyUpgraded = true
                        if AQL.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG ..
                                "[AQL] Provider upgraded for " .. tostring(capability) ..
                                ": " .. tostring(provider.addonName) .. AQL.RESET)
                        end
                        break
                    end
                    -- IsAvailable=true, Validate=false: skip silently during retry window.
                end
            end
        end
    end
    if anyUpgraded then
        AQL.provider = AQL.providers[AQL.Capability.Chain] or AQL.NullProvider
        AQL.QuestCache:Rebuild()
    end
    if AQL.debug then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG ..
            "[AQL] Provider upgrade attempt " ..
            tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS - attemptsLeft + 1) ..
            "/" .. tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS) ..
            (anyUpgraded and " — upgraded" or " — retrying") .. AQL.RESET)
    end
    C_Timer.After(1, function() tryUpgradeProviders(attemptsLeft - 1) end)
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
                elseif EventEngine.pendingAcceptCount > 0 then
                    EventEngine.pendingAcceptCount = EventEngine.pendingAcceptCount - 1
                    AQL.callbacks:Fire(AQL.Event.QuestAccepted, newInfo)
                    if AQL.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest accepted: " .. tostring(questID) ..
                              " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                    end
                else
                    -- Quest appeared in cache without a preceding QUEST_ACCEPTED event.
                    -- Silently absorb: cache inconsistency, group-join UNIT_QUEST_LOG_CHANGED,
                    -- or other non-accept log update. Do not fire AQL_QUEST_ACCEPTED.
                    if AQL.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Quest absorbed (no QUEST_ACCEPTED event): " ..
                              tostring(questID) .. " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
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

local function handleQuestLogUpdate(bypassCooldown)
    if not EventEngine.initialized then
        if AQL.debug == "verbose" then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Event received before init, skipping" .. AQL.RESET)
        end
        return
    end

    -- Suppress QUEST_LOG_UPDATE / QUEST_WATCH_LIST_CHANGED events fired synchronously
    -- by Retail WoW API calls inside QuestCache._buildEntry (e.g. C_QuestLog calls that
    -- trigger the event as a side-effect). Real player-action events bypass this gate.
    if not bypassCooldown and GetTime() < EventEngine.rebuildCooldownUntil then
        if AQL.debug == "verbose" then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] handleQuestLogUpdate suppressed (cooldown)" .. AQL.RESET)
        end
        return
    end

    EventEngine.debounceGeneration = EventEngine.debounceGeneration + 1
    local gen = EventEngine.debounceGeneration

    C_Timer.After(0.5, function()
        if EventEngine.debounceGeneration ~= gen then return end  -- a newer event came in; this rebuild is stale

        if EventEngine.diffInProgress then return end

        -- Belt-and-suspenders: silently fill any still-unresolved capability slots.
        -- tryUpgradeProviders handles the common case; this catches missed windows.
        -- Intentionally does not fire broken-provider notifications.
        for cap, candidates in pairs(getProviderPriority()) do
            if AQL.providers[cap] == nil then
                for _, p in ipairs(candidates) do
                    if p and p:IsAvailable() then
                        local ok = p:Validate()
                        if ok then
                            AQL.providers[cap] = p
                            if AQL.debug then
                                DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG ..
                                    "[AQL] Provider upgraded (inline) for " ..
                                    tostring(cap) .. ": " .. tostring(p.addonName) .. AQL.RESET)
                            end
                            break
                        end
                    end
                end
            end
        end
        AQL.provider = AQL.providers[AQL.Capability.Chain] or AQL.NullProvider

        local oldCache = AQL.QuestCache:Rebuild()
        -- Set cooldown after rebuild so any QUEST_LOG_UPDATE fired synchronously
        -- by Rebuild's own API calls is suppressed rather than scheduling another rebuild.
        EventEngine.rebuildCooldownUntil = GetTime() + 0.1
        if oldCache == nil then return end

        runDiff(oldCache)
    end)
end

------------------------------------------------------------------------
-- WoW event handlers
------------------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, ...)
    if AQL.debug then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Event: " .. tostring(event) .. AQL.RESET)
    end
    if event == "PLAYER_LOGIN" then
        -- Select providers for each capability (fills immediately-available slots).
        -- Deferred upgrade below catches Questie's async init.
        selectProviders(true)   -- silent: notifyBroken deferred to the final upgrade attempt

        -- Load completed quest history (synchronous in TBC Classic).
        AQL.HistoryCache:Load()

        -- Build the initial snapshot (no diff on first build).
        AQL.QuestCache:Rebuild()
        EventEngine.initialized = true

        -- Register for quest events now that we're ready.
        frame:RegisterEvent("QUEST_ACCEPTED")
        frame:RegisterEvent("QUEST_REMOVED")
        frame:RegisterEvent("QUEST_TURNED_IN")
        frame:RegisterEvent("QUEST_LOG_UPDATE")
        frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
        frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")

        -- Deferred provider upgrade: fires after all PLAYER_LOGIN handlers complete.
        -- QuestWeaver is caught on the first attempt (its PLAYER_LOGIN handler runs
        -- before C_Timer.After(0, ...) callbacks fire). Questie may take ~3 s;
        -- retries cover up to 5 s total.
        C_Timer.After(0, function() tryUpgradeProviders(MAX_DEFERRED_UPGRADE_ATTEMPTS) end)
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

    elseif event == "QUEST_ACCEPTED" then
        -- In TBC Classic (Interface 20505), QUEST_ACCEPTED does not pass questID —
        -- it passes the quest log index (or nothing). Using a count avoids depending
        -- on the argument type and works for all WoW versions.
        EventEngine.pendingAcceptCount = EventEngine.pendingAcceptCount + 1
        AQL:_ClearChainSelectionCache()
        handleQuestLogUpdate(true)  -- bypass cooldown: real player action
    elseif event == "QUEST_REMOVED" then
        -- Reset the count so a stale accept cannot fire for a quest that was removed
        -- (e.g. player accepted then immediately abandoned before the diff ran).
        EventEngine.pendingAcceptCount = 0
        AQL:_ClearChainSelectionCache()
        handleQuestLogUpdate(true)  -- bypass cooldown: real player action
    elseif event == "QUEST_TURNED_IN" then
        -- Set pendingTurnIn so objective regression during item transfer is suppressed.
        -- Do NOT call handleQuestLogUpdate here — QUEST_REMOVED fires next and drives
        -- the diff that detects quest removal and fires AQL_QUEST_COMPLETED.
        local questID = ...
        if questID and questID ~= 0 then
            EventEngine.pendingTurnIn[questID] = true
            AQL:_ClearChainSelectionCache()
            if AQL.debug then
                DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] pendingTurnIn set (QUEST_TURNED_IN): questID=" .. tostring(questID) .. AQL.RESET)
            end
        end
    elseif event == "QUEST_WATCH_LIST_CHANGED"
        or event == "QUEST_LOG_UPDATE" then
        handleQuestLogUpdate()
    end
end)

-- Register only PLAYER_LOGIN at load time; everything else registers post-login.
frame:RegisterEvent("PLAYER_LOGIN")
