-- AbsoluteQuestLog-1.0
-- LibStub library providing unified quest data access for WoW TBC Anniversary.
-- Consumers: LibStub("AbsoluteQuestLog-1.0")

local MAJOR, MINOR = "AbsoluteQuestLog-1.0", 1
local AQL, oldVersion = LibStub:NewLibrary(MAJOR, MINOR)
if not AQL then return end  -- Already loaded at equal or higher version.

-- CallbackHandler injects AQL:RegisterCallback and AQL:UnregisterCallback.
-- Usage: AQL:RegisterCallback("AQL_QUEST_ACCEPTED", handler, target)
--        AQL:UnregisterCallback("AQL_QUEST_ACCEPTED", handler)
-- See CLAUDE.md Callbacks Reference for the full event list.
AQL.callbacks = AQL.callbacks or LibStub("CallbackHandler-1.0"):New(AQL)

-- Chat color escape sequences for debug/error messages.
AQL.RED   = "|cffff0000"
AQL.RESET = "|r"
AQL.DBG   = "|cFFFFD200"   -- gold (colorblind-safe, distinct from errors and chat text)

-- Sub-module slots — populated by the files that load after this one.
-- AbsoluteQuestLog.lua loads first (per TOC order), so these are nil until
-- the sub-module files run. Public methods guard against nil sub-modules.
-- AQL.QuestCache   set by Core/QuestCache.lua
-- AQL.HistoryCache set by Core/HistoryCache.lua
-- AQL.EventEngine  set by Core/EventEngine.lua
-- AQL.provider     set by Core/EventEngine.lua at PLAYER_LOGIN

------------------------------------------------------------------------
-- Enumeration Constants
-- Public — consumers reference AQL.ChainStatus, AQL.Provider, etc.
-- String values are unchanged; these tables are the canonical reference.
-- Tables are mutable by convention only (no __newindex guard).
------------------------------------------------------------------------

AQL.ChainStatus = {
    Known     = "known",
    NotAChain = "not_a_chain",
    Unknown   = "unknown",
}

AQL.StepStatus = {
    Completed   = "completed",
    Active      = "active",
    Finished    = "finished",
    Failed      = "failed",
    Available   = "available",
    Unavailable = "unavailable",
    Unknown     = "unknown",
}

AQL.Provider = {
    Questie     = "Questie",
    QuestWeaver = "QuestWeaver",
    None        = "none",
}

AQL.QuestType = {
    Normal  = "normal",
    Elite   = "elite",
    Dungeon = "dungeon",
    Raid    = "raid",
    Daily   = "daily",
    PvP     = "pvp",
    Escort  = "escort",
}

AQL.Faction = {
    Alliance = "Alliance",
    Horde    = "Horde",
}

AQL.FailReason = {
    Timeout    = "timeout",
    EscortDied = "escort_died",
}

------------------------------------------------------------------------
-- GROUP 1: QUEST APIS
-- Data and state queries about quests. No interaction with the quest log frame.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Quest State
------------------------------------------------------------------------

-- GetQuest(questID) → QuestInfo or nil
-- Returns the cached QuestInfo for questID, or nil if the quest is not in
-- the player's active log. Cache-only — does not scan the WoW log or
-- provider. Use GetQuestInfo for three-tier resolution.
function AQL:GetQuest(questID)
    return self.QuestCache and self.QuestCache:Get(questID) or nil
end

-- GetAllQuests() → {[questID]=QuestInfo}
-- Returns the full active quest cache snapshot.
-- Keys are questIDs; values are QuestInfo tables.
function AQL:GetAllQuests()
    return self.QuestCache and self.QuestCache:GetAll() or {}
end

-- GetQuestsByZone(zone) → {[questID]=QuestInfo}
-- Returns all active quests whose zone field matches zone.
-- zone is the English canonical zone name as stored by the active chain
-- provider (e.g. "Blasted Lands"). On non-English clients, use
-- GetAllQuests() and filter by questID instead.
function AQL:GetQuestsByZone(zone)
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.zone == zone then
            result[questID] = info
        end
    end
    return result
end

-- IsQuestActive(questID) → bool
-- Returns true if questID is currently in the player's active quest log.
function AQL:IsQuestActive(questID)
    return self.QuestCache ~= nil and self.QuestCache:Get(questID) ~= nil
end

-- IsQuestFinished(questID) → bool
-- Returns true if questID is in the log and all objectives are met
-- (isComplete = true) but the quest has not yet been turned in.
function AQL:IsQuestFinished(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q ~= nil and q.isComplete == true
end

------------------------------------------------------------------------
-- Quest History
------------------------------------------------------------------------

-- HasCompletedQuest(questID) → bool
-- Returns true if questID is in the character's completion history.
-- Checks HistoryCache first; falls back to WowQuestAPI.IsQuestFlaggedCompleted.
function AQL:HasCompletedQuest(questID)
    if self.HistoryCache and self.HistoryCache:HasCompleted(questID) then
        return true
    end
    return WowQuestAPI.IsQuestFlaggedCompleted(questID)
end

-- GetCompletedQuests() → {[questID]=true}
-- Returns the full set of quests completed by this character.
function AQL:GetCompletedQuests()
    return self.HistoryCache and self.HistoryCache:GetAll() or {}
end

-- GetCompletedQuestCount() → number
-- Returns the count of quests completed by this character.
function AQL:GetCompletedQuestCount()
    return self.HistoryCache and self.HistoryCache:GetCount() or 0
end

-- GetQuestType(questID) → string or nil
-- Returns the quest type from the cache (e.g. AQL.QuestType.Elite), or nil
-- if unknown. Cache-only; returns nil if the quest is not in the active log.
function AQL:GetQuestType(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.type or nil
end

-- GetQuestLink(questID) → hyperlink string or nil
-- Returns a WoW quest hyperlink for questID.
-- Tier 1: live cache link (pre-built by QuestCache._buildEntry with fallback
-- construction, so always non-nil for active quests).
-- Tier 2/3: constructs a link from GetQuestInfo when the quest is not cached.
-- Returns nil only when no title can be resolved (all three tiers exhausted).
function AQL:GetQuestLink(questID)
    -- Tier 1: live cache (always non-nil for active quests; see _buildEntry fallback).
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.link then return q.link end

    -- Tier 2+3: quest not in active log — resolve via GetQuestInfo (which itself
    -- chains: QuestCache → WoW log scan → provider). The QuestCache check above
    -- already handled Tier 1, so in practice GetQuestInfo will reach Tier 2 or 3.
    -- If the provider returns chain-only data with no title, info.title will be nil
    -- and we return nil — a link cannot be constructed without a title.
    local info = self:GetQuestInfo(questID)
    if not info or not info.title then return nil end
    return string.format("|cFFFFD200|Hquest:%d:%d|h[%s]|h|r",
        questID, info.level or 0, info.title)
end

------------------------------------------------------------------------
-- Objectives
------------------------------------------------------------------------

-- GetObjectives(questID) → array or nil
-- Returns the objectives array for questID from the cache, or nil if the
-- quest is not in the active log.
-- Each entry: { index, text, name, type, numFulfilled, numRequired, isFinished, isFailed }.
function AQL:GetObjectives(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.objectives or nil
end

-- GetObjective(questID, index) → table or nil
-- Returns the single objective at index for questID, or nil if not found.
function AQL:GetObjective(questID, index)
    local objs = self:GetObjectives(questID)
    return objs and objs[index] or nil
end

------------------------------------------------------------------------
-- Chain Info
------------------------------------------------------------------------

-- GetChainInfo(questID) → ChainInfo
-- Returns chain info from the cache. Falls back to
-- { knownStatus = AQL.ChainStatus.Unknown } when not found. Never returns nil.
function AQL:GetChainInfo(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.chainInfo then
        return q.chainInfo
    end
    return { knownStatus = AQL.ChainStatus.Unknown }
end

-- GetChainStep(questID) → number or nil
-- Returns the 1-based step position of questID in its chain, or nil if unknown.
function AQL:GetChainStep(questID)
    return self:GetChainInfo(questID).step
end

-- GetChainLength(questID) → number or nil
-- Returns the total number of quests in questID's chain, or nil if unknown.
function AQL:GetChainLength(questID)
    return self:GetChainInfo(questID).length
end

------------------------------------------------------------------------
-- Quest Resolution
------------------------------------------------------------------------

-- Three-tier resolution. Contrast with AQL:GetQuest which is cache-only.
--   Tier 1: AQL QuestCache (full normalized snapshot)
--   Tier 2: WowQuestAPI log scan → { questID, title, level, suggestedGroup, isComplete, zone }
--           or title-only { questID, title } when not in log; augmented from Tier 3 when zone absent
--   Tier 3: AQL.provider:GetQuestBasicInfo → { title, questLevel, requiredLevel, zone }
--           merged with AQL.provider:GetChainInfo → chainInfo (chainID, step, length)
-- Returns nil only when all three tiers have no data.
function AQL:GetQuestInfo(questID)
    -- Tier 1: cache.
    local cached = self.QuestCache and self.QuestCache:Get(questID)
    if cached then return cached end

    -- Tier 2: WoW log scan / title fallback.
    local result = WowQuestAPI.GetQuestInfo(questID)
    if result then
        -- Augment with Tier 3 if zone is absent (title-only path: quest not in
        -- player's log). Zone is nil only in that path; the log-scan path always
        -- sets zone from the zone-header row. All provider calls are pcall-guarded.
        if not result.zone then
            local provider = self.provider
            if provider then
                if provider.GetQuestBasicInfo then
                    local ok, basicInfo = pcall(provider.GetQuestBasicInfo, provider, questID)
                    if ok and basicInfo then
                        result.zone          = result.zone          or basicInfo.zone
                        result.level         = result.level         or basicInfo.questLevel
                        result.requiredLevel = result.requiredLevel or basicInfo.requiredLevel
                        result.title         = result.title         or basicInfo.title
                    end
                end
                if provider.GetChainInfo then
                    local ok, ci = pcall(provider.GetChainInfo, provider, questID)
                    if ok and ci then
                        result.chainInfo = result.chainInfo or ci
                    end
                end
            end
        end
        return result
    end

    -- Tier 3: provider (Questie / QuestWeaver).
    local provider = self.provider
    if not provider then return nil end

    local basicInfo
    if provider.GetQuestBasicInfo then
        local ok, info = pcall(provider.GetQuestBasicInfo, provider, questID)
        if ok and info then basicInfo = info end
    end

    local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
    if provider.GetChainInfo then
        local ok, ci = pcall(provider.GetChainInfo, provider, questID)
        if ok and ci then chainInfo = ci end
    end

    if not basicInfo and chainInfo.knownStatus == AQL.ChainStatus.Unknown then return nil end

    return {
        questID       = questID,
        title         = basicInfo and basicInfo.title         or nil,
        level         = basicInfo and basicInfo.questLevel    or nil,
        requiredLevel = basicInfo and basicInfo.requiredLevel or nil,
        zone          = basicInfo and basicInfo.zone          or nil,
        chainInfo     = chainInfo,
    }
end

-- Returns the title string for any questID, or nil.
-- Delegates to GetQuestInfo and extracts .title.
function AQL:GetQuestTitle(questID)
    local info = self:GetQuestInfo(questID)
    return info and info.title or nil
end

-- Returns the objectives array for a questID.
-- Cache first (normalized fields: isFinished, etc.).
-- WowQuestAPI fallback returns raw TBC fields (finished, type, etc.).
function AQL:GetQuestObjectives(questID)
    local cached = self.QuestCache and self.QuestCache:Get(questID)
    if cached then return cached.objectives or {} end
    return WowQuestAPI.GetQuestObjectives(questID)
end

-- Returns true if msg's base name (description without ": X/Y" count) matches
-- the leading text of any objective in the active quest cache. The pattern is
-- applied once to msg; each objective is checked with a plain string.sub
-- comparison so no regex runs inside the loop. A stale cache (previous count)
-- still matches an incoming UI_INFO_MESSAGE (new count) because only the base
-- description is compared. Used by SocialQuest to identify UI_INFO_MESSAGE
-- events that duplicate its own objective-progress banner. Reads from the live
-- quest cache; the cache is always complete because QuestCache:Rebuild() expands
-- collapsed zones before reading.
function AQL:IsQuestObjectiveText(msg)
    if not msg then return false end
    if not self.QuestCache then return false end
    local msgBase = msg:match("^(.+):%s*%d+/%d+$")
    if not msgBase then return false end
    local baseLen = #msgBase
    for _, quest in pairs(self.QuestCache.data) do
        if quest.objectives then
            for _, obj in ipairs(quest.objectives) do
                if obj.text and obj.text:sub(1, baseLen) == msgBase then
                    return true
                end
            end
        end
    end
    return false
end

------------------------------------------------------------------------
-- Quest Tracking
------------------------------------------------------------------------

-- Tracks a quest by questID.
-- Returns false if the watch cap (MAX_WATCHABLE_QUESTS) is already reached.
-- Returns true if the quest was successfully handed to AddQuestWatch.
-- Caller is responsible for displaying a message when false is returned.
function AQL:TrackQuest(questID)
    if GetNumQuestWatches() >= MAX_WATCHABLE_QUESTS then
        return false
    end
    WowQuestAPI.TrackQuest(questID)
    return true
end

-- Untracks a quest by questID. Always delegates; no cap check needed.
function AQL:UntrackQuest(questID)
    WowQuestAPI.UntrackQuest(questID)
end

-- Returns bool on Retail (UnitIsOnQuest exists), nil on TBC/Classic.
function AQL:IsUnitOnQuest(questID, unit)
    return WowQuestAPI.IsUnitOnQuest(questID, unit)
end

------------------------------------------------------------------------
-- Player & Level
-- Filters the active quest cache by quest level (questInfo.level —
-- the recommended difficulty level, not requiredLevel).
-- Absolute-level methods use strict comparisons: < and >.
-- BetweenLevels is inclusive on both endpoints.
-- Delta methods delegate to the absolute methods; delta should be a
-- non-negative integer (negative values produce valid but counter-intuitive
-- results — see individual method notes).
-- All methods return {} (never nil) when no quests match.
-- No debug messages — pure data queries.
------------------------------------------------------------------------

-- GetPlayerLevel() → number
-- Returns the player's current character level.
function AQL:GetPlayerLevel()
    return WowQuestAPI.GetPlayerLevel()
end

-- GetQuestsInQuestLogBelowLevel(level) → {[questID]=QuestInfo}
-- Returns all active quests where questInfo.level < level.
function AQL:GetQuestsInQuestLogBelowLevel(level)
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.level and info.level < level then
            result[questID] = info
        end
    end
    return result
end

-- GetQuestsInQuestLogAboveLevel(level) → {[questID]=QuestInfo}
-- Returns all active quests where questInfo.level > level.
function AQL:GetQuestsInQuestLogAboveLevel(level)
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.level and info.level > level then
            result[questID] = info
        end
    end
    return result
end

-- GetQuestsInQuestLogBetweenLevels(minLevel, maxLevel) → {[questID]=QuestInfo}
-- Returns all active quests where minLevel <= questInfo.level <= maxLevel.
-- Returns {} if minLevel > maxLevel.
function AQL:GetQuestsInQuestLogBetweenLevels(minLevel, maxLevel)
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.level and info.level >= minLevel and info.level <= maxLevel then
            result[questID] = info
        end
    end
    return result
end

-- GetQuestsInQuestLogBelowLevelDelta(delta) → {[questID]=QuestInfo}
-- Returns quests more than delta levels below the player.
-- e.g. delta=5 at player level 40 → quests strictly below level 35.
-- Delegates to GetQuestsInQuestLogBelowLevel(playerLevel - delta).
function AQL:GetQuestsInQuestLogBelowLevelDelta(delta)
    return self:GetQuestsInQuestLogBelowLevel(WowQuestAPI.GetPlayerLevel() - delta)
end

-- GetQuestsInQuestLogAboveLevelDelta(delta) → {[questID]=QuestInfo}
-- Returns quests more than delta levels above the player.
-- e.g. delta=5 at player level 40 → quests strictly above level 45.
-- Delegates to GetQuestsInQuestLogAboveLevel(playerLevel + delta).
function AQL:GetQuestsInQuestLogAboveLevelDelta(delta)
    return self:GetQuestsInQuestLogAboveLevel(WowQuestAPI.GetPlayerLevel() + delta)
end

-- GetQuestsInQuestLogWithinLevelRange(delta) → {[questID]=QuestInfo}
-- Returns quests within ±delta levels of the player's current level
-- (inclusive endpoints — the "currently worth doing" set).
-- e.g. delta=3 at player level 40 → quests between levels 37 and 43.
-- Delegates to GetQuestsInQuestLogBetweenLevels(playerLevel - delta, playerLevel + delta).
function AQL:GetQuestsInQuestLogWithinLevelRange(delta)
    local playerLevel = WowQuestAPI.GetPlayerLevel()
    return self:GetQuestsInQuestLogBetweenLevels(playerLevel - delta, playerLevel + delta)
end

------------------------------------------------------------------------
-- GROUP 2: QUEST LOG APIS
-- Methods that interact with the built-in WoW quest log frame.
--
-- logIndex note: logIndex is always a position in the *currently visible*
-- quest log entries. Quests under collapsed zone headers are invisible to
-- the WoW API and return nil from any logIndex-resolution method.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Quest Log APIs — Thin Wrappers
-- One-to-one with WoW globals. No debug messages (direct pass-throughs).
------------------------------------------------------------------------

-- ShowQuestLog()
-- Opens the quest log frame.
function AQL:ShowQuestLog()
    WowQuestAPI.ShowQuestLog()
end

-- HideQuestLog()
-- Closes the quest log frame.
function AQL:HideQuestLog()
    WowQuestAPI.HideQuestLog()
end

-- IsQuestLogShown() → bool
-- Returns true if the quest log frame is currently visible.
function AQL:IsQuestLogShown()
    return WowQuestAPI.IsQuestLogShown()
end

-- GetQuestLogSelection() → logIndex
-- Returns the currently selected quest log entry index (0 if none selected).
function AQL:GetQuestLogSelection()
    return WowQuestAPI.GetQuestLogSelection()
end

-- SelectQuestLogEntry(logIndex)
-- Sets the selected entry without refreshing the quest log display.
-- Does not emit a debug message — use SetQuestLogSelection for the
-- display-refreshing version.
function AQL:SelectQuestLogEntry(logIndex)
    WowQuestAPI.SelectQuestLogEntry(logIndex)
end

-- IsQuestLogShareable() → bool
-- Returns true if the currently selected quest can be shared with party members.
-- Delegates to WowQuestAPI.GetQuestLogPushable().
-- WARNING: Result depends entirely on the current quest log selection.
-- If nothing is selected or the wrong entry is selected, the result is
-- meaningless. Prefer IsQuestIndexShareable or IsQuestIdShareable when
-- operating on a specific quest. This method exists only for callers that
-- have already managed selection themselves.
-- Emits no debug message (pass-through; caller manages selection context).
function AQL:IsQuestLogShareable()
    return WowQuestAPI.GetQuestLogPushable()
end

-- SetQuestLogSelection(logIndex)
-- Sets selection AND refreshes the quest log display.
-- Calls WowQuestAPI.QuestLog_SetSelection(logIndex) followed immediately
-- by WowQuestAPI.QuestLog_Update(). These two calls are always used together;
-- this is the canonical two-call sequence.
function AQL:SetQuestLogSelection(logIndex)
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] SetQuestLogSelection: logIndex=" .. tostring(logIndex) .. self.RESET)
    end
    WowQuestAPI.QuestLog_SetSelection(logIndex)
    WowQuestAPI.QuestLog_Update()
end

-- ExpandQuestLogHeader(logIndex)
-- Expands the collapsed zone header at logIndex.
-- Verifies the entry is a header before acting; emits a normal-level debug
-- message and returns without expanding if it is not.
-- Emits a verbose debug message on successful expansion.
function AQL:ExpandQuestLogHeader(logIndex)
    local _, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(logIndex)
    if not isHeader then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ExpandQuestLogHeader: logIndex=" .. tostring(logIndex) .. " is not a header — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.ExpandQuestHeader(logIndex)
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ExpandQuestLogHeader: expanded header at logIndex=" .. tostring(logIndex) .. self.RESET)
    end
end

-- CollapseQuestLogHeader(logIndex)
-- Collapses the zone header at logIndex.
-- Verifies the entry is a header before acting; emits a normal-level debug
-- message and returns without collapsing if it is not.
-- Emits a verbose debug message on successful collapse.
function AQL:CollapseQuestLogHeader(logIndex)
    local _, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(logIndex)
    if not isHeader then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] CollapseQuestLogHeader: logIndex=" .. tostring(logIndex) .. " is not a header — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.CollapseQuestHeader(logIndex)
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] CollapseQuestLogHeader: collapsed header at logIndex=" .. tostring(logIndex) .. self.RESET)
    end
end

-- GetQuestDifficultyColor(level) → {r, g, b}
-- Returns a color table for the given quest level relative to the player.
function AQL:GetQuestDifficultyColor(level)
    return WowQuestAPI.GetQuestDifficultyColor(level)
end

-- GetQuestLogIndex(questID) → logIndex or nil
-- Returns the 1-based quest log index for a questID, or nil if not found.
-- Returns nil for quests under collapsed zone headers — they are invisible
-- to the WoW API even though the quest is in the player's log; expand the
-- header first to make the quest visible.
-- Zone header rows carry no questID and are never matched.
function AQL:GetQuestLogIndex(questID)
    return WowQuestAPI.GetQuestLogIndex(questID)
end

------------------------------------------------------------------------
-- Quest Log APIs — Compound ByIndex
-- Multi-step operations taking logIndex. Delegate down to thin wrappers
-- and WowQuestAPI. All iteration uses WowQuestAPI.GetNumQuestLogEntries()
-- and WowQuestAPI.GetQuestLogTitle(i).
------------------------------------------------------------------------

-- IsQuestIndexShareable(logIndex) → bool
-- Returns true if the quest at logIndex can be shared with party members.
-- Verifies the entry is a quest row (not a header); returns false with a
-- normal-level debug message if it is a header.
-- Saves and restores the current quest log selection so the quest log's
-- visual state is unchanged after the call.
function AQL:IsQuestIndexShareable(logIndex)
    local _, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(logIndex)
    if isHeader then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] IsQuestIndexShareable: logIndex=" .. tostring(logIndex) .. " is a header row — returning false" .. self.RESET)
        end
        return false
    end
    local saved = WowQuestAPI.GetQuestLogSelection()
    WowQuestAPI.SelectQuestLogEntry(logIndex)
    local result = WowQuestAPI.GetQuestLogPushable()
    WowQuestAPI.SelectQuestLogEntry(saved)
    return result
end

-- SelectAndShowQuestLogEntryByIndex(logIndex)
-- Selects the entry at logIndex and refreshes the quest log display.
-- Delegates to SetQuestLogSelection (which emits a verbose debug message).
function AQL:SelectAndShowQuestLogEntryByIndex(logIndex)
    self:SetQuestLogSelection(logIndex)
end

-- OpenQuestLogByIndex(logIndex)
-- Shows the quest log frame and navigates to logIndex.
function AQL:OpenQuestLogByIndex(logIndex)
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] OpenQuestLogByIndex: showing quest log, navigating to logIndex=" .. tostring(logIndex) .. self.RESET)
    end
    WowQuestAPI.ShowQuestLog()
    self:SelectAndShowQuestLogEntryByIndex(logIndex)
end

-- ToggleQuestLogByIndex(logIndex)
-- If the quest log is shown and logIndex is the current selection, hides
-- the quest log. Otherwise opens the quest log and navigates to logIndex.
-- On the hide path: emits a verbose debug message.
-- On the open path: delegates to OpenQuestLogByIndex (which emits its own
-- verbose message — no separate message from ToggleQuestLogByIndex).
function AQL:ToggleQuestLogByIndex(logIndex)
    if WowQuestAPI.IsQuestLogShown() and WowQuestAPI.GetQuestLogSelection() == logIndex then
        if self.debug == "verbose" then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ToggleQuestLogByIndex: quest log is shown and logIndex=" .. tostring(logIndex) .. " is selected — hiding" .. self.RESET)
        end
        WowQuestAPI.HideQuestLog()
    else
        self:OpenQuestLogByIndex(logIndex)
    end
end

-- GetSelectedQuestId() → questID or nil
-- Returns the questID of the currently selected quest log entry.
-- Returns nil if nothing is selected (logIndex = 0) or if the selected
-- entry is a zone header row.
function AQL:GetSelectedQuestId()
    local logIndex = WowQuestAPI.GetQuestLogSelection()
    if not logIndex or logIndex == 0 then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestId: no entry selected — returning nil" .. self.RESET)
        end
        return nil
    end
    local _, _, _, isHeader, _, _, _, questID = WowQuestAPI.GetQuestLogTitle(logIndex)
    if isHeader or not questID then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestId: selected entry logIndex=" .. tostring(logIndex) .. " is a zone header — returning nil" .. self.RESET)
        end
        return nil
    end
    return questID
end

-- GetQuestLogEntries() → array
-- Returns a structured array of all visible quest log entries in display order.
-- Each element: { logIndex=N, isHeader=bool, title="string",
--                 questID=N_or_nil, isCollapsed=bool_or_nil }
-- For quest rows (non-headers): isCollapsed is nil.
-- For header rows: questID is nil.
-- Emits no debug message — pure data query.
function AQL:GetQuestLogEntries()
    local entries = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, isCollapsed, _, _, questID = WowQuestAPI.GetQuestLogTitle(i)
        if title then
            table.insert(entries, {
                logIndex    = i,
                isHeader    = isHeader == true,
                title       = title,
                questID     = (not isHeader) and questID or nil,
                isCollapsed = isHeader and (isCollapsed == true) or nil,
            })
        end
    end
    return entries
end

-- GetQuestLogZones() → array of {name, isCollapsed}
-- Returns an ordered array of zone header entries in the quest log.
-- Each element: { name="string", isCollapsed=bool }
-- Useful for capturing collapsed state before bulk-expanding, then restoring:
--   local zones = AQL:GetQuestLogZones()
--   AQL:ExpandAllQuestLogHeaders()
--   -- ... do work ...
--   for _, z in ipairs(zones) do
--       if z.isCollapsed then AQL:CollapseQuestLogZoneByName(z.name) end
--   end
-- Emits no debug message — pure data query.
function AQL:GetQuestLogZones()
    local zones = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, isCollapsed = WowQuestAPI.GetQuestLogTitle(i)
        if title and isHeader then
            table.insert(zones, { name = title, isCollapsed = isCollapsed == true })
        end
    end
    return zones
end

-- ExpandAllQuestLogHeaders()
-- Expands all currently collapsed zone headers in the quest log.
-- Emits a verbose debug message listing the count of headers expanded.
function AQL:ExpandAllQuestLogHeaders()
    local toExpand = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, isHeader, isCollapsed = WowQuestAPI.GetQuestLogTitle(i)
        if isHeader and isCollapsed then
            table.insert(toExpand, i)
        end
    end
    -- Expand back-to-front to preserve earlier indices.
    for k = #toExpand, 1, -1 do
        WowQuestAPI.ExpandQuestHeader(toExpand[k])
    end
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ExpandAllQuestLogHeaders: expanded " .. tostring(#toExpand) .. " headers" .. self.RESET)
    end
end

-- CollapseAllQuestLogHeaders()
-- Collapses all zone headers in the quest log.
-- Emits a verbose debug message listing the count of headers collapsed.
function AQL:CollapseAllQuestLogHeaders()
    local toCollapse = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(i)
        if isHeader then
            table.insert(toCollapse, i)
        end
    end
    -- Collapse back-to-front to preserve earlier indices.
    for k = #toCollapse, 1, -1 do
        WowQuestAPI.CollapseQuestHeader(toCollapse[k])
    end
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] CollapseAllQuestLogHeaders: collapsed " .. tostring(#toCollapse) .. " headers" .. self.RESET)
    end
end

-- Local helper: finds the logIndex of a zone header by name.
-- Returns logIndex, isCollapsed  — or nil, nil if not found.
local function findZoneHeader(zoneName)
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, isCollapsed = WowQuestAPI.GetQuestLogTitle(i)
        if title and isHeader and title == zoneName then
            return i, isCollapsed == true
        end
    end
    return nil, nil
end

-- ExpandQuestLogZoneByName(zoneName)
-- Finds the zone header matching zoneName and expands it.
-- No-op with a normal-level debug message if zoneName is not found.
function AQL:ExpandQuestLogZoneByName(zoneName)
    local logIndex = findZoneHeader(zoneName)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ExpandQuestLogZoneByName: zone \"" .. tostring(zoneName) .. "\" not found in quest log — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.ExpandQuestHeader(logIndex)
end

-- CollapseQuestLogZoneByName(zoneName)
-- Finds the zone header matching zoneName and collapses it.
-- No-op with a normal-level debug message if zoneName is not found.
function AQL:CollapseQuestLogZoneByName(zoneName)
    local logIndex = findZoneHeader(zoneName)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] CollapseQuestLogZoneByName: zone \"" .. tostring(zoneName) .. "\" not found in quest log — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.CollapseQuestHeader(logIndex)
end

-- ToggleQuestLogZoneByName(zoneName)
-- Finds the zone header matching zoneName; expands if collapsed, collapses
-- if expanded.
-- No-op with a normal-level debug message if zoneName is not found.
function AQL:ToggleQuestLogZoneByName(zoneName)
    local logIndex, isCollapsed = findZoneHeader(zoneName)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ToggleQuestLogZoneByName: zone \"" .. tostring(zoneName) .. "\" not found in quest log — no-op" .. self.RESET)
        end
        return
    end
    if isCollapsed then
        WowQuestAPI.ExpandQuestHeader(logIndex)
    else
        WowQuestAPI.CollapseQuestHeader(logIndex)
    end
end

-- IsQuestLogZoneCollapsed(zoneName) → bool or nil
-- Returns true if the zone header matching zoneName is collapsed,
-- false if expanded, nil if not found.
-- Emits a normal-level debug message when zoneName is not found.
function AQL:IsQuestLogZoneCollapsed(zoneName)
    local logIndex, isCollapsed = findZoneHeader(zoneName)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] IsQuestLogZoneCollapsed: zone \"" .. tostring(zoneName) .. "\" not found in quest log — returning nil" .. self.RESET)
        end
        return nil
    end
    return isCollapsed
end

------------------------------------------------------------------------
-- Quest Log APIs — Compound ById
-- Same operations as ByIndex but accept questID. Internally resolve
-- questID → logIndex via WowQuestAPI.GetQuestLogIndex.
-- If the questID is not in the player's active quest log (including quests
-- under collapsed headers), all ById methods are silent no-ops:
-- bool methods return false, void methods do nothing.
-- A normal-level debug message is emitted so consumers can observe this.
------------------------------------------------------------------------

-- IsQuestIdShareable(questID) → bool
-- Returns true if the quest with questID can be shared with party members.
-- Returns false with a normal-level debug message if questID is not in
-- the active quest log.
function AQL:IsQuestIdShareable(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] IsQuestIdShareable: questID=" .. tostring(questID) .. " not in quest log — returning false" .. self.RESET)
        end
        return false
    end
    return self:IsQuestIndexShareable(logIndex)
end

-- SelectAndShowQuestLogEntryById(questID)
-- Selects questID in the quest log and refreshes the display.
-- No-op with a normal-level debug message if questID is not in the log.
function AQL:SelectAndShowQuestLogEntryById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] SelectAndShowQuestLogEntryById: questID=" .. tostring(questID) .. " not in quest log — no-op" .. self.RESET)
        end
        return
    end
    self:SelectAndShowQuestLogEntryByIndex(logIndex)
end

-- OpenQuestLogById(questID)
-- Opens the quest log and navigates to questID.
-- No-op with a normal-level debug message if questID is not in the log.
function AQL:OpenQuestLogById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] OpenQuestLogById: questID=" .. tostring(questID) .. " not in quest log — no-op" .. self.RESET)
        end
        return
    end
    self:OpenQuestLogByIndex(logIndex)
end

-- ToggleQuestLogById(questID)
-- Toggles the quest log open/closed for questID.
-- No-op with a normal-level debug message if questID is not in the log.
function AQL:ToggleQuestLogById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ToggleQuestLogById: questID=" .. tostring(questID) .. " not in quest log — no-op" .. self.RESET)
        end
        return
    end
    self:ToggleQuestLogByIndex(logIndex)
end

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------

SLASH_ABSOLUTEQUESTLOG1 = "/aql"
SlashCmdList["ABSOLUTEQUESTLOG"] = function(input)
    -- Look up the library at call time so this handler is robust even if the
    -- file was loaded more than once (e.g. two copies on the load path).
    local aql = LibStub("AbsoluteQuestLog-1.0", true)
    if not aql then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[AQL] Error: library not loaded|r")
        return
    end
    local sub, arg = (input or ""):match("^%s*(%S+)%s*(.-)%s*$")
    sub = sub and sub:lower() or ""
    arg = arg and arg:lower() or ""

    if sub == "debug" then
        if arg == "on" or arg == "normal" then
            aql.debug = "normal"
            DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Debug mode: normal" .. aql.RESET)
        elseif arg == "verbose" then
            aql.debug = "verbose"
            DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Debug mode: verbose" .. aql.RESET)
        elseif arg == "off" then
            aql.debug = nil
            DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Debug mode: off" .. aql.RESET)
        else
            DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Usage: /aql debug [on|normal|verbose|off]" .. aql.RESET)
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Usage: /aql debug [on|normal|verbose|off]" .. aql.RESET)
    end
end
