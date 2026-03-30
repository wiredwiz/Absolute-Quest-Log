# BtWQuestsProvider — Design Spec

**Date:** 2026-03-30
**Status:** Approved
**Scope:** Phase 2 of the provider system refactor — implement `BtWQuestsProvider` for Retail/MoP chain, quest info, and requirements data.

---

## Problem

On Retail and MoP, no chain provider exists. `AQL.providers[AQL.Capability.Chain]` is always nil, so `GetChainInfo` always returns `knownStatus = "unknown"`. BtWQuests is the only addon with explicit chain structure data for these version families.

---

## Goals

1. Implement `BtWQuestsProvider` covering Chain, QuestInfo, and Requirements capabilities
2. Register it at the bottom of each capability's priority list (below Questie and QuestWeaver)
3. On Retail without Questie or QuestWeaver, BtWQuestsProvider fills all three slots
4. No behavioral changes on TBC/Classic where Questie or QuestWeaver is active

---

## Capabilities

```lua
BtWQuestsProvider.capabilities = {
    AQL.Capability.Chain,
    AQL.Capability.QuestInfo,
    AQL.Capability.Requirements,
}
```

**QuestInfo registration rationale:** On Retail without Questie/QuestWeaver, BtWQuestsProvider fills the QuestInfo slot. It can only provide faction (from chain-level restrictions). `GetQuestType` and `GetQuestBasicInfo` return nil. This is better than leaving the slot empty.

**Requirements registration rationale:** Chain-level data (level range, breadcrumb) can be partially inferred per-quest. Level requirements are only returned for step 1 — returning them for mid-chain steps would produce false eligibility negatives for players already in the chain. Grail (Phase 3) will be inserted above BtWQuests in the Requirements priority list when implemented.

---

## Priority Lists

Updated `getProviderPriority()` in `Core/EventEngine.lua`:

```lua
[AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider },
[AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider },
[AQL.Capability.Requirements] = { AQL.QuestieProvider, AQL.BtWQuestsProvider },
```

Grail's slot in Requirements (between Questie and BtWQuests) is reserved for Phase 3.

---

## Files Changed

| File | Change |
|---|---|
| `Providers/BtWQuestsProvider.lua` | New file |
| `Providers/Provider.lua` | Update ChainInfo contract doc comment: `provider` field value list (line 33) from `"Questie" \| "QuestWeaver" \| "none"` to `"Questie" \| "QuestWeaver" \| "BtWQuests" \| "none"` |
| `AbsoluteQuestLog.lua` | Add `BtWQuests = "BtWQuests"` entry to `AQL.Provider` enum |
| `Core/EventEngine.lua` | Update `getProviderPriority()` with BtWQuests entries |
| All 5 TOC files | Add `Providers/BtWQuestsProvider.lua` line |
| `CLAUDE.md` + `changelog.txt` | Version bump to 2.6.1 |

---

## BtWQuests Data Structure

```lua
BtWQuests.Database.Chains[chainKey] = {
    name          = "Chain name",         -- localized string; NOT surfaced in ChainInfo
    range         = { min=10, max=20 },   -- level requirements (chain-granularity)
    items         = { ... },              -- ordered array of step entries (see below)
    prerequisites = { chainKey, ... },    -- chain-level prerequisites
    restrictions  = HORDE_RESTRICTIONS    -- or ALLIANCE_RESTRICTIONS, or absent
                  | ALLIANCE_RESTRICTIONS,
    relationship  = { breadcrumb=questID }, -- present if chain is a breadcrumb
}
```

Each `items[]` entry is one step:

```lua
{ id = 12345, type="quest" }              -- single-quest step
{ ids = { 12345, 12346 }, type="quest" }  -- multi-questID step (see note below)
{ type="npc" }                            -- non-quest item; filtered out silently
```

**Note on chain names:** BtWQuests stores an independent localized `name` on each chain, sourced from achievement criteria or its own localization table. This is not the same as the first quest's title and is not surfaced in AQL's `ChainInfo`. AQL's implicit chain name remains `steps[1].title` (consistent with all other providers).

**Known limitation:** BtWQuests chains are editorially curated groupings and may not correspond 1:1 with Blizzard's `nextQuestInChain` relationships as reflected on WoWhead. On Retail this is the only chain data available; consumers should be aware chain boundaries may differ from the server-enforced definition.

---

## `chainKey` vs AQL `chainID`

BtWQuests keys its `Chains` table by its own internal chainKey, which is not a questID. AQL's `ChainInfo.chainID` contract specifies "questID of the first quest in the chain."

**Resolution:** AQL's `chainID` is computed as `steps[1].questID` — the questID of the first quest entry in `items[]` after filtering non-quest items. The BtWQuests chainKey is used only for internal index lookups and is never exposed in output.

---

## Incremental Reverse Index

BtWQuests is keyed by chainKey; `GetChainInfo` is called with a questID. A reverse index is required.

Three module-local variables:

```lua
local _questToChain  = {}    -- [questID] = chainKey
local _scannedChains = {}    -- [chainKey] = true
local _fullyIndexed  = false -- true once all chains have been scanned
```

Lookup algorithm (`findChainKey(questID)`):

1. Return `_questToChain[questID]` if present (O(1) hit).
2. If `_fullyIndexed`, return nil (quest not in BtWQuests).
3. Iterate `BtWQuests.Database.Chains`, skipping keys in `_scannedChains`. Skip any entry whose value is not a table (guards against non-chain metadata stored at the top level of the Chains table). For each unscanned chain, iterate `items[]` and for every quest-type item add ALL candidate questIDs to `_questToChain`: `item.id` (single), every entry in `item.ids` (OR variants), and every entry in `item.variations`. All map to the same chainKey. Mark chain as scanned. Stop as soon as `_questToChain[questID]` is populated.
4. If all chains exhausted without finding questID, set `_fullyIndexed = true`, return nil.

The index is built incrementally on demand. A questID in an early-accessed chain is found after scanning only a small portion of the database. The full index is never built unless the player looks up quests across many unrelated chains.

---

## Step Extraction

**`.ids` semantics (confirmed from BtWQuestsItem_Active source):** `.ids` is OR logic — multiple questIDs that all satisfy the same step position. This handles scenarios where different players receive different questIDs for the same story beat (e.g. different phases, patch replacements). Each `items[]` entry is exactly one step; `.ids` lists alternative questIDs for that step. Flattening `.ids` into separate entries inflates chain length and produces wrong step numbers and must not be done.

`extractQuestIDs` returns one entry per quest-type `items[]` entry. The `questID` field holds the most-relevant questID for the current player, resolved by `resolveStepQuestID`. All IDs in `.ids` (and in `item.variations` when present) are added to the reverse index pointing to the same chainKey.

```lua
-- Resolve which questID best represents a step for the current player.
-- Priority: player's active quest (QuestCache) > completed (HistoryCache) > ids[1]/id.
local function resolveStepQuestID(item, lookupQuestID)
    local candidates = {}
    if item.ids then
        for _, qid in ipairs(item.ids) do candidates[#candidates+1] = qid end
    else
        candidates[1] = item.id
    end
    if item.variations then
        for _, qid in ipairs(item.variations) do candidates[#candidates+1] = qid end
    end

    -- Return the lookupQuestID itself if it's one of the candidates.
    if lookupQuestID then
        for _, qid in ipairs(candidates) do
            if qid == lookupQuestID then return lookupQuestID end
        end
    end
    -- Return the candidate currently in the player's active quest log.
    for _, qid in ipairs(candidates) do
        if AQL.QuestCache and AQL.QuestCache:Get(qid) then return qid end
    end
    -- Return the first candidate the player has completed.
    for _, qid in ipairs(candidates) do
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(qid) then return qid end
    end
    return candidates[1]
end

local function extractQuestIDs(items, lookupQuestID)
    local result = {}
    for _, item in ipairs(items) do
        if item.type == "quest" then
            local qid = resolveStepQuestID(item, lookupQuestID)
            if qid then
                table.insert(result, { questID = qid })
            end
        end
        -- non-quest items (type="npc", type="event", etc.) silently skipped
    end
    return result
end
```

The reverse index (`_questToChain`) must index ALL candidate questIDs for each step — both `item.id` and every entry in `item.ids` and `item.variations` — so that any player variant resolves to the correct chainKey. See the Incremental Reverse Index section below for the full indexing logic.

---

## `IsAvailable()` and `Validate()`

```lua
function BtWQuestsProvider:IsAvailable()
    return type(BtWQuests) == "table"
end

function BtWQuestsProvider:Validate()
    if type(BtWQuests) ~= "table" then return false, "BtWQuests global missing" end
    if type(BtWQuests.Database) ~= "table" then return false, "BtWQuests.Database missing" end
    if type(BtWQuests.Database.Chains) ~= "table" then return false, "Chains table missing" end
    local sample = next(BtWQuests.Database.Chains)
    if sample == nil then return false, "Chains table is empty" end
    return true
end
```

`IsAvailable()` checks only the top-level `BtWQuests` global — consistent with the provider interface contract where `IsAvailable() = false` means "addon not installed, skip silently" and `IsAvailable() = true` + `Validate() = false` means "addon present but broken, fire warning." Moving `.Database` into `Validate()` ensures a broken install triggers the user-visible notification.

BtWQuests loads its database synchronously. An empty `Chains` table indicates a broken installation, not async init in progress — unlike Questie, no deferred retry is needed for this provider.

---

## Method Implementations

### `GetChainInfo(questID)`

```lua
function BtWQuestsProvider:GetChainInfo(questID)
    local chainKey = findChainKey(questID)
    if not chainKey then
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    local chain = BtWQuests.Database.Chains[chainKey]
    if not chain then
        return { knownStatus = AQL.ChainStatus.Unknown }
    end

    local steps = extractQuestIDs(chain.items, questID)
    -- A BtWQuests chain that yields fewer than 2 quest steps after filtering non-quest
    -- items (e.g. a chain composed entirely of NPC steps plus one quest) is treated as
    -- NotAChain. The questID remains in _questToChain so findChainKey still returns
    -- the chainKey on future calls — this is intentional, no caching of the extracted
    -- steps is needed for this path since the guard is cheap.
    if #steps < 2 then
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    local aqlChainID = steps[1].questID

    -- stepNum: find which step represents questID. Because resolveStepQuestID
    -- prioritizes questID itself when it's a valid candidate, the matching step's
    -- questID field equals questID after extraction. Safe to compare directly.
    local stepNum = nil
    for i, s in ipairs(steps) do
        if s.questID == questID then stepNum = i break end
    end

    for i, s in ipairs(steps) do
        local sid = s.questID
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(sid) then
            s.status = AQL.StepStatus.Completed
        elseif AQL.QuestCache and AQL.QuestCache:Get(sid) then
            local q = AQL.QuestCache:Get(sid)
            if q.isFailed then         s.status = AQL.StepStatus.Failed
            elseif q.isComplete then   s.status = AQL.StepStatus.Finished
            else                       s.status = AQL.StepStatus.Active end
        else
            local prev = steps[i - 1]
            local prevDone = prev and AQL.HistoryCache
                and AQL.HistoryCache:HasCompleted(prev.questID)
            s.status = (i == 1 or prevDone)
                and AQL.StepStatus.Available
                or  AQL.StepStatus.Unavailable
        end
        s.title = WowQuestAPI.GetQuestInfo(sid) or ("Quest "..sid)
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

Step titles are populated via `WowQuestAPI.GetQuestInfo(questID)`. On Retail, `C_QuestLog.GetQuestInfo` returns titles for known questIDs regardless of whether they are in the player's log. Falls back to `"Quest "..questID` for unrecognized IDs.

**Status annotation:** The HistoryCache-based Available/Unavailable pattern here follows `QuestieProvider` and is the authoritative standard. `QuestWeaverProvider` diverges by checking `prev.status == Completed` instead — that is the exception, not this implementation.

### `GetQuestRequirements(questID)`

Level requirements and prerequisites are chain-granularity in BtWQuests. Returning them for mid-chain steps would produce false eligibility negatives (a player already on step 3 would appear ineligible based on step 1's level requirement). Level data is therefore only returned for step 1.

`nextQuestInChain` and `breadcrumbForQuestId` are computed per-quest from chain position and are returned for all steps.

```lua
function BtWQuestsProvider:GetQuestRequirements(questID)
    local chainKey = findChainKey(questID)
    if not chainKey then return nil end
    local chain = BtWQuests.Database.Chains[chainKey]
    if not chain then return nil end

    local steps = extractQuestIDs(chain.items)
    if #steps == 0 then return nil end

    local isFirstStep = steps[1].questID == questID

    local nextInChain = nil
    for i, s in ipairs(steps) do
        if s.questID == questID and steps[i + 1] then
            nextInChain = steps[i + 1].questID
            break
        end
    end

    local breadcrumb = isFirstStep
        and chain.relationship and chain.relationship.breadcrumb
        or nil

    if isFirstStep then
        return {
            requiredLevel        = chain.range and chain.range.min or nil,
            requiredMaxLevel     = chain.range and chain.range.max or nil,
            nextQuestInChain     = nextInChain,
            breadcrumbForQuestId = breadcrumb,
            -- preQuestGroup/preQuestSingle: BtWQuests prerequisites[] are chain-level
            -- and not mappable to AQL's per-quest contract. Omitted.
        }
    else
        -- breadcrumb is structurally always nil for non-first steps: only the first
        -- step can be a breadcrumb entry point (isFirstStep=false forces breadcrumb=nil
        -- above). The guard below effectively reduces to `if not nextInChain then`.
        -- Written in full for symmetry with the first-step path.
        if not nextInChain and not breadcrumb then return nil end
        return {
            nextQuestInChain     = nextInChain,
            breadcrumbForQuestId = breadcrumb,
        }
    end
end
```

### `GetQuestFaction(questID)`

**Faction restriction encoding (confirmed from BtWQuests source):** `chain.restrictions` is an array. Faction is encoded as either numeric condition IDs (923 = Horde, 924 = Alliance) or table entries of the form `{type="faction", id="Horde"}` / `{type="faction", id="Alliance"}`. Both formats appear in BtWQuests data. The implementation iterates the restrictions array and checks for either form:

```lua
local HORDE_CONDITION    = 923
local ALLIANCE_CONDITION = 924

local function decodeFaction(restrictions)
    if type(restrictions) ~= "table" then return nil end
    for _, r in ipairs(restrictions) do
        if r == HORDE_CONDITION then return AQL.Faction.Horde end
        if r == ALLIANCE_CONDITION then return AQL.Faction.Alliance end
        if type(r) == "table" and r.type == "faction" then
            if r.id == "Horde"    then return AQL.Faction.Horde    end
            if r.id == "Alliance" then return AQL.Faction.Alliance end
        end
    end
    return nil
end

function BtWQuestsProvider:GetQuestFaction(questID)
    local chainKey = findChainKey(questID)
    if not chainKey then return nil end
    local chain = BtWQuests.Database.Chains[chainKey]
    if not chain then return nil end
    return decodeFaction(chain.restrictions)
end
```

### `GetQuestType(questID)`

Returns nil — BtWQuests has no quest type data (elite/dungeon/raid/daily).

```lua
function BtWQuestsProvider:GetQuestType(questID) return nil end
```

### `GetQuestBasicInfo(questID)`

Not implemented. BtWQuests stores no per-quest title, level, or zone. Per the provider interface contract, `GetQuestBasicInfo` is optional and checked with `if provider.GetQuestBasicInfo then` before calling — omitting it entirely is correct.

---

## `AQL.Provider.BtWQuests`

Add `BtWQuests = "BtWQuests"` to the existing `AQL.Provider` enum in `AbsoluteQuestLog.lua`. The existing `None = "none"` key (capital N) must not be changed:

```lua
AQL.Provider = {
    Questie     = "Questie",
    QuestWeaver = "QuestWeaver",
    BtWQuests   = "BtWQuests",   -- add this line
    None        = "none",        -- existing key — do not rename
}
```

---

## Out of Scope

- `GrailProvider` implementation (Phase 3)
- Any changes to `WowQuestAPI.lua`
- Any changes to `QuestCache.lua`
