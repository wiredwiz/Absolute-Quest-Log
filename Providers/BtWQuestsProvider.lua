-- Providers/BtWQuestsProvider.lua
-- Reads quest chain data from BtWQuests if installed (Retail).
-- BtWQuests stores chains at BtWQuests.Database.Chains[chainKey].
-- Covers: Chain capability (GetChainInfo), QuestInfo (GetQuestFaction only),
-- Requirements (level range + nextQuestInChain for step 1).

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local BtWQuestsProvider = {}

------------------------------------------------------------------------
-- Module-level constants
-- Define all literals in one place so changes require edits in exactly one spot.
------------------------------------------------------------------------

-- Item type string for quest steps. BtWQuests has no exported constant for this.
local ITEM_TYPE_QUEST = "quest"

-- Faction condition IDs used in chain.restrictions arrays.
-- Registered in BtWQuestsDatabase.lua via Database:AddCondition(923/924, ...).
-- BtWQuests exports no named constant for these numeric IDs.
local CONDITION_ID_HORDE    = 923
local CONDITION_ID_ALLIANCE = 924

------------------------------------------------------------------------
-- Reverse index: questID → chainKey
-- Built incrementally on demand. All IDs for a step (item.id, item.ids,
-- item.variations) are indexed so any player variant resolves correctly.
------------------------------------------------------------------------

local _questToChain  = {}    -- [questID] = chainKey
local _scannedChains = {}    -- [chainKey] = true; prevents re-scanning
local _fullyIndexed  = false -- set true once all chains exhausted

-- Scan one chain and write all its questID → chainKey mappings.
local function indexChain(chainKey, chain)
    if type(chain.items) ~= "table" then return end
    for _, item in ipairs(chain.items) do
        if item.type == ITEM_TYPE_QUEST then
            -- Collect every questID that satisfies this step.
            local candidates = {}
            if item.ids then
                for _, qid in ipairs(item.ids) do candidates[#candidates + 1] = qid end
            elseif item.id then
                candidates[1] = item.id
            end
            if item.variations then
                for _, qid in ipairs(item.variations) do candidates[#candidates + 1] = qid end
            end
            -- First-write-wins: a questID in two chains is an authoring error; keep first.
            for _, qid in ipairs(candidates) do
                if not _questToChain[qid] then
                    _questToChain[qid] = chainKey
                end
            end
        end
    end
    _scannedChains[chainKey] = true
end

-- Find the chainKey for questID. Scans lazily — stops as soon as a hit is found.
local function findChainKey(questID)
    if not (BtWQuests and BtWQuests.Database and BtWQuests.Database.Chains) then
        return nil
    end
    if _questToChain[questID] then return _questToChain[questID] end
    if _fullyIndexed then return nil end

    for chainKey, chain in pairs(BtWQuests.Database.Chains) do
        if type(chain) == "table" and not _scannedChains[chainKey] then
            indexChain(chainKey, chain)
            if _questToChain[questID] then return chainKey end
        end
    end
    _fullyIndexed = true
    return nil
end

------------------------------------------------------------------------
-- Identity and capability declaration
------------------------------------------------------------------------

BtWQuestsProvider.addonName    = "BtWQuests"
BtWQuestsProvider.capabilities = {
    AQL.Capability.Chain,
    AQL.Capability.QuestInfo,
    AQL.Capability.Requirements,
}

------------------------------------------------------------------------
-- IsAvailable / Validate
------------------------------------------------------------------------

-- Lightweight presence check. IsAvailable()=false → skip silently (addon absent).
function BtWQuestsProvider:IsAvailable()
    return type(BtWQuests) == "table"
        and type(BtWQuests.Database) == "table"
end

-- Structural check. IsAvailable()=true + Validate()=false → fire broken-provider warning.
-- BtWQuests loads synchronously; an empty Chains table is a broken install, not async init.
function BtWQuestsProvider:Validate()
    if type(BtWQuests) ~= "table" then
        return false, "BtWQuests global missing"
    end
    if type(BtWQuests.Database) ~= "table" then
        return false, "BtWQuests.Database missing"
    end
    if type(BtWQuests.Database.Chains) ~= "table" then
        return false, "Chains table missing"
    end
    local sample = next(BtWQuests.Database.Chains)
    if sample == nil then
        return false, "Chains table is empty"
    end
    return true
end

AQL.BtWQuestsProvider = BtWQuestsProvider
