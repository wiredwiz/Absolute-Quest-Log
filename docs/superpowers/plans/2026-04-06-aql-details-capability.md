# AQL Details Capability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `AQL.Capability.Details` to the provider system, populating rich quest tooltip fields (`description`, `starterNPC`, `starterZone`, `finisherNPC`, `finisherZone`, `isDungeon`, `isRaid`) on `QuestInfo`, plus a derived `isGroup` convenience field.

**Architecture:** A fourth capability bucket `Details` is added alongside Chain, QuestInfo, and Requirements. Each provider implements `GetQuestDetails(questID)` returning a partial table — nil fields are simply omitted. Fields are merged onto `QuestInfo` in `_buildEntry` (cached quests) and `GetQuestInfo` Tier 3 (non-cached). `isGroup` is derived from `type` wherever type is set.

**Tech Stack:** Lua, LibStub, AceLocale. No new dependencies. Providers: QuestieProvider (full data), GrailProvider (NPC + dungeon/raid), NullProvider (nil stub).

---

## File Map

| File | Change |
|---|---|
| `AbsoluteQuestLog.lua` | Add `Capability.Details` enum entry; add `providers[Capability.Details]` slot; augment `GetQuestInfo` Tier 2 and Tier 3 to call `GetQuestDetails` and merge; derive `isGroup` from type |
| `Core/EventEngine.lua` | Add `Details` to `CAPABILITY_LABEL` and `getProviderPriority()` |
| `Core/QuestCache.lua` | Call `GetQuestDetails` in `_buildEntry`; derive `isGroup` from `questType` |
| `Providers/Provider.lua` | Document `GetQuestDetails` interface and field availability tiers |
| `Providers/NullProvider.lua` | Add `GetQuestDetails` returning nil |
| `Providers/QuestieProvider.lua` | Implement full `GetQuestDetails` |
| `Providers/GrailProvider.lua` | Implement partial `GetQuestDetails` |
| `CLAUDE.md` | Update QuestInfo data structure section with new fields and availability tiers |

---

### Task 1: Add `Capability.Details` enum and provider slot

**Files:**
- Modify: `AbsoluteQuestLog.lua:84-98`

- [ ] **Step 1: Add `Details` to the `AQL.Capability` table**

In `AbsoluteQuestLog.lua`, find the `AQL.Capability` table (around line 84) and add the `Details` entry:

```lua
AQL.Capability = {
    Chain        = "Chain",        -- GetChainInfo
    QuestInfo    = "QuestInfo",    -- GetQuestBasicInfo, GetQuestType, GetQuestFaction
    Requirements = "Requirements", -- GetQuestRequirements
    Details      = "Details",      -- GetQuestDetails
}
```

- [ ] **Step 2: Add `Details` slot to `AQL.providers`**

Find the `AQL.providers` table (around line 94) and add the Details slot:

```lua
AQL.providers = AQL.providers or {
    [AQL.Capability.Chain]        = nil,
    [AQL.Capability.QuestInfo]    = nil,
    [AQL.Capability.Requirements] = nil,
    [AQL.Capability.Details]      = nil,
}
```

- [ ] **Step 3: Verify the file loads without error**

Load WoW (or use `/reload`) and confirm no Lua errors in chat. No functionality should change yet since no provider implements `GetQuestDetails`.

- [ ] **Step 4: Commit**

```bash
git add AbsoluteQuestLog.lua
git commit -m "feat: add AQL.Capability.Details enum entry and providers slot"
```

---

### Task 2: Wire Details into EventEngine provider selection

**Files:**
- Modify: `Core/EventEngine.lua:75-96`

- [ ] **Step 1: Add `Details` to `CAPABILITY_LABEL`**

Find the `CAPABILITY_LABEL` table (around line 75) and add:

```lua
local CAPABILITY_LABEL = {
    [AQL.Capability.Chain]        = "quest chain",
    [AQL.Capability.QuestInfo]    = "quest info",
    [AQL.Capability.Requirements] = "requirements",
    [AQL.Capability.Details]      = "quest details",
}
```

- [ ] **Step 2: Add `Details` to `getProviderPriority()`**

Find `_PROVIDER_PRIORITY` inside `getProviderPriority()` (around line 89) and add the Details list. Priority: Questie → Grail (QuestWeaver and BtWQuests have no detail data).

```lua
_PROVIDER_PRIORITY = {
    [AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
    [AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
    [AQL.Capability.Requirements] = { AQL.QuestieProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
    [AQL.Capability.Details]      = { AQL.QuestieProvider, AQL.GrailProvider },
}
```

- [ ] **Step 3: Verify provider selection still works**

Log in and run `/aql debug on`. Confirm "Provider selected for Details: ..." message appears (once providers implement the capability — will show "No quest details provider found" until then, which is correct).

- [ ] **Step 4: Commit**

```bash
git add Core/EventEngine.lua
git commit -m "feat: add Details capability to EventEngine provider selection"
```

---

### Task 3: Add `GetQuestDetails` stub to NullProvider

**Files:**
- Modify: `Providers/NullProvider.lua`

- [ ] **Step 1: Add `GetQuestDetails` returning nil**

In `NullProvider`, after `GetQuestRequirements`, add:

```lua
function NullProvider:GetQuestDetails(questID)
    return nil
end
```

- [ ] **Step 2: Update `NullProvider.capabilities` to note Details is not covered**

`NullProvider.capabilities` is already `{}` (covers nothing) — no change needed.

- [ ] **Step 3: Commit**

```bash
git add Providers/NullProvider.lua
git commit -m "feat: add GetQuestDetails nil stub to NullProvider"
```

---

### Task 4: Implement `QuestieProvider:GetQuestDetails`

**Files:**
- Modify: `Providers/QuestieProvider.lua`

Questie data access (using existing `getDB()` helper):
- `quest.objectivesText` — key #8, array of strings — quest description/objectives text
- `quest.startedBy[1]` — array of NPC IDs that start the quest (key #2, index 1)
- `quest.finishedBy[1]` — array of NPC IDs that finish the quest (key #3, index 1)
- `quest.questTagId` — TAG_DUNGEON=81, TAG_RAID=62 (already defined as constants at top of file)
- NPC lookup: `db:GetNPC(npcId)` returns a table with `npc.name` (key #1) and `npc.zoneID` (key #9)
- NPC zone name: `WowQuestAPI.GetAreaInfo(npc.zoneID)` (same as used by `GetQuestBasicInfo`)

- [ ] **Step 1: Add `GetQuestDetails` to QuestieProvider**

Add after `GetQuestRequirements` (end of file, before `AQL.QuestieProvider = QuestieProvider`):

```lua
-- Helper: resolves the first NPC starter/finisher name and zone from a Questie NPC ID array.
-- Returns name, zone (both may be nil if NPC not in DB or zone not resolvable).
local function resolveNPCInfo(db, npcIds)
    if not npcIds or #npcIds == 0 then return nil, nil end
    local npcId = npcIds[1]
    if not npcId or npcId == 0 then return nil, nil end
    local ok, npc = pcall(db.GetNPC, db, npcId)
    if not ok or not npc then return nil, nil end
    local name = npc.name
    local zone
    if npc.zoneID and npc.zoneID > 0 then
        zone = WowQuestAPI.GetAreaInfo(npc.zoneID)
    end
    return name, zone
end

function QuestieProvider:GetQuestDetails(questID)
    local db = getDB()
    if not db then return nil end
    local ok, quest = pcall(db.GetQuest, questID)
    if not ok or not quest then return nil end

    -- Description: objectivesText is an array of strings; join or use first entry.
    local description
    if quest.objectivesText then
        if type(quest.objectivesText) == "table" then
            description = table.concat(quest.objectivesText, "\n")
        elseif type(quest.objectivesText) == "string" then
            description = quest.objectivesText
        end
        if description == "" then description = nil end
    end

    -- Starter NPC.
    local starterNPC, starterZone
    if quest.startedBy then
        starterNPC, starterZone = resolveNPCInfo(db, quest.startedBy[1])
    end

    -- Finisher NPC.
    local finisherNPC, finisherZone
    if quest.finishedBy then
        finisherNPC, finisherZone = resolveNPCInfo(db, quest.finishedBy[1])
    end

    -- Dungeon / raid flags from questTagId.
    local isDungeon = (quest.questTagId == TAG_DUNGEON) or nil
    local isRaid    = (quest.questTagId == TAG_RAID)    or nil
    -- Normalize false → nil so callers can just check truthiness.
    if isDungeon == false then isDungeon = nil end
    if isRaid    == false then isRaid    = nil end

    -- Return nil when we have nothing useful to contribute.
    if not description and not starterNPC and not finisherNPC
       and not isDungeon and not isRaid then
        return nil
    end

    return {
        description  = description,
        starterNPC   = starterNPC,
        starterZone  = starterZone,
        finisherNPC  = finisherNPC,
        finisherZone = finisherZone,
        isDungeon    = isDungeon,
        isRaid       = isRaid,
    }
end
```

- [ ] **Step 2: Add `Details` to `QuestieProvider.capabilities`**

Find the `QuestieProvider.capabilities` table (around line 22) and add Details:

```lua
QuestieProvider.capabilities = {
    AQL.Capability.Chain,
    AQL.Capability.QuestInfo,
    AQL.Capability.Requirements,
    AQL.Capability.Details,
}
```

- [ ] **Step 3: Verify in-game**

With Questie installed, run in `/aql debug verbose` mode and accept a quest. Check that the rebuilt cache entry has no errors. Use `/script local q = LibStub("AbsoluteQuestLog-1.0"):GetQuestInfo(questID) print(q and q.description or "nil")` to confirm description is populated.

- [ ] **Step 4: Commit**

```bash
git add Providers/QuestieProvider.lua
git commit -m "feat: implement QuestieProvider:GetQuestDetails with description, NPC, dungeon/raid"
```

---

### Task 5: Implement `GrailProvider:GetQuestDetails`

**Files:**
- Modify: `Providers/GrailProvider.lua`

Grail API used (based on existing `GetQuestBasicInfo` patterns):
- `g:QuestLocationsAccept(questID)` — returns array of location objects; `locs[1].mapArea` is a uiMapID
- `g:QuestLocationsTurnin(questID)` — same structure for turn-in locations
- `g:MapAreaName(mapArea)` — converts uiMapID to localized zone name string
- `g:IsDungeon(questID)`, `g:IsRaid(questID)` — bool flags (already used in `GetQuestType`)
- NPC name: `-- TODO: verify Grail API` — Grail may expose NPC names via `g:NPCName(npcID)` if the location record contains an NPC ID. If unavailable, only zone is returned.

- [ ] **Step 1: Add `GetQuestDetails` to GrailProvider**

Add after `GetQuestRequirements`:

```lua
-- Helper: resolves zone name from a Grail location record array.
-- Returns zone string or nil.
local function grailLocationZone(g, locs)
    if not locs or not locs[1] then return nil end
    local mapArea = locs[1].mapArea
    if not mapArea then return nil end
    return g:MapAreaName(mapArea)
end

function GrailProvider:GetQuestDetails(questID)
    local g = _G["Grail"]
    if not g then return nil end

    local starterZone  = grailLocationZone(g, g:QuestLocationsAccept(questID))
    local finisherZone = grailLocationZone(g, g:QuestLocationsTurnin and g:QuestLocationsTurnin(questID))

    -- isDungeon / isRaid already computed in GetQuestType; reuse same API.
    local isDungeon = g:IsDungeon(questID) or nil
    local isRaid    = g:IsRaid(questID)    or nil
    if isDungeon == false then isDungeon = nil end
    if isRaid    == false then isRaid    = nil end

    if not starterZone and not finisherZone and not isDungeon and not isRaid then
        return nil
    end

    return {
        starterZone  = starterZone,
        finisherZone = finisherZone,
        isDungeon    = isDungeon,
        isRaid       = isRaid,
        -- starterNPC / finisherNPC: omitted — Grail location records do not expose
        -- NPC names directly. TODO: verify if g:NPCName(npcID) exists and if
        -- location records carry npcID fields.
    }
end
```

- [ ] **Step 2: Add `Details` to `GrailProvider.capabilities`**

```lua
GrailProvider.capabilities = {
    AQL.Capability.Chain,
    AQL.Capability.QuestInfo,
    AQL.Capability.Requirements,
    AQL.Capability.Details,
}
```

- [ ] **Step 3: Commit**

```bash
git add Providers/GrailProvider.lua
git commit -m "feat: implement GrailProvider:GetQuestDetails with zone and dungeon/raid"
```

---

### Task 6: Merge Details fields in `QuestCache._buildEntry` and derive `isGroup`

**Files:**
- Modify: `Core/QuestCache.lua:200-249`

The current `_buildEntry` (around line 200) calls the QuestInfo provider for `GetQuestType` and `GetQuestFaction`. We add a Details provider call immediately after, then derive `isGroup` from the resolved `questType`.

- [ ] **Step 1: Add Details provider call and `isGroup` derivation to `_buildEntry`**

Find the provider block in `_buildEntry` (around line 200–220) and extend it:

```lua
    local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
    local questType, questFaction
    local questDetails  -- NEW

    local chainProvider = AQL.providers and AQL.providers[AQL.Capability.Chain]
    if chainProvider then
        local ok, result = pcall(chainProvider.GetChainInfo, chainProvider, questID)
        if ok and result then chainInfo = result end
    end

    local infoProvider = AQL.providers and AQL.providers[AQL.Capability.QuestInfo]
    if infoProvider then
        local ok2, result2 = pcall(infoProvider.GetQuestType, infoProvider, questID)
        if ok2 then questType = result2 end

        local ok3, result3 = pcall(infoProvider.GetQuestFaction, infoProvider, questID)
        if ok3 then questFaction = result3 end
    end

    -- NEW: Details capability — description, NPC info, dungeon/raid flags.
    local detailsProvider = AQL.providers and AQL.providers[AQL.Capability.Details]
    if detailsProvider then
        local ok4, result4 = pcall(detailsProvider.GetQuestDetails, detailsProvider, questID)
        if ok4 then questDetails = result4 end
    end

    -- NEW: isGroup — derived from type; true when type is elite, dungeon, or raid.
    local isGroup = (questType == AQL.QuestType.Elite
                  or questType == AQL.QuestType.Dungeon
                  or questType == AQL.QuestType.Raid) or nil
    if isGroup == false then isGroup = nil end
```

- [ ] **Step 2: Merge `questDetails` fields and `isGroup` into the returned entry**

Find the `return { ... }` block at the end of `_buildEntry` (around line 230) and add the new fields:

```lua
    return {
        questID        = questID,
        title          = info.title or "",
        level          = info.level or 0,
        suggestedGroup = tonumber(info.suggestedGroup) or 0,
        zone           = zone,
        type           = questType,
        faction        = questFaction,
        isGroup        = isGroup,                                           -- NEW
        description    = questDetails and questDetails.description  or nil, -- NEW
        starterNPC     = questDetails and questDetails.starterNPC    or nil, -- NEW
        starterZone    = questDetails and questDetails.starterZone   or nil, -- NEW
        finisherNPC    = questDetails and questDetails.finisherNPC   or nil, -- NEW
        finisherZone   = questDetails and questDetails.finisherZone  or nil, -- NEW
        isDungeon      = questDetails and questDetails.isDungeon     or nil, -- NEW
        isRaid         = questDetails and questDetails.isRaid        or nil, -- NEW
        isComplete     = isComplete,
        isFailed       = isFailed,
        failReason     = failReason,
        isTracked      = isTracked,
        link           = link,
        logIndex       = logIndex,
        snapshotTime   = GetTime(),
        timerSeconds   = timerSeconds,
        objectives     = objectives,
        chainInfo      = chainInfo,
    }
```

- [ ] **Step 3: Verify in-game**

Accept a quest and run:
```lua
/script local q = LibStub("AbsoluteQuestLog-1.0"):GetQuest(questID) if q then print(q.isGroup, q.isDungeon, q.starterNPC) end
```
For a dungeon quest: `isGroup` should be `true`, `isDungeon` should be `true`.
For a normal quest: `isGroup` should be `nil`.

- [ ] **Step 4: Commit**

```bash
git add Core/QuestCache.lua
git commit -m "feat: merge Details fields and derive isGroup in QuestCache._buildEntry"
```

---

### Task 7: Merge Details fields in `GetQuestInfo` Tier 3

**Files:**
- Modify: `AbsoluteQuestLog.lua:416-475`

`GetQuestInfo` Tier 3 handles quests not in the active log (remote party member quests, alias questIDs). We add a Details provider call and `isGroup` derivation to this path. Also augment the Tier 2 path (zone-absent case) similarly.

- [ ] **Step 1: Add Details merge to `GetQuestInfo` Tier 2 augmentation block**

In `GetQuestInfo`, find the `if not result.zone then` block (around line 427) and extend it to also call `GetQuestDetails`:

```lua
        if not result.zone then
            local infoProvider  = self.providers and self.providers[AQL.Capability.QuestInfo]
            local chainProvider = self.providers and self.providers[AQL.Capability.Chain]
            local detailsProvider = self.providers and self.providers[AQL.Capability.Details]  -- NEW
            if infoProvider and infoProvider.GetQuestBasicInfo then
                local ok, basicInfo = pcall(infoProvider.GetQuestBasicInfo, infoProvider, questID)
                if ok and basicInfo then
                    result.zone          = result.zone          or basicInfo.zone
                    result.level         = result.level         or basicInfo.questLevel
                    result.requiredLevel = result.requiredLevel or basicInfo.requiredLevel
                    result.title         = result.title         or basicInfo.title
                end
            end
            if chainProvider then
                local ok, ci = pcall(chainProvider.GetChainInfo, chainProvider, questID)
                if ok and ci then
                    result.chainInfo = result.chainInfo or ci
                end
            end
            -- NEW: merge detail fields for non-cached quests.
            if detailsProvider then
                local ok, details = pcall(detailsProvider.GetQuestDetails, detailsProvider, questID)
                if ok and details then
                    result.description  = result.description  or details.description
                    result.starterNPC   = result.starterNPC   or details.starterNPC
                    result.starterZone  = result.starterZone  or details.starterZone
                    result.finisherNPC  = result.finisherNPC  or details.finisherNPC
                    result.finisherZone = result.finisherZone or details.finisherZone
                    result.isDungeon    = result.isDungeon    or details.isDungeon
                    result.isRaid       = result.isRaid       or details.isRaid
                end
            end
        end
```

- [ ] **Step 2: Add `isGroup` derivation to Tier 2 return path**

Immediately before `return result` in the Tier 2 block (after the `if not result.zone then` block):

```lua
        -- Derive isGroup from type (if type was populated by infoProvider or cache).
        if result.type then
            result.isGroup = (result.type == AQL.QuestType.Elite
                           or result.type == AQL.QuestType.Dungeon
                           or result.type == AQL.QuestType.Raid) or nil
            if result.isGroup == false then result.isGroup = nil end
        end
        return result
```

- [ ] **Step 3: Add Details merge and `isGroup` derivation to Tier 3 return block**

Find the Tier 3 provider block (around line 449) and add after the existing `basicInfo` / `chainInfo` calls:

```lua
    -- NEW: Details provider.
    local detailsProvider = self.providers and self.providers[AQL.Capability.Details]
    local questDetails
    if detailsProvider then
        local ok, details = pcall(detailsProvider.GetQuestDetails, detailsProvider, questID)
        if ok and details then questDetails = details end
    end

    -- NEW: type and isGroup for non-cached quests.
    local questType, isGroup
    local infoProviderT3 = self.providers and self.providers[AQL.Capability.QuestInfo]
    if infoProviderT3 then
        local ok, t = pcall(infoProviderT3.GetQuestType, infoProviderT3, questID)
        if ok and t then questType = t end
    end
    if questType then
        isGroup = (questType == AQL.QuestType.Elite
                or questType == AQL.QuestType.Dungeon
                or questType == AQL.QuestType.Raid) or nil
        if isGroup == false then isGroup = nil end
    end
```

Then in the `return { ... }` block at Tier 3:

```lua
    return {
        questID       = questID,
        title         = basicInfo and basicInfo.title         or nil,
        level         = basicInfo and basicInfo.questLevel    or nil,
        requiredLevel = basicInfo and basicInfo.requiredLevel or nil,
        zone          = basicInfo and basicInfo.zone          or nil,
        chainInfo     = chainInfo,
        type          = questType,                                          -- NEW
        isGroup       = isGroup,                                            -- NEW
        description   = questDetails and questDetails.description  or nil, -- NEW
        starterNPC    = questDetails and questDetails.starterNPC    or nil, -- NEW
        starterZone   = questDetails and questDetails.starterZone   or nil, -- NEW
        finisherNPC   = questDetails and questDetails.finisherNPC   or nil, -- NEW
        finisherZone  = questDetails and questDetails.finisherZone  or nil, -- NEW
        isDungeon     = questDetails and questDetails.isDungeon     or nil, -- NEW
        isRaid        = questDetails and questDetails.isRaid        or nil, -- NEW
    }
```

- [ ] **Step 4: Verify with a remote quest (non-cached)**

Use `/script local q = LibStub("AbsoluteQuestLog-1.0"):GetQuestInfo(someQuestIDNotInLog) if q then print(q.starterNPC, q.isDungeon, q.isGroup) end` for a known dungeon quest like RFC (questID 1127 on TBC).

- [ ] **Step 5: Commit**

```bash
git add AbsoluteQuestLog.lua
git commit -m "feat: merge Details fields and isGroup into GetQuestInfo Tier 2 and Tier 3"
```

---

### Task 8: Update `Provider.lua` documentation and `CLAUDE.md`

**Files:**
- Modify: `Providers/Provider.lua`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Document `GetQuestDetails` in `Provider.lua`**

Add to the provider interface documentation in `Providers/Provider.lua`:

```lua
-- GetQuestDetails(questID) → table or nil
--   Returns a partial table of rich tooltip fields. Nil fields are absent (not present in
--   the returned table). Returns nil entirely when the provider has no data for the quest.
--   Fields and availability:
--     description  (string) — quest body/objectives text.        Questie only.
--     starterNPC   (string) — quest-giver NPC name.              Questie + Grail (partial).
--     starterZone  (string) — zone of quest-giver.               Questie + Grail.
--     finisherNPC  (string) — turn-in NPC name.                  Questie + Grail (partial).
--     finisherZone (string) — zone of turn-in NPC.               Questie + Grail.
--     isDungeon    (bool)   — true when quest is a dungeon quest. Questie + Grail.
--     isRaid       (bool)   — true when quest is a raid quest.    Questie + Grail.
--   Providers that cannot supply a field must omit it (not set it to nil or false).
```

- [ ] **Step 2: Update `CLAUDE.md` QuestInfo data structure**

In the `CLAUDE.md` QuestInfo structure section, add the new fields with availability annotations. Insert after the `type` field:

```
isGroup        = bool or nil,    -- DERIVED: true when type is elite/dungeon/raid. Nil when type is nil.
description    = "string" or nil, -- DETAILS: quest body text. Questie only.
starterNPC     = "string" or nil, -- DETAILS: quest-giver NPC name. Questie + Grail (partial).
starterZone    = "string" or nil, -- DETAILS: zone of quest-giver. Questie + Grail.
finisherNPC    = "string" or nil, -- DETAILS: turn-in NPC name. Questie + Grail (partial).
finisherZone   = "string" or nil, -- DETAILS: zone of turn-in NPC. Questie + Grail.
isDungeon      = bool or nil,    -- DETAILS: true for dungeon quests. Questie + Grail.
isRaid         = bool or nil,    -- DETAILS: true for raid quests. Questie + Grail.
```

Also add a "Field Availability Tiers" note below the structure:
```
-- Field availability tiers:
--   Guaranteed:      questID, title, isGroup (when type is set)
--   Usually present  (~60-70% of users, Questie or Grail installed):
--                    starterNPC*, starterZone, finisherNPC*, finisherZone, isDungeon, isRaid
--                    (* NPC name requires Questie; Grail provides zone only currently)
--   Less likely      (~40-50% of users, Questie only):
--                    description
```

Update the Provider Interface section to list `GetQuestDetails` under the required methods.

Also bump the AQL version per the versioning rule (first change today → increment minor, reset revision). Update `AbsoluteQuestLog.toc` and all other TOC files, and add a changelog entry.

- [ ] **Step 3: Run tests**

AQL has no automated unit tests. Verify in-game:
1. `/aql debug on` — confirm "Provider selected for Details: Questie" appears on login
2. `/script local q = LibStub("AbsoluteQuestLog-1.0"):GetQuestInfo(questID) for k,v in pairs(q) do print(k,v) end` on a quest in the log — confirm new fields appear
3. No Lua errors in chat during normal play

- [ ] **Step 4: Commit**

```bash
git add Providers/Provider.lua CLAUDE.md AbsoluteQuestLog.lua AbsoluteQuestLog.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_Mainline.toc changelog.txt
git commit -m "docs: document GetQuestDetails interface, update CLAUDE.md QuestInfo fields, bump version"
```
