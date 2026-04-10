# AQL GrailProvider + ChainInfo Contract Redesign
**Date:** 2026-03-30
**Version target:** 3.0.0 (major bump — breaking API change)

---

## Overview

This spec covers two tightly coupled deliverables:

1. **GrailProvider** — a new provider covering all three AQL capabilities (Chain, QuestInfo, Requirements) backed by the Grail addon (Grail-123 for Classic/TBC/Wrath, Grail-124 for Retail/TWW).
2. **ChainInfo contract redesign** — `GetChainInfo` is changed to return a structured wrapper object that supports multiple chains per quest, multi-quest steps within a chain, and a standardized `SelectBestChain` utility. This is a **breaking change** requiring a major version bump to 3.0.0.

---

## Breaking Change Summary

> **BREAKING (3.0.0):** `AQL:GetChainInfo(questID)` no longer returns a bare `ChainInfo` table. It now returns a wrapper object `{ knownStatus, chains }`. All callers must update. See Migration section.

---

## Scope of Changes

| # | Area | Type |
|---|------|------|
| 1 | `ChainInfo` wrapper structure | Breaking change |
| 2 | Multi-quest step format inside chains | New feature |
| 3 | `AQL:SelectBestChain(chains, engagedQuestIDs)` | New public API |
| 4 | `AQL.QuestType.Weekly = "weekly"` | Additive |
| 5 | `AQL.Provider.Grail = "Grail"` | Additive |
| 6 | `GrailProvider.lua` | New file |
| 7 | Existing providers wrap return in new structure | Mechanical update |
| 8 | `QuestCache`, `AbsoluteQuestLog.lua` internal updates | Mechanical update |
| 9 | EventEngine priority lists updated | Additive |
| 10 | SocialQuest callsite updates | Mechanical update |
| 11 | `README.md`, `README.txt` updated | Docs |
| 12 | `CLAUDE.md` updated | Docs |
| 13 | `changelog.txt` — breaking change callout | Docs |

---

## 1. ChainInfo Wrapper Structure

### 1.1 New return shape for `GetChainInfo`

`GetChainInfo(questID)` always returns a wrapper table. Never returns nil.

```lua
-- Quest not part of any chain (provider explicitly knows this):
{ knownStatus = "not_a_chain" }

-- No provider could determine chain membership:
{ knownStatus = "unknown" }

-- Chain data found (one or more chains):
{
    knownStatus = "known",
    chains = {
        {
            chainID    = N,        -- questID of chain root (first step)
            step       = N,        -- 1-based step-position of the queried quest
            length     = N,        -- total step-positions (a group counts as 1)
            questCount = N,        -- total individual quests across all steps
            steps      = { ... }, -- see section 1.2
            provider   = "Grail"|"Questie"|"QuestWeaver"|"BtWQuests"|"none",
        },
        -- second entry only when quest belongs to multiple distinct chains
    }
}
```

`knownStatus` is a property of the lookup result, not of individual chain entries. When status is `"known"`, all entries in `chains` are fully populated chain data. Mixed-status arrays never occur.

### 1.2 Step format within a chain

Steps are duck-typed — no explicit `stepType` field needed.

**Single-quest step** (the common case, unchanged fields):
```lua
{ questID = N, title = "string", status = "completed"|"active"|"finished"|"failed"|"available"|"unavailable"|"unknown" }
```

**Multi-quest step** (new — parallel group or branch):
```lua
{
    quests = {
        { questID = N, title = "string", status = "..." },
        { questID = M, title = "string", status = "..." },
    },
    groupType = "parallel",  -- do all (no I: exclusivity codes between members)
                             -- "branch"  (I: codes confirm mutual exclusion)
                             -- "unknown" (relationship cannot be determined)
}
```

Consumers distinguish step types by checking for the `quests` field:
```lua
if step.questID then
    -- single-quest step
elseif step.quests then
    -- multi-quest step
end
```

### 1.3 Migration for existing callers

```lua
-- Before (2.x):
local ci = AQL:GetChainInfo(questID)
if ci.knownStatus == AQL.ChainStatus.Known then
    show(ci.step, ci.length)
end

-- After (3.0):
local result = AQL:GetChainInfo(questID)
if result.knownStatus == AQL.ChainStatus.Known then
    local ci = result.chains[1]   -- or SelectBestChain for cross-player use
    show(ci.step, ci.length)
end
```

`QuestInfo.chainInfo` on cache entries now holds the wrapper object (not a bare ChainInfo).

---

## 2. New and Updated Public API

### 2.1 `AQL:SelectBestChain(chainResult, engagedQuestIDs)` — new

Player-agnostic best-chain selector. Scores chains by counting how many of their member quests appear in the provided engaged set. Returns the highest-scoring chain entry, or `nil` if `chainResult.knownStatus ~= "known"`.

```lua
-- chainResult:      return value of AQL:GetChainInfo(questID)
-- engagedQuestIDs:  { [questID] = true } — set of completed/active quests for the target player
-- returns:          single chain table ({ chainID, step, length, questCount, steps, provider })
--                   or nil

local chain = AQL:SelectBestChain(result, engagedSet)
```

**Cache:** Results are memoized by `(chainID, fingerprint)` where fingerprint is a `count:xor:sum` composite of the engaged set. Cache is cleared on any quest state change (`QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`). Callers with different engaged sets get independent cache entries.

**For current player:**
```lua
local result  = AQL:GetChainInfo(questID)
local engaged = AQL:_GetCurrentPlayerEngagedQuests()  -- private: HistoryCache + active QuestCache
local chain   = AQL:SelectBestChain(result, engaged)
```

**For party member (SocialQuest):**
```lua
local result  = AQL:GetChainInfo(questID)
local chain   = AQL:SelectBestChain(result, memberCompletedQuestIDs)
```

### 2.2 `AQL:GetChainStep(questID)` — updated

Returns `step` from the best-fit chain for the current player, or nil.
Uses `SelectBestChain` + `_GetCurrentPlayerEngagedQuests` internally.

### 2.3 `AQL:GetChainLength(questID)` — updated

Returns `length` from the best-fit chain for the current player, or nil.

### 2.4 `AQL.QuestType.Weekly = "weekly"` — new

Grail exposes `IsWeekly()`. Added to the `AQL.QuestType` enum. Returned by `GrailProvider:GetQuestType()` and documented in the public API. Additive — no existing callers affected.

### 2.5 `AQL.Provider.Grail = "Grail"` — new

Enum entry for the provider field on chain entries.

---

## 3. GrailProvider

**File:** `Providers/GrailProvider.lua`
**Capabilities:** Chain, QuestInfo, Requirements

### 3.1 Detection

```lua
-- IsAvailable(): lightweight presence check
return _G["Grail"] ~= nil
    and type(Grail.questCodes) == "table"
    and type(Grail.questPrerequisites) == "table"

-- Validate(): database has loaded
return next(Grail.questCodes) ~= nil
```

Grail initializes synchronously (unlike Questie), so a non-empty `questCodes` at `PLAYER_LOGIN` means it is ready. No deferred retry needed.

### 3.2 `GetQuestBasicInfo(questID)`

```lua
{
    title         = Grail:QuestName(questID),
    questLevel    = Grail:QuestLevel(questID),
    requiredLevel = Grail:QuestLevelRequired(questID),
    zone          = resolveZone(questID),
}
```

**Zone resolution:** Call `Grail:QuestLocationsAccept(questID)`. Take the first location record's `mapArea` field. Call `WowQuestAPI.GetAreaInfo(mapArea)` for the zone name string. Return nil if no location records exist.

### 3.3 `GetQuestType(questID)`

Priority order (a quest is classified by the first match):

| Grail API | AQL type |
|-----------|----------|
| `Grail:IsRaid(questID)` | `"raid"` |
| `Grail:IsDungeon(questID)` | `"dungeon"` |
| `Grail:IsEscort(questID)` | `"escort"` |
| `Grail:IsGroup(questID)` | `"elite"` |
| `Grail:IsPVP(questID)` | `"pvp"` |
| `Grail:IsWeekly(questID)` | `"weekly"` |
| `Grail:IsDaily(questID)` | `"daily"` |
| none match | `nil` (normal quest) |

### 3.4 `GetQuestFaction(questID)`

Parse the raw `Grail.questCodes[questID]` string for faction tokens using plain-text search:

```lua
local code = Grail.questCodes[questID]
if not code then return nil end
if strfind(code, "FA", 1, true) then return AQL.Faction.Alliance end
if strfind(code, "FH", 1, true) then return AQL.Faction.Horde end
return nil
```

Note: lowercase `fA`/`fH` tokens exist in Grail data (forced faction on otherwise neutral quests). The search is case-sensitive; `FA`/`FH` covers the primary cases. A follow-up pass for `fA`/`fH` can be added if gaps are found in practice.

### 3.5 `GetQuestRequirements(questID)`

```lua
{
    requiredLevel        = Grail:QuestLevelRequired(questID),
    requiredMaxLevel     = orNil(Grail:QuestLevelVariableMax(questID)),  -- 0 → nil
    preQuestGroup        = parseAndPrereqs(prereqPattern),    -- P:A+B → { A, B }
    preQuestSingle       = parseOrPrereqs(prereqPattern),     -- P:A,B → { A, B }
    exclusiveTo          = parseExclusiveTo(questID),         -- I: codes
    breadcrumbForQuestId = parseOptionalFirst(questID),       -- first O: code entry
    nextQuestInChain     = nil,                               -- not derivable here
    requiredRaces        = nil,                               -- omitted (letter codes, not bitmask)
    requiredClasses      = nil,                               -- omitted (letter codes, not bitmask)
}
```

`prereqPattern` is `Grail.questPrerequisites[questID]` — the raw P: code string with prefix stripped.

Parsing helpers extract only plain-numeric tokens (no letter prefix). Letter-prefixed tokens (world quest `a`, threat `b`, calling `^`, profession `P`, reputation `T`, etc.) are not quest-chain prerequisites and are skipped.

Race/class bitmask mapping is deferred — Grail uses single-letter codes rather than bitmasks, and the mapping table is non-trivial. Fields return nil initially and can be added in a follow-up.

### 3.6 `GetChainInfo(questID)` — chain reconstruction

#### Reverse-map build (lazy, once)

On first call to `GetChainInfo`, scan `Grail.questPrerequisites` once to build:

```lua
reverseMap[prereqID] = { questID1, questID2, ... }
```

Only plain-numeric tokens are chain links. Letter-prefixed tokens are skipped (see §3.5 parsing note). After the scan, `reverseMapBuilt = true` — subsequent calls skip the scan.

#### Chain reconstruction

**Step 1 — Find roots (walk backward)**

From the queried quest, follow `questPrerequisites` backward. A root is a quest with no plain-numeric prerequisites. A `visited` table guards against cycles. Multiple roots indicate the queried quest is reachable from multiple independent starting points (distinct chains).

**Step 2 — Walk forward from each root**

For each root, walk forward using `reverseMap`. At each step:
- **Single successor:** linear step, continue.
- **Multiple successors, mutually exclusive** (each has I: codes pointing at the others): `groupType = "branch"` multi-quest step.
- **Multiple successors, no exclusivity:** `groupType = "parallel"` multi-quest step.
- **Multiple successors leading to divergent paths:** collect the full forward set of questIDs reachable from each successor. If the two sets share no questIDs (no downstream convergence), the paths are truly independent chains — stop the current chain here and start a separate chain entry per divergent path. If they share descendants (they reconverge later), treat as a branch/parallel group and continue as one chain.

**Limits:**
- Cycle guard: `visited` table prevents infinite loops.
- Depth cap: 50 step-positions maximum. Returns partial chain with whatever was built. Protects against malformed data.

**Step 3 — Classify step status**

For each quest in each step (in order of precedence):

| Condition | Status |
|-----------|--------|
| `AQL.HistoryCache:Has(questID)` | `"completed"` |
| `QuestCache:Get(questID).isFailed` | `"failed"` |
| `QuestCache:Get(questID).isComplete` | `"finished"` |
| `QuestCache:Get(questID)` exists | `"active"` |
| All prerequisites completed | `"available"` |
| Prerequisites not met | `"unavailable"` |
| Cannot determine | `"unknown"` |

**Step 4 — Compute step/length/questCount**

Walk the steps array to find the entry containing the queried questID. Its 1-based index is `step`. `length = #steps`. `questCount` = total individual questIDs across all step entries.

**Return value:**

```lua
-- Quest not found in any chain:
{ knownStatus = "not_a_chain" }

-- One or more chains found:
{
    knownStatus = "known",
    chains = { chain1, chain2, ... }   -- one per distinct root
}
```

---

## 4. Existing Provider Updates

All four existing providers (`QuestieProvider`, `QuestWeaverProvider`, `BtWQuestsProvider`, `NullProvider`) change their `GetChainInfo` return from a bare ChainInfo to the new wrapper:

```lua
-- QuestieProvider / QuestWeaverProvider / BtWQuestsProvider:
-- Last line of GetChainInfo changes from:
return chainInfo
-- to:
return { knownStatus = AQL.ChainStatus.Known, chains = { chainInfo } }

-- not_a_chain cases:
return { knownStatus = AQL.ChainStatus.NotAChain }

-- NullProvider:
return { knownStatus = AQL.ChainStatus.Unknown }
```

These are mechanical one-line changes per provider.

---

## 5. EventEngine Priority Lists

```lua
[AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
[AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
[AQL.Capability.Requirements] = { AQL.QuestieProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
```

Version filtering is automatic — each provider's `IsAvailable()` returns false for unsupported versions, so the priority order handles all versions from a single list:

| Version | Effective Chain order |
|---------|----------------------|
| Classic Era | Questie → QuestWeaver → *(BtWQuests skipped)* → Grail |
| TBC | Questie → QuestWeaver → *(BtWQuests skipped)* → Grail |
| MoP | Questie → *(QuestWeaver skipped)* → BtWQuests → Grail |
| Retail | *(Questie skipped)* → *(QuestWeaver skipped)* → BtWQuests → Grail |

---

## 6. QuestCache and AbsoluteQuestLog.lua Updates

### QuestCache

`_buildEntry` fallback changes from:
```lua
local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
```
to:
```lua
local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }   -- same shape, now a wrapper
```
No change needed — the wrapper and the old bare structure share the same `knownStatus` field. The difference is the absence of `chains` when unknown, which consumers already guard with `knownStatus` checks.

The `chainInfo` field on the `QuestInfo` entry now holds the wrapper object.

### AbsoluteQuestLog.lua

`GetChainInfo` fallback:
```lua
return { knownStatus = AQL.ChainStatus.Unknown }
```

`GetChainStep` / `GetChainLength`:
```lua
function AQL:GetChainStep(questID)
    local r = self:GetChainInfo(questID)
    if r.knownStatus ~= AQL.ChainStatus.Known then return nil end
    local engaged = self:_GetCurrentPlayerEngagedQuests()
    local chain = self:SelectBestChain(r, engaged)
    return chain and chain.step or nil
end

function AQL:GetChainLength(questID)
    local r = self:GetChainInfo(questID)
    if r.knownStatus ~= AQL.ChainStatus.Known then return nil end
    local engaged = self:_GetCurrentPlayerEngagedQuests()
    local chain = self:SelectBestChain(r, engaged)
    return chain and chain.length or nil
end
```

`_GetCurrentPlayerEngagedQuests()` (private method on AQL, defined in `AbsoluteQuestLog.lua`):
```lua
-- Merges HistoryCache (all completed) with active QuestCache (questIDs of in-log quests)
-- Returns { [questID] = true }
```

`SelectBestChain` and its cache live in `AbsoluteQuestLog.lua` as a private local table (`local selectionCache = {}`). EventEngine clears it by calling `AQL:_ClearChainSelectionCache()` (private) on `QUEST_ACCEPTED`, `QUEST_REMOVED`, and `QUEST_TURNED_IN`.

---

## 7. SocialQuest Updates

All callsites follow the same migration pattern:

```lua
-- Before:
local ci = questInfo.chainInfo
if ci and ci.knownStatus == AQL.ChainStatus.Known then
    show(ci.step, ci.length)
end

-- After:
local result = questInfo.chainInfo
if result and result.knownStatus == AQL.ChainStatus.Known then
    local ci = AQL:SelectBestChain(result, currentPlayerEngaged)
    if ci then
        show(ci.step, ci.length)
    end
end
```

For cross-player chain selection (party member quests), `TabUtils.GetChainInfoForQuestID` passes the member's engaged set to `SelectBestChain` instead of the current player's.

Filter expressions (`entry.chainInfo and entry.chainInfo.step`) update to use the `SelectBestChain` result:
```lua
-- Before:
entry.chainInfo and entry.chainInfo.step
-- After:
entry.chainInfo and entry.chainInfo.knownStatus == AQL.ChainStatus.Known
    and AQL:SelectBestChain(entry.chainInfo, currentPlayerEngaged)
    and AQL:SelectBestChain(entry.chainInfo, currentPlayerEngaged).step
```
Note: callers that invoke `SelectBestChain` multiple times on the same input hit the cache on the second call — no performance concern.

---

## 8. Documentation Updates

### README.md / README.txt
- Document new `GetChainInfo` return shape with migration example
- Document `SelectBestChain` with both current-player and cross-player examples
- Document `"weekly"` quest type
- **Breaking change section at top of 3.0.0 release notes**

### CLAUDE.md
- Update ChainInfo data structure section with new wrapper format and multi-quest step format
- Update Provider Interface section with new `GetChainInfo` return contract
- Update Version History with 3.0.0 entry including breaking change callout

### changelog.txt
- 3.0.0 entry with `## Breaking Changes` section at top

---

## 9. Version

Target version on completion: **3.0.0**

Overrides the normal daily versioning rule. The major version bump reflects the breaking change to `GetChainInfo`. changelog.txt and CLAUDE.md version history updated accordingly with a `## Breaking Changes` subsection clearly listing:
- `GetChainInfo` return type change
- `QuestInfo.chainInfo` field type change
- Migration path for both
