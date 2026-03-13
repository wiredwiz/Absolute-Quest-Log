-- Core/QuestCache.lua
-- Builds and stores QuestInfo snapshots from C_QuestLog.
-- QuestCache:Rebuild() is called by EventEngine on each relevant WoW event.
-- Returns the previous snapshot so EventEngine can diff old vs. new.

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local WOWHEAD_QUEST_BASE = "https://www.wowhead.com/tbc/quest="

local QuestCache = {}
AQL.QuestCache = QuestCache

-- data[questID] = QuestInfo table (see spec for full field list)
QuestCache.data = {}


-- Rebuild the entire cache from C_QuestLog.
-- Returns the previous cache table so callers can diff.
function QuestCache:Rebuild()
    local new = {}
    local numEntries = GetNumQuestLogEntries()  -- TBC 20505: global, returns numEntries, numQuests
    local currentZone = nil

    -- Build a logIndex-by-questID map during iteration (needed for timer queries).
    local logIndexByQuestID = {}

    -- Preserve the player's current quest log selection.
    -- _buildEntry calls SelectQuestLogEntry() to read timer data; without this
    -- the player's selected entry would silently shift to the last processed quest.
    local originalSelection = GetQuestLogSelection()

    for i = 1, numEntries do
        -- TBC 20505: C_QuestLog.GetInfo() does not exist; use GetQuestLogTitle() global.
        -- Returns: title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
        --          frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI,
        --          isTask, isBounty, isStory, isHidden, isScaling
        local title, level, suggestedGroup, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
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
                logIndexByQuestID[questID] = i
                -- Wrap each entry build in pcall so one bad entry never aborts the loop.
                local ok, entryOrErr = pcall(self._buildEntry, self, questID, info, currentZone, i)
                if ok and entryOrErr then
                    new[questID] = entryOrErr
                elseif not ok and AQL.debug then
                    print(AQL.RED .. "[AQL] QuestCache: error building entry for questID " .. tostring(questID) .. ": " .. tostring(entryOrErr) .. AQL.RESET)
                end
            end
        end
    end

    SelectQuestLogEntry(originalSelection or 0)  -- restore player's selection

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

    -- Quest link.
    local link = GetQuestLink(logIndex)

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
        wowheadUrl     = WOWHEAD_QUEST_BASE .. tostring(questID),
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
