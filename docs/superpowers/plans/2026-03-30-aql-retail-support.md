# AQL 2.5.5 Retail Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AQL fully functional on Retail (Interface 120001) by adding IS_RETAIL branches to WowQuestAPI.lua, updating QuestCache.lua to use the new normalization wrapper, and delegating GetSelectedQuestLogEntryId to the new WowQuestAPI wrapper.

**Architecture:** All version-specific branching lives in `Core/WowQuestAPI.lua` — the existing rule. Consumer files (`QuestCache.lua`, `AbsoluteQuestLog.lua`) gain no IS_RETAIL checks of their own; they call WowQuestAPI wrappers that handle branching internally. Classic Era, TBC, and MoP behavior is completely unchanged.

**Tech Stack:** Lua 5.1 (WoW scripting environment), WoW C_QuestLog and WorldMapFrame Retail APIs, LibStub. No automated test framework — verification is by code inspection (grep) plus runtime smoke testing on Retail.

---

## Design Reference

Spec: `docs/superpowers/specs/2026-03-29-aql-retail-support-design.md`

---

## File Map

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | New `GetQuestLogInfo` wrapper; new `GetSelectedQuestLogEntryId` wrapper; IS_RETAIL branches on existing functions: GetQuestsCompleted, TrackQuest, UntrackQuest, IsQuestWatchedByIndex, IsQuestWatchedById, GetQuestLinkById, ShowQuestLog, HideQuestLog, IsQuestLogShown, QuestLog_SetSelection, SelectQuestLogEntry, QuestLog_Update, GetQuestLogPushable; nil-guards on GetMaxWatchableQuests and GetWatchedQuestCount |
| `Core/QuestCache.lua` | Phase 3 of `Rebuild()` switches from positional `GetQuestLogTitle` to table-returning `GetQuestLogInfo` |
| `AbsoluteQuestLog.lua` | `GetSelectedQuestLogEntryId` body replaced with single delegation to `WowQuestAPI.GetSelectedQuestLogEntryId()` |
| `AbsoluteQuestLog.toc` + four version tocs | Version bump 2.5.4 → 2.5.5 |
| `changelog.txt` | Add 2.5.5 entry |
| `CLAUDE.md` | Add Version 2.5.5 entry |

---

## Important Constraints

**Phases 1 and 4 of QuestCache:Rebuild() — intentionally NOT migrated:** These phases call `WowQuestAPI.GetQuestLogTitle`. Do not change them. The `GetQuestLogTitle` global still exists on Retail as a deprecated Blizzard compatibility shim, and these phases only need `isHeader` and `isCollapsed`.

**ExpandQuestHeader / CollapseQuestHeader — no changes needed:** `ExpandQuestHeader(logIndex)` and `CollapseQuestHeader(logIndex)` exist unchanged on Retail. No IS_RETAIL branch is needed for these wrappers.

---

## Task 1: WowQuestAPI — GetQuestLogInfo normalization wrapper

**Files:**
- Modify: `Core/WowQuestAPI.lua`

This is the prerequisite for Tasks 3, 5, 8, and 9. `GetQuestLogInfo(logIndex)` normalizes positional returns from `GetQuestLogTitle` (Classic/TBC/MoP) and the table returned by `C_QuestLog.GetInfo` (Retail) into a single consistent table shape.

Add the function after the `GetQuestLogTitle` wrapper block (between `GetQuestLogTitle` and `GetQuestLogSelection`).

- [ ] **Step 1: Insert GetQuestLogInfo after GetQuestLogTitle**

Find this exact block in `Core/WowQuestAPI.lua`:
```lua
-- GetQuestLogTitle(logIndex) → title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
-- Returns all fields for the entry at the given visible logIndex.
-- Header rows: title = zone name, isHeader = true, questID = nil.
-- Quest rows:  isHeader = false, questID = the quest's numeric ID.
function WowQuestAPI.GetQuestLogTitle(logIndex)
    return GetQuestLogTitle(logIndex)
end

-- GetQuestLogSelection() → logIndex
```

Replace with:
```lua
-- GetQuestLogTitle(logIndex) → title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
-- Returns all fields for the entry at the given visible logIndex.
-- Header rows: title = zone name, isHeader = true, questID = nil.
-- Quest rows:  isHeader = false, questID = the quest's numeric ID.
function WowQuestAPI.GetQuestLogTitle(logIndex)
    return GetQuestLogTitle(logIndex)
end

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestLogInfo(logIndex)
-- Normalized wrapper for per-entry quest log data. Consistent table on
-- all version families.
-- Returns: { title, level, suggestedGroup, isHeader, isCollapsed, isComplete, questID }
-- On Classic/TBC/MoP: reads positional returns from GetQuestLogTitle(logIndex).
-- On Retail: reads fields from C_QuestLog.GetInfo(logIndex).
-- Returns nil if logIndex is out of range or the entry does not exist.
------------------------------------------------------------------------
function WowQuestAPI.GetQuestLogInfo(logIndex)
    if IS_RETAIL then
        local info = C_QuestLog.GetInfo(logIndex)
        if not info then return nil end
        return {
            title          = info.title,
            level          = info.level,
            suggestedGroup = info.suggestedGroup,
            isHeader       = info.isHeader,
            isCollapsed    = info.isCollapsed,
            isComplete     = info.isComplete,
            questID        = info.questID,
        }
    else
        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, _, questID =
            GetQuestLogTitle(logIndex)
        if not title then return nil end
        return {
            title          = title,
            level          = level,
            suggestedGroup = suggestedGroup,
            isHeader       = isHeader,
            isCollapsed    = isCollapsed,
            isComplete     = isComplete,
            questID        = questID,
        }
    end
end

-- GetQuestLogSelection() → logIndex
```

- [ ] **Step 2: Verify**

```bash
grep -n "GetQuestLogInfo" "Core/WowQuestAPI.lua"
```
Expected: at least 2 lines — the comment header and the function declaration.

- [ ] **Step 3: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: add WowQuestAPI.GetQuestLogInfo normalization wrapper"
```

---

## Task 2: WowQuestAPI — GetQuestsCompleted Retail branch

**Files:**
- Modify: `Core/WowQuestAPI.lua`

The current implementation has a placeholder `if IS_RETAIL then return nil end`. Replace it with the real Retail path: convert `C_QuestLog.GetAllCompletedQuestIDs()` (sequential array) into `{[questID]=true}` (associative hash map) for O(1) lookup by HistoryCache. Also remove the stale "sub-project" note from the doc comment.

- [ ] **Step 1: Replace GetQuestsCompleted**

Find:
```lua
------------------------------------------------------------------------
-- WowQuestAPI.GetQuestsCompleted()
-- Returns the associative table {[questID]=true} of all quests completed
-- by this character. Same return shape on Classic Era, TBC, and MoP.
-- Note: Retail uses C_QuestLog.GetAllCompletedQuestIDs() which returns a
-- sequential array — IS_RETAIL branch will be added in the Retail sub-project.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestsCompleted()
    if IS_RETAIL then return nil end  -- C_QuestLog.GetAllCompletedQuestIDs() will be added in the Retail sub-project
    return GetQuestsCompleted()
end
```

Replace with:
```lua
------------------------------------------------------------------------
-- WowQuestAPI.GetQuestsCompleted()
-- Returns the associative table {[questID]=true} of all quests completed
-- by this character. Same return shape on all versions.
-- On Retail: converts C_QuestLog.GetAllCompletedQuestIDs() sequential array
-- to an associative hash map for O(1) lookup.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestsCompleted()
    if IS_RETAIL then
        local ids = C_QuestLog.GetAllCompletedQuestIDs()
        if not ids then return nil end
        local result = {}
        for _, questID in ipairs(ids) do
            result[questID] = true
        end
        return result
    end
    return GetQuestsCompleted()
end
```

- [ ] **Step 2: Verify**

```bash
grep -n "GetAllCompletedQuestIDs" "Core/WowQuestAPI.lua"
```
Expected: 1 match.

```bash
grep -n "sub-project" "Core/WowQuestAPI.lua"
```
Expected: this entry's old note is gone. (Other "sub-project" notes are handled in their own tasks.)

- [ ] **Step 3: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: implement WowQuestAPI.GetQuestsCompleted Retail branch"
```

---

## Task 3: WowQuestAPI — Quest tracking Retail branches

**Files:**
- Modify: `Core/WowQuestAPI.lua`

**Prerequisite:** Task 1 must be complete.

Four tracking functions get Retail branches:
- `TrackQuest`: `AddQuestWatch(logIndex)` → `C_QuestLog.AddQuestWatch(questID)`
- `UntrackQuest`: `RemoveQuestWatch(logIndex)` → `C_QuestLog.RemoveQuestWatch(questID)`
- `IsQuestWatchedById`: direct `C_QuestLog.IsQuestWatched(questID)` on Retail (no logIndex needed)
- `IsQuestWatchedByIndex`: resolves logIndex → questID via `GetQuestLogInfo`, then calls `C_QuestLog.IsQuestWatched(questID)`

Also remove the stale "sub-project" note from the `IsQuestWatchedByIndex`/`IsQuestWatchedById` doc comment.

- [ ] **Step 1: Replace TrackQuest**

Find:
```lua
function WowQuestAPI.TrackQuest(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if logIndex then
        AddQuestWatch(logIndex)
    end
end
```

Replace with:
```lua
function WowQuestAPI.TrackQuest(questID)
    if IS_RETAIL then
        C_QuestLog.AddQuestWatch(questID)
    else
        local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
        if logIndex then AddQuestWatch(logIndex) end
    end
end
```

- [ ] **Step 2: Replace UntrackQuest**

Find:
```lua
function WowQuestAPI.UntrackQuest(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if logIndex then
        RemoveQuestWatch(logIndex)
    end
end
```

Replace with:
```lua
function WowQuestAPI.UntrackQuest(questID)
    if IS_RETAIL then
        C_QuestLog.RemoveQuestWatch(questID)
    else
        local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
        if logIndex then RemoveQuestWatch(logIndex) end
    end
end
```

- [ ] **Step 3: Replace IsQuestWatchedByIndex and IsQuestWatchedById**

Find:
```lua
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

Replace with:
```lua
-- On Retail: ByIndex resolves logIndex → questID via GetQuestLogInfo, then calls
-- C_QuestLog.IsQuestWatched(questID). Returns false if logIndex has no entry.
-- ById calls C_QuestLog.IsQuestWatched(questID) directly.
------------------------------------------------------------------------

function WowQuestAPI.IsQuestWatchedByIndex(logIndex)
    if IS_RETAIL then
        local info = WowQuestAPI.GetQuestLogInfo(logIndex)
        if not info or not info.questID then return false end
        return C_QuestLog.IsQuestWatched(info.questID) and true or false
    end
    return IsQuestWatched(logIndex) and true or false
end

function WowQuestAPI.IsQuestWatchedById(questID)
    if IS_RETAIL then
        return C_QuestLog.IsQuestWatched(questID) and true or false
    end
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    return IsQuestWatched(logIndex) and true or false
end
```

- [ ] **Step 4: Verify**

```bash
grep -n "C_QuestLog.AddQuestWatch\|C_QuestLog.RemoveQuestWatch\|C_QuestLog.IsQuestWatched" "Core/WowQuestAPI.lua"
```
Expected: 4 matches total.

- [ ] **Step 5: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: add Retail branches for TrackQuest, UntrackQuest, IsQuestWatched wrappers"
```

---

## Task 4: WowQuestAPI — Watchable quest nil-guards

**Files:**
- Modify: `Core/WowQuestAPI.lua`

Two defensive changes for Retail where globals may be absent:
- `GetMaxWatchableQuests`: adds `or 25` fallback if `MAX_WATCHABLE_QUESTS` constant is nil
- `GetWatchedQuestCount`: guards against `GetNumQuestWatches` global being absent; returns 0 as safe degradation (TrackQuest will always see count 0 and never block on the cap — acceptable)

- [ ] **Step 1: Add fallback to GetMaxWatchableQuests**

Find:
```lua
function WowQuestAPI.GetMaxWatchableQuests()
    return MAX_WATCHABLE_QUESTS
end
```

Replace with:
```lua
function WowQuestAPI.GetMaxWatchableQuests()
    return MAX_WATCHABLE_QUESTS or 25
end
```

- [ ] **Step 2: Add nil-guard to GetWatchedQuestCount**

Find:
```lua
function WowQuestAPI.GetWatchedQuestCount()
    return GetNumQuestWatches()
end
```

Replace with:
```lua
function WowQuestAPI.GetWatchedQuestCount()
    if GetNumQuestWatches then return GetNumQuestWatches() end
    return 0
end
```

- [ ] **Step 3: Verify**

```bash
grep -n "or 25\|if GetNumQuestWatches" "Core/WowQuestAPI.lua"
```
Expected: 2 matches.

- [ ] **Step 4: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: add Retail nil-guards for MAX_WATCHABLE_QUESTS and GetNumQuestWatches"
```

---

## Task 5: WowQuestAPI — GetSelectedQuestLogEntryId new wrapper

**Files:**
- Modify: `Core/WowQuestAPI.lua`

**Prerequisite:** Task 1 must be complete.

New function added to WowQuestAPI. On Retail, `C_QuestLog.GetSelectedQuest()` returns questID directly — no logIndex resolution needed. On Classic/TBC/MoP, resolves via `GetQuestLogSelection()` → `GetQuestLogInfo()`.

Insert after `GetQuestLogSelection` and before `SelectQuestLogEntry`.

- [ ] **Step 1: Insert GetSelectedQuestLogEntryId**

Find:
```lua
-- GetQuestLogSelection() → logIndex
-- Returns the currently selected quest log entry index, or 0 if none selected.
function WowQuestAPI.GetQuestLogSelection()
    return GetQuestLogSelection()
end

-- SelectQuestLogEntry(logIndex)
```

Replace with:
```lua
-- GetQuestLogSelection() → logIndex
-- Returns the currently selected quest log entry index, or 0 if none selected.
function WowQuestAPI.GetQuestLogSelection()
    return GetQuestLogSelection()
end

-- WowQuestAPI.GetSelectedQuestLogEntryId() → questID or nil
-- Returns the questID of the currently selected quest log entry.
-- On Retail: C_QuestLog.GetSelectedQuest() returns questID directly.
-- On Classic/TBC/MoP: resolves via GetQuestLogSelection() → GetQuestLogInfo().
-- Returns nil if nothing is selected or if the selected entry is a zone header.
function WowQuestAPI.GetSelectedQuestLogEntryId()
    if IS_RETAIL then
        local questID = C_QuestLog.GetSelectedQuest()
        return (questID and questID ~= 0) and questID or nil
    end
    local logIndex = WowQuestAPI.GetQuestLogSelection()
    if not logIndex or logIndex == 0 then return nil end
    local info = WowQuestAPI.GetQuestLogInfo(logIndex)
    if not info or info.isHeader or not info.questID then return nil end
    return info.questID
end

-- SelectQuestLogEntry(logIndex)
```

- [ ] **Step 2: Verify**

```bash
grep -n "WowQuestAPI.GetSelectedQuestLogEntryId\|C_QuestLog.GetSelectedQuest" "Core/WowQuestAPI.lua"
```
Expected: 2 matches.

- [ ] **Step 3: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: add WowQuestAPI.GetSelectedQuestLogEntryId wrapper with Retail support"
```

---

## Task 6: WowQuestAPI — GetQuestLinkById Retail branch

**Files:**
- Modify: `Core/WowQuestAPI.lua`

On Retail, `C_QuestLog.GetQuestLink(questID)` replaces the legacy `GetQuestLink(logIndex)` approach. Also removes the stale "sub-project" note from the doc comment.

- [ ] **Step 1: Replace GetQuestLinkById**

Find:
```lua
-- GetQuestLinkById(questID) → hyperlink string or nil
-- Resolves questID → logIndex, then returns the hyperlink.
-- Returns nil if the quest is not in the player's log.
-- Note: Retail equivalent will be added in the Retail sub-project.
function WowQuestAPI.GetQuestLinkById(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    return GetQuestLink(logIndex)
end
```

Replace with:
```lua
-- GetQuestLinkById(questID) → hyperlink string or nil
-- On Retail: calls C_QuestLog.GetQuestLink(questID) directly.
-- On Classic/TBC/MoP: resolves questID → logIndex, then calls GetQuestLink(logIndex).
-- Returns nil if the quest link is unavailable.
function WowQuestAPI.GetQuestLinkById(questID)
    if IS_RETAIL then
        return C_QuestLog.GetQuestLink(questID)
    end
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    return GetQuestLink(logIndex)
end
```

- [ ] **Step 2: Verify**

```bash
grep -n "C_QuestLog.GetQuestLink" "Core/WowQuestAPI.lua"
```
Expected: 1 match.

- [ ] **Step 3: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: add Retail branch for WowQuestAPI.GetQuestLinkById"
```

---

## Task 7: WowQuestAPI — Frame show/hide/isShown Retail branches

**Files:**
- Modify: `Core/WowQuestAPI.lua`

`QuestLogFrame` was removed in WoW 6.0.2. On Retail, all three frame visibility methods redirect to `WorldMapFrame`.

- [ ] **Step 1: Replace ShowQuestLog**

Find:
```lua
-- ShowQuestLog()
-- Opens the quest log frame via ShowUIPanel(QuestLogFrame).
function WowQuestAPI.ShowQuestLog()
    ShowUIPanel(QuestLogFrame)
end
```

Replace with:
```lua
-- ShowQuestLog()
-- Opens the quest log (Retail: WorldMapFrame; Classic/TBC/MoP: QuestLogFrame).
function WowQuestAPI.ShowQuestLog()
    if IS_RETAIL then WorldMapFrame:Show() else ShowUIPanel(QuestLogFrame) end
end
```

- [ ] **Step 2: Replace HideQuestLog**

Find:
```lua
-- HideQuestLog()
-- Closes the quest log frame via HideUIPanel(QuestLogFrame).
function WowQuestAPI.HideQuestLog()
    HideUIPanel(QuestLogFrame)
end
```

Replace with:
```lua
-- HideQuestLog()
-- Closes the quest log (Retail: WorldMapFrame; Classic/TBC/MoP: QuestLogFrame).
function WowQuestAPI.HideQuestLog()
    if IS_RETAIL then WorldMapFrame:Hide() else HideUIPanel(QuestLogFrame) end
end
```

- [ ] **Step 3: Replace IsQuestLogShown**

Find:
```lua
-- IsQuestLogShown() → bool
-- Returns true if the quest log frame is currently visible.
function WowQuestAPI.IsQuestLogShown()
    return QuestLogFrame ~= nil and QuestLogFrame:IsShown() == true
end
```

Replace with:
```lua
-- IsQuestLogShown() → bool
-- Returns true if the quest log (or WorldMapFrame on Retail) is currently visible.
function WowQuestAPI.IsQuestLogShown()
    if IS_RETAIL then return WorldMapFrame:IsVisible() end
    return QuestLogFrame:IsVisible()
end
```

- [ ] **Step 4: Verify**

```bash
grep -n "WorldMapFrame" "Core/WowQuestAPI.lua"
```
Expected: 3 matches (Show, Hide, IsVisible).

- [ ] **Step 5: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: redirect ShowQuestLog/HideQuestLog/IsQuestLogShown to WorldMapFrame on Retail"
```

---

## Task 8: WowQuestAPI — Selection APIs Retail branches

**Files:**
- Modify: `Core/WowQuestAPI.lua`

**Prerequisites:** Task 1 (GetQuestLogInfo) and Task 5 (GetSelectedQuestLogEntryId) must be complete.

Four selection-related functions:
- `QuestLog_SetSelection`: resolves logIndex → questID via `GetQuestLogInfo`, calls `C_QuestLog.SetSelectedQuest(questID)` on Retail; the non-Retail path adds a paired `QuestLog_Update()` call (matches the doc comment's stated contract)
- `SelectQuestLogEntry`: same resolution, calls `C_QuestLog.SetSelectedQuest(questID)` on Retail; no `QuestLog_Update()` (this is the non-refreshing variant)
- `QuestLog_Update`: no-op on Retail (quest log auto-updates when selection changes)
- `GetQuestLogPushable`: resolves selected questID via `GetSelectedQuestLogEntryId`, calls `C_QuestLog.IsPushableQuest(questID)` on Retail

- [ ] **Step 1: Replace QuestLog_SetSelection**

Find:
```lua
-- QuestLog_SetSelection(logIndex)
-- Updates the UI selection highlight. Always paired with QuestLog_Update().
-- Use AQL:SetQuestLogSelection() for the canonical two-call sequence.
function WowQuestAPI.QuestLog_SetSelection(logIndex)
    QuestLog_SetSelection(logIndex)
end
```

Replace with:
```lua
-- QuestLog_SetSelection(logIndex)
-- Updates the UI selection highlight and refreshes the quest log display.
-- On Retail: resolves logIndex → questID via GetQuestLogInfo, calls
-- C_QuestLog.SetSelectedQuest(questID). QuestLog_Update() is not needed on Retail.
-- On Classic/TBC/MoP: calls QuestLog_SetSelection + QuestLog_Update (the required pair).
function WowQuestAPI.QuestLog_SetSelection(logIndex)
    if IS_RETAIL then
        local info = WowQuestAPI.GetQuestLogInfo(logIndex)
        if info and info.questID then
            C_QuestLog.SetSelectedQuest(info.questID)
        end
        return
    end
    QuestLog_SetSelection(logIndex)
    QuestLog_Update()
end
```

- [ ] **Step 2: Replace SelectQuestLogEntry**

Find:
```lua
-- SelectQuestLogEntry(logIndex)
-- Sets the selected entry without refreshing the quest log display.
function WowQuestAPI.SelectQuestLogEntry(logIndex)
    SelectQuestLogEntry(logIndex)
end
```

Replace with:
```lua
-- SelectQuestLogEntry(logIndex)
-- Sets the selected entry without refreshing the quest log display.
-- On Retail: resolves logIndex → questID via GetQuestLogInfo, calls
-- C_QuestLog.SetSelectedQuest(questID).
function WowQuestAPI.SelectQuestLogEntry(logIndex)
    if IS_RETAIL then
        local info = WowQuestAPI.GetQuestLogInfo(logIndex)
        if info and info.questID then
            C_QuestLog.SetSelectedQuest(info.questID)
        end
        return
    end
    SelectQuestLogEntry(logIndex)
end
```

- [ ] **Step 3: Replace QuestLog_Update**

Find:
```lua
-- QuestLog_Update()
-- Refreshes the quest log display. Always paired with QuestLog_SetSelection().
-- Use AQL:SetQuestLogSelection() for the canonical two-call sequence.
function WowQuestAPI.QuestLog_Update()
    QuestLog_Update()
end
```

Replace with:
```lua
-- QuestLog_Update()
-- Refreshes the quest log display on Classic/TBC/MoP.
-- No-op on Retail (the quest log auto-updates when selection changes).
function WowQuestAPI.QuestLog_Update()
    if IS_RETAIL then return end
    QuestLog_Update()
end
```

- [ ] **Step 4: Replace GetQuestLogPushable**

Find:
```lua
-- GetQuestLogPushable() → bool
-- Returns true if the currently selected quest can be shared with party members.
-- Only meaningful when the target quest is already selected.
function WowQuestAPI.GetQuestLogPushable()
    if GetQuestLogPushable() then return true end
    return false
end
```

Replace with:
```lua
-- GetQuestLogPushable() → bool
-- Returns true if the currently selected quest can be shared with party members.
-- On Retail: resolves the selected questID via GetSelectedQuestLogEntryId, calls
-- C_QuestLog.IsPushableQuest(questID).
-- On Classic/TBC/MoP: calls GetQuestLogPushable() which reads UI selection state.
function WowQuestAPI.GetQuestLogPushable()
    if IS_RETAIL then
        local questID = WowQuestAPI.GetSelectedQuestLogEntryId()
        if not questID then return false end
        return C_QuestLog.IsPushableQuest(questID) and true or false
    end
    return GetQuestLogPushable() and true or false
end
```

- [ ] **Step 5: Verify**

```bash
grep -n "C_QuestLog.SetSelectedQuest\|C_QuestLog.IsPushableQuest" "Core/WowQuestAPI.lua"
```
Expected: 3 matches for `SetSelectedQuest` (QuestLog_SetSelection + SelectQuestLogEntry), 1 for `IsPushableQuest`.

- [ ] **Step 6: Commit**

```bash
git add "Core/WowQuestAPI.lua"
git commit -m "feat: add Retail branches for QuestLog_SetSelection, SelectQuestLogEntry, QuestLog_Update, GetQuestLogPushable"
```

---

## Task 9: QuestCache — Phase 3 switch to GetQuestLogInfo

**Files:**
- Modify: `Core/QuestCache.lua`

**Prerequisite:** Task 1 (GetQuestLogInfo) must be complete.

Phase 3 of `QuestCache:Rebuild()` currently calls `WowQuestAPI.GetQuestLogTitle` and unpacks positional return values into a local `info` table. Replace with `WowQuestAPI.GetQuestLogInfo(i)` which returns the same-shaped table on all versions.

**Key behavior difference:** The original code used `if title then` as a loop termination guard (nil title = end-of-log). The new code uses `if info then` as a skip guard (nil = malformed entry, not end-of-log). Loop termination is controlled by the existing `for i = 1, numEntries` bound — do not change the loop structure.

**Do NOT touch Phases 1 or 4** — they still call `WowQuestAPI.GetQuestLogTitle` intentionally (see constraint note at top of plan).

- [ ] **Step 1: Replace Phase 3 body in QuestCache:Rebuild()**

Find this exact block in `Core/QuestCache.lua` (it is the Phase 3 inner loop body):
```lua
    numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        -- TBC 20505: C_QuestLog.GetInfo() does not exist; use GetQuestLogTitle() global.
        -- Returns: title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
        --          frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI,
        --          isTask, isBounty, isStory, isHidden, isScaling
        local title, level, suggestedGroup, isHeader, _, isComplete, _, questID =
            WowQuestAPI.GetQuestLogTitle(i)
        if title then
            local info = {
                title          = title,
                level          = level,
                suggestedGroup = suggestedGroup,  -- nil-safe: _buildEntry applies or 0 fallback
                isHeader       = isHeader,
                isComplete     = isComplete,
                questID        = questID,
            }
            if info.isHeader then
                currentZone = info.title
            else
                -- Wrap each entry build in pcall so one bad entry never aborts the loop.
                local ok, entryOrErr = pcall(self._buildEntry, self, questID, info, currentZone, i)
                if ok and entryOrErr then
                    new[questID] = entryOrErr
                elseif not ok and AQL.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(AQL.RED .. "[AQL] QuestCache: error building entry for questID "
                        .. tostring(questID) .. ": " .. tostring(entryOrErr) .. AQL.RESET)
                end
            end
        end
    end
```

Replace with:
```lua
    numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        -- GetQuestLogInfo normalizes Classic/TBC/MoP positional returns and Retail
        -- C_QuestLog.GetInfo() table into a single consistent table.
        -- Returns nil for a malformed/out-of-range entry — skip (do not break).
        -- Loop termination is controlled by the numEntries bound above.
        local info = WowQuestAPI.GetQuestLogInfo(i)
        if not info then
            -- skip this entry; do not break — a nil mid-log entry should not
            -- cut off all subsequent quests from the cache rebuild
        else
            local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, questID =
                info.title, info.level, info.suggestedGroup, info.isHeader,
                info.isCollapsed, info.isComplete, info.questID
            if info.isHeader then
                currentZone = info.title
            else
                -- Wrap each entry build in pcall so one bad entry never aborts the loop.
                local ok, entryOrErr = pcall(self._buildEntry, self, questID, info, currentZone, i)
                if ok and entryOrErr then
                    new[questID] = entryOrErr
                elseif not ok and AQL.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(AQL.RED .. "[AQL] QuestCache: error building entry for questID "
                        .. tostring(questID) .. ": " .. tostring(entryOrErr) .. AQL.RESET)
                end
            end
        end
    end
```

- [ ] **Step 2: Verify Phase 3 uses GetQuestLogInfo**

```bash
grep -n "GetQuestLogInfo\|GetQuestLogTitle" "Core/QuestCache.lua"
```
Expected: `GetQuestLogInfo` appears once (Phase 3); `GetQuestLogTitle` appears twice (Phase 1 ~line 30 and Phase 4 ~line 101) — do NOT remove these.

- [ ] **Step 3: Commit**

```bash
git add "Core/QuestCache.lua"
git commit -m "feat: QuestCache Phase 3 switches from GetQuestLogTitle to GetQuestLogInfo for Retail support"
```

---

## Task 10: AbsoluteQuestLog — GetSelectedQuestLogEntryId delegation

**Files:**
- Modify: `AbsoluteQuestLog.lua`

**Prerequisite:** Task 5 (WowQuestAPI.GetSelectedQuestLogEntryId) must be complete.

`AQL:GetSelectedQuestLogEntryId()` currently contains its own logIndex-resolution and debug-message logic. Replace the body with a single delegation. The separator block and doc comment above the function are preserved — only the function body changes. The debug messages are intentionally removed (they referenced logIndex which no longer applies on Retail; if debug output is needed for selection queries it belongs in WowQuestAPI).

- [ ] **Step 1: Replace the function body**

Find in `AbsoluteQuestLog.lua`:
```lua
function AQL:GetSelectedQuestLogEntryId()
    local logIndex = WowQuestAPI.GetQuestLogSelection()
    if not logIndex or logIndex == 0 then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestLogEntryId: no entry selected — returning nil" .. self.RESET)
        end
        return nil
    end
    local _, _, _, isHeader, _, _, _, questID = WowQuestAPI.GetQuestLogTitle(logIndex)
    if isHeader or not questID then
        if self.debug then
            DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestLogEntryId: selected entry logIndex=" .. tostring(logIndex) .. " is a zone header — returning nil" .. self.RESET)
        end
        return nil
    end
    return questID
end
```

Replace with:
```lua
function AQL:GetSelectedQuestLogEntryId()
    return WowQuestAPI.GetSelectedQuestLogEntryId()
end
```

- [ ] **Step 2: Verify the body is a single delegation**

```bash
grep -n -A 3 "function AQL:GetSelectedQuestLogEntryId" "AbsoluteQuestLog.lua"
```
Expected: function declaration, then `return WowQuestAPI.GetSelectedQuestLogEntryId()`, then `end`.

- [ ] **Step 3: Commit**

```bash
git add "AbsoluteQuestLog.lua"
git commit -m "refactor: AQL:GetSelectedQuestLogEntryId delegates to WowQuestAPI.GetSelectedQuestLogEntryId"
```

---

## Task 11: Version bump 2.5.4 → 2.5.5 and documentation

**Files:**
- Modify: `AbsoluteQuestLog.toc`
- Modify: `AbsoluteQuestLog_Classic.toc`
- Modify: `AbsoluteQuestLog_TBC.toc`
- Modify: `AbsoluteQuestLog_Mists.toc`
- Modify: `AbsoluteQuestLog_Mainline.toc`
- Modify: `changelog.txt`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump version in all 5 toc files**

In each of the five files below, find `## Version: 2.5.4` and replace with `## Version: 2.5.5`:
- `AbsoluteQuestLog.toc`
- `AbsoluteQuestLog_Classic.toc`
- `AbsoluteQuestLog_TBC.toc`
- `AbsoluteQuestLog_Mists.toc`
- `AbsoluteQuestLog_Mainline.toc`

- [ ] **Step 2: Prepend 2.5.5 entry to changelog.txt**

`changelog.txt` uses plain-text format with a `---` underline. Prepend the following block before the existing `Version 2.5.4` entry (preserve the file header `AbsoluteQuestLog-1.0 Changelog` and `======...` line):

```
Version 2.5.5 (March 2026)
---------------------------
- Retail support: AQL is now fully functional on Retail (Interface 120001). No behavioral changes on Classic Era, TBC, or MoP.
- New: WowQuestAPI.GetQuestLogInfo(logIndex) — normalization wrapper returning { title, level, suggestedGroup, isHeader, isCollapsed, isComplete, questID } from GetQuestLogTitle (Classic/TBC/MoP) or C_QuestLog.GetInfo (Retail).
- New: WowQuestAPI.GetSelectedQuestLogEntryId() — Retail uses C_QuestLog.GetSelectedQuest() directly; Classic/TBC/MoP resolve via logIndex → GetQuestLogInfo.
- Fix: GetQuestsCompleted() Retail branch converts C_QuestLog.GetAllCompletedQuestIDs() sequential array to {[questID]=true} hash map.
- Fix: TrackQuest/UntrackQuest call C_QuestLog.AddQuestWatch/RemoveQuestWatch(questID) on Retail.
- Fix: IsQuestWatchedByIndex/ById call C_QuestLog.IsQuestWatched on Retail.
- Fix: ShowQuestLog/HideQuestLog/IsQuestLogShown redirect to WorldMapFrame on Retail.
- Fix: QuestLog_SetSelection/SelectQuestLogEntry call C_QuestLog.SetSelectedQuest(questID) on Retail.
- Fix: GetQuestLogPushable calls C_QuestLog.IsPushableQuest(questID) on Retail.
- Fix: GetQuestLinkById calls C_QuestLog.GetQuestLink(questID) on Retail.
- Robustness: GetMaxWatchableQuests falls back to 25 if MAX_WATCHABLE_QUESTS is nil on Retail.
- Robustness: GetWatchedQuestCount returns 0 if GetNumQuestWatches global is absent on Retail.
- Refactor: AQL:GetSelectedQuestLogEntryId body replaced with single delegation to WowQuestAPI.GetSelectedQuestLogEntryId(). Debug messages removed.
- Refactor: QuestCache Phase 3 uses GetQuestLogInfo instead of GetQuestLogTitle. Skip-not-break on nil entries.

```

- [ ] **Step 3: Prepend 2.5.5 entry to CLAUDE.md Version History**

In `CLAUDE.md`, find the `## Version History` section. Add the following block immediately before the `### Version 2.5.4` heading:

```markdown
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

```

- [ ] **Step 4: Verify version bump across all toc files**

```bash
grep "Version: " AbsoluteQuestLog.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Mainline.toc
```
Expected: all five show `## Version: 2.5.5`.

- [ ] **Step 5: Commit**

```bash
git add AbsoluteQuestLog.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Mainline.toc changelog.txt CLAUDE.md
git commit -m "chore: bump version to 2.5.5, update changelog and CLAUDE.md"
```

---

## Runtime Smoke Test (Retail)

After all tasks are committed, load the addon on Retail (Interface 120001) and verify:

1. **Quest cache rebuilds without errors** — open `/aql debug on`, reload, confirm "QuestCache rebuilt: N quests" appears with N > 0.
2. **HasCompletedQuest returns true for a completed quest** — confirm a known-completed questID returns true.
3. **TrackQuest / UntrackQuest** — track a quest, confirm it appears on the watch list; untrack it, confirm it is removed.
4. **ShowQuestLog opens World Map** — `AQL:ShowQuestLog()` opens the World Map frame.
5. **OpenQuestLogById opens World Map to the correct quest** — `AQL:OpenQuestLogById(questID)` opens World Map and highlights the quest.
6. **GetSelectedQuestLogEntryId returns questID** — click a quest in the World Map quest log, call `AQL:GetSelectedQuestLogEntryId()`, confirm the correct questID is returned.
