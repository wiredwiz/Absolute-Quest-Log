# AQL WowQuestAPI Architectural Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every direct WoW global call outside `Core/WowQuestAPI.lua` with a wrapper call, and add the 10 missing wrapper functions to `WowQuestAPI.lua`.

**Architecture:** All version-specific WoW API branching lives in `Core/WowQuestAPI.lua`. Every other file calls through wrappers only. This sub-project is pure mechanical refactoring — zero behavioral changes. All new wrappers call the same underlying globals as the current direct calls; no IS_RETAIL branches are added here.

**Tech Stack:** Lua (WoW addon). No automated test framework — verification is by reading file content after each edit and running the success-criteria grep commands at the end.

---

## Background

### The rule
`Core/WowQuestAPI.lua` opens with: "No other AQL file should reference WoW quest globals directly." This sub-project enforces that rule everywhere it was missed.

### No behavioral changes
Every new wrapper is a transparent passthrough. `WowQuestAPI.GetQuestsCompleted()` calls `GetQuestsCompleted()`. `WowQuestAPI.IsQuestWatchedByIndex(logIndex)` calls `IsQuestWatched(logIndex) and true or false` — the boolean coercion that was already at the callsite moves into the wrapper. Nothing else changes.

### Line numbers shift as you edit
Work top-to-bottom within each file. After each Edit, read back the affected lines to confirm before continuing. Always match on content, not line numbers.

---

## Files Modified

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | Add 10 new wrapper functions in 4 groups |
| `Core/QuestCache.lua` | Replace 15 direct WoW calls |
| `Core/HistoryCache.lua` | Replace 1 direct WoW call |
| `Core/EventEngine.lua` | Replace 1 direct WoW call |
| `AbsoluteQuestLog.lua` | Replace 2 direct WoW calls |
| `Providers/QuestieProvider.lua` | Replace 1 direct WoW call |
| All 5 toc files | Version bump 2.5.2 → 2.5.3 |
| `CLAUDE.md` | Version entry + reinforce WowQuestAPI rule |
| `changelog.txt` | Add 2.5.3 entry |

---

## Task 1: WowQuestAPI.lua — Add 10 new wrappers

**Files:**
- Modify: `Core/WowQuestAPI.lua`

Add all new wrappers in four groups, working top-to-bottom. Commit once at the end.

---

- [ ] **Step 1: Read the insertion points**

  Read `Core/WowQuestAPI.lua` lines 94–170. Confirm:
  - Line 108: `end` closing the `IsQuestFlaggedCompleted` if/else block
  - Lines 110–123: `GetQuestLogIndex` block (starts with `--------`)
  - Lines 125–140: `TrackQuest` / `UntrackQuest` block
  - Lines 142–167: `IsUnitOnQuest` block

  Then read lines 165–230 to locate the Quest Log Frame section and find the `SelectQuestLogEntry` wrapper (the function that wraps the global `SelectQuestLogEntry(logIndex)`).

---

- [ ] **Step 2: Insert Group A — GetQuestsCompleted (after IsQuestFlaggedCompleted)**

  Find this exact line:
  ```lua
  end

  ------------------------------------------------------------------------
  -- WowQuestAPI.GetQuestLogIndex(questID)
  ```

  Replace with:
  ```lua
  end

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

  ------------------------------------------------------------------------
  -- WowQuestAPI.GetQuestLogIndex(questID)
  ```

- [ ] **Step 3: Verify Step 2**

  Read the area around the new `GetQuestsCompleted` block. Confirm:
  - The separator lines above and below are intact
  - The function body calls `GetQuestsCompleted()` directly
  - `GetQuestLogIndex` still follows immediately after

---

- [ ] **Step 4: Insert Group B — GetWatchedQuestCount, GetMaxWatchableQuests, IsQuestWatchedByIndex/ById (after UntrackQuest)**

  Find this exact block (the end of UntrackQuest and the start of IsUnitOnQuest):
  ```lua
  function WowQuestAPI.UntrackQuest(questID)
      local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
      if logIndex then
          RemoveQuestWatch(logIndex)
      end
  end

  ------------------------------------------------------------------------
  -- WowQuestAPI.IsUnitOnQuest(questID, unit)
  ```

  Replace with:
  ```lua
  function WowQuestAPI.UntrackQuest(questID)
      local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
      if logIndex then
          RemoveQuestWatch(logIndex)
      end
  end

  ------------------------------------------------------------------------
  -- WowQuestAPI.GetWatchedQuestCount()
  -- Returns the number of quests currently on the watch list.
  ------------------------------------------------------------------------

  function WowQuestAPI.GetWatchedQuestCount()
      return GetNumQuestWatches()
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

  ------------------------------------------------------------------------
  -- WowQuestAPI.IsUnitOnQuest(questID, unit)
  ```

- [ ] **Step 5: Verify Step 4**

  Read the four new wrapper blocks. Confirm:
  - `GetWatchedQuestCount` wraps `GetNumQuestWatches()`
  - `GetMaxWatchableQuests` returns `MAX_WATCHABLE_QUESTS`
  - `IsQuestWatchedByIndex` uses `and true or false` coercion
  - `IsQuestWatchedById` returns nil when `GetQuestLogIndex` returns nil, else uses the same coercion
  - `IsUnitOnQuest` block still follows

---

- [ ] **Step 6: Insert Group C — GetQuestLogTimeLeft, GetQuestLinkByIndex/ById, GetCurrentDisplayedQuestID (in Quest Log Frame section)**

  Find the `SelectQuestLogEntry` wrapper (it wraps the global `SelectQuestLogEntry(logIndex)`). It looks like:
  ```lua
  -- SelectQuestLogEntry(logIndex)
  -- Sets the selected entry without refreshing the quest log display.
  function WowQuestAPI.SelectQuestLogEntry(logIndex)
      SelectQuestLogEntry(logIndex)
  end
  ```

  Find the next `--` comment block that follows it (the `GetQuestLogPushable` wrapper). Insert the new wrappers **between** `SelectQuestLogEntry` and `GetQuestLogPushable`:

  Match on:
  ```lua
  function WowQuestAPI.SelectQuestLogEntry(logIndex)
      SelectQuestLogEntry(logIndex)
  end

  -- GetQuestLogPushable() → bool
  ```

  Replace with:
  ```lua
  function WowQuestAPI.SelectQuestLogEntry(logIndex)
      SelectQuestLogEntry(logIndex)
  end

  -- GetQuestLogTimeLeft() → number or nil
  -- Returns the time remaining in seconds for the selected quest's timer,
  -- or nil if the selected quest has no timer.
  function WowQuestAPI.GetQuestLogTimeLeft()
      return GetQuestLogTimeLeft()
  end

  -- GetQuestLinkByIndex(logIndex) → hyperlink string or nil
  -- Returns the chat hyperlink for the quest at logIndex.
  function WowQuestAPI.GetQuestLinkByIndex(logIndex)
      return GetQuestLink(logIndex)
  end

  -- GetQuestLinkById(questID) → hyperlink string or nil
  -- Resolves questID → logIndex, then returns the hyperlink.
  -- Returns nil if the quest is not in the player's log.
  -- Note: Retail equivalent will be added in the Retail sub-project.
  function WowQuestAPI.GetQuestLinkById(questID)
      local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
      if not logIndex then return nil end
      return GetQuestLink(logIndex)
  end

  -- GetCurrentDisplayedQuestID() → number or nil
  -- Returns the questID of the quest currently displayed in the NPC quest dialog.
  -- This covers both accepting a quest from a quest giver and the turn-in reward
  -- screen — any context where a quest is open in the NPC interaction UI.
  -- Only meaningful while an NPC quest dialog is open.
  function WowQuestAPI.GetCurrentDisplayedQuestID()
      return GetQuestID()
  end

  -- GetQuestLogPushable() → bool
  ```

- [ ] **Step 7: Verify Step 6**

  Read the area around the four new wrappers. Confirm:
  - `GetQuestLogTimeLeft` returns `GetQuestLogTimeLeft()`
  - `GetQuestLinkByIndex` returns `GetQuestLink(logIndex)`
  - `GetQuestLinkById` returns nil when logIndex not found, otherwise `GetQuestLink(logIndex)`
  - `GetCurrentDisplayedQuestID` returns `GetQuestID()`
  - `SelectQuestLogEntry` still precedes them; `GetQuestLogPushable` still follows

---

- [ ] **Step 8: Insert Group D — GetAreaInfo (at end of file)**

  Read the last few lines of `Core/WowQuestAPI.lua` to find the end of the `GetPlayerLevel` function. It looks like:
  ```lua
  -- GetPlayerLevel() → number
  -- Returns the player's current character level.
  function WowQuestAPI.GetPlayerLevel()
      return UnitLevel("player")
  end
  ```

  Append after it:
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

- [ ] **Step 9: Verify Step 8**

  Read the last 15 lines of `Core/WowQuestAPI.lua`. Confirm `GetAreaInfo` is the final function and calls `C_Map.GetAreaInfo(areaID)`.

---

- [ ] **Step 10: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add Core/WowQuestAPI.lua && git commit -m "feat: add 10 missing WowQuestAPI wrappers for architectural cleanup"
  ```

---

## Task 2: QuestCache.lua — Replace 15 direct WoW calls

**Files:**
- Modify: `Core/QuestCache.lua`

Work top-to-bottom. After each edit, read the changed line(s) to confirm before continuing.

---

- [ ] **Step 1: Read current state**

  Read `Core/QuestCache.lua` in full to confirm the 15 direct calls are present.

---

- [ ] **Step 2: Line 21 — GetQuestLogSelection**

  Find:
  ```lua
      local originalSelection = GetQuestLogSelection()
  ```
  Replace with:
  ```lua
      local originalSelection = WowQuestAPI.GetQuestLogSelection()
  ```

---

- [ ] **Step 3: Line 28 — GetNumQuestLogEntries (first occurrence)**

  Find:
  ```lua
      local numEntries = GetNumQuestLogEntries()
  ```
  Replace with:
  ```lua
      local numEntries = WowQuestAPI.GetNumQuestLogEntries()
  ```

---

- [ ] **Step 4: Line 30 — GetQuestLogTitle (Phase 1)**

  Find:
  ```lua
          local title, _, _, isHeader, isCollapsed = GetQuestLogTitle(i)
  ```
  Replace with:
  ```lua
          local title, _, _, isHeader, isCollapsed = WowQuestAPI.GetQuestLogTitle(i)
  ```

---

- [ ] **Step 5: Line 45 — ExpandQuestHeader**

  Find:
  ```lua
          ExpandQuestHeader(collapsedHeaders[k].index)
  ```
  Replace with:
  ```lua
          WowQuestAPI.ExpandQuestHeader(collapsedHeaders[k].index)
  ```

---

- [ ] **Step 6: Line 52 — GetNumQuestLogEntries (Phase 3 reassignment)**

  Find:
  ```lua
      numEntries = GetNumQuestLogEntries()
      for i = 1, numEntries do
          -- TBC 20505: C_QuestLog.GetInfo() does not exist; use GetQuestLogTitle() global.
  ```
  Replace with:
  ```lua
      numEntries = WowQuestAPI.GetNumQuestLogEntries()
      for i = 1, numEntries do
          -- TBC 20505: C_QuestLog.GetInfo() does not exist; use GetQuestLogTitle() global.
  ```

---

- [ ] **Step 7: Lines 58–59 — GetQuestLogTitle (Phase 3 full destructure)**

  Find:
  ```lua
          local title, level, suggestedGroup, isHeader, _, isComplete, _, questID =
              GetQuestLogTitle(i)
  ```
  Replace with:
  ```lua
          local title, level, suggestedGroup, isHeader, _, isComplete, _, questID =
              WowQuestAPI.GetQuestLogTitle(i)
  ```

---

- [ ] **Step 8: Lines 99–101 — GetNumQuestLogEntries + GetQuestLogTitle (Phase 4)**

  Find:
  ```lua
          numEntries = GetNumQuestLogEntries()
          for i = 1, numEntries do
              local title, _, _, isHeader = GetQuestLogTitle(i)
  ```
  Replace with:
  ```lua
          numEntries = WowQuestAPI.GetNumQuestLogEntries()
          for i = 1, numEntries do
              local title, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(i)
  ```

---

- [ ] **Step 9: Line 108 — CollapseQuestHeader**

  Find:
  ```lua
              CollapseQuestHeader(toCollapse[k])
  ```
  Replace with:
  ```lua
              WowQuestAPI.CollapseQuestHeader(toCollapse[k])
  ```

---

- [ ] **Step 10: Line 116 — SelectQuestLogEntry (Phase 5 restore)**

  Find:
  ```lua
      SelectQuestLogEntry(originalSelection or 0)
  ```
  Replace with:
  ```lua
      WowQuestAPI.SelectQuestLogEntry(originalSelection or 0)
  ```

---

- [ ] **Step 11: Line 135 — SelectQuestLogEntry (in _buildEntry)**

  Find:
  ```lua
      SelectQuestLogEntry(logIndex)
      local rawTimer = GetQuestLogTimeLeft()
  ```
  Replace with:
  ```lua
      WowQuestAPI.SelectQuestLogEntry(logIndex)
      local rawTimer = WowQuestAPI.GetQuestLogTimeLeft()
  ```

  > Note: This replaces both line 135 (`SelectQuestLogEntry`) and line 136 (`GetQuestLogTimeLeft`) in one edit since they are adjacent. This is two of the 15 replacements.

---

- [ ] **Step 12: Line 141 — GetQuestLink**

  Find:
  ```lua
      local link = GetQuestLink(logIndex)
  ```
  Replace with:
  ```lua
      local link = WowQuestAPI.GetQuestLinkByIndex(logIndex)
  ```

---

- [ ] **Step 13: Line 148 — IsQuestWatched**

  Find:
  ```lua
      local isTracked = IsQuestWatched(logIndex) and true or false
  ```
  Replace with:
  ```lua
      local isTracked = WowQuestAPI.IsQuestWatchedByIndex(logIndex)
  ```

---

- [ ] **Step 14: Line 156 — C_QuestLog.GetQuestObjectives**

  Find:
  ```lua
      local rawObjs = C_QuestLog.GetQuestObjectives(questID)
  ```
  Replace with:
  ```lua
      local rawObjs = WowQuestAPI.GetQuestObjectives(questID)
  ```

  > Note: `WowQuestAPI.GetQuestObjectives` returns `{}` if the API returns nil. The surrounding `if rawObjs then` guard will still work correctly since `{}` is truthy — verify this is the expected behavior after the edit.

---

- [ ] **Step 15: Verify all 15 replacements**

  Run:
  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -n "GetQuestLogSelection()\|GetNumQuestLogEntries()\|GetQuestLogTitle(\|ExpandQuestHeader(\|CollapseQuestHeader(\|SelectQuestLogEntry(\|GetQuestLogTimeLeft()\|GetQuestLink(\|IsQuestWatched(\|C_QuestLog\.GetQuestObjectives(" Core/QuestCache.lua
  ```
  Expected: zero results. If any matches remain, fix them before committing.

---

- [ ] **Step 16: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add Core/QuestCache.lua && git commit -m "refactor: replace 15 direct WoW calls with WowQuestAPI wrappers in QuestCache"
  ```

---

## Task 3: HistoryCache, EventEngine, AbsoluteQuestLog, QuestieProvider — small callsite updates

**Files:**
- Modify: `Core/HistoryCache.lua`
- Modify: `Core/EventEngine.lua`
- Modify: `AbsoluteQuestLog.lua`
- Modify: `Providers/QuestieProvider.lua`

---

- [ ] **Step 1: HistoryCache.lua — GetQuestsCompleted**

  Find:
  ```lua
      local data = GetQuestsCompleted()
  ```
  Replace with:
  ```lua
      local data = WowQuestAPI.GetQuestsCompleted()
  ```

  Verify: read lines 16–28 of `Core/HistoryCache.lua`. Confirm `WowQuestAPI.GetQuestsCompleted()` is present and the `for questID, done in pairs(data)` loop is unchanged.

---

- [ ] **Step 2: EventEngine.lua — GetQuestID**

  Find:
  ```lua
      local questID = GetQuestID()
  ```
  inside the `hooksecurefunc("GetQuestReward", ...)` block.

  Replace with:
  ```lua
      local questID = WowQuestAPI.GetCurrentDisplayedQuestID()
  ```

  Verify: read lines 51–59 of `Core/EventEngine.lua`. Confirm the hook body now calls `WowQuestAPI.GetCurrentDisplayedQuestID()` and the rest of the hook (pendingTurnIn assignment, debug message) is unchanged.

---

- [ ] **Step 3: AbsoluteQuestLog.lua — GetNumQuestWatches and MAX_WATCHABLE_QUESTS**

  Find:
  ```lua
      if GetNumQuestWatches() >= MAX_WATCHABLE_QUESTS then
  ```
  Replace with:
  ```lua
      if WowQuestAPI.GetWatchedQuestCount() >= WowQuestAPI.GetMaxWatchableQuests() then
  ```

  Verify: read the `TrackQuest` method (around line 394). Confirm the condition now uses both wrapper calls and the function body is otherwise unchanged.

---

- [ ] **Step 4: QuestieProvider.lua — C_Map.GetAreaInfo**

  Find:
  ```lua
          zone = C_Map.GetAreaInfo(quest.zoneOrSort)  -- returns string or nil
  ```
  Replace with:
  ```lua
          zone = WowQuestAPI.GetAreaInfo(quest.zoneOrSort)  -- returns string or nil
  ```

  Verify: read lines 205–220 of `Providers/QuestieProvider.lua`. Confirm `WowQuestAPI.GetAreaInfo` is present and the surrounding `if quest.zoneOrSort and quest.zoneOrSort > 0 then` guard is unchanged.

---

- [ ] **Step 5: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add Core/HistoryCache.lua Core/EventEngine.lua AbsoluteQuestLog.lua Providers/QuestieProvider.lua && git commit -m "refactor: replace direct WoW calls with WowQuestAPI wrappers in remaining files"
  ```

---

## Task 4: Version bump and documentation

**Files:**
- Modify: `AbsoluteQuestLog.toc`, `AbsoluteQuestLog_Classic.toc`, `AbsoluteQuestLog_TBC.toc`, `AbsoluteQuestLog_Mists.toc`, `AbsoluteQuestLog_Mainline.toc`
- Modify: `CLAUDE.md`
- Modify: `changelog.txt`

---

- [ ] **Step 1: Bump version in all five toc files**

  In each file, change `## Version: 2.5.2` to `## Version: 2.5.3`. Edit all five:
  - `AbsoluteQuestLog.toc`
  - `AbsoluteQuestLog_Classic.toc`
  - `AbsoluteQuestLog_TBC.toc`
  - `AbsoluteQuestLog_Mists.toc`
  - `AbsoluteQuestLog_Mainline.toc`

- [ ] **Step 2: Verify version bump**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep "Version:" AbsoluteQuestLog*.toc
  ```
  Expected: all five show `## Version: 2.5.3`

---

- [ ] **Step 3: Add version 2.5.3 entry to CLAUDE.md**

  Find `### Version 2.5.2 (March 2026)` and insert the following block **above** it:

  ```markdown
  ### Version 2.5.3 (March 2026)
  - Refactor: All direct WoW global calls outside `WowQuestAPI.lua` replaced with wrapper calls. Files updated: `QuestCache.lua` (15 callsites), `HistoryCache.lua` (1), `EventEngine.lua` (1), `AbsoluteQuestLog.lua` (2), `QuestieProvider.lua` (1).
  - New wrappers added to `WowQuestAPI.lua`: `GetQuestsCompleted`, `IsQuestWatchedByIndex`, `IsQuestWatchedById`, `GetQuestLogTimeLeft`, `GetQuestLinkByIndex`, `GetQuestLinkById`, `GetCurrentDisplayedQuestID`, `GetWatchedQuestCount`, `GetMaxWatchableQuests`, `GetAreaInfo`. Zero behavioral changes.

  ```

- [ ] **Step 4: Reinforce WowQuestAPI rule in CLAUDE.md Architecture section**

  Find the `WowQuestAPI.lua` row in the Core Modules table. Current description:
  ```
  | `Core\WowQuestAPI.lua` | `WowQuestAPI` (global) | Thin, stateless wrappers around WoW quest globals. All version-specific branching (TBC vs Retail) lives here. No other AQL file references WoW quest globals directly. |
  ```

  Replace with:
  ```
  | `Core\WowQuestAPI.lua` | `WowQuestAPI` (global) | Thin, stateless wrappers around WoW quest globals. All version-specific branching lives here. **All WoW API calls — including those in providers — must go through WowQuestAPI wrappers, no exceptions.** No other AQL file may reference WoW quest globals directly. |
  ```

- [ ] **Step 5: Add 2.5.3 entry to changelog.txt**

  Find `Version 2.5.2 (March 2026)` at the top of `changelog.txt` and insert the following block **above** it:

  ```
  Version 2.5.3 (March 2026)
  ---------------------------
  - Refactor: All direct WoW global calls outside WowQuestAPI.lua replaced with
    wrapper calls. Files updated: QuestCache.lua (15 callsites), HistoryCache.lua
    (1), EventEngine.lua (1), AbsoluteQuestLog.lua (2), QuestieProvider.lua (1).
  - New wrappers added to WowQuestAPI.lua: GetQuestsCompleted,
    IsQuestWatchedByIndex, IsQuestWatchedById, GetQuestLogTimeLeft,
    GetQuestLinkByIndex, GetQuestLinkById, GetCurrentDisplayedQuestID,
    GetWatchedQuestCount, GetMaxWatchableQuests, GetAreaInfo.
    Zero behavioral changes on all four supported WoW version families.

  ```

- [ ] **Step 6: Verify CLAUDE.md and changelog.txt**

  Read the Version History section in CLAUDE.md. Confirm:
  - `### Version 2.5.3` appears above `### Version 2.5.2`
  - Two bullet points present
  - WowQuestAPI row in Architecture table updated

  Read the top of `changelog.txt`. Confirm `Version 2.5.3` is the first entry.

---

- [ ] **Step 7: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add AbsoluteQuestLog.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Mainline.toc CLAUDE.md changelog.txt && git commit -m "chore: bump version to 2.5.3 — WowQuestAPI architectural cleanup"
  ```

---

## Final Verification

After all four tasks complete:

- [ ] **Verify no direct WoW calls remain in non-WowQuestAPI files**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -rn "GetQuestsCompleted\|IsQuestWatched\|GetQuestLogTimeLeft\|GetQuestLink\|GetCurrentDisplayedQuestID\|GetQuestID()\|GetWatchedQuestCount\|GetNumQuestWatches\|MAX_WATCHABLE_QUESTS\|C_Map\.GetAreaInfo" Core/ AbsoluteQuestLog.lua Providers/ --include="*.lua" | grep -v WowQuestAPI.lua
  ```
  Expected: zero results.

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -n "GetQuestLogSelection()\|GetNumQuestLogEntries()\|GetQuestLogTitle(\|ExpandQuestHeader(\|CollapseQuestHeader(\|SelectQuestLogEntry(" Core/QuestCache.lua
  ```
  Expected: zero results.

- [ ] **Verify all 10 new wrappers exist in WowQuestAPI.lua**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -n "function WowQuestAPI\." Core/WowQuestAPI.lua
  ```
  Expected output includes all 10 new functions: `GetQuestsCompleted`, `GetWatchedQuestCount`, `GetMaxWatchableQuests`, `IsQuestWatchedByIndex`, `IsQuestWatchedById`, `GetQuestLogTimeLeft`, `GetQuestLinkByIndex`, `GetQuestLinkById`, `GetCurrentDisplayedQuestID`, `GetAreaInfo`.
