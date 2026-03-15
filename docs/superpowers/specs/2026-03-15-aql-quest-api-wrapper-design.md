# AQL Quest API Wrapper Design

**Date:** 2026-03-15
**Status:** Approved

---

## Overview

Introduce a two-layer abstraction so that (a) all raw WoW quest API calls are centralized in one file for easy version-branching and (b) callers of AQL never touch WoW globals directly.

**Goal:** All WoW quest API calls live in `Core\WowQuestAPI.lua`. AQL exposes new public methods that delegate to `WowQuestAPI`. Social Quest (and any other consumer) calls only AQL or WowQuestAPI — never WoW globals.

---

## Section 1: WowQuestAPI.lua

### Location

`Core\WowQuestAPI.lua` — listed in the TOC before any AQL file that uses it.

### Namespace Creation

```lua
WowQuestAPI = WowQuestAPI or {}
```

Plain global table. No LibStub, no AceAddon, no `:OnEnable`.

### Purpose

Stateless, thin wrappers around WoW globals. No caching, no addon state, no event handling. If Classic Era or Retail support is added later, only this file changes.

### API Surface

#### `WowQuestAPI.GetQuestInfo(questID)`

Returns a minimal table with only the fields that can be derived from a single `C_QuestLog.GetQuestInfo` call **without** requiring a log-index selection or additional queries. On TBC 20505, `C_QuestLog.GetQuestInfo(questID)` returns just a title string.

```lua
-- TBC implementation:
-- C_QuestLog.GetQuestInfo(questID) → title string or nil
-- Returns { questID = questID, title = title } or nil (if title is nil)
WowQuestAPI.GetQuestInfo(questID)  --> { questID = questID, title = title } | nil

-- Retail implementation:
-- C_QuestLog.GetQuestInfo(questID) → info table with .title field
-- Returns { questID = questID, title = info.title } or nil (if info is nil)
```

This is a **title-lookup fallback** for quests not in the local log (e.g., a quest mentioned by a party member). Callers that need the full snapshot (level, zone, objectives, timerSeconds, etc.) must use the AQL cache via `AQL:GetQuestInfo`.

#### `WowQuestAPI.GetQuestObjectives(questID)`

Wraps `C_QuestLog.GetQuestObjectives(questID)`. Returns the raw objectives array for an active quest by questID. This is a thin pass-through — field names match the WoW API exactly. On TBC 20505 each entry contains: `{ text, type, finished, numFulfilled, numRequired }`. Returns an empty table if the quest is not in the log.

Note: The AQL cache normalizes these fields (e.g., `isFinished` instead of `finished`). `WowQuestAPI.GetQuestObjectives` returns raw/unnormalized data; callers that need the normalized form should use the AQL cache (`AQL:GetQuestObjectives`) which applies the normalization.

```lua
WowQuestAPI.GetQuestObjectives(questID)  --> table (may be empty)
```

#### `WowQuestAPI.IsQuestFlaggedCompleted(questID)`

```lua
-- TBC/TBC-Anniversary:
WowQuestAPI.IsQuestFlaggedCompleted(questID)
  --> C_QuestLog.IsQuestFlaggedCompleted(questID)  -- bool

-- Classic Era (future stub):
WowQuestAPI.IsQuestFlaggedCompleted(questID)
  --> IsQuestFlaggedCompleted(questID)  -- legacy global
```

#### `WowQuestAPI.GetQuestLogIndex(questID)`

Scans the quest log to find the 1-based log index for the given questID. Returns nil if the quest is not in the player's log.

```lua
WowQuestAPI.GetQuestLogIndex(questID)  --> number | nil
```

Underlying: iterates `GetNumQuestLogEntries()`, calling `GetQuestLogTitle(i)` for each entry and matching on the 8th return value of `GetQuestLogTitle`, which is the questID. Do not use `SelectQuestLogEntry`/`GetQuestID` — that approach has side-effects.

#### `WowQuestAPI.TrackQuest(questID)` / `WowQuestAPI.UntrackQuest(questID)`

Resolve questID to log index, then call the TBC tracking globals. These are thin wrappers — no watch-count enforcement.

```lua
-- TBC underlying APIs:
--   AddQuestWatch(logIndex)    -- adds timer/tracker
--   RemoveQuestWatch(logIndex) -- removes
-- No-op if questID is not in the log.
WowQuestAPI.TrackQuest(questID)    --> void
WowQuestAPI.UntrackQuest(questID)  --> void
```

#### `WowQuestAPI.IsUnitOnQuest(questID, unit)`

```lua
-- TBC: UnitIsOnQuest does not exist → always nil.
-- Retail: UnitIsOnQuest(unit, questID) → bool.
WowQuestAPI.IsUnitOnQuest(questID, unit)  --> bool | nil
```

### Version-Branch Pattern

```lua
local TOC = select(4, GetBuildInfo())  -- e.g. 20505

if TOC >= 100000 then          -- Retail
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return UnitIsOnQuest(unit, questID)
    end
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return C_QuestLog.IsQuestFlaggedCompleted(questID)
    end
elseif TOC >= 20000 then       -- TBC Classic (including TBC Anniversary)
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return nil             -- API does not exist in TBC
    end
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return C_QuestLog.IsQuestFlaggedCompleted(questID)
    end
else                           -- Classic Era (future)
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return nil
    end
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return IsQuestFlaggedCompleted(questID)  -- legacy global
    end
end
```

---

## Section 2: New AQL Public Methods

### Relationship to existing API

| Existing method | New method | Relationship |
|----------------|------------|--------------|
| `AQL:GetQuest(questID)` | `AQL:GetQuestInfo(questID)` | `GetQuestInfo` is a **new method with different semantics** (see below). `GetQuest` is kept as-is (cache-only, no fallback) and is not deprecated. |
| `AQL:HasCompletedQuest(questID)` | *(enhanced in place)* | `HasCompletedQuest` keeps its name and is enhanced to also fall back to `WowQuestAPI.IsQuestFlaggedCompleted` when the HistoryCache has no record. No new method is added. |
| `AQL:GetObjectives(questID)` / `AQL:GetObjective(questID, i)` | `AQL:GetQuestObjectives(questID)` | The existing methods are kept unchanged. `GetQuestObjectives` is a new method with WowQuestAPI fallback; `GetObjectives` remains cache-only. |

### New Method Signatures

#### `AQL:GetQuestInfo(questID)`

Returns the full AQL cache snapshot if the quest is in the cache. If not cached, falls back to `WowQuestAPI.GetQuestInfo(questID)` which returns only `{ questID, title }`. Returns nil if neither source has data.

```lua
AQL:GetQuestInfo(questID)  --> table | nil
-- Full snapshot when cached; { questID, title } when only WowQuestAPI knows; nil otherwise.
```

This is **not** the same as `AQL:GetQuest(questID)`. `GetQuest` returns nil for any quest not in the cache. `GetQuestInfo` tries the WoW API as a fallback. Use `GetQuestInfo` when you need a title for any questID (e.g., a quest in a party member's log but not yours). Use `GetQuest` when you specifically want to know if AQL has a full snapshot.

#### `AQL:GetQuestTitle(questID)`

Returns just the title string, or nil.

```lua
AQL:GetQuestTitle(questID)  --> string | nil
-- AQL cache first → WowQuestAPI.GetQuestInfo(questID).title fallback
```

#### `AQL:GetQuestObjectives(questID)`

Returns objectives array (may be empty).

```lua
AQL:GetQuestObjectives(questID)  --> table
-- AQL cache first → WowQuestAPI.GetQuestObjectives(questID) fallback
```

#### `AQL:HasCompletedQuest(questID)` *(enhanced)*

Existing method, enhanced in place. Previously checked only the HistoryCache. Now also falls back to `WowQuestAPI.IsQuestFlaggedCompleted(questID)` when the cache has no record.

```lua
AQL:HasCompletedQuest(questID)  --> bool
-- HistoryCache first → WowQuestAPI.IsQuestFlaggedCompleted fallback
```

#### `AQL:TrackQuest(questID)` / `AQL:UntrackQuest(questID)`

`AQL:TrackQuest` enforces the TBC watch cap before calling through. Returns `true` if the quest was tracked, `false` if the cap was already reached.

```lua
AQL:TrackQuest(questID)    --> bool  -- false if GetNumQuestWatches() >= MAX_WATCHABLE_QUESTS
AQL:UntrackQuest(questID)  --> void  -- always delegates; no cap check needed
```

`MAX_WATCHABLE_QUESTS` is a WoW global (value: 5 on TBC). `GetNumQuestWatches()` returns the current count. Both are read at call time; no caching.

#### `AQL:IsUnitOnQuest(questID, unit)`

Delegates to `WowQuestAPI.IsUnitOnQuest`. Returns nil on TBC.

```lua
AQL:IsUnitOnQuest(questID, unit)  --> bool | nil
```

---

## Section 3: Social Quest Migration

After the new AQL methods and WowQuestAPI are in place, Social Quest removes every direct WoW quest API call and replaces them with AQL calls.

### Call Sites to Migrate

| File | Current call | Replacement |
|------|-------------|-------------|
| `Core/Announcements.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |
| `Core/GroupData.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |
| `Core/GroupData.lua` | `C_QuestLog.IsQuestFlaggedCompleted` | `AQL:HasCompletedQuest(questID)` |
| `UI/TabUtils.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |
| `UI/Tabs/PartyTab.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |
| `UI/Tabs/SharedTab.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |

After migration, Social Quest will contain no direct WoW quest API calls. AQL internal files (`Core\QuestCache.lua`, `Providers\*.lua`) are **not** migrated in this phase — they continue to call WoW globals directly. Migrating AQL internals to use WowQuestAPI is deferred to a future phase. The invariant for this phase is: **Social Quest is the only consumer addon that never calls WoW quest globals.**

### Load Order

`Core\WowQuestAPI.lua` must be listed in `AbsoluteQuestLog.toc` before any AQL file that calls it.

### TOC Dependencies

Social Quest already declares `AbsoluteQuestLog` as a dependency in its TOC (`## Dependencies`). No Social Quest TOC changes are needed — AQL's new public methods are available as soon as AQL loads.

---

## Out of Scope

- Chat-link generation (`GetQuestLink`) — already in AQL; no change needed.
- Quest watch count eviction — `AQL:TrackQuest` returns `false` at cap but does not evict the oldest watch to make room.
- Classic Era implementation — version branches are stubs returning nil; implementations added when Classic Era support is a target.
- Retail `GetQuestInfo` — the Retail branch returns `{ questID = questID, title = info.title }` (extracting title from the info table); full Retail support is not a target for this phase.
- Migrating AQL internal files — `Core\QuestCache.lua` and `Providers\*.lua` continue to call WoW globals directly; their migration is deferred.
- Refactoring `QuestCache:_buildEntry` — the internal snapshot builder is unchanged; `WowQuestAPI` does not duplicate its work.
