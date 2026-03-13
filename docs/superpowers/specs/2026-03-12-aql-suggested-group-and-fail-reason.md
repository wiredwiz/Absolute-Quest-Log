# AQL Enhancement: suggestedGroup + failReason

**Date:** 2026-03-12
**Addon:** AbsoluteQuestLog-1.0 (Interface 20505 — TBC Anniversary)
**Scope:** Two additive enhancements to QuestInfo and the quest failure callback.

---

## Overview

### Feature 1: suggestedGroup

`GetQuestLogTitle()` returns `suggestedGroup` (3rd return value) — the recommended number of players for a quest (0 = solo, 2 = duo, 5 = 5-man, etc.). This value is currently discarded. It will be stored on the QuestInfo snapshot and is accessible to consumers via `AQL:GetQuest(questID).suggestedGroup`.

### Feature 2: failReason

When a quest fails, AQL now infers *why* and stores that reason on QuestInfo as `failReason`. The reason is set when `QUEST_FAILED` fires (before rebuild) and remains on the QuestInfo entry for the lifetime of the failed quest in the log. It is accessible via `newInfo.failReason` in the `AQL_QUEST_FAILED` callback, or via `AQL:GetQuest(questID).failReason` while the quest is still present.

`failedSet` entries are never pruned — they persist for the session. Memory impact is negligible (one string value per quest failure per session).

---

## Data Structures

### QuestInfo — new fields

| Field | Type | Description |
|---|---|---|
| `suggestedGroup` | `number` | Recommended player count from `GetQuestLogTitle()`. `0` means solo. Always present. |
| `failReason` | `string\|nil` | `"timeout"`, `"escort_died"`, or `"unknown"` when quest has failed. `nil` when quest is active/complete. |

---

## Implementation Details

### QuestCache.lua

**`Rebuild()`**

Capture the 3rd return value of `GetQuestLogTitle()` (previously `_`) as `suggestedGroup` and pass it plain (no fallback here) in the `info` table to `_buildEntry`:

```lua
local title, level, suggestedGroup, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
-- ...
local info = {
    title          = title,
    level          = level,
    suggestedGroup = suggestedGroup,   -- nil-safe: _buildEntry applies the or 0 fallback
    isHeader       = isHeader,
    isComplete     = isComplete,
    questID        = questID,
}
```

**`_buildEntry()`**

**Replace** the existing line that sets `isFailed` (currently `local isFailed = self.failedSet[questID] == true`) with this two-line block. The old line must be removed entirely — it evaluates to `false` for string values and would break `isFailed` detection:

```lua
local isFailed   = self.failedSet[questID] ~= nil
local failReason = type(self.failedSet[questID]) == "string" and self.failedSet[questID] or nil
```

Also update the comment on `failedSet` at the top of QuestCache.lua to reflect that values are now reason strings, not `true`:

```lua
-- failedSet[questID] = reason string ("timeout", "escort_died", "unknown") when
-- QUEST_FAILED has fired for that quest. EventEngine writes; QuestCache reads.
```

The `_buildEntry` function signature is unchanged — `suggestedGroup` arrives via the existing `info` table parameter.

Add both new fields to the returned QuestInfo table:

```lua
suggestedGroup = info.suggestedGroup or 0,
failReason     = failReason,
```

---

### EventEngine.lua

**`QUEST_FAILED` handler**

Before calling `handleQuestLogUpdate()`, look up the current QuestCache entry (the pre-failure snapshot) and determine the failure reason. Store the reason string in `QuestCache.failedSet[questID]`.

The timeout check uses `<= 1` (one-second epsilon) rather than `<= 0` to account for the small lag between the last snapshot and event delivery — server-fired timer expiry events arrive within milliseconds, so one second is a safe threshold with no false positives in practice. Note: the formula depends on `snapshotTime` being captured at or immediately after `timerSeconds` is read in `_buildEntry`; both are set synchronously in the same function call so the delta is sub-millisecond:

```lua
elseif event == "QUEST_FAILED" then
    local questID = ...
    if questID and type(questID) == "number" then
        -- Determine failure reason from pre-failure snapshot.
        local entry  = AQL.QuestCache and AQL.QuestCache.data[questID]
        local reason = "unknown"
        if entry then
            if entry.timerSeconds and
               (entry.timerSeconds - (GetTime() - entry.snapshotTime)) <= 1 then
                reason = "timeout"
            elseif entry.type == "escort" then
                reason = "escort_died"
            end
        end
        AQL.QuestCache.failedSet[questID] = reason
    end
    handleQuestLogUpdate()
```

Also update the `failedSet` comment in EventEngine.lua (currently "EventEngine writes to this set") to note that values are reason strings:

```lua
-- EventEngine writes reason strings here ("timeout", "escort_died", "unknown");
-- QuestCache reads during _buildEntry to populate QuestInfo.failReason.
```

**Note:** When `questID` is not available from the event, `failedSet` is not written. The quest is still detected as failed via the diff on the subsequent `QUEST_LOG_UPDATE`; `failReason` will be `nil` in that case.

---

## Callback Impact

### `AQL_QUEST_FAILED`

Signature unchanged: `(questInfo)`. The `questInfo` table now includes `failReason`:

```lua
AQL:RegisterCallback("AQL_QUEST_FAILED", function(questInfo)
    print(questInfo.title .. " failed: " .. (questInfo.failReason or "unknown"))
end)
```

No other callbacks are affected.

---

## Files Changed

| File | Change |
|---|---|
| `Core/QuestCache.lua` | Capture `suggestedGroup` in `Rebuild()`; **replace** `isFailed` local with two-line block in `_buildEntry()`; add `suggestedGroup` + `failReason` to QuestInfo return; update `failedSet` comment |
| `Core/EventEngine.lua` | Reason detection logic in `QUEST_FAILED` handler; update `failedSet` comment |

**Files NOT changed:** `AbsoluteQuestLog.lua`, `Core/HistoryCache.lua`, all Providers. No new public API methods — both fields are accessible via the existing `AQL:GetQuest()`.

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| Escort quest with a timer that expires | `"timeout"` takes priority (timer check runs first) |
| Escort quest fails before its timer expires (escort NPC dies) | `"escort_died"` — requires provider to have typed the quest as `"escort"`; `"unknown"` if provider unavailable |
| Non-escort timed quest fails for non-timeout reason | Theoretically `"unknown"` — no known TBC quest mechanics produce this |
| `QUEST_FAILED` fires without questID | `failedSet` not written; quest detected failed via diff; `failReason = nil` |
| Provider unavailable (NullProvider) | `entry.type` is `nil`; escort check skipped safely; reason is `"unknown"` |
| Provider returns wrong type for escort quest | `"escort_died"` will not fire; reason falls through to `"unknown"` — known limitation of provider dependency |
| Quest not in cache at failure time | `entry` is `nil`; reason is `"unknown"` |
| Failed quest subsequently abandoned | `failedSet[questID]` entry persists (orphaned); no behavioral impact |
