# Quest Log API Wrappers Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WowQuestAPI wrappers for all WoW quest log frame globals, expose them as a fully-documented two-group public API on AQL, and add level-range filtering methods.

**Architecture:** All WoW globals are wrapped in `WowQuestAPI.lua`. `AbsoluteQuestLog.lua` exposes them as Group 1 (Quest APIs — data) and Group 2 (Quest Log APIs — frame interaction). Compound methods delegate down the chain: ById → ByIndex → thin wrappers → WowQuestAPI → WoW globals.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary (Interface 20505), LibStub. No automated test framework — verification is in-game via `/aql debug verbose` and the WoW `/run` command.

**Spec:** `docs/superpowers/specs/2026-03-23-quest-log-api-wrappers-design.md`

---

## File Map

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | Append new Quest Log Frame & Navigation section (14 new wrappers) |
| `AbsoluteQuestLog.lua` | Update section headers; append Group 1 Player & Level + entire Group 2 |
| `CLAUDE.md` | Update Public API table to reflect two-group structure and all new methods |

**Load order note (from TOC):** `AbsoluteQuestLog.lua` loads before `Core/WowQuestAPI.lua`. All new AQL methods are function definitions only — they call `WowQuestAPI.*` at runtime, not at load time. No ordering issue.

---

## Chunk 1: WowQuestAPI additions

### Task 1: Add Quest Log Frame & Navigation section to `Core/WowQuestAPI.lua`

**Files:**
- Modify: `Core/WowQuestAPI.lua` (append after the `IsUnitOnQuest` block at line 155)

- [ ] **Step 1: Append the new section**

Add to the bottom of `Core/WowQuestAPI.lua`:

```lua
------------------------------------------------------------------------
-- Quest Log Frame & Navigation
-- Thin, stateless wrappers matching WoW global names exactly.
-- Compound logic lives in AbsoluteQuestLog.lua.
-- logIndex is always a position in the *currently visible* quest log
-- entries. Quests under collapsed headers are invisible to these APIs.
------------------------------------------------------------------------

-- GetNumQuestLogEntries() → number
-- Returns the total number of visible entries (zone headers + quests).
function WowQuestAPI.GetNumQuestLogEntries()
    return GetNumQuestLogEntries()
end

-- GetQuestLogTitle(logIndex) → title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
-- Returns all fields for the entry at the given visible logIndex.
-- Header rows: title = zone name, isHeader = true, questID = nil.
-- Quest rows:  isHeader = false, questID = the quest's numeric ID.
function WowQuestAPI.GetQuestLogTitle(logIndex)
    return GetQuestLogTitle(logIndex)
end

-- GetQuestLogSelection() → logIndex
-- Returns the currently selected quest log entry index, or 0 if none selected.
function WowQuestAPI.GetQuestLogSelection()
    return GetQuestLogSelection()
end

-- SelectQuestLogEntry(logIndex)
-- Sets the selected entry without refreshing the quest log display.
function WowQuestAPI.SelectQuestLogEntry(logIndex)
    SelectQuestLogEntry(logIndex)
end

-- GetQuestLogPushable() → bool
-- Returns true if the currently selected quest can be shared with party members.
-- Only meaningful when the target quest is already selected.
function WowQuestAPI.GetQuestLogPushable()
    return GetQuestLogPushable() == true
end

-- QuestLog_SetSelection(logIndex)
-- Updates the UI selection highlight. Always paired with QuestLog_Update().
-- Use AQL:SetQuestLogSelection() for the canonical two-call sequence.
function WowQuestAPI.QuestLog_SetSelection(logIndex)
    QuestLog_SetSelection(logIndex)
end

-- QuestLog_Update()
-- Refreshes the quest log display. Always paired with QuestLog_SetSelection().
-- Use AQL:SetQuestLogSelection() for the canonical two-call sequence.
function WowQuestAPI.QuestLog_Update()
    QuestLog_Update()
end

-- ExpandQuestHeader(logIndex)
-- Expands the collapsed zone header at logIndex.
function WowQuestAPI.ExpandQuestHeader(logIndex)
    ExpandQuestHeader(logIndex)
end

-- CollapseQuestHeader(logIndex)
-- Collapses the zone header at logIndex.
function WowQuestAPI.CollapseQuestHeader(logIndex)
    CollapseQuestHeader(logIndex)
end

-- ShowQuestLog()
-- Opens the quest log frame via ShowUIPanel(QuestLogFrame).
function WowQuestAPI.ShowQuestLog()
    ShowUIPanel(QuestLogFrame)
end

-- HideQuestLog()
-- Closes the quest log frame via HideUIPanel(QuestLogFrame).
function WowQuestAPI.HideQuestLog()
    HideUIPanel(QuestLogFrame)
end

-- IsQuestLogShown() → bool
-- Returns true if the quest log frame is currently visible.
function WowQuestAPI.IsQuestLogShown()
    return QuestLogFrame:IsShown() == true
end

-- GetQuestDifficultyColor(level) → {r, g, b}
-- Returns a color table for a quest level relative to the player.
-- Uses native GetQuestDifficultyColor if available; falls back to manual
-- level-delta thresholds when the API is absent.
-- Fallback thresholds (diff = questLevel - playerLevel):
--   diff >= 5  → red    {1.00, 0.10, 0.10}  (very hard)
--   diff >= 3  → orange {1.00, 0.50, 0.25}  (hard)
--   diff >= -2 → yellow {1.00, 1.00, 0.00}  (normal)
--   diff >= -5 → green  {0.25, 0.75, 0.25}  (easy)
--   else       → grey   {0.75, 0.75, 0.75}  (trivial)
function WowQuestAPI.GetQuestDifficultyColor(level)
    if GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(level)
        if color then
            return { r = color.r, g = color.g, b = color.b }
        end
    end
    local playerLevel = UnitLevel("player") or 1
    local diff = level - playerLevel
    if diff >= 5 then
        return { r = 1.00, g = 0.10, b = 0.10 }
    elseif diff >= 3 then
        return { r = 1.00, g = 0.50, b = 0.25 }
    elseif diff >= -2 then
        return { r = 1.00, g = 1.00, b = 0.00 }
    elseif diff >= -5 then
        return { r = 0.25, g = 0.75, b = 0.25 }
    else
        return { r = 0.75, g = 0.75, b = 0.75 }
    end
end

-- GetPlayerLevel() → number
-- Returns the player's current character level.
function WowQuestAPI.GetPlayerLevel()
    return UnitLevel("player")
end
```

- [ ] **Step 2: Verify in-game**

`/reload`, then in the WoW chat box:
```
/run print(WowQuestAPI.GetPlayerLevel())
/run print(WowQuestAPI.IsQuestLogShown())
/run print(WowQuestAPI.GetNumQuestLogEntries())
/run local c = WowQuestAPI.GetQuestDifficultyColor(60) print(c.r, c.g, c.b)
```
Expected: player level number, `false` (log closed), entry count, color values.

- [ ] **Step 3: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: add Quest Log Frame & Navigation wrappers to WowQuestAPI"
```

---

## Chunk 2: AbsoluteQuestLog.lua — section reorganization and thin wrappers

### Task 2: Update section headers for two-group structure

The existing methods stay in place. Only comment headers are added or renamed to create the Group 1 / Group 2 structure.

**Files:**
- Modify: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Replace Quest State header with Group 1 banner + Quest State subsection**

Find:
```lua
------------------------------------------------------------------------
-- Public API: Quest State Queries
------------------------------------------------------------------------
```
Replace with:
```lua
------------------------------------------------------------------------
-- GROUP 1: QUEST APIS
-- Data and state queries about quests. No interaction with the quest log frame.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Quest State
------------------------------------------------------------------------
```

- [ ] **Step 2: Add Quest History subsection header**

`HasCompletedQuest` is currently in the Quest State block. Insert a subsection header directly before `function AQL:HasCompletedQuest`:

```lua
------------------------------------------------------------------------
-- Quest History
------------------------------------------------------------------------
```

- [ ] **Step 3: Replace WowQuestAPI-backed Extended Queries header with Quest Resolution**

Find:
```lua
------------------------------------------------------------------------
-- Public API: WowQuestAPI-backed Extended Queries
------------------------------------------------------------------------
```
Replace with:
```lua
------------------------------------------------------------------------
-- Quest Resolution
------------------------------------------------------------------------
```

- [ ] **Step 4: Replace Objective Queries and Chain Queries headers**

Find and replace:
```lua
------------------------------------------------------------------------
-- Public API: Objective Queries
------------------------------------------------------------------------
```
→
```lua
------------------------------------------------------------------------
-- Objectives
------------------------------------------------------------------------
```

Find and replace:
```lua
------------------------------------------------------------------------
-- Public API: Chain Queries
------------------------------------------------------------------------
```
→
```lua
------------------------------------------------------------------------
-- Chain Info
------------------------------------------------------------------------
```

- [ ] **Step 5: Add Quest Tracking subsection header**

Insert directly before `function AQL:TrackQuest`:
```lua
------------------------------------------------------------------------
-- Quest Tracking
------------------------------------------------------------------------
```

- [ ] **Step 6: Verify — `/reload` in WoW, confirm no errors in chat**

- [ ] **Step 7: Commit**

```bash
git add "AbsoluteQuestLog.lua"
git commit -m "refactor: reorganize AbsoluteQuestLog.lua into Group 1 / Group 2 structure"
```

---

### Task 3: Add Group 2 thin wrappers

Add the Group 2 section and all thin wrapper methods. Insert this block between the last Quest Tracking method (`AQL:IsUnitOnQuest`) and the `-- Slash command` section.

**Files:**
- Modify: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Add the thin wrappers block**

Insert after `AQL:IsUnitOnQuest` and before the `-- Slash command` section:

```lua
------------------------------------------------------------------------
-- GROUP 2: QUEST LOG APIS
-- Methods that interact with the built-in WoW quest log frame.
--
-- logIndex note: logIndex is always a position in the *currently visible*
-- quest log entries. Quests under collapsed zone headers are invisible to
-- the WoW API and return nil from any logIndex-resolution method.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Quest Log APIs — Thin Wrappers
-- One-to-one with WoW globals. No debug messages (direct pass-throughs).
------------------------------------------------------------------------

-- ShowQuestLog()
-- Opens the quest log frame.
function AQL:ShowQuestLog()
    WowQuestAPI.ShowQuestLog()
end

-- HideQuestLog()
-- Closes the quest log frame.
function AQL:HideQuestLog()
    WowQuestAPI.HideQuestLog()
end

-- IsQuestLogShown() → bool
-- Returns true if the quest log frame is currently visible.
function AQL:IsQuestLogShown()
    return WowQuestAPI.IsQuestLogShown()
end

-- GetQuestLogSelection() → logIndex
-- Returns the currently selected quest log entry index (0 if none selected).
function AQL:GetQuestLogSelection()
    return WowQuestAPI.GetQuestLogSelection()
end

-- SelectQuestLogEntry(logIndex)
-- Sets the selected entry without refreshing the quest log display.
-- Does not emit a debug message — use SetQuestLogSelection for the
-- display-refreshing version.
function AQL:SelectQuestLogEntry(logIndex)
    WowQuestAPI.SelectQuestLogEntry(logIndex)
end

-- IsQuestLogShareable() → bool
-- Returns true if the currently selected quest can be shared with party members.
-- Delegates to WowQuestAPI.GetQuestLogPushable().
-- WARNING: Result depends entirely on the current quest log selection.
-- If nothing is selected or the wrong entry is selected, the result is
-- meaningless. Prefer IsQuestIndexShareable or IsQuestIdShareable when
-- operating on a specific quest. This method exists only for callers that
-- have already managed selection themselves.
-- Emits no debug message (pass-through; caller manages selection context).
function AQL:IsQuestLogShareable()
    return WowQuestAPI.GetQuestLogPushable()
end

-- SetQuestLogSelection(logIndex)
-- Sets selection AND refreshes the quest log display.
-- Calls WowQuestAPI.QuestLog_SetSelection(logIndex) followed immediately
-- by WowQuestAPI.QuestLog_Update(). These two calls are always used together;
-- this is the canonical two-call sequence.
function AQL:SetQuestLogSelection(logIndex)
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] SetQuestLogSelection: logIndex=" .. tostring(logIndex) .. self.RESET)
    end
    WowQuestAPI.QuestLog_SetSelection(logIndex)
    WowQuestAPI.QuestLog_Update()
end

-- ExpandQuestLogHeader(logIndex)
-- Expands the collapsed zone header at logIndex.
-- Verifies the entry is a header before acting; emits a normal-level debug
-- message and returns without expanding if it is not.
-- Emits a verbose debug message on successful expansion.
function AQL:ExpandQuestLogHeader(logIndex)
    local _, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(logIndex)
    if not isHeader then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ExpandQuestLogHeader: logIndex=" .. tostring(logIndex) .. " is not a header — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.ExpandQuestHeader(logIndex)
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ExpandQuestLogHeader: expanded header at logIndex=" .. tostring(logIndex) .. self.RESET)
    end
end

-- CollapseQuestLogHeader(logIndex)
-- Collapses the zone header at logIndex.
-- Verifies the entry is a header before acting; emits a normal-level debug
-- message and returns without collapsing if it is not.
-- Emits a verbose debug message on successful collapse.
function AQL:CollapseQuestLogHeader(logIndex)
    local _, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(logIndex)
    if not isHeader then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] CollapseQuestLogHeader: logIndex=" .. tostring(logIndex) .. " is not a header — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.CollapseQuestHeader(logIndex)
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] CollapseQuestLogHeader: collapsed header at logIndex=" .. tostring(logIndex) .. self.RESET)
    end
end

-- GetQuestDifficultyColor(level) → {r, g, b}
-- Returns a color table for the given quest level relative to the player.
function AQL:GetQuestDifficultyColor(level)
    return WowQuestAPI.GetQuestDifficultyColor(level)
end

-- GetQuestLogIndex(questID) → logIndex or nil
-- Returns the 1-based quest log index for a questID, or nil if not found.
-- Returns nil for quests under collapsed zone headers — they are invisible
-- to the WoW API even though the quest is in the player's log; expand the
-- header first to make the quest visible.
-- Zone header rows carry no questID and are never matched.
function AQL:GetQuestLogIndex(questID)
    return WowQuestAPI.GetQuestLogIndex(questID)
end
```

- [ ] **Step 2: Verify in-game**

```
/reload
/aql debug verbose
/run AQL:ShowQuestLog()
/run AQL:HideQuestLog()
/run print(AQL:IsQuestLogShown())
/run print(AQL:GetQuestLogIndex(1234))
/run AQL:ExpandQuestLogHeader(999)
```
Expected: quest log opens/closes, `false` printed, `nil` printed for unknown quest, normal-level debug message for index 999 ("not a header").

- [ ] **Step 3: Commit**

```bash
git add "AbsoluteQuestLog.lua"
git commit -m "feat: add Group 2 Quest Log thin wrapper methods to AQL"
```

---

## Chunk 3: Compound ByIndex methods — selection and navigation

### Task 4: IsQuestIndexShareable, SelectAndShow, Open, Toggle, GetSelectedQuestId

Add after the thin wrappers block, before the slash command section.

**Files:**
- Modify: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Add compound ByIndex methods (selection/navigation group)**

Insert after the thin wrappers block:

```lua
------------------------------------------------------------------------
-- Quest Log APIs — Compound ByIndex
-- Multi-step operations taking logIndex. Delegate down to thin wrappers
-- and WowQuestAPI. All iteration uses WowQuestAPI.GetNumQuestLogEntries()
-- and WowQuestAPI.GetQuestLogTitle(i).
------------------------------------------------------------------------

-- IsQuestIndexShareable(logIndex) → bool
-- Returns true if the quest at logIndex can be shared with party members.
-- Verifies the entry is a quest row (not a header); returns false with a
-- normal-level debug message if it is a header.
-- Saves and restores the current quest log selection so the quest log's
-- visual state is unchanged after the call.
function AQL:IsQuestIndexShareable(logIndex)
    local _, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(logIndex)
    if isHeader then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] IsQuestIndexShareable: logIndex=" .. tostring(logIndex) .. " is a header row — returning false" .. self.RESET)
        end
        return false
    end
    local saved = WowQuestAPI.GetQuestLogSelection()
    WowQuestAPI.SelectQuestLogEntry(logIndex)
    local result = WowQuestAPI.GetQuestLogPushable()
    WowQuestAPI.SelectQuestLogEntry(saved)
    return result
end

-- SelectAndShowQuestLogEntryByIndex(logIndex)
-- Selects the entry at logIndex and refreshes the quest log display.
-- Delegates to SetQuestLogSelection (which emits a verbose debug message).
function AQL:SelectAndShowQuestLogEntryByIndex(logIndex)
    self:SetQuestLogSelection(logIndex)
end

-- OpenQuestLogByIndex(logIndex)
-- Shows the quest log frame and navigates to logIndex.
function AQL:OpenQuestLogByIndex(logIndex)
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] OpenQuestLogByIndex: showing quest log, navigating to logIndex=" .. tostring(logIndex) .. self.RESET)
    end
    WowQuestAPI.ShowQuestLog()
    self:SelectAndShowQuestLogEntryByIndex(logIndex)
end

-- ToggleQuestLogByIndex(logIndex)
-- If the quest log is shown and logIndex is the current selection, hides
-- the quest log. Otherwise opens the quest log and navigates to logIndex.
-- On the hide path: emits a verbose debug message.
-- On the open path: delegates to OpenQuestLogByIndex (which emits its own
-- verbose message — no separate message from ToggleQuestLogByIndex).
function AQL:ToggleQuestLogByIndex(logIndex)
    if WowQuestAPI.IsQuestLogShown() and WowQuestAPI.GetQuestLogSelection() == logIndex then
        if self.debug == "verbose" then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ToggleQuestLogByIndex: quest log is shown and logIndex=" .. tostring(logIndex) .. " is selected — hiding" .. self.RESET)
        end
        WowQuestAPI.HideQuestLog()
    else
        self:OpenQuestLogByIndex(logIndex)
    end
end

-- GetSelectedQuestId() → questID or nil
-- Returns the questID of the currently selected quest log entry.
-- Returns nil if nothing is selected (logIndex = 0) or if the selected
-- entry is a zone header row.
function AQL:GetSelectedQuestId()
    local logIndex = WowQuestAPI.GetQuestLogSelection()
    if not logIndex or logIndex == 0 then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestId: no entry selected — returning nil" .. self.RESET)
        end
        return nil
    end
    local _, _, _, isHeader, _, _, _, questID = WowQuestAPI.GetQuestLogTitle(logIndex)
    if isHeader or not questID then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestId: selected entry logIndex=" .. tostring(logIndex) .. " is a zone header — returning nil" .. self.RESET)
        end
        return nil
    end
    return questID
end
```

- [ ] **Step 2: Verify in-game**

```
/reload
/aql debug verbose
-- Open the built-in quest log, click a quest, then:
/run print(AQL:GetSelectedQuestId())
/run print(AQL:IsQuestIndexShareable(1))
/run AQL:ToggleQuestLogByIndex(AQL:GetQuestLogSelection())
/run AQL:ToggleQuestLogByIndex(AQL:GetQuestLogSelection())
```
Expected: questID printed, bool printed, quest log closes on first toggle, opens on second toggle. Verbose messages appear in chat.

- [ ] **Step 3: Commit**

```bash
git add "AbsoluteQuestLog.lua"
git commit -m "feat: add IsQuestIndexShareable, SelectAndShow, Open, Toggle, GetSelectedQuestId"
```

---

## Chunk 4: Compound ByIndex methods — iteration-based

### Task 5: GetQuestLogEntries, GetQuestLogZoneNames, ExpandAll, CollapseAll

**Files:**
- Modify: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Add iteration-based compound methods**

Append after `GetSelectedQuestId`:

```lua
-- GetQuestLogEntries() → array
-- Returns a structured array of all visible quest log entries in display order.
-- Each element: { logIndex=N, isHeader=bool, title="string",
--                 questID=N_or_nil, isCollapsed=bool_or_nil }
-- For quest rows (non-headers): isCollapsed is nil.
-- For header rows: questID is nil.
-- Emits no debug message — pure data query.
function AQL:GetQuestLogEntries()
    local entries = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, isCollapsed, _, _, questID = WowQuestAPI.GetQuestLogTitle(i)
        if title then
            table.insert(entries, {
                logIndex    = i,
                isHeader    = isHeader == true,
                title       = title,
                questID     = (not isHeader) and questID or nil,
                isCollapsed = isHeader and (isCollapsed == true) or nil,
            })
        end
    end
    return entries
end

-- GetQuestLogZoneNames() → array of strings
-- Returns an ordered array of all zone header name strings in the quest log.
-- Emits no debug message — pure data query.
function AQL:GetQuestLogZoneNames()
    local names = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(i)
        if title and isHeader then
            table.insert(names, title)
        end
    end
    return names
end

-- ExpandAllQuestLogHeaders()
-- Expands all currently collapsed zone headers in the quest log.
-- Emits a verbose debug message listing the count of headers expanded.
function AQL:ExpandAllQuestLogHeaders()
    local toExpand = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, isHeader, isCollapsed = WowQuestAPI.GetQuestLogTitle(i)
        if isHeader and isCollapsed then
            table.insert(toExpand, i)
        end
    end
    -- Expand back-to-front to preserve earlier indices.
    for k = #toExpand, 1, -1 do
        WowQuestAPI.ExpandQuestHeader(toExpand[k])
    end
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ExpandAllQuestLogHeaders: expanded " .. tostring(#toExpand) .. " headers" .. self.RESET)
    end
end

-- CollapseAllQuestLogHeaders()
-- Collapses all zone headers in the quest log.
-- Emits a verbose debug message listing the count of headers collapsed.
function AQL:CollapseAllQuestLogHeaders()
    local toCollapse = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(i)
        if isHeader then
            table.insert(toCollapse, i)
        end
    end
    -- Collapse back-to-front to preserve earlier indices.
    for k = #toCollapse, 1, -1 do
        WowQuestAPI.CollapseQuestHeader(toCollapse[k])
    end
    if self.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] CollapseAllQuestLogHeaders: collapsed " .. tostring(#toCollapse) .. " headers" .. self.RESET)
    end
end
```

- [ ] **Step 2: Verify in-game**

```
/reload
/aql debug verbose
/run local e = AQL:GetQuestLogEntries() print(#e, "entries")
/run local z = AQL:GetQuestLogZoneNames() for _,n in ipairs(z) do print(n) end
/run AQL:CollapseAllQuestLogHeaders()
/run AQL:ExpandAllQuestLogHeaders()
```
Expected: entry count printed, zone names listed, all headers collapse then expand, verbose count messages appear.

- [ ] **Step 3: Commit**

```bash
git add "AbsoluteQuestLog.lua"
git commit -m "feat: add GetQuestLogEntries, GetQuestLogZoneNames, ExpandAll, CollapseAll"
```

---

### Task 6: Zone-by-name methods and IsQuestLogZoneCollapsed

**Files:**
- Modify: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Add a local helper for zone-header lookup**

Add immediately before the zone-by-name methods (not a public AQL method — a file-local helper):

```lua
-- Local helper: finds the logIndex of a zone header by name.
-- Returns logIndex, isCollapsed  — or nil, nil if not found.
local function findZoneHeader(zoneName)
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, isCollapsed = WowQuestAPI.GetQuestLogTitle(i)
        if title and isHeader and title == zoneName then
            return i, isCollapsed == true
        end
    end
    return nil, nil
end
```

- [ ] **Step 2: Add zone-by-name methods**

```lua
-- ExpandQuestLogZoneByName(zoneName)
-- Finds the zone header matching zoneName and expands it.
-- No-op with a normal-level debug message if zoneName is not found.
function AQL:ExpandQuestLogZoneByName(zoneName)
    local logIndex = findZoneHeader(zoneName)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ExpandQuestLogZoneByName: zone \"" .. tostring(zoneName) .. "\" not found in quest log — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.ExpandQuestHeader(logIndex)
end

-- CollapseQuestLogZoneByName(zoneName)
-- Finds the zone header matching zoneName and collapses it.
-- No-op with a normal-level debug message if zoneName is not found.
function AQL:CollapseQuestLogZoneByName(zoneName)
    local logIndex = findZoneHeader(zoneName)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] CollapseQuestLogZoneByName: zone \"" .. tostring(zoneName) .. "\" not found in quest log — no-op" .. self.RESET)
        end
        return
    end
    WowQuestAPI.CollapseQuestHeader(logIndex)
end

-- ToggleQuestLogZoneByName(zoneName)
-- Finds the zone header matching zoneName; expands if collapsed, collapses
-- if expanded.
-- No-op with a normal-level debug message if zoneName is not found.
function AQL:ToggleQuestLogZoneByName(zoneName)
    local logIndex, isCollapsed = findZoneHeader(zoneName)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ToggleQuestLogZoneByName: zone \"" .. tostring(zoneName) .. "\" not found in quest log — no-op" .. self.RESET)
        end
        return
    end
    if isCollapsed then
        WowQuestAPI.ExpandQuestHeader(logIndex)
    else
        WowQuestAPI.CollapseQuestHeader(logIndex)
    end
end

-- IsQuestLogZoneCollapsed(zoneName) → bool or nil
-- Returns true if the zone header matching zoneName is collapsed,
-- false if expanded, nil if not found.
-- Emits a normal-level debug message when zoneName is not found.
function AQL:IsQuestLogZoneCollapsed(zoneName)
    local logIndex, isCollapsed = findZoneHeader(zoneName)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] IsQuestLogZoneCollapsed: zone \"" .. tostring(zoneName) .. "\" not found in quest log — returning nil" .. self.RESET)
        end
        return nil
    end
    return isCollapsed
end
```

- [ ] **Step 3: Verify in-game**

Replace `"Durotar"` with an actual zone name from your quest log:
```
/reload
/aql debug verbose
/run AQL:CollapseQuestLogZoneByName("Durotar")
/run print(AQL:IsQuestLogZoneCollapsed("Durotar"))
/run AQL:ToggleQuestLogZoneByName("Durotar")
/run print(AQL:IsQuestLogZoneCollapsed("Durotar"))
/run AQL:ExpandQuestLogZoneByName("FakeZone")
```
Expected: zone collapses, `true` printed, zone expands, `false` printed, "not found" normal-level message for FakeZone.

- [ ] **Step 4: Commit**

```bash
git add "AbsoluteQuestLog.lua"
git commit -m "feat: add zone-by-name methods and IsQuestLogZoneCollapsed"
```

---

## Chunk 5: Compound ById + Player & Level + CLAUDE.md

### Task 7: Compound ById methods

**Files:**
- Modify: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Add ById section**

Append after the ByIndex methods:

```lua
------------------------------------------------------------------------
-- Quest Log APIs — Compound ById
-- Same operations as ByIndex but accept questID. Internally resolve
-- questID → logIndex via WowQuestAPI.GetQuestLogIndex.
-- If the questID is not in the player's active quest log (including quests
-- under collapsed headers), all ById methods are silent no-ops:
-- bool methods return false, void methods do nothing.
-- A normal-level debug message is emitted so consumers can observe this.
------------------------------------------------------------------------

-- IsQuestIdShareable(questID) → bool
-- Returns true if the quest with questID can be shared with party members.
-- Returns false with a normal-level debug message if questID is not in
-- the active quest log.
function AQL:IsQuestIdShareable(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] IsQuestIdShareable: questID=" .. tostring(questID) .. " not in quest log — returning false" .. self.RESET)
        end
        return false
    end
    return self:IsQuestIndexShareable(logIndex)
end

-- SelectAndShowQuestLogEntryById(questID)
-- Selects questID in the quest log and refreshes the display.
-- No-op with a normal-level debug message if questID is not in the log.
function AQL:SelectAndShowQuestLogEntryById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] SelectAndShowQuestLogEntryById: questID=" .. tostring(questID) .. " not in quest log — no-op" .. self.RESET)
        end
        return
    end
    self:SelectAndShowQuestLogEntryByIndex(logIndex)
end

-- OpenQuestLogById(questID)
-- Opens the quest log and navigates to questID.
-- No-op with a normal-level debug message if questID is not in the log.
function AQL:OpenQuestLogById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] OpenQuestLogById: questID=" .. tostring(questID) .. " not in quest log — no-op" .. self.RESET)
        end
        return
    end
    self:OpenQuestLogByIndex(logIndex)
end

-- ToggleQuestLogById(questID)
-- Toggles the quest log open/closed for questID.
-- No-op with a normal-level debug message if questID is not in the log.
function AQL:ToggleQuestLogById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] ToggleQuestLogById: questID=" .. tostring(questID) .. " not in quest log — no-op" .. self.RESET)
        end
        return
    end
    self:ToggleQuestLogByIndex(logIndex)
end
```

- [ ] **Step 2: Verify in-game**

Replace `12345` with a real questID from your log, `99999` with one that is not:
```
/reload
/aql debug verbose
/run AQL:OpenQuestLogById(12345)
/run AQL:OpenQuestLogById(99999)
/run print(AQL:IsQuestIdShareable(12345))
/run AQL:ToggleQuestLogById(12345)
/run AQL:ToggleQuestLogById(12345)
```
Expected: log opens to quest 12345, no-op message for 99999, bool for shareability, log toggles closed then open.

- [ ] **Step 3: Commit**

```bash
git add "AbsoluteQuestLog.lua"
git commit -m "feat: add Group 2 compound ById methods"
```

---

### Task 8: Group 1 — Player & Level section

Add the Player & Level sub-section to Group 1. Insert immediately before the `-- GROUP 2: QUEST LOG APIS` banner.

**Files:**
- Modify: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Add Player & Level methods**

```lua
------------------------------------------------------------------------
-- Player & Level
-- Filters the active quest cache by quest level (questInfo.level —
-- the recommended difficulty level, not requiredLevel).
-- Absolute-level methods use strict comparisons: < and >.
-- BetweenLevels is inclusive on both endpoints.
-- Delta methods delegate to the absolute methods; delta should be a
-- non-negative integer (negative values produce valid but counter-intuitive
-- results — see individual method notes).
-- All methods return {} (never nil) when no quests match.
-- No debug messages — pure data queries.
------------------------------------------------------------------------

-- GetPlayerLevel() → number
-- Returns the player's current character level.
function AQL:GetPlayerLevel()
    return WowQuestAPI.GetPlayerLevel()
end

-- GetQuestsInQuestLogBelowLevel(level) → {[questID]=QuestInfo}
-- Returns all active quests where questInfo.level < level.
function AQL:GetQuestsInQuestLogBelowLevel(level)
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.level and info.level < level then
            result[questID] = info
        end
    end
    return result
end

-- GetQuestsInQuestLogAboveLevel(level) → {[questID]=QuestInfo}
-- Returns all active quests where questInfo.level > level.
function AQL:GetQuestsInQuestLogAboveLevel(level)
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.level and info.level > level then
            result[questID] = info
        end
    end
    return result
end

-- GetQuestsInQuestLogBetweenLevels(minLevel, maxLevel) → {[questID]=QuestInfo}
-- Returns all active quests where minLevel <= questInfo.level <= maxLevel.
-- Returns {} if minLevel > maxLevel.
function AQL:GetQuestsInQuestLogBetweenLevels(minLevel, maxLevel)
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.level and info.level >= minLevel and info.level <= maxLevel then
            result[questID] = info
        end
    end
    return result
end

-- GetQuestsInQuestLogBelowLevelDelta(delta) → {[questID]=QuestInfo}
-- Returns quests more than delta levels below the player.
-- e.g. delta=5 at player level 40 → quests strictly below level 35.
-- Delegates to GetQuestsInQuestLogBelowLevel(playerLevel - delta).
function AQL:GetQuestsInQuestLogBelowLevelDelta(delta)
    return self:GetQuestsInQuestLogBelowLevel(WowQuestAPI.GetPlayerLevel() - delta)
end

-- GetQuestsInQuestLogAboveLevelDelta(delta) → {[questID]=QuestInfo}
-- Returns quests more than delta levels above the player.
-- e.g. delta=5 at player level 40 → quests strictly above level 45.
-- Delegates to GetQuestsInQuestLogAboveLevel(playerLevel + delta).
function AQL:GetQuestsInQuestLogAboveLevelDelta(delta)
    return self:GetQuestsInQuestLogAboveLevel(WowQuestAPI.GetPlayerLevel() + delta)
end

-- GetQuestsInQuestLogWithinLevelRange(delta) → {[questID]=QuestInfo}
-- Returns quests within ±delta levels of the player's current level
-- (inclusive endpoints — the "currently worth doing" set).
-- e.g. delta=3 at player level 40 → quests between levels 37 and 43.
-- Delegates to GetQuestsInQuestLogBetweenLevels(playerLevel - delta, playerLevel + delta).
function AQL:GetQuestsInQuestLogWithinLevelRange(delta)
    local playerLevel = WowQuestAPI.GetPlayerLevel()
    return self:GetQuestsInQuestLogBetweenLevels(playerLevel - delta, playerLevel + delta)
end
```

- [ ] **Step 2: Verify in-game**

```
/reload
/run print(AQL:GetPlayerLevel())
/run local q = AQL:GetQuestsInQuestLogWithinLevelRange(5) local c=0 for _ in pairs(q) do c=c+1 end print(c, "quests within 5 levels")
/run local q = AQL:GetQuestsInQuestLogBelowLevelDelta(10) local c=0 for _ in pairs(q) do c=c+1 end print(c, "trivial quests")
```
Expected: player level printed, counts printed.

- [ ] **Step 3: Commit**

```bash
git add "AbsoluteQuestLog.lua"
git commit -m "feat: add Group 1 Player & Level section with level-range filtering methods"
```

---

### Task 9: Update CLAUDE.md and bump version

**Files:**
- Modify: `CLAUDE.md`
- Modify: `AbsoluteQuestLog.toc`

- [ ] **Step 1: Update the Public API section in CLAUDE.md**

Replace the existing Public API section (from `## Public API` through the end of `### Callbacks`) with the following two-group structure. Keep the Callbacks section unchanged.

```markdown
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
| `AQL:GetQuestLogZoneNames()` | array of strings | Ordered zone header names |
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
```

- [ ] **Step 2: Bump version in `AbsoluteQuestLog.toc`**

Current version is `2.1.1`. This is the first modification today → bump minor, reset revision: `2.2.0`.

Change:
```
## Version: 2.1.1
```
to:
```
## Version: 2.2.0
```

- [ ] **Step 3: Add version entry to CLAUDE.md Version History**

Add at the top of Version History:
```markdown
### Version 2.2.0 (March 2026)
- Added Quest Log Frame & Navigation wrappers to `WowQuestAPI.lua` (`GetNumQuestLogEntries`, `GetQuestLogTitle`, `GetQuestLogSelection`, `SelectQuestLogEntry`, `GetQuestLogPushable`, `QuestLog_SetSelection`, `QuestLog_Update`, `ExpandQuestHeader`, `CollapseQuestHeader`, `ShowQuestLog`, `HideQuestLog`, `IsQuestLogShown`, `GetQuestDifficultyColor`, `GetPlayerLevel`)
- Added Group 2 Quest Log APIs to AQL public interface: 11 thin wrappers, 13 compound ByIndex methods, 4 compound ById methods
- Added Group 1 Player & Level section: `GetPlayerLevel` + 6 level-range filtering methods
- Reorganized `AbsoluteQuestLog.lua` public API into two-group structure (Quest APIs / Quest Log APIs) with subsections
```

- [ ] **Step 4: Final in-game smoke test**

```
/reload
/aql debug verbose
/run print(AQL:GetPlayerLevel())
/run print(AQL:IsQuestLogShown())
/run AQL:ShowQuestLog()
/run local e = AQL:GetQuestLogEntries() print(#e)
/run AQL:CollapseAllQuestLogHeaders()
/run AQL:ExpandAllQuestLogHeaders()
/run local q = AQL:GetQuestsInQuestLogWithinLevelRange(5) local c=0 for _ in pairs(q) do c=c+1 end print(c)
```
Confirm no Lua errors in the chat frame at any point.

- [ ] **Step 5: Commit**

```bash
git add "CLAUDE.md" "AbsoluteQuestLog.toc"
git commit -m "docs: update CLAUDE.md public API table and bump version to 2.2.0"
```
