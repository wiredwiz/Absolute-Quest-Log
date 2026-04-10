# AQL questID API Audit & README — Design Spec

**Date:** 2026-03-29
**Repo:** Absolute-Quest-Log
**Feature:** questID-first public API — add missing questID variants, deprecate logIndex-exposing thin wrappers, rewrite README for consumers

---

## Goal

Make the AQL public API stable, version-agnostic, and consumer-friendly. The WoW Retail API shifted from logIndex to questID in 9.0.1; several AQL thin wrappers still expose logIndex directly, which is an implementation detail that will not survive that transition. This sub-project:

1. Adds two missing questID-based methods
2. Marks seven logIndex-exposing thin wrappers as deprecated (no removal — backwards compat maintained)
3. Restructures the CLAUDE.md public API tables to make questID-first intent visible
4. Rewrites README.md as a complete consumer-facing reference with examples

Zero behavioral changes to non-deprecated methods. All deprecated methods continue to work.

---

## Context

AQL is a version-agnostic quest data library. questID is the stable, cross-version identifier for quests. logIndex is a positional cursor into the visible quest log frame — it changes on every log update and does not exist in the same form on Retail (where `C_QuestLog.SetSelectedQuest` takes questID instead). Any public method that exposes logIndex to consumers is a future breaking point.

The compound ByIndex/ById method pairs (`OpenQuestLogByIndex`/`OpenQuestLogById`, etc.) are **not deprecated** — logIndex is still valid for consumers who already have it (e.g., from iterating `GetQuestLogEntries()`), and the ByIndex/ById suffix makes the parameter type explicit.

---

## Files Modified

| File | Change |
|---|---|
| `AbsoluteQuestLog.lua` | Add 2 new methods; add `@deprecated` doc markers on 7 methods |
| `CLAUDE.md` | Restructure Group 2 thin wrappers table; add new methods to ById/ByIndex sections; version entry |
| `README.md` | Complete rewrite — consumer-facing reference with examples |
| All 5 toc files | Version bump per versioning rule |
| `changelog.txt` | New version entry |

---

## Deliverable 1 — New methods in AbsoluteQuestLog.lua

### 1a. `AQL:GetSelectedQuestLogEntryId()` (replaces `GetSelectedQuestId`)

Add immediately after `GetSelectedQuestId`. Identical body — `GetSelectedQuestId` becomes a deprecated alias pointing here.

```lua
------------------------------------------------------------------------
-- GetSelectedQuestLogEntryId() → questID or nil
-- Returns the questID of the currently selected quest log entry.
-- Returns nil if nothing is selected or if the selected entry is a
-- zone header row.
-- Replaces: GetSelectedQuestId() (deprecated)
------------------------------------------------------------------------
function AQL:GetSelectedQuestLogEntryId()
    local logIndex = WowQuestAPI.GetQuestLogSelection()
    if not logIndex or logIndex == 0 then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestLogEntryId: no entry selected — returning nil" .. self.RESET)
        end
        return nil
    end
    local _, _, _, isHeader, _, _, _, questID = WowQuestAPI.GetQuestLogTitle(logIndex)
    if isHeader then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestLogEntryId: selected entry is a header — returning nil" .. self.RESET)
        end
        return nil
    end
    return questID
end
```

> **Note for implementer:** The code block above is **illustrative only**. You MUST read the existing `GetSelectedQuestId()` body at line ~686 and copy it verbatim — only change the method name in the function declaration and in any debug message strings. Two specific differences between the illustration and the real code that you must NOT lose:
> 1. The isHeader guard in the real code is `if isHeader or not questID then` — not just `if isHeader then`
> 2. The debug message strings include `logIndex` in the output (e.g., `"logIndex=" .. tostring(logIndex)`)
> Copy the full real implementation; do not use the illustration as the source.

### 1b. `AQL:SelectQuestLogEntryById(questID)` (new method — no existing equivalent)

Add in the Compound ById section of `AbsoluteQuestLog.lua`, after `IsQuestIdShareable`:

```lua
-- SelectQuestLogEntryById(questID)
-- Selects questID in the quest log WITHOUT refreshing the display.
-- Use SelectAndShowQuestLogEntryById to select and refresh simultaneously.
-- No-op with a normal-level debug message if questID is not in the log.
function AQL:SelectQuestLogEntryById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] SelectQuestLogEntryById: questID=" .. tostring(questID) .. " not in quest log — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.SelectQuestLogEntry(logIndex)
end
```

---

## Deliverable 2 — Deprecation markers on 7 methods in AbsoluteQuestLog.lua

For each method below, prepend a `@deprecated` line to the existing doc comment block. Do not change the function body — the method must continue to work.

**Deprecation comment format** (add as first line of the doc block):

```lua
-- @deprecated Use <replacement> instead. This method exposes a logIndex or
-- implicit selection state that is not stable across WoW version families.
-- Will be removed in a future major version.
```

| Method | Replacement |
|---|---|
| `AQL:GetQuestLogSelection()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:GetSelectedQuestId()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:IsQuestLogShareable()` | `AQL:IsQuestIdShareable(questID)` |
| `AQL:SelectQuestLogEntry(logIndex)` | `AQL:SelectQuestLogEntryById(questID)` |
| `AQL:SetQuestLogSelection(logIndex)` | `AQL:SelectAndShowQuestLogEntryById(questID)` |
| `AQL:ExpandQuestLogHeader(logIndex)` | `AQL:ExpandQuestLogZoneByName(zoneName)` |
| `AQL:CollapseQuestLogHeader(logIndex)` | `AQL:CollapseQuestLogZoneByName(zoneName)` |

---

## Deliverable 3 — CLAUDE.md restructure

### 3a. Split the Thin Wrappers table in Group 2

Replace the single "Thin Wrappers" table with two sub-sections:

**Thin Wrappers — Preferred** (keep in primary position):

| Method | Returns | Notes |
|---|---|---|
| `AQL:ShowQuestLog()` | — | Opens the quest log frame |
| `AQL:HideQuestLog()` | — | Closes the quest log frame |
| `AQL:IsQuestLogShown()` | bool | True if quest log is visible |
| `AQL:GetQuestDifficultyColor(level)` | `{r,g,b}` | Fallback to manual delta if native API absent |
| `AQL:GetQuestLogIndex(questID)` | logIndex or nil | nil if not in log or under collapsed header |

**Thin Wrappers — Deprecated** (new sub-section after Preferred):

> ⚠️ **Deprecated.** These methods expose logIndex or implicit selection state that is not stable across WoW version families. Use the questID-based alternatives shown. They will be removed in a future major version.

| Deprecated Method | Replacement |
|---|---|
| `AQL:GetQuestLogSelection()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:IsQuestLogShareable()` | `AQL:IsQuestIdShareable(questID)` |
| `AQL:SelectQuestLogEntry(logIndex)` | `AQL:SelectQuestLogEntryById(questID)` |
| `AQL:SetQuestLogSelection(logIndex)` | `AQL:SelectAndShowQuestLogEntryById(questID)` |
| `AQL:ExpandQuestLogHeader(logIndex)` | `AQL:ExpandQuestLogZoneByName(zoneName)` |
| `AQL:CollapseQuestLogHeader(logIndex)` | `AQL:CollapseQuestLogZoneByName(zoneName)` |

### 3b. Update Compound ByIndex section

Add `GetSelectedQuestLogEntryId` to the Compound ByIndex table (it is a ByIndex-equivalent operation — reads the current log selection):

| Method | Returns | Notes |
|---|---|---|
| `AQL:GetSelectedQuestLogEntryId()` | questID or nil | nil if nothing selected or header selected. **Replaces deprecated `GetSelectedQuestId()`** |
| _(existing entries unchanged)_ | | |

Also add to the "Deprecated" column note on `GetSelectedQuestId()` in the existing ByIndex table if it appears there.

### 3c. Update Compound ById section

Add `SelectQuestLogEntryById` to the Compound ById table:

| Method | Returns | Notes |
|---|---|---|
| `AQL:SelectQuestLogEntryById(questID)` | — | Selects without display refresh; no-op + debug if not in log |
| _(existing entries unchanged)_ | | |

Add note to ById section header: *"**Preferred for most consumers.** Use ById methods when you have a questID — questID is stable across WoW version families; logIndex is not."*

Also add `GetSelectedQuestId()` to the deprecated thin wrappers table (it was in Compound ByIndex before — move it to deprecated).

### 3d. Add Version entry

Add version entry per versioning rule (see Deliverable 5).

---

## Deliverable 4 — README.md complete rewrite

Replace the current stub with the following structure. Full content is specified section by section below.

### Section 1: Header and description

```markdown
# AbsoluteQuestLog-1.0

A version-agnostic WoW addon library that provides a clean, stable API for quest data and quest log events. AbsoluteQuestLog (AQL) abstracts away the differences between WoW client versions and gives your addon a single consistent interface that works across Classic Era, TBC Classic, Mists of Pandaria Classic, and Retail — without you having to branch for each one.

**Supported WoW versions:**

| Version Family | Interface | Status |
|---|---|---|
| Classic Era | 1.14.x (11508) | ✅ Supported |
| TBC Classic | 2.5.x (20505) | ✅ Supported |
| Mists of Pandaria Classic | 5.4.x (50503) | ✅ Supported |
| Retail (The War Within) | 11.x (120001) | 🚧 In development |
```

### Section 2: Installation

```markdown
## Installation

Declare AQL as a dependency in your addon's `.toc` file:

```
## Dependencies: AbsoluteQuestLog
```

Then get the library handle at the top of your Lua file:

```lua
local AQL = LibStub("AbsoluteQuestLog-1.0")
```
```

### Section 3: Quick Start

```markdown
## Quick Start

### Reacting to quest events

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

### Fetching quest data

```lua
local AQL = LibStub("AbsoluteQuestLog-1.0")

-- Get data for a specific quest
local questInfo = AQL:GetQuest(questID)
if questInfo then
    print(questInfo.title .. " — Level " .. questInfo.level)
    print("Zone: " .. (questInfo.zone or "Unknown"))
    print("Complete: " .. tostring(questInfo.isComplete))
end

-- Get all quests in the player's log
for questID, questInfo in pairs(AQL:GetAllQuests()) do
    print(questID, questInfo.title)
end
```

### Checking quest history

```lua
if AQL:HasCompletedQuest(questID) then
    print("Already done this one.")
end
```
```

### Section 4: API Reference — Group 1: Quest APIs

Document all Group 1 methods. These are all questID-based — no logIndex anywhere.

Subsections: Quest State, Quest History, Quest Resolution, Objectives, Chain Info, Requirements, Quest Tracking, Player & Level.

For each method, one table row: method signature | returns | description.

Use the existing CLAUDE.md tables as the source of truth for method signatures and return types. Keep descriptions concise (one line each).

Include this note at the top of the Group 1 section:
> All Group 1 methods take `questID` as their primary identifier. questID is stable across all WoW version families.

### Section 5: API Reference — Group 2: Quest Log Frame APIs

> ℹ️ Group 2 methods interact with the quest log frame UI. The **ById methods are preferred** — they take questID, which is stable across WoW version families.

**Sub-section: Compound ById (Preferred)**
All ById methods: `IsQuestIdShareable`, `SelectQuestLogEntryById`, `SelectAndShowQuestLogEntryById`, `OpenQuestLogById`, `ToggleQuestLogById`.

Also include: `GetSelectedQuestLogEntryId`, `GetQuestLogEntries`, `GetQuestLogZones`, zone expand/collapse/toggle methods, `IsQuestLogZoneCollapsed`.

Note on nil behavior: *"If questID is not in the active quest log, all ById methods are silent no-ops (return false or nothing). A debug message is emitted when debug mode is on."*

**Sub-section: Compound ByIndex (Available)**
All ByIndex methods. Note: *"Use these when you already have a logIndex (e.g., from iterating `GetQuestLogEntries()`). logIndex is a positional cursor — it changes on every quest log update."*

**Sub-section: Other (Frame control)**
`ShowQuestLog`, `HideQuestLog`, `IsQuestLogShown`, `GetQuestDifficultyColor`, `GetQuestLogIndex`.

**Sub-section: ⚠️ Deprecated Methods**

```markdown
### ⚠️ Deprecated Methods

The following methods expose `logIndex` or implicit selection state directly.
They will be removed in a future major version. Migrate to the alternatives shown.

| Deprecated | Use instead |
|---|---|
| `AQL:GetQuestLogSelection()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:GetSelectedQuestId()` | `AQL:GetSelectedQuestLogEntryId()` |
| `AQL:IsQuestLogShareable()` | `AQL:IsQuestIdShareable(questID)` |
| `AQL:SelectQuestLogEntry(logIndex)` | `AQL:SelectQuestLogEntryById(questID)` |
| `AQL:SetQuestLogSelection(logIndex)` | `AQL:SelectAndShowQuestLogEntryById(questID)` |
| `AQL:ExpandQuestLogHeader(logIndex)` | `AQL:ExpandQuestLogZoneByName(zoneName)` |
| `AQL:CollapseQuestLogHeader(logIndex)` | `AQL:CollapseQuestLogZoneByName(zoneName)` |
```

### Section 6: Callbacks

```markdown
## Callbacks

Register for events using:

```lua
AQL:RegisterCallback(AQL.Event.QuestAccepted, handlerFunction, optionalTarget)
AQL:UnregisterCallback(AQL.Event.QuestAccepted, handlerFunction)
```

Use the `AQL.Event` constants — do not use raw strings:

| Constant | Raw String | Arguments | Fired When |
|---|---|---|---|
| `AQL.Event.QuestAccepted` | `AQL_QUEST_ACCEPTED` | `(questInfo)` | Quest newly appears in log |
| `AQL.Event.QuestAbandoned` | `AQL_QUEST_ABANDONED` | `(questInfo)` | Quest removed without completion |
| `AQL.Event.QuestCompleted` | `AQL_QUEST_COMPLETED` | `(questInfo)` | Quest turned in successfully |
| `AQL.Event.QuestFinished` | `AQL_QUEST_FINISHED` | `(questInfo)` | All objectives met, not yet turned in |
| `AQL.Event.QuestFailed` | `AQL_QUEST_FAILED` | `(questInfo)` | Quest failed (timeout / escort died) |
| `AQL.Event.QuestTracked` | `AQL_QUEST_TRACKED` | `(questInfo)` | Quest added to watch list |
| `AQL.Event.QuestUntracked` | `AQL_QUEST_UNTRACKED` | `(questInfo)` | Quest removed from watch list |
| `AQL.Event.ObjectiveProgressed` | `AQL_OBJECTIVE_PROGRESSED` | `(questInfo, objInfo, delta)` | Objective count increased |
| `AQL.Event.ObjectiveCompleted` | `AQL_OBJECTIVE_COMPLETED` | `(questInfo, objInfo)` | Objective reached required count |
| `AQL.Event.ObjectiveRegressed` | `AQL_OBJECTIVE_REGRESSED` | `(questInfo, objInfo, delta)` | Objective count decreased |
| `AQL.Event.ObjectiveFailed` | `AQL_OBJECTIVE_FAILED` | `(questInfo, objInfo)` | Objective failed with quest |
| `AQL.Event.UnitQuestLogChanged` | `AQL_UNIT_QUEST_LOG_CHANGED` | `(unit)` | Another unit's quest log changed |
```

### Section 7: Data Structures

Document QuestInfo and ChainInfo field tables. Use CLAUDE.md as the source of truth. Keep field descriptions to one line each.

### Section 8: Debug Mode

```markdown
## Debug Mode

```
/aql debug on       — Key events only
/aql debug verbose  — Everything (cache rebuilds, diffs, all firings)
/aql debug off      — Silent (default)
```

Debug messages are prefixed `[AQL]` in gold.
```

---

## Deliverable 5 — Version bump and changelog

- Bump all five toc files per versioning rule (same-day → revision bump from 2.5.3 → **2.5.4**; new day → minor bump → **2.6.0**). Apply whichever rule applies at implementation time.
- Add version entry to CLAUDE.md Version History.
- Add entry to `changelog.txt`.

### Changelog content

```
- Feature: AQL:GetSelectedQuestLogEntryId() added — questID-based replacement for
  deprecated GetSelectedQuestId() and GetQuestLogSelection().
- Feature: AQL:SelectQuestLogEntryById(questID) added — select without display
  refresh; questID-based replacement for deprecated SelectQuestLogEntry(logIndex).
- Deprecation: GetQuestLogSelection, GetSelectedQuestId, IsQuestLogShareable,
  SelectQuestLogEntry, SetQuestLogSelection, ExpandQuestLogHeader,
  CollapseQuestLogHeader marked @deprecated. All continue to function; will be
  removed in a future major version. See README for migration guide.
- Docs: README.md rewritten as complete consumer-facing reference with API docs,
  callback reference, data structures, code examples, and deprecation guide.
  Version support table updated to reflect Classic Era, TBC, MoP, and Retail (in
  development) support.
- Docs: CLAUDE.md Group 2 thin wrappers restructured into Preferred and Deprecated
  sub-sections; ById section marked as preferred for most consumers.
```

---

## Success Criteria

1. `AQL:GetSelectedQuestLogEntryId()` exists and returns the same result as `GetSelectedQuestId()`.
2. `AQL:SelectQuestLogEntryById(questID)` exists, resolves questID → logIndex, calls `SelectQuestLogEntry`, and is a no-op when questID is not in the log.
3. All 7 deprecated methods still function (no behavioral change); each has `@deprecated` in its doc comment naming its replacement.
4. README.md contains all public API methods, all 12 callbacks with args, QuestInfo and ChainInfo data structures, two Quick Start examples, and the deprecated methods table.
5. CLAUDE.md Group 2 thin wrappers section has two sub-sections: Preferred and Deprecated.
6. Version bumped in all five toc files; changelog and CLAUDE.md Version History updated.
