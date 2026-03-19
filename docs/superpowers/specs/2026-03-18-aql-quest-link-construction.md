# AQL Quest Link Construction — Design Spec

**Goal:** Ensure `AQL:GetQuestLink(questID)` always returns a valid WoW quest hyperlink string, whether or not the quest is currently in the player's quest log.

**Problem:** `GetQuestLink(logIndex)` (WoW global) returns nil in some versions of TBC Classic 20505, causing `info.link` in QuestCache entries to be nil. As a result, outbound SocialQuest chat announcements fall back to plain title text instead of generating clickable quest hyperlinks.

**Solution:** Two complementary fixes:

1. **`_buildEntry` fallback** — after calling `GetQuestLink(logIndex)`, if the result is nil, construct the standard WoW hyperlink manually from the questID, level, and title that are already available in the same function. This guarantees every entry in `QuestCache.data` has a non-nil `link` field.

2. **`GetQuestLink` three-tier upgrade** — extend the public `AQL:GetQuestLink(questID)` API to work for quests *not* in the active log. Tier 1: return `q.link` from cache (always non-nil after fix 1). Tier 2+3: call `self:GetQuestInfo(questID)` (which already does provider + WoW-log fallback) and construct the hyperlink from the returned title and level. Returns nil only if no data source has any information about the questID.

**WoW quest hyperlink format** (standard, natively clickable in TBC 20505 chat):
```
|cFFFFD200|Hquest:<questID>:<questLevel>|h[<title>]|h|r
```

---

## Files

- Modify: `Core/QuestCache.lua` — `_buildEntry`, line 140
- Modify: `AbsoluteQuestLog.lua` — `GetQuestLink`, lines 79–82

---

## Detailed Behaviour

### `_buildEntry` (QuestCache.lua)

Current (line 140):
```lua
    -- Quest link.
    local link = GetQuestLink(logIndex)
```

After fix — `link` is always non-nil for any quest successfully built by `_buildEntry`:
```lua
    -- Quest link: prefer the WoW native API; construct manually if it returns nil
    -- so every QuestCache entry has a valid hyperlink regardless of client version.
    local link = GetQuestLink(logIndex)
    if not link then
        link = string.format("|cFFFFD200|Hquest:%d:%d|h[%s]|h|r",
            questID, info.level or 0, info.title or ("Quest " .. questID))
    end
```

The `questID`, `level` (from `info.level`), and `info.title` are all in scope at this point and always non-nil for a valid quest log entry.

### `AQL:GetQuestLink` (AbsoluteQuestLog.lua)

Current (lines 79–82) — cache-only:
```lua
function AQL:GetQuestLink(questID)
    local q = self.QuestCache and self.QuestCache:Get(questID)
    return q and q.link or nil
end
```

After fix — three-tier, works for any questID with known data:
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

Returns nil only when all tiers yield no title (unknown questID with no provider data).

---

## Consumer Impact

**SocialQuest `Core/Announcements.lua`** (no code change required): the `display` variable already uses `info.link` from `AQL:GetQuest(questID)`. After this fix, `info.link` is always non-nil for active quests, so outbound chat announcements automatically use clickable hyperlinks.

**SocialQuest debug test button** (future work): calls `SocialQuest.AQL:GetQuestLink(337)` — works even if quest 337 is not in the player's log, as long as the provider (Questie or QuestWeaver) has quest 337 in its database.

---

## In-Game Verification

1. Accept a quest while in a party with chat announcements enabled. Confirm the outbound chat message shows a gold bracketed quest name that is ctrl-clickable.
2. Turn in a quest while in a party. Confirm the completion message contains a clickable quest link.
3. Type `/script print(LibStub("AbsoluteQuestLog-1.0"):GetQuestLink(337))` in chat. Confirm a non-nil hyperlink string is printed (requires Questie or QuestWeaver installed with quest 337 in database).
4. While quest 337 is not in the active log, the above slash command should still return a link via the provider tier.
