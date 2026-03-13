# suggestedGroup + failReason Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `suggestedGroup` (recommended party size) and `failReason` (`"timeout"`, `"escort_died"`, or `"unknown"`) to the QuestInfo snapshot so consumers of AQL can read them via `AQL:GetQuest(questID)`.

**Architecture:** Two surgical edits — QuestCache.lua captures `suggestedGroup` from `GetQuestLogTitle()` and threads both new fields into the QuestInfo return table; EventEngine.lua infers failure reason from the pre-failure cache snapshot and stores it in `failedSet` before triggering a rebuild. No new files, no new public API methods, no callback signature changes.

**Tech Stack:** Lua 5.1 (TBC Anniversary Interface 20505), LibStub-1.0, CallbackHandler-1.0. No automated test runner — verification is in-game via the WoW client.

**Spec:** `docs/superpowers/specs/2026-03-12-aql-suggested-group-and-fail-reason.md`

---

## Chunk 1: QuestCache.lua — suggestedGroup + failReason fields

### Task 1: Update QuestCache.lua

**Files:**
- Modify: `Core/QuestCache.lua:15-16` (failedSet comment)
- Modify: `Core/QuestCache.lua:34` (GetQuestLogTitle capture)
- Modify: `Core/QuestCache.lua:36-42` (info table construction)
- Modify: `Core/QuestCache.lua:67` (isFailed local — REPLACE, do not supplement)
- Modify: `Core/QuestCache.lua:124-139` (QuestInfo return table)

- [ ] **Step 1: Update the `failedSet` comment at the top of the file**

At `Core/QuestCache.lua` lines 15-16, replace:
```lua
-- failedSet[questID] = true when QUEST_FAILED has fired for that quest.
-- EventEngine writes to this set; QuestCache reads it during Rebuild.
```
With:
```lua
-- failedSet[questID] = reason string ("timeout", "escort_died", "unknown") when
-- QUEST_FAILED has fired for that quest. EventEngine writes; QuestCache reads.
```

- [ ] **Step 2: Capture `suggestedGroup` from `GetQuestLogTitle()` in `Rebuild()`**

At `Core/QuestCache.lua` line 34, replace:
```lua
        local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
```
With:
```lua
        local title, level, suggestedGroup, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
```

- [ ] **Step 3: Add `suggestedGroup` to the `info` table in `Rebuild()`**

At `Core/QuestCache.lua` lines 36-42, replace the `info` table construction:
```lua
            local info = {
                title      = title,
                level      = level,
                isHeader   = isHeader,
                isComplete = isComplete,
                questID    = questID,
            }
```
With:
```lua
            local info = {
                title          = title,
                level          = level,
                suggestedGroup = suggestedGroup,  -- nil-safe: _buildEntry applies or 0 fallback
                isHeader       = isHeader,
                isComplete     = isComplete,
                questID        = questID,
            }
```

- [ ] **Step 4: Replace the `isFailed` local in `_buildEntry()` with the two-line block**

At `Core/QuestCache.lua` line 67, **replace** the existing line entirely:
```lua
    local isFailed   = self.failedSet[questID] == true
```
With this two-line block (the old line must be removed — it evaluates to `false` for string values):
```lua
    local isFailed   = self.failedSet[questID] ~= nil
    local failReason = type(self.failedSet[questID]) == "string" and self.failedSet[questID] or nil
```

- [ ] **Step 5: Add `suggestedGroup` and `failReason` to the QuestInfo return table**

At `Core/QuestCache.lua` lines 124-139, add the two new fields to the `return` block. The full updated return table:
```lua
    return {
        questID        = questID,
        title          = info.title or "",
        level          = info.level or 0,
        suggestedGroup = info.suggestedGroup or 0,
        zone           = zone,
        type           = questType,
        faction        = questFaction,
        isComplete     = isComplete,
        isFailed       = isFailed,
        failReason     = failReason,
        isTracked      = isTracked,
        link           = link,
        snapshotTime   = GetTime(),
        timerSeconds   = timerSeconds,
        objectives     = objectives,
        chainInfo      = chainInfo,
    }
```

- [ ] **Step 6: Commit**

```bash
git add Core/QuestCache.lua
git commit -m "feat: add suggestedGroup and failReason to QuestInfo snapshot"
```

---

## Chunk 2: EventEngine.lua — failure reason detection

### Task 2: Update EventEngine.lua

**Files:**
- Modify: `Core/EventEngine.lua:17-19` (failedSet comment)
- Modify: `Core/EventEngine.lua:204-214` (QUEST_FAILED handler body)

- [ ] **Step 1: Update the `failedSet` comment in EventEngine.lua**

At `Core/EventEngine.lua` lines 17-19, replace:
```lua
-- Set by QuestCache to track quests that have received QUEST_FAILED.
-- EventEngine writes here; QuestCache reads here during _buildEntry.
-- (QuestCache.failedSet is initialized in QuestCache.lua; we just write to it.)
```
With:
```lua
-- EventEngine writes reason strings here ("timeout", "escort_died", "unknown");
-- QuestCache reads during _buildEntry to populate QuestInfo.failReason.
-- (QuestCache.failedSet is initialized in QuestCache.lua; we just write to it.)
```

- [ ] **Step 2: Replace the QUEST_FAILED handler body with reason-detection logic**

At `Core/EventEngine.lua` lines 204-214, replace the entire `elseif event == "QUEST_FAILED" then` block:
```lua
    elseif event == "QUEST_FAILED" then
        -- Mark the quest as failed before the next cache rebuild picks it up.
        local questID = ...  -- first event argument; select(2,...) would skip it
        -- In TBC Classic, QUEST_FAILED may not pass a questID directly.
        -- As a fallback, mark all currently active quests that have isFailed
        -- based on the next QUEST_LOG_UPDATE (it will set isFailed via isComplete=-1).
        -- If questID is available, mark it directly.
        if questID and type(questID) == "number" then
            AQL.QuestCache.failedSet[questID] = true
        end
        handleQuestLogUpdate()
```
With:
```lua
    elseif event == "QUEST_FAILED" then
        local questID = ...  -- first event argument
        if questID and type(questID) == "number" then
            -- Determine failure reason from the pre-failure snapshot.
            -- timerSeconds and snapshotTime are set synchronously in _buildEntry,
            -- so their delta accurately estimates time remaining at event delivery.
            -- Use a 1-second epsilon to account for event delivery lag.
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
        -- When questID is unavailable, the quest is detected failed via the diff
        -- on the subsequent QUEST_LOG_UPDATE; failReason will be nil in that case.
        handleQuestLogUpdate()
```

- [ ] **Step 3: Commit**

```bash
git add Core/EventEngine.lua
git commit -m "feat: infer quest failure reason in QUEST_FAILED handler"
```

---

## In-Game Verification

This addon has no automated test runner. Verify in the WoW TBC Anniversary client after copying files to the AddOns directory:

**suggestedGroup:**
- Accept a solo quest → `/run print(LibStub("AbsoluteQuestLog-1.0"):GetQuest(<questID>).suggestedGroup)` → expect `0`
- Accept a group quest (e.g. a [Group 5] quest) → same command → expect `5` (or the appropriate count)

**failReason:**
- Let a timed quest expire → `AQL_QUEST_FAILED` callback's `questInfo.failReason` → expect `"timeout"`
- Fail an escort quest by letting the NPC die (requires Questie loaded for `type == "escort"`) → expect `"escort_died"`
- Fail a quest by other means → expect `"unknown"` or `nil`
