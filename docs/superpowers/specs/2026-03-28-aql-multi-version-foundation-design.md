# AQL Multi-Version Foundation — Design Spec

**Date:** 2026-03-28
**Repo:** Absolute-Quest-Log
**Feature:** Multi-toc infrastructure, version detection constants, API compatibility audit

---

## Goal

Establish the infrastructure that enables AQL to load correctly on all currently active WoW version families, and produce a structured API compatibility audit that guides the subsequent per-version implementation sub-projects.

No behavioral changes to existing TBC functionality. After this sub-project, AQL still only works correctly on TBC Anniversary — but it loads without errors on all versions, the version detection constants are in place, and every API call used by AQL has been researched and documented.

---

## Context

AQL currently targets Interface 20505 (TBC Anniversary) exclusively. `WowQuestAPI.lua` already contains a `_TOC = select(4, GetBuildInfo())` version detection pattern and three ad-hoc branches: `_TOC >= 100000` appears twice (for `GetQuestInfo` and `IsUnitOnQuest`) and `_TOC >= 20000` once (for `IsQuestFlaggedCompleted`). The existing abstraction — all WoW API calls routed through `WowQuestAPI.lua`, no raw WoW globals elsewhere — means most future version-specific work lands in that one file.

**Out-of-scope version families:** WotLK Classic (3.x) and Cataclysm Classic (4.x) are not target versions for this project. Their TOC ranges (30000–49999) are intentionally not covered by any `IS_*` constant. If AQL is loaded on those clients it falls back to the base `AbsoluteQuestLog.toc` (Interface 20505) and is unsupported. The `IS_TBC` upper bound of `< 30000` captures this gap cleanly.

**Target version families:**

| Family | Versions covered | Interface range |
|---|---|---|
| Classic Era | Classic Era, Season of Discovery, Hardcore | 1.14.x (~11503) |
| TBC | TBC Anniversary | 2.x (20505) — current |
| MoP Classic | Mists of Pandaria Classic | 5.x (~50500, to verify) |
| Retail | The War Within and forward | 11.x+ (~110107, to verify) |

---

## Deliverable 1 — Multi-toc infrastructure

### Files created

Five `.toc` files in the addon root. Each has the same `# file list` section as the current `AbsoluteQuestLog.toc`; only `## Interface:`, `## Notes:`, and `## Title:` differ.

| File | Interface | Notes field |
|---|---|---|
| `AbsoluteQuestLog.toc` | 20505 | Keep as-is; base fallback |
| `AbsoluteQuestLog_Classic.toc` | 11503 | Classic Era, Season of Discovery, Hardcore |
| `AbsoluteQuestLog_BCC.toc` | 20505 | TBC Anniversary — **verify suffix is correct for Anniversary client** |
| `AbsoluteQuestLog_MoP.toc` | TBD | MoP Classic — **verify exact interface number** |
| `AbsoluteQuestLog_Mainline.toc` | TBD | Retail — **verify exact interface number** |

**Interface numbers and suffix names to verify before committing:**
- `_BCC`: This suffix was introduced for the original TBC Classic (2021). TBC Anniversary may use the same suffix or a different one — confirm against Blizzard's current multi-toc documentation or a known working addon on Anniversary servers. If `_BCC` is not the correct Anniversary suffix, the base `AbsoluteQuestLog.toc` (20505) will serve as the fallback and a corrected suffixed toc can be added.
- `_MoP`: Confirm the exact interface number from `GetBuildInfo()` on a live MoP Classic client or Blizzard's patch notes.
- `_Mainline`: Confirm the current Retail interface number; this changes each patch. Use the most recent patch number at time of implementation.

All five toc files load the same Lua files in the same order as the current toc. No new Lua files are introduced by this deliverable.

---

## Deliverable 2 — Version detection constants

### File modified: `Core/WowQuestAPI.lua`

Replace the existing ad-hoc `_TOC` comparisons with named constants defined once at the top of the file, immediately after `_TOC` is set:

```lua
local _TOC           = select(4, GetBuildInfo())
local IS_CLASSIC_ERA = _TOC <  20000                   -- 1.14.x: Classic Era, SoD, Hardcore
local IS_TBC         = _TOC >= 20000 and _TOC < 30000  -- 2.x: TBC Anniversary (current)
local IS_MOP         = _TOC >= 50000 and _TOC < 60000  -- 5.x: MoP Classic
local IS_RETAIL      = _TOC >= 100000                  -- 11.x+: Retail (The War Within+)
```

**Existing branches to update (all three):**

| Location in `WowQuestAPI.lua` | Current expression | Replace with |
|---|---|---|
| `GetQuestInfo` (line ~24) | `if _TOC >= 100000 then` | `if IS_RETAIL then` |
| `IsQuestFlaggedCompleted` (line ~92) | `if _TOC >= 20000 then` | `if IS_TBC or IS_MOP or IS_RETAIL then` |
| `IsUnitOnQuest` (line ~147) | `if _TOC >= 100000 then` | `if IS_RETAIL then` |

The `else` comment on the `GetQuestInfo` branch should be updated from `-- TBC Classic / TBC Anniversary (and Classic Era stub)` to `-- IS_TBC (IS_CLASSIC_ERA and IS_MOP handled in later sub-projects)`.

These constants are **local to `WowQuestAPI.lua`**. Nothing outside this file branches on version — all version differences are encapsulated inside `WowQuestAPI` wrappers. If any future code outside `WowQuestAPI.lua` needs version-specific behavior, it gets a new wrapper, not a raw `_TOC` check.

---

## Deliverable 3 — API compatibility audit

### File created: `docs/api-compatibility.md`

A structured Markdown document mapping every WoW API call used by AQL against all four version families. Produced by the implementer during this sub-project through research (Blizzard documentation, wowpedia, known addon community references).

**Legend:**

| Symbol | Meaning |
|---|---|
| ✓ | Works as-is, same signature and return type |
| ~ | Present but different signature, return type, or namespace |
| ✗ | Absent / removed in this version |
| ? | Not yet researched |

**Categories to cover** (one table per category):

1. **Quest log enumeration** — `GetNumQuestLogEntries`, `GetQuestLogTitle`
2. **Quest info resolution** — `C_QuestLog.GetQuestInfo`, `C_QuestLog.GetQuestObjectives`
3. **Quest history** — `GetQuestsCompleted`, `IsQuestFlaggedCompleted`, `C_QuestLog.IsQuestFlaggedCompleted`
4. **Quest sharing** — `GetQuestLogPushable`, `QuestLogPushQuest`
5. **Quest log frame globals** — `QuestLogFrame`, `QuestLog_SetSelection`, `QuestLog_Update`, `ExpandQuestHeader`, `CollapseQuestHeader`, `ShowUIPanel`, `HideUIPanel`
6. **Quest tracking** — `AddQuestWatch`, `RemoveQuestWatch`, `MAX_WATCHABLE_QUESTS`, `QUEST_WATCH_LIST_CHANGED` event
7. **Turn-in detection** — `GetQuestReward` (`hooksecurefunc` target), `QUEST_TURNED_IN` event
8. **WoW events** — `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_LOG_UPDATE`, `UNIT_QUEST_LOG_CHANGED`
9. **Miscellaneous** — `UnitLevel`, `GetBuildInfo`, `GetQuestDifficultyColor`, `C_Map.GetAreaInfo`

**Required columns:** Classic Era 1.14.x | TBC 2.x | MoP 5.x | Retail 11.x | Notes

Any cell that remains `?` at the end of this sub-project must have a comment in the Notes column explaining why it could not be researched and what the implication is for the relevant version sub-project.

---

## Files Modified

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | Add four named version constants; replace three ad-hoc `_TOC` comparisons |

## Files Created

| File | Purpose |
|---|---|
| `AbsoluteQuestLog_Classic.toc` | Loads AQL on Classic Era / SoD / Hardcore |
| `AbsoluteQuestLog_BCC.toc` | Loads AQL on TBC Anniversary (explicit suffix) |
| `AbsoluteQuestLog_MoP.toc` | Loads AQL on MoP Classic |
| `AbsoluteQuestLog_Mainline.toc` | Loads AQL on Retail |
| `docs/api-compatibility.md` | API compatibility audit across all four version families |

## Not In Scope

- Any behavioral changes to existing TBC functionality
- Implementing support for Classic Era, MoP, or Retail (those are separate sub-projects)
- Provider changes (Questie/QuestWeaver availability per version is researched in the audit but not implemented)
- SocialQuest changes — AQL Foundation is AQL-only
- Any new public API methods

---

## Success Criteria

1. AQL loads without Lua errors on Classic Era, TBC, MoP Classic, and Retail clients (even if it does nothing useful yet on non-TBC versions).
2. All existing TBC functionality is unchanged — AQL behaves identically on TBC Anniversary before and after this sub-project.
3. `docs/api-compatibility.md` has zero unresearched `?` cells, or any remaining `?` cells are explicitly documented with a reason.
4. Version constants are used consistently — no remaining raw `_TOC` numeric comparisons in `WowQuestAPI.lua`.
