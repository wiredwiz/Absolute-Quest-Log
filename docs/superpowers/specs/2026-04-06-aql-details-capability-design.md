# AQL Details Capability Design

## Goal

Extend AQL's provider system with a new `Capability.Details` slot that populates rich quest tooltip fields on `QuestInfo` — quest description, starter/finisher NPC names and zones, dungeon/raid/group flags, and per-objective type and target names. These fields are used by SocialQuest's custom quest tooltip and are available to any other AQL consumer.

## Architecture

A fourth capability bucket `AQL.Capability.Details` is added to the existing multi-provider system alongside `Chain`, `QuestInfo`, and `Requirements`. `EventEngine` selects the Details provider from a priority-ordered candidate list at `PLAYER_LOGIN`, with the same deferred upgrade retry loop used by other capabilities.

Provider priority for Details: **Questie → Grail → NullProvider**

QuestWeaverProvider does not implement Details — it has no data beyond what `QuestInfo` already carries.

New fields are merged onto the existing `QuestInfo` table. Missing fields are simply `nil` — no placeholders. The `isGroup` convenience field is derived from `type` at build time, not from the Details provider.

## New QuestInfo Fields

```lua
-- Derived from existing type field — no provider needed:
isGroup         -- bool, true when type is "elite", "dungeon", or "raid"

-- Populated by Details capability (nil when provider doesn't supply them):
description     -- quest body text
starterNPC      -- quest-giver NPC name
starterZone     -- zone of quest-giver
finisherNPC     -- turn-in NPC name
finisherZone    -- zone of turn-in NPC
isDungeon       -- bool
isRaid          -- bool

-- New sub-fields on existing objectives[i] entries:
objectives[i].npcOrItemName  -- target name for kill/collect objectives
objectives[i].objType        -- "monster" | "item" | "object" | "event"
```

### Availability Tiers

- **Guaranteed**: `questID`, `title`, `isGroup` (when `type` is set)
- **Usually present** — Questie or Grail (~60–70% of users): `starterNPC`, `starterZone`, `finisherNPC`, `finisherZone`, `isDungeon`, `isRaid`
- **Less likely** — Questie only (~40–50% of users): `description`, `objectives[i].npcOrItemName`, `objectives[i].objType`

## Provider Interface

Each provider that implements Details exposes:

```lua
Provider:GetQuestDetails(questID)
-- Returns nil when the quest is unknown to this provider.
-- Returns a table with any subset of:
{
    description  = "string",
    starterNPC   = "string",
    starterZone  = "string",
    finisherNPC  = "string",
    finisherZone = "string",
    isDungeon    = bool,
    isRaid       = bool,
    objectives   = {
        [i] = {
            npcOrItemName = "string",
            objType       = "monster" | "item" | "object" | "event",
        }
    }
}
```

### Provider Coverage

| Field | Questie | Grail | QuestWeaver | NullProvider |
|---|---|---|---|---|
| `description` | ✓ | — | — | — |
| `starterNPC` / `starterZone` | ✓ | ✓ | — | — |
| `finisherNPC` / `finisherZone` | ✓ | ✓ | — | — |
| `isDungeon` / `isRaid` | ✓ | ✓ | — | — |
| `objectives[i].npcOrItemName` | ✓ | — | — | — |
| `objectives[i].objType` | ✓ | — | — | — |

QuestWeaverProvider: does not implement `GetQuestDetails` (no data to contribute).

## Integration Points

### `QuestCache._buildEntry`

After building the base entry, calls `detailsProvider:GetQuestDetails(questID)` and merges any non-nil fields onto the entry. Derives `isGroup` from `type` immediately after `type` is set.

This is the same code path as the existing `GetQuestType` and `GetQuestFaction` provider calls — same performance profile (in-memory table lookup into Questie/Grail DB per quest per rebuild). With a typical 20–25 quest log this is negligible overhead.

### `GetQuestInfo` Tier 3

After `GetQuestBasicInfo` populates `title`, `level`, `zone`, calls `GetQuestDetails` and merges fields onto the result. Derives `isGroup` from `type` before returning. Covers non-cached quests (remote party members' quests, alias questIDs, etc.).

## Files to Create or Modify

| File | Change |
|---|---|
| `AbsoluteQuestLog.lua` | Add `AQL.Capability.Details` enum entry; add `AQL.providers[Capability.Details]` slot; update `GetQuestInfo` Tier 3 to call `GetQuestDetails` and merge; derive `isGroup` from `type` |
| `Core/EventEngine.lua` | Add Details capability to provider selection and deferred upgrade loop |
| `Core/QuestCache.lua` | Call `GetQuestDetails` in `_buildEntry`; derive `isGroup` from `type` |
| `Providers/Provider.lua` | Document `GetQuestDetails` interface contract and field availability tiers |
| `Providers/QuestieProvider.lua` | Implement `GetQuestDetails` using Questie's quest DB |
| `Providers/GrailProvider.lua` | Implement `GetQuestDetails` using Grail's NPC/dungeon APIs |
| `Providers/NullProvider.lua` | Add `GetQuestDetails` returning nil |
| `Providers/QuestWeaverProvider.lua` | No change (does not implement Details) |
| `CLAUDE.md` | Update QuestInfo data structure docs with new fields and availability tiers; add `Capability.Details` to provider interface section |
