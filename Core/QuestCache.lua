-- Core/QuestCache.lua
-- Builds and stores QuestInfo snapshots from C_QuestLog.
-- QuestCache:Rebuild() is called by EventEngine on each relevant WoW event.
-- Returns the previous snapshot so EventEngine can diff old vs. new.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local QuestCache = {}
AQL.QuestCache = QuestCache

-- data[questID] = QuestInfo table (see spec for full field list)
QuestCache.data = {}


-- Rebuild the entire cache from C_QuestLog.
-- Returns the previous cache table so callers can diff.
function QuestCache:Rebuild()
    local new = {}
    local currentZone = nil
    local originalSelection = WowQuestAPI.GetQuestLogSelection()

    -- Phase 1: Collect collapsed zone headers.
    if AQL.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] QuestCache: phase 1 — collecting collapsed headers" .. AQL.RESET)
    end
    local collapsedHeaders = {}
    local numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, isCollapsed = WowQuestAPI.GetQuestLogTitle(i)
        if title and isHeader and isCollapsed then
            table.insert(collapsedHeaders, { index = i, title = title })
        end
    end

    if AQL.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] QuestCache: phase 1 — " .. tostring(#collapsedHeaders) ..
              " collapsed headers found" .. AQL.RESET)
    end
    -- Phase 2: Expand collapsed headers back-to-front to preserve earlier indices.
    if AQL.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] QuestCache: phase 2 — expanding headers" .. AQL.RESET)
    end
    for k = #collapsedHeaders, 1, -1 do
        WowQuestAPI.ExpandQuestHeader(collapsedHeaders[k].index)
    end

    -- Phase 3: Full rebuild — all quests now visible.
    if AQL.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] QuestCache: phase 3 — building entries" .. AQL.RESET)
    end
    numEntries = WowQuestAPI.GetNumQuestLogEntries()
    for i = 1, numEntries do
        -- GetQuestLogInfo normalizes Classic/TBC/MoP positional returns and Retail
        -- C_QuestLog.GetInfo() table into a single consistent table.
        -- Returns nil for a malformed/out-of-range entry — skip (do not break).
        -- Loop termination is controlled by the numEntries bound above.
        local info = WowQuestAPI.GetQuestLogInfo(i)
        if not info then
            -- skip this entry; do not break — a nil mid-log entry should not
            -- cut off all subsequent quests from the cache rebuild
        else
            local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, questID =
                info.title, info.level, info.suggestedGroup, info.isHeader,
                info.isCollapsed, info.isComplete, info.questID
            if info.isHeader then
                currentZone = info.title
            else
                -- Wrap each entry build in pcall so one bad entry never aborts the loop.
                local ok, entryOrErr = pcall(self._buildEntry, self, questID, info, currentZone, i)
                if ok and entryOrErr then
                    new[questID] = entryOrErr
                elseif not ok and AQL.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(AQL.RED .. "[AQL] QuestCache: error building entry for questID "
                        .. tostring(questID) .. ": " .. tostring(entryOrErr) .. AQL.RESET)
                end
            end
        end
    end

    if AQL.debug then
        local count = 0
        for _ in pairs(new) do count = count + 1 end
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] QuestCache rebuilt: " .. tostring(count) .. " quests" .. AQL.RESET)
    end
    -- Phase 4: Re-collapse headers that were collapsed before rebuild.
    if #collapsedHeaders > 0 then
        if AQL.debug == "verbose" then
            DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] QuestCache: phase 4 — re-collapsing headers" .. AQL.RESET)
        end
        local collapsedTitles = {}
        for _, h in ipairs(collapsedHeaders) do
            collapsedTitles[h.title] = true
        end
        local toCollapse = {}
        numEntries = WowQuestAPI.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local title, _, _, isHeader = WowQuestAPI.GetQuestLogTitle(i)
            if title and isHeader and collapsedTitles[title] then
                table.insert(toCollapse, i)
            end
        end
        -- Collapse back-to-front to preserve earlier indices.
        for k = #toCollapse, 1, -1 do
            WowQuestAPI.CollapseQuestHeader(toCollapse[k])
        end
    end

    -- Phase 5: Restore quest log selection.
    if AQL.debug == "verbose" then
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] QuestCache: phase 5 — restoring selection" .. AQL.RESET)
    end
    WowQuestAPI.SelectQuestLogEntry(originalSelection or 0)

    local old = self.data
    self.data = new
    return old
end

function QuestCache:_buildEntry(questID, info, zone, logIndex)
    -- isComplete: C_QuestLog.GetInfo returns isComplete as 1 (done, not yet turned in)
    -- or false/nil if not complete.
    local isComplete = (info.isComplete == 1 or info.isComplete == true)
    -- isFailed and failReason are set by EventEngine's diff when the quest
    -- disappears from the log. Snapshots of live quests are always not-failed.
    local isFailed   = false
    local failReason = nil

    -- Timer: legacy path selects the entry then reads GetQuestLogTimeLeft().
    -- On Retail, C_QuestLog.SetSelectedQuest fires QUEST_LOG_UPDATE which would
    -- cause a rebuild loop; GetQuestTimerByIndex skips the call on Retail.
    local timerSeconds = WowQuestAPI.GetQuestTimerByIndex(logIndex)

    -- Quest link: prefer the WoW native API; construct manually if it returns nil
    -- so every QuestCache entry has a valid hyperlink regardless of client version.
    local link = WowQuestAPI.GetQuestLinkByIndex(logIndex)
    if not link then
        link = string.format("|cFFFFD200|Hquest:%d:%d|h[%s]|h|r",
            questID, info.level or 0, info.title or ("Quest " .. questID))
    end

    -- isTracked: IsQuestWatched takes a quest log index.
    local isTracked = WowQuestAPI.IsQuestWatchedByIndex(logIndex)

    -- Objectives.
    -- C_QuestLog.GetQuestObjectives returns per-objective: text, type, finished,
    -- numFulfilled, numRequired. `name` is parsed from text by stripping the
    -- count suffix (e.g. "Tainted Ooze killed: 4/10" → name = "Tainted Ooze killed").
    -- For event/log types with no count, name equals the full text.
    local objectives = {}
    local rawObjs = WowQuestAPI.GetQuestObjectives(questID)
    if rawObjs then
        for idx, obj in ipairs(rawObjs) do
            local text = obj.text or ""
            local name = text:match("^(.-):%s*%d+/%d+%s*$") or text
            objectives[idx] = {
                index        = idx,
                text         = text,
                type         = obj.type or "log",
                name         = name,
                numFulfilled = obj.numFulfilled or 0,
                numRequired  = obj.numRequired or 1,
                isFinished   = obj.finished == true,
                isFailed     = false,
            }
        end
    end

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

    if AQL.debug == "verbose" then
        local objCount = 0
        for _ in ipairs(objectives) do objCount = objCount + 1 end
        DEFAULT_CHAT_FRAME:AddMessage(AQL.DBG .. "[AQL] QuestCache: built questID=" .. tostring(questID) ..
              " \"" .. tostring(info.title or "") .. "\"" ..
              " zone=\"" .. tostring(zone or "") .. "\"" ..
              " objs=" .. tostring(objCount) .. AQL.RESET)
    end
    return {
        questID        = questID,
        title          = info.title or "",
        level          = info.level or 0,
        suggestedGroup = tonumber(info.suggestedGroup) or 0,
        zone           = zone,
        type           = questType,
        faction        = questFaction,
        isComplete     = isComplete,
        isFailed       = isFailed,
        failReason     = failReason,
        isTracked      = isTracked,
        link           = link,
        logIndex       = logIndex,
        snapshotTime   = GetTime(),
        timerSeconds   = timerSeconds,
        objectives     = objectives,
        chainInfo      = chainInfo,
    }
end

function QuestCache:Get(questID)
    return self.data[questID]
end

function QuestCache:GetAll()
    return self.data
end
