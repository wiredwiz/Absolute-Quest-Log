# AQL Enhancement: suggestedGroup + failReason

**Date:** 2026-03-12
**Addon:** AbsoluteQuestLog-1.0 (Interface 20505 — TBC Anniversary)
**Scope:** Two additive enhancements to QuestInfo and the quest failure callback.

---

## Overview

### Feature 1: suggestedGroup

`GetQuestLogTitle()` returns `suggestedGroup` (3rd return value) — the recommended number of players for a quest (0 = solo, 2 = duo, 5 = 5-man, etc.). This value is currently discarded. It will be stored on the QuestInfo snapshot and is accessible to consumers via `AQL:GetQuest(questID).suggestedGroup`.

### Feature 2: failReason

When a quest fails, AQL now infers *why* and stores that reason on QuestInfo as `failReason`. The reason is set when `QUEST_FAILED` fires (before rebuild) and remains on the QuestInfo entry for the lifetime of the failed quest. It is accessible via `newInfo.failReason` in the `AQL_QUEST_FAILED` callback, or via `AQL:GetQuest(questID).failReason` while the quest is still in the log.

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

Capture the 3rd return value of `GetQuestLogTitle()` (previously `_`) as `suggestedGroup` and include it in the `info` table passed to `_buildEntry`.

```lua
local title, level, suggestedGroup, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
-- ...
local info = {
    title          = title,
    level          = level,
    suggestedGroup = suggestedGroup or 0,
    isHeader       = isHeader,
    isComplete     = isComplete,
    questID        = questID,
}
```

**`_buildEntry()`**

1. Add `suggestedGroup = info.suggestedGroup or 0` to the returned QuestInfo table.

2. Replace `self.failedSet[questID] == true` with a truthy check. Read the reason string:

```lua
local isFailed   = self.failedSet[questID] ~= nil
local failReason = type(self.failedSet[questID]) == "string" and self.failedSet[questID] or nil
```

3. Add both fields to the returned table:

```lua
suggestedGroup = info.suggestedGroup or 0,
failReason     = failReason,
```

---

### EventEngine.lua

**`QUEST_FAILED` handler**

Before calling `handleQuestLogUpdate()`, look up the current QuestCache entry (the pre-failure snapshot) and determine the failure reason. Store the reason string in `QuestCache.failedSet[questID]` instead of `true`.

```lua
elseif event == "QUEST_FAILED" then
    local questID = ...
    if questID and type(questID) == "number" then
        -- Determine failure reason from pre-failure snapshot.
        local entry    = AQL.QuestCache and AQL.QuestCache.data[questID]
        local reason   = "unknown"
        if entry then
            if entry.timerSeconds and
               (entry.timerSeconds - (GetTime() - entry.snapshotTime)) <= 0 then
                reason = "timeout"
            elseif entry.type == "escort" then
                reason = "escort_died"
            end
        end
        AQL.QuestCache.failedSet[questID] = reason
    end
    handleQuestLogUpdate()
```

**Note:** When `questID` is not available from the event (TBC may not always provide it), the fallback path still marks the quest failed via the diff on the subsequent `QUEST_LOG_UPDATE`. In that case `failedSet` is not written, so `failReason` will be `nil` (treated as `"unknown"` by consumers).

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
| `Core/QuestCache.lua` | Capture `suggestedGroup`; add `suggestedGroup` + `failReason` to QuestInfo; truthy check on `failedSet` |
| `Core/EventEngine.lua` | Reason detection logic in `QUEST_FAILED` handler |

**Files NOT changed:** `AbsoluteQuestLog.lua`, `Core/HistoryCache.lua`, all Providers. No new public API methods are added — both fields are accessible via the existing `AQL:GetQuest()`.

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| Timed quest fails before timer expires | `failReason = "unknown"` (timer check fails; not escort type) |
| Escort quest with a timer that expires | `"timeout"` takes priority over `"escort_died"` |
| `QUEST_FAILED` fires without questID | `failedSet` not written; quest detected failed via diff; `failReason = nil` |
| Provider unavailable (NullProvider) | `entry.type` is `nil`; escort check fails safely; reason is `"unknown"` |
| Quest not in cache at failure time | `entry` is `nil`; reason is `"unknown"` |
