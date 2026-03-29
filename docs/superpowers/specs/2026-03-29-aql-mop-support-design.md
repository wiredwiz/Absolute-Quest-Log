# AQL MoP Classic Support — Design Spec

**Date:** 2026-03-29
**Repo:** Absolute-Quest-Log
**Feature:** MoP Classic (5.x) explicit support — IsUnitOnQuest MoP branch + QUEST_TURNED_IN event registration

---

## Goal

Make MoP Classic (5.x) fully functional in AQL. Two behavioral gaps exist on MoP clients that are not covered by the Foundation or Classic Era sub-projects:

1. `WowQuestAPI.IsUnitOnQuest` returns `nil` on MoP even though the global `IsUnitOnQuest(logIndex, unit)` is available. Fix: add a MoP branch that resolves `questID → logIndex` via the existing `WowQuestAPI.GetQuestLogIndex`, then calls the global.

2. Turn-in detection on MoP uses only the `GetQuestReward` hook (carried over from TBC). MoP fires `QUEST_TURNED_IN` natively. Fix: register and handle the event to set `pendingTurnIn`, which is the stable public-API approach. Keep the hook for TBC clients where the event does not fire.

No AQL callback double-firing risk: `QUEST_TURNED_IN` only sets `pendingTurnIn[questID]` — it does not call `handleQuestLogUpdate`. The diff that fires `AQL_QUEST_COMPLETED` is triggered solely by `QUEST_REMOVED`, which fires after `QUEST_TURNED_IN` and removes the quest from the log. One diff, one callback.

---

## Context

### Version detection constants (already in place)

```lua
-- Core/WowQuestAPI.lua
local IS_CLASSIC_ERA = _TOC <  20000
local IS_TBC         = _TOC >= 20000 and _TOC < 30000
local IS_MOP         = _TOC >= 50000 and _TOC < 60000
local IS_RETAIL      = _TOC >= 100000
```

### IsUnitOnQuest API availability (from api-compatibility.md)

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x |
|---|---|---|---|---|
| `IsUnitOnQuest(logIndex, unit)` | ✓ | ✗ | ✓ | ~ (renamed) |

MoP: global `IsUnitOnQuest(logIndex, unit)` is available. The existing `WowQuestAPI.GetQuestLogIndex(questID)` converts questID → logIndex. Returns nil when the quest is not in the player's log (collapsed or absent).

### QUEST_TURNED_IN event availability (from api-compatibility.md)

| Event | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x |
|---|---|---|---|---|
| `QUEST_TURNED_IN` | ✓ | ✗ | ✓ | ✓ |

Args: `(questID, xpReward, moneyReward)`. Does not fire on TBC (runtime-tested). Registering it unconditionally is safe — on TBC it simply never fires.

### Current GetQuestReward hook (EventEngine.lua lines 49–57)

```lua
hooksecurefunc("GetQuestReward", function()
    local questID = GetQuestID()
    if questID and questID ~= 0 then
        EventEngine.pendingTurnIn[questID] = true
    end
end)
```

This fires on all versions. On MoP, both this hook and `QUEST_TURNED_IN` will set `pendingTurnIn` — idempotent, harmless. The hook is kept for TBC compatibility. Update its comment to state it handles TBC; the event handles MoP/Classic Era/Retail.

---

## Deliverable 1 — WowQuestAPI.lua: IsUnitOnQuest MoP branch

### File modified: `Core/WowQuestAPI.lua`

#### Current code (lines 155–163)

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

#### Replacement

```lua
if IS_RETAIL then
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return UnitIsOnQuest(unit, questID)
    end
elseif IS_MOP then
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
        if not logIndex then return nil end
        return IsUnitOnQuest(logIndex, unit) == true
    end
else
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return nil
    end
end
```

**Why not `IS_CLASSIC_ERA` here:** Classic Era also has `IsUnitOnQuest(logIndex, unit)` (api-compatibility.md shows ✓). However, the IsUnitOnQuest wrapper comment already says "Returns nil on TBC/Classic" and the Classic Era sub-project confirmed no change was needed there. Classic Era support for `IsUnitOnQuest` is deferred — this sub-project adds MoP only.

#### Header comment update (lines 148–153)

Current:
```lua
-- WowQuestAPI.IsUnitOnQuest(questID, unit)
-- Returns bool on Retail (UnitIsOnQuest exists).
-- Returns nil on TBC/Classic (API does not exist).
-- Note: parameter order is (questID, unit) — the opposite of the WoW
-- global UnitIsOnQuest(unit, questID) — to keep questID-first convention.
```

Replace with:
```lua
-- WowQuestAPI.IsUnitOnQuest(questID, unit)
-- Returns bool on Retail and MoP.
-- Returns nil on TBC/Classic Era (API does not exist on TBC; deferred on Classic Era).
-- MoP: resolves questID → logIndex via GetQuestLogIndex, then calls IsUnitOnQuest(logIndex, unit).
-- Returns nil on MoP if the quest is not in the player's log (collapsed or absent).
-- Note: parameter order is (questID, unit) — the opposite of the WoW
-- global UnitIsOnQuest(unit, questID) — to keep questID-first convention.
```

---

## Deliverable 2 — WowQuestAPI.lua: GetQuestInfo else-branch comment cleanup

### File modified: `Core/WowQuestAPI.lua`

The `GetQuestInfo` else-branch comment currently reads:

```lua
else  -- IS_TBC, IS_CLASSIC_ERA, and IS_MOP (same log-scan API; MoP sub-project handles MoP-specific improvements)
```

Update to remove the deferred language (this sub-project fulfills that promise):

```lua
else  -- IS_TBC, IS_CLASSIC_ERA, and IS_MOP (same log-scan API on all three versions)
```

---

## Deliverable 3 — EventEngine.lua: QUEST_TURNED_IN registration and handler

### File modified: `Core/EventEngine.lua`

#### Change 1: Update GetQuestReward hook comment (lines 42–48)

Current comment block:
```lua
-- QUEST_TURNED_IN does not fire in TBC Classic (Interface 20505).
-- Hook GetQuestReward instead: it fires synchronously when the player clicks
-- the confirm button, before items are transferred. GetQuestID() returns the
-- active questID at this point. This sets pendingTurnIn so that any objective
-- regression events fired during item transfer are suppressed.
-- The hook fires only on confirmation; cancelling the reward screen does not
-- call GetQuestReward, so pendingTurnIn is never set on cancel.
```

Replace with:
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

#### Change 2: Register QUEST_TURNED_IN in PLAYER_LOGIN handler

Current event registration block (lines 407–411):
```lua
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
```

Replace with:
```lua
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
```

#### Change 3: Add QUEST_TURNED_IN handler branch

The `OnEvent` handler currently ends with (lines 441–444):
```lua
    elseif event == "QUEST_WATCH_LIST_CHANGED"
        or event == "QUEST_LOG_UPDATE" then
        handleQuestLogUpdate()
    end
```

Insert a new branch **before** the `QUEST_WATCH_LIST_CHANGED` branch:
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

---

## Files Modified

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | Add MoP branch to `IsUnitOnQuest`; update header comment; clean up `GetQuestInfo` else-branch deferred language |
| `Core/EventEngine.lua` | Update `GetQuestReward` hook comment; register `QUEST_TURNED_IN`; add event handler branch |
| `AbsoluteQuestLog.toc` + four version tocs | Version bump to 2.5.2 |
| `CLAUDE.md` | Add version 2.5.2 entry |

## Not In Scope

- Classic Era `IsUnitOnQuest` support (deferred — its API signature is the same as MoP but was not in scope for the Classic Era sub-project; address in a future pass)
- Retail support (separate sub-project)
- Provider implementation changes
- Any other EventEngine behavioral changes

---

## Success Criteria

1. On MoP clients, `WowQuestAPI.IsUnitOnQuest(questID, unit)` returns a bool when the quest is in the player's log, and nil when it is not.
2. On MoP clients, completing a quest sets `pendingTurnIn` via `QUEST_TURNED_IN` before `QUEST_REMOVED` fires — objective regression suppression works correctly.
3. `AQL_QUEST_COMPLETED` fires exactly once per turn-in on all versions — no double-firing.
4. TBC behavior is identical: `GetQuestReward` hook still fires; `QUEST_TURNED_IN` does not fire on TBC so the new handler branch is never reached.
5. The `GetQuestInfo` else-branch comment no longer contains deferred language about the MoP sub-project.
