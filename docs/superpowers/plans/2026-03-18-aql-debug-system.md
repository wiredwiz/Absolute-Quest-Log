# AQL Debug System — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/aql` slash command that toggles two-level debug logging (normal / verbose) with gold-colored output to the default chat frame.

**Architecture:** Three files modified — `AbsoluteQuestLog.lua` gets the `AQL.DBG` constant and slash command; `Core/EventEngine.lua` gets normal + verbose prints throughout; `Core/QuestCache.lua` gets phase markers and per-entry prints. `AQL.debug` is a string sentinel (`nil` / `"normal"` / `"verbose"`); nil is falsy so all existing `if AQL.debug then` checks in both files remain valid without change.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary (Interface 20505). No automated test framework — verification is manual, in-game. All edits are exact Find/Replace against the current file content.

---

## Chunk 1: All three files

### Task 1: AbsoluteQuestLog.lua — `AQL.DBG` constant and `/aql` slash command

**Files:**
- Modify: `Absolute-Quest-Log/AbsoluteQuestLog.lua`

**Background:** `AbsoluteQuestLog.lua` currently defines `AQL.RED` and `AQL.RESET` at lines 13–14 and ends at line 232 (`AQL:IsUnitOnQuest`). We add `AQL.DBG` after `AQL.RESET`, then append the slash command block after all public API methods. Slash command registration uses vanilla WoW globals (`SLASH_X1` / `SlashCmdList`), not AceAddon — this does not affect how WoW categorizes the library.

- [ ] **Step 1: Add `AQL.DBG` color constant**

  Find:
  ```lua
  AQL.RED   = "|cffff0000"
  AQL.RESET = "|r"
  ```
  Replace with:
  ```lua
  AQL.RED   = "|cffff0000"
  AQL.RESET = "|r"
  AQL.DBG   = "|cFFFFD200"   -- gold (colorblind-safe, distinct from errors and chat text)
  ```

- [ ] **Step 2: Append slash command block at end of file**

  Find (the last two functions of the file):
  ```lua
  -- Untracks a quest by questID. Always delegates; no cap check needed.
  function AQL:UntrackQuest(questID)
      WowQuestAPI.UntrackQuest(questID)
  end

  -- Returns bool on Retail (UnitIsOnQuest exists), nil on TBC/Classic.
  function AQL:IsUnitOnQuest(questID, unit)
      return WowQuestAPI.IsUnitOnQuest(questID, unit)
  end
  ```
  Replace with:
  ```lua
  -- Untracks a quest by questID. Always delegates; no cap check needed.
  function AQL:UntrackQuest(questID)
      WowQuestAPI.UntrackQuest(questID)
  end

  -- Returns bool on Retail (UnitIsOnQuest exists), nil on TBC/Classic.
  function AQL:IsUnitOnQuest(questID, unit)
      return WowQuestAPI.IsUnitOnQuest(questID, unit)
  end

  ------------------------------------------------------------------------
  -- Slash command
  ------------------------------------------------------------------------

  SLASH_ABSOLUTEQUESTLOG1 = "/aql"
  SlashCmdList["ABSOLUTEQUESTLOG"] = function(input)
      local cmd = strtrim(input or ""):lower()
      if cmd == "on" or cmd == "normal" then
          AQL.debug = "normal"
          print(AQL.DBG .. "[AQL] Debug mode: normal" .. AQL.RESET)
      elseif cmd == "verbose" then
          AQL.debug = "verbose"
          print(AQL.DBG .. "[AQL] Debug mode: verbose" .. AQL.RESET)
      elseif cmd == "off" then
          AQL.debug = nil
          print(AQL.DBG .. "[AQL] Debug mode: off" .. AQL.RESET)
      else
          print(AQL.DBG .. "[AQL] Usage: /aql [on|normal|verbose|off]" .. AQL.RESET)
      end
  end
  ```

- [ ] **Step 3: Verify the edit**

  Read back `AbsoluteQuestLog.lua` lines 1–20 and confirm `AQL.DBG` is on line 16 and the two lines before it are `AQL.RED` and `AQL.RESET` (spacing preserved).

  Read back the last 30 lines and confirm:
  - `SLASH_ABSOLUTEQUESTLOG1 = "/aql"` is present
  - `SlashCmdList["ABSOLUTEQUESTLOG"]` handler covers `on`, `normal`, `verbose`, `off`, and the else usage line
  - All four branches use `AQL.DBG .. "..." .. AQL.RESET`

- [ ] **Step 4: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
  git add AbsoluteQuestLog.lua
  git commit -m "feat: add AQL.DBG gold color constant and /aql debug slash command

  Adds AQL.DBG = \"|cFFFFD200\" (gold) alongside AQL.RED/AQL.RESET.
  Registers /aql [on|normal|verbose|off] using vanilla WoW SlashCmdList.
  Sets AQL.debug to nil/\"normal\"/\"verbose\" — session-only, no persistence.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 2: Core/EventEngine.lua — debug prints throughout

**Files:**
- Modify: `Absolute-Quest-Log/Core/EventEngine.lua`

**Background:** All edits are in file order (top to bottom). The file has no test runner; verify each edit by reading back the modified section. The key structural changes are: (1) `tryUpgradeProvider` — capture `providerName` from `selectProvider()` for logging; (2) `handleQuestLogUpdate` — same for the inline belt-and-suspenders provider upgrade, plus verbose initialized-guard; (3) `runDiff` — re-entrancy guard gets a verbose print, entry/exit get verbose prints, all callback sites get normal-level prints; (4) `OnEvent` handler — event print at the very top + provider-selected print in the PLAYER_LOGIN branch.

**Normal-level guard:** `if AQL.debug then`
**Verbose-level guard:** `if AQL.debug == "verbose" then`

- [ ] **Step 1: `hooksecurefunc("GetQuestReward")` — pendingTurnIn set debug**

  Find:
  ```lua
  hooksecurefunc("GetQuestReward", function()
      local questID = GetQuestID()
      if questID and questID ~= 0 then
          EventEngine.pendingTurnIn[questID] = true
      end
  end)
  ```
  Replace with:
  ```lua
  hooksecurefunc("GetQuestReward", function()
      local questID = GetQuestID()
      if questID and questID ~= 0 then
          EventEngine.pendingTurnIn[questID] = true
          if AQL.debug then
              print(AQL.DBG .. "[AQL] pendingTurnIn set: questID=" .. tostring(questID) .. AQL.RESET)
          end
      end
  end)
  ```

- [ ] **Step 2: `tryUpgradeProvider` — capture `providerName`, add debug prints**

  Find:
  ```lua
  -- providerName (second return of selectProvider) is intentionally discarded;
  -- it is not stored on AQL anywhere in this file.
  local function tryUpgradeProvider(attemptsLeft)
      if AQL.provider ~= AQL.NullProvider then return end  -- already upgraded

      local provider = selectProvider()
      if provider ~= AQL.NullProvider then
          AQL.provider = provider
          AQL.QuestCache:Rebuild()
          return
      end

      if attemptsLeft > 0 then
          C_Timer.After(1, function() tryUpgradeProvider(attemptsLeft - 1) end)
      end
  end
  ```
  Replace with:
  ```lua
  local function tryUpgradeProvider(attemptsLeft)
      if AQL.provider ~= AQL.NullProvider then return end  -- already upgraded

      local provider, providerName = selectProvider()
      if provider ~= AQL.NullProvider then
          AQL.provider = provider
          if AQL.debug then
              print(AQL.DBG .. "[AQL] Provider upgraded: " .. tostring(providerName) .. AQL.RESET)
          end
          AQL.QuestCache:Rebuild()
          return
      end

      if attemptsLeft > 0 then
          if AQL.debug then
              print(AQL.DBG .. "[AQL] Provider upgrade attempt " ..
                    tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS - attemptsLeft + 1) ..
                    "/" .. tostring(MAX_DEFERRED_UPGRADE_ATTEMPTS) ..
                    " — still on NullProvider" .. AQL.RESET)
          end
          C_Timer.After(1, function() tryUpgradeProvider(attemptsLeft - 1) end)
      end
  end
  ```

- [ ] **Step 3: `runDiff` — re-entrancy guard (verbose) + entry print (verbose)**

  Find:
  ```lua
  local function runDiff(oldCache)
      if EventEngine.diffInProgress then return end
      EventEngine.diffInProgress = true
  ```
  Replace with:
  ```lua
  local function runDiff(oldCache)
      if EventEngine.diffInProgress then
          if AQL.debug == "verbose" then
              print(AQL.DBG .. "[AQL] runDiff: skipped (already in progress)" .. AQL.RESET)
          end
          return
      end
      EventEngine.diffInProgress = true
      if AQL.debug == "verbose" then
          local oldCount, newCount = 0, 0
          for _ in pairs(oldCache) do oldCount = oldCount + 1 end
          for _ in pairs(AQL.QuestCache.data) do newCount = newCount + 1 end
          print(AQL.DBG .. "[AQL] runDiff: start — old=" .. tostring(oldCount) ..
                " new=" .. tostring(newCount) .. " quests" .. AQL.RESET)
      end
  ```

- [ ] **Step 4: `runDiff` — quest accepted print**

  Find:
  ```lua
              else
                      AQL.callbacks:Fire("AQL_QUEST_ACCEPTED", newInfo)
                  end
  ```

  That context may not be unique enough. Use the wider block:

  Find:
  ```lua
          for questID, newInfo in pairs(newCache) do
              if not oldCache[questID] then
                  if histCache and histCache:HasCompleted(questID) then
                      -- Quest was already completed historically; ignore as a new accept.
                      -- (Can happen at login when cache first builds.)
                  else
                      AQL.callbacks:Fire("AQL_QUEST_ACCEPTED", newInfo)
                  end
              end
          end
  ```
  Replace with:
  ```lua
          for questID, newInfo in pairs(newCache) do
              if not oldCache[questID] then
                  if histCache and histCache:HasCompleted(questID) then
                      -- Quest was already completed historically; ignore as a new accept.
                      -- (Can happen at login when cache first builds.)
                  else
                      AQL.callbacks:Fire("AQL_QUEST_ACCEPTED", newInfo)
                      if AQL.debug then
                          print(AQL.DBG .. "[AQL] Quest accepted: " .. tostring(questID) ..
                                " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                      end
                  end
              end
          end
  ```

- [ ] **Step 5: `runDiff` — pendingTurnIn cleared print**

  Find:
  ```lua
              if not newCache[questID] then
                  -- Quest was removed from the log.
                  EventEngine.pendingTurnIn[questID] = nil
                  if (histCache and histCache:HasCompleted(questID))
  ```
  Replace with:
  ```lua
              if not newCache[questID] then
                  -- Quest was removed from the log.
                  EventEngine.pendingTurnIn[questID] = nil
                  if AQL.debug then
                      print(AQL.DBG .. "[AQL] pendingTurnIn cleared: questID=" .. tostring(questID) .. AQL.RESET)
                  end
                  if (histCache and histCache:HasCompleted(questID))
  ```

- [ ] **Step 6: `runDiff` — quest completed print**

  Find:
  ```lua
                      if histCache then histCache:MarkCompleted(questID) end
                      AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
                  else
  ```
  Replace with:
  ```lua
                      if histCache then histCache:MarkCompleted(questID) end
                      AQL.callbacks:Fire("AQL_QUEST_COMPLETED", oldInfo)
                      if AQL.debug then
                          print(AQL.DBG .. "[AQL] Quest completed: " .. tostring(questID) ..
                                " \"" .. tostring(oldInfo.title) .. "\"" .. AQL.RESET)
                      end
                  else
  ```

- [ ] **Step 7: `runDiff` — quest failed (removed-quest branch) + objective failed loop**

  Find:
  ```lua
                  if failReason then
                      oldInfo.isFailed   = true
                      oldInfo.failReason = failReason
                      AQL.callbacks:Fire("AQL_QUEST_FAILED", oldInfo)
                      for _, obj in ipairs(oldInfo.objectives or {}) do
                          if not obj.isFinished then
                              obj.isFailed = true
                              AQL.callbacks:Fire("AQL_OBJECTIVE_FAILED", oldInfo, obj)
                          end
                      end
                  else
  ```
  Replace with:
  ```lua
                  if failReason then
                      oldInfo.isFailed   = true
                      oldInfo.failReason = failReason
                      AQL.callbacks:Fire("AQL_QUEST_FAILED", oldInfo)
                      if AQL.debug then
                          print(AQL.DBG .. "[AQL] Quest failed: " .. tostring(questID) ..
                                " \"" .. tostring(oldInfo.title) .. "\" reason=" .. tostring(failReason) .. AQL.RESET)
                      end
                      for _, obj in ipairs(oldInfo.objectives or {}) do
                          if not obj.isFinished then
                              obj.isFailed = true
                              AQL.callbacks:Fire("AQL_OBJECTIVE_FAILED", oldInfo, obj)
                              if AQL.debug then
                                  print(AQL.DBG .. "[AQL] Objective failed: " .. tostring(questID) ..
                                        " \"" .. tostring(obj.text or "") .. "\"" .. AQL.RESET)
                              end
                          end
                      end
                  else
  ```

- [ ] **Step 8: `runDiff` — quest abandoned print**

  Find (read `Core/EventEngine.lua` lines 162–171 to confirm exact indentation before applying):
  ```lua
                    else
                        AQL.callbacks:Fire("AQL_QUEST_ABANDONED", oldInfo)
                    end
                end
            end
        end

        -- Detect changes in existing quests.
  ```
  Replace with:
  ```lua
                    else
                        AQL.callbacks:Fire("AQL_QUEST_ABANDONED", oldInfo)
                        if AQL.debug then
                            print(AQL.DBG .. "[AQL] Quest abandoned: " .. tostring(questID) ..
                                  " \"" .. tostring(oldInfo.title) .. "\"" .. AQL.RESET)
                        end
                    end
                end
            end
        end

        -- Detect changes in existing quests.
  ```

- [ ] **Step 9: `runDiff` — quest finished + isFailed transition (existing quests) + objective failed**

  Find:
  ```lua
                  -- isComplete transition.
                  if newInfo.isComplete and not oldInfo.isComplete then
                      AQL.callbacks:Fire("AQL_QUEST_FINISHED", newInfo)
                  end

                  -- isFailed transition: quest newly failed.
                  if newInfo.isFailed and not oldInfo.isFailed then
                      AQL.callbacks:Fire("AQL_QUEST_FAILED", newInfo)
                      -- Fire AQL_OBJECTIVE_FAILED for every unfinished objective
                      -- (the quest failing marks all incomplete objectives as failed).
                      for _, obj in ipairs(newInfo.objectives or {}) do
                          if not obj.isFinished then
                              -- Mark isFailed on the objective in the live snapshot.
                              obj.isFailed = true
                              AQL.callbacks:Fire("AQL_OBJECTIVE_FAILED", newInfo, obj)
                          end
                      end
                  end
  ```
  Replace with:
  ```lua
                  -- isComplete transition.
                  if newInfo.isComplete and not oldInfo.isComplete then
                      AQL.callbacks:Fire("AQL_QUEST_FINISHED", newInfo)
                      if AQL.debug then
                          print(AQL.DBG .. "[AQL] Quest finished (ready to turn in): " .. tostring(questID) ..
                                " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                      end
                  end

                  -- isFailed transition: quest newly failed.
                  if newInfo.isFailed and not oldInfo.isFailed then
                      AQL.callbacks:Fire("AQL_QUEST_FAILED", newInfo)
                      if AQL.debug then
                          print(AQL.DBG .. "[AQL] Quest failed (isFailed): " .. tostring(questID) ..
                                " \"" .. tostring(newInfo.title) .. "\"" ..
                                (newInfo.failReason and (" reason=" .. tostring(newInfo.failReason)) or "") .. AQL.RESET)
                      end
                      -- Fire AQL_OBJECTIVE_FAILED for every unfinished objective
                      -- (the quest failing marks all incomplete objectives as failed).
                      for _, obj in ipairs(newInfo.objectives or {}) do
                          if not obj.isFinished then
                              -- Mark isFailed on the objective in the live snapshot.
                              obj.isFailed = true
                              AQL.callbacks:Fire("AQL_OBJECTIVE_FAILED", newInfo, obj)
                              if AQL.debug then
                                  print(AQL.DBG .. "[AQL] Objective failed: " .. tostring(questID) ..
                                        " \"" .. tostring(obj.text or "") .. "\"" .. AQL.RESET)
                              end
                          end
                      end
                  end
  ```

- [ ] **Step 10: `runDiff` — isTracked transitions (verbose)**

  Find:
  ```lua
                  -- isTracked transition.
                  if newInfo.isTracked ~= oldInfo.isTracked then
                      if newInfo.isTracked then
                          AQL.callbacks:Fire("AQL_QUEST_TRACKED", newInfo)
                      else
                          AQL.callbacks:Fire("AQL_QUEST_UNTRACKED", newInfo)
                      end
                  end
  ```
  Replace with:
  ```lua
                  -- isTracked transition.
                  if newInfo.isTracked ~= oldInfo.isTracked then
                      if newInfo.isTracked then
                          AQL.callbacks:Fire("AQL_QUEST_TRACKED", newInfo)
                          if AQL.debug == "verbose" then
                              print(AQL.DBG .. "[AQL] Quest tracked: " .. tostring(questID) ..
                                    " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                          end
                      else
                          AQL.callbacks:Fire("AQL_QUEST_UNTRACKED", newInfo)
                          if AQL.debug == "verbose" then
                              print(AQL.DBG .. "[AQL] Quest untracked: " .. tostring(questID) ..
                                    " \"" .. tostring(newInfo.title) .. "\"" .. AQL.RESET)
                          end
                      end
                  end
  ```

- [ ] **Step 11: `runDiff` — objective progressed, completed, regressed, suppressed**

  Find:
  ```lua
                      if newN > oldN then
                          local delta = newN - oldN
                          AQL.callbacks:Fire("AQL_OBJECTIVE_PROGRESSED", newInfo, newObj, delta)
                          -- Also fire COMPLETED if this progression crossed the threshold.
                          if newN >= newObj.numRequired and oldN < newObj.numRequired then
                              AQL.callbacks:Fire("AQL_OBJECTIVE_COMPLETED", newInfo, newObj)
                          end
                      elseif newN < oldN then
                          -- Suppress regression during turn-in window: objective drop
                          -- is the NPC taking items, not a genuine regression.
                          if not EventEngine.pendingTurnIn[questID] then
                              local delta = oldN - newN
                              AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)
                          end
                      end
  ```
  Replace with:
  ```lua
                      if newN > oldN then
                          local delta = newN - oldN
                          AQL.callbacks:Fire("AQL_OBJECTIVE_PROGRESSED", newInfo, newObj, delta)
                          if AQL.debug then
                              print(AQL.DBG .. "[AQL] Objective progressed: " .. tostring(questID) ..
                                    " obj[" .. tostring(i) .. "] " ..
                                    tostring(newObj.numFulfilled) .. "/" .. tostring(newObj.numRequired) .. AQL.RESET)
                          end
                          -- Also fire COMPLETED if this progression crossed the threshold.
                          if newN >= newObj.numRequired and oldN < newObj.numRequired then
                              AQL.callbacks:Fire("AQL_OBJECTIVE_COMPLETED", newInfo, newObj)
                              if AQL.debug then
                                  print(AQL.DBG .. "[AQL] Objective completed: " .. tostring(questID) ..
                                        " obj[" .. tostring(i) .. "]" .. AQL.RESET)
                              end
                          end
                      elseif newN < oldN then
                          -- Suppress regression during turn-in window: objective drop
                          -- is the NPC taking items, not a genuine regression.
                          if not EventEngine.pendingTurnIn[questID] then
                              local delta = oldN - newN
                              AQL.callbacks:Fire("AQL_OBJECTIVE_REGRESSED", newInfo, newObj, delta)
                              if AQL.debug then
                                  print(AQL.DBG .. "[AQL] Objective regressed: " .. tostring(questID) ..
                                        " obj[" .. tostring(i) .. "] " ..
                                        tostring(newObj.numFulfilled) .. "/" .. tostring(newObj.numRequired) .. AQL.RESET)
                              end
                          else
                              if AQL.debug then
                                  print(AQL.DBG .. "[AQL] Objective regression suppressed (pendingTurnIn): " ..
                                        tostring(questID) .. " obj[" .. tostring(i) .. "]" .. AQL.RESET)
                              end
                          end
                      end
  ```

- [ ] **Step 12: `runDiff` — exit print (verbose, before `diffInProgress = false`)**

  Find:
  ```lua
      EventEngine.diffInProgress = false

      if not ok then
  ```
  Replace with:
  ```lua
      if AQL.debug == "verbose" then
          print(AQL.DBG .. "[AQL] runDiff: done" .. AQL.RESET)
      end
      EventEngine.diffInProgress = false

      if not ok then
  ```

- [ ] **Step 13: `handleQuestLogUpdate` — initialized guard (verbose) + inline provider upgrade**

  Find:
  ```lua
  local function handleQuestLogUpdate()
      if not EventEngine.initialized then return end

      -- Belt-and-suspenders: re-attempt provider selection if still on NullProvider.
      -- tryUpgradeProvider handles the common case via C_Timer; this is a fallback
      -- in case the upgrade window was missed. One comparison per rebuild — no cost.
      -- providerName (second return of selectProvider) is intentionally discarded.
      if AQL.provider == AQL.NullProvider then
          local provider = selectProvider()
          if provider ~= AQL.NullProvider then
              AQL.provider = provider
          end
      end
  ```
  Replace with:
  ```lua
  local function handleQuestLogUpdate()
      if not EventEngine.initialized then
          if AQL.debug == "verbose" then
              print(AQL.DBG .. "[AQL] Event received before init, skipping" .. AQL.RESET)
          end
          return
      end

      -- Belt-and-suspenders: re-attempt provider selection if still on NullProvider.
      -- tryUpgradeProvider handles the common case via C_Timer; this is a fallback
      -- in case the upgrade window was missed. One comparison per rebuild — no cost.
      if AQL.provider == AQL.NullProvider then
          local provider, providerName = selectProvider()
          if provider ~= AQL.NullProvider then
              AQL.provider = provider
              if AQL.debug then
                  print(AQL.DBG .. "[AQL] Provider upgraded (inline): " .. tostring(providerName) .. AQL.RESET)
              end
          end
      end
  ```

- [ ] **Step 14: OnEvent handler — event print at top + provider selected print**

  Find:
  ```lua
  frame:SetScript("OnEvent", function(self, event, ...)
      if event == "PLAYER_LOGIN" then
          -- Select the best available provider.
          local provider, providerName = selectProvider()
          AQL.provider = provider
  ```
  Replace with:
  ```lua
  frame:SetScript("OnEvent", function(self, event, ...)
      if AQL.debug then
          print(AQL.DBG .. "[AQL] Event: " .. tostring(event) .. AQL.RESET)
      end
      if event == "PLAYER_LOGIN" then
          -- Select the best available provider.
          local provider, providerName = selectProvider()
          AQL.provider = provider
          if AQL.debug then
              print(AQL.DBG .. "[AQL] Provider selected: " .. tostring(providerName) .. AQL.RESET)
          end
  ```

- [ ] **Step 15: Verify the edit**

  Read back the following sections and confirm each block is correct:
  - Lines 40–50: `hooksecurefunc` — `pendingTurnIn set` print inside the `questID ~= 0` guard
  - Lines 85–100: `tryUpgradeProvider` — `providerName` captured, upgrade and retry prints present, old "intentionally discarded" comment removed
  - Lines 104–112: `runDiff` opening — re-entrancy verbose guard then `diffInProgress = true` then verbose entry print
  - Lines 229–240: `runDiff` close — verbose "done" print immediately before `diffInProgress = false`
  - Lines 241–260: `handleQuestLogUpdate` — verbose initialized-guard, `providerName` captured inline, upgrade print present, old comment removed
  - Lines 265–285: OnEvent handler — event print at very top, provider-selected print after `AQL.provider = provider`

- [ ] **Step 16: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
  git add Core/EventEngine.lua
  git commit -m "feat: add debug logging throughout EventEngine

  Normal level: events received, provider selection/upgrade, pendingTurnIn
  set/cleared, all quest lifecycle transitions (accepted/completed/failed/
  abandoned/finished), all objective transitions (progressed/completed/
  regressed/suppressed), objective failed.
  Verbose level: runDiff entry/exit/skipped, initialized guard skip, isTracked
  transitions, inline provider upgrade path.
  Also captures providerName in tryUpgradeProvider and handleQuestLogUpdate
  inline upgrade so it is available for logging.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 3: Core/QuestCache.lua — phase markers and per-entry detail

**Files:**
- Modify: `Absolute-Quest-Log/Core/QuestCache.lua`

**Background:** `QuestCache:Rebuild()` has five explicitly commented phases. The verbose prints go at the start of each phase (Phase 4's print is inside the `if #collapsedHeaders > 0 then` guard since Phase 4 only runs when headers need recollapsing). The normal-level rebuild-count print goes after the Phase 3 loop, before Phase 4. The verbose per-entry print goes in `_buildEntry`, just before the `return { ... }` statement.

- [ ] **Step 1: Phase 1 start verbose print**

  Find:
  ```lua
      -- Phase 1: Collect collapsed zone headers.
      local collapsedHeaders = {}
      local numEntries = GetNumQuestLogEntries()
  ```
  Replace with:
  ```lua
      -- Phase 1: Collect collapsed zone headers.
      if AQL.debug == "verbose" then
          print(AQL.DBG .. "[AQL] QuestCache: phase 1 — collecting collapsed headers" .. AQL.RESET)
      end
      local collapsedHeaders = {}
      local numEntries = GetNumQuestLogEntries()
  ```

- [ ] **Step 2: Phase 1 count + Phase 2 start verbose prints**

  Find:
  ```lua
      -- Phase 2: Expand collapsed headers back-to-front to preserve earlier indices.
      for k = #collapsedHeaders, 1, -1 do
  ```
  Replace with:
  ```lua
      if AQL.debug == "verbose" then
          print(AQL.DBG .. "[AQL] QuestCache: phase 1 — " .. tostring(#collapsedHeaders) ..
                " collapsed headers found" .. AQL.RESET)
      end
      -- Phase 2: Expand collapsed headers back-to-front to preserve earlier indices.
      if AQL.debug == "verbose" then
          print(AQL.DBG .. "[AQL] QuestCache: phase 2 — expanding headers" .. AQL.RESET)
      end
      for k = #collapsedHeaders, 1, -1 do
  ```

- [ ] **Step 3: Phase 3 start verbose print**

  Find:
  ```lua
      -- Phase 3: Full rebuild — all quests now visible.
      numEntries = GetNumQuestLogEntries()
  ```
  Replace with:
  ```lua
      -- Phase 3: Full rebuild — all quests now visible.
      if AQL.debug == "verbose" then
          print(AQL.DBG .. "[AQL] QuestCache: phase 3 — building entries" .. AQL.RESET)
      end
      numEntries = GetNumQuestLogEntries()
  ```

- [ ] **Step 4: Normal-level rebuild count + Phase 4 start verbose print**

  Find:
  ```lua
      -- Phase 4: Re-collapse headers that were collapsed before rebuild.
      if #collapsedHeaders > 0 then
          local collapsedTitles = {}
  ```
  Replace with:
  ```lua
      if AQL.debug then
          local count = 0
          for _ in pairs(new) do count = count + 1 end
          print(AQL.DBG .. "[AQL] QuestCache rebuilt: " .. tostring(count) .. " quests" .. AQL.RESET)
      end
      -- Phase 4: Re-collapse headers that were collapsed before rebuild.
      if #collapsedHeaders > 0 then
          if AQL.debug == "verbose" then
              print(AQL.DBG .. "[AQL] QuestCache: phase 4 — re-collapsing headers" .. AQL.RESET)
          end
          local collapsedTitles = {}
  ```

- [ ] **Step 5: Phase 5 start verbose print**

  Find:
  ```lua
      -- Phase 5: Restore quest log selection.
      SelectQuestLogEntry(originalSelection or 0)
  ```
  Replace with:
  ```lua
      -- Phase 5: Restore quest log selection.
      if AQL.debug == "verbose" then
          print(AQL.DBG .. "[AQL] QuestCache: phase 5 — restoring selection" .. AQL.RESET)
      end
      SelectQuestLogEntry(originalSelection or 0)
  ```

- [ ] **Step 6: `_buildEntry` per-entry verbose detail**

  Find:
  ```lua
      return {
          questID        = questID,
          title          = info.title or "",
  ```
  Replace with:
  ```lua
      if AQL.debug == "verbose" then
          local objCount = 0
          for _ in ipairs(objectives) do objCount = objCount + 1 end
          print(AQL.DBG .. "[AQL] QuestCache: built questID=" .. tostring(questID) ..
                " \"" .. tostring(info.title or "") .. "\"" ..
                " zone=\"" .. tostring(zone or "") .. "\"" ..
                " objs=" .. tostring(objCount) .. AQL.RESET)
      end
      return {
          questID        = questID,
          title          = info.title or "",
  ```

- [ ] **Step 7: Verify the edit**

  Read back `Core/QuestCache.lua` lines 18–98 (`Rebuild` function) and confirm:
  - Phase 1 verbose print is the first statement inside `Rebuild()`, before `local collapsedHeaders`
  - Phase 1 count verbose print appears just before the Phase 2 comment
  - Phase 2 verbose print appears between the Phase 2 comment and the `for k = #collapsedHeaders` loop
  - Phase 3 verbose print appears just before `numEntries = GetNumQuestLogEntries()` (the second assignment)
  - Normal-level count block (with `for _ in pairs(new)`) appears before the Phase 4 comment
  - Phase 4 verbose print appears as the first statement inside `if #collapsedHeaders > 0 then`
  - Phase 5 verbose print appears just before `SelectQuestLogEntry(originalSelection or 0)`

  Read back `Core/QuestCache.lua` lines 160–185 (`_buildEntry` return section) and confirm:
  - Verbose per-entry print block is immediately before `return {`
  - The block uses `for _ in ipairs(objectives) do objCount = objCount + 1 end`

- [ ] **Step 8: Commit**

  ```bash
  cd "D:/Projects/Wow Addons/Absolute-Quest-Log"
  git add Core/QuestCache.lua
  git commit -m "feat: add debug logging throughout QuestCache

  Normal level: rebuild summary (quest count) after Phase 3.
  Verbose level: per-phase markers (phases 1-5) with Phase 1 collapsed-
  header count and Phase 4 conditional on #collapsedHeaders > 0.
  Verbose level: per-entry build detail in _buildEntry (questID, title,
  zone, objective count) immediately before the return statement.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 4: In-Game Verification

Reload the WoW client. Run each test with debug active:

- [ ] **Test 1 — Slash command basics**
  - `/aql on` → gold `[AQL] Debug mode: normal` in chat
  - `/aql verbose` → gold `[AQL] Debug mode: verbose`
  - `/aql off` → gold `[AQL] Debug mode: off`, then NO further `[AQL]` output
  - `/aql` (no args) → gold `[AQL] Usage: /aql [on|normal|verbose|off]`

- [ ] **Test 2 — Normal mode: accept a quest**
  Turn on `/aql on`. Accept any quest. Confirm:
  - `[AQL] Event: QUEST_ACCEPTED` appears
  - `[AQL] Quest accepted: <id> "<title>"` appears

- [ ] **Test 3 — Normal mode: complete a quest (turn in)**
  Complete objectives and turn in a quest. Confirm:
  - `[AQL] pendingTurnIn set: questID=<id>` appears on turn-in click
  - `[AQL] Quest completed: <id> "<title>"` appears
  - No `Quest abandoned` or `Objective regressed` lines for this turn-in

- [ ] **Test 4 — Normal mode: abandon a quest**
  Accept a quest, then abandon it. Confirm `[AQL] Quest abandoned: <id> "<title>"` and no `Completed` line.

- [ ] **Test 5 — Normal mode: objective progress**
  Accept a kill or collect quest. Kill one enemy / collect one item. Confirm `[AQL] Objective progressed: <id> obj[1] <n>/<max>` appears.

- [ ] **Test 6 — Verbose mode: reload UI**
  Turn on `/aql verbose`, then `/reload`. Confirm in chat:
  - `[AQL] Provider selected: <name>` fires during login
  - Phase markers appear: `phase 1`, `phase 2`, `phase 3`, `phase 4` (if any zones collapsed), `phase 5`
  - `[AQL] QuestCache rebuilt: <N> quests` appears
  - Per-entry lines `[AQL] QuestCache: built questID=...` appear for each quest

- [ ] **Test 7 — Verbose mode: any quest event**
  In verbose mode, trigger any event (e.g., pick up an item that updates a quest objective). Confirm:
  - `[AQL] runDiff: start — old=<N> new=<M> quests` appears
  - `[AQL] runDiff: done` appears

- [ ] **Test 8 — Verbose mode: track/untrack a quest**
  In verbose mode, track a quest via the Quest Log, then untrack it. Confirm `[AQL] Quest tracked:` and `[AQL] Quest untracked:` lines appear.

---

*Spec: `Absolute-Quest-Log/docs/superpowers/specs/2026-03-18-aql-debug-system.md`*
