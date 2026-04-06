# AbsoluteQuestLog — WoW TBC Library Addon

## Project Overview

**AbsoluteQuestLog-1.0 (AQL)** is a LibStub library for World of Warcraft: The Burning Crusade Anniversary edition. It provides a unified, event-driven quest data API for consumer addons. Consumers access it via `LibStub("AbsoluteQuestLog-1.0")`.

**Interface**: 20505 (TBC Anniversary)
**Author**: Thad Ryker
**Status**: Active development

> **IMPORTANT FOR CLAUDE:** This file must be updated whenever significant changes are made to the project — architecture changes, new modules, protocol changes, new public API, or notable bug fixes. Update the version number in `AbsoluteQuestLog.toc` after every set of meaningful changes using the versioning rule below. Do not leave this file stale.

> **Versioning Rule:** The major version number should never be changed by Claude unless explicitly instructed to do so. The first time the library is modified on any given day, the minor version number should be incremented and the revision number should be reset to 0. Any extra changes occurring within the same day should increment the revision number only, unless explicitly instructed otherwise.

> **Changelog Rule:** After every version bump, update `changelog.txt` in the project root with the new version entry (same content as the Version History entry added to this file). If `changelog.txt` does not exist, create it. The file should list versions in reverse chronological order, newest first.

> **Task List Rule:** After completing each task or sub-task, immediately mark it as completed in the visual task list (TaskUpdate with status=completed). Mark tasks as in_progress before starting them. Never leave the task list showing stale pending/in_progress states — misleading task display is not productive. Delete tasks that were created in a prior session and are no longer relevant.

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
| `Core\WowQuestAPI.lua` | `WowQuestAPI` (global) | Thin, stateless wrappers around WoW quest globals. All version-specific branching lives here. **All WoW API calls — including those in providers — must go through WowQuestAPI wrappers, no exceptions.** No other AQL file may reference WoW quest globals directly. |
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
| `Providers\GrailProvider.lua` | `AQL.GrailProvider` | When Grail is installed. Last in all priority lists. Covers Classic/TBC/Wrath/MoP/Retail. |

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
| `AQL:GetQuestType(questID)` | string or nil | From cache only. Possible values include those in `AQL.QuestType` (Normal, Elite, Dungeon, Raid, Daily, PvP, Escort, Weekly). |

#### Quest Alias

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetQuestAliasKey(questID)` | string or nil | Fingerprint key — same for Retail variant questIDs of the same logical quest. `tostring(questID)` on non-Retail. `nil` on Retail if not in cache. |
| `AQL:AreQuestsAliases(id1, id2)` | bool | True if both IDs fingerprint to the same quest. False when either is not in cache. |

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
| `AQL:GetChainInfo(questID)` | wrapper | Returns wrapper { knownStatus, chains }. Never nil. Use SelectBestChain to get a chain entry. |
| `AQL:SelectBestChain(chainResult, engagedQuestIDs)` | chain entry or nil | Scores chains by overlap with engaged set; memoized. |
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

#### Thin Wrappers — Preferred

| Method | Returns | Notes |
|---|---|---|
| `AQL:ShowQuestLog()` | — | Opens the quest log frame |
| `AQL:HideQuestLog()` | — | Closes the quest log frame |
| `AQL:IsQuestLogShown()` | bool | True if quest log is visible |
| `AQL:GetQuestDifficultyColor(level)` | `{r,g,b}` | Fallback to manual delta if native API absent |
| `AQL:GetQuestLogIndex(questID)` | logIndex or nil | nil if not in log or under collapsed header |

#### Thin Wrappers — Deprecated

> ⚠️ **Deprecated.** These methods expose logIndex or implicit selection state that is not stable across WoW version families. Use the questID-based alternatives shown. They will be removed in a future major version.

| Deprecated Method | Replacement |
|---|---|
| `AQL:GetQuestLogSelection()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:GetSelectedQuestId()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:IsQuestLogShareable()` | `AQL:IsQuestIdShareable(questID)` |
| `AQL:SelectQuestLogEntry(logIndex)` | `AQL:SelectQuestLogEntryById(questID)` |
| `AQL:SetQuestLogSelection(logIndex)` | `AQL:SelectAndShowQuestLogEntryById(questID)` |
| `AQL:ExpandQuestLogHeader(logIndex)` | `AQL:ExpandQuestLogZoneByName(zoneName)` |
| `AQL:CollapseQuestLogHeader(logIndex)` | `AQL:CollapseQuestLogZoneByName(zoneName)` |

#### Compound — ByIndex

| Method | Returns | Notes |
|---|---|---|
| `AQL:IsQuestIndexShareable(logIndex)` | bool | Save/check/restore; guards against header rows |
| `AQL:SelectAndShowQuestLogEntryByIndex(logIndex)` | — | Delegates to `SetQuestLogSelection` (deprecated internally; update callsite when `SetQuestLogSelection` is removed) |
| `AQL:OpenQuestLogByIndex(logIndex)` | — | Shows log + navigates to logIndex |
| `AQL:ToggleQuestLogByIndex(logIndex)` | — | Hides if shown+selected; else opens |
| `AQL:GetSelectedQuestLogEntryId()` | questID or nil | nil if nothing selected or header selected. **Replaces deprecated `GetSelectedQuestId()`** |
| `AQL:GetQuestLogEntries()` | array | All visible entries: `{logIndex, isHeader, title, questID, isCollapsed}` |
| `AQL:GetQuestLogZones()` | array of `{name, isCollapsed}` | Ordered zone header entries; useful for save/restore of collapsed state |
| `AQL:ExpandAllQuestLogHeaders()` | — | Expands all collapsed headers |
| `AQL:CollapseAllQuestLogHeaders()` | — | Collapses all headers |
| `AQL:ExpandQuestLogZoneByName(zoneName)` | — | No-op + normal debug if not found |
| `AQL:CollapseQuestLogZoneByName(zoneName)` | — | No-op + normal debug if not found |
| `AQL:ToggleQuestLogZoneByName(zoneName)` | — | Expand/collapse; no-op + normal debug if not found |
| `AQL:IsQuestLogZoneCollapsed(zoneName)` | bool or nil | nil if not found |

#### Compound — ById

**Preferred for most consumers.** Use ById methods when you have a questID — questID is stable across WoW version families; logIndex is not.

If questID is not in the active quest log, all ById methods are silent no-ops (false / nothing). A normal-level debug message is emitted.

| Method | Returns | Notes |
|---|---|---|
| `AQL:IsQuestIdShareable(questID)` | bool | Resolves logIndex; delegates to `IsQuestIndexShareable` |
| `AQL:SelectQuestLogEntryById(questID)` | — | Selects without display refresh; no-op + debug if not in log |
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
    chains = {
        {
            chainID    = N,        -- questID of chain root (first step)
            step       = N,        -- 1-based step-position of the queried quest
            length     = N,        -- total step-positions (a group counts as 1)
            questCount = N,        -- total individual quests across all steps
            steps      = {
                -- Single-quest step (common case):
                { questID = N, title = "string",
                  status = "completed"|"active"|"finished"|"failed"|"available"|"unavailable"|"unknown" },
                -- Multi-quest step (parallel or branch):
                {
                    quests = {
                        { questID = N, title = "string", status = "..." },
                        { questID = M, title = "string", status = "..." },
                    },
                    groupType = "parallel"|"branch"|"unknown",
                },
            },
            provider   = "Grail"|"Questie"|"QuestWeaver"|"BtWQuests"|"none",
        },
        -- second entry only when quest belongs to multiple distinct chains
    }
}
-- knownStatus = "not_a_chain": only knownStatus field present
-- knownStatus = "unknown": only knownStatus field present
```

---

## Provider Interface

Every provider must implement:

- `Provider:IsAvailable()` → bool
- `Provider:GetChainInfo(questID)` → `{ knownStatus, chains }` wrapper (see ChainInfo Structure)
- `Provider:GetQuestType(questID)` → string or nil
- `Provider:GetQuestFaction(questID)` → "Alliance" | "Horde" | nil
- `Provider:GetQuestBasicInfo(questID)` → `{ title, questLevel, requiredLevel, zone }` or nil (optional — checked with `if provider.GetQuestBasicInfo then`)
- `Provider:GetQuestRequirements(questID)` → requirements table or nil

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

`PLAYER_LOGIN` is registered at load time. After `PLAYER_LOGIN` fires, `EventEngine` also registers: `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`, `QUEST_LOG_UPDATE`, `UNIT_QUEST_LOG_CHANGED`, `QUEST_WATCH_LIST_CHANGED`.

---

## Version History

### Version 3.5.3 (April 2026)
- Bug fix: `AQL:GetQuestAliasKey` now uses title-based fingerprinting on MoP Classic
  in addition to Retail. Previously the non-Retail path returned `tostring(questID)`
  with no fingerprinting, so `AreQuestsAliases(X, Y)` always returned false on MoP
  even when X and Y were the same logical quest with different race/class variant IDs.
  Fix: changed guard from `if not IS_RETAIL` to `if not IS_RETAIL and not IS_MOP`.
  Returns nil (not in active cache) instead of a simple questID string, consistent
  with Retail behavior. Callers should use `AQL:GetQuestAliasKey(id) or tostring(id)`
  as a fallback.

### Version 3.5.2 (April 2026)
- Bug fix: `AQL_QUEST_FINISHED` never fired on Retail. Root cause: on Retail,
  `C_QuestLog.GetInfo().isComplete` returns `nil` (not `true`) even after all objectives
  are fulfilled — it does not transition before turn-in. `QuestCache._buildEntry` now
  derives `isComplete` from objective state on Retail: if the quest has at least one
  objective and every objective has `isFinished=true`, `isComplete` is set to `true`. This
  matches the semantics of `AQL_QUEST_FINISHED` (objectives met, ready to turn in) on
  all WoW versions. Non-Retail behavior is unchanged.
- Bug fix: transient `questID=0` entries — non-header entries that `C_QuestLog.GetInfo()`
  returns with `questID=0` during brief quest-log transition states on Retail — were being
  written into the cache and generating spurious `AQL_OBJECTIVE_COMPLETED` callbacks.
  `QuestCache:Rebuild` now skips any non-header entry whose `questID` is `0` or `nil`.

### Version 3.5.1 (April 2026)
- Bug fix: `/aql fire finished` (`AQL_QUEST_FINISHED`) now passes `isComplete=true` in
  the `questInfo` seen by subscribers. AQL only fires `AQL_QUEST_FINISHED` when
  `isComplete` transitions to true — the stub used `false`, causing SQ's `SQ_UPDATE`
  payload to encode `isComplete=0`. The receiving party member then stored `false` for
  the sender's quest state, and `checkAllCompleted`'s remote-done check suppressed
  "Everyone Completed". Fix: wrap questInfo in a `setmetatable` proxy that overrides
  `isComplete=true` without mutating the AQL cache entry.

### Version 3.5.0 (April 2026)
- Feature: `/aql list` — prints all quests in the active cache sorted by questID with
  each quest's title. Useful for identifying questIDs to use with `/aql fire`.
- Feature: `/aql fire <questid> <event>` — artificially fires any AQL callback for a
  given quest. `questInfo` is resolved from the live cache (`GetQuest`/`GetQuestInfo`)
  with a minimal stub fallback when the quest is not in the log. Objective events
  (`progressed`, `obj_completed`, `regressed`, `obj_failed`) receive a synthetic
  `objInfo` with 10/10 progress. Accepts short event names (`finished`, `completed`,
  `accepted`, etc.) or full lowercased event strings (`aql_quest_finished`, etc.).
  Prints a confirmation message with the resolved title.

### Version 3.4.1 (April 2026)
- Bug fix: `AQL:IsQuestObjectiveText` now correctly matches Retail's count-first objective
  text format (`"X/Y Description"`) in addition to the existing count-last format
  (`"Description: X/Y"`). Previously the function only matched count-last, so on Retail
  the `UI_INFO_MESSAGE` suppression in SocialQuest never fired — WoW's built-in floating
  progress text showed alongside SQ's own banner. Fix: added count-first pattern
  (`^%d+/%d+%s+(.+)$`) as a second match fallback; comparison now uses `obj.name` (count
  already stripped by `_buildEntry` since 3.2.19) instead of `obj.text:sub(1, baseLen)`.

### Version 3.4.0 (April 2026)
- Bug fix: `AQL_QUEST_FINISHED` never fired on Retail after the last objective completed.
  Root cause: on Retail some `C_QuestLog` calls inside `QuestCache._buildEntry` fire
  `QUEST_LOG_UPDATE` as a next-frame side-effect; the 100 ms cooldown gate blocks those
  noise events to prevent an infinite rebuild loop — but also silently dropped the
  server's `isComplete=true` update, which typically arrives within the same 100 ms window.
  Fix: after each Retail rebuild, a one-shot follow-up rebuild fires at t+150 ms (after
  the cooldown expires). It re-reads the current quest log state, detects the `isComplete`
  transition the cooldown blocked, and fires `AQL_QUEST_FINISHED`. Uses the same debounce
  generation token as the original rebuild, so any real player action (which bumps gen)
  cancels it — the real action's own rebuild captures the state instead.

### Version 3.3.0 (April 2026)
- Feature: `AQL:GetQuestAliasKey(questID)` — returns a stable fingerprint key for a
  quest (title + zone + sorted objective names/counts). On Retail, two questIDs that
  represent the same logical quest (variant questIDs assigned per race/class character
  type) return identical keys. On non-Retail, returns `tostring(questID)` with no
  overhead. Returns `nil` on Retail when questID is not in the active cache.
- Feature: `AQL:AreQuestsAliases(id1, id2)` — convenience wrapper; returns `true` when
  both questIDs share the same alias key.
- Internal: `QuestCache:_buildAliasKey(info)` — private fingerprint builder.

### Version 3.2.19 (April 2026)
- Bug fix: `QuestCache._buildEntry` `name` extraction now handles Retail's count-first objective text format. The existing pattern (`^(.-):%s*%d+/%d+%s*$`) only stripped count-last format (`"Description: X/Y"`). On Retail, `C_QuestLog.GetQuestObjectives` returns count-first format (`"X/Y Description"`), which didn't match — so `name` fell back to the full text including the count prefix. Any consumer using `objective.name` (including `Announcements.lua`'s outbound chat messages) would then prepend its own `X/Y`, producing `"4/8 4/8 Goblin Assassin slain"`. Fix: added `text:match("^%d+/%d+%s+(.+)$")` as a second fallback before the verbatim full-text fallback.

### Version 3.2.18 (April 2026)
- Bug fix: `AQL:OpenQuestLogByIndex` now closes WorldMapFrame before reopening when the log is already open in quest list mode (Retail only). `QuestMapFrame_ShowQuestDetails` called from list mode (`QuestModelScene` not visible — the state after pressing Back from quest details) closes WorldMapFrame as a side effect. Fix: detect list mode via `QuestModelScene:IsVisible()` at the top of `OpenQuestLogByIndex`; if open in list mode, call `WowQuestAPI.HideQuestLog()` before `ShowQuestLog()`. Both calls happen in the same Lua frame (no visible flash), and `ShowQuestDetails` is safe on the resulting fresh-open path.

### Version 3.2.17 (April 2026)
- Feature: `WowQuestAPI.IsQuestDetailPanelShown()` added to `Core/WowQuestAPI.lua`. Checks `QuestModelScene:IsVisible()` on Retail. NOTE: in Retail's split-pane quest log layout, QuestModelScene remains visible even when the quest list is shown, so this function does not reliably distinguish "detail panel active" from "quest list showing." Do not use for toggle-close detection; use hook-based tracking instead (see SQ RowFactory 2.17.18). Exposed as `AQL:IsQuestDetailShown()`. On TBC/Classic/MoP always returns true.

### Version 3.2.16 (April 2026)
- Bug fix: replaced `QuestModelScene:GetRight()` readiness guard with `QuestMapFrame:IsVisible()` in both `WowQuestAPI.ShowQuestDetails` and `AQL:OpenQuestLogByIndex`. `QuestModelScene:GetRight()` returns nil even after `ToggleQuestLog()` has properly activated `QuestMapFrame` (the scene itself hasn't been shown yet), which incorrectly blocked navigation on every first SQ click per session. `QuestMapFrame:IsVisible()` is the correct signal: it confirms the quest log panel is active and `QuestModelScene`'s anchors can be resolved, making `ShowQuestDetails` safe even before the detail panel has been opened that session.

### Version 3.2.15 (April 2026)
- Bug fix: `WowQuestAPI.ShowQuestLog` on Retail now calls `ToggleQuestLog()` (the TOGGLEQUESTLOG keybind function) when WorldMapFrame is not visible, instead of `WorldMapFrame:Show()` or `QuestMapFrame_OpenToAllQuests()`. `WorldMapFrame:Show()` opens in map mode without activating the quest log panel, leaving `QuestModelScene` uninitialized. `QuestMapFrame_OpenToAllQuests()` calls an internal toggle that hides WorldMapFrame when it is already visible, preventing the window from appearing. `ToggleQuestLog()` opens WorldMapFrame in quest log panel mode, properly initializing `QuestModelScene`. Falls back to `WorldMapFrame:Show()` if absent.

### Version 3.2.14 (April 2026)
- Bug fix: `WowQuestAPI.ShowQuestLog` on Retail now calls `WorldMapFrame:Show()` AND `QuestMapFrame_OpenToAllQuests()`. `WorldMapFrame:Show()` alone opens the frame in map mode without activating the quest log panel, leaving `QuestModelScene` uninitialized and causing tracker-click crashes. `QuestMapFrame_OpenToAllQuests()` alone navigates the internal panel without making the window visible. Both calls are required: Show() for visibility, OpenToAllQuests for quest log panel activation and `QuestModelScene` geometry initialization.

### Version 3.2.13 (April 2026)
- Bug fix: `WowQuestAPI.ShowQuestLog` on Retail now calls `QuestMapFrame_OpenToAllQuests()` instead of `WorldMapFrame:Show()`. `WorldMapFrame:Show()` opens the frame in map mode without activating `QuestMapFrame` (the quest log panel inside WorldMapFrame), leaving `QuestModelScene` uninitialized. `QuestMapFrame_OpenToAllQuests()` navigates WorldMapFrame to quest log panel mode, which activates `QuestMapFrame` and causes `QuestModelScene` to receive valid geometry — making subsequent detail navigation and tracker clicks safe. Falls back to `WorldMapFrame:Show()` if the function is absent.

### Version 3.2.12 (April 2026)
- Bug fix: `WowQuestAPI.ShowQuestDetails` guard was checking `QuestFrameModelScene` (the NPC quest dialog's model scene) instead of `QuestModelScene` (the WorldMapFrame detail panel's model scene — the one that actually crashes). `QuestFrameModelScene` may be initialized even when `QuestModelScene` is not, so the guard passed and allowed the call through. Fixed by checking `QuestModelScene:GetRight()` instead.
- Bug fix: `AQL:OpenQuestLogByIndex` now gates `SelectAndShowQuestLogEntryByIndex` on Retail behind the same `QuestModelScene` readiness check. `C_QuestLog.SetSelectedQuest` (called internally) may trigger WorldMapFrame's auto-navigation to the detail panel, which follows the same crash path as `QuestMapFrame_ShowQuestDetails`. When not ready, the quest log opens but does not navigate or select — safe no-op degradation.

### Version 3.2.11 (April 2026)
- Bug fix: `WowQuestAPI.ShowQuestDetails` now guards against the Blizzard `QuestFrameModelScene` crash before calling `QuestMapFrame_ShowQuestDetails`. `QuestFrameModelScene` is a child of the NPC quest dialog (`QuestFrame`) and is lazy-initialized — `GetRight()` returns nil until the player opens that dialog at least once this session. Calling `QuestMapFrame_ShowQuestDetails` before initialization triggers a Blizzard bug ("Cannot perform measurement in QuestFrameModelScene") that breaks the quest tracker for the rest of the session. Guard added: `if not QuestFrameModelScene or not QuestFrameModelScene:GetRight() then return end`. pcall restored around the actual call.

### Version 3.2.10 (April 2026)
- Diagnostic: removed pcall from `WowQuestAPI.ShowQuestDetails` so any error from `QuestMapFrame_ShowQuestDetails` surfaces in the WoW error frame. Nil-guard on the global is retained. This is a temporary diagnostic build — restore pcall once the error is identified and the correct API is determined.

### Version 3.2.9 (April 2026)
- Reverted 3.2.8's `_openedQuestID` tracking approach. Tracking which quest SQ last opened is naive: if the player opens the quest log from the tracker, a keybind, or any other source, the tracked value is stale and the toggle fires on the wrong quest. The toggle must be based on observable UI state only. The correct check (`C_QuestLog.GetSelectedQuest() == questID` via `GetSelectedQuestLogEntryId`) is already in place and works on TBC/Classic/MoP. On Retail it requires `WowQuestAPI.ShowQuestDetails` to successfully establish the visual selection — until that unverified Retail API is resolved, toggle-close gracefully degrades to a no-op (the log always opens; never incorrectly closes based on stale state). Documented in `ToggleQuestLogByIndex`.

### Version 3.2.8 (April 2026)

### Version 3.2.7 (April 2026)
- Feature: `WowQuestAPI.ShowQuestDetails(questID)` added to `Core/WowQuestAPI.lua`. On Retail, opening the WorldMapFrame and calling `C_QuestLog.SetSelectedQuest()` sets the C-level selection but does not navigate the WorldMapFrame to the quest's detail panel. `QuestMapFrame_ShowQuestDetails(questID)` is the expected FrameXML global for this — nil-guarded (no-op if absent) and pcall-guarded (portrait model scene crash observed from Blizzard's own tracker; does not propagate). No-op on TBC/Classic/MoP where `QuestLog_SetSelection` + `QuestLog_Update` already fully refreshes the standalone `QuestLogFrame`. Marked `-- TODO: verify Retail API` per AQL convention for unverified Retail globals.
- Feature: `AQL:OpenQuestLogByIndex(logIndex)` now calls `WowQuestAPI.ShowQuestDetails()` after `SelectAndShowQuestLogEntryByIndex()`. Resolves questID from logIndex via `GetQuestLogInfo`. All `OpenQuestLog*` callers (including SocialQuest's quest-title click) now get proper detail-panel navigation on Retail at no cost to TBC/Classic/MoP.

### Version 3.2.6 (April 2026)
- Feature: `AQL:GetChainInfo(questID)` now falls through to the Chain provider when
  `QuestCache` has no Known answer for the queried questID. Previously, questIDs not in
  the local player's log (e.g. a party member's Retail variant questID) always returned
  `knownStatus = Unknown`. Now the Chain provider (e.g. GrailProvider) is consulted as a
  tier-2 source; its result is returned when Known. Cache is still preferred when Known —
  the provider is only consulted when the cache has no Known result. The `pcall` guard
  is consistent with how EventEngine calls providers.

### Version 3.2.5 (April 2026)
- Bug fix: `GrailProvider.GetChainInfo` was calling `annotateSteps` directly on the cached
  steps array returned by `buildVariantChain` / `buildChainFromRoot`. Because `variantChainCache`
  stores a direct reference to the same `steps` table, each `GetChainInfo` call overwrote
  `.status` fields on cached step objects — any consumer holding a prior reference would see
  stale statuses from the latest call. Fixed by adding `deepCopySteps` (two-level fixed-depth
  copy: outer steps array + each step table, plus sub-quest tables inside group steps). All
  three code paths in `GetChainInfo` (Path 1, Path 2, Path 3) now deep-copy before annotating;
  the cached originals are never mutated.
- Performance fix: `GetChainInfo` Path 2 (questID with no graph edges, searching for a
  same-title variant root) iterated `pairs(reverseMap)` — O(N) over the entire Grail database
  per call on Retail. Fixed by adding a third pass in `buildReverseMap` that populates
  `titleToReverseMapIDs[name] = { id1, id2, ... }` for every key in `reverseMap`. Path 2 now
  does a single `titleToReverseMapIDs[title]` lookup instead of a full scan.
- Refactor: `annotateSteps` hoisted from a closure defined inside `GetChainInfo` on every call
  to a module-level `local function`. No behavioral change; eliminates repeated closure allocation.

### Version 3.2.4 (April 2026)
- Bug fix (Retail): `buildReverseMap` stored successor questIDs directly from `pairs(g.questPrerequisites)` without normalizing type. If Grail uses string keys, stored values were strings; `g:QuestName(stringID)` returns nil (Grail uses numeric keys internally), causing `allSameTitle` to return false and `buildChainFromRoot` to break at the first multi-variant step. Fix: store `tonumber(questID) or questID` so reverseMap values are always numbers when possible. This unblocks same-title variant step detection and chain traversal beyond step 2.
- Bug fix (Retail): `GetChainInfo` fallback for unlinked variant questIDs (e.g. 28763 for "Beating Them Back!" — absent from Grail's prereq graph) previously searched `QuestCache.data` for a same-title quest with `knownStatus = Known`. This had a timing dependency: if the PLAYER_LOGIN rebuild ran before the reverseMap was populated, 28766's `chainInfo` was stored as `"not_a_chain"` and the fallback found no match. Replaced with a direct `reverseMap` key search (reverseMap keys are always numeric questIDs with known successors). If a key's title matches the variant's title via `g:QuestName`, that is the canonical questID — its chain is built via `findRoots` + `buildChainFromRoot` and returned. No QuestCache dependency, no timing issues.

### Version 3.2.3 (April 2026)
- Bug fix (Retail): `GrailProvider.buildChainFromRoot` stopped chain traversal when a quest had multiple successors that did not share a downstream convergence point. On Retail, each chain step has many race/class variant questIDs stored as independent successors in Grail's prerequisite graph — not genuinely divergent branches. Fix: two new helpers (`allSameTitle`, `collectSuccessors`) added before `buildChainFromRoot`. When multiple successors fail the convergence check, their titles are compared via `g:QuestName`. If all share the same title, they are grouped as a `"parallel"` variant step and traversal continues with the union of their successors. Applies to both the single-wave and multi-wave loop paths. Chain length now reflects the full Grail-known chain rather than stopping at the first multi-variant step.
- Bug fix (Retail): `GrailProvider.GetChainInfo` returned `"not_a_chain"` for Retail variant questIDs absent from Grail's prerequisite graph (e.g. the local player's questID differs from the canonical one Grail recorded). Fix: before returning `NotAChain`, the quest's title is looked up via `g:QuestName` and `QuestCache.data` is searched for a same-title quest with `knownStatus = Known`. If found, that chain info is returned, allowing consumers to group both variants under the same `chainID`.

### Version 3.2.2 (April 2026)
- Bug fix: `GrailProvider.buildReverseMap()` set `reverseMapBuilt = true` even when Grail's `questPrerequisites` table was empty at call time. This created a permanent race condition on `/reload`: AQL's `PLAYER_LOGIN` handler calls `GetChainInfo` (via `QuestCache._buildEntry`) before Grail finishes populating `questPrerequisites`, so the reverse map was built empty and locked — all subsequent `GetChainInfo` calls returned `"not_a_chain"` for the rest of the session. Fix: added an early-return guard (`if not next(g.questPrerequisites) then return end`) before the loop body, so `buildReverseMap` does not set `reverseMapBuilt = true` when the table is empty. The next call after Grail populates the table completes the build correctly.

### Version 3.2.1 (April 2026)
- Bug fix: `GrailProvider:GetQuestBasicInfo` was calling `WowQuestAPI.GetAreaInfo(mapArea)` to resolve zone names, but Grail's `mapArea` values are uiMapIDs, not AreaTable IDs. `C_Map.GetAreaInfo` expects an AreaTable ID — passing a uiMapID returned an unrelated sub-area name (e.g. uiMapID 12 → AreaTable ID 12 → "Moonwell of Purity" instead of "Elwynn Forest"). Fixed by calling `g:MapAreaName(mapArea)` instead, which uses Grail's own `mapAreaMapping` table (uiMapID → localized zone name, built at startup via `C_Map.GetMapInfo`). Correct on all WoW version families.

### Version 3.2.0 (April 2026)
- Bug fix (defensive): `WowQuestAPI.GetQuestInfo` Retail branch and `QuestCache:Rebuild()` now skip campaign/chapter headers when tracking the current zone. On Retail, `C_QuestLog.GetInfo()` returns both geographic zone headers and campaign chapter headers (both have `isHeader = true`). The previous code blindly assigned `currentZone = info.title` for any header, which could set campaign chapter names as zone labels. Both code paths now guard with `if not (info.campaignID and info.campaignID ~= 0)` before updating `currentZone`.
- New: `WowQuestAPI.GetQuestLogInfo()` Retail return table now includes `campaignID` field, needed by `QuestCache:Rebuild()` for the campaign header guard.

### Version 3.1.5 (April 2026)
- Bug fix: `WowQuestAPI.GetQuestInfo` crashed on Retail with "attempt to call field 'GetQuestInfo' (a nil value)". The Retail branch was calling `C_QuestLog.GetQuestInfo(questID)`, which was removed in Patch 9.0.1 (Shadowlands, 2020) — the original code was always wrong on current Retail. Fixed by replacing the Retail branch with the same Tier-1 log scan + Tier-2 fallback pattern used by the Classic/TBC/MoP branch: scan via `C_QuestLog.GetNumQuestLogEntries()` + `C_QuestLog.GetInfo(i)` (returning zone, level, and full fields when the quest is in the log), then fall back to `C_QuestLog.GetTitleForQuestID(questID)` for quests not in the log. `isComplete` normalized to boolean (`== true`) since `C_QuestLog.GetInfo` returns boolean on Retail, not 0/1. This fixes `AQL:GetQuestInfo` and `AQL:GetQuestTitle` on Retail.

### Version 3.1.4 (April 2026)
- Scope fix: post-rebuild cooldown gate (`rebuildCooldownUntil`) in `EventEngine.lua` now only activates on Retail. The 3.1.3 fix set the cooldown unconditionally after every rebuild, which could suppress legitimate `QUEST_LOG_UPDATE` events within 100 ms on Classic/TBC/MoP. The cooldown set is now guarded by `WowQuestAPI.IS_RETAIL`; on all other versions `rebuildCooldownUntil` stays 0 and the gate is always a no-op.
- New: `WowQuestAPI.IS_RETAIL`, `IS_TBC`, `IS_CLASSIC_ERA`, `IS_MOP` exported as fields on `WowQuestAPI` so other AQL modules can reference version flags without re-parsing the TOC version independently.

### Version 3.1.3 (April 2026)
- Bug fix: Infinite `QUEST_LOG_UPDATE` loop persisted on Retail even after 3.1.1 and 3.1.2 fixes. Root cause: some Retail `C_QuestLog` API calls inside `QuestCache._buildEntry` still fire `QUEST_LOG_UPDATE` synchronously as a side-effect, re-entering `handleQuestLogUpdate` mid-rebuild and scheduling another rebuild for every quest in the log. Fix: added a post-rebuild cooldown gate in `EventEngine.lua`. After each rebuild completes, `EventEngine.rebuildCooldownUntil` is set to `GetTime() + 0.1`. Any `QUEST_LOG_UPDATE` or `QUEST_WATCH_LIST_CHANGED` received within that 100 ms window is silently dropped. Real player-action events (`QUEST_ACCEPTED`, `QUEST_REMOVED`) bypass the gate via `bypassCooldown=true` and are never suppressed.

### Version 3.1.2 (April 2026)
- Bug fix: Infinite `QUEST_LOG_UPDATE` loop continued after 3.1.1. `WowQuestAPI.GetQuestLogSelection()` had no `IS_RETAIL` guard — if the `GetQuestLogSelection` global exists on Retail and returns a non-zero logIndex, the Phase 5 restore in `QuestCache:Rebuild()` called `SelectQuestLogEntry()` → `C_QuestLog.SetSelectedQuest()` → fired `QUEST_LOG_UPDATE`. `GetQuestLogSelection` now returns 0 unconditionally on Retail; the save/restore is only needed to undo `ExpandQuestHeader` calls, which are no-ops on Retail.
- Bug fix: `GetQuestLinkByIndex()` and `GetQuestLinkById()` called `C_QuestLog.GetQuestLink` without nil-guarding. `C_QuestLog.GetQuestLink` is absent on Interface 120001. Both wrappers now nil-guard it and return nil when absent (callers fall back to manual hyperlink construction).

### Version 3.1.1 (April 2026)
- Bug fix: Infinite `QUEST_LOG_UPDATE` loop on Retail. `QuestCache._buildEntry` called `WowQuestAPI.SelectQuestLogEntry(logIndex)` per quest to fetch the timer; on Retail this calls `C_QuestLog.SetSelectedQuest()` which fires `QUEST_LOG_UPDATE` synchronously, bumping the debounce generation mid-rebuild and scheduling another rebuild. Repeats for every quest in the log. Fix: new `WowQuestAPI.GetQuestTimerByIndex(logIndex)` wrapper that skips the select+timer block entirely on Retail (returns nil). `_buildEntry` now calls `GetQuestTimerByIndex` instead of the separate `SelectQuestLogEntry` + `GetQuestLogTimeLeft` calls.
- Bug fix: `WowQuestAPI.GetQuestLogTimeLeft()` called the bare global which is absent on Retail. Added nil-guard; returns nil when the global is not present.
- Bug fix: `WowQuestAPI.GetQuestLinkByIndex(logIndex)` called `GetQuestLink(logIndex)` which is absent on Retail. On Retail, resolves `logIndex → questID` via `GetQuestLogInfo` then calls `C_QuestLog.GetQuestLink(questID)`. Added nil-guard for `GetQuestLink` on legacy clients.

### Version 3.1.0 (April 2026)
- Bug fix: `WowQuestAPI.IsQuestWatchedByIndex()` and `IsQuestWatchedById()` crashed on Retail with "attempt to call field 'IsQuestWatched' (a nil value)" — `C_QuestLog.IsQuestWatched` was removed in a later Retail build. Both wrappers now nil-check `C_QuestLog.IsQuestWatched` first; if absent, fall back to `C_QuestLog.GetQuestWatchType(questID) ~= nil` (non-nil = watched); if both absent, return false.

### Version 3.0.1 (April 2026)
- Bug fix: `WowQuestAPI.GetNumQuestLogEntries()` crashed on Retail with "attempt to call global 'GetNumQuestLogEntries' (a nil value)" — the global was removed in Retail. Added Retail branch calling `C_QuestLog.GetNumQuestLogEntries()` (returns numEntries as first value).
- Bug fix: `WowQuestAPI.GetQuestLogTitle()` called the removed `GetQuestLogTitle` global on Retail. Added Retail branch mapping `C_QuestLog.GetInfo(logIndex)` fields to the legacy 8-value positional return format (`title, level, suggestedGroup, isHeader, isCollapsed, isComplete, 0, questID`).
- Bug fix: `WowQuestAPI.ExpandQuestHeader()` and `CollapseQuestHeader()` call the bare globals directly with no nil-guard. These globals may be absent on Retail builds. Both wrappers now check for global existence before calling.

### Version 3.0.0 (March 2026)
> **BREAKING CHANGE:** `AQL:GetChainInfo(questID)` now returns a wrapper object
> `{ knownStatus, chains }` instead of a bare ChainInfo table. All callers must update.
> `QuestInfo.chainInfo` field type changes accordingly.
>
> **Migration:**
> ```lua
> -- Before (2.x):
> local ci = AQL:GetChainInfo(questID)
> if ci.knownStatus == AQL.ChainStatus.Known then
>     show(ci.step, ci.length)
> end
> -- After (3.0):
> local result = AQL:GetChainInfo(questID)
> if result.knownStatus == AQL.ChainStatus.Known then
>     local ci = AQL:SelectBestChain(result, engagedSet)
>     if ci then show(ci.step, ci.length) end
> end
> ```
- New: `GrailProvider` — quest chain, basic info, and requirements from the Grail addon.
  Covers all WoW versions where Grail is installed (Classic Era, TBC, Wrath, MoP, Retail).
  Chain info reverse-engineered from `Grail.questPrerequisites` via a lazy reverse map.
  Last in all three provider priority lists.
- New: `AQL:SelectBestChain(chainResult, engagedQuestIDs)` — player-agnostic best-chain
  selector. Pass any `{ [questID] = true }` set (current player or party member) to pick
  the chain entry with the most overlap. Memoized by (chainID, count:xor:sum fingerprint).
  Cache cleared by EventEngine on quest state changes.
- New: `AQL.QuestType.Weekly = "weekly"` — weekly quest type reported by GrailProvider.
- New: `AQL.Provider.Grail = "Grail"` — enum entry used in chain `provider` field.
- Breaking: `GetChainInfo` return shape changed from bare ChainInfo to wrapper. See above.
- Breaking: `QuestInfo.chainInfo` now holds wrapper object (not bare ChainInfo).
- Updated: `GetChainStep` / `GetChainLength` use `SelectBestChain` internally.
- Multi-quest steps now supported: duck-typed `step.quests` array with `groupType`.

### Version 2.6.1 (March 2026)
- New provider: `BtWQuestsProvider` — supplies chain data (GetChainInfo), faction
  (GetQuestFaction), and level-range requirements (GetQuestRequirements) on Retail
  from the BtWQuests addon. Inert on TBC/Classic/MoP (IsAvailable returns false when
  BtWQuests global is absent).
- Reverse index built incrementally on first use: questID → chainKey. Handles .ids
  (OR-logic step variants), item.variations, and non-quest chain items (silently skipped).
- New: `AQL.Provider.BtWQuests = "BtWQuests"` enum entry.
- EventEngine: BtWQuestsProvider added to Chain, QuestInfo, and Requirements priority
  lists. On Retail without Questie or QuestWeaver, fills all three capability slots.

### Version 2.6.0 (March 2026)
- Refactor: provider system restructured for multi-provider capability routing.
  Three capability buckets (`Chain`, `QuestInfo`, `Requirements`) each carry an
  independent provider slot in `AQL.providers`, selected from a priority-ordered
  candidate list. `AQL.provider` (singular) is kept as a backward-compatibility shim.
- New: `AQL.Capability` enum (`Chain`, `QuestInfo`, `Requirements`).
- New: `AQL.WARN` orange color constant for always-on provider warning messages.
- New: `AQL.providers` table keyed by `AQL.Capability.*`; replaces single `AQL.provider`
  as the authoritative provider reference for all internal code.
- New: `Provider:Validate()` method on all providers — structural check separate from
  `IsAvailable()` (presence check). `IsAvailable()=true` + `Validate()=false` fires a
  one-time orange warning with sound; `IsAvailable()=false` is silent.
- New: `Provider.addonName` and `Provider.capabilities` fields on all providers.
- New: Always-on "No X provider found" notification (with sound) fires after the
  deferred upgrade window closes for any capability that remains unresolved.
- Behavior unchanged for players with a working Questie or QuestWeaver installation.

### Version 2.5.5 (March 2026)
- Retail support: AQL is now fully functional on Retail (Interface 120001). No behavioral changes on Classic Era, TBC, or MoP.
- New: `WowQuestAPI.GetQuestLogInfo(logIndex)` — normalization wrapper returning `{ title, level, suggestedGroup, isHeader, isCollapsed, isComplete, questID }` from `GetQuestLogTitle` (Classic/TBC/MoP) or `C_QuestLog.GetInfo` (Retail).
- New: `WowQuestAPI.GetSelectedQuestLogEntryId()` — Retail uses `C_QuestLog.GetSelectedQuest()` directly; Classic/TBC/MoP resolve via logIndex → `GetQuestLogInfo`.
- Fix: `GetQuestsCompleted()` Retail branch converts `C_QuestLog.GetAllCompletedQuestIDs()` sequential array to `{[questID]=true}` hash map.
- Fix: `TrackQuest`/`UntrackQuest` call `C_QuestLog.AddQuestWatch(questID)`/`RemoveQuestWatch(questID)` on Retail.
- Fix: `IsQuestWatchedByIndex`/`IsQuestWatchedById` call `C_QuestLog.IsQuestWatched` on Retail.
- Fix: `ShowQuestLog`/`HideQuestLog`/`IsQuestLogShown` redirect to `WorldMapFrame` on Retail.
- Fix: `QuestLog_SetSelection`/`SelectQuestLogEntry` call `C_QuestLog.SetSelectedQuest(questID)` on Retail.
- Fix: `GetQuestLogPushable` calls `C_QuestLog.IsPushableQuest(questID)` on Retail.
- Fix: `GetQuestLinkById` calls `C_QuestLog.GetQuestLink(questID)` on Retail.
- Robustness: `GetMaxWatchableQuests` falls back to `25` if `MAX_WATCHABLE_QUESTS` is nil on Retail.
- Robustness: `GetWatchedQuestCount` returns `0` if `GetNumQuestWatches` global is absent on Retail.
- Refactor: `AQL:GetSelectedQuestLogEntryId` body replaced with single delegation to `WowQuestAPI.GetSelectedQuestLogEntryId()`. Debug messages removed.
- Refactor: `QuestCache` Phase 3 uses `GetQuestLogInfo` instead of `GetQuestLogTitle`. Skip-not-break on nil entries.

### Version 2.5.4 (March 2026)
- Feature: `AQL:GetSelectedQuestLogEntryId()` added — questID-based, unambiguously named replacement for deprecated `GetSelectedQuestId()`.
- Feature: `AQL:SelectQuestLogEntryById(questID)` added — select without display refresh; questID-based replacement for deprecated `SelectQuestLogEntry(logIndex)`.
- Deprecation: `GetQuestLogSelection`, `GetSelectedQuestId`, `IsQuestLogShareable`, `SelectQuestLogEntry`, `SetQuestLogSelection`, `ExpandQuestLogHeader`, `CollapseQuestLogHeader` marked `@deprecated`. All continue to function; replacements listed in each doc comment and in README.md. Will be removed in a future major version.
- Docs: README.md rewritten as complete consumer-facing reference with API docs, callback reference, data structures, Quick Start examples, and deprecation migration table. Version support updated to reflect Classic Era, TBC, MoP, and Retail (in development).
- Docs: CLAUDE.md Group 2 thin wrappers split into Preferred and Deprecated sub-sections. ById section marked as preferred for most consumers.

### Version 2.5.3 (March 2026)
- Refactor: All direct WoW global calls outside `WowQuestAPI.lua` replaced with wrapper calls. Files updated: `QuestCache.lua` (15 callsites), `HistoryCache.lua` (1), `EventEngine.lua` (1), `AbsoluteQuestLog.lua` (1), `QuestieProvider.lua` (1).
- New wrappers added to `WowQuestAPI.lua`: `GetQuestsCompleted`, `IsQuestWatchedByIndex`, `IsQuestWatchedById`, `GetQuestLogTimeLeft`, `GetQuestLinkByIndex`, `GetQuestLinkById`, `GetCurrentDisplayedQuestID`, `GetWatchedQuestCount`, `GetMaxWatchableQuests`, `GetAreaInfo`. Zero behavioral changes.

### Version 2.5.2 (March 2026)
- Feature: MoP Classic (5.x) `IsUnitOnQuest` now functional — resolves questID to logIndex via `GetQuestLogIndex` and calls the MoP global `IsUnitOnQuest(logIndex, unit)`. Returns nil when quest is not in the player's log.
- Feature: `QUEST_TURNED_IN` event registered and handled in `EventEngine`. Sets `pendingTurnIn` directly on Classic Era, MoP, and Retail. `GetQuestReward` hook retained for TBC compatibility.
- Fix: Boolean coercion on legacy WoW globals — `GetQuestLogPushable` and `IsQuestWatched` now use explicit `if/then/return` / `and true or false` patterns instead of `~= nil` / `== true` comparisons that could silently return wrong results.

### Version 2.5.1 (March 2026)
- Docs: Classic Era support made explicit in `Core/WowQuestAPI.lua` — `GetQuestInfo` else-branch comment now names IS_TBC, IS_CLASSIC_ERA, and IS_MOP; header and tier-2 comments updated accordingly. `IsQuestFlaggedCompleted` header comment notes which API each version uses.
- Docs: `docs/api-compatibility.md` — provider availability table added (Questie/QuestWeaver/NullProvider × 4 version families). QuestWeaver confirmed Classic Era and TBC only (no MoP). Retail chain info confirmed always-unknown (no provider exists).

### Version 2.5.0 (March 2026)
- Infrastructure: Multi-toc files added (`AbsoluteQuestLog_Classic.toc` Interface 11508, `AbsoluteQuestLog_TBC.toc` Interface 20505, `AbsoluteQuestLog_Mists.toc` Interface 50503, `AbsoluteQuestLog_Mainline.toc` Interface 120001). AQL now loads without Lua errors on all four active WoW version families. Suffixes confirmed: `_Classic`, `_TBC`, `_Mists`, `_Mainline`.
- Refactor: Version detection constants (`IS_CLASSIC_ERA`, `IS_TBC`, `IS_MOP`, `IS_RETAIL`) added to `Core/WowQuestAPI.lua`, replacing three ad-hoc `_TOC` numeric comparisons. No behavioral change on TBC (20505). WotLK (30000–39999) and Cata (40000–49999) intentionally out of scope; documented in code.
- Docs: `docs/api-compatibility.md` — full API compatibility audit covering 9 API categories × 4 version families. All cells researched. Key findings: most legacy quest globals removed in Retail 9.0.1 (moved to `C_QuestLog` namespace); `QUEST_ACCEPTED` on TBC passes logIndex only (not questID); `QUEST_TURNED_IN` does not fire on TBC/Classic.

### Version 2.4.1 (March 2026)
- Bug fix: `AQL_QUEST_ACCEPTED` never fired after the 2.3.0 false-positive fix. Root cause: in TBC Classic (Interface 20505), the `QUEST_ACCEPTED` event does not pass a questID — it passes the quest log index (or nothing). The 2.3.0 fix stored `pendingQuestAccepts[logIndex] = true`, but `runDiff` checked `pendingQuestAccepts[questID]`, so they never matched and every accept was silently absorbed. Fix: replaced the per-ID table with a `pendingAcceptCount` integer. `QUEST_ACCEPTED` increments the count; `runDiff` decrements and fires for each new quest while count > 0; `QUEST_REMOVED` resets to 0 to clear stale counts on abandon. Group-join false positives are still blocked (`UNIT_QUEST_LOG_CHANGED` carries no `QUEST_ACCEPTED`, so count stays 0).

### Version 2.4.0 (March 2026)
- Feature: Added `AQL:GetQuestRequirements(questID)` public method. Returns provider-backed quest eligibility requirements: requiredLevel, requiredMaxLevel, requiredRaces (bitmask), requiredClasses (bitmask), preQuestGroup, preQuestSingle, exclusiveTo, nextQuestInChain, breadcrumbForQuestId. All bitmask fields with value 0 are normalised to nil. Returns nil when NullProvider is active. `QuestieProvider` implements full field mapping from QuestieDB. `QuestWeaverProvider` returns requiredLevel only (other fields nil — QuestWeaver does not expose them). `NullProvider` returns nil. `Provider.lua` documentation updated with interface contract.

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
