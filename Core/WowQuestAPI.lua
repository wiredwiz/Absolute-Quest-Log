-- Core/WowQuestAPI.lua
-- Thin, stateless wrappers around WoW quest globals.
-- All version-specific branching lives here.
-- No other AQL or Social Quest file should reference WoW quest globals directly.

WowQuestAPI = WowQuestAPI or {}

------------------------------------------------------------------------
-- Version detection
------------------------------------------------------------------------

local _TOC = select(4, GetBuildInfo())

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestInfo(questID)
-- Two-tier resolution. Returns nil when no source has data.
-- Guaranteed fields: questID, title.
-- Conditional fields (only when quest is in player's log): level,
--   suggestedGroup, isComplete, zone.
-- TBC: tier-1 log scan (GetQuestLogTitle), tier-2 C_QuestLog.GetQuestInfo.
-- Retail: single C_QuestLog.GetQuestInfo call returns full info table.
------------------------------------------------------------------------

if _TOC >= 100000 then  -- Retail
    function WowQuestAPI.GetQuestInfo(questID)
        local info = C_QuestLog.GetQuestInfo(questID)
        if not info or not info.title then return nil end
        -- zone: not included; full Retail support is out of scope for this phase.
        return {
            questID        = questID,
            title          = info.title,
            level          = info.level,
            suggestedGroup = info.suggestedGroup or 0,
            isComplete     = info.isComplete == 1,
            isTask         = info.isTask,
            isBounty       = info.isBounty,
            isStory        = info.isStory,
            campaignID     = info.campaignID,
        }
    end
else  -- TBC Classic / TBC Anniversary (and Classic Era stub)
    function WowQuestAPI.GetQuestInfo(questID)
        -- Tier 1: log scan for richer data.
        -- GetQuestLogTitle returns: title, level, suggestedGroup, isHeader,
        --   isCollapsed, isComplete, frequency, questID
        -- Header rows (isHeader == true) carry the zone/category name as `title`.
        -- Track the most recent header to associate a zone with each quest.
        local numEntries = GetNumQuestLogEntries()
        local currentZone
        for i = 1, numEntries do
            local title, level, suggestedGroup, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
            if isHeader then
                currentZone = title
            elseif qid == questID then
                return {
                    questID        = questID,
                    title          = title,
                    level          = level,
                    suggestedGroup = tonumber(suggestedGroup) or 0,
                    isComplete     = (isComplete == 1 or isComplete == true),
                    zone           = currentZone,
                }
            end
        end

        -- Tier 2: quest not in log — title-only fallback.
        -- C_QuestLog.GetQuestInfo(questID) returns a title string or nil on TBC.
        local title = C_QuestLog.GetQuestInfo(questID)
        if not title then return nil end
        return { questID = questID, title = title }
    end
end

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestObjectives(questID)
-- Returns the raw objectives array from C_QuestLog.GetQuestObjectives.
-- TBC 20505 fields per entry: text, type, finished, numFulfilled, numRequired
-- Note: field is `finished` (bool), NOT `isFinished`. AQL cache normalizes
-- to `isFinished`; this wrapper returns raw API data.
-- Returns {} if the quest is not in the log.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestObjectives(questID)
    return C_QuestLog.GetQuestObjectives(questID) or {}
end

------------------------------------------------------------------------
-- WowQuestAPI.IsQuestFlaggedCompleted(questID)
-- Returns bool. True when the quest is in the character's completion history.
------------------------------------------------------------------------

if _TOC >= 20000 then  -- TBC Classic, TBC Anniversary, Retail
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return C_QuestLog.IsQuestFlaggedCompleted(questID) == true
    end
else  -- Classic Era (future)
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return IsQuestFlaggedCompleted(questID) == true
    end
end

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestLogIndex(questID)
-- Returns the 1-based quest log index or nil if not in the player's log.
-- Matches on the 8th return value of GetQuestLogTitle(i) (the questID).
-- Does NOT use SelectQuestLogEntry/GetQuestID to avoid side-effects.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestLogIndex(questID)
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, _, _, _, _, qid = GetQuestLogTitle(i)
        if qid == questID then return i end
    end
    return nil
end

------------------------------------------------------------------------
-- WowQuestAPI.TrackQuest(questID)
-- WowQuestAPI.UntrackQuest(questID)
-- Thin wrappers — no watch-cap enforcement (that lives in AQL:TrackQuest).
-- No-op if the quest is not in the player's log.
------------------------------------------------------------------------

function WowQuestAPI.TrackQuest(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if logIndex then
        AddQuestWatch(logIndex)
    end
end

function WowQuestAPI.UntrackQuest(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if logIndex then
        RemoveQuestWatch(logIndex)
    end
end

------------------------------------------------------------------------
-- WowQuestAPI.IsUnitOnQuest(questID, unit)
-- Returns bool on Retail (UnitIsOnQuest exists).
-- Returns nil on TBC/Classic (API does not exist).
-- Note: parameter order is (questID, unit) — the opposite of the WoW
-- global UnitIsOnQuest(unit, questID) — to keep questID-first convention.
------------------------------------------------------------------------

if _TOC >= 100000 then  -- Retail
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return UnitIsOnQuest(unit, questID)
    end
else
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return nil
    end
end
