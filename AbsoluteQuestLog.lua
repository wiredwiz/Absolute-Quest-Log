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
    return self.HistoryCache ~= nil and self.HistoryCache:HasCompleted(questID)
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
