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

-- EventEngine writes reason strings here ("timeout", "escort_died", "unknown");
-- QuestCache reads during _buildEntry to populate QuestInfo.failReason.
-- (QuestCache.failedSet is initialized in QuestCache.lua; we just write to it.)

EventEngine.diffInProgress   = false
EventEngine.initialized      = false

-- Hidden event frame.
local frame = CreateFrame("Frame")
EventEngine.frame = frame

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

------------------------------------------------------------------------
-- Diff + dispatch logic
------------------------------------------------------------------------

local function runDiff(oldCache)
    if EventEngine.diffInProgress then return end
    EventEngine.diffInProgress = true

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
                    AQL.callbacks:Fire("AQL_QUEST_ACCEPTED", newInfo)
                end
            end
        end

        -- Detect removed quests (in old, not in new).
        for questID, oldInfo in pairs(oldCache) do
            if not newCache[questID] then
                -- Quest was removed from the log.
                if histCache and histCache:HasCompleted(questID) then
                    -- Already recorded by the QUEST_TURNED_IN handler before this
                    -- diff ran. MarkCompleted is idempotent so calling it again is
                    -- safe and ensures correctness if QUEST_TURNED_IN was missed.
                    histCache:MarkCompleted(questID)
                    AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
                else
                    -- No completion record → abandoned.
                    AQL.callbacks:Fire("AQL_QUEST_ABANDONED", oldInfo)
                end
            end
        end

        -- Detect changes in existing quests.
        for questID, newInfo in pairs(newCache) do
            local oldInfo = oldCache[questID]
            if oldInfo then
                -- isComplete transition.
                if newInfo.isComplete and not oldInfo.isComplete then
                    AQL.callbacks:Fire("AQL_QUEST_FINISHED", newInfo)
                end

                -- isFailed transition: quest newly failed.
                if newInfo.isFailed and not oldInfo.isFailed then
                    AQL.callbacks:Fire("AQL_QUEST_FAILED", newInfo)
                    -- Fire AQL_OBJECTIVE_FAILED for every unfinished objective
                    -- (the quest failing marks all incomplete objectives as failed).
                    for _, obj in ipairs(newInfo.objectives or {}) do
                        if not obj.isFinished then
                            -- Mark isFailed on the objective in the live snapshot.
                            obj.isFailed = true
                            AQL.callbacks:Fire("AQL_OBJECTIVE_FAILED", newInfo, obj)
                        end
                    end
                end

                -- isTracked transition.
                if newInfo.isTracked ~= oldInfo.isTracked then
                    if newInfo.isTracked then
                        AQL.callbacks:Fire("AQL_QUEST_TRACKED", newInfo)
                    else
                        AQL.callbacks:Fire("AQL_QUEST_UNTRACKED", newInfo)
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
                            AQL.callbacks:Fire("AQL_OBJECTIVE_PROGRESSED", newInfo, newObj, delta)
                            -- Also fire COMPLETED if this progression crossed the threshold.
                            if newN >= newObj.numRequired and oldN < newObj.numRequired then
                                AQL.callbacks:Fire("AQL_OBJECTIVE_COMPLETED", newInfo, newObj)
                            end
                        elseif newN < oldN then
                            local delta = oldN - newN
                            AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)
                        end
                    end
                end
            end
        end
    end)

    EventEngine.diffInProgress = false

    if not ok then
        -- Log diff errors in debug mode; do not propagate.
        if AQL.debug then
            print("[AQL] EventEngine diff error: " .. tostring(err))
        end
    end
end

local function handleQuestLogUpdate()
    if not EventEngine.initialized then return end

    local oldCache = AQL.QuestCache:Rebuild()
    if oldCache == nil then return end  -- Rebuild failed (re-entrant guard from QuestCache side)

    runDiff(oldCache)
end

------------------------------------------------------------------------
-- WoW event handlers
------------------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Select the best available provider.
        local provider, providerName = selectProvider()
        AQL.provider = provider

        -- Trigger async history load.
        AQL.HistoryCache:Load(frame)

        -- Build the initial snapshot (no diff on first build).
        AQL.QuestCache:Rebuild()
        EventEngine.initialized = true

        -- Register for quest events now that we're ready.
        frame:RegisterEvent("QUEST_ACCEPTED")
        frame:RegisterEvent("QUEST_REMOVED")
        frame:RegisterEvent("QUEST_TURNED_IN")
        frame:RegisterEvent("QUEST_FAILED")
        frame:RegisterEvent("QUEST_LOG_UPDATE")
        frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
        frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")

    elseif event == "QUEST_QUERY_COMPLETE" then
        AQL.HistoryCache:OnQueryComplete()
        frame:UnregisterEvent("QUEST_QUERY_COMPLETE")

    elseif event == "QUEST_FAILED" then
        local questID = ...  -- first event argument
        if questID and type(questID) == "number" then
            -- Determine failure reason from the pre-failure snapshot.
            -- timerSeconds and snapshotTime are set synchronously in _buildEntry,
            -- so their delta accurately estimates time remaining at event delivery.
            -- Use a 1-second epsilon to account for event delivery lag.
            local entry  = AQL.QuestCache and AQL.QuestCache.data[questID]
            local reason = "unknown"
            if entry then
                if entry.timerSeconds and
                   (entry.timerSeconds - (GetTime() - entry.snapshotTime)) <= 1 then
                    reason = "timeout"
                elseif entry.type == "escort" then
                    reason = "escort_died"
                end
            end
            AQL.QuestCache.failedSet[questID] = reason
        end
        -- When questID is unavailable, the quest is detected failed via the diff
        -- on the subsequent QUEST_LOG_UPDATE; failReason will be nil in that case.
        handleQuestLogUpdate()

    elseif event == "QUEST_TURNED_IN" then
        -- QUEST_TURNED_IN fires BEFORE QUEST_LOG_UPDATE removes the quest.
        -- Pre-mark the quest as completed in HistoryCache NOW so that when
        -- the subsequent diff sees the quest disappear from the log, it
        -- correctly identifies it as a turn-in (HasCompleted → true) rather
        -- than an abandonment.
        -- In TBC Classic, QUEST_TURNED_IN passes: questID, xpReward, moneyReward.
        local questID = ...
        if questID and type(questID) == "number" then
            AQL.HistoryCache:MarkCompleted(questID)
        end
        handleQuestLogUpdate()

    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        local unit = ...
        if unit ~= "player" then
            -- Fire the AQL callback so SocialQuest can do its UnitIsOnQuest sweep.
            AQL.callbacks:Fire("AQL_UNIT_QUEST_LOG_CHANGED", unit)
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
