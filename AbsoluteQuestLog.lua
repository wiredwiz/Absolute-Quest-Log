-- AbsoluteQuestLog-1.0
-- LibStub library providing unified quest data access for WoW TBC Anniversary.
-- Consumers: LibStub("AbsoluteQuestLog-1.0")

local MAJOR, MINOR = "AbsoluteQuestLog-1.0", 1
local AQL, oldVersion = LibStub:NewLibrary(MAJOR, MINOR)
if not AQL then return end  -- Already loaded at equal or higher version.

-- CallbackHandler provides AQL:RegisterCallback / AQL:UnregisterCallback.
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

function AQL:GetQuest(questID)
    return self.QuestCache and self.QuestCache:Get(questID) or nil
end

function AQL:GetAllQuests()
    return self.QuestCache and self.QuestCache:GetAll() or {}
end

function AQL:GetQuestsByZone(zone)
    -- zone is the English canonical zone name as stored by the active chain
    -- provider (e.g. "Blasted Lands"). On non-English clients, use
    -- GetAllQuests() and filter by questID instead.
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.zone == zone then
            result[questID] = info
        end
    end
    return result
end

function AQL:IsQuestActive(questID)
    return self.QuestCache ~= nil and self.QuestCache:Get(questID) ~= nil
end

function AQL:IsQuestFinished(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q ~= nil and q.isComplete == true
end

------------------------------------------------------------------------
-- Quest History
------------------------------------------------------------------------

function AQL:HasCompletedQuest(questID)
    if self.HistoryCache and self.HistoryCache:HasCompleted(questID) then
        return true
    end
    return WowQuestAPI.IsQuestFlaggedCompleted(questID)
end

function AQL:GetCompletedQuests()
    return self.HistoryCache and self.HistoryCache:GetAll() or {}
end

function AQL:GetCompletedQuestCount()
    return self.HistoryCache and self.HistoryCache:GetCount() or 0
end

function AQL:GetQuestType(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.type or nil
end

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

function AQL:GetObjectives(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.objectives or nil
end

function AQL:GetObjective(questID, index)
    local objs = self:GetObjectives(questID)
    return objs and objs[index] or nil
end

------------------------------------------------------------------------
-- Chain Info
------------------------------------------------------------------------

function AQL:GetChainInfo(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.chainInfo then
        return q.chainInfo
    end
    return { knownStatus = AQL.ChainStatus.Unknown }
end

function AQL:GetChainStep(questID)
    return self:GetChainInfo(questID).step
end

function AQL:GetChainLength(questID)
    return self:GetChainInfo(questID).length
end

-- AQL:RegisterCallback(event, handler, target) -- from CallbackHandler
-- AQL:UnregisterCallback(event, handler)        -- from CallbackHandler

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
