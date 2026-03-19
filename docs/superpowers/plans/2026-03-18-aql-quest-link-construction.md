# AQL Quest Link Construction — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure every QuestCache entry always has a valid WoW quest hyperlink, and `AQL:GetQuestLink` works for any questID regardless of whether it is in the player's active log.

**Architecture:** Two small, independent edits. `_buildEntry` in `QuestCache.lua` gains a fallback that constructs the standard `|Hquest:...|h` hyperlink when `GetQuestLink(logIndex)` returns nil. `AQL:GetQuestLink` in `AbsoluteQuestLog.lua` is upgraded from a cache-only lookup to a three-tier resolution that can build the link from provider data for quests not in the active log.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary (Interface 20505), LibStub. No automated test framework — verification is manual, in-game and via `/script` commands.

---

## Chunk 1: Both changes

### Task 1: `_buildEntry` link fallback

**Files:**
- Modify: `Core/QuestCache.lua` — `_buildEntry`, after line 140

**Background:** `GetQuestLink(logIndex)` calls the WoW global of the same name. In some builds of TBC Classic 20505 it returns nil. The fix adds a manual construction of the standard quest hyperlink using `questID`, `info.level`, and `info.title`, all of which are always in scope and non-nil at this point in `_buildEntry`. The WoW quest hyperlink format is `|cFFFFD200|Hquest:<questID>:<questLevel>|h[<title>]|h|r`.

**Current state (lines 139–140):**
```lua
    -- Quest link.
    local link = GetQuestLink(logIndex)
```

- [ ] **Step 1: Apply the edit**

  Find:
  ```lua
      -- Quest link.
      local link = GetQuestLink(logIndex)
  ```

  Replace with:
  ```lua
      -- Quest link: prefer the WoW native API; construct manually if it returns nil
      -- so every QuestCache entry has a valid hyperlink regardless of client version.
      local link = GetQuestLink(logIndex)
      if not link then
          link = string.format("|cFFFFD200|Hquest:%d:%d|h[%s]|h|r",
              questID, info.level or 0, info.title or ("Quest " .. questID))
      end
  ```

- [ ] **Step 2: Verify the edit**

  Read back `Core/QuestCache.lua` lines 135–150 and confirm:
  - `local link = GetQuestLink(logIndex)` is still present (unchanged)
  - The `if not link then ... end` block follows immediately
  - `info.level` (not bare `level`) is used in the fallback format string
  - `info.title` (not bare `title`) is used in the fallback format string

- [ ] **Step 3: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
  git add Core/QuestCache.lua
  git commit -m "feat: always populate quest link in _buildEntry with fallback construction

  GetQuestLink(logIndex) returns nil in some TBC Classic 20505 builds. Fall
  back to manually constructing the standard |Hquest:id:level|h hyperlink
  from questID, level, and title — all of which are always in scope here.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 2: `GetQuestLink` three-tier upgrade

**Files:**
- Modify: `AbsoluteQuestLog.lua` — `AQL:GetQuestLink`, lines 79–82

**Background:** The current implementation (lines 79–82) is a one-liner that reads from the live cache. It returns nil for any quest not currently in the player's log. The upgrade adds a Tier 2+3 path: call `self:GetQuestInfo(questID)` (which already chains cache → WoW log scan → provider) and construct the link from the returned `title` and `level`. This enables callers like `SocialQuestAnnounce:TestChatLink()` to get a valid link for arbitrary questIDs (e.g. quest 337) using only provider database data.

**Current state (lines 79–82):**
```lua
function AQL:GetQuestLink(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.link or nil
end
```

- [ ] **Step 1: Apply the edit**

  Find:
  ```lua
  function AQL:GetQuestLink(questID)
      local q = self.QuestCache and self.QuestCache:Get(questID)
      return q and q.link or nil
  end
  ```

  Replace with:
  ```lua
  function AQL:GetQuestLink(questID)
      -- Tier 1: live cache (always non-nil for active quests; see _buildEntry fallback).
      local q = self.QuestCache and self.QuestCache:Get(questID)
      if q and q.link then return q.link end

      -- Tier 2+3: quest not in active log — resolve via GetQuestInfo (which itself
      -- chains: QuestCache → WoW log scan → provider). The QuestCache check above
      -- already handled Tier 1, so in practice GetQuestInfo will reach Tier 2 or 3.
      -- If the provider returns chain-only data with no title, info.title will be nil
      -- and we return nil — a link cannot be constructed without a title.
      local info = self:GetQuestInfo(questID)
      if not info or not info.title then return nil end
      return string.format("|cFFFFD200|Hquest:%d:%d|h[%s]|h|r",
          questID, info.level or 0, info.title)
  end
  ```

- [ ] **Step 2: Verify the edit**

  Read back `AbsoluteQuestLog.lua` lines 79–95 and confirm:
  - Tier 1: `if q and q.link then return q.link end` (not `return q and q.link or nil`)
  - Tier 2+3: `self:GetQuestInfo(questID)` is called, result checked for nil title
  - `string.format` with the correct hyperlink format string follows the nil guard

- [ ] **Step 3: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
  git add AbsoluteQuestLog.lua
  git commit -m "feat: upgrade GetQuestLink to three-tier resolution

  Previously cache-only; now falls back to GetQuestInfo (which chains
  cache → WoW log scan → provider) to construct the hyperlink for quests
  not currently in the active log. Returns nil only when no title is
  available from any source.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

## In-Game Verification

Load the updated addon in WoW TBC Classic (Interface 20505).

**Test 1 — Active quest link always non-nil:**
Open your quest log and note any questID. Run:
```
/script local AQL = LibStub("AbsoluteQuestLog-1.0"); local q = AQL:GetQuest(<questID>); print(tostring(q and q.link))
```
Expected: a non-nil gold hyperlink string (not `nil`).

**Test 2 — GetQuestLink for active quest:**
```
/script local AQL = LibStub("AbsoluteQuestLog-1.0"); print(tostring(AQL:GetQuestLink(<questID>)))
```
Expected: same hyperlink string.

**Test 3 — GetQuestLink for quest not in log (requires Questie or QuestWeaver):**
```
/script local AQL = LibStub("AbsoluteQuestLog-1.0"); print(tostring(AQL:GetQuestLink(337)))
```
Expected: a non-nil hyperlink string if the provider database has quest 337. May be `nil` if no provider is installed or quest 337 is unknown to the provider.

**Test 4 — Chat announcements use clickable links (requires SocialQuest and being in a party):**
Accept or complete a quest while in a party with SocialQuest transmission enabled. Confirm the chat message shows a gold bracketed quest name that is ctrl-clickable (shows the quest tooltip on ctrl-click).
