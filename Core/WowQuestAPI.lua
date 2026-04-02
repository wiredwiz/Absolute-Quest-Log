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

-- Expose version flags so other AQL modules (e.g. EventEngine) can gate
-- version-specific behaviour without re-parsing the TOC version themselves.
WowQuestAPI.IS_RETAIL      = IS_RETAIL
WowQuestAPI.IS_TBC         = IS_TBC
WowQuestAPI.IS_CLASSIC_ERA = IS_CLASSIC_ERA
WowQuestAPI.IS_MOP         = IS_MOP

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
        -- Tier 1: log scan — same pattern as Classic/TBC/MoP, using Retail APIs.
        -- C_QuestLog.GetInfo returns a table per entry; isHeader rows carry the zone name.
        -- isComplete is boolean on Retail (not 0/1 integer like legacy clients).
        -- C_QuestLog.GetNumQuestLogEntries() returns numEntries, numQuests; capture first only.
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        local currentZone
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    if not (info.campaignID and info.campaignID ~= 0) then
                        currentZone = info.title
                    end
                elseif info.questID == questID then
                    return {
                        questID        = questID,
                        title          = info.title,
                        level          = info.level,
                        suggestedGroup = info.suggestedGroup or 0,
                        isComplete     = info.isComplete == true,
                        zone           = currentZone,
                        isTask         = info.isTask,
                        isBounty       = info.isBounty,
                        isStory        = info.isStory,
                        campaignID     = info.campaignID,
                    }
                end
            end
        end
        -- Tier 2: quest not in log — title-only fallback.
        -- C_QuestLog.GetQuestInfo was removed in Patch 9.0.1 (Shadowlands).
        -- GetTitleForQuestID is the canonical replacement for out-of-log title lookup.
        local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        if not title then return nil end
        return { questID = questID, title = title }
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
-- by this character. Same return shape on all versions.
-- On Retail: converts C_QuestLog.GetAllCompletedQuestIDs() sequential array
-- to an associative hash map for O(1) lookup.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestsCompleted()
    if IS_RETAIL then
        local ids = C_QuestLog.GetAllCompletedQuestIDs()
        if not ids then return nil end
        local result = {}
        for _, questID in ipairs(ids) do
            result[questID] = true
        end
        return result
    end
    return GetQuestsCompleted()
end

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestLogIndex(questID)
-- Returns the 1-based quest log index or nil if not in the player's log.
-- Matches on the 8th return value of GetQuestLogTitle(i) (the questID).
-- Does NOT use SelectQuestLogEntry/GetQuestID to avoid side-effects.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestLogIndex(questID)
    if IS_RETAIL then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local info = WowQuestAPI.GetQuestLogInfo(i)
            if info and info.questID == questID then return i end
        end
        return nil
    end
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
    if IS_RETAIL then
        C_QuestLog.AddQuestWatch(questID)
    else
        local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
        if logIndex then AddQuestWatch(logIndex) end
    end
end

function WowQuestAPI.UntrackQuest(questID)
    if IS_RETAIL then
        C_QuestLog.RemoveQuestWatch(questID)
    else
        local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
        if logIndex then RemoveQuestWatch(logIndex) end
    end
end

------------------------------------------------------------------------
-- WowQuestAPI.GetWatchedQuestCount()
-- Returns the number of quests currently on the watch list.
------------------------------------------------------------------------

function WowQuestAPI.GetWatchedQuestCount()
    if GetNumQuestWatches then return GetNumQuestWatches() end
    return 0
end

------------------------------------------------------------------------
-- WowQuestAPI.GetMaxWatchableQuests()
-- Returns the maximum number of quests that can be watched simultaneously.
-- Wraps the MAX_WATCHABLE_QUESTS global constant as a function for
-- consistent access through the WowQuestAPI layer.
------------------------------------------------------------------------

function WowQuestAPI.GetMaxWatchableQuests()
    return MAX_WATCHABLE_QUESTS or 25
end

------------------------------------------------------------------------
-- WowQuestAPI.IsQuestWatchedByIndex(logIndex)
-- WowQuestAPI.IsQuestWatchedById(questID)
-- Returns true if the quest is on the watch list, false otherwise.
-- Explicit boolean coercion: IsQuestWatched returns 1/nil on legacy clients.
-- ById variant resolves questID → logIndex via GetQuestLogIndex.
-- Returns nil from ById if the quest is not in the player's log.
-- On Retail: C_QuestLog.IsQuestWatched was removed in a later build.
--   Primary:  C_QuestLog.IsQuestWatched(questID) if present.
--   Fallback: C_QuestLog.GetQuestWatchType(questID) ~= nil (non-nil = watched).
--   Both nil: returns false.
------------------------------------------------------------------------

function WowQuestAPI.IsQuestWatchedByIndex(logIndex)
    if IS_RETAIL then
        local info = WowQuestAPI.GetQuestLogInfo(logIndex)
        if not info or not info.questID then return false end
        if C_QuestLog.IsQuestWatched then
            return C_QuestLog.IsQuestWatched(info.questID) and true or false
        end
        if C_QuestLog.GetQuestWatchType then
            return C_QuestLog.GetQuestWatchType(info.questID) ~= nil
        end
        return false
    end
    return IsQuestWatched(logIndex) and true or false
end

function WowQuestAPI.IsQuestWatchedById(questID)
    if IS_RETAIL then
        if C_QuestLog.IsQuestWatched then
            return C_QuestLog.IsQuestWatched(questID) and true or false
        end
        if C_QuestLog.GetQuestWatchType then
            return C_QuestLog.GetQuestWatchType(questID) ~= nil
        end
        return false
    end
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
-- Retail: C_QuestLog.GetNumQuestLogEntries() returns numEntries, numQuests;
-- only the first value (numEntries) is returned here.
function WowQuestAPI.GetNumQuestLogEntries()
    if IS_RETAIL then
        return C_QuestLog.GetNumQuestLogEntries()
    end
    return GetNumQuestLogEntries()
end

-- GetQuestLogTitle(logIndex) → title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
-- Returns all fields for the entry at the given visible logIndex.
-- Header rows: title = zone name, isHeader = true, questID = nil.
-- Quest rows:  isHeader = false, questID = the quest's numeric ID.
-- Retail: maps C_QuestLog.GetInfo() fields to the legacy positional return format.
-- frequency is not exposed in the Retail API; always returns 0.
function WowQuestAPI.GetQuestLogTitle(logIndex)
    if IS_RETAIL then
        local info = C_QuestLog.GetInfo(logIndex)
        if not info then return nil end
        return info.title, info.level, info.suggestedGroup,
               info.isHeader, info.isCollapsed, info.isComplete,
               0, info.questID
    end
    return GetQuestLogTitle(logIndex)
end

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestLogInfo(logIndex)
-- Normalized wrapper for per-entry quest log data. Consistent table on
-- all version families.
-- Returns: { title, level, suggestedGroup, isHeader, isCollapsed, isComplete, questID }
-- On Classic/TBC/MoP: reads positional returns from GetQuestLogTitle(logIndex).
-- On Retail: reads fields from C_QuestLog.GetInfo(logIndex).
-- Returns nil if logIndex is out of range or the entry does not exist.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestLogInfo(logIndex)
    if IS_RETAIL then
        local info = C_QuestLog.GetInfo(logIndex)
        if not info then return nil end
        return {
            title          = info.title,
            level          = info.level,
            suggestedGroup = info.suggestedGroup,
            isHeader       = info.isHeader,
            isCollapsed    = info.isCollapsed,
            isComplete     = info.isComplete,
            questID        = info.questID,
            campaignID     = info.campaignID,
        }
    else
        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, _, questID =
            GetQuestLogTitle(logIndex)
        if not title then return nil end
        return {
            title          = title,
            level          = level,
            suggestedGroup = suggestedGroup,
            isHeader       = isHeader,
            isCollapsed    = isCollapsed,
            isComplete     = isComplete,
            questID        = questID,
        }
    end
end

-- GetQuestLogSelection() → logIndex
-- Returns the currently selected quest log entry index, or 0 if none selected.
-- On Retail: always returns 0 — the save/restore in QuestCache:Rebuild is only
-- needed to undo ExpandQuestHeader calls, which are no-ops on Retail. Allowing a
-- real logIndex to flow through would cause SelectQuestLogEntry to call
-- C_QuestLog.SetSelectedQuest(), which fires QUEST_LOG_UPDATE and loops the rebuild.
function WowQuestAPI.GetQuestLogSelection()
    if IS_RETAIL then return 0 end
    if GetQuestLogSelection then return GetQuestLogSelection() end
    return 0
end

-- WowQuestAPI.GetSelectedQuestLogEntryId() → questID or nil
-- Returns the questID of the currently selected quest log entry.
-- On Retail: C_QuestLog.GetSelectedQuest() returns questID directly.
-- On Classic/TBC/MoP: resolves via GetQuestLogSelection() → GetQuestLogInfo().
-- Returns nil if nothing is selected or if the selected entry is a zone header.
function WowQuestAPI.GetSelectedQuestLogEntryId()
    if IS_RETAIL then
        local questID = C_QuestLog.GetSelectedQuest()
        return (questID and questID ~= 0) and questID or nil
    end
    local logIndex = WowQuestAPI.GetQuestLogSelection()
    if not logIndex or logIndex == 0 then return nil end
    local info = WowQuestAPI.GetQuestLogInfo(logIndex)
    if not info or info.isHeader or not info.questID then return nil end
    return info.questID
end

-- SelectQuestLogEntry(logIndex)
-- Sets the selected entry without refreshing the quest log display.
-- On Retail: resolves logIndex → questID via GetQuestLogInfo, calls
-- C_QuestLog.SetSelectedQuest(questID).
function WowQuestAPI.SelectQuestLogEntry(logIndex)
    if IS_RETAIL then
        local info = WowQuestAPI.GetQuestLogInfo(logIndex)
        if info and info.questID then
            C_QuestLog.SetSelectedQuest(info.questID)
        end
        return
    end
    SelectQuestLogEntry(logIndex)
end

-- GetQuestLogTimeLeft() → number or nil
-- Returns the time remaining in seconds for the selected quest's timer,
-- or nil if the selected quest has no timer.
-- Selection-dependent: call SelectQuestLogEntry(logIndex) first.
-- Nil-guards the global: GetQuestLogTimeLeft may be absent on Retail.
function WowQuestAPI.GetQuestLogTimeLeft()
    if GetQuestLogTimeLeft then return GetQuestLogTimeLeft() end
    return nil
end

-- GetQuestTimerByIndex(logIndex) → seconds or nil
-- Returns time remaining for the quest at logIndex, or nil if no timer.
-- On Classic/TBC/MoP: selects the entry then reads GetQuestLogTimeLeft().
-- On Retail: C_QuestLog.SetSelectedQuest() fires QUEST_LOG_UPDATE and would
--   cause a rebuild loop — returns nil instead.
--   TODO: implement Retail timer via C_QuestLog.GetTimeAllowed(questID).
function WowQuestAPI.GetQuestTimerByIndex(logIndex)
    if IS_RETAIL then return nil end
    WowQuestAPI.SelectQuestLogEntry(logIndex)
    local rawTimer = WowQuestAPI.GetQuestLogTimeLeft()
    return (rawTimer and rawTimer > 0) and rawTimer or nil
end

-- GetQuestLinkByIndex(logIndex) → hyperlink string or nil
-- Returns the chat hyperlink for the quest at logIndex.
-- On Retail: GetQuestLink global removed. C_QuestLog.GetQuestLink also absent on
--   some builds (Interface 120001+); nil-guarded. Returns nil when unavailable —
--   callers should fall back to manual hyperlink construction.
-- On Classic/TBC/MoP: nil-guards GetQuestLink for robustness.
function WowQuestAPI.GetQuestLinkByIndex(logIndex)
    if IS_RETAIL then
        if C_QuestLog.GetQuestLink then
            local info = WowQuestAPI.GetQuestLogInfo(logIndex)
            if info and info.questID then
                return C_QuestLog.GetQuestLink(info.questID)
            end
        end
        return nil
    end
    if GetQuestLink then return GetQuestLink(logIndex) end
    return nil
end

-- GetQuestLinkById(questID) → hyperlink string or nil
-- On Retail: C_QuestLog.GetQuestLink nil-guarded (absent on Interface 120001+).
-- On Classic/TBC/MoP: resolves questID → logIndex, then calls GetQuestLink(logIndex).
-- Returns nil if the quest link is unavailable.
function WowQuestAPI.GetQuestLinkById(questID)
    if IS_RETAIL then
        if C_QuestLog.GetQuestLink then
            return C_QuestLog.GetQuestLink(questID)
        end
        return nil
    end
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    if GetQuestLink then return GetQuestLink(logIndex) end
    return nil
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
-- On Retail: resolves the selected questID via GetSelectedQuestLogEntryId, calls
-- C_QuestLog.IsPushableQuest(questID).
-- On Classic/TBC/MoP: calls GetQuestLogPushable() which reads UI selection state.
function WowQuestAPI.GetQuestLogPushable()
    if IS_RETAIL then
        local questID = WowQuestAPI.GetSelectedQuestLogEntryId()
        if not questID then return false end
        return C_QuestLog.IsPushableQuest(questID) and true or false
    end
    return GetQuestLogPushable() and true or false
end

-- QuestLog_SetSelection(logIndex)
-- Updates the UI selection highlight and refreshes the quest log display.
-- On Retail: resolves logIndex → questID via GetQuestLogInfo, calls
-- C_QuestLog.SetSelectedQuest(questID). QuestLog_Update() is not needed on Retail.
-- On Classic/TBC/MoP: calls QuestLog_SetSelection + QuestLog_Update (the required pair).
function WowQuestAPI.QuestLog_SetSelection(logIndex)
    if IS_RETAIL then
        local info = WowQuestAPI.GetQuestLogInfo(logIndex)
        if info and info.questID then
            C_QuestLog.SetSelectedQuest(info.questID)
        end
        return
    end
    QuestLog_SetSelection(logIndex)
    QuestLog_Update()
end

-- QuestLog_Update()
-- Refreshes the quest log display on Classic/TBC/MoP.
-- No-op on Retail (the quest log auto-updates when selection changes).
function WowQuestAPI.QuestLog_Update()
    if IS_RETAIL then return end
    QuestLog_Update()
end

-- ExpandQuestHeader(logIndex)
-- Expands the collapsed zone header at logIndex.
-- No-op on Retail if the global is absent (removed in some Retail builds).
function WowQuestAPI.ExpandQuestHeader(logIndex)
    if ExpandQuestHeader then ExpandQuestHeader(logIndex) end
end

-- CollapseQuestHeader(logIndex)
-- Collapses the zone header at logIndex.
-- No-op on Retail if the global is absent (removed in some Retail builds).
function WowQuestAPI.CollapseQuestHeader(logIndex)
    if CollapseQuestHeader then CollapseQuestHeader(logIndex) end
end

-- ShowQuestLog()
-- Opens the quest log (Retail: WorldMapFrame; Classic/TBC/MoP: QuestLogFrame).
function WowQuestAPI.ShowQuestLog()
    if IS_RETAIL then WorldMapFrame:Show() else ShowUIPanel(QuestLogFrame) end
end

-- HideQuestLog()
-- Closes the quest log (Retail: WorldMapFrame; Classic/TBC/MoP: QuestLogFrame).
function WowQuestAPI.HideQuestLog()
    if IS_RETAIL then WorldMapFrame:Hide() else HideUIPanel(QuestLogFrame) end
end

-- IsQuestLogShown() → bool
-- Returns true if the quest log (or WorldMapFrame on Retail) is currently visible.
function WowQuestAPI.IsQuestLogShown()
    if IS_RETAIL then return WorldMapFrame:IsVisible() end
    return QuestLogFrame:IsVisible()
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
