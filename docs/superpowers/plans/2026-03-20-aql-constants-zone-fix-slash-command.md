# AQL Constants, Zone Augmentation, and Slash Command Redesign — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six enumeration constant tables to AQL, fix remote quest zone resolution via Tier 2→3 augmentation in `GetQuestInfo`, restructure the `/aql` slash command to require a `debug` subcommand, and update SocialQuest to use the new constants.

**Architecture:** Constant tables are added to `AbsoluteQuestLog.lua` at module scope (loads first per TOC — all other files see them immediately). Raw string literals across all AQL files and SocialQuest are mechanically replaced with constant references; string values are unchanged so runtime behavior is identical. The zone fix modifies only the `AQL:GetQuestInfo` Tier 2 early-return to augment before returning when zone is absent. The slash command handler body is replaced in-place.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary (Interface 20505), LibStub library pattern. No automated test runner — verification is done in-game and via grep.

**Repos touched:**
- Primary: `D:/Projects/Wow Addons/Absolute-Quest-Log/`
- Secondary: `D:/Projects/Wow Addons/Social-Quest/`

---

## Chunk 1: AQL String Constants

### Task 1: Add constant tables to AbsoluteQuestLog.lua and replace existing raw strings in that file

**Files:**
- Modify: `AbsoluteQuestLog.lua` (add six tables after color constants; replace three raw strings in `GetChainInfo` and `GetQuestInfo`)

---

- [ ] **Step 1: Read AbsoluteQuestLog.lua and confirm current state**

Open `AbsoluteQuestLog.lua`. Confirm:
- Lines 12–15 contain the three color constants (`AQL.RED`, `AQL.RESET`, `AQL.DBG`)
- Lines 17–24 contain the sub-module slots comment block ending before the `--------` Public API divider
- The `GetChainInfo` function contains `return { knownStatus = "unknown" }`
- The `GetQuestInfo` function contains `local chainInfo = { knownStatus = "unknown" }` and `chainInfo.knownStatus == "unknown"`

---

- [ ] **Step 2: Insert the six constant tables after the sub-module slots comment block**

In `AbsoluteQuestLog.lua`, locate the blank line that separates the sub-module slots comment from the `--------` Public API divider. Insert the following block immediately before that divider:

```lua
------------------------------------------------------------------------
-- Enumeration Constants
-- Public — consumers reference AQL.ChainStatus, AQL.Provider, etc.
-- String values are unchanged; these tables are the canonical reference.
-- Tables are mutable by convention only (no __newindex guard).
------------------------------------------------------------------------

AQL.ChainStatus = {
    Known     = "known",
    NotAChain = "not_a_chain",
    Unknown   = "unknown",
}

AQL.StepStatus = {
    Completed   = "completed",
    Active      = "active",
    Finished    = "finished",
    Failed      = "failed",
    Available   = "available",
    Unavailable = "unavailable",
    Unknown     = "unknown",
}

AQL.Provider = {
    Questie     = "Questie",
    QuestWeaver = "QuestWeaver",
    None        = "none",
}

AQL.QuestType = {
    Normal  = "normal",
    Elite   = "elite",
    Dungeon = "dungeon",
    Raid    = "raid",
    Daily   = "daily",
    PvP     = "pvp",
    Escort  = "escort",
}

AQL.Faction = {
    Alliance = "Alliance",
    Horde    = "Horde",
}

AQL.FailReason = {
    Timeout    = "timeout",
    EscortDied = "escort_died",
}

```

---

- [ ] **Step 3: Replace the three raw knownStatus strings in AbsoluteQuestLog.lua**

In `GetChainInfo`, replace:
```lua
    return { knownStatus = "unknown" }
```
with:
```lua
    return { knownStatus = AQL.ChainStatus.Unknown }
```

In `GetQuestInfo` (Tier 3 block), replace:
```lua
    local chainInfo = { knownStatus = "unknown" }
```
with:
```lua
    local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
```

In `GetQuestInfo` (Tier 3 block, the early-return guard), replace:
```lua
    if not basicInfo and chainInfo.knownStatus == "unknown" then return nil end
```
with:
```lua
    if not basicInfo and chainInfo.knownStatus == AQL.ChainStatus.Unknown then return nil end
```

---

- [ ] **Step 4: Verify**

Grep `AbsoluteQuestLog.lua` for `"unknown"` and `"known"`. The only remaining hits should be inside the constant table definitions (lines like `Unknown = "unknown"`, `Known = "known"`) and the `GetQuestInfo` function comment header. No raw comparisons or table constructions should remain.

---

- [ ] **Step 5: Commit**

```bash
cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
git add AbsoluteQuestLog.lua
git commit -m "$(cat <<'EOF'
feat: add AQL enumeration constant tables; replace raw strings in AbsoluteQuestLog.lua

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Replace raw strings in Core/EventEngine.lua

**Files:**
- Modify: `Core/EventEngine.lua` (three string literals: two `failReason` assignments and one quest type comparison)

---

- [ ] **Step 1: Read Core/EventEngine.lua and confirm the three target lines**

Open `Core/EventEngine.lua`. In the `runDiff` function, in the block that infers fail reason for a removed quest, confirm:
- A line reads `failReason = "timeout"` (inside the timer-remaining check)
- A line reads `if not failReason and oldInfo.type == "escort" then`
- A line reads `failReason = "escort_died"`

There is no `{ knownStatus = ... }` construction in EventEngine — only the three strings above need replacing.

---

- [ ] **Step 2: Replace the three raw string literals**

Replace:
```lua
                        failReason = "timeout"
```
with:
```lua
                        failReason = AQL.FailReason.Timeout
```

Replace:
```lua
                    if not failReason and oldInfo.type == "escort" then
                        failReason = "escort_died"
```
with:
```lua
                    if not failReason and oldInfo.type == AQL.QuestType.Escort then
                        failReason = AQL.FailReason.EscortDied
```

---

- [ ] **Step 3: Verify**

Grep `Core/EventEngine.lua` for `== "escort"` (the type comparison), `"timeout"`, and `"escort_died"` as code-level string literals. Expected: zero matches. The comment on line 17 which mentions these strings in prose is acceptable.

---

- [ ] **Step 4: Commit**

```bash
git add Core/EventEngine.lua
git commit -m "$(cat <<'EOF'
refactor: replace raw failReason and quest type strings in EventEngine with AQL constants

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Replace raw strings in Core/QuestCache.lua

**Files:**
- Modify: `Core/QuestCache.lua` (one raw string: `chainInfo` initialization in `_buildEntry`)

---

- [ ] **Step 1: Read Core/QuestCache.lua and confirm the target line**

Open `Core/QuestCache.lua`. In `_buildEntry`, confirm a line reads:
```lua
    local chainInfo = { knownStatus = "unknown" }
```

Note: `type = obj.type or "log"` also appears in this file — `"log"` is a raw WoW API objective-type value, not an AQL enum. Leave it unchanged.

---

- [ ] **Step 2: Replace the raw string**

Replace:
```lua
    local chainInfo = { knownStatus = "unknown" }
```
with:
```lua
    local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
```

---

- [ ] **Step 3: Verify**

Grep `Core/QuestCache.lua` for `"unknown"`. Expected: zero matches. (`"log"` remains — confirm it is present and untouched.)

---

- [ ] **Step 4: Commit**

```bash
git add Core/QuestCache.lua
git commit -m "$(cat <<'EOF'
refactor: replace raw knownStatus string in QuestCache with AQL constant

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Replace raw strings in Providers/QuestieProvider.lua

**Files:**
- Modify: `Providers/QuestieProvider.lua` (knownStatus values, step status assignments, provider name, quest type returns, faction returns)

---

- [ ] **Step 1: Read the full Providers/QuestieProvider.lua**

Open `Providers/QuestieProvider.lua`. Confirm the locations of all raw string literals. Key blocks to find:
- `GetChainInfo`: two `{ knownStatus = ... }` returns and one `knownStatus = "known"` in the final return table, plus `provider = "Questie"`
- Step annotation loop inside `GetChainInfo`: seven status string assignments
- `GetQuestType`: four type return statements (`"elite"`, `"raid"`, `"dungeon"`, `"daily"`, `"normal"`)
- `GetQuestFaction`: two faction return statements (`"Horde"`, `"Alliance"`)

---

- [ ] **Step 2: Replace knownStatus and provider strings in GetChainInfo**

Replace:
```lua
    if not db then return { knownStatus = "unknown" } end
```
with:
```lua
    if not db then return { knownStatus = AQL.ChainStatus.Unknown } end
```

Replace:
```lua
        return { knownStatus = "not_a_chain" }
```
with:
```lua
        return { knownStatus = AQL.ChainStatus.NotAChain }
```

In the final `return { ... }` table at the end of `GetChainInfo`, replace:
```lua
        knownStatus = "known",
```
with:
```lua
        knownStatus = AQL.ChainStatus.Known,
```

In that same return table, replace:
```lua
        provider    = "Questie",
```
with:
```lua
        provider    = AQL.Provider.Questie,
```

---

- [ ] **Step 3: Replace step status string literals in the step annotation loop**

In the step annotation loop inside `GetChainInfo`, replace each status assignment:

```lua
                s.status = "completed"
```
→
```lua
                s.status = AQL.StepStatus.Completed
```

```lua
                    s.status = "failed"
```
→
```lua
                    s.status = AQL.StepStatus.Failed
```

```lua
                    s.status = "finished"
```
→
```lua
                    s.status = AQL.StepStatus.Finished
```

```lua
                    s.status = "active"
```
→
```lua
                    s.status = AQL.StepStatus.Active
```

```lua
                s.status = "unknown"
```
→
```lua
                s.status = AQL.StepStatus.Unknown
```

```lua
                    s.status = prevCompleted and "available" or "unavailable"
```
→
```lua
                    s.status = prevCompleted and AQL.StepStatus.Available or AQL.StepStatus.Unavailable
```

```lua
                s.status = "available"  -- first step, not yet started
```
→
```lua
                s.status = AQL.StepStatus.Available  -- first step, not yet started
```

---

- [ ] **Step 4: Replace quest type return strings in GetQuestType**

Replace:
```lua
    if tag == TAG_ELITE   then return "elite"   end
    if tag == TAG_RAID    then return "raid"    end
    if tag == TAG_DUNGEON then return "dungeon" end
```
with:
```lua
    if tag == TAG_ELITE   then return AQL.QuestType.Elite   end
    if tag == TAG_RAID    then return AQL.QuestType.Raid    end
    if tag == TAG_DUNGEON then return AQL.QuestType.Dungeon end
```

Replace (inside the daily flag check):
```lua
        return "daily"
```
with:
```lua
        return AQL.QuestType.Daily
```

Replace (the final fallback):
```lua
    return "normal"
```
with:
```lua
    return AQL.QuestType.Normal
```

---

- [ ] **Step 5: Replace faction return strings in GetQuestFaction**

Replace:
```lua
    if quest.requiredFaction == 1 then return "Horde"    end
    if quest.requiredFaction == 2 then return "Alliance" end
```
with:
```lua
    if quest.requiredFaction == 1 then return AQL.Faction.Horde    end
    if quest.requiredFaction == 2 then return AQL.Faction.Alliance end
```

---

- [ ] **Step 6: Verify**

Grep `Providers/QuestieProvider.lua` for each of the following string literals and confirm zero code-level matches (comments are acceptable):
`"known"`, `"not_a_chain"`, `"unknown"`, `"completed"`, `"active"`, `"finished"`, `"failed"`, `"available"`, `"unavailable"`, `"Questie"`, `"elite"`, `"raid"`, `"dungeon"`, `"daily"`, `"normal"`, `"Horde"`, `"Alliance"`

---

- [ ] **Step 7: Commit**

```bash
git add Providers/QuestieProvider.lua
git commit -m "$(cat <<'EOF'
refactor: replace raw string literals in QuestieProvider with AQL constants

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Replace raw strings in Providers/QuestWeaverProvider.lua

**Files:**
- Modify: `Providers/QuestWeaverProvider.lua` (knownStatus values, step status assignments, provider name, quest type fallback)

---

- [ ] **Step 1: Read the full Providers/QuestWeaverProvider.lua**

Open `Providers/QuestWeaverProvider.lua`. Confirm the locations of all raw string literals. Key blocks:
- `GetChainInfo`: two `{ knownStatus = "unknown" }` returns (one for missing `qw`, one for missing `quest`), one `{ knownStatus = "not_a_chain" }`, and `knownStatus = "known"` plus `provider = "QuestWeaver"` in the final return
- Step status loop: six status assignments including one compound `and/or` expression that also compares against `"completed"`
- `GetQuestType`: one `"normal"` fallback in `quest.quest_type or "normal"`

---

- [ ] **Step 2: Replace knownStatus and provider strings in GetChainInfo**

Replace:
```lua
    if not qw then return { knownStatus = "unknown" } end
```
with:
```lua
    if not qw then return { knownStatus = AQL.ChainStatus.Unknown } end
```

Replace:
```lua
    if not quest then return { knownStatus = "unknown" } end
```
with:
```lua
    if not quest then return { knownStatus = AQL.ChainStatus.Unknown } end
```

Replace:
```lua
        return { knownStatus = "not_a_chain" }
```
with:
```lua
        return { knownStatus = AQL.ChainStatus.NotAChain }
```

In the final `return { ... }` table, replace:
```lua
        knownStatus = "known",
```
with:
```lua
        knownStatus = AQL.ChainStatus.Known,
```

In that same return table, replace:
```lua
        provider    = "QuestWeaver",
```
with:
```lua
        provider    = AQL.Provider.QuestWeaver,
```

---

- [ ] **Step 3: Replace step status string literals in the step loop**

Replace each status assignment, including the one compound expression that compares a previous step's status:

```lua
            status = "completed"
```
→ `AQL.StepStatus.Completed`

```lua
                status = "failed"
```
→ `AQL.StepStatus.Failed`

```lua
                status = "finished"
```
→ `AQL.StepStatus.Finished`

```lua
                status = "active"
```
→ `AQL.StepStatus.Active`

```lua
                status = "unknown"
```
→ `AQL.StepStatus.Unknown`

```lua
                status = "available"
```
→ `AQL.StepStatus.Available` (applies to both the `i == 1` branch and any standalone assignment)

```lua
                status = (prev and prev.status == "completed") and "available" or "unavailable"
```
→
```lua
                status = (prev and prev.status == AQL.StepStatus.Completed) and AQL.StepStatus.Available or AQL.StepStatus.Unavailable
```

---

- [ ] **Step 4: Replace the quest type fallback**

In `GetQuestType`, replace:
```lua
    return quest.quest_type or "normal"
```
with:
```lua
    return quest.quest_type or AQL.QuestType.Normal
```

`quest.quest_type` is a QuestWeaver-native string and is left as-is — only the `"normal"` fallback literal is replaced.

---

- [ ] **Step 5: Verify**

Grep `Providers/QuestWeaverProvider.lua` for `"unknown"`, `"not_a_chain"`, `"known"`, `"completed"`, `"failed"`, `"finished"`, `"active"`, `"available"`, `"unavailable"`, `"QuestWeaver"` (as a return string), `"normal"` (as fallback). Expected: zero code-level matches.

---

- [ ] **Step 6: Commit**

```bash
git add Providers/QuestWeaverProvider.lua
git commit -m "$(cat <<'EOF'
refactor: replace raw string literals in QuestWeaverProvider with AQL constants

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Replace raw string in Providers/NullProvider.lua

**Files:**
- Modify: `Providers/NullProvider.lua` (one raw string: `knownStatus` in `GetChainInfo`)

---

- [ ] **Step 1: Read Providers/NullProvider.lua and confirm the target line**

Open `Providers/NullProvider.lua`. Confirm that `GetChainInfo` returns:
```lua
    return { knownStatus = "unknown" }
```

---

- [ ] **Step 2: Replace the raw string**

Replace:
```lua
    return { knownStatus = "unknown" }
```
with:
```lua
    return { knownStatus = AQL.ChainStatus.Unknown }
```

---

- [ ] **Step 3: Verify**

Grep `Providers/NullProvider.lua` for `"unknown"`. Expected: zero matches.

---

- [ ] **Step 4: Commit**

```bash
git add Providers/NullProvider.lua
git commit -m "$(cat <<'EOF'
refactor: replace raw knownStatus string in NullProvider with AQL constant

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Chunk 2: Zone Fix, Slash Command, and SocialQuest

### Task 7: Fix GetQuestInfo Tier 2 → Tier 3 zone augmentation

**Files:**
- Modify: `AbsoluteQuestLog.lua` (`AQL:GetQuestInfo` — Tier 2 early-return block only)

---

- [ ] **Step 1: Read the current GetQuestInfo function**

Open `AbsoluteQuestLog.lua`. Find `AQL:GetQuestInfo`. Confirm the Tier 2 block currently reads:
```lua
    -- Tier 2: WoW log scan / title fallback.
    local result = WowQuestAPI.GetQuestInfo(questID)
    if result then return result end
```

Note: after Task 1 (Chunk 1), the Tier 3 block's `local chainInfo` line already reads `{ knownStatus = AQL.ChainStatus.Unknown }`. The Tier 3 block is unchanged by this task.

---

- [ ] **Step 2: Replace the Tier 2 early-return with augmentation logic**

Replace:
```lua
    -- Tier 2: WoW log scan / title fallback.
    local result = WowQuestAPI.GetQuestInfo(questID)
    if result then return result end
```
with:
```lua
    -- Tier 2: WoW log scan / title fallback.
    local result = WowQuestAPI.GetQuestInfo(questID)
    if result then
        -- Augment with Tier 3 if zone is absent (title-only path: quest not in
        -- player's log). Zone is nil only in that path; the log-scan path always
        -- sets zone from the zone-header row. All provider calls are pcall-guarded.
        if not result.zone then
            local provider = self.provider
            if provider then
                if provider.GetQuestBasicInfo then
                    local ok, basicInfo = pcall(provider.GetQuestBasicInfo, provider, questID)
                    if ok and basicInfo then
                        result.zone          = result.zone          or basicInfo.zone
                        result.level         = result.level         or basicInfo.questLevel
                        result.requiredLevel = result.requiredLevel or basicInfo.requiredLevel
                        result.title         = result.title         or basicInfo.title
                    end
                end
                if provider.GetChainInfo then
                    local ok, ci = pcall(provider.GetChainInfo, provider, questID)
                    if ok and ci then
                        result.chainInfo = result.chainInfo or ci
                    end
                end
            end
        end
        return result
    end
```

---

- [ ] **Step 3: Update the GetQuestInfo function comment to reflect augmentation**

Locate the doc comment immediately above `AQL:GetQuestInfo`. It currently says:
```lua
--   Tier 2: WowQuestAPI log scan → { questID, title, level, suggestedGroup, isComplete, zone }
--           or title-only { questID, title } when not in log
```

Replace those two lines with:
```lua
--   Tier 2: WowQuestAPI log scan → { questID, title, level, suggestedGroup, isComplete, zone }
--           or title-only { questID, title } when not in log; augmented from Tier 3 when zone absent
```

---

- [ ] **Step 4: Verify the full GetQuestInfo function shape**

Read the updated function. Confirm:
- Tier 1 (QuestCache check) is unchanged
- Tier 2 block: `local result = ...` followed by `if result then` with the augmentation block, ending in `return result` inside the `if`
- Tier 3 block (below): `local provider = self.provider`, `if not provider then return nil end`, `local basicInfo`, etc. — all unchanged

---

- [ ] **Step 5: Commit**

```bash
cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
git add AbsoluteQuestLog.lua
git commit -m "$(cat <<'EOF'
fix(GetQuestInfo): augment Tier 2 title-only result with Tier 3 zone and chain data

When C_QuestLog.GetQuestInfo returns a title for a quest not in the player's
log, continue to provider (Questie/QuestWeaver) to fill in zone, level,
requiredLevel, and chainInfo. Fixes remote quests appearing in 'Other Quests'.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Restructure the /aql slash command

**Files:**
- Modify: `AbsoluteQuestLog.lua` (slash command handler body only — `SLASH_ABSOLUTEQUESTLOG1` line is unchanged)

---

- [ ] **Step 1: Read the current slash command handler**

Open `AbsoluteQuestLog.lua` near the bottom. Confirm the current handler:
- Matches input against `"on"`, `"normal"`, `"verbose"`, `"off"` directly using a single `cmd` variable
- Prints `[AQL] Usage: /aql [on|normal|verbose|off]`
- `SLASH_ABSOLUTEQUESTLOG1 = "/aql"` appears on the line immediately above `SlashCmdList[...]`

---

- [ ] **Step 2: Replace the handler body**

Replace the entire `SlashCmdList["ABSOLUTEQUESTLOG"] = function(input) ... end` block with:

```lua
SlashCmdList["ABSOLUTEQUESTLOG"] = function(input)
    -- Look up the library at call time so this handler is robust even if the
    -- file was loaded more than once (e.g. two copies on the load path).
    local aql = LibStub("AbsoluteQuestLog-1.0", true)
    if not aql then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[AQL] Error: library not loaded|r")
        return
    end
    local sub, arg = (input or ""):match("^%s*(%S+)%s*(.-)%s*$")
    sub = sub and sub:lower() or ""
    arg = arg and arg:lower() or ""

    if sub == "debug" then
        if arg == "on" or arg == "normal" then
            aql.debug = "normal"
            DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Debug mode: normal" .. aql.RESET)
        elseif arg == "verbose" then
            aql.debug = "verbose"
            DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Debug mode: verbose" .. aql.RESET)
        elseif arg == "off" then
            aql.debug = nil
            DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Debug mode: off" .. aql.RESET)
        else
            DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Usage: /aql debug [on|normal|verbose|off]" .. aql.RESET)
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage(aql.DBG .. "[AQL] Usage: /aql debug [on|normal|verbose|off]" .. aql.RESET)
    end
end
```

---

- [ ] **Step 3: Verify**

Read the bottom of `AbsoluteQuestLog.lua`. Confirm:
- `SLASH_ABSOLUTEQUESTLOG1 = "/aql"` is present and unchanged
- The handler body matches the above exactly
- No usage message exists with the form `/aql [on|normal|verbose|off]` (i.e., without the `debug` subcommand in between)

---

- [ ] **Step 4: Commit**

```bash
git add AbsoluteQuestLog.lua
git commit -m "$(cat <<'EOF'
feat: restructure /aql slash command — require 'debug' subcommand

/aql on|normal|verbose|off is now /aql debug on|normal|verbose|off.
Deliberate breaking change; adds a slot for future subcommands.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Update SocialQuest to use AQL.ChainStatus constants

**Prerequisite: Chunk 1 Task 1 must be complete.** `AQL.ChainStatus` must be defined in `AbsoluteQuestLog.lua` before any step in this task is executed. Step 1 below verifies this — if the table is absent, stop.

**Files:**
- Modify: `D:/Projects/Wow Addons/Social-Quest/Core/Announcements.lua` (line 46)
- Modify: `D:/Projects/Wow Addons/Social-Quest/UI/RowFactory.lua` (line 222)
- Modify: `D:/Projects/Wow Addons/Social-Quest/UI/TabUtils.lua` (lines 37, 41)
- Modify: `D:/Projects/Wow Addons/Social-Quest/UI/Tabs/MineTab.lua` (lines 60, 77)
- Modify: `D:/Projects/Wow Addons/Social-Quest/UI/Tabs/PartyTab.lua` (lines 32, 33, 74, 75, 160)
- Modify: `D:/Projects/Wow Addons/Social-Quest/UI/Tabs/SharedTab.lua` (lines 31, 198)

`AQL` is **not** a global in SocialQuest files. It is accessed via `local AQL = SocialQuest.AQL` at function scope. Most target functions already have this local declared; two do not and must use `SocialQuest.AQL.ChainStatus.Known` directly. Since these constants evaluate to the same strings (`"known"`, `"unknown"`), all comparisons produce identical runtime results.

**AQL scope per target:**
- `Core/Announcements.lua:46` — `appendChainStep` has **no** `local AQL` → use `SocialQuest.AQL.ChainStatus.Known`
- `UI/RowFactory.lua:222` — this file has **no** `local AQL` at all → use `SocialQuest.AQL.ChainStatus.Known`
- `UI/TabUtils.lua:37,41` — `GetChainInfoForQuestID` declares `local AQL = SocialQuest.AQL` at line 35 → use `AQL.ChainStatus.Known`
- `UI/Tabs/MineTab.lua:60,77` — `BuildTree()` declares `local AQL = SocialQuest.AQL` at line 21 → use `AQL.ChainStatus.Known`
- `UI/Tabs/PartyTab.lua:32,33,74,75` — `buildPlayerRowsForQuest` declares `local AQL = SocialQuest.AQL` at line 16 → use `AQL.ChainStatus.Known`
- `UI/Tabs/PartyTab.lua:160` — `BuildTree()` declares `local AQL = SocialQuest.AQL` at line 105 → use `AQL.ChainStatus.Known`
- `UI/Tabs/SharedTab.lua:31,198` — `BuildTree()` declares `local AQL = SocialQuest.AQL` at line 20 → use `AQL.ChainStatus.Known`/`AQL.ChainStatus.Unknown`

---

- [ ] **Step 1: Verify AQL constants prerequisite**

Open `D:/Projects/Wow Addons/Absolute-Quest-Log/AbsoluteQuestLog.lua`. Confirm that `AQL.ChainStatus`, `AQL.ChainStatus.Known`, and `AQL.ChainStatus.Unknown` are defined (added by Task 1 in Chunk 1). If they are not present, stop — Chunk 1 must be completed before proceeding with this task.

---

- [ ] **Step 2: Update Core/Announcements.lua**

In `D:/Projects/Wow Addons/Social-Quest/Core/Announcements.lua`, replace:
```lua
    if not chainInfo or chainInfo.knownStatus ~= "known" or not chainInfo.step then
```
with:
```lua
    if not chainInfo or chainInfo.knownStatus ~= SocialQuest.AQL.ChainStatus.Known or not chainInfo.step then
```

(`appendChainStep` has no `local AQL`, so `SocialQuest.AQL` is used directly.)

---

- [ ] **Step 3: Update UI/RowFactory.lua**

Replace:
```lua
    if ci and ci.knownStatus == "known" then
```
with:
```lua
    if ci and ci.knownStatus == SocialQuest.AQL.ChainStatus.Known then
```

(No `local AQL` exists in this file, so `SocialQuest.AQL` is used directly.)

---

- [ ] **Step 4: Update UI/TabUtils.lua**

Replace (line 37):
```lua
    if ci.knownStatus == "known" then return ci end
```
with:
```lua
    if ci.knownStatus == AQL.ChainStatus.Known then return ci end
```

Replace (line 41):
```lua
        if ok and result and result.knownStatus == "known" then return result end
```
with:
```lua
        if ok and result and result.knownStatus == AQL.ChainStatus.Known then return result end
```

---

- [ ] **Step 5: Update UI/Tabs/MineTab.lua**

Replace (line 60):
```lua
        if ci and ci.knownStatus == "known" and ci.chainID then
```
with:
```lua
        if ci and ci.knownStatus == AQL.ChainStatus.Known and ci.chainID then
```

Replace (line 77):
```lua
                        if pCI.knownStatus == "known"
```
with:
```lua
                        if pCI.knownStatus == AQL.ChainStatus.Known
```

---

- [ ] **Step 6: Update UI/Tabs/PartyTab.lua**

Replace lines 32–33:
```lua
            step           = ci and ci.knownStatus == "known" and ci.step       or nil,
            chainLength    = ci and ci.knownStatus == "known" and ci.length     or nil,
```
with:
```lua
            step           = ci and ci.knownStatus == AQL.ChainStatus.Known and ci.step       or nil,
            chainLength    = ci and ci.knownStatus == AQL.ChainStatus.Known and ci.length     or nil,
```

Replace lines 74–75:
```lua
                step           = pCI.knownStatus == "known" and pCI.step   or nil,
                chainLength    = pCI.knownStatus == "known" and pCI.length or nil,
```
with:
```lua
                step           = pCI.knownStatus == AQL.ChainStatus.Known and pCI.step   or nil,
                chainLength    = pCI.knownStatus == AQL.ChainStatus.Known and pCI.length or nil,
```

Replace (line 160):
```lua
        if ci.knownStatus == "known" and ci.chainID then
```
with:
```lua
        if ci.knownStatus == AQL.ChainStatus.Known and ci.chainID then
```

---

- [ ] **Step 7: Update UI/Tabs/SharedTab.lua**

Replace (line 31):
```lua
        if ci.knownStatus == "known" and ci.chainID then
```
with:
```lua
        if ci.knownStatus == AQL.ChainStatus.Known and ci.chainID then
```

Replace (line 198):
```lua
                chainInfo      = { knownStatus = "unknown" },
```
with:
```lua
                chainInfo      = { knownStatus = AQL.ChainStatus.Unknown },
```

---

- [ ] **Step 8: Verify**

Grep the SocialQuest directory for `knownStatus.*"known"` and `knownStatus.*"unknown"`. Expected: zero matches. All 12 `"known"` comparisons and the one `"unknown"` construction should now use `AQL.ChainStatus.*`.

---

- [ ] **Step 9: Commit**

```bash
cd "D:/Projects/Wow Addons/Social-Quest"
git add Core/Announcements.lua UI/RowFactory.lua UI/TabUtils.lua UI/Tabs/MineTab.lua UI/Tabs/PartyTab.lua UI/Tabs/SharedTab.lua
git commit -m "$(cat <<'EOF'
refactor: replace raw knownStatus strings with AQL.ChainStatus constants

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Chunk 3: Version Bumps, Documentation, and Verification

### Task 10: Bump AQL version and update CLAUDE.md

**Files:**
- Modify: `D:/Projects/Wow Addons/Absolute-Quest-Log/AbsoluteQuestLog.toc`
- Modify: `D:/Projects/Wow Addons/Absolute-Quest-Log/CLAUDE.md`

Today is 2026-03-20. This is the first functional modification to AQL today. Per the versioning rule: increment minor version, reset revision to 0. `2.0` → `2.1.0`.

---

- [ ] **Step 1: Bump version in AbsoluteQuestLog.toc**

In `AbsoluteQuestLog.toc`, change:
```
## Version: 2.0
```
to:
```
## Version: 2.1.0
```

---

- [ ] **Step 2: Update the Debug System section in CLAUDE.md**

In `CLAUDE.md` (AQL repo), find the Debug System section. It currently reads:
```
`/aql [on|normal|verbose|off]` — Controls debug output to `DEFAULT_CHAT_FRAME`.
```

Replace that line with:
```
`/aql debug [on|normal|verbose|off]` — Controls debug output to `DEFAULT_CHAT_FRAME`.
```

---

- [ ] **Step 3: Add version entry to CLAUDE.md**

In `CLAUDE.md` (AQL repo), in the Version History section, add a new entry above the existing `### Version 2.0` entry:

```markdown
### Version 2.1.0 (March 2026)
- Added `AQL.ChainStatus`, `AQL.StepStatus`, `AQL.Provider`, `AQL.QuestType`, `AQL.Faction`, `AQL.FailReason` enumeration constant tables; all raw string literals in AQL source replaced with these constants
- Fixed `AQL:GetQuestInfo` Tier 2→3 augmentation: remote quests now resolve zone, level, and chainInfo from Questie/QuestWeaver when not in the player's log (fixes "Other Quests" grouping in SocialQuest Party tab)
- Restructured `/aql` slash command: debug mode now requires `/aql debug [on|normal|verbose|off]`
```

---

- [ ] **Step 4: Commit AQL version bump**

```bash
cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
git add AbsoluteQuestLog.toc CLAUDE.md
git commit -m "$(cat <<'EOF'
chore: bump version to 2.1.0, update CLAUDE.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Bump SocialQuest version and update CLAUDE.md

**Files:**
- Modify: `D:/Projects/Wow Addons/Social-Quest/SocialQuest.toc`
- Modify: `D:/Projects/Wow Addons/Social-Quest/CLAUDE.md`

Today is 2026-03-20. SocialQuest is currently at version 2.1.1, which was the second change today. This is another same-day change: increment revision only. `2.1.1` → `2.1.2`.

---

- [ ] **Step 1: Bump version in SocialQuest.toc**

In `SocialQuest.toc`, change:
```
## Version: 2.1.1
```
to:
```
## Version: 2.1.2
```

---

- [ ] **Step 2: Add version entry to SocialQuest CLAUDE.md**

In `CLAUDE.md` (SocialQuest repo), add a new version entry above the existing `### Version 2.1.1` entry:

```markdown
### Version 2.1.2 (March 2026 — Improvements branch)
- Updated all `knownStatus` comparisons to use `AQL.ChainStatus.Known` / `AQL.ChainStatus.Unknown` constants
```

---

- [ ] **Step 3: Commit SocialQuest version bump**

```bash
cd "D:/Projects/Wow Addons/Social-Quest"
git add SocialQuest.toc CLAUDE.md
git commit -m "$(cat <<'EOF'
chore: bump version to 2.1.2, update CLAUDE.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: In-game verification

Load both addons in WoW (Interface 20505 / TBC Anniversary).

- [ ] **Step 1: Verify slash command**

Type `/aql`. Expected: gold usage message `[AQL] Usage: /aql debug [on|normal|verbose|off]`.
Type `/aql on`. Expected: same usage message (old bare syntax is now broken — intentional).
Type `/aql debug on`. Expected: `[AQL] Debug mode: normal`.
Type `/aql debug verbose`. Expected: `[AQL] Debug mode: verbose`.
Type `/aql debug off`. Expected: `[AQL] Debug mode: off`.

- [ ] **Step 2: Verify no Lua errors at login**

Enable debug mode (`/aql debug normal`) and watch the chat frame during login. Expected: no red `[AQL]` error messages. Normal `[AQL]` debug output is expected and acceptable.

- [ ] **Step 3: Verify zone resolution for remote quests**

Open the SocialQuest frame (`/sq`). With a party member who has quests that Questie knows about, check the Party tab. Expected: quests appear under their correct zone headers (e.g., "Hellfire Peninsula", "Zangarmarsh") rather than "Other Quests".

- [ ] **Step 4: Verify no regressions in chain display**

In the Mine tab, find a quest that is part of a chain. Confirm chain step info (e.g., "Step 2/4") still displays correctly. In the Shared tab, verify chain grouping is unchanged.

- [ ] **Step 5: Verify objective progress and quest events still fire**

Make progress on a quest objective. Confirm the SocialQuest banner notification appears in chat as before. Confirm no `[AQL]` errors appear.
