# Grail Variant Chain — Implementation Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix GrailProvider to correctly represent Retail WoW quest chains where each step has multiple class/race variant quest IDs, producing a single unified chain for all variants and the correct 5-step length instead of stopping at step 2.

**Architecture:** Variant root groups are detected at reverse-map build time. Chain building walks all variant members simultaneously at each step, using a majority-vote filter to discard side-branch successors. AQL's public `GetChainInfo` gains a provider-fallthrough tier so remote (uncached) quest IDs also resolve correctly. SocialQuest tab patches become unnecessary and are removed.

**Affected repositories:**
- `AbsoluteQuestLog` — GrailProvider.lua, AbsoluteQuestLog.lua
- `Social-Quest` — UI/TabUtils.lua, UI/Tabs/PartyTab.lua, UI/Tabs/SharedTab.lua

---

## Background and Root Cause

On Retail WoW, every quest in a chain has one variant quest ID per class (and sometimes per race). For example, "Beating Them Back!" has 9 variant IDs (28757, 28762–28767, 29078, 31139) — one per class — all with the same name, zone, and accept NPC, but no cross-references between them in Grail's data. Each step in the 5-step chain follows this pattern.

**Problem 1 — Multiple roots, multiple chains:** Each variant root has no numeric prerequisites, so GrailProvider's `findRoots` returns each variant as its own independent root. `buildChainFromRoot(28766)` produces `chainID=28766` and `buildChainFromRoot(28763)` produces `chainID=28763`. Two players on the same logical chain get different `chainID` values and are never grouped together in the SocialQuest tabs.

**Problem 2 — Chain terminates at step 2:** At every step, each variant's linear chain has one "true continuation" successor (e.g. 28789 "Join the Battle!") AND one class-specific letter quest side branch (e.g. 3100 "Simple Letter", 3104 "Glyphic Letter", etc.). These letter quests have different names from the main continuation and from each other. The current divergence check in `buildChainFromRoot` sees two non-converging, different-named successors and executes `break -- genuinely divergent paths`, terminating the chain at step 2 instead of continuing to the full 5 steps.

**Problem 3 — AQL:GetChainInfo misses remote quests:** `AQL:GetChainInfo` only reads `QuestCache`, which only contains the local player's active quests. A remote party member's variant quest ID (not in the local log) always returns `Unknown`, causing SocialQuest to route it to the standalone quest bucket instead of the chain bucket.

---

## Data Structure: Variant Groups

Two new tables are built once inside `buildReverseMap`, after the existing prereq traversal completes:

```lua
-- variantGroups[canonicalID] = { id1, id2, id3, ... }
-- All root quest IDs (no numeric prereqs) that share the same name + zone.
-- canonicalID = numerically smallest member of the group.
local variantGroups = {}

-- variantOf[questID] = canonicalID
-- Reverse lookup: maps any non-canonical variant root to its canonical ID.
local variantOf = {}
```

A quest ID qualifies as a **variant root** if `g.questPrerequisites[questID]` is nil or contains no plain-numeric tokens (i.e. `parsePlainNumericTokens` returns empty). Two variant roots belong to the same group if they share the same quest name (via `g:QuestName`) AND the same zone (via `g:MapAreaName(g:QuestLocationsAccept(id)[1].mapArea)`), with a zone-unavailable fallback to name-only matching when either zone is nil.

---

## Core Algorithm: `buildVariantChain(canonicalID)`

Replaces `buildChainFromRoot` for all chains that have a variant group of size ≥ 1. (For size-1 groups, it degrades to identical behavior.)

```
Input:  canonicalID — the smallest root ID of the variant group
Output: steps array, questCount  (same format as buildChainFromRoot)

1. currentWave = variantGroups[canonicalID]   -- all root variants
2. visited = set of all IDs in currentWave
3. While currentWave is non-empty and steps < MAX_CHAIN_DEPTH:
   a. Record current wave as one step:
      - If #currentWave == 1: single-quest step { questID, title, status }
      - If #currentWave > 1:  group step { quests=[...], groupType="parallel" }
   b. Collect all successors of every ID in currentWave (from reverseMap),
      excluding already-visited IDs.
   c. Group collected successors by (name, zone) pair.
   d. Majority-vote filter: keep only the (name, zone) group whose member count
      is > (#currentWave / 2). All other groups are side branches — discard them.
      (If no group passes the threshold, break — chain has ended.)
   e. currentWave = the surviving group's member IDs
   f. Mark all as visited
4. Return steps, questCount
```

The majority-vote threshold `> N/2` handles the letter-quest side branches: "Join the Battle!" appears once per variant (6/6 pass), while each letter quest appears once total (1/6 fail). Even if Grail data is incomplete and some variants are missing, the threshold adapts to the actual variant count at each step.

---

## `GetChainInfo` Integration

`GrailProvider:GetChainInfo(questID)` updated logic:

```
1. Call buildReverseMap() as before (now also populates variantGroups/variantOf).
2. Determine canonical:
   - If variantOf[questID] exists  → canonical = variantOf[questID]
   - Else if variantGroups[questID] exists → canonical = questID (it IS canonical)
   - Else → canonical = nil (not a variant root)
3. If canonical is not nil:
   - Build (or retrieve cached) chain via buildVariantChain(canonical)
   - Find questID's step: walk steps array, check step.questID and step.quests[*].questID
   - Return { knownStatus=Known, chains=[{ chainID=canonical, step=N, length=M, steps=..., ... }] }
4. Else: fall through to existing hasPrereqs/hasSuccessors logic (unchanged for
   mid-chain quests, non-variant chains, and TBC/Classic chains).
```

**Chain caching:** `buildVariantChain` results are cached in a `variantChainCache[canonicalID]` table. Subsequent `GetChainInfo` calls for any variant of the same chain return the cached result. Cache is never invalidated (Grail data is static per session).

**Mid-chain variant lookup:** When `GetChainInfo` is called for a mid-chain variant (e.g. 28771, Rogue "Lions for Lambs") that is not a root:
- It has prerequisites → falls through to existing `hasPrereqs` path
- `findRoots` walks back to a root variant (e.g. 28763)
- `variantOf[28763]` → canonical 28757
- `buildVariantChain(28757)` builds/returns the full chain
- Step detection finds 28771 inside the step-2 group → step=2
- Returns correct result.

---

## `AQL:GetChainInfo` Provider Fallthrough (AbsoluteQuestLog.lua)

Current implementation (reads cache only):
```lua
function AQL:GetChainInfo(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.chainInfo then return q.chainInfo end
    return { knownStatus = AQL.ChainStatus.Unknown }
end
```

New implementation (tier-2 provider fallthrough):
```lua
function AQL:GetChainInfo(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.chainInfo and q.chainInfo.knownStatus == AQL.ChainStatus.Known then
        return q.chainInfo
    end
    local provider = self.providers and self.providers[self.Capability.Chain]
    if provider then
        local ok, result = pcall(provider.GetChainInfo, provider, questID)
        if ok and result and result.knownStatus == AQL.ChainStatus.Known then
            return result
        end
    end
    return (q and q.chainInfo) or { knownStatus = AQL.ChainStatus.Unknown }
end
```

The `pcall` guard is consistent with how EventEngine calls providers. Cached results are still preferred when Known — the provider is only consulted when the cache has no Known answer (covers remote quest IDs, and quests not yet in the log).

---

## SocialQuest Cleanup (Social-Quest repository)

**`UI/TabUtils.lua`:** Remove `GetChainInfoForQuestID`. Replace all call sites with direct `AQL:GetChainInfo(questID)` calls. `AQL:GetChainInfo` now handles all cases correctly.

**`UI/Tabs/PartyTab.lua`:** Remove the title+zone merge block in `BuildTree` (lines 326–341 in 2.17.8). Replace it with step-number deduplication. A `chainStepEntries` table (local to `BuildTree`) maps `chainID → stepNum → entry`, making lookup O(1):

```lua
local chainStepEntries = {}   -- [chainID][stepNum] = existing entry

-- After resolving ciEntry for the questID:
if ciEntry and ciEntry.chainID then
    local chainID = ciEntry.chainID
    local stepNum = ciEntry.step
    if not zone.chains[chainID] then
        zone.chains[chainID] = { title = entry.title, steps = {} }
    end
    if ciEntry.step == 1 then zone.chains[chainID].title = entry.title end

    if not chainStepEntries[chainID] then chainStepEntries[chainID] = {} end
    local existing = chainStepEntries[chainID][stepNum]
    if existing then
        -- Variant questID for an already-recorded step: merge players only.
        for _, p in ipairs(entry.players) do
            table.insert(existing.players, p)
        end
    else
        -- First questID seen at this step: record and insert.
        chainStepEntries[chainID][stepNum] = entry
        table.insert(zone.chains[chainID].steps, entry)
    end
end
```

This is semantically correct and simpler than the title+zone heuristic: two questIDs belonging to the same logical step always produce the same `(chainID, step)` pair from AQL, so the dedup key is unambiguous.

**`UI/Tabs/SharedTab.lua`:** Apply the same step-number deduplication in the chain processing section (line 168 area). SharedTab currently has no deduplication at all for variants — this fixes it cleanly.

**Version bumps:** AQL bumps per versioning rule (minor increment + revision reset if first change of the day, otherwise revision increment). The `GetChainInfo` behavior change for uncached quest IDs is a notable API improvement — note it in AQL's changelog and CLAUDE.md. SocialQuest bumps per its own versioning rule on the day of the change.

---

## Testing Checklist

**Unit tests (Lua, no WoW required):**
- [ ] Variant group detection correctly groups 28757/28762/28763/28764/28765/28766/28767 under canonical 28757
- [ ] `buildVariantChain(28757)` produces 5 steps, each a group step with all class variants
- [ ] Majority-vote filter discards the letter quest side branches at step 3
- [ ] Single-root chains (any TBC chain) produce identical output to old `buildChainFromRoot`

**In-game live tests:**
- [ ] `/run` — `AQL:GetChainInfo(28763).knownStatus` → "known"
- [ ] `/run` — `AQL:GetChainInfo(28766).knownStatus` → "known"
- [ ] Both return same `chainID` value
- [ ] Both return `step=1`, `length=5`
- [ ] `/run` — `AQL:GetChainInfo(28774).step` → 2
- [ ] Party tab: two players on 28763 and 28766 appear as ONE entry under ONE chain header
- [ ] Shared tab: same result
- [ ] Known TBC chain quest (e.g. a Questie chain) still resolves correctly — regression check

---

## What Does NOT Change

- `GrailProvider:GetQuestBasicInfo`, `GetQuestType`, `GetQuestFaction`, `GetQuestRequirements` — untouched
- All non-Grail providers (Questie, QuestWeaver, BtWQuests, NullProvider) — untouched
- AQL callbacks, EventEngine, QuestCache, HistoryCache — untouched
- SocialQuest communication protocol, GroupData, Announcements — untouched
