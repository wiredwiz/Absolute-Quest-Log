-- Author      : Thad
-- Create Date : 9/6/2010 8:51:36 AM

local questEventValues = {	accept		=	"Quest accepted",
							abandon		=	"Quest abandoned",
							finish		=	"Quest finished",
							complete	=	"Quest completed",
							progress	=	"Quest progress",
							fail		=	"Quest failed",
							tracked		=	"Quest tracked",
							not_tracked	=	"Quest not tracked"
						};

local options = {
	name = "AbsoluteQuestLog",
	desc = "Absolute Quest Log Configuration.",
	type = "group",
	args = {
		debug ={
		type = "toggle",
		name = "Debug mode",
		desc = "Toggles the display of debug messages.",
		order = 10,
		get = function()
				return AbsoluteQuestLog.db.char.debug.enabled;
			end,
		set = function()
				AbsoluteQuestLog.db.char.debug.enabled = not AbsoluteQuestLog.db.char.debug.enabled;
			end
		},
		announceMessages ={
			type = "multiselect",
			name = "Quest events to print",
			desc = "Toggles whether each quest event type will be printed for debug.",
			order = 20,
			values = questEventValues,
			get =	function(t,k) return AbsoluteQuestLog.db.char.debug.announce[k]; end,
			set =	function(t,k,v) AbsoluteQuestLog.db.char.debug.announce[k] = v; end
		}
	}
};

LibStub("AceConfig-3.0"):RegisterOptionsTable("AbsoluteQuestLog", options, "AbsoluteQuestLog");
LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("AbsoluteQuestLog", options);
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("AbsoluteQuestLog", "Absolute Quest Log");