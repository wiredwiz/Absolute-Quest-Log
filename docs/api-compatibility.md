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
| ? | Not yet researched (see Notes column for reason) |

**Version families:**
- Classic Era 1.14.x — Classic Era, Season of Discovery, Hardcore (Interface 11508)
- TBC 2.x — TBC Anniversary (Interface 20505, current — fully working)
- MoP 5.x — Mists of Pandaria Classic (Interface 50503)
- Retail 12.x — Midnight (Interface 120001)

---

## 1. Quest Log Enumeration

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `GetNumQuestLogEntries()` | ✓ | ✓ | ✓ | ~ | Retail: moved to `C_QuestLog.GetNumQuestLogEntries()` in 9.0.1; global still exists as deprecated wrapper |
| `GetQuestLogTitle(logIndex)` | ✓ | ✓ | ✓ | ~ | Retail: moved to `C_QuestLog.GetInfo(logIndex)` in 9.0.1, returns QuestInfo table instead of positional returns |

## 2. Quest Info Resolution

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `C_QuestLog.GetQuestInfo(questID)` | ~ | ~ | ~ | ✗ | All Classic/TBC/MoP: returns title string. Retail: renamed to `C_QuestLog.GetTitleForQuestID()` in 9.0.1 |
| `C_QuestLog.GetQuestObjectives(questID)` | ✓ | ✓ | ✓ | ✓ | Added 8.0.1 / backported to 1.13.2; available on all versions |

## 3. Quest History

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `GetQuestsCompleted()` | ✓ | ✓ | ✓ | ~ | Retail: changed to `C_QuestLog.GetAllCompletedQuestIDs()` in 9.0.1; returns sequential table instead of associative |
| `IsQuestFlaggedCompleted(questID)` | ✓ | ✗ | ✓ | ✓ | Global version. Added 5.0.4 / backported to 1.13.2. Absent on TBC per runtime testing (use C_QuestLog version) |
| `C_QuestLog.IsQuestFlaggedCompleted(questID)` | ✓ | ✓ | ✓ | ✓ | Namespaced version moved to C_QuestLog in 8.2.5; available on all versions |

## 4. Quest Sharing

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `GetQuestLogPushable()` | ✓ | ✓ | ✓ | ~ | Retail: moved to `C_QuestLog.IsPushableQuest()` in 9.0.1; global still exists as deprecated wrapper |
| `QuestLogPushQuest()` | ✓ | ✓ | ✓ | ~ | Retail 9.0.1+: use `C_QuestLog.PushQuest(questID)` instead. Global wrapper may still exist as stub. |

## 5. Quest Log Frame Globals

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `QuestLogFrame` | ✓ | ✓ | ✓ | ✗ | Retail: quest log integrated into World Map in 6.0.2; standalone frame removed |
| `QuestLog_SetSelection(logIndex)` | ✓ | ✓ | ✓ | ✗ | FrameXML function. Retail: use `C_QuestLog.SetSelectedQuest(questID)` (note: takes questID, not logIndex) |
| `QuestLog_Update()` | ✓ | ✓ | ✓ | ✗ | FrameXML function. Retail: no direct equivalent; quest log UI auto-updates |
| `ExpandQuestHeader(logIndex)` | ✓ | ✓ | ✓ | ✓ | Available on all versions since 1.0.0 |
| `CollapseQuestHeader(logIndex)` | ✓ | ✓ | ✓ | ✓ | Available on all versions since 1.0.0 |
| `ShowUIPanel(frame)` | ✓ | ✓ | ✓ | ✓ | Protected during combat since 8.2.0; available on all versions. On Retail, `QuestLogFrame` does not exist (see above), so the quest-log use case requires World Map API instead. `ShowUIPanel`/`HideUIPanel` themselves still exist. |
| `HideUIPanel(frame)` | ✓ | ✓ | ✓ | ✓ | Protected during combat since 8.2.0; available on all versions. On Retail, `QuestLogFrame` does not exist (see above), so the quest-log use case requires World Map API instead. `ShowUIPanel`/`HideUIPanel` themselves still exist. |

## 6. Quest Tracking

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `AddQuestWatch(logIndex)` | ✓ | ✓ | ✓ | ~ | Retail: moved to `C_QuestLog.AddQuestWatch(questID)` in 9.0.1 (note: takes questID, not logIndex) |
| `RemoveQuestWatch(logIndex)` | ✓ | ✓ | ✓ | ~ | Retail: moved to `C_QuestLog.RemoveQuestWatch(questID)` in 9.0.1 (note: takes questID, not logIndex) |
| `MAX_WATCHABLE_QUESTS` | ✓ | ✓ | ✓ | ? | FrameXML constant. Could not verify current Retail value — test at runtime. If nil at runtime, treat as no cap or use a fallback value (e.g., 25). AQL's `TrackQuest` already guards on this constant. |
| `QUEST_WATCH_LIST_CHANGED` | ✓ | ✓ | ✓ | ✓ | Added 6.0.2 / backported to 1.13.2; available on all versions |

## 7. Turn-in Detection

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `GetQuestReward()` | ✓ | ✓ | ✓ | ✓ | Available on all versions since 1.0.0; used as hooksecurefunc target for turn-in detection on TBC |
| `QUEST_TURNED_IN` | ✓ | ✗ | ✓ | ✓ | Added 6.0.2 / backported to 1.13.2. Wiki lists TBC 2.5.5 but does NOT fire on TBC per runtime testing; use GetQuestReward hook instead. Args: questID, xpReward, moneyReward |

## 8. WoW Events

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `QUEST_ACCEPTED` | ~ | ~ | ~ | ✓ | Classic/TBC: arg1 = logIndex only; questID is nil — do not assume arg2 exists. MoP/Retail: arg1 = questID. Added 3.1.0 / backported to 1.13.2 |
| `QUEST_REMOVED` | ✓ | ✓ | ✓ | ✓ | Added 6.0.2 / backported to 1.13.2. Args: questID, wasReplayQuest (wasReplayQuest added 8.2.5) |
| `QUEST_LOG_UPDATE` | ✓ | ✓ | ✓ | ✓ | Available on all versions since 1.0.0 |
| `UNIT_QUEST_LOG_CHANGED` | ✓ | ✓ | ✓ | ✓ | Available on all versions since 1.3.0 |

## 9. Miscellaneous

| API | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| `UnitLevel(unit)` | ✓ | ✓ | ✓ | ✓ | Core API; available on all versions since 1.0.0 |
| `GetBuildInfo()` | ✓ | ✓ | ✓ | ✓ | Core API; available on all versions. Returns version, build, date, tocVersion |
| `GetQuestDifficultyColor(level)` | ✓ | ✓ | ✓ | ✓ | Available on all four versions. The name `GetQuestDifficultyColor` is correct for Classic/TBC — no special handling needed. (Renamed from `GetDifficultyColor` in 3.2.0.) |
| `C_Map.GetAreaInfo(areaID)` | ✓ | ✓ | ✓ | ✓ | Added 8.0.1 / backported to 1.13.2; available on all versions |
| `IsUnitOnQuest(logIndex, unit)` | ✓ | ✗ | ✓ | ~ | Added 1.3.0. Absent on TBC per runtime testing. Retail: moved to `C_QuestLog.IsUnitOnQuest(questID, unit)` in 9.0.1 (note: takes questID, not logIndex) |

---

## Summary of Retail Migration Patterns

Most legacy quest globals were moved to the `C_QuestLog` namespace in Patch 9.0.1 (Shadowlands). The common patterns are:

| Legacy Global | Retail Replacement | Key Difference |
|---|---|---|
| `GetNumQuestLogEntries()` | `C_QuestLog.GetNumQuestLogEntries()` | Same signature |
| `GetQuestLogTitle(logIndex)` | `C_QuestLog.GetInfo(logIndex)` | Returns QuestInfo table |
| `C_QuestLog.GetQuestInfo(questID)` | `C_QuestLog.GetTitleForQuestID(questID)` | Renamed only |
| `GetQuestsCompleted()` | `C_QuestLog.GetAllCompletedQuestIDs()` | Sequential table |
| `GetQuestLogPushable()` | `C_QuestLog.IsPushableQuest()` | Renamed only |
| `AddQuestWatch(logIndex)` | `C_QuestLog.AddQuestWatch(questID)` | Takes questID |
| `RemoveQuestWatch(logIndex)` | `C_QuestLog.RemoveQuestWatch(questID)` | Takes questID |
| `SelectQuestLogEntry(logIndex)` | `C_QuestLog.SetSelectedQuest(questID)` | Takes questID |
| `IsUnitOnQuest(logIndex, unit)` | `C_QuestLog.IsUnitOnQuest(questID, unit)` | Takes questID |
| `QuestLogFrame` | World Map integrated | No standalone frame |
| `QuestLog_SetSelection()` | `C_QuestLog.SetSelectedQuest()` | FrameXML removed |
| `QuestLog_Update()` | *(none)* | Auto-updates |
