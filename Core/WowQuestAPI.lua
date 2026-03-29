-- Core/WowQuestAPI.lua
-- Thin, stateless wrappers around WoW quest globals.
-- All version-specific branching lives here.
-- No other AQL or Social Quest file should reference WoW quest globals directly.

WowQuestAPI = WowQuestAPI or {}

------------------------------------------------------------------------
-- Version detection
------------------------------------------------------------------------

local _TOC = select(4, GetBuildInfo())
local IS_CLASSIC_ERA = _TOC <  20000                   -- 1.14.x: Classic Era, SoD, Hardcore
local IS_TBC         = _TOC >= 20000 and _TOC < 30000  -- 2.x: TBC Anniversary (current)
local IS_MOP         = _TOC >= 50000 and _TOC < 60000  -- 5.x: MoP Classic
local IS_RETAIL      = _TOC >= 100000                  -- 11.x+: Retail (The War Within+)
-- Note: WotLK (30000–39999) and Cata (40000–49999) are intentionally not covered.
-- AQL is unsupported on those clients; the base toc (20505) serves as fallback.

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestInfo(questID)
-- Two-tier resolution. Returns nil when no source has data.
-- Guaranteed fields: questID, title.
-- Conditional fields (only when quest is in player's log): level,
--   suggestedGroup, isComplete, zone.
-- Classic Era, TBC, and MoP: tier-1 log scan (GetQuestLogTitle),
--   tier-2 C_QuestLog.GetQuestInfo (returns title string on all three versions).
-- Retail: single C_QuestLog.GetQuestInfo call returns full info table.
------------------------------------------------------------------------

if IS_RETAIL then
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
else  -- IS_TBC, IS_CLASSIC_ERA, and IS_MOP (same log-scan API on all three versions)
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
        -- C_QuestLog.GetQuestInfo(questID) returns a title string or nil on TBC, Classic Era, and MoP.
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
-- Classic Era: uses global IsQuestFlaggedCompleted(). TBC/MoP/Retail: uses C_QuestLog variant.
------------------------------------------------------------------------

if IS_TBC or IS_MOP or IS_RETAIL then
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return C_QuestLog.IsQuestFlaggedCompleted(questID) == true
    end
else  -- IS_CLASSIC_ERA
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return IsQuestFlaggedCompleted(questID) == true
    end
end

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestsCompleted()
-- Returns the associative table {[questID]=true} of all quests completed
-- by this character. Same return shape on Classic Era, TBC, and MoP.
-- Note: Retail uses C_QuestLog.GetAllCompletedQuestIDs() which returns a
-- sequential array — IS_RETAIL branch will be added in the Retail sub-project.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestsCompleted()
    return GetQuestsCompleted()
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
-- WowQuestAPI.GetWatchedQuestCount()
-- Returns the number of quests currently on the watch list.
------------------------------------------------------------------------

function WowQuestAPI.GetWatchedQuestCount()
    return GetNumQuestWatches()
end

------------------------------------------------------------------------
-- WowQuestAPI.GetMaxWatchableQuests()
-- Returns the maximum number of quests that can be watched simultaneously.
-- Wraps the MAX_WATCHABLE_QUESTS global constant as a function for
-- consistent access through the WowQuestAPI layer.
------------------------------------------------------------------------

function WowQuestAPI.GetMaxWatchableQuests()
    return MAX_WATCHABLE_QUESTS
end

------------------------------------------------------------------------
-- WowQuestAPI.IsQuestWatchedByIndex(logIndex)
-- WowQuestAPI.IsQuestWatchedById(questID)
-- Returns true if the quest is on the watch list, false otherwise.
-- Explicit boolean coercion: IsQuestWatched returns 1/nil on legacy clients.
-- ById variant resolves questID → logIndex via GetQuestLogIndex.
-- Returns nil from ById if the quest is not in the player's log.
-- Note: Retail uses C_QuestLog.IsQuestWatched(questID) — IS_RETAIL branch
-- will be added in the Retail sub-project (ById variant will be updated).
------------------------------------------------------------------------

function WowQuestAPI.IsQuestWatchedByIndex(logIndex)
    return IsQuestWatched(logIndex) and true or false
end

function WowQuestAPI.IsQuestWatchedById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    return IsQuestWatched(logIndex) and true or false
end

------------------------------------------------------------------------
-- WowQuestAPI.IsUnitOnQuest(questID, unit)
-- Returns bool on Retail and MoP.
-- Returns nil on TBC/Classic Era (API does not exist on TBC; deferred on Classic Era).
-- MoP: resolves questID → logIndex via GetQuestLogIndex, then calls IsUnitOnQuest(logIndex, unit).
-- Returns nil on MoP if the quest is not in the player's log (collapsed or absent).
-- Note: parameter order is (questID, unit) — the opposite of the WoW
-- global UnitIsOnQuest(unit, questID) — to keep questID-first convention.
------------------------------------------------------------------------

if IS_RETAIL then
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return UnitIsOnQuest(unit, questID)
    end
elseif IS_MOP then
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
        if not logIndex then return nil end
        if IsUnitOnQuest(logIndex, unit) then return true end
        return false
    end
else
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return nil
    end
end

------------------------------------------------------------------------
-- Quest Log Frame & Navigation
-- Thin, stateless wrappers matching WoW global names exactly.
-- Compound logic lives in AbsoluteQuestLog.lua.
-- logIndex is always a position in the *currently visible* quest log
-- entries. Quests under collapsed headers are invisible to these APIs.
------------------------------------------------------------------------

-- GetNumQuestLogEntries() → number
-- Returns the total number of visible entries (zone headers + quests).
function WowQuestAPI.GetNumQuestLogEntries()
    return GetNumQuestLogEntries()
end

-- GetQuestLogTitle(logIndex) → title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
-- Returns all fields for the entry at the given visible logIndex.
-- Header rows: title = zone name, isHeader = true, questID = nil.
-- Quest rows:  isHeader = false, questID = the quest's numeric ID.
function WowQuestAPI.GetQuestLogTitle(logIndex)
    return GetQuestLogTitle(logIndex)
end

-- GetQuestLogSelection() → logIndex
-- Returns the currently selected quest log entry index, or 0 if none selected.
function WowQuestAPI.GetQuestLogSelection()
    return GetQuestLogSelection()
end

-- SelectQuestLogEntry(logIndex)
-- Sets the selected entry without refreshing the quest log display.
function WowQuestAPI.SelectQuestLogEntry(logIndex)
    SelectQuestLogEntry(logIndex)
end

-- GetQuestLogTimeLeft() → number or nil
-- Returns the time remaining in seconds for the selected quest's timer,
-- or nil if the selected quest has no timer.
function WowQuestAPI.GetQuestLogTimeLeft()
    return GetQuestLogTimeLeft()
end

-- GetQuestLinkByIndex(logIndex) → hyperlink string or nil
-- Returns the chat hyperlink for the quest at logIndex.
function WowQuestAPI.GetQuestLinkByIndex(logIndex)
    return GetQuestLink(logIndex)
end

-- GetQuestLinkById(questID) → hyperlink string or nil
-- Resolves questID → logIndex, then returns the hyperlink.
-- Returns nil if the quest is not in the player's log.
-- Note: Retail equivalent will be added in the Retail sub-project.
function WowQuestAPI.GetQuestLinkById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    return GetQuestLink(logIndex)
end

-- GetCurrentDisplayedQuestID() → number or nil
-- Returns the questID of the quest currently displayed in the NPC quest dialog.
-- This covers both accepting a quest from a quest giver and the turn-in reward
-- screen — any context where a quest is open in the NPC interaction UI.
-- Only meaningful while an NPC quest dialog is open.
function WowQuestAPI.GetCurrentDisplayedQuestID()
    return GetQuestID()
end

-- GetQuestLogPushable() → bool
-- Returns true if the currently selected quest can be shared with party members.
-- Only meaningful when the target quest is already selected.
function WowQuestAPI.GetQuestLogPushable()
    if GetQuestLogPushable() then return true end
    return false
end

-- QuestLog_SetSelection(logIndex)
-- Updates the UI selection highlight. Always paired with QuestLog_Update().
-- Use AQL:SetQuestLogSelection() for the canonical two-call sequence.
function WowQuestAPI.QuestLog_SetSelection(logIndex)
    QuestLog_SetSelection(logIndex)
end

-- QuestLog_Update()
-- Refreshes the quest log display. Always paired with QuestLog_SetSelection().
-- Use AQL:SetQuestLogSelection() for the canonical two-call sequence.
function WowQuestAPI.QuestLog_Update()
    QuestLog_Update()
end

-- ExpandQuestHeader(logIndex)
-- Expands the collapsed zone header at logIndex.
function WowQuestAPI.ExpandQuestHeader(logIndex)
    ExpandQuestHeader(logIndex)
end

-- CollapseQuestHeader(logIndex)
-- Collapses the zone header at logIndex.
function WowQuestAPI.CollapseQuestHeader(logIndex)
    CollapseQuestHeader(logIndex)
end

-- ShowQuestLog()
-- Opens the quest log frame via ShowUIPanel(QuestLogFrame).
function WowQuestAPI.ShowQuestLog()
    ShowUIPanel(QuestLogFrame)
end

-- HideQuestLog()
-- Closes the quest log frame via HideUIPanel(QuestLogFrame).
function WowQuestAPI.HideQuestLog()
    HideUIPanel(QuestLogFrame)
end

-- IsQuestLogShown() → bool
-- Returns true if the quest log frame is currently visible.
function WowQuestAPI.IsQuestLogShown()
    return QuestLogFrame ~= nil and QuestLogFrame:IsShown() == true
end

-- GetQuestDifficultyColor(level) → {r, g, b}
-- Returns a color table for a quest level relative to the player.
-- Uses native GetQuestDifficultyColor if available; falls back to manual
-- level-delta thresholds when the API is absent.
-- Fallback thresholds (diff = questLevel - playerLevel):
--   diff >= 5  → red    {1.00, 0.10, 0.10}  (very hard)
--   diff >= 3  → orange {1.00, 0.50, 0.25}  (hard)
--   diff >= -2 → yellow {1.00, 1.00, 0.00}  (normal)
--   diff >= -5 → green  {0.25, 0.75, 0.25}  (easy)
--   else       → grey   {0.75, 0.75, 0.75}  (trivial)
function WowQuestAPI.GetQuestDifficultyColor(level)
    if not level then return { r = 0.75, g = 0.75, b = 0.75 } end
    if GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(level)
        if color then
            return { r = color.r, g = color.g, b = color.b }
        end
    end
    local playerLevel = UnitLevel("player") or 1
    local diff = level - playerLevel
    if diff >= 5 then
        return { r = 1.00, g = 0.10, b = 0.10 }
    elseif diff >= 3 then
        return { r = 1.00, g = 0.50, b = 0.25 }
    elseif diff >= -2 then
        return { r = 1.00, g = 1.00, b = 0.00 }
    elseif diff >= -5 then
        return { r = 0.25, g = 0.75, b = 0.25 }
    else
        return { r = 0.75, g = 0.75, b = 0.75 }
    end
end

-- GetPlayerLevel() → number
-- Returns the player's current character level.
function WowQuestAPI.GetPlayerLevel()
    return UnitLevel("player")
end

------------------------------------------------------------------------
-- WowQuestAPI.GetAreaInfo(areaID)
-- Returns the area info table for the given areaID via C_Map.GetAreaInfo.
-- Available on all four version families (backported to 1.13.2).
-- Used by QuestieProvider to resolve zone names from Questie's zoneOrSort IDs.
------------------------------------------------------------------------

function WowQuestAPI.GetAreaInfo(areaID)
    return C_Map.GetAreaInfo(areaID)
end
