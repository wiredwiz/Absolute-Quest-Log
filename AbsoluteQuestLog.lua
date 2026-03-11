AbsoluteQuestLog = LibStub("AceAddon-3.0"):NewAddon("AbsoluteQuestLog","AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0");

local defaults = {};
defaults.char = {};
defaults.char.debug = {};
defaults.char.debug.enabled = false;
defaults.char.debug.announce = {	accept = true,
									abandon = true,
									finish = true,
									complete = true,
									progress = true,
									fail = true,
									tracked = true,
									not_tracked = true
								};
defaults.char.history = {};
defaults.global = {};
defaults.global.history = {};
defaults.char.hasScannedCompletedQuests = false;

--[[
--  Much of the code that follows here is based on and borrowed largely from the Sea library.  All of these instances are noted
--	so as to be explicitly clear.  All of those who worked on the Sea.wow.questlog library deserve a lot of credit because without
--  that work I would probably still be fighting with the questlog api's.  I wrestled a lot as to whether I should incorporate modified versions
--  of some of the questlog code or simply try to do my best to support Sea with updates that I felt were beneficial.  In the end I decided
--  to do both, yeah I'm a bit of a control freak at times and I like to be able to fix code the minute I see a bug.  So anyway, props to
--  all those who have come before me and laid such strong foundations in the addon community, you guys rock.
--  - Mathaius@Kirin Tor
]]--


	--	AbsoluteQuestLog.Quests = A table of entries where each entry is a quest in the player's quest log.  Each of these entries is keyed
	--					  by the quest's cleanTitle
	--
	--	{
	--		{
	--			id - (string) id when fully expanded  {{ this field is largely unused but kept for those who might use it }}
	--			uniqueID - (number) unique numeric id of the quest (according to Blizzard)
	--			title - (string) quest title
	--			cleanTitle - (string) quest title with any [] style level indicators removed
	--			level - (number) quest level
	--			tag - (string) Elite or Raid
	--			link - (string) in game link to quest
	--			tracked - (number) is quest being tracked
	--          groupNum - (number) Number of recommended party members
	--			complete - (number) is quest completed (1 = complete, -1 = fail, nil otherwise)
	--			zone - (string) collapsable header name
	--          daily - (boolean) is daily quest
	--			failed - (boolean) - has quest failed?
	--			pushable - (boolean) - is quest shareable?
	--			timer - (number)
	--			description - full description text (string)
	--			objective - objective text (string)
	--			requiredMoney - (number) Money required
	--			rewardMoney - (number) Money reward
	--			objectives - objective status (table)
	--				{
	--					text - description (string)
	--					questType - monster, reputation, item or log (string)
	--					finished - (boolean)
	--					info - status information (table)
	--					{
	--						name 	- monster/item/faction name
	--						done 	- number - number obtained or killed
	--								- string - faction achieved
	--						total 	- number - amount needed
	--								- string - faction required
	--					}
	--				}
	--			choices - choices of items (table)
	--				{
	--					name - item name
	--					texture - item texture
	--					numItems - count of items (number)
	--					quality - item quality (number)
	--					isUsable - (boolean)
	--					info - link information (table)
	--						{
	--							color - color string (string)
	--							link - item link (string)
	--							linkname - [Item of Power] (string)
	--						}
	--				}
	--			rewards - items always recieved (table)
	--				{
	--					name - item name
	--					texture - item texture
	--					numItems - count of items (number)
	--					quality - item quality (number)
	--					isUsable - (boolean)
	--					info - link information (table)
	--						{
	--							color - color string (string)
	--							link - item link (string)
	--							linkname - [Item of Power] (string)
	--						}
	--				}
	--			spellReward - the spell given to you after the quest (table)
	--				{
	--					name - spell name (string)
	--					texture - spell texture (string)
	--				}
	--		}
	--	}
	--
	--	AbsoluteQuestLog.QuestsByUniqueID =	A table of entries keyed by a quest's uniqueID that has the value of the index used in AbsoluteQuestLog.Quests
	--										to retreive the entry for the specified quest
	--	{
	--		uniqueID - quest's index name (string)
	--	}
	
AQ_VERSION="1.00";

AbsoluteQuestLog.Quests = {};
AbsoluteQuestLog.QuestsByUniqueID = {};
AbsoluteQuestLog.NumHeaders = 0;
AbsoluteQuestLog.NumQuests = 0;
AbsoluteQuestLog.Abandoned = false;
AbsoluteQuestLog.Completed = false;
AbsoluteQuestLog.Initialized = false;

-- NOTE: The Quest progress updated event does not fire if that progress update finishes the quest.  In that case the Quest finished event fires
-- instead
-- e.g. if you had to kill 12 kobold vermin as the quest objective, when you kill the 12th one, a quest progress update event does not fire
AbsoluteQuestLog.AQ_QUEST_COMPLETED = "AQ_QUEST_COMPLETED";
AbsoluteQuestLog.AQ_QUEST_PROGRESS_UPDATED = "AQ_QUEST_PROGRESS_UPDATED";
AbsoluteQuestLog.AQ_QUEST_ABANDONED = "AQ_QUEST_ABANDONED";
AbsoluteQuestLog.AQ_QUEST_ACCEPTED = "AQ_QUEST_ACCEPTED";
AbsoluteQuestLog.AQ_QUEST_FAILED = "AQ_QUEST_FAILED";
AbsoluteQuestLog.AQ_QUEST_FINISHED = "AQ_QUEST_FINISHED";
AbsoluteQuestLog.AQ_QUEST_TRACKED = "AQ_QUEST_TRACKED";
AbsoluteQuestLog.AQ_QUEST_NOT_TRACKED = "AQ_QUEST_NOT_TRACKED";

local ProtectionData = {};

--[[
--	Copied from Sea.wow.questLog
--		Modified by Mathaius
--
--]]

-- Protect this function to prevent outside calling without protecting quest log.
local function _getPlayerQuestData( id )
	if ( not id ) then
		return nil;
	end
	
	local questInfo = {};

	-- Select it
	SelectQuestLogEntry(id);

	questInfo.id = id;
	questInfo.title, questInfo.level, questInfo.tag = GetQuestLogTitle(id);
	questInfo.failed = IsCurrentQuestFailed();
	questInfo.description, questInfo.objective = GetQuestLogQuestText();
	questInfo.pushable = GetQuestLogPushable();
	questInfo.timer = GetQuestLogTimeLeft();
	questInfo.link = GetQuestLink(id);
	questInfo.uniqueID = AbsoluteQuestLog:GetUniqueIDFromLink(questInfo.link);
	questInfo.tracked = IsQuestWatched(id);

	questInfo.objectives = {};

	for i=1, GetNumQuestLeaderBoards(), 1 do
		local item = {};

		item.text, item.questType, item.finished = GetQuestLogLeaderBoard(i);

		local itemGlobal,objectGlobal,monsterGlobal,factionGlobal = QUEST_ITEMS_NEEDED,QUEST_OBJECTS_FOUND,QUEST_MONSTERS_KILLED,QUEST_FACTION_NEEDED;
		QUEST_ITEMS_NEEDED = "%s:%d/%d";
		QUEST_OBJECTS_FOUND = QUEST_ITEMS_NEEDED;
		QUEST_MONSTERS_KILLED = QUEST_ITEMS_NEEDED;
		QUEST_FACTION_NEEDED = "%s:%s/%s";
		local info;
		if ( item.questType == "item" or item.questType == "object" or item.questType == "monster" ) then
			info = {string.match(GetQuestLogLeaderBoard(i),"(.+):(%d+)/(%d+)")};
			
			item.info = {};
			item.info.name = info[1];
			item.info.done = tonumber(info[2]);
			item.info.total = tonumber(info[3]);
		elseif ( item.questType == "reputation" ) then
			info = {string.match(GetQuestLogLeaderBoard(i),"(.+):(.+)/(.+)")};
			
			item.info = {};
			item.info.name = info[1];
			item.info.done = info[2];
			item.info.total = info[3];
		else -- questType of type "event", "log" and any other new ones
			item.info = {};
			item.info.name = "";
			if (item.finished) then 
				item.info.done = 1;
			else
				item.info.done = 0;
			end
			item.info.total = 1;
		end
		QUEST_ITEMS_NEEDED,QUEST_OBJECTS_FOUND,QUEST_MONSTERS_KILLED,QUEST_FACTION_NEEDED = itemGlobal,objectGlobal,monsterGlobal,factionGlobal;
		table.insert(questInfo.objectives, item);
	end

	if ( GetQuestLogRequiredMoney() > 0 ) then
		questInfo.requiredMoney = GetQuestLogRequiredMoney();
	end
	questInfo.rewardMoney = GetQuestLogRewardMoney();

	questInfo.rewards = {};
	questInfo.choices = {};

	for i=1, GetNumQuestLogChoices(), 1 do
		local item = {};
		item.name, item.texture, item.numItems, item.quality, item.isUsable = GetQuestLogChoiceInfo(i);

		local info = GetQuestLogItemLink("choice", i );
		if ( info ) then
			item.info = {};
			item.info.color = string.gsub(info, "|c(.*)|H(.*)|h(.*)|h|r.*", "%1");
			item.info.link = string.gsub(info, "|c(.*)|H(.*)|h(.*)|h|r.*", "%2");
			item.info.linkname = string.gsub(info, "|c(.*)|H(.*)|h(.*)|h|r.*", "%3");
		end
		table.insert(questInfo.choices, item);
	end
	for i=1, GetNumQuestLogRewards(), 1 do
		local item = {};
		item.name, item.texture, item.numItems, item.quality, item.isUsable = GetQuestLogRewardInfo(i);

		local info = GetQuestLogItemLink("reward", i );
		if ( info ) then
			item.info = {};
			item.info.color = string.gsub(info, "|c(.*)|H(.*)|h(.*)|h|r.*", "%1");
			item.info.link = string.gsub(info, "|c(.*)|H(.*)|h(.*)|h|r.*", "%2");
			item.info.linkname = string.gsub(info, "|c(.*)|H(.*)|h(.*)|h|r.*", "%3");
		end

		table.insert(questInfo.rewards, item);
	end

	if ( GetRewardSpell() or GetQuestLogRewardSpell() ) then
		questInfo.spellReward={};
		if ( GetRewardSpell() ) then
			questInfo.spellReward.texture, questInfo.spellReward.name = GetRewardSpell();
		else
			questInfo.spellReward.texture, questInfo.spellReward.name = GetQuestLogRewardSpell();
		end
	end

	return questInfo;
end


--  COPIED from Sea.wow.questlog - I DID NOT WRITE THIS, The developers of the Sea library deserve the credit for this function
--
--	storeCollapsedQuests
--
--	 Stores the currently collapsed quests and returns them
--
-- Returns:
-- 	(table quests)
-- 	quests - a list containing the title of the collapsed quests
--
local function storeCollapsedQuests()
	local collapsed = {};
	for i=1, MAX_QUESTLOG_QUESTS do
		local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i);
		if ( isCollapsed ) then
			table.insert(collapsed, title);
		end
	end

	return collapsed;
end;

--  COPIED from Sea.wow.questlog - I DID NOT WRITE THIS, The developers of the Sea library deserve the credit for this function
--
--	collapseStoredQuests (collapseTitles)
--		Collapses all quests whose titles are in the list
--
-- Args:
--	(table collapseTitles)
--	collapseTitles - the titles which will be collapsed
--
-- Returns:
-- 	nil
--
local function collapseStoredQuests(collapseThese)
	for i=1, MAX_QUESTLOG_QUESTS do
		local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i);
		if ( Sea.list.isInList(collapseThese, title) ) then
			CollapseQuestHeader(i);
		end
	end
end;


--  COPIED from Sea.wow.questlog - I DID NOT WRITE THIS, The developers of the Sea library deserve the credit for this function
--
-- 	protectQuestLog()
-- 		Preserves the quest log state.
-- 		Don't forget to call unprotectQuestLog()
-- 		after modifying the log.
--
--		This will return false if someone else
--		has protected the quest log and
--		not unprotected it yet.
--
--	Args:
--		none
--	Returns:
--		true - the log was protected
--		false - someone else is modifying the log now
--
local function protectQuestLog()
	if ( ProtectionData.protected ) then
		return nil;
	end

	-- Store the protected state
	ProtectionData.protected = true;

	-- Store the event
	ProtectionData.ql_OnEvent = QuestLog_OnEvent;
	QuestLog_OnEvent = function() end;

	-- Store the collapsed
	ProtectionData.collapsed = storeCollapsedQuests();

	-- Store the selection
	ProtectionData.savedID = GetQuestLogSelection();

	-- Store the scroll bar position
	--ProtectionData.savedScrollBar = FauxScrollFrame_GetOffset(QuestLogListScrollFrame);
	--ProtectionData.savedValue = QuestLogListScrollFrameScrollBar:GetValue()

	-- Expand everything if there is anything collapse
	-- Expanding triggers a QUEST_LOG_UPDATE event so only do it if really necessary.
	if #(ProtectionData.collapsed) > 0 then
		ExpandQuestHeader(0);
	end

	return true;
end;

--  COPIED from Sea.wow.questlog - I DID NOT WRITE THIS, The developers of the Sea library deserve the credit for this function
--
--	unprotectQuestLog()
--		Restores the state of the quest log.
--		Useful if you're going to mess with the
--		quest log in order to get info out, and
--		don't want the user to notice.
--
--	Args:
--		none
--	Returns:
--		nil
--
local function unprotectQuestLog()
	-- Collapse again
	collapseStoredQuests(ProtectionData.collapsed);

	-- Restore the scroll bar position
	--FauxScrollFrame_SetOffset(QuestLogListScrollFrame,ProtectionData.savedScrollBar);
	--QuestLogListScrollFrameScrollBar:SetValue(ProtectionData.savedValue);
	
	-- Restore the selection
	SelectQuestLogEntry(ProtectionData.savedID);

	-- Restore the event
	QuestLog_OnEvent = ProtectionData.ql_OnEvent;
	ProtectionData.ql_OnEvent = nil;

	-- Unprotect
	ProtectionData.protected = false;
end;

--  COPIED from Sea.wow.questlog and modified by Mathaius
--
--	BuildQuestTree()
--		Returns a flat table containing all of
--		the quests the player currently has and the 
--      details of the quests.
--
--	Returns:
--				oldQuests - (table) the previous value of the QuestTree before it was rebuilt
--				oldNumHeaders - (number) the number of questlog headers in the QuestTree before we rebuilt it
--				oldNumQuests - (number) the number of questlog quests in the QuestTree before we rebuilt it
--
function BuildQuestTree()
	local questList = {};
	local byUniqueID = {};

	-- Build our quest list
	local tempNumEntries, tempNumQuests = GetNumQuestLogEntries();
	local oldQuests,oldNumHeaders,oldNumQuests = AbsoluteQuestLog.Quests,AbsoluteQuestLog.NumHeaders,AbsoluteQuestLog.NumQuests;

	-- If no quests, exit so we don't call ExpandQuestHeader which triggers another QUEST_LOG_UPDATE event
	if ( tempNumEntries == 0 ) then
		AbsoluteQuestLog.Quests = questList;
		AbsoluteQuestLog.NumHeaders = 0;
		AbsoluteQuestLog.NumQuests = 0;
		return oldQuests,oldNumHeaders,oldNumQuests;
	end

	if ( not protectQuestLog() ) then
		return nil;
	end
	

	-- Rebuild our quest list since expanding quest headers can cause a change
	local numEntries, numQuests = GetNumQuestLogEntries();

	local currentZone;

	for questIndex=1, numEntries, 1 do
		local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily = GetQuestLogTitle(questIndex);
		if ( title ) then
			if ( isHeader ) then
				currentZone = title;
			else
				local entry =
				{
					id = questIndex;
					title = title;
					level = level;
					tag = questTag;
					groupNum = suggestedGroup;
					complete = isComplete;
					zone = currentZone;
					daily = isDaily;
				};

				local questData = _getPlayerQuestData(questIndex);
				if (questData) then
					entry.uniqueID = questData.uniqueID;
					entry.link = questData.link;
					entry.tracked = questData.tracked;
					entry.failed = questData.failed;
					entry.pushable = questData.pushable;
					entry.timer = questData.timer;
					entry.description = questData.description;
					entry.objective = questData.objective;
					entry.objectives = Sea.table.copy(questData.objectives);
					entry.choices = Sea.table.copy(questData.choices);
					entry.rewards = Sea.table.copy(questData.rewards);
					entry.rewardMoney = questData.rewardMoney;
					if ( questData.rewardMoney) then
						entry.requiredMoney = questData.requiredMoney;
					end
					entry.spellReward = Sea.table.copy(questData.spellReward);
				end
				if entry.title:match('^%[') then
					entry.cleanTitle = entry.title:match("^%[[^%]]+%]%s?(.*)"); -- idea borrowed from Quixote quest lib
				else
					entry.cleanTitle = entry.title;
				end

				questList[entry.cleanTitle] = entry;
				byUniqueID[entry.uniqueID] = entry.cleanTitle;
			end
		end
	end
	
	AbsoluteQuestLog.Quests = questList;
	AbsoluteQuestLog.QuestsByUniqueID = byUniqueID;
	AbsoluteQuestLog.NumHeaders = (numEntries - numQuests);
	AbsoluteQuestLog.NumQuests = numQuests;

	-- Unprotect
	unprotectQuestLog();

	return oldQuests,oldNumHeaders,oldNumQuests;
end;

--[[
--		HERE BEGINS MY ORIGINAL CODE - Mathaius
]]--

--
--	MergeTables()
--		Adds a copy of all keys and values from the originalTable to the newTable
--
--
function AbsoluteQuestLog:MergeTables(originalTable, newTable)
	if (not newTable) then
		newTable = {};
	end
	for k,v in pairs(originalTable) do
		local key, val = k,v;
		if ( type(key) == "table" ) then
			key = {};
			MergeTables(k,key);
		end
		if ( type(val) == "table" ) then
			val = {};
			AbsoluteQuestLog:MergeTables(v, val);
		end
		newTable[key] = val;
	end
	return newTable;
end


--
--	GetQuestLogByZone()
--		Returns a table containing a key for every zone the player has a quest in.  Each index has a value of a list of all quests
--		the player has in that zone keyed by the quest title
--
--	Returns:
--				QuestTree - (table) the QuestTree grouped by zone
--
function AbsoluteQuestLog.GetQuestLogByZone()
	local groupedQuests = {};
	for indx,questData in pairs(AbsoluteQuestLog.Quests) do
		if (not groupedQuests[questData.zone]) then
			groupedQuests[questData.zone] = {};
		end
		groupedQuests[questData.zone][indx] = questData;
	end
	return groupedQuests;
end

local function AbsoluteQuestLog_PrintDebugData(...)
	local message, type = ...;
	if (AbsoluteQuestLog.db.char.debug.enabled and (not (type) or AbsoluteQuestLog.db.char.debug.announce[type])) then
		AbsoluteQuestLog:Print("Debug::"..message);
	end
end

function AbsoluteQuestLog:GetQuestHistory(uniqueID)
	if (not uniqueID) then
		return nil;
	end
	local globalHistory = AbsoluteQuestLog.db.char.history[uniqueID];
	local charHistory = AbsoluteQuestLog.db.global.history[uniqueID];
	if (not globalHistory) and (not charHistory) then
		return nil;
	end
	globalHistory = AbsoluteQuestLog:MergeTables(globalHistory); -- this effectively clones globalHistory as a new table and reassigns it
	return AbsoluteQuestLog:MergeTables(charHistory, globalHistory); -- now we merge the clone with our character history
end

function AbsoluteQuestLog:GetQuestByTitle(title)
	if (not title) then
		return nil;
	end
	return AbsoluteQuestLog.Quests[title];
end

function AbsoluteQuestLog:GetQuestByID(uniqueID)
	if (not uniqueID) then
		return nil;
	end
	return AbsoluteQuestLog:GetQuestByTitle(AbsoluteQuestLog.QuestsByUniqueID[uniqueID]);
end

function AbsoluteQuestLog:AddQuestHistory(questInfo)
	if (not questInfo) then
		return;
	end
	if (not questInfo.uniqueID) then
		return;
	end
	local questID = questInfo.uniqueID;
	if (AbsoluteQuestLog.db.global.history[questID] == nil) then
		if (AbsoluteQuestLog.db.char.history[questID] == nil) then
			AbsoluteQuestLog.db.char.history[questID] = {};
		end
		AbsoluteQuestLog.db.global.history[questID] = {};
		AbsoluteQuestLog.db.global.history[questID].cleanTitle = questInfo.cleanTitle;
		AbsoluteQuestLog.db.global.history[questID].title = questInfo.title;
		AbsoluteQuestLog.db.global.history[questID].link = questInfo.link;
		AbsoluteQuestLog.db.global.history[questID].uniqueID = questInfo.uniqueID;
		AbsoluteQuestLog.db.global.history[questID].zone = questInfo.zone;
		AbsoluteQuestLog.db.global.history[questID].level = questInfo.level;
		AbsoluteQuestLog.db.global.history[questID].groupNum = questInfo.groupNum;
		AbsoluteQuestLog.db.global.history[questID].timer = questInfo.timer;
		AbsoluteQuestLog.db.global.history[questID].rewardMoney = questInfo.rewardMoney;
		AbsoluteQuestLog.db.global.history[questID].requiredMoney = questInfo.requiredMoney;
		AbsoluteQuestLog.db.global.history[questID].objective = questInfo.objective;
		AbsoluteQuestLog.db.global.history[questID].objectives = {};
		AbsoluteQuestLog.db.global.history[questID].eventLog = {};
		AbsoluteQuestLog.db.char.history[questID].complete = false;
		AbsoluteQuestLog.db.char.history[questID].turnedIn = false;
		AbsoluteQuestLog.db.char.history[questID].abandoned = false;
		AbsoluteQuestLog.db.char.history[questID].failed = false;
		AbsoluteQuestLog.db.char.history[questID].eventLog = {};
		for i=1,#questInfo.objectives do
			local objective = questInfo.objectives[i];
			local newObjective = {};
			newObjective.text = objective.text;
			newObjective.questType = objective.questType;
			newObjective.info = {};
			newObjective.info.name = objective.info.name;
			newObjective.info.total = objective.info.total;
			table.insert(AbsoluteQuestLog.db.global.history[questID].objectives,newObjective);
		end
	end
	if (not AbsoluteQuestLog.db.char.hasScannedCompletedQuests) then
		AbsoluteQuestLog:UpdateHistoryFromCompletedQuests();
	end
end

local function AddQuestHistoryEvent(...)
	local questInfo, eventID, objective = ...;
	-- add history entry if it is missing
	AbsoluteQuestLog:AddQuestHistory(questInfo);
	local eventData = {};
	eventData.id = eventID;
	-- set time event data
	eventData.time = {};
	local hours,minutes = GetGameTime();
	eventData.time.hours = hours;
	eventData.time.minutes = minutes;
	-- set date event data
	eventData.date = {};
	local weekday, month, day, year = CalendarGetDate()
	eventData.date.month = month;
	eventData.date.day = day;
	eventData.date.year = year;
	-- set map position and zone data
	SetMapToCurrentZone();
	local unitX, unitY = GetPlayerMapPosition("player");
	eventData.position = {};
	eventData.position.x = unitX * 100;
	eventData.position.y = unitY * 100;
	local zones = {GetMapZones(GetCurrentMapContinent())};
	eventData.position.zone = zones[GetCurrentMapZone()];
	-- process eventID types
	local questID = questInfo.uniqueID;
	if (eventID == AbsoluteQuestLog.AQ_QUEST_PROGRESS_UPDATED) then		
		eventData.objectiveType = objective.questType;
		eventData.objectiveName = objective.info.name;
	elseif (eventID == AbsoluteQuestLog.AQ_QUEST_COMPLETED) then
		AbsoluteQuestLog.db.char.history[questID].turnedIn = true;
		AbsoluteQuestLog.db.char.history[questID].complete = true;
		AbsoluteQuestLog.db.char.history[questID].abandoned = false;
		AbsoluteQuestLog.db.char.history[questID].failed = false;
		local partySize = GetNumPartyMembers();
		if (partySize ~= 0) then
			eventData.partyMembers = {};
			for i=1,partySize do
				table.insert(eventData.partyMembers,GetUnitName("party"..i));
			end
		end
	elseif (eventID == AbsoluteQuestLog.AQ_QUEST_FINISHED) then
		AbsoluteQuestLog.db.char.history[questID].complete = true;
		AbsoluteQuestLog.db.char.history[questID].abandoned = false;
		AbsoluteQuestLog.db.char.history[questID].failed = false;
	elseif (eventID == AbsoluteQuestLog.AQ_QUEST_FAILED) then
		AbsoluteQuestLog.db.char.history[questID].failed = true;
	elseif (eventID == AbsoluteQuestLog.AQ_QUEST_ACCEPTED) then
		AbsoluteQuestLog.db.char.history[questID].complete = false;
		AbsoluteQuestLog.db.char.history[questID].abandoned = false;
		AbsoluteQuestLog.db.char.history[questID].failed = false;
	elseif (eventID == AbsoluteQuestLog.AQ_QUEST_ABANDONED) then
		AbsoluteQuestLog.db.char.history[questID].abandoned = true;
	end
	local globalEventData = {};
	globalEventData.id = eventData.id;
	globalEventData.position = eventData.position;
	globalEventData.objectiveType = eventData.objectiveType;
	globalEventData.objectiveName = eventData.objectiveName;	
	table.insert(AbsoluteQuestLog.db.global.history[questID].eventLog,globalEventData);
	table.insert(AbsoluteQuestLog.db.char.history[questID].eventLog,eventData);
end

-- Used to broadcast quest completion events
-- Quest Completed: A quest was turned in and completed, thus removing it from the quest log as well as any quest items associated to it
local function Quest_Completed(questInfo)
	AddQuestHistoryEvent(questInfo,AbsoluteQuestLog.AQ_QUEST_COMPLETED);
	AbsoluteQuestLog:SendMessage(AbsoluteQuestLog.AQ_QUEST_COMPLETED,questInfo);
	AbsoluteQuestLog_PrintDebugData(AbsoluteQuestLog.AQ_QUEST_COMPLETED..":["..tostring(questInfo.uniqueID).."]:"..questInfo.link,"complete");
end
-- Used to broadcast quest progress update events
-- Quest Progress: One or more of the quest objectives for a quest changed status
local function Quest_Progress_Updated(questInfo,objective,positiveProgress)	
	if (positiveProgress) then
		-- don't bother logging loss of progress
		AddQuestHistoryEvent(questInfo, AbsoluteQuestLog.AQ_QUEST_PROGRESS_UPDATED, objective);
	end
	AbsoluteQuestLog:SendMessage(AbsoluteQuestLog.AQ_QUEST_PROGRESS_UPDATED,questInfo,objective);
	AbsoluteQuestLog_PrintDebugData(AbsoluteQuestLog.AQ_QUEST_PROGRESS_UPDATED..":["..tostring(questInfo.uniqueID).."]:"..questInfo.link,"progress");
end
-- Used to broadcast quest abandoned events
-- Quest Abandoned: A quest from the quest log was abandoned
local function Quest_Abandoned(questInfo)
	AddQuestHistoryEvent(questInfo, AbsoluteQuestLog.AQ_QUEST_ABANDONED);
	AbsoluteQuestLog:SendMessage(AbsoluteQuestLog.AQ_QUEST_ABANDONED,questInfo);
	AbsoluteQuestLog_PrintDebugData(AbsoluteQuestLog.AQ_QUEST_ABANDONED..":["..tostring(questInfo.uniqueID).."]:"..questInfo.link,"abandon");
end
-- Used to broadcast quest accepted events
-- Quest Accepted: A new quest was accepted and added to the quest log
local function Quest_Accepted(questInfo)
	AddQuestHistoryEvent(questInfo, AbsoluteQuestLog.AQ_QUEST_ACCEPTED);
	AbsoluteQuestLog:SendMessage(AbsoluteQuestLog.AQ_QUEST_ACCEPTED,questInfo);
	AbsoluteQuestLog_PrintDebugData(AbsoluteQuestLog.AQ_QUEST_ACCEPTED..":["..tostring(questInfo.uniqueID).."]:"..questInfo.link,"accept");
end
-- Used to broadcast quest failed events
-- Quest Failed: 1 or more objectives for the quest were failed (most likely an escort or timed quest)
local function Quest_Failed(questInfo)
	AddQuestHistoryEvent(questInfo, AbsoluteQuestLog.AQ_QUEST_FAILED);
	AbsoluteQuestLog:SendMessage(AbsoluteQuestLog.AQ_QUEST_FAILED,questInfo);
	AbsoluteQuestLog_PrintDebugData(AbsoluteQuestLog.AQ_QUEST_FAILED..":["..tostring(questInfo.uniqueID).."]:"..questInfo.link,"failed");
end
-- Used to broadcast quest finished events
-- Quest Finished: All objectives for the quest have been completed
local function Quest_Finished(questInfo)
	AddQuestHistoryEvent(questInfo, AbsoluteQuestLog.AQ_QUEST_FINISHED);
	AbsoluteQuestLog:SendMessage(AbsoluteQuestLog.AQ_QUEST_FINISHED,questInfo);
	AbsoluteQuestLog_PrintDebugData(AbsoluteQuestLog.AQ_QUEST_FINISHED..":["..tostring(questInfo.uniqueID).."]:"..questInfo.link,"finish");
end

local function Quest_Tracked(questInfo)
	AddQuestHistoryEvent(questInfo, AbsoluteQuestLog.AQ_QUEST_TRACKED);
	AbsoluteQuestLog:SendMessage(AbsoluteQuestLog.AQ_QUEST_TRACKED,questInfo);
	AbsoluteQuestLog_PrintDebugData(AbsoluteQuestLog.AQ_QUEST_TRACKED..":["..tostring(questInfo.uniqueID).."]:"..questInfo.link,"tracked");
end

local function Quest_Not_Tracked(questInfo)
	AddQuestHistoryEvent(questInfo, AbsoluteQuestLog.AQ_QUEST_NOT_TRACKED);
	AbsoluteQuestLog:SendMessage(AbsoluteQuestLog.AQ_QUEST_NOT_TRACKED,questInfo);
	AbsoluteQuestLog_PrintDebugData(AbsoluteQuestLog.AQ_QUEST_NOT_TRACKED..":["..tostring(questInfo.uniqueID).."]:"..questInfo.link,"not_tracked");
end

local function HandleLogUpdate()
	-- Build a list of quests
	local oldQuests, oldNumEntries, oldNumQuests = BuildQuestTree();
	if oldQuests == nil then
		return nil;
	end
	if (not AbsoluteQuestLog.Initialized) then
		AbsoluteQuestLog.Initialized = true;
		AbsoluteQuestLog_PrintDebugData("Quest database initialized");
		return;
	end
	--local changeType = 0;
	--if AbsoluteQuestLog.NumQuests > oldNumQuests then
		--changeType = 1;
	--elseif AbsoluteQuestLog.NumQuests < oldNumQuests then
		--changeType = 2;
	--end

	-- search for a change to broadcast	
	for title, newQuestInfo in pairs(AbsoluteQuestLog.Quests) do
		oldQuestInfo = oldQuests[title];
		if (oldQuestInfo ~= nil) then
			-- Find quests with tracking changes
			if (newQuestInfo.tracked ~= oldQuestInfo.tracked) then
				if (newQuestInfo.tracked) then
					Quest_Tracked(newQuestInfo);
				else
					Quest_Not_Tracked(newQuestInfo);
				end
			end
			-- Find quests with objective progress updates
			for i=1,#newQuestInfo.objectives do
				currentObjectiveNew = newQuestInfo.objectives[i];
				currentObjectiveOld = oldQuestInfo.objectives[i];
				statusNew = currentObjectiveNew.info;
				statusOld = currentObjectiveOld.info;
				if (statusNew.done > statusOld.done) then
					Quest_Progress_Updated(newQuestInfo, currentObjectiveNew, true);
					AbsoluteQuestLog.Completed = false;
					AbsoluteQuestLog.Abandoned = false;
				elseif (statusNew.done < statusOld.done) and (not AbsoluteQuestLog.Completed) and (not AbsoluteQuestLog.Abandoned) then
					Quest_Progress_Updated(newQuestInfo, currentObjectiveNew, false);
				end						
			end
			-- Find finished/failed quests
			if (newQuestInfo.complete == 1) and (oldQuestInfo.complete ~= 1) then
				AbsoluteQuestLog.Completed = false;
				AbsoluteQuestLog.Abandoned = false;
				Quest_Finished(newQuestInfo);
			elseif (newQuestInfo.failed == 1) and (oldQuestInfo.failed ~= 1) then
				AbsoluteQuestLog.Completed = false;
				AbsoluteQuestLog.Abandoned = false;
				Quest_Failed(newQuestInfo);
			end
		end
	end
	
	-- find new quest and add it to our list, then fire event
	for title, questInfo in pairs(AbsoluteQuestLog.Quests) do
		if oldQuests[title] == nil then
			AbsoluteQuestLog.Completed = false;
			AbsoluteQuestLog.Abandoned = false;
			Quest_Accepted(questInfo);
			if (questInfo.complete == 1) then
				Quest_Finished(questInfo);
			end
		end
	end		

	-- find removed quest (turnins and abandons)
	for title, questInfo in pairs(oldQuests) do
		if AbsoluteQuestLog.Quests[title] == nil then
			if AbsoluteQuestLog.Abandoned then
				Quest_Abandoned(questInfo);
				AbsoluteQuestLog.Abandoned = false;
			else
				Quest_Completed(questInfo);
				AbsoluteQuestLog.Completed = false;
			end
		end
	end
end

--	GetUniqueIDFromLink()
--
--	 Extracts the unique numeric quest id from a quest link string
--
-- Returns:
-- 	(number id)
-- 	id - unique numeric id of the quest OR nil if link is nil or it was not possible to extract the id from the link string
--
function AbsoluteQuestLog:GetUniqueIDFromLink(...)
	local link = ...;
	if (link ~= nil) then
		return tonumber(string.match(link,"quest:(%d+):%d+"));
	end
	return nil;
end

function AbsoluteQuestLog:GetQuestUniqueIDByIndex(index)
	return AbsoluteQuestLog:GetUniqueIDFromLink(GetQuestLink(index));
end

function AbsoluteQuestLog:GetQuestUniqueIDByQuestTitle(title)
	return AbsoluteQuestLog:GetUniqueIDFromLink(AbsoluteQuestLog.Quests[title]);
end

function AbsoluteQuestLog:HasCompletedQuest(uniqueID)
	if (not uniqueID) then
		return false;
	end
	local historyEntry = AbsoluteQuestLog.db.char.history[uniqueID];
	if (not historyEntry) then
		return false;
	end
	return (historyEntry.turnedIn);
end

function AbsoluteQuestLog:AbandonQuest()
	AbsoluteQuestLog.Abandoned = true;
	AbsoluteQuestLog.Completed = false;
end

function AbsoluteQuestLog:CompleteQuest()
	AbsoluteQuestLog.Completed = true;
	AbsoluteQuestLog.Abandoned = false;
end

function AbsoluteQuestLog:AddQuestWatch()
	-- We're updating the tracked status here but we have to call the HandleLogUpdate because often
	-- this method gets called after an item as been added to the quest log, but before QUEST_LOG_UPDATE is fired
	-- So it is quite possible a quest event could fire as a result of this but it's just as valid as being
	-- fired from the QUEST_LOG_UPDATE
	HandleLogUpdate();
end

function AbsoluteQuestLog:RemoveQuestWatch()
	-- See comments from the above AddQuestWatch
	HandleLogUpdate();
end

function AbsoluteQuestLog:QUEST_LOG_UPDATE(...)
	HandleLogUpdate();
end

function AbsoluteQuestLog:UpdateHistoryFromCompletedQuests()
	AbsoluteQuestLog:RegisterEvent("QUEST_QUERY_COMPLETE");
	QueryQuestsCompleted();
end

function AbsoluteQuestLog:QUEST_QUERY_COMPLETE(...)
	local completedQuests = GetQuestsCompleted();
	for uniqueID, complete in pairs(completedQuests) do
		if (complete) then
			if (not AbsoluteQuestLog.db.char.history[uniqueID]) then
				AbsoluteQuestLog.db.char.history[uniqueID] = {};
			end
			local historyEntry = AbsoluteQuestLog.db.char.history[uniqueID];
			historyEntry.uniqueID = uniqueID;
			historyEntry.complete = true;
			historyEntry.turnedIn = true;
			historyEntry.abandoned = false;
			historyEntry.failed = false;
		end
	end
	AbsoluteQuestLog.db.char.hasScannedCompletedQuests = true;
	AbsoluteQuestLog:UnregisterEvent("QUEST_QUERY_COMPLETE");
end

function AbsoluteQuestLog:PARTY_MEMBERS_CHANGED(eventName)
	HandleLogUpdate(); -- fire just to update log in case it needs re-initialization
end

function AbsoluteQuestLog:OnInitialize()
    -- Called when the addon is loaded
    AbsoluteQuestLog.db = LibStub("AceDB-3.0"):New("ABSOLUTEQUESTLOG_CONFIG", defaults);
    AbsoluteQuestLog:Print("v"..AQ_VERSION.." Loaded");
end

function AbsoluteQuestLog:OnEnable()
	-- Called when the addon is enabled
	AbsoluteQuestLog:SecureHook("AbandonQuest");
	AbsoluteQuestLog:SecureHook("AddQuestWatch");
	AbsoluteQuestLog:SecureHook("RemoveQuestWatch");
	AbsoluteQuestLog:Hook("CompleteQuest",true);
	AbsoluteQuestLog:RegisterEvent("QUEST_LOG_UPDATE");
	AbsoluteQuestLog:RegisterEvent("PARTY_MEMBERS_CHANGED");
end

function AbsoluteQuestLog:OnDisable()
    -- Called when the addon is disabled
    AbsoluteQuestLog:UnregisterEvent("QUEST_QUERY_COMPLETE");
    AbsoluteQuestLog:UnregisterEvent("PARTY_MEMBERS_CHANGED");
    AbsoluteQuestLog:UnregisterEvent("QUEST_LOG_UPDATE");    
    AbsoluteQuestLog:UnHook("CompleteQuest");
    AbsoluteQuestLog:UnHook("AbandonQuest");
    AbsoluteQuestLog:UnHook("AddQuestWatch");
	AbsoluteQuestLog:UnHook("RemoveQuestWatch");
end
