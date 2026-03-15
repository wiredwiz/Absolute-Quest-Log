# AQL Quest API Wrapper Design

**Date:** 2026-03-15
**Status:** Approved

---

## Overview

Introduce a two-layer abstraction so that (a) all raw WoW quest API calls are centralized in one file for easy version-branching and (b) callers of AQL never touch WoW globals directly.

**Goal:** All WoW quest API calls live in `Core/WowQuestAPI.lua`. AQL exposes new public methods that delegate to `WowQuestAPI`. Social Quest (and any other consumer) calls only AQL or WowQuestAPI — never WoW globals.

---

## Section 1: WowQuestAPI.lua

### Location

`Core/WowQuestAPI.lua` — loaded before AQL's core files.

### Purpose

A pure namespace of version-normalized functions. No addon state, no AceAddon, no LibStub. If Classic Era or Retail support is added later, only this file changes.

### API Surface

```lua
-- Returns a normalized table or nil.
-- On TBC 20505 uses C_QuestLog.GetQuestInfo() for title.
-- { questID, title, level, zone, suggestedGroup, isComplete, isFailed,
--   isTracked, logIndex, timerSeconds, snapshotTime, objectives }
WowQuestAPI.GetQuestInfo(questID)  --> table | nil

-- Returns the objectives array for an active quest by log index.
-- Each entry: { text, numFulfilled, numRequired, isFinished }
WowQuestAPI.GetQuestObjectives(questID)  --> table (may be empty)

-- Wraps C_QuestLog.IsQuestFlaggedCompleted (TBC) / IsQuestFlaggedCompleted (Classic).
WowQuestAPI.IsQuestFlaggedCompleted(questID)  --> bool

-- Returns the 1-based quest log index, or nil if not in log.
WowQuestAPI.GetQuestLogIndex(questID)  --> number | nil

-- Adds/removes the quest timer/tracker.  No-op if quest not in log.
WowQuestAPI.TrackQuest(questID)    --> void
WowQuestAPI.UntrackQuest(questID)  --> void

-- Returns true when `unit` is on questID.
-- Returns nil on TBC (UnitIsOnQuest does not exist).
-- Returns bool on Retail.
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
elseif TOC >= 20000 then       -- TBC Classic
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
        return IsQuestFlaggedCompleted(questID)
    end
end
```

### Non-Goals

- No caching — AQL handles caching.
- No event handling.
- No addon lifecycle (no `:OnEnable`, no LibStub).

---

## Section 2: New AQL Public Methods

AQL already maintains an internal snapshot cache (`self.quests`). The new public methods delegate to that cache first; `WowQuestAPI` is the fallback for quests not in the cache (e.g., fetching a title by questID for a quest another player mentioned).

### Method Signatures

```lua
-- Returns AQL cache entry for questID, or nil if not tracked.
-- This replaces the current AQL:GetQuest(questID) for callers that need a
-- full snapshot. The name matches WowQuestAPI for discoverability.
AQL:GetQuestInfo(questID)  --> table | nil

-- Returns the quest title string, or nil.
-- Cache first; falls back to WowQuestAPI.GetQuestInfo(questID).title.
AQL:GetQuestTitle(questID)  --> string | nil

-- Returns objectives array (may be empty).
-- Cache first; falls back to WowQuestAPI.GetQuestObjectives(questID).
AQL:GetQuestObjectives(questID)  --> table

-- True when questID is in the historical completion set OR
-- WowQuestAPI.IsQuestFlaggedCompleted returns true.
AQL:IsQuestEverCompleted(questID)  --> bool

-- Delegates directly to WowQuestAPI; applies questID → logIndex resolution.
AQL:TrackQuest(questID)    --> void
AQL:UntrackQuest(questID)  --> void

-- Delegates to WowQuestAPI.IsUnitOnQuest; returns nil on TBC.
AQL:IsUnitOnQuest(questID, unit)  --> bool | nil
```

### Backward Compatibility

`AQL:GetQuest(questID)` is **not removed** — it is kept as an alias for `AQL:GetQuestInfo(questID)` during the transition period. Callers can migrate at their own pace; once Social Quest is fully migrated the alias may be removed.

---

## Section 3: Social Quest Migration

After the new AQL methods and WowQuestAPI are in place, Social Quest removes every direct WoW quest API call and replaces them with AQL or WowQuestAPI calls.

### Call Sites to Migrate

| File | Current call | Replacement |
|------|-------------|-------------|
| `Core/Announcements.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |
| `Core/GroupData.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |
| `Core/GroupData.lua` | `C_QuestLog.IsQuestFlaggedCompleted` | `AQL:IsQuestEverCompleted(questID)` |
| `UI/TabUtils.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |
| `UI/Tabs/PartyTab.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |
| `UI/Tabs/SharedTab.lua` | `C_QuestLog.GetQuestInfo(questID)` | `AQL:GetQuestTitle(questID)` |

After migration, `Core/WowQuestAPI.lua` is the **only** file in either project that references WoW quest globals.

### Load Order

`WowQuestAPI.lua` must be listed in `AbsoluteQuestLog.toc` before any AQL file that calls it.

---

## Out of Scope

- Chat-link generation (`GetQuestLink`) — already in AQL; no change needed.
- Quest watch count limits — internal AQL concern; not exposed.
- Classic Era implementation — version branches are stubs returning nil; implementations added when Classic Era support is a target.
