# Quest Addon Analysis

Comparison of data sources available for quest information: the standard WoW API, and the quest database addons AQL supports or may support as providers.

---

## Data Coverage Matrix

**Column key:**
- `WoW API (in log)` — quest is in the player's active quest log
- `WoW API (not in log)` — quest is known by questID only (e.g., a chain step not yet accepted); only `C_QuestLog.GetQuestInfo(questID)` / `GetQuestInfo(questID)` is available
- `Questie` — Classic Era, TBC, Wrath, MoP; `QuestieDB.GetQuest(questID)`
- `QuestWeaver` — Classic Era, TBC; `_G["QuestWeaver"].Quests[questID]`
- `BtWQuests` — MoP + all Retail; chain-level data via `BtWQuests.Database.Chains[chainID]`
- `Grail` — Classic Era, TBC, Wrath, Cata, Retail, TWW; function-call API
- `RXPGuides` — Vanilla through Retail; guide-step data, not a quest database
- `Wholly` — Classic Era through TWW; UI wrapper — delegates entirely to Grail

> `✅*` = available but at chain granularity (not per-quest). See BtWQuests notes below.
> `†` = via prerequisite graph traversal, not a stored flat field.

| Field | WoW API (in log) | WoW API (not in log) | Questie | QuestWeaver | BtWQuests | Grail | RXPGuides | Wholly |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Identity** | | | | | | | | |
| `questID` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `title` | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| **Log-state (active quests only)** | | | | | | | | |
| `level` (recommended) | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| `suggestedGroup` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `isComplete` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `isTracked` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `link` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `timerSeconds` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `objectives` | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Classification** | | | | | | | | |
| `type` (elite/dungeon/raid/daily…) | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| `faction` (Alliance/Horde) | ❌ | ❌ | ✅ | ✅ | ✅* | ✅ | ❌ | ✅ |
| **Zone** | | | | | | | | |
| `zone` (log header) | ✅ | ❌ | — | — | — | — | — | — |
| `zone` (quest DB) | — | — | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| **Requirements** | | | | | | | | |
| `requiredLevel` | ❌ | ❌ | ✅ | ✅ | ✅* | ✅ | ❌ | ✅ |
| `requiredMaxLevel` | ❌ | ❌ | ✅ | ❌ | ✅* | ✅ | ❌ | ✅ |
| `requiredRaces` | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ |
| `requiredClasses` | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ |
| `preQuestGroup` (ALL required) | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ |
| `preQuestSingle` (ANY ONE required) | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ |
| `exclusiveTo` | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ |
| `nextQuestInChain` | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `breadcrumbForQuestId` | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ |
| **Chain structure** | | | | | | | | |
| `chainID` | ❌ | ❌ | ❌ | ✅ | ✅* | ❌ | ❌ | ❌ |
| `step` | ❌ | ❌ | ❌ | ✅ | ✅* | ❌ | ❌ | ❌ |
| `length` | ❌ | ❌ | ❌ | ✅ | ✅* | ❌ | ❌ | ❌ |
| `steps[]` | ❌ | ❌ | ❌ | ✅ | ✅* | ❌† | ❌ | ❌ |

---

## Provider Candidate Assessment

### Grail — Strong candidate

**Versions:** Classic Era · TBC · Wrath · Cata · Retail · TWW (two separate addon packages: Grail-123 = Classic/TBC/Wrath/Cata, Grail-124 = Retail/TWW)

**Data access:** Function-call API — `Grail:QuestName(questID)`, `Grail:QuestLevel(questID)`, `Grail:LocationQuest(questID)`, `Grail:MeetsRequirementLevel(questID)`, `Grail:IsRaid(questID)`, `Grail:IsDungeon(questID)`, `Grail:IsGroup(questID)`, `Grail:IsEscort(questID)`, `Grail:AvailableBreadcrumbs(questID)`, `Grail:AncestorQuests(questID)`

**Strengths:**
- Widest version coverage of all candidates — covers every active WoW client family AQL targets
- Rich metadata: title, level, requiredLevel, requiredMaxLevel, zone, race restrictions, class restrictions, faction, quest type, prerequisites (both AND and ANY-ONE), exclusiveTo, breadcrumbs
- Quest data is stored as a compact prerequisite code string per questID (e.g. `G[questID] = 'L5150 FH Rx ...'`) which Grail's API decodes into structured results
- Would fill the Retail metadata gap (Grail-124 covers Retail; BtWQuests does not provide metadata)

**Gaps:**
- No explicit chain structure: Grail models quests as a prerequisite DAG, not ordered chains. `AncestorQuests()` returns a prerequisite tree, not a flat step array. `GetChainInfo` would either return `knownStatus = "not_a_chain"` for all quests, or require complex DAG traversal to approximate chains.
- Two separate addon packages to detect and load

**Verdict:** High-value provider. Implement a `GrailProvider` that covers `GetQuestBasicInfo`, `GetQuestType`, `GetQuestFaction`, and `GetQuestRequirements` fully. Leave `GetChainInfo` returning `knownStatus = "unknown"` unless chain traversal is added later.

---

### BtWQuests — Targeted candidate for Retail chain data

**Versions:** MoP + all Retail expansions (Classic through The War Within and beyond)

**Data access:** Chain-centric — `BtWQuests.Database.Chains[chainID]` contains an `items[]` array of quest steps. Requires a reverse index (questID → chainID) built at init time.

**Strengths:**
- The only addon in this set with explicit chain structure data for Retail
- Each chain stores: `items[]` (ordered quest steps), `name`, level `range = {min, max}`, faction `restrictions`, `prerequisites` (chain-level), `breadcrumb` relationship
- Would plug the Retail `GetChainInfo` gap that currently always returns `knownStatus = "unknown"`

**Gaps:**
- No per-quest title — uses WoW API at runtime; cannot populate `steps[].title` from the database alone
- Level data is chain-granularity (`range = {min, max}`), not per-quest
- No quest type (elite/dungeon/raid), no race/class restrictions, no detailed requirements
- Faction and level requirements are on the chain, not on individual quest items

**Verdict:** Worthwhile as a chain-only provider for Retail. Implement a `BtWQuestsProvider` that covers `GetChainInfo` only. Pair with `GrailProvider` (Grail-124) to cover metadata on Retail; the two together would give near-complete coverage on Retail.

---

### Wholly — Not a candidate

Wholly is a quest log UI addon that delegates all data access entirely to Grail. It has no independent quest database. Implementing a `GrailProvider` makes a Wholly provider redundant.

---

### RXPGuides — Not a candidate

RXPGuides is a leveling guide addon. Its data is organized as guide step sequences (accept quest X, kill mob Y, turn in quest Z) rather than per-quest field records. It does not store title, level, zone, race/class restrictions, type, or faction as addressable fields. The prerequisite information it contains (`previousQuest`, `preQuestAny`) describes guide flow order, not server-enforced quest requirements. Not suitable as a quest data provider.

---

## Addon Details

### Questie

- **Versions supported:** Classic Era (11508), TBC (20505), Wrath (38000), MoP (50503), Retail
- **Data access:** `QuestieLoader:ImportModule("QuestieDB").GetQuest(questID)`
- **Initialization:** Asynchronous — `db.QuestPointers` is nil until `QuestieDB:Initialize()` runs (~3 s after `PLAYER_LOGIN`)
- **AQL provider status:** Implemented (`QuestieProvider.lua`)

| Field | Source in QuestieDB |
|---|---|
| `title` | `quest.name` (questKey 1) |
| `level` | `quest.questLevel` (questKey 5) |
| `requiredLevel` | `quest.requiredLevel` (questKey 4) |
| `requiredMaxLevel` | `quest.requiredMaxLevel` (questKey 32) |
| `zone` | `quest.zoneOrSort` (questKey 17) → `C_Map.GetAreaInfo`; negative values (sort categories) omitted |
| `requiredRaces` | `quest.requiredRaces` (questKey 6); 0 normalised to nil |
| `requiredClasses` | `quest.requiredClasses` (questKey 7); 0 normalised to nil |
| `preQuestGroup` | `quest.preQuestGroup` (questKey 12) |
| `preQuestSingle` | `quest.preQuestSingle` (questKey 13) |
| `exclusiveTo` | `quest.exclusiveTo` (questKey 16) |
| `nextQuestInChain` | `quest.nextQuestInChain` (questKey 22); 0 normalised to nil |
| `breadcrumbForQuestId` | `quest.breadcrumbForQuestId` (questKey 27) |
| `type` | `quest.questTagId` (elite=1, raid=62, dungeon=81) + `quest.questFlags` bit 1 (daily) |
| `faction` | `quest.requiredFaction` (0=any, 1=Horde, 2=Alliance) |
| Chain data | Derived from `quest.nextQuestInChain` via reverse-index walk over `db.QuestPointers` |

---

### QuestWeaver

- **Versions supported:** Classic Era, TBC Classic (Interface 20504)
- **Data access:** `_G["QuestWeaver"].Quests[questID]`
- **Initialization:** Synchronous — available immediately after load
- **AQL provider status:** Implemented (`QuestWeaverProvider.lua`)

| Field | Source in QuestWeaver | Notes |
|---|---|---|
| `title` | `quest.name` | |
| `level` | `quest.level` | |
| `requiredLevel` | `quest.min_level` | Only requirement field exposed |
| `zone` | `quest.source_zone` or `quest.zone` | |
| `type` | `quest.quest_type` (string) | |
| `faction` | `quest.faction` | "Alliance" / "Horde" / nil |
| Chain: `chainID` | `quest.chain_id` | questID of first quest in chain |
| Chain: `step` | `quest.chain_position` | 1-based position |
| Chain: `length` | `quest.chain_length` | total steps |
| Chain: `steps[]` | `quest.quest_series` | ordered questID array |

All other requirement fields (`requiredMaxLevel`, `requiredRaces`, `requiredClasses`, `preQuestGroup`, `preQuestSingle`, `exclusiveTo`, `nextQuestInChain`, `breadcrumbForQuestId`) are not exposed.

---

### BtWQuests

- **Versions supported:** MoP (50500) + all Retail expansions through The War Within and beyond
- **Data access:** Chain-centric — `BtWQuests.Database.Chains[chainID]`; per-quest access requires building a reverse index at init
- **AQL provider status:** Not yet implemented — future candidate

BtWQuests organizes quest data into named chains. Each chain object stores:
- `name` — localized chain name (from achievement criteria or localization table)
- `items[]` — ordered array of quest/NPC/event step entries; quest entries have `.id` (questID) or `.ids` (array of questIDs for multi-version steps)
- `range = {min, max}` — player level range for the chain
- `prerequisites[]` — chain-level prerequisites (type: "level", "chain", "quest")
- `restrictions` — faction restriction ID (ALLIANCE_RESTRICTIONS / HORDE_RESTRICTIONS constants)
- `relationship.breadcrumb` — breadcrumb questID (on individual quest items)

Chains are grouped by expansion and zone category. Quest titles are fetched via WoW API at runtime and are not stored in the database.

---

### Grail

- **Versions supported (Classic package, Grail-123):** Classic Era (11502/11503), TBC (20504), Wrath (30403), Cata (40400)
- **Versions supported (Retail package, Grail-124):** Retail (100207+), TWW (110000+)
- **Data access:** Function-call API on the `Grail` global
- **AQL provider status:** Not yet implemented — strong candidate

Grail stores per-quest data as a compact prerequisite code string indexed by questID:
```
G[questID] = 'L5150 FH A:12345 T:67890 P:6383 ...'
```

Each code prefix encodes a specific attribute. Key codes:

| Code | Meaning |
|---|---|
| `L`xxx | Min player level |
| `l`xxx | Max player level (must be < xxx) |
| `FA` / `FH` | Faction: Alliance / Horde |
| `Rx` | Race restriction (race code x) |
| `Nx` | Required class (class code x) |
| `nx` | Excluded class |
| `P:`xxx | Prerequisite quest (default: must be turned in) |
| `B:`xxx | Breadcrumb quest |
| `X` | Quest must NOT be turned in (exclusiveTo semantics) |
| `fH` / `fA` | Quest type flags (Raid, Dungeon, Group, Escort, Heroic, PVP) |

Key API functions:

| Function | Returns |
|---|---|
| `Grail:QuestName(questID)` | Localized title string |
| `Grail:QuestLevel(questID)` | Recommended level |
| `Grail:MeetsRequirementLevel(questID)` | Min and max levels |
| `Grail:LocationQuest(questID)` | Zone/location |
| `Grail:AvailableBreadcrumbs(questID)` | Breadcrumb quests |
| `Grail:AncestorQuests(questID)` | Full prerequisite tree (DAG) |
| `Grail:IsRaid(questID)` / `IsDungeon()` / `IsGroup()` / `IsEscort()` / `IsHeroic()` / `IsPVP()` | Quest type booleans |

Grail does not have an explicit chain model. Quest relationships are expressed as a prerequisite directed acyclic graph (DAG). `AncestorQuests()` returns this prerequisite tree but not a flat ordered `steps[]` array.

---

### RXPGuides

- **Versions supported:** Vanilla (11508), TBC (20505), Wrath (38000), MoP (50502), Retail (110205+)
- **Data access:** `addon.QuestDB[group]` — guide step sequences
- **AQL provider status:** Not a candidate

RXPGuides is a leveling guide addon. Data is structured as ordered guide steps (accept, kill, loot, turn in), not a per-quest metadata database. The `previousQuest` / `preQuestAny` fields describe guide-path ordering, not server-enforced requirements. No title, level, zone, race/class restriction, or quest type fields are stored as addressable per-quest data.

---

### Wholly

- **Versions supported:** Classic Era, TBC, Wrath, Cata, Retail, TWW
- **Data access:** Entirely delegates to Grail — no independent database
- **AQL provider status:** Not a candidate (superseded by GrailProvider)

Wholly is a quest log UI addon built on top of Grail. All data access calls through to `Grail:*` API functions. Implementing a `GrailProvider` covers all data Wholly would provide.
