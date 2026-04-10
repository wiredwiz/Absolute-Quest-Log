# AQL questID API Audit & README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two missing questID-based methods, mark seven logIndex-exposing thin wrappers as deprecated, restructure CLAUDE.md Group 2 tables, and rewrite README.md as a complete consumer-facing reference.

**Architecture:** All code changes are in `AbsoluteQuestLog.lua` (public API file). Two new methods follow the existing ById pattern exactly. Seven deprecation markers are doc-comment-only — no function bodies change. CLAUDE.md and README.md are documentation updates only.

**Tech Stack:** Lua (WoW addon), Markdown. No automated test framework — verification is by reading file content after each edit.

---

## Files Modified

| File | Change |
|---|---|
| `AbsoluteQuestLog.lua` | Add 2 new methods; add `@deprecated` markers to 7 method doc blocks |
| `CLAUDE.md` | Restructure Group 2 thin wrappers into Preferred/Deprecated; add new methods to tables; add version entry |
| `README.md` | Complete rewrite — consumer-facing API reference |
| `AbsoluteQuestLog.toc` + four version tocs | Version bump 2.5.3 → 2.5.4 |
| `changelog.txt` | Add 2.5.4 entry |

---

## Task 1: AbsoluteQuestLog.lua — Add 2 new methods

**Files:**
- Modify: `AbsoluteQuestLog.lua`

---

- [ ] **Step 1: Read the insertion area for GetSelectedQuestLogEntryId**

  Read `AbsoluteQuestLog.lua` lines 682–703. You will see `GetSelectedQuestId()`. The new method goes immediately after it.

---

- [ ] **Step 2: Add GetSelectedQuestLogEntryId after GetSelectedQuestId**

  Find:
  ```lua
  -- GetSelectedQuestId() → questID or nil
  -- Returns the questID of the currently selected quest log entry.
  -- Returns nil if nothing is selected (logIndex = 0) or if the selected
  -- entry is a zone header row.
  function AQL:GetSelectedQuestId()
  ```

  Replace with:
  ```lua
  -- GetSelectedQuestId() → questID or nil
  -- Returns the questID of the currently selected quest log entry.
  -- Returns nil if nothing is selected (logIndex = 0) or if the selected
  -- entry is a zone header row.
  -- @deprecated Use GetSelectedQuestLogEntryId() instead. This method name
  -- is ambiguous about which selection context it refers to. Will be removed
  -- in a future major version.
  function AQL:GetSelectedQuestId()
  ```

  Then find the end of `GetSelectedQuestId` (the `end` on line ~702) and the start of the next function. The full block ending is:
  ```lua
      return questID
  end

  -- GetQuestLogEntries() → array
  ```

  Replace with:
  ```lua
      return questID
  end

  ------------------------------------------------------------------------
  -- GetSelectedQuestLogEntryId() → questID or nil
  -- Returns the questID of the currently selected quest log entry.
  -- Returns nil if nothing is selected or if the selected entry is a zone
  -- header row.
  -- Replaces: GetSelectedQuestId() (deprecated)
  ------------------------------------------------------------------------
  function AQL:GetSelectedQuestLogEntryId()
      local logIndex = WowQuestAPI.GetQuestLogSelection()
      if not logIndex or logIndex == 0 then
          if self.debug then
              DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestLogEntryId: no entry selected — returning nil" .. self.RESET)
          end
          return nil
      end
      local _, _, _, isHeader, _, _, _, questID = WowQuestAPI.GetQuestLogTitle(logIndex)
      if isHeader or not questID then
          if self.debug then
              DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] GetSelectedQuestLogEntryId: selected entry logIndex=" .. tostring(logIndex) .. " is a zone header — returning nil" .. self.RESET)
          end
          return nil
      end
      return questID
  end

  -- GetQuestLogEntries() → array
  ```

  > **CRITICAL:** The guard on the header check MUST be `if isHeader or not questID then` — not just `if isHeader then`. Verify this after the edit.

---

- [ ] **Step 3: Verify GetSelectedQuestLogEntryId**

  Read lines 682–730 of `AbsoluteQuestLog.lua`. Confirm:
  - `GetSelectedQuestId` has the `@deprecated` marker at the top of its doc block
  - `GetSelectedQuestLogEntryId` follows immediately after
  - The guard reads `if isHeader or not questID then` (not just `if isHeader then`)
  - The debug messages use `GetSelectedQuestLogEntryId` as the method name
  - `GetQuestLogEntries` still follows

---

- [ ] **Step 4: Add SelectQuestLogEntryById after IsQuestIdShareable**

  Read lines 879–906. Confirm `IsQuestIdShareable` ends at ~line 892 and `SelectAndShowQuestLogEntryById` starts at ~line 894.

  Find:
  ```lua
  function AQL:IsQuestIdShareable(questID)
      local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
      if not logIndex then
          if self.debug then
              DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] IsQuestIdShareable: questID=" .. tostring(questID) .. " not in quest log — returning false" .. self.RESET)
          end
          return false
      end
      return self:IsQuestIndexShareable(logIndex)
  end

  -- SelectAndShowQuestLogEntryById(questID)
  ```

  Replace with:
  ```lua
  function AQL:IsQuestIdShareable(questID)
      local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
      if not logIndex then
          if self.debug then
              DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] IsQuestIdShareable: questID=" .. tostring(questID) .. " not in quest log — returning false" .. self.RESET)
          end
          return false
      end
      return self:IsQuestIndexShareable(logIndex)
  end

  -- SelectQuestLogEntryById(questID)
  -- Selects questID in the quest log WITHOUT refreshing the display.
  -- Use SelectAndShowQuestLogEntryById to select and refresh simultaneously.
  -- No-op with a normal-level debug message if questID is not in the log.
  function AQL:SelectQuestLogEntryById(questID)
      local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
      if not logIndex then
          if self.debug then
              DEFAULT_CHAT_FRAME:AddMessage(self.DBG .. "[AQL] SelectQuestLogEntryById: questID=" .. tostring(questID) .. " not in quest log — no-op" .. self.RESET)
          end
          return
      end
      WowQuestAPI.SelectQuestLogEntry(logIndex)
  end

  -- SelectAndShowQuestLogEntryById(questID)
  ```

---

- [ ] **Step 5: Verify SelectQuestLogEntryById**

  Read lines 879–910. Confirm:
  - `SelectQuestLogEntryById` is present between `IsQuestIdShareable` and `SelectAndShowQuestLogEntryById`
  - It calls `WowQuestAPI.SelectQuestLogEntry(logIndex)` (not `WowQuestAPI.QuestLog_SetSelection`)
  - The no-op guard and debug message follow the same pattern as other ById methods

---

- [ ] **Step 6: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add AbsoluteQuestLog.lua && git commit -m "feat: add GetSelectedQuestLogEntryId and SelectQuestLogEntryById; deprecate GetSelectedQuestId"
  ```

---

## Task 2: AbsoluteQuestLog.lua — Deprecation markers on remaining 6 methods

**Files:**
- Modify: `AbsoluteQuestLog.lua`

Add `@deprecated` doc comment lines to the remaining 6 methods. Work top-to-bottom. Do NOT change any function body.

---

- [ ] **Step 1: Deprecate GetQuestLogSelection (line ~526)**

  Find:
  ```lua
  -- GetQuestLogSelection() → logIndex
  -- Returns the currently selected quest log entry index (0 if none selected).
  function AQL:GetQuestLogSelection()
  ```

  Replace with:
  ```lua
  -- GetQuestLogSelection() → logIndex
  -- Returns the currently selected quest log entry index (0 if none selected).
  -- @deprecated Use GetSelectedQuestLogEntryId() instead. Returns a raw logIndex
  -- which is not stable across WoW version families. Will be removed in a future
  -- major version.
  function AQL:GetQuestLogSelection()
  ```

---

- [ ] **Step 2: Deprecate SelectQuestLogEntry (line ~532)**

  Find:
  ```lua
  -- SelectQuestLogEntry(logIndex)
  -- Sets the selected entry without refreshing the quest log display.
  -- Does not emit a debug message — use SetQuestLogSelection for the
  -- display-refreshing version.
  function AQL:SelectQuestLogEntry(logIndex)
  ```

  Replace with:
  ```lua
  -- SelectQuestLogEntry(logIndex)
  -- Sets the selected entry without refreshing the quest log display.
  -- Does not emit a debug message — use SetQuestLogSelection for the
  -- display-refreshing version.
  -- @deprecated Use SelectQuestLogEntryById(questID) instead. Takes a raw
  -- logIndex which is not stable across WoW version families. Will be removed
  -- in a future major version.
  function AQL:SelectQuestLogEntry(logIndex)
  ```

---

- [ ] **Step 3: Deprecate IsQuestLogShareable (line ~540)**

  Find:
  ```lua
  -- IsQuestLogShareable() → bool
  -- Returns true if the currently selected quest can be shared with party members.
  -- Delegates to WowQuestAPI.GetQuestLogPushable().
  -- WARNING: Result depends entirely on the current quest log selection.
  -- If nothing is selected or the wrong entry is selected, the result is
  -- meaningless. Prefer IsQuestIndexShareable or IsQuestIdShareable when
  -- operating on a specific quest. This method exists only for callers that
  -- have already managed selection themselves.
  -- Emits no debug message (pass-through; caller manages selection context).
  function AQL:IsQuestLogShareable()
  ```

  Replace with:
  ```lua
  -- IsQuestLogShareable() → bool
  -- Returns true if the currently selected quest can be shared with party members.
  -- Delegates to WowQuestAPI.GetQuestLogPushable().
  -- WARNING: Result depends entirely on the current quest log selection.
  -- If nothing is selected or the wrong entry is selected, the result is
  -- meaningless. Prefer IsQuestIndexShareable or IsQuestIdShareable when
  -- operating on a specific quest. This method exists only for callers that
  -- have already managed selection themselves.
  -- Emits no debug message (pass-through; caller manages selection context).
  -- @deprecated Use IsQuestIdShareable(questID) instead. Selection-dependent
  -- with no parameters — fragile by design. Will be removed in a future major
  -- version.
  function AQL:IsQuestLogShareable()
  ```

---

- [ ] **Step 4: Deprecate SetQuestLogSelection (line ~553)**

  Find:
  ```lua
  -- SetQuestLogSelection(logIndex)
  -- Sets selection AND refreshes the quest log display.
  -- Calls WowQuestAPI.QuestLog_SetSelection(logIndex) followed immediately
  -- by WowQuestAPI.QuestLog_Update(). These two calls are always used together;
  -- this is the canonical two-call sequence.
  function AQL:SetQuestLogSelection(logIndex)
  ```

  Replace with:
  ```lua
  -- SetQuestLogSelection(logIndex)
  -- Sets selection AND refreshes the quest log display.
  -- Calls WowQuestAPI.QuestLog_SetSelection(logIndex) followed immediately
  -- by WowQuestAPI.QuestLog_Update(). These two calls are always used together;
  -- this is the canonical two-call sequence.
  -- @deprecated Use SelectAndShowQuestLogEntryById(questID) instead. Takes a
  -- raw logIndex which is not stable across WoW version families. Will be
  -- removed in a future major version.
  function AQL:SetQuestLogSelection(logIndex)
  ```

---

- [ ] **Step 5: Deprecate ExpandQuestLogHeader (line ~566)**

  Find:
  ```lua
  -- ExpandQuestLogHeader(logIndex)
  -- Expands the collapsed zone header at logIndex.
  -- Verifies the entry is a header before acting; emits a normal-level debug
  -- message and returns without expanding if it is not.
  -- Emits a verbose debug message on successful expansion.
  function AQL:ExpandQuestLogHeader(logIndex)
  ```

  Replace with:
  ```lua
  -- ExpandQuestLogHeader(logIndex)
  -- Expands the collapsed zone header at logIndex.
  -- Verifies the entry is a header before acting; emits a normal-level debug
  -- message and returns without expanding if it is not.
  -- Emits a verbose debug message on successful expansion.
  -- @deprecated Use ExpandQuestLogZoneByName(zoneName) instead. Zone name is
  -- the stable identifier; logIndex changes on every quest log update. Will be
  -- removed in a future major version.
  function AQL:ExpandQuestLogHeader(logIndex)
  ```

---

- [ ] **Step 6: Deprecate CollapseQuestLogHeader (line ~585)**

  Find:
  ```lua
  -- CollapseQuestLogHeader(logIndex)
  -- Collapses the zone header at logIndex.
  -- Verifies the entry is a header before acting; emits a normal-level debug
  -- message and returns without collapsing if it is not.
  -- Emits a verbose debug message on successful collapse.
  function AQL:CollapseQuestLogHeader(logIndex)
  ```

  Replace with:
  ```lua
  -- CollapseQuestLogHeader(logIndex)
  -- Collapses the zone header at logIndex.
  -- Verifies the entry is a header before acting; emits a normal-level debug
  -- message and returns without collapsing if it is not.
  -- Emits a verbose debug message on successful collapse.
  -- @deprecated Use CollapseQuestLogZoneByName(zoneName) instead. Zone name is
  -- the stable identifier; logIndex changes on every quest log update. Will be
  -- removed in a future major version.
  function AQL:CollapseQuestLogHeader(logIndex)
  ```

---

- [ ] **Step 7: Verify all deprecation markers**

  Run:
  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -n "@deprecated" AbsoluteQuestLog.lua
  ```

  Expected: 7 lines, one for each of: `GetQuestLogSelection`, `GetSelectedQuestId`, `IsQuestLogShareable`, `SelectQuestLogEntry`, `SetQuestLogSelection`, `ExpandQuestLogHeader`, `CollapseQuestLogHeader`.

  Also confirm no function bodies changed:
  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -n "function AQL:GetQuestLogSelection\|function AQL:SelectQuestLogEntry\|function AQL:IsQuestLogShareable\|function AQL:SetQuestLogSelection\|function AQL:ExpandQuestLogHeader\|function AQL:CollapseQuestLogHeader" AbsoluteQuestLog.lua
  ```
  Expected: 6 results, all function declarations unchanged.

---

- [ ] **Step 8: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add AbsoluteQuestLog.lua && git commit -m "deprecate: mark 6 logIndex-exposing thin wrappers as @deprecated with replacements"
  ```

---

## Task 3: CLAUDE.md — Restructure Group 2 tables

**Files:**
- Modify: `CLAUDE.md`

---

- [ ] **Step 1: Replace the Thin Wrappers table with Preferred + Deprecated sub-sections**

  Find the current "#### Thin Wrappers" table. It starts with:
  ```
  #### Thin Wrappers

  | Method | Returns | Notes |
  |---|---|---|
  | `AQL:ShowQuestLog()` | — | Opens the quest log frame |
  ```

  And ends before `#### Compound — ByIndex`. Replace the entire Thin Wrappers section (from `#### Thin Wrappers` through the closing table row before `#### Compound`) with:

  ```markdown
  #### Thin Wrappers — Preferred

  | Method | Returns | Notes |
  |---|---|---|
  | `AQL:ShowQuestLog()` | — | Opens the quest log frame |
  | `AQL:HideQuestLog()` | — | Closes the quest log frame |
  | `AQL:IsQuestLogShown()` | bool | True if quest log is visible |
  | `AQL:GetQuestDifficultyColor(level)` | `{r,g,b}` | Fallback to manual delta if native API absent |
  | `AQL:GetQuestLogIndex(questID)` | logIndex or nil | nil if not in log or under collapsed header |

  #### Thin Wrappers — Deprecated

  > ⚠️ **Deprecated.** These methods expose logIndex or implicit selection state that is not stable across WoW version families. Use the questID-based alternatives shown. They will be removed in a future major version.

  | Deprecated Method | Replacement |
  |---|---|
  | `AQL:GetQuestLogSelection()` | `AQL:GetSelectedQuestLogEntryId()` |
  | `AQL:IsQuestLogShareable()` | `AQL:IsQuestIdShareable(questID)` |
  | `AQL:SelectQuestLogEntry(logIndex)` | `AQL:SelectQuestLogEntryById(questID)` |
  | `AQL:SetQuestLogSelection(logIndex)` | `AQL:SelectAndShowQuestLogEntryById(questID)` |
  | `AQL:ExpandQuestLogHeader(logIndex)` | `AQL:ExpandQuestLogZoneByName(zoneName)` |
  | `AQL:CollapseQuestLogHeader(logIndex)` | `AQL:CollapseQuestLogZoneByName(zoneName)` |

  ```

  > **Note:** Read the current Thin Wrappers table carefully before editing. The exact rows may differ slightly from the list above — match on the section header `#### Thin Wrappers` and the first table row to identify the right block. Replace only this section; stop before `#### Compound — ByIndex`.

---

- [ ] **Step 2: Update Compound ByIndex section**

  In the `#### Compound — ByIndex` table, find the row for `GetSelectedQuestId()`:
  ```
  | `AQL:GetSelectedQuestId()` | questID or nil | nil if nothing selected or header selected |
  ```

  Replace with:
  ```
  | `AQL:GetSelectedQuestLogEntryId()` | questID or nil | nil if nothing selected or header selected. **Replaces deprecated `GetSelectedQuestId()`** |
  ```

---

- [ ] **Step 3: Update Compound ById section**

  Find the note above the Compound ById table (the "If questID is not in the active quest log..." paragraph) and add a **Preferred** callout. Find:
  ```
  If questID is not in the active quest log, all ById methods are silent no-ops (false / nothing). A normal-level debug message is emitted.
  ```

  Replace with:
  ```
  **Preferred for most consumers.** Use ById methods when you have a questID — questID is stable across WoW version families; logIndex is not.

  If questID is not in the active quest log, all ById methods are silent no-ops (false / nothing). A normal-level debug message is emitted.
  ```

  Then add `SelectQuestLogEntryById` to the ById table. Find the first row:
  ```
  | `AQL:IsQuestIdShareable(questID)` | bool | Resolves logIndex; delegates to `IsQuestIndexShareable` |
  ```

  Replace with:
  ```
  | `AQL:IsQuestIdShareable(questID)` | bool | Resolves logIndex; delegates to `IsQuestIndexShareable` |
  | `AQL:SelectQuestLogEntryById(questID)` | — | Selects without display refresh; no-op + debug if not in log |
  ```

  Also add `GetSelectedQuestId()` to the deprecated list in the Thin Wrappers — Deprecated table (Step 1 above already excludes it from that table; it should instead appear as a note on the `GetSelectedQuestLogEntryId` row added in Step 2, which it already does).

---

- [ ] **Step 4: Add Version 2.5.4 entry to CLAUDE.md Version History**

  Find `### Version 2.5.3 (March 2026)` and insert above it:

  ```markdown
  ### Version 2.5.4 (March 2026)
  - Feature: `AQL:GetSelectedQuestLogEntryId()` added — questID-based, unambiguously named replacement for deprecated `GetSelectedQuestId()`.
  - Feature: `AQL:SelectQuestLogEntryById(questID)` added — select without display refresh; questID-based replacement for deprecated `SelectQuestLogEntry(logIndex)`.
  - Deprecation: `GetQuestLogSelection`, `GetSelectedQuestId`, `IsQuestLogShareable`, `SelectQuestLogEntry`, `SetQuestLogSelection`, `ExpandQuestLogHeader`, `CollapseQuestLogHeader` marked `@deprecated`. All continue to function; replacements listed in each doc comment and in README.md. Will be removed in a future major version.
  - Docs: README.md rewritten as complete consumer-facing reference with API docs, callback reference, data structures, Quick Start examples, and deprecation migration table. Version support updated to reflect Classic Era, TBC, MoP, and Retail (in development).
  - Docs: CLAUDE.md Group 2 thin wrappers split into Preferred and Deprecated sub-sections. ById section marked as preferred for most consumers.

  ```

---

- [ ] **Step 5: Verify CLAUDE.md changes**

  Read the Group 2 section. Confirm:
  - `#### Thin Wrappers — Preferred` has exactly 5 rows (ShowQuestLog, HideQuestLog, IsQuestLogShown, GetQuestDifficultyColor, GetQuestLogIndex)
  - `#### Thin Wrappers — Deprecated` has 6 rows with the ⚠️ warning note
  - `GetSelectedQuestLogEntryId` is in the ByIndex table (not `GetSelectedQuestId`)
  - `SelectQuestLogEntryById` is in the ById table
  - `GetSelectedQuestId()` does NOT appear in the preferred thin wrappers table
  - Version 2.5.4 entry appears above 2.5.3

---

- [ ] **Step 6: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add CLAUDE.md && git commit -m "docs: restructure CLAUDE.md Group 2 — Preferred/Deprecated thin wrappers; add 2.5.4 entry"
  ```

---

## Task 4: README.md — Complete rewrite

**Files:**
- Modify: `README.md`

Read the current `README.md` first (it is a short stub), then replace the entire content with what follows.

---

- [ ] **Step 1: Read current README.md**

  Read `README.md`. The current content is a short stub (~6 lines). Confirm the file exists and note the current content so you know you're replacing it entirely.

---

- [ ] **Step 2: Write the full README.md**

  Replace the entire file content with:

  ````markdown
  # AbsoluteQuestLog-1.0

  A version-agnostic WoW addon library that provides a clean, stable API for quest data and quest log events. AbsoluteQuestLog (AQL) abstracts away the differences between WoW client versions and gives your addon a single consistent interface that works across Classic Era, TBC Classic, Mists of Pandaria Classic, and Retail — without you having to branch for each one.

  **Supported WoW versions:**

  | Version Family | Interface | Status |
  |---|---|---|
  | Classic Era | 1.14.x (11508) | ✅ Supported |
  | TBC Classic | 2.5.x (20505) | ✅ Supported |
  | Mists of Pandaria Classic | 5.4.x (50503) | ✅ Supported |
  | Retail (The War Within) | 11.x (120001) | 🚧 In development |

  ---

  ## Installation

  Declare AQL as a dependency in your addon's `.toc` file:

  ```
  ## Dependencies: AbsoluteQuestLog
  ```

  Then get the library handle at the top of your Lua file:

  ```lua
  local AQL = LibStub("AbsoluteQuestLog-1.0")
  ```

  ---

  ## Quick Start

  ### React to quest events

  ```lua
  local AQL = LibStub("AbsoluteQuestLog-1.0")

  -- Fire when the player accepts a new quest
  AQL:RegisterCallback(AQL.Event.QuestAccepted, function(questInfo)
      print("New quest accepted: " .. questInfo.title)
  end)

  -- Fire when a quest objective progresses
  AQL:RegisterCallback(AQL.Event.ObjectiveProgressed, function(questInfo, objInfo, delta)
      print(questInfo.title .. ": " .. objInfo.text .. " (+" .. delta .. ")")
  end)
  ```

  ### Fetch quest data

  ```lua
  local AQL = LibStub("AbsoluteQuestLog-1.0")

  -- Get data for a specific quest
  local questInfo = AQL:GetQuest(questID)
  if questInfo then
      print(questInfo.title .. " — Level " .. questInfo.level)
      print("Zone: " .. (questInfo.zone or "Unknown"))
      print("Complete: " .. tostring(questInfo.isComplete))
  end

  -- Iterate all quests in the player's log
  for questID, questInfo in pairs(AQL:GetAllQuests()) do
      print(questID, questInfo.title)
  end
  ```

  ### Check quest history

  ```lua
  if AQL:HasCompletedQuest(questID) then
      print("Already done this one.")
  end
  ```

  ---

  ## API Reference

  All methods are called on the library handle: `AQL:MethodName(...)`.

  ### Group 1: Quest APIs

  > All Group 1 methods take `questID` as their primary identifier. questID is stable across all WoW version families and does not change between quest log updates.

  #### Quest State

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:GetQuest(questID)` | QuestInfo or nil | Returns cached quest data. nil if quest is not in the player's log. |
  | `AQL:GetAllQuests()` | `{[questID]=QuestInfo}` | Returns the full quest cache snapshot. |
  | `AQL:GetQuestsByZone(zone)` | `{[questID]=QuestInfo}` | Returns all quests in the given zone. |
  | `AQL:IsQuestActive(questID)` | bool | True if quest is in the player's active log. |
  | `AQL:IsQuestFinished(questID)` | bool | True if all objectives are complete but the quest has not been turned in. |
  | `AQL:GetQuestType(questID)` | string or nil | One of: `"normal"`, `"elite"`, `"dungeon"`, `"raid"`, `"daily"`, `"pvp"`, `"escort"`. Requires a quest DB provider (Questie or QuestWeaver). |

  #### Quest History

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:HasCompletedQuest(questID)` | bool | True if this character has ever completed the quest. |
  | `AQL:GetCompletedQuests()` | `{[questID]=true}` | All quests completed by this character this session. |
  | `AQL:GetCompletedQuestCount()` | number | Count of completed quests. |

  #### Quest Resolution

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:GetQuestInfo(questID)` | QuestInfo or nil | Three-tier resolution: cache → WoW log scan → provider DB. Always returns at minimum `{questID, title}` if the quest can be found anywhere. |
  | `AQL:GetQuestTitle(questID)` | string or nil | Returns the quest title. Delegates to `GetQuestInfo`. |
  | `AQL:GetQuestLink(questID)` | hyperlink or nil | Returns a chat-linkable hyperlink for the quest. |

  #### Objectives

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:GetObjectives(questID)` | array or nil | Returns the objectives array from the cache. |
  | `AQL:GetObjective(questID, index)` | table or nil | Returns a single objective by 1-based index. |
  | `AQL:GetQuestObjectives(questID)` | array | Cache first; falls back to WoW API. Returns `{}` if no objectives found. |
  | `AQL:IsQuestObjectiveText(msg)` | bool | True if `msg` matches any active quest objective text. Useful for suppressing duplicate `UI_INFO_MESSAGE` notifications. |

  #### Chain Info

  Requires Questie or QuestWeaver to be installed. Returns `{knownStatus="unknown"}` otherwise.

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:GetChainInfo(questID)` | ChainInfo | Full chain data. See [ChainInfo](#chaininfo) below. |
  | `AQL:GetChainStep(questID)` | number or nil | 1-based position of this quest in its chain. |
  | `AQL:GetChainLength(questID)` | number or nil | Total number of quests in the chain. |

  #### Requirements

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:GetQuestRequirements(questID)` | table or nil | Eligibility requirements: `requiredLevel`, `requiredMaxLevel`, `requiredRaces`, `requiredClasses`, `preQuestGroup`, `preQuestSingle`, `exclusiveTo`, `nextQuestInChain`, `breadcrumbForQuestId`. Bitmask fields with value 0 are normalized to nil. Returns nil when NullProvider is active. |

  #### Quest Tracking

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:TrackQuest(questID)` | bool | Adds quest to the watch list. Returns false if the watch cap is already reached. |
  | `AQL:UntrackQuest(questID)` | — | Removes quest from the watch list. |
  | `AQL:IsUnitOnQuest(questID, unit)` | bool or nil | True if the given unit has this quest. Returns nil on TBC (API unavailable). |

  #### Player & Level

  Level filters use `questInfo.level` (recommended difficulty level). Strict comparisons for Below/Above; inclusive for Between.

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:GetPlayerLevel()` | number | Player's current character level. |
  | `AQL:GetQuestsInQuestLogBelowLevel(level)` | `{[questID]=QuestInfo}` | Quests with `questInfo.level < level`. |
  | `AQL:GetQuestsInQuestLogAboveLevel(level)` | `{[questID]=QuestInfo}` | Quests with `questInfo.level > level`. |
  | `AQL:GetQuestsInQuestLogBetweenLevels(min, max)` | `{[questID]=QuestInfo}` | Quests with `min <= questInfo.level <= max`. Returns `{}` if min > max. |
  | `AQL:GetQuestsInQuestLogBelowLevelDelta(delta)` | `{[questID]=QuestInfo}` | Quests below `playerLevel - delta`. |
  | `AQL:GetQuestsInQuestLogAboveLevelDelta(delta)` | `{[questID]=QuestInfo}` | Quests above `playerLevel + delta`. |
  | `AQL:GetQuestsInQuestLogWithinLevelRange(delta)` | `{[questID]=QuestInfo}` | Quests between `playerLevel - delta` and `playerLevel + delta`. |

  ---

  ### Group 2: Quest Log Frame APIs

  Methods that interact with the WoW quest log frame UI.

  > **ById methods are preferred.** questID is stable across WoW version families; logIndex is a positional cursor that changes on every quest log update.

  #### Frame Control

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:ShowQuestLog()` | — | Opens the quest log frame. |
  | `AQL:HideQuestLog()` | — | Closes the quest log frame. |
  | `AQL:IsQuestLogShown()` | bool | True if the quest log frame is currently visible. |
  | `AQL:GetQuestDifficultyColor(level)` | `{r,g,b}` | Returns the difficulty color for a quest of the given level relative to the player. |
  | `AQL:GetQuestLogIndex(questID)` | logIndex or nil | Resolves questID to its current logIndex. Returns nil if the quest is not in the log or is under a collapsed zone header. |

  #### Compound — ById *(Preferred)*

  If questID is not in the active quest log, all ById methods are silent no-ops (return false or nothing). A debug message is emitted when debug mode is on.

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:GetSelectedQuestLogEntryId()` | questID or nil | Returns the questID of the currently selected quest log entry. nil if nothing selected or a zone header is selected. |
  | `AQL:IsQuestIdShareable(questID)` | bool | True if the quest can be shared with party members. |
  | `AQL:SelectQuestLogEntryById(questID)` | — | Selects the quest log entry without refreshing the display. Use `SelectAndShowQuestLogEntryById` to also refresh. |
  | `AQL:SelectAndShowQuestLogEntryById(questID)` | — | Selects the quest log entry and refreshes the display. |
  | `AQL:OpenQuestLogById(questID)` | — | Opens the quest log and navigates to this quest. |
  | `AQL:ToggleQuestLogById(questID)` | — | Toggles the quest log open/closed for this quest. |

  #### Compound — ByIndex

  Use these when you already have a logIndex (e.g., from iterating `GetQuestLogEntries()`).

  | Method | Returns | Description |
  |---|---|---|
  | `AQL:GetQuestLogEntries()` | array | All visible entries in display order: `{logIndex, isHeader, title, questID, isCollapsed}`. questID is nil for header rows. |
  | `AQL:GetQuestLogZones()` | array of `{name, isCollapsed}` | Zone header entries. Useful for save/restore of collapsed state. |
  | `AQL:IsQuestIndexShareable(logIndex)` | bool | True if the quest at logIndex can be shared. Saves/restores selection. |
  | `AQL:SelectAndShowQuestLogEntryByIndex(logIndex)` | — | Selects and refreshes the display. |
  | `AQL:OpenQuestLogByIndex(logIndex)` | — | Opens the quest log and navigates to logIndex. |
  | `AQL:ToggleQuestLogByIndex(logIndex)` | — | Toggles the quest log open/closed for logIndex. |
  | `AQL:ExpandAllQuestLogHeaders()` | — | Expands all collapsed zone headers. |
  | `AQL:CollapseAllQuestLogHeaders()` | — | Collapses all zone headers. |
  | `AQL:ExpandQuestLogZoneByName(zoneName)` | — | Expands the named zone header. No-op if not found. |
  | `AQL:CollapseQuestLogZoneByName(zoneName)` | — | Collapses the named zone header. No-op if not found. |
  | `AQL:ToggleQuestLogZoneByName(zoneName)` | — | Toggles the named zone header. No-op if not found. |
  | `AQL:IsQuestLogZoneCollapsed(zoneName)` | bool or nil | True if the zone header is collapsed. nil if not found. |

  #### ⚠️ Deprecated Methods

  The following methods expose `logIndex` or implicit selection state directly. They continue to function but **will be removed in a future major version**. Migrate to the alternatives shown.

  | Deprecated | Use instead |
  |---|---|
  | `AQL:GetQuestLogSelection()` | `AQL:GetSelectedQuestLogEntryId()` |
  | `AQL:GetSelectedQuestId()` | `AQL:GetSelectedQuestLogEntryId()` |
  | `AQL:IsQuestLogShareable()` | `AQL:IsQuestIdShareable(questID)` |
  | `AQL:SelectQuestLogEntry(logIndex)` | `AQL:SelectQuestLogEntryById(questID)` |
  | `AQL:SetQuestLogSelection(logIndex)` | `AQL:SelectAndShowQuestLogEntryById(questID)` |
  | `AQL:ExpandQuestLogHeader(logIndex)` | `AQL:ExpandQuestLogZoneByName(zoneName)` |
  | `AQL:CollapseQuestLogHeader(logIndex)` | `AQL:CollapseQuestLogZoneByName(zoneName)` |

  ---

  ## Callbacks

  Register for events using:

  ```lua
  AQL:RegisterCallback(AQL.Event.QuestAccepted, handlerFunction, optionalTarget)
  AQL:UnregisterCallback(AQL.Event.QuestAccepted, handlerFunction)
  ```

  Always use the `AQL.Event` constants — do not use raw strings directly.

  | Constant | Arguments | Fired When |
  |---|---|---|
  | `AQL.Event.QuestAccepted` | `(questInfo)` | Quest newly appears in the player's log (not fired on first login rebuild). |
  | `AQL.Event.QuestAbandoned` | `(questInfo)` | Quest removed from log without completing or failing. |
  | `AQL.Event.QuestCompleted` | `(questInfo)` | Quest turned in successfully (`IsQuestFlaggedCompleted` is true). |
  | `AQL.Event.QuestFinished` | `(questInfo)` | All objectives met; quest not yet turned in (`isComplete` → true). |
  | `AQL.Event.QuestFailed` | `(questInfo)` | Quest failed (timer expired or escort NPC died). |
  | `AQL.Event.QuestTracked` | `(questInfo)` | Quest added to the watch list (`isTracked` → true). |
  | `AQL.Event.QuestUntracked` | `(questInfo)` | Quest removed from the watch list (`isTracked` → false). |
  | `AQL.Event.ObjectiveProgressed` | `(questInfo, objInfo, delta)` | Objective `numFulfilled` increased. `delta` is the increase amount. |
  | `AQL.Event.ObjectiveCompleted` | `(questInfo, objInfo)` | Objective reached `numRequired`. |
  | `AQL.Event.ObjectiveRegressed` | `(questInfo, objInfo, delta)` | Objective `numFulfilled` decreased. Suppressed during quest turn-in. |
  | `AQL.Event.ObjectiveFailed` | `(questInfo, objInfo)` | Objective failed alongside a failed quest. |
  | `AQL.Event.UnitQuestLogChanged` | `(unit)` | `UNIT_QUEST_LOG_CHANGED` fired for a non-player unit (e.g., party member). |

  ---

  ## Data Structures

  ### QuestInfo

  Returned by `GetQuest`, `GetAllQuests`, `GetQuestsByZone`, and callback arguments.

  ```lua
  {
      questID        = N,
      title          = "string",
      level          = N,               -- Recommended difficulty level
      suggestedGroup = N,               -- 0 if not a group quest
      zone           = "string",        -- Zone header from quest log (nil for non-cached quests)
      type           = "string" or nil, -- "normal"|"elite"|"dungeon"|"raid"|"daily"|"pvp"|"escort"
      faction        = "string" or nil, -- "Alliance"|"Horde"|nil
      isComplete     = bool,            -- true = objectives met, not yet turned in
      isFailed       = bool,
      failReason     = "string" or nil, -- "timeout"|"escort_died"
      isTracked      = bool,
      link           = "string",        -- Chat hyperlink
      logIndex       = N,               -- Position in quest log at snapshot time
      snapshotTime   = N,               -- GetTime() when this entry was built
      timerSeconds   = N or nil,        -- nil if quest has no timer
      objectives     = {
          {
              index        = N,
              text         = "string",  -- Full text e.g. "Tainted Ooze killed: 4/10"
              name         = "string",  -- Text with count suffix stripped
              type         = "string",
              numFulfilled = N,
              numRequired  = N,
              isFinished   = bool,
              isFailed     = bool,
          },
          -- ...
      },
      chainInfo = ChainInfo,
  }
  ```

  `GetQuestInfo` (three-tier resolution) returns at minimum `{questID, title}` for quests not in the active log.

  ### ChainInfo

  Returned by `GetChainInfo`. Requires Questie or QuestWeaver.

  ```lua
  -- When chain data is known:
  {
      knownStatus = "known",
      chainID     = N,        -- questID of the first quest in the chain
      step        = N,        -- 1-based position of this quest
      length      = N,        -- Total quests in the chain
      steps       = {
          {
              questID = N,
              title   = "string",
              status  = "completed"|"active"|"finished"|"failed"|"available"|"unavailable"|"unknown",
          },
          -- ...
      },
      provider = "Questie"|"QuestWeaver"|"none",
  }

  -- When the quest is not part of a chain:
  { knownStatus = "not_a_chain" }

  -- When no provider is available:
  { knownStatus = "unknown" }
  ```

  Use `AQL.ChainStatus.Known`, `AQL.ChainStatus.NotAChain`, and `AQL.ChainStatus.Unknown` constants instead of raw strings.

  ---

  ## Debug Mode

  ```
  /aql debug on       -- Key events: quest accept/complete/fail/abandon, provider selection
  /aql debug verbose  -- Everything: cache rebuilds, diffs, all event firings
  /aql debug off      -- Silent (default)
  ```

  Debug messages are prefixed `[AQL]` in gold.
  ````

---

- [ ] **Step 3: Verify README.md**

  Read the full `README.md`. Confirm:
  - Version support table has 4 rows (Classic Era, TBC, MoP, Retail in development)
  - Quick Start has 3 code examples
  - All 7 deprecated methods appear in the `⚠️ Deprecated Methods` table
  - Callbacks table has exactly 12 rows
  - Both QuestInfo and ChainInfo data structures are present
  - `GetSelectedQuestLogEntryId` appears in the ById Preferred table (not `GetSelectedQuestId`)

---

- [ ] **Step 4: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add README.md && git commit -m "docs: rewrite README as complete consumer-facing API reference"
  ```

---

## Task 5: Version bump and changelog

**Files:**
- Modify: `AbsoluteQuestLog.toc`, `AbsoluteQuestLog_Classic.toc`, `AbsoluteQuestLog_TBC.toc`, `AbsoluteQuestLog_Mists.toc`, `AbsoluteQuestLog_Mainline.toc`
- Modify: `changelog.txt`

---

- [ ] **Step 1: Bump all five toc files**

  In each file, change `## Version: 2.5.3` to `## Version: 2.5.4`.

  Edit all five:
  - `AbsoluteQuestLog.toc`
  - `AbsoluteQuestLog_Classic.toc`
  - `AbsoluteQuestLog_TBC.toc`
  - `AbsoluteQuestLog_Mists.toc`
  - `AbsoluteQuestLog_Mainline.toc`

---

- [ ] **Step 2: Verify version bump**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep "Version:" AbsoluteQuestLog*.toc
  ```
  Expected: all five show `## Version: 2.5.4`

---

- [ ] **Step 3: Add 2.5.4 entry to changelog.txt**

  Find `Version 2.5.3 (March 2026)` at the top of `changelog.txt` and insert above it:

  ```
  Version 2.5.4 (March 2026)
  ---------------------------
  - Feature: AQL:GetSelectedQuestLogEntryId() added — questID-based, unambiguously
    named replacement for deprecated GetSelectedQuestId(). Identical behavior.
  - Feature: AQL:SelectQuestLogEntryById(questID) added — selects quest log entry
    without display refresh; questID-based replacement for deprecated
    SelectQuestLogEntry(logIndex).
  - Deprecation: GetQuestLogSelection, GetSelectedQuestId, IsQuestLogShareable,
    SelectQuestLogEntry, SetQuestLogSelection, ExpandQuestLogHeader,
    CollapseQuestLogHeader marked @deprecated. All continue to function.
    See README.md for migration guide. Will be removed in a future major version.
  - Docs: README.md rewritten as complete consumer-facing API reference with Quick
    Start examples, full method tables, callback reference, QuestInfo/ChainInfo
    data structures, and deprecation migration table. Version support updated to
    reflect Classic Era, TBC, MoP, and Retail (in development).
  - Docs: CLAUDE.md Group 2 thin wrappers split into Preferred and Deprecated
    sub-sections. ById methods marked as preferred for most consumers.

  ```

---

- [ ] **Step 4: Verify changelog**

  Read the top of `changelog.txt`. Confirm `Version 2.5.4` is the first entry and `Version 2.5.3` follows.

---

- [ ] **Step 5: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && git add AbsoluteQuestLog.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Mainline.toc changelog.txt && git commit -m "chore: bump version to 2.5.4 — questID API audit and README"
  ```

---

## Final Verification

After all five tasks complete:

- [ ] **Check @deprecated count**
  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -c "@deprecated" AbsoluteQuestLog.lua
  ```
  Expected: 7

- [ ] **Check new methods exist**
  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep -n "function AQL:GetSelectedQuestLogEntryId\|function AQL:SelectQuestLogEntryById" AbsoluteQuestLog.lua
  ```
  Expected: 2 results

- [ ] **Check version**
  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log" && grep "Version:" AbsoluteQuestLog*.toc
  ```
  Expected: all five show `2.5.4`
