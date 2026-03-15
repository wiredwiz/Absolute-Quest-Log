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

Two-tier resolution. Returns nil when no source has data.

**Guaranteed fields** (always present on non-nil return):
- `questID`, `title`

**Conditional fields** (only present when the quest is in the player's log):
- `level`, `suggestedGroup`, `isComplete`, `zone`

**TBC implementation — tier 1: log scan**

Iterates `GetQuestLogTitle` to find the questID (8th return value). Zone name is captured from header rows (where `isHeader == true` and `title` is the zone/category name) as the loop runs — same pattern used by `QuestCache:Rebuild()`. When the target quest is found, returns the richer table:

```lua
-- GetQuestLogTitle(i) returns:
--   title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
-- isComplete: 1 = done (not yet turned in), false/nil = in progress
-- currentZone is updated each time a header row is encountered (isHeader == true)
{
    questID        = questID,
    title          = title,
    level          = level,
    suggestedGroup = tonumber(suggestedGroup) or 0,
    isComplete     = (isComplete == 1 or isComplete == true),
    zone           = currentZone,  -- nil if no header seen before this quest
}
```

**TBC implementation — tier 2: title-only fallback**

When the quest is not in the player's log, falls back to `C_QuestLog.GetQuestInfo(questID)` (returns title string or nil):

```lua
{ questID = questID, title = title }  -- level/suggestedGroup/isComplete absent
```

**Retail implementation**

`C_QuestLog.GetQuestInfo(questID)` returns a full info table in one call — no log scan needed:

```lua
-- Returns nil if info is nil.
-- zone: not included; full Retail support is out of scope for this phase.
{
    questID        = questID,
    title          = info.title,
    level          = info.level,
    suggestedGroup = info.suggestedGroup or 0,
    isComplete     = info.isComplete == 1,
    isTask         = info.isTask,
    isBounty       = info.isBounty,
    isStory        = info.isStory,
    campaignID     = info.campaignID,
}
```

```lua
WowQuestAPI.GetQuestInfo(questID)  --> table | nil
```

This is a **fallback for quests not in the AQL cache**. The AQL cache (`AQL:GetQuestInfo`) is always checked first and returns the full normalized snapshot when available. Callers that need zone, objectives, timerSeconds, or chainInfo must use the AQL cache.

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

Three-tier resolution. Returns nil only when all three tiers have no data.

```lua
AQL:GetQuestInfo(questID)  --> table | nil
```

**Tier 1 — AQL QuestCache (fastest)**

Returns the full normalized snapshot immediately if cached. All fields present.

**Tier 2 — WowQuestAPI log scan / title fallback**

Called only on cache miss. Returns a partial table (see `WowQuestAPI.GetQuestInfo` in Section 1). Guaranteed fields: `questID`, `title`. Conditional fields when quest is in log: `level`, `suggestedGroup`, `isComplete`, `zone`.

**Tier 3 — Provider (Questie / QuestWeaver)**

Called only when tiers 1 and 2 both return nil (quest not in player's log and not cached). Uses `AQL.provider` which is already set at login. Two provider calls are made and their results merged:

1. `provider:GetQuestBasicInfo(questID)` — new optional provider method (see below). Returns `{ title, questLevel, requiredLevel }` from the provider's static database, or nil.
2. `provider:GetChainInfo(questID)` — existing method. If `knownStatus == "known"`, `chainID`, `step`, and `length` are merged into the result.

Both calls are wrapped in `pcall`. If the provider returns nil for both, `AQL:GetQuestInfo` returns nil.

Tier 3 result shape (fields vary by what the provider knows):
```lua
{
    questID       = questID,
    title         = quest.name,          -- from GetQuestBasicInfo
    level         = quest.questLevel,    -- from GetQuestBasicInfo
    requiredLevel = quest.requiredLevel, -- from GetQuestBasicInfo
    zone          = ...,                 -- from GetQuestBasicInfo (string or nil)
    chainInfo     = {                    -- from GetChainInfo, always present
        knownStatus = "known"|"not_a_chain"|"unknown",
        chainID     = ...,  -- only when knownStatus == "known"
        step        = ...,
        length      = ...,
    },
}
```

This is **not** the same as `AQL:GetQuest(questID)`. `GetQuest` is cache-only and returns nil for uncached quests. `GetQuestInfo` is the enriched fallback path. Use `GetQuestInfo` when you need data for any questID regardless of whether the player has it active.

---

### Provider interface extension: `GetQuestBasicInfo`

New **optional** method added to the provider interface. `NullProvider` does not implement this method and always returns nil. Callers guard with `provider.GetQuestBasicInfo and`.

```lua
Provider:GetQuestBasicInfo(questID)
-- Returns { title, questLevel, requiredLevel, zone } or nil.
-- All fields are optional (may be nil if the provider does not have them).
```

**QuestieProvider implementation** — reads from `QuestieDB.GetQuest(questID)`:

```lua
-- Questie questKeys (from tbcQuestDB.lua):
--   quest.name          = key 1  (string)
--   quest.requiredLevel = key 4  (int, minimum player level to accept)
--   quest.questLevel    = key 5  (int, quest difficulty level)
--   quest.zoneOrSort    = key 17 (int: >0 = DBC AreaTable ID, <0 = QuestSort category, 0 = none)
-- Zone name is resolved via C_Map.GetAreaInfo(quest.zoneOrSort) when zoneOrSort > 0.
-- Negative values are quest-sort categories (e.g., "Fishing", "Epic") not geographic zones;
-- zone is omitted for negative zoneOrSort values.
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
```

**QuestWeaverProvider implementation** — reads from `qw.Quests[questID]`:

```lua
-- QuestWeaver quest objects have:
--   quest.name        (string, quest title)
--   quest.level       (int, quest difficulty level)
--   quest.min_level   (int, minimum player level to accept)
--   quest.zone        (string, zone name from data file)
--   quest.source_zone (string, zone name set at load time from ZoneIndex)
-- Prefer source_zone (set at load) over zone (from data file); both are human-readable strings.
function QuestWeaverProvider:GetQuestBasicInfo(questID)
    if not self:IsAvailable() then return nil end
    local ok, quest = pcall(function() return qw.Quests[questID] end)
    if not ok or not quest then return nil end
    return {
        title         = quest.name,
        questLevel    = quest.level,
        requiredLevel = quest.min_level,
        zone          = quest.source_zone or quest.zone,
    }
end
```

**NullProvider** — does not implement `GetQuestBasicInfo`; returns nil. Method may be omitted entirely; callers guard with `provider.GetQuestBasicInfo and`.

---

#### `AQL:GetQuestTitle(questID)`

Returns just the title string, or nil. Delegates to `AQL:GetQuestInfo` and extracts `.title`.

```lua
AQL:GetQuestTitle(questID)  --> string | nil
-- AQL cache → WowQuestAPI log scan / title fallback → provider GetQuestBasicInfo
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
| `Core/Announcements.lua` | `C_QuestLog.GetQuestInfo(questID)` ×4 | `AQL:GetQuestTitle(questID)` |
| `Core/Announcements.lua` | `C_QuestLog.IsQuestFlaggedCompleted(questID)` ×1 | `AQL:HasCompletedQuest(questID)` |
| `Core/GroupData.lua` | `C_QuestLog.GetQuestInfo(questID)` ×2 | `AQL:GetQuestTitle(questID)` |
| `UI/Tabs/PartyTab.lua` | `C_QuestLog.GetQuestInfo(questID)` ×1 | `AQL:GetQuestTitle(questID)` |
| `UI/Tabs/SharedTab.lua` | `C_QuestLog.GetQuestInfo(questID)` ×2 | `AQL:GetQuestTitle(questID)` |

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
