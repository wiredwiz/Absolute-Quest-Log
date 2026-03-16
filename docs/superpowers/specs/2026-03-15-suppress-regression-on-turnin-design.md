# Suppress Objective Regression on Quest Turn-In — Design Spec

## Problem

When a player turns in a collection quest, `AQL_OBJECTIVE_REGRESSED` fires spuriously
before `AQL_QUEST_COMPLETED`. Social Quest receives the callback and shows a regression
announcement that is incorrect — the objective decrease is a side-effect of the NPC
taking the items, not a genuine regression.

## Root Cause

The actual TBC Classic event order after turning in a collection quest is:

1. `QUEST_TURNED_IN` — quest still in log, item objectives already zeroed (items handed to NPC)
2. `UNIT_QUEST_LOG_CHANGED` (unit = "player") — fires while quest is still in log
3. `QUEST_LOG_UPDATE` — fires while quest is still in log
4. `QUEST_REMOVED` — quest removed from log
5. `QUEST_LOG_UPDATE` — fires after quest is gone

A prior fix (`fc208e9`) correctly removed the `handleQuestLogUpdate()` call from the
`QUEST_TURNED_IN` handler, eliminating that specific trigger. However, steps 2 and 3
above still fire `handleQuestLogUpdate()`. Because the quest is still present in the
cache at that point (step 4 hasn't fired yet), the diff runs with the quest present
but item objectives at 0 vs. the prior snapshot of e.g. 10/10, and fires
`AQL_OBJECTIVE_REGRESSED` spuriously.

## Goal

Suppress `AQL_OBJECTIVE_REGRESSED` for the turn-in window (QUEST_TURNED_IN through
QUEST_REMOVED). All other events must continue to fire normally.

## Design

**File:** `Core/EventEngine.lua` only.

### Approach: `pendingTurnIn` flag

Track a set of quest IDs that are in the turn-in window. The diff skips regression
events for these quests. The flag is cleared when the quest is detected as removed.

**No new files. No new data structures beyond the flag table.**

### Changes

**1. Initialize flag table** (alongside `diffInProgress` and `initialized`):
```lua
EventEngine.pendingTurnIn = {}
```

**2. Set flag in `QUEST_TURNED_IN` handler:**
```lua
elseif event == "QUEST_TURNED_IN" then
    local questID = ...
    if questID and type(questID) == "number" then
        EventEngine.pendingTurnIn[questID] = true   -- ← add this
        AQL.HistoryCache:MarkCompleted(questID)
    end
    -- (no handleQuestLogUpdate call — already removed by fc208e9)
```

**3. Clear flag in `runDiff` when quest is removed from log:**
```lua
for questID, oldInfo in pairs(oldCache) do
    if not newCache[questID] then
        EventEngine.pendingTurnIn[questID] = nil   -- ← add this
        if histCache and histCache:HasCompleted(questID) then
            ...
```

**4. Guard `AQL_OBJECTIVE_REGRESSED` in the objective diff:**
```lua
elseif newN < oldN then
    if not EventEngine.pendingTurnIn[questID] then   -- ← add guard
        local delta = oldN - newN
        AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)
    end
end
```

### Why this is safe

- The flag is set synchronously in `QUEST_TURNED_IN` and cleared the moment the quest
  leaves the cache in the next `runDiff` call (triggered by `QUEST_REMOVED`).
- No memory leak: `QUEST_REMOVED` always fires after `QUEST_TURNED_IN`.
- Genuine mid-quest regressions (item destroyed before turn-in, escort reset) are
  unaffected: those happen when no `QUEST_TURNED_IN` has fired for the quest.

## Correctness

| Scenario | Before fix | After fix |
|---|---|---|
| Turn in collection quest | Regression fires, then completion fires (bug) | Only completion fires ✓ |
| Turn in kill/non-item quest | Completion fires | Completion fires ✓ |
| Genuine mid-quest regression (destroy item, escort resets) | Regression fires | Regression fires ✓ |
| Quest abandoned | Abandoned fires | Abandoned fires ✓ |
| Quest failed (timeout, escort wipe) | Failed fires | Failed fires ✓ |

## Testing

1. Accept a collection quest (items required).
2. Collect all required items so the quest is flagged complete.
3. Turn it in at the NPC.
4. Confirm no regression announcement appears in Social Quest chat or banner.
5. Confirm a completion announcement appears normally.
6. Accept a kill quest, complete it, turn in — confirm completion fires, no regression.
7. Accept a collection quest, collect partway, then destroy an item — confirm regression
   announcement still fires for this genuine regression.
