# Suppress Objective Regression on Quest Turn-In — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Suppress the spurious `AQL_OBJECTIVE_REGRESSED` callback that fires when item objectives drop to zero during a quest turn-in, while preserving all genuine regression events.

**Architecture:** Add a `pendingTurnIn` flag table to `EventEngine`. Set `pendingTurnIn[questID] = true` in the `QUEST_TURNED_IN` handler (already correctly set up from the prior fix). In `runDiff`, clear the flag when the quest is removed from the log, and skip `AQL_OBJECTIVE_REGRESSED` for quests in the flag set. Single file, four touch points.

**Tech Stack:** Lua 5.1, WoW TBC Classic (Interface 20505), AceAddon-3.0, LibStub. No automated test framework — verification is manual in-game.

---

## Chunk 1: pendingTurnIn flag in Core/EventEngine.lua

### Task 1: Add pendingTurnIn to Core/EventEngine.lua

**Files:**
- Modify: `Core/EventEngine.lua`
  - Touch point 1: initialization block (~line 21) — add `EventEngine.pendingTurnIn = {}`
  - Touch point 2: `QUEST_TURNED_IN` handler (~line 224) — set `pendingTurnIn[questID] = true`
  - Touch point 3: `runDiff` removed-quest loop (~line 82) — clear `pendingTurnIn[questID]`
  - Touch point 4: `runDiff` objective diff (~line 170) — guard `AQL_OBJECTIVE_REGRESSED`

**Background for the implementer:**

A prior fix (`fc208e9`) removed `handleQuestLogUpdate()` from the `QUEST_TURNED_IN`
handler. That correctly eliminated one trigger, but `UNIT_QUEST_LOG_CHANGED` (for the
player) and `QUEST_LOG_UPDATE` still fire while the quest is in the log but item
objectives are zeroed. Those events call `handleQuestLogUpdate()`, which diffs the
cache, sees `numFulfilled` drop from e.g. 10 to 0, and fires `AQL_OBJECTIVE_REGRESSED`
spuriously.

The fix: track a `pendingTurnIn` set. When `QUEST_TURNED_IN` fires, add the quest to
the set. When `runDiff` detects the quest has been removed from the log, remove it.
Any regression event for a quest in the set is silently dropped — the objectives only
dropped because the NPC took them, not because of a real regression.

**Current state of the file (read before editing):**

File: `D:\Projects\Wow Addons\Absolute-Quest-Log\Core\EventEngine.lua`

Lines 21–22 (initialization block):
```lua
EventEngine.diffInProgress   = false
EventEngine.initialized      = false
```

Lines 224–238 (`QUEST_TURNED_IN` handler — already has the prior fix applied):
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
    -- In TBC Classic, QUEST_TURNED_IN passes: questID, xpReward, moneyReward.
    local questID = ...
    if questID and type(questID) == "number" then
        AQL.HistoryCache:MarkCompleted(questID)
    end
```

Lines 82–121 (removed-quest detection loop inside `runDiff`):
```lua
        -- Detect removed quests (in old, not in new).
        for questID, oldInfo in pairs(oldCache) do
            if not newCache[questID] then
                -- Quest was removed from the log.
                if histCache and histCache:HasCompleted(questID) then
                    ...
                    AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
                else
                    ...
                end
            end
        end
```

Lines 158–175 (objective diff inside `runDiff`):
```lua
                for i, newObj in ipairs(newObjs) do
                    local oldObj = oldObjs[i]
                    if oldObj then
                        local newN = newObj.numFulfilled
                        local oldN = oldObj.numFulfilled
                        if newN > oldN then
                            local delta = newN - oldN
                            AQL.callbacks:Fire("AQL_OBJECTIVE_PROGRESSED", newInfo, newObj, delta)
                            if newN >= newObj.numRequired and oldN < newObj.numRequired then
                                AQL.callbacks:Fire("AQL_OBJECTIVE_COMPLETED", newInfo, newObj)
                            end
                        elseif newN < oldN then
                            local delta = oldN - newN
                            AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)
                        end
                    end
                end
```

- [ ] **Step 1: Add `pendingTurnIn` initialization (touch point 1)**

Open `Core/EventEngine.lua`. Find lines 21–22:
```lua
EventEngine.diffInProgress   = false
EventEngine.initialized      = false
```

Replace with:
```lua
EventEngine.diffInProgress   = false
EventEngine.initialized      = false
EventEngine.pendingTurnIn    = {}  -- questIDs currently between QUEST_TURNED_IN and QUEST_REMOVED
```

- [ ] **Step 2: Set the flag in the `QUEST_TURNED_IN` handler (touch point 2)**

Find the `elseif event == "QUEST_TURNED_IN" then` block. The block currently ends:
```lua
    local questID = ...
    if questID and type(questID) == "number" then
        AQL.HistoryCache:MarkCompleted(questID)
    end
```

Replace with:
```lua
    local questID = ...
    if questID and type(questID) == "number" then
        EventEngine.pendingTurnIn[questID] = true
        AQL.HistoryCache:MarkCompleted(questID)
    end
```

Update the comment in the same block to mention `pendingTurnIn`. Replace the comment block that begins `-- Pre-mark the quest as completed` with:
```lua
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
```

- [ ] **Step 3: Clear the flag when the quest is removed (touch point 3)**

Inside `runDiff`, find the removed-quest loop. The first line inside the `if not newCache[questID] then` block currently reads:
```lua
                -- Quest was removed from the log.
                if histCache and histCache:HasCompleted(questID) then
```

Add the flag clear immediately after the comment:
```lua
                -- Quest was removed from the log.
                EventEngine.pendingTurnIn[questID] = nil
                if histCache and histCache:HasCompleted(questID) then
```

- [ ] **Step 4: Guard `AQL_OBJECTIVE_REGRESSED` (touch point 4)**

Inside `runDiff`, in the objective diff loop, find:
```lua
                        elseif newN < oldN then
                            local delta = oldN - newN
                            AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)
```

Replace with:
```lua
                        elseif newN < oldN then
                            -- Suppress regression during turn-in window: objective drop
                            -- is the NPC taking items, not a genuine regression.
                            if not EventEngine.pendingTurnIn[questID] then
                                local delta = oldN - newN
                                AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)
                            end
```

- [ ] **Step 5: Verify the full file is intact**

Re-read `Core/EventEngine.lua` and confirm:
- `EventEngine.pendingTurnIn = {}` is present in the initialization block alongside `diffInProgress` and `initialized`
- `EventEngine.pendingTurnIn[questID] = true` is inside the `if questID and type(questID) == "number" then` guard in `QUEST_TURNED_IN`
- `EventEngine.pendingTurnIn[questID] = nil` is the first statement inside `if not newCache[questID] then` in the removed-quest loop
- `if not EventEngine.pendingTurnIn[questID] then` wraps the `AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", ...)` call
- The closing `end` count is balanced — no dangling `end`s, no missing `end`s

- [ ] **Step 6: Commit**

```bash
cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
git add "Core/EventEngine.lua"
git commit -m "fix: suppress AQL_OBJECTIVE_REGRESSED during quest turn-in window

After QUEST_TURNED_IN fires, UNIT_QUEST_LOG_CHANGED and QUEST_LOG_UPDATE
can still fire while the quest is in the log but item objectives are
zeroed. Add pendingTurnIn flag (set on QUEST_TURNED_IN, cleared on
QUEST_REMOVED) and skip AQL_OBJECTIVE_REGRESSED for quests in the set.
Genuine mid-quest regressions are unaffected."
```

---

## Manual Verification Checklist

These steps cannot be automated (no test framework for WoW Lua). Perform them in-game after loading the updated addon. Enable Social Quest with `displayOwn = true` (or use a party member) to see announcement banners.

**Test A — Turn-in no longer shows regression (the bug fix)**
- [ ] Accept a collection quest that requires items (e.g. "Collect 5 Wolf Paws").
- [ ] Collect all required items so the quest shows as complete.
- [ ] Turn the quest in to the NPC.
- [ ] Confirm: **no** regression announcement or banner appears.
- [ ] Confirm: completion announcement / banner appears normally.

**Test B — Kill quest turn-in is unaffected**
- [ ] Accept a kill-objective quest.
- [ ] Complete it and turn it in.
- [ ] Confirm: completion fires, no regression fires.

**Test C — Genuine mid-quest regression still fires**
- [ ] Accept a collection quest and collect some (but not all) required items.
- [ ] Delete one of the collected items from your bags.
- [ ] Confirm: Social Quest regression announcement appears (proving `AQL_OBJECTIVE_REGRESSED` still fires for real regressions).
