-- Core/HistoryCache.lua
-- Tracks quests completed at any point in this character's history.
-- Initial data comes from GetQuestsCompleted() (requires async query).
-- Subsequent completions are recorded via HistoryCache:MarkCompleted().

local AQL = LibStub("AbsoluteQuestLog-1.0", true)
if not AQL then return end

local HistoryCache = {}
AQL.HistoryCache = HistoryCache

-- completed[questID] = true for every quest ever turned in.
 HistoryCache.completed = {}
HistoryCache.count = 0

-- Called by EventEngine at PLAYER_LOGIN.
-- GetQuestsCompleted() is synchronous in TBC Classic; no async query needed.
function HistoryCache:Load()
    local data = GetQuestsCompleted()
    local count = 0
    for questID, done in pairs(data) do
        if done then
            self.completed[questID] = true
            count = count + 1
        end
    end
    self.count = count
end

-- Called by EventEngine when it detects a quest turn-in (AQL_QUEST_COMPLETED).
function HistoryCache:MarkCompleted(questID)
    if not self.completed[questID] then
        self.completed[questID] = true
        self.count = self.count + 1
    end
end

function HistoryCache:HasCompleted(questID)
    return self.completed[questID] == true
end

function HistoryCache:GetAll()
    return self.completed
end

function HistoryCache:GetCount()
    return self.count
end
