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

The full event sequence after a turn-in on TBC Classic 20505 is:

1. `QUEST_TURNED_IN` — quest still in log, item objectives zeroed. We mark completed in `HistoryCache` and stop. No diff runs.
2. `QUEST_REMOVED` — fires after the quest has been removed from the log. `handleQuestLogUpdate()` runs: `QuestCache:Rebuild()` no longer finds the quest, so the diff takes the "removed quest" path. `HistoryCache:HasCompleted(questID) == true` (set in step 1), so `AQL_QUEST_COMPLETED` fires. No objective diff runs because the quest is absent from the new cache.
3. `QUEST_LOG_UPDATE` — fires after `QUEST_REMOVED`. `QuestCache:Rebuild()` returns an already-updated cache that does not contain the quest. The diff sees no change and fires nothing.

`QUEST_REMOVED` fires only after the quest is fully removed from the log — not while objectives are still readable. This means there is no window in which `QUEST_REMOVED` could trigger a diff with the zeroed-but-still-present quest, so the fix covers all three events in the sequence.

### Change

```lua
-- Before (excerpt — elseif branch inside OnEvent handler)
elseif event == "QUEST_TURNED_IN" then
    local questID = ...
    if questID and type(questID) == "number" then
        AQL.HistoryCache:MarkCompleted(questID)
    end
    handleQuestLogUpdate()   -- ← remove this line

-- After (excerpt — elseif branch inside OnEvent handler)
elseif event == "QUEST_TURNED_IN" then
    local questID = ...
    if questID and type(questID) == "number" then
        AQL.HistoryCache:MarkCompleted(questID)
    end
    -- No diff here. QUEST_REMOVED and QUEST_LOG_UPDATE follow and run the
    -- diff once the quest is already removed from the log, so objective
    -- counts for items handed to the NPC never produce AQL_OBJECTIVE_REGRESSED.
```

## Correctness

| Scenario | Before | After |
|---|---|---|
| Turn in collection quest | `AQL_OBJECTIVE_REGRESSED` fires (bug), then `AQL_QUEST_COMPLETED` fires | Only `AQL_QUEST_COMPLETED` fires ✓ |
| Turn in kill/non-item quest | `AQL_QUEST_COMPLETED` fires | `AQL_QUEST_COMPLETED` fires ✓ |
| Genuine mid-quest regression (item destroyed, escort resets) | `AQL_OBJECTIVE_REGRESSED` fires | `AQL_OBJECTIVE_REGRESSED` fires ✓ |
| Quest abandoned | `AQL_QUEST_ABANDONED` fires | `AQL_QUEST_ABANDONED` fires ✓ |
| Quest failed (escort wipe, timeout) | `AQL_QUEST_FAILED` fires | `AQL_QUEST_FAILED` fires ✓ (unaffected — QUEST_TURNED_IN does not fire for failures) |

## Testing

1. Accept a collection quest (items required).
2. Collect all required items so the quest is complete.
3. Turn it in.
4. Confirm no `AQL_OBJECTIVE_REGRESSED` fires (no regression announcement in Social Quest chat or banner).
5. Confirm `AQL_QUEST_COMPLETED` fires (completion announcement appears normally).
6. Accept a kill quest, complete it, turn it in — confirm `AQL_QUEST_COMPLETED` fires with no regressions.
7. Accept a collection quest, collect partway, then destroy an item — confirm `AQL_OBJECTIVE_REGRESSED` still fires for this genuine regression (Social Quest regression announcement appears in chat).
