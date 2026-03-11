# AbsoluteQuestLog — Design Specification

**Date:** 2026-03-11
**Version:** 2.0
**Interface:** 20505 (WoW Burning Crusade Anniversary)
**Author:** Thad Ryker
**Status:** Approved for implementation

---

## Overview

AbsoluteQuestLog (AQL) is a shared library that provides a rich, unified API for all quest-related data in World of Warcraft Burning Crusade Anniversary. It abstracts over the live WoW quest log (`C_QuestLog`), completion history (`GetQuestsCompleted`), and static chain/metadata from optional companion addons (Questie, QuestWeaver). Consumers such as SocialQuest never call `C_QuestLog` directly — AQL is the single source of truth for all quest knowledge.

AQL is a **LibStub library**, not an AceAddon. It has no slash commands, no options panel, and no user-visible presence. It is infrastructure.

---

## Dependencies

| Dependency | Type | Notes |
|---|---|---|
| LibStub | Required | Bundled in Ace3 |
| CallbackHandler-1.0 | Required | Bundled in Ace3 |
| Questie | Optional | Primary chain/metadata provider |
| QuestWeaver | Optional | Secondary chain/metadata provider |

Ace3 must be installed as a standalone addon. AQL does not embed any libraries.

---

## Architecture

```
AbsoluteQuestLog-1.0 (LibStub library)
│
├── Core/
│   ├── EventEngine.lua       -- WoW event listeners, diff logic, callback dispatch
│   ├── QuestCache.lua        -- Live quest state built from C_QuestLog
│   └── HistoryCache.lua      -- Completion history via GetQuestsCompleted()
│
└── Providers/
    ├── Provider.lua          -- Abstract interface all providers implement
    ├── QuestieProvider.lua   -- Reads from QuestieDB (if loaded)
    ├── QuestWeaverProvider.lua -- Reads from QuestWeaver global (if loaded)
    └── NullProvider.lua      -- Returns knownStatus = "unknown" for everything
```

### Registration

```lua
-- AbsoluteQuestLog.lua
local AQL, oldVersion = LibStub:NewLibrary("AbsoluteQuestLog-1.0", 1)
if not AQL then return end  -- already loaded, newer version wins

AQL.callbacks = AQL.callbacks or LibStub("CallbackHandler-1.0"):New(AQL)
```

---

## Chain Data Provider System

At load time, AQL detects which companion addons are present and selects a provider in priority order:

1. **QuestieProvider** — if `QuestieDB` global exists and `QuestieDB.GetQuest` is callable
2. **QuestWeaverProvider** — if `QuestWeaver` global exists and `QuestWeaver.Quests` is populated
3. **NullProvider** — fallback when neither is present

Provider loading is wrapped in `pcall`. If a provider's internal structure has changed (breaking AQL's assumptions), the error is caught, a debug warning is logged, and the next provider in the chain is tried. This makes AQL resilient to version mismatches in companion addons.

### Provider Interface

Every provider implements the same interface:

```lua
Provider:GetChainInfo(questID)  -- returns ChainInfo table or nil
Provider:GetQuestType(questID)  -- returns type string or nil
Provider:GetQuestFaction(questID) -- returns "Alliance", "Horde", or nil
```

---

## Public API

All methods take a numeric `questID` as the primary key. The library object is retrieved once at addon load:

```lua
local AQL = LibStub("AbsoluteQuestLog-1.0")
```

### Quest State Queries

```lua
AQL:GetQuest(questID)             -- QuestInfo table (see Data Structures)
AQL:GetAllQuests()                -- table of all active QuestInfo, keyed by questID
AQL:GetQuestsByZone(zone)         -- filtered subset keyed by questID; zone is the English canonical zone name as stored by the active chain provider (e.g. "Blasted Lands"). Cross-locale zone name matching is undefined — on non-English clients use GetAllQuests() and filter by questID instead.
AQL:IsQuestActive(questID)        -- boolean: in player's quest log right now
AQL:IsQuestFinished(questID)      -- boolean: all objectives done, awaiting turn-in
AQL:HasCompletedQuest(questID)    -- boolean: completed at any point in character history
AQL:GetCompletedQuests()          -- table of all ever-completed questIDs (value = true)
AQL:GetCompletedQuestCount()      -- number
AQL:GetQuestType(questID)         -- "normal"|"elite"|"dungeon"|"raid"|"daily"|"pvp"|"escort"
AQL:GetQuestLink(questID)         -- in-game hyperlink string or nil
```

### Objective Queries

```lua
AQL:GetObjectives(questID)        -- array of Objective tables (see Data Structures)
AQL:GetObjective(questID, index)  -- single Objective table by 1-based index
```

### Chain Queries

```lua
AQL:GetChainInfo(questID)         -- ChainInfo table (see Data Structures)
AQL:GetChainStep(questID)         -- current step number (1-based), or nil if unknown
AQL:GetChainLength(questID)       -- total steps in chain, or nil if unknown
```

### Callback Registration

```lua
AQL:RegisterCallback(event, handler, target)
AQL:UnregisterCallback(event, handler)
```

---

## Data Structures

### QuestInfo Table

Returned by `AQL:GetQuest(questID)`:

```lua
{
    questID      = 1234,
    title        = "The Tainted Scar",      -- from C_QuestLog, in client language
    level        = 58,
    zone         = "Blasted Lands",
    type         = "elite",                 -- from static provider; nil if unknown
    faction      = "Alliance",              -- nil if available to both factions
    isComplete   = false,                   -- all objectives done, not yet turned in
    isFailed     = false,
    isTracked    = true,
    link         = "|cffffff00|Hquest:1234:58|h[...]|h|r",
    snapshotTime = 12345.678,               -- GetTime() at the moment this snapshot was built
    timerSeconds = 300,                     -- seconds remaining at snapshotTime from GetQuestLogTimeLeft(); nil if quest has no timer
    objectives   = { ... },                 -- array of Objective tables
    chainInfo    = { ... },                 -- ChainInfo table
}
```

#### Timer Usage

To calculate current time remaining from a QuestInfo snapshot:

```lua
if questInfo.timerSeconds then
    local elapsed = GetTime() - questInfo.snapshotTime
    local currentRemaining = questInfo.timerSeconds - elapsed
    if currentRemaining <= 0 then
        -- timer has expired since snapshot was taken
    end
end
```

This works identically whether the snapshot is local (just built by AQL) or received from a remote player via SocialQuest. The `snapshotTime` is always the sender's `GetTime()` value, and the receiver uses their own `GetTime()` for the diff — both clients share the same server clock reference in WoW, so the calculation is accurate across machines.

### Objective Table

Each entry in `AQL:GetObjectives(questID)`:

```lua
{
    index        = 1,
    text         = "Tainted Ooze killed: 4/10",   -- from C_QuestLog, in client language
    type         = "monster",   -- "monster"|"item"|"object"|"reputation"|"event"|"log"
    name         = "Tainted Ooze",
    numFulfilled = 4,
    numRequired  = 10,
    isFinished   = false,
    isFailed     = false,
}
```

### ChainInfo Table

Returned by `AQL:GetChainInfo(questID)`:

```lua
{
    knownStatus = "known",       -- "known" | "not_a_chain" | "unknown"
    chainID     = 1200,          -- questID of the first quest in the chain
    step        = 3,             -- this quest's position (1-based)
    length      = 5,             -- total quests in the chain
    steps = {
        { questID = 1200, title = "...", status = "completed"   },
        { questID = 1201, title = "...", status = "completed"   },
        { questID = 1234, title = "...", status = "active"      },
        { questID = 1235, title = "...", status = "available"   },
        { questID = 1236, title = "...", status = "available"   },
    },
    provider = "Questie",        -- "Questie" | "QuestWeaver" | "none"
}
```

#### Step Status Enum

Every entry in `steps` carries a `status` string. The complete set of valid values:

| Value | Meaning | Condition |
|---|---|---|
| `"completed"` | Player has turned in this step | `AQL:HasCompletedQuest(questID)` returns true |
| `"active"` | Player currently has this step in their quest log | `AQL:IsQuestActive(questID)` returns true |
| `"finished"` | Player has completed all objectives but not yet turned in | `AQL:IsQuestFinished(questID)` returns true |
| `"failed"` | Player failed this step (timed/escort quest) | Quest is in log with failed state |
| `"available"` | Step is not yet started; previous step is `"completed"` | `AQL:HasCompletedQuest(previousQuestID)` returns true |
| `"unavailable"` | Step is locked; previous step is not yet completed | Previous step is `"active"`, `"available"`, `"unavailable"`, or `"failed"` |
| `"unknown"` | This specific step's questID exists in the chain definition but cannot be matched to any known status | Quest ID not found in history, active log, or provider data — only possible when `knownStatus = "known"` but an individual step's questID is absent from the provider's dataset. Distinct from `knownStatus = "unknown"` (which means the entire chain structure is absent and the `steps` array is `nil`). |

When `knownStatus = "unknown"`, `chainID`, `step`, `length`, `steps`, and `provider` are all `nil`. Callers must check `knownStatus` before accessing other fields.

When `knownStatus = "not_a_chain"`, the quest is confirmed to be a standalone quest.

---

## Event System

AQL fires callbacks at both quest and objective granularity. Every handler receives a data snapshot at the moment of the event — callers do not need to immediately re-query.

### Quest-Level Callbacks

| Event | Arguments | Description |
|---|---|---|
| `AQL_QUEST_ACCEPTED` | `questInfo` | New quest added to log |
| `AQL_QUEST_ABANDONED` | `questInfo` | Quest removed by abandonment |
| `AQL_QUEST_FINISHED` | `questInfo` | All objectives done; awaiting turn-in |
| `AQL_QUEST_COMPLETED` | `questInfo` | Quest turned in and removed from log |
| `AQL_QUEST_FAILED` | `questInfo` | Quest failed (timer/escort expired) |
| `AQL_QUEST_TRACKED` | `questInfo` | Quest added to watch list |
| `AQL_QUEST_UNTRACKED` | `questInfo` | Quest removed from watch list |
| `AQL_UNIT_QUEST_LOG_CHANGED` | `unit` | Another unit's quest log changed |

### Objective-Level Callbacks

| Event | Arguments | Description |
|---|---|---|
| `AQL_OBJECTIVE_PROGRESSED` | `questInfo, objective, delta` | Objective count increased |
| `AQL_OBJECTIVE_COMPLETED` | `questInfo, objective` | Single objective finished |
| `AQL_OBJECTIVE_REGRESSED` | `questInfo, objective, delta` | Objective count decreased |
| `AQL_OBJECTIVE_FAILED` | `questInfo, objective` | Single objective failed |

`delta` is a positive number representing the absolute change (e.g. `1` for killing one mob).

### Subscribing

```lua
local AQL = LibStub("AbsoluteQuestLog-1.0")

AQL:RegisterCallback("AQL_QUEST_ACCEPTED",       SocialQuest, SocialQuest.OnQuestAccepted)
AQL:RegisterCallback("AQL_OBJECTIVE_PROGRESSED", SocialQuest, SocialQuest.OnObjectiveProgress)
```

---

## Internal Design: EventEngine

The EventEngine is the heart of AQL. It:

1. Listens to WoW events: `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`, `QUEST_FAILED`, `QUEST_LOG_UPDATE`, `UNIT_QUEST_LOG_CHANGED`, `QUEST_WATCH_LIST_CHANGED`
2. On each relevant event, rebuilds the `QuestCache` snapshot
3. Diffs the new snapshot against the previous one at both quest and objective granularity
4. Fires the appropriate AQL callbacks with data snapshots

### Re-entrancy Guard

If `QUEST_LOG_UPDATE` fires while a diff is already in progress, the second call is dropped. A simple boolean flag (`diffInProgress`) prevents double-firing of events. This replaces the old `protectQuestLog` mechanism.

**Known limitation:** A dropped update means the EventEngine may miss state changes from rapid back-to-back events (e.g. two objectives completing in the same frame). `QUEST_LOG_UPDATE` fires frequently enough in normal gameplay that eventual consistency is acceptable — the next naturally occurring event will catch any missed state. This is a deliberate simplification over the old `protectQuestLog` approach, which had its own re-entrancy problems.

### Objective Diffing

For each quest in the cache, each objective's `numFulfilled` is compared between the old and new snapshots:

- `new > old` → `AQL_OBJECTIVE_PROGRESSED` (delta = new - old); additionally if `new >= numRequired and old < numRequired` → also fire `AQL_OBJECTIVE_COMPLETED`
- `new < old` → `AQL_OBJECTIVE_REGRESSED` (delta = old - new)

Note: `AQL_OBJECTIVE_COMPLETED` is fired as part of the same progression event that crosses the `numRequired` threshold — it is not a separate condition. The `new == old` guard was intentionally omitted; completion is detected purely by crossing the threshold from below.

---

## Error Handling

- All provider calls are wrapped in `pcall`. A failing provider is marked unavailable and the next provider is tried.
- Individual quest data reads from `C_QuestLog` are wrapped so a single bad entry does not abort the cache rebuild. Bad entries are skipped and logged in debug mode.
- If AQL detects it is already loaded at a higher version (LibStub guarantee), it returns early without re-running initialization.

---

## File Structure

```
AbsoluteQuestLog\
    AbsoluteQuestLog.toc
    AbsoluteQuestLog.lua          -- LibStub registration, public API surface
    Core\
        EventEngine.lua           -- WoW event listeners, diff logic, callback dispatch
        QuestCache.lua            -- Live quest state from C_QuestLog
        HistoryCache.lua          -- Completion history via GetQuestsCompleted()
    Providers\
        Provider.lua              -- Abstract interface definition
        QuestieProvider.lua       -- Reads from QuestieDB
        QuestWeaverProvider.lua   -- Reads from QuestWeaver global table
        NullProvider.lua          -- Returns knownStatus = "unknown"
```

### TOC File

```
## Interface: 20505
## Title: Lib: AbsoluteQuestLog
## Notes: A rich quest data library for WoW Burning Crusade Anniversary.
## Author: Thad Ryker
## Version: 2.0
## X-Category: Library

AbsoluteQuestLog.lua
Core\EventEngine.lua
Core\QuestCache.lua
Core\HistoryCache.lua
Providers\Provider.lua
Providers\QuestieProvider.lua
Providers\QuestWeaverProvider.lua
Providers\NullProvider.lua
```

---

## Testing Checklist

- [ ] Library loads and registers with LibStub without errors
- [ ] `AQL:GetQuest()` returns correct data for an active quest
- [ ] `AQL:GetAllQuests()` matches actual quest log contents
- [ ] `AQL:HasCompletedQuest()` returns true for a known completed quest
- [ ] `AQL:GetCompletedQuests()` count matches `GetQuestsCompleted()` count
- [ ] `AQL:GetCompletedQuestCount()` returns correct number
- [ ] `AQL_QUEST_ACCEPTED` fires when accepting a new quest
- [ ] `AQL_QUEST_ABANDONED` fires when abandoning a quest
- [ ] `AQL_QUEST_FINISHED` fires when all objectives are complete
- [ ] `AQL_QUEST_COMPLETED` fires on quest turn-in
- [ ] `AQL_OBJECTIVE_PROGRESSED` fires with correct delta when killing a mob
- [ ] `AQL_OBJECTIVE_COMPLETED` fires when a single objective finishes
- [ ] `AQL:GetChainInfo()` returns correct step/length with Questie loaded
- [ ] `AQL:GetChainInfo()` returns correct step/length with QuestWeaver loaded (Questie absent)
- [ ] `AQL:GetChainInfo()` returns `knownStatus = "unknown"` with neither loaded
- [ ] Provider fallback works when Questie returns nil for a quest
- [ ] Re-entrancy guard prevents double-firing during nested QUEST_LOG_UPDATE
- [ ] Quest with no objectives does not crash objective diff
- [ ] Full quest log (25 quests) initializes correctly at login
