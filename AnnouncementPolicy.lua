-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether

-- Emotes used when celebrating completed quests and level-ups.
QuestTogether.completionEmotes = {
	"applaud",
	"bow",
	"cheer",
	"clap",
	"commend",
	"congratulate",
	"curtsey",
	"dance",
	"golfclap",
	"happy",
	"highfive",
	"huzzah",
	"impressed",
	"praise",
	"proud",
	"roar",
	"sexy",
	"smirk",
	"strut",
	"victory",
}

function QuestTogether:GetAnnouncementOptionKey(eventType)
	local keysByType = {
		QUEST_ACCEPTED = "announceAccepted",
		QUEST_STARTER_FOUND = "announceQuestStarterItems",
		LOOKING_FOR_QUEST_PARTNERS = "announceQuestPartners",
		QUEST_COMPLETED = "announceCompleted",
		QUEST_READY_TO_TURN_IN = "announceReadyToTurnIn",
		QUEST_REMOVED = "announceRemoved",
		QUEST_PROGRESS = "announceProgress",
		WORLD_QUEST_ENTERED = "announceWorldQuestAreaEnter",
		WORLD_QUEST_LEFT = "announceWorldQuestAreaLeave",
		WORLD_QUEST_PROGRESS = "announceWorldQuestProgress",
		WORLD_QUEST_COMPLETED = "announceWorldQuestCompleted",
		BONUS_OBJECTIVE_ENTERED = "announceBonusObjectiveAreaEnter",
		BONUS_OBJECTIVE_LEFT = "announceBonusObjectiveAreaLeave",
		BONUS_OBJECTIVE_PROGRESS = "announceBonusObjectiveProgress",
		BONUS_OBJECTIVE_COMPLETED = "announceBonusObjectiveCompleted",
	}

	return keysByType[eventType]
end

function QuestTogether:IsWorldQuestAnnouncementType(eventType)
	return eventType == "WORLD_QUEST_ENTERED"
		or eventType == "WORLD_QUEST_LEFT"
		or eventType == "WORLD_QUEST_PROGRESS"
		or eventType == "WORLD_QUEST_COMPLETED"
end

function QuestTogether:IsBonusObjectiveAnnouncementType(eventType)
	return eventType == "BONUS_OBJECTIVE_ENTERED"
		or eventType == "BONUS_OBJECTIVE_LEFT"
		or eventType == "BONUS_OBJECTIVE_PROGRESS"
		or eventType == "BONUS_OBJECTIVE_COMPLETED"
end

function QuestTogether:ShouldDisplayAnnouncementType(eventType)
	local optionKey = self:GetAnnouncementOptionKey(eventType)
	if not optionKey then
		return true
	end
	return self:GetOption(optionKey) and true or false
end
