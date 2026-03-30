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
3. Iterate `BtWQuests.Database.Chains`, skipping keys in `_scannedChains`. Skip any entry whose value is not a table (guards against non-chain metadata stored at the top level of the Chains table). For each unscanned chain, extract all questIDs from `items[]` into `_questToChain`, mark chain as scanned. Stop as soon as `_questToChain[questID]` is populated.
4. If all chains exhausted without finding questID, set `_fullyIndexed = true`, return nil.

The index is built incrementally on demand. A questID in an early-accessed chain is found after scanning only a small portion of the database. The full index is never built unless the player looks up quests across many unrelated chains.

---

## Step Extraction

```lua
local function extractQuestIDs(items)
    local result = {}
    for _, item in ipairs(items) do
        if item.type == "quest" then
            if item.id then
                table.insert(result, { questID = item.id })
            elseif item.ids then
                for _, qid in ipairs(item.ids) do
                    table.insert(result, { questID = qid })
                end
            end
        end
        -- non-quest items (type="npc", type="event", etc.) silently skipped
    end
    return result
end
```

**⚠ VERIFY BEFORE IMPLEMENTATION — `.ids` semantics — DO NOT IMPLEMENT until confirmed:**

The meaning of `.ids` on a step entry must be confirmed against BtWQuests source before writing any code that touches multi-ID steps. Two possibilities with different implementations:

- **Faction/version variants** (more likely): `ids` = multiple questIDs that are alternative versions of the same logical step (e.g. Alliance vs. Horde variants, or a quest updated in a patch). Each `items[]` entry is one step position. `extractQuestIDs` must treat each entry as one step and match the player's questID against any ID in the set. Flattening inflates chain length and produces wrong step numbers.
- **True parallel branches:** `ids` = quests that can be completed in any order. Flattening into separate entries may be correct.

The code sample above flattens `.ids` as a placeholder only. It is likely wrong for the faction-variant case and **must be revised** once semantics are confirmed. Do not copy this code without first verifying.

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

    local steps = extractQuestIDs(chain.items)
    -- A BtWQuests chain that yields fewer than 2 quest steps after filtering non-quest
    -- items (e.g. a chain composed entirely of NPC steps plus one quest) is treated as
    -- NotAChain. The questID remains in _questToChain so findChainKey still returns
    -- the chainKey on future calls — this is intentional, no caching of the extracted
    -- steps is needed for this path since the guard is cheap.
    if #steps < 2 then
        return { knownStatus = AQL.ChainStatus.NotAChain }
    end

    local aqlChainID = steps[1].questID

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

**`stepNum` nil note:** With the flattening approach, every questID indexed in `_questToChain` also appears in `steps`, so `stepNum` should always be found for `.id` entries. For `.ids` entries, `stepNum` correctness depends on the resolved `.ids` semantics — another reason not to implement before confirming. `step = nil` in the ChainInfo return is technically valid (consumers must nil-check it) but should not occur in normal operation.

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

```lua
function BtWQuestsProvider:GetQuestFaction(questID)
    local chainKey = findChainKey(questID)
    if not chainKey then return nil end
    local chain = BtWQuests.Database.Chains[chainKey]
    if not chain or not chain.restrictions then return nil end
    if chain.restrictions == HORDE_RESTRICTIONS    then return AQL.Faction.Horde    end
    if chain.restrictions == ALLIANCE_RESTRICTIONS then return AQL.Faction.Alliance end
    return nil
end
```

**⚠ VERIFY BEFORE IMPLEMENTATION — `HORDE_RESTRICTIONS` / `ALLIANCE_RESTRICTIONS`:** The type, origin, and exact values of these constants must be confirmed from BtWQuests source before implementing. They may be BtWQuests-defined globals, Blizzard globals, numeric IDs, or string keys. If they are not globals (e.g. module-local constants), the comparison approach above must be revised.

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
