# Quest Log API Wrappers — Design Spec

**Date:** 2026-03-23
**Project:** AbsoluteQuestLog-1.0
**Status:** Approved

---

## Overview

AQL's stated design principle is that `WowQuestAPI.lua` is the sole interface to WoW quest globals — no other AQL or consumer file should reference them directly. Currently, several WoW quest log globals are called directly from SocialQuest (`RowFactory.lua`, `PartyTab.lua`) rather than routing through AQL. This spec covers:

1. Adding thin wrappers for the missing quest log globals in `WowQuestAPI.lua`.
2. Exposing those wrappers as a fully-documented public API on the `AQL` object in `AbsoluteQuestLog.lua`.
3. Adding compound convenience methods (ByIndex and ById variants) for common multi-step operations.
4. Adding quest-level filtering methods to the Quest APIs group.
5. Reorganizing all existing public `AQL` methods into a clear two-group structure for developer discoverability.

SocialQuest call-site migration (replacing direct WoW globals with AQL calls) is **out of scope** for this spec and will be addressed in a separate task.

**Pre-existing exception out of scope:** `AQL:TrackQuest` in `AbsoluteQuestLog.lua` currently calls `GetNumQuestWatches()` and references `MAX_WATCHABLE_QUESTS` as raw WoW globals. This is a pre-existing violation of the design principle that is not addressed by this spec. It is noted here for completeness; wrapping those globals is a future task.

---

## Goals

- All WoW quest log globals accessible through AQL, with no consumer needing to reference them directly.
- A public API that is easy for a new developer to discover and use, with concise but complete inline documentation.
- Compound methods that hide common ceremony (selection save/restore, selection+display pairing, quest log open+navigate) while still exposing the individual primitives for consumers with different needs.
- Level-range filtering methods that let consumers easily query quests appropriate for the player's current level.
- Debug messages on all new public methods so consumers can trace behavior during development.

---

## Naming Convention

AQL thin wrapper methods for quest log frame globals add "QuestLog" to the name (e.g., WoW global `ExpandQuestHeader` → AQL method `ExpandQuestLogHeader`). This distinguishes AQL public methods from their `WowQuestAPI` backing functions, which use the exact WoW global name. The "QuestLog" infix makes it immediately clear at the call site that the method interacts with the built-in quest log frame.

`AQL:GetQuestLogIndex(questID)` is placed in the Quest Log APIs group (Group 2) rather than Quest APIs (Group 1) because it operates on logIndex — a quest log-specific coordinate — and is primarily useful in the context of quest log frame interactions. It is a data-resolution helper for Quest Log operations, not a quest state query.

---

## File Changes

### 1. `Core/WowQuestAPI.lua`

A new section — **Quest Log Frame & Navigation** — is added at the bottom of the file. Each wrapper has the exact same name as the WoW global it wraps, keeping the mapping obvious to any developer familiar with the WoW API. All version branching and fallback logic lives here.

**New wrappers (added to this file):**

| WowQuestAPI function | Wraps | Notes |
|---|---|---|
| `GetNumQuestLogEntries()` | `GetNumQuestLogEntries()` | Returns the total number of entries (headers + quests) in the quest log |
| `GetQuestLogTitle(logIndex)` | `GetQuestLogTitle(logIndex)` | Returns title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID for a given logIndex |
| `GetQuestLogSelection()` | `GetQuestLogSelection()` | Returns current selected logIndex (0 if none) |
| `SelectQuestLogEntry(logIndex)` | `SelectQuestLogEntry(logIndex)` | Sets selection; no UI refresh |
| `GetQuestLogPushable()` | `GetQuestLogPushable()` | Checks currently-selected entry; normalized to bool |
| `QuestLog_SetSelection(logIndex)` | `QuestLog_SetSelection(logIndex)` | UI selection update only; always paired with `QuestLog_Update()` |
| `QuestLog_Update()` | `QuestLog_Update()` | Refreshes quest log display; always paired with `QuestLog_SetSelection(logIndex)` |
| `ExpandQuestHeader(logIndex)` | `ExpandQuestHeader(logIndex)` | Expands a collapsed zone header |
| `CollapseQuestHeader(logIndex)` | `CollapseQuestHeader(logIndex)` | Collapses a zone header |
| `ShowQuestLog()` | `ShowUIPanel(QuestLogFrame)` | Named semantically; hides the generic ShowUIPanel detail |
| `HideQuestLog()` | `HideUIPanel(QuestLogFrame)` | Named semantically |
| `IsQuestLogShown()` | `QuestLogFrame:IsShown()` | Returns bool |
| `GetQuestDifficultyColor(level)` | `GetQuestDifficultyColor(level)` | Returns `{r,g,b}`; includes manual fallback if API absent |
| `GetPlayerLevel()` | `UnitLevel("player")` | Returns the player's current level as a number |

**Existing wrapper (already in this file — do NOT re-add):**

`WowQuestAPI.GetQuestLogIndex(questID)` already exists in this file. It is surfaced as a new public `AQL:` method (see Section 2) but requires no change to `WowQuestAPI.lua`.

**Note on `GetQuestLogTitle` and `GetNumQuestLogEntries`:** These WoW globals are already called as raw globals inside the existing `WowQuestAPI.GetQuestInfo` and `WowQuestAPI.GetQuestLogIndex` function bodies. Those existing functions are **not** updated to use the new wrappers — updating existing `WowQuestAPI` internals is out of scope for this spec. The new wrappers are for use in new AQL-layer compound methods that need to iterate quest log entries, so those compound methods are not required to reference WoW globals directly.

**Note on `QuestLog_SetSelection` and `QuestLog_Update`:** These are not exposed as standalone public `AQL:` methods — `AQL:SetQuestLogSelection` is the canonical two-call sequence and the intended sole consumer of these two wrappers. They are added to `WowQuestAPI` for completeness (AQL design principle) but are internal implementation details at the AQL layer.

**Note on `GetQuestDifficultyColor`:** The fallback logic (manual grey/green/yellow/orange/red based on player level delta) currently lives in SocialQuest's `RowFactory.lua`. It is moved here as part of this work since it references `UnitLevel("player")` — a WoW global that belongs in `WowQuestAPI`, not in a UI file.

**Note on `GetPlayerLevel`:** `UnitLevel("player")` is referenced by the new level-range filtering methods. It is wrapped here so no other AQL file references WoW globals directly.

---

### 2. `AbsoluteQuestLog.lua` — Public API reorganization

All existing and new public methods are reorganized into two clearly labeled top-level groups with sub-sections. The goal is fast discoverability: a developer scanning the file immediately sees whether a method is about quest data or about interacting with the quest log frame.

#### Group 1: Quest APIs

Data and state queries about quests. No interaction with the quest log frame.

| Sub-section | Methods |
|---|---|
| Quest State | `GetQuest`, `GetAllQuests`, `GetQuestsByZone`, `IsQuestActive`, `IsQuestFinished`, `GetQuestType` |
| Quest History | `HasCompletedQuest`, `GetCompletedQuests`, `GetCompletedQuestCount` |
| Quest Resolution | `GetQuestInfo`, `GetQuestTitle`, `GetQuestLink` |
| Objectives | `GetObjectives`, `GetObjective`, `GetQuestObjectives`, `IsQuestObjectiveText` |
| Chain Info | `GetChainInfo`, `GetChainStep`, `GetChainLength` |
| Quest Tracking | `TrackQuest`, `UntrackQuest`, `IsUnitOnQuest` |
| Player & Level | `GetPlayerLevel`, `GetQuestsInQuestLogBelowLevel`, `GetQuestsInQuestLogAboveLevel`, `GetQuestsInQuestLogBetweenLevels`, `GetQuestsInQuestLogBelowLevelDelta`, `GetQuestsInQuestLogAboveLevelDelta`, `GetQuestsInQuestLogWithinLevelRange` |

#### Group 2: Quest Log APIs

Methods that interact with the built-in WoW quest log frame. Divided into three tiers:

**Thin Wrappers** — one-to-one with WoW globals. Take `logIndex` or no parameters.

| Method | Description |
|---|---|
| `ShowQuestLog()` | Opens the quest log frame. Delegates to `WowQuestAPI.ShowQuestLog()`. |
| `HideQuestLog()` | Closes the quest log frame. Delegates to `WowQuestAPI.HideQuestLog()`. |
| `IsQuestLogShown()` | Returns true if the quest log is currently visible. Delegates to `WowQuestAPI.IsQuestLogShown()`. |
| `GetQuestLogSelection()` | Returns the currently selected logIndex (0 if none). Delegates to `WowQuestAPI.GetQuestLogSelection()`. |
| `SelectQuestLogEntry(logIndex)` | Sets the selected entry; does not refresh the display. Delegates to `WowQuestAPI.SelectQuestLogEntry(logIndex)`. |
| `IsQuestLogShareable()` | Returns true if the currently selected quest can be shared. Delegates to `WowQuestAPI.GetQuestLogPushable()`. **Result depends entirely on the current quest log selection** — if nothing is selected or the wrong entry is selected, the result is meaningless. Prefer `IsQuestIndexShareable` or `IsQuestIdShareable` when operating on a specific quest; this method exists only for callers that have already managed selection themselves. The inline doc comment must include this selection-dependency warning. This warning takes precedence over the general "comments are concise" guideline for this specific method because the selection dependency is a sharp edge that cannot be communicated by name alone. This method emits no debug message — it is a pass-through with no no-op condition to report. |
| `SetQuestLogSelection(logIndex)` | Sets selection AND refreshes display. Calls `WowQuestAPI.QuestLog_SetSelection(logIndex)` followed immediately by `WowQuestAPI.QuestLog_Update()`. These two WowQuestAPI calls are always used together; this method calls them directly rather than through any intermediate AQL thin wrappers, because `QuestLog_SetSelection` and `QuestLog_Update` are not exposed as standalone public AQL methods. This method is the canonical two-call sequence. `SelectAndShowQuestLogEntryByIndex` delegates to it. Emits a verbose debug message on every call. |
| `ExpandQuestLogHeader(logIndex)` | Expands a collapsed zone header row. Delegates to `WowQuestAPI.ExpandQuestHeader(logIndex)`. |
| `CollapseQuestLogHeader(logIndex)` | Collapses a zone header row. Delegates to `WowQuestAPI.CollapseQuestHeader(logIndex)`. |
| `GetQuestDifficultyColor(level)` | Returns `{r, g, b}` for the given quest level relative to the player. Delegates to `WowQuestAPI.GetQuestDifficultyColor(level)`. |
| `GetQuestLogIndex(questID)` | Returns the 1-based quest log index for a questID, or nil if not in the player's quest log. Delegates to `WowQuestAPI.GetQuestLogIndex(questID)`. Zone header rows carry no questID and are automatically excluded from matching. |

**Compound — ByIndex** — multi-step operations taking `logIndex`. Handle common ceremony that consumers would otherwise repeat.

For methods that need to iterate all quest log entries (`GetQuestLogEntries`, zone-by-name methods, expand/collapse-all methods), the iteration uses `WowQuestAPI.GetNumQuestLogEntries()` and `WowQuestAPI.GetQuestLogTitle(logIndex)`.

**Note on header collapse and `QuestCache:Rebuild()`:** `QuestCache:Rebuild()` expands all collapsed zone headers before scanning the quest log, then re-collapses them. This means any headers collapsed by `CollapseQuestLogZoneByName`, `CollapseAllQuestLogHeaders`, or `ToggleQuestLogZoneByName` will be silently re-expanded by the next `QUEST_LOG_UPDATE` event that triggers a `Rebuild()`. Consumers should be aware that programmatic header collapse is ephemeral and will not survive a cache rebuild.

| Method | Behavior |
|---|---|
| `IsQuestIndexShareable(logIndex)` | Saves current quest log selection via `WowQuestAPI.GetQuestLogSelection()` → selects `logIndex` via `WowQuestAPI.SelectQuestLogEntry(logIndex)` → calls `WowQuestAPI.GetQuestLogPushable()` → restores previous selection via `WowQuestAPI.SelectQuestLogEntry(savedIndex)`. Returns bool. The save/restore ensures the quest log's visual state is unchanged after the call. |
| `SelectAndShowQuestLogEntryByIndex(logIndex)` | Delegates to `AQL:SetQuestLogSelection(logIndex)`. Named explicitly for the compound context so callers in a multi-step sequence have a clearly named entry point. Emits no debug message of its own — the verbose message from `SetQuestLogSelection` is the message emitted on this path. |
| `OpenQuestLogByIndex(logIndex)` | Calls `WowQuestAPI.ShowQuestLog()` to open the quest log frame, then calls `AQL:SelectAndShowQuestLogEntryByIndex(logIndex)`. Emits a verbose debug message before opening. |
| `ToggleQuestLogByIndex(logIndex)` | If `WowQuestAPI.IsQuestLogShown()` is true and `WowQuestAPI.GetQuestLogSelection()` equals `logIndex` → calls `WowQuestAPI.HideQuestLog()` and emits a verbose debug message. Otherwise → delegates to `AQL:OpenQuestLogByIndex(logIndex)` with no separate message (the `OpenQuestLogByIndex` verbose message is the one emitted on the open path). |
| `GetSelectedQuestId()` | Calls `WowQuestAPI.GetQuestLogSelection()` to get the current logIndex. If logIndex is 0, emits a normal-level debug message and returns nil. Otherwise calls `WowQuestAPI.GetQuestLogTitle(logIndex)` and returns the 8th return value (questID). If that questID is nil (the selected entry is a zone header row), emits a normal-level debug message and returns nil. |
| `GetQuestLogEntries()` | Returns a structured array of all quest log entries in display order. Iterates from 1 to `WowQuestAPI.GetNumQuestLogEntries()`, calling `WowQuestAPI.GetQuestLogTitle(i)` for each entry. Each element: `{ logIndex=N, isHeader=bool, title="string", questID=N_or_nil, isCollapsed=bool_or_nil }`. For quest rows (non-headers), `isCollapsed` is nil. For header rows, `questID` is nil. Emits no debug message — this is a pure data query with no no-op condition. |
| `GetQuestLogZoneNames()` | Returns an ordered array of all zone header name strings currently in the quest log. Iterates entries; collects header titles in display order. Emits no debug message — pure data query. |
| `ExpandAllQuestLogHeaders()` | Iterates all entries; for each header row that is collapsed, calls `WowQuestAPI.ExpandQuestHeader(logIndex)`. Emits a verbose debug message listing the count of headers expanded. |
| `CollapseAllQuestLogHeaders()` | Iterates all entries; for each header row, calls `WowQuestAPI.CollapseQuestHeader(logIndex)`. Emits a verbose debug message listing the count of headers collapsed. |
| `ExpandQuestLogZoneByName(zoneName)` | Iterates entries to find the header row where `title == zoneName`; calls `WowQuestAPI.ExpandQuestHeader(logIndex)`. No-op with normal-level debug message if `zoneName` is not found. |
| `CollapseQuestLogZoneByName(zoneName)` | Iterates entries to find the header row where `title == zoneName`; calls `WowQuestAPI.CollapseQuestHeader(logIndex)`. No-op with normal-level debug message if `zoneName` is not found. |
| `ToggleQuestLogZoneByName(zoneName)` | Iterates entries to find the header row where `title == zoneName`; expands if collapsed, collapses if expanded. No-op with normal-level debug message if `zoneName` is not found. |
| `IsQuestLogZoneCollapsed(zoneName)` | Returns true if the zone header matching `zoneName` is currently collapsed, false if expanded, nil if not found. Emits a normal-level debug message when `zoneName` is not found. |

**Compound — ById** — same operations as ByIndex but accept `questID`. Internally resolve `questID` to `logIndex` via `WowQuestAPI.GetQuestLogIndex`. **If the questID is not in the player's active quest log, all ById methods are silent no-ops** (bool methods return `false`, void methods do nothing). A debug message is emitted at normal level so consumers can observe this during development.

| Method | Behavior |
|---|---|
| `IsQuestIdShareable(questID)` | Resolves logIndex via `WowQuestAPI.GetQuestLogIndex(questID)`; returns `false` if not in quest log. Delegates to `IsQuestIndexShareable`. |
| `SelectAndShowQuestLogEntryById(questID)` | Resolves logIndex; no-op if not in quest log. Delegates to `SelectAndShowQuestLogEntryByIndex`. |
| `OpenQuestLogById(questID)` | Resolves logIndex; no-op if not in quest log. Delegates to `OpenQuestLogByIndex`. |
| `ToggleQuestLogById(questID)` | Resolves logIndex; no-op if not in quest log. Delegates to `ToggleQuestLogByIndex`. |

---

### 3. Level-Range Filtering Methods (Quest APIs Group)

These methods filter the active quest cache by quest level. All use `questInfo.level` — the recommended difficulty level shown in the quest log (from `GetQuestLogTitle`), not `requiredLevel`. Player level is retrieved via `WowQuestAPI.GetPlayerLevel()`.

**`AQL:GetPlayerLevel()` — delegates to `WowQuestAPI.GetPlayerLevel()` and returns the player's current level as a number. Emits no debug message — pure data query.**

**Absolute-level methods** (take an explicit level number). Comparisons are strict: "below" means strictly less than (`<`), "above" means strictly greater than (`>`). `BetweenLevels` is inclusive on both endpoints. A quest at exactly `level` is not included by `BelowLevel(level)` or `AboveLevel(level)`. `GetQuestsInQuestLogBetweenLevels` returns an empty table (not nil) when `minLevel > maxLevel` — callers are responsible for passing valid bounds. These methods emit no debug messages — they are pure data queries over the quest cache.

| Method | Returns | Filter |
|---|---|---|
| `GetQuestsInQuestLogBelowLevel(level)` | `{[questID]=QuestInfo}` | `questInfo.level < level` |
| `GetQuestsInQuestLogAboveLevel(level)` | `{[questID]=QuestInfo}` | `questInfo.level > level` |
| `GetQuestsInQuestLogBetweenLevels(minLevel, maxLevel)` | `{[questID]=QuestInfo}` | `minLevel <= questInfo.level <= maxLevel`; empty table if `minLevel > maxLevel` |

**Delta methods** (take a `delta` relative to the player's current level). `delta` should be a non-negative integer; negative values produce well-defined but counter-intuitive results (e.g., `BelowLevelDelta(-5)` at player level 40 returns quests below level 45, not below level 35). Each delta method calculates the absolute threshold and delegates to the corresponding absolute method. These methods emit no debug messages — pure data queries.

| Method | Delegates To | Use Case |
|---|---|---|
| `GetQuestsInQuestLogBelowLevelDelta(delta)` | `GetQuestsInQuestLogBelowLevel(playerLevel - delta)` | Quests more than `delta` levels below the player (e.g., delta=5 at level 40 → quests strictly below level 35 — quests the player has outleveled) |
| `GetQuestsInQuestLogAboveLevelDelta(delta)` | `GetQuestsInQuestLogAboveLevel(playerLevel + delta)` | Quests more than `delta` levels above the player (e.g., delta=5 at level 40 → quests strictly above level 45 — quests the player may struggle with) |
| `GetQuestsInQuestLogWithinLevelRange(delta)` | `GetQuestsInQuestLogBetweenLevels(playerLevel - delta, playerLevel + delta)` | Quests within ±`delta` levels of the player (the "currently worth doing" set; endpoints inclusive) |

**Note on `questInfo.level` vs `requiredLevel`:** `questInfo.level` is the recommended level for the quest (the orange number shown in the quest log). `requiredLevel` is the minimum level to accept it. For level-range filtering, `questInfo.level` is the correct field.

---

## Debug Behavior

All new public Quest Log methods emit debug messages using the existing `AQL.debug` system, except pure data query methods (Get* / Is* with no side effects and no no-op condition) which emit no messages. Methods with no-op conditions always emit at normal level. Methods with successful mutation/navigation operations emit at verbose level.

**Methods that emit NO debug messages:**

Thin wrappers emit no messages — they are direct pass-throughs with no conditional logic to trace:
`ShowQuestLog`, `HideQuestLog`, `IsQuestLogShown`, `GetQuestLogSelection`, `SelectQuestLogEntry`, `IsQuestLogShareable`, `ExpandQuestLogHeader`, `CollapseQuestLogHeader`, `GetQuestDifficultyColor`, `GetQuestLogIndex`.

Methods whose side effects are fully reversed (selection save/restore) and that have no no-op branch emit no messages:
`IsQuestIndexShareable`.

Pure data queries with no no-op condition emit no messages:
`GetPlayerLevel`, `GetQuestLogEntries`, `GetQuestLogZoneNames`, all level-range filtering methods (`GetQuestsInQuestLog*`), `SelectAndShowQuestLogEntryByIndex` (delegates fully to `SetQuestLogSelection` which emits its own message).

Methods with a not-found condition emit a normal-level message (examples in the block below):
`GetSelectedQuestId` (nothing selected; selected entry is a header), `ExpandQuestLogZoneByName`, `CollapseQuestLogZoneByName`, `ToggleQuestLogZoneByName`, `IsQuestLogZoneCollapsed`.

**Debug message examples, labeled by level:**

```
-- Normal level (no-op or not-found conditions):
[AQL] IsQuestIdShareable: questID=1234 not in quest log — returning false
[AQL] SelectAndShowQuestLogEntryById: questID=1234 not in quest log — no-op
[AQL] OpenQuestLogById: questID=1234 not in quest log — no-op
[AQL] ToggleQuestLogById: questID=1234 not in quest log — no-op
[AQL] ExpandQuestLogZoneByName: zone "Duskwood" not found in quest log — no-op
[AQL] CollapseQuestLogZoneByName: zone "Duskwood" not found in quest log — no-op
[AQL] ToggleQuestLogZoneByName: zone "Duskwood" not found in quest log — no-op
[AQL] IsQuestLogZoneCollapsed: zone "Duskwood" not found in quest log — returning nil
[AQL] GetSelectedQuestId: no entry selected — returning nil
[AQL] GetSelectedQuestId: selected entry logIndex=2 is a zone header — returning nil

-- Verbose level (successful operations):
[AQL] SetQuestLogSelection: logIndex=3
[AQL] OpenQuestLogByIndex: showing quest log, navigating to logIndex=3
[AQL] ToggleQuestLogByIndex: quest log is shown and logIndex=3 is selected — hiding
[AQL] ExpandAllQuestLogHeaders: expanded 4 headers
[AQL] CollapseAllQuestLogHeaders: collapsed 4 headers
```

`ToggleQuestLogByIndex` on the open path delegates to `OpenQuestLogByIndex`, which emits its own verbose message. `ToggleQuestLogByIndex` emits no separate message on the open path.

---

## Documentation Standard

Each public method has a header comment block with:
- One-line description
- Parameters and return values
- Any behavior notes (selection state dependency, no-op conditions, delegation chain, etc.)

Comments are concise — enough for a developer to use the method correctly without reading the implementation. Verbose implementation details belong in inline comments, not the header block. Exception: `IsQuestLogShareable` must include the selection-dependency warning in its header comment because the selection dependency is a sharp edge that cannot be communicated by name alone.

Example:
```lua
-- IsQuestIndexShareable(logIndex) → bool
-- Returns true if the quest at logIndex can be shared with party members.
-- Saves and restores the current selection so the quest log's visual state is unchanged.
function AQL:IsQuestIndexShareable(logIndex)
```

---

## CLAUDE.md Updates

The Public API table in `CLAUDE.md` is updated to reflect:
- The two-group (Quest APIs / Quest Log APIs) structure
- All new Quest Log thin wrapper methods (including `GetQuestLogIndex`)
- All new compound ByIndex and ById methods
- The no-op/false behavior for ById methods when questID is not in quest log
- The new Player & Level sub-section under Quest APIs
- All six level-range filtering methods and `GetPlayerLevel`
