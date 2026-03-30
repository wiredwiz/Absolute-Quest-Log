# BtWQuestsProvider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `BtWQuestsProvider` to supply chain, faction, and level-range data on Retail from the BtWQuests addon, and wire it into the existing multi-provider priority system.

**Architecture:** New file `Providers/BtWQuestsProvider.lua` with module-local reverse index (`questID → chainKey`), built incrementally on first use. Plugged into the existing `getProviderPriority()` table in `Core/EventEngine.lua`. Covers the Chain, QuestInfo, and Requirements capability slots.

**Tech Stack:** Lua, WoW AddOn API (all version families; provider is inert on non-Retail clients where BtWQuests is absent), BtWQuests 2.x `Database.Chains` data tables.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Providers/BtWQuestsProvider.lua` | Create | Full provider implementation |
| `AbsoluteQuestLog.lua` | Modify | Add `BtWQuests` to `AQL.Provider` enum; update stale comment |
| `Core/EventEngine.lua` | Modify | Add BtWQuestsProvider to all three capability lists in `getProviderPriority()` |
| `Providers/Provider.lua` | Modify | Update doc comment: add `"BtWQuests"` to `provider` field value list |
| `AbsoluteQuestLog_Mainline.toc` | Modify | Add `Providers/BtWQuestsProvider.lua` |
| `AbsoluteQuestLog_TBC.toc` | Modify | Add `Providers/BtWQuestsProvider.lua` |
| `AbsoluteQuestLog_Classic.toc` | Modify | Add `Providers/BtWQuestsProvider.lua` |
| `AbsoluteQuestLog_Mists.toc` | Modify | Add `Providers/BtWQuestsProvider.lua` |
| `AbsoluteQuestLog.toc` | Modify | Add `Providers/BtWQuestsProvider.lua` |
| `CLAUDE.md` | Modify | Version bump to 2.6.1; add changelog entry |
| `changelog.txt` | Modify | Add 2.6.1 entry |

---

## Task 1: Add AQL.Provider.BtWQuests enum entry

**Files:**
- Modify: `AbsoluteQuestLog.lua:53–57` (AQL.Provider table)
- Modify: `AbsoluteQuestLog.lua:81` (stale Phase 2 comment)

**What this enables:** The string constant `AQL.Provider.BtWQuests` used in `GetChainInfo`'s return value. Without it, providers would have to embed a raw string literal.

- [ ] **Step 1: Update the AQL.Provider enum**

In `AbsoluteQuestLog.lua`, find the `AQL.Provider` table and add the `BtWQuests` entry:

```lua
AQL.Provider = {
    Questie     = "Questie",
    QuestWeaver = "QuestWeaver",
    BtWQuests   = "BtWQuests",   -- add this line
    None        = "none",
}
```

- [ ] **Step 2: Update the stale comment on line 81**

Change:
```lua
-- Phase 2 will add GrailProvider (QuestInfo, Requirements) and BtWQuestsProvider (Chain).
```
To:
```lua
-- Phase 3 will add GrailProvider (QuestInfo, Requirements).
```

- [ ] **Step 3: Verify the enum is accessible**

Load the addon in-game (or `/reload`) and run:
```
/script print(AQL.Provider.BtWQuests)
```
Expected output: `BtWQuests`

- [ ] **Step 4: Commit**

```bash
git add AbsoluteQuestLog.lua
git commit -m "feat: add AQL.Provider.BtWQuests enum entry"
```

---

## Task 2: Create BtWQuestsProvider skeleton

**Files:**
- Create: `Providers/BtWQuestsProvider.lua`

**What this enables:** A provider that loads without error, reports availability correctly, and validates the BtWQuests API structure before use.

- [ ] **Step 1: Create the file with module constants and identity fields**

Create `Providers/BtWQuestsProvider.lua`:

```lua
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
```

- [ ] **Step 2: Add the file to all five TOC files**

In each of the five TOC files (`AbsoluteQuestLog.toc`, `AbsoluteQuestLog_Mainline.toc`, `AbsoluteQuestLog_TBC.toc`, `AbsoluteQuestLog_Classic.toc`, `AbsoluteQuestLog_Mists.toc`), add this line after `Providers\NullProvider.lua`:

```
Providers\BtWQuestsProvider.lua
```

- [ ] **Step 3: Verify the provider object loads**

`/reload` in-game, then:
```
/script print(AQL.BtWQuestsProvider ~= nil)
/script print(AQL.BtWQuestsProvider.addonName)
```
Expected: `true`, then `BtWQuests`

On a Retail client with BtWQuests installed:
```
/script print(AQL.BtWQuestsProvider:IsAvailable())
/script local ok, err = AQL.BtWQuestsProvider:Validate(); print(ok, err)
```
Expected: `true`, then `true nil`

On any non-Retail client (TBC/Classic/MoP) where BtWQuests is absent:
```
/script print(AQL.BtWQuestsProvider:IsAvailable())
```
Expected: `false`

- [ ] **Step 4: Commit**

```bash
git add Providers/BtWQuestsProvider.lua AbsoluteQuestLog.toc AbsoluteQuestLog_Mainline.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_Mists.toc
git commit -m "feat: add BtWQuestsProvider skeleton with IsAvailable/Validate"
```

---

## Task 3: Implement the reverse index

**Files:**
- Modify: `Providers/BtWQuestsProvider.lua`

**What this enables:** O(1) chain lookup by questID. BtWQuests keys its Chains table by an internal chainKey; we need to go the other direction (questID → chainKey). Built incrementally: only scans as many chains as needed before finding a hit.

- [ ] **Step 1: Add module-local index state and helper functions**

After the `CONDITION_ID_ALLIANCE` constant and before the `BtWQuestsProvider.addonName` line, insert:

```lua
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
```

- [ ] **Step 2: Verify the reverse index resolves a known Retail chain**

On a Retail client with BtWQuests installed, find a questID for a known chain quest (e.g. an active chain quest in your log). Then:

```
/script local qid = C_QuestLog.GetQuestIDForLogIndex(1); print(qid)
```
Note the questID, then:
```
/script local ck = (function() ... end)()  -- paste findChainKey inline if needed
```

A simpler approach — enable debug and reload, then accept a chain quest:
```
/aql debug verbose
```
After the next `QUEST_LOG_UPDATE`, check for BtWQuestsProvider log output once it's wired up in Task 7.

For now, a basic smoke test:
```
/script
local chains = BtWQuests.Database.Chains
local count = 0
for _ in pairs(chains) do count = count + 1 end
print("Total chains:", count)
```
Expected: a non-zero number (thousands on a loaded Retail client).

- [ ] **Step 3: Commit**

```bash
git add Providers/BtWQuestsProvider.lua
git commit -m "feat: add BtWQuestsProvider incremental reverse index (questID→chainKey)"
```

---

## Task 4: Implement step resolution helpers

**Files:**
- Modify: `Providers/BtWQuestsProvider.lua`

**What this enables:** `extractQuestIDs` produces one step entry per `items[]` quest entry, with the most-relevant questID for the current player selected. This is the foundation for both `GetChainInfo` and `GetQuestRequirements`.

- [ ] **Step 1: Add resolveStepQuestID and extractQuestIDs after the reverse index block**

After `findChainKey` and before `BtWQuestsProvider.addonName`, insert:

```lua
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
```

- [ ] **Step 2: Verify step extraction on a known chain**

On a Retail client with BtWQuests installed, pick a chainKey from the first entry in `BtWQuests.Database.Chains` and inspect its extracted steps:

```
/script
local chainKey, chain = next(BtWQuests.Database.Chains)
print("Chain:", chainKey, chain.name)
local count = 0
for _, item in ipairs(chain.items or {}) do
    if item.type == "quest" then count = count + 1 end
end
print("Quest steps:", count)
```
Expected: a chain name and a non-zero step count.

- [ ] **Step 3: Commit**

```bash
git add Providers/BtWQuestsProvider.lua
git commit -m "feat: add resolveStepQuestID and extractQuestIDs helpers"
```

---

## Task 5: Implement GetChainInfo

**Files:**
- Modify: `Providers/BtWQuestsProvider.lua`

**What this enables:** The core Chain capability method. Returns a fully-annotated `ChainInfo` table for any questID that BtWQuests knows about.

- [ ] **Step 1: Add GetChainInfo before the AQL.BtWQuestsProvider assignment**

```lua
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
        elseif AQL.QuestCache and AQL.QuestCache:Get(sid) then
            local q = AQL.QuestCache:Get(sid)
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
        s.title = WowQuestAPI.GetQuestInfo(sid) or ("Quest " .. sid)
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
```

- [ ] **Step 2: Verify GetChainInfo returns correct data**

On a Retail client with BtWQuests installed, find a questID that is part of a chain (check wowhead or use a quest you know is in a chain):

```
/script
local info = AQL.BtWQuestsProvider:GetChainInfo(QUESTID_HERE)
print("status:", info.knownStatus)
print("step:", info.step, "of", info.length)
if info.steps then
    for i, s in ipairs(info.steps) do
        print(i, s.questID, s.title or "?", s.status)
    end
end
```
Expected for a known chain quest:
- `knownStatus = "known"`
- `step` is the correct 1-based position
- Steps have titles (not "Quest N") if C_QuestLog.GetQuestInfo returns them
- The current quest shows `status = "active"`; completed prior steps show `"completed"`

For a standalone quest (questID with no chain in BtWQuests):
```
/script local info = AQL.BtWQuestsProvider:GetChainInfo(STANDALONE_QUESTID); print(info.knownStatus)
```
Expected: `not_a_chain`

- [ ] **Step 3: Commit**

```bash
git add Providers/BtWQuestsProvider.lua
git commit -m "feat: implement BtWQuestsProvider:GetChainInfo"
```

---

## Task 6: Implement GetQuestFaction

**Files:**
- Modify: `Providers/BtWQuestsProvider.lua`

**What this enables:** The QuestInfo capability's faction method. Decodes chain-level faction restrictions from BtWQuests, handling both numeric condition IDs (923/924) and `{type="faction"}` table entries.

- [ ] **Step 1: Add decodeFaction helper and GetQuestFaction**

After the Chain capability block and before `AQL.BtWQuestsProvider = BtWQuestsProvider`:

```lua
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
    local factionConst = BtWQuests.Constant.Faction   -- { Horde = "Horde", Alliance = "Alliance" }
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
```

- [ ] **Step 2: Verify GetQuestFaction on a faction-gated chain**

Find a questID from a known Horde-only or Alliance-only chain (check wowhead for a quest with faction restriction):

```
/script print(AQL.BtWQuestsProvider:GetQuestFaction(HORDE_QUESTID_HERE))
```
Expected: `Horde`

```
/script print(AQL.BtWQuestsProvider:GetQuestFaction(ALLIANCE_QUESTID_HERE))
```
Expected: `Alliance`

For a neutral chain quest:
```
/script print(AQL.BtWQuestsProvider:GetQuestFaction(NEUTRAL_QUESTID_HERE))
```
Expected: `nil` (prints nothing)

- [ ] **Step 3: Commit**

```bash
git add Providers/BtWQuestsProvider.lua
git commit -m "feat: implement BtWQuestsProvider:GetQuestFaction with decodeFaction"
```

---

## Task 7: Implement GetQuestRequirements

**Files:**
- Modify: `Providers/BtWQuestsProvider.lua`

**What this enables:** The Requirements capability. Returns level range and nextQuestInChain for step 1 of a chain; only nextQuestInChain for subsequent steps (returning mid-chain level requirements would produce false eligibility negatives for players already in the chain).

- [ ] **Step 1: Add GetQuestRequirements after GetQuestType**

```lua
------------------------------------------------------------------------
-- Requirements capability
------------------------------------------------------------------------

function BtWQuestsProvider:GetQuestRequirements(questID)
    local chainKey = findChainKey(questID)
    if not chainKey then return nil end
    local chain = BtWQuests.Database.Chains[chainKey]
    if not chain then return nil end

    local steps = extractQuestIDs(chain.items or {}, questID)
    if #steps == 0 then return nil end

    local isFirstStep = (steps[1].questID == questID)

    -- nextQuestInChain: the questID of the next step in this chain, or nil if last step.
    local nextInChain = nil
    for i, s in ipairs(steps) do
        if s.questID == questID and steps[i + 1] then
            nextInChain = steps[i + 1].questID
            break
        end
    end

    -- breadcrumbForQuestId: only the first step of a chain can be a breadcrumb entry.
    -- chain.relationship.breadcrumb holds the questID this chain is a breadcrumb for.
    local breadcrumb = isFirstStep
        and chain.relationship
        and chain.relationship.breadcrumb
        or nil

    if isFirstStep then
        -- Return level range only for step 1. Returning it for later steps would
        -- show players as ineligible for quests they are already in the middle of.
        return {
            requiredLevel        = chain.range and chain.range.min or nil,
            requiredMaxLevel     = chain.range and chain.range.max or nil,
            nextQuestInChain     = nextInChain,
            breadcrumbForQuestId = breadcrumb,
        }
    else
        -- Mid-chain or final step: only return fields that have values.
        if not nextInChain and not breadcrumb then return nil end
        return {
            nextQuestInChain     = nextInChain,
            breadcrumbForQuestId = breadcrumb,
        }
    end
end
```

- [ ] **Step 2: Verify GetQuestRequirements on a chain's first and middle steps**

For step 1 of a known chain (with a level range defined):
```
/script
local r = AQL.BtWQuestsProvider:GetQuestRequirements(STEP1_QUESTID)
if r then print(r.requiredLevel, r.requiredMaxLevel, r.nextQuestInChain) else print("nil") end
```
Expected: `10 60 NEXT_QUESTID` (or similar non-nil values for a levelling chain)

For a mid-chain step:
```
/script
local r = AQL.BtWQuestsProvider:GetQuestRequirements(STEP2_QUESTID)
if r then print(r.requiredLevel, r.nextQuestInChain) else print("nil") end
```
Expected: `nil NEXT_QUESTID` (no level restriction, but next chain link present)

For the last step of a chain:
```
/script
local r = AQL.BtWQuestsProvider:GetQuestRequirements(LAST_STEP_QUESTID)
print(r)
```
Expected: `nil` (no next step, no breadcrumb)

- [ ] **Step 3: Commit**

```bash
git add Providers/BtWQuestsProvider.lua
git commit -m "feat: implement BtWQuestsProvider:GetQuestRequirements"
```

---

## Task 8: Wire BtWQuestsProvider into EventEngine

**Files:**
- Modify: `Core/EventEngine.lua:80–86` (`getProviderPriority()` inner table)

**What this enables:** `selectProviders()` will now consider BtWQuestsProvider for all three capability slots. On Retail without Questie or QuestWeaver, it fills all three. On TBC/Classic/MoP, `IsAvailable()` returns false and it is skipped silently.

- [ ] **Step 1: Update getProviderPriority() to include BtWQuestsProvider**

In `Core/EventEngine.lua`, find `getProviderPriority()` and replace the inner table:

```lua
-- Before:
_PROVIDER_PRIORITY = {
    [AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider },
    [AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider },
    [AQL.Capability.Requirements] = { AQL.QuestieProvider },
}

-- After:
_PROVIDER_PRIORITY = {
    [AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider },
    [AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider },
    [AQL.Capability.Requirements] = { AQL.QuestieProvider, AQL.BtWQuestsProvider },
}
```

Note: `AQL.BtWQuestsProvider` is nil when `_PROVIDER_PRIORITY` is first built if `BtWQuestsProvider.lua` loads before EventEngine resolves providers, but `selectProviders()` nil-checks each candidate — it is safe. The nil-check is in the `if provider and provider:IsAvailable()` condition inside `selectProviders()`.

- [ ] **Step 2: Verify provider selection on Retail with BtWQuests installed**

On Retail with BtWQuests installed (and Questie/QuestWeaver absent), enable debug and reload:

```
/aql debug on
/reload
```

Expected in chat (within 5 seconds of login):
```
[AQL] Provider selected for Chain: BtWQuests
[AQL] Provider selected for QuestInfo: BtWQuests
[AQL] Provider selected for Requirements: BtWQuests
```

Confirm via:
```
/script
print("Chain:", AQL.providers[AQL.Capability.Chain] and AQL.providers[AQL.Capability.Chain].addonName)
print("QuestInfo:", AQL.providers[AQL.Capability.QuestInfo] and AQL.providers[AQL.Capability.QuestInfo].addonName)
print("Requirements:", AQL.providers[AQL.Capability.Requirements] and AQL.providers[AQL.Capability.Requirements].addonName)
```
Expected: `Chain: BtWQuests`, `QuestInfo: BtWQuests`, `Requirements: BtWQuests`

On TBC with Questie installed:
```
/script print(AQL.providers[AQL.Capability.Chain].addonName)
```
Expected: `Questie` (BtWQuestsProvider correctly skipped)

- [ ] **Step 3: Verify a chain quest populates chainInfo in QuestCache**

On Retail, accept a chain quest, then:
```
/script
local questID = C_QuestLog.GetQuestIDForLogIndex(1)  -- adjust index as needed
local qi = AQL:GetQuest(questID)
if qi and qi.chainInfo then
    print("provider:", qi.chainInfo.provider)
    print("step:", qi.chainInfo.step, "of", qi.chainInfo.length)
else
    print("no chainInfo")
end
```
Expected: `provider: BtWQuests`, `step: N of M`

- [ ] **Step 4: Commit**

```bash
git add Core/EventEngine.lua
git commit -m "feat: add BtWQuestsProvider to all capability priority lists in EventEngine"
```

---

## Task 9: Update Provider.lua doc comment

**Files:**
- Modify: `Providers/Provider.lua:33`

**What this enables:** The interface contract documentation stays accurate. Consumers reading Provider.lua see `"BtWQuests"` as a valid `provider` field value.

- [ ] **Step 1: Update the provider field value list in the ChainInfo comment**

In `Providers/Provider.lua`, find the line:
```lua
--     When knownStatus = "unknown":     only knownStatus present.
```
Just above it, find the `provider` doc line and update:
```lua
-- Before:
--       provider    = "Questie" | "QuestWeaver" | "none"

-- After:
--       provider    = "Questie" | "QuestWeaver" | "BtWQuests" | "none"
```

- [ ] **Step 2: Commit**

```bash
git add Providers/Provider.lua
git commit -m "docs: add BtWQuests to Provider.lua ChainInfo provider field values"
```

---

## Task 10: Version bump and changelog

**Files:**
- Modify: `CLAUDE.md` (Version History section + version number)
- Modify: `changelog.txt`
- Modify: `AbsoluteQuestLog.toc` (Version line)
- Modify: `AbsoluteQuestLog_Mainline.toc` (Version line)
- Modify: `AbsoluteQuestLog_TBC.toc` (Version line)
- Modify: `AbsoluteQuestLog_Classic.toc` (Version line)
- Modify: `AbsoluteQuestLog_Mists.toc` (Version line)

- [ ] **Step 1: Update version in all five TOC files**

Change `## Version: 2.6.0` to `## Version: 2.6.1` in all five `.toc` files.

- [ ] **Step 2: Add changelog entry to CLAUDE.md**

In the Version History section, insert before the existing `### Version 2.6.0` entry:

```markdown
### Version 2.6.1 (March 2026)
- New provider: `BtWQuestsProvider` — supplies chain data (GetChainInfo), faction
  (GetQuestFaction), and level-range requirements (GetQuestRequirements) on Retail
  from the BtWQuests addon. Inert on TBC/Classic/MoP (IsAvailable returns false when
  BtWQuests global is absent).
- Reverse index built incrementally on first use: questID → chainKey. Handles .ids
  (OR-logic step variants), item.variations, and non-quest chain items (silently skipped).
- New: `AQL.Provider.BtWQuests = "BtWQuests"` enum entry.
- EventEngine: BtWQuestsProvider added to Chain, QuestInfo, and Requirements priority
  lists. On Retail without Questie or QuestWeaver, fills all three capability slots.
```

- [ ] **Step 3: Add entry to changelog.txt**

At the top of `changelog.txt`, add the same content as the CLAUDE.md entry above.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md changelog.txt AbsoluteQuestLog.toc AbsoluteQuestLog_Mainline.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_Mists.toc
git commit -m "chore: bump version to 2.6.1 — BtWQuestsProvider"
```

---

## Task 11: End-to-end smoke test (Retail)

No code changes. Manual verification of the full path from login to chain data in QuestCache.

- [ ] **Step 1: Full Retail smoke test with BtWQuests installed, Questie absent**

1. Ensure BtWQuests is enabled. Ensure Questie and QuestWeaver are disabled.
2. Log in to a Retail character with at least one active chain quest.
3. Run `/aql debug on` then `/reload`.
4. Confirm in chat:
   - No `[AQL] WARNING:` messages (no broken provider, no missing provider)
   - Debug lines show `Provider selected for Chain: BtWQuests`, etc.
5. Inspect a chain quest:
   ```
   /script
   local qi = AQL:GetQuest(YOUR_CHAIN_QUESTID)
   if qi then
       print("type:", qi.type)
       print("faction:", qi.faction)
       local ci = qi.chainInfo
       if ci then print("chain:", ci.knownStatus, ci.step, "/", ci.length, "provider:", ci.provider)
       else print("no chainInfo") end
   else print("quest not in cache") end
   ```
   Expected: `chain: known N / M provider: BtWQuests`

- [ ] **Step 2: Full Retail smoke test with Questie installed**

1. Enable Questie alongside BtWQuests.
2. `/reload`. Confirm debug shows Questie selected for all three slots.
3. BtWQuestsProvider should be silently skipped (Questie wins the priority race).
4. Confirm: no BtWQuests warnings, no missing-provider warnings.

- [ ] **Step 3: TBC smoke test (no BtWQuests)**

1. On a TBC client (Interface 20505), log in with Questie installed.
2. `/reload`. Confirm debug shows Questie selected. No warnings about BtWQuests.
   ```
   /script print(AQL.BtWQuestsProvider:IsAvailable())
   ```
   Expected: `false`
