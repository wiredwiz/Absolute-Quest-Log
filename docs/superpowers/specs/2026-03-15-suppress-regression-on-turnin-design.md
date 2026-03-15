# Suppress Objective Regression on Quest Turn-In — Design Spec

## Problem

When a player turns in a collection quest, `AQL_OBJECTIVE_REGRESSED` fires spuriously. The cause:

1. `QUEST_TURNED_IN` fires **before** `QUEST_LOG_UPDATE` removes the quest from the log.
2. AQL's `QUEST_TURNED_IN` handler calls `handleQuestLogUpdate()` immediately.
3. At that moment the quest still exists in the cache, but its item objectives have already dropped to zero (items handed to the NPC).
4. The diff sees `newN < oldN` and fires `AQL_OBJECTIVE_REGRESSED`.

Consumers such as Social Quest receive this callback and display a regression announcement, which is incorrect — the decrease is a side-effect of the turn-in, not a genuine regression.

## Goal

Suppress `AQL_OBJECTIVE_REGRESSED` for objectives that decrease as part of a quest turn-in. All other callbacks (`AQL_QUEST_COMPLETED`, progression events, etc.) must continue to fire normally.

## Design

**File:** `Core/EventEngine.lua`

Remove the `handleQuestLogUpdate()` call from the `QUEST_TURNED_IN` event branch. Keep `HistoryCache:MarkCompleted(questID)`.

### Why this is safe

`QUEST_LOG_UPDATE` always fires after `QUEST_TURNED_IN`. By the time that event fires, the quest has been removed from the log. The diff's "removed quest" path runs, finds `HistoryCache:HasCompleted(questID) == true` (set by the `QUEST_TURNED_IN` handler above), and fires `AQL_QUEST_COMPLETED` correctly.

Because the quest is absent from the new cache when the `QUEST_LOG_UPDATE` diff runs, the objective diff loop never executes for it — so `AQL_OBJECTIVE_REGRESSED` cannot fire.

### Change

```lua
-- Before
elseif event == "QUEST_TURNED_IN" then
    local questID = ...
    if questID and type(questID) == "number" then
        AQL.HistoryCache:MarkCompleted(questID)
    end
    handleQuestLogUpdate()

-- After
elseif event == "QUEST_TURNED_IN" then
    local questID = ...
    if questID and type(questID) == "number" then
        AQL.HistoryCache:MarkCompleted(questID)
    end
    -- No diff here. QUEST_LOG_UPDATE always follows and runs the diff once
    -- the quest is already removed from the log, so objective counts for
    -- items handed to the NPC never produce AQL_OBJECTIVE_REGRESSED.
```

## Correctness

| Scenario | Before | After |
|---|---|---|
| Turn in collection quest | `AQL_OBJECTIVE_REGRESSED` fires (bug), then `AQL_QUEST_COMPLETED` fires | Only `AQL_QUEST_COMPLETED` fires ✓ |
| Turn in kill/non-item quest | `AQL_QUEST_COMPLETED` fires | `AQL_QUEST_COMPLETED` fires ✓ |
| Genuine mid-quest regression (item destroyed, escort resets) | `AQL_OBJECTIVE_REGRESSED` fires | `AQL_OBJECTIVE_REGRESSED` fires ✓ |
| Quest abandoned | `AQL_QUEST_ABANDONED` fires | `AQL_QUEST_ABANDONED` fires ✓ |

## Testing

1. Accept a collection quest (items required).
2. Collect all required items so the quest is complete.
3. Turn it in.
4. Confirm no `AQL_OBJECTIVE_REGRESSED` fires (no regression announcement in Social Quest chat or banner).
5. Confirm `AQL_QUEST_COMPLETED` fires (completion announcement appears normally).
6. Accept a kill quest, complete it, turn it in — confirm `AQL_QUEST_COMPLETED` fires with no regressions.
7. Accept a collection quest, collect partway, then destroy an item — confirm `AQL_OBJECTIVE_REGRESSED` still fires for this genuine regression.
