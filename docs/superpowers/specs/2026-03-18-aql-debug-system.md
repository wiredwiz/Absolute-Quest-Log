# AQL Debug System — Design Spec

## Overview

Add a `/aql` slash command to AbsoluteQuestLog that toggles a debug logging mode, with two
verbosity levels. Debug output is printed to the default chat frame using a gold prefix so
it is visually distinct from normal chat without being confused with error messages (red).

---

## Debug State

`AQL.debug` changes from an uninitialized optional boolean to a string sentinel:

| Value | Meaning |
|-------|---------|
| `nil` | Off — default, never initialized |
| `"normal"` | Normal debug mode |
| `"verbose"` | Verbose debug mode |

`nil` is falsy in Lua 5.1, so the existing `if AQL.debug then` checks in EventEngine.lua
and QuestCache.lua continue to work correctly — they fire whenever any debug level is
active. Verbose-only messages use `if AQL.debug == "verbose" then`.

---

## Slash Command

Registered in `AbsoluteQuestLog.lua` at the bottom of the file (after all public API
definitions), using vanilla WoW slash command registration:

```lua
SLASH_ABSOLUTEQUESTLOG1 = "/aql"
SlashCmdList["ABSOLUTEQUESTLOG"] = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "on" or cmd == "normal" then
        AQL.debug = "normal"
        print(AQL.DBG .. "[AQL] Debug mode: normal" .. AQL.RESET)
    elseif cmd == "verbose" then
        AQL.debug = "verbose"
        print(AQL.DBG .. "[AQL] Debug mode: verbose" .. AQL.RESET)
    elseif cmd == "off" then
        AQL.debug = nil
        print(AQL.DBG .. "[AQL] Debug mode: off" .. AQL.RESET)
    else
        print(AQL.DBG .. "[AQL] Usage: /aql [on|normal|verbose|off]" .. AQL.RESET)
    end
end
```

`/aql on` and `/aql normal` are equivalent — both set `"normal"`. The command is
session-only; debug state resets to `nil` on UI reload.

---

## Color Constant

A new constant `AQL.DBG` is added to `AbsoluteQuestLog.lua` alongside `AQL.RED` and
`AQL.RESET`:

```lua
AQL.DBG   = "|cFFFFD200"   -- gold (colorblind-safe, distinct from errors and chat text)
```

All debug print statements use `AQL.DBG .. "[AQL] <message>" .. AQL.RESET`. Existing
error prints continue using `AQL.RED`.

---

## Debug Messages

### Normal level — `if AQL.debug then`

Fires whenever `AQL.debug` is `"normal"` or `"verbose"`.

#### `AbsoluteQuestLog.lua`

The slash command handler itself prints mode confirmation (shown above). No other normal-level
messages in this file.

#### `Core/EventEngine.lua`

**Provider selection (`selectProvider` / PLAYER_LOGIN handler):**

The PLAYER_LOGIN handler already captures the second return value of `selectProvider()`:
```lua
local provider, providerName = selectProvider()
```
After `AQL.provider = provider`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Provider selected: " .. tostring(providerName) .. AQL.RESET)
end
```

**Provider upgrade (`tryUpgradeProvider`):**

`tryUpgradeProvider` currently discards the `providerName` second return from `selectProvider()`.
Change `local provider = selectProvider()` to `local provider, providerName = selectProvider()`
so the name is available for logging. On a successful upgrade (provider ~= NullProvider),
add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Provider upgraded: " .. tostring(providerName) .. AQL.RESET)
end
```
On each retry attempt (attemptsLeft > 0, upgrade not yet found), add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Provider upgrade attempt " ..
          tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS - attemptsLeft + 1) ..
          "/" .. tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS) ..
          " — still on NullProvider" .. AQL.RESET)
end
```

**`handleQuestLogUpdate` — inline provider upgrade:**

`handleQuestLogUpdate` contains a belt-and-suspenders provider upgrade check that currently
discards `providerName`. Change `local provider = selectProvider()` to
`local provider, providerName = selectProvider()` (removing the adjacent comment that says
providerName is intentionally discarded). On a successful upgrade, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Provider upgraded (inline): " .. tostring(providerName) .. AQL.RESET)
end
```

**WoW events received:**

In the OnEvent handler, at the top of each handled branch, print the event name at normal
level. For clarity, a single helper is used at the top of the OnEvent handler:

```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Event: " .. tostring(event) .. AQL.RESET)
end
```

This single line covers all events. At normal level it logs:
QUEST_LOG_UPDATE, QUEST_ACCEPTED, QUEST_REMOVED, QUEST_WATCH_LIST_CHANGED, and the
player-branch of UNIT_QUEST_LOG_CHANGED (since those call `handleQuestLogUpdate`).
UNIT_QUEST_LOG_CHANGED for non-player units also prints at this level.

**`hooksecurefunc("GetQuestReward", ...)` — pendingTurnIn set:**

After `EventEngine.pendingTurnIn[questID] = true`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] pendingTurnIn set: questID=" .. tostring(questID) .. AQL.RESET)
end
```

**`runDiff` — quest accepted:**

After `AQL.callbacks:Fire("AQL_QUEST_ACCEPTED", newInfo)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Quest accepted: " .. tostring(questID) ..
          " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
end
```

**`runDiff` — pendingTurnIn cleared:**

After `EventEngine.pendingTurnIn[questID] = nil` (in the removed-quest branch), add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] pendingTurnIn cleared: questID=" .. tostring(questID) .. AQL.RESET)
end
```

**`runDiff` — quest completed:**

After `AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Quest completed: " .. tostring(questID) ..
          " \"" .. tostring(oldInfo.title) .. "\"" .. AQL.RESET)
end
```

**`runDiff` — quest failed (removed-quest branch):**

After `AQL.callbacks:Fire("AQL_QUEST_FAILED", oldInfo)` in the removed-quest branch
(timer/escort heuristic path), add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Quest failed: " .. tostring(questID) ..
          " \"" .. tostring(oldInfo.title) .. "\" reason=" .. tostring(failReason) .. AQL.RESET)
end
```
Then, inside the `for _, obj in ipairs(oldInfo.objectives or {}) do` loop that follows
(the one that fires `AQL_OBJECTIVE_FAILED`), after each
`AQL.callbacks:Fire("AQL_OBJECTIVE_FAILED", oldInfo, obj)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Objective failed: " .. tostring(questID) ..
          " \"" .. tostring(obj.text or "") .. "\"" .. AQL.RESET)
end
```

**`runDiff` — quest failed (isFailed transition in existing quests):**

`runDiff` also detects `isFailed` transitions in the existing-quests loop (when
`newInfo.isFailed and not oldInfo.isFailed`). After
`AQL.callbacks:Fire("AQL_QUEST_FAILED", newInfo)` in that branch, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Quest failed (isFailed): " .. tostring(questID) ..
          " \"" .. tostring(newInfo.title) .. "\"" ..
          (newInfo.failReason and (" reason=" .. tostring(newInfo.failReason)) or "") .. AQL.RESET)
end
```
Then, inside the `for _, obj in ipairs(newInfo.objectives or {}) do` loop that follows
in that same branch, after each `AQL.callbacks:Fire("AQL_OBJECTIVE_FAILED", newInfo, obj)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Objective failed: " .. tostring(questID) ..
          " \"" .. tostring(obj.text or "") .. "\"" .. AQL.RESET)
end
```

**`runDiff` — quest abandoned:**

After `AQL.callbacks:Fire("AQL_QUEST_ABANDONED", oldInfo)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Quest abandoned: " .. tostring(questID) ..
          " \"" .. tostring(oldInfo.title) .. "\"" .. AQL.RESET)
end
```

**`runDiff` — quest finished (ready to turn in):**

After `AQL.callbacks:Fire("AQL_QUEST_FINISHED", newInfo)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Quest finished (ready to turn in): " .. tostring(questID) ..
          " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
end
```

**`runDiff` — objective progressed:**

After `AQL.callbacks:Fire("AQL_OBJECTIVE_PROGRESSED", newInfo, newObj, delta)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Objective progressed: " .. tostring(questID) ..
          " obj[" .. tostring(i) .. "] " ..
          tostring(newObj.numFulfilled) .. "/" .. tostring(newObj.numRequired) .. AQL.RESET)
end
```

**`runDiff` — objective completed:**

After `AQL.callbacks:Fire("AQL_OBJECTIVE_COMPLETED", newInfo, newObj)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Objective completed: " .. tostring(questID) ..
          " obj[" .. tostring(i) .. "]" .. AQL.RESET)
end
```

**`runDiff` — objective regressed:**

After `AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)`, add:
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Objective regressed: " .. tostring(questID) ..
          " obj[" .. tostring(i) .. "] " ..
          tostring(newObj.numFulfilled) .. "/" .. tostring(newObj.numRequired) .. AQL.RESET)
end
```

**`runDiff` — objective regression suppressed:**

In the `elseif newN < oldN then` branch, the suppression check is:
```lua
if not EventEngine.pendingTurnIn[questID] then
    -- fire regressed
else
    -- suppressed
end
```
Add in the suppressed path (when `EventEngine.pendingTurnIn[questID]` is set):
```lua
if AQL.debug then
    print(AQL.DBG .. "[AQL] Objective regression suppressed (pendingTurnIn): " ..
          tostring(questID) .. " obj[" .. tostring(i) .. "]" .. AQL.RESET)
end
```

#### `Core/QuestCache.lua`

**Rebuild summary — end of Phase 3:**

After the Phase 3 loop completes (all entries built into `new`), before Phase 4, add:
```lua
if AQL.debug then
    local count = 0
    for _ in pairs(new) do count = count + 1 end
    print(AQL.DBG .. "[AQL] QuestCache rebuilt: " .. tostring(count) .. " quests" .. AQL.RESET)
end
```

---

### Verbose level — `if AQL.debug == "verbose" then`

Fires only when `AQL.debug` is `"verbose"`.

#### `Core/EventEngine.lua`

**`runDiff` — entry:**

At the very top of `runDiff`, after the re-entrancy check, add:
```lua
if AQL.debug == "verbose" then
    local oldCount, newCount = 0, 0
    for _ in pairs(oldCache) do oldCount = oldCount + 1 end
    for _ in pairs(AQL.QuestCache.data) do newCount = newCount + 1 end
    print(AQL.DBG .. "[AQL] runDiff: start — old=" .. tostring(oldCount) ..
          " new=" .. tostring(newCount) .. " quests" .. AQL.RESET)
end
```

**`runDiff` — exit:**

Immediately before `EventEngine.diffInProgress = false`, add:
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] runDiff: done" .. AQL.RESET)
end
```

**`runDiff` — re-entrancy guard:**

Change the existing guard at the top of `runDiff` from:
```lua
if EventEngine.diffInProgress then return end
```
to:
```lua
if EventEngine.diffInProgress then
    if AQL.debug == "verbose" then
        print(AQL.DBG .. "[AQL] runDiff: skipped (already in progress)" .. AQL.RESET)
    end
    return
end
```

**`handleQuestLogUpdate` — initialized guard:**

Change:
```lua
if not EventEngine.initialized then return end
```
to:
```lua
if not EventEngine.initialized then
    if AQL.debug == "verbose" then
        print(AQL.DBG .. "[AQL] Event received before init, skipping" .. AQL.RESET)
    end
    return
end
```

**`runDiff` — isTracked transitions:**

After `AQL.callbacks:Fire("AQL_QUEST_TRACKED", newInfo)`, add:
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] Quest tracked: " .. tostring(questID) ..
          " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
end
```
After `AQL.callbacks:Fire("AQL_QUEST_UNTRACKED", newInfo)`, add:
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] Quest untracked: " .. tostring(questID) ..
          " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
end
```

#### `Core/QuestCache.lua`

**Phase markers:**

At the start of each phase (using the existing comments as anchors), add:

Phase 1 start:
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] QuestCache: phase 1 — collecting collapsed headers" .. AQL.RESET)
end
```
After Phase 1 (before Phase 2), print the count:
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] QuestCache: phase 1 — " .. tostring(#collapsedHeaders) ..
          " collapsed headers found" .. AQL.RESET)
end
```
Phase 2 start:
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] QuestCache: phase 2 — expanding headers" .. AQL.RESET)
end
```
Phase 3 start:
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] QuestCache: phase 3 — building entries" .. AQL.RESET)
end
```
Phase 4 start (if there are headers to collapse):
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] QuestCache: phase 4 — re-collapsing headers" .. AQL.RESET)
end
```
Phase 5 start:
```lua
if AQL.debug == "verbose" then
    print(AQL.DBG .. "[AQL] QuestCache: phase 5 — restoring selection" .. AQL.RESET)
end
```

**Per-entry detail:**

At the end of `_buildEntry`, just before the `return { ... }` statement, add:
```lua
if AQL.debug == "verbose" then
    local objCount = 0
    for _ in ipairs(objectives) do objCount = objCount + 1 end
    print(AQL.DBG .. "[AQL] QuestCache: built questID=" .. tostring(questID) ..
          " \"" .. tostring(info.title or "") .. "\"" ..
          " zone=\"" .. tostring(zone or "") .. "\"" ..
          " objs=" .. tostring(objCount) .. AQL.RESET)
end
```

---

## Files Changed

| File | Change |
|------|--------|
| `Absolute-Quest-Log/AbsoluteQuestLog.lua` | Add `AQL.DBG` color constant; register `/aql` slash command at end of file |
| `Absolute-Quest-Log/Core/EventEngine.lua` | Add normal + verbose debug prints throughout; capture `providerName` in `tryUpgradeProvider` |
| `Absolute-Quest-Log/Core/QuestCache.lua` | Add normal + verbose debug prints in `Rebuild` and `_buildEntry` |

---

## Testing

1. **`/aql on`:** Confirm `[AQL] Debug mode: normal` prints in gold text.
2. **`/aql verbose`:** Confirm `[AQL] Debug mode: verbose` prints.
3. **`/aql off`:** Confirm `[AQL] Debug mode: off` prints, and no further `[AQL]` output appears.
4. **`/aql` (no args):** Confirm usage line prints.
5. **Normal mode — accept a quest:** Confirm `[AQL] Quest accepted: <id> "<title>"` appears.
6. **Normal mode — complete a quest:** Confirm `[AQL] Quest completed: <id> "<title>"` appears. No `Abandoned` line.
7. **Normal mode — turn in with item objectives:** Confirm `[AQL] pendingTurnIn set:` and `[AQL] Objective regression suppressed` appear. No `Objective regressed` line.
8. **Normal mode — abandon a quest:** Confirm `[AQL] Quest abandoned:` appears.
9. **Verbose mode — reload UI:** Confirm phase markers appear during cache rebuild (they fire on every rebuild, not only the initial one — reloading the UI is a convenient trigger for the first rebuild).
10. **Verbose mode — any event:** Confirm `[AQL] runDiff: start` / `done` lines bracket each diff.
11. **Verbose mode — track a quest:** Confirm `[AQL] Quest tracked:` and `[AQL] Quest untracked:` lines appear on toggle.
