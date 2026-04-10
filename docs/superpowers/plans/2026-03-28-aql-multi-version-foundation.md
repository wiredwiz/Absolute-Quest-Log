# AQL Multi-Version Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the infrastructure that lets AQL load on all four active WoW version families and produce a complete API compatibility audit, without changing any existing TBC behavior.

**Architecture:** Three deliverables in sequence — version detection constants (code), multi-toc files (config), and API compatibility audit (research doc). All are independent of each other and can be reviewed in isolation. The only runtime Lua change is in `Core/WowQuestAPI.lua`; the toc files are inert config. No behavioral change to TBC functionality.

**Tech Stack:** Lua 5.1 (WoW), WoW multi-toc system, Markdown

---

## File Map

| Action | File | Purpose |
|---|---|---|
| Modify | `Core/WowQuestAPI.lua` | Replace 3 ad-hoc `_TOC` comparisons with 4 named constants |
| Create | `AbsoluteQuestLog_Classic.toc` | Loads AQL on Classic Era / SoD / Hardcore (Interface 11503) |
| Create | `AbsoluteQuestLog_BCC.toc` | Loads AQL on TBC Anniversary (Interface 20505, suffix `_BCC`) |
| Create | `AbsoluteQuestLog_MoP.toc` | Loads AQL on MoP Classic (interface number TBD — see Task 2) |
| Create | `AbsoluteQuestLog_Mainline.toc` | Loads AQL on Retail (interface number TBD — see Task 2) |
| Create | `docs/api-compatibility.md` | API compatibility audit across all four version families |

---

## Background you must read first

Read `Core/WowQuestAPI.lua` before starting. It has three `_TOC` comparisons today:
- Line ~24: `if _TOC >= 100000 then` (Retail branch for `GetQuestInfo`)
- Line ~92: `if _TOC >= 20000 then` (TBC+ branch for `IsQuestFlaggedCompleted`)
- Line ~147: `if _TOC >= 100000 then` (Retail branch for `IsUnitOnQuest`)

Read `AbsoluteQuestLog.toc` to see the exact file list that every new toc file must replicate.

Read the spec at `docs/superpowers/specs/2026-03-28-aql-multi-version-foundation-design.md` for full context.

---

## Task 1 — Version detection constants in WowQuestAPI.lua

**Files:**
- Modify: `Core/WowQuestAPI.lua:12` (after `local _TOC = select(4, GetBuildInfo())`)

No automated test is possible without a running WoW client. Verification is a careful read-back of the modified file confirming syntax and logic are correct.

- [ ] **Step 1: Read the current file**

Read `Core/WowQuestAPI.lua` in full. Identify the three branch locations exactly (lines ~24, ~92, ~147).

- [ ] **Step 2: Add the four named constants**

Immediately after `local _TOC = select(4, GetBuildInfo())` (line 12), insert:

```lua
local IS_CLASSIC_ERA = _TOC <  20000                   -- 1.14.x: Classic Era, SoD, Hardcore
local IS_TBC         = _TOC >= 20000 and _TOC < 30000  -- 2.x: TBC Anniversary (current)
local IS_MOP         = _TOC >= 50000 and _TOC < 60000  -- 5.x: MoP Classic
local IS_RETAIL      = _TOC >= 100000                  -- 11.x+: Retail (The War Within+)
```

**Why each range:**
- `IS_CLASSIC_ERA`: `< 20000` — all 1.x interface numbers are below 20000; this captures Classic Era, SoD, and Hardcore.
- `IS_TBC`: `>= 20000 and < 30000` — the 2.x range; upper bound `< 30000` intentionally leaves WotLK (30000–39999) and Cata (40000–49999) in a gap, since those versions are explicitly out of scope.
- `IS_MOP`: `>= 50000 and < 60000` — the 5.x range for MoP Classic.
- `IS_RETAIL`: `>= 100000` — all 11.x+ interface numbers.

- [ ] **Step 3: Replace the three existing branches**

**Branch 1 — `GetQuestInfo` (line ~24):**
```lua
-- BEFORE:
if _TOC >= 100000 then  -- Retail

-- AFTER:
if IS_RETAIL then
```

Update the `else` comment on the same branch (line ~41):
```lua
-- BEFORE:
else  -- TBC Classic / TBC Anniversary (and Classic Era stub)

-- AFTER:
else  -- IS_TBC (IS_CLASSIC_ERA and IS_MOP handled in later sub-projects)
```

**Branch 2 — `IsQuestFlaggedCompleted` (line ~92):**
```lua
-- BEFORE:
if _TOC >= 20000 then  -- TBC Classic, TBC Anniversary, Retail

-- AFTER:
if IS_TBC or IS_MOP or IS_RETAIL then
```

Update the `else` comment:
```lua
-- BEFORE:
else  -- Classic Era (future)

-- AFTER:
else  -- IS_CLASSIC_ERA
```

**Branch 3 — `IsUnitOnQuest` (line ~147):**
```lua
-- BEFORE:
if _TOC >= 100000 then  -- Retail

-- AFTER:
if IS_RETAIL then
```

- [ ] **Step 4: Verify — read back the version detection section**

Read `Core/WowQuestAPI.lua` lines 1–160. Confirm:
1. `local _TOC` line is unchanged.
2. Four `local IS_*` lines immediately follow it.
3. No raw `_TOC >=` or `_TOC <` comparisons remain anywhere in the file.
4. `IS_TBC or IS_MOP or IS_RETAIL` is used for the `IsQuestFlaggedCompleted` branch — not just `IS_TBC`.
5. Both `IS_RETAIL` branches (GetQuestInfo and IsUnitOnQuest) use `IS_RETAIL`.
6. The else comment on `GetQuestInfo` reads `-- IS_TBC (IS_CLASSIC_ERA and IS_MOP handled in later sub-projects)`.

- [ ] **Step 5: Commit**

```bash
git add Core/WowQuestAPI.lua
git commit -m "refactor: replace ad-hoc _TOC comparisons with named version constants

Adds IS_CLASSIC_ERA, IS_TBC, IS_MOP, IS_RETAIL locals in WowQuestAPI.lua.
Replaces all three raw _TOC numeric comparisons. No behavioral change on TBC (20505)."
```

---

## Task 2 — Multi-toc files

**Files:**
- Create: `AbsoluteQuestLog_Classic.toc`
- Create: `AbsoluteQuestLog_BCC.toc`
- Create: `AbsoluteQuestLog_MoP.toc`
- Create: `AbsoluteQuestLog_Mainline.toc`

No automated test is possible without live WoW clients. Verification is confirming file contents match the spec.

### Step 2a: Verify multi-toc suffix names and interface numbers

- [ ] **Step 1: Research the _BCC suffix for TBC Anniversary**

The `_BCC` suffix was introduced for the 2021 TBC Classic launch. Confirm it is still the correct suffix for TBC Anniversary servers by checking:
- Blizzard's current addon documentation at https://wowpedia.fandom.com/wiki/TOC_format
- The "Game version-specific TOC files" section of that page lists the exact suffix for each client

If `_BCC` is confirmed correct: create `AbsoluteQuestLog_BCC.toc` with Interface 20505.
If a different suffix is required (e.g., `_TBCC`): create the toc with that suffix and note the finding. The base `AbsoluteQuestLog.toc` (Interface 20505) will serve as the fallback in the meantime.

- [ ] **Step 2: Research the MoP Classic interface number**

Find the current MoP Classic interface number. Sources:
- Wowpedia "Interface version" page or Blizzard patch notes
- The `## Interface:` value used by any popular MoP Classic addon (e.g., on CurseForge or WoWInterface, filter by Mists of Pandaria)

Expected range: 50000–59999. Use the exact current value. If you cannot confirm it, use 50500 as the best available estimate and add a `# TODO: verify interface number on live MoP client` comment.

Also confirm the correct `.toc` suffix for MoP Classic (expected: `_Mists` or `_MoP`).

- [ ] **Step 3: Research the current Retail interface number**

Find the current Retail WoW interface number at time of implementation. This changes each patch.
- Check https://wowpedia.fandom.com/wiki/Interface_version or the WoW patch notes
- Expected format: 11xxxx (The War Within 11.x era)

The correct suffix for Retail `.toc` files is `_Mainline` — this is well-established and does not need verification.

### Step 2b: Create the toc files

Each new toc file has **identical `# file list` content** to `AbsoluteQuestLog.toc`. Only `## Interface:`, `## Title:`, and `## Notes:` differ.

- [ ] **Step 4: Create AbsoluteQuestLog_Classic.toc**

```
## Interface: 11503
## Title: Lib: AbsoluteQuestLog
## Notes: A rich quest data library — Classic Era, Season of Discovery, Hardcore.
## Author: Thad Ryker
## Version: 2.4.1
## X-Category: Library
## X-Embeds: LibStub, CallbackHandler-1.0
## IconTexture: Interface\AddOns\AbsoluteQuestLog\Logo.png

# Embedded libraries
Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua

# Core modules
AbsoluteQuestLog.lua
Core\WowQuestAPI.lua
Core\EventEngine.lua
Core\QuestCache.lua
Core\HistoryCache.lua

# Extended quest info provider modules
Providers\Provider.lua
Providers\QuestieProvider.lua
Providers\QuestWeaverProvider.lua
Providers\NullProvider.lua
```

- [ ] **Step 5: Create AbsoluteQuestLog_BCC.toc**

Use the suffix confirmed in Step 1. File name: `AbsoluteQuestLog_BCC.toc` (or the confirmed suffix variant).

```
## Interface: 20505
## Title: Lib: AbsoluteQuestLog
## Notes: A rich quest data library — TBC Anniversary.
## Author: Thad Ryker
## Version: 2.4.1
## X-Category: Library
## X-Embeds: LibStub, CallbackHandler-1.0
## IconTexture: Interface\AddOns\AbsoluteQuestLog\Logo.png

# Embedded libraries
Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua

# Core modules
AbsoluteQuestLog.lua
Core\WowQuestAPI.lua
Core\EventEngine.lua
Core\QuestCache.lua
Core\HistoryCache.lua

# Extended quest info provider modules
Providers\Provider.lua
Providers\QuestieProvider.lua
Providers\QuestWeaverProvider.lua
Providers\NullProvider.lua
```

- [ ] **Step 6: Create AbsoluteQuestLog_MoP.toc**

Replace `<MOP_INTERFACE>` with the number found in Step 2. Replace `_MoP` with the correct suffix if it differs.

```
## Interface: <MOP_INTERFACE>
## Title: Lib: AbsoluteQuestLog
## Notes: A rich quest data library — Mists of Pandaria Classic.
## Author: Thad Ryker
## Version: 2.4.1
## X-Category: Library
## X-Embeds: LibStub, CallbackHandler-1.0
## IconTexture: Interface\AddOns\AbsoluteQuestLog\Logo.png

# Embedded libraries
Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua

# Core modules
AbsoluteQuestLog.lua
Core\WowQuestAPI.lua
Core\EventEngine.lua
Core\QuestCache.lua
Core\HistoryCache.lua

# Extended quest info provider modules
Providers\Provider.lua
Providers\QuestieProvider.lua
Providers\QuestWeaverProvider.lua
Providers\NullProvider.lua
```

- [ ] **Step 7: Create AbsoluteQuestLog_Mainline.toc**

Replace `<RETAIL_INTERFACE>` with the current Retail interface number found in Step 3.

```
## Interface: <RETAIL_INTERFACE>
## Title: Lib: AbsoluteQuestLog
## Notes: A rich quest data library — Retail (The War Within and forward).
## Author: Thad Ryker
## Version: 2.4.1
## X-Category: Library
## X-Embeds: LibStub, CallbackHandler-1.0
## IconTexture: Interface\AddOns\AbsoluteQuestLog\Logo.png

# Embedded libraries
Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua

# Core modules
AbsoluteQuestLog.lua
Core\WowQuestAPI.lua
Core\EventEngine.lua
Core\QuestCache.lua
Core\HistoryCache.lua

# Extended quest info provider modules
Providers\Provider.lua
Providers\QuestieProvider.lua
Providers\QuestWeaverProvider.lua
Providers\NullProvider.lua
```

- [ ] **Step 8: Verify all four toc files**

For each file, confirm:
1. `## Interface:` value is a plausible number for that version family (Classic ~11xxx, TBC ~20505, MoP ~5xxxx, Retail ~1xxxxx).
2. The file list section is byte-for-byte identical to `AbsoluteQuestLog.toc` — same files, same order, same comments.
3. `## Version:` matches the current version in `AbsoluteQuestLog.toc`.

- [ ] **Step 9: Commit**

```bash
git add AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_BCC.toc AbsoluteQuestLog_MoP.toc AbsoluteQuestLog_Mainline.toc
git commit -m "feat: add multi-toc files for Classic Era, TBC, MoP Classic, and Retail

Enables WoW client to select the correct toc per version family.
Base AbsoluteQuestLog.toc (20505) remains as fallback for unsupported versions."
```

---

## Task 3 — API compatibility audit

**Files:**
- Create: `docs/api-compatibility.md`

This task is research + documentation. The output is a Markdown file with nine tables. Every cell must be filled in — no `?` cells unless you add a note explaining what could not be researched and what the implication is.

### Legend

| Symbol | Meaning |
|---|---|
| ✓ | Works as-is, same signature and return type |
| ~ | Present but different signature, return type, or namespace |
| ✗ | Absent / removed in this version |
| ? | Not yet researched (must add a note) |

**Columns:** Classic Era 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes

### Research approach

Primary sources (in order of reliability):
1. **wowpedia.org** — each API has a page with version availability. Search e.g. "GetNumQuestLogEntries wowpedia".
2. **wow.tools/db** — for event names and data structure changes.
3. **CurseForge / WoWInterface** — search for addons that support all versions; read their version-branching code.
4. **WoW addon GitHub repos** — projects like HandyNotes or QuestHelper that support multiple versions will have `_TOC` branches that reveal exactly which APIs exist on each version.

**TBC column is already known** — the current code works on TBC 20505. Every TBC entry is ✓ unless the Notes section of `Core/WowQuestAPI.lua` or `CLAUDE.md` says otherwise. Use these known facts:
- `QUEST_TURNED_IN` does not fire on TBC (✗) — detected via `hooksecurefunc("GetQuestReward")` instead.
- `C_QuestLog.IsQuestFlaggedCompleted` exists on TBC 20505 (✓) — used in current code.
- `IsQuestFlaggedCompleted` (global, not C_QuestLog) exists on Classic Era (✓).
- `C_Map.GetAreaInfo` is used by Questie on TBC — likely ✓ on TBC but needs confirmation for Classic Era.
- `UnitIsOnQuest` (used by `IsUnitOnQuest` wrapper) exists on Retail but not TBC/Classic (✗ TBC, ✗ Classic).

- [ ] **Step 1: Create the file with the header and legend**

Create `docs/api-compatibility.md`:

```markdown
# AQL API Compatibility Audit

**Date:** 2026-03-28
**Spec:** docs/superpowers/specs/2026-03-28-aql-multi-version-foundation-design.md

This document maps every WoW API call used by AQL against all four target version
families. Produced during the Multi-Version Foundation sub-project.

## Legend

| Symbol | Meaning |
|---|---|
| ✓ | Works as-is, same signature and return type |
| ~ | Present but different signature, return type, or namespace |
| ✗ | Absent / removed in this version |
| ? | Not yet researched (see Notes column) |

**Version families:**
- Classic Era 1.14.x — Classic Era, Season of Discovery, Hardcore (~11503)
- TBC 2.x — TBC Anniversary (20505, current — fully working)
- MoP 5.x — Mists of Pandaria Classic (~50500)
- Retail 11.x — The War Within and forward (~110xxx)

---
```

- [ ] **Step 2: Research and write Category 1 — Quest log enumeration**

Research `GetNumQuestLogEntries` and `GetQuestLogTitle` across all four versions.

Known facts:
- Both exist on TBC (✓ TBC).
- Retail removed both; use `C_QuestLog.GetNumQuestLogEntries()` and `C_QuestLog.GetTitleForQuestID()` instead (✗ Retail).
- Classic Era: both should exist (✓ Classic Era) — the Classic API surface mirrors early-expansion WoW.
- MoP: likely still present in 5.x but verify (the shift to C_QuestLog APIs accelerated in later expansions).

Add to `docs/api-compatibility.md`:

```markdown
## 1. Quest Log Enumeration

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `GetNumQuestLogEntries()` | ✓ | ✓ | [research] | ✗ | Retail: use `C_QuestLog.GetNumQuestLogEntries()` |
| `GetQuestLogTitle(logIndex)` | ✓ | ✓ | [research] | ✗ | Retail: use `C_QuestLog.GetTitleForQuestID(questID)` — different signature and input type |

```

Replace `[research]` with ✓, ~, or ✗ based on findings. Add Notes for any ~ entry describing the difference.

- [ ] **Step 3: Research and write Category 2 — Quest info resolution**

Research `C_QuestLog.GetQuestInfo` and `C_QuestLog.GetQuestObjectives` across all four versions.

Known facts:
- TBC: `C_QuestLog.GetQuestInfo(questID)` returns a **title string**, not a table (✓ but ~ signature vs. Retail).
- Retail: `C_QuestLog.GetQuestInfo(questID)` returns a full info table with many fields.
- `C_QuestLog.GetQuestObjectives`: exists on TBC (✓ TBC, current code uses it).
- Classic Era: `C_QuestLog.GetQuestInfo` may return a title string like TBC, or may not exist — verify.
- MoP: likely returns a full info table similar to Retail (the table-return form was introduced around MoP/WoD).

```markdown
## 2. Quest Info Resolution

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `C_QuestLog.GetQuestInfo(questID)` | [research] | ~ | [research] | ✓ | TBC: returns title string, not a table. Retail: returns full info table. |
| `C_QuestLog.GetQuestObjectives(questID)` | [research] | ✓ | [research] | ✓ | |

```

- [ ] **Step 4: Research and write Category 3 — Quest history**

Research `GetQuestsCompleted`, `IsQuestFlaggedCompleted` (global), and `C_QuestLog.IsQuestFlaggedCompleted`.

Known facts:
- TBC: `C_QuestLog.IsQuestFlaggedCompleted` ✓ (current code uses it).
- Classic Era: `IsQuestFlaggedCompleted` (global, not C_QuestLog) ✓ — already in current WowQuestAPI.lua as the Classic branch.
- Classic Era: `C_QuestLog.IsQuestFlaggedCompleted` likely ✗ — verify.
- Retail: `C_QuestLog.IsQuestFlaggedCompleted` ✓.
- `GetQuestsCompleted`: returns `{[questID]=true}` table; used in `HistoryCache`. Exists on Classic/TBC; check MoP/Retail.

```markdown
## 3. Quest History

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `GetQuestsCompleted()` | [research] | ✓ | [research] | [research] | Returns table of all completed questIDs |
| `IsQuestFlaggedCompleted(questID)` | ✓ | ✗ | ✗ | ✗ | Classic Era global; replaced by C_QuestLog variant in TBC+ |
| `C_QuestLog.IsQuestFlaggedCompleted(questID)` | ✗ | ✓ | ✓ | ✓ | Does not exist in Classic Era |

```

- [ ] **Step 5: Research and write Category 4 — Quest sharing**

Research `GetQuestLogPushable` and `QuestLogPushQuest`.

Known facts:
- TBC: both ✓ (current code uses them via SocialQuest).
- Retail: `GetQuestLogPushable` likely replaced by `C_QuestLog.IsPushableQuest(questID)` (✗ → verify replacement).
- Retail: `QuestLogPushQuest` likely replaced by `C_QuestLog.PushQuest(questID)` (✗ → verify replacement).
- Classic Era and MoP: likely ✓ for both — verify.

```markdown
## 4. Quest Sharing

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `GetQuestLogPushable()` | [research] | ✓ | [research] | [research] | Selection-dependent; TBC used after `SelectQuestLogEntry` |
| `QuestLogPushQuest()` | [research] | ✓ | [research] | [research] | Pushes currently selected quest to party |

```

- [ ] **Step 6: Research and write Category 5 — Quest log frame globals**

Research `QuestLogFrame`, `QuestLog_SetSelection`, `QuestLog_Update`, `ExpandQuestHeader`, `CollapseQuestHeader`, `ShowUIPanel`, `HideUIPanel`.

Known facts:
- All ✓ on TBC.
- Retail replaced the entire quest log UI. `QuestLogFrame` → new frame name (`QuestLogPopupDetailFrame` or similar). `QuestLog_SetSelection` and `QuestLog_Update` do not exist as globals in Retail.
- `ExpandQuestHeader`/`CollapseQuestHeader` removed in Retail; use `C_QuestLog.ExpandQuestLogHeaders`/`CollapseQuestLogHeaders`.
- `ShowUIPanel`/`HideUIPanel` still exist in Retail (✓ Retail).
- Classic Era: all likely ✓ (same-era UI).
- MoP: the quest log UI was redesigned in MoP. `QuestLogFrame` still exists but layout changed; `QuestLog_SetSelection` and `QuestLog_Update` likely still exist. Verify.

```markdown
## 5. Quest Log Frame Globals

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `QuestLogFrame` | ✓ | ✓ | [research] | ~ | Retail: frame exists but renamed/restructured |
| `QuestLog_SetSelection(logIndex)` | ✓ | ✓ | [research] | ✗ | Retail: no direct replacement; selection model changed |
| `QuestLog_Update()` | ✓ | ✓ | [research] | ✗ | Retail: no direct replacement |
| `ExpandQuestHeader(logIndex)` | ✓ | ✓ | [research] | ✗ | Retail: `C_QuestLog.ExpandQuestLogHeaders()` (no per-zone control) |
| `CollapseQuestHeader(logIndex)` | ✓ | ✓ | [research] | ✗ | Retail: `C_QuestLog.CollapseQuestLogHeaders()` |
| `ShowUIPanel(frame)` | ✓ | ✓ | ✓ | ✓ | Exists across all versions |
| `HideUIPanel(frame)` | ✓ | ✓ | ✓ | ✓ | Exists across all versions |

```

- [ ] **Step 7: Research and write Category 6 — Quest tracking**

Research `AddQuestWatch`, `RemoveQuestWatch`, `MAX_WATCHABLE_QUESTS`, and the `QUEST_WATCH_LIST_CHANGED` event.

Known facts:
- TBC: all ✓.
- Retail: `AddQuestWatch(logIndex)` / `RemoveQuestWatch(logIndex)` replaced by `C_QuestLog.AddQuestWatch(questID)` / `C_QuestLog.RemoveQuestWatch(questID)` — different namespace AND different parameter (questID, not logIndex). `MAX_WATCHABLE_QUESTS` may be a different value or constant location.
- Classic Era: likely same as TBC (✓).
- MoP: likely same as TBC (✓) — verify whether any namespace change occurred.

```markdown
## 6. Quest Tracking

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `AddQuestWatch(logIndex)` | ✓ | ✓ | [research] | ✗ | Retail: `C_QuestLog.AddQuestWatch(questID)` — different namespace and parameter |
| `RemoveQuestWatch(logIndex)` | ✓ | ✓ | [research] | ✗ | Retail: `C_QuestLog.RemoveQuestWatch(questID)` |
| `MAX_WATCHABLE_QUESTS` | ✓ | ✓ | [research] | ~ | Retail: constant may be in different location; value may differ |
| `QUEST_WATCH_LIST_CHANGED` (event) | ✓ | ✓ | [research] | [research] | Verify event still fires and name unchanged |

```

- [ ] **Step 8: Research and write Category 7 — Turn-in detection**

Research `GetQuestReward` (the `hooksecurefunc` target) and the `QUEST_TURNED_IN` event.

Known facts:
- TBC: `QUEST_TURNED_IN` does not fire — turn-in detected via `hooksecurefunc("GetQuestReward")` (✓ TBC for GetQuestReward, ✗ TBC for event).
- Retail: `QUEST_TURNED_IN` **does** fire (✓ Retail for event).
- Retail: `GetQuestReward` likely still exists (used by the UI for selection screen) — verify.
- Classic Era: likely same as TBC — `QUEST_TURNED_IN` probably does not fire; verify.
- MoP: unclear when `QUEST_TURNED_IN` was introduced — verify.

```markdown
## 7. Turn-In Detection

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `GetQuestReward()` (hooksecurefunc target) | ✓ | ✓ | [research] | [research] | Used as turn-in hook on TBC/Classic where QUEST_TURNED_IN is absent |
| `QUEST_TURNED_IN` (event) | [research] | ✗ | [research] | ✓ | Does not fire in TBC; fires in Retail. Check MoP and Classic Era. |

```

- [ ] **Step 9: Research and write Category 8 — WoW events**

Research `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_LOG_UPDATE`, `UNIT_QUEST_LOG_CHANGED`.

Known facts:
- TBC: all four fire (✓ TBC).
- TBC/Classic: `QUEST_ACCEPTED` passes the quest log index as arg1, **not** the questID — this is a known TBC behavior (documented in AQL 2.4.1 version history). Mark as ~ with a note.
- Retail: `QUEST_ACCEPTED` fires with questID as arg1 (✓ Retail — standard behavior).
- All four events likely exist across all versions — verify MoP and Classic Era.

```markdown
## 8. WoW Events

| Event | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `QUEST_ACCEPTED` | ~ | ~ | [research] | ✓ | Classic/TBC: arg1 is logIndex (not questID). Retail: arg1 is questID. |
| `QUEST_REMOVED` | ✓ | ✓ | [research] | ✓ | arg1 = questID across all versions |
| `QUEST_LOG_UPDATE` | ✓ | ✓ | [research] | ✓ | Fires when quest log changes |
| `UNIT_QUEST_LOG_CHANGED` | ✓ | ✓ | [research] | ✓ | arg1 = unit token |

```

- [ ] **Step 10: Research and write Category 9 — Miscellaneous**

Research `UnitLevel`, `GetBuildInfo`, `GetQuestDifficultyColor`, `C_Map.GetAreaInfo`.

Known facts:
- `UnitLevel`: ✓ all versions.
- `GetBuildInfo`: ✓ all versions (used for `_TOC` detection itself).
- `GetQuestDifficultyColor(level)`: exists on TBC (✓ TBC). May not exist on all versions — the current `WowQuestAPI.GetQuestDifficultyColor` already has a runtime `if GetQuestDifficultyColor then` guard, so absence is handled gracefully. Verify which versions lack it.
- `C_Map.GetAreaInfo(areaID)`: used by Questie providers to resolve zone names from IDs. Likely ✗ on Classic Era (the C_Map namespace was introduced later). Verify.

```markdown
## 9. Miscellaneous

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes |
|---|---|---|---|---|---|
| `UnitLevel(unit)` | ✓ | ✓ | ✓ | ✓ | |
| `GetBuildInfo()` | ✓ | ✓ | ✓ | ✓ | Returns `version, build, date, tocVersion` |
| `GetQuestDifficultyColor(level)` | [research] | ✓ | [research] | [research] | Current wrapper has runtime guard; absence is handled gracefully |
| `C_Map.GetAreaInfo(areaID)` | ✗ | ✓ | ✓ | ✓ | Classic Era: C_Map namespace not present; Questie providers use this for zone resolution |

```

- [ ] **Step 11: Fill all [research] cells**

Go through every `[research]` placeholder. For each one:
1. Search wowpedia for the API name.
2. If wowpedia lists it as removed in a particular version, mark ✗ with the replacement in Notes.
3. If it exists but with a different signature or return type, mark ~ with a description in Notes.
4. If it works identically, mark ✓.
5. If you genuinely cannot find information after checking wowpedia, wow.tools, and searching GitHub for multi-version addon code, mark ? and add a Notes entry: "Could not verify — implication: MoP sub-project must test this at runtime."

Confirm: zero `[research]` placeholders remain. Any remaining `?` must have a Notes entry.

- [ ] **Step 12: Commit**

```bash
git add docs/api-compatibility.md
git commit -m "docs: add API compatibility audit for all four WoW version families

Covers 9 API categories × 4 versions. Research complete — no unresearched cells."
```

---

## Task 4 — Version bump and CLAUDE.md update

**Files:**
- Modify: `AbsoluteQuestLog.toc`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump the version in AbsoluteQuestLog.toc**

Today is 2026-03-28. Check the current version. Per the versioning rule: if this is the first change today, increment the minor version and reset the revision to 0. If other changes were made today already, increment the revision only.

Current version: `2.4.0` (from toc file — last change was version 2.4.1 per CLAUDE.md, so the toc may already be 2.4.1; read it to confirm).

Update `## Version:` in `AbsoluteQuestLog.toc` to match. Also update `## Version:` in **all four new toc files** to match.

- [ ] **Step 2: Update CLAUDE.md**

Add a new version entry at the top of the Version History section in `CLAUDE.md`:

```markdown
### Version 2.5.0 (March 2026)
- Infrastructure: Multi-toc files added for Classic Era (`_Classic`), TBC Anniversary (`_BCC`), MoP Classic (`_MoP`), and Retail (`_Mainline`). AQL now loads without Lua errors on all four active WoW version families.
- Refactor: Version detection constants (`IS_CLASSIC_ERA`, `IS_TBC`, `IS_MOP`, `IS_RETAIL`) replace three ad-hoc `_TOC` numeric comparisons in `WowQuestAPI.lua`. No behavioral change on TBC (20505).
- Docs: `docs/api-compatibility.md` — full API compatibility audit across all four version families (9 categories, all cells researched).
```

(Adjust the version number to whatever was actually set in Step 1.)

- [ ] **Step 3: Commit**

```bash
git add AbsoluteQuestLog.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_BCC.toc AbsoluteQuestLog_MoP.toc AbsoluteQuestLog_Mainline.toc CLAUDE.md
git commit -m "chore: bump version to 2.5.0, update CLAUDE.md for multi-version foundation"
```

---

## Success Criteria

Before calling this plan complete, verify all four:

1. **No raw `_TOC` comparisons remain** in `Core/WowQuestAPI.lua` — search the file for `_TOC >=` and `_TOC <` after Task 1. Only the initial `local _TOC = select(4, GetBuildInfo())` assignment should exist.

2. **All four toc files exist** at the repo root with correct `## Interface:` values and identical file lists.

3. **`docs/api-compatibility.md` has zero `[research]` or unresearched `?` cells** — every cell is ✓, ~, or ✗, with Notes entries for any ~ or ✗ that has a replacement or implication.

4. **TBC functionality is unchanged** — the version constants are purely additive; the logic of all three branches is semantically identical to the before state. Verify by tracing: `IS_RETAIL` = `_TOC >= 100000`, `IS_TBC or IS_MOP or IS_RETAIL` = `_TOC >= 20000`.
