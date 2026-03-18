# Fix: Quest Turn-In Detection — Design Spec

## Overview

Two bugs share one root cause: `QUEST_TURNED_IN` does not fire in TBC Classic
(Interface 20505).

1. **False "Abandoned" banner** — `QUEST_TURNED_IN` is supposed to call
   `HistoryCache:MarkCompleted(questID)` before the quest disappears from the log.
   Because it never fires, `runDiff` sees the quest removed and calls
   `histCache:HasCompleted(questID)`, which returns false, causing
   `AQL_QUEST_ABANDONED` to fire instead of `AQL_QUEST_COMPLETED`.

2. **Spurious objective regression** — `QUEST_TURNED_IN` is also supposed to set
   `EventEngine.pendingTurnIn[questID]`, which suppresses `AQL_OBJECTIVE_REGRESSED`
   while the NPC takes the player's quest items. Because it never fires, the
   suppression is never set and the regression fires on every turn-in.

---

## Root Cause

The WoW TBC Classic client (Interface 20505) does not fire `QUEST_TURNED_IN`.
This is a known engine limitation of this version. The event fires in Retail but
not in the TBC Anniversary client used by this project.

All logic in `EventEngine.lua` that depends on `QUEST_TURNED_IN` is therefore
dead code in the current runtime environment.

---

## Fix

Two targeted changes to `EventEngine.lua`. No other files are modified.

### Change 1 — Replace QUEST_TURNED_IN dependency for `pendingTurnIn`

Hook `GetQuestReward` (the WoW API function the quest frame calls when the player
clicks the final "Complete Quest" / confirm reward button) using
`hooksecurefunc`. This fires synchronously on the same frame the player confirms
the turn-in, before items are transferred. It fires only on actual confirmation,
not on opening the reward screen, and not on cancellation (closing the quest
frame without confirming). The hook survives UI reloads normally because it is
registered at module load time.

`GetQuestID()` returns the questID of the quest currently shown in the quest
interaction frame; it is valid and non-zero at the moment `GetQuestReward` is
called.

```lua
hooksecurefunc("GetQuestReward", function()
    local questID = GetQuestID()
    if questID and questID ~= 0 then
        EventEngine.pendingTurnIn[questID] = true
    end
end)
```

This replaces the `pendingTurnIn` responsibility of `QUEST_TURNED_IN`. The
`QUEST_TURNED_IN` event registration and handler block are **removed** (the
handler is dead code and the `frame:RegisterEvent("QUEST_TURNED_IN")` call is
also removed).

The `pendingTurnIn[questID]` entry is already cleared in `runDiff` when the
quest is removed from the log (`EventEngine.pendingTurnIn[questID] = nil` at
line 114). No change needed there.

### Change 2 — Add `IsQuestFlaggedCompleted` fallback in `runDiff`

The removed-quest branch in `runDiff` checks `histCache:HasCompleted(questID)`
to distinguish a turn-in from an abandonment. Since `MarkCompleted` is no longer
called before the quest disappears (that was the `QUEST_TURNED_IN` handler's
job), this check always returns false for in-session completions.

`WowQuestAPI.IsQuestFlaggedCompleted(questID)` calls
`C_QuestLog.IsQuestFlaggedCompleted(questID)`, which is the server-authoritative
completion flag. It returns `true` immediately after the quest is turned in,
before `QUEST_REMOVED` fires. This is the correct signal to use.

Replace the completion guard:

**Before:**
```lua
if histCache and histCache:HasCompleted(questID) then
    histCache:MarkCompleted(questID)
    AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
else
    -- abandonment / failure logic
end
```

**After:**
```lua
if (histCache and histCache:HasCompleted(questID))
   or WowQuestAPI.IsQuestFlaggedCompleted(questID) then
    if histCache then histCache:MarkCompleted(questID) end
    AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
else
    -- abandonment / failure logic (unchanged)
end
```

`histCache:MarkCompleted(questID)` is idempotent. Calling it for quests that
`HasCompleted` already returned true for is safe and ensures HistoryCache stays
consistent for the rest of the session. The `if histCache then` guard is
defensive: in practice `histCache` is always non-nil when `runDiff` runs (it is
loaded synchronously in `PLAYER_LOGIN` before events are registered and
`initialized` is set to true), but nil-safety is maintained to avoid a Lua
error if the invariant ever breaks.

**Ordering dependency:** `IsQuestFlaggedCompleted` must return `true` at the
point `QUEST_REMOVED` fires (and `runDiff` executes). In TBC Classic, the server
sets the completion flag at the same time it removes the quest from the log;
`QUEST_REMOVED` fires after the log update is applied client-side. This ordering
means the flag is readable when `runDiff` runs. Test case 1 verifies this
end-to-end.

---

## Invariants

- `pendingTurnIn[questID]` is set on the same frame the player confirms the
  turn-in. Any `QUEST_LOG_UPDATE` or `UNIT_QUEST_LOG_CHANGED` that fires during
  item transfer (objectives dropping to zero) will see the flag and suppress
  `AQL_OBJECTIVE_REGRESSED` correctly.
- `pendingTurnIn[questID]` is cleared when the quest is removed from the log
  (existing code, unchanged).
- If the player opens the reward screen and then cancels (closes without
  confirming), `GetQuestReward` is never called, so `pendingTurnIn` is never set.
  A subsequent genuine objective regression on that quest will fire correctly.
- `IsQuestFlaggedCompleted` returns false for abandoned quests (server does not
  mark the quest completed), so the fallback does not promote genuine
  abandonments to completions.
- For quests already completed before this session (login), `HasCompleted`
  returns true and takes priority; `IsQuestFlaggedCompleted` is not needed but
  is also harmlessly true.
- The `QUEST_TURNED_IN` event registration is removed. If Blizzard ever patches
  TBC Classic to fire it, the hook fires first (harmlessly sets the flag again)
  and the handler is gone — behavior is correct either way, though in that
  hypothetical the handler could be re-added.

---

## Files Changed

| File | Change |
|------|--------|
| `Absolute-Quest-Log/Core/EventEngine.lua` | Remove `QUEST_TURNED_IN` event registration and handler; add `hooksecurefunc("GetQuestReward", ...)` at module load time; update `runDiff` completion guard to OR with `WowQuestAPI.IsQuestFlaggedCompleted` |

---

## Testing

1. **Turn-in with item reward choice**: Accept a chain quest that requires item
   collection. Complete objectives. Turn in; select an item reward. Confirm:
   - No regression banner appears.
   - "Completed" banner appears (not "Abandoned").

2. **Turn-in on a quest without item objectives**: Accept and complete a kill
   quest. Turn in. Confirm: "Completed" banner, no spurious output.

3. **Cancel turn-in then abandon**: Accept a quest with item objectives. Complete
   it. Open reward screen. Close it without clicking Complete. Then manually
   abandon the quest. Confirm: "Abandoned" banner fires; no "Completed" banner.

4. **Genuine objective regression**: Accept an item-collection quest. Collect
   some items. Then drop one item from inventory. Confirm:
   `AQL_OBJECTIVE_REGRESSED` fires (regression is not suppressed).

5. **Normal abandonment**: Accept a non-completed quest. Abandon it. Confirm:
   "Abandoned" banner.

6. **Prior-session completions at login**: Log out with a completed quest history.
   Log back in. Confirm: no `AQL_QUEST_ACCEPTED` fires for quests already in the
   completed history (the left-hand `HasCompleted` check still suppresses them at
   the initial cache build). This verifies the existing behavior is not disturbed
   by the OR condition addition.
