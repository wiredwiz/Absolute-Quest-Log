# AQL WowQuestAPI Architectural Cleanup — Design Spec

**Date:** 2026-03-29
**Repo:** Absolute-Quest-Log
**Feature:** Centralize all WoW API calls in WowQuestAPI.lua; add missing wrappers; update all callers

---

## Goal

Every direct WoW global call in the addon must go through a `WowQuestAPI` wrapper. This is the existing architectural rule ("No other AQL file should reference WoW quest globals directly") applied comprehensively — including providers. Zero behavioral changes. This sub-project prepares the codebase for Retail IS_RETAIL branches in the next sub-project.

---

## Context

### Why this matters

`WowQuestAPI.lua` is the single point where all version-specific branching lives. Any direct WoW global call outside that file bypasses the branching layer — meaning Retail `IS_RETAIL` branches added in the next sub-project would be silently ignored for those callsites.

### Scope

**Not in scope:** IS_RETAIL branches, behavioral changes, new public API methods, deprecations. Pure mechanical refactoring.

### Files Modified

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | Add 10 new wrapper functions |
| `Core/QuestCache.lua` | Replace 14 direct WoW calls with wrapper calls |
| `Core/HistoryCache.lua` | Replace 1 direct WoW call |
| `Core/EventEngine.lua` | Replace 1 direct WoW call |
| `AbsoluteQuestLog.lua` | Replace 2 direct WoW calls |
| `Providers/QuestieProvider.lua` | Replace 1 direct WoW call |
| `AbsoluteQuestLog.toc` + four version tocs | Version bump to 2.5.3 |
| `CLAUDE.md` | Version 2.5.3 entry; reinforce WowQuestAPI rule in Architecture section |
| `changelog.txt` | Add 2.5.3 entry |

---

## Deliverable 1 — New wrappers in WowQuestAPI.lua

Add all new wrappers in logical groups within the existing file. Work top-to-bottom. Place each group immediately after the related existing wrapper.

### Group A: Quest History (after `IsQuestFlaggedCompleted` block)

```lua
------------------------------------------------------------------------
-- WowQuestAPI.GetQuestsCompleted()
-- Returns the associative table {[questID]=true} of all quests completed
-- by this character. Same return shape on Classic Era, TBC, and MoP.
-- Note: Retail uses C_QuestLog.GetAllCompletedQuestIDs() which returns a
-- sequential array — IS_RETAIL branch will be added in the Retail sub-project.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestsCompleted()
    return GetQuestsCompleted()
end
```

### Group B: Quest Tracking (after `UntrackQuest` block)

```lua
------------------------------------------------------------------------
-- WowQuestAPI.GetWatchedQuestCount()
-- Returns the number of quests currently on the watch list.
------------------------------------------------------------------------

function WowQuestAPI.GetWatchedQuestCount()
    return GetWatchedQuestCount()
end

------------------------------------------------------------------------
-- WowQuestAPI.GetMaxWatchableQuests()
-- Returns the maximum number of quests that can be watched simultaneously.
-- Wraps the MAX_WATCHABLE_QUESTS global constant as a function for
-- consistent access through the WowQuestAPI layer.
------------------------------------------------------------------------

function WowQuestAPI.GetMaxWatchableQuests()
    return MAX_WATCHABLE_QUESTS
end

------------------------------------------------------------------------
-- WowQuestAPI.IsQuestWatchedByIndex(logIndex)
-- WowQuestAPI.IsQuestWatchedById(questID)
-- Returns true if the quest is on the watch list, false otherwise.
-- Explicit boolean coercion: IsQuestWatched returns 1/nil on legacy clients.
-- ById variant resolves questID → logIndex via GetQuestLogIndex.
-- Returns nil from ById if the quest is not in the player's log.
-- Note: Retail uses C_QuestLog.IsQuestWatched(questID) — IS_RETAIL branch
-- will be added in the Retail sub-project (ById variant will be updated).
------------------------------------------------------------------------

function WowQuestAPI.IsQuestWatchedByIndex(logIndex)
    return IsQuestWatched(logIndex) and true or false
end

function WowQuestAPI.IsQuestWatchedById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    return IsQuestWatched(logIndex) and true or false
end
```

### Group C: Quest Log Frame & Navigation (within the existing Quest Log Frame section)

Add after `SelectQuestLogEntry` wrapper:

```lua
-- GetQuestLogTimeLeft() → number or nil
-- Returns the time remaining in seconds for the selected quest's timer,
-- or nil if the selected quest has no timer.
function WowQuestAPI.GetQuestLogTimeLeft()
    return GetQuestLogTimeLeft()
end
```

Add after `GetQuestLogTimeLeft`:

```lua
-- GetQuestLinkByIndex(logIndex) → hyperlink string or nil
-- Returns the chat hyperlink for the quest at logIndex.
-- GetQuestLinkById(questID) → hyperlink string or nil
-- Resolves questID → logIndex, then returns the hyperlink.
-- Returns nil if the quest is not in the player's log.
-- Note: Retail equivalent will be added in the Retail sub-project.
function WowQuestAPI.GetQuestLinkByIndex(logIndex)
    return GetQuestLink(logIndex)
end

function WowQuestAPI.GetQuestLinkById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    return GetQuestLink(logIndex)
end
```

Add after `GetQuestLinkById`:

```lua
-- GetCurrentDisplayedQuestID() → number or nil
-- Returns the questID of the quest currently displayed in the NPC quest dialog.
-- This covers both accepting a quest from a quest giver and the turn-in reward
-- screen — any context where a quest is open in the NPC interaction UI.
-- Only meaningful while an NPC quest dialog is open.
function WowQuestAPI.GetCurrentDisplayedQuestID()
    return GetQuestID()
end
```

### Group D: Map / Miscellaneous (at end of file)

```lua
------------------------------------------------------------------------
-- WowQuestAPI.GetAreaInfo(areaID)
-- Returns the area info table for the given areaID via C_Map.GetAreaInfo.
-- Available on all four version families (backported to 1.13.2).
-- Used by QuestieProvider to resolve zone names from Questie's zoneOrSort IDs.
------------------------------------------------------------------------

function WowQuestAPI.GetAreaInfo(areaID)
    return C_Map.GetAreaInfo(areaID)
end
```

---

## Deliverable 2 — QuestCache.lua: replace 15 direct calls

All replacements are one-for-one. No logic changes. Work top-to-bottom to avoid line-shift confusion.

| Line | Current | Replacement |
|---|---|---|
| 21 | `GetQuestLogSelection()` | `WowQuestAPI.GetQuestLogSelection()` |
| 28 | `GetNumQuestLogEntries()` | `WowQuestAPI.GetNumQuestLogEntries()` |
| 30 | `GetQuestLogTitle(i)` | `WowQuestAPI.GetQuestLogTitle(i)` |
| 45 | `ExpandQuestHeader(logIndex)` | `WowQuestAPI.ExpandQuestHeader(logIndex)` |
| 52 | `GetNumQuestLogEntries()` | `WowQuestAPI.GetNumQuestLogEntries()` |
| 59 | `GetQuestLogTitle(i)` | `WowQuestAPI.GetQuestLogTitle(i)` |
| ~99 | `GetNumQuestLogEntries()` | `WowQuestAPI.GetNumQuestLogEntries()` |
| ~101 | `GetQuestLogTitle(i)` | `WowQuestAPI.GetQuestLogTitle(i)` |
| ~108 | `CollapseQuestHeader(logIndex)` | `WowQuestAPI.CollapseQuestHeader(logIndex)` |
| ~116 | `SelectQuestLogEntry(logIndex)` | `WowQuestAPI.SelectQuestLogEntry(logIndex)` |
| ~135 | `SelectQuestLogEntry(logIndex)` | `WowQuestAPI.SelectQuestLogEntry(logIndex)` |
| ~136 | `GetQuestLogTimeLeft()` | `WowQuestAPI.GetQuestLogTimeLeft()` |
| ~141 | `GetQuestLink(logIndex)` | `WowQuestAPI.GetQuestLinkByIndex(logIndex)` |
| ~148 | `IsQuestWatched(logIndex) and true or false` | `WowQuestAPI.IsQuestWatchedByIndex(logIndex)` |
| ~156 | `C_QuestLog.GetQuestObjectives(questID)` | `WowQuestAPI.GetQuestObjectives(questID)` |

> **Note on line ~156:** `WowQuestAPI.GetQuestObjectives` returns `{} ` if the API returns nil. Verify the surrounding code in QuestCache handles an empty table correctly (it should already — this is how the wrapper has always behaved when called from other paths).

---

## Deliverable 3 — HistoryCache.lua: replace 1 direct call

| Line | Current | Replacement |
|---|---|---|
| 19 | `GetQuestsCompleted()` | `WowQuestAPI.GetQuestsCompleted()` |

---

## Deliverable 4 — EventEngine.lua: replace 1 direct call

| Line | Current | Replacement |
|---|---|---|
| ~52 | `GetQuestID()` | `WowQuestAPI.GetCurrentDisplayedQuestID()` |

This call is inside `hooksecurefunc("GetQuestReward", ...)`, which only fires on TBC. The wrapper is a transparent passthrough on all versions.

---

## Deliverable 5 — AbsoluteQuestLog.lua: replace 2 direct calls

Both calls are in the `TrackQuest` method (around line 395).

| Current | Replacement |
|---|---|
| `GetWatchedQuestCount()` | `WowQuestAPI.GetWatchedQuestCount()` |
| `MAX_WATCHABLE_QUESTS` | `WowQuestAPI.GetMaxWatchableQuests()` |

---

## Deliverable 6 — QuestieProvider.lua: replace 1 direct call

| Line | Current | Replacement |
|---|---|---|
| ~212 | `C_Map.GetAreaInfo(quest.zoneOrSort)` | `WowQuestAPI.GetAreaInfo(quest.zoneOrSort)` |

---

## Deliverable 7 — Version bump and documentation

- Bump all five toc files: `2.5.2` → `2.5.3`
- Add `### Version 2.5.3 (March 2026)` entry to `CLAUDE.md` Version History
- Update `WowQuestAPI` entry in `CLAUDE.md` Architecture section to reinforce: "All WoW API calls — including those in providers — must go through WowQuestAPI wrappers, no exceptions"
- Add `Version 2.5.3` entry to `changelog.txt`

### Version 2.5.3 changelog content

```
- Refactor: All direct WoW global calls outside WowQuestAPI.lua replaced with
  wrapper calls. Files updated: QuestCache.lua (15 callsites), HistoryCache.lua
  (1), EventEngine.lua (1), AbsoluteQuestLog.lua (2), QuestieProvider.lua (1).
- New wrappers added to WowQuestAPI.lua: GetQuestsCompleted,
  IsQuestWatchedByIndex, IsQuestWatchedById, GetQuestLogTimeLeft,
  GetQuestLinkByIndex, GetQuestLinkById, GetCurrentDisplayedQuestID,
  GetWatchedQuestCount, GetMaxWatchableQuests, GetAreaInfo. Zero behavioral changes.
```

---

## Success Criteria

1. No direct WoW global calls remain in any file outside `Core/WowQuestAPI.lua`.
2. All 10 new wrappers are present in `WowQuestAPI.lua` with correct doc comments.
3. `IsQuestWatchedByIndex` and `IsQuestWatchedById` both include `and true or false` boolean coercion.
4. `IsQuestWatchedById` and `GetQuestLinkById` return nil when the quest is not in the player's log.
5. All callers compile (no Lua syntax errors introduced).
6. Grep confirms zero remaining direct calls — two checks:

   **New wrappers (APIs that had no wrapper before this sub-project):**
   ```bash
   grep -rn "GetQuestsCompleted\|IsQuestWatched\|GetQuestLogTimeLeft\|GetQuestLink\|GetQuestID\(\)\|GetWatchedQuestCount\|MAX_WATCHABLE_QUESTS\|C_Map\.GetAreaInfo" Core/ AbsoluteQuestLog.lua Providers/ --include="*.lua" | grep -v WowQuestAPI.lua
   ```
   Expected: zero results.

   **Existing wrappers (APIs that had wrappers but were still called directly in QuestCache.lua):**
   ```bash
   grep -n "GetQuestLogSelection()\|GetNumQuestLogEntries()\|GetQuestLogTitle(\|ExpandQuestHeader(\|CollapseQuestHeader(\|SelectQuestLogEntry(" Core/QuestCache.lua
   ```
   Expected: zero results (all 11 remaining callsites now use `WowQuestAPI.*`).
7. Version is 2.5.3 in all five toc files.
