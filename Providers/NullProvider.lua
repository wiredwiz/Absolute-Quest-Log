-- Providers/NullProvider.lua
-- Fallback provider used when neither Questie nor QuestWeaver is present.
-- Always returns knownStatus = "unknown" for chain queries.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local NullProvider = {}

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
