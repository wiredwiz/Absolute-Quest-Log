-- Providers/QuestWeaverProvider.lua
-- Reads chain metadata from QuestWeaver if installed (and Questie is absent).
-- QuestWeaver stores quest data at _G["QuestWeaver"].Quests[questID].
-- Relevant fields: quest_series (array of questIDs), chain_id, chain_position,
-- chain_length. ChainBuilder:GetChain(questID) builds the full chain table.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local QuestWeaverProvider = {}

function QuestWeaverProvider:IsAvailable()
    local qw = _G["QuestWeaver"]
    return type(qw) == "table"
        and type(qw.Quests) == "table"
        and next(qw.Quests) ~= nil
end

function QuestWeaverProvider:GetChainInfo(questID)
    local qw = _G["QuestWeaver"]
    if not qw then return { knownStatus = "unknown" } end

    local quest = qw.Quests[questID]
    if not quest then return { knownStatus = "unknown" } end

    -- quest_series is an ordered array of questIDs in this chain.
    local series = quest.quest_series
    if not series or #series == 0 then
        return { knownStatus = "not_a_chain" }
    end

    local chainID = series[1]  -- first questID in the series
    local length  = #series
    local stepNum = nil

    local steps = {}
    for i, sid in ipairs(series) do
        if sid == questID then stepNum = i end

        local status
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(sid) then
            status = "completed"
        elseif AQL.QuestCache and AQL.QuestCache:Get(sid) then
            local q = AQL.QuestCache:Get(sid)
            if q.isFailed then
                status = "failed"
            elseif q.isComplete then
                status = "finished"
            else
                status = "active"
            end
        else
            -- "unknown": sid is in quest_series but absent from qw.Quests —
            -- the chain structure is known but this step's data is missing.
            if not qw.Quests[sid] then
                status = "unknown"
            elseif i == 1 then
                status = "available"
            else
                local prev = steps[i - 1]
                status = (prev and prev.status == "completed") and "available" or "unavailable"
            end
        end

        -- Title: prefer QuestWeaver stored name, fall back to C_QuestLog.GetQuestInfo
        -- (returns title string only in TBC 20505), then a numeric placeholder.
        local title = C_QuestLog.GetQuestInfo(sid) or ("Quest "..sid)  -- pre-existing; AQL internal migration deferred
        local sqw = qw.Quests[sid]
        if sqw and sqw.name then title = sqw.name end

        steps[i] = { questID = sid, title = title, status = status }
    end

    return {
        knownStatus = "known",
        chainID     = chainID,
        step        = stepNum,
        length      = length,
        steps       = steps,
        provider    = "QuestWeaver",
    }
end

function QuestWeaverProvider:GetQuestType(questID)
    local qw = _G["QuestWeaver"]
    if not qw then return nil end
    local quest = qw.Quests and qw.Quests[questID]
    if not quest then return nil end
    -- QuestWeaver stores quest type in quest.quest_type (string) when present.
    return quest.quest_type or "normal"
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
    if not self:IsAvailable() then return nil end
    local qw = _G["QuestWeaver"]
    local quest = qw.Quests[questID]
    if not quest then return nil end
    return {
        title         = quest.name,
        questLevel    = quest.level,
        requiredLevel = quest.min_level,
        zone          = quest.source_zone or quest.zone,
    }
end

AQL.QuestWeaverProvider = QuestWeaverProvider
