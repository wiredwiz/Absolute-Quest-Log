# GrailProvider + ChainInfo Contract Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GrailProvider to AQL, redesign `GetChainInfo` to return a multi-chain wrapper, and add `SelectBestChain` to support cross-player chain selection, shipping as version 3.0.0.

**Architecture:** `GetChainInfo` returns `{ knownStatus, chains={...} }` — a wrapper object whose `chains` array may hold multiple chain entries when a quest belongs to more than one chain. `SelectBestChain(chainResult, engagedQuestIDs)` picks the best entry by scoring member overlap against an arbitrary engaged-quest set, enabling both current-player and cross-player use. GrailProvider reverse-engineers chain topology by scanning `Grail.questPrerequisites` once (lazy, on first `GetChainInfo` call) to build a `reverseMap`, then walking backward to roots and forward to reconstruct the full chain.

**Tech Stack:** Lua 5.1 (WoW), LibStub, AQL provider pattern, Grail addon (`_G["Grail"]`), `bit.bxor` for cache key fingerprinting.

---

## File Map

**New files:**
- `Absolute-Quest-Log/Providers/GrailProvider.lua`

**Modified files:**
- `Absolute-Quest-Log/AbsoluteQuestLog.lua` — enum additions, SelectBestChain, helpers, GetChainStep/Length
- `Absolute-Quest-Log/Core/EventEngine.lua` — provider lists, cache clearing
- `Absolute-Quest-Log/Providers/QuestieProvider.lua` — wrap Known return in `chains={}`
- `Absolute-Quest-Log/Providers/QuestWeaverProvider.lua` — wrap Known return in `chains={}`
- `Absolute-Quest-Log/Providers/BtWQuestsProvider.lua` — wrap Known return in `chains={}`
- `Absolute-Quest-Log/Providers/NullProvider.lua` — no change (already wrapper-compatible)
- `Absolute-Quest-Log/AbsoluteQuestLog.toc` + all 4 multi-toc files — add GrailProvider.lua
- `Social-Quest/Core/Announcements.lua` — appendChainStep uses SelectBestChain
- `Social-Quest/UI/RowFactory.lua` — chain step display uses SelectBestChain
- `Social-Quest/UI/TabUtils.lua` — GetChainInfoForQuestID simplified
- `Social-Quest/UI/Tabs/MineTab.lua` — all chainInfo accesses use wrapper pattern
- `Absolute-Quest-Log/CLAUDE.md` — updated docs
- `Absolute-Quest-Log/README.md`, `README.txt` — breaking change section
- `Absolute-Quest-Log/changelog.txt` — 3.0.0 entry

---

## Task 1: Enum Additions

**Files:**
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog.lua:53-68`

- [ ] **Step 1: Add `AQL.QuestType.Weekly` and `AQL.Provider.Grail`**

  In `AbsoluteQuestLog.lua`, the `AQL.Provider` table is at lines 53–58 and `AQL.QuestType` at lines 60–68. Add one entry to each:

  ```lua
  -- AQL.Provider block — add Grail:
  AQL.Provider = {
      Questie     = "Questie",
      QuestWeaver = "QuestWeaver",
      BtWQuests   = "BtWQuests",
      Grail       = "Grail",
      None        = "none",
  }

  -- AQL.QuestType block — add Weekly:
  AQL.QuestType = {
      Normal  = "normal",
      Elite   = "elite",
      Dungeon = "dungeon",
      Raid    = "raid",
      Daily   = "daily",
      Weekly  = "weekly",
      PvP     = "pvp",
      Escort  = "escort",
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  cd "D:\Projects\Wow Addons\Absolute-Quest-Log"
  git add AbsoluteQuestLog.lua
  git commit -m "feat: add AQL.QuestType.Weekly and AQL.Provider.Grail enums"
  ```

---

## Task 2: Wrap Existing Provider `GetChainInfo` Returns

All three active providers return a bare ChainInfo table when status is `Known`. Each one must now return a wrapper: `{ knownStatus = "known", chains = { chainEntry } }`. `NotAChain` and `Unknown` returns are already wrapper-compatible (no `chains` key needed).

**Files:**
- Modify: `Absolute-Quest-Log/Providers/QuestieProvider.lua:210-217`
- Modify: `Absolute-Quest-Log/Providers/QuestWeaverProvider.lua:91-98`
- Modify: `Absolute-Quest-Log/Providers/BtWQuestsProvider.lua:234-241`

- [ ] **Step 1: Wrap QuestieProvider `GetChainInfo` return**

  In `QuestieProvider.lua`, find the final `return` in `GetChainInfo` (currently lines 210–217):

  ```lua
  -- BEFORE:
  return {
      knownStatus = AQL.ChainStatus.Known,
      chainID     = chainID,
      step        = stepNum,
      length      = length,
      steps       = steps,
      provider    = AQL.Provider.Questie,
  }

  -- AFTER:
  return {
      knownStatus = AQL.ChainStatus.Known,
      chains = {
          {
              chainID    = chainID,
              step       = stepNum,
              length     = length,
              questCount = length,
              steps      = steps,
              provider   = AQL.Provider.Questie,
          }
      }
  }
  ```

- [ ] **Step 2: Wrap QuestWeaverProvider `GetChainInfo` return**

  In `QuestWeaverProvider.lua`, find the final `return` in `GetChainInfo` (currently lines 91–98):

  ```lua
  -- BEFORE:
  return {
      knownStatus = AQL.ChainStatus.Known,
      chainID     = chainID,
      step        = stepNum,
      length      = length,
      steps       = steps,
      provider    = AQL.Provider.QuestWeaver,
  }

  -- AFTER:
  return {
      knownStatus = AQL.ChainStatus.Known,
      chains = {
          {
              chainID    = chainID,
              step       = stepNum,
              length     = length,
              questCount = length,
              steps      = steps,
              provider   = AQL.Provider.QuestWeaver,
          }
      }
  }
  ```

- [ ] **Step 3: Wrap BtWQuestsProvider `GetChainInfo` return**

  In `BtWQuestsProvider.lua`, find the final `return` in `GetChainInfo` (currently lines 234–241):

  ```lua
  -- BEFORE:
  return {
      knownStatus = AQL.ChainStatus.Known,
      chainID     = aqlChainID,
      step        = stepNum,
      length      = #steps,
      steps       = steps,
      provider    = AQL.Provider.BtWQuests,
  }

  -- AFTER:
  return {
      knownStatus = AQL.ChainStatus.Known,
      chains = {
          {
              chainID    = aqlChainID,
              step       = stepNum,
              length     = #steps,
              questCount = #steps,
              steps      = steps,
              provider   = AQL.Provider.BtWQuests,
          }
      }
  }
  ```

- [ ] **Step 4: Verify NullProvider needs no change**

  `NullProvider:GetChainInfo` returns `{ knownStatus = AQL.ChainStatus.Unknown }` — no `chains` key. This is already wrapper-compatible since all consumers guard with `knownStatus == Known` before accessing `chains`. No edit needed.

- [ ] **Step 5: Commit**

  ```bash
  git add Providers/QuestieProvider.lua Providers/QuestWeaverProvider.lua Providers/BtWQuestsProvider.lua
  git commit -m "refactor: wrap GetChainInfo Known returns in chains={} wrapper (3.0 breaking change)"
  ```

---

## Task 3: SelectBestChain and Helpers in AbsoluteQuestLog.lua

Add the private cache table, two private methods, and one new public method to `AbsoluteQuestLog.lua`, in the Chain Info section (after line 268).

**Files:**
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog.lua:248-268` (Chain Info section)

- [ ] **Step 1: Add private cache + `_GetCurrentPlayerEngagedQuests`**

  Just before the `GetChainInfo` function (around line 247), add:

  ```lua
  -- Private memoization cache for SelectBestChain. Keyed by "chainID:count:xor:sum".
  -- Cleared by _ClearChainSelectionCache on quest state changes.
  local selectionCache = {}
  ```

  Then after the `GetChainLength` function (after line 268), add:

  ```lua
  -- _GetCurrentPlayerEngagedQuests() → { [questID] = true }
  -- Merges HistoryCache (all completed quests) with active QuestCache (all in-log quests).
  -- Used by GetChainStep, GetChainLength, and SocialQuest's Mine tab to score chains
  -- for the local player.
  function AQL:_GetCurrentPlayerEngagedQuests()
      local engaged = {}
      if self.HistoryCache then
          for questID in pairs(self.HistoryCache:GetAll()) do
              engaged[questID] = true
          end
      end
      if self.QuestCache then
          for questID in pairs(self.QuestCache:GetAll()) do
              engaged[questID] = true
          end
      end
      return engaged
  end

  -- _ClearChainSelectionCache()
  -- Resets the SelectBestChain memoization cache.
  -- Called by EventEngine on QUEST_ACCEPTED, QUEST_REMOVED, and QUEST_TURNED_IN.
  function AQL:_ClearChainSelectionCache()
      selectionCache = {}
  end
  ```

- [ ] **Step 2: Add `SelectBestChain`**

  After `_ClearChainSelectionCache`, add:

  ```lua
  -- SelectBestChain(chainResult, engagedQuestIDs) → chain entry table or nil
  -- Player-agnostic best-chain selector. Scores each chain in chainResult by counting
  -- how many of its member quests appear in engagedQuestIDs. Returns the highest-scoring
  -- chain entry, or nil if chainResult.knownStatus is not "known".
  --
  -- chainResult:     return value of AQL:GetChainInfo(questID)
  -- engagedQuestIDs: { [questID] = true } — completed + active quests for the target player
  -- returns:         chain entry { chainID, step, length, questCount, steps, provider } or nil
  --
  -- Results are memoized per (chainID, fingerprint) where fingerprint is a count:xor:sum
  -- composite of the engaged set. Cache is cleared by _ClearChainSelectionCache.
  function AQL:SelectBestChain(chainResult, engagedQuestIDs)
      if not chainResult or chainResult.knownStatus ~= AQL.ChainStatus.Known then
          return nil
      end
      local chains = chainResult.chains
      if not chains or #chains == 0 then return nil end
      if #chains == 1 then return chains[1] end  -- fast path: no scoring needed

      -- Build fingerprint of the engaged set: count:xor:sum
      -- bit.bxor is available in WoW's Lua environment (LuaJIT / Lua BitOp).
      local count, xorVal, sumVal = 0, 0, 0
      for qid in pairs(engagedQuestIDs or {}) do
          count  = count  + 1
          xorVal = bit.bxor(xorVal, qid)
          sumVal = sumVal + qid
      end
      local fp = count .. ":" .. xorVal .. ":" .. sumVal

      local bestChain, bestScore = chains[1], -1
      for _, chain in ipairs(chains) do
          local cacheKey = tostring(chain.chainID or 0) .. ":" .. fp
          local score = selectionCache[cacheKey]
          if score == nil then
              -- Score: count engaged quests that appear anywhere in this chain's steps.
              score = 0
              for _, step in ipairs(chain.steps or {}) do
                  if step.questID then
                      if engagedQuestIDs[step.questID] then score = score + 1 end
                  elseif step.quests then
                      for _, sq in ipairs(step.quests) do
                          if engagedQuestIDs[sq.questID] then score = score + 1 end
                      end
                  end
              end
              selectionCache[cacheKey] = score
          end
          if score > bestScore then
              bestScore = score
              bestChain = chain
          end
      end

      return bestChain
  end
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add AbsoluteQuestLog.lua
  git commit -m "feat: add SelectBestChain, _GetCurrentPlayerEngagedQuests, _ClearChainSelectionCache"
  ```

---

## Task 4: Update `GetChainStep` and `GetChainLength`

These currently access `.step` and `.length` directly on the `GetChainInfo` result. Update them to use `SelectBestChain`.

**Files:**
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog.lua:258-268`

- [ ] **Step 1: Replace GetChainStep and GetChainLength**

  ```lua
  -- BEFORE (lines 258-268):
  -- GetChainStep(questID) → number or nil
  -- Returns the 1-based step position of questID in its chain, or nil if unknown.
  function AQL:GetChainStep(questID)
      return self:GetChainInfo(questID).step
  end

  -- GetChainLength(questID) → number or nil
  -- Returns the total number of quests in questID's chain, or nil if unknown.
  function AQL:GetChainLength(questID)
      return self:GetChainInfo(questID).length
  end

  -- AFTER:
  -- GetChainStep(questID) → number or nil
  -- Returns the 1-based step position for the current player's best-fit chain, or nil.
  function AQL:GetChainStep(questID)
      local r = self:GetChainInfo(questID)
      if r.knownStatus ~= AQL.ChainStatus.Known then return nil end
      local engaged = self:_GetCurrentPlayerEngagedQuests()
      local chain = self:SelectBestChain(r, engaged)
      return chain and chain.step or nil
  end

  -- GetChainLength(questID) → number or nil
  -- Returns the total step count for the current player's best-fit chain, or nil.
  function AQL:GetChainLength(questID)
      local r = self:GetChainInfo(questID)
      if r.knownStatus ~= AQL.ChainStatus.Known then return nil end
      local engaged = self:_GetCurrentPlayerEngagedQuests()
      local chain = self:SelectBestChain(r, engaged)
      return chain and chain.length or nil
  end
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add AbsoluteQuestLog.lua
  git commit -m "refactor: GetChainStep/Length use SelectBestChain for current player"
  ```

---

## Task 5: EventEngine Updates

Two changes: (1) add `AQL.GrailProvider` to all three capability priority lists; (2) call `AQL:_ClearChainSelectionCache()` when quest state changes.

**Files:**
- Modify: `Absolute-Quest-Log/Core/EventEngine.lua:80-84` (priority lists)
- Modify: `Absolute-Quest-Log/Core/EventEngine.lua:541-562` (QUEST_ACCEPTED, QUEST_REMOVED, QUEST_TURNED_IN handlers)

- [ ] **Step 1: Add GrailProvider to priority lists**

  In `EventEngine.lua`, find the `_PROVIDER_PRIORITY` table assignment (lines 80–84):

  ```lua
  -- BEFORE:
  _PROVIDER_PRIORITY = {
      [AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider },
      [AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider },
      [AQL.Capability.Requirements] = { AQL.QuestieProvider, AQL.BtWQuestsProvider },
  }

  -- AFTER:
  _PROVIDER_PRIORITY = {
      [AQL.Capability.Chain]        = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
      [AQL.Capability.QuestInfo]    = { AQL.QuestieProvider, AQL.QuestWeaverProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
      [AQL.Capability.Requirements] = { AQL.QuestieProvider, AQL.BtWQuestsProvider, AQL.GrailProvider },
  }
  ```

- [ ] **Step 2: Clear SelectBestChain cache on quest state changes**

  In the `OnEvent` handler (lines 541–566), add `AQL:_ClearChainSelectionCache()` calls:

  ```lua
  -- In the QUEST_ACCEPTED branch (line 541):
  elseif event == "QUEST_ACCEPTED" then
      EventEngine.pendingAcceptCount = EventEngine.pendingAcceptCount + 1
      AQL:_ClearChainSelectionCache()
      handleQuestLogUpdate()

  -- In the QUEST_REMOVED branch (line 547):
  elseif event == "QUEST_REMOVED" then
      EventEngine.pendingAcceptCount = 0
      AQL:_ClearChainSelectionCache()
      handleQuestLogUpdate()

  -- In the QUEST_TURNED_IN branch (line 552):
  elseif event == "QUEST_TURNED_IN" then
      local questID = ...
      if questID and questID ~= 0 then
          EventEngine.pendingTurnIn[questID] = true
          AQL:_ClearChainSelectionCache()
          if AQL.debug then
              DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] pendingTurnIn set (QUEST_TURNED_IN): questID=" .. tostring(questID) .. AQL.RESET)
          end
      end
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add Core/EventEngine.lua
  git commit -m "feat: add GrailProvider to priority lists; clear SelectBestChain cache on quest events"
  ```

---

## Task 6: Create GrailProvider.lua

**Files:**
- Create: `Absolute-Quest-Log/Providers/GrailProvider.lua`

- [ ] **Step 1: Create the file with provider skeleton, detection, and QuestInfo capability**

  Create `Absolute-Quest-Log/Providers/GrailProvider.lua`:

  ```lua
  -- Providers/GrailProvider.lua
  -- Reads quest data from the Grail addon (Grail-123 for Classic/TBC/Wrath,
  -- Grail-124 for Retail/TWW). Covers all three AQL capabilities:
  --   Chain        — reverse-engineered from Grail.questPrerequisites
  --   QuestInfo    — GetQuestBasicInfo, GetQuestType, GetQuestFaction
  --   Requirements — prerequisite IDs, exclusiveTo, level range
  --
  -- Chain reconstruction is lazy: the reverse map is built on the first call to
  -- GetChainInfo and cached for the session. All other methods are per-quest lookups
  -- with no upfront cost.

  local AQL = LibStub("AbsoluteQuestLog-1.0", true)
  if not AQL then return end

  local GrailProvider = {}

  GrailProvider.addonName    = "Grail"
  GrailProvider.capabilities = {
      AQL.Capability.Chain,
      AQL.Capability.QuestInfo,
      AQL.Capability.Requirements,
  }

  ------------------------------------------------------------------------
  -- Detection
  ------------------------------------------------------------------------

  -- IsAvailable(): lightweight structural check — Grail global + required tables present.
  function GrailProvider:IsAvailable()
      local g = _G["Grail"]
      return g ~= nil
          and type(g.questCodes)        == "table"
          and type(g.questPrerequisites) == "table"
  end

  -- Validate(): database has loaded (questCodes is non-empty).
  -- Grail initializes synchronously at PLAYER_LOGIN, so non-empty = ready.
  function GrailProvider:Validate()
      local g = _G["Grail"]
      if not g then return false end
      return next(g.questCodes) ~= nil
  end

  ------------------------------------------------------------------------
  -- QuestInfo capability
  ------------------------------------------------------------------------

  function GrailProvider:GetQuestBasicInfo(questID)
      local g = _G["Grail"]
      if not g then return nil end

      local title = g:QuestName(questID)
      if not title then return nil end

      -- Zone: take the first accept-location record's mapArea, resolve via GetAreaInfo.
      local zone
      local locs = g:QuestLocationsAccept(questID)
      if locs and locs[1] then
          local mapArea = locs[1].mapArea
          if mapArea and mapArea > 0 then
              zone = WowQuestAPI.GetAreaInfo(mapArea)
          end
      end

      return {
          title         = title,
          questLevel    = g:QuestLevel(questID),
          requiredLevel = g:QuestLevelRequired(questID),
          zone          = zone,
      }
  end

  -- Priority-ordered type detection. Returns the first matching AQL type string, or nil.
  function GrailProvider:GetQuestType(questID)
      local g = _G["Grail"]
      if not g then return nil end
      if g:IsRaid(questID)   then return AQL.QuestType.Raid    end
      if g:IsDungeon(questID) then return AQL.QuestType.Dungeon end
      if g:IsEscort(questID) then return AQL.QuestType.Escort  end
      if g:IsGroup(questID)  then return AQL.QuestType.Elite   end
      if g:IsPVP(questID)    then return AQL.QuestType.PvP     end
      if g:IsWeekly(questID) then return AQL.QuestType.Weekly  end
      if g:IsDaily(questID)  then return AQL.QuestType.Daily   end
      return nil
  end

  -- Parse faction from Grail's raw questCodes string.
  -- "FA" = Alliance, "FH" = Horde. Plain-text search; case-sensitive.
  function GrailProvider:GetQuestFaction(questID)
      local g = _G["Grail"]
      if not g then return nil end
      local code = g.questCodes[questID]
      if not code then return nil end
      if strfind(code, "FA", 1, true) then return AQL.Faction.Alliance end
      if strfind(code, "FH", 1, true) then return AQL.Faction.Horde    end
      return nil
  end

  ------------------------------------------------------------------------
  -- Requirements capability
  -- Helper: extract only plain-numeric tokens from a prerequisites string.
  -- Letter-prefixed tokens (a=world quest, b=threat, P=profession, T=rep, etc.)
  -- are not chain links and are skipped entirely.
  ------------------------------------------------------------------------

  local function parsePlainNumericTokens(prereqStr)
      if not prereqStr or prereqStr == "" then return {} end
      local ids = {}
      for token in prereqStr:gmatch("[^,+]+") do
          token = token:match("^%s*(.-)%s*$")  -- trim whitespace
          if token:match("^%d+$") then
              ids[#ids + 1] = tonumber(token)
          end
          -- letter-prefixed tokens like "a12345", "P1", "T45" are silently skipped
      end
      return ids
  end

  -- Parse AND prereqs (tokens joined by "+"): all must be completed.
  local function parseAndPrereqs(prereqStr)
      if not prereqStr or prereqStr == "" then return nil end
      local ids = {}
      for token in prereqStr:gmatch("[^,]+") do
          token = token:match("^%s*(.-)%s*$")
          -- Each AND group is the whole token; check it has only numerics joined by "+"
          local allNumeric = true
          for part in token:gmatch("[^+]+") do
              part = part:match("^%s*(.-)%s*$")
              if not part:match("^%d+$") then allNumeric = false; break end
          end
          if allNumeric and token:find("+", 1, true) then
              local group = {}
              for part in token:gmatch("[^+]+") do
                  group[#group + 1] = tonumber(part:match("^%s*(.-)%s*$"))
              end
              if #group > 0 then ids[#ids + 1] = group end
          end
      end
      return #ids > 0 and ids or nil
  end

  -- Parse OR prereqs (tokens joined by ","): any one satisfies the requirement.
  local function parseOrPrereqs(prereqStr)
      if not prereqStr or prereqStr == "" then return nil end
      local ids = {}
      for token in prereqStr:gmatch("[^,]+") do
          token = token:match("^%s*(.-)%s*$")
          if token:match("^%d+$") then
              ids[#ids + 1] = tonumber(token)
          end
      end
      return #ids > 1 and ids or nil
  end

  function GrailProvider:GetQuestRequirements(questID)
      local g = _G["Grail"]
      if not g then return nil end

      local prereqRaw = g.questPrerequisites[questID]

      -- Exclusive quests: quests that are mutually exclusive with this one.
      -- Grail encodes these as "I:" codes in questCodes. Parse them.
      local exclusiveTo = nil
      local code = g.questCodes[questID]
      if code then
          local iCodes = {}
          for iVal in code:gmatch("I:(%d+)") do
              iCodes[#iCodes + 1] = tonumber(iVal)
          end
          if #iCodes > 0 then exclusiveTo = iCodes end
      end

      -- Breadcrumb: first "O:" code entry (optional follow-on quest).
      local breadcrumb = nil
      if code then
          local oVal = code:match("O:(%d+)")
          if oVal then breadcrumb = tonumber(oVal) end
      end

      local maxLevel = g:QuestLevelVariableMax and g:QuestLevelVariableMax(questID) or nil
      if maxLevel == 0 then maxLevel = nil end

      return {
          requiredLevel        = g:QuestLevelRequired(questID),
          requiredMaxLevel     = maxLevel,
          preQuestGroup        = parseAndPrereqs(prereqRaw),
          preQuestSingle       = parseOrPrereqs(prereqRaw),
          exclusiveTo          = exclusiveTo,
          breadcrumbForQuestId = breadcrumb,
          nextQuestInChain     = nil,  -- not derivable from prerequisites alone
          requiredRaces        = nil,  -- Grail uses letter codes; bitmask mapping deferred
          requiredClasses      = nil,  -- same
      }
  end

  ------------------------------------------------------------------------
  -- Chain capability
  -- Reverse-map built once (lazy) on first GetChainInfo call.
  -- reverseMap[prereqID] = { questID1, questID2, ... }
  ------------------------------------------------------------------------

  local reverseMap = {}
  local reverseMapBuilt = false

  local function buildReverseMap()
      if reverseMapBuilt then return end
      local g = _G["Grail"]
      if not g or not g.questPrerequisites then return end
      for questID, prereqStr in pairs(g.questPrerequisites) do
          for token in prereqStr:gmatch("[^,+]+") do
              token = token:match("^%s*(.-)%s*$")
              if token:match("^%d+$") then
                  local prereqID = tonumber(token)
                  if not reverseMap[prereqID] then reverseMap[prereqID] = {} end
                  reverseMap[prereqID][#reverseMap[prereqID] + 1] = questID
              end
          end
      end
      reverseMapBuilt = true
  end

  -- Walk backward from questID to find all root questIDs (quests with no plain-numeric prereqs).
  -- Returns a list of root questIDs. A visited table prevents cycles.
  local function findRoots(startQuestID)
      local g = _G["Grail"]
      local roots = {}
      local visited = {}

      local function walkBack(qid)
          if visited[qid] then return end
          visited[qid] = true
          local prereqStr = g.questPrerequisites[qid]
          if not prereqStr or prereqStr == "" then
              -- No prerequisites: this is a root.
              roots[#roots + 1] = qid
              return
          end
          local plainNumerics = parsePlainNumericTokens(prereqStr)
          if #plainNumerics == 0 then
              -- All prereqs are letter-prefixed (non-chain conditions): treat as root.
              roots[#roots + 1] = qid
              return
          end
          -- Walk back through all plain-numeric prereqs.
          for _, prereqID in ipairs(plainNumerics) do
              walkBack(prereqID)
          end
      end

      walkBack(startQuestID)
      return roots
  end

  -- Compute the set of all questIDs reachable forward from startQuestID.
  local function forwardReachable(startQuestID)
      local reachable = {}
      local visited = {}
      local queue = { startQuestID }
      while #queue > 0 do
          local qid = table.remove(queue, 1)
          if not visited[qid] then
              visited[qid] = true
              reachable[qid] = true
              local successors = reverseMap[qid] or {}
              for _, s in ipairs(successors) do
                  queue[#queue + 1] = s
              end
          end
      end
      return reachable
  end

  -- Determine groupType for a multi-successor step.
  -- If all successors have mutual I: codes pointing at each other → "branch".
  -- If none → "parallel". Otherwise → "unknown".
  local function getGroupType(successors)
      local g = _G["Grail"]
      -- Build exclusion sets for each successor.
      local exclusions = {}
      for _, sid in ipairs(successors) do
          local code = g.questCodes[sid]
          if code then
              local exSet = {}
              for iVal in code:gmatch("I:(%d+)") do
                  exSet[tonumber(iVal)] = true
              end
              exclusions[sid] = exSet
          else
              exclusions[sid] = {}
          end
      end
      -- Check if every pair is mutually exclusive.
      for i, sid in ipairs(successors) do
          for j, other in ipairs(successors) do
              if i ~= j then
                  if not exclusions[sid][other] then
                      return "parallel"
                  end
              end
          end
      end
      return "branch"
  end

  -- Classify step status for a questID.
  local function classifyStatus(stepQuestID, stepIndex, steps)
      if AQL.HistoryCache and AQL.HistoryCache:HasCompleted(stepQuestID) then
          return AQL.StepStatus.Completed
      end
      local q = AQL.QuestCache and AQL.QuestCache:Get(stepQuestID)
      if q then
          if q.isFailed   then return AQL.StepStatus.Failed   end
          if q.isComplete then return AQL.StepStatus.Finished end
          return AQL.StepStatus.Active
      end
      -- Not active, not in history: determine available/unavailable/unknown.
      if stepIndex == 1 then return AQL.StepStatus.Available end
      local prevStep = steps[stepIndex - 1]
      if not prevStep then return AQL.StepStatus.Unknown end
      -- Check if all quests in the previous step are completed.
      local prevIDs = {}
      if prevStep.questID then
          prevIDs[1] = prevStep.questID
      elseif prevStep.quests then
          for _, sq in ipairs(prevStep.quests) do prevIDs[#prevIDs + 1] = sq.questID end
      end
      for _, pid in ipairs(prevIDs) do
          if not (AQL.HistoryCache and AQL.HistoryCache:HasCompleted(pid)) then
              return AQL.StepStatus.Unavailable
          end
      end
      return AQL.StepStatus.Available
  end

  -- Build a single chain starting at rootQuestID.
  -- Returns a steps array (each step is single-quest or multi-quest) and the total questCount.
  local MAX_CHAIN_DEPTH = 50

  local function buildChainFromRoot(rootQuestID)
      local g = _G["Grail"]
      local steps = {}
      local visited = {}
      local questCount = 0

      -- BFS-style forward walk; processes one "wave" (step position) at a time.
      local currentWave = { rootQuestID }
      visited[rootQuestID] = true

      while #currentWave > 0 and #steps < MAX_CHAIN_DEPTH do
          if #currentWave == 1 then
              -- Single quest at this step.
              local qid = currentWave[1]
              local title = (g:QuestName(qid)) or ("Quest " .. qid)
              steps[#steps + 1] = {
                  questID = qid,
                  title   = title,
                  status  = AQL.StepStatus.Unknown,  -- annotated below
              }
              questCount = questCount + 1

              -- Find successors for next wave.
              local successors = reverseMap[qid] or {}
              if #successors == 0 then
                  break  -- end of chain
              end

              -- Filter out already-visited successors (cycle guard).
              local nextWave = {}
              for _, s in ipairs(successors) do
                  if not visited[s] then
                      visited[s] = true
                      nextWave[#nextWave + 1] = s
                  end
              end

              if #nextWave == 0 then break end

              -- Check if successors diverge or converge.
              if #nextWave == 1 then
                  currentWave = nextWave
              else
                  -- Multiple successors: check if they reconverge downstream.
                  local sets = {}
                  for _, s in ipairs(nextWave) do
                      sets[s] = forwardReachable(s)
                  end
                  -- Test if any two forward-reachable sets share a questID (convergence).
                  local converge = false
                  for i = 1, #nextWave do
                      for j = i + 1, #nextWave do
                          for qid2 in pairs(sets[nextWave[i]]) do
                              if sets[nextWave[j]][qid2] then
                                  converge = true
                                  break
                              end
                          end
                          if converge then break end
                      end
                      if converge then break end
                  end

                  if converge then
                      -- Successors branch and reconverge: group them as one step.
                      local groupType = getGroupType(nextWave)
                      local subQuests = {}
                      for _, s in ipairs(nextWave) do
                          local stitle = (g:QuestName(s)) or ("Quest " .. s)
                          subQuests[#subQuests + 1] = {
                              questID = s,
                              title   = stitle,
                              status  = AQL.StepStatus.Unknown,
                          }
                          questCount = questCount + 1
                      end
                      steps[#steps + 1] = { quests = subQuests, groupType = groupType }
                      -- Find successors of the group (the convergence point).
                      -- Union all forward successors, pick the one reachable from all.
                      local unionSuccessors = {}
                      for _, s in ipairs(nextWave) do
                          for _, ns in ipairs(reverseMap[s] or {}) do
                              if not visited[ns] then
                                  -- Check if ns is reachable from all nextWave members.
                                  local reachableFromAll = true
                                  for _, other in ipairs(nextWave) do
                                      if other ~= s and not sets[other][ns] then
                                          reachableFromAll = false; break
                                      end
                                  end
                                  if reachableFromAll then
                                      visited[ns] = true
                                      unionSuccessors[ns] = true
                                  end
                              end
                          end
                      end
                      currentWave = {}
                      for ns in pairs(unionSuccessors) do currentWave[#currentWave + 1] = ns end
                  else
                      -- Successors diverge: this chain ends here. Divergent paths are
                      -- separate chains (each root handles them via findRoots returning
                      -- multiple entries when this quest is a branching point).
                      break
                  end
              end
          else
              -- Multi-quest wave (shouldn't normally happen after the first step unless
              -- the convergence logic didn't find a single next step).
              break
          end
      end

      return steps, questCount
  end

  function GrailProvider:GetChainInfo(questID)
      local g = _G["Grail"]
      if not g then return { knownStatus = AQL.ChainStatus.Unknown } end

      -- Lazy build of the reverse map on first call.
      buildReverseMap()

      -- Check if questID appears in the prerequisite graph at all.
      -- A quest is in the graph if it has prerequisites OR if it has successors.
      local hasPrereqs = g.questPrerequisites[questID] and g.questPrerequisites[questID] ~= ""
      local hasSuccessors = reverseMap[questID] and #reverseMap[questID] > 0
      if not hasPrereqs and not hasSuccessors then
          return { knownStatus = AQL.ChainStatus.NotAChain }
      end

      -- Find all root quests by walking backward.
      local roots = findRoots(questID)
      if #roots == 0 then
          return { knownStatus = AQL.ChainStatus.NotAChain }
      end

      -- Build a chain from each root. Skip chains that don't contain questID.
      local chains = {}
      local seenRoots = {}
      for _, root in ipairs(roots) do
          if not seenRoots[root] then
              seenRoots[root] = true
              local steps, questCount = buildChainFromRoot(root)
              if #steps >= 2 then
                  -- Find the step index for questID.
                  local stepNum = nil
                  for i, step in ipairs(steps) do
                      if step.questID == questID then
                          stepNum = i; break
                      elseif step.quests then
                          for _, sq in ipairs(step.quests) do
                              if sq.questID == questID then stepNum = i; break end
                          end
                          if stepNum then break end
                      end
                  end

                  if stepNum then
                      -- Annotate step statuses now that we have the full steps array.
                      for i, step in ipairs(steps) do
                          if step.questID then
                              step.status = classifyStatus(step.questID, i, steps)
                          elseif step.quests then
                              for _, sq in ipairs(step.quests) do
                                  sq.status = classifyStatus(sq.questID, i, steps)
                              end
                          end
                      end

                      chains[#chains + 1] = {
                          chainID    = root,
                          step       = stepNum,
                          length     = #steps,
                          questCount = questCount,
                          steps      = steps,
                          provider   = AQL.Provider.Grail,
                      }
                  end
              end
          end
      end

      if #chains == 0 then
          return { knownStatus = AQL.ChainStatus.NotAChain }
      end

      return {
          knownStatus = AQL.ChainStatus.Known,
          chains      = chains,
      }
  end

  AQL.GrailProvider = GrailProvider
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add Providers/GrailProvider.lua
  git commit -m "feat: add GrailProvider with Chain/QuestInfo/Requirements capabilities"
  ```

---

## Task 7: Register GrailProvider in All TOC Files

GrailProvider.lua must be added to all 5 TOC files after `BtWQuestsProvider.lua`.

**Files:**
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog.toc:26`
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog_TBC.toc`
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog_Classic.toc`
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog_Mists.toc`
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog_Mainline.toc`

- [ ] **Step 1: Add GrailProvider.lua to all TOC files**

  In each TOC file, after the line `Providers\BtWQuestsProvider.lua`, add:
  ```
  Providers\GrailProvider.lua
  ```

  Repeat for all 5 TOC files.

- [ ] **Step 2: Commit**

  ```bash
  git add AbsoluteQuestLog.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Mainline.toc
  git commit -m "build: add GrailProvider.lua to all TOC files"
  ```

---

## Task 8: SocialQuest Callsite Updates

Four files need updating. All callsites follow the same pattern: `chainInfo.step` and `chainInfo.knownStatus` now come from the result of `SelectBestChain`, not directly from the wrapper.

**Files:**
- Modify: `Social-Quest/Core/Announcements.lua:47-53` (appendChainStep)
- Modify: `Social-Quest/UI/RowFactory.lua:183-187` (chain step display)
- Modify: `Social-Quest/UI/TabUtils.lua:34-44` (GetChainInfoForQuestID)
- Modify: `Social-Quest/UI/Tabs/MineTab.lua:59-111` (chainInfo usage in BuildTree)
- Modify: `Social-Quest/UI/Tabs/MineTab.lua:103-111` (sort comparator)
- Modify: `Social-Quest/UI/Tabs/MineTab.lua:138-139` (ft.step filter)

- [ ] **Step 1: Update `appendChainStep` in Announcements.lua**

  `appendChainStep` currently accesses `chainInfo.step` directly. It must now call `SelectBestChain` first. All callers pass the current player's chain data (local events), so `_GetCurrentPlayerEngagedQuests()` is correct.

  ```lua
  -- BEFORE (lines 47-53):
  local function appendChainStep(msg, eventType, chainInfo)
      if not CHAIN_STEP_EVENTS[eventType] then return msg end
      if not chainInfo or chainInfo.knownStatus ~= SocialQuest.AQL.ChainStatus.Known or not chainInfo.step then
          return msg
      end
      return msg .. " " .. string.format(L["(Step %s)"], chainInfo.step)
  end

  -- AFTER:
  local function appendChainStep(msg, eventType, chainResult)
      if not CHAIN_STEP_EVENTS[eventType] then return msg end
      if not chainResult or chainResult.knownStatus ~= SocialQuest.AQL.ChainStatus.Known then
          return msg
      end
      local AQL = SocialQuest.AQL
      local engaged = AQL:_GetCurrentPlayerEngagedQuests()
      local ci = AQL:SelectBestChain(chainResult, engaged)
      if not ci or not ci.step then return msg end
      return msg .. " " .. string.format(L["(Step %s)"], ci.step)
  end
  ```

  The two callsites at lines 207 and 474 (`msg = appendChainStep(msg, eventType, chainInfo)`) and the callsite at line 537 (`msg = appendChainStep(msg, eventType, chainInfo)`) already pass the wrapper object — no change needed at those call sites.

- [ ] **Step 2: Update chain step display in RowFactory.lua**

  ```lua
  -- BEFORE (lines 183-187):
  local ci = questEntry.chainInfo
  if ci and ci.knownStatus == SocialQuest.AQL.ChainStatus.Known then
      titleText = titleText
          .. string.format(L[" (Step %s of %s)"], tostring(ci.step or "?"), tostring(ci.length or "?"))
  end

  -- AFTER:
  local chainResult = questEntry.chainInfo
  if chainResult and chainResult.knownStatus == SocialQuest.AQL.ChainStatus.Known then
      local AQL = SocialQuest.AQL
      local engaged = AQL:_GetCurrentPlayerEngagedQuests()
      local ci = AQL:SelectBestChain(chainResult, engaged)
      if ci then
          titleText = titleText
              .. string.format(L[" (Step %s of %s)"], tostring(ci.step or "?"), tostring(ci.length or "?"))
      end
  end
  ```

- [ ] **Step 3: Update `GetChainInfoForQuestID` in TabUtils.lua**

  This function queries `AQL:GetChainInfo` and falls back to calling the provider directly. After the change, `GetChainInfo` and the provider both return the wrapper — the function still returns the wrapper; callers must call `SelectBestChain` on the result.

  ```lua
  -- BEFORE (lines 34-44):
  function SocialQuestTabUtils.GetChainInfoForQuestID(questID)
      local AQL = SocialQuest.AQL
      local ci  = AQL:GetChainInfo(questID)
      if ci.knownStatus == AQL.ChainStatus.Known then return ci end
      local provider = AQL.provider
      if provider then
          local ok, result = pcall(provider.GetChainInfo, provider, questID)
          if ok and result and result.knownStatus == AQL.ChainStatus.Known then return result end
      end
      return ci
  end

  -- AFTER:
  -- Returns the GetChainInfo wrapper { knownStatus, chains } for questID.
  -- Queries AQL cache first; falls back to the active Chain provider for remote quests.
  -- Callers must use AQL:SelectBestChain(result, engagedSet) to pick a chain entry.
  function SocialQuestTabUtils.GetChainInfoForQuestID(questID)
      local AQL = SocialQuest.AQL
      local result = AQL:GetChainInfo(questID)
      if result.knownStatus == AQL.ChainStatus.Known then return result end
      local provider = AQL.providers and AQL.providers[AQL.Capability.Chain]
      if provider then
          local ok, provResult = pcall(provider.GetChainInfo, provider, questID)
          if ok and provResult and provResult.knownStatus == AQL.ChainStatus.Known then
              return provResult
          end
      end
      return result
  end
  ```

- [ ] **Step 4: Update chainInfo usage in MineTab.lua BuildTree**

  **4a.** The block at lines 59-99 uses `ci.chainID`, `ci.step`, and `pCI.chainID`/`pCI.step`:

  ```lua
  -- BEFORE (lines 59-99, condensed to show the relevant parts):
  local ci = questInfo.chainInfo
  if ci and ci.knownStatus == AQL.ChainStatus.Known and ci.chainID then
      local chainID = ci.chainID
      ...
      local pCI = SocialQuestTabUtils.GetChainInfoForQuestID(pQuestID)
      if pCI.knownStatus == AQL.ChainStatus.Known
          and pCI.chainID == chainID
          and pCI.step    ~= ci.step then
          table.insert(entry.players, {
              ...
              step        = pCI.step,
              chainLength = pCI.length,
          })
      end
  end

  -- AFTER:
  local chainResult = questInfo.chainInfo
  local engaged = AQL:_GetCurrentPlayerEngagedQuests()
  local ci = chainResult and chainResult.knownStatus == AQL.ChainStatus.Known
      and AQL:SelectBestChain(chainResult, engaged)
  if ci and ci.chainID then
      local chainID = ci.chainID
      ...
      for playerName, playerData in pairs(SocialQuestGroupData.PlayerQuests) do
          if playerData.quests then
              for pQuestID in pairs(playerData.quests) do
                  local pChainResult = SocialQuestTabUtils.GetChainInfoForQuestID(pQuestID)
                  -- Build the party member's engaged set from their data.
                  local pEngaged = {}
                  for aqid in pairs(playerData.completedQuests or {}) do pEngaged[aqid] = true end
                  for aqid in pairs(playerData.quests) do pEngaged[aqid] = true end
                  local pCI = AQL:SelectBestChain(pChainResult, pEngaged)
                  if pCI and pCI.chainID == chainID and pCI.step ~= ci.step then
                      table.insert(entry.players, {
                          name           = playerName,
                          isMe           = false,
                          hasSocialQuest = playerData.hasSocialQuest,
                          step           = pCI.step,
                          chainLength    = pCI.length,
                          objectives     = {},
                          isComplete     = playerData.quests[pQuestID] and
                                           playerData.quests[pQuestID].isComplete or false,
                          hasCompleted   = false,
                          needsShare     = false,
                          dataProvider   = playerData.dataProvider,
                      })
                  end
              end
          end
      end
  else
      table.insert(zone.quests, entry)
  end
  ```

  **4b.** The sort at lines 103-111 compares `a.chainInfo.step`:

  ```lua
  -- BEFORE (lines 103-111):
  table.sort(chain.steps, function(a, b)
      local aStep = a.chainInfo and a.chainInfo.step or 0
      local bStep = b.chainInfo and b.chainInfo.step or 0
      return aStep < bStep
  end)

  -- AFTER — compute engaged once, outside the sort:
  local sortEngaged = AQL:_GetCurrentPlayerEngagedQuests()
  for _, zone in pairs(tree.zones) do
      for _, chain in pairs(zone.chains) do
          table.sort(chain.steps, function(a, b)
              local aResult = a.chainInfo
              local bResult = b.chainInfo
              local aci = aResult and aResult.knownStatus == AQL.ChainStatus.Known
                  and AQL:SelectBestChain(aResult, sortEngaged)
              local bci = bResult and bResult.knownStatus == AQL.ChainStatus.Known
                  and AQL:SelectBestChain(bResult, sortEngaged)
              return (aci and aci.step or 0) < (bci and bci.step or 0)
          end)
      end
  end
  ```

  **4c.** The `ft.step` filter at lines 138-139 accesses `entry.chainInfo.step`:

  ```lua
  -- BEFORE (line 138-139):
  if ft.step   and not T.MatchesNumericFilter(
          entry.chainInfo and entry.chainInfo.step, ft.step)          then return false end

  -- AFTER — add above the ft.step check inside questPasses(), after other field extractions:
  -- Extract chainStep for the current player once per entry:
  local chainStep = nil
  if entry.chainInfo and entry.chainInfo.knownStatus == AQL.ChainStatus.Known then
      local stepEngaged = AQL:_GetCurrentPlayerEngagedQuests()
      local sci = AQL:SelectBestChain(entry.chainInfo, stepEngaged)
      chainStep = sci and sci.step
  end
  if ft.step   and not T.MatchesNumericFilter(chainStep, ft.step)     then return false end
  ```

- [ ] **Step 5: Run SocialQuest unit tests**

  ```bash
  cd "D:\Projects\Wow Addons\Social-Quest"
  lua tests/FilterParser_test.lua
  lua tests/TabUtils_test.lua
  ```

  Expected output: both print `0 failures` (or equivalent pass message). Fix any failures before continuing.

- [ ] **Step 6: Commit SocialQuest updates**

  ```bash
  cd "D:\Projects\Wow Addons\Social-Quest"
  git add Core/Announcements.lua UI/RowFactory.lua UI/TabUtils.lua UI/Tabs/MineTab.lua
  git commit -m "refactor: update chainInfo callsites for 3.0 wrapper format; use SelectBestChain"
  ```

---

## Task 9: Version Bump, Documentation, and Changelog

**Files:**
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog.toc` (and all multi-toc files) — version 3.0.0
- Modify: `Absolute-Quest-Log/CLAUDE.md` — updated ChainInfo structure, new API, version history
- Modify: `Absolute-Quest-Log/README.md` — breaking change section, new API docs
- Modify: `Absolute-Quest-Log/README.txt` — same as README.md
- Modify: `Absolute-Quest-Log/changelog.txt` — 3.0.0 entry

- [ ] **Step 1: Bump version to 3.0.0 in all TOC files**

  In all 5 TOC files (`AbsoluteQuestLog.toc`, `AbsoluteQuestLog_TBC.toc`, `AbsoluteQuestLog_Classic.toc`, `AbsoluteQuestLog_Mists.toc`, `AbsoluteQuestLog_Mainline.toc`), change:
  ```
  ## Version: 2.6.1
  ```
  to:
  ```
  ## Version: 3.0.0
  ```

- [ ] **Step 2: Update CLAUDE.md**

  **2a.** In the **ChainInfo Structure** section (under QuestInfo Data Structure), replace the existing code block with the new wrapper format:

  ```lua
  -- knownStatus = "known":
  {
      knownStatus = "known",
      chains = {
          {
              chainID    = N,        -- questID of chain root (first step)
              step       = N,        -- 1-based step-position of the queried quest
              length     = N,        -- total step-positions (a group counts as 1)
              questCount = N,        -- total individual quests across all steps
              steps      = {
                  -- Single-quest step (common case):
                  { questID = N, title = "string",
                    status = "completed"|"active"|"finished"|"failed"|"available"|"unavailable"|"unknown" },
                  -- Multi-quest step (parallel or branch):
                  {
                      quests = {
                          { questID = N, title = "string", status = "..." },
                          { questID = M, title = "string", status = "..." },
                      },
                      groupType = "parallel"|"branch"|"unknown",
                  },
              },
              provider   = "Grail"|"Questie"|"QuestWeaver"|"BtWQuests"|"none",
          },
          -- second entry only when quest belongs to multiple distinct chains
      }
  }
  -- knownStatus = "not_a_chain": only knownStatus field present
  -- knownStatus = "unknown": only knownStatus field present
  ```

  **2b.** In the **Provider Interface** section, update `GetChainInfo` return contract:

  ```
  - `Provider:GetChainInfo(questID)` → `{ knownStatus, chains }` wrapper (see ChainInfo Structure above)
  ```

  **2c.** In the **Chain Info** methods table (Public API section), update the Notes column for `GetChainInfo`:

  ```
  Returns wrapper `{ knownStatus, chains }`. Never nil. Use SelectBestChain to get a chain entry.
  ```

  Add new rows for `SelectBestChain` and the weekly type:

  | Method | Returns | Notes |
  |---|---|---|
  | `AQL:SelectBestChain(chainResult, engagedQuestIDs)` | chain entry or nil | Scores chains by overlap with engaged set; memoized. |

  **2d.** Update `AQL.QuestType` enum entry: add `Weekly = "weekly"`.

  **2e.** In the **Providers** table, add a row for GrailProvider:

  | `Providers\GrailProvider.lua` | `AQL.GrailProvider` | When Grail is installed. Last in all priority lists. Covers Classic/TBC/Wrath/MoP/Retail. |

  **2f.** Add version 3.0.0 entry to **Version History**:

  ```markdown
  ### Version 3.0.0 (March 2026)
  > **BREAKING CHANGE:** `AQL:GetChainInfo(questID)` now returns a wrapper object
  > `{ knownStatus, chains }` instead of a bare ChainInfo table. All callers must update.
  > `QuestInfo.chainInfo` field type changes accordingly. See Migration below.
  >
  > **Migration:**
  > ```lua
  > -- Before (2.x):
  > local ci = AQL:GetChainInfo(questID)
  > if ci.knownStatus == AQL.ChainStatus.Known then
  >     show(ci.step, ci.length)
  > end
  > -- After (3.0):
  > local result = AQL:GetChainInfo(questID)
  > if result.knownStatus == AQL.ChainStatus.Known then
  >     local ci = AQL:SelectBestChain(result, engagedSet)
  >     if ci then show(ci.step, ci.length) end
  > end
  > ```
  - New: `GrailProvider` — quest chain, basic info, and requirements from the Grail addon.
    Covers all WoW versions where Grail is installed (Classic Era, TBC, Wrath, MoP, Retail).
    Chain info is reverse-engineered from `Grail.questPrerequisites` via a lazy reverse map
    built on first `GetChainInfo` call. Last in all three provider priority lists.
  - New: `AQL:SelectBestChain(chainResult, engagedQuestIDs)` — player-agnostic best-chain
    selector. Pass any `{ [questID] = true }` set (current player or party member) to pick
    the chain entry with the most overlap. Memoized by (chainID, count:xor:sum fingerprint).
    Cache cleared by EventEngine on quest state changes.
  - New: `AQL.QuestType.Weekly = "weekly"` — reported by GrailProvider for weekly quests.
  - New: `AQL.Provider.Grail = "Grail"` — enum entry used in chain `provider` field.
  - Breaking: `GetChainInfo` return shape changed from bare ChainInfo to wrapper. See above.
  - Breaking: `QuestInfo.chainInfo` now holds wrapper object (not bare ChainInfo).
  - Updated: `GetChainStep` / `GetChainLength` use `SelectBestChain` internally.
  - Multi-quest steps now supported in chain format (duck-typed `step.quests` array with
    `groupType = "parallel"|"branch"|"unknown"`). Produced by GrailProvider when Grail data
    shows branching prerequisites.
  ```

- [ ] **Step 3: Update README.md**

  Add a **Breaking Changes in 3.0.0** section near the top of the changelog / release notes section:

  ```markdown
  ## Breaking Changes in 3.0.0

  ### `GetChainInfo` Return Type Changed

  `AQL:GetChainInfo(questID)` now returns a **wrapper object** instead of a bare ChainInfo table.

  **Before (2.x):**
  ```lua
  local ci = AQL:GetChainInfo(questID)
  if ci.knownStatus == AQL.ChainStatus.Known then
      print("Step " .. ci.step .. " of " .. ci.length)
  end
  ```

  **After (3.0):**
  ```lua
  local result = AQL:GetChainInfo(questID)
  if result.knownStatus == AQL.ChainStatus.Known then
      -- For current player:
      local ci = AQL:SelectBestChain(result, AQL:_GetCurrentPlayerEngagedQuests())
      -- For a party member (SocialQuest pattern):
      -- local ci = AQL:SelectBestChain(result, memberCompletedQuestIDs)
      if ci then
          print("Step " .. ci.step .. " of " .. ci.length)
      end
  end
  ```

  The wrapper shape:
  ```lua
  -- Quest in a chain:
  { knownStatus = "known", chains = { { chainID, step, length, questCount, steps, provider }, ... } }
  -- Quest not in a chain:
  { knownStatus = "not_a_chain" }
  -- Unknown:
  { knownStatus = "unknown" }
  ```

  `QuestInfo.chainInfo` (on cached quest entries) now holds this wrapper object.

  ### New: `AQL:SelectBestChain(chainResult, engagedQuestIDs)`

  Picks the best-fit chain entry for a given player's engaged quest set. Scores by counting
  how many chain member quests appear in the engaged set. Memoized.

  ```lua
  -- Current player:
  local engaged = AQL:_GetCurrentPlayerEngagedQuests()
  local chain = AQL:SelectBestChain(result, engaged)

  -- Party member (from SocialQuest GroupData):
  local memberEngaged = {}
  for qid in pairs(member.completedQuests or {}) do memberEngaged[qid] = true end
  for qid in pairs(member.quests or {}) do memberEngaged[qid] = true end
  local chain = AQL:SelectBestChain(result, memberEngaged)
  ```

  ### New Quest Type: `AQL.QuestType.Weekly = "weekly"`

  Reported by GrailProvider for weekly quests. Additive — no existing callers are affected unless
  they enumerate all possible type values.
  ```

  Also update the **Providers** section to list GrailProvider, and update the `GetChainInfo` entry in the API reference table.

- [ ] **Step 4: Update README.txt**

  Apply the same breaking changes content as README.md. README.txt uses plain text formatting (no Markdown rendering), so replace code blocks with indented text and strip Markdown decorators (`##`, backticks, etc.).

- [ ] **Step 5: Update changelog.txt**

  Prepend a 3.0.0 entry at the top of `changelog.txt`:

  ```
  Version 3.0.0 (March 2026)
  ==========================
  BREAKING CHANGES
  ----------------
  - GetChainInfo return type: AQL:GetChainInfo(questID) now returns
    { knownStatus, chains={...} } wrapper instead of a bare ChainInfo.
    All callers must update. Use AQL:SelectBestChain(result, engagedSet)
    to extract a chain entry. See README.md for full migration guide.
  - QuestInfo.chainInfo field now holds the wrapper object (not bare ChainInfo).

  New Features
  ------------
  - GrailProvider: quest chain, basic info, and requirements from the Grail addon.
    Last in all three provider priority lists. Covers all WoW version families.
  - AQL:SelectBestChain(chainResult, engagedQuestIDs) — player-agnostic chain
    selector. Pass any {[questID]=true} set; returns best-fit chain entry. Memoized.
  - AQL.QuestType.Weekly = "weekly" — weekly quest type (GrailProvider).
  - AQL.Provider.Grail = "Grail" — enum for GrailProvider chain entries.
  - Multi-quest steps in chain format: { quests={...}, groupType="parallel"|"branch"|"unknown" }.
    Produced by GrailProvider for branching prerequisite paths.

  Updated
  -------
  - GetChainStep / GetChainLength use SelectBestChain internally for current player.
  - EventEngine clears SelectBestChain cache on QUEST_ACCEPTED, QUEST_REMOVED,
    QUEST_TURNED_IN so stale chain scoring is never served.
  ```

- [ ] **Step 6: Commit everything**

  ```bash
  cd "D:\Projects\Wow Addons\Absolute-Quest-Log"
  git add AbsoluteQuestLog.toc AbsoluteQuestLog_TBC.toc AbsoluteQuestLog_Classic.toc AbsoluteQuestLog_Mists.toc AbsoluteQuestLog_Mainline.toc
  git add CLAUDE.md README.md README.txt changelog.txt
  git commit -m "docs: 3.0.0 — breaking GetChainInfo change, GrailProvider, SelectBestChain"
  ```

---

## Self-Review Checklist

- **Spec coverage:**
  1. ChainInfo wrapper structure — Tasks 2, 3, 4 ✓
  2. Multi-quest step format — GrailProvider (Task 6) builds steps with `quests` arrays ✓
  3. `SelectBestChain` — Task 3 ✓
  4. `AQL.QuestType.Weekly` — Task 1 ✓
  5. `AQL.Provider.Grail` — Task 1 ✓
  6. `GrailProvider.lua` — Task 6 ✓
  7. Existing providers wrap return — Task 2 ✓
  8. QuestCache / AbsoluteQuestLog.lua internal updates — Tasks 3, 4 ✓ (QuestCache needs no change per spec §6)
  9. EventEngine priority lists — Task 5 ✓
  10. SocialQuest callsites — Task 8 ✓
  11. README.md, README.txt — Task 9 ✓
  12. CLAUDE.md — Task 9 ✓
  13. changelog.txt — Task 9 ✓

- **Type consistency:** All chain entry accesses (`ci.step`, `ci.length`, `ci.chainID`) come from the result of `SelectBestChain`, which returns a chain entry table. Wrapper accesses (`result.knownStatus`, `result.chains`) are from `GetChainInfo` return. No mixing.

- **`questCount` field:** Added to all three wrapped providers as `questCount = length` (correct for linear chains where each step has one quest). GrailProvider tracks `questCount` independently during `buildChainFromRoot` (increments for each quest in multi-quest steps).

- **`_GetCurrentPlayerEngagedQuests` is private:** Documented with underscore prefix. Not in the Public API table (only in the private helpers section).

- **`_ClearChainSelectionCache` is private:** Called only by EventEngine; not exposed in public API docs.

- **No placeholder text present in this plan.**
