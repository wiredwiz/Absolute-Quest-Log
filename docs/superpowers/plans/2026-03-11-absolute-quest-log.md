# AbsoluteQuestLog — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite AbsoluteQuestLog as a LibStub-1.0 library with CallbackHandler events, per-objective diffing, and a chain provider system (Questie → QuestWeaver → NullProvider) for WoW Burning Crusade Anniversary (Interface 20505).

**Architecture:** AQL registers with LibStub and exposes a stable public API. Three sub-modules (QuestCache, HistoryCache, EventEngine) handle live state, completion history, and event diffing respectively. At PLAYER_LOGIN, EventEngine selects the best available chain provider and begins listening for WoW quest events. All diff logic and callback dispatch lives in EventEngine; QuestCache and HistoryCache are pure data stores.

**Tech Stack:** LibStub-1.0, CallbackHandler-1.0 (both bundled in Ace3), C_QuestLog (TBC Anniversary), GetQuestsCompleted(), WoW event frame (no AceAddon — this is a plain LibStub library).

---

## File Map

| File | Role |
|---|---|
| `AbsoluteQuestLog.toc` | Addon manifest; lists all files in load order |
| `AbsoluteQuestLog.lua` | LibStub registration, CallbackHandler init, all public API methods |
| `Core/EventEngine.lua` | WoW event frame, PLAYER_LOGIN init, provider selection, diff loop, callback dispatch |
| `Core/QuestCache.lua` | Builds and stores QuestInfo snapshots from C_QuestLog |
| `Core/HistoryCache.lua` | Loads and stores completion history from GetQuestsCompleted() |
| `Providers/Provider.lua` | Documents the provider interface (no runtime code) |
| `Providers/NullProvider.lua` | Returns knownStatus = "unknown" for all queries |
| `Providers/QuestieProvider.lua` | Reads chain/type/faction from QuestieDB |
| `Providers/QuestWeaverProvider.lua` | Reads chain/type/faction from QuestWeaver globals |

**Files to delete:** `AbsoluteQuestLog.Options.lua` (not needed — AQL is infrastructure, no options UI).

---

## Chunk 1: Foundation

Establish the TOC, LibStub registration, provider interface, and NullProvider. After this chunk the library loads without errors and returns an AQL object.

### Task 1: Replace the TOC

**Files:**
- Replace: `AbsoluteQuestLog.toc`

- [ ] **Step 1: Overwrite the TOC**

```
## Interface: 20505
## Title: Lib: AbsoluteQuestLog
## Notes: A rich quest data library for WoW Burning Crusade Anniversary.
## Author: Thad Ryker
## Version: 2.0
## X-Category: Library
## Dependencies: Ace3

AbsoluteQuestLog.lua
Core\EventEngine.lua
Core\QuestCache.lua
Core\HistoryCache.lua
Providers\Provider.lua
Providers\QuestieProvider.lua
Providers\QuestWeaverProvider.lua
Providers\NullProvider.lua
```

Note: NullProvider loads last so providers load in priority order before EventEngine selects one at PLAYER_LOGIN. (Spec TOC order.)

- [ ] **Step 2: Delete the old options file**

Delete `AbsoluteQuestLog.Options.lua` — it references Sea and AceDB and is entirely replaced by the new design. AQL has no user-visible options.

---

### Task 2: LibStub registration and CallbackHandler setup

**Files:**
- Replace: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Write the new AbsoluteQuestLog.lua**

```lua
-- AbsoluteQuestLog-1.0
-- LibStub library providing unified quest data access for WoW TBC Anniversary.
-- Consumers: LibStub("AbsoluteQuestLog-1.0")

local MAJOR, MINOR = "AbsoluteQuestLog-1.0", 1
local AQL, oldVersion = LibStub:NewLibrary(MAJOR, MINOR)
if not AQL then return end  -- Already loaded at equal or higher version.

-- CallbackHandler provides AQL:RegisterCallback / AQL:UnregisterCallback.
AQL.callbacks = AQL.callbacks or LibStub("CallbackHandler-1.0"):New(AQL)

-- Sub-module slots — populated by the files that load after this one.
-- AbsoluteQuestLog.lua loads first (per TOC order), so these are nil until
-- the sub-module files run. Public methods guard against nil sub-modules.
-- AQL.QuestCache   set by Core/QuestCache.lua
-- AQL.HistoryCache set by Core/HistoryCache.lua
-- AQL.EventEngine  set by Core/EventEngine.lua
-- AQL.provider     set by Core/EventEngine.lua at PLAYER_LOGIN

------------------------------------------------------------------------
-- Public API: Quest State Queries
------------------------------------------------------------------------

function AQL:GetQuest(questID)
    return self.QuestCache and self.QuestCache:Get(questID) or nil
end

function AQL:GetAllQuests()
    return self.QuestCache and self.QuestCache:GetAll() or {}
end

function AQL:GetQuestsByZone(zone)
    -- zone is the English canonical zone name as stored by the active chain
    -- provider (e.g. "Blasted Lands"). On non-English clients, use
    -- GetAllQuests() and filter by questID instead.
    local result = {}
    for questID, info in pairs(self:GetAllQuests()) do
        if info.zone == zone then
            result[questID] = info
        end
    end
    return result
end

function AQL:IsQuestActive(questID)
    return self.QuestCache ~= nil and self.QuestCache:Get(questID) ~= nil
end

function AQL:IsQuestFinished(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q ~= nil and q.isComplete == true
end

function AQL:HasCompletedQuest(questID)
    return self.HistoryCache ~= nil and self.HistoryCache:HasCompleted(questID)
end

function AQL:GetCompletedQuests()
    return self.HistoryCache and self.HistoryCache:GetAll() or {}
end

function AQL:GetCompletedQuestCount()
    return self.HistoryCache and self.HistoryCache:GetCount() or 0
end

function AQL:GetQuestType(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.type or nil
end

function AQL:GetQuestLink(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.link or nil
end

------------------------------------------------------------------------
-- Public API: Objective Queries
------------------------------------------------------------------------

function AQL:GetObjectives(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.objectives or nil
end

function AQL:GetObjective(questID, index)
    local objs = self:GetObjectives(questID)
    return objs and objs[index] or nil
end

------------------------------------------------------------------------
-- Public API: Chain Queries
------------------------------------------------------------------------

function AQL:GetChainInfo(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    if q and q.chainInfo then
        return q.chainInfo
    end
    return { knownStatus = "unknown" }
end

function AQL:GetChainStep(questID)
    return self:GetChainInfo(questID).step
end

function AQL:GetChainLength(questID)
    return self:GetChainInfo(questID).length
end

-- AQL:RegisterCallback(event, handler, target) -- from CallbackHandler
-- AQL:UnregisterCallback(event, handler)        -- from CallbackHandler
```

- [ ] **Step 3: Load in WoW and verify registration**

Enable the addon. In-game, run:
```
/run print(LibStub("AbsoluteQuestLog-1.0") ~= nil)
```
Expected output: `true`

If you get a LibStub error, Ace3 is not installed or not loading before AQL (check TOC Dependencies line).

- [ ] **Step 4: Commit**

```bash
git add AbsoluteQuestLog.toc AbsoluteQuestLog.lua
git commit -m "feat: replace TOC and establish LibStub registration with public API stubs"
```

---

### Task 3: Provider interface documentation

**Files:**
- Create: `Providers/Provider.lua`

- [ ] **Step 1: Write Provider.lua**

This file documents the interface. All providers must implement these three methods.

```lua
-- Providers/Provider.lua
-- Documents the interface every AQL provider must implement.
-- This file contains no runtime code; it is documentation only.
--
-- Every provider implements:
--
--   Provider:GetChainInfo(questID)
--     Returns a ChainInfo table or nil.
--     ChainInfo fields (when knownStatus = "known"):
--       knownStatus = "known" | "not_a_chain" | "unknown"
--       chainID     = questID of first quest in chain
--       step        = this quest's 1-based position
--       length      = total quests in chain
--       steps       = array of { questID, title, status }
--       provider    = "Questie" | "QuestWeaver" | "none"
--     When knownStatus = "unknown": all other fields are nil.
--     When knownStatus = "not_a_chain": all other fields except knownStatus are nil.
--
--   Provider:GetQuestType(questID)
--     Returns "normal"|"elite"|"dungeon"|"raid"|"daily"|"pvp"|"escort" or nil.
--
--   Provider:GetQuestFaction(questID)
--     Returns "Alliance", "Horde", or nil (nil means available to both).
--
-- All provider calls in EventEngine are wrapped in pcall. A provider that
-- errors is marked unavailable and the next provider in the chain is tried.
```

- [ ] **Step 2: Commit**

```bash
git add Providers/Provider.lua
git commit -m "feat: add provider interface documentation"
```

---

### Task 4: NullProvider

**Files:**
- Create: `Providers/NullProvider.lua`

- [ ] **Step 1: Write NullProvider.lua**

```lua
-- Providers/NullProvider.lua
-- Fallback provider used when neither Questie nor QuestWeaver is present.
-- Always returns knownStatus = "unknown" for chain queries.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local NullProvider = {}

function NullProvider:GetChainInfo(questID)
    return { knownStatus = "unknown" }
end

function NullProvider:GetQuestType(questID)
    return nil
end

function NullProvider:GetQuestFaction(questID)
    return nil
end

AQL.NullProvider = NullProvider
```

- [ ] **Step 2: Commit**

```bash
git add Providers/NullProvider.lua
git commit -m "feat: add NullProvider returning unknown chain status"
```

---

## Chunk 2: Data Layer

Build QuestCache and HistoryCache. After this chunk, `AQL:GetAllQuests()` and `AQL:HasCompletedQuest()` return real data (once EventEngine triggers the first rebuild — that happens in Chunk 4).

### Task 5: HistoryCache

**Files:**
- Create: `Core/HistoryCache.lua`

- [ ] **Step 1: Write HistoryCache.lua**

```lua
-- Core/HistoryCache.lua
-- Tracks quests completed at any point in this character's history.
-- Initial data comes from GetQuestsCompleted() (requires async query).
-- Subsequent completions are recorded via HistoryCache:MarkCompleted().

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local HistoryCache = {}
AQL.HistoryCache = HistoryCache

-- completed[questID] = true for every quest ever turned in.
HistoryCache.completed = {}
HistoryCache.count = 0

-- Called by EventEngine at PLAYER_LOGIN. Registers for QUEST_QUERY_COMPLETE,
-- fires QueryQuestsCompleted(), then populates from the result.
function HistoryCache:Load(eventFrame)
    eventFrame:RegisterEvent("QUEST_QUERY_COMPLETE")
    QueryQuestsCompleted()
end

-- Called from the QUEST_QUERY_COMPLETE handler in EventEngine.
function HistoryCache:OnQueryComplete()
    local data = GetQuestsCompleted()
    local count = 0
    for questID, done in pairs(data) do
        if done then
            self.completed[questID] = true
            count = count + 1
        end
    end
    self.count = count
end

-- Called by EventEngine when it detects a quest turn-in (AQL_QUEST_COMPLETED).
function HistoryCache:MarkCompleted(questID)
    if not self.completed[questID] then
        self.completed[questID] = true
        self.count = self.count + 1
    end
end

function HistoryCache:HasCompleted(questID)
    return self.completed[questID] == true
end

function HistoryCache:GetAll()
    return self.completed
end

function HistoryCache:GetCount()
    return self.count
end
```

- [ ] **Step 2: Commit**

```bash
git add Core/HistoryCache.lua
git commit -m "feat: add HistoryCache with async GetQuestsCompleted loading"
```

---

### Task 6: QuestCache

**Files:**
- Create: `Core/QuestCache.lua`

- [ ] **Step 1: Write QuestCache.lua**

```lua
-- Core/QuestCache.lua
-- Builds and stores QuestInfo snapshots from C_QuestLog.
-- QuestCache:Rebuild() is called by EventEngine on each relevant WoW event.
-- Returns the previous snapshot so EventEngine can diff old vs. new.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local QuestCache = {}
AQL.QuestCache = QuestCache

-- data[questID] = QuestInfo table (see spec for full field list)
QuestCache.data = {}

-- failedSet[questID] = true when QUEST_FAILED has fired for that quest.
-- EventEngine writes to this set; QuestCache reads it during Rebuild.
QuestCache.failedSet = {}

-- Rebuild the entire cache from C_QuestLog.
-- Returns the previous cache table so callers can diff.
function QuestCache:Rebuild()
    local new = {}
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    local currentZone = nil

    -- Build a logIndex-by-questID map during iteration (needed for timer queries).
    local logIndexByQuestID = {}

    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                currentZone = info.title
            else
                local questID = info.questID
                logIndexByQuestID[questID] = i
                -- Wrap each entry build in pcall so one bad entry never aborts the loop.
                local ok, entryOrErr = pcall(self._buildEntry, self, questID, info, currentZone, i)
                if ok and entryOrErr then
                    new[questID] = entryOrErr
                elseif not ok and AQL.debug then
                    print("[AQL] QuestCache: error building entry for questID " .. tostring(questID) .. ": " .. tostring(entryOrErr))
                end
            end
        end
    end

    local old = self.data
    self.data = new
    return old
end

function QuestCache:_buildEntry(questID, info, zone, logIndex)
    -- isComplete: C_QuestLog.GetInfo returns isComplete as 1 (done, not yet turned in)
    -- or false/nil if not complete.
    local isComplete = (info.isComplete == 1 or info.isComplete == true)
    local isFailed   = self.failedSet[questID] == true

    -- Timer: requires selecting the quest log entry.
    -- SelectQuestLogEntry briefly changes quest log UI selection; this is safe
    -- to do during cache rebuild since it is instantaneous and non-destructive.
    SelectQuestLogEntry(logIndex)
    local rawTimer = GetQuestLogTimeLeft()
    local timerSeconds = (rawTimer and rawTimer > 0) and rawTimer or nil

    -- Quest link.
    local link = GetQuestLink(logIndex)

    -- isTracked: IsQuestWatched takes a quest log index.
    local isTracked = IsQuestWatched(logIndex) == true

    -- Objectives.
    -- C_QuestLog.GetQuestObjectives returns per-objective: text, type, finished,
    -- numFulfilled, numRequired. `name` is parsed from text by stripping the
    -- count suffix (e.g. "Tainted Ooze killed: 4/10" → name = "Tainted Ooze killed").
    -- For event/log types with no count, name equals the full text.
    local objectives = {}
    local rawObjs = C_QuestLog.GetQuestObjectives(questID)
    if rawObjs then
        for idx, obj in ipairs(rawObjs) do
            local text = obj.text or ""
            local name = text:match("^(.-):%s*%d+/%d+%s*$") or text
            objectives[idx] = {
                index        = idx,
                text         = text,
                type         = obj.type or "log",
                name         = name,
                numFulfilled = obj.numFulfilled or 0,
                numRequired  = obj.numRequired or 1,
                isFinished   = obj.finished == true,
                isFailed     = false,  -- set to true by EventEngine when the quest fails
            }
        end
    end

    -- Provider data (chain/type/faction).
    -- AQL.provider may be nil during the very first Rebuild before EventEngine
    -- has run provider selection. Nil-guard here; the next rebuild after
    -- PLAYER_LOGIN will have a provider set.
    local chainInfo = { knownStatus = "unknown" }
    local questType, questFaction
    local provider = AQL.provider
    if provider then
        local ok, result = pcall(provider.GetChainInfo, provider, questID)
        if ok and result then chainInfo = result end

        local ok2, result2 = pcall(provider.GetQuestType, provider, questID)
        if ok2 then questType = result2 end

        local ok3, result3 = pcall(provider.GetQuestFaction, provider, questID)
        if ok3 then questFaction = result3 end
    end

    return {
        questID      = questID,
        title        = info.title or "",
        level        = info.level or 0,
        zone         = zone,
        type         = questType,
        faction      = questFaction,
        isComplete   = isComplete,
        isFailed     = isFailed,
        isTracked    = isTracked,
        link         = link,
        snapshotTime = GetTime(),
        timerSeconds = timerSeconds,
        objectives   = objectives,
        chainInfo    = chainInfo,
    }
end

function QuestCache:Get(questID)
    return self.data[questID]
end

function QuestCache:GetAll()
    return self.data
end
```

- [ ] **Step 2: Commit**

```bash
git add Core/QuestCache.lua
git commit -m "feat: add QuestCache with C_QuestLog-based snapshot building"
```

---

## Chunk 3: Chain Data Providers

Implement QuestieProvider and QuestWeaverProvider. NullProvider already exists as the fallback. After this chunk, chain info flows from whichever provider is present.

### Task 7: QuestieProvider

**Files:**
- Create: `Providers/QuestieProvider.lua`

- [ ] **Step 1: Write QuestieProvider.lua**

```lua
-- Providers/QuestieProvider.lua
-- Reads chain metadata from QuestieDB if Questie is installed.
-- Questie stores quest data under QuestieDB.GetQuest(questID).
-- Relevant fields on a quest object (questie v11.x):
--   quest.nextQuestInChain  (questID of next step, or 0)
-- Type info comes from quest.requiredClasses / questTagIds in QuestieDB.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local QuestieProvider = {}

-- questTagIds enum values from QuestieDB (QuestieDB.lua questKeys):
--   ELITE = 1, RAID = 62, DUNGEON = 81
-- Daily is detected via quest.questFlags (bit 1 = DAILY in classic era flags).
local TAG_ELITE   = 1
local TAG_RAID    = 62
local TAG_DUNGEON = 81

-- Returns true if Questie is available and the provider can be used.
function QuestieProvider:IsAvailable()
    return type(QuestieDB) == "table"
        and type(QuestieDB.GetQuest) == "function"
end

-- Lazy reverse-index: reverseChain[N] = questID whose nextQuestInChain == N.
-- Built once from QuestieDB.QuestPointers (the table of all questIDs in Questie).
-- Allows O(1) backward traversal to find the true chain root.
-- WARNING: QuestieDB.QuestPointers must exist in the installed Questie version.
-- If absent, chainID falls back to the current questID (chain matching across
-- players at different steps will break — document this to consumers).
local reverseChain = nil

local function buildReverseChain()
    if reverseChain then return reverseChain end
    reverseChain = {}
    local pointers = QuestieDB.QuestPointers or QuestieDB.questPointers
    if type(pointers) ~= "table" then
        -- QuestPointers not available in this Questie version. reverseChain stays empty.
        return reverseChain
    end
    for questID in pairs(pointers) do
        local ok, q = pcall(QuestieDB.GetQuest, questID)
        if ok and q and q.nextQuestInChain and q.nextQuestInChain ~= 0 then
            reverseChain[q.nextQuestInChain] = questID
        end
    end
    return reverseChain
end

-- Walk backward from questID to find the true chain root (the quest with no predecessor).
local function findChainRoot(questID)
    local rev = buildReverseChain()
    local current = questID
    local visited = {}
    while rev[current] and not visited[current] do
        visited[current] = true
        current = rev[current]
    end
    return current  -- returns questID itself if no predecessor is found
end

-- Build a chain starting from the true root, following nextQuestInChain forward.
-- Returns { chainRoot, steps[] } or nil if the quest is not part of a chain.
local function buildChain(startQuestID)
    local quest = QuestieDB.GetQuest(startQuestID)
    if not quest then return nil end

    local nextID = quest.nextQuestInChain
    if not nextID or nextID == 0 then
        -- Check if any quest points TO startQuestID (startQuestID may be a later step).
        local rev = buildReverseChain()
        if not rev[startQuestID] then
            return nil  -- standalone quest
        end
        -- startQuestID is a later step in a chain; fall through to root-finding below.
    end

    -- Find the true chain root by walking backward.
    local chainRoot = findChainRoot(startQuestID)

    -- Collect all steps by walking forward from the root.
    local steps = {}
    local current = chainRoot
    local visited = { [chainRoot] = true }

    while current do
        table.insert(steps, { questID = current })
        local q = QuestieDB.GetQuest(current)
        local nxt = q and q.nextQuestInChain
        if not nxt or nxt == 0 or visited[nxt] then break end
        visited[nxt] = true
        current = nxt
    end

    if #steps < 2 then return nil end  -- single-step "chain" is just a standalone quest

    return { chainRoot = chainRoot, steps = steps }
end

function QuestieProvider:GetChainInfo(questID)
    local chain = buildChain(questID)
    if not chain then
        return { knownStatus = "not_a_chain" }
    end

    local steps = chain.steps
    local chainID = chain.chainRoot
    local length = #steps

    -- Find the step index for questID within the steps array.
    local stepNum = nil
    for i, s in ipairs(steps) do
        if s.questID == questID then
            stepNum = i
            break
        end
    end

    -- Annotate each step with title and status.
    for _, s in ipairs(steps) do
        local sid = s.questID
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(sid) then
            s.status = "completed"
        elseif AQL.QuestCache and AQL.QuestCache:Get(sid) then
            local q = AQL.QuestCache:Get(sid)
            if q.isFailed then
                s.status = "failed"
            elseif q.isComplete then
                s.status = "finished"
            else
                s.status = "active"
            end
        else
            -- Quest not active and not in completion history.
            -- Determine available / unavailable / unknown.
            local prevIdx = nil
            for i, ps in ipairs(steps) do
                if ps.questID == sid then prevIdx = i break end
            end

            -- "unknown": questID is in the chain definition but QuestieDB cannot
            -- return data for it (QuestieDB.GetQuest returns nil). Only applies
            -- when the chain itself is known (knownStatus = "known") but this
            -- individual step's questID is missing from QuestieDB.
            local stepQuestData = QuestieDB.GetQuest(sid)
            -- Use `questID` (the parameter of GetChainInfo) not `startQuestID`
            -- (which is local to buildChain and out of scope here).
            if not stepQuestData and sid ~= questID then
                s.status = "unknown"
            elseif prevIdx and prevIdx > 1 then
                local prev = steps[prevIdx - 1]
                local prevCompleted = AQL.HistoryCache and AQL.HistoryCache:HasCompleted(prev.questID)
                s.status = prevCompleted and "available" or "unavailable"
            else
                s.status = "available"  -- first step, not yet started
            end
        end

        -- Title: prefer Questie's stored name, fall back to C_QuestLog title query,
        -- then a numeric placeholder. Note: C_QuestLog.GetTitleForQuestID is available
        -- in TBC Anniversary; verify in-game if it returns nil for inactive quests.
        local sq = QuestieDB.GetQuest(sid)
        s.title = (sq and sq.name) or C_QuestLog.GetTitleForQuestID(sid) or ("Quest "..sid)
    end

    return {
        knownStatus = "known",
        chainID     = chainID,
        step        = stepNum,
        length      = length,
        steps       = steps,
        provider    = "Questie",
    }
end

function QuestieProvider:GetQuestType(questID)
    local quest = QuestieDB.GetQuest(questID)
    if not quest then return nil end

    -- questTagIds field stores the quest's tag (from QuestieDB questKeys).
    local tag = quest.questTagId
    if tag == TAG_ELITE   then return "elite"   end
    if tag == TAG_RAID    then return "raid"    end
    if tag == TAG_DUNGEON then return "dungeon" end

    -- Daily detection: check zoneOrSort or questFlags depending on Questie version.
    -- Questie v11 uses a flags bitmask; bit 1 (value 1) = DAILY in Classic.
    if quest.questFlags and bit.band(quest.questFlags, 1) == 1 then
        return "daily"
    end

    return "normal"
end

function QuestieProvider:GetQuestFaction(questID)
    local quest = QuestieDB.GetQuest(questID)
    if not quest then return nil end
    -- Questie stores faction as a numeric: 0 = any, 1 = Horde, 2 = Alliance
    if quest.requiredFaction == 1 then return "Horde"    end
    if quest.requiredFaction == 2 then return "Alliance" end
    return nil
end

AQL.QuestieProvider = QuestieProvider
```

- [ ] **Step 2: Commit**

```bash
git add Providers/QuestieProvider.lua
git commit -m "feat: add QuestieProvider reading chain and type data from QuestieDB"
```

---

### Task 8: QuestWeaverProvider

**Files:**
- Create: `Providers/QuestWeaverProvider.lua`

- [ ] **Step 1: Write QuestWeaverProvider.lua**

```lua
-- Providers/QuestWeaverProvider.lua
-- Reads chain metadata from QuestWeaver if installed (and Questie is absent).
-- QuestWeaver stores quest data at _G["QuestWeaver"].Quests[questID].
-- Relevant fields: quest_series (array of questIDs), chain_id, chain_position,
-- chain_length. ChainBuilder:GetChain(questID) builds the full chain table.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local QuestWeaverProvider = {}

function QuestWeaverProvider:IsAvailable()
    local qw = _G["QuestWeaver"]
    return type(qw) == "table"
        and type(qw.Quests) == "table"
        and next(qw.Quests) ~= nil
end

function QuestWeaverProvider:GetChainInfo(questID)
    local qw = _G["QuestWeaver"]
    if not qw then return { knownStatus = "unknown" } end

    local quest = qw.Quests[questID]
    if not quest then return { knownStatus = "unknown" } end

    -- quest_series is an ordered array of questIDs in this chain.
    local series = quest.quest_series
    if not series or #series == 0 then
        return { knownStatus = "not_a_chain" }
    end

    local chainID = series[1]  -- first questID in the series
    local length  = #series
    local stepNum = nil

    local steps = {}
    for i, sid in ipairs(series) do
        if sid == questID then stepNum = i end

        local status
        if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(sid) then
            status = "completed"
        elseif AQL.QuestCache and AQL.QuestCache:Get(sid) then
            local q = AQL.QuestCache:Get(sid)
            if q.isFailed then
                status = "failed"
            elseif q.isComplete then
                status = "finished"
            else
                status = "active"
            end
        else
            -- "unknown": sid is in quest_series but absent from qw.Quests —
            -- the chain structure is known but this step's data is missing.
            if not qw.Quests[sid] then
                status = "unknown"
            elseif i == 1 then
                status = "available"
            else
                local prev = steps[i - 1]
                status = (prev and prev.status == "completed") and "available" or "unavailable"
            end
        end

        -- Title: prefer QuestWeaver stored name, fall back to C_QuestLog.
        local title = C_QuestLog.GetTitleForQuestID(sid) or ("Quest "..sid)
        local sqw = qw.Quests[sid]
        if sqw and sqw.name then title = sqw.name end

        steps[i] = { questID = sid, title = title, status = status }
    end

    return {
        knownStatus = "known",
        chainID     = chainID,
        step        = stepNum,
        length      = length,
        steps       = steps,
        provider    = "QuestWeaver",
    }
end

function QuestWeaverProvider:GetQuestType(questID)
    local qw = _G["QuestWeaver"]
    if not qw then return nil end
    local quest = qw.Quests and qw.Quests[questID]
    if not quest then return nil end
    -- QuestWeaver stores quest type in quest.quest_type (string) when present.
    return quest.quest_type or "normal"
end

function QuestWeaverProvider:GetQuestFaction(questID)
    local qw = _G["QuestWeaver"]
    if not qw then return nil end
    local quest = qw.Quests and qw.Quests[questID]
    if not quest then return nil end
    -- QuestWeaver faction field: "Alliance", "Horde", or nil.
    return quest.faction or nil
end

AQL.QuestWeaverProvider = QuestWeaverProvider
```

- [ ] **Step 2: Commit**

```bash
git add Providers/QuestWeaverProvider.lua
git commit -m "feat: add QuestWeaverProvider reading chain data from QuestWeaver globals"
```

---

## Chunk 4: EventEngine

The heart of AQL. Listens to WoW events, drives cache rebuilds, diffs old vs. new snapshots, and fires callbacks. After this chunk the library is fully functional end-to-end.

### Task 9: EventEngine

**Files:**
- Create: `Core/EventEngine.lua`

- [ ] **Step 1: Write Core/EventEngine.lua**

```lua
-- Core/EventEngine.lua
-- Owns the WoW event frame. On PLAYER_LOGIN, selects the chain provider and
-- triggers the initial cache build. On quest events, rebuilds QuestCache,
-- diffs old vs. new state at quest and objective granularity, and fires
-- AQL callbacks via CallbackHandler.
--
-- Re-entrancy guard: if QUEST_LOG_UPDATE fires while a diff is already running,
-- the second call is silently dropped. This is a known limitation — in normal
-- gameplay the next natural event will catch any missed state.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local EventEngine = {}
AQL.EventEngine = EventEngine

-- Set by QuestCache to track quests that have received QUEST_FAILED.
-- EventEngine writes here; QuestCache reads here during _buildEntry.
-- (QuestCache.failedSet is initialized in QuestCache.lua; we just write to it.)

EventEngine.diffInProgress   = false
EventEngine.initialized      = false

-- Hidden event frame.
local frame = CreateFrame("Frame")
EventEngine.frame = frame

------------------------------------------------------------------------
-- Provider selection
------------------------------------------------------------------------

local function selectProvider()
    -- Try Questie first.
    local ok1, result1 = pcall(function()
        return AQL.QuestieProvider
            and AQL.QuestieProvider:IsAvailable()
            and AQL.QuestieProvider
    end)
    if ok1 and result1 then
        return result1, "Questie"
    end

    -- Try QuestWeaver.
    local ok2, result2 = pcall(function()
        return AQL.QuestWeaverProvider
            and AQL.QuestWeaverProvider:IsAvailable()
            and AQL.QuestWeaverProvider
    end)
    if ok2 and result2 then
        return result2, "QuestWeaver"
    end

    -- Fallback.
    return AQL.NullProvider, "none"
end

------------------------------------------------------------------------
-- Diff + dispatch logic
------------------------------------------------------------------------

local function runDiff(oldCache)
    if EventEngine.diffInProgress then return end
    EventEngine.diffInProgress = true

    local ok, err = pcall(function()
        local newCache = AQL.QuestCache.data
        local histCache = AQL.HistoryCache

        -- Detect newly accepted quests (in new, not in old).
        for questID, newInfo in pairs(newCache) do
            if not oldCache[questID] then
                if histCache and histCache:HasCompleted(questID) then
                    -- Quest was already completed historically; ignore as a new accept.
                    -- (Can happen at login when cache first builds.)
                else
                    AQL.callbacks:Fire("AQL_QUEST_ACCEPTED", newInfo)
                end
            end
        end

        -- Detect removed quests (in old, not in new).
        for questID, oldInfo in pairs(oldCache) do
            if not newCache[questID] then
                -- Quest was removed from the log.
                if histCache and histCache:HasCompleted(questID) then
                    -- Already recorded by the QUEST_TURNED_IN handler before this
                    -- diff ran. MarkCompleted is idempotent so calling it again is
                    -- safe and ensures correctness if QUEST_TURNED_IN was missed.
                    histCache:MarkCompleted(questID)
                    AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
                else
                    -- No completion record → abandoned.
                    AQL.callbacks:Fire("AQL_QUEST_ABANDONED", oldInfo)
                end
            end
        end

        -- Detect changes in existing quests.
        for questID, newInfo in pairs(newCache) do
            local oldInfo = oldCache[questID]
            if oldInfo then
                -- isComplete transition.
                if newInfo.isComplete and not oldInfo.isComplete then
                    AQL.callbacks:Fire("AQL_QUEST_FINISHED", newInfo)
                end

                -- isFailed transition: quest newly failed.
                if newInfo.isFailed and not oldInfo.isFailed then
                    AQL.callbacks:Fire("AQL_QUEST_FAILED", newInfo)
                    -- Fire AQL_OBJECTIVE_FAILED for every unfinished objective
                    -- (the quest failing marks all incomplete objectives as failed).
                    for _, obj in ipairs(newInfo.objectives or {}) do
                        if not obj.isFinished then
                            -- Mark isFailed on the objective in the live snapshot.
                            obj.isFailed = true
                            AQL.callbacks:Fire("AQL_OBJECTIVE_FAILED", newInfo, obj)
                        end
                    end
                end

                -- isTracked transition.
                if newInfo.isTracked ~= oldInfo.isTracked then
                    if newInfo.isTracked then
                        AQL.callbacks:Fire("AQL_QUEST_TRACKED", newInfo)
                    else
                        AQL.callbacks:Fire("AQL_QUEST_UNTRACKED", newInfo)
                    end
                end

                -- Objective diff.
                local newObjs = newInfo.objectives or {}
                local oldObjs = oldInfo.objectives or {}
                for i, newObj in ipairs(newObjs) do
                    local oldObj = oldObjs[i]
                    if oldObj then
                        local newN = newObj.numFulfilled
                        local oldN = oldObj.numFulfilled
                        if newN > oldN then
                            local delta = newN - oldN
                            AQL.callbacks:Fire("AQL_OBJECTIVE_PROGRESSED", newInfo, newObj, delta)
                            -- Also fire COMPLETED if this progression crossed the threshold.
                            if newN >= newObj.numRequired and oldN < newObj.numRequired then
                                AQL.callbacks:Fire("AQL_OBJECTIVE_COMPLETED", newInfo, newObj)
                            end
                        elseif newN < oldN then
                            local delta = oldN - newN
                            AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)
                        end
                    end
                end
            end
        end
    end)

    EventEngine.diffInProgress = false

    if not ok then
        -- Log diff errors in debug mode; do not propagate.
        if AQL.debug then
            print("[AQL] EventEngine diff error: " .. tostring(err))
        end
    end
end

local function handleQuestLogUpdate()
    if not EventEngine.initialized then return end

    local oldCache = AQL.QuestCache:Rebuild()
    if oldCache == nil then return end  -- Rebuild failed (re-entrant guard from QuestCache side)

    runDiff(oldCache)
end

------------------------------------------------------------------------
-- WoW event handlers
------------------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Select the best available provider.
        local provider, providerName = selectProvider()
        AQL.provider = provider

        -- Trigger async history load.
        AQL.HistoryCache:Load(frame)

        -- Build the initial snapshot (no diff on first build).
        AQL.QuestCache:Rebuild()
        EventEngine.initialized = true

        -- Register for quest events now that we're ready.
        frame:RegisterEvent("QUEST_ACCEPTED")
        frame:RegisterEvent("QUEST_REMOVED")
        frame:RegisterEvent("QUEST_TURNED_IN")
        frame:RegisterEvent("QUEST_FAILED")
        frame:RegisterEvent("QUEST_LOG_UPDATE")
        frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
        frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")

    elseif event == "QUEST_QUERY_COMPLETE" then
        AQL.HistoryCache:OnQueryComplete()
        frame:UnregisterEvent("QUEST_QUERY_COMPLETE")

    elseif event == "QUEST_FAILED" then
        -- Mark the quest as failed before the next cache rebuild picks it up.
        local questID = select(2, ...)  -- QUEST_FAILED passes questID as arg2 in TBC Classic
        -- In TBC Classic, QUEST_FAILED may not pass a questID directly.
        -- As a fallback, mark all currently active quests that have isFailed
        -- based on the next QUEST_LOG_UPDATE (it will set isFailed via isComplete=-1).
        -- If questID is available, mark it directly.
        if questID and type(questID) == "number" then
            AQL.QuestCache.failedSet[questID] = true
        end
        handleQuestLogUpdate()

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

    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        local unit = ...
        if unit ~= "player" then
            -- Fire the AQL callback so SocialQuest can do its UnitIsOnQuest sweep.
            AQL.callbacks:Fire("AQL_UNIT_QUEST_LOG_CHANGED", unit)
        else
            -- Player's own log changed (e.g. item picked up that updates a quest).
            -- Run a diff. Note: QUEST_LOG_UPDATE will often fire too, but the
            -- re-entrancy guard (diffInProgress) prevents double-firing callbacks.
            handleQuestLogUpdate()
        end

    elseif event == "QUEST_WATCH_LIST_CHANGED"
        or event == "QUEST_LOG_UPDATE"
        or event == "QUEST_ACCEPTED"
        or event == "QUEST_REMOVED" then
        handleQuestLogUpdate()
    end
end)

-- Register only PLAYER_LOGIN at load time; everything else registers post-login.
frame:RegisterEvent("PLAYER_LOGIN")
```

- [ ] **Step 2: Load in WoW and verify**

```
/reload
```

Check for Lua errors. Then test that quests load:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local t = AQL:GetAllQuests(); local n = 0; for _ in pairs(t) do n = n + 1 end; print("Active quests:", n)
```
Expected: prints the number of quests currently in your quest log.

Test completion history:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); print("Completed quests:", AQL:GetCompletedQuestCount())
```
Expected: prints the number of quests your character has ever completed (may be 0 until QUEST_QUERY_COMPLETE fires — wait a second after login and try again).

Test a specific quest (replace 1 with a questID you know you have active):
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local q = AQL:GetQuest(1); if q then print(q.title, q.isComplete) else print("not active") end
```

Test that accepting a quest fires AQL_QUEST_ACCEPTED:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); AQL:RegisterCallback("AQL_QUEST_ACCEPTED", function(e, q) print("ACCEPTED:", q.title) end)
```
Then accept a quest. Expected: prints the quest title in chat.

Test objective progress fires AQL_OBJECTIVE_PROGRESSED:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); AQL:RegisterCallback("AQL_OBJECTIVE_PROGRESSED", function(e, q, obj, delta) print("PROGRESS:", q.title, delta) end)
```
Then kill a mob that counts toward a quest objective. Expected: prints quest title and delta.

- [ ] **Step 3: Commit**

```bash
git add Core/EventEngine.lua
git commit -m "feat: add EventEngine with WoW event listeners, diff logic, and callback dispatch"
```

---

## Chunk 5: Verification and Completion

End-to-end checklist matching the spec's Testing Checklist.

### Task 10: Final verification

- [ ] **Step 1: Verify library registration**
```
/run print(LibStub("AbsoluteQuestLog-1.0") ~= nil)
```
Expected: `true`

- [ ] **Step 2: Verify GetAllQuests matches quest log**

Count your quests in the default UI, then:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local n = 0; for _ in pairs(AQL:GetAllQuests()) do n = n + 1 end; print("AQL quests:", n)
```
Expected: same count as quest log.

- [ ] **Step 3: Verify HasCompletedQuest for a known completed quest**

Find a questID you know you completed. In-game, check with:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); print(AQL:HasCompletedQuest(INSERT_QUEST_ID_HERE))
```
Expected: `true`

- [ ] **Step 4: Verify AQL_QUEST_ABANDONED fires when abandoning**

Register the callback then abandon a test quest:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); AQL:RegisterCallback("AQL_QUEST_ABANDONED", function(e,q) print("ABANDONED:", q.title) end)
```

- [ ] **Step 5: Verify AQL_QUEST_FINISHED fires when objectives complete**

Register callback:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); AQL:RegisterCallback("AQL_QUEST_FINISHED", function(e,q) print("FINISHED:", q.title) end)
```
Complete all objectives on any quest. Expected: fires before turn-in.

- [ ] **Step 6: Verify AQL_QUEST_COMPLETED fires on turn-in**

Register callback:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); AQL:RegisterCallback("AQL_QUEST_COMPLETED", function(e,q) print("COMPLETED:", q.title) end)
```
Turn in a quest. Expected: fires after hand-in.

- [ ] **Step 7: Verify GetChainInfo returns correct knownStatus with neither provider**

With Questie and QuestWeaver both disabled:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local q = AQL:GetAllQuests(); for id, info in pairs(q) do print(id, info.chainInfo.knownStatus) break end
```
Expected: `unknown`

- [ ] **Step 8: Verify GetChainInfo with Questie installed**

With Questie enabled and a chain quest active:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); for id, info in pairs(AQL:GetAllQuests()) do if info.chainInfo.knownStatus == "known" then print(id, info.chainInfo.step, "/", info.chainInfo.length) break end end
```
Expected: prints step and length for a chain quest.

- [ ] **Step 9: Verify no crash with empty quest log**

Log out to a character with no quests. Run:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); print("quests:", AQL:GetCompletedQuestCount())
```
Expected: no errors, prints a number (may be 0 briefly before QUEST_QUERY_COMPLETE fires).

- [ ] **Step 10: Verify timed quest reports timerSeconds**

If you have a timed quest active:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); for id, q in pairs(AQL:GetAllQuests()) do if q.timerSeconds then print(q.title, "timer:", q.timerSeconds) end end
```
Expected: prints time remaining in seconds.

- [ ] **Step 11: Verify GetCompletedQuests count matches GetQuestsCompleted**

Wait ~2 seconds after login for QUEST_QUERY_COMPLETE, then:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local aqlCount = AQL:GetCompletedQuestCount(); local rawCount = 0; for _ in pairs(GetQuestsCompleted()) do rawCount = rawCount + 1 end; print("AQL:", aqlCount, "Raw:", rawCount)
```
Expected: both counts match.

- [ ] **Step 12: Verify AQL_OBJECTIVE_COMPLETED fires**

```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); AQL:RegisterCallback("AQL_OBJECTIVE_COMPLETED", function(e, q, obj) print("OBJ COMPLETE:", q.title, obj.text) end)
```
Complete a quest objective (kill the last required mob). Expected: prints after the final kill.

- [ ] **Step 13: Verify AQL_OBJECTIVE_FAILED fires when a quest fails**

```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); AQL:RegisterCallback("AQL_OBJECTIVE_FAILED", function(e, q, obj) print("OBJ FAILED:", q.title, obj.text) end)
```
Fail a timed or escort quest. Expected: fires once per unfinished objective.

- [ ] **Step 14: Verify provider fallback when Questie returns nil for one quest**

With Questie installed, run:
```
/run local ok, r = pcall(QuestieDB.GetQuest, 99999999); print("pcall ok:", ok, "result:", tostring(r))
```
Expected: no crash (pcall protects the call). AQL continues loading normally.

- [ ] **Step 15: Verify re-entrancy guard prevents double-firing**

Enable debug mode temporarily (set `AQL.debug = true`) and look for double-fired ACCEPTED events when accepting a quest. Expected: each event fires exactly once per quest accepted even if QUEST_LOG_UPDATE fires multiple times.

- [ ] **Step 16: Verify quest with no objectives does not crash objective diff**

Accept a quest known to have zero objectives (some escort-setup quests or event quests). Then:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); for id, q in pairs(AQL:GetAllQuests()) do if #q.objectives == 0 then print("No-obj quest:", q.title) break end end
```
Expected: no Lua errors, quest appears normally with empty objectives table.

- [ ] **Step 17: Verify full quest log (25 quests) initializes correctly**

Log in on a character with 25 active quests (the TBC limit). Run:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); local n = 0; for _ in pairs(AQL:GetAllQuests()) do n = n + 1 end; print("Quests:", n)
```
Expected: prints 25 (or however many are in the log), no errors.

- [ ] **Step 18: Verify GetChainInfo with QuestWeaver (Questie absent)**

Disable Questie, ensure QuestWeaver is enabled. Accept a chain quest. Run:
```
/run local AQL = LibStub("AbsoluteQuestLog-1.0"); for id, info in pairs(AQL:GetAllQuests()) do if info.chainInfo.knownStatus == "known" then print("QW chain:", id, info.chainInfo.provider, info.chainInfo.step, "/", info.chainInfo.length) break end end
```
Expected: prints "QW chain: [questID] QuestWeaver [step] / [length]".

- [ ] **Step 19: Final commit**

```bash
git add --all
git status  # confirm no unexpected files
git commit -m "feat: AbsoluteQuestLog v2.0 complete — LibStub library with CallbackHandler events and chain provider system"
```
