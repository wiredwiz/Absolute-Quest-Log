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
