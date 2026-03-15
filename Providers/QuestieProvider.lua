-- Providers/QuestieProvider.lua
-- Reads chain metadata from QuestieDB if Questie is installed.
-- Questie stores quest data under QuestieDB.GetQuest(questID).
-- Relevant fields on a quest object (questie v11.x):
--   quest.nextQuestInChain  (questID of next step, or 0)
-- Type info comes from quest.requiredClasses / questTagIds in QuestieDB.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local QuestieProvider = {}

-- questTagIds enum values from QuestieDB (QuestieDB.lua questKeys):
--   ELITE = 1, RAID = 62, DUNGEON = 81
-- Daily is detected via quest.questFlags (bit 1 = DAILY in classic era flags).
local TAG_ELITE   = 1
local TAG_RAID    = 62
local TAG_DUNGEON = 81

-- Returns true if Questie is available and the provider can be used.
function QuestieProvider:IsAvailable()
    return type(QuestieDB) == "table"
        and type(QuestieDB.GetQuest) == "function"
end

-- Lazy reverse-index: reverseChain[N] = questID whose nextQuestInChain == N.
-- Built once from QuestieDB.QuestPointers (the table of all questIDs in Questie).
-- Allows O(1) backward traversal to find the true chain root.
-- WARNING: QuestieDB.QuestPointers must exist in the installed Questie version.
-- If absent, chainID falls back to the current questID (chain matching across
-- players at different steps will break — document this to consumers).
local reverseChain = nil

local function buildReverseChain()
    if reverseChain then return reverseChain end
    reverseChain = {}
    local pointers = QuestieDB.QuestPointers or QuestieDB.questPointers
    if type(pointers) ~= "table" then
        -- QuestPointers not available in this Questie version. reverseChain stays empty.
        return reverseChain
    end
    for questID in pairs(pointers) do
        local ok, q = pcall(QuestieDB.GetQuest, questID)
        if ok and q and q.nextQuestInChain and q.nextQuestInChain ~= 0 then
            reverseChain[q.nextQuestInChain] = questID
        end
    end
    return reverseChain
end

-- Walk backward from questID to find the true chain root (the quest with no predecessor).
local function findChainRoot(questID)
    local rev = buildReverseChain()
    local current = questID
    local visited = {}
    while rev[current] and not visited[current] do
        visited[current] = true
        current = rev[current]
    end
    return current  -- returns questID itself if no predecessor is found
end

-- Build a chain starting from the true root, following nextQuestInChain forward.
-- Returns { chainRoot, steps[] } or nil if the quest is not part of a chain.
local function buildChain(startQuestID)
    local quest = QuestieDB.GetQuest(startQuestID)
    if not quest then return nil end

    local nextID = quest.nextQuestInChain
    if not nextID or nextID == 0 then
        -- Check if any quest points TO startQuestID (startQuestID may be a later step).
        local rev = buildReverseChain()
        if not rev[startQuestID] then
            return nil  -- standalone quest
        end
        -- startQuestID is a later step in a chain; fall through to root-finding below.
    end

    -- Find the true chain root by walking backward.
    local chainRoot = findChainRoot(startQuestID)

    -- Collect all steps by walking forward from the root.
    local steps = {}
    local current = chainRoot
    local visited = { [chainRoot] = true }

    while current do
        table.insert(steps, { questID = current })
        local q = QuestieDB.GetQuest(current)
        local nxt = q and q.nextQuestInChain
        if not nxt or nxt == 0 or visited[nxt] then break end
        visited[nxt] = true
        current = nxt
    end

    if #steps < 2 then return nil end  -- single-step "chain" is just a standalone quest

    return { chainRoot = chainRoot, steps = steps }
end

function QuestieProvider:GetChainInfo(questID)
    local chain = buildChain(questID)
    if not chain then
        return { knownStatus = "not_a_chain" }
    end

    local steps = chain.steps
    local chainID = chain.chainRoot
    local length = #steps

    -- Find the step index for questID within the steps array.
    local stepNum = nil
    for i, s in ipairs(steps) do
        if s.questID == questID then
            stepNum = i
            break
        end
    end

    -- Annotate each step with title and status.
    for _, s in ipairs(steps) do
        local sid = s.questID
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(sid) then
            s.status = "completed"
        elseif AQL.QuestCache and AQL.QuestCache:Get(sid) then
            local q = AQL.QuestCache:Get(sid)
            if q.isFailed then
                s.status = "failed"
            elseif q.isComplete then
                s.status = "finished"
            else
                s.status = "active"
            end
        else
            -- Quest not active and not in completion history.
            -- Determine available / unavailable / unknown.
            local prevIdx = nil
            for i, ps in ipairs(steps) do
                if ps.questID == sid then prevIdx = i break end
            end

            -- "unknown": questID is in the chain definition but QuestieDB cannot
            -- return data for it (QuestieDB.GetQuest returns nil). Only applies
            -- when the chain itself is known (knownStatus = "known") but this
            -- individual step's questID is missing from QuestieDB.
            local stepQuestData = QuestieDB.GetQuest(sid)
            -- Use `questID` (the parameter of GetChainInfo) not `startQuestID`
            -- (which is local to buildChain and out of scope here).
            if not stepQuestData and sid ~= questID then
                s.status = "unknown"
            elseif prevIdx and prevIdx > 1 then
                local prev = steps[prevIdx - 1]
                local prevCompleted = AQL.HistoryCache and AQL.HistoryCache:HasCompleted(prev.questID)
                s.status = prevCompleted and "available" or "unavailable"
            else
                s.status = "available"  -- first step, not yet started
            end
        end

        -- Title: prefer Questie's stored name, fall back to C_QuestLog.GetQuestInfo
        -- (returns title string only in TBC 20505), then a numeric placeholder.
        local sq = QuestieDB.GetQuest(sid)
        s.title = (sq and sq.name) or C_QuestLog.GetQuestInfo(sid) or ("Quest "..sid)  -- pre-existing; AQL internal migration deferred
    end

    return {
        knownStatus = "known",
        chainID     = chainID,
        step        = stepNum,
        length      = length,
        steps       = steps,
        provider    = "Questie",
    }
end

-- Returns { title, questLevel, requiredLevel, zone } from QuestieDB, or nil.
-- Questie questKeys (tbcQuestDB.lua):
--   quest.name          = key 1  (string, quest title)
--   quest.requiredLevel = key 4  (int, minimum player level to accept)
--   quest.questLevel    = key 5  (int, quest difficulty level)
--   quest.zoneOrSort    = key 17 (int: >0 = DBC AreaTable ID, <0 = QuestSort category, 0 = none)
-- Zone: C_Map.GetAreaInfo(quest.zoneOrSort) returns the localized zone name string when
-- zoneOrSort > 0. Negative values are quest categories (not geographic zones) — omit.
function QuestieProvider:GetQuestBasicInfo(questID)
    if not self:IsAvailable() then return nil end
    local ok, quest = pcall(QuestieDB.GetQuest, questID)
    if not ok or not quest then return nil end
    local zone
    if quest.zoneOrSort and quest.zoneOrSort > 0 then
        zone = C_Map.GetAreaInfo(quest.zoneOrSort)  -- returns string or nil
    end
    return {
        title         = quest.name,
        questLevel    = quest.questLevel,
        requiredLevel = quest.requiredLevel,
        zone          = zone,
    }
end

function QuestieProvider:GetQuestType(questID)
    local quest = QuestieDB.GetQuest(questID)
    if not quest then return nil end

    -- questTagIds field stores the quest's tag (from QuestieDB questKeys).
    local tag = quest.questTagId
    if tag == TAG_ELITE   then return "elite"   end
    if tag == TAG_RAID    then return "raid"    end
    if tag == TAG_DUNGEON then return "dungeon" end

    -- Daily detection: check zoneOrSort or questFlags depending on Questie version.
    -- Questie v11 uses a flags bitmask; bit 1 (value 1) = DAILY in Classic.
    if quest.questFlags and bit.band(quest.questFlags, 1) == 1 then
        return "daily"
    end

    return "normal"
end

function QuestieProvider:GetQuestFaction(questID)
    local quest = QuestieDB.GetQuest(questID)
    if not quest then return nil end
    -- Questie stores faction as a numeric: 0 = any, 1 = Horde, 2 = Alliance
    if quest.requiredFaction == 1 then return "Horde"    end
    if quest.requiredFaction == 2 then return "Alliance" end
    return nil
end

AQL.QuestieProvider = QuestieProvider
