-- Providers/GrailProvider.lua
-- Reads quest data from the Grail addon (Grail-123 for Classic/TBC/Wrath,
-- Grail-124 for Retail/TWW). Covers all three AQL capabilities:
--   Chain        — reverse-engineered from Grail.questPrerequisites
--   QuestInfo    — GetQuestBasicInfo, GetQuestType, GetQuestFaction
--   Requirements — prerequisite IDs, exclusiveTo, level range
--
-- Chain reconstruction is lazy: the reverse map is built on the first call to
-- GetChainInfo and cached for the session. All other methods are per-quest lookups
-- with no upfront cost.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local GrailProvider = {}

GrailProvider.addonName    = "Grail"
GrailProvider.capabilities = {
    AQL.Capability.Chain,
    AQL.Capability.QuestInfo,
    AQL.Capability.Requirements,
}

------------------------------------------------------------------------
-- Detection
------------------------------------------------------------------------

-- IsAvailable(): lightweight structural check — Grail global + required tables present.
function GrailProvider:IsAvailable()
    local g = _G["Grail"]
    return g ~= nil
        and type(g.questCodes)         == "table"
        and type(g.questPrerequisites) == "table"
end

-- Validate(): database has loaded (questCodes is non-empty).
-- Grail initializes synchronously at PLAYER_LOGIN, so non-empty = ready.
function GrailProvider:Validate()
    local g = _G["Grail"]
    if not g then return false end
    return next(g.questCodes) ~= nil
end

------------------------------------------------------------------------
-- QuestInfo capability
------------------------------------------------------------------------

function GrailProvider:GetQuestBasicInfo(questID)
    local g = _G["Grail"]
    if not g then return nil end

    local title = g:QuestName(questID)
    if not title then return nil end

    -- Zone: take the first accept-location record's mapArea and resolve via Grail's
    -- own MapAreaName(). mapArea values are uiMapIDs, not AreaTable IDs — calling
    -- C_Map.GetAreaInfo(mapArea) is wrong because GetAreaInfo expects AreaTable IDs
    -- and passing a uiMapID returns an unrelated sub-area name.
    -- g:MapAreaName() looks up Grail's mapAreaMapping table (uiMapID → localized zone
    -- name) which is built at startup from C_Map.GetMapInfo and is correct on all
    -- WoW version families.
    local zone
    local locs = g:QuestLocationsAccept(questID)
    if locs and locs[1] then
        local mapArea = locs[1].mapArea
        if mapArea then
            zone = g:MapAreaName(mapArea)
        end
    end

    return {
        title         = title,
        questLevel    = g:QuestLevel(questID),
        requiredLevel = g:QuestLevelRequired(questID),
        zone          = zone,
    }
end

-- Priority-ordered type detection. Returns the first matching AQL type string, or nil.
function GrailProvider:GetQuestType(questID)
    local g = _G["Grail"]
    if not g then return nil end
    if g:IsRaid(questID)    then return AQL.QuestType.Raid    end
    if g:IsDungeon(questID) then return AQL.QuestType.Dungeon end
    if g:IsEscort(questID)  then return AQL.QuestType.Escort  end
    if g:IsGroup(questID)   then return AQL.QuestType.Elite   end
    if g:IsPVP(questID)     then return AQL.QuestType.PvP     end
    if g:IsWeekly(questID)  then return AQL.QuestType.Weekly  end
    if g:IsDaily(questID)   then return AQL.QuestType.Daily   end
    return nil
end

-- Parse faction from Grail's raw questCodes string.
-- "FA" = Alliance, "FH" = Horde. Plain-text search; case-sensitive.
function GrailProvider:GetQuestFaction(questID)
    local g = _G["Grail"]
    if not g then return nil end
    local code = g.questCodes[questID]
    if not code then return nil end
    if strfind(code, "FA", 1, true) then return AQL.Faction.Alliance end
    if strfind(code, "FH", 1, true) then return AQL.Faction.Horde    end
    return nil
end

------------------------------------------------------------------------
-- Requirements capability
-- Parsing helpers: extract only plain-numeric tokens from prerequisite strings.
-- Letter-prefixed tokens (a=world quest, b=threat, P=profession, T=rep, etc.)
-- are not chain links and are skipped entirely.
------------------------------------------------------------------------

local function parsePlainNumericTokens(prereqStr)
    if not prereqStr or prereqStr == "" then return {} end
    local ids = {}
    for token in prereqStr:gmatch("[^,+]+") do
        token = token:match("^%s*(.-)%s*$")  -- trim whitespace
        if token:match("^%d+$") then
            ids[#ids + 1] = tonumber(token)
        end
        -- letter-prefixed tokens like "a12345", "P1", "T45" are silently skipped
    end
    return ids
end

-- Parse AND prereqs (tokens joined by "+"): all must be completed.
-- Returns a list of groups, where each group is an array of questIDs.
local function parseAndPrereqs(prereqStr)
    if not prereqStr or prereqStr == "" then return nil end
    local ids = {}
    for token in prereqStr:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$")
        -- An AND group is a token that contains "+" and only plain numerics.
        local allNumeric = true
        for part in token:gmatch("[^+]+") do
            part = part:match("^%s*(.-)%s*$")
            if not part:match("^%d+$") then allNumeric = false; break end
        end
        if allNumeric and token:find("+", 1, true) then
            local group = {}
            for part in token:gmatch("[^+]+") do
                group[#group + 1] = tonumber(part:match("^%s*(.-)%s*$"))
            end
            if #group > 0 then ids[#ids + 1] = group end
        end
    end
    return #ids > 0 and ids or nil
end

-- Parse OR prereqs (tokens joined by ","): any one satisfies the requirement.
-- Returns a flat list of questIDs (plain numerics only).
local function parseOrPrereqs(prereqStr)
    if not prereqStr or prereqStr == "" then return nil end
    local ids = {}
    for token in prereqStr:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$")
        if token:match("^%d+$") then
            ids[#ids + 1] = tonumber(token)
        end
    end
    return #ids > 0 and ids or nil
end

function GrailProvider:GetQuestRequirements(questID)
    local g = _G["Grail"]
    if not g then return nil end

    local prereqRaw = g.questPrerequisites[questID]
    local code = g.questCodes[questID]

    -- Exclusive quests: quests that are mutually exclusive with this one.
    -- Grail encodes these as "I:" codes in questCodes.
    local exclusiveTo = nil
    if code then
        local iCodes = {}
        for iVal in code:gmatch("I:(%d+)") do
            iCodes[#iCodes + 1] = tonumber(iVal)
        end
        if #iCodes > 0 then exclusiveTo = iCodes end
    end

    -- Breadcrumb: first "O:" code entry (optional follow-on quest).
    local breadcrumb = nil
    if code then
        local oVal = code:match("O:(%d+)")
        if oVal then breadcrumb = tonumber(oVal) end
    end

    local maxLevel = g.QuestLevelVariableMax and g:QuestLevelVariableMax(questID) or nil
    if maxLevel == 0 then maxLevel = nil end

    return {
        requiredLevel        = g:QuestLevelRequired(questID),
        requiredMaxLevel     = maxLevel,
        preQuestGroup        = parseAndPrereqs(prereqRaw),
        preQuestSingle       = parseOrPrereqs(prereqRaw),
        exclusiveTo          = exclusiveTo,
        breadcrumbForQuestId = breadcrumb,
        nextQuestInChain     = nil,  -- not derivable from prerequisites alone
        requiredRaces        = nil,  -- Grail uses letter codes; bitmask mapping deferred
        requiredClasses      = nil,  -- same
    }
end

------------------------------------------------------------------------
-- Chain capability
-- Reverse-map built once (lazy) on first GetChainInfo call.
-- reverseMap[prereqID] = { questID1, questID2, ... }
------------------------------------------------------------------------

local reverseMap      = {}
local reverseMapBuilt = false
local MAX_CHAIN_DEPTH = 50
local variantGroups    = {}   -- [canonicalID] = { id1, id2, ... }
local variantOf        = {}   -- [nonCanonicalID] = canonicalID
local variantChainCache = {}  -- [canonicalID] = { steps = ..., questCount = ... }; populated by buildVariantChain

local function buildReverseMap()
    if reverseMapBuilt then return end
    local g = _G["Grail"]
    if not g or not g.questPrerequisites then return end
    -- Do not lock as built if questPrerequisites is empty — Grail may not have
    -- finished populating it yet (race condition on PLAYER_LOGIN). A later call
    -- will retry once the table has data.
    if not next(g.questPrerequisites) then return end
    for questID, prereqStr in pairs(g.questPrerequisites) do
        -- Normalize questID to a number. Grail may use string or numeric keys
        -- depending on version; downstream code (g:QuestName, reverseMap lookups)
        -- expects numbers everywhere.
        local numQuestID = tonumber(questID) or questID
        for token in prereqStr:gmatch("[^,+]+") do
            token = token:match("^%s*(.-)%s*$")
            if token:match("^%d+$") then
                local prereqID = tonumber(token)
                if not reverseMap[prereqID] then reverseMap[prereqID] = {} end
                reverseMap[prereqID][#reverseMap[prereqID] + 1] = numQuestID
            end
        end
    end
    -- Second pass: detect variant root groups.
    -- Iterates reverseMap keys (questIDs that have successors) and groups
    -- root questIDs (no plain-numeric prerequisites) that share the same
    -- quest name AND accept zone. Canonical ID = smallest in each group.
    local rootsByNameZone = {}
    for questID in pairs(reverseMap) do
        local prereqStr     = g.questPrerequisites[questID] or g.questPrerequisites[tostring(questID)]
        local plainNumerics = parsePlainNumericTokens(prereqStr)
        if #plainNumerics == 0 then
            local name = g:QuestName(questID)
            if name then
                local zone = nil
                local locs = g:QuestLocationsAccept(questID)
                if locs and locs[1] and locs[1].mapArea then
                    zone = g:MapAreaName(locs[1].mapArea)
                end
                local key = name .. "\0" .. (zone or "")
                if not rootsByNameZone[key] then rootsByNameZone[key] = {} end
                rootsByNameZone[key][#rootsByNameZone[key] + 1] = questID
            end
        end
    end
    for _, group in pairs(rootsByNameZone) do
        if #group >= 2 then
            table.sort(group)
            local canonical = group[1]
            variantGroups[canonical] = group
            for i = 2, #group do
                variantOf[group[i]] = canonical
            end
        end
    end
    reverseMapBuilt = true
end

-- Walk backward from questID to find all root questIDs (quests with no plain-numeric prereqs).
-- Returns a list of root questIDs. A visited table prevents cycles.
local function findRoots(startQuestID)
    local g = _G["Grail"]
    local roots = {}
    local visited = {}

    local function walkBack(qid)
        if visited[qid] then return end
        visited[qid] = true
        local prereqStr = g.questPrerequisites[qid]
        if not prereqStr or prereqStr == "" then
            roots[#roots + 1] = qid
            return
        end
        local plainNumerics = parsePlainNumericTokens(prereqStr)
        if #plainNumerics == 0 then
            -- All prereqs are letter-prefixed (non-chain conditions): treat as root.
            roots[#roots + 1] = qid
            return
        end
        for _, prereqID in ipairs(plainNumerics) do
            walkBack(prereqID)
        end
    end

    walkBack(startQuestID)
    return roots
end

-- Compute the set of all questIDs reachable forward from startQuestID,
-- limited to MAX_CHAIN_DEPTH hops to avoid traversing the entire database.
local function forwardReachable(startQuestID)
    local reachable = {}
    local queue = { startQuestID }
    local depth = { [startQuestID] = 0 }
    local head = 1
    while head <= #queue do
        local qid = queue[head]
        head = head + 1
        if not reachable[qid] then
            reachable[qid] = true
            local d = depth[qid]
            if d < MAX_CHAIN_DEPTH then
                for _, s in ipairs(reverseMap[qid] or {}) do
                    if not depth[s] then
                        depth[s] = d + 1
                        queue[#queue + 1] = s
                    end
                end
            end
        end
    end
    return reachable
end

-- Determine groupType for a multi-successor step.
-- If all successors have mutual I: codes pointing at each other -> "branch".
-- Otherwise -> "parallel".
local function getGroupType(successors)
    local g = _G["Grail"]
    local exclusions = {}
    for _, sid in ipairs(successors) do
        local code = g.questCodes[sid]
        if code then
            local exSet = {}
            for iVal in code:gmatch("I:(%d+)") do
                exSet[tonumber(iVal)] = true
            end
            exclusions[sid] = exSet
        else
            exclusions[sid] = {}
        end
    end
    for i, sid in ipairs(successors) do
        for j, other in ipairs(successors) do
            if i ~= j then
                if not exclusions[sid][other] then
                    return "parallel"
                end
            end
        end
    end
    return "branch"
end

-- Classify step status for a questID given its position in the steps array.
local function classifyStatus(stepQuestID, stepIndex, steps)
    if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(stepQuestID) then
        return AQL.StepStatus.Completed
    end
    local q = AQL.QuestCache and AQL.QuestCache:Get(stepQuestID)
    if q then
        if q.isFailed   then return AQL.StepStatus.Failed   end
        if q.isComplete then return AQL.StepStatus.Finished end
        return AQL.StepStatus.Active
    end
    -- Not active, not in history: determine available/unavailable/unknown.
    if stepIndex == 1 then return AQL.StepStatus.Available end
    local prevStep = steps[stepIndex - 1]
    if not prevStep then return AQL.StepStatus.Unknown end
    -- Check if all quests in the previous step are completed.
    local prevIDs = {}
    if prevStep.questID then
        prevIDs[1] = prevStep.questID
    elseif prevStep.quests then
        for _, sq in ipairs(prevStep.quests) do prevIDs[#prevIDs + 1] = sq.questID end
    end
    for _, pid in ipairs(prevIDs) do
        if not (AQL.HistoryCache and AQL.HistoryCache:HasCompleted(pid)) then
            return AQL.StepStatus.Unavailable
        end
    end
    return AQL.StepStatus.Available
end

-- Returns true if all quests in the list share the same non-nil title per Grail.
-- Used to detect race/class variant steps: multiple questIDs for the same logical
-- quest stored as independent successors with no shared convergence point in Grail.
local function allSameTitle(questList)
    local g = _G["Grail"]
    local first = g:QuestName(questList[1])
    if not first then return false end
    for k = 2, #questList do
        if g:QuestName(questList[k]) ~= first then return false end
    end
    return true
end

-- Returns all unvisited successors across every quest in questList.
-- Marks each returned successor as visited.
local function collectSuccessors(questList, visited)
    local seen = {}
    local result = {}
    for _, qid in ipairs(questList) do
        for _, succ in ipairs(reverseMap[qid] or {}) do
            if not visited[succ] and not seen[succ] then
                seen[succ] = true
                visited[succ] = true
                result[#result + 1] = succ
            end
        end
    end
    return result
end

-- Build a single chain starting at rootQuestID using BFS forward walk.
-- Returns steps array and total questCount.
local function buildChainFromRoot(rootQuestID)
    local g = _G["Grail"]
    local steps = {}
    local visited = {}
    local questCount = 0

    local currentWave = { rootQuestID }
    visited[rootQuestID] = true

    while #currentWave > 0 and #steps < MAX_CHAIN_DEPTH do
        if #currentWave == 1 then
            local qid = currentWave[1]
            local title = g:QuestName(qid) or ("Quest " .. qid)
            steps[#steps + 1] = {
                questID = qid,
                title   = title,
                status  = AQL.StepStatus.Unknown,  -- annotated after full walk
            }
            questCount = questCount + 1

            local successors = reverseMap[qid] or {}
            if #successors == 0 then break end

            -- Filter already-visited successors (cycle guard).
            local nextWave = {}
            for _, s in ipairs(successors) do
                if not visited[s] then
                    visited[s] = true
                    nextWave[#nextWave + 1] = s
                end
            end
            if #nextWave == 0 then break end

            if #nextWave == 1 then
                currentWave = nextWave
            else
                -- Multiple successors: check if they reconverge downstream.
                local sets = {}
                for _, s in ipairs(nextWave) do
                    sets[s] = forwardReachable(s)
                end

                local converge = false
                for i = 1, #nextWave do
                    for j = i + 1, #nextWave do
                        for qid2 in pairs(sets[nextWave[i]]) do
                            if sets[nextWave[j]][qid2] then
                                converge = true
                                break
                            end
                        end
                        if converge then break end
                    end
                    if converge then break end
                end

                if converge then
                    -- Successors branch and reconverge: group as one step.
                    local groupType = getGroupType(nextWave)
                    local subQuests = {}
                    for _, s in ipairs(nextWave) do
                        subQuests[#subQuests + 1] = {
                            questID = s,
                            title   = g:QuestName(s) or ("Quest " .. s),
                            status  = AQL.StepStatus.Unknown,
                        }
                        questCount = questCount + 1
                    end
                    steps[#steps + 1] = { quests = subQuests, groupType = groupType }

                    -- Find the convergence point (reachable from all nextWave members).
                    local unionSuccessors = {}
                    for _, s in ipairs(nextWave) do
                        for _, ns in ipairs(reverseMap[s] or {}) do
                            if not visited[ns] then
                                local reachableFromAll = true
                                for _, other in ipairs(nextWave) do
                                    if other ~= s and not sets[other][ns] then
                                        reachableFromAll = false; break
                                    end
                                end
                                if reachableFromAll then
                                    visited[ns] = true
                                    unionSuccessors[ns] = true
                                end
                            end
                        end
                    end
                    currentWave = {}
                    for ns in pairs(unionSuccessors) do currentWave[#currentWave + 1] = ns end
                else
                    -- Not a convergent branch. Check if these are same-title race/class
                    -- variants (Retail pattern: one logical quest, many questIDs).
                    if allSameTitle(nextWave) then
                        local subQuests = {}
                        for _, s in ipairs(nextWave) do
                            subQuests[#subQuests + 1] = {
                                questID = s,
                                title   = g:QuestName(s) or ("Quest " .. s),
                                status  = AQL.StepStatus.Unknown,
                            }
                            questCount = questCount + 1
                        end
                        steps[#steps + 1] = { quests = subQuests, groupType = "parallel" }
                        currentWave = collectSuccessors(nextWave, visited)
                        if #currentWave == 0 then break end
                    else
                        break  -- genuinely divergent paths; end chain here
                    end
                end
            end
        else
            -- Multi-node wave: nodes that followed from a previous convergence result.
            -- These have not yet been added as steps. Check if they reconverge.
            local sets = {}
            for _, s in ipairs(currentWave) do
                sets[s] = forwardReachable(s)
            end
            local converge = false
            for i = 1, #currentWave do
                for j = i + 1, #currentWave do
                    for rqid in pairs(sets[currentWave[i]]) do
                        if sets[currentWave[j]][rqid] then converge = true; break end
                    end
                    if converge then break end
                end
                if converge then break end
            end
            if converge then
                local groupType = getGroupType(currentWave)
                local subQuests = {}
                for _, s in ipairs(currentWave) do
                    subQuests[#subQuests + 1] = {
                        questID = s,
                        title   = g:QuestName(s) or ("Quest " .. s),
                        status  = AQL.StepStatus.Unknown,
                    }
                    questCount = questCount + 1
                end
                steps[#steps + 1] = { quests = subQuests, groupType = groupType }
                local unionSuccessors = {}
                for _, s in ipairs(currentWave) do
                    for _, ns in ipairs(reverseMap[s] or {}) do
                        if not visited[ns] then
                            local reachableFromAll = true
                            for _, other in ipairs(currentWave) do
                                if other ~= s and not sets[other][ns] then
                                    reachableFromAll = false; break
                                end
                            end
                            if reachableFromAll then
                                visited[ns] = true
                                unionSuccessors[ns] = true
                            end
                        end
                    end
                end
                currentWave = {}
                for ns in pairs(unionSuccessors) do currentWave[#currentWave + 1] = ns end
            else
                -- Not a convergent branch. Check if these are same-title race/class
                -- variants (Retail pattern: one logical quest, many questIDs).
                if allSameTitle(currentWave) then
                    local subQuests = {}
                    for _, s in ipairs(currentWave) do
                        subQuests[#subQuests + 1] = {
                            questID = s,
                            title   = g:QuestName(s) or ("Quest " .. s),
                            status  = AQL.StepStatus.Unknown,
                        }
                        questCount = questCount + 1
                    end
                    steps[#steps + 1] = { quests = subQuests, groupType = "parallel" }
                    currentWave = collectSuccessors(currentWave, visited)
                    if #currentWave == 0 then break end
                else
                    break  -- genuinely divergent paths; end chain here
                end
            end
        end
    end

    return steps, questCount
end

function GrailProvider:GetChainInfo(questID)
    local g = _G["Grail"]
    if not g then return { knownStatus = AQL.ChainStatus.Unknown } end

    -- Lazy build of the reverse map on first call.
    buildReverseMap()

    -- A quest is in the chain graph if it has prerequisites OR successors.
    local hasPrereqs = g.questPrerequisites[questID] and g.questPrerequisites[questID] ~= ""
    local hasSuccessors = reverseMap[questID] and #reverseMap[questID] > 0
    if not hasPrereqs and not hasSuccessors then
        -- Before giving up, search the reverseMap for a same-title questID that IS
        -- in the chain graph (has known successors). This handles Retail race/class
        -- variant quests where Grail only recorded one questID per step (e.g. 28763
        -- vs 28766 for "Beating Them Back!" — only 28766 appears in questPrerequisites
        -- as a predecessor of 28774, so 28763 has no graph edges). We search reverseMap
        -- keys (always numbers, always "quests with successors") for a matching title,
        -- then build and return the chain for that canonical questID. This avoids any
        -- timing dependency on QuestCache state.
        local title = g:QuestName(questID)
        if title then
            local canonical = nil
            for altID in pairs(reverseMap) do
                if altID ~= questID and g:QuestName(altID) == title then
                    canonical = altID
                    break
                end
            end
            if canonical then
                local roots = findRoots(canonical)
                if #roots > 0 then
                    local chains = {}
                    local seenRoots = {}
                    for _, root in ipairs(roots) do
                        if not seenRoots[root] then
                            seenRoots[root] = true
                            local steps, questCount = buildChainFromRoot(root)
                            if #steps >= 2 then
                                local stepNum = nil
                                for i, step in ipairs(steps) do
                                    if step.questID == canonical then
                                        stepNum = i; break
                                    elseif step.quests then
                                        for _, sq in ipairs(step.quests) do
                                            if sq.questID == canonical then stepNum = i; break end
                                        end
                                        if stepNum then break end
                                    end
                                end
                                if stepNum then
                                    for i, step in ipairs(steps) do
                                        if step.questID then
                                            step.status = classifyStatus(step.questID, i, steps)
                                        elseif step.quests then
                                            for _, sq in ipairs(step.quests) do
                                                sq.status = classifyStatus(sq.questID, i, steps)
                                            end
                                        end
                                    end
                                    chains[#chains + 1] = {
                                        chainID    = root,
                                        step       = stepNum,
                                        length     = #steps,
                                        questCount = questCount,
                                        steps      = steps,
                                        provider   = AQL.Provider.Grail,
                                    }
                                end
                            end
                        end
                    end
                    if #chains > 0 then
                        return { knownStatus = AQL.ChainStatus.Known, chains = chains }
                    end
                end
            end
        end
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    -- Find all root quests by walking backward.
    local roots = findRoots(questID)
    if #roots == 0 then
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    -- Build a chain from each root. Only keep chains that contain questID.
    local chains = {}
    local seenRoots = {}
    for _, root in ipairs(roots) do
        if not seenRoots[root] then
            seenRoots[root] = true
            local steps, questCount = buildChainFromRoot(root)
            if #steps >= 2 then
                -- Find the step index for questID.
                local stepNum = nil
                for i, step in ipairs(steps) do
                    if step.questID == questID then
                        stepNum = i; break
                    elseif step.quests then
                        for _, sq in ipairs(step.quests) do
                            if sq.questID == questID then stepNum = i; break end
                        end
                        if stepNum then break end
                    end
                end

                if stepNum then
                    -- Annotate step statuses with full steps array context.
                    for i, step in ipairs(steps) do
                        if step.questID then
                            step.status = classifyStatus(step.questID, i, steps)
                        elseif step.quests then
                            for _, sq in ipairs(step.quests) do
                                sq.status = classifyStatus(sq.questID, i, steps)
                            end
                        end
                    end

                    chains[#chains + 1] = {
                        chainID    = root,
                        step       = stepNum,
                        length     = #steps,
                        questCount = questCount,
                        steps      = steps,
                        provider   = AQL.Provider.Grail,
                    }
                end
            end
        end
    end

    if #chains == 0 then
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    return {
        knownStatus = AQL.ChainStatus.Known,
        chains      = chains,
    }
end

AQL.GrailProvider = GrailProvider
