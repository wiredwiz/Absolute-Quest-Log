# Fix: Quest Turn-In Detection — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix false "Abandoned" banner and spurious objective regression that both fire during quest turn-in because `QUEST_TURNED_IN` does not fire in TBC Classic (Interface 20505).

**Architecture:** Two targeted edits to `Core/EventEngine.lua`. Replace the dead `QUEST_TURNED_IN` event handler with a `hooksecurefunc("GetQuestReward", ...)` hook that sets `pendingTurnIn` on actual turn-in confirmation. Add `WowQuestAPI.IsQuestFlaggedCompleted` as a fallback completion signal in `runDiff` so quests turned in during the current session are correctly identified as completions rather than abandonments.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary client (Interface 20505), LibStub, CallbackHandler-1.0. No automated test framework — verification is manual, in-game.

---

## Chunk 1: EventEngine.lua changes

### Task 1: Replace QUEST_TURNED_IN event handling with hooksecurefunc

**Files:**
- Modify: `Absolute-Quest-Log/Core/EventEngine.lua`

**Background:** `EventEngine.pendingTurnIn` is a table of questIDs that are currently in the window between the player clicking "Complete Quest" and the quest being removed from the log. During this window, item objectives drop to zero (the NPC takes the items), which would otherwise fire spurious `AQL_OBJECTIVE_REGRESSED` callbacks. The current code relies on the `QUEST_TURNED_IN` event to set `pendingTurnIn[questID]`, but that event does not fire in TBC Classic. `GetQuestReward(itemChoice)` is the underlying WoW function called when the player confirms a turn-in; it always fires on confirmation, never on cancel, and `GetQuestID()` returns a valid non-zero questID at that moment.

**Current state of the file:**

Line 23 (pendingTurnIn init):
```lua
EventEngine.pendingTurnIn    = {}  -- questIDs currently between QUEST_TURNED_IN and QUEST_REMOVED
```

Line 264 (inside PLAYER_LOGIN handler, in the RegisterEvent block):
```lua
        frame:RegisterEvent("QUEST_TURNED_IN")
```

Lines 275–292 (inside the OnEvent script's if-elseif chain):
```lua
    elseif event == "QUEST_TURNED_IN" then
        -- Pre-mark the quest as completed in HistoryCache so that when the
        -- subsequent QUEST_REMOVED / QUEST_LOG_UPDATE diff sees the quest
        -- disappear from the log, it correctly identifies it as a turn-in
        -- (HasCompleted → true) rather than an abandonment.
        -- Do NOT call handleQuestLogUpdate() here: at this moment the quest
        -- is still in the log but item objectives have already dropped to zero
        -- (items handed to the NPC), which would fire AQL_OBJECTIVE_REGRESSED
        -- spuriously. QUEST_REMOVED fires next, after the quest is fully
        -- removed, and produces AQL_QUEST_COMPLETED correctly.
        -- pendingTurnIn suppresses AQL_OBJECTIVE_REGRESSED in any diff that
        -- runs while the quest is in this window (e.g. UNIT_QUEST_LOG_CHANGED).
        -- In TBC Classic, QUEST_TURNED_IN passes: questID, xpReward, moneyReward.
        local questID = ...
        if questID and type(questID) == "number" then
            EventEngine.pendingTurnIn[questID] = true
            AQL.HistoryCache:MarkCompleted(questID)
        end
```

- [ ] **Step 1: Update the pendingTurnIn comment and add the hooksecurefunc hook**

  Open `Absolute-Quest-Log/Core/EventEngine.lua`.

  Find line 23 (the `pendingTurnIn` initialization) and replace the end-of-line comment:

  **Find:**
  ```lua
  EventEngine.pendingTurnIn    = {}  -- questIDs currently between QUEST_TURNED_IN and QUEST_REMOVED
  ```

  **Replace with:**
  ```lua
  EventEngine.pendingTurnIn    = {}  -- questIDs currently awaiting QUEST_REMOVED after turn-in confirmation
  ```

  Then immediately after line 31 (the `MAX_DEFERRED_UPGRADE_ATTEMPTS` constant — the line that reads `local MAX_DEFERRED_UPGRADE_ATTEMPTS = 5`), add a blank line and the hook:

  **Find (the constant and its preceding comment block, ending at the blank line before `--------`):**
  ```lua
  -- Number of deferred 1-second retry attempts after the initial frame-0 attempt.
  -- Total checks: 1 immediate (t=0) + 5 retries (t=1s–5s) = 6 total, up to 5 s.
  local MAX_DEFERRED_UPGRADE_ATTEMPTS = 5

  ------------------------------------------------------------------------
  ```

  **Replace with:**
  ```lua
  -- Number of deferred 1-second retry attempts after the initial frame-0 attempt.
  -- Total checks: 1 immediate (t=0) + 5 retries (t=1s–5s) = 6 total, up to 5 s.
  local MAX_DEFERRED_UPGRADE_ATTEMPTS = 5

  -- QUEST_TURNED_IN does not fire in TBC Classic (Interface 20505).
  -- Hook GetQuestReward instead: it fires synchronously when the player clicks
  -- the confirm button, before items are transferred. GetQuestID() returns the
  -- active questID at this point. This sets pendingTurnIn so that any objective
  -- regression events fired during item transfer are suppressed.
  -- The hook fires only on confirmation; cancelling the reward screen does not
  -- call GetQuestReward, so pendingTurnIn is never set on cancel.
  hooksecurefunc("GetQuestReward", function()
      local questID = GetQuestID()
      if questID and questID ~= 0 then
          EventEngine.pendingTurnIn[questID] = true
      end
  end)

  ------------------------------------------------------------------------
  ```

- [ ] **Step 2: Remove `frame:RegisterEvent("QUEST_TURNED_IN")` from the PLAYER_LOGIN handler**

  In the same file, find the RegisterEvent block inside the PLAYER_LOGIN handler (around line 262–266). Remove the `QUEST_TURNED_IN` line:

  **Find:**
  ```lua
          frame:RegisterEvent("QUEST_ACCEPTED")
          frame:RegisterEvent("QUEST_REMOVED")
          frame:RegisterEvent("QUEST_TURNED_IN")
          frame:RegisterEvent("QUEST_LOG_UPDATE")
  ```

  **Replace with:**
  ```lua
          frame:RegisterEvent("QUEST_ACCEPTED")
          frame:RegisterEvent("QUEST_REMOVED")
          frame:RegisterEvent("QUEST_LOG_UPDATE")
  ```

- [ ] **Step 3: Remove the QUEST_TURNED_IN event handler block**

  Find and delete the entire `elseif event == "QUEST_TURNED_IN" then` block from the OnEvent script. The block to remove is:

  **Find (remove this entire block including the leading blank line):**
  ```lua

      elseif event == "QUEST_TURNED_IN" then
          -- Pre-mark the quest as completed in HistoryCache so that when the
          -- subsequent QUEST_REMOVED / QUEST_LOG_UPDATE diff sees the quest
          -- disappear from the log, it correctly identifies it as a turn-in
          -- (HasCompleted → true) rather than an abandonment.
          -- Do NOT call handleQuestLogUpdate() here: at this moment the quest
          -- is still in the log but item objectives have already dropped to zero
          -- (items handed to the NPC), which would fire AQL_OBJECTIVE_REGRESSED
          -- spuriously. QUEST_REMOVED fires next, after the quest is fully
          -- removed, and produces AQL_QUEST_COMPLETED correctly.
          -- pendingTurnIn suppresses AQL_OBJECTIVE_REGRESSED in any diff that
          -- runs while the quest is in this window (e.g. UNIT_QUEST_LOG_CHANGED).
          -- In TBC Classic, QUEST_TURNED_IN passes: questID, xpReward, moneyReward.
          local questID = ...
          if questID and type(questID) == "number" then
              EventEngine.pendingTurnIn[questID] = true
              AQL.HistoryCache:MarkCompleted(questID)
          end
  ```

  **Replace with:** *(nothing — delete the block entirely)*

- [ ] **Step 4: Verify the file looks correct after edits**

  Read back the top of `EventEngine.lua` (~lines 1–90) and confirm:
  - `pendingTurnIn` comment reads "awaiting QUEST_REMOVED after turn-in confirmation"
  - `hooksecurefunc("GetQuestReward", ...)` block appears after `MAX_DEFERRED_UPGRADE_ATTEMPTS`
  - No `frame:RegisterEvent("QUEST_TURNED_IN")` line exists anywhere

  Read back the OnEvent script (~lines 245–315) and confirm:
  - No `elseif event == "QUEST_TURNED_IN"` block exists

- [ ] **Step 5: Commit**

  ```bash
  git add Absolute-Quest-Log/Core/EventEngine.lua
  git commit -m "fix: replace QUEST_TURNED_IN with hooksecurefunc(GetQuestReward) for pendingTurnIn

  QUEST_TURNED_IN does not fire in TBC Classic (Interface 20505).
  Hook GetQuestReward to set pendingTurnIn[questID] on turn-in confirmation.
  Remove dead QUEST_TURNED_IN registration and handler.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 2: Fix completion detection in runDiff

**Files:**
- Modify: `Absolute-Quest-Log/Core/EventEngine.lua`

**Background:** When a quest is removed from the log, `runDiff` checks `histCache:HasCompleted(questID)` to decide whether to fire `AQL_QUEST_COMPLETED` or `AQL_QUEST_ABANDONED`. The old `QUEST_TURNED_IN` handler called `HistoryCache:MarkCompleted` before the quest disappeared, making `HasCompleted` return true. Now that handler is gone. `WowQuestAPI.IsQuestFlaggedCompleted(questID)` calls `C_QuestLog.IsQuestFlaggedCompleted` — the server-authoritative completion flag — which returns true immediately after the player confirms the turn-in and before `QUEST_REMOVED` fires. This is the correct fallback signal.

**Current state (inside `runDiff`, removed-quest branch, ~lines 115–120):**
```lua
                if histCache and histCache:HasCompleted(questID) then
                    -- Already recorded by the QUEST_TURNED_IN handler before this
                    -- diff ran. MarkCompleted is idempotent so calling it again is
                    -- safe and ensures correctness if QUEST_TURNED_IN was missed.
                    histCache:MarkCompleted(questID)
                    AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
```

- [ ] **Step 1: Update the completion guard in runDiff**

  Find the comment and guard above:

  **Find:**
  ```lua
                if histCache and histCache:HasCompleted(questID) then
                    -- Already recorded by the QUEST_TURNED_IN handler before this
                    -- diff ran. MarkCompleted is idempotent so calling it again is
                    -- safe and ensures correctness if QUEST_TURNED_IN was missed.
                    histCache:MarkCompleted(questID)
                    AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
  ```

  **Replace with:**
  ```lua
                if (histCache and histCache:HasCompleted(questID))
                   or WowQuestAPI.IsQuestFlaggedCompleted(questID) then
                    -- IsQuestFlaggedCompleted is the server-authoritative completion
                    -- flag; it returns true after turn-in, before QUEST_REMOVED fires.
                    -- HasCompleted covers quests completed in previous sessions.
                    -- MarkCompleted is idempotent; the histCache guard is defensive
                    -- (histCache is always non-nil post-login but nil-safety is kept).
                    if histCache then histCache:MarkCompleted(questID) end
                    AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
  ```

- [ ] **Step 2: Verify the edit**

  Read back the `runDiff` function body (~lines 90–150) and confirm:
  - The completion guard now reads `(histCache and histCache:HasCompleted(questID)) or WowQuestAPI.IsQuestFlaggedCompleted(questID)`
  - `MarkCompleted` is called inside `if histCache then ... end`
  - The abandonment/failure logic below the `else` is unchanged

- [ ] **Step 3: Commit**

  ```bash
  git add Absolute-Quest-Log/Core/EventEngine.lua
  git commit -m "fix: use IsQuestFlaggedCompleted to detect quest completion in runDiff

  HasCompleted() returns false for in-session turn-ins because the
  QUEST_TURNED_IN handler (which called MarkCompleted) never fired.
  Add IsQuestFlaggedCompleted as a server-authoritative fallback.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

## In-Game Verification

After both tasks are committed, reload the WoW client with the updated addon and verify all test cases from the spec. Run these in order — each verifies a specific code path.

**Test 1 — Turn-in with item objectives (primary regression test):**
Accept an item-collection quest (e.g., collect 10 of something). Complete it. Open the turn-in NPC. Click Complete Quest and select a reward item. Confirm:
- No regression banner appears while the NPC takes items
- A "Completed" banner appears (not "Abandoned")

**Test 2 — Turn-in without item objectives:**
Accept and complete a kill/escort quest. Turn it in. Confirm: "Completed" banner only.

**Test 3 — Cancel then abandon (critical edge case):**
Accept an item-collection quest. Complete it. Open the NPC reward screen. Close it WITHOUT clicking Complete. Now manually abandon the quest via the quest log. Confirm: "Abandoned" banner fires. No "Completed" banner.

**Test 4 — Genuine objective regression (ensure suppression is scoped):**
Accept an item-collection quest (not yet complete). Pick up some items. Then DROP one item from inventory. Confirm: `AQL_OBJECTIVE_REGRESSED` fires (regression is NOT suppressed — `pendingTurnIn` was never set for this quest).

**Test 5 — Normal abandonment:**
Accept any non-complete quest. Abandon it. Confirm: "Abandoned" banner.

**Test 6 — Login with prior-session completions:**
With any previously turned-in quests in your history, log out then back in. Confirm: no "Accepted" banner fires for historically completed quests.

---

*Spec: `Absolute-Quest-Log/docs/superpowers/specs/2026-03-18-fix-quest-turnin-detection.md`*
