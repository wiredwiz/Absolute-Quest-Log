# AQL Classic Era Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Classic Era (1.14.x) support explicit and self-documenting in `Core/WowQuestAPI.lua` and add a provider availability table to `docs/api-compatibility.md`.

**Architecture:** Pure documentation pass — no Lua logic changes. Three comment edits in `WowQuestAPI.lua` (header comment and else-branch comment in `GetQuestInfo`, one added line in `IsQuestFlaggedCompleted`). One new markdown section appended to `docs/api-compatibility.md`. Version bump to 2.5.1 across all toc files and CLAUDE.md.

**Tech Stack:** Lua (WoW addon), Markdown. No test framework — verification is done by reading file contents after each edit.

---

## Files Modified

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | Update `GetQuestInfo` header and else-branch comments; add one line to `IsQuestFlaggedCompleted` header |
| `docs/api-compatibility.md` | Append provider availability section |
| `AbsoluteQuestLog.toc` | Version bump to 2.5.1 |
| `AbsoluteQuestLog_Classic.toc` | Version bump to 2.5.1 |
| `AbsoluteQuestLog_TBC.toc` | Version bump to 2.5.1 |
| `AbsoluteQuestLog_Mists.toc` | Version bump to 2.5.1 |
| `AbsoluteQuestLog_Mainline.toc` | Version bump to 2.5.1 |
| `CLAUDE.md` | Add version 2.5.1 entry |

---

## Background: Why these specific changes

**Version constants (already in place from Foundation sub-project):**
```lua
local IS_CLASSIC_ERA = _TOC <  20000                   -- 1.14.x: Classic Era, SoD, Hardcore
local IS_TBC         = _TOC >= 20000 and _TOC < 30000  -- 2.x: TBC Anniversary
local IS_MOP         = _TOC >= 50000 and _TOC < 60000  -- 5.x: MoP Classic
local IS_RETAIL      = _TOC >= 100000                  -- 11.x+: Retail
```

**`GetQuestInfo` current structure (lines 30–78):**
The function is defined inside an `if IS_RETAIL then ... else ... end` block at load time. The `else` branch serves TBC, Classic Era, AND MoP — all three use the same log-scan API. **Do NOT change `else` to `elseif IS_TBC or IS_CLASSIC_ERA`** — that would leave `WowQuestAPI.GetQuestInfo` as `nil` on MoP clients, causing a call-time Lua error the moment any code calls it.

**`IsQuestFlaggedCompleted` current structure (lines 98–106):**
Already has explicit conditions: `if IS_TBC or IS_MOP or IS_RETAIL then ... else -- IS_CLASSIC_ERA`. The condition is correct; only the function header comment needs updating.

---

## Task 1: Update GetQuestInfo comments in WowQuestAPI.lua

**Files:**
- Modify: `Core/WowQuestAPI.lua:26-27` (header comment)
- Modify: `Core/WowQuestAPI.lua:47` (else-branch comment)
- Modify: `Core/WowQuestAPI.lua:73` (tier-2 comment)

There is no test framework for WoW addons. Verification is done by reading the file after editing and confirming exact line content.

- [ ] **Step 1: Update the GetQuestInfo header comment (lines 26–27)**

  Current text (lines 26–27):
  ```lua
  -- TBC: tier-1 log scan (GetQuestLogTitle), tier-2 C_QuestLog.GetQuestInfo.
  -- Retail: single C_QuestLog.GetQuestInfo call returns full info table.
  ```

  Replace with:
  ```lua
  -- Classic Era, TBC, and MoP: tier-1 log scan (GetQuestLogTitle),
  --   tier-2 C_QuestLog.GetQuestInfo (returns title string on all three versions).
  -- Retail: single C_QuestLog.GetQuestInfo call returns full info table.
  ```

  Use the Edit tool — match on `-- TBC: tier-1 log scan (GetQuestLogTitle), tier-2 C_QuestLog.GetQuestInfo.\n-- Retail: single C_QuestLog.GetQuestInfo call returns full info table.`

- [ ] **Step 2: Verify the header comment change**

  Read `Core/WowQuestAPI.lua` lines 20–30. Confirm:
  - Line 26 reads `-- Classic Era, TBC, and MoP: tier-1 log scan (GetQuestLogTitle),`
  - Line 27 reads `--   tier-2 C_QuestLog.GetQuestInfo (returns title string on all three versions).`
  - Line 28 reads `-- Retail: single C_QuestLog.GetQuestInfo call returns full info table.`

- [ ] **Step 3: Update the else-branch comment (line 47)**

  Current text:
  ```lua
  else  -- IS_TBC (IS_CLASSIC_ERA and IS_MOP handled in later sub-projects)
  ```

  Replace with:
  ```lua
  else  -- IS_TBC, IS_CLASSIC_ERA, and IS_MOP (same log-scan API; MoP sub-project handles MoP-specific improvements)
  ```

  Use the Edit tool — match on the exact old string above.

- [ ] **Step 4: Verify the else-branch comment change**

  Read lines 45–50. Confirm line 47 reads exactly:
  ```lua
  else  -- IS_TBC, IS_CLASSIC_ERA, and IS_MOP (same log-scan API; MoP sub-project handles MoP-specific improvements)
  ```
  Also confirm the surrounding Lua structure is unchanged: `if IS_RETAIL then` above, `end` at line 78 below.

- [ ] **Step 5: Update the tier-2 comment (line 73)**

  Current text:
  ```lua
          -- C_QuestLog.GetQuestInfo(questID) returns a title string or nil on TBC.
  ```

  Replace with:
  ```lua
          -- C_QuestLog.GetQuestInfo(questID) returns a title string or nil on TBC, Classic Era, and MoP.
  ```

  Use the Edit tool — match on the exact old string above (including 8 leading spaces).

- [ ] **Step 6: Verify the tier-2 comment change**

  Read lines 70–78. Confirm the tier-2 comment reads:
  ```lua
          -- C_QuestLog.GetQuestInfo(questID) returns a title string or nil on TBC, Classic Era, and MoP.
  ```
  Also confirm the `end` closing the `else` block is still at line 78 and the `end` closing the `if IS_RETAIL` block is at line 79 (one-indexed; may shift by one with 3-line header).

  > **Note on line number shift:** The header comment was expanded from 2 lines to 3 lines in Step 1, so all subsequent line numbers shift down by 1. The else-branch comment originally at line 47 is now at line 48, and the tier-2 comment originally at line 73 is now at line 74. Verify by content, not line number if there is any doubt.

- [ ] **Step 7: Commit**

  ```bash
  git add Core/WowQuestAPI.lua
  git commit -m "docs: make Classic Era explicit in GetQuestInfo comments"
  ```

---

## Task 2: Update IsQuestFlaggedCompleted header comment in WowQuestAPI.lua

**Files:**
- Modify: `Core/WowQuestAPI.lua` — lines around `IsQuestFlaggedCompleted` function header

- [ ] **Step 1: Add version-routing note to the function header**

  Current text (two dashes block above `if IS_TBC or IS_MOP or IS_RETAIL then`):
  ```lua
  -- WowQuestAPI.IsQuestFlaggedCompleted(questID)
  -- Returns bool. True when the quest is in the character's completion history.
  ```

  Replace with:
  ```lua
  -- WowQuestAPI.IsQuestFlaggedCompleted(questID)
  -- Returns bool. True when the quest is in the character's completion history.
  -- Classic Era: uses global IsQuestFlaggedCompleted(). TBC/MoP/Retail: uses C_QuestLog variant.
  ```

  Use the Edit tool — match on:
  ```
  -- WowQuestAPI.IsQuestFlaggedCompleted(questID)\n-- Returns bool. True when the quest is in the character's completion history.
  ```

- [ ] **Step 2: Verify the change**

  Read the `IsQuestFlaggedCompleted` section. Confirm:
  - The new third header line is present: `-- Classic Era: uses global IsQuestFlaggedCompleted(). TBC/MoP/Retail: uses C_QuestLog variant.`
  - The condition `if IS_TBC or IS_MOP or IS_RETAIL then` immediately follows (no blank line)
  - The `else  -- IS_CLASSIC_ERA` branch and both function bodies are unchanged

- [ ] **Step 3: Commit**

  ```bash
  git add Core/WowQuestAPI.lua
  git commit -m "docs: name Classic Era API variant in IsQuestFlaggedCompleted comment"
  ```

---

## Task 3: Add provider availability section to docs/api-compatibility.md

**Files:**
- Modify: `docs/api-compatibility.md` — append at end of file (currently 121 lines)

- [ ] **Step 1: Verify current end of file**

  Read `docs/api-compatibility.md` lines 115–121. Confirm the last line is:
  ```
  | `QuestLog_Update()` | *(none)* | Auto-updates |
  ```
  This confirms the append point.

- [ ] **Step 2: Append the provider availability section**

  Append the following content to the end of `docs/api-compatibility.md`. Use the Edit tool matching on the last line of the file:

  Old string (the current last line):
  ```
  | `QuestLog_Update()` | *(none)* | Auto-updates |
  ```

  New string (last line + new section):
  ```
  | `QuestLog_Update()` | *(none)* | Auto-updates |

  ---

  ## Provider Availability by Version

  The AQL provider system (Questie, QuestWeaver, NullProvider) supplies chain info, quest
  type, and prerequisite data that is not available from the WoW client API directly.

  | Provider | Classic 1.14.x | TBC 2.x | MoP 5.x | Retail 12.x | Notes |
  |---|---|---|---|---|---|
  | Questie | ✓ | ✓ | ✓ | ✗ | No Retail version exists |
  | QuestWeaver | ✓ | ✓ | ✗ | ✗ | Classic Era and TBC only |
  | NullProvider | ✓ | ✓ | ✓ | ✓ | Always available as fallback |

  **Retail note:** Neither Questie nor QuestWeaver exists for Retail. Chain info always
  returns `knownStatus = "unknown"` on Retail. Quest type, level, and objective data are
  available through native `C_QuestLog` APIs without a provider — this is sufficient for
  most AQL functionality on Retail.

  **MoP note:** Questie supports MoP Classic. QuestWeaver does not support MoP —
  treat as NullProvider fallback on MoP.
  ```

- [ ] **Step 3: Verify the appended section**

  Read `docs/api-compatibility.md` lines 119–145 (approximately). Confirm:
  - A `---` separator appears after the migration table
  - The `## Provider Availability by Version` heading is present
  - The provider table has 3 data rows (Questie, QuestWeaver, NullProvider)
  - QuestWeaver MoP column shows `✗`
  - QuestWeaver Notes reads "Classic Era and TBC only"
  - The Retail note paragraph is present
  - The MoP note paragraph is present and says "QuestWeaver does not support MoP"

- [ ] **Step 4: Commit**

  ```bash
  git add docs/api-compatibility.md
  git commit -m "docs: add provider availability table to api-compatibility.md"
  ```

---

## Task 4: Version bump and CLAUDE.md update

**Files:**
- Modify: `AbsoluteQuestLog.toc`
- Modify: `AbsoluteQuestLog_Classic.toc`
- Modify: `AbsoluteQuestLog_TBC.toc`
- Modify: `AbsoluteQuestLog_Mists.toc`
- Modify: `AbsoluteQuestLog_Mainline.toc`
- Modify: `CLAUDE.md`

**Versioning rule:** Version 2.5.0 was set earlier today (2026-03-29). This is the second set of changes on the same day, so the version becomes **2.5.1** (revision increments; minor stays).

- [ ] **Step 1: Bump version in all toc files**

  In each of the five toc files, change:
  ```
  ## Version: 2.5.0
  ```
  To:
  ```
  ## Version: 2.5.1
  ```

  Edit all five files:
  - `AbsoluteQuestLog.toc`
  - `AbsoluteQuestLog_Classic.toc`
  - `AbsoluteQuestLog_TBC.toc`
  - `AbsoluteQuestLog_Mists.toc`
  - `AbsoluteQuestLog_Mainline.toc`

- [ ] **Step 2: Verify version bump**

  Run:
  ```bash
  grep "Version:" AbsoluteQuestLog*.toc
  ```
  Expected: all five files show `## Version: 2.5.1`

- [ ] **Step 3: Add version 2.5.1 entry to CLAUDE.md**

  In `CLAUDE.md`, find the Version History section. Locate the `### Version 2.5.0` heading and insert the following block **above** it (2.5.1 is newer and goes at the top of the history):

  ```markdown
  ### Version 2.5.1 (March 2026)
  - Docs: Classic Era support made explicit in `Core/WowQuestAPI.lua` — `GetQuestInfo` else-branch comment now names IS_TBC, IS_CLASSIC_ERA, and IS_MOP; header and tier-2 comments updated accordingly. `IsQuestFlaggedCompleted` header comment notes which API each version uses.
  - Docs: `docs/api-compatibility.md` — provider availability table added (Questie/QuestWeaver/NullProvider × 4 version families). QuestWeaver confirmed Classic Era and TBC only (no MoP). Retail chain info confirmed always-unknown (no provider exists).

  ```

- [ ] **Step 4: Verify CLAUDE.md update**

  Read the Version History section of `CLAUDE.md`. Confirm:
  - `### Version 2.5.1 (March 2026)` appears above `### Version 2.5.0`
  - The two bullet points are present and accurate

- [ ] **Step 5: Commit**

  ```bash
  git add AbsoluteQuestLog.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Mainline.toc CLAUDE.md
  git commit -m "chore: bump version to 2.5.1 — Classic Era support documented"
  ```

---

## Final Verification

After all four tasks are complete, perform a final check:

- [ ] **Verify no deferred comments remain**

  ```bash
  grep -n "later sub-projects" Core/WowQuestAPI.lua
  ```
  Expected: no output (0 matches).

- [ ] **Verify provider table is in api-compatibility.md**

  ```bash
  grep -n "Provider Availability" docs/api-compatibility.md
  ```
  Expected: one match on the `## Provider Availability by Version` heading.

- [ ] **Verify version is 2.5.1 everywhere**

  ```bash
  grep "Version:" AbsoluteQuestLog*.toc
  grep "Version 2.5.1" CLAUDE.md
  ```
  Expected: five toc files at 2.5.1, one CLAUDE.md match.
