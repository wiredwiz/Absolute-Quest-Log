# AQL Retail Support — Design Spec

**Date:** 2026-03-29
**Repo:** Absolute-Quest-Log
**Version:** 2.5.4 → 2.5.5

---

## Goal

Make AQL fully functional on Retail (Interface 120001). Two independent concerns are addressed together:

1. **Core functional gaps** — several WowQuestAPI wrappers return nil or break on Retail because they call legacy globals that were moved to `C_QuestLog.*` in Patch 9.0.1. Fix these by adding IS_RETAIL branches inside WowQuestAPI.lua.

2. **Quest Log Frame APIs** — `QuestLogFrame` was removed in 6.0.2 (integrated into World Map). All Group 2 frame methods redirect to World Map equivalents on Retail rather than silently failing.

No behavioral changes on Classic Era, TBC, or MoP.

---

## Approach

All version-specific code lives in `Core/WowQuestAPI.lua` — the existing architectural rule. Consumer files (`QuestCache.lua`, `AbsoluteQuestLog.lua`, `HistoryCache.lua`) do not gain IS_RETAIL checks; they call WowQuestAPI wrappers that handle version branching internally.

---

## Files Modified

| File | Change |
|---|---|
| `Core/WowQuestAPI.lua` | New `GetQuestLogInfo` normalization wrapper; IS_RETAIL branches on 14 existing functions; new `GetSelectedQuestLogEntryId` wrapper |
| `Core/QuestCache.lua` | Switch from `GetQuestLogTitle` → `GetQuestLogInfo`; field access updated from positional to table |
| `AbsoluteQuestLog.lua` | `GetSelectedQuestLogEntryId` body replaced with `WowQuestAPI.GetSelectedQuestLogEntryId()` delegate |
| `AbsoluteQuestLog.toc` + four version tocs | Version bump 2.5.4 → 2.5.5 |
| `changelog.txt` | Add 2.5.5 entry |
| `CLAUDE.md` | Add Version 2.5.5 entry |

---

## Section 1: WowQuestAPI.lua — Core Functional Gaps

### 1a. `GetQuestLogInfo(logIndex)` — new normalization wrapper

`QuestCache` currently reads positional return values from `GetQuestLogTitle(logIndex)`. On Retail, `C_QuestLog.GetInfo(logIndex)` returns a table instead. A new `WowQuestAPI.GetQuestLogInfo(logIndex)` normalizes both into a consistent table on all versions:

```lua
-- Returns: { title, level, suggestedGroup, isHeader, isCollapsed, isComplete, questID }
-- On Classic/TBC/MoP: reads positional returns from GetQuestLogTitle(logIndex)
-- On Retail: reads fields from C_QuestLog.GetInfo(logIndex)
-- Returns nil if logIndex is out of range or the entry does not exist.
function WowQuestAPI.GetQuestLogInfo(logIndex)
    if IS_RETAIL then
        local info = C_QuestLog.GetInfo(logIndex)
        if not info then return nil end
        return {
            title         = info.title,
            level         = info.level,
            suggestedGroup = info.suggestedGroup,
            isHeader      = info.isHeader,
            isCollapsed   = info.isCollapsed,
            isComplete    = info.isComplete,
            questID       = info.questID,
        }
    else
        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, _, questID =
            GetQuestLogTitle(logIndex)
        if not title then return nil end
        return {
            title         = title,
            level         = level,
            suggestedGroup = suggestedGroup,
            isHeader      = isHeader,
            isCollapsed   = isCollapsed,
            isComplete    = isComplete,
            questID       = questID,
        }
    end
end
```

`QuestCache:Rebuild()` switches from calling `WowQuestAPI.GetQuestLogTitle` to `WowQuestAPI.GetQuestLogInfo` and reads fields by name from the returned table.

### 1b. `GetQuestsCompleted()` Retail branch

`C_QuestLog.GetAllCompletedQuestIDs()` returns a sequential array `{questID1, questID2, ...}`. The wrapper converts it to the associative hash map `{[questID]=true}` that `HistoryCache` expects — enabling O(1) lookup. No changes needed in `HistoryCache`.

```lua
function WowQuestAPI.GetQuestsCompleted()
    if IS_RETAIL then
        local ids = C_QuestLog.GetAllCompletedQuestIDs()
        if not ids then return nil end
        local result = {}
        for _, questID in ipairs(ids) do
            result[questID] = true
        end
        return result
    end
    return GetQuestsCompleted()
end
```

### 1c. Quest tracking Retail branches

`TrackQuest` and `UntrackQuest` currently resolve questID → logIndex → `AddQuestWatch(logIndex)`. On Retail, skip the logIndex step entirely:

```lua
-- TrackQuest (inside WowQuestAPI)
if IS_RETAIL then
    C_QuestLog.AddQuestWatch(questID)
else
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if logIndex then AddQuestWatch(logIndex) end
end

-- UntrackQuest
if IS_RETAIL then
    C_QuestLog.RemoveQuestWatch(questID)
else
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if logIndex then RemoveQuestWatch(logIndex) end
end
```

`IsQuestWatchedById(questID)` on Retail calls `C_QuestLog.IsQuestWatched(questID)` directly.

`IsQuestWatchedByIndex(logIndex)` on Retail: resolve logIndex → questID via `GetQuestLogInfo(logIndex)`, then call `C_QuestLog.IsQuestWatched(questID)`.

### 1d. `MAX_WATCHABLE_QUESTS` and `GetNumQuestWatches` fallbacks

`GetMaxWatchableQuests()` reads the FrameXML constant `MAX_WATCHABLE_QUESTS`. Its Retail value is unverified at compile time. Add a nil-guard fallback:

```lua
function WowQuestAPI.GetMaxWatchableQuests()
    return MAX_WATCHABLE_QUESTS or 25
end
```

`GetWatchedQuestCount()` calls the global `GetNumQuestWatches()`. This global's availability on Retail is unverified. Add a nil-guard:

```lua
function WowQuestAPI.GetWatchedQuestCount()
    if GetNumQuestWatches then return GetNumQuestWatches() end
    return 0
end
```

If `GetNumQuestWatches` is absent on Retail, `TrackQuest` will always see count 0 and never block on the cap — a safe degradation.

### 1e. `GetSelectedQuestLogEntryId()` — new WowQuestAPI wrapper

On Retail, `C_QuestLog.GetSelectedQuest()` returns the selected questID directly — no logIndex resolution needed. On Classic/TBC/MoP, the existing two-step resolution applies. Move this logic into WowQuestAPI:

```lua
function WowQuestAPI.GetSelectedQuestLogEntryId()
    if IS_RETAIL then
        local questID = C_QuestLog.GetSelectedQuest()
        return (questID and questID ~= 0) and questID or nil
    end
    -- Classic/TBC/MoP: resolve via logIndex
    local logIndex = WowQuestAPI.GetQuestLogSelection()
    if not logIndex or logIndex == 0 then return nil end
    local info = WowQuestAPI.GetQuestLogInfo(logIndex)
    if not info or info.isHeader or not info.questID then return nil end
    return info.questID
end
```

`AQL:GetSelectedQuestLogEntryId()` in `AbsoluteQuestLog.lua` is simplified to:

```lua
function AQL:GetSelectedQuestLogEntryId()
    return WowQuestAPI.GetSelectedQuestLogEntryId()
end
```

The existing debug messages (which reference logIndex) are removed — they no longer apply on Retail, and the function body is now a single delegation. Debug output for selection queries is the responsibility of WowQuestAPI if needed.

### 1f. `GetQuestLinkById(questID)` Retail branch

`C_QuestLog.GetQuestLink(questID)` replaces the legacy `GetQuestLink(logIndex)` on Retail:

```lua
function WowQuestAPI.GetQuestLinkById(questID)
    if IS_RETAIL then
        return C_QuestLog.GetQuestLink(questID)
    end
    local logIndex = WowQuestAPI.GetQuestLogIndex(questID)
    if not logIndex then return nil end
    return GetQuestLink(logIndex)
end
```

---

## Section 2: Quest Log Frame APIs on Retail

### Show / Hide / IsShown

```lua
function WowQuestAPI.ShowQuestLog()
    if IS_RETAIL then WorldMapFrame:Show() else ShowUIPanel(QuestLogFrame) end
end

function WowQuestAPI.HideQuestLog()
    if IS_RETAIL then WorldMapFrame:Hide() else HideUIPanel(QuestLogFrame) end
end

function WowQuestAPI.IsQuestLogShown()
    if IS_RETAIL then return WorldMapFrame:IsVisible() end
    return QuestLogFrame:IsVisible()
end
```

### Selection

`QuestLog_SetSelection(logIndex)` and `SelectQuestLogEntry(logIndex)` both map to `C_QuestLog.SetSelectedQuest(questID)` on Retail. The logIndex is resolved to questID via `GetQuestLogInfo(logIndex)`.

`QuestLog_Update()` is a no-op on Retail (the quest log auto-updates when selection changes).

```lua
function WowQuestAPI.QuestLog_SetSelection(logIndex)
    if IS_RETAIL then
        local info = WowQuestAPI.GetQuestLogInfo(logIndex)
        if info and info.questID then
            C_QuestLog.SetSelectedQuest(info.questID)
        end
        return
    end
    QuestLog_SetSelection(logIndex)
    QuestLog_Update()
end

function WowQuestAPI.SelectQuestLogEntry(logIndex)
    if IS_RETAIL then
        local info = WowQuestAPI.GetQuestLogInfo(logIndex)
        if info and info.questID then
            C_QuestLog.SetSelectedQuest(info.questID)
        end
        return
    end
    SelectQuestLogEntry(logIndex)
end

function WowQuestAPI.QuestLog_Update()
    if IS_RETAIL then return end
    QuestLog_Update()
end
```

### Open to quest (ById / ByIndex)

`OpenQuestLogByIndex` and `OpenQuestLogById` in `AbsoluteQuestLog.lua` currently call `SetQuestLogSelection` then `ShowQuestLog`. On Retail this naturally becomes: `C_QuestLog.SetSelectedQuest(questID)` + `WorldMapFrame:Show()` — which is exactly what the WowQuestAPI wrappers above do. No changes needed in `AbsoluteQuestLog.lua` for these methods.

### Shareability

`GetQuestLogPushable()` is selection-dependent and has no direct questID equivalent on Retail. The wrapper resolves the selected questID first:

```lua
function WowQuestAPI.GetQuestLogPushable()
    if IS_RETAIL then
        local questID = WowQuestAPI.GetSelectedQuestLogEntryId()
        if not questID then return false end
        return C_QuestLog.IsPushableQuest(questID) and true or false
    end
    return GetQuestLogPushable() and true or false
end
```

### Collapse/Expand headers

`ExpandQuestHeader(logIndex)` and `CollapseQuestHeader(logIndex)` exist unchanged on Retail. No IS_RETAIL branch needed.

---

## Section 3: QuestCache.lua

### Switch to `GetQuestLogInfo`

`QuestCache:Rebuild()` Phase 2 currently:

```lua
local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, _, questID =
    WowQuestAPI.GetQuestLogTitle(i)
if not title then break end
```

Replace with:

```lua
local info = WowQuestAPI.GetQuestLogInfo(i)
if not info then
    -- skip this entry; do not break — a nil mid-log entry should not
    -- cut off all subsequent quests from the cache rebuild
else
    local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, questID =
        info.title, info.level, info.suggestedGroup, info.isHeader,
        info.isCollapsed, info.isComplete, info.questID
    -- ... existing downstream processing unchanged ...
end
```

> **Note on loop termination:** The original code used `if not title then break end` because `GetQuestLogTitle` returning nil reliably means "past the end of the log." `GetQuestLogInfo` returns nil for any out-of-range index, so the existing `for i = 1, numEntries` upper bound (from `GetNumQuestLogEntries()`) controls loop termination. The `if not info then` branch skips malformed entries without breaking early. The implementer should read the full Rebuild() loop to confirm this matches the existing control flow.

**Phase 1 and Phase 4 of QuestCache:Rebuild()** (collect collapsed headers / re-collapse them) also call `WowQuestAPI.GetQuestLogTitle`. These phases are intentionally **not** migrated to `GetQuestLogInfo` — `GetQuestLogTitle` still exists as a deprecated wrapper on Retail and these phases only need `isHeader` and `isCollapsed` which the existing wrapper returns correctly. Migrating them would be scope creep.

`IsQuestWatchedByIndex(logIndex)` in QuestCache currently calls `WowQuestAPI.IsQuestWatchedByIndex(logIndex)`. WowQuestAPI gains an IS_RETAIL branch for this (Section 1c above) — no change needed in QuestCache itself.

---

## Key Constraints

- **No behavioral changes on Classic Era, TBC, or MoP.** Every IS_RETAIL branch is guarded by `IS_RETAIL` — all other version families fall through to the existing code path.
- **`GetQuestLogTitle` wrapper stays.** It is used by existing deprecated public API methods (`GetQuestLogSelection`, `IsQuestIndexShareable`, etc.) that still resolve via logIndex on all non-Retail versions. It is not removed or modified.
- **Chain info remains `knownStatus="unknown"` on Retail.** BtwQuestsProvider is a separate sub-project. No provider selection changes in this sub-project.
- **`AQL:GetSelectedQuestLogEntryId()` debug messages removed.** The body becomes a single delegation to `WowQuestAPI.GetSelectedQuestLogEntryId()`; the verbose debug messages in the old body no longer apply at the public API layer. If debug output is needed for selection queries, it belongs in WowQuestAPI.

---

## Testing

No automated test framework. Verification is by reading file content (grep) and runtime testing on each WoW version family:

- Classic Era / TBC / MoP: all existing behavior unchanged — verify by grep that no IS_RETAIL branch touches non-Retail paths
- Retail: manual smoke test — quest accept/complete callbacks fire, `HasCompletedQuest` returns true for completed quests, `TrackQuest` / `UntrackQuest` toggle watch list, `ShowQuestLog` opens World Map, `OpenQuestLogById` opens World Map to correct quest
