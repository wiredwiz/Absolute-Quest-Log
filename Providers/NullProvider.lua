-- Providers/NullProvider.lua
-- Fallback provider used when neither Questie nor QuestWeaver is present.
-- Always returns knownStatus = "unknown" for chain queries.
-- NullProvider is never in the PROVIDER_PRIORITY table — it is not selectable.
-- It exists as the value of the AQL.provider backward-compatibility shim when
-- no Chain provider is active.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local NullProvider = {}

NullProvider.addonName    = "none"
NullProvider.capabilities = {}   -- covers no capabilities

function NullProvider:IsAvailable()
    return false   -- NullProvider is never selected; always reports unavailable
end

function NullProvider:Validate()
    return true    -- structurally valid; covers no capabilities
end

function NullProvider:GetChainInfo(questID)
    return { knownStatus = AQL.ChainStatus.Unknown }
end

function NullProvider:GetQuestType(questID)
    return nil
end

function NullProvider:GetQuestFaction(questID)
    return nil
end

function NullProvider:GetQuestRequirements(questID)
    return nil
end

AQL.NullProvider = NullProvider
