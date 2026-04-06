# Grail Variant Chain — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix GrailProvider so Retail WoW quest chains with per-class variant questIDs produce one unified chain with the correct length, and update AQL's public `GetChainInfo` so remote (uncached) quest IDs also resolve correctly.

**Architecture:** Variant root groups are detected at reverse-map build time using a second pass over the roots in `reverseMap`. Chain building walks all variant members simultaneously at each step, using a majority-vote filter to discard side-branch successors. `AQL:GetChainInfo` gains a provider-fallthrough tier. `SocialQuestTabUtils.GetChainInfoForQuestID` is removed; call sites replaced with `AQL:GetChainInfo`. Both tab dedup strategies (PartyTab, SharedTab) are upgraded from title+zone matching to step-number keying.

**Tech Stack:** Lua 5.1 (WoW addon environment), LibStub, AQL public API, Grail addon data. Unit tests: plain `lua` interpreter with mock globals.

---

## File Structure

| File | Change |
|---|---|
| `Providers/GrailProvider.lua` | Add 3 module-level tables; second pass in `buildReverseMap`; new `findStepForQuestID` + `buildVariantChain` helpers; rewrite `GetChainInfo` |
| `AbsoluteQuestLog.lua` | Rewrite `AQL:GetChainInfo` with provider-fallthrough tier |
| `AbsoluteQuestLog.toc` | Version bump |
| `CLAUDE.md` (AQL) | Add version history entry |
| `changelog.txt` (AQL) | Add version entry |
| `tests/GrailProvider_test.lua` | New unit test file (AQL repo, no prior test dir) |
| `UI/TabUtils.lua` (SocialQuest) | Remove `GetChainInfoForQuestID` |
| `UI/Tabs/PartyTab.lua` (SocialQuest) | Update `ci` resolution; step-number dedup |
| `UI/Tabs/SharedTab.lua` (SocialQuest) | Update `ci` resolution; step-number dedup |
| `SocialQuest.toc` | Version bump |
| `CLAUDE.md` (SocialQuest) | Add version history entry |

---

## Versioning Note

Current AQL: 3.2.4 — Current SocialQuest: 2.17.8 (both from April 2026).
Per the versioning rule: the **first** code change on a given calendar day increments the minor and resets the revision; subsequent same-day changes increment the revision only.
If 3.2.4 and 2.17.8 were made on a previous day → new versions are **AQL 3.3.0** and **SQ 2.18.0**.
If they were made today (2026-04-02) → new versions are **AQL 3.2.5** and **SQ 2.17.9**.
Check git log dates and apply the correct version before committing.

---

## Task 1: Variant Group Detection — `buildReverseMap` Second Pass

**Files:**
- Create: `tests/GrailProvider_test.lua`
- Modify: `Providers/GrailProvider.lua:210-237`

### Background

`buildReverseMap` currently builds `reverseMap[prereqID] = {successorIDs}` from `g.questPrerequisites` and returns. We add three module-level tables and a second pass that groups all root questIDs that share the same quest name AND zone into variant groups.

A questID is a **root** if `parsePlainNumericTokens(g.questPrerequisites[questID])` returns an empty table (no plain-numeric chain prerequisites). We only check questIDs that ARE in `reverseMap` (i.e., quests that have at least one successor — guarantees they're part of a chain).

- [ ] **Step 1: Write the failing test**

Create `tests/GrailProvider_test.lua` with this content:

```lua
-- tests/GrailProvider_test.lua
-- Run from repo root: lua tests/GrailProvider_test.lua
-- Tests GrailProvider variant chain logic with a mock Grail + AQL environment.

local failures = 0
local function check(label, cond)
    if not cond then
        print("FAIL: " .. label)
        failures = failures + 1
    else
        print("pass: " .. label)
    end
end

------------------------------------------------------------------------
-- Minimal WoW global stubs
------------------------------------------------------------------------
_G = _G or {}

-- LibStub mock: returns the AQL table when queried.
local aql = {
    ChainStatus = { Known="known", Unknown="unknown", NotAChain="not_a_chain" },
    StepStatus  = { Unknown="unknown", Active="active", Completed="completed",
                    Finished="finished", Failed="failed",
                    Available="available", Unavailable="unavailable" },
    Provider    = { Grail="Grail" },
    Capability  = { Chain="Chain", QuestInfo="QuestInfo", Requirements="Requirements" },
    HistoryCache = nil,
    QuestCache   = nil,
}
function LibStub(name, silent)
    if name == "AbsoluteQuestLog-1.0" then return aql end
    return nil
end
_G["LibStub"] = LibStub

------------------------------------------------------------------------
-- Mock Grail data:
--   3 variant roots (101, 102, 103) → "Beating Them Back!" in "Dun Morogh"
--   Each root → 1 step-2 variant (201/202/203 "Lions for Lambs" same zone)
--                + 1 letter-quest side branch (901/902/903 different name/zone)
--   All step-2 variants → 1 step-3 quest (301 "Join the Battle!" same zone)
--   Non-variant chain: 500 → 501 (simple 2-step, no variants)
------------------------------------------------------------------------
local questNames = {
    [101]="Beating Them Back!", [102]="Beating Them Back!", [103]="Beating Them Back!",
    [201]="Lions for Lambs",    [202]="Lions for Lambs",    [203]="Lions for Lambs",
    [301]="Join the Battle!",
    [901]="Simple Letter",      [902]="Glyphic Letter",     [903]="Embossed Letter",
    [500]="The First Step",
    [501]="The Second Step",
}
local questMapAreas = {
    [101]=1, [102]=1, [103]=1,
    [201]=1, [202]=1, [203]=1,
    [301]=1,
    [901]=2, [902]=2, [903]=2,  -- different zone → fail majority vote
    [500]=3, [501]=3,
}
local mapAreaNames = { [1]="Dun Morogh", [2]="Elwynn Forest", [3]="Westfall" }

_G["Grail"] = {
    -- questPrerequisites: keys = quests that HAVE prerequisites.
    -- Values are comma-separated prereq questIDs.
    questPrerequisites = {
        [201]="101", [202]="102", [203]="103",
        [301]="201,202,203",
        [901]="101", [902]="102", [903]="103",
        [501]="500",
    },
    questCodes = {},
    QuestName = function(self, id) return questNames[id] end,
    MapAreaName = function(self, mapArea) return mapAreaNames[mapArea] end,
    QuestLocationsAccept = function(self, id)
        local z = questMapAreas[id]
        if z then return {{ mapArea = z }} else return {} end
    end,
    QuestLevelRequired = function(self, id) return 1 end,
    QuestLevelVariableMax = nil,
}

------------------------------------------------------------------------
-- Load GrailProvider (sets aql.GrailProvider at the bottom of the file).
------------------------------------------------------------------------
dofile("Providers/GrailProvider.lua")
local GP = aql.GrailProvider

------------------------------------------------------------------------
-- Task 1 tests: variant group detection via GetChainInfo results.
-- After Task 1, these checks confirm the groups are built correctly
-- (same chainID returned for all variants of the same root group).
------------------------------------------------------------------------
local r101 = GP:GetChainInfo(101)
local r102 = GP:GetChainInfo(102)
local r103 = GP:GetChainInfo(103)

check("101 known",             r101.knownStatus == "known")
check("102 known",             r102.knownStatus == "known")
check("103 known",             r103.knownStatus == "known")
check("101 chainID is 101",    r101.chains and r101.chains[1].chainID == 101)
check("102 chainID is 101",    r102.chains and r102.chains[1].chainID == 101)
check("103 chainID is 101",    r103.chains and r103.chains[1].chainID == 101)

------------------------------------------------------------------------
-- Task 2 tests: buildVariantChain produces correct step count + structure.
------------------------------------------------------------------------
check("101 length=3",          r101.chains and r101.chains[1].length == 3)
check("102 length=3",          r102.chains and r102.chains[1].length == 3)
check("step1 is group",        r101.chains and r101.chains[1].steps[1].quests ~= nil)
check("step1 has 3 variants",  r101.chains and r101.chains[1].steps[1].quests ~= nil
                                and #r101.chains[1].steps[1].quests == 3)
check("step2 is group",        r101.chains and r101.chains[1].steps[2].quests ~= nil)
check("step2 has 3 variants",  r101.chains and #r101.chains[1].steps[2].quests == 3)
check("step3 is single quest", r101.chains and r101.chains[1].steps[3].questID ~= nil)
check("step3 questID is 301",  r101.chains and r101.chains[1].steps[3].questID == 301)

-- Majority-vote filter: side branch letter quests must NOT appear in step2.
if r101.chains and r101.chains[1].steps[2].quests then
    local step2IDs = {}
    for _, sq in ipairs(r101.chains[1].steps[2].quests) do
        step2IDs[sq.questID] = true
    end
    check("901 not in step2 (majority vote)", not step2IDs[901])
    check("902 not in step2 (majority vote)", not step2IDs[902])
    check("903 not in step2 (majority vote)", not step2IDs[903])
    check("201 in step2",                     step2IDs[201])
    check("202 in step2",                     step2IDs[202])
    check("203 in step2",                     step2IDs[203])
else
    check("step2 quests accessible", false)
end

------------------------------------------------------------------------
-- Task 3 tests: GetChainInfo step detection for mid-chain + convergence.
------------------------------------------------------------------------
local r201 = GP:GetChainInfo(201)
local r301 = GP:GetChainInfo(301)
local r901 = GP:GetChainInfo(901)

check("201 known",             r201.knownStatus == "known")
check("201 chainID is 101",    r201.chains and r201.chains[1].chainID == 101)
check("201 step is 2",         r201.chains and r201.chains[1].step == 2)
check("301 known",             r301.knownStatus == "known")
check("301 chainID is 101",    r301.chains and r301.chains[1].chainID == 101)
check("301 step is 3",         r301.chains and r301.chains[1].step == 3)
check("901 not a chain",       r901.knownStatus == "not_a_chain")

-- Non-variant chain: 500 → 501 (no variants; falls through to buildChainFromRoot).
local r500 = GP:GetChainInfo(500)
local r501 = GP:GetChainInfo(501)
check("500 known",             r500.knownStatus == "known")
check("500 chainID is 500",    r500.chains and r500.chains[1].chainID == 500)
check("500 step is 1",         r500.chains and r500.chains[1].step == 1)
check("500 length is 2",       r500.chains and r500.chains[1].length == 2)
check("501 known",             r501.knownStatus == "known")
check("501 chainID is 500",    r501.chains and r501.chains[1].chainID == 500)
check("501 step is 2",         r501.chains and r501.chains[1].step == 2)

------------------------------------------------------------------------
print(string.rep("-", 50))
if failures == 0 then
    print("All tests passed.")
else
    print(failures .. " test(s) FAILED.")
    os.exit(1)
end
```

- [ ] **Step 2: Run to verify it fails (GrailProvider.lua not yet modified)**

```
cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
lua tests/GrailProvider_test.lua
```

Expected: Many FAILs — `101 chainID is 101` fails because old code returns chainID=101 for 101 and chainID=102 for 102 (different roots). `101 length=3` fails because old code stops at step 2.

- [ ] **Step 3: Add 3 new module-level tables to GrailProvider.lua**

In `Providers/GrailProvider.lua`, after line 212 (`local MAX_CHAIN_DEPTH = 50`), insert:

```lua
local variantGroups    = {}   -- [canonicalID] = { id1, id2, ... }
local variantOf        = {}   -- [nonCanonicalID] = canonicalID
local variantChainCache = {}  -- [canonicalID] = { steps = ..., questCount = ... }
```

- [ ] **Step 4: Add second pass to `buildReverseMap`**

In `Providers/GrailProvider.lua`, insert the second pass block between the end of the `pairs(g.questPrerequisites)` loop (line 235, the closing `end`) and `reverseMapBuilt = true` (line 236):

```lua
    -- Second pass: detect variant root groups.
    -- Iterates reverseMap keys (questIDs that have successors) and groups
    -- root questIDs (no plain-numeric prerequisites) that share the same
    -- quest name AND accept zone. Canonical ID = smallest in each group.
    local rootsByNameZone = {}
    for questID in pairs(reverseMap) do
        local prereqStr     = g.questPrerequisites[questID]
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
```

- [ ] **Step 5: Run tests — expect some to pass, some to still fail**

```
lua tests/GrailProvider_test.lua
```

Expected result at this stage:
- `101 known` → still FAIL (GetChainInfo not yet updated to use variantGroups)
- All other tests still fail

This confirms variant group detection was not yet wired into GetChainInfo (as expected — that happens in Task 3). Task 1 only adds the data structures. The tests will fully pass after Task 3.

- [ ] **Step 6: Commit**

```bash
cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
git add tests/GrailProvider_test.lua Providers/GrailProvider.lua
git commit -m "$(cat <<'EOF'
feat: variant group detection in buildReverseMap second pass

Add variantGroups/variantOf/variantChainCache module tables.
buildReverseMap second pass groups root questIDs by name+zone.
Canonical ID is the smallest in each group.
Test harness created at tests/GrailProvider_test.lua.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `buildVariantChain` with Majority-Vote Filter

**Files:**
- Modify: `Providers/GrailProvider.lua` — add `findStepForQuestID` and `buildVariantChain` before `GetChainInfo`

### Background

`buildVariantChain(canonicalID)` replaces `buildChainFromRoot` for variant chains. It walks all variant members simultaneously (one "wave" per step), collecting successors and grouping them by (name, zone). The majority-vote filter (`count > waveSize / 2`) keeps only the true chain continuation and discards side-branch letter quests.

**Deduplication note:** When all N wave members share a single successor quest (convergence point), that quest appears N times in the candidate list. This passes the vote (`N > N/2`). After selecting the winning group, deduplicate the IDs so the next wave contains the quest only once.

Status annotation is intentionally NOT done inside `buildVariantChain` — `GetChainInfo` annotates in-place before every return so statuses always reflect current HistoryCache/QuestCache state.

- [ ] **Step 1: Add `findStepForQuestID` helper before `GetChainInfo` in GrailProvider.lua**

Insert immediately before `function GrailProvider:GetChainInfo(questID)` (currently line 572):

```lua
-- Returns the 1-based step index of questID in the given steps array, or nil.
local function findStepForQuestID(questID, steps)
    for i, step in ipairs(steps) do
        if step.questID == questID then return i end
        if step.quests then
            for _, sq in ipairs(step.quests) do
                if sq.questID == questID then return i end
            end
        end
    end
    return nil
end
```

- [ ] **Step 2: Add `buildVariantChain` function after `findStepForQuestID`**

Insert immediately after `findStepForQuestID` and before `function GrailProvider:GetChainInfo`:

```lua
-- buildVariantChain: walks all variant roots simultaneously (one wave per step),
-- majority-votes successors to discard side-branch quests, and returns the
-- steps array + questCount. Results are cached by canonicalID.
-- Status annotation is left to GetChainInfo so it stays fresh on every call.
local function buildVariantChain(canonicalID)
    if variantChainCache[canonicalID] then
        local c = variantChainCache[canonicalID]
        return c.steps, c.questCount
    end

    local g          = _G["Grail"]
    local steps      = {}
    local questCount = 0
    local visited    = {}
    local currentWave = {}
    for _, id in ipairs(variantGroups[canonicalID]) do
        currentWave[#currentWave + 1] = id
        visited[id] = true
    end

    while #currentWave > 0 and #steps < MAX_CHAIN_DEPTH do
        -- Record current wave as one step.
        if #currentWave == 1 then
            local qid = currentWave[1]
            steps[#steps + 1] = {
                questID = qid,
                title   = g:QuestName(qid) or ("Quest " .. qid),
                status  = AQL.StepStatus.Unknown,
            }
            questCount = questCount + 1
        else
            local subQuests = {}
            for _, qid in ipairs(currentWave) do
                subQuests[#subQuests + 1] = {
                    questID = qid,
                    title   = g:QuestName(qid) or ("Quest " .. qid),
                    status  = AQL.StepStatus.Unknown,
                }
                questCount = questCount + 1
            end
            steps[#steps + 1] = { quests = subQuests, groupType = "parallel" }
        end

        -- Collect successors grouped by (name, zone).
        -- Allow duplicate IDs so that a convergence-point quest appearing in
        -- multiple wave members counts as multiple votes toward the majority.
        local candidatesByKey = {}
        for _, qid in ipairs(currentWave) do
            for _, succ in ipairs(reverseMap[qid] or {}) do
                if not visited[succ] then
                    local name = g:QuestName(succ)
                    if name then
                        local zone = nil
                        local locs = g:QuestLocationsAccept(succ)
                        if locs and locs[1] and locs[1].mapArea then
                            zone = g:MapAreaName(locs[1].mapArea)
                        end
                        local key = name .. "\0" .. (zone or "")
                        if not candidatesByKey[key] then
                            candidatesByKey[key] = { ids = {} }
                        end
                        local ids = candidatesByKey[key].ids
                        ids[#ids + 1] = succ
                    end
                end
            end
        end

        -- Majority vote: keep only the group with count > waveSize / 2.
        local waveSize  = #currentWave
        local nextWave  = nil
        local bestCount = 0
        for _, group in pairs(candidatesByKey) do
            if #group.ids > waveSize / 2 and #group.ids > bestCount then
                bestCount = #group.ids
                nextWave  = group.ids
            end
        end
        if not nextWave or #nextWave == 0 then break end

        -- Deduplicate: a convergence-point quest appears once per wave member.
        local seen    = {}
        local deduped = {}
        for _, id in ipairs(nextWave) do
            if not seen[id] then
                seen[id] = true
                deduped[#deduped + 1] = id
            end
        end
        nextWave = deduped

        for _, id in ipairs(nextWave) do visited[id] = true end
        currentWave = nextWave
    end

    variantChainCache[canonicalID] = { steps = steps, questCount = questCount }
    return steps, questCount
end
```

- [ ] **Step 3: Run tests — expect more passes but Task 3 tests still fail**

```
lua tests/GrailProvider_test.lua
```

Expected: Task 1 and Task 2 structural tests (chainID, length, step count, group structure, majority vote) still fail because GetChainInfo hasn't been wired yet to call buildVariantChain. All tests will pass after Task 3.

- [ ] **Step 4: Commit**

```bash
git add Providers/GrailProvider.lua
git commit -m "$(cat <<'EOF'
feat: buildVariantChain with majority-vote side-branch filter

findStepForQuestID helper locates a questID in a steps array.
buildVariantChain walks all variant roots simultaneously, groups
successors by (name, zone), and discards groups that fail the
majority vote (count <= waveSize/2). Convergence-point quests
that appear in multiple wave members vote correctly and are
deduplicated after selection. Results cached by canonicalID.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Rewrite `GetChainInfo` to Use Variant Chains

**Files:**
- Modify: `Providers/GrailProvider.lua:572-712` — replace entire `GetChainInfo` body

### Background

The new `GetChainInfo` has three paths:

1. **Fast path — variant root:** `variantOf[questID]` or `variantGroups[questID]` is set → call `buildVariantChain(canonical)` and find the step.

2. **No-graph-edges fallback:** questID has neither prereqs nor successors → search reverseMap for a same-title quest that IS a variant root, use its chain.

3. **Mid-chain / non-variant:** has prereqs or successors → `findRoots` as before. If the root is a variant canonical, use `buildVariantChain`; otherwise use `buildChainFromRoot`.

In ALL paths, annotate step statuses in-place before returning.

- [ ] **Step 1: Replace the `GetChainInfo` body**

Replace the entire function body of `GrailProvider:GetChainInfo` (currently lines 572–712, everything from `function GrailProvider:GetChainInfo(questID)` through the final `end` before `AQL.GrailProvider = GrailProvider`):

```lua
function GrailProvider:GetChainInfo(questID)
    local g = _G["Grail"]
    if not g then return { knownStatus = AQL.ChainStatus.Unknown } end
    buildReverseMap()

    -- Helper: annotate step statuses in-place using current HistoryCache/QuestCache.
    local function annotateSteps(steps)
        for i, step in ipairs(steps) do
            if step.questID then
                step.status = classifyStatus(step.questID, i, steps)
            elseif step.quests then
                for _, sq in ipairs(step.quests) do
                    sq.status = classifyStatus(sq.questID, i, steps)
                end
            end
        end
    end

    -- Path 1: variant root (canonical or non-canonical).
    local canonical = variantOf[questID] or (variantGroups[questID] and questID)
    if canonical then
        local steps, questCount = buildVariantChain(canonical)
        if #steps >= 2 then
            local stepNum = findStepForQuestID(questID, steps)
            if stepNum then
                annotateSteps(steps)
                return {
                    knownStatus = AQL.ChainStatus.Known,
                    chains = {{
                        chainID    = canonical,
                        step       = stepNum,
                        length     = #steps,
                        questCount = questCount,
                        steps      = steps,
                        provider   = AQL.Provider.Grail,
                    }}
                }
            end
        end
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    -- Path 2: questID has no graph edges — search for a same-title variant root.
    local hasPrereqs    = g.questPrerequisites[questID] and g.questPrerequisites[questID] ~= ""
    local hasSuccessors = reverseMap[questID] and #reverseMap[questID] > 0
    if not hasPrereqs and not hasSuccessors then
        local title = g:QuestName(questID)
        if title then
            for altID in pairs(reverseMap) do
                if altID ~= questID and g:QuestName(altID) == title then
                    local altCanonical = variantOf[altID] or (variantGroups[altID] and altID)
                    if altCanonical then
                        local steps, questCount = buildVariantChain(altCanonical)
                        if #steps >= 2 then
                            local stepNum = findStepForQuestID(altID, steps)
                            if stepNum then
                                annotateSteps(steps)
                                return {
                                    knownStatus = AQL.ChainStatus.Known,
                                    chains = {{
                                        chainID    = altCanonical,
                                        step       = stepNum,
                                        length     = #steps,
                                        questCount = questCount,
                                        steps      = steps,
                                        provider   = AQL.Provider.Grail,
                                    }}
                                }
                            end
                        end
                    end
                end
            end
        end
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    -- Path 3: mid-chain or non-variant — walk back to roots.
    local roots = findRoots(questID)
    if #roots == 0 then return { knownStatus = AQL.ChainStatus.NotAChain } end

    local chains    = {}
    local seenRoots = {}
    for _, root in ipairs(roots) do
        if not seenRoots[root] then
            seenRoots[root] = true
            local rootCanonical = variantOf[root] or (variantGroups[root] and root)
            local steps, questCount
            if rootCanonical then
                steps, questCount = buildVariantChain(rootCanonical)
            else
                steps, questCount = buildChainFromRoot(root)
            end
            if #steps >= 2 then
                local stepNum = findStepForQuestID(questID, steps)
                if stepNum then
                    annotateSteps(steps)
                    chains[#chains + 1] = {
                        chainID    = rootCanonical or root,
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

    if #chains == 0 then return { knownStatus = AQL.ChainStatus.NotAChain } end
    return { knownStatus = AQL.ChainStatus.Known, chains = chains }
end
```

- [ ] **Step 2: Run tests — all should pass**

```
lua tests/GrailProvider_test.lua
```

Expected: `All tests passed.` with 0 failures.

- [ ] **Step 3: Commit**

```bash
git add Providers/GrailProvider.lua
git commit -m "$(cat <<'EOF'
feat: GetChainInfo wired to buildVariantChain for variant roots

Three-path GetChainInfo: (1) variant root fast path via
variantOf/variantGroups; (2) no-graph-edges fallback via same-title
reverseMap search; (3) mid-chain/non-variant via findRoots as before.
Path 3 uses buildVariantChain when the root is a variant canonical.
All paths annotate step statuses before returning.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: AQL `GetChainInfo` Provider Fallthrough + Version Bump

**Files:**
- Modify: `AbsoluteQuestLog.lua:255-261`
- Modify: `AbsoluteQuestLog.toc` — version bump
- Modify: `CLAUDE.md` — add version history entry
- Modify: `changelog.txt` — add version entry

### Background

`AQL:GetChainInfo` currently reads QuestCache only. Remote party member questIDs are never in the local cache → always returns Unknown. The fix: if the cache has no Known result, query the Chain provider directly (wrapped in `pcall`).

This is the same pattern EventEngine uses for provider calls. The provider's result is used only when the cache has no Known answer — it is NOT written back to the cache (cache is updated only via EventEngine rebuild cycles).

- [ ] **Step 1: Replace `AQL:GetChainInfo` in AbsoluteQuestLog.lua**

Replace lines 255–261 (the current `GetChainInfo` implementation):

```lua
-- Current (to be replaced):
function AQL:GetChainInfo(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.chainInfo then
        return q.chainInfo
    end
    return { knownStatus = AQL.ChainStatus.Unknown }
end
```

With:

```lua
-- GetChainInfo(questID) → ChainInfo wrapper
-- Tier 1: QuestCache (fast, session-local). Tier 2: Chain provider fallthrough
-- for remote/uncached questIDs (e.g. party member's variant quest not in local log).
function AQL:GetChainInfo(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.chainInfo and q.chainInfo.knownStatus == self.ChainStatus.Known then
        return q.chainInfo
    end
    local provider = self.providers and self.providers[self.Capability.Chain]
    if provider then
        local ok, result = pcall(provider.GetChainInfo, provider, questID)
        if ok and result and result.knownStatus == self.ChainStatus.Known then
            return result
        end
    end
    return (q and q.chainInfo) or { knownStatus = self.ChainStatus.Unknown }
end
```

- [ ] **Step 2: Bump version in AbsoluteQuestLog.toc**

Change the `## Version:` line to the correct new version per the versioning rule (see Versioning Note at top of plan — either `3.3.0` or `3.2.5`).

- [ ] **Step 3: Add version history entry to CLAUDE.md**

Add at the top of the Version History section:

```markdown
### Version X.X.X (April 2026)
- Feature (Retail): `AQL:GetChainInfo` now has a two-tier resolution strategy. Tier 1: reads QuestCache (unchanged — fast path for local player's quests with Known status). Tier 2: calls the Chain provider directly (pcall-guarded) when the cache has no Known result. This allows remote party member quest IDs — which are never in the local quest cache — to resolve to their correct chain via GrailProvider's variant chain logic. The provider result is used for the return value but not written back to cache; cache is updated only by EventEngine rebuild cycles.
- Feature (Retail): GrailProvider now correctly builds unified chains for Retail WoW quests where each step has multiple per-class/race variant questIDs. New `buildVariantChain` function walks all variant roots simultaneously, groups successors by (name+zone), and uses a majority-vote filter (`count > waveSize/2`) to discard class-specific letter-quest side branches that previously caused chain traversal to stop at step 2. Produces the correct 5-step chain (or N-step chain for any variant pattern) instead of stopping early.
- Feature (Retail): `buildReverseMap` now runs a second pass after the prerequisite graph is built. Root questIDs (no plain-numeric prerequisites) that share the same quest name AND accept zone are grouped into `variantGroups[canonicalID]` (canonicalID = smallest in group). Non-canonical roots are indexed in `variantOf[id] = canonicalID`. Used by `buildVariantChain` and `GetChainInfo` to unify variant quest IDs under a single chain.
```

- [ ] **Step 4: Add entry to changelog.txt**

Add the same version history content at the top of `changelog.txt` (create file if it doesn't exist).

- [ ] **Step 5: Commit**

```bash
cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
git add AbsoluteQuestLog.lua AbsoluteQuestLog.toc CLAUDE.md changelog.txt
git commit -m "$(cat <<'EOF'
feat: AQL:GetChainInfo provider fallthrough for remote quests

When QuestCache has no Known result for a questID (e.g. a remote party
member's variant quest not in the local log), fall through to the Chain
provider. This allows GrailProvider's new variant chain logic to resolve
any Retail variant questID regardless of whether it's in the local log.
Bump version per versioning rule.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: SocialQuest Cleanup — Remove `GetChainInfoForQuestID`, Step-Number Dedup

**Files:**
- Modify: `UI/TabUtils.lua` — remove `GetChainInfoForQuestID`
- Modify: `UI/Tabs/PartyTab.lua` — update `ci` resolution; replace title+zone merge with step-number dedup
- Modify: `UI/Tabs/SharedTab.lua` — update `ci` resolution; add step-number dedup
- Modify: `SocialQuest.toc` — version bump
- Modify: `CLAUDE.md` — add version history entry

### Background

With `AQL:GetChainInfo` now handling provider fallthrough, `SocialQuestTabUtils.GetChainInfoForQuestID` is redundant. Remove it and replace all call sites.

**Why step-number dedup beats title+zone:**
Two variant questIDs (28763 and 28766) both resolve to `chainID=28757, step=1` via the new AQL. This pair is unambiguous — no false positives. The old title+zone match was fragile (failed when variants had different chainIDs, which was the root cause of the bug in 2.17.8).

**PartyTab dedup:** add `local chainStepEntries = {}` before the main questID loop. When inserting into `zone.chains[chainID].steps`, check `chainStepEntries[chainID][stepNum]` first. If it exists, merge `entry.players` into it. If not, record and insert.

**SharedTab dedup:** same approach. SharedTab's inner loop already deduplicates by questID within a chain group (`addedQuestIDs`). Add step-number dedup around the insert so DIFFERENT questIDs at the same step are merged.

**`GetChainInfoForQuestID` call sites:**
- `SharedTab.lua:30` — in `addEngagement` local function
- `SharedTab.lua:102` — in the chain-processing loop
- `PartyTab.lua:286` — in the main questID loop

- [ ] **Step 1: Run existing SocialQuest tests to establish baseline**

```
cd "D:/Projects/Wow Addons/Social-Quest"
lua tests/FilterParser_test.lua
lua tests/TabUtils_test.lua
```

Expected: 0 failures. (These tests do not reference `GetChainInfoForQuestID`.)

- [ ] **Step 2: Remove `GetChainInfoForQuestID` from UI/TabUtils.lua**

Remove lines 32–47 entirely (the comment block `-- Returns the GetChainInfo wrapper...` through the closing `end` of `GetChainInfoForQuestID`):

```lua
-- REMOVE this entire block (lines 32-47):
-- Returns the GetChainInfo wrapper { knownStatus, chains } for questID.
-- Queries AQL cache first; falls back to the active Chain provider for remote quests.
-- Callers should use SocialQuestTabUtils.SelectChain(result, engagedSet) to pick a chain entry.
function SocialQuestTabUtils.GetChainInfoForQuestID(questID)
    local AQL = SocialQuest.AQL
    local result = AQL:GetChainInfo(questID)
    if result.knownStatus == AQL.ChainStatus.Known then return result end
    local provider = AQL.providers and AQL.providers[AQL.Capability.Chain]
    if provider then
        local ok, provResult = pcall(provider.GetChainInfo, provider, questID)
        if ok and provResult and provResult.knownStatus == AQL.ChainStatus.Known then
            return provResult
        end
    end
    return result
end
```

- [ ] **Step 3: Update `UI/Tabs/SharedTab.lua` — replace call sites and add step-number dedup**

**3a.** On line 30, inside the `addEngagement` function, change:
```lua
-- OLD:
local chainResult = SocialQuestTabUtils.GetChainInfoForQuestID(questID)
```
to:
```lua
-- NEW:
local chainResult = AQL:GetChainInfo(questID)
```

**3b.** On line 102, inside the chain-processing loop, change:
```lua
-- OLD:
local ci = SocialQuestTabUtils.GetChainInfoForQuestID(eng.questID)
```
to:
```lua
-- NEW:
local ci = AQL:GetChainInfo(eng.questID)
```

**3c.** Add `local chainStepEntries = {}` declaration on the line immediately before the `for chainID, engaged in pairs(chainEngaged) do` loop (currently around line 75):
```lua
-- Add this line before the chain loop:
local chainStepEntries = {}   -- [chainID][stepNum] = existing entry
```

**3d.** Replace the inner insert at line 168:
```lua
-- OLD (line 168):
                        table.insert(zone.chains[chainID].steps, entry)
```
With the step-number dedup block:
```lua
-- NEW:
                        if not chainStepEntries[chainID] then chainStepEntries[chainID] = {} end
                        local existing = chainStepEntries[chainID][eng.step]
                        if existing then
                            for _, p in ipairs(entry.players) do
                                table.insert(existing.players, p)
                            end
                        else
                            chainStepEntries[chainID][eng.step] = entry
                            table.insert(zone.chains[chainID].steps, entry)
                        end
```

- [ ] **Step 4: Update `UI/Tabs/PartyTab.lua` — replace call site and step-number dedup**

**4a.** On line 286, change:
```lua
-- OLD:
            local ci           = localInfo and localInfo.chainInfo or SocialQuestTabUtils.GetChainInfoForQuestID(questID)
```
to:
```lua
-- NEW:
            local ci           = AQL:GetChainInfo(questID)
```

**4b.** Add `local chainStepEntries = {}` on the line immediately before `for questID in pairs(allQuestIDs) do` (currently around line 270):
```lua
-- Add this line before the questID loop:
    local chainStepEntries = {}   -- [chainID][stepNum] = existing entry
```

**4c.** Replace the title+zone merge block (currently lines 326–341) and the surrounding `if not merged / else` logic:
```lua
-- REMOVE (lines 326-341 plus the surrounding merged/not-merged logic):
                -- Merge same-title/same-zone steps: ...
                local merged = false
                for _, existingStep in ipairs(zone.chains[chainID].steps) do
                    if existingStep.title == entry.title and existingStep.zone == entry.zone then
                        for _, p in ipairs(entry.players) do
                            table.insert(existingStep.players, p)
                        end
                        merged = true
                        break
                    end
                end
                if not merged then
                    table.insert(zone.chains[chainID].steps, entry)
                end
```
Replace with:
```lua
-- ADD: step-number dedup — two variant questIDs at the same (chainID, step) merge here.
                if not chainStepEntries[chainID] then chainStepEntries[chainID] = {} end
                local stepNum = ciEntry.step
                local existing = chainStepEntries[chainID][stepNum]
                if existing then
                    for _, p in ipairs(entry.players) do
                        table.insert(existing.players, p)
                    end
                else
                    chainStepEntries[chainID][stepNum] = entry
                    table.insert(zone.chains[chainID].steps, entry)
                end
```

- [ ] **Step 5: Run SocialQuest tests to confirm no regressions**

```
cd "D:/Projects/Wow Addons/Social-Quest"
lua tests/FilterParser_test.lua
lua tests/TabUtils_test.lua
```

Expected: 0 failures.

- [ ] **Step 6: Bump version in SocialQuest.toc**

Change `## Version:` to the correct new version (see Versioning Note — either `2.18.0` or `2.17.9`).

- [ ] **Step 7: Add version history entry to SocialQuest CLAUDE.md**

Add at the top of the Version History section:

```markdown
### Version X.X.X (April 2026 — Improvements branch)
- Bug fix (Retail): Party and Shared tabs now correctly group two players on different
  class/race variant questIDs for the same logical chain step (e.g. questID 28763 and
  28766 for "Beating Them Back!") into ONE step entry under ONE chain header. Root-cause
  fix: AQL's `GrailProvider` now builds a unified variant chain with the correct step
  count (e.g. 5 steps instead of 2) using a majority-vote algorithm that discards
  class-specific side-branch quests. `AQL:GetChainInfo` now falls through to the Chain
  provider for remote questIDs not in the local cache. All three fixes are in AQL.
- Refactor: `SocialQuestTabUtils.GetChainInfoForQuestID` removed. All call sites replaced
  with direct `AQL:GetChainInfo(questID)` calls, which now handle both local and remote
  questIDs correctly. The provider fallthrough that was in `GetChainInfoForQuestID` has
  moved into `AQL:GetChainInfo` itself — the correct location per the AQL-is-sole-source
  policy.
- Refactor: Party tab and Shared tab chain step deduplication upgraded from title+zone
  string matching to step-number keying (`chainStepEntries[chainID][stepNum]`). Two
  variant questIDs that resolve to the same `(chainID, step)` pair via AQL are always
  unambiguous — no false positives possible. The previous title+zone heuristic failed
  when variants had different chainIDs (the root cause of the 2.17.8 incomplete fix).
```

- [ ] **Step 8: Commit**

```bash
cd "D:/Projects/Wow Addons/Social-Quest"
git add UI/TabUtils.lua UI/Tabs/PartyTab.lua UI/Tabs/SharedTab.lua SocialQuest.toc CLAUDE.md
git commit -m "$(cat <<'EOF'
refactor: remove GetChainInfoForQuestID; step-number dedup in tabs

GetChainInfoForQuestID was a SQ-level provider fallthrough that is now
handled correctly inside AQL:GetChainInfo. Removing it keeps AQL as
the sole source of truth for chain data. PartyTab and SharedTab now
dedup chain step entries by (chainID, stepNum) instead of title+zone:
variant questIDs at the same logical step always share these values,
making the dedup unambiguous. Bump version per versioning rule.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task covering it |
|---|---|
| Variant group detection (variantGroups/variantOf) in buildReverseMap | Task 1 |
| `buildVariantChain` with majority-vote filter | Task 2 |
| `GetChainInfo` variant root fast path | Task 3 |
| `GetChainInfo` mid-chain variant lookup (walks back to root, uses buildVariantChain) | Task 3 (Path 3) |
| `AQL:GetChainInfo` provider fallthrough | Task 4 |
| Remove `GetChainInfoForQuestID` | Task 5 |
| PartyTab step-number dedup | Task 5 |
| SharedTab step-number dedup | Task 5 |
| Version bumps + changelogs | Tasks 4 and 5 |
| Unit tests for all variant behaviors | Task 1 (test file covers Tasks 1–3) |

**Placeholder scan:** No TBD, TODO, or vague steps — all code is shown in full.

**Type consistency check:**
- `variantGroups[canonicalID]` accessed in Task 1 (write), Task 2 (read in `buildVariantChain`), Task 3 (read in `GetChainInfo`) — consistent.
- `variantOf[questID]` accessed in Task 1 (write), Task 3 (read) — consistent.
- `variantChainCache[canonicalID]` accessed in Task 2 (write + read) — consistent.
- `findStepForQuestID(questID, steps)` defined in Task 2 Step 1, called in Task 3 — consistent signature.
- `buildVariantChain(canonicalID)` defined in Task 2 Step 2, called in Task 3 — consistent signature.
- `annotateSteps(steps)` defined and used locally inside `GetChainInfo` in Task 3 — no cross-task dependency.
- `chainStepEntries[chainID][stepNum]` used consistently in both PartyTab and SharedTab in Task 5.

**Edge cases covered:**
- `buildVariantChain` for a group of size 1 (no-op — just walks the single root normally) ✓
- Convergence-point quest (single quest shared by all variant paths): appears N times in candidate list, passes majority vote, deduplicated to one in nextWave ✓
- Side-branch letter quests: appear once, fail majority vote, discarded ✓
- Mid-chain variant questID: findRoots walks back to root, root is in variantOf, uses buildVariantChain ✓
- Non-variant chain (TBC Classic): root not in variantGroups, falls through to buildChainFromRoot ✓
- Questie/QuestWeaver/BtWQuests chains: no change — these don't use GrailProvider ✓
