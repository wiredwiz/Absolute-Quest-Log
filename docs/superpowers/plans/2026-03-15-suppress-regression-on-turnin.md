# Suppress Objective Regression on Quest Turn-In — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the spurious `AQL_OBJECTIVE_REGRESSED` callback that fires when item objectives drop to zero during a quest turn-in.

**Architecture:** Delete one line — `handleQuestLogUpdate()` — from the `QUEST_TURNED_IN` event branch in `Core/EventEngine.lua`. Replace it with a clarifying comment. `QUEST_REMOVED` and `QUEST_LOG_UPDATE` already fire after the quest is gone from the log, so the diff correctly produces `AQL_QUEST_COMPLETED` without running an objective diff for the turned-in quest.

**Tech Stack:** Lua 5.1, WoW TBC Classic (Interface 20505), AceAddon-3.0, LibStub. No automated test framework — verification is manual in-game.

---

## Chunk 1: Remove handleQuestLogUpdate from QUEST_TURNED_IN

### Task 1: Edit Core/EventEngine.lua

**Files:**
- Modify: `Core/EventEngine.lua` — `QUEST_TURNED_IN` event branch (lines 224–235)

**Background for the implementer:**

The event frame's `OnEvent` handler has a branch for `QUEST_TURNED_IN` that currently:
1. Calls `HistoryCache:MarkCompleted(questID)` — **keep this**
2. Calls `handleQuestLogUpdate()` — **remove this**

The `handleQuestLogUpdate()` call runs a diff while the quest is still in the log and its item counts are already zeroed (items just handed to the NPC). This diff fires `AQL_OBJECTIVE_REGRESSED` spuriously. `QUEST_REMOVED` always fires next — after the quest is removed from the log — and runs the correct diff that fires `AQL_QUEST_COMPLETED` via the "removed quest" path. The `handleQuestLogUpdate()` in `QUEST_TURNED_IN` is therefore redundant *and* harmful.

**Current code at lines 224–235:**

```lua
elseif event == "QUEST_TURNED_IN" then
    -- QUEST_TURNED_IN fires BEFORE QUEST_LOG_UPDATE removes the quest.
    -- Pre-mark the quest as completed in HistoryCache NOW so that when
    -- the subsequent diff sees the quest disappear from the log, it
    -- correctly identifies it as a turn-in (HasCompleted → true) rather
    -- than an abandonment.
    -- In TBC Classic, QUEST_TURNED_IN passes: questID, xpReward, moneyReward.
    local questID = ...
    if questID and type(questID) == "number" then
        AQL.HistoryCache:MarkCompleted(questID)
    end
    handleQuestLogUpdate()
```

- [ ] **Step 1: Open `Core/EventEngine.lua` and locate the `QUEST_TURNED_IN` branch (around line 224)**

- [ ] **Step 2: Remove `handleQuestLogUpdate()` and update the block comment**

Replace the entire branch with:

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

- [ ] **Step 3: Verify the file is syntactically valid**

Open `Core/EventEngine.lua` and confirm:
- The `elseif event == "QUEST_TURNED_IN" then` block no longer contains `handleQuestLogUpdate()`
- The surrounding `elseif` chain and the final `end` closing the `OnEvent` handler are intact
- No stray lines were accidentally removed

- [ ] **Step 4: Commit**

```bash
cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
git add "Core/EventEngine.lua"
git commit -m "fix: suppress AQL_OBJECTIVE_REGRESSED during quest turn-in

Removing handleQuestLogUpdate() from the QUEST_TURNED_IN handler
eliminates the spurious regression callback that fired when item
objectives dropped to zero as items were handed to the NPC. QUEST_REMOVED
fires after the quest is fully gone from the log and produces
AQL_QUEST_COMPLETED correctly via the HistoryCache path."
```

---

## Manual Verification Checklist

These steps cannot be automated (no test framework for WoW Lua). Perform them in-game after loading the updated addon.

**Test A — Turn-in suppresses regression (the bug fix)**
- [ ] Accept a collection quest that requires items (e.g. "Collect 5 Wolf Paws").
- [ ] Kill mobs until all required items are collected and the quest is complete (`isComplete == true`).
- [ ] Turn the quest in to the quest giver.
- [ ] Confirm: **no** regression announcement in Social Quest chat, **no** regression banner.
- [ ] Confirm: **yes** completion announcement in Social Quest chat / completion banner fires normally.

**Test B — Kill quest turn-in is unaffected**
- [ ] Accept a kill-objective quest.
- [ ] Complete it and turn it in.
- [ ] Confirm: completion announcement fires, no regression fires.

**Test C — Genuine mid-quest regression still fires**
- [ ] Accept a collection quest and collect some (but not all) required items.
- [ ] Delete one of the collected items from your bags.
- [ ] Confirm: Social Quest regression announcement appears in chat (proving `AQL_OBJECTIVE_REGRESSED` still fires for real regressions).
