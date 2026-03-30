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
-- Step extraction helpers
------------------------------------------------------------------------

-- Pick the single questID that best represents a chain step for the current player.
-- A step may have multiple valid questIDs (item.ids = OR logic; item.variations =
-- alternate versions). Priority:
--   1. lookupQuestID itself, if it's a candidate for this step
--   2. Any candidate currently in the player's active quest log (QuestCache)
--   3. Any candidate the player has completed (HistoryCache)
--   4. First candidate (arbitrary but deterministic)
local function resolveStepQuestID(item, lookupQuestID)
    local candidates = {}
    if item.ids then
        for _, qid in ipairs(item.ids) do candidates[#candidates + 1] = qid end
    elseif item.id then
        candidates[1] = item.id
    end
    if item.variations then
        for _, qid in ipairs(item.variations) do candidates[#candidates + 1] = qid end
    end

    if lookupQuestID then
        for _, qid in ipairs(candidates) do
            if qid == lookupQuestID then return lookupQuestID end
        end
    end
    for _, qid in ipairs(candidates) do
        if AQL.QuestCache and AQL.QuestCache:Get(qid) then return qid end
    end
    for _, qid in ipairs(candidates) do
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(qid) then return qid end
    end
    return candidates[1]
end

-- Build an ordered array of { questID } entries from a chain's items[],
-- one entry per quest-type item. Non-quest items are silently skipped.
-- lookupQuestID is used by resolveStepQuestID to prefer the caller's own questID
-- when it is a valid candidate for a step.
local function extractQuestIDs(items, lookupQuestID)
    local result = {}
    for _, item in ipairs(items) do
        if item.type == ITEM_TYPE_QUEST then
            local qid = resolveStepQuestID(item, lookupQuestID)
            if qid then
                result[#result + 1] = { questID = qid }
            end
        end
    end
    return result
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

------------------------------------------------------------------------
-- Chain capability
------------------------------------------------------------------------

function BtWQuestsProvider:GetChainInfo(questID)
    local chainKey = findChainKey(questID)
    if not chainKey then
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    local chain = BtWQuests.Database.Chains[chainKey]
    if not chain then
        -- chainKey was indexed but chain is now missing — stale index entry.
        return { knownStatus = AQL.ChainStatus.Unknown }
    end

    local steps = extractQuestIDs(chain.items or {}, questID)
    -- Chains that yield fewer than 2 quest steps after filtering (e.g. chains
    -- composed mostly of NPC/cutscene items) are not surfaced as chains.
    if #steps < 2 then
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    local aqlChainID = steps[1].questID

    -- stepNum: resolveStepQuestID prioritises questID itself as the representative
    -- for its step, so comparing steps[i].questID == questID is safe.
    local stepNum = nil
    for i, s in ipairs(steps) do
        if s.questID == questID then stepNum = i; break end
    end

    -- Annotate each step with title and status.
    for i, s in ipairs(steps) do
        local sid = s.questID
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(sid) then
            s.status = AQL.StepStatus.Completed
        else
            local q = AQL.QuestCache and AQL.QuestCache:Get(sid)
            if q then
                if q.isFailed then
                    s.status = AQL.StepStatus.Failed
                elseif q.isComplete then
                    s.status = AQL.StepStatus.Finished
                else
                    s.status = AQL.StepStatus.Active
                end
            else
                local prev = steps[i - 1]
                local prevDone = prev
                    and AQL.HistoryCache
                    and AQL.HistoryCache:HasCompleted(prev.questID)
                s.status = (i == 1 or prevDone)
                    and AQL.StepStatus.Available
                    or  AQL.StepStatus.Unavailable
            end
        end
        local info = WowQuestAPI.GetQuestInfo(sid)
        s.title = (info and info.title) or ("Quest " .. sid)
    end

    return {
        knownStatus = AQL.ChainStatus.Known,
        chainID     = aqlChainID,
        step        = stepNum,
        length      = #steps,
        steps       = steps,
        provider    = AQL.Provider.BtWQuests,
    }
end

------------------------------------------------------------------------
-- QuestInfo capability
------------------------------------------------------------------------

-- Decode faction from a chain.restrictions array.
-- BtWQuests encodes faction in two ways:
--   Numeric condition IDs: 923 = Horde, 924 = Alliance (most chains)
--   Table entries: { type = "faction", id = "Horde" } (some chains)
-- BtWQuests.Constant.Faction holds the authoritative faction strings.
local function decodeFaction(restrictions)
    if type(restrictions) ~= "table" then return nil end
    local factionConst = BtWQuests.Constant and BtWQuests.Constant.Faction  -- { Horde="Horde", Alliance="Alliance" }
    if not factionConst then return nil end
    for _, r in ipairs(restrictions) do
        if r == CONDITION_ID_HORDE    then return AQL.Faction.Horde    end
        if r == CONDITION_ID_ALLIANCE then return AQL.Faction.Alliance end
        if type(r) == "table" and r.type == "faction" then
            if r.id == factionConst.Horde    then return AQL.Faction.Horde    end
            if r.id == factionConst.Alliance then return AQL.Faction.Alliance end
        end
    end
    return nil
end

-- GetQuestFaction reads chain-level restrictions only.
-- Item-level restrictions are not decoded (chain-level covers the vast majority of
-- faction-gated content; item-level faction gates are rare and chain-level is
-- sufficient for UI purposes).
function BtWQuestsProvider:GetQuestFaction(questID)
    local chainKey = findChainKey(questID)
    if not chainKey then return nil end
    local chain = BtWQuests.Database.Chains[chainKey]
    if not chain then return nil end
    return decodeFaction(chain.restrictions)
end

-- BtWQuests has no quest type data (elite/dungeon/raid/daily).
function BtWQuestsProvider:GetQuestType(questID)
    return nil
end

AQL.BtWQuestsProvider = BtWQuestsProvider
