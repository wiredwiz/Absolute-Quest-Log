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

-- Sub-module slots — populated by the files that load after this one.
-- AbsoluteQuestLog.lua loads first (per TOC order), so these are nil until
-- the sub-module files run. Public methods guard against nil sub-modules.
-- AQL.QuestCache   set by Core/QuestCache.lua
-- AQL.HistoryCache set by Core/HistoryCache.lua
-- AQL.EventEngine  set by Core/EventEngine.lua
-- AQL.provider     set by Core/EventEngine.lua at PLAYER_LOGIN

------------------------------------------------------------------------
-- Public API: Quest State Queries
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
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.link or nil
end

------------------------------------------------------------------------
-- Public API: Objective Queries
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
-- Public API: Chain Queries
------------------------------------------------------------------------

function AQL:GetChainInfo(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.chainInfo then
        return q.chainInfo
    end
    return { knownStatus = "unknown" }
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
-- Public API: WowQuestAPI-backed Extended Queries
------------------------------------------------------------------------

-- Three-tier resolution. Contrast with AQL:GetQuest which is cache-only.
--   Tier 1: AQL QuestCache (full normalized snapshot)
--   Tier 2: WowQuestAPI log scan → { questID, title, level, suggestedGroup, isComplete, zone }
--           or title-only { questID, title } when not in log
--   Tier 3: AQL.provider:GetQuestBasicInfo → { title, questLevel, requiredLevel, zone }
--           merged with AQL.provider:GetChainInfo → chainInfo (chainID, step, length)
-- Returns nil only when all three tiers have no data.
function AQL:GetQuestInfo(questID)
    -- Tier 1: cache.
    local cached = self.QuestCache and self.QuestCache:Get(questID)
    if cached then return cached end

    -- Tier 2: WoW log scan / title fallback.
    local result = WowQuestAPI.GetQuestInfo(questID)
    if result then return result end

    -- Tier 3: provider (Questie / QuestWeaver).
    local provider = self.provider
    if not provider then return nil end

    local basicInfo
    if provider.GetQuestBasicInfo then
        local ok, info = pcall(provider.GetQuestBasicInfo, provider, questID)
        if ok and info then basicInfo = info end
    end

    local chainInfo = { knownStatus = "unknown" }
    if provider.GetChainInfo then
        local ok, ci = pcall(provider.GetChainInfo, provider, questID)
        if ok and ci then chainInfo = ci end
    end

    if not basicInfo and chainInfo.knownStatus == "unknown" then return nil end

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
