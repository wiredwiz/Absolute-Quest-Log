# AQL Quest API Wrapper Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize all WoW quest API calls in `Core\WowQuestAPI.lua`, expose clean wrapper methods on AQL, and remove all direct WoW quest globals from Social Quest.

**Architecture:** A new stateless `WowQuestAPI` global table owns every raw WoW quest API call and version-branches at load time. AQL gains new public methods that delegate to `WowQuestAPI` with cache-first fallback. Social Quest replaces each direct WoW call with the equivalent AQL method.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary (Interface 20505), LibStub, no test framework — verification via in-game `/run` console commands after `/reload`.

---

## Projects and key paths

| Label | Path |
|-------|------|
| AQL root | `D:\Projects\Wow Addons\Absolute-Quest-Log\` |
| SQ root  | `D:\Projects\Wow Addons\Social-Quest\` |

---

## File structure

| Action | File | Purpose |
|--------|------|---------|
| CREATE | `AQL\Core\WowQuestAPI.lua` | All raw WoW quest globals; version-branched |
| MODIFY | `AQL\AbsoluteQuestLog.toc` | Load WowQuestAPI.lua before other Core files |
| MODIFY | `AQL\AbsoluteQuestLog.lua` | New public methods + enhanced HasCompletedQuest |
| MODIFY | `SQ\Core\Announcements.lua` | Replace `C_QuestLog.GetQuestInfo` (×4) + `C_QuestLog.IsQuestFlaggedCompleted` (×1) |
| MODIFY | `SQ\Core\GroupData.lua` | Replace `C_QuestLog.GetQuestInfo` (×2) |
| MODIFY | `SQ\UI\Tabs\PartyTab.lua` | Replace `C_QuestLog.GetQuestInfo` (×1) |
| MODIFY | `SQ\UI\Tabs\SharedTab.lua` | Replace `C_QuestLog.GetQuestInfo` (×2) |

---

## Chunk 1: WowQuestAPI.lua + TOC

### Task 1: Create Core\WowQuestAPI.lua

**Files:**
- Create: `D:\Projects\Wow Addons\Absolute-Quest-Log\Core\WowQuestAPI.lua`

- [ ] **Step 1: Create the file with the full implementation**

```lua
-- Core/WowQuestAPI.lua
-- Thin, stateless wrappers around WoW quest globals.
-- All version-specific branching lives here.
-- No other AQL or Social Quest file should reference WoW quest globals directly.

WowQuestAPI = WowQuestAPI or {}

------------------------------------------------------------------------
-- Version detection
------------------------------------------------------------------------

local _TOC = select(4, GetBuildInfo())

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestInfo(questID)
-- Two-tier resolution. Returns nil when no source has data.
-- Guaranteed fields: questID, title.
-- Conditional fields (only when quest is in player's log): level,
--   suggestedGroup, isComplete.
-- TBC: tier-1 log scan (GetQuestLogTitle), tier-2 C_QuestLog.GetQuestInfo.
-- Retail: single C_QuestLog.GetQuestInfo call returns full info table.
------------------------------------------------------------------------

if _TOC >= 100000 then  -- Retail
    function WowQuestAPI.GetQuestInfo(questID)
        local info = C_QuestLog.GetQuestInfo(questID)
        if not info or not info.title then return nil end
        return {
            questID        = questID,
            title          = info.title,
            level          = info.level,
            suggestedGroup = info.suggestedGroup or 0,
            isComplete     = info.isComplete == 1,
            isTask         = info.isTask,
            isBounty       = info.isBounty,
            isStory        = info.isStory,
            campaignID     = info.campaignID,
        }
    end
else  -- TBC Classic / TBC Anniversary (and Classic Era stub)
    function WowQuestAPI.GetQuestInfo(questID)
        -- Tier 1: log scan for richer data.
        -- GetQuestLogTitle returns: title, level, suggestedGroup, isHeader,
        --   isCollapsed, isComplete, frequency, questID
        local numEntries = GetNumQuestLogEntries()
        for i = 1, numEntries do
            local title, level, suggestedGroup, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
            if qid == questID and not isHeader then
                return {
                    questID        = questID,
                    title          = title,
                    level          = level,
                    suggestedGroup = tonumber(suggestedGroup) or 0,
                    isComplete     = (isComplete == 1 or isComplete == true),
                }
            end
        end

        -- Tier 2: quest not in log — title-only fallback.
        -- C_QuestLog.GetQuestInfo(questID) returns a title string or nil on TBC.
        local title = C_QuestLog.GetQuestInfo(questID)
        if not title then return nil end
        return { questID = questID, title = title }
    end
end

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestObjectives(questID)
-- Returns the raw objectives array from C_QuestLog.GetQuestObjectives.
-- TBC 20505 fields per entry: text, type, finished, numFulfilled, numRequired
-- Note: field is `finished` (bool), NOT `isFinished`. AQL cache normalizes
-- to `isFinished`; this wrapper returns raw API data.
-- Returns {} if the quest is not in the log.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestObjectives(questID)
    return C_QuestLog.GetQuestObjectives(questID) or {}
end

------------------------------------------------------------------------
-- WowQuestAPI.IsQuestFlaggedCompleted(questID)
-- Returns bool. True when the quest is in the character's completion history.
------------------------------------------------------------------------

if _TOC >= 20000 then  -- TBC Classic, TBC Anniversary, Retail
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return C_QuestLog.IsQuestFlaggedCompleted(questID) == true
    end
else  -- Classic Era (future)
    function WowQuestAPI.IsQuestFlaggedCompleted(questID)
        return IsQuestFlaggedCompleted(questID) == true
    end
end

------------------------------------------------------------------------
-- WowQuestAPI.GetQuestLogIndex(questID)
-- Returns the 1-based quest log index or nil if not in the player's log.
-- Matches on the 8th return value of GetQuestLogTitle(i) (the questID).
-- Does NOT use SelectQuestLogEntry/GetQuestID to avoid side-effects.
------------------------------------------------------------------------

function WowQuestAPI.GetQuestLogIndex(questID)
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, _, _, _, _, qid = GetQuestLogTitle(i)
        if qid == questID then return i end
    end
    return nil
end

------------------------------------------------------------------------
-- WowQuestAPI.TrackQuest(questID)
-- WowQuestAPI.UntrackQuest(questID)
-- Thin wrappers — no watch-cap enforcement (that lives in AQL:TrackQuest).
-- No-op if the quest is not in the player's log.
------------------------------------------------------------------------

function WowQuestAPI.TrackQuest(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if logIndex then
        AddQuestWatch(logIndex)
    end
end

function WowQuestAPI.UntrackQuest(questID)
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if logIndex then
        RemoveQuestWatch(logIndex)
    end
end

------------------------------------------------------------------------
-- WowQuestAPI.IsUnitOnQuest(questID, unit)
-- Returns bool on Retail (UnitIsOnQuest exists).
-- Returns nil on TBC/Classic (API does not exist).
-- Note: parameter order is (questID, unit) — the opposite of the WoW
-- global UnitIsOnQuest(unit, questID) — to keep questID-first convention.
------------------------------------------------------------------------

if _TOC >= 100000 then  -- Retail
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return UnitIsOnQuest(unit, questID)
    end
else
    function WowQuestAPI.IsUnitOnQuest(questID, unit)
        return nil
    end
end
```

- [ ] **Step 2: Verify file exists**

```bash
ls "D:\Projects\Wow Addons\Absolute-Quest-Log\Core\WowQuestAPI.lua"
```

Expected: file listed.

---

### Task 2: Register WowQuestAPI.lua in the TOC

**Files:**
- Modify: `D:\Projects\Wow Addons\Absolute-Quest-Log\AbsoluteQuestLog.toc`

Current TOC load order:
```
AbsoluteQuestLog.lua
Core\EventEngine.lua
Core\QuestCache.lua
...
```

`WowQuestAPI.lua` must be loaded before any file that *calls* WowQuestAPI at call-time. `AbsoluteQuestLog.lua` only *defines* functions that reference WowQuestAPI — it never calls them at file scope — so `WowQuestAPI.lua` can safely follow it. The correct position is immediately after `AbsoluteQuestLog.lua`, before `Core\EventEngine.lua`.

- [ ] **Step 1: Add `Core\WowQuestAPI.lua` to the TOC**

In `AbsoluteQuestLog.toc`, insert `Core\WowQuestAPI.lua` as the second line (after `AbsoluteQuestLog.lua`):

```
AbsoluteQuestLog.lua
Core\WowQuestAPI.lua
Core\EventEngine.lua
Core\QuestCache.lua
Core\HistoryCache.lua
Providers\Provider.lua
Providers\QuestieProvider.lua
Providers\QuestWeaverProvider.lua
Providers\NullProvider.lua
```

- [ ] **Step 2: Commit**

```bash
cd "D:\Projects\Wow Addons\Absolute-Quest-Log"
git add Core\WowQuestAPI.lua AbsoluteQuestLog.toc
git commit -m "feat: add WowQuestAPI.lua — centralized WoW quest API wrappers"
```

- [ ] **Step 3: In-game smoke test**

Load into WoW, then in chat:

```
/reload
/run print(type(WowQuestAPI))
```

Expected output: `table`

```
/run print(type(WowQuestAPI.GetQuestInfo))
```

Expected output: `function`

---

## Chunk 2: New AQL public methods

### Task 3: Add new public methods to AbsoluteQuestLog.lua

**Files:**
- Modify: `D:\Projects\Wow Addons\Absolute-Quest-Log\AbsoluteQuestLog.lua`

The existing public API section ends at line 116. Add a new section after the Chain Queries block and update `HasCompletedQuest`.

- [ ] **Step 1: Update `AQL:HasCompletedQuest` to add WowQuestAPI fallback**

Current implementation (lines 58–60):
```lua
function AQL:HasCompletedQuest(questID)
    return self.HistoryCache ~= nil and self.HistoryCache:HasCompleted(questID)
end
```

Replace with:
```lua
function AQL:HasCompletedQuest(questID)
    if self.HistoryCache and self.HistoryCache:HasCompleted(questID) then
        return true
    end
    return WowQuestAPI.IsQuestFlaggedCompleted(questID)
end
```

- [ ] **Step 2: Add the new public methods**

After the `-- AQL:RegisterCallback / AQL:UnregisterCallback` comment at the end of the file, append:

```lua
------------------------------------------------------------------------
-- Public API: WowQuestAPI-backed Extended Queries
------------------------------------------------------------------------

-- Returns the full AQL cache snapshot when cached; falls back to
-- WowQuestAPI.GetQuestInfo which returns { questID, title } only.
-- Returns nil when neither source has data.
-- Contrast with AQL:GetQuest which is cache-only (returns nil when uncached).
function AQL:GetQuestInfo(questID)
    local cached = self.QuestCache and self.QuestCache:Get(questID)
    if cached then return cached end
    return WowQuestAPI.GetQuestInfo(questID)
end

-- Returns the title string for any questID, or nil.
-- Cache first; WowQuestAPI title-lookup fallback.
function AQL:GetQuestTitle(questID)
    local cached = self.QuestCache and self.QuestCache:Get(questID)
    if cached then return cached.title end
    local info = WowQuestAPI.GetQuestInfo(questID)
    return info and info.title or nil
end

-- Returns the objectives array for a questID.
-- Cache first (normalized fields: isFinished, etc.).
-- WowQuestAPI fallback returns raw TBC fields (finished, type, etc.).
function AQL:GetQuestObjectives(questID)
    local cached = self.QuestCache and self.QuestCache:Get(questID)
    if cached then return cached.objectives or {} end
    return WowQuestAPI.GetQuestObjectives(questID)
end

-- Tracks a quest by questID.
-- Returns false if the watch cap (MAX_WATCHABLE_QUESTS) is already reached.
-- Returns true if the quest was successfully handed to AddQuestWatch.
-- Caller is responsible for displaying a message when false is returned.
function AQL:TrackQuest(questID)
    if GetNumQuestWatches() >= MAX_WATCHABLE_QUESTS then
        return false
    end
    WowQuestAPI.TrackQuest(questID)
    return true
end

-- Untracks a quest by questID. Always delegates; no cap check needed.
function AQL:UntrackQuest(questID)
    WowQuestAPI.UntrackQuest(questID)
end

-- Returns bool on Retail (UnitIsOnQuest exists), nil on TBC/Classic.
function AQL:IsUnitOnQuest(questID, unit)
    return WowQuestAPI.IsUnitOnQuest(questID, unit)
end
```

- [ ] **Step 3: Commit**

```bash
cd "D:\Projects\Wow Addons\Absolute-Quest-Log"
git add AbsoluteQuestLog.lua
git commit -m "feat: add AQL public methods GetQuestInfo, GetQuestTitle, GetQuestObjectives, TrackQuest, UntrackQuest, IsUnitOnQuest; enhance HasCompletedQuest with WowQuestAPI fallback"
```

- [ ] **Step 4: In-game smoke tests**

After `/reload`, run each block in chat one at a time.

**GetQuestTitle — for a quest you have active:**
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local id = next(AQL:GetAllQuests()); print(id, AQL:GetQuestTitle(id))
```
Expected: questID number and a quest title string.

**GetQuestTitle — for a quest you do NOT have (use any numeric ID from wowhead):**
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); print(AQL:GetQuestTitle(9999))
```
Expected: either a title string (if WoW client has it cached) or `nil`.

**HasCompletedQuest — for a quest flagged completed:**
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local id = next(AQL:GetCompletedQuests()); print(id, AQL:HasCompletedQuest(id))
```
Expected: questID number and `true`.

**TrackQuest — tracking a quest you have active:**
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local id = next(AQL:GetAllQuests()); print(AQL:TrackQuest(id))
```
Expected: `true` (or `false` if already at 5 watched quests).

**IsUnitOnQuest — always nil on TBC:**
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local id = next(AQL:GetAllQuests()); print(AQL:IsUnitOnQuest(id, "player"))
```
Expected: `nil` on TBC Anniversary.

---

## Chunk 3: Social Quest migration

### Context for implementer

Social Quest is a separate addon at `D:\Projects\Wow Addons\Social-Quest\`. It accesses AQL via:
```lua
local AQL = SocialQuest.AQL   -- set during addon init from LibStub("AbsoluteQuestLog-1.0")
```

All five files below currently call `C_QuestLog.GetQuestInfo(questID)` directly to get a title string when a questID is known but the quest may not be in the local log. Replace every such call with `AQL:GetQuestTitle(questID)`. Do not change any other logic.

### Task 4: Migrate Core\Announcements.lua

**Files:**
- Modify: `D:\Projects\Wow Addons\Social-Quest\Core\Announcements.lua`

There are **5 call sites** to replace. All have `local AQL = SocialQuest.AQL` in scope at the call site.

- [ ] **Step 1: Replace `C_QuestLog.GetQuestInfo` at line 173**

Context — `OnQuestEvent`, title fallback chain:
```lua
-- Before:
local title = (info and info.title)
           or C_QuestLog.GetQuestInfo(questID)
           or ("Quest " .. questID)

-- After:
local title = (info and info.title)
           or AQL:GetQuestTitle(questID)
           or ("Quest " .. questID)
```

- [ ] **Step 2: Replace `C_QuestLog.IsQuestFlaggedCompleted` at line 300**

Context — `checkAllCompleted`, localFlagged check. `AQL` is in scope (set on line 292):
```lua
-- Before:
local localFlagged  = localHasCompleted or C_QuestLog.IsQuestFlaggedCompleted(questID)

-- After:
local localFlagged  = localHasCompleted or AQL:HasCompletedQuest(questID)
```

- [ ] **Step 3: Replace `C_QuestLog.GetQuestInfo` at line 327**

Context — `checkAllCompleted`, title fallback chain:
```lua
-- Before:
local title = (info and info.title)
           or C_QuestLog.GetQuestInfo(questID)
           or ("Quest " .. questID)

-- After:
local title = (info and info.title)
           or AQL:GetQuestTitle(questID)
           or ("Quest " .. questID)
```

- [ ] **Step 4: Replace `C_QuestLog.GetQuestInfo` at line 372**

Context — `OnRemoteQuestEvent`, title fallback chain:
```lua
-- Before:
local title = cachedTitle
           or (info and info.title)
           or C_QuestLog.GetQuestInfo(questID)
           or ("Quest " .. questID)

-- After:
local title = cachedTitle
           or (info and info.title)
           or AQL:GetQuestTitle(questID)
           or ("Quest " .. questID)
```

- [ ] **Step 5: Replace `C_QuestLog.GetQuestInfo` at line 399**

Context — `OnRemoteObjectiveEvent`. The first branch tries `GetQuestLink` (returns a chat hyperlink); `GetQuestTitle` is the plain-text fallback. This is semantically correct. `AQL` is set on line 397:
```lua
-- Before:
local title = (AQL and AQL:GetQuestLink(questID))
           or C_QuestLog.GetQuestInfo(questID)
           or ("Quest " .. questID)

-- After:
local title = (AQL and AQL:GetQuestLink(questID))
           or (AQL and AQL:GetQuestTitle(questID))
           or ("Quest " .. questID)
```

- [ ] **Step 6: Verify no direct WoW quest API calls remain**

```bash
grep -n "C_QuestLog\." "D:\Projects\Wow Addons\Social-Quest\Core\Announcements.lua"
```

Expected: no output (note: `C_FriendList` calls are unrelated and will still appear — that is correct).

---

### Task 5: Migrate Core\GroupData.lua

**Files:**
- Modify: `D:\Projects\Wow Addons\Social-Quest\Core\GroupData.lua`

There are **2 call sites**, both in the same fallback pattern. Both have `local AQL = SocialQuest.AQL` in scope.

- [ ] **Step 1: Replace `C_QuestLog.GetQuestInfo` at line 65 (`OnInitReceived`)**

```lua
-- Before:
q.title = (info and info.title) or C_QuestLog.GetQuestInfo(questID)

-- After:
q.title = (info and info.title) or AQL:GetQuestTitle(questID)
```

- [ ] **Step 2: Replace `C_QuestLog.GetQuestInfo` at line 111 (`OnUpdateReceived`)**

```lua
-- Before:
title = (info and info.title) or C_QuestLog.GetQuestInfo(questID),

-- After:
title = (info and info.title) or AQL:GetQuestTitle(questID),
```

- [ ] **Step 3: Verify no direct WoW quest API calls remain**

```bash
grep -n "C_QuestLog\." "D:\Projects\Wow Addons\Social-Quest\Core\GroupData.lua"
```

Expected: no output.

---

### Task 6: Migrate UI\Tabs\PartyTab.lua

**Files:**
- Modify: `D:\Projects\Wow Addons\Social-Quest\UI\Tabs\PartyTab.lua`

- [ ] **Step 1: Find all direct WoW quest API calls**

```bash
grep -n "C_QuestLog\." "D:\Projects\Wow Addons\Social-Quest\UI\Tabs\PartyTab.lua"
```

- [ ] **Step 2: Replace each call**

PartyTab.lua accesses AQL via `local AQL = SocialQuest.AQL` at the top of each function. Confirm the local is in scope at each call site, then:

```lua
-- Before:
C_QuestLog.GetQuestInfo(questID)

-- After:
AQL:GetQuestTitle(questID)
```

- [ ] **Step 3: Verify**

```bash
grep -n "C_QuestLog\." "D:\Projects\Wow Addons\Social-Quest\UI\Tabs\PartyTab.lua"
```

Expected: no output.

---

### Task 7: Migrate UI\Tabs\SharedTab.lua

**Files:**
- Modify: `D:\Projects\Wow Addons\Social-Quest\UI\Tabs\SharedTab.lua`

- [ ] **Step 1: Find all direct WoW quest API calls**

```bash
grep -n "C_QuestLog\." "D:\Projects\Wow Addons\Social-Quest\UI\Tabs\SharedTab.lua"
```

- [ ] **Step 2: Replace at line 111 (chain section — uses `eng.questID`)**

```lua
-- Before:
or C_QuestLog.GetQuestInfo(eng.questID)

-- After:
or AQL:GetQuestTitle(eng.questID)
```

- [ ] **Step 3: Replace at line 183 (standalone section — uses `questID`)**

```lua
-- Before:
or C_QuestLog.GetQuestInfo(questID)

-- After:
or AQL:GetQuestTitle(questID)
```

- [ ] **Step 4: Verify**

```bash
grep -n "C_QuestLog\." "D:\Projects\Wow Addons\Social-Quest\UI\Tabs\SharedTab.lua"
```

Expected: no output.

---

### Task 8: Final verification + commit

- [ ] **Step 1: Confirm no direct WoW quest API calls remain in Social Quest**

```bash
grep -rn "C_QuestLog\." "D:\Projects\Wow Addons\Social-Quest"
```

Expected: no output. (This catches any `C_QuestLog` namespace call, not just the ones we planned to replace.)

- [ ] **Step 2: In-game functional test — titles resolve correctly**

Load WoW with both addons. In a party with another Social Quest user, or using the test demo commands, verify:
- Quest accepted banners show quest title (not "Quest 12345")
- Party tab shows correct quest titles for party members
- Shared tab shows correct quest titles

- [ ] **Step 3: Commit Social Quest changes**

```bash
cd "D:\Projects\Wow Addons\Social-Quest"
git add Core\Announcements.lua Core\GroupData.lua UI\Tabs\PartyTab.lua UI\Tabs\SharedTab.lua
git commit -m "refactor: replace direct C_QuestLog calls with AQL:GetQuestTitle"
```
