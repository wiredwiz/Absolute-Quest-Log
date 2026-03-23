================================================================================
  AbsoluteQuestLog-1.0  (AQL)
  A quest data library for World of Warcraft: The Burning Crusade Anniversary
  Interface: 20505
================================================================================

AQL is a LibStub library that provides a unified, event-driven quest data API
for consumer addons. It maintains a live snapshot of the player's quest log,
tracks completion history, fires callbacks when quest and objective states
change, and resolves extended quest data (chain info, zone, type, faction)
through Questie or QuestWeaver when either is installed.

AQL has no external addon dependencies. LibStub and CallbackHandler-1.0 are
bundled inside the Libs\ folder.


--------------------------------------------------------------------------------
  GETTING THE LIBRARY
--------------------------------------------------------------------------------

Declare AQL as a dependency in your .toc file:

    ## Dependencies: AbsoluteQuestLog

Then retrieve the library at the top of your addon file:

    local AQL = LibStub("AbsoluteQuestLog-1.0")

AQL is not available until PLAYER_LOGIN has fired. If your addon initializes
before then, retrieve the library inside your OnEnable or PLAYER_LOGIN handler.


--------------------------------------------------------------------------------
  REGISTERING AND UNREGISTERING CALLBACKS
--------------------------------------------------------------------------------

AQL uses CallbackHandler-1.0. Register a callback by name:

    AQL:RegisterCallback("AQL_QUEST_ACCEPTED", "MyHandlerMethod", MyAddon)
    -- MyAddon:MyHandlerMethod(event, questInfo) will be called

Or with a plain function:

    AQL:RegisterCallback("AQL_QUEST_ACCEPTED", function(event, questInfo)
        print("Accepted:", questInfo.title)
    end)

Unregister:

    AQL:UnregisterCallback("AQL_QUEST_ACCEPTED", MyAddon)

See the CALLBACKS section below for the full list of events and their arguments.


--------------------------------------------------------------------------------
  PUBLIC API
--------------------------------------------------------------------------------

All methods are called on the library table (colon syntax).

  --- Quest State Queries ---

  AQL:GetQuest(questID)
      Returns the QuestInfo snapshot for a quest currently in the player's log,
      or nil if the quest is not active. Cache-only; does not query WoW APIs.

  AQL:GetAllQuests()
      Returns a table { [questID] = QuestInfo } containing every quest
      currently in the player's log.

  AQL:GetQuestsByZone(zone)
      Returns a table { [questID] = QuestInfo } filtered to a specific zone.
      The zone name must match the English canonical name stored by the active
      provider (e.g. "Blasted Lands"). On non-English clients, prefer
      GetAllQuests() and filter by questID.

  AQL:IsQuestActive(questID)
      Returns true if the quest is currently in the player's log.

  AQL:IsQuestFinished(questID)
      Returns true if the quest is in the log and all objectives are complete
      (isComplete = true), meaning it is ready to be turned in but has not
      been yet.

  AQL:HasCompletedQuest(questID)
      Returns true if the character has ever completed this quest. Checks the
      HistoryCache first, then falls back to IsQuestFlaggedCompleted.

  AQL:GetCompletedQuests()
      Returns a table { [questID] = true } of all quests completed this
      session.

  AQL:GetCompletedQuestCount()
      Returns the number of quests completed this session.

  AQL:GetQuestType(questID)
      Returns the quest type string for an active quest, or nil. Possible
      values are defined in AQL.QuestType (see CONSTANTS below).


  --- Extended Resolution ---

  AQL:GetQuestInfo(questID)
      Three-tier resolution — use this when you need quest data for a quest
      that may not be in the player's active log (e.g. a party member's quest).

        Tier 1: AQL QuestCache  — full normalized snapshot (all fields set)
        Tier 2: WoW log scan    — returns questID, title, level, suggestedGroup,
                                  isComplete, zone; augmented from Tier 3 if
                                  zone is absent
        Tier 3: Provider DB     — Questie or QuestWeaver; adds zone, level,
                                  requiredLevel, chainInfo

      Returns nil only when all three tiers have no data.
      Guaranteed fields when non-nil: questID, title.

  AQL:GetQuestTitle(questID)
      Returns the title string for any questID, or nil. Delegates to
      GetQuestInfo.

  AQL:GetQuestLink(questID)
      Returns a WoW quest hyperlink string for the given questID, or nil if
      no title can be resolved. For active quests this returns the link stored
      in the cache snapshot. For inactive quests it constructs the link from
      GetQuestInfo data.

  AQL:GetQuestObjectives(questID)
      Returns the objectives array for a questID. Uses the normalized cache
      fields (isFinished, etc.) when the quest is active; falls back to the
      raw WoW API when it is not.


  --- Objective Queries ---

  AQL:GetObjectives(questID)
      Returns the objectives array from the active cache, or nil if the quest
      is not in the log. Each entry is an ObjectiveInfo table (see DATA
      STRUCTURES below).

  AQL:GetObjective(questID, index)
      Returns a single ObjectiveInfo by 1-based index, or nil.


  --- Chain Queries ---

  AQL:GetChainInfo(questID)
      Returns a ChainInfo table for an active quest. Returns
      { knownStatus = "unknown" } if the quest is not in the cache or no
      provider data is available. See DATA STRUCTURES below.

  AQL:GetChainStep(questID)
      Returns the 1-based step number of this quest within its chain, or nil
      if the chain status is not "known".

  AQL:GetChainLength(questID)
      Returns the total number of quests in the chain, or nil if the chain
      status is not "known".


  --- Tracking ---

  AQL:TrackQuest(questID)
      Adds the quest to the quest watch list. Returns false if the watch cap
      (MAX_WATCHABLE_QUESTS) has already been reached, true otherwise.

  AQL:UntrackQuest(questID)
      Removes the quest from the quest watch list.


  --- Unit ---

  AQL:IsUnitOnQuest(questID, unit)
      Returns bool on Retail (UnitIsOnQuest is available). Returns nil on TBC
      Classic where the API does not exist.


  --- Utility ---

  AQL:IsQuestObjectiveText(msg)
      Returns true if msg matches the base description of any active quest
      objective. Strips the count suffix (": X/Y") before comparing so that
      stale-count UI_INFO_MESSAGE events still match. Used to identify
      objective-progress system messages.


--------------------------------------------------------------------------------
  CALLBACKS
--------------------------------------------------------------------------------

All callbacks receive the event name as the first argument, followed by the
arguments listed below.

  AQL_QUEST_ACCEPTED       (questInfo)
      Fired when a quest newly appears in the log. Not fired during the
      initial rebuild at login.

  AQL_QUEST_ABANDONED      (questInfo)
      Fired when a quest is removed from the log without being completed or
      failing for a known reason.

  AQL_QUEST_COMPLETED      (questInfo)
      Fired when a quest is removed from the log and IsQuestFlaggedCompleted
      is true (i.e. the quest was successfully turned in).
      Note: QUEST_TURNED_IN does not fire on Interface 20505. Turn-in is
      detected via a GetQuestReward hook + IsQuestFlaggedCompleted.

  AQL_QUEST_FINISHED       (questInfo)
      Fired when a quest's isComplete field transitions to true — all
      objectives are met but the quest has not yet been turned in.

  AQL_QUEST_FAILED         (questInfo)
      Fired when a quest is removed from the log and a failure reason is
      inferred (timer expiry or escort NPC death). questInfo.failReason will
      be set to AQL.FailReason.Timeout or AQL.FailReason.EscortDied.

  AQL_QUEST_TRACKED        (questInfo)
      Fired when a quest's isTracked field transitions to true.

  AQL_QUEST_UNTRACKED      (questInfo)
      Fired when a quest's isTracked field transitions to false.

  AQL_OBJECTIVE_PROGRESSED (questInfo, objInfo, delta)
      Fired when a quest objective's numFulfilled count increases. delta is
      the positive integer amount by which it increased.

  AQL_OBJECTIVE_COMPLETED  (questInfo, objInfo)
      Fired when numFulfilled reaches numRequired (objective fully satisfied).

  AQL_OBJECTIVE_REGRESSED  (questInfo, objInfo, delta)
      Fired when numFulfilled decreases. delta is the positive integer amount
      by which it decreased. Suppressed while a turn-in is pending (set by the
      GetQuestReward hook) to avoid false regressions from item bag updates.

  AQL_OBJECTIVE_FAILED     (questInfo, objInfo)
      Fired when an objective fails alongside a failed quest.

  AQL_UNIT_QUEST_LOG_CHANGED (unit)
      Fired when UNIT_QUEST_LOG_CHANGED fires for a unit other than "player".


--------------------------------------------------------------------------------
  DATA STRUCTURES
--------------------------------------------------------------------------------

  QuestInfo
  ---------
  Returned by GetQuest, GetAllQuests, GetQuestsByZone, and passed to callbacks.
  All fields are present for cache snapshots. GetQuestInfo results from Tier 2
  or Tier 3 may have some fields as nil.

    questID        (number)   Quest ID.
    title          (string)   Quest title.
    level          (number)   Recommended quest level.
    suggestedGroup (number)   Suggested group size. 0 if not a group quest.
    zone           (string)   Zone header from the quest log. Nil for non-cached
                              results where the quest is not in the player's log.
    type           (string)   Quest type. See AQL.QuestType constants, or nil.
    faction        (string)   "Alliance", "Horde", or nil.
    isComplete     (bool)     True when objectives are met, not yet turned in.
    isFailed       (bool)     True when a failure reason was detected.
    failReason     (string)   AQL.FailReason value, or nil.
    isTracked      (bool)     True if on the quest watch list.
    link           (string)   WoW quest hyperlink string.
    logIndex       (number)   1-based position in the quest log at snapshot time.
    snapshotTime   (number)   GetTime() when the snapshot was taken.
    timerSeconds   (number)   Seconds remaining on a timed quest, or nil.
    objectives     (array)    Array of ObjectiveInfo tables (see below).
    chainInfo      (table)    ChainInfo table (see below).


  ObjectiveInfo
  -------------
  Entries in questInfo.objectives.

    index        (number)  1-based index within the quest's objective list.
    text         (string)  Full objective text, e.g. "Wolves killed: 4/10".
    name         (string)  Objective text with the count suffix stripped,
                           e.g. "Wolves killed".
    type         (string)  Objective type string from the WoW API.
    numFulfilled (number)  Current count toward the objective.
    numRequired  (number)  Count required to complete the objective.
    isFinished   (bool)    True when numFulfilled >= numRequired.
    isFailed     (bool)    True when the objective failed with the quest.


  ChainInfo
  ---------
  Returned by GetChainInfo and embedded in QuestInfo.chainInfo.

  When knownStatus = "known":

    knownStatus  (string)  AQL.ChainStatus.Known
    chainID      (number)  questID of the first quest in the chain.
    step         (number)  1-based position of this quest in the chain.
    length       (number)  Total number of quests in the chain.
    provider     (string)  AQL.Provider value identifying the data source.
    steps        (array)   Array of step tables:
                             { questID, title, status }
                           status is an AQL.StepStatus value:
                             "completed", "active", "finished", "failed",
                             "available", "unavailable", "unknown"

  When knownStatus = "not_a_chain":
    Only knownStatus is present. The quest has no chain data.

  When knownStatus = "unknown":
    Only knownStatus is present. No provider data is available.


--------------------------------------------------------------------------------
  CONSTANTS
--------------------------------------------------------------------------------

  AQL.ChainStatus
    .Known       = "known"
    .NotAChain   = "not_a_chain"
    .Unknown     = "unknown"

  AQL.StepStatus
    .Completed   = "completed"
    .Active      = "active"
    .Finished    = "finished"
    .Failed      = "failed"
    .Available   = "available"
    .Unavailable = "unavailable"
    .Unknown     = "unknown"

  AQL.Provider
    .Questie     = "Questie"
    .QuestWeaver = "QuestWeaver"
    .None        = "none"

  AQL.QuestType
    .Normal      = "normal"
    .Elite       = "elite"
    .Dungeon     = "dungeon"
    .Raid        = "raid"
    .Daily       = "daily"
    .PvP         = "pvp"
    .Escort      = "escort"

  AQL.Faction
    .Alliance    = "Alliance"
    .Horde       = "Horde"

  AQL.FailReason
    .Timeout     = "timeout"
    .EscortDied  = "escort_died"


--------------------------------------------------------------------------------
  DEBUG
--------------------------------------------------------------------------------

  /aql debug on        Enable normal debug output to the chat frame.
  /aql debug normal    Same as "on".
  /aql debug verbose   Enable verbose output (every cache phase, every event).
  /aql debug off       Disable debug output (default).

Debug messages are prefixed with [AQL] in gold text.


--------------------------------------------------------------------------------
  EXAMPLE
--------------------------------------------------------------------------------

    local AQL = LibStub("AbsoluteQuestLog-1.0")

    MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "AceEvent-3.0")

    function MyAddon:OnEnable()
        AQL:RegisterCallback("AQL_QUEST_ACCEPTED",         "OnQuestAccepted",  self)
        AQL:RegisterCallback("AQL_QUEST_COMPLETED",        "OnQuestCompleted", self)
        AQL:RegisterCallback("AQL_OBJECTIVE_PROGRESSED",   "OnObjectiveProgress", self)
    end

    function MyAddon:OnQuestAccepted(event, questInfo)
        print("Quest accepted:", questInfo.title, "(Level", questInfo.level .. ")")
        if questInfo.chainInfo.knownStatus == AQL.ChainStatus.Known then
            print("  Chain step", questInfo.chainInfo.step,
                  "of", questInfo.chainInfo.length)
        end
    end

    function MyAddon:OnQuestCompleted(event, questInfo)
        print("Quest completed:", questInfo.title)
    end

    function MyAddon:OnObjectiveProgress(event, questInfo, obj, delta)
        print(string.format("%s — %s: %d/%d (+%d)",
            questInfo.title, obj.name,
            obj.numFulfilled, obj.numRequired, delta))
    end


================================================================================
