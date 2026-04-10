# AQL MoP Classic Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MoP Classic (5.x) fully functional — fix `IsUnitOnQuest` to use the MoP global API, register `QUEST_TURNED_IN` for native turn-in detection, and fix two unsafe boolean coercions on legacy WoW globals.

**Architecture:** Four files touched. `Core/WowQuestAPI.lua` gets a MoP branch in `IsUnitOnQuest`, a header comment update, a boolean coercion fix in `GetQuestLogPushable`, and a deferred-language cleanup in `GetQuestInfo`. `Core/QuestCache.lua` gets a boolean coercion fix in `IsQuestWatched`. `Core/EventEngine.lua` registers and handles `QUEST_TURNED_IN`. Housekeeping: version bump and CLAUDE.md update.

**Tech Stack:** Lua (WoW addon). No automated test framework — verification is by reading file content after edits and checking exact line text.

---

## Background

### Version constants (already in place — read-only, do not change)

```lua
-- Core/WowQuestAPI.lua
local IS_CLASSIC_ERA = _TOC <  20000
local IS_TBC         = _TOC >= 20000 and _TOC < 30000
local IS_MOP         = _TOC >= 50000 and _TOC < 60000
local IS_RETAIL      = _TOC >= 100000
```

### Why `if API() then return true end / return false` instead of `== true` or `~= nil`

Legacy WoW C globals commonly return `1` (number) for truthy results, not Lua `true`. In Lua, `1 == true` is `false`. And `~= nil` breaks if the global returns boolean `false`. The explicit `if/then/return` pattern handles `1`, `true`, `nil`, and `false` correctly regardless of WoW API version.

### QUEST_TURNED_IN does not double-fire AQL_QUEST_COMPLETED

`QUEST_TURNED_IN` only sets `pendingTurnIn[questID]` — it does NOT call `handleQuestLogUpdate()`. The diff that fires `AQL_QUEST_COMPLETED` is triggered solely by `QUEST_REMOVED`. One diff, one callback.

### WowQuestAPI.GetQuestLogIndex already exists

`WowQuestAPI.GetQuestLogIndex(questID)` scans the log and returns the logIndex for a questID, or nil if not found. The MoP `IsUnitOnQuest` branch uses this to convert questID → logIndex before calling the global.

---

## Files Modified

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | Boolean coercion fix in `GetQuestLogPushable`; MoP branch + comment update in `IsUnitOnQuest`; deferred-language cleanup in `GetQuestInfo` else-branch |
| `Core/QuestCache.lua` | Boolean coercion fix in `IsQuestWatched` |
| `Core/EventEngine.lua` | Update `GetQuestReward` hook comment; register `QUEST_TURNED_IN`; add event handler branch |
| `AbsoluteQuestLog.toc` | Version bump to 2.5.2 |
| `AbsoluteQuestLog_Classic.toc` | Version bump to 2.5.2 |
| `AbsoluteQuestLog_TBC.toc` | Version bump to 2.5.2 |
| `AbsoluteQuestLog_Mists.toc` | Version bump to 2.5.2 |
| `AbsoluteQuestLog_Mainline.toc` | Version bump to 2.5.2 |
| `CLAUDE.md` | Add version 2.5.2 entry; add `QUEST_TURNED_IN` to "WoW Events Registered" section |

---

## Task 1: WowQuestAPI.lua — all changes

**Files:**
- Modify: `Core/WowQuestAPI.lua`

All four changes in this file are done in a single task and committed together. Work top-to-bottom in the file to avoid line-shift confusion.

> **Important:** Line numbers shift as you edit. Always match by content, not line number. After each Edit, read back the relevant section to confirm before continuing.

---

- [ ] **Step 1: Read the file before editing**

  Read `Core/WowQuestAPI.lua` lines 44–52 and 147–170 and 198–210 to confirm current state.

  Confirm:
  - Line ~48: `else  -- IS_TBC, IS_CLASSIC_ERA, and IS_MOP (same log-scan API; MoP sub-project handles MoP-specific improvements)`
  - Lines ~148–152: the five-line `IsUnitOnQuest` comment block
  - Lines ~155–163: the `if IS_RETAIL then ... else ... end` block
  - Line ~203: `    return GetQuestLogPushable() ~= nil`

---

- [ ] **Step 2: Clean up the GetQuestInfo else-branch comment**

  Use the Edit tool. Match on the exact string:
  ```lua
  else  -- IS_TBC, IS_CLASSIC_ERA, and IS_MOP (same log-scan API; MoP sub-project handles MoP-specific improvements)
  ```

  Replace with:
  ```lua
  else  -- IS_TBC, IS_CLASSIC_ERA, and IS_MOP (same log-scan API on all three versions)
  ```

- [ ] **Step 3: Verify Step 2**

  Read lines 44–52. Confirm the else-branch comment no longer contains "MoP sub-project handles" language.

---

- [ ] **Step 4: Update the IsUnitOnQuest header comment**

  The current five-line comment block (between the separator dashes) reads:
  ```lua
  -- WowQuestAPI.IsUnitOnQuest(questID, unit)
  -- Returns bool on Retail (UnitIsOnQuest exists).
  -- Returns nil on TBC/Classic (API does not exist).
  -- Note: parameter order is (questID, unit) — the opposite of the WoW
  -- global UnitIsOnQuest(unit, questID) — to keep questID-first convention.
  ```

  Use the Edit tool. Match on that exact block (5 lines). Replace with:
  ```lua
  -- WowQuestAPI.IsUnitOnQuest(questID, unit)
  -- Returns bool on Retail and MoP.
  -- Returns nil on TBC/Classic Era (API does not exist on TBC; deferred on Classic Era).
  -- MoP: resolves questID → logIndex via GetQuestLogIndex, then calls IsUnitOnQuest(logIndex, unit).
  -- Returns nil on MoP if the quest is not in the player's log (collapsed or absent).
  -- Note: parameter order is (questID, unit) — the opposite of the WoW
  -- global UnitIsOnQuest(unit, questID) — to keep questID-first convention.
  ```

- [ ] **Step 5: Verify Step 4**

  Read the IsUnitOnQuest header. Confirm 7 comment lines are present, the `--------` separator lines above and below are still intact, and the new lines about MoP and `GetQuestLogIndex` are present.

---

- [ ] **Step 6: Add MoP branch to IsUnitOnQuest code block**

  Current code (the `if IS_RETAIL then ... else ... end` block):
  ```lua
  if IS_RETAIL then
      function WowQuestAPI.IsUnitOnQuest(questID, unit)
          return UnitIsOnQuest(unit, questID)
      end
  else
      function WowQuestAPI.IsUnitOnQuest(questID, unit)
          return nil
      end
  end
  ```

  Use the Edit tool. Match on the exact block above. Replace with:
  ```lua
  if IS_RETAIL then
      function WowQuestAPI.IsUnitOnQuest(questID, unit)
          return UnitIsOnQuest(unit, questID)
      end
  elseif IS_MOP then
      function WowQuestAPI.IsUnitOnQuest(questID, unit)
          local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
          if not logIndex then return nil end
          if IsUnitOnQuest(logIndex, unit) then return true end
          return false
      end
  else
      function WowQuestAPI.IsUnitOnQuest(questID, unit)
          return nil
      end
  end
  ```

- [ ] **Step 7: Verify Step 6**

  Read the IsUnitOnQuest block. Confirm:
  - `if IS_RETAIL then` branch is unchanged
  - `elseif IS_MOP then` branch is present with the `GetQuestLogIndex` call and `if/then/return` boolean coercion
  - `else` branch still returns nil (for TBC/Classic Era)
  - Three `end` statements close the three function bodies; one final `end` closes the if block

---

- [ ] **Step 8: Fix GetQuestLogPushable boolean coercion**

  Find the `GetQuestLogPushable` wrapper function. The current body line reads:
  ```lua
      return GetQuestLogPushable() ~= nil
  ```

  Use the Edit tool. Match on that exact line (with 4 leading spaces). Replace with:
  ```lua
      if GetQuestLogPushable() then return true end
      return false
  ```

- [ ] **Step 9: Verify Step 8**

  Read the `GetQuestLogPushable` function. Confirm:
  - The function body now has two lines: `if GetQuestLogPushable() then return true end` and `return false`
  - The surrounding `-- GetQuestLogPushable() → bool` comment and function declaration are unchanged

---

- [ ] **Step 10: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add Core/WowQuestAPI.lua && git commit -m "feat: add MoP IsUnitOnQuest branch; fix boolean coercions in WowQuestAPI"
  ```

---

## Task 2: QuestCache.lua — IsQuestWatched boolean fix

**Files:**
- Modify: `Core/QuestCache.lua`

- [ ] **Step 1: Read the file**

  Read `Core/QuestCache.lua` lines 144–152. Confirm line 148 reads:
  ```lua
      local isTracked = IsQuestWatched(logIndex) == true
  ```

- [ ] **Step 2: Fix the boolean coercion**

  Use the Edit tool. Match on the exact line (with 4 leading spaces):
  ```lua
      local isTracked = IsQuestWatched(logIndex) == true
  ```

  Replace with:
  ```lua
      local isTracked = IsQuestWatched(logIndex) and true or false
  ```

- [ ] **Step 3: Verify**

  Read lines 144–152. Confirm line 148 now reads:
  ```lua
      local isTracked = IsQuestWatched(logIndex) and true or false
  ```
  and no other lines changed.

- [ ] **Step 4: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add Core/QuestCache.lua && git commit -m "fix: safe boolean coercion for IsQuestWatched"
  ```

---

## Task 3: EventEngine.lua — QUEST_TURNED_IN

**Files:**
- Modify: `Core/EventEngine.lua`

Three changes in this file, all committed together. Work top-to-bottom.

- [ ] **Step 1: Read the file**

  Read `Core/EventEngine.lua` lines 40–58 and lines 404–416 and lines 438–446 to confirm current state.

  Confirm:
  - Lines 42–48: seven-line `GetQuestReward` hook comment block
  - Lines 407–411: five `RegisterEvent` calls (no QUEST_TURNED_IN yet)
  - Lines 441–444: `elseif event == "QUEST_WATCH_LIST_CHANGED" or event == "QUEST_LOG_UPDATE" then ... end`

---

- [ ] **Step 2: Update the GetQuestReward hook comment**

  Current comment (7 lines, immediately before `hooksecurefunc`):
  ```lua
  -- QUEST_TURNED_IN does not fire in TBC Classic (Interface 20505).
  -- Hook GetQuestReward instead: it fires synchronously when the player clicks
  -- the confirm button, before items are transferred. GetQuestID() returns the
  -- active questID at this point. This sets pendingTurnIn so that any objective
  -- regression events fired during item transfer are suppressed.
  -- The hook fires only on confirmation; cancelling the reward screen does not
  -- call GetQuestReward, so pendingTurnIn is never set on cancel.
  ```

  Use the Edit tool. Match on the exact 7-line block. Replace with:
  ```lua
  -- QUEST_TURNED_IN does not fire in TBC Classic (Interface 20505).
  -- Hook GetQuestReward as the turn-in signal for TBC: it fires synchronously
  -- when the player clicks the confirm button, before items are transferred.
  -- GetQuestID() returns the active questID at this point.
  -- On Classic Era, MoP, and Retail, QUEST_TURNED_IN fires and also sets
  -- pendingTurnIn directly (see the event handler below). Both paths are
  -- harmless on versions that fire both; the hook is kept for TBC compatibility.
  -- The hook fires only on confirmation; cancelling the reward screen does not
  -- call GetQuestReward, so pendingTurnIn is never set on cancel.
  ```

- [ ] **Step 3: Verify Step 2**

  Read lines 40–58. Confirm the updated 9-line comment block is present immediately before the `hooksecurefunc("GetQuestReward", ...)` call, and the hook body itself (lines setting `pendingTurnIn` and the debug message) is unchanged.

---

- [ ] **Step 4: Register QUEST_TURNED_IN**

  Current 5-line registration block:
  ```lua
          frame:RegisterEvent("QUEST_ACCEPTED")
          frame:RegisterEvent("QUEST_REMOVED")
          frame:RegisterEvent("QUEST_LOG_UPDATE")
          frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
          frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
  ```

  Use the Edit tool. Match on the exact 5-line block (with leading spaces). Replace with:
  ```lua
          frame:RegisterEvent("QUEST_ACCEPTED")
          frame:RegisterEvent("QUEST_REMOVED")
          frame:RegisterEvent("QUEST_TURNED_IN")
          frame:RegisterEvent("QUEST_LOG_UPDATE")
          frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
          frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
  ```

- [ ] **Step 5: Verify Step 4**

  Read the PLAYER_LOGIN registration block. Confirm 6 `RegisterEvent` calls are present and `QUEST_TURNED_IN` is between `QUEST_REMOVED` and `QUEST_LOG_UPDATE`.

---

- [ ] **Step 6: Add QUEST_TURNED_IN event handler branch**

  Current tail of the OnEvent handler (the last elseif before the closing `end`):
  ```lua
      elseif event == "QUEST_WATCH_LIST_CHANGED"
          or event == "QUEST_LOG_UPDATE" then
          handleQuestLogUpdate()
      end
  ```

  Use the Edit tool. Match on the exact 4-line block. Replace with:
  ```lua
      elseif event == "QUEST_TURNED_IN" then
          -- Set pendingTurnIn so objective regression during item transfer is suppressed.
          -- Do NOT call handleQuestLogUpdate here — QUEST_REMOVED fires next and drives
          -- the diff that detects quest removal and fires AQL_QUEST_COMPLETED.
          local questID = ...
          if questID and questID ~= 0 then
              EventEngine.pendingTurnIn[questID] = true
              if AQL.debug then
                  DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] pendingTurnIn set (QUEST_TURNED_IN): questID=" .. tostring(questID) .. AQL.RESET)
              end
          end
      elseif event == "QUEST_WATCH_LIST_CHANGED"
          or event == "QUEST_LOG_UPDATE" then
          handleQuestLogUpdate()
      end
  ```

- [ ] **Step 7: Verify Step 6**

  Read the tail of the OnEvent handler. Confirm:
  - `QUEST_TURNED_IN` branch is present before `QUEST_WATCH_LIST_CHANGED`
  - The branch sets `EventEngine.pendingTurnIn[questID] = true` with guard `if questID and questID ~= 0 then`
  - The branch does NOT call `handleQuestLogUpdate()`
  - Debug message follows the existing `AQL.DBG` pattern
  - The `QUEST_WATCH_LIST_CHANGED` / `QUEST_LOG_UPDATE` branch is unchanged
  - The handler closes with a single `end`

---

- [ ] **Step 8: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add Core/EventEngine.lua && git commit -m "feat: register and handle QUEST_TURNED_IN for MoP turn-in detection"
  ```

---

## Task 4: Version bump and CLAUDE.md update

**Files:**
- Modify: `AbsoluteQuestLog.toc`, `AbsoluteQuestLog_Classic.toc`, `AbsoluteQuestLog_TBC.toc`, `AbsoluteQuestLog_Mists.toc`, `AbsoluteQuestLog_Mainline.toc`
- Modify: `CLAUDE.md`

**Versioning rule:** Version 2.5.1 was set earlier today (2026-03-29). This is the third change set on the same day, so the version becomes **2.5.2** (revision increments again; minor stays).

- [ ] **Step 1: Bump version in all five toc files**

  In each toc file, change `## Version: 2.5.1` to `## Version: 2.5.2`. Edit all five:
  - `AbsoluteQuestLog.toc`
  - `AbsoluteQuestLog_Classic.toc`
  - `AbsoluteQuestLog_TBC.toc`
  - `AbsoluteQuestLog_Mists.toc`
  - `AbsoluteQuestLog_Mainline.toc`

- [ ] **Step 2: Verify version bump**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep "Version:" AbsoluteQuestLog*.toc
  ```
  Expected: all five files show `## Version: 2.5.2`

- [ ] **Step 3: Add version 2.5.2 entry to CLAUDE.md**

  In `CLAUDE.md`, find `### Version 2.5.1 (March 2026)` and insert the following block **above** it:

  ```markdown
  ### Version 2.5.2 (March 2026)
  - Feature: MoP Classic (5.x) `IsUnitOnQuest` now functional — resolves questID to logIndex via `GetQuestLogIndex` and calls the MoP global `IsUnitOnQuest(logIndex, unit)`. Returns nil when quest is not in the player's log.
  - Feature: `QUEST_TURNED_IN` event registered and handled in `EventEngine`. Sets `pendingTurnIn` directly on Classic Era, MoP, and Retail. `GetQuestReward` hook retained for TBC compatibility.
  - Fix: Boolean coercion on legacy WoW globals — `GetQuestLogPushable` and `IsQuestWatched` now use explicit `if/then/return` / `and true or false` patterns instead of `~= nil` / `== true` comparisons that could silently return wrong results.

  ```

  Use the Edit tool — match on `### Version 2.5.1 (March 2026)` and insert the new block above it.

- [ ] **Step 4: Update "WoW Events Registered" section in CLAUDE.md**

  Find the "WoW Events Registered" section. The current line reads:

  ```
  `PLAYER_LOGIN` is registered at load time. After `PLAYER_LOGIN` fires, `EventEngine` also registers: `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_LOG_UPDATE`, `UNIT_QUEST_LOG_CHANGED`, `QUEST_WATCH_LIST_CHANGED`.
  ```

  Replace with:

  ```
  `PLAYER_LOGIN` is registered at load time. After `PLAYER_LOGIN` fires, `EventEngine` also registers: `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`, `QUEST_LOG_UPDATE`, `UNIT_QUEST_LOG_CHANGED`, `QUEST_WATCH_LIST_CHANGED`.
  ```

- [ ] **Step 5: Verify CLAUDE.md**

  Read the Version History section. Confirm:
  - `### Version 2.5.2 (March 2026)` appears above `### Version 2.5.1`
  - Three bullet points are present
  - "WoW Events Registered" section now lists `QUEST_TURNED_IN`

- [ ] **Step 6: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add AbsoluteQuestLog.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Mainline.toc CLAUDE.md && git commit -m "chore: bump version to 2.5.2 — MoP support and boolean coercion fixes"
  ```

---

## Final Verification

After all four tasks are complete:

- [ ] **Verify no unsafe boolean patterns remain on WoW globals**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -n "~= nil\|== true" Core/WowQuestAPI.lua Core/QuestCache.lua
  ```

  Expected output — only safe comparisons should remain:
  - `WowQuestAPI.lua`: `(isComplete == 1 or isComplete == true)` (safe — handles both), `QuestLogFrame ~= nil` (safe — checking object existence), `:IsShown() == true` (safe — Frame method returns real bool), `C_QuestLog.IsQuestFlaggedCompleted(...) == true` (safe — C_QuestLog returns real bool), `IsQuestFlaggedCompleted(...) == true` (safe — confirmed returns real bool in production)
  - `QuestCache.lua`: `isComplete == 1 or info.isComplete == true` (safe — handles both), `obj.finished == true` (safe — C_QuestLog field returns real bool)
  - No remaining `GetQuestLogPushable() ~= nil` or `IsQuestWatched(...) == true`

- [ ] **Verify MoP IsUnitOnQuest branch is present**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -A5 "elseif IS_MOP" Core/WowQuestAPI.lua
  ```
  Expected: the MoP branch with `GetQuestLogIndex` and `if IsUnitOnQuest then return true end` is shown.

- [ ] **Verify QUEST_TURNED_IN is registered**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep "QUEST_TURNED_IN" Core/EventEngine.lua
  ```
  Expected: three matches — the comment update, the `RegisterEvent` call, and the `elseif event ==` handler branch.
