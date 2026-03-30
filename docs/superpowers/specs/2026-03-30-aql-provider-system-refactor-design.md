# AQL Provider System Refactor — Design Spec

**Date:** 2026-03-30
**Status:** Approved
**Scope:** Phase 1 of 2 — restructure the provider system for multi-provider capability routing and always-on notifications. New providers (GrailProvider, BtWQuestsProvider) are Phase 2 and out of scope here.

---

## Problem

The current provider system selects a single addon (Questie → QuestWeaver → Null) and routes all four provider method calls through it. This prevents:

- Using Grail for metadata/requirements on clients where Questie is absent
- Using BtWQuests for chain data on Retail alongside Grail for metadata
- Giving players actionable feedback when a provider's API is broken or no suitable provider is installed

---

## Goals

1. Support multiple simultaneously-active providers, each covering a different data capability
2. Each provider declares which capabilities it covers
3. Priority-ordered selection per capability, centrally defined in EventEngine
4. Always-on (never debug-gated) warnings when a provider is structurally broken or no provider is found for a capability
5. Update existing providers (Questie, QuestWeaver, Null) to conform to the new interface
6. No behavioral changes on any WoW version family for players with a working provider installed

---

## Capability Buckets

Three capability constants added to `AQL.Capability` (alongside existing enums in `AbsoluteQuestLog.lua`):

```lua
AQL.Capability = {
    Chain        = "Chain",        -- GetChainInfo
    QuestInfo    = "QuestInfo",    -- GetQuestBasicInfo, GetQuestType, GetQuestFaction
    Requirements = "Requirements", -- GetQuestRequirements
}
```

Method-to-capability routing:

| Method | Capability |
|---|---|
| `GetChainInfo` | `Chain` |
| `GetQuestBasicInfo` | `QuestInfo` |
| `GetQuestType` | `QuestInfo` |
| `GetQuestFaction` | `QuestInfo` |
| `GetQuestRequirements` | `Requirements` |

---

## Provider Interface (updated)

Every provider must implement or declare:

```lua
Provider.addonName    = "AddonName"        -- string; used in notification messages
Provider.capabilities = { ... }            -- array of AQL.Capability values this provider covers

Provider:IsAvailable()   -- bool: addon is loaded and initialized (existing)
Provider:Validate()      -- bool, errMsg: API structure is intact (new)
Provider:GetChainInfo(questID)
Provider:GetQuestBasicInfo(questID)
Provider:GetQuestType(questID)
Provider:GetQuestFaction(questID)
Provider:GetQuestRequirements(questID)
```

`IsAvailable()` and `Validate()` are called in sequence during provider selection:
- `IsAvailable()` false → skip silently (addon not installed)
- `IsAvailable()` true, `Validate()` false → skip and fire broken-provider notification (once)
- Both true → use this provider for its declared capabilities

`GetQuestBasicInfo` remains optional (checked with `if provider.GetQuestBasicInfo then`).

---

## EventEngine Changes

### Provider storage

`AQL.provider` (single reference) is replaced by `AQL.providers` — a table keyed by capability:

```lua
AQL.providers = {
    [AQL.Capability.Chain]        = nil,
    [AQL.Capability.QuestInfo]    = nil,
    [AQL.Capability.Requirements] = nil,
}
```

Each slot holds the active provider for that capability, or `nil` if unresolved.

### Priority table

Defined at the top of `EventEngine.lua`. First available and valid provider per capability wins:

```lua
local PROVIDER_PRIORITY = {
    [AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider },
    [AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.GrailProvider },
    [AQL.Capability.Requirements] = { AQL.QuestieProvider, AQL.GrailProvider, AQL.QuestWeaverProvider },
}
```

New providers register themselves here when implemented. Note: `AQL.BtWQuestsProvider` and `AQL.GrailProvider` are nil until Phase 2 — `selectProviders()` nil-checks each entry.

### Provider selection

`selectProvider()` becomes `selectProviders()`. For each capability, iterates its priority list:

```lua
local function selectProviders()
    for capability, candidates in pairs(PROVIDER_PRIORITY) do
        for _, provider in ipairs(candidates) do
            if provider and provider:IsAvailable() then
                local ok, err = provider:Validate()
                if ok then
                    AQL.providers[capability] = provider
                    break
                else
                    notifyBroken(provider, err)
                end
            end
        end
    end
end
```

### Deferred upgrade

`tryUpgradeProvider()` becomes `tryUpgradeProviders()`. Re-runs per-capability selection for any bucket where `AQL.providers[capability]` is still `nil`.

**Important:** During the deferred upgrade retry window, `Validate()` returning false is treated the same as `IsAvailable()` returning false — retry next cycle, no notification. The broken-provider notification only fires on the **final attempt** when `IsAvailable()` is true but `Validate()` is still false. This handles Questie's normal async-init case (`QuestPointers == nil` for ~3 s) without spuriously warning the user.

After the upgrade window closes, fires missing-provider notifications for still-unresolved buckets.

### Consumer call sites

All references to `AQL.provider:Method(...)` update to route through the capability:

```lua
-- Before
local provider = AQL.provider
if provider then
    local ok, result = pcall(provider.GetChainInfo, provider, questID)
    ...
end

-- After
local chainProvider = AQL.providers[AQL.Capability.Chain]
if chainProvider then
    local ok, result = pcall(chainProvider.GetChainInfo, chainProvider, questID)
    ...
end
```

The existing `pcall` guards remain on all call sites.

---

## Notification System

Two always-on message types. Neither is gated by `AQL.debug`. Both use `AQL.WARN` (orange) to distinguish from normal output and debug messages.

### Broken provider

Fires once per provider when `IsAvailable()` is true but `Validate()` fails. Tracked in a module-local `notifiedBroken` set keyed by `provider.addonName`:

```
[AQL] WARNING: BtWQuestsProvider could not be loaded — BtWQuests may have changed its API.
      Quest chain data will be unavailable. (Update or disable BtWQuests to resolve.)
```

### No provider found

Fires once per capability after the deferred upgrade window closes with that bucket still `nil`. Tracked in a module-local `notifiedMissing` set keyed by capability. The addon list is built dynamically from `PROVIDER_PRIORITY[capability]` — each entry's `addonName` joined with `/`:

```
[AQL] WARNING: No quest chain provider found. Install one of: Questie, QuestWeaver, BtWQuests.
[AQL] WARNING: No quest info provider found. Install one of: Questie, QuestWeaver, Grail.
[AQL] WARNING: No requirements provider found. Install one of: Questie, QuestWeaver, Grail.
```

Only fires if the capability is genuinely unresolved — no message if a working provider is found.

---

## Updated Existing Providers

### QuestieProvider

```lua
QuestieProvider.addonName    = "Questie"
QuestieProvider.capabilities = { AQL.Capability.Chain, AQL.Capability.QuestInfo, AQL.Capability.Requirements }

function QuestieProvider:Validate()
    if type(QuestieLoader) ~= "table" then return false, "QuestieLoader missing" end
    if type(QuestieLoader.ImportModule) ~= "function" then return false, "ImportModule missing" end
    local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if not ok or not db then return false, "QuestieDB unavailable" end
    if type(db.GetQuest) ~= "function" then return false, "GetQuest missing" end
    if db.QuestPointers == nil then return false, "QuestPointers nil (not yet initialized)" end
    return true
end
```

Note: `Validate()` returning false due to `QuestPointers == nil` during the deferred upgrade window is the normal async-init case — the broken-provider notification is suppressed until the final retry attempt. See EventEngine deferred upgrade section.

### QuestWeaverProvider

```lua
QuestWeaverProvider.addonName    = "QuestWeaver"
QuestWeaverProvider.capabilities = { AQL.Capability.Chain, AQL.Capability.QuestInfo }
-- Requirements excluded: QuestWeaver only exposes min_level, not the full requirements contract

function QuestWeaverProvider:Validate()
    local qw = _G["QuestWeaver"]
    if type(qw) ~= "table" then return false, "QuestWeaver global missing" end
    if type(qw.Quests) ~= "table" then return false, "QuestWeaver.Quests missing" end
    -- Spot-check: verify at least one quest entry has expected shape
    local sample = next(qw.Quests)
    if sample == nil then return false, "QuestWeaver.Quests is empty" end
    return true
end
```

### NullProvider

```lua
NullProvider.addonName    = "none"
NullProvider.capabilities = {}

function NullProvider:Validate()
    return true  -- always valid; covers nothing
end
```

NullProvider is never in `PROVIDER_PRIORITY` — it is not a selectable provider. It remains the default return value of `GetChainInfo` for callers that check `AQL.providers[capability]` and find nil. Actually: with nil-per-capability replacing NullProvider, callers just nil-check the provider slot. NullProvider is retained only for backward compatibility if any consumer holds a reference to `AQL.provider`.

---

## Backward Compatibility

`AQL.provider` is kept as a read-only shim for any external consumers that may reference it:

```lua
AQL.provider = AQL.providers[AQL.Capability.Chain] or AQL.NullProvider
```

Updated after each `selectProviders()` / `tryUpgradeProviders()` call. Always returns a callable provider (never nil). Will be removed in a future major version.

---

## Out of Scope (Phase 2)

- `GrailProvider` implementation
- `BtWQuestsProvider` implementation
- Any changes to `WowQuestAPI.lua`
- Any changes to `QuestCache.lua` beyond the provider call site routing update

---

## Files Changed

| File | Change |
|---|---|
| `AbsoluteQuestLog.lua` | Add `AQL.Capability` enum; add `AQL.WARN` color constant; add `AQL.providers` table; keep `AQL.provider` shim |
| `Core/EventEngine.lua` | `PROVIDER_PRIORITY` table; `selectProviders()`; `tryUpgradeProviders()`; notification logic (`notifiedBroken`, `notifiedMissing`); update all `AQL.provider` call sites to route via capability |
| `Core/QuestCache.lua` | Update `_buildEntry` provider call sites to use `AQL.providers[capability]` |
| `Providers/Provider.lua` | Updated interface contract: `addonName`, `capabilities`, `Validate()` |
| `Providers/QuestieProvider.lua` | Add `addonName`, `capabilities`, `Validate()` |
| `Providers/QuestWeaverProvider.lua` | Add `addonName`, `capabilities`, `Validate()` |
| `Providers/NullProvider.lua` | Add `addonName`, `capabilities`, `Validate()` |
