# AQL Constants, Zone Augmentation, and Slash Command Redesign — Design Spec

## Overview

Three related improvements to AbsoluteQuestLog-1.0:

1. **String constants** — Replace bare string literals used as enumeration values with named tables on the `AQL` object, making them accessible to consumers without requiring string duplication.
2. **Tier 2 zone augmentation** — When `AQL:GetQuestInfo` returns a Tier 2 title-only result (quest not in player's log), augment it with all available fields from the Tier 3 provider before returning, rather than returning a partial result.
3. **Slash command restructure** — Change `/aql [on|normal|verbose|off]` to `/aql debug [on|normal|verbose|off]` to make the intent explicit and leave room for future subcommands.

---

## 1. String Constants

### Problem

String literals like `"known"`, `"Questie"`, `"escort"`, `"timeout"` are scattered across multiple AQL source files and are part of the public API surface (returned in `QuestInfo`, `ChainInfo`, and callback arguments). Consumers must duplicate these strings to compare against them.

### Solution

Define six constant tables on the `AQL` object in `AbsoluteQuestLog.lua` at module scope, before the public API methods. Each table maps a PascalCase key to its string value. The string values are unchanged — existing comparisons continue to work. The tables are the new canonical reference.

```lua
AQL.ChainStatus = {
    Known      = "known",
    NotAChain  = "not_a_chain",
    Unknown    = "unknown",
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

`AQL.DebugMode` is explicitly **not** defined — debug mode strings (`"normal"`, `"verbose"`) are internal implementation details with no consumer value.

### Key Design Notes

**Load order is already correct.** `AbsoluteQuestLog.lua` is the first file listed in the TOC. All Core and Provider files load after it, so `AQL.ChainStatus.*` etc. are defined before any of them execute.

**`AQL.Faction` has no neutral value.** `GetQuestFaction` returns `nil` (not a string) for quests available to both factions. No provider in the codebase produces any faction string other than `"Alliance"` and `"Horde"` — there is no `"Neutral"` or `"Both"` string to enumerate.

**`AQL.QuestType` key naming convention.** Keys use PascalCase matching the style of all other constant tables. All future additions should follow this convention.

**`AQL.StepStatus` values are a passthrough.** `Finished`, `Failed`, `Active`, etc. are existing strings already in the codebase — this change does not alter their semantics, only replaces bare string literals with constant references.

**`AQL.ChainStatus.Unknown` and `AQL.StepStatus.Unknown` both map to `"unknown"`.** This is intentional — they are semantically distinct fields on different structures (`chainInfo.knownStatus` vs. `step.status`), not duplicates to be merged.

**Constants tables are mutable by convention only.** Lua tables are mutable by default; no `__newindex` guard is added. Consumers are expected not to modify them. This is consistent with how AQL's other module tables (`QuestCache`, `EventEngine`, etc.) work.

**`"log"` in `QuestCache._buildEntry` is an objective type, not a quest type.** `type = obj.type or "log"` sets the `type` field on an individual objective row (from `C_QuestLog.GetQuestObjectives`), not on the `QuestInfo` itself. `QuestInfo.type` (the quest's type) comes from `provider:GetQuestType` and is always one of the `AQL.QuestType` values or nil. `"log"` never appears in `QuestInfo.type` and is correctly excluded from `AQL.QuestType`.

### Files Changed

All raw string literals in AQL source files that correspond to these constants are replaced with the constant references, and SocialQuest is updated to use them where it currently compares against AQL-owned strings. The listed replacements are all known occurrences; the implementer should verify completeness by grepping each file for the raw string values after making changes.

**`AbsoluteQuestLog.lua`** — Add the six tables above.

**`Core/EventEngine.lua`** — Replace:
- `{ knownStatus = "unknown" }` → `{ knownStatus = AQL.ChainStatus.Unknown }`
- `failReason = "timeout"` → `failReason = AQL.FailReason.Timeout`
- `failReason = "escort_died"` → `failReason = AQL.FailReason.EscortDied`
- `oldInfo.type == "escort"` → `oldInfo.type == AQL.QuestType.Escort`

**`Core/QuestCache.lua`** — Replace:
- `{ knownStatus = "unknown" }` → `{ knownStatus = AQL.ChainStatus.Unknown }`
- `type = obj.type or "log"` — `"log"` is a raw WoW API value, not an AQL enum; leave as-is

**`Providers/QuestieProvider.lua`** — Replace:
- `return { knownStatus = "not_a_chain" }` → `AQL.ChainStatus.NotAChain`
- `return { knownStatus = "unknown" }` → `AQL.ChainStatus.Unknown`
- `knownStatus = "known"` → `AQL.ChainStatus.Known`
- `s.status = "completed"` → `AQL.StepStatus.Completed`
- `s.status = "active"` / `"finished"` / `"failed"` / `"available"` / `"unavailable"` / `"unknown"` → corresponding `AQL.StepStatus.*`
- `provider = "Questie"` → `AQL.Provider.Questie`
- `if tag == TAG_ELITE then return "elite" end` → `return AQL.QuestType.Elite`, etc.
- `if quest.requiredFaction == 1 then return "Horde" end` → `return AQL.Faction.Horde`, etc.

**`Providers/QuestWeaverProvider.lua`** — Replace:
- `return { knownStatus = "unknown" }` / `"not_a_chain"` / `"known"` → `AQL.ChainStatus.*`
- `status = "completed"` / `"failed"` / etc. → `AQL.StepStatus.*`
- `provider = "QuestWeaver"` → `AQL.Provider.QuestWeaver`
- `return quest.quest_type or "normal"` — `quest.quest_type` is a QuestWeaver-native string that passes through unfiltered; replace the `"normal"` fallback literal only: `return quest.quest_type or AQL.QuestType.Normal`. QuestWeaver may return type strings not in `AQL.QuestType` (e.g. a QuestWeaver-specific value). This is intentional — provider-native strings pass through for compatibility. Consumers comparing against `AQL.QuestType.*` will not match unmapped values; this is acceptable and unchanged from the current behavior where any string can appear in `QuestInfo.type`.

**`Providers/NullProvider.lua`** — No string constants used; no changes.

**`D:\Projects\Wow Addons\Social-Quest` (multiple files)** — SocialQuest uses `knownStatus == "known"` in 12 places across 6 files, and constructs `{ knownStatus = "unknown" }` directly in one place. These are the only AQL-owned string values SocialQuest references; all other strings in SocialQuest (`"finished"`, `"completed"`, `"failed"`, etc.) are SocialQuest-internal and are not AQL constants. Replace:

- `Core/Announcements.lua:46` — `chainInfo.knownStatus ~= "known"` → `~= AQL.ChainStatus.Known`
- `UI/RowFactory.lua:222` — `ci.knownStatus == "known"` → `== AQL.ChainStatus.Known`
- `UI/TabUtils.lua:37,41` — two occurrences of `knownStatus == "known"` → `AQL.ChainStatus.Known`
- `UI/Tabs/MineTab.lua:60,77` — two occurrences → `AQL.ChainStatus.Known`
- `UI/Tabs/PartyTab.lua:32,33,74,75,160` — five occurrences → `AQL.ChainStatus.Known`
- `UI/Tabs/SharedTab.lua:31` — `ci.knownStatus == "known"` → `AQL.ChainStatus.Known`
- `UI/Tabs/SharedTab.lua:198` — `{ knownStatus = "unknown" }` → `{ knownStatus = AQL.ChainStatus.Unknown }`

SocialQuest accesses `AQL` via its existing `LibStub("AbsoluteQuestLog-1.0")` reference. The constant tables are available as soon as AQL loads, which happens before SocialQuest files run (AQL is a listed dependency in SocialQuest's TOC).

---

## 2. Tier 2 Zone Augmentation in `GetQuestInfo`

### Problem

`AQL:GetQuestInfo` has three resolution tiers:
- **Tier 1** — QuestCache (full snapshot; only for quests in the player's active log)
- **Tier 2** — `WowQuestAPI.GetQuestInfo`: log scan (full data) or `C_QuestLog.GetQuestInfo` title-only fallback (quest not in log)
- **Tier 3** — provider (`GetQuestBasicInfo` + `GetChainInfo`): zone from Questie/QuestWeaver DB

When a quest is not in the player's log, `WowQuestAPI.GetQuestInfo` calls `C_QuestLog.GetQuestInfo(questID)`, which on TBC 20505 returns only a title string. It wraps this as `{ questID, title }` and returns it. `AQL:GetQuestInfo` hits `if result then return result` and exits — Tier 3 is never reached, so `zone`, `level`, `requiredLevel`, and `chainInfo` are never populated. This causes party members' quests to appear under "Other Quests" in SocialQuest's Party tab (which groups by zone).

### Root Cause

The `if result then return result` guard in `AQL:GetQuestInfo` does not distinguish between a full Tier 2 result (quest in log — has zone) and a partial Tier 2 result (quest not in log — title only, no zone).

### Fix

After Tier 2 returns, check whether enrichment from Tier 3 is both needed and possible. The trigger condition is `not result.zone` — this is always nil in the title-only path and always populated in the log-scan path, making it a clean discriminator. `zone` is either a string or nil in `WowQuestAPI.GetQuestInfo` results — it is never `false` or any other falsy non-nil value, so `not result.zone` is safe to use as the guard.

**Provider method signatures** (both return a single value via `pcall`):
- `provider:GetQuestBasicInfo(questID)` → a **named-key table** `{ title = ..., questLevel = ..., requiredLevel = ..., zone = ... }` or `nil` if the quest is not in the provider's DB. The code accesses `basicInfo.zone`, `basicInfo.questLevel`, etc. — named keys, not positional array indices.
- `provider:GetChainInfo(questID)` → ChainInfo table (always non-nil; returns `{ knownStatus = "unknown" }` at minimum). Always a single return value.

**`self.provider`** is the existing access pattern already used in `AQL:GetQuestInfo`. The augmentation block uses the same pattern — no change to how the provider is accessed.

**Tier 2 title-only result shape:** `{ questID = questID, title = title }` — named keys. `result.zone`, `result.level`, and `result.requiredLevel` are all absent (nil) in this path. `result.title` is always a non-nil string.

When `not result.zone` and a provider is available:
1. Call `provider:GetQuestBasicInfo(questID)` (if it exists) to get `zone`, `questLevel`, `requiredLevel`, `title`.
2. Call `provider:GetChainInfo(questID)` (if it exists) to get `chainInfo`.
3. Merge into the existing result table: Tier 2 fields win for any field already set; Tier 3 fills only nil fields.

Each provider call is individually wrapped in `pcall`. If Tier 3 provides nothing useful (provider unavailable, quest not in DB, pcall fails), the Tier 2 result is returned as-is — same behavior as today.

**Merge semantics within the `not result.zone` guard:** In the title-only path (the only path that reaches this block), `result.zone`, `result.level`, and `result.requiredLevel` are always nil — so the `or` assignments for those three are redundant but correct and harmless. `result.title` is always non-nil (Tier 2 always has a title), so `result.title or basicInfo.title` always preserves the Tier 2 title. The `or` on title is purely defensive.

**`chainInfo` from Tier 3:** `GetChainInfo` may return `{ knownStatus = "not_a_chain" }` or `{ knownStatus = "unknown" }` — both are valid, non-nil results. Merging either into `result.chainInfo` is intentional and correct: it is exactly what the existing Tier 3 path already returns for the same quests when Tier 2 returns nil. Consumers already handle all three `knownStatus` values.

### Fields Filled from Tier 3 (when nil in Tier 2 result)

| Field | Source |
|---|---|
| `zone` | `basicInfo.zone` |
| `level` | `basicInfo.questLevel` |
| `requiredLevel` | `basicInfo.requiredLevel` |
| `title` | `basicInfo.title` (defensive; Tier 2 already has title) |
| `chainInfo` | `provider:GetChainInfo` result |

### Code Shape

```lua
-- Tier 2: WoW log scan / title fallback.
local result = WowQuestAPI.GetQuestInfo(questID)
if result then
    -- Augment with Tier 3 if the result is missing a zone (title-only path).
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

### Files Changed

**`AbsoluteQuestLog.lua`** — `AQL:GetQuestInfo` only. No changes to `WowQuestAPI.lua`, `QuestCache.lua`, `EventEngine.lua`, or any provider.

---

## 3. Slash Command Restructure

### Problem

`/aql [on|normal|verbose|off]` directly maps the argument to a debug mode. This is ambiguous (debug is the only thing `/aql` can do) and leaves no extensibility for future subcommands.

### Solution

Change to `/aql debug [on|normal|verbose|off]`. The handler parses the first token as a subcommand; the remainder is passed to the subcommand handler. Unrecognized subcommands and a bare `/aql` print usage. This is a **deliberate breaking change** — all four bare forms (`/aql on`, `/aql normal`, `/aql verbose`, `/aql off`) stop working and must be updated to the `debug` subcommand form.

`aql.DBG` and `aql.RESET` are static color code string constants always present on the AQL object (defined in `AbsoluteQuestLog.lua` at module scope). They are not conditional on debug mode being active. It is safe to use them in the slash command handler regardless of the current debug state. Usage/help messages use `aql.DBG` (gold); only the library-not-loaded error uses a hardcoded red — this is consistent with the existing handler.

`aql.debug = nil` correctly disables debug mode. All debug checks in `EventEngine.lua` use truthiness (`if AQL.debug then`) or a direct string comparison for verbose (`if AQL.debug == "verbose" then`). No code tests for the string `"off"` as a value of `aql.debug`, so setting nil is safe.

A bare `/aql` with no input passes an empty string to the handler. The pattern `^%s*(%S+)%s*(.-)%s*$` fails to match an empty string (since `%S+` requires at least one non-space character), so `sub` and `arg` are both nil; `sub = sub and sub:lower() or ""` produces `""`, which falls through to the `else` usage branch. This is intentional.

```lua
SlashCmdList["ABSOLUTEQUESTLOG"] = function(input)
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

### Files Changed

**`AbsoluteQuestLog.lua`** — Slash command handler only. `SLASH_ABSOLUTEQUESTLOG1 = "/aql"` is already registered in the existing file; no change to the registration line is needed. Debug mode values are lowercased via `arg:lower()`, making the command case-insensitive by design (`/aql debug ON` works the same as `/aql debug on`).

---

## Explicitly Out of Scope

- Adding new `/aql` subcommands beyond `debug`
- Persisting debug mode across sessions
- Any changes to how QuestCache, EventEngine, or providers work beyond the string constant substitution
