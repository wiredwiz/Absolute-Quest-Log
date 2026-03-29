# AQL Classic Era Support — Design Spec

**Date:** 2026-03-29
**Repo:** Absolute-Quest-Log
**Feature:** Explicit Classic Era (1.14.x) support — condition pass in WowQuestAPI.lua + provider notes in API audit

---

## Goal

Make Classic Era (1.14.x) support explicit and self-documenting in the codebase. The Foundation sub-project established version detection constants and confirmed via API audit that Classic Era uses the same API surface as TBC for all functions in scope. This sub-project fulfills the deferred promise in the Foundation comments ("IS_CLASSIC_ERA handled in later sub-projects") by making Classic Era explicit in every branch.

No behavioral changes to any existing functionality. After this sub-project, a developer reading `WowQuestAPI.lua` can immediately see which versions each branch covers — there are no implicit fallthrough assumptions.

---

## Context

### What the Foundation left deferred

`WowQuestAPI.GetQuestInfo` currently has:

```lua
if IS_RETAIL then
    -- Retail-specific C_QuestLog.GetQuestInfo (returns full table)
else  -- IS_TBC (IS_CLASSIC_ERA and IS_MOP handled in later sub-projects)
    -- Log-scan tier-1 + C_QuestLog.GetQuestInfo title-string tier-2
end
```

The `else` branch covers Classic Era by accident of logic — `_TOC < 20000` falls through to it. The comment explicitly flags this as deferred.

### Why Classic Era uses the same code as TBC

The API compatibility audit (`docs/api-compatibility.md`) confirms:

| API | Classic 1.14.x | TBC 2.x |
|---|---|---|
| `GetNumQuestLogEntries()` | ✓ | ✓ |
| `GetQuestLogTitle(logIndex)` | ✓ | ✓ |
| `C_QuestLog.GetQuestInfo(questID)` | ~ (returns title string) | ~ (returns title string) |
| `C_QuestLog.GetQuestObjectives(questID)` | ✓ | ✓ |
| `IsQuestFlaggedCompleted` (global) | ✓ | ✗ |
| `C_QuestLog.IsQuestFlaggedCompleted` | ✗ | ✓ |

Classic Era and TBC use identical tier-1 (log scan) and tier-2 (title-string fallback) logic. No Classic Era-specific code paths are needed — only explicit acknowledgment in the conditions.

### Provider availability

- **Questie**: Available for Classic Era (1.14.x), TBC, and MoP Classic. Not available for Retail.
- **QuestWeaver**: Available for Classic Era and TBC. Retail status unknown/unavailable.
- **Retail**: Neither provider is available. Chain info always returns `knownStatus = "unknown"`. The richer native `C_QuestLog` APIs on Retail supply quest type, level, and objective data without a provider — chain relationship data is not available through any native Retail API.

This provider picture is currently undocumented in `docs/api-compatibility.md`. This sub-project adds it.

---

## Deliverable 1 — WowQuestAPI.lua condition pass

### File modified: `Core/WowQuestAPI.lua`

Three locations require updates. No logic changes — only condition expressions and comments.

#### Location 1: `GetQuestInfo` — line 26-27 header comment and line 47 condition

**Header comment** (lines 26–27), update to:
```lua
-- Classic Era and TBC: tier-1 log scan (GetQuestLogTitle),
--   tier-2 C_QuestLog.GetQuestInfo (returns title string on both versions).
-- Retail: single C_QuestLog.GetQuestInfo call returns full info table.
```

**Condition** (line 47), change from:
```lua
else  -- IS_TBC (IS_CLASSIC_ERA and IS_MOP handled in later sub-projects)
```
To:
```lua
elseif IS_TBC or IS_CLASSIC_ERA then  -- same API surface; MoP handled in MoP sub-project
```

This requires adding a closing `end` to terminate the `if/elseif` block (the current `else` terminates with `end` at line 78; the `elseif` form needs the same `end`).

**Tier-2 comment** (line 73), update from:
```lua
-- C_QuestLog.GetQuestInfo(questID) returns a title string or nil on TBC.
```
To:
```lua
-- C_QuestLog.GetQuestInfo(questID) returns a title string or nil on TBC and Classic Era.
```

#### Location 2: `IsQuestFlaggedCompleted` — line 94-96 header comment

The condition (`if IS_TBC or IS_MOP or IS_RETAIL then ... else -- IS_CLASSIC_ERA`) is already correct and explicit. Only the function header comment needs updating to name Classic Era:

Current (line 94):
```lua
-- Returns bool. True when the quest is in the character's completion history.
```

Add one line below it:
```lua
-- Classic Era: uses global IsQuestFlaggedCompleted(). TBC/MoP/Retail: uses C_QuestLog variant.
```

#### Location 3: `IsUnitOnQuest` — header comment

The condition (`if IS_RETAIL then ... else return nil`) correctly returns nil for Classic Era and TBC. The header comment already says "Returns nil on TBC/Classic". Confirm this comment explicitly names Classic Era. If it reads only "TBC/Classic" already — no change. If it says "Returns nil on TBC" only — update to "Returns nil on TBC and Classic Era (API does not exist)".

---

## Deliverable 2 — API audit provider section

### File modified: `docs/api-compatibility.md`

Add a new section at the end of the document:

```markdown
---

## Provider Availability by Version

The AQL provider system (Questie, QuestWeaver, NullProvider) supplies chain info, quest
type, and prerequisite data that is not available from the WoW client API directly.

| Provider | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
|---|---|---|---|---|---|
| Questie | ✓ | ✓ | ✓ | ✗ | No Retail version exists |
| QuestWeaver | ✓ | ✓ | ? | ✗ | QuestWeaver MoP support unconfirmed |
| NullProvider | ✓ | ✓ | ✓ | ✓ | Always available as fallback |

**Retail note:** Neither Questie nor QuestWeaver exists for Retail. Chain info always
returns `knownStatus = "unknown"` on Retail. Quest type, level, and objective data are
available through native `C_QuestLog` APIs without a provider — this is sufficient for
most AQL functionality on Retail.

**MoP note:** Questie supports MoP Classic. QuestWeaver MoP support is unconfirmed —
treat as NullProvider fallback until verified in the MoP sub-project.
```

---

## Files Modified

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | Update `GetQuestInfo` condition and comments; confirm `IsQuestFlaggedCompleted` and `IsUnitOnQuest` comments |
| `docs/api-compatibility.md` | Add provider availability section |

## Not In Scope

- Any behavioral changes to TBC or Classic Era functionality
- MoP Classic support (separate sub-project)
- Retail support (separate sub-project)
- Provider implementation changes (QuestieProvider, QuestWeaverProvider)
- New public API methods

---

## Success Criteria

1. No branch in `WowQuestAPI.lua` has a comment deferring Classic Era to "later sub-projects."
2. Every `if/elseif/else` block in `WowQuestAPI.lua` explicitly names all version families it covers (no implicit fallthrough assumptions).
3. `docs/api-compatibility.md` has a provider availability table with Retail, MoP, QuestWeaver notes documented.
4. TBC behavior is byte-for-byte identical before and after — the condition `IS_TBC or IS_CLASSIC_ERA` is logically equivalent to the previous `else` for any TBC client.
