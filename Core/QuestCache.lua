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
    local originalSelection = GetQuestLogSelection()

    -- Phase 1: Collect collapsed zone headers.
    if AQL.debug == "verbose" then
        print(AQL.DBG .. "[AQL] QuestCache: phase 1 — collecting collapsed headers" .. AQL.RESET)
    end
    local collapsedHeaders = {}
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, _, _, isHeader, isCollapsed = GetQuestLogTitle(i)
        if title and isHeader and isCollapsed then
            table.insert(collapsedHeaders, { index = i, title = title })
        end
    end

    if AQL.debug == "verbose" then
        print(AQL.DBG .. "[AQL] QuestCache: phase 1 — " .. tostring(#collapsedHeaders) ..
              " collapsed headers found" .. AQL.RESET)
    end
    -- Phase 2: Expand collapsed headers back-to-front to preserve earlier indices.
    if AQL.debug == "verbose" then
        print(AQL.DBG .. "[AQL] QuestCache: phase 2 — expanding headers" .. AQL.RESET)
    end
    for k = #collapsedHeaders, 1, -1 do
        ExpandQuestHeader(collapsedHeaders[k].index)
    end

    -- Phase 3: Full rebuild — all quests now visible.
    if AQL.debug == "verbose" then
        print(AQL.DBG .. "[AQL] QuestCache: phase 3 — building entries" .. AQL.RESET)
    end
    numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        -- TBC 20505: C_QuestLog.GetInfo() does not exist; use GetQuestLogTitle() global.
        -- Returns: title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
        --          frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI,
        --          isTask, isBounty, isStory, isHidden, isScaling
        local title, level, suggestedGroup, isHeader, _, isComplete, _, questID =
            GetQuestLogTitle(i)
        if title then
            local info = {
                title          = title,
                level          = level,
                suggestedGroup = suggestedGroup,  -- nil-safe: _buildEntry applies or 0 fallback
                isHeader       = isHeader,
                isComplete     = isComplete,
                questID        = questID,
            }
            if info.isHeader then
                currentZone = info.title
            else
                -- Wrap each entry build in pcall so one bad entry never aborts the loop.
                local ok, entryOrErr = pcall(self._buildEntry, self, questID, info, currentZone, i)
                if ok and entryOrErr then
                    new[questID] = entryOrErr
                elseif not ok and AQL.debug then
                    print(AQL.RED .. "[AQL] QuestCache: error building entry for questID "
                        .. tostring(questID) .. ": " .. tostring(entryOrErr) .. AQL.RESET)
                end
            end
        end
    end

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
        for _, h in ipairs(collapsedHeaders) do
            collapsedTitles[h.title] = true
        end
        local toCollapse = {}
        numEntries = GetNumQuestLogEntries()
        for i = 1, numEntries do
            local title, _, _, isHeader = GetQuestLogTitle(i)
            if title and isHeader and collapsedTitles[title] then
                table.insert(toCollapse, i)
            end
        end
        -- Collapse back-to-front to preserve earlier indices.
        for k = #toCollapse, 1, -1 do
            CollapseQuestHeader(toCollapse[k])
        end
    end

    -- Phase 5: Restore quest log selection.
    if AQL.debug == "verbose" then
        print(AQL.DBG .. "[AQL] QuestCache: phase 5 — restoring selection" .. AQL.RESET)
    end
    SelectQuestLogEntry(originalSelection or 0)

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

    -- Timer: requires selecting the quest log entry.
    -- SelectQuestLogEntry briefly changes quest log UI selection; this is safe
    -- to do during cache rebuild since it is instantaneous and non-destructive.
    SelectQuestLogEntry(logIndex)
    local rawTimer = GetQuestLogTimeLeft()
    local timerSeconds = (rawTimer and rawTimer > 0) and rawTimer or nil

    -- Quest link: prefer the WoW native API; construct manually if it returns nil
    -- so every QuestCache entry has a valid hyperlink regardless of client version.
    local link = GetQuestLink(logIndex)
    if not link then
        link = string.format("|cFFFFD200|Hquest:%d:%d|h[%s]|h|r",
            questID, info.level or 0, info.title or ("Quest " .. questID))
    end

    -- isTracked: IsQuestWatched takes a quest log index.
    local isTracked = IsQuestWatched(logIndex) == true

    -- Objectives.
    -- C_QuestLog.GetQuestObjectives returns per-objective: text, type, finished,
    -- numFulfilled, numRequired. `name` is parsed from text by stripping the
    -- count suffix (e.g. "Tainted Ooze killed: 4/10" → name = "Tainted Ooze killed").
    -- For event/log types with no count, name equals the full text.
    local objectives = {}
    local rawObjs = C_QuestLog.GetQuestObjectives(questID)
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

    -- Provider data (chain/type/faction).
    -- AQL.provider may be nil during the very first Rebuild before EventEngine
    -- has run provider selection. Nil-guard here; the next rebuild after
    -- PLAYER_LOGIN will have a provider set.
    local chainInfo = { knownStatus = "unknown" }
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
