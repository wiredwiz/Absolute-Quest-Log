# AQL Provider System Refactor — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-provider selection model in AQL with a per-capability multi-provider routing system, adding always-on broken-provider and missing-provider notifications.

**Architecture:** Three capability buckets (`Chain`, `QuestInfo`, `Requirements`) each get their own provider slot in `AQL.providers`, selected from a priority-ordered candidate list. Providers declare `addonName`, `capabilities`, and a new `Validate()` method. The existing `AQL.provider` shim is preserved for backward compatibility. Notifications use `AQL.WARN` (orange) and a sound to surface broken or absent providers regardless of debug mode.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary (Interface 20505), LibStub, no automated test infrastructure — verify manually in-game after each task via `/reload` and `/aql debug on`.

---

## File Structure

| File | What Changes |
|---|---|
| `AbsoluteQuestLog.lua` | Add `AQL.WARN`, `AQL.Capability`, `AQL.providers`; update `GetQuestInfo()` Tier 2/3 call sites to route through capability slots |
| `Providers/Provider.lua` | Update interface contract docs: add `addonName`, `capabilities`, `Validate()` |
| `Providers/NullProvider.lua` | Add `addonName`, `capabilities`, `IsAvailable()`, `Validate()` |
| `Providers/QuestieProvider.lua` | Add `addonName`, `capabilities`, `Validate()`; simplify `IsAvailable()` to presence-only check |
| `Providers/QuestWeaverProvider.lua` | Add `addonName`, `capabilities`, `Validate()`; simplify `IsAvailable()` to presence-only check |
| `Core/EventEngine.lua` | Replace `selectProvider()` + `tryUpgradeProvider()` with multi-capability equivalents; add `CAPABILITY_LABEL`, lazy `getProviderPriority()`, `notifiedBroken`/`notifiedMissing` sets, `notifyBroken()`/`notifyMissing()`, `selectProviders()`, `tryUpgradeProviders()`; update PLAYER_LOGIN handler and inline upgrade check |
| `Core/QuestCache.lua` | Update `_buildEntry` to route Chain calls through `AQL.providers[Chain]` and QuestInfo calls through `AQL.providers[QuestInfo]` |
| `AbsoluteQuestLog.toc` (×5) | Version bump to 2.6.0 |
| `CLAUDE.md` | Add version history entry |
| `changelog.txt` | Add version entry |

No new files are created.

**Load order note:** Per the TOC, `Core/EventEngine.lua` loads *before* `Providers/*.lua`. This means `AQL.QuestieProvider` etc. are `nil` at EventEngine load time. The provider priority table must be initialized lazily (on first call from `selectProviders()`), not as a module-level table literal.

---

## Chunk 1: Foundation (Tasks 1–2)

---

### Task 1: Add `AQL.WARN`, `AQL.Capability`, and `AQL.providers` to `AbsoluteQuestLog.lua`

**Files:**
- Modify: `AbsoluteQuestLog.lua`

- [ ] **Step 1: Add `AQL.WARN` color constant after the existing `AQL.DBG` line (line 18)**

  The current block is:
  ```lua
  AQL.RED   = "|cffff0000"
  AQL.RESET = "|r"
  AQL.DBG   = "|cFFFFD200"   -- gold (colorblind-safe, distinct from errors and chat text)
  ```

  Change it to:
  ```lua
  AQL.RED   = "|cffff0000"
  AQL.RESET = "|r"
  AQL.DBG   = "|cFFFFD200"   -- gold (colorblind-safe, distinct from errors and chat text)
  AQL.WARN  = "|cffff8c00"   -- orange; always-on provider warnings (never debug-gated)
  ```

- [ ] **Step 2: Update the sub-module slots comment (lines 23–27) to mention `AQL.providers`**

  Change:
  ```lua
  -- AQL.provider     set by Core/EventEngine.lua at PLAYER_LOGIN
  ```

  To:
  ```lua
  -- AQL.provider     backward-compat shim; always AQL.providers[AQL.Capability.Chain] or NullProvider
  -- AQL.providers    active provider per AQL.Capability.*; set by Core/EventEngine.lua at PLAYER_LOGIN
  ```

- [ ] **Step 3: Add `AQL.Capability` enum and `AQL.providers` table after `AQL.FailReason` (after line 75)**

  After the closing `}` of `AQL.FailReason`, insert:
  ```lua
  -- Capability buckets for the multi-provider routing system.
  -- Each capability is served independently by the highest-priority available+valid provider.
  -- Phase 2 will add GrailProvider (QuestInfo, Requirements) and BtWQuestsProvider (Chain).
  AQL.Capability = {
      Chain        = "Chain",        -- GetChainInfo
      QuestInfo    = "QuestInfo",    -- GetQuestBasicInfo, GetQuestType, GetQuestFaction
      Requirements = "Requirements", -- GetQuestRequirements
  }

  -- Active provider per capability. Set by Core/EventEngine.lua at PLAYER_LOGIN.
  -- Each slot is nil until provider selection runs.
  -- AQL.provider (singular) is kept as a backward-compatibility shim for external
  -- consumers; it always equals AQL.providers[AQL.Capability.Chain] or AQL.NullProvider.
  AQL.providers = AQL.providers or {
      [AQL.Capability.Chain]        = nil,
      [AQL.Capability.QuestInfo]    = nil,
      [AQL.Capability.Requirements] = nil,
  }
  ```

- [ ] **Step 4: Update `GetQuestInfo()` Tier 2 augmentation to route via capability (around line 270)**

  The current Tier 2 block reads:
  ```lua
          if not result.zone then
              local provider = self.provider
              if provider then
                  if provider.GetQuestBasicInfo then
                      local ok, basicInfo = pcall(provider.GetQuestBasicInfo, provider, questID)
                      if ok and basicInfo then
                          result.zone          = result.zone          or basicInfo.zone
                          result.level         = result.level         or basicInfo.questLevel
                          result.requiredLevel = result.requiredLevel or basicInfo.requiredLevel
                          result.title         = result.title         or basicInfo.title
                      end
                  end
                  if provider.GetChainInfo then
                      local ok, ci = pcall(provider.GetChainInfo, provider, questID)
                      if ok and ci then
                          result.chainInfo = result.chainInfo or ci
                      end
                  end
              end
          end
  ```

  Replace with:
  ```lua
          if not result.zone then
              local infoProvider  = self.providers and self.providers[AQL.Capability.QuestInfo]
              local chainProvider = self.providers and self.providers[AQL.Capability.Chain]
              if infoProvider and infoProvider.GetQuestBasicInfo then
                  local ok, basicInfo = pcall(infoProvider.GetQuestBasicInfo, infoProvider, questID)
                  if ok and basicInfo then
                      result.zone          = result.zone          or basicInfo.zone
                      result.level         = result.level         or basicInfo.questLevel
                      result.requiredLevel = result.requiredLevel or basicInfo.requiredLevel
                      result.title         = result.title         or basicInfo.title
                  end
              end
              if chainProvider then
                  local ok, ci = pcall(chainProvider.GetChainInfo, chainProvider, questID)
                  if ok and ci then
                      result.chainInfo = result.chainInfo or ci
                  end
              end
          end
  ```

- [ ] **Step 5: Update `GetQuestInfo()` Tier 3 to route via capability (around line 293)**

  The current Tier 3 block reads:
  ```lua
      -- Tier 3: provider (Questie / QuestWeaver).
      local provider = self.provider
      if not provider then return nil end

      local basicInfo
      if provider.GetQuestBasicInfo then
          local ok, info = pcall(provider.GetQuestBasicInfo, provider, questID)
          if ok and info then basicInfo = info end
      end

      local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
      if provider.GetChainInfo then
          local ok, ci = pcall(provider.GetChainInfo, provider, questID)
          if ok and ci then chainInfo = ci end
      end

      if not basicInfo and chainInfo.knownStatus == AQL.ChainStatus.Unknown then return nil end
  ```

  Replace with:
  ```lua
      -- Tier 3: provider (Questie / QuestWeaver).
      local infoProvider  = self.providers and self.providers[AQL.Capability.QuestInfo]
      local chainProvider = self.providers and self.providers[AQL.Capability.Chain]

      local basicInfo
      if infoProvider and infoProvider.GetQuestBasicInfo then
          local ok, info = pcall(infoProvider.GetQuestBasicInfo, infoProvider, questID)
          if ok and info then basicInfo = info end
      end

      local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
      if chainProvider then
          local ok, ci = pcall(chainProvider.GetChainInfo, chainProvider, questID)
          if ok and ci then chainInfo = ci end
      end

      if not basicInfo and chainInfo.knownStatus == AQL.ChainStatus.Unknown then return nil end
  ```

- [ ] **Step 6: Commit**
  ```bash
  git add "AbsoluteQuestLog.lua"
  git commit -m "refactor: add AQL.Capability, AQL.WARN, AQL.providers; route GetQuestInfo via capability slots"
  ```

---

### Task 2: Add `addonName`, `capabilities`, `Validate()` to all four provider files

**Files:**
- Modify: `Providers/Provider.lua`
- Modify: `Providers/NullProvider.lua`
- Modify: `Providers/QuestieProvider.lua`
- Modify: `Providers/QuestWeaverProvider.lua`

- [ ] **Step 1: Update `Providers/Provider.lua` interface contract docs**

  Replace the entire file content with:
  ```lua
  -- Providers/Provider.lua
  -- Documents the interface every AQL provider must implement.
  -- This file contains no runtime code; it is documentation only.
  --
  -- Every provider must declare:
  --
  --   Provider.addonName    = "AddonName"   -- string; used in notification messages
  --   Provider.capabilities = { ... }       -- array of AQL.Capability.* values this provider covers
  --
  -- Every provider must implement:
  --
  --   Provider:IsAvailable()  → bool
  --     Lightweight presence check: addon global is loaded.
  --     false → skip silently (addon not installed); no notification.
  --     true  → proceed to Validate().
  --
  --   Provider:Validate()  → bool, errMsg
  --     Structural check: API shape is intact and data is initialized.
  --     Called only after IsAvailable() returns true.
  --     true        → use this provider for its declared capabilities.
  --     false, msg  → skip; fire broken-provider notification once per addonName.
  --     Note: during the deferred upgrade retry window, false is treated as
  --     IsAvailable() false — silent retry, no notification.
  --
  --   Provider:GetChainInfo(questID)
  --     Returns a ChainInfo table (never nil).
  --     ChainInfo fields when knownStatus = "known":
  --       knownStatus = "known" | "not_a_chain" | "unknown"
  --       chainID     = questID of first quest in chain
  --       step        = this quest's 1-based position
  --       length      = total quests in chain
  --       steps       = array of { questID, title, status }
  --       provider    = "Questie" | "QuestWeaver" | "none"
  --     When knownStatus = "unknown":     only knownStatus present.
  --     When knownStatus = "not_a_chain": only knownStatus present.
  --
  --   Provider:GetQuestType(questID)
  --     Returns "normal"|"elite"|"dungeon"|"raid"|"daily"|"pvp"|"escort" or nil.
  --
  --   Provider:GetQuestFaction(questID)
  --     Returns "Alliance", "Horde", or nil (nil = available to both factions).
  --
  --   Provider:GetQuestRequirements(questID)
  --     Returns a requirements table or nil.
  --     Shape:
  --       {
  --         requiredLevel        = N or nil,
  --         requiredMaxLevel     = N or nil,
  --         requiredRaces        = N or nil,   -- bitmask; nil = no restriction
  --         requiredClasses      = N or nil,   -- bitmask; nil = no restriction
  --         preQuestGroup        = { questID, ... } or nil,  -- ALL must be complete
  --         preQuestSingle       = { questID, ... } or nil,  -- ANY ONE must be complete
  --         exclusiveTo          = { questID, ... } or nil,
  --         nextQuestInChain     = questID or nil,
  --         breadcrumbForQuestId = questID or nil,
  --       }
  --     Bitmask fields with value 0 are normalised to nil.
  --     Returns nil when the provider has no data, or the method is not implemented.
  --
  --   Provider:GetQuestBasicInfo(questID)   [optional — checked with `if provider.GetQuestBasicInfo then`]
  --     Returns { title, questLevel, requiredLevel, zone } or nil.
  --
  -- All provider calls in EventEngine and QuestCache are wrapped in pcall.
  -- A provider that errors does not crash the library.
  ```

- [ ] **Step 2: Update `Providers/NullProvider.lua`**

  Replace the entire file with:
  ```lua
  -- Providers/NullProvider.lua
  -- Fallback provider used when neither Questie nor QuestWeaver is present.
  -- Always returns knownStatus = "unknown" for chain queries.
  -- NullProvider is never in the PROVIDER_PRIORITY table — it is not selectable.
  -- It exists as the value of the AQL.provider backward-compatibility shim when
  -- no Chain provider is active.

  local AQL = LibStub("AbsoluteQuestLog-1.0", true)
  if not AQL then return end

  local NullProvider = {}

  NullProvider.addonName    = "none"
  NullProvider.capabilities = {}   -- covers no capabilities

  function NullProvider:IsAvailable()
      return false   -- NullProvider is never selected; always reports unavailable
  end

  function NullProvider:Validate()
      return true    -- structurally valid; covers no capabilities
  end

  function NullProvider:GetChainInfo(questID)
      return { knownStatus = AQL.ChainStatus.Unknown }
  end

  function NullProvider:GetQuestType(questID)
      return nil
  end

  function NullProvider:GetQuestFaction(questID)
      return nil
  end

  function NullProvider:GetQuestRequirements(questID)
      return nil
  end

  AQL.NullProvider = NullProvider
  ```

- [ ] **Step 3: Update `Providers/QuestieProvider.lua` — add fields and split `IsAvailable()` / `Validate()`**

  After the `local TAG_DUNGEON = 81` line and before `local function getDB()`, insert:
  ```lua
  QuestieProvider.addonName    = "Questie"
  QuestieProvider.capabilities = {
      AQL.Capability.Chain,
      AQL.Capability.QuestInfo,
      AQL.Capability.Requirements,
  }
  ```

  Replace the existing `QuestieProvider:IsAvailable()` function (lines ~37–39):
  ```lua
  -- IsAvailable: Questie global loader is present and exposes ImportModule.
  -- Validate() handles the deeper structural and initialization checks.
  function QuestieProvider:IsAvailable()
      return type(QuestieLoader) == "table"
          and type(QuestieLoader.ImportModule) == "function"
  end
  ```

  Add `Validate()` immediately after `IsAvailable()`:
  ```lua
  function QuestieProvider:Validate()
      if type(QuestieLoader) ~= "table" then return false, "QuestieLoader missing" end
      if type(QuestieLoader.ImportModule) ~= "function" then return false, "ImportModule missing" end
      local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
      if not ok or not db then return false, "QuestieDB unavailable" end
      if type(db.GetQuest) ~= "function" then return false, "GetQuest missing" end
      -- QuestPointers is nil during Questie's async init (~3 s after PLAYER_LOGIN).
      -- This causes Validate() to return false during the deferred upgrade retry window,
      -- which is treated as a silent retry (no notification). Once Questie finishes
      -- initializing, Validate() returns true and the provider is selected.
      if db.QuestPointers == nil then return false, "QuestPointers nil (not yet initialized)" end
      return true
  end
  ```

- [ ] **Step 4: Update `Providers/QuestWeaverProvider.lua` — add fields and split `IsAvailable()` / `Validate()`**

  After the `local QuestWeaverProvider = {}` line, insert:
  ```lua
  QuestWeaverProvider.addonName    = "QuestWeaver"
  QuestWeaverProvider.capabilities = {
      AQL.Capability.Chain,
      AQL.Capability.QuestInfo,
      -- Requirements excluded: QuestWeaver only exposes min_level, not the full requirements contract.
  }
  ```

  Replace the existing `QuestWeaverProvider:IsAvailable()` function:
  ```lua
  -- IsAvailable: QuestWeaver global table is present.
  -- Validate() handles the structural readiness check.
  function QuestWeaverProvider:IsAvailable()
      return type(_G["QuestWeaver"]) == "table"
  end
  ```

  Add `Validate()` immediately after `IsAvailable()`:
  ```lua
  function QuestWeaverProvider:Validate()
      local qw = _G["QuestWeaver"]
      if type(qw) ~= "table" then return false, "QuestWeaver global missing" end
      if type(qw.Quests) ~= "table" then return false, "QuestWeaver.Quests missing" end
      local sample = next(qw.Quests)
      if sample == nil then return false, "QuestWeaver.Quests is empty" end
      return true
  end
  ```

- [ ] **Step 5: Verify in-game**

  `/reload` in WoW. With Questie installed, `/aql debug on` should show provider selection messages. With no provider installed, nothing breaks (NullProvider behavior unchanged).

- [ ] **Step 6: Commit**
  ```bash
  git add "Providers/Provider.lua" "Providers/NullProvider.lua" "Providers/QuestieProvider.lua" "Providers/QuestWeaverProvider.lua"
  git commit -m "refactor: add addonName/capabilities/Validate() to all providers; split IsAvailable from Validate"
  ```

---

## Chunk 2: EventEngine, Call Sites, Version Bump (Tasks 3–5)

---

### Task 3: Rewrite `Core/EventEngine.lua` provider selection

**Files:**
- Modify: `Core/EventEngine.lua`

This task replaces `selectProvider()` (lines 65–88) and `tryUpgradeProvider()` (lines 90–119) entirely, and adds the new infrastructure above them.

- [ ] **Step 1: Replace the provider selection block (lines 65–119) with the full new implementation**

  Delete everything from `------------------------------------------------------------------------` / `-- Provider selection` through the closing `end` of `tryUpgradeProvider`. Replace with:

  ```lua
  ------------------------------------------------------------------------
  -- Provider selection
  ------------------------------------------------------------------------

  -- Human-readable labels for capability buckets used in notification messages.
  local CAPABILITY_LABEL = {
      [AQL.Capability.Chain]        = "quest chain",
      [AQL.Capability.QuestInfo]    = "quest info",
      [AQL.Capability.Requirements] = "requirements",
  }

  -- Priority-ordered provider candidates per capability.
  -- Built lazily: Providers/ load *after* EventEngine.lua in the TOC, so
  -- AQL.QuestieProvider etc. are nil at EventEngine load time.
  -- getProviderPriority() is first called from selectProviders() inside
  -- PLAYER_LOGIN, by which point all provider globals are populated.
  local _PROVIDER_PRIORITY = nil
  local function getProviderPriority()
      if not _PROVIDER_PRIORITY then
          _PROVIDER_PRIORITY = {
              [AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider },
              [AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider },
              [AQL.Capability.Requirements] = { AQL.QuestieProvider },
          }
      end
      return _PROVIDER_PRIORITY
  end

  -- Tracks which providers/capabilities have already received a warning this session.
  -- Keyed by provider.addonName (notifiedBroken) or AQL.Capability.* (notifiedMissing).
  local notifiedBroken  = {}
  local notifiedMissing = {}

  -- Fires once per provider.addonName when IsAvailable=true but Validate=false.
  -- Always-on: never gated by AQL.debug.
  local function notifyBroken(provider, err)
      if notifiedBroken[provider.addonName] then return end
      notifiedBroken[provider.addonName] = true
      DEFAULT_CHAT_FRAME:AddMessage(AQL.WARN ..
          "[AQL] WARNING: " .. provider.addonName .. "Provider could not be loaded — " ..
          provider.addonName .. " may have changed its API.\n" ..
          "      Quest data will be unavailable. (Update or disable " ..
          provider.addonName .. " to resolve.)" .. AQL.RESET)
      PlaySound(SOUNDKIT and SOUNDKIT.LEVEL_UP or "LEVELUP")
  end

  -- Fires once per capability when the deferred upgrade window closes with no provider found.
  -- Always-on: never gated by AQL.debug.
  local function notifyMissing(capability)
      if notifiedMissing[capability] then return end
      notifiedMissing[capability] = true
      local label = CAPABILITY_LABEL[capability] or capability:lower()
      local names = {}
      for _, p in ipairs(getProviderPriority()[capability] or {}) do
          if p and p.addonName then table.insert(names, p.addonName) end
      end
      local addonList = #names > 0 and table.concat(names, ", ") or "none available"
      DEFAULT_CHAT_FRAME:AddMessage(AQL.WARN ..
          "[AQL] WARNING: No " .. label .. " provider found. " ..
          "Install one of: " .. addonList .. "." .. AQL.RESET)
      PlaySound(SOUNDKIT and SOUNDKIT.LEVEL_UP or "LEVELUP")
  end

  -- Fills unresolved capability slots from the priority list.
  -- Fires notifyBroken for providers that are available but structurally broken.
  -- Called at PLAYER_LOGIN and on the final deferred upgrade attempt.
  local function selectProviders()
      local priority = getProviderPriority()
      for capability, candidates in pairs(priority) do
          if AQL.providers[capability] == nil then
              for _, provider in ipairs(candidates) do
                  if provider and provider:IsAvailable() then
                      local ok, err = provider:Validate()
                      if ok then
                          AQL.providers[capability] = provider
                          if AQL.debug then
                              DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG ..
                                  "[AQL] Provider selected for " .. tostring(capability) ..
                                  ": " .. tostring(provider.addonName) .. AQL.RESET)
                          end
                          break
                      else
                          notifyBroken(provider, err)
                      end
                  end
              end
          end
      end
      -- Update backward-compatibility shim.
      AQL.provider = AQL.providers[AQL.Capability.Chain] or AQL.NullProvider
  end

  -- Re-runs selection for still-unresolved capabilities.
  -- During intermediate retries (attemptsLeft > 0): Validate()=false is treated as
  -- IsAvailable()=false — silent retry, no notification. Handles Questie's async
  -- init (~3 s) without spuriously warning the user.
  -- On the final attempt (attemptsLeft == 0): calls selectProviders() which fires
  -- notifyBroken, then fires notifyMissing for capabilities still unresolved.
  local function tryUpgradeProviders(attemptsLeft)
      local priority = getProviderPriority()

      -- Early out if all capabilities are already resolved.
      local allResolved = true
      for capability in pairs(priority) do
          if AQL.providers[capability] == nil then allResolved = false; break end
      end
      if allResolved then return end

      if attemptsLeft == 0 then
          -- Final attempt: run full selectProviders() which fires notifyBroken.
          selectProviders()
          -- Rebuild to incorporate any provider just selected.
          AQL.QuestCache:Rebuild()
          -- Notify for capabilities still unresolved after all attempts.
          for capability in pairs(priority) do
              if AQL.providers[capability] == nil then
                  notifyMissing(capability)
              end
          end
          return
      end

      -- Intermediate retry: silently try each unresolved capability.
      -- Validate()=false is skipped without notification.
      local anyUpgraded = false
      for capability, candidates in pairs(priority) do
          if AQL.providers[capability] == nil then
              for _, provider in ipairs(candidates) do
                  if provider and provider:IsAvailable() then
                      local ok = provider:Validate()
                      if ok then
                          AQL.providers[capability] = provider
                          anyUpgraded = true
                          if AQL.debug then
                              DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG ..
                                  "[AQL] Provider upgraded for " .. tostring(capability) ..
                                  ": " .. tostring(provider.addonName) .. AQL.RESET)
                          end
                          break
                      end
                      -- IsAvailable=true, Validate=false: skip silently during retry window.
                  end
              end
          end
      end
      if anyUpgraded then
          AQL.provider = AQL.providers[AQL.Capability.Chain] or AQL.NullProvider
          AQL.QuestCache:Rebuild()
      end
      if AQL.debug then
          DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG ..
              "[AQL] Provider upgrade attempt " ..
              tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS - attemptsLeft + 1) ..
              "/" .. tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS) ..
              (anyUpgraded and " — upgraded" or " — retrying") .. AQL.RESET)
      end
      C_Timer.After(1, function() tryUpgradeProviders(attemptsLeft - 1) end)
  end
  ```

- [ ] **Step 2: Update the inline upgrade check inside `handleQuestLogUpdate`**

  Inside the `C_Timer.After(0.5, function()` block, find the belt-and-suspenders block:
  ```lua
          if AQL.provider == AQL.NullProvider then
              local provider, providerName = selectProvider()
              if provider ~= AQL.NullProvider then
                  AQL.provider = provider
                  if AQL.debug then
                      DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Provider upgraded (inline): " .. tostring(providerName) .. AQL.RESET)
                  end
              end
          end
  ```

  Replace with:
  ```lua
          -- Belt-and-suspenders: silently fill any still-unresolved capability slots.
          -- tryUpgradeProviders handles the common case; this catches missed windows.
          -- Intentionally does not fire broken-provider notifications.
          for cap, candidates in pairs(getProviderPriority()) do
              if AQL.providers[cap] == nil then
                  for _, p in ipairs(candidates) do
                      if p and p:IsAvailable() then
                          local ok = p:Validate()
                          if ok then
                              AQL.providers[cap] = p
                              if AQL.debug then
                                  DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG ..
                                      "[AQL] Provider upgraded (inline) for " ..
                                      tostring(cap) .. ": " .. tostring(p.addonName) .. AQL.RESET)
                              end
                              break
                          end
                      end
                  end
              end
          end
          AQL.provider = AQL.providers[AQL.Capability.Chain] or AQL.NullProvider
  ```

- [ ] **Step 3: Update the PLAYER_LOGIN handler to call `selectProviders()` instead of `selectProvider()`**

  Inside the `if event == "PLAYER_LOGIN" then` block, find:
  ```lua
          -- Select the best available provider.
          local provider, providerName = selectProvider()
          AQL.provider = provider
          if AQL.debug then
              DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] Provider selected: " .. tostring(providerName) .. AQL.RESET)
          end
  ```

  Replace with:
  ```lua
          -- Select providers for each capability (fills immediately-available slots).
          -- Deferred upgrade below catches Questie's async init.
          selectProviders()
  ```

  Also update the deferred upgrade call at the bottom of the PLAYER_LOGIN block:
  ```lua
          C_Timer.After(0, function() tryUpgradeProvider(MAX_DEFERRED_UPGRADE_ATTEMPTS) end)
  ```
  Change to:
  ```lua
          C_Timer.After(0, function() tryUpgradeProviders(MAX_DEFERRED_UPGRADE_ATTEMPTS) end)
  ```

- [ ] **Step 4: Verify in-game**

  `/reload`. With debug on (`/aql debug on`), check that:
  - With Questie: three "Provider selected for Chain/QuestInfo/Requirements: Questie" messages appear
  - With no provider: after ~5 s, orange "WARNING: No quest chain provider found" messages appear with sound
  - Quest chain steps still display correctly in the party/shared tabs of SocialQuest (if installed)

- [ ] **Step 5: Commit**
  ```bash
  git add "Core/EventEngine.lua"
  git commit -m "refactor: replace selectProvider/tryUpgradeProvider with multi-capability selectProviders/tryUpgradeProviders; add notifyBroken/notifyMissing"
  ```

---

### Task 4: Update consumer call sites in `Core/QuestCache.lua`

**Files:**
- Modify: `Core/QuestCache.lua`

- [ ] **Step 1: Update `_buildEntry` provider calls to route through capability slots**

  Find the provider data section (around line 172–187):
  ```lua
      -- Provider data (chain/type/faction).
      -- AQL.provider may be nil during the very first Rebuild before EventEngine
      -- has run provider selection. Nil-guard here; the next rebuild after
      -- PLAYER_LOGIN will have a provider set.
      local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
      local questType, questFaction
      local provider = AQL.provider
      if provider then
          local ok, result = pcall(provider.GetChainInfo, provider, questID)
          if ok and result then chainInfo = result end

          local ok2, result2 = pcall(provider.GetQuestType, provider, questID)
          if ok2 then questType = result2 end

          local ok3, result3 = pcall(provider.GetQuestFaction, provider, questID)
          if ok3 then questFaction = result3 end
      end
  ```

  Replace with:
  ```lua
      -- Provider data (chain/type/faction) routed through capability slots.
      -- AQL.providers may be nil during the very first Rebuild before EventEngine
      -- runs provider selection. Nil-guards here; the next rebuild after
      -- PLAYER_LOGIN will have providers set.
      local chainInfo = { knownStatus = AQL.ChainStatus.Unknown }
      local questType, questFaction

      local chainProvider = AQL.providers and AQL.providers[AQL.Capability.Chain]
      if chainProvider then
          local ok, result = pcall(chainProvider.GetChainInfo, chainProvider, questID)
          if ok and result then chainInfo = result end
      end

      local infoProvider = AQL.providers and AQL.providers[AQL.Capability.QuestInfo]
      if infoProvider then
          local ok2, result2 = pcall(infoProvider.GetQuestType, infoProvider, questID)
          if ok2 then questType = result2 end

          local ok3, result3 = pcall(infoProvider.GetQuestFaction, infoProvider, questID)
          if ok3 then questFaction = result3 end
      end
  ```

- [ ] **Step 2: Verify in-game**

  `/reload`. Quest entries in the Mine/Party/Shared tabs should still show chain step indicators (e.g. "Step 2/4") and type badges ([Group], [Dungeon]) exactly as before.

- [ ] **Step 3: Commit**
  ```bash
  git add "Core/QuestCache.lua"
  git commit -m "refactor: route QuestCache _buildEntry provider calls through AQL.providers capability slots"
  ```

---

### Task 5: Version bump and documentation

**Files:**
- Modify: `AbsoluteQuestLog.toc`, `AbsoluteQuestLog_TBC.toc`, `AbsoluteQuestLog_Classic.toc`, `AbsoluteQuestLog_Mainline.toc`, `AbsoluteQuestLog_Mists.toc`
- Modify: `CLAUDE.md`
- Modify: `changelog.txt`

- [ ] **Step 1: Bump version to 2.6.0 in all five toc files**

  In each of the five `.toc` files, change:
  ```
  ## Version: 2.5.5
  ```
  to:
  ```
  ## Version: 2.6.0
  ```

- [ ] **Step 2: Add version history entry to `CLAUDE.md`**

  Add at the top of the Version History section (above the existing 2.5.5 entry):
  ```markdown
  ### Version 2.6.0 (March 2026)
  - Refactor: provider system restructured for multi-provider capability routing.
    Three capability buckets (`Chain`, `QuestInfo`, `Requirements`) each carry an
    independent provider slot in `AQL.providers`, selected from a priority-ordered
    candidate list. `AQL.provider` (singular) is kept as a backward-compatibility shim.
  - New: `AQL.Capability` enum (`Chain`, `QuestInfo`, `Requirements`).
  - New: `AQL.WARN` orange color constant for always-on provider warning messages.
  - New: `AQL.providers` table keyed by `AQL.Capability.*`; replaces single `AQL.provider`
    as the authoritative provider reference for all internal code.
  - New: `Provider:Validate()` method on all providers — structural check separate from
    `IsAvailable()` (presence check). `IsAvailable()=true` + `Validate()=false` fires a
    one-time orange warning with sound; `IsAvailable()=false` is silent.
  - New: `Provider.addonName` and `Provider.capabilities` fields on all providers.
  - New: Always-on "No X provider found" notification (with sound) fires after the
    deferred upgrade window closes for any capability that remains unresolved.
  - Behavior unchanged for players with a working Questie or QuestWeaver installation.
  ```

- [ ] **Step 3: Add version entry to `changelog.txt`**

  Insert at the top of the file (after the header lines), before the 2.5.5 entry:
  ```
  Version 2.6.0 (March 2026)
  ---------------------------
  - Refactor: provider system restructured for multi-provider capability routing (Chain, QuestInfo, Requirements buckets).
  - New: AQL.Capability enum, AQL.WARN color constant, AQL.providers table.
  - New: Provider:Validate() method, Provider.addonName and Provider.capabilities fields on all providers.
  - New: Always-on broken-provider and missing-provider notifications (orange, with sound).
  - Behavior unchanged for players with a working Questie or QuestWeaver installation.
  ```

- [ ] **Step 4: Commit**
  ```bash
  git add "AbsoluteQuestLog.toc" "AbsoluteQuestLog_TBC.toc" "AbsoluteQuestLog_Classic.toc" "AbsoluteQuestLog_Mainline.toc" "AbsoluteQuestLog_Mists.toc" "CLAUDE.md" "changelog.txt"
  git commit -m "chore: bump version to 2.6.0; update CLAUDE.md and changelog for provider system refactor"
  ```

---

## Manual Verification Checklist

After all tasks are complete, verify the following in-game:

| Scenario | Expected |
|---|---|
| Questie installed, `/aql debug on`, `/reload` | Three "Provider selected for Chain/QuestInfo/Requirements: Questie" messages in chat |
| QuestWeaver installed (no Questie), debug on | "Provider selected for Chain/QuestInfo: QuestWeaver" + "No requirements provider found" warning with sound |
| No quest DB addon installed | Orange warning messages for all three capabilities with ding sound after ~5 s |
| Quest chain steps in SocialQuest Party tab | "Step N/M" still appears; no regression |
| Quest type badges ([Group], [Dungeon]) | Still visible; no regression |
| `/aql debug off`, Questie installed | No output; everything works silently |
