-- Providers/QuestWeaverProvider.lua
-- Reads chain metadata from QuestWeaver if installed (and Questie is absent).
-- QuestWeaver stores quest data at _G["QuestWeaver"].Quests[questID].
-- Relevant fields: quest_series (array of questIDs), chain_id, chain_position,
-- chain_length. ChainBuilder:GetChain(questID) builds the full chain table.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local QuestWeaverProvider = {}

QuestWeaverProvider.addonName    = "QuestWeaver"
QuestWeaverProvider.capabilities = {
    AQL.Capability.Chain,
    AQL.Capability.QuestInfo,
    -- Requirements excluded: QuestWeaver only exposes min_level, not the full requirements contract.
}

-- IsAvailable: QuestWeaver global table is present.
-- Validate() handles the structural readiness check.
function QuestWeaverProvider:IsAvailable()
    return type(_G["QuestWeaver"]) == "table"
end

function QuestWeaverProvider:Validate()
    local qw = _G["QuestWeaver"]
    if type(qw) ~= "table" then return false, "QuestWeaver global missing" end
    if type(qw.Quests) ~= "table" then return false, "QuestWeaver.Quests missing" end
    -- QuestWeaver populates qw.Quests synchronously at load time (unlike Questie's async init).
    -- An empty Quests table here means QuestWeaver is broken, not "not yet ready".
    local sample = next(qw.Quests)
    if sample == nil then return false, "QuestWeaver.Quests is empty" end
    return true
end

function QuestWeaverProvider:GetChainInfo(questID)
    local qw = _G["QuestWeaver"]
    if not qw then return { knownStatus = AQL.ChainStatus.Unknown } end

    local quest = qw.Quests[questID]
    if not quest then return { knownStatus = AQL.ChainStatus.Unknown } end

    -- quest_series is an ordered array of questIDs in this chain.
    local series = quest.quest_series
    if not series or #series == 0 then
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    local chainID = series[1]  -- first questID in the series
    local length  = #series
    local stepNum = nil

    local steps = {}
    for i, sid in ipairs(series) do
        if sid == questID then stepNum = i end

        local status
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(sid) then
            status = AQL.StepStatus.Completed
        elseif AQL.QuestCache and AQL.QuestCache:Get(sid) then
            local q = AQL.QuestCache:Get(sid)
            if q.isFailed then
                status = AQL.StepStatus.Failed
            elseif q.isComplete then
                status = AQL.StepStatus.Finished
            else
                status = AQL.StepStatus.Active
            end
        else
            -- "unknown": sid is in quest_series but absent from qw.Quests —
            -- the chain structure is known but this step's data is missing.
            if not qw.Quests[sid] then
                status = AQL.StepStatus.Unknown
            elseif i == 1 then
                status = AQL.StepStatus.Available
            else
                local prev = steps[i - 1]
                status = (prev and prev.status == AQL.StepStatus.Completed) and AQL.StepStatus.Available or AQL.StepStatus.Unavailable
            end
        end

        -- Title: prefer QuestWeaver stored name, fall back to C_QuestLog.GetQuestInfo
        -- (returns title string only in TBC 20505), then a numeric placeholder.
        local title = WowQuestAPI.GetQuestInfo(sid) or ("Quest "..sid)
        local sqw = qw.Quests[sid]
        if sqw and sqw.name then title = sqw.name end

        steps[i] = { questID = sid, title = title, status = status }
    end

    return {
        knownStatus = AQL.ChainStatus.Known,
        chains = {
            {
                chainID    = chainID,
                step       = stepNum,
                length     = length,
                questCount = length,
                steps      = steps,
                provider   = AQL.Provider.QuestWeaver,
            }
        }
    }
end

function QuestWeaverProvider:GetQuestType(questID)
    local qw = _G["QuestWeaver"]
    if not qw then return nil end
    local quest = qw.Quests and qw.Quests[questID]
    if not quest then return nil end
    -- QuestWeaver stores quest type in quest.quest_type (string) when present.
    return quest.quest_type or AQL.QuestType.Normal
end

function QuestWeaverProvider:GetQuestFaction(questID)
    local qw = _G["QuestWeaver"]
    if not qw then return nil end
    local quest = qw.Quests and qw.Quests[questID]
    if not quest then return nil end
    -- QuestWeaver faction field: "Alliance", "Horde", or nil.
    return quest.faction or nil
end

function QuestWeaverProvider:GetQuestBasicInfo(questID)
    local qw = _G["QuestWeaver"]
    if not qw or not qw.Quests then return nil end
    local quest = qw.Quests[questID]
    if not quest then return nil end
    return {
        title         = quest.name,
        questLevel    = quest.level,
        requiredLevel = quest.min_level,
        zone          = quest.source_zone or quest.zone,
    }
end

function QuestWeaverProvider:GetQuestRequirements(questID)
    local qw = _G["QuestWeaver"]
    local quest = qw.Quests and qw.Quests[questID]
    if not quest then return nil end
    -- QuestWeaver only exposes min_level; all other requirement fields are unavailable.
    local minLevel = quest.min_level
    if not minLevel or minLevel == 0 then minLevel = nil end
    return {
        requiredLevel        = minLevel,
        requiredMaxLevel     = nil,
        requiredRaces        = nil,
        requiredClasses      = nil,
        preQuestGroup        = nil,
        preQuestSingle       = nil,
        exclusiveTo          = nil,
        nextQuestInChain     = nil,
        breadcrumbForQuestId = nil,
    }
end

AQL.QuestWeaverProvider = QuestWeaverProvider
