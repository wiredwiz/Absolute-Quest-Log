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
4. Reorganizing all existing public `AQL` methods into a clear two-group structure for developer discoverability.

SocialQuest call-site migration (replacing direct WoW globals with AQL calls) is **out of scope** for this spec and will be addressed in a separate task.

---

## Goals

- All WoW quest log globals accessible through AQL, with no consumer needing to reference them directly.
- A public API that is easy for a new developer to discover and use, with concise but complete inline documentation.
- Compound methods that hide common ceremony (selection save/restore, selection+display pairing, log open+navigate) while still exposing the individual primitives for consumers with different needs.
- Debug messages on all new public methods so consumers can trace behavior during development.

---

## File Changes

### 1. `Core/WowQuestAPI.lua`

A new section — **Quest Log Frame & Navigation** — is added at the bottom of the file. Each wrapper has the exact same name as the WoW global it wraps, keeping the mapping obvious to any developer familiar with the WoW API. All version branching and fallback logic lives here.

**New wrappers:**

| WowQuestAPI function | Wraps | Notes |
|---|---|---|
| `GetQuestLogSelection()` | `GetQuestLogSelection()` | Returns current logIndex |
| `SelectQuestLogEntry(logIndex)` | `SelectQuestLogEntry(logIndex)` | Sets selection; no UI refresh |
| `GetQuestLogPushable()` | `GetQuestLogPushable()` | Checks currently-selected entry; normalized to bool |
| `QuestLog_SetSelection(logIndex)` | `QuestLog_SetSelection(logIndex)` | UI selection update |
| `QuestLog_Update()` | `QuestLog_Update()` | Refreshes quest log display |
| `ExpandQuestHeader(logIndex)` | `ExpandQuestHeader(logIndex)` | Expands a collapsed zone header |
| `CollapseQuestHeader(logIndex)` | `CollapseQuestHeader(logIndex)` | Collapses a zone header |
| `ShowQuestLog()` | `ShowUIPanel(QuestLogFrame)` | Named semantically; hides the generic ShowUIPanel detail |
| `HideQuestLog()` | `HideUIPanel(QuestLogFrame)` | Named semantically |
| `IsQuestLogShown()` | `QuestLogFrame:IsShown()` | Returns bool |
| `GetQuestDifficultyColor(level)` | `GetQuestDifficultyColor(level)` | Returns `{r,g,b}`; includes manual fallback if API absent |

**Note on `GetQuestDifficultyColor`:** The fallback logic (manual grey/green/yellow/orange/red based on player level delta) currently lives in SocialQuest's `RowFactory.lua`. It is moved here as part of this work since it references `UnitLevel("player")` — a WoW global that belongs in `WowQuestAPI`, not in a UI file.

---

### 2. `AbsoluteQuestLog.lua` — Public API reorganization

All existing and new public methods are reorganized into two clearly labeled top-level groups with sub-sections. The goal is fast discoverability: a developer scanning the file immediately sees whether a method is about quest data or about interacting with the log frame.

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

#### Group 2: Quest Log APIs

Methods that interact with the built-in WoW quest log frame. Divided into three tiers:

**Thin Wrappers** — one-to-one with WoW globals. Take `logIndex` or no parameters.

| Method | Description |
|---|---|
| `ShowQuestLog()` | Opens the quest log frame |
| `HideQuestLog()` | Closes the quest log frame |
| `IsQuestLogShown()` | Returns true if the quest log is currently visible |
| `GetQuestLogSelection()` | Returns the currently selected logIndex (0 if none) |
| `SelectQuestLogEntry(logIndex)` | Sets the selected entry; does not refresh the display |
| `IsQuestLogShareable()` | Returns true if the currently selected quest can be shared. **Result depends entirely on the current log selection** — if nothing is selected or the wrong entry is selected the result is meaningless. Prefer `IsQuestIndexShareable` or `IsQuestIdShareable` when operating on a specific quest; this method exists only for callers that have already managed selection themselves. The inline doc comment must reproduce this warning verbatim so it is visible to developers scanning the file without reading this spec. |
| `SetQuestLogSelection(logIndex)` | Sets selection AND refreshes display (`QuestLog_SetSelection` + `QuestLog_Update` as one call — they are always used together). This method is the canonical two-call sequence; `SelectAndShowQuestLogEntryByIndex` delegates to it. |
| `ExpandQuestLogHeader(logIndex)` | Expands a collapsed zone header row |
| `CollapseQuestLogHeader(logIndex)` | Collapses a zone header row |
| `GetQuestDifficultyColor(level)` | Returns `{r, g, b}` for the given quest level relative to the player |

**Compound — ByIndex** — multi-step operations taking `logIndex`. Handle common ceremony that consumers would otherwise repeat.

| Method | Behavior |
|---|---|
| `IsQuestIndexShareable(logIndex)` | Saves current selection → selects logIndex → checks shareability → restores selection. Returns bool. |
| `SelectAndShowQuestLogEntryByIndex(logIndex)` | Delegates to `SetQuestLogSelection(logIndex)`. Named explicitly for the compound context so callers in a multi-step sequence have a clearly named entry point. |
| `OpenQuestLogByIndex(logIndex)` | Shows the log frame, then calls `SelectAndShowQuestLogEntryByIndex`. |
| `ToggleQuestLogByIndex(logIndex)` | If the log is shown and `logIndex` is the current selection → hides the log. Otherwise calls `OpenQuestLogByIndex`. |

**Compound — ById** — same operations as ByIndex but accept `questID`. Internally resolve `questID` to `logIndex` via `WowQuestAPI.GetQuestLogIndex`. **If the questID is not in the player's active quest log, all ById methods are silent no-ops** (bool methods return `false`, void methods do nothing). A debug message is emitted at normal level so consumers can observe this during development.

| Method | Behavior |
|---|---|
| `IsQuestIdShareable(questID)` | Resolves logIndex; returns `false` if not in log. Delegates to `IsQuestIndexShareable`. |
| `SelectAndShowQuestLogEntryById(questID)` | Resolves logIndex; no-op if not in log. Delegates to `SelectAndShowQuestLogEntryByIndex`. |
| `OpenQuestLogById(questID)` | Resolves logIndex; no-op if not in log. Delegates to `OpenQuestLogByIndex`. |
| `ToggleQuestLogById(questID)` | Resolves logIndex; no-op if not in log. Delegates to `ToggleQuestLogByIndex`. |

---

## Debug Behavior

All new public Quest Log methods emit debug messages using the existing `AQL.debug` system.

- **Verbose level** — normal successful operations (e.g., "opening log to logIndex=3")
- **Normal level** — no-op conditions that a consumer is likely to want to know about (e.g., questID not in log)

Example messages:
```
[AQL] IsQuestIdShareable: questID=1234 not in log — returning false
[AQL] SelectAndShowQuestLogEntryById: questID=1234 not in log — no-op
[AQL] OpenQuestLogById: questID=1234 not in log — no-op
[AQL] ToggleQuestLogById: questID=1234 not in log — no-op
[AQL] ToggleQuestLogByIndex: log is shown and logIndex=3 is selected — hiding
[AQL] OpenQuestLogByIndex: showing log, navigating to logIndex=3
```

---

## Documentation Standard

Each public method has a header comment block with:
- One-line description
- Parameters and return values
- Any behavior notes (selection state dependency, no-op conditions, etc.)

Comments are concise — enough for a developer to use the method correctly without reading the implementation. Verbose implementation details belong in inline comments, not the header block.

Example:
```lua
-- IsQuestIndexShareable(logIndex) → bool
-- Returns true if the quest at logIndex can be shared with party members.
-- Saves and restores the current selection so the log's visual state is unchanged.
function AQL:IsQuestIndexShareable(logIndex)
```

---

## CLAUDE.md Updates

The Public API table in `CLAUDE.md` is updated to reflect:
- The two-group (Quest APIs / Quest Log APIs) structure
- All new Quest Log thin wrapper methods
- All new compound ByIndex and ById methods
- The no-op/false behavior for ById methods when questID is not in log
