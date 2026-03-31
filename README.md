# AbsoluteQuestLog-1.0

A version-agnostic WoW addon library that provides a clean, stable API for quest data and quest log events. AbsoluteQuestLog (AQL) abstracts away the differences between WoW client versions and gives your addon a single consistent interface that works across Classic Era, TBC Classic, Mists of Pandaria Classic, and Retail — without you having to branch for each one.

**Supported WoW versions:**

| Version Family | Interface | Status |
|---|---|---|
| Classic Era | 1.14.x (11508) | ✅ Supported |
| TBC Classic | 2.5.x (20505) | ✅ Supported |
| Mists of Pandaria Classic | 5.4.x (50503) | ✅ Supported |
| Retail (The War Within) | 11.x (120001) | 🚧 In development |

---

## Installation

Declare AQL as a dependency in your addon's `.toc` file:

```
## Dependencies: AbsoluteQuestLog
```

Then get the library handle at the top of your Lua file:

```lua
local AQL = LibStub("AbsoluteQuestLog-1.0")
```

---

## Quick Start

### React to quest events

```lua
local AQL = LibStub("AbsoluteQuestLog-1.0")

-- Fire when the player accepts a new quest
AQL:RegisterCallback(AQL.Event.QuestAccepted, function(questInfo)
    print("New quest accepted: " .. questInfo.title)
end)

-- Fire when a quest objective progresses
AQL:RegisterCallback(AQL.Event.ObjectiveProgressed, function(questInfo, objInfo, delta)
    print(questInfo.title .. ": " .. objInfo.text .. " (+" .. delta .. ")")
end)
```

### Fetch quest data

```lua
local AQL = LibStub("AbsoluteQuestLog-1.0")

-- Get data for a specific quest
local questInfo = AQL:GetQuest(questID)
if questInfo then
    print(questInfo.title .. " — Level " .. questInfo.level)
    print("Zone: " .. (questInfo.zone or "Unknown"))
    print("Complete: " .. tostring(questInfo.isComplete))
end

-- Iterate all quests in the player's log
for questID, questInfo in pairs(AQL:GetAllQuests()) do
    print(questID, questInfo.title)
end
```

### Check quest history

```lua
if AQL:HasCompletedQuest(questID) then
    print("Already done this one.")
end
```

---

## Breaking Changes in 3.0.0

### `GetChainInfo` Return Type Changed

`AQL:GetChainInfo(questID)` now returns a **wrapper object** instead of a bare ChainInfo table.

**Before (2.x):**
```lua
local ci = AQL:GetChainInfo(questID)
if ci.knownStatus == AQL.ChainStatus.Known then
    print("Step " .. ci.step .. " of " .. ci.length)
end
```

**After (3.0):**
```lua
local result = AQL:GetChainInfo(questID)
if result.knownStatus == AQL.ChainStatus.Known then
    local ci = AQL:SelectBestChain(result, AQL:_GetCurrentPlayerEngagedQuests())
    if ci then
        print("Step " .. ci.step .. " of " .. ci.length)
    end
end
```

The wrapper shape:
```lua
{ knownStatus = "known", chains = { { chainID, step, length, questCount, steps, provider }, ... } }
{ knownStatus = "not_a_chain" }
{ knownStatus = "unknown" }
```

`QuestInfo.chainInfo` (on cached quest entries) now holds this wrapper object.

### New: `AQL:SelectBestChain(chainResult, engagedQuestIDs)`

Picks the best-fit chain entry for a given player's engaged quest set.

```lua
-- Current player:
local engaged = AQL:_GetCurrentPlayerEngagedQuests()
local chain = AQL:SelectBestChain(result, engaged)

-- Party member:
local memberEngaged = {}
for qid in pairs(member.completedQuests or {}) do memberEngaged[qid] = true end
for qid in pairs(member.quests or {}) do memberEngaged[qid] = true end
local chain = AQL:SelectBestChain(result, memberEngaged)
```

### New Quest Type: `AQL.QuestType.Weekly = "weekly"`

Reported by GrailProvider for weekly quests. Additive.

---

## API Reference

All methods are called on the library handle: `AQL:MethodName(...)`.

### Group 1: Quest APIs

> All Group 1 methods take `questID` as their primary identifier. questID is stable across all WoW version families and does not change between quest log updates.

#### Quest State

| Method | Returns | Description |
|---|---|---|
| `AQL:GetQuest(questID)` | QuestInfo or nil | Returns cached quest data. nil if quest is not in the player's log. |
| `AQL:GetAllQuests()` | `{[questID]=QuestInfo}` | Returns the full quest cache snapshot. |
| `AQL:GetQuestsByZone(zone)` | `{[questID]=QuestInfo}` | Returns all quests in the given zone. |
| `AQL:IsQuestActive(questID)` | bool | True if quest is in the player's active log. |
| `AQL:IsQuestFinished(questID)` | bool | True if all objectives are complete but the quest has not been turned in. |
| `AQL:GetQuestType(questID)` | string or nil | One of: `"normal"`, `"elite"`, `"dungeon"`, `"raid"`, `"daily"`, `"pvp"`, `"escort"`. Cache-only; returns nil if the quest is not in the active log. |

#### Quest History

| Method | Returns | Description |
|---|---|---|
| `AQL:HasCompletedQuest(questID)` | bool | True if this character has ever completed the quest. |
| `AQL:GetCompletedQuests()` | `{[questID]=true}` | All quests ever completed by this character (loaded at login from the server's completion record). |
| `AQL:GetCompletedQuestCount()` | number | Count of completed quests. |

#### Quest Resolution

| Method | Returns | Description |
|---|---|---|
| `AQL:GetQuestInfo(questID)` | QuestInfo or nil | Three-tier resolution: cache → WoW log scan → provider DB. `questID` is always present in the result; `title` is present when any tier finds it but may be nil on a chain-data-only provider result. |
| `AQL:GetQuestTitle(questID)` | string or nil | Returns the quest title. Delegates to `GetQuestInfo`. |
| `AQL:GetQuestLink(questID)` | hyperlink or nil | Returns a chat-linkable hyperlink for the quest. |

#### Objectives

| Method | Returns | Description |
|---|---|---|
| `AQL:GetObjectives(questID)` | array or nil | Returns the objectives array from the cache. |
| `AQL:GetObjective(questID, index)` | table or nil | Returns a single objective by 1-based index. |
| `AQL:GetQuestObjectives(questID)` | array | Cache first; falls back to WoW API. Returns `{}` if no objectives found. |
| `AQL:IsQuestObjectiveText(msg)` | bool | True if `msg` matches any active quest objective text. Useful for suppressing duplicate `UI_INFO_MESSAGE` notifications. |

#### Chain Info

Requires Questie or QuestWeaver to be installed. Returns `{knownStatus="unknown"}` otherwise.

| Method | Returns | Description |
|---|---|---|
| `AQL:GetChainInfo(questID)` | ChainInfo | Full chain data. See [ChainInfo](#chaininfo) below. |
| `AQL:GetChainStep(questID)` | number or nil | 1-based position of this quest in its chain. |
| `AQL:GetChainLength(questID)` | number or nil | Total number of quests in the chain. |

#### Requirements

| Method | Returns | Description |
|---|---|---|
| `AQL:GetQuestRequirements(questID)` | table or nil | Eligibility requirements: `requiredLevel`, `requiredMaxLevel`, `requiredRaces`, `requiredClasses`, `preQuestGroup`, `preQuestSingle`, `exclusiveTo`, `nextQuestInChain`, `breadcrumbForQuestId`. Bitmask fields with value 0 are normalized to nil. Returns nil when NullProvider is active. |

#### Quest Tracking

| Method | Returns | Description |
|---|---|---|
| `AQL:TrackQuest(questID)` | bool | Adds quest to the watch list. Returns false if the watch cap is already reached. |
| `AQL:UntrackQuest(questID)` | — | Removes quest from the watch list. |
| `AQL:IsUnitOnQuest(questID, unit)` | bool or nil | True if the given unit has this quest. Returns nil on TBC and Classic Era (API unavailable on those versions). |

#### Player & Level

Level filters use `questInfo.level` (recommended difficulty level). Strict comparisons for Below/Above; inclusive for Between.

| Method | Returns | Description |
|---|---|---|
| `AQL:GetPlayerLevel()` | number | Player's current character level. |
| `AQL:GetQuestsInQuestLogBelowLevel(level)` | `{[questID]=QuestInfo}` | Quests with `questInfo.level < level`. |
| `AQL:GetQuestsInQuestLogAboveLevel(level)` | `{[questID]=QuestInfo}` | Quests with `questInfo.level > level`. |
| `AQL:GetQuestsInQuestLogBetweenLevels(min, max)` | `{[questID]=QuestInfo}` | Quests with `min <= questInfo.level <= max`. Returns `{}` if min > max. |
| `AQL:GetQuestsInQuestLogBelowLevelDelta(delta)` | `{[questID]=QuestInfo}` | Quests below `playerLevel - delta`. |
| `AQL:GetQuestsInQuestLogAboveLevelDelta(delta)` | `{[questID]=QuestInfo}` | Quests above `playerLevel + delta`. |
| `AQL:GetQuestsInQuestLogWithinLevelRange(delta)` | `{[questID]=QuestInfo}` | Quests between `playerLevel - delta` and `playerLevel + delta`. |

---

### Group 2: Quest Log Frame APIs

Methods that interact with the WoW quest log frame UI.

> **ById methods are preferred.** questID is stable across WoW version families; logIndex is a positional cursor that changes on every quest log update.

#### Frame Control

| Method | Returns | Description |
|---|---|---|
| `AQL:ShowQuestLog()` | — | Opens the quest log frame. |
| `AQL:HideQuestLog()` | — | Closes the quest log frame. |
| `AQL:IsQuestLogShown()` | bool | True if the quest log frame is currently visible. |
| `AQL:GetQuestDifficultyColor(level)` | `{r,g,b}` | Returns the difficulty color for a quest of the given level relative to the player. |
| `AQL:GetQuestLogIndex(questID)` | logIndex or nil | Resolves questID to its current logIndex. Returns nil if the quest is not in the log or is under a collapsed zone header. |

#### Compound — ById *(Preferred)*

If questID is not in the active quest log, all ById methods are silent no-ops (return false or nothing). A debug message is emitted when debug mode is on.

| Method | Returns | Description |
|---|---|---|
| `AQL:GetSelectedQuestLogEntryId()` | questID or nil | Returns the questID of the currently selected quest log entry. nil if nothing selected or a zone header is selected. |
| `AQL:IsQuestIdShareable(questID)` | bool | True if the quest can be shared with party members. |
| `AQL:SelectQuestLogEntryById(questID)` | — | Selects the quest log entry without refreshing the display. Use `SelectAndShowQuestLogEntryById` to also refresh. |
| `AQL:SelectAndShowQuestLogEntryById(questID)` | — | Selects the quest log entry and refreshes the display. |
| `AQL:OpenQuestLogById(questID)` | — | Opens the quest log and navigates to this quest. |
| `AQL:ToggleQuestLogById(questID)` | — | Toggles the quest log open/closed for this quest. |

#### Compound — ByIndex

Use these when you already have a logIndex (e.g., from iterating `GetQuestLogEntries()`).

| Method | Returns | Description |
|---|---|---|
| `AQL:GetQuestLogEntries()` | array | All visible entries in display order: `{logIndex, isHeader, title, questID, isCollapsed}`. `questID` is nil for header rows; `isCollapsed` is nil (not false) for quest rows. |
| `AQL:GetQuestLogZones()` | array of `{name, isCollapsed}` | Zone header entries. Useful for save/restore of collapsed state. |
| `AQL:IsQuestIndexShareable(logIndex)` | bool | True if the quest at logIndex can be shared. Saves/restores selection. |
| `AQL:SelectAndShowQuestLogEntryByIndex(logIndex)` | — | Selects and refreshes the display. |
| `AQL:OpenQuestLogByIndex(logIndex)` | — | Opens the quest log and navigates to logIndex. |
| `AQL:ToggleQuestLogByIndex(logIndex)` | — | Toggles the quest log open/closed for logIndex. |
| `AQL:ExpandAllQuestLogHeaders()` | — | Expands all collapsed zone headers. |
| `AQL:CollapseAllQuestLogHeaders()` | — | Collapses all zone headers. |
| `AQL:ExpandQuestLogZoneByName(zoneName)` | — | Expands the named zone header. No-op if not found. |
| `AQL:CollapseQuestLogZoneByName(zoneName)` | — | Collapses the named zone header. No-op if not found. |
| `AQL:ToggleQuestLogZoneByName(zoneName)` | — | Toggles the named zone header. No-op if not found. |
| `AQL:IsQuestLogZoneCollapsed(zoneName)` | bool or nil | True if the zone header is collapsed. nil if not found. |

#### ⚠️ Deprecated Methods

The following methods expose `logIndex` or implicit selection state directly. They continue to function but **will be removed in a future major version**. Migrate to the alternatives shown.

| Deprecated | Use instead |
|---|---|
| `AQL:GetQuestLogSelection()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:GetSelectedQuestId()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:IsQuestLogShareable()` | `AQL:IsQuestIdShareable(questID)` |
| `AQL:SelectQuestLogEntry(logIndex)` | `AQL:SelectQuestLogEntryById(questID)` |
| `AQL:SetQuestLogSelection(logIndex)` | `AQL:SelectAndShowQuestLogEntryById(questID)` |
| `AQL:ExpandQuestLogHeader(logIndex)` | `AQL:ExpandQuestLogZoneByName(zoneName)` |
| `AQL:CollapseQuestLogHeader(logIndex)` | `AQL:CollapseQuestLogZoneByName(zoneName)` |

---

## Callbacks

Register for events using:

```lua
AQL:RegisterCallback(AQL.Event.QuestAccepted, handlerFunction, optionalTarget)
AQL:UnregisterCallback(AQL.Event.QuestAccepted, handlerFunction)
```

Always use the `AQL.Event` constants — do not use raw strings directly.

| Constant | Arguments | Fired When |
|---|---|---|
| `AQL.Event.QuestAccepted` | `(questInfo)` | Quest newly appears in the player's log (not fired on first login rebuild). |
| `AQL.Event.QuestAbandoned` | `(questInfo)` | Quest removed from log without completing or failing. |
| `AQL.Event.QuestCompleted` | `(questInfo)` | Quest turned in successfully (`IsQuestFlaggedCompleted` is true). |
| `AQL.Event.QuestFinished` | `(questInfo)` | All objectives met; quest not yet turned in (`isComplete` → true). |
| `AQL.Event.QuestFailed` | `(questInfo)` | Quest failed (timer expired or escort NPC died). |
| `AQL.Event.QuestTracked` | `(questInfo)` | Quest added to the watch list (`isTracked` → true). |
| `AQL.Event.QuestUntracked` | `(questInfo)` | Quest removed from the watch list (`isTracked` → false). |
| `AQL.Event.ObjectiveProgressed` | `(questInfo, objInfo, delta)` | Objective `numFulfilled` increased. `delta` is the increase amount. |
| `AQL.Event.ObjectiveCompleted` | `(questInfo, objInfo)` | Objective reached `numRequired`. |
| `AQL.Event.ObjectiveRegressed` | `(questInfo, objInfo, delta)` | Objective `numFulfilled` decreased. Suppressed during quest turn-in. |
| `AQL.Event.ObjectiveFailed` | `(questInfo, objInfo)` | Objective failed alongside a failed quest. |
| `AQL.Event.UnitQuestLogChanged` | `(unit)` | `UNIT_QUEST_LOG_CHANGED` fired for a non-player unit (e.g., party member). |

---

## Data Structures

### QuestInfo

Returned by `GetQuest`, `GetAllQuests`, `GetQuestsByZone`, and callback arguments.

```lua
{
    questID        = N,
    title          = "string",
    level          = N,               -- Recommended difficulty level
    suggestedGroup = N,               -- 0 if not a group quest
    zone           = "string",        -- Zone header from quest log (nil for non-cached quests)
    type           = "string" or nil, -- "normal"|"elite"|"dungeon"|"raid"|"daily"|"pvp"|"escort"
    faction        = "string" or nil, -- "Alliance"|"Horde"|nil
    isComplete     = bool,            -- true = objectives met, not yet turned in
    isFailed       = bool,
    failReason     = "string" or nil, -- "timeout"|"escort_died"
    isTracked      = bool,
    link           = "string",        -- Chat hyperlink
    logIndex       = N,               -- Position in quest log at snapshot time
    snapshotTime   = N,               -- GetTime() when this entry was built
    timerSeconds   = N or nil,        -- nil if quest has no timer
    objectives     = {
        {
            index        = N,
            text         = "string",  -- Full text e.g. "Tainted Ooze killed: 4/10"
            name         = "string",  -- Text with count suffix stripped
            type         = "string",
            numFulfilled = N,
            numRequired  = N,
            isFinished   = bool,
            isFailed     = bool,
        },
        -- ...
    },
    chainInfo = ChainInfo,
}
```

`GetQuestInfo` (three-tier resolution) always includes `questID`. `title` is included when any resolution tier finds it; it may be nil for quests known only through chain data.

### ChainInfo

Returned by `GetChainInfo`. Requires Questie or QuestWeaver.

```lua
-- When chain data is known:
{
    knownStatus = "known",
    chainID     = N,        -- questID of the first quest in the chain
    step        = N,        -- 1-based position of this quest
    length      = N,        -- Total quests in the chain
    steps       = {
        {
            questID = N,
            title   = "string",
            status  = "completed"|"active"|"finished"|"failed"|"available"|"unavailable"|"unknown",
        },
        -- ...
    },
    provider = "Questie"|"QuestWeaver"|"none",
}

-- When the quest is not part of a chain:
{ knownStatus = "not_a_chain" }

-- When no provider is available:
{ knownStatus = "unknown" }
```

Use `AQL.ChainStatus.Known`, `AQL.ChainStatus.NotAChain`, and `AQL.ChainStatus.Unknown` constants instead of raw strings.

---

## Debug Mode

```
/aql debug on       -- Key events: quest accept/complete/fail/abandon, provider selection
/aql debug verbose  -- Everything: cache rebuilds, diffs, all event firings
/aql debug off      -- Silent (default)
```

Debug messages are prefixed `[AQL]` in gold.
