# AbsoluteQuestLog — WoW TBC Library Addon

## Project Overview

**AbsoluteQuestLog-1.0 (AQL)** is a LibStub library for World of Warcraft: The Burning Crusade Anniversary edition. It provides a unified, event-driven quest data API for consumer addons. Consumers access it via `LibStub("AbsoluteQuestLog-1.0")`.

**Interface**: 20505 (TBC Anniversary)
**Author**: Thad Ryker
**Status**: Active development

> **IMPORTANT FOR CLAUDE:** This file must be updated whenever significant changes are made to the project — architecture changes, new modules, protocol changes, new public API, or notable bug fixes. Update the version number in `AbsoluteQuestLog.toc` after every set of meaningful changes using the versioning rule below. Do not leave this file stale.

> **Versioning Rule:** The major version number should never be changed by Claude unless explicitly instructed to do so. The first time the library is modified on any given day, the minor version number should be incremented and the revision number should be reset to 0. Any extra changes occurring within the same day should increment the revision number only, unless explicitly instructed otherwise.

---

## Architecture

### Bundled Libraries (`Libs\`)

| File | Purpose |
|---|---|
| `Libs\LibStub\LibStub.lua` | Library bootstrapper. Self-versioning — safe to bundle; deduplicates automatically if another addon loads a newer version. |
| `Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua` | Callback registration and firing. Registered through LibStub; same deduplication guarantee. |

AQL has no external addon dependencies. The `Libs\` copies are the sole requirement for standalone use.

### Entry Point

`AbsoluteQuestLog.lua` — Registers the library with LibStub (`"AbsoluteQuestLog-1.0"`, minor=1). Sets up CallbackHandler (`AQL.callbacks`). Declares sub-module slots (`QuestCache`, `HistoryCache`, `EventEngine`, `provider`) as nil — populated by subsequent files per TOC load order. Contains all public API methods.

### Core Modules (`Core\`)

| File | Object | Responsibility |
|---|---|---|
| `Core\WowQuestAPI.lua` | `WowQuestAPI` (global) | Thin, stateless wrappers around WoW quest globals. All version-specific branching (TBC vs Retail) lives here. No other AQL file references WoW quest globals directly. |
| `Core\EventEngine.lua` | `AQL.EventEngine` | Owns the hidden WoW event frame. Selects the provider at `PLAYER_LOGIN`, manages deferred provider upgrades, rebuilds `QuestCache` on relevant events, diffs old vs. new state, and fires AQL callbacks. |
| `Core\QuestCache.lua` | `AQL.QuestCache` | Builds and stores `QuestInfo` snapshots from `C_QuestLog`. `Rebuild()` expands collapsed zone headers before scanning, then re-collapses them. Returns the previous snapshot for diffing. |
| `Core\HistoryCache.lua` | `AQL.HistoryCache` | Tracks all quests ever completed by this character. Loaded synchronously via `GetQuestsCompleted()` at `PLAYER_LOGIN`; updated incrementally via `MarkCompleted()`. |

### Providers (`Providers\`)

| File | Object | When Active |
|---|---|---|
| `Providers\Provider.lua` | (docs only) | Interface contract for all providers. No runtime code. |
| `Providers\QuestieProvider.lua` | `AQL.QuestieProvider` | When Questie is installed. Reads quest DB via `QuestieLoader:ImportModule("QuestieDB")`. Guards on `db.QuestPointers` for readiness (Questie's async init). |
| `Providers\QuestWeaverProvider.lua` | `AQL.QuestWeaverProvider` | When QuestWeaver is installed and Questie is absent. Reads from `_G["QuestWeaver"].Quests`. |
| `Providers\NullProvider.lua` | `AQL.NullProvider` | Fallback when no quest DB addon is present. Always returns `knownStatus = "unknown"`. |

Provider selection runs at `PLAYER_LOGIN` via `selectProvider()`. Because Questie's DB initializes asynchronously (~3 s), `EventEngine` retries every 1 s for up to 5 s via `tryUpgradeProvider()`. A belt-and-suspenders inline check also fires on each `QUEST_LOG_UPDATE` in case the upgrade window was missed.

---

## Public API

### Group 1: Quest APIs

Data and state queries about quests. No interaction with the quest log frame.

#### Quest State

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetQuest(questID)` | `QuestInfo` or nil | Cache-only; nil if quest not in player's log |
| `AQL:GetAllQuests()` | `{[questID]=QuestInfo}` | Full cache snapshot |
| `AQL:GetQuestsByZone(zone)` | `{[questID]=QuestInfo}` | Filters cache by zone |
| `AQL:IsQuestActive(questID)` | bool | True if quest is in active log |
| `AQL:IsQuestFinished(questID)` | bool | True if objectives complete, not yet turned in |
| `AQL:GetQuestType(questID)` | string or nil | From cache only |

#### Quest History

| Method | Returns | Notes |
|---|---|---|
| `AQL:HasCompletedQuest(questID)` | bool | HistoryCache + `IsQuestFlaggedCompleted` fallback |
| `AQL:GetCompletedQuests()` | `{[questID]=true}` | All completed quests this session |
| `AQL:GetCompletedQuestCount()` | number | Count of completed quests |

#### Quest Resolution

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetQuestInfo(questID)` | `QuestInfo` or nil | Tier 1: cache → Tier 2: WoW log scan / title fallback → Tier 3: provider |
| `AQL:GetQuestTitle(questID)` | string or nil | Delegates to `GetQuestInfo` |
| `AQL:GetQuestLink(questID)` | hyperlink or nil | Tier 1: cache link → Tier 2/3: `GetQuestInfo` |

#### Objectives

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetObjectives(questID)` | array or nil | |
| `AQL:GetObjective(questID, index)` | table or nil | |
| `AQL:GetQuestObjectives(questID)` | array | Cache first; `WowQuestAPI` fallback |
| `AQL:IsQuestObjectiveText(msg)` | bool | Matches `UI_INFO_MESSAGE` text against active objectives |

#### Chain Info

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetChainInfo(questID)` | `ChainInfo` | Cache first; returns `{knownStatus="unknown"}` if not found |
| `AQL:GetChainStep(questID)` | number or nil | |
| `AQL:GetChainLength(questID)` | number or nil | |

#### Quest Tracking

| Method | Returns | Notes |
|---|---|---|
| `AQL:TrackQuest(questID)` | bool | Returns false if at `MAX_WATCHABLE_QUESTS` cap |
| `AQL:UntrackQuest(questID)` | — | |
| `AQL:IsUnitOnQuest(questID, unit)` | bool or nil | nil on TBC (API unavailable) |

#### Player & Level

All level filters use `questInfo.level` (recommended difficulty level). Strict comparisons for Below/Above; inclusive for Between. Delta methods delegate to absolute methods.

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetPlayerLevel()` | number | Player's current level |
| `AQL:GetQuestsInQuestLogBelowLevel(level)` | `{[questID]=QuestInfo}` | `questInfo.level < level` |
| `AQL:GetQuestsInQuestLogAboveLevel(level)` | `{[questID]=QuestInfo}` | `questInfo.level > level` |
| `AQL:GetQuestsInQuestLogBetweenLevels(min, max)` | `{[questID]=QuestInfo}` | `min <= questInfo.level <= max`; `{}` if min > max |
| `AQL:GetQuestsInQuestLogBelowLevelDelta(delta)` | `{[questID]=QuestInfo}` | Delegates to `BelowLevel(playerLevel - delta)` |
| `AQL:GetQuestsInQuestLogAboveLevelDelta(delta)` | `{[questID]=QuestInfo}` | Delegates to `AboveLevel(playerLevel + delta)` |
| `AQL:GetQuestsInQuestLogWithinLevelRange(delta)` | `{[questID]=QuestInfo}` | Delegates to `BetweenLevels(playerLevel - delta, playerLevel + delta)` |

---

### Group 2: Quest Log APIs

Methods that interact with the built-in WoW quest log frame.

**logIndex note:** logIndex is always a position in the *currently visible* entries. Quests under collapsed zone headers are invisible to the WoW API; `GetQuestLogIndex` returns nil for them.

#### Thin Wrappers

| Method | Returns | Notes |
|---|---|---|
| `AQL:ShowQuestLog()` | — | Opens the quest log frame |
| `AQL:HideQuestLog()` | — | Closes the quest log frame |
| `AQL:IsQuestLogShown()` | bool | True if quest log is visible |
| `AQL:GetQuestLogSelection()` | logIndex | 0 if nothing selected |
| `AQL:SelectQuestLogEntry(logIndex)` | — | Sets selection; no display refresh |
| `AQL:IsQuestLogShareable()` | bool | **Selection-dependent** — only meaningful when correct entry is already selected; prefer `IsQuestIndexShareable` / `IsQuestIdShareable` |
| `AQL:SetQuestLogSelection(logIndex)` | — | Sets selection + refreshes display (canonical `QuestLog_SetSelection` + `QuestLog_Update` pair) |
| `AQL:ExpandQuestLogHeader(logIndex)` | — | Guards: no-op + normal debug if not a header |
| `AQL:CollapseQuestLogHeader(logIndex)` | — | Guards: no-op + normal debug if not a header |
| `AQL:GetQuestDifficultyColor(level)` | `{r,g,b}` | Fallback to manual delta if native API absent |
| `AQL:GetQuestLogIndex(questID)` | logIndex or nil | nil if not in log or under collapsed header |

#### Compound — ByIndex

| Method | Returns | Notes |
|---|---|---|
| `AQL:IsQuestIndexShareable(logIndex)` | bool | Save/check/restore; guards against header rows |
| `AQL:SelectAndShowQuestLogEntryByIndex(logIndex)` | — | Delegates to `SetQuestLogSelection` |
| `AQL:OpenQuestLogByIndex(logIndex)` | — | Shows log + navigates to logIndex |
| `AQL:ToggleQuestLogByIndex(logIndex)` | — | Hides if shown+selected; else opens |
| `AQL:GetSelectedQuestId()` | questID or nil | nil if nothing selected or header selected |
| `AQL:GetQuestLogEntries()` | array | All visible entries: `{logIndex, isHeader, title, questID, isCollapsed}` |
| `AQL:GetQuestLogZones()` | array of `{name, isCollapsed}` | Ordered zone header entries; useful for save/restore of collapsed state |
| `AQL:ExpandAllQuestLogHeaders()` | — | Expands all collapsed headers |
| `AQL:CollapseAllQuestLogHeaders()` | — | Collapses all headers |
| `AQL:ExpandQuestLogZoneByName(zoneName)` | — | No-op + normal debug if not found |
| `AQL:CollapseQuestLogZoneByName(zoneName)` | — | No-op + normal debug if not found |
| `AQL:ToggleQuestLogZoneByName(zoneName)` | — | Expand/collapse; no-op + normal debug if not found |
| `AQL:IsQuestLogZoneCollapsed(zoneName)` | bool or nil | nil if not found |

#### Compound — ById

If questID is not in the active quest log, all ById methods are silent no-ops (false / nothing). A normal-level debug message is emitted.

| Method | Returns | Notes |
|---|---|---|
| `AQL:IsQuestIdShareable(questID)` | bool | Resolves logIndex; delegates to `IsQuestIndexShareable` |
| `AQL:SelectAndShowQuestLogEntryById(questID)` | — | Resolves logIndex; delegates to ByIndex variant |
| `AQL:OpenQuestLogById(questID)` | — | Resolves logIndex; delegates to ByIndex variant |
| `AQL:ToggleQuestLogById(questID)` | — | Resolves logIndex; delegates to ByIndex variant |

### Callbacks

Registered via CallbackHandler: `AQL:RegisterCallback(event, handler, target)` / `AQL:UnregisterCallback(event, handler)`

---

## Callbacks Reference

| Callback | Args | Fired When |
|---|---|---|
| `AQL_QUEST_ACCEPTED` | `(questInfo)` | Quest newly appears in log (excluding first-login rebuild) |
| `AQL_QUEST_ABANDONED` | `(questInfo)` | Quest removed from log without completion or known failure reason |
| `AQL_QUEST_COMPLETED` | `(questInfo)` | Quest removed from log and `IsQuestFlaggedCompleted` is true |
| `AQL_QUEST_FINISHED` | `(questInfo)` | `isComplete` transitions true (objectives met, not yet turned in) |
| `AQL_QUEST_FAILED` | `(questInfo)` | Quest removed and failure reason inferred (timeout / escort_died) |
| `AQL_QUEST_TRACKED` | `(questInfo)` | `isTracked` transitions true |
| `AQL_QUEST_UNTRACKED` | `(questInfo)` | `isTracked` transitions false |
| `AQL_OBJECTIVE_PROGRESSED` | `(questInfo, objInfo, delta)` | `numFulfilled` increased |
| `AQL_OBJECTIVE_COMPLETED` | `(questInfo, objInfo)` | `numFulfilled` reached `numRequired` |
| `AQL_OBJECTIVE_REGRESSED` | `(questInfo, objInfo, delta)` | `numFulfilled` decreased (suppressed during `pendingTurnIn`) |
| `AQL_OBJECTIVE_FAILED` | `(questInfo, objInfo)` | Objective failed alongside a failed quest |
| `AQL_UNIT_QUEST_LOG_CHANGED` | `(unit)` | `UNIT_QUEST_LOG_CHANGED` fired for a non-player unit |

---

## QuestInfo Data Structure

```lua
-- QuestCache entry (from player's active log):
{
    questID        = N,
    title          = "string",
    level          = N,
    suggestedGroup = N,          -- 0 if not a group quest
    zone           = "string",   -- zone header from quest log (player's log only)
    type           = "normal"|"elite"|"dungeon"|"raid"|"daily"|"pvp"|"escort"|nil,
    faction        = "Alliance"|"Horde"|nil,
    isComplete     = bool,       -- true = objectives met, not yet turned in
    isFailed       = bool,
    failReason     = "timeout"|"escort_died"|nil,
    isTracked      = bool,
    link           = "hyperlink string",
    logIndex       = N,          -- 1-based quest log index at snapshot time
    snapshotTime   = GetTime(),
    timerSeconds   = N or nil,   -- nil if no timer
    objectives     = {
        {
            index        = N,
            text         = "string",  -- e.g. "Tainted Ooze killed: 4/10"
            name         = "string",  -- text with count suffix stripped
            type         = "string",
            numFulfilled = N,
            numRequired  = N,
            isFinished   = bool,
            isFailed     = bool,
        }, ...
    },
    chainInfo      = ChainInfo,  -- see below
}

-- GetQuestInfo result for non-cached quests (Tier 2 / Tier 3):
-- Guaranteed: questID, title
-- May be nil: level, zone, chainInfo, requiredLevel
```

### ChainInfo Structure

```lua
-- knownStatus = "known":
{
    knownStatus = "known",
    chainID     = N,             -- questID of first quest in chain
    step        = N,             -- 1-based position of this quest
    length      = N,             -- total quests in chain
    steps       = {
        { questID = N, title = "string",
          status = "completed"|"active"|"finished"|"failed"|"available"|"unavailable"|"unknown" },
        ...
    },
    provider    = "Questie"|"QuestWeaver"|"none",
}
-- knownStatus = "not_a_chain": only knownStatus field present
-- knownStatus = "unknown": only knownStatus field present
```

---

## Provider Interface

Every provider must implement:

- `Provider:IsAvailable()` → bool
- `Provider:GetChainInfo(questID)` → ChainInfo
- `Provider:GetQuestType(questID)` → string or nil
- `Provider:GetQuestFaction(questID)` → "Alliance" | "Horde" | nil
- `Provider:GetQuestBasicInfo(questID)` → `{ title, questLevel, requiredLevel, zone }` or nil (optional — checked with `if provider.GetQuestBasicInfo then`)

All provider calls in EventEngine are wrapped in `pcall`. A provider that errors does not crash the library.

---

## Key Behaviors and Constraints

- **Zone from log vs. provider:** `QuestCache` sets `zone` from the log's zone-header row during `Rebuild()` — only works for quests in the **player's** log. `GetQuestInfo()` Tier 2 (`WowQuestAPI.GetQuestInfo`) also resolves zone from the log scan; when a quest is not in the log, Tier 2 returns a title-only result (no zone). Tier 3 (`GetQuestBasicInfo`) resolves zone from the provider's quest DB (e.g. Questie's `zoneOrSort` → `C_Map.GetAreaInfo`).
- **`GetQuestInfo` Tier 2 early-return:** When `WowQuestAPI.GetQuestInfo` finds the quest in the log it returns a full result; when it does not find it in the log but `C_QuestLog.GetQuestInfo(questID)` returns a title string, it returns `{ questID, title }` with **no zone field**. `AQL:GetQuestInfo` currently returns this result immediately, never reaching Tier 3. This is the root cause of remote quests showing "Other Quests" — the fix is to check for a missing zone and continue to Tier 3.
- **Collapsed zone headers:** `QuestCache:Rebuild()` expands all collapsed headers before scanning, then re-collapses them. Without this, collapsed zones appear invisible and trigger false `AQL_QUEST_ABANDONED` events.
- **Turn-in regression suppression:** `hooksecurefunc("GetQuestReward", ...)` sets `pendingTurnIn[questID]`. Objective regression events are suppressed while a questID is in this set. Cleared when `QUEST_REMOVED` fires.
- **Re-entrancy guard:** `EventEngine.diffInProgress` prevents a `QUEST_LOG_UPDATE` during a diff from being processed. Missed events are caught by the next natural event.
- **QUEST_TURNED_IN missing in TBC Classic:** Does not fire on Interface 20505. Turn-in is detected via `hooksecurefunc("GetQuestReward")` + `IsQuestFlaggedCompleted`.

---

## Debug System

`/aql debug [on|normal|verbose|off]` — Controls debug output to `DEFAULT_CHAT_FRAME`.

- `on` / `normal` — Log key events: quest accepted/completed/failed/abandoned, cache rebuild count, provider selection, objective changes.
- `verbose` — Everything above plus: each cache phase, every quest entry built, diff start/end, all event firings.
- `off` — No debug output (default).

Debug messages are prefixed `[AQL]` in gold (`AQL.DBG` color).

---

## WoW Events Registered

`PLAYER_LOGIN` is registered at load time. After `PLAYER_LOGIN` fires, `EventEngine` also registers: `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_LOG_UPDATE`, `UNIT_QUEST_LOG_CHANGED`, `QUEST_WATCH_LIST_CHANGED`.

---

## Version History

### Version 2.3.0 (March 2026)
- Bug fix: `AQL_QUEST_ACCEPTED` was firing for quests already in the player's log when `UNIT_QUEST_LOG_CHANGED` fired on party join, causing SocialQuest to announce existing quests as newly accepted. Root cause: `runDiff` fired the callback for any quest appearing "new in cache" regardless of whether the player had actually accepted it. Fix: added `EventEngine.pendingQuestAccepts` set. The `QUEST_ACCEPTED` WoW event handler records the questID; `runDiff` only fires `AQL_QUEST_ACCEPTED` when `pendingQuestAccepts[questID]` is set and clears it on fire. `QUEST_REMOVED` also clears any stale entry. Quests that appear new in a diff without a matching `QUEST_ACCEPTED` event are silently absorbed into the cache with a debug-mode log message.

### Version 2.2.8 (March 2026)
- Bug fix: splitting or combining stacks of quest items in bags caused false `AQL_OBJECTIVE_REGRESSED` and `AQL_OBJECTIVE_PROGRESSED` callbacks, even though actual quest progress had not changed. WoW fires two `QUEST_LOG_UPDATE` events during these operations — one with a temporarily incorrect item count, one with the correct count — and AQL was reacting to both. Replaced all cursor-detection logic with a 500 ms debounce: every `QUEST_LOG_UPDATE` call increments `debounceGeneration` and schedules a `C_Timer`; only the timer whose generation still matches fires the rebuild. Both bag-operation events collapse into one rebuild against the settled state, producing a net-zero diff and no false callbacks. The 500 ms window covers the full server round-trip latency between the two events. Cursor-based detection (`CursorHasItem()`) was never viable for this scenario because the cursor is already empty by the time WoW delivers the events.

### Version 2.2.2 (March 2026)
- Added addon logo for addon screen.

### Version 2.2.1 (March 2026)
- Added `AQL.Event` enumeration constant table for all 12 AQL callback event strings (`QuestAccepted`, `QuestAbandoned`, `QuestCompleted`, `QuestFinished`, `QuestFailed`, `QuestTracked`, `QuestUntracked`, `ObjectiveProgressed`, `ObjectiveCompleted`, `ObjectiveRegressed`, `ObjectiveFailed`, `UnitQuestLogChanged`); all raw `"AQL_*"` string literals in `EventEngine.lua` replaced with constants
- Replaced `GetQuestLogZoneNames()` (returned array of strings) with `GetQuestLogZones()` returning `{name, isCollapsed}` entries per zone header, enabling save/restore of collapsed state around bulk operations
- Added doc comments to all previously undocumented Group 1 public API methods

### Version 2.2.0 (March 2026)
- Added Quest Log Frame & Navigation wrappers to `WowQuestAPI.lua` (`GetNumQuestLogEntries`, `GetQuestLogTitle`, `GetQuestLogSelection`, `SelectQuestLogEntry`, `GetQuestLogPushable`, `QuestLog_SetSelection`, `QuestLog_Update`, `ExpandQuestHeader`, `CollapseQuestHeader`, `ShowQuestLog`, `HideQuestLog`, `IsQuestLogShown`, `GetQuestDifficultyColor`, `GetPlayerLevel`)
- Added Group 2 Quest Log APIs to AQL public interface: 11 thin wrappers, 13 compound ByIndex methods, 4 compound ById methods
- Added Group 1 Player & Level section: `GetPlayerLevel` + 6 level-range filtering methods
- Reorganized `AbsoluteQuestLog.lua` public API into two-group structure (Quest APIs / Quest Log APIs) with subsections

### Version 2.1.1 (March 2026)
- Bundled LibStub and CallbackHandler-1.0 inside `Libs\`. Removed `## Dependencies: Ace3` from the toc. AQL is now fully self-contained with zero external dependencies. Both libraries are self-versioning via LibStub and deduplicate safely if Ace3 or another addon loads the same or newer versions.

### Version 2.1.0 (March 2026)
- Added `AQL.ChainStatus`, `AQL.StepStatus`, `AQL.Provider`, `AQL.QuestType`, `AQL.Faction`, `AQL.FailReason` enumeration constant tables; all raw string literals in AQL source replaced with these constants
- Fixed `AQL:GetQuestInfo` Tier 2→3 augmentation: remote quests now resolve zone, level, and chainInfo from Questie/QuestWeaver when not in the player's log (fixes "Other Quests" grouping in SocialQuest Party tab)
- Restructured `/aql` slash command: debug mode now requires `/aql debug [on|normal|verbose|off]`

### Version 2.0 (March 2026)
- Initial full implementation: LibStub library, QuestCache, HistoryCache, EventEngine, WowQuestAPI wrapper, provider system (Questie, QuestWeaver, Null)
- Full callback suite: quest accept/complete/finished/failed/abandoned/tracked/untracked, objective progressed/completed/regressed/failed
- Three-tier `GetQuestInfo` resolution: cache → WoW log scan → provider
- `GetQuestLink` with fallback hyperlink construction
- Debug system via `/aql`
- Expanded collapsed-header fix (prevents false AQL_QUEST_ABANDONED on rebuild)
- Turn-in regression suppression via `GetQuestReward` hook + `pendingTurnIn`
- Deferred provider upgrade (up to 5 retries, 1 s apart) to catch Questie's async init
- `IsQuestObjectiveText` for `UI_INFO_MESSAGE` suppression

---

*This file must be kept up to date. Update it when adding modules, changing the public API, fixing significant bugs, or bumping the version number.*
