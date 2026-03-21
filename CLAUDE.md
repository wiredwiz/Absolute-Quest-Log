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

### Quest State Queries

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetQuest(questID)` | `QuestInfo` or nil | Cache-only; nil if quest not in player's log |
| `AQL:GetAllQuests()` | `{[questID]=QuestInfo}` | Full cache snapshot |
| `AQL:GetQuestsByZone(zone)` | `{[questID]=QuestInfo}` | Filters cache by zone |
| `AQL:IsQuestActive(questID)` | bool | True if quest is in active log |
| `AQL:IsQuestFinished(questID)` | bool | True if objectives complete, not yet turned in |
| `AQL:HasCompletedQuest(questID)` | bool | HistoryCache + `IsQuestFlaggedCompleted` fallback |
| `AQL:GetCompletedQuests()` | `{[questID]=true}` | All completed quests this session |
| `AQL:GetCompletedQuestCount()` | number | Count of completed quests |
| `AQL:GetQuestType(questID)` | string or nil | From cache only |

### Extended Resolution (Three-Tier)

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetQuestInfo(questID)` | `QuestInfo` or nil | Tier 1: cache → Tier 2: WoW log scan / title fallback → Tier 3: provider |
| `AQL:GetQuestTitle(questID)` | string or nil | Delegates to `GetQuestInfo` |
| `AQL:GetQuestLink(questID)` | hyperlink or nil | Tier 1: cache link → Tier 2/3: `GetQuestInfo` |
| `AQL:GetQuestObjectives(questID)` | array | Cache first; `WowQuestAPI` fallback |

### Chain Queries

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetChainInfo(questID)` | `ChainInfo` | Cache first; returns `{knownStatus="unknown"}` if not found |
| `AQL:GetChainStep(questID)` | number or nil | |
| `AQL:GetChainLength(questID)` | number or nil | |

### Objective Queries

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetObjectives(questID)` | array or nil | |
| `AQL:GetObjective(questID, index)` | table or nil | |
| `AQL:IsQuestObjectiveText(msg)` | bool | Matches `UI_INFO_MESSAGE` text against active objectives (base-name prefix match, stale-count safe) |

### Tracking / Unit

| Method | Returns | Notes |
|---|---|---|
| `AQL:TrackQuest(questID)` | bool | Returns false if at `MAX_WATCHABLE_QUESTS` cap |
| `AQL:UntrackQuest(questID)` | — | |
| `AQL:IsUnitOnQuest(questID, unit)` | bool or nil | nil on TBC (API unavailable) |

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
