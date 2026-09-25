--[[
QuestTogether Core (No Ace Dependencies)

This file intentionally contains a lot of explanatory comments.
The goal is to make the addon understandable even for someone new to WoW addon development.

Key responsibilities in this file:
1. Create and expose the global addon table.
2. Initialize and maintain SavedVariables with defaults.
3. Handle addon lifecycle (load, login, enable/disable).
4. Provide utility methods used by the other files (events/comms/options/tests).
5. Implement slash commands and shared behavior like announcements.
]]

local addonName, addonTable = ...
local LibChev = assert(addonTable and addonTable.LibChev, "libchev must load before Core.lua")

-- Reuse an existing global table if it already exists (for safety), otherwise use the loader table.
local QuestTogether = _G.QuestTogether or addonTable or {}
_G.QuestTogether = QuestTogether
QuestTogether.LibChev = LibChev

local raw_tostring = tostring
local raw_string_match = string.match
local raw_string_find = string.find
local raw_issecretvalue = type(issecretvalue) == "function" and issecretvalue or nil
local raw_canaccessvalue = type(canaccessvalue) == "function" and canaccessvalue or nil
local raw_canaccesstable = type(canaccesstable) == "function" and canaccesstable or nil

local function NormalizeQuestInfoFlagValue(rawValue)
	if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
		return nil
	end
	if type(rawValue) == "boolean" then
		return rawValue
	end
	local numericFlag = QuestTogether and QuestTogether.SafeToNumber
		and QuestTogether:SafeToNumber(rawValue)
		or nil
	if numericFlag ~= nil then
		return numericFlag ~= 0
	end
	return nil
end

local function CanAccessForeignValue(rawValue)
	if raw_canaccessvalue then
		local ok, canAccess = pcall(raw_canaccessvalue, rawValue)
		if not ok or not canAccess then
			return false
		end
	end
	if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
		return false
	end
	return true
end

local function CanAccessForeignTable(rawTable)
	if type(rawTable) ~= "table" then
		return false
	end
	if raw_canaccesstable then
		local ok, canAccess = pcall(raw_canaccesstable, rawTable)
		if not ok or not canAccess then
			return false
		end
	end
	return CanAccessForeignValue(rawTable)
end

local function SanitizeQuestInfoEnumValue(rawValue)
	if not CanAccessForeignValue(rawValue) then
		return nil
	end
	local numericValue = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue) or nil
	if numericValue == nil then
		return nil
	end
	numericValue = math.floor(numericValue + 0.5)
	if numericValue < 0 then
		return nil
	end
	return numericValue
end

local function BuildSanitizedQuestLogInfoRecord(questLogIndex, titleValue, isHeaderValue, isHiddenValue, isTaskValue, isOnMapValue, hasLocalPOIValue, isCompleteValue, questIDValue, displayQuestIDValue, isWorldQuestValue)
	local numericQuestLogIndex = QuestTogether and QuestTogether.SafeToNumber
		and QuestTogether:SafeToNumber(questLogIndex)
		or nil
	if not numericQuestLogIndex or numericQuestLogIndex <= 0 then
		return nil
	end

	local titleIsSecret = QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(titleValue)
	local sanitizedInfo = {
		title = (type(titleValue) == "string" and not titleIsSecret) and titleValue or nil,
		questLogIndex = math.floor(numericQuestLogIndex + 0.5),
		isHeader = NormalizeQuestInfoFlagValue(isHeaderValue) == true,
		isHidden = NormalizeQuestInfoFlagValue(isHiddenValue) == true,
		isTask = NormalizeQuestInfoFlagValue(isTaskValue) == true,
		isOnMap = NormalizeQuestInfoFlagValue(isOnMapValue) == true,
		hasLocalPOI = NormalizeQuestInfoFlagValue(hasLocalPOIValue) == true,
		isComplete = NormalizeQuestInfoFlagValue(isCompleteValue) == true,
	}

	local numericQuestID = QuestTogether and QuestTogether.SafeToNumber
		and QuestTogether:SafeToNumber(questIDValue)
		or nil
	if not numericQuestID or numericQuestID <= 0 then
		numericQuestID = QuestTogether and QuestTogether.SafeToNumber
			and QuestTogether:SafeToNumber(displayQuestIDValue)
			or nil
	end
	if numericQuestID and numericQuestID > 0 then
		sanitizedInfo.questID = math.floor(numericQuestID + 0.5)
	end

	local normalizedIsWorldQuest = NormalizeQuestInfoFlagValue(isWorldQuestValue)
	if normalizedIsWorldQuest ~= nil then
		sanitizedInfo.isWorldQuest = normalizedIsWorldQuest
	end

	return sanitizedInfo
end

local function BuildSanitizedQuestLogInfoFromRawInfo(questLogIndex, rawInfo)
	if not CanAccessForeignTable(rawInfo) then
		return nil
	end

	local sanitizedInfo = BuildSanitizedQuestLogInfoRecord(
		questLogIndex,
		rawInfo.title,
		rawInfo.isHeader,
		rawInfo.isHidden,
		rawInfo.isTask,
		rawInfo.isOnMap,
		rawInfo.hasLocalPOI,
		rawInfo.isComplete,
		rawInfo.questID,
		rawInfo.displayQuestID,
		rawInfo.isWorldQuest
	)
	if not sanitizedInfo then
		return nil
	end

	sanitizedInfo.campaignID = SanitizeQuestInfoEnumValue(rawInfo.campaignID)
	sanitizedInfo.frequency = SanitizeQuestInfoEnumValue(rawInfo.frequency)
	sanitizedInfo.questClassification = SanitizeQuestInfoEnumValue(rawInfo.questClassification)
	return sanitizedInfo
end

local function MergeSanitizedQuestLogInfo(primaryInfo, fallbackInfo)
	if type(primaryInfo) ~= "table" then
		return type(fallbackInfo) == "table" and fallbackInfo or nil
	end
	if type(fallbackInfo) ~= "table" then
		return primaryInfo
	end

	local mergedInfo = {}
	mergedInfo.questLogIndex = primaryInfo.questLogIndex or fallbackInfo.questLogIndex
	mergedInfo.title = primaryInfo.title or fallbackInfo.title
	mergedInfo.questID = primaryInfo.questID or fallbackInfo.questID
	mergedInfo.isHeader = primaryInfo.isHeader == true or fallbackInfo.isHeader == true
	mergedInfo.isHidden = primaryInfo.isHidden == true or fallbackInfo.isHidden == true
	mergedInfo.isTask = primaryInfo.isTask == true or fallbackInfo.isTask == true
	mergedInfo.isOnMap = primaryInfo.isOnMap == true or fallbackInfo.isOnMap == true
	mergedInfo.hasLocalPOI = primaryInfo.hasLocalPOI == true or fallbackInfo.hasLocalPOI == true
	mergedInfo.isComplete = primaryInfo.isComplete == true or fallbackInfo.isComplete == true
	mergedInfo.campaignID = primaryInfo.campaignID or fallbackInfo.campaignID
	mergedInfo.frequency = primaryInfo.frequency or fallbackInfo.frequency
	mergedInfo.questClassification = primaryInfo.questClassification or fallbackInfo.questClassification
	if primaryInfo.isWorldQuest ~= nil then
		mergedInfo.isWorldQuest = primaryInfo.isWorldQuest == true
	elseif fallbackInfo.isWorldQuest ~= nil then
		mergedInfo.isWorldQuest = fallbackInfo.isWorldQuest == true
	end

	return mergedInfo
end

local function GetSnapshotBuilderQuestLogInfo(addon, questLogIndex)
	local numericQuestLogIndex = addon and addon.SafeToNumber
		and addon:SafeToNumber(questLogIndex)
		or nil
	if not numericQuestLogIndex or numericQuestLogIndex <= 0 then
		return nil
	end
	numericQuestLogIndex = math.floor(numericQuestLogIndex + 0.5)

	local questInfo = addon and addon.API and addon.API.GetQuestLogInfo
		and addon.API.GetQuestLogInfo(numericQuestLogIndex)
		or nil
	return questInfo
end

local function SafeText(value, fallback)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, fallback ~= nil and fallback or "<secret>")
	end

	local ok, textValue = pcall(raw_tostring, value)
	if ok then
		return textValue
	end

	if fallback ~= nil then
		return fallback
	end
	return "<secret>"
end

local function SafeMatch(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, first, second, third, fourth = pcall(raw_string_match, safeText, pattern)
	if not ok then
		return nil
	end

	return first, second, third, fourth
end

local function SafeFind(text, pattern, init, plain)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, firstIndex, secondIndex = pcall(raw_string_find, safeText, pattern, init, plain)
	if not ok then
		return nil
	end

	return firstIndex, secondIndex
end

local tostring = SafeText

QuestTogether.addonName = addonName or "QuestTogether"
QuestTogether.commPrefix = "QuestTogether"
QuestTogether.announcementChannelName = "QuestTogetherAnnounce1"
QuestTogether.questLogWindowName = "QuestTogether"
QuestTogether.CHAT_BUBBLE_SIZE_MIN = 80
QuestTogether.CHAT_BUBBLE_SIZE_MAX = 160
QuestTogether.CHAT_BUBBLE_SIZE_STEP = 5
QuestTogether.CHAT_BUBBLE_DURATION_MIN = 1
QuestTogether.CHAT_BUBBLE_DURATION_MAX = 8
QuestTogether.CHAT_BUBBLE_DURATION_STEP = 0.5
QuestTogether.ANNOUNCEMENT_NEARBY_RADIUS = 5

-- Runtime state flags.
QuestTogether.isInitialized = QuestTogether.isInitialized or false
QuestTogether.hasLoggedIn = QuestTogether.hasLoggedIn or false
QuestTogether.isEnabled = QuestTogether.isEnabled or false
QuestTogether.activeProfileKey = QuestTogether.activeProfileKey or nil
QuestTogether.activeCharacterKey = QuestTogether.activeCharacterKey or nil
QuestTogether.pendingPingRequests = QuestTogether.pendingPingRequests or {}
QuestTogether.pendingQuestCompareRequests = QuestTogether.pendingQuestCompareRequests or {}
QuestTogether.debugLogLines = QuestTogether.debugLogLines or {}
QuestTogether.debugLogTextLengthSum = QuestTogether.debugLogTextLengthSum or 0
QuestTogether.debugLogStoreNormalized = QuestTogether.debugLogStoreNormalized or false
QuestTogether.isRunningTests = QuestTogether.isRunningTests or false
QuestTogether.DEBUG_LOG_MAX_LINES = 1000
QuestTogether.DEBUG_LOG_MAX_CHARS = 200000
QuestTogether.DEBUG_DEFAULT_CATEGORY = "DEBUG"
QuestTogether.DEBUG_ALL_CATEGORIES = "ALL"

-- Work queues / state tables used by event handlers.
QuestTogether.onQuestLogUpdate = QuestTogether.onQuestLogUpdate or {}
QuestTogether.questsCompleted = QuestTogether.questsCompleted or {}
QuestTogether.pendingQuestRemovals = QuestTogether.pendingQuestRemovals or {}
QuestTogether.worldQuestAreaStateByQuestID = QuestTogether.worldQuestAreaStateByQuestID or {}
QuestTogether.bonusObjectiveAreaStateByQuestID = QuestTogether.bonusObjectiveAreaStateByQuestID or {}

-- Default settings for SavedVariables.
QuestTogether.DEFAULTS = {
	profile = {
		enabled = true,
		announceAccepted = true,
		announceCompleted = true,
		announceReadyToTurnIn = true,
		announceRemoved = true,
		announceProgress = true,
		announceWorldQuestAreaEnter = true,
		announceWorldQuestAreaLeave = true,
		announceWorldQuestProgress = true,
		announceWorldQuestCompleted = true,
		announceBonusObjectiveAreaEnter = true,
		announceBonusObjectiveAreaLeave = true,
		announceBonusObjectiveProgress = true,
		announceBonusObjectiveCompleted = true,
			showChatBubbles = true,
			hideMyOwnChatBubbles = false,
			showChatLogs = true,
			chatLogDestination = "main",
			mirrorChatLogsToMainChat = false,
			showProgressFor = "party_nearby",
			devLogAllAnnouncements = false,
		chatBubbleSize = 100,
		chatBubbleDuration = 3,
		emoteOnQuestCompletion = true,
		emoteOnNearbyPlayerQuestCompletion = true,
		nameplateQuestIconEnabled = true,
		nameplateQuestIconStyle = "left",
		nameplateQuestHealthColorEnabled = true,
		nameplateQuestHealthColor = {
			r = 0.95,
			g = 0.45,
			b = 0.05,
		},
		-- Stored per profile so each character/profile can pick its own chat tab.
		questLogChatFrameID = nil,
	},
		global = {
			questTrackers = {},
			personalBubbleAnchors = {},
			debugLogCategoryFilter = "ALL",
			debugLogSearchFilter = "",
			debugLogPrefixFilter = "",
		},
	}

QuestTogether.nameplateQuestIconStyleLabels = {
	left = "Left",
	right = "Right",
	top = "Top",
	prefix = "Prefix",
}

QuestTogether.nameplateQuestIconStyleOrder = {
	"left",
	"right",
	"top",
	"prefix",
}

QuestTogether.showProgressForLabels = {
	party_nearby = "Party & Nearby Players",
	party_only = "Party Only",
}

QuestTogether.showProgressForOrder = {
	"party_nearby",
	"party_only",
}

QuestTogether.chatLogDestinationLabels = {
	main = "Main Chat Window",
	separate = "Separate Chat Window",
}

QuestTogether.chatLogDestinationOrder = {
	"main",
	"separate",
}
QuestTogether.chatLogLinkType = "questtogetherlog"
QuestTogether.chatLogQuestLinkType = "questtogetherquest"
QuestTogether.chatLogCoordLinkType = "questtogethercoord"
QuestTogether.questTitleLinkEventTypes = {
	QUEST_ACCEPTED = true,
	QUEST_COMPLETED = true,
	QUEST_READY_TO_TURN_IN = true,
	QUEST_REMOVED = true,
	WORLD_QUEST_ENTERED = true,
	WORLD_QUEST_LEFT = true,
	WORLD_QUEST_COMPLETED = true,
	BONUS_OBJECTIVE_ENTERED = true,
	BONUS_OBJECTIVE_LEFT = true,
	BONUS_OBJECTIVE_COMPLETED = true,
}

QuestTogether.DEFAULT_PERSONAL_BUBBLE_ANCHOR = {
	point = "CENTER",
	relativePoint = "CENTER",
	x = 0,
	y = 120,
}

function QuestTogether:IsShowProgressFor(value)
	for _, candidate in ipairs(self.showProgressForOrder) do
		if candidate == value then
			return true
		end
	end
	return false
end

function QuestTogether:IsChatLogDestination(value)
	for _, candidate in ipairs(self.chatLogDestinationOrder) do
		if candidate == value then
			return true
		end
	end
	return false
end

function QuestTogether:GetChatLogDestinationLabel(value)
	return self.chatLogDestinationLabels[value] or tostring(value)
end

function QuestTogether:NormalizeChatBubbleSizeValue(value)
	local numericValue = self:SafeToNumber(value)
	if not numericValue then
		return nil
	end

	local step = self.CHAT_BUBBLE_SIZE_STEP or 5
	numericValue = math.floor((numericValue / step) + 0.5) * step

	if numericValue < self.CHAT_BUBBLE_SIZE_MIN or numericValue > self.CHAT_BUBBLE_SIZE_MAX then
		return nil
	end

	return numericValue
end

function QuestTogether:IsChatBubbleSize(value)
	return self:NormalizeChatBubbleSizeValue(value) ~= nil
end

function QuestTogether:NormalizeChatBubbleDurationValue(value)
	local numericValue = self:SafeToNumber(value)
	if not numericValue then
		return nil
	end

	local step = self.CHAT_BUBBLE_DURATION_STEP or 0.5
	numericValue = math.floor((numericValue / step) + 0.5) * step
	numericValue = math.floor((numericValue * 10) + 0.5) / 10

	if numericValue < self.CHAT_BUBBLE_DURATION_MIN or numericValue > self.CHAT_BUBBLE_DURATION_MAX then
		return nil
	end

	return numericValue
end

function QuestTogether:IsChatBubbleDuration(value)
	return self:NormalizeChatBubbleDurationValue(value) ~= nil
end

function QuestTogether:IsNameplateQuestIconStyle(styleKey)
	for _, candidate in ipairs(self.nameplateQuestIconStyleOrder) do
		if candidate == styleKey then
			return true
		end
	end
	return false
end

function QuestTogether:GetNameplateQuestIconStyleLabel(styleKey)
	return self.nameplateQuestIconStyleLabels[styleKey] or tostring(styleKey)
end

function QuestTogether:GetNameplateQuestIconStyle()
	local configured = self:GetOption("nameplateQuestIconStyle")
	if self:IsNameplateQuestIconStyle(configured) then
		return configured
	end
	return self.DEFAULTS.profile.nameplateQuestIconStyle
end

function QuestTogether:GetShowProgressForLabel(value)
	return self.showProgressForLabels[value] or tostring(value)
end

function QuestTogether:GetChatBubbleSizeLabel(sizeKey)
	local numericValue = self:NormalizeChatBubbleSizeValue(sizeKey)
	if not numericValue then
		return tostring(sizeKey)
	end

	return tostring(numericValue) .. "%"
end

function QuestTogether:GetChatBubbleDurationLabel(durationValue)
	local numericValue = self:NormalizeChatBubbleDurationValue(durationValue)
	if not numericValue then
		return tostring(durationValue)
	end

	if math.abs(numericValue - math.floor(numericValue)) < 0.001 then
		return string.format("%d sec", numericValue)
	end

	return string.format("%.1f sec", numericValue)
end

function QuestTogether:GetPersonalBubbleAnchorKey()
	if self:UsesRegionalPlayerNames() then
		return self:GetCurrentCharacterKey()
	end
	if self.GetPlayerFullName then
		local fullName = self:GetPlayerFullName()
		if fullName and fullName ~= "" then
			return fullName
		end
	end

	local playerName = self:GetPlayerName()
	if playerName and playerName ~= "" then
		return playerName
	end

	return "player"
end

function QuestTogether:GetPersonalBubbleAnchorStore()
	if not self.db or not self.db.global then
		return nil
	end

	if type(self.db.global.personalBubbleAnchors) ~= "table" then
		self.db.global.personalBubbleAnchors = {}
	end

	return self.db.global.personalBubbleAnchors
end

function QuestTogether:GetPersonalBubbleAnchor()
	local defaults = self.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	local anchor = {
		point = defaults.point,
		relativePoint = defaults.relativePoint,
		x = defaults.x,
		y = defaults.y,
	}

	local store = self:GetPersonalBubbleAnchorStore()
	local key = self:GetPersonalBubbleAnchorKey()
	local saved = store and store[key] or nil
	if type(saved) ~= "table" then
		return anchor
	end

	if type(saved.point) == "string" and saved.point ~= "" then
		anchor.point = saved.point
	end
	if type(saved.relativePoint) == "string" and saved.relativePoint ~= "" then
		anchor.relativePoint = saved.relativePoint
	end
	local numericX = self:SafeToNumber(saved.x)
	if numericX ~= nil then
		anchor.x = numericX
	end
	local numericY = self:SafeToNumber(saved.y)
	if numericY ~= nil then
		anchor.y = numericY
	end

	return anchor
end

function QuestTogether:SetPersonalBubbleAnchor(point, relativePoint, offsetX, offsetY)
	local store = self:GetPersonalBubbleAnchorStore()
	if not store then
		return false
	end

	local defaults = self.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	local numericOffsetX = self:SafeToNumber(offsetX)
	local numericOffsetY = self:SafeToNumber(offsetY)
	store[self:GetPersonalBubbleAnchorKey()] = {
		point = type(point) == "string" and point ~= "" and point or defaults.point,
		relativePoint = type(relativePoint) == "string" and relativePoint ~= "" and relativePoint or defaults.relativePoint,
		x = numericOffsetX ~= nil and numericOffsetX or defaults.x,
		y = numericOffsetY ~= nil and numericOffsetY or defaults.y,
	}

	if self.ApplySavedPersonalBubbleAnchor then
		self:ApplySavedPersonalBubbleAnchor()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end
	return true
end

function QuestTogether:ResetPersonalBubbleAnchor()
	local store = self:GetPersonalBubbleAnchorStore()
	if not store then
		return false
	end

	store[self:GetPersonalBubbleAnchorKey()] = nil
	if self.ApplySavedPersonalBubbleAnchor then
		self:ApplySavedPersonalBubbleAnchor()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end
	return true
end

-- Emotes used when celebrating completed quests.
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

-- The runtime event list that should only be registered while the addon is enabled.
QuestTogether.runtimeEvents = {
	"CHAT_MSG_ADDON",
	"QUEST_ACCEPTED",
	"QUEST_TURNED_IN",
	"QUEST_REMOVED",
	"UNIT_QUEST_LOG_CHANGED",
	"QUEST_LOG_UPDATE",
	"QUEST_POI_UPDATE",
	"AREA_POIS_UPDATED",
	"PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED",
	"ZONE_CHANGED",
	"ZONE_CHANGED_INDOORS",
	"ZONE_CHANGED_NEW_AREA",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_ENTERING_WORLD",
	"ADDON_RESTRICTION_STATE_CHANGED",
	"SUPER_TRACKING_CHANGED",
	"GROUP_JOINED",
	"GROUP_ROSTER_UPDATE",
}

--[[
API wrapper table.

Why this exists:
- Production code uses these wrappers to call WoW globals.
- Tests can replace one or more wrappers to observe behavior without touching global WoW APIs.
]]
-- API wrapper layer:
-- Guard Blizzard calls that can throw (invalid token, secure context, or transient data race)
-- so runtime features fail soft instead of tainting shared execution paths.
QuestTogether.API = QuestTogether.API or {
	Delay = function(seconds, callback)
		C_Timer.After(seconds, callback)
	end,
	JoinPermanentChannel = function(name, password, chatFrameId, hasVoice)
		return JoinPermanentChannel(name, password, chatFrameId, hasVoice)
	end,
	LeaveChannelByName = function(name)
		return LeaveChannelByName(name)
	end,
	GetChannelName = function(name)
		return GetChannelName(name)
	end,
	GetNumChatWindows = function()
		return NUM_CHAT_WINDOWS or 0
	end,
	GetChatWindowInfo = function(chatFrameID)
		return FCF_GetChatWindowInfo(chatFrameID)
	end,
	GetChatFrameByID = function(chatFrameID)
		local chatFrame = FCF_GetChatFrameByID(chatFrameID)
		if QuestTogether and QuestTogether.CanAccessForeignFrame and not QuestTogether:CanAccessForeignFrame(chatFrame) then
			return nil
		end
		return chatFrame
	end,
		GetCVar = function(cvarName)
			if not (C_CVar and C_CVar.GetCVar and type(cvarName) == "string" and cvarName ~= "") then
				return nil
			end
		local ok, value = pcall(C_CVar.GetCVar, cvarName)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(value) then
			return nil
			end
			return value
		end,
		GetInstanceInfo = function()
			if type(GetInstanceInfo) ~= "function" then
				return nil
			end
			local ok, name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID, instanceGroupSize =
				pcall(GetInstanceInfo)
			if not ok then
				return nil
			end
			return {
				name = name,
				instanceType = instanceType,
				difficultyID = difficultyID,
				difficultyName = difficultyName,
				maxPlayers = maxPlayers,
				dynamicDifficulty = dynamicDifficulty,
				isDynamic = isDynamic,
				instanceMapID = instanceMapID,
				instanceGroupSize = instanceGroupSize,
			}
		end,
		RemoveChatWindowChannel = function(chatFrame, channelName)
			if QuestTogether and QuestTogether.CanAccessForeignFrame and not QuestTogether:CanAccessForeignFrame(chatFrame) then
				return nil
			end
		if chatFrame and chatFrame.RemoveChannel then
			return chatFrame:RemoveChannel(channelName)
		end
		if type(ChatFrame_RemoveChannel) == "function" and chatFrame then
			return ChatFrame_RemoveChannel(chatFrame, channelName)
		end
		return nil
	end,
	AddMessageEventFilter = function(eventName, filterFunc)
		if type(ChatFrame_AddMessageEventFilter) == "function" then
			ChatFrame_AddMessageEventFilter(eventName, filterFunc)
		end
	end,
	RemoveMessageEventFilter = function(eventName, filterFunc)
		if type(ChatFrame_RemoveMessageEventFilter) == "function" then
			ChatFrame_RemoveMessageEventFilter(eventName, filterFunc)
		end
	end,
	OpenChatWindow = function(name, noDefaultChannels)
		return FCF_OpenNewWindow(name, noDefaultChannels)
	end,
	CloseChatWindow = function(chatFrame)
		if QuestTogether and QuestTogether.CanAccessForeignFrame and not QuestTogether:CanAccessForeignFrame(chatFrame) then
			return nil
		end
		return FCF_Close(chatFrame)
	end,
	SetChatWindowFontSize = function(chatFrame, fontSize)
		if QuestTogether and QuestTogether.CanAccessForeignFrame and not QuestTogether:CanAccessForeignFrame(chatFrame) then
			return nil
		end
		return FCF_SetChatWindowFontSize(nil, chatFrame, fontSize)
	end,
		RegisterAddonPrefix = function(prefix)
			local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
			return ok and result or nil
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
			return ok and result or nil
		end,
	IsInInstanceGroup = function()
		return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	end,
	IsInParty = function()
		return UnitInParty("player")
	end,
	IsInRaid = function()
		return IsInRaid()
	end,
	IsInInstance = function()
		local inInstance = IsInInstance()
		return inInstance and true or false
	end,
	InCombatLockdown = function()
		if InCombatLockdown then
			return InCombatLockdown() and true or false
		end
		return false
	end,
	DoEmote = function(emoteToken, target)
		local performEmote = C_ChatInfo and C_ChatInfo.PerformEmote
		if type(performEmote) ~= "function" then
			performEmote = DoEmote
		end
		if type(performEmote) ~= "function" then
			return false
		end
		local ok = pcall(performEmote, emoteToken, target)
		return ok
	end,
	IsMounted = function()
		return IsMounted()
	end,
	GetFaction = function()
		local faction = UnitFactionGroup("player")
		return faction
	end,
	Random = function(low, high)
		return math.random(low, high)
	end,
		GetTime = function()
			return GetTime()
		end,
		ReloadUI = function()
			if type(ReloadUI) ~= "function" then
				return false
			end
			local ok = pcall(ReloadUI)
			return ok and true or false
		end,
		IsModifiedClick = function(action)
			if type(IsModifiedClick) ~= "function" then
				return false
			end
		local ok, modified = pcall(IsModifiedClick, action)
		return ok and modified and true or false
	end,
		UnitExists = function(unitToken)
			local ok, exists = pcall(UnitExists, unitToken)
			return ok and exists and true or false
		end,
		UnitIsUnit = function(leftUnitToken, rightUnitToken)
			if type(UnitIsUnit) ~= "function" then
				return false
			end
			local ok, isSameUnit = pcall(UnitIsUnit, leftUnitToken, rightUnitToken)
			if not ok or not CanAccessForeignValue(isSameUnit) then
				return false
			end
			return isSameUnit and true or false
		end,
	UnitGUID = function(unitToken)
		local ok, guidValue = pcall(UnitGUID, unitToken)
		if not ok or not CanAccessForeignValue(guidValue) then
			return nil
		end
		return guidValue
	end,
	UnitFullName = function(unitToken)
		local ok, unitName, unitRealm = pcall(UnitFullName, unitToken)
		if not ok then
			return nil, nil
		end
		if not CanAccessForeignValue(unitName) then
			unitName = nil
		end
		if not CanAccessForeignValue(unitRealm) then
			unitRealm = nil
		end
		return unitName, unitRealm
	end,
	RegionalUniqueNamesEnabled = function()
		if type(RegionalUniqueNamesEnabled) ~= "function" then
			return false
		end
		local ok, enabled = pcall(RegionalUniqueNamesEnabled)
		if ok and CanAccessForeignValue(enabled) and type(enabled) == "boolean" then
			return enabled
		end
		return nil
	end,
	ShouldDisplaySurname = function()
		if not CanAccessForeignTable(C_PlayerInfo) then
			return nil
		end
		local getter = C_PlayerInfo.ShouldDisplaySurname
		if not CanAccessForeignValue(getter) or type(getter) ~= "function" then
			return nil
		end
		local ok, display = pcall(getter)
		if ok and CanAccessForeignValue(display) and type(display) == "boolean" then
			return display
		end
		return nil
	end,
	UnitClass = function(unitToken)
		local ok, className, classFile = pcall(UnitClass, unitToken)
		if not ok then
			return nil, nil
		end
		if QuestTogether and QuestTogether.IsSecretValue then
			if QuestTogether:IsSecretValue(className) then
				className = nil
			end
			if QuestTogether:IsSecretValue(classFile) then
				classFile = nil
			end
		end
		return className, classFile
	end,
	UnitRace = function(unitToken)
		local ok, raceName = pcall(UnitRace, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(raceName) then
			return nil
		end
		return raceName
	end,
	UnitLevel = function(unitToken)
		local ok, levelValue = pcall(UnitLevel, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(levelValue) then
			return nil
		end
		return levelValue
	end,
	UnitName = function(unitToken)
		local ok, unitName = pcall(UnitName, unitToken)
		if not ok or not CanAccessForeignValue(unitName) then
			return nil
		end
		return unitName
	end,
		UnitHealth = function(unitToken)
			local ok, unitHealth = pcall(UnitHealth, unitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(unitHealth) then
				return nil
			end
			return unitHealth
		end,
		UnitHealthMax = function(unitToken)
			local ok, maxHealth = pcall(UnitHealthMax, unitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(maxHealth) then
				return nil
			end
			return maxHealth
		end,
		UnitIsDeadOrGhost = function(unitToken)
			if type(UnitIsDeadOrGhost) == "function" then
				local ok, result = pcall(UnitIsDeadOrGhost, unitToken)
				return ok and result and true or false
			end
			if type(UnitIsDead) == "function" then
				local ok, result = pcall(UnitIsDead, unitToken)
				return ok and result and true or false
			end
			return false
		end,
		UnitIsPlayer = function(unitToken)
			local ok, result = pcall(UnitIsPlayer, unitToken)
			return ok and result and true or false
		end,
		GetQuestLogIndexForQuestID = function(questID)
			if InCombatLockdown and InCombatLockdown() then
				return nil
			end
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			local snapshotState = QuestTogether
				and QuestTogether.GetQuestSnapshotStateStore
				and QuestTogether:GetQuestSnapshotStateStore()
				or nil
			local snapshotByQuestID = snapshotState and snapshotState.byQuestID or nil
			local snapshot = snapshotByQuestID and snapshotByQuestID[numericQuestID] or nil
			if type(snapshot) == "table" then
				local snapshotQuestLogIndex = QuestTogether
					and QuestTogether.SafeToNumber
					and QuestTogether:SafeToNumber(snapshot.questLogIndex)
					or nil
				if snapshotQuestLogIndex and snapshotQuestLogIndex > 0 then
					local rowIndex = math.floor(snapshotQuestLogIndex + 0.5)
					local row = QuestTogether.API.GetQuestLogInfo(rowIndex)
					if row and QuestTogether:NormalizeQuestID(row.questID) == numericQuestID then
						return rowIndex
					end
				end
			end
			local numericCount = QuestTogether and QuestTogether.API and QuestTogether.API.GetNumQuestLogEntries
				and QuestTogether.API.GetNumQuestLogEntries()
				or 0
			numericCount = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(numericCount) or nil
			if numericCount and numericCount > 0 then
				numericCount = math.floor(numericCount + 0.5)
				for questLogIndex = 1, numericCount do
					local entryInfo = QuestTogether and QuestTogether.API and QuestTogether.API.GetQuestLogInfo
						and QuestTogether.API.GetQuestLogInfo(questLogIndex)
						or nil
					local normalizedEntryQuestID = entryInfo
						and QuestTogether
						and QuestTogether.NormalizeQuestID
						and QuestTogether:NormalizeQuestID(entryInfo.questID)
						or nil
					if normalizedEntryQuestID == numericQuestID then
						return questLogIndex
					end
				end
			end
			return nil
		end,
		IsQuestFlaggedCompleted = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
				local ok, isCompleted = pcall(C_QuestLog.IsQuestFlaggedCompleted, numericQuestID)
				if ok and CanAccessForeignValue(isCompleted) and type(isCompleted) == "boolean" then
					return isCompleted
				end
				return nil
			end
			return nil
		end,
		IsQuestReadyForTurnIn = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_QuestLog and C_QuestLog.ReadyForTurnIn then
				local ok, isReady = pcall(C_QuestLog.ReadyForTurnIn, numericQuestID)
				if ok and CanAccessForeignValue(isReady) and type(isReady) == "boolean" then
					return isReady
				end
				return nil
			end
			return nil
		end,
		IsQuestComplete = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_QuestLog and C_QuestLog.IsComplete then
				local ok, isComplete = pcall(C_QuestLog.IsComplete, numericQuestID)
				if ok and CanAccessForeignValue(isComplete) and type(isComplete) == "boolean" then
					return isComplete
				end
				return nil
			end
			return nil
		end,
		GetQuestClassification = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end

			if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
				local ok, classification = pcall(C_QuestInfoSystem.GetQuestClassification, numericQuestID)
				if ok and CanAccessForeignValue(classification) then
					local normalizedClassification = QuestTogether and QuestTogether.SafeToNumber
						and QuestTogether:SafeToNumber(classification)
						or nil
					if normalizedClassification ~= nil and normalizedClassification >= 0 then
						return math.floor(normalizedClassification + 0.5)
					end
				end
			end

			local questLogIndex = QuestTogether and QuestTogether.API and QuestTogether.API.GetQuestLogIndexForQuestID
				and QuestTogether.API.GetQuestLogIndexForQuestID(numericQuestID)
				or nil
			if not questLogIndex then
				return nil
			end

			local questInfo = QuestTogether and QuestTogether.API and QuestTogether.API.GetQuestLogInfo
				and QuestTogether.API.GetQuestLogInfo(questLogIndex)
				or nil
			if type(questInfo) ~= "table" then
				return nil
			end

			return SanitizeQuestInfoEnumValue(questInfo.questClassification)
		end,
		GetQuestFrequency = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end

			local questLogIndex = QuestTogether and QuestTogether.API and QuestTogether.API.GetQuestLogIndexForQuestID
				and QuestTogether.API.GetQuestLogIndexForQuestID(numericQuestID)
				or nil
			if not questLogIndex then
				return nil
			end

			local questInfo = QuestTogether and QuestTogether.API and QuestTogether.API.GetQuestLogInfo
				and QuestTogether.API.GetQuestLogInfo(questLogIndex)
				or nil
			if type(questInfo) ~= "table" then
				return nil
			end

			return SanitizeQuestInfoEnumValue(questInfo.frequency)
		end,
		GetQuestTagAtlas = function(tagID, worldQuestType)
			if type(QuestUtils_GetQuestTagAtlas) ~= "function" then
				return nil
			end

			local normalizedTagID = SanitizeQuestInfoEnumValue(tagID)
			local normalizedWorldQuestType = SanitizeQuestInfoEnumValue(worldQuestType)
			local ok, atlas = pcall(QuestUtils_GetQuestTagAtlas, normalizedTagID, normalizedWorldQuestType)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(atlas) then
				return nil
			end
			if type(atlas) ~= "string" or atlas == "" then
				return nil
			end

			return atlas
		end,
		GetQuestPoiTagType = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end

			local currentMapID = QuestTogether and QuestTogether.API and QuestTogether.API.GetPlayerMapID
				and QuestTogether.API.GetPlayerMapID("player")
				or nil
			if not currentMapID then
				return nil
			end

			local questPois = QuestTogether and QuestTogether.API and QuestTogether.API.GetQuestPOIsOnMap
				and QuestTogether.API.GetQuestPOIsOnMap(currentMapID)
				or nil
			if type(questPois) ~= "table" then
				return nil
			end

			for index = 1, #questPois do
				local poiInfo = questPois[index]
				if type(poiInfo) == "table" then
					local poiQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(poiInfo.questID)
						or nil
					if poiQuestID == numericQuestID then
						return SanitizeQuestInfoEnumValue(poiInfo.questTagType)
					end
				end
			end

			return nil
		end,
		IsQuestOnMap = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return false
			end
			if C_QuestLog and C_QuestLog.IsOnMap then
				local ok, isOnMap = pcall(C_QuestLog.IsOnMap, numericQuestID)
				if not ok then
					return false
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isOnMap) then
					return false
				end
				if type(isOnMap) == "boolean" then
					return isOnMap
				end
				local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(isOnMap) or nil
				if numericFlag ~= nil then
					return numericFlag ~= 0
				end
			end
			return false
		end,
		IsWorldQuest = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_QuestLog and C_QuestLog.IsWorldQuest then
				local ok, isWorldQuest = pcall(C_QuestLog.IsWorldQuest, numericQuestID)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isWorldQuest) then
					return nil
				end
				if type(isWorldQuest) == "boolean" then
					return isWorldQuest
				end
				local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(isWorldQuest)
					or nil
				if numericFlag ~= nil then
					return numericFlag ~= 0
				end
			end
			return nil
		end,
		IsTaskQuestActive = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_TaskQuest and C_TaskQuest.IsActive then
				local ok, isActive = pcall(C_TaskQuest.IsActive, numericQuestID)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isActive) then
					return nil
				end
				if type(isActive) == "boolean" then
					return isActive
				end
				local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(isActive) or nil
				if numericFlag ~= nil then
					return numericFlag ~= 0
				end
			end
			return nil
		end,
		GetTaskQuestInfoByQuestID = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if not (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID) then
				return nil
			end

			local ok, questTitle, factionID, capped, displayAsObjective =
				pcall(C_TaskQuest.GetQuestInfoByQuestID, numericQuestID)
			if not ok then
				return nil
			end

			local function NormalizeBooleanFlag(rawValue)
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
					return nil
				end
				if type(rawValue) == "boolean" then
					return rawValue
				end
				local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue) or nil
				if numericFlag ~= nil then
					return numericFlag ~= 0
				end
				return nil
			end

			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questTitle) then
				questTitle = nil
			end
			if type(questTitle) ~= "string" or questTitle == "" then
				questTitle = nil
			end

			local normalizedFactionID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(factionID)
				or nil
			if normalizedFactionID ~= nil then
				normalizedFactionID = math.floor(normalizedFactionID + 0.5)
				if normalizedFactionID <= 0 then
					normalizedFactionID = nil
				end
			end

			return {
				questTitle = questTitle,
				factionID = normalizedFactionID,
				capped = NormalizeBooleanFlag(capped),
				displayAsObjective = NormalizeBooleanFlag(displayAsObjective),
			}
		end,
		GetTaskInfo = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil, nil, nil, nil, nil
			end
			if type(GetTaskInfo) ~= "function" then
				return nil, nil, nil, nil, nil
			end

			local ok, isInArea, isOnMap, numObjectives, taskName, displayAsObjective = pcall(GetTaskInfo, numericQuestID)
			if not ok then
				return nil, nil, nil, nil, nil
			end

			local function NormalizeBooleanFlag(rawValue)
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
					return nil
				end
				if type(rawValue) == "boolean" then
					return rawValue
				end
				local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue) or nil
				if numericFlag ~= nil then
					return numericFlag ~= 0
				end
				return nil
			end

			local normalizedInArea = NormalizeBooleanFlag(isInArea)
			local normalizedOnMap = NormalizeBooleanFlag(isOnMap)
			local normalizedDisplayAsObjective = NormalizeBooleanFlag(displayAsObjective)

			local normalizedObjectiveCount = nil
			if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(numObjectives)) then
				normalizedObjectiveCount = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(numObjectives)
					or nil
				if normalizedObjectiveCount ~= nil then
					normalizedObjectiveCount = math.floor(normalizedObjectiveCount + 0.5)
					if normalizedObjectiveCount < 0 then
						normalizedObjectiveCount = 0
					end
				end
			end

			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(taskName) then
				taskName = nil
			end
			if type(taskName) ~= "string" or taskName == "" then
				taskName = nil
			end

			return normalizedInArea, normalizedOnMap, normalizedObjectiveCount, taskName, normalizedDisplayAsObjective
		end,
		GetNamePlateForUnit = function(unitToken)
			if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
				return nil
			end
			if type(unitToken) ~= "string" or unitToken == "" then
				return nil
			end

			local ok, namePlateFrameBase = pcall(C_NamePlate.GetNamePlateForUnit, unitToken, false)
			if not ok or not CanAccessForeignValue(namePlateFrameBase) then
				return nil
			end
			return namePlateFrameBase
		end,
		GetNamePlates = function()
			if not (C_NamePlate and C_NamePlate.GetNamePlates) then
				return {}
			end

			local ok, rawNameplates = pcall(C_NamePlate.GetNamePlates, false)
			if not ok or not CanAccessForeignTable(rawNameplates) then
				return {}
			end

			local nameplates = {}
			local okCopy = pcall(function()
				for _, frame in pairs(rawNameplates) do
					if CanAccessForeignValue(frame) then
						nameplates[#nameplates + 1] = frame
					end
				end
			end)
			if not okCopy then
				return {}
			end
			return nameplates
		end,
		GetPlayerMapID = function(unitToken)
			if not (C_Map and C_Map.GetBestMapForUnit) then
				return nil
			end

			local normalizedUnitToken = type(unitToken) == "string" and unitToken ~= "" and unitToken or "player"
			local ok, mapID = pcall(C_Map.GetBestMapForUnit, normalizedUnitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapID) then
				return nil
			end
			local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
			if not numericMapID or numericMapID <= 0 then
				return nil
			end
			return math.floor(numericMapID + 0.5)
		end,
		IsWorldMapVisible = function()
			if not WorldMapFrame then
				return false
			end
			if WorldMapFrame.IsForbidden then
				local okForbidden, isForbidden = pcall(WorldMapFrame.IsForbidden, WorldMapFrame)
				if okForbidden and isForbidden then
					return false
				end
			end
			if not WorldMapFrame.IsShown then
				return false
			end
			local okShown, isShown = pcall(WorldMapFrame.IsShown, WorldMapFrame)
			return okShown and isShown and true or false
		end,
		GetLocalTaskQuests = function()
			if type(GetTasksTable) ~= "function" then
				return nil
			end

			-- Blizzard's objective tracker uses GetTasksTable() as the local-area task list.
			-- Call it behind pcall for transient quest-log races, then copy only scalar quest IDs
			-- out so we never retain Blizzard-owned tables.
			local ok, tasks = pcall(GetTasksTable)
			if not ok or (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tasks)) then
				return nil
			end
			if type(tasks) ~= "table" then
				return nil
			end

			local questIds = {}
			for index = 1, #tasks do
				local questID = tasks[index]
				if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questID)) then
					local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questID)
						or nil
					if numericQuestID and numericQuestID > 0 then
						questIds[#questIds + 1] = math.floor(numericQuestID + 0.5)
					end
				end
			end

			return questIds
		end,
		GetTaskQuestsOnMap = function(mapID)
			local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
			if not numericMapID or numericMapID <= 0 then
				return nil
			end
			numericMapID = math.floor(numericMapID + 0.5)

			if not C_TaskQuest then
				return nil
			end
			local getTaskQuestsForMap = C_TaskQuest.GetQuestsOnMap
			local questIDField = "questID"
			if type(getTaskQuestsForMap) ~= "function" then
				getTaskQuestsForMap = C_TaskQuest.GetQuestsForPlayerByMapID
				questIDField = "questId"
			end
			if type(getTaskQuestsForMap) ~= "function" then
				return nil
			end

			local ok, tasks = pcall(getTaskQuestsForMap, numericMapID)
			if not ok or not CanAccessForeignTable(tasks) then
				return nil
			end

			local questIds = {}
			for index = 1, #tasks do
				local taskInfo = tasks[index]
				if CanAccessForeignTable(taskInfo) then
					local questID = taskInfo[questIDField]
					if CanAccessForeignValue(questID) then
						local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questID)
							or nil
						if numericQuestID and numericQuestID > 0 then
							questIds[#questIds + 1] = math.floor(numericQuestID + 0.5)
						end
					end
				end
			end

			return questIds
		end,
		GetTaskQuestTitle = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questID) or nil
			if not numericQuestID or numericQuestID <= 0 then
				return nil
			end
			numericQuestID = math.floor(numericQuestID + 0.5)

			if not (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID) then
				return nil
			end

			local ok, questTitle = pcall(C_TaskQuest.GetQuestInfoByQuestID, numericQuestID)
			if not ok or (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questTitle)) then
				return nil
			end
			if type(questTitle) ~= "string" or questTitle == "" then
				return nil
			end

			return questTitle
		end,
		GetQuestPOIsOnMap = function(mapID)
			local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
			if not numericMapID or numericMapID <= 0 then
				return nil
			end
			numericMapID = math.floor(numericMapID + 0.5)

			if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
				return nil
			end

			local ok, pois = pcall(C_QuestLog.GetQuestsOnMap, numericMapID)
			if not ok or not CanAccessForeignTable(pois) then
				return nil
			end

			local sanitized = {}
			for index = 1, #pois do
				local poi = pois[index]
				if CanAccessForeignTable(poi) then
					local questID = poi.questID
					if CanAccessForeignValue(questID) then
						local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questID)
							or nil
						if numericQuestID and numericQuestID > 0 then
							local function NormalizeBool(rawValue)
								if not CanAccessForeignValue(rawValue) then
									return nil
								end
								if type(rawValue) == "boolean" then
									return rawValue
								end
								local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue)
									or nil
								if numericFlag ~= nil then
									return numericFlag ~= 0
								end
								return nil
							end

							local questTagType = nil
							if CanAccessForeignValue(poi.questTagType) then
								questTagType = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(poi.questTagType)
									or nil
								if questTagType ~= nil then
									questTagType = math.floor(questTagType + 0.5)
								end
							end

							sanitized[#sanitized + 1] = {
								questID = math.floor(numericQuestID + 0.5),
								inProgress = NormalizeBool(poi.inProgress),
								isQuestStart = NormalizeBool(poi.isQuestStart),
								isMapIndicatorQuest = NormalizeBool(poi.isMapIndicatorQuest),
								questTagType = questTagType,
							}
						end
					end
				end
			end

			return sanitized
		end,
		IsOnQuest = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_QuestLog and C_QuestLog.IsOnQuest then
				local ok, isOnQuest = pcall(C_QuestLog.IsOnQuest, numericQuestID)
				if ok and CanAccessForeignValue(isOnQuest) and type(isOnQuest) == "boolean" then
					return isOnQuest
				end
				return nil
			end
			return nil
		end,
		IsPushableQuest = function(questID)
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end
			if C_QuestLog and C_QuestLog.IsPushableQuest then
				local ok, isPushable = pcall(C_QuestLog.IsPushableQuest, numericQuestID)
				if ok and CanAccessForeignValue(isPushable) and type(isPushable) == "boolean" then
					return isPushable
				end
				return nil
			end
			-- Classic's legacy query applies to the selected quest. Read it only
			-- when selection already matches; never move the user's selection.
			if type(GetQuestLogSelection) == "function" and type(GetQuestLogPushable) == "function" then
				local selectionOK, selection = pcall(GetQuestLogSelection)
				local index = selectionOK and QuestTogether:SafeToNumber(selection) or nil
				local row = index and index > 0 and QuestTogether.API.GetQuestLogInfo(index) or nil
				if row and QuestTogether:NormalizeQuestID(row.questID) == numericQuestID then
					local ok, pushable = pcall(GetQuestLogPushable)
					if ok and CanAccessForeignValue(pushable) and type(pushable) == "boolean" then return pushable end
				end
			end
			return nil
		end,
		GetNumQuestLogEntries = function()
			local getter = type(GetNumQuestLogEntries) == "function" and GetNumQuestLogEntries
				or (C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
			if type(getter) ~= "function" then return nil end
			local ok, count = pcall(getter)
			local numericCount = ok and QuestTogether:SafeToNumber(count) or nil
			if numericCount == nil or numericCount < 0 then return nil end
			return math.floor(numericCount + 0.5)
		end,
		GetQuestLogInfo = function(questLogIndex)
			local numericQuestLogIndex = QuestTogether and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(questLogIndex)
				or nil
			if numericQuestLogIndex == nil then
				return nil
			end
			numericQuestLogIndex = math.floor(numericQuestLogIndex + 0.5)
			if numericQuestLogIndex <= 0 then
				return nil
			end

			local titleInfo = nil
			if type(GetQuestLogTitle) == "function" then
				local okTitle, title, _, _, isHeader, _, isComplete, _, questID, _, displayQuestID, isOnMap, hasLocalPOI, isTask, _ =
					pcall(GetQuestLogTitle, numericQuestLogIndex)
				if okTitle then
					titleInfo = BuildSanitizedQuestLogInfoRecord(
						numericQuestLogIndex,
						title,
						isHeader,
						nil,
						isTask,
						isOnMap,
						hasLocalPOI,
						isComplete,
						questID,
						displayQuestID,
						nil
					)
				end
			end

			if C_QuestLog and C_QuestLog.GetInfo then
				local okInfo, rawInfo = pcall(C_QuestLog.GetInfo, numericQuestLogIndex)
				if okInfo then
					local sanitizedInfo = BuildSanitizedQuestLogInfoFromRawInfo(numericQuestLogIndex, rawInfo)
					if sanitizedInfo then
						return MergeSanitizedQuestLogInfo(sanitizedInfo, titleInfo)
					end
				end
			end

			return titleInfo
		end,
		GetNumQuestLeaderBoards = function(questLogIndex)
			if InCombatLockdown and InCombatLockdown() then
				return 0
			end
			local numericQuestLogIndex = QuestTogether and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(questLogIndex)
				or nil
			if numericQuestLogIndex == nil then
				return 0
			end
			numericQuestLogIndex = math.floor(numericQuestLogIndex + 0.5)
			if numericQuestLogIndex <= 0 then
				return 0
			end
			if type(GetNumQuestLeaderBoards) ~= "function" then
				return 0
			end
			local ok, objectiveCount = pcall(GetNumQuestLeaderBoards, numericQuestLogIndex)
			if not ok then
				return 0
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(objectiveCount) then
				return 0
			end
			local numericObjectiveCount = QuestTogether and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(objectiveCount)
				or nil
			if numericObjectiveCount == nil then
				return 0
			end
			if numericObjectiveCount <= 0 then
				return 0
			end
			return math.floor(numericObjectiveCount + 0.5)
		end,
		GetQuestObjectiveInfo = function(questID, objectiveIndex, displayComplete)
			if InCombatLockdown and InCombatLockdown() then
				return nil, nil, nil, nil
			end
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil, nil, nil, nil
			end

			local numericObjectiveIndex = QuestTogether and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(objectiveIndex)
				or nil
			if numericObjectiveIndex == nil then
				return nil, nil, nil, nil
			end
			numericObjectiveIndex = math.floor(numericObjectiveIndex + 0.5)
			if numericObjectiveIndex <= 0 then
				return nil, nil, nil, nil
			end

			local ok, text, objectiveType, finished, currentValue
			if type(GetQuestObjectiveInfo) == "function" then
				ok, text, objectiveType, finished, currentValue =
					pcall(GetQuestObjectiveInfo, numericQuestID, numericObjectiveIndex, displayComplete)
			elseif C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function" then
				local queryOK, objectives = pcall(C_QuestLog.GetQuestObjectives, numericQuestID)
				if not queryOK or not CanAccessForeignTable(objectives) then return nil, nil, nil, nil end
				local objective = objectives[numericObjectiveIndex]
				if not CanAccessForeignTable(objective) then return nil, nil, nil, nil end
				ok, text, objectiveType, finished, currentValue = true, objective.text, objective.type, objective.finished, objective.numFulfilled
			elseif type(GetQuestLogLeaderBoard) == "function" then
				local index = QuestTogether.API.GetQuestLogIndexForQuestID(numericQuestID)
				if not index then return nil, nil, nil, nil end
				ok, text, objectiveType, finished = pcall(GetQuestLogLeaderBoard, numericObjectiveIndex, index)
			end
			if not ok then
				return nil, nil, nil, nil
			end
			if not CanAccessForeignValue(text) then
				text = nil
			end
			if not CanAccessForeignValue(objectiveType) then
				objectiveType = nil
			end
			if not CanAccessForeignValue(finished) then
				finished = nil
			end
			if not CanAccessForeignValue(currentValue) then
				currentValue = nil
			end
			return text, objectiveType, finished, currentValue
		end,
		GetQuestProgressBarPercent = function(questID)
			if InCombatLockdown and InCombatLockdown() then
				return nil
			end
			local numericQuestID = QuestTogether and QuestTogether.NormalizeQuestID and QuestTogether:NormalizeQuestID(questID)
				or nil
			if not numericQuestID then
				return nil
			end

			if type(GetQuestProgressBarPercent) ~= "function" then
				return nil
			end
			local ok, progressValue = pcall(GetQuestProgressBarPercent, numericQuestID)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(progressValue) then
				return nil
			end
			return progressValue
		end,
		InviteUnit = function(name)
			if C_PartyInfo and C_PartyInfo.InviteUnit then
				local ok, result = pcall(C_PartyInfo.InviteUnit, name)
				return ok and result or nil
			end
			return nil
		end,
		SendTell = function(name, chatFrame)
			if ChatFrameUtil and ChatFrameUtil.SendTell then
				local ok, result = pcall(ChatFrameUtil.SendTell, name, chatFrame)
				return ok and result or nil
			end
			if type(ChatFrame_SendTell) == "function" then
				local ok, result = pcall(ChatFrame_SendTell, name, chatFrame)
				return ok and result or nil
			end
			return nil
		end,
		AddFriend = function(name)
			if C_FriendList and C_FriendList.AddFriend then
				local ok, result = pcall(C_FriendList.AddFriend, name)
				return ok and result or nil
			end
			return nil
		end,
	AddOrDelIgnore = function(name)
		if C_FriendList and C_FriendList.AddOrDelIgnore then
			-- Ignore-list APIs can throw for invalid names; keep menu actions non-fatal.
			local ok, result = pcall(C_FriendList.AddOrDelIgnore, name)
			return ok and result or nil
		end
		return nil
	end,
	IsOnIgnoredList = function(name)
		if C_FriendList and C_FriendList.IsOnIgnoredList then
			-- Ignore-list lookups can throw on malformed names; treat as "not ignored".
			local ok, result = pcall(C_FriendList.IsOnIgnoredList, name)
			return ok and result or false
		end
		return false
	end,
		IsAddOnLoaded = function(addonName)
			if C_AddOns and C_AddOns.IsAddOnLoaded then
				local ok, isLoaded = pcall(C_AddOns.IsAddOnLoaded, addonName)
				return ok and isLoaded and true or false
			end
			local ok, isLoaded = pcall(IsAddOnLoaded, addonName)
			return ok and isLoaded and true or false
		end,
		GetAddOnMetadata = function(addonName, fieldName)
			if C_AddOns and C_AddOns.GetAddOnMetadata then
				local ok, metadata = pcall(C_AddOns.GetAddOnMetadata, addonName, fieldName)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(metadata) then
					return nil
				end
				return metadata
			end
			if type(GetAddOnMetadata) == "function" then
				local ok, metadata = pcall(GetAddOnMetadata, addonName, fieldName)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(metadata) then
					return nil
				end
				return metadata
			end
			return nil
		end,
		UnitInParty = function(unitToken)
			local ok, result = pcall(UnitInParty, unitToken)
			return ok and result and true or false
		end,
		UnitInRaid = function(unitToken)
			local ok, result = pcall(UnitInRaid, unitToken)
			return ok and result and true or false
		end,
		Ambiguate = function(name, context)
			local ok, result = pcall(Ambiguate, name, context)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(result) then
				return nil
			end
			return result
		end,
	GetRealmName = function()
		local ok, realmName = pcall(GetRealmName)
		if not ok then
			return ""
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(realmName) then
			return ""
		end
		return realmName
	end,
	GetBestMapForUnit = function(unitToken)
		if C_Map and C_Map.GetBestMapForUnit then
			local ok, mapID = pcall(C_Map.GetBestMapForUnit, unitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapID) then
				return nil
			end
			return mapID
		end
		return nil
	end,
		GetMapInfo = function(mapID)
			if C_Map and C_Map.GetMapInfo then
				local ok, mapInfo = pcall(C_Map.GetMapInfo, mapID)
				if not ok or type(mapInfo) ~= "table" then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapInfo) then
					return nil
				end

				local sanitizedInfo = {}
				local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapInfo.mapID)
					or nil
				if not numericMapID then
					numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
				end
				if numericMapID and numericMapID > 0 then
					sanitizedInfo.mapID = math.floor(numericMapID + 0.5)
				end

				local mapName = mapInfo.name
				if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapName)) then
					if type(mapName) == "string" and mapName ~= "" then
						sanitizedInfo.name = mapName
					end
				end

				return sanitizedInfo
			end
			return nil
		end,
		GetPlayerMapPosition = function(mapID, unitToken)
			if C_Map and C_Map.GetPlayerMapPosition then
				local ok, mapPosition = pcall(C_Map.GetPlayerMapPosition, mapID, unitToken)
				if not ok or not mapPosition then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapPosition) then
					return nil
				end

				local rawX = mapPosition.x
				local rawY = mapPosition.y
				if (rawX == nil or rawY == nil) and mapPosition.GetXY then
					local okXY, xValue, yValue = pcall(mapPosition.GetXY, mapPosition)
					if okXY then
						rawX = rawX or xValue
						rawY = rawY or yValue
					end
				end

				local numericX = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawX) or nil
				local numericY = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawY) or nil
				if numericX == nil or numericY == nil then
					return nil
				end

				return {
					x = numericX,
					y = numericY,
				}
			end
			return nil
		end,
		GetTooltipDataForHyperlink = function(hyperlink)
			if C_TooltipInfo and C_TooltipInfo.GetHyperlink and type(hyperlink) == "string" and hyperlink ~= "" then
				local ok, tooltipData = pcall(C_TooltipInfo.GetHyperlink, hyperlink)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tooltipData) then
					return nil
				end
				return tooltipData
			end
			return nil
		end,
		GetTooltipDataForUnit = function(unitToken)
			if C_TooltipInfo and C_TooltipInfo.GetUnit then
				local ok, tooltipData = pcall(C_TooltipInfo.GetUnit, unitToken)
				if not ok then
					return nil
				end
				if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tooltipData) then
					return nil
				end
				return tooltipData
			end
			return nil
		end,
		SurfaceTooltipDataArgs = function(tooltipData)
			-- SurfaceArgs writes into Blizzard's tables. The tooltip reader already
			-- understands nested args; leave foreign data untouched.
			return CanAccessForeignTable(tooltipData) and tooltipData or nil
		end,
		IsWarModeActive = function()
			if C_PvP and C_PvP.IsWarModeDesired then
				return C_PvP.IsWarModeDesired()
			end
		if C_PvP and C_PvP.IsWarModeActive then
			return C_PvP.IsWarModeActive()
		end
		return false
	end,
	CreateUiMapPoint = function(mapID, x, y)
		if UiMapPoint and UiMapPoint.CreateFromCoordinates then
			return UiMapPoint.CreateFromCoordinates(mapID, x, y)
		end
		return nil
	end,
		CanSetUserWaypointOnMap = function(mapID)
			if C_Map and C_Map.CanSetUserWaypointOnMap then
				local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
				return ok and canSet and true or false
			end
			return false
		end,
		SetUserWaypoint = function(point)
			if C_Map and C_Map.SetUserWaypoint then
				local ok, result = pcall(C_Map.SetUserWaypoint, point)
				return ok and result or nil
			end
			return nil
		end,
		SetSuperTrackedUserWaypoint = function(shouldSuperTrack)
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				local ok, result = pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, shouldSuperTrack)
				return ok and result or nil
			end
			return nil
		end,
}

function QuestTogether:IsSecretValue(value)
	if not raw_issecretvalue then
		return false
	end

	local ok, isSecret = pcall(raw_issecretvalue, value)
	return not ok or (isSecret and true or false)
end

function QuestTogether:CanAccessValue(value)
	return CanAccessForeignValue(value)
end

function QuestTogether:CanAccessTable(tableValue)
	return CanAccessForeignTable(tableValue)
end

local function ReadForeignFrameMethod(frame, memberName)
	local ok, method = pcall(function()
		return frame[memberName]
	end)
	if not ok or not CanAccessForeignValue(method) then
		return nil, false
	end
	return method, true
end

function QuestTogether:IsForbiddenFrame(frame)
	local frameType = type(frame)
	if not frame or (frameType ~= "table" and frameType ~= "userdata") then
		return false
	end
	if not CanAccessForeignValue(frame) or (frameType == "table" and not CanAccessForeignTable(frame)) then
		return true
	end
	local method, readable = ReadForeignFrameMethod(frame, "IsForbidden")
	if not readable then
		return true
	end
	if type(method) ~= "function" then
		return false
	end

	local ok, forbidden = pcall(method, frame)
	return not ok or not CanAccessForeignValue(forbidden) or forbidden == true
end

function QuestTogether:IsProtectedFrame(frame)
	if not self:CanAccessValue(frame) then
		return true, false
	end

	local frameType = type(frame)
	if not frame or (frameType ~= "table" and frameType ~= "userdata") then
		return false, false
	end
	if self:IsForbiddenFrame(frame) then
		return true, false
	end
	local method, readable = ReadForeignFrameMethod(frame, "IsProtected")
	if not readable then
		return true, false
	end
	if type(method) ~= "function" then
		return false, false
	end

	local ok, isProtected, isProtectedExplicitly = pcall(method, frame)
	if not ok or not CanAccessForeignValue(isProtected) or not CanAccessForeignValue(isProtectedExplicitly) then
		return true, false
	end
	return isProtected and true or false, isProtectedExplicitly and true or false
end

function QuestTogether:CanAccessForeignFrame(frame, requireShown)
	local frameType = type(frame)
	if not frame or (frameType ~= "table" and frameType ~= "userdata") then
		return false
	end
	if not CanAccessForeignValue(frame) then
		return false
	end
	if self:IsForbiddenFrame(frame) then
		return false
	end

	if requireShown then
		local method, readable = ReadForeignFrameMethod(frame, "IsShown")
		if not readable or type(method) ~= "function" then
			return false
		end
		local okShown, isShown = pcall(method, frame)
		if not okShown or not CanAccessForeignValue(isShown) or not isShown then
			return false
		end
	end

	return true
end

function QuestTogether:GetAccessibleFrameMember(frame, memberName)
	if not self:CanAccessForeignFrame(frame) or type(memberName) ~= "string" or memberName == "" then
		return nil, false
	end

	local ok, value = pcall(function()
		return frame[memberName]
	end)
	if not ok or not self:CanAccessValue(value) then
		return nil, false
	end
	return value, true
end

function QuestTogether:TryAddMessageToChatFrame(chatFrame, message)
	if not self:CanAccessForeignFrame(chatFrame) or type(chatFrame.AddMessage) ~= "function" then
		return false
	end

	local ok = pcall(chatFrame.AddMessage, chatFrame, self:SafeToString(message, ""))
	return ok and true or false
end

function QuestTogether:SafeToNumber(value)
	if not self:CanAccessValue(value) then
		return nil
	end

	local valueType = type(value)
	if valueType == "number" then
		-- Reject NaN/inf to keep downstream math safe and deterministic.
		if value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		return value
	end

	if valueType ~= "string" then
		return nil
	end

	local trimmedValue = self:SafeTrimString(value, "")
	if trimmedValue == "" then
		return nil
	end

	local numericValue = tonumber(trimmedValue)
	if type(numericValue) ~= "number" then
		return nil
	end

	if numericValue ~= numericValue or numericValue == math.huge or numericValue == -math.huge then
		return nil
	end

	return numericValue
end

function QuestTogether:NormalizeQuestID(questId)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or numericQuestId <= 0 then
		return nil
	end

	return math.floor(numericQuestId + 0.5)
end

function QuestTogether:SafeToString(value, fallback)
	if not self:CanAccessValue(value) then
		if fallback ~= nil then
			return fallback
		end
		return "<secret>"
	end

	local valueType = type(value)
	if valueType == "string" then
		return value
	end
	if valueType == "number" or valueType == "boolean" or valueType == "nil" then
		return raw_tostring(value)
	end

	-- String coercion is intentionally shielded so debug/log paths never trigger taint errors.
	local ok, stringValue = pcall(raw_tostring, value)
	if ok then
		return stringValue
	end

	if fallback ~= nil then
		return fallback
	end
	return "<secret>"
end

function QuestTogether:SafeTrimString(value, fallback)
	local fallbackValue = fallback or ""
	if type(value) ~= "string" or not self:CanAccessValue(value) then
		return fallbackValue
	end

	local trimmedValue = string.match(value, "^%s*(.-)%s*$")
	if type(trimmedValue) ~= "string" or not self:CanAccessValue(trimmedValue) then
		return fallbackValue
	end
	return trimmedValue
end

function QuestTogether:SafeStripWhitespace(value, fallback)
	local fallbackValue = fallback or ""
	if type(value) ~= "string" or not self:CanAccessValue(value) then
		return fallbackValue
	end

	local stripped = string.gsub(value, "%s+", "")
	if type(stripped) ~= "string" or not self:CanAccessValue(stripped) then
		return fallbackValue
	end
	return stripped
end

-- Deep copy helper used for defaults merging and tests.
function QuestTogether:DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, nestedValue in pairs(value) do
		copy[key] = self:DeepCopy(nestedValue)
	end
	return copy
end

local function SortDebugKeys(keys)
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
end

local function FormatDebugValue(value, depth, visited)
	if QuestTogether:IsSecretValue(value) then
		return "<secret>"
	end

	local valueType = type(value)
	if valueType == "nil" then
		return "nil"
	end
	if valueType == "boolean" or valueType == "number" then
		return tostring(value)
	end
	if valueType == "string" then
		local ok, quoted = pcall(string.format, "%q", value)
		if ok then
			return quoted
		end
		return tostring(value, "<secret>")
	end
	if valueType ~= "table" then
		return "<" .. tostring(valueType) .. ">"
	end

	depth = depth or 0
	if depth >= 2 then
		return "{...}"
	end

	visited = visited or {}
	if visited[value] then
		return "{<cycle>}"
	end
	visited[value] = true

	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	SortDebugKeys(keys)

	local parts = {}
	local maxParts = 8
	for index = 1, math.min(#keys, maxParts) do
		local key = keys[index]
		parts[#parts + 1] = tostring(key) .. "=" .. FormatDebugValue(value[key], depth + 1, visited)
	end
	if #keys > maxParts then
		parts[#parts + 1] = string.format("...(%d more)", #keys - maxParts)
	end

	visited[value] = nil
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- Merge defaults into destination recursively without deleting existing values.
function QuestTogether:ApplyDefaults(destination, defaults)
	for key, defaultValue in pairs(defaults) do
		if destination[key] == nil then
			destination[key] = self:DeepCopy(defaultValue)
		elseif type(destination[key]) == "table" and type(defaultValue) == "table" then
			self:ApplyDefaults(destination[key], defaultValue)
		end
	end
end

local function NormalizeProfileKey(profileKey)
	if type(profileKey) ~= "string" then
		return nil
	end

	local trimmed = QuestTogether:SafeTrimString(profileKey, "")
	if trimmed == "" then
		return nil
	end
	return trimmed
end

function QuestTogether:GetCurrentCharacterKey()
	-- Keep existing Forever profile assignments: earlier versions interpreted
	-- UnitFullName's second return as a realm and stored First-Surname keys.
	-- This legacy storage key must not become a display or transport identity.
	if self:UsesRegionalPlayerNames() then
		local first, last = self.API.UnitFullName("player")
		first = self:SafeTrimString(first, "")
		last = self:SafeStripWhitespace(last, "")
		if first ~= "" and last ~= "" then
			return first .. "-" .. last
		end
	end
	local fullName = self.GetPlayerFullName and self:GetPlayerFullName() or nil
	if type(fullName) == "string" and fullName ~= "" then
		return fullName
	end

	local playerName = self:GetPlayerName() or "Unknown"
	if SafeFind(playerName, "-", 1, true) then
		return playerName
	end

	local realmName = self:SafeStripWhitespace(self.API.GetRealmName and self.API.GetRealmName() or "", "")
	if realmName ~= "" then
		return playerName .. "-" .. realmName
	end

	return playerName
end

function QuestTogether:EnsureProfileStorage()
	if not self.db then
		return false
	end

	if type(self.db.profiles) ~= "table" then
		self.db.profiles = {}
	end
	if type(self.db.profileKeys) ~= "table" then
		self.db.profileKeys = {}
	end

	return true
end

function QuestTogether:GetCurrentProfileKey()
	return self.activeProfileKey
end

function QuestTogether:GetProfileKeys()
	if not self.db then
		return {}
	end
	self:EnsureProfileStorage()

	local keys = {}
	for profileKey, profileData in pairs(self.db.profiles) do
		if type(profileKey) == "string" and type(profileData) == "table" then
			keys[#keys + 1] = profileKey
		end
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
	return keys
end

function QuestTogether:EnsureProfile(profileKey, sourceProfile)
	if not self.db or not self:EnsureProfileStorage() then
		return nil, nil
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return nil, nil
	end

	if type(self.db.profiles[normalizedKey]) ~= "table" then
		self.db.profiles[normalizedKey] = self:DeepCopy(sourceProfile or self.DEFAULTS.profile)
	end
	self:ApplyDefaults(self.db.profiles[normalizedKey], self.DEFAULTS.profile)
	return normalizedKey, self.db.profiles[normalizedKey]
end

function QuestTogether:ApplyActiveProfileState(changeReason)
	if not self.db or not self.db.profile then
		return false
	end

	self:NormalizeAnnouncementDisplayOptions()
	self:NormalizeNameplateOptions()

	if self.db.profile.chatLogDestination == "separate" then
		local chatFrame = self:EnsureQuestLogChatFrame()
		if chatFrame then
			self:ApplyMainChatFontSizeToChatFrame(chatFrame)
		end
	else
		self:CloseQuestLogChatFrame()
	end

	if self.hasLoggedIn then
		if self.db.profile.enabled then
			self:Enable()
		else
			self:Disable()
		end
	end

	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end
	if self.RefreshNameplateAugmentation then
		self:RefreshNameplateAugmentation()
	end
	if self.RefreshActiveAnnouncementBubbles then
		self:RefreshActiveAnnouncementBubbles()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end
	if self.RefreshPersonalBubbleEditModeDialog then
		self:RefreshPersonalBubbleEditModeDialog()
	end
	if self.RefreshOptionsWindow then
		self:RefreshOptionsWindow()
	end
	if self.RefreshProfilesWindow then
		self:RefreshProfilesWindow()
	end

	self:Debugf(
		"profile",
		"Applied active profile state reason=%s character=%s profile=%s",
		tostring(changeReason or "unknown"),
		tostring(self.activeCharacterKey),
		tostring(self.activeProfileKey)
	)
	return true
end

function QuestTogether:SetActiveProfile(profileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end

	local normalizedKey, profileData = self:EnsureProfile(profileKey)
	if not normalizedKey or not profileData then
		return false, "Profile name cannot be empty."
	end

	local characterKey = self.activeCharacterKey or self:GetCurrentCharacterKey()
	self.activeCharacterKey = characterKey
	self.activeProfileKey = normalizedKey
	self.db.profileKeys[characterKey] = normalizedKey
	self.db.profile = profileData

	self:ApplyActiveProfileState("switch")
	return true
end

function QuestTogether:CreateProfile(profileKey, sourceProfileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return false, "Profile name cannot be empty."
	end
	if type(self.db.profiles[normalizedKey]) == "table" then
		return false, "A profile with that name already exists."
	end

	local sourceProfile = self.db.profile
	local normalizedSource = NormalizeProfileKey(sourceProfileKey)
	if normalizedSource and type(self.db.profiles[normalizedSource]) == "table" then
		sourceProfile = self.db.profiles[normalizedSource]
	end

	self.db.profiles[normalizedKey] = self:DeepCopy(sourceProfile or self.DEFAULTS.profile)
	self:ApplyDefaults(self.db.profiles[normalizedKey], self.DEFAULTS.profile)
	return true
end

function QuestTogether:CopyProfileIntoActiveProfile(sourceProfileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end

	local sourceKey = NormalizeProfileKey(sourceProfileKey)
	if not sourceKey then
		return false, "Profile name cannot be empty."
	end
	if type(self.db.profiles[sourceKey]) ~= "table" then
		return false, "Profile not found: " .. tostring(sourceKey)
	end
	if not self.activeProfileKey then
		return false, "No active profile is set."
	end

	self.db.profiles[self.activeProfileKey] = self:DeepCopy(self.db.profiles[sourceKey])
	self:ApplyDefaults(self.db.profiles[self.activeProfileKey], self.DEFAULTS.profile)
	self.db.profile = self.db.profiles[self.activeProfileKey]
	self:ApplyActiveProfileState("copy")
	return true
end

function QuestTogether:ResetActiveProfile()
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end
	if not self.activeProfileKey then
		return false, "No active profile is set."
	end

	self.db.profiles[self.activeProfileKey] = self:DeepCopy(self.DEFAULTS.profile)
	self.db.profile = self.db.profiles[self.activeProfileKey]
	self:ApplyActiveProfileState("reset")
	return true
end

function QuestTogether:DeleteProfile(profileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, "Profile database is unavailable."
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return false, "Profile name cannot be empty."
	end
	if normalizedKey == self.activeProfileKey then
		return false, "You cannot delete the active profile."
	end
	if type(self.db.profiles[normalizedKey]) ~= "table" then
		return false, "Profile not found: " .. tostring(normalizedKey)
	end

	self.db.profiles[normalizedKey] = nil

	for characterKey, mappedProfileKey in pairs(self.db.profileKeys) do
		if mappedProfileKey == normalizedKey then
			local fallbackProfileKey = NormalizeProfileKey(characterKey) or tostring(characterKey)
			self.db.profileKeys[characterKey] = fallbackProfileKey
			self:EnsureProfile(fallbackProfileKey, self.DEFAULTS.profile)
		end
	end

	return true
end

function QuestTogether:Print(message)
	local text = "|cff33ff99QuestTogether|r: " .. self:SafeToString(message)
	local chatFrame = self:GetChatLogFrame()
	if not self:TryAddMessageToChatFrame(chatFrame, text) then
		print("QuestTogether:", self:SafeToString(message))
	end
end

function QuestTogether:PrintRaw(message)
	local text = self:SafeToString(message)
	local chatFrame = self:GetChatLogFrame()
	if not self:TryAddMessageToChatFrame(chatFrame, text) then
		print(text)
	end
end

function QuestTogether:PrintChatLogSystemMessage(message)
	self:PrintChatLogRaw("|cff33ff99QuestTogether|r: " .. self:SafeToString(message, ""))
end

function QuestTogether:PrintChatLogWarningMessage(message)
	local warningPrefix = "|cffff8800Warning:|r"
	local iconTag = self.GetQuestIconChatTag and self:GetQuestIconChatTag(14) or ""
	if iconTag ~= "" then
		warningPrefix = iconTag .. warningPrefix
	end

	self:PrintChatLogRaw(
		warningPrefix .. " |cffffd200" .. self:SafeToString(message, "") .. "|r"
	)
end

function QuestTogether:PrintChatLogInfoMessage(message)
	local infoPrefix = "|cff33ff99Info:|r"
	local iconTag = self.GetQuestIconChatTag and self:GetQuestIconChatTag(14) or ""
	if iconTag ~= "" then
		infoPrefix = iconTag .. infoPrefix
	end

	self:PrintChatLogRaw(
		infoPrefix .. " |cffffd200" .. self:SafeToString(message, "") .. "|r"
	)
end

function QuestTogether:PrintChatLogWarningDetailMessage(message)
	self:PrintChatLogRaw("|cffff8800 - |r" .. self:SafeToString(message, ""))
end

function QuestTogether:PrintChatLogInfoDetailMessage(message)
	self:PrintChatLogRaw("|cff33ff99 - |r" .. self:SafeToString(message, ""))
end

function QuestTogether:ShouldMirrorChatLogsToMainChat()
	if not self.db or not self.db.profile or self.db.profile.mirrorChatLogsToMainChat ~= true then
		return false
	end

	if self:GetResolvedChatLogDestination() ~= "separate" then
		return false
	end

	local chatFrame = self:FindVisibleQuestLogChatFrame()
	return self:IsChatFrameDocked(chatFrame)
end

function QuestTogether:GetMainChatFrame()
	return DEFAULT_CHAT_FRAME
end

function QuestTogether:GetConfiguredQuestLogChatFrameID()
	if not self.db then
		return nil
	end

	local configuredID = self:SafeToNumber(self.db.profile and self.db.profile.questLogChatFrameID)
	if configuredID and configuredID > 0 then
		return configuredID
	end

	return nil
end

function QuestTogether:SetConfiguredQuestLogChatFrameID(chatFrameID)
	if not self.db then
		return false
	end

	local numericID = self:SafeToNumber(chatFrameID)
	if numericID and numericID > 0 then
		if self.db.profile then
			self.db.profile.questLogChatFrameID = numericID
		end
	else
		if self.db.profile then
			self.db.profile.questLogChatFrameID = nil
		end
	end

	return true
end

function QuestTogether:FindQuestLogChatFrame()
	local chatWindowName = self.questLogWindowName or "QuestTogether"
	local configuredID = self:GetConfiguredQuestLogChatFrameID()
	if configuredID and self.API.GetChatFrameByID and self.API.GetChatWindowInfo then
		local configuredFrame = self.API.GetChatFrameByID(configuredID)
		local configuredName = self.API.GetChatWindowInfo(configuredID)
		if self:CanAccessForeignFrame(configuredFrame) and configuredName == chatWindowName then
			return configuredFrame, configuredID
		end
	end

	local maxWindows = self:SafeToNumber(self.API.GetNumChatWindows and self.API.GetNumChatWindows()) or 0
	for chatFrameID = 1, maxWindows do
		local frameName = self.API.GetChatWindowInfo and self.API.GetChatWindowInfo(chatFrameID)
		if frameName == chatWindowName then
			local chatFrame = nil
			if self.API.GetChatFrameByID then
				chatFrame = self.API.GetChatFrameByID(chatFrameID)
			end
			if not chatFrame then
				chatFrame = _G["ChatFrame" .. tostring(chatFrameID)]
			end
			if self:CanAccessForeignFrame(chatFrame) then
				self:SetConfiguredQuestLogChatFrameID(chatFrameID)
				return chatFrame, chatFrameID
			end
		end
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	return nil, nil
end

function QuestTogether:GetResolvedChatLogDestination()
	local chatFrame = self:FindVisibleQuestLogChatFrame()
	if chatFrame then
		return "separate"
	end

	return "main"
end

function QuestTogether:FindVisibleQuestLogChatFrame(excludedFrame)
	local chatWindowName = self.questLogWindowName or "QuestTogether"
	local maxWindows = self:SafeToNumber(self.API.GetNumChatWindows and self.API.GetNumChatWindows()) or 0

	for chatFrameID = 1, maxWindows do
		local frameName = self.API.GetChatWindowInfo and self.API.GetChatWindowInfo(chatFrameID)
		if frameName == chatWindowName then
			local chatFrame = nil
			if self.API.GetChatFrameByID then
				chatFrame = self.API.GetChatFrameByID(chatFrameID)
			end
			if not chatFrame then
				chatFrame = _G["ChatFrame" .. tostring(chatFrameID)]
			end
			if
				chatFrame
				and chatFrame ~= excludedFrame
				and self:CanAccessForeignFrame(chatFrame)
				and self:IsQuestLogChatFrameVisible(chatFrame)
			then
				self:SetConfiguredQuestLogChatFrameID(chatFrameID)
				return chatFrame, chatFrameID
			end
		end
	end

	return nil, nil
end

function QuestTogether:IsQuestLogChatFrame(chatFrame)
	if not self:CanAccessForeignFrame(chatFrame) or not chatFrame.GetID then
		return false
	end

	local expectedName = self.questLogWindowName or "QuestTogether"
	local frameID = chatFrame:GetID()
	local configuredID = self:GetConfiguredQuestLogChatFrameID()
	if configuredID and configuredID == frameID then
		return true
	end

	if self.API.GetChatWindowInfo then
		local frameName = self.API.GetChatWindowInfo(frameID)
		if frameName == expectedName then
			return true
		end
	end

	return false
end

function QuestTogether:IsQuestLogChatFrameVisible(chatFrame)
	if not self:CanAccessForeignFrame(chatFrame) or not self:IsQuestLogChatFrame(chatFrame) then
		return false
	end

	local frameShown = chatFrame.IsShown and chatFrame:IsShown()
	if frameShown then
		return true
	end

	local frameName = chatFrame.GetName and chatFrame:GetName()
	if not frameName or frameName == "" then
		return false
	end

	local chatTab = _G[frameName .. "Tab"]
	return self:CanAccessForeignFrame(chatTab) and chatTab.IsShown and chatTab:IsShown() or false
end

function QuestTogether:IsChatFrameDocked(chatFrame)
	if not self:CanAccessForeignFrame(chatFrame) then
		return false
	end

	if chatFrame.IsDocked then
		local ok, isDocked = pcall(chatFrame.IsDocked, chatFrame)
		if ok and type(isDocked) == "boolean" then
			return isDocked
		end
	end

	if type(chatFrame.isDocked) == "boolean" then
		return chatFrame.isDocked
	end

	local frameName = chatFrame.GetName and chatFrame:GetName()
	if frameName and frameName ~= "" then
		local chatTab = _G[frameName .. "Tab"]
		if self:CanAccessForeignFrame(chatTab) and type(chatTab.isDocked) == "boolean" then
			return chatTab.isDocked
		end
	end

	if FCFDock_GetChatFrames and GENERAL_CHAT_DOCK then
		local ok, dockedFrames = pcall(FCFDock_GetChatFrames, GENERAL_CHAT_DOCK)
		if ok and type(dockedFrames) == "table" then
			for _, dockedFrame in ipairs(dockedFrames) do
				if dockedFrame == chatFrame then
					return true
				end
			end
		end
	end

	return false
end

function QuestTogether:HandleQuestLogChatFrameClosed(chatFrame)
	if self.suppressQuestLogChatCloseHook then
		return false
	end
	if self.isLoggingOut then
		return false
	end
	if not self:IsQuestLogChatFrame(chatFrame) then
		return false
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	local evaluateClose = function()
		if self.isLoggingOut then
			return
		end

		local existingFrame, existingID = self:FindVisibleQuestLogChatFrame(chatFrame)
		if existingFrame then
			self:SetConfiguredQuestLogChatFrameID(existingID)
			self:Debugf(
				"chat",
				"Ignoring QuestTogether chat window close because a visible replacement exists id=%s",
				tostring(existingID)
			)
			if self.RefreshOptionsWindow then
				self:RefreshOptionsWindow()
			end
			return
		end

		self:Debug("QuestTogether chat window was closed; reverting chat log destination to main chat window", "chat")
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		if self.isEnabled and self.hasLoggedIn then
			self:PrintChatLogDestinationMessage()
		end
	end

	if self.API and self.API.Delay then
		self.API.Delay(0, evaluateClose)
	else
		evaluateClose()
	end

	return true
end

function QuestTogether:TryInstallChatWindowHooks()
	if self.chatWindowHooksInstalled then
		return
	end
	if type(hooksecurefunc) ~= "function" or type(FCF_Close) ~= "function" then
		return
	end

	hooksecurefunc("FCF_Close", function(frame, fallback)
		local closedFrame = fallback or frame
		QuestTogether:HandleQuestLogChatFrameClosed(closedFrame)
	end)

	self.chatWindowHooksInstalled = true
	self:Debug("Installed chat window hooks", "chat")
end

function QuestTogether:ActivateQuestLogChatFrame(chatFrame)
	if not self:CanAccessForeignFrame(chatFrame) or not chatFrame.GetID then
		return false
	end

	local chatTab = _G[chatFrame:GetName() .. "Tab"]
	local frameShown = chatFrame.IsShown and chatFrame:IsShown()
	local tabShown = self:CanAccessForeignFrame(chatTab) and chatTab.IsShown and chatTab:IsShown() or false
	if frameShown or tabShown then
		return true
	end

	if FCF_CheckShowChatFrame then
		FCF_CheckShowChatFrame(chatFrame)
		if self:CanAccessForeignFrame(chatTab) then
			FCF_CheckShowChatFrame(chatTab)
		end
	end
	if SetChatWindowShown then
		SetChatWindowShown(chatFrame:GetID(), true)
	end
	if FCF_DockFrame and FCFDock_GetChatFrames and GENERAL_CHAT_DOCK then
		FCF_DockFrame(chatFrame, (#FCFDock_GetChatFrames(GENERAL_CHAT_DOCK) + 1), true)
	end
	if FCF_FadeInChatFrame and FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
		local selectedFrame = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
		if selectedFrame then
			FCF_FadeInChatFrame(selectedFrame)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.SetLastActiveWindow and self:CanAccessForeignFrame(chatFrame.editBox) then
		ChatFrameUtil.SetLastActiveWindow(chatFrame.editBox)
	end

	self:Debugf("chat", "Reactivated existing QuestTogether chat window id=%s", tostring(chatFrame:GetID()))
	return true
end

function QuestTogether:EnsureQuestLogChatFrame()
	local existingFrame, existingID = self:FindQuestLogChatFrame()
	if existingFrame then
		self:ActivateQuestLogChatFrame(existingFrame)
		return existingFrame, existingID
	end

	if not self.API.OpenChatWindow then
		return nil, nil
	end

	local chatFrame, chatFrameID = self.API.OpenChatWindow(self.questLogWindowName or "QuestTogether", true)
	if not self:CanAccessForeignFrame(chatFrame) then
		return nil, nil
	end

	if chatFrame.RemoveAllMessageGroups then
		chatFrame:RemoveAllMessageGroups()
	end
	if chatFrame.RemoveAllChannels then
		chatFrame:RemoveAllChannels()
	end
	self:SetConfiguredQuestLogChatFrameID(chatFrameID)
	self:Debugf("chat", "Created QuestTogether chat window id=%s", tostring(chatFrameID))
	return chatFrame, chatFrameID
end

function QuestTogether:CloseQuestLogChatFrame()
	local chatFrame, chatFrameID = self:FindQuestLogChatFrame()
	if not chatFrame then
		self:SetConfiguredQuestLogChatFrameID(nil)
		return false
	end
	if not self:CanAccessForeignFrame(chatFrame) then
		self:SetConfiguredQuestLogChatFrameID(nil)
		return false
	end

	if self.API.CloseChatWindow then
		self.suppressQuestLogChatCloseHook = true
		-- Closing chat windows can fail in restricted UI states; keep close flow resilient.
		local ok = pcall(self.API.CloseChatWindow, chatFrame)
		self.suppressQuestLogChatCloseHook = false
		if not ok then
			self:Debugf("chat", "Failed to close QuestTogether chat window id=%s", tostring(chatFrameID))
		end
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	self:Debugf("chat", "Closed QuestTogether chat window id=%s", tostring(chatFrameID))
	if self.isEnabled and self.hasLoggedIn then
		self:PrintChatLogDestinationMessage()
	end
	return true
end

function QuestTogether:ReconcileQuestLogChatDestination()
	local visibleFrame, visibleID = self:FindVisibleQuestLogChatFrame()
	if visibleFrame and visibleID then
		self:SetConfiguredQuestLogChatFrameID(visibleID)
		self:Debugf("chat", "Adopted existing QuestTogether chat window id=%s on login", tostring(visibleID))
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		return true
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	return false
end

function QuestTogether:ApplyMainChatFontSizeToChatFrame(chatFrame)
	if
		not self:CanAccessForeignFrame(chatFrame)
		or not chatFrame.GetID
		or not self.API.GetChatWindowInfo
		or not self.API.SetChatWindowFontSize
	then
		return false
	end
	local mainChatFrame = self:GetMainChatFrame()
	if not self:CanAccessForeignFrame(mainChatFrame) or not mainChatFrame.GetID then
		return false
	end

	local mainChatID = mainChatFrame:GetID()
	local _, fontSize = self.API.GetChatWindowInfo(mainChatID)
	fontSize = self:SafeToNumber(fontSize)
	if not fontSize or fontSize <= 0 then
		return false
	end

	self.API.SetChatWindowFontSize(chatFrame, fontSize)
	self:Debugf("chat", "Applied main chat font size=%s to QuestTogether chat frame id=%s", tostring(fontSize), tostring(chatFrame:GetID()))
	return true
end

function QuestTogether:GetChatLogFrame()
	if self:GetResolvedChatLogDestination() == "separate" then
		local chatFrame = self:EnsureQuestLogChatFrame()
		if chatFrame and chatFrame.AddMessage then
			return chatFrame
		end
		self:Debug("Separate QuestTogether chat window unavailable; falling back to main chat", "chat")
	end

	return DEFAULT_CHAT_FRAME
end

function QuestTogether:TryAddMessageToConfiguredChatLogFrames(message)
	local text = self:SafeToString(message, "")
	local primaryFrame = self:GetChatLogFrame()
	local wroteMessage = self:TryAddMessageToChatFrame(primaryFrame, text)

	if self:ShouldMirrorChatLogsToMainChat() then
		local mainChatFrame = self:GetMainChatFrame()
		if mainChatFrame and mainChatFrame ~= primaryFrame and self:TryAddMessageToChatFrame(mainChatFrame, text) then
			wroteMessage = true
		end
	end

	return wroteMessage
end

function QuestTogether:PrintChatLogRaw(message)
	local text = self:SafeToString(message, "")
	if not self:TryAddMessageToConfiguredChatLogFrames(text) then
		self:PrintRaw(text)
	end
end

function QuestTogether:GetQuestIconChatTag(size)
	local texturePath = self.NAMEPLATE_QUEST_ICON_TEXTURE
	if type(texturePath) ~= "string" or texturePath == "" then
		return ""
	end

	local iconSize = math.max(1, math.floor((self:SafeToNumber(size) or 14)))
	return string.format("|T%s:%d:%d:0:0|t", texturePath, iconSize, iconSize)
end

function QuestTogether:GetIconChatTagFromAsset(iconAsset, iconKind, size)
	local asset = tostring(iconAsset or "")
	if asset == "" then
		return ""
	end

	local iconSize = math.max(1, math.floor((self:SafeToNumber(size) or 14)))
	if iconKind == "atlas" then
		return "|A:" .. asset .. ":" .. tostring(iconSize) .. ":" .. tostring(iconSize) .. "|a"
	end

	return string.format("|T%s:%d:%d:0:0|t", asset, iconSize, iconSize)
end

function QuestTogether:GetClassColorCode(classFile)
	local colorTable = nil
	if CUSTOM_CLASS_COLORS and classFile and CUSTOM_CLASS_COLORS[classFile] then
		colorTable = CUSTOM_CLASS_COLORS[classFile]
	elseif RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile] then
		colorTable = RAID_CLASS_COLORS[classFile]
	end

	if not colorTable or not colorTable.colorStr then
		return "|cffffffff"
	end

	return "|c" .. tostring(colorTable.colorStr)
end

function QuestTogether:GetPlayerClassFile()
	local _, classFile = self.API.UnitClass("player")
	return classFile or "PRIEST"
end

function QuestTogether:GetAddonVersion()
	local metadata = self.API and self.API.GetAddOnMetadata and self.API.GetAddOnMetadata(self.addonName, "Version")
	if type(metadata) ~= "string" then
		return ""
	end

	local version = self:SafeTrimString(metadata, "")
	if version == "" then
		return ""
	end

	return version
end

function QuestTogether:GetShortDisplayName(name)
	name = self:SafeTrimString(name, "")
	if name == "" then
		return "Unknown"
	end
	if self:UsesRegionalPlayerNames() then
		local fullName = self:NormalizeMemberName(name) or name
		if self:IsSelfSender(fullName) then
			local getter = self.API and self.API.ShouldDisplaySurname
			local ok, showSurname = false, nil
			if type(getter) == "function" then
				ok, showSurname = pcall(getter)
			end
			if not ok or not self:CanAccessValue(showSurname) or showSurname ~= true then
				return SafeMatch(fullName, "^(%S+)") or fullName
			end
		end
		return fullName
	end

	local ambiguate = self.API.Ambiguate or Ambiguate
	if type(ambiguate) == "function" then
		local ok, displayName = pcall(ambiguate, name, "short")
		if ok then
			return self:SafeTrimString(displayName, name)
		end
	end
	return name
end

function QuestTogether:NormalizeAnnouncementWarModeValue(warMode)
	if type(warMode) == "boolean" then
		return warMode
	end
	if type(warMode) == "string" then
		local normalized = string.lower(warMode)
		if warMode == "1" or normalized == "true" then
			return true
		end
		if warMode == "0" or normalized == "false" then
			return false
		end
	end
	return nil
end

function QuestTogether:RebuildQuestSnapshotStore()
	local snapshotState = self.GetQuestSnapshotStateStore and self:GetQuestSnapshotStateStore() or nil
	if type(snapshotState) ~= "table" then
		return nil
	end
	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
		return snapshotState
	end

	-- Build privately, then publish atomically. An unreadable row must not erase
	-- the previous snapshot or make an active quest look removed.
	local snapshotByQuestID = {}
	local snapshotOrder = {}

	local totalEntries = self.API and self.API.GetNumQuestLogEntries and self.API.GetNumQuestLogEntries()
	totalEntries = self:SafeToNumber(totalEntries)
	if totalEntries == nil then
		if snapshotState.lastUnreadableRow ~= "count" then
			self:Debug("snapshot_deferred reason=unknown_count", "QUEST")
		end
		snapshotState.lastUnreadableRow = "count"
		return snapshotState
	end
	totalEntries = math.max(0, math.floor(totalEntries + 0.5))
	local sampleRows = {}

	for questLogIndex = 1, totalEntries do
		local questInfo = GetSnapshotBuilderQuestLogInfo(self, questLogIndex)
		if not questInfo or (questInfo.isHeader ~= true and not self:NormalizeQuestID(questInfo.questID)) then
			if snapshotState.lastUnreadableRow ~= questLogIndex then
				self:Debugf("quest", "snapshot_deferred unreadable_row=%d rows=%d generation=%d",
					questLogIndex, totalEntries, snapshotState.generation or 0)
			end
			snapshotState.lastUnreadableRow = questLogIndex
			return snapshotState
		end
		if questLogIndex <= 5 then
			sampleRows[#sampleRows + 1] = {
				index = questLogIndex,
				title = questInfo and questInfo.title or nil,
				isHeader = questInfo and questInfo.isHeader == true or false,
				questID = questInfo and questInfo.questID or nil,
				isTask = questInfo and questInfo.isTask == true or false,
				isOnMap = questInfo and questInfo.isOnMap == true or false,
				hasLocalPOI = questInfo and questInfo.hasLocalPOI == true or false,
			}
		end
		if questInfo and questInfo.isHeader ~= true then
			local numericQuestID = self:NormalizeQuestID(questInfo.questID)
			if numericQuestID then
				local isWorldQuest = questInfo.isWorldQuest == true
				if not isWorldQuest and self.API and self.API.IsWorldQuest then
					isWorldQuest = self.API.IsWorldQuest(numericQuestID) == true
				end
				local isTaskQuest = questInfo.isTask == true or isWorldQuest == true
				local taskQuestInfo = nil
				if isTaskQuest and not isWorldQuest and self.API and self.API.GetTaskQuestInfoByQuestID then
					taskQuestInfo = self.API.GetTaskQuestInfoByQuestID(numericQuestID)
				end
				local displayAsObjective = taskQuestInfo and taskQuestInfo.displayAsObjective == true or false

				local snapshot = {
					questID = numericQuestID,
					questLogIndex = self:SafeToNumber(questInfo.questLogIndex) or questLogIndex,
					title = type(questInfo.title) == "string" and questInfo.title or nil,
					isHidden = questInfo.isHidden == true,
					isTask = isTaskQuest and true or false,
					isOnMap = questInfo.isOnMap == true,
					hasLocalPOI = questInfo.hasLocalPOI == true,
					isComplete = questInfo.isComplete == true,
					isWorldQuest = isWorldQuest and true or false,
					displayAsObjective = displayAsObjective,
					isBonusObjective = displayAsObjective,
					tagInfo = nil,
					poiIcon = nil,
				}
				snapshot.taskAnnouncementType = snapshot.isWorldQuest and "world"
					or (snapshot.isBonusObjective and "bonus" or nil)

				snapshotByQuestID[numericQuestID] = snapshot
				snapshotOrder[#snapshotOrder + 1] = numericQuestID
			end
		end
	end

	wipe(snapshotState.byQuestID)
	wipe(snapshotState.order)
	for questID, snapshot in pairs(snapshotByQuestID) do
		snapshotState.byQuestID[questID] = snapshot
	end
	for index, questID in ipairs(snapshotOrder) do
		snapshotState.order[index] = questID
	end
	snapshotState.lastUnreadableRow = nil
	snapshotState.generation = (snapshotState.generation or 0) + 1

	if totalEntries > 0 and #snapshotOrder == 0 and not snapshotState.didLogEmptyBuildDiagnostics then
		snapshotState.didLogEmptyBuildDiagnostics = true
		local sampleParts = {}
		for index = 1, #sampleRows do
			local row = sampleRows[index]
			sampleParts[#sampleParts + 1] = string.format(
				"#%d title=%s header=%s questID=%s task=%s onMap=%s poi=%s",
				row.index,
				self:SafeToString(row.title, "<nil>"),
				tostring(row.isHeader),
				self:SafeToString(row.questID, "<nil>"),
				tostring(row.isTask),
				tostring(row.isOnMap),
				tostring(row.hasLocalPOI)
			)
		end
		self:Debug(
			"empty quest snapshot. totalEntries="
				.. tostring(totalEntries)
				.. " samples: "
				.. table.concat(sampleParts, " | "),
			"quest"
		)
	elseif #snapshotOrder > 0 then
		snapshotState.didLogEmptyBuildDiagnostics = false
	end

	return snapshotState
end

function QuestTogether:EnsureQuestSnapshotStore()
	local snapshotState = self.GetQuestSnapshotStateStore and self:GetQuestSnapshotStateStore() or nil
	if type(snapshotState) ~= "table" then
		return nil
	end
	if type(snapshotState.byQuestID) ~= "table" or next(snapshotState.byQuestID) == nil then
		if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
			return snapshotState
		end
		return self:RebuildQuestSnapshotStore()
	end
	return snapshotState
end

local function IsQuestRecurringFrequency(frequency)
	local frequencyEnum = Enum and Enum.QuestFrequency or nil
	if not frequencyEnum or frequency == nil then
		return false
	end

	return frequency == frequencyEnum.Daily
		or frequency == frequencyEnum.Weekly
		or frequency == frequencyEnum.ResetByScheduler
end

local function GetQuestClassificationFlags(classification)
	local classificationEnum = Enum and Enum.QuestClassification or nil
	if not classificationEnum or classification == nil then
		return {
			isLegendary = false,
			isRepeatable = false,
			isImportant = false,
			isMeta = false,
			isCampaign = false,
			isCalling = false,
		}
	end

	return {
		isLegendary = classification == classificationEnum.Legendary,
		isRepeatable = classification == classificationEnum.Recurring,
		isImportant = classification == classificationEnum.Important,
		isMeta = classification == classificationEnum.Meta,
		isCampaign = classification == classificationEnum.Campaign,
		isCalling = classification == classificationEnum.Calling,
	}
end

local function ResolveQuestOfferAnnouncementIcon(classification, frequency)
	local flags = GetQuestClassificationFlags(classification)
	if flags.isCampaign then
		return "CampaignAvailableQuestIcon", "atlas"
	elseif flags.isLegendary then
		return "legendaryavailablequesticon", "atlas"
	elseif flags.isCalling then
		return "CampaignAvailableDailyQuestIcon", "atlas"
	elseif flags.isImportant then
		return "importantavailablequesticon", "atlas"
	elseif flags.isMeta then
		return "Wrapperavailablequesticon", "atlas"
	elseif IsQuestRecurringFrequency(frequency) then
		return "Recurringavailablequesticon", "atlas"
	elseif flags.isRepeatable then
		return "Interface/GossipFrame/DailyActiveQuestIcon", "texture"
	end

	return "Interface/GossipFrame/AvailableQuestIcon", "texture"
end

local function ResolveQuestActiveAnnouncementIcon(classification, frequency, isComplete)
	local flags = GetQuestClassificationFlags(classification)
	if isComplete then
		if flags.isCampaign then
			return "CampaignActiveQuestIcon", "atlas"
		elseif flags.isCalling then
			return "CampaignActiveDailyQuestIcon", "atlas"
		elseif IsQuestRecurringFrequency(frequency) then
			return "Recurringactivequesticon", "atlas"
		elseif flags.isLegendary then
			return "legendaryactivequesticon", "atlas"
		elseif flags.isImportant then
			return "importantactivequesticon", "atlas"
		elseif flags.isMeta then
			return "Wrapperactivequesticon", "atlas"
		end

		return "Interface/GossipFrame/ActiveQuestIcon", "texture"
	end

	if flags.isCampaign or flags.isCalling then
		return "CampaignInProgressQuestIcon", "atlas"
	elseif IsQuestRecurringFrequency(frequency) then
		return "RepeatableInProgressquesticon", "atlas"
	elseif flags.isLegendary then
		return "legendaryInProgressquesticon", "atlas"
	elseif flags.isImportant then
		return "importantInProgressquesticon", "atlas"
	elseif flags.isMeta then
		return "WrapperInProgressquesticon", "atlas"
	end

	return "SideInProgressquesticon", "atlas"
end

local function GetQuestAnnouncementLookInfo(addon, questId)
	local numericQuestId = addon and addon.NormalizeQuestID and addon:NormalizeQuestID(questId) or nil
	if not numericQuestId then
		return nil, nil
	end

	local classification = addon.API and addon.API.GetQuestClassification and addon.API.GetQuestClassification(numericQuestId)
		or nil
	local frequency = addon.API and addon.API.GetQuestFrequency and addon.API.GetQuestFrequency(numericQuestId) or nil
	if classification ~= nil and frequency ~= nil then
		return classification, frequency
	end

	local questLogIndex = addon.API and addon.API.GetQuestLogIndexForQuestID
		and addon.API.GetQuestLogIndexForQuestID(numericQuestId)
		or nil
	if not questLogIndex then
		return classification, frequency
	end

	local questInfo = addon.API and addon.API.GetQuestLogInfo and addon.API.GetQuestLogInfo(questLogIndex) or nil
	if type(questInfo) ~= "table" then
		return classification, frequency
	end

	if classification == nil then
		classification = SanitizeQuestInfoEnumValue(questInfo.questClassification)
	end
	if frequency == nil then
		frequency = SanitizeQuestInfoEnumValue(questInfo.frequency)
	end

	return classification, frequency
end

function QuestTogether:GetQuestStateAnnouncementIconInfo(eventType, questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if numericQuestId and self.API then
		local classification, frequency = GetQuestAnnouncementLookInfo(self, numericQuestId)
		local iconAsset = nil
		local iconKind = nil
		if eventType == "QUEST_ACCEPTED" then
			iconAsset, iconKind = ResolveQuestOfferAnnouncementIcon(classification, frequency)
		else
			local useCompleteIcon = eventType == "QUEST_COMPLETED" or eventType == "QUEST_READY_TO_TURN_IN"
			iconAsset, iconKind = ResolveQuestActiveAnnouncementIcon(classification, frequency, useCompleteIcon)
		end
		if type(iconAsset) == "string" and iconAsset ~= "" then
			return iconAsset, iconKind
		end
	end

	local texturePath = self.NAMEPLATE_QUEST_ICON_TEXTURE
	if type(texturePath) ~= "string" or texturePath == "" then
		return nil, nil
	end

	return texturePath, "texture"
end

function QuestTogether:GetWorldQuestAnnouncementIconInfo(questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return "worldquest-icon", "atlas"
	end

	local questTagType = self.API and self.API.GetQuestPoiTagType and self.API.GetQuestPoiTagType(numericQuestId) or nil
	if questTagType ~= nil and self.API and self.API.GetQuestTagAtlas then
		local atlas = self.API.GetQuestTagAtlas(nil, questTagType)
		if type(atlas) == "string" and atlas ~= "" then
			return atlas, "atlas"
		end
	end

	return "worldquest-icon", "atlas"
end

function QuestTogether:GetBonusObjectiveAnnouncementIconInfo(eventType, questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return "Bonus-Objective-Star", "atlas"
	end

	local questStateEventType = eventType
	if eventType == "BONUS_OBJECTIVE_ENTERED" then
		questStateEventType = "QUEST_ACCEPTED"
	elseif eventType == "BONUS_OBJECTIVE_PROGRESS" or eventType == "BONUS_OBJECTIVE_LEFT" then
		questStateEventType = "QUEST_PROGRESS"
	elseif eventType == "BONUS_OBJECTIVE_COMPLETED" then
		questStateEventType = "QUEST_COMPLETED"
	end

	local asset, kind = self:GetQuestStateAnnouncementIconInfo(questStateEventType, numericQuestId)
	if type(asset) == "string" and asset ~= "" then
		return asset, kind
	end

	return "Bonus-Objective-Star", "atlas"
end

function QuestTogether:GetAnnouncementIconInfo(eventType, questId)
	if self:IsWorldQuestAnnouncementType(eventType) then
		return self:GetWorldQuestAnnouncementIconInfo(questId)
	end
	if self:IsBonusObjectiveAnnouncementType(eventType) then
		return self:GetBonusObjectiveAnnouncementIconInfo(eventType, questId)
	end

	return self:GetQuestStateAnnouncementIconInfo(eventType, questId)
end

function QuestTogether:GetAnnouncementIconChatTag(eventType, size, iconAsset, iconKind)
	local asset = iconAsset
	local kind = iconKind
	if type(asset) ~= "string" or asset == "" then
		asset, kind = self:GetAnnouncementIconInfo(eventType, nil)
	end
	if type(asset) == "string" and asset ~= "" then
		return self:GetIconChatTagFromAsset(asset, kind, size)
	end

	return self:GetQuestIconChatTag(size)
end

function QuestTogether:GetPlayerAnnouncementLocationInfo()
	local mapID = self.API.GetBestMapForUnit and self.API.GetBestMapForUnit("player") or nil
	local zoneName = nil
	if mapID and self.API.GetMapInfo then
		local mapInfo = self.API.GetMapInfo(mapID)
		if type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
			zoneName = mapInfo.name
		end
	end

	local coordX = nil
	local coordY = nil
	if mapID and self.API.GetPlayerMapPosition then
		local position = self.API.GetPlayerMapPosition(mapID, "player")
		if position then
			local rawX = position.x or (position.GetXY and select(1, position:GetXY())) or nil
			local rawY = position.y or (position.GetXY and select(2, position:GetXY())) or nil
			local numericX = self:SafeToNumber(rawX)
			local numericY = self:SafeToNumber(rawY)
			if numericX and numericY then
				coordX = numericX * 100
				coordY = numericY * 100
			end
		end
	end

	local warModeActive = self.API.IsWarModeActive and self.API.IsWarModeActive() and true or false
	return {
		mapID = mapID,
		zoneName = zoneName or "",
		coordX = coordX,
		coordY = coordY,
		warMode = warModeActive,
	}
end

function QuestTogether:IsAnnouncementSenderNearbyByLocation(locationInfo)
	if type(locationInfo) ~= "table" then
		return false
	end

	local localInfo = self.GetPlayerAnnouncementLocationInfo and self:GetPlayerAnnouncementLocationInfo() or nil
	if type(localInfo) ~= "table" then
		return false
	end

	local localZoneName = type(localInfo.zoneName) == "string" and localInfo.zoneName or ""
	local remoteZoneName = type(locationInfo.zoneName) == "string" and locationInfo.zoneName or ""
	if localZoneName == "" or remoteZoneName == "" or localZoneName ~= remoteZoneName then
		return false
	end

	local localWarMode = self:NormalizeAnnouncementWarModeValue(localInfo.warMode)
	local remoteWarMode = self:NormalizeAnnouncementWarModeValue(locationInfo.warMode)
	if localWarMode == nil or remoteWarMode == nil or localWarMode ~= remoteWarMode then
		return false
	end

	local localCoordX = self:SafeToNumber(localInfo.coordX)
	local localCoordY = self:SafeToNumber(localInfo.coordY)
	local remoteCoordX = self:SafeToNumber(locationInfo.coordX)
	local remoteCoordY = self:SafeToNumber(locationInfo.coordY)
	if not localCoordX or not localCoordY or not remoteCoordX or not remoteCoordY then
		return false
	end

	local deltaX = localCoordX - remoteCoordX
	local deltaY = localCoordY - remoteCoordY
	local radius = self.ANNOUNCEMENT_NEARBY_RADIUS or 5
	return (deltaX * deltaX + deltaY * deltaY) <= (radius * radius)
end

function QuestTogether:BuildAnnouncementLocationSuffix(locationInfo)
	if type(locationInfo) ~= "table" then
		return ""
	end

	local parts = {}
	local zoneName = type(locationInfo.zoneName) == "string" and locationInfo.zoneName or ""
	if zoneName ~= "" then
		parts[#parts + 1] = zoneName
	end

	local coordX = self:SafeToNumber(locationInfo.coordX)
	local coordY = self:SafeToNumber(locationInfo.coordY)
	if coordX and coordY then
		parts[#parts + 1] = string.format("%.1f, %.1f", coordX, coordY)
	end

	local warMode = self:NormalizeAnnouncementWarModeValue(locationInfo.warMode)
	if warMode ~= nil then
		parts[#parts + 1] = warMode and "WM On" or "WM Off"
	end

	if #parts == 0 then
		return ""
	end

	return " |cff999999[" .. table.concat(parts, " | ") .. "]|r"
end

function QuestTogether:BuildChatLogSpeakerLabel(targetName, classFile)
	local trimmedTargetName = self:GetShortDisplayName(targetName)
	local speakerLabel = trimmedTargetName ~= "" and trimmedTargetName or "QT"
	local speakerColor = self:GetClassColorCode(classFile)

	if LinkUtil and LinkUtil.FormatLink then
		local linkDisplayText = "[" .. speakerLabel .. "]"
		local linkText = LinkUtil.FormatLink(self.chatLogLinkType or "questtogetherlog", linkDisplayText, tostring(targetName or ""))
		return speakerColor .. linkText .. "|r"
	end

	return speakerColor .. speakerLabel .. "|r"
end

function QuestTogether:BuildChatLogQuestLabel(questId, questTitle)
	local numericQuestId = self:SafeToNumber(questId)
	local titleText = tostring(questTitle or "")
	if not numericQuestId or titleText == "" or not LinkUtil or not LinkUtil.FormatLink then
		return titleText
	end

	local linkDisplayText = "[" .. titleText .. "]"
	return LinkUtil.FormatLink(self.chatLogQuestLinkType or "questtogetherquest", linkDisplayText, tostring(numericQuestId))
end

function QuestTogether:DecorateAnnouncementMessageWithQuestLink(message, eventType, questId)
	if not self.questTitleLinkEventTypes or not self.questTitleLinkEventTypes[eventType] then
		return self:SafeToString(message, "")
	end

	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return self:SafeToString(message, "")
	end

	local messageText = self:SafeToString(message, "")
	local prefixText, questTitle = SafeMatch(messageText, "^(.-:%s+)(.+)$")
	if not prefixText or not questTitle or questTitle == "" then
		return messageText
	end

	return prefixText .. self:BuildChatLogQuestLabel(numericQuestId, questTitle)
end

function QuestTogether:GetQuestStatusLabel(questId)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return "Unknown"
	end

	local statusState = self.GetTrackedQuestStatusState and self:GetTrackedQuestStatusState(numericQuestId, true) or nil
	if type(statusState) == "table" then
		if statusState.isFlaggedCompleted == true then
			return "Completed"
		end
		if statusState.isReadyForTurnIn == true then
			return "Ready to Turn In"
		end
		if statusState.isComplete == true then
			return "Objectives Complete"
		end
		if statusState.isTracked == true or statusState.isOnQuest == true then
			return "In Progress"
		end
	end

	return "Not Started"
end

function QuestTogether:GetTrackedQuestStatusState(questId, allowLiveFallback)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return nil
	end

	local tracker = self.GetPlayerTracker and self:GetPlayerTracker() or nil
	local trackedQuest = tracker and tracker[numericQuestId] or nil
	local state = {
		isTracked = trackedQuest ~= nil,
		isComplete = trackedQuest and trackedQuest.isComplete == true or false,
		isReadyForTurnIn = trackedQuest and trackedQuest.isReadyForTurnIn == true or false,
		isFlaggedCompleted = false,
		isOnQuest = false,
	}

	if type(trackedQuest) == "table" then
		state.isOnQuest = true
	end

	if self.EnsureQuestSnapshotStore then
		self:EnsureQuestSnapshotStore()
	end
	local snapshot = self.GetQuestSnapshot and self:GetQuestSnapshot(numericQuestId) or nil
	if type(snapshot) == "table" then
		state.isTracked = true
		state.isOnQuest = true
		if state.isComplete ~= true then
			state.isComplete = snapshot.isComplete == true
		end
	end

	if allowLiveFallback ~= true then
		return state
	end

	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
		return state
	end

	for field, method in pairs({
		isFlaggedCompleted = "IsQuestFlaggedCompleted",
		isReadyForTurnIn = "IsQuestReadyForTurnIn",
		isComplete = "IsQuestComplete",
		isOnQuest = "IsOnQuest",
	}) do
		if self.API and type(self.API[method]) == "function" then
			local value = self.API[method](numericQuestId)
			if self:CanAccessValue(value) and type(value) == "boolean" then
				state[field] = value
			end
		end
	end
	if not state.isOnQuest then
		local questLogIndex = self.API and self.API.GetQuestLogIndexForQuestID and self.API.GetQuestLogIndexForQuestID(numericQuestId)
		local isOnQuest = self.API and self.API.IsOnQuest and self.API.IsOnQuest(numericQuestId)
		state.isOnQuest = (questLogIndex ~= nil) or (isOnQuest and true or false)
	end

	return state
end

function QuestTogether:GetQuestShareableStatusLabel(questId)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return "Unknown"
	end

	local statusState = self:GetTrackedQuestStatusState(numericQuestId, true)
	if type(statusState) ~= "table" or statusState.isOnQuest ~= true then
		return "Unknown"
	end

	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
		return "Unknown"
	end

	local pushable = self.API and self.API.IsPushableQuest and self.API.IsPushableQuest(numericQuestId)
	if not self:CanAccessValue(pushable) or type(pushable) ~= "boolean" then return "Unknown" end
	return pushable and "Yes" or "No"
end

function QuestTogether:NormalizeQuestLinkTitleText(titleText)
	local normalizedText = self:SafeTrimString(titleText, "")
	if SafeMatch(normalizedText, "^%[.+%]$") then
		normalizedText = string.sub(normalizedText, 2, -2)
	end
	return normalizedText
end

function QuestTogether:BuildQuestStatusMessage(questId, fallbackTitle)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return "Quest status unavailable."
	end

	local questTitle = self:GetQuestTitle(numericQuestId)
	local normalizedFallbackTitle = self:NormalizeQuestLinkTitleText(fallbackTitle)
	if
		normalizedFallbackTitle ~= ""
		and (questTitle == nil or questTitle == "" or questTitle == ("Quest " .. tostring(numericQuestId)))
	then
		questTitle = normalizedFallbackTitle
	end
	local statusLabel = self:GetQuestStatusLabel(numericQuestId)
	local shareableLabel = self:GetQuestShareableStatusLabel(numericQuestId)
	return "Quest Status: " .. tostring(questTitle) .. " - " .. tostring(statusLabel) .. " | Shareable: " .. tostring(shareableLabel)
end

function QuestTogether:GetQuestStatusAnnouncementEventType(questId)
	local statusLabel = self:GetQuestStatusLabel(questId)
	if statusLabel == "Completed" or statusLabel == "Objectives Complete" then
		return "QUEST_COMPLETED"
	end
	if statusLabel == "Ready to Turn In" then
		return "QUEST_READY_TO_TURN_IN"
	end
	if statusLabel == "In Progress" then
		return "QUEST_PROGRESS"
	end
	if statusLabel == "Not Started" then
		return "QUEST_ACCEPTED"
	end

	return "QUEST_PROGRESS"
end

function QuestTogether:GetTrackedQuestAnnouncementIcon(questData)
	if type(questData) ~= "table" then
		return nil, nil
	end

	local iconAsset = tostring(questData.iconAsset or "")
	if iconAsset == "" then
		return nil, nil
	end

	local iconKind = tostring(questData.iconKind or "")
	if iconKind == "" then
		iconKind = nil
	end

	return iconAsset, iconKind
end

function QuestTogether:RefreshTrackedQuestAnnouncementIcon(questId, questData, eventType)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or type(questData) ~= "table" then
		return nil, nil
	end

	local resolvedEventType = eventType or self:GetQuestStatusAnnouncementEventType(numericQuestId)
	local iconAsset, iconKind = self:GetAnnouncementIconInfo(resolvedEventType, numericQuestId)
	questData.iconAsset = iconAsset or nil
	questData.iconKind = iconKind or nil
	return iconAsset, iconKind
end

function QuestTogether:PrintQuestStatus(questId, fallbackTitle)
	local message = self:BuildQuestStatusMessage(questId, fallbackTitle)
	local eventType = self:GetQuestStatusAnnouncementEventType(questId)
	self:PrintConsoleAnnouncement(message, nil, nil, eventType)
end

function QuestTogether:GetQuestCompareRemoteStatusLabel(isComplete)
	if isComplete then
		return "Complete"
	end

	return "In Progress"
end

function QuestTogether:GetQuestCompareShareableToYouLabel(isPushable)
	if type(isPushable) == "boolean" then
		return isPushable and "Yes" or "No"
	end

	if type(isPushable) == "string" then
		local normalized = string.lower(isPushable)
		if isPushable == "1" or normalized == "true" then
			return "Yes"
		end
		if isPushable == "0" or normalized == "false" then
			return "No"
		end
	end

	return "Unknown"
end

function QuestTogether:BuildQuestCompareMessage(remoteName, compareEntry)
	if type(compareEntry) ~= "table" then
		return "Quest comparison unavailable."
	end

	local questId = self:SafeToNumber(compareEntry.questId)
	local questTitle = tostring(compareEntry.questTitle or "")
	if questTitle == "" then
		questTitle = self:GetQuestTitle(questId)
	end
	local localStatus = self:GetQuestStatusLabel(questId)
	local shareableLabel = self:GetQuestCompareShareableToYouLabel(compareEntry.isPushable)
	local remoteStatus = self:GetQuestCompareRemoteStatusLabel(compareEntry.isComplete)
	local decoratedQuestTitle = self:BuildChatLogQuestLabel(questId, questTitle)

	return tostring(decoratedQuestTitle)
		.. " | Them: "
		.. tostring(remoteStatus)
		.. " | You: "
		.. tostring(localStatus)
		.. " | Shareable to You: "
		.. tostring(shareableLabel)
end

function QuestTogether:PrintQuestCompareMessage(remoteName, compareEntry, classFile)
	local eventType = compareEntry and compareEntry.isComplete and "QUEST_COMPLETED" or "QUEST_PROGRESS"
	local locationInfo = {
		questId = compareEntry and compareEntry.questId or nil,
	}
	self:PrintConsoleAnnouncement(
		self:BuildQuestCompareMessage(remoteName, compareEntry),
		remoteName,
		classFile,
		eventType,
		nil,
		nil,
		locationInfo
	)
end

function QuestTogether:PrintQuestCompareStart(remoteName, classFile)
	self:PrintConsoleAnnouncement("Comparing quests...", remoteName, classFile, "QUEST_PROGRESS")
end

function QuestTogether:PrintQuestCompareDone(remoteName, count, classFile)
	local suffix = ""
	local numericCount = self:SafeToNumber(count)
	if numericCount then
		suffix = string.format(" (%d quests)", numericCount)
	end
	self:PrintConsoleAnnouncement("Finished comparing quests" .. suffix .. ".", remoteName, classFile, "QUEST_COMPLETED")
end

function QuestTogether:BuildConsoleAnnouncementMessage(targetName, message, classFile, eventType, iconAsset, iconKind, locationInfo)
	local iconTag = self:GetAnnouncementIconChatTag(eventType, 14, iconAsset, iconKind)
	local questId = type(locationInfo) == "table" and locationInfo.questId or nil
	local trimmedMessage = self:DecorateAnnouncementMessageWithQuestLink(tostring(message or ""), eventType, questId)
	local body = trimmedMessage
	local speakerText = self:BuildChatLogSpeakerLabel(targetName, classFile)

	if iconTag ~= "" then
		return iconTag .. speakerText .. "|cffffd200: " .. body .. "|r"
	end

	return speakerText .. "|cffffd200: " .. body .. "|r"
end

function QuestTogether:BuildPingResponseMessage(pongData)
	if type(pongData) ~= "table" then
		return "|cff33ff99QuestTogether|r: Pong: <invalid payload>"
	end

	local senderName = pongData.senderName or "Unknown"
	local speakerLabel = self:GetShortDisplayName(senderName)
	local speakerColor = self:GetClassColorCode(pongData.classFile)
	local coloredName = speakerColor .. tostring(speakerLabel or "Unknown") .. "|r"
	local realmName = tostring(pongData.realmName or "")
	local raceName = tostring(pongData.raceName or "")
	local className = tostring(pongData.className or pongData.classFile or "")
	local level = self:SafeToNumber(pongData.level)

	local parts = {}
	parts[#parts + 1] = coloredName
	if realmName ~= "" then
		parts[#parts + 1] = "(" .. realmName .. ")"
	end
	if level then
		parts[#parts + 1] = "Lvl " .. tostring(math.floor(level))
	end
	if raceName ~= "" then
		parts[#parts + 1] = raceName
	end
	if className ~= "" then
		parts[#parts + 1] = className
	end
	local addonVersion = tostring(pongData.addonVersion or "")
	if addonVersion ~= "" then
		parts[#parts + 1] = "QT v" .. addonVersion
	end

	local locationBits = {}
	local zoneName = tostring(pongData.zoneName or "")
	if zoneName ~= "" then
		locationBits[#locationBits + 1] = zoneName
	end
	local coordX = self:SafeToNumber(pongData.coordX)
	local coordY = self:SafeToNumber(pongData.coordY)
	if coordX and coordY then
		locationBits[#locationBits + 1] = self:BuildPingCoordinateLabel(pongData.mapID, coordX, coordY)
	end
	local warMode = self:NormalizeAnnouncementWarModeValue(pongData.warMode)
	if warMode ~= nil then
		locationBits[#locationBits + 1] = warMode and "WM On" or "WM Off"
	end
	if #locationBits > 0 then
		parts[#parts + 1] = "- " .. table.concat(locationBits, " | ")
	end

	return "|cff33ff99QuestTogether|r: Pong: " .. table.concat(parts, " ")
end

function QuestTogether:BuildPingCoordinateLabel(mapID, coordX, coordY)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericX or not numericY then
		return ""
	end

	local bracketedText = string.format("[%.1f, %.1f]", numericX, numericY)
	local numericMapID = self:SafeToNumber(mapID)
	if not numericMapID or not LinkUtil or not LinkUtil.FormatLink then
		return bracketedText
	end

	local linkData = string.format("%d:%.1f:%.1f", numericMapID, numericX, numericY)
	return LinkUtil.FormatLink(self.chatLogCoordLinkType or "questtogethercoord", bracketedText, linkData)
end

function QuestTogether:PrintPingResponse(pongData)
	self:PrintChatLogRaw(self:BuildPingResponseMessage(pongData))
end

function QuestTogether:CreateTomTomWaypoint(mapID, coordX, coordY)
	local numericMapID = self:SafeToNumber(mapID)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericMapID or not numericX or not numericY then
		return false
	end

	if not (self.API and self.API.IsAddOnLoaded and self.API.IsAddOnLoaded("TomTom")) then
		return false
	end

	local tomTom = _G.TomTom
	if not (tomTom and tomTom.AddWaypoint) then
		return false
	end

	-- TomTom may reject waypoint creation during transient map states; keep fallback path alive.
	local ok = pcall(tomTom.AddWaypoint, tomTom, numericMapID, numericX / 100, numericY / 100, {
		title = string.format("QuestTogether %.1f, %.1f", numericX, numericY),
		from = "QuestTogether/ping",
	})
	return ok and true or false
end

function QuestTogether:CreateBlizzardWaypoint(mapID, coordX, coordY)
	local numericMapID = self:SafeToNumber(mapID)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericMapID or not numericX or not numericY then
		return false
	end

	local function applyWaypoint()
		if not (self.API and self.API.CanSetUserWaypointOnMap and self.API.CanSetUserWaypointOnMap(numericMapID)) then
			return false
		end

		local point = self.API.CreateUiMapPoint and self.API.CreateUiMapPoint(numericMapID, numericX / 100, numericY / 100)
		if not point then
			return false
		end

		if self.API.SetUserWaypoint then
			self.API.SetUserWaypoint(point)
		end
		if self.API.SetSuperTrackedUserWaypoint then
			pcall(self.API.SetSuperTrackedUserWaypoint, true)
		end
		return true
	end

	if self.RunOrDeferWork then
		self:SetPendingWaypointIntent({
			mapID = numericMapID,
			coordX = numericX,
			coordY = numericY,
		})
		local applied = false
		local ranNow = self:RunOrDeferWork("waypoint_mutation", "user_waypoint", function()
			local pending = self.GetRuntimeWorkStateStore
				and self:GetRuntimeWorkStateStore().pendingWaypointIntent
				or nil
			self:SetPendingWaypointIntent(nil)
			if pending then
				applied = applyWaypoint()
			end
		end, 0.2, "CreateBlizzardWaypoint")
		if not ranNow then
			return true
		end
		return applied
	end

	return applyWaypoint()
end

function QuestTogether:OpenPingWaypoint(mapID, coordX, coordY)
	if self:CreateTomTomWaypoint(mapID, coordX, coordY) then
		return true
	end

	return self:CreateBlizzardWaypoint(mapID, coordX, coordY)
end

function QuestTogether:PrintConsoleAnnouncement(message, targetName, classFile, eventType, iconAsset, iconKind, locationInfo)
	local speakerName = targetName
	local isRemoteSpeaker = false
	if speakerName == nil or speakerName == "" then
		speakerName = self:GetPlayerFullName() or self:GetPlayerName()
	end
	local resolvedClassFile = classFile
	if not resolvedClassFile or resolvedClassFile == "" then
		if speakerName ~= nil and speakerName ~= "" and self.NormalizeMemberName then
			local normalizedSpeaker = self:NormalizeMemberName(speakerName)
			local normalizedPlayer = self:NormalizeMemberName(self:GetPlayerFullName() or self:GetPlayerName() or "")
			isRemoteSpeaker = normalizedSpeaker and normalizedPlayer and normalizedSpeaker ~= normalizedPlayer and true or false
			if isRemoteSpeaker then
				resolvedClassFile = self.GetGroupedSenderClassFile and self:GetGroupedSenderClassFile(speakerName) or nil
			end
		end
		if (not resolvedClassFile or resolvedClassFile == "") and not isRemoteSpeaker then
			resolvedClassFile = self:GetPlayerClassFile()
		end
	end
	self:PrintChatLogRaw(
		self:BuildConsoleAnnouncementMessage(
			speakerName,
			message,
			resolvedClassFile,
			eventType,
			iconAsset,
			iconKind,
			locationInfo
		)
	)
end

function QuestTogether:ShowChatLogSpeakerMenu(ownerFrame, speakerName)
	if not MenuUtil or not MenuUtil.CreateContextMenu then
		return false
	end

	MenuUtil.CreateContextMenu(ownerFrame, function(_, rootDescription)
		self:PopulateChatLogSpeakerMenu(rootDescription, ownerFrame, speakerName)
	end)
	return true
end

function QuestTogether:IsIgnoredPlayerName(playerName)
	local fullName = tostring(playerName or "")
	if fullName == "" or not self.API or not self.API.IsOnIgnoredList then
		return false
	end

	if self.API.IsOnIgnoredList(fullName) then
		return true
	end
	-- Hiding our surname is presentation only; never query social identity
	-- using a first-name-only label that could identify somebody else.
	if self:UsesRegionalPlayerNames() then
		return false
	end

	local shortName = self:GetShortDisplayName(fullName)
	if shortName ~= "" and shortName ~= fullName and self.API.IsOnIgnoredList(shortName) then
		return true
	end

	return false
end

function QuestTogether:InviteChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.InviteUnit then
		return false
	end

	self.API.InviteUnit(fullName)
	return true
end

function QuestTogether:WhisperChatLogSpeaker(speakerName, ownerFrame)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.SendTell then
		return false
	end

	self.API.SendTell(fullName, ownerFrame)
	return true
end

function QuestTogether:AddFriendFromChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.AddFriend then
		return false
	end

	self.API.AddFriend(fullName)
	return true
end

function QuestTogether:ToggleIgnoreChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.AddOrDelIgnore then
		return false
	end

	self.API.AddOrDelIgnore(fullName)
	return true
end

function QuestTogether:CompareQuestsWithChatLogSpeaker(speakerName)
	local fullName = self:NormalizeMemberName(speakerName) or tostring(speakerName or "")
	if fullName == "" or not self.RequestQuestCompare then
		return false
	end

	return self:RequestQuestCompare(fullName)
end

function QuestTogether:PopulateChatLogSpeakerMenu(rootDescription, ownerFrame, speakerName)
	if not rootDescription then
		return false
	end

	local fullName = tostring(speakerName or "")
	local shortName = self:GetShortDisplayName(fullName)
	local isSeparate = self:GetOption("chatLogDestination") == "separate"
	local isIgnored = false
	-- Context menus should stay usable even if ignored-list lookups fail for edge-case names.
	local ignoredOk, ignoredResult = pcall(function()
		return self:IsIgnoredPlayerName(fullName)
	end)
	if ignoredOk and ignoredResult then
		isIgnored = true
	end

	rootDescription:CreateTitle(shortName ~= "" and shortName or "QuestTogether")

	if fullName ~= "" then
		rootDescription:CreateButton("Invite", function()
			self:InviteChatLogSpeaker(fullName)
		end)
		rootDescription:CreateButton("Whisper", function()
			self:WhisperChatLogSpeaker(fullName, ownerFrame)
		end)
		rootDescription:CreateButton("Add Friend", function()
			self:AddFriendFromChatLogSpeaker(fullName)
		end)
		rootDescription:CreateButton(isIgnored and "Unignore" or "Ignore", function()
			self:ToggleIgnoreChatLogSpeaker(fullName)
		end)
		rootDescription:CreateButton("Compare Quests", function()
			self:CompareQuestsWithChatLogSpeaker(fullName)
		end)
	end

	if rootDescription.CreateDivider then
		rootDescription:CreateDivider()
	end

	local buttonText = isSeparate and "Move QuestTogether Logs to Main Window" or "Move QuestTogether Logs to Separate Window"
	rootDescription:CreateButton(buttonText, function()
		self:SetOption("chatLogDestination", isSeparate and "main" or "separate")
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
	end)

	return true
end

function QuestTogether:HandleChatLogSpeakerLink(link, text, linkData, contextData)
	local speakerName = linkData and linkData.options
	if not speakerName or speakerName == "" then
		return LinkProcessorResponse.Handled
	end
	if self.API and self.API.IsModifiedClick and self.API.IsModifiedClick("CHATLINK") then
		return LinkProcessorResponse.Handled
	end
	return self:ShowChatLogSpeakerMenu(contextData and contextData.frame or UIParent, speakerName) and LinkProcessorResponse.Handled
		or LinkProcessorResponse.Handled
end

function QuestTogether:HandleChatLogQuestLink(link, text, linkData, contextData)
	local questId = linkData and linkData.options
	if not questId or questId == "" then
		return LinkProcessorResponse.Handled
	end
	if self.API and self.API.IsModifiedClick and self.API.IsModifiedClick("CHATLINK") then
		return LinkProcessorResponse.Handled
	end

	self:PrintQuestStatus(questId, text)
	return LinkProcessorResponse.Handled
end

function QuestTogether:HandleChatLogCoordLink(link, text, linkData, contextData)
	local options = tostring(linkData and linkData.options or "")
	local mapID, coordX, coordY = SafeMatch(options, "^([^:]+):([^:]+):([^:]+)$")
	if not mapID or not coordX or not coordY then
		return LinkProcessorResponse.Handled
	end
	if self.API and self.API.IsModifiedClick and self.API.IsModifiedClick("CHATLINK") then
		return LinkProcessorResponse.Handled
	end

	self:OpenPingWaypoint(mapID, coordX, coordY)
	return LinkProcessorResponse.Handled
end

function QuestTogether:TryInstallChatLogLinkHandler()
	if self.chatLogLinkHandlerInstalled then
		return
	end
	if not LinkUtil or not LinkUtil.RegisterLinkHandler then
		return
	end

	local speakerRegistered = LinkUtil.IsLinkHandlerRegistered and LinkUtil.IsLinkHandlerRegistered(self.chatLogLinkType)
	if not speakerRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogSpeakerLink(link, text, linkData, contextData)
		end)
	end

	local questRegistered = LinkUtil.IsLinkHandlerRegistered and LinkUtil.IsLinkHandlerRegistered(self.chatLogQuestLinkType)
	if not questRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogQuestLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogQuestLink(link, text, linkData, contextData)
		end)
	end
	local coordRegistered = LinkUtil.IsLinkHandlerRegistered and LinkUtil.IsLinkHandlerRegistered(self.chatLogCoordLinkType)
	if not coordRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogCoordLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogCoordLink(link, text, linkData, contextData)
		end)
	end
	self.chatLogLinkHandlerInstalled = true
end

function QuestTogether:PrintChatLogDestinationMessage()
	self:PrintConsoleAnnouncement("You will now see QuestTogether logs here.")
end

function QuestTogether:GetPlayerName()
	local playerName = self.API and self.API.UnitName and self.API.UnitName("player") or nil
	return playerName or "Unknown"
end

function QuestTogether:IsSelfSender(sender)
	if not self:CanAccessValue(sender) or type(sender) ~= "string" or sender == "" then
		return false
	end
	local playerName = self:GetPlayerFullName()
	return playerName ~= nil and self:NormalizeMemberName(sender) == self:NormalizeMemberName(playerName)
end

function QuestTogether:GetAnnouncementOptionKey(eventType)
	local keysByType = {
		QUEST_ACCEPTED = "announceAccepted",
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

function QuestTogether:IsWorldQuest(questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return false
	end

	if self.API and self.API.IsWorldQuest then
		local apiResult = self.API.IsWorldQuest(numericQuestId)
		if apiResult ~= nil then
			return apiResult == true
		end
	end

	if self.EnsureQuestSnapshotStore then
		self:EnsureQuestSnapshotStore()
	end
	local snapshot = self.GetQuestSnapshot and self:GetQuestSnapshot(numericQuestId) or nil
	if snapshot and snapshot.isWorldQuest ~= nil then
		return snapshot.isWorldQuest == true
	end

	local tracker = self.GetPlayerTracker and self:GetPlayerTracker() or nil
	local trackedQuest = tracker and tracker[numericQuestId] or nil
	if trackedQuest and trackedQuest.taskAnnouncementType == "world" then
		return true
	end

	return false
end

function QuestTogether:IsBonusObjective(questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return false
	end

	if self.EnsureQuestSnapshotStore then
		self:EnsureQuestSnapshotStore()
	end
	local bonusState = self.GetTaskAreaStateStore and self:GetTaskAreaStateStore("bonus") or nil
	if type(bonusState) == "table" and bonusState[numericQuestId] then
		return true
	end
	local snapshot = self.GetQuestSnapshot and self:GetQuestSnapshot(numericQuestId) or nil
	if snapshot and snapshot.isBonusObjective ~= nil then
		return snapshot.isBonusObjective == true
	end
	return false
end

function QuestTogether:GetQuestTitle(questId, questInfo)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return "Quest " .. tostring(questId)
	end

	if questInfo and type(questInfo.title) == "string" and questInfo.title ~= "" then
		return questInfo.title
	end

	if self.EnsureQuestSnapshotStore then
		self:EnsureQuestSnapshotStore()
	end
	local snapshot = self.GetQuestSnapshot and self:GetQuestSnapshot(numericQuestId) or nil
	if snapshot and type(snapshot.title) == "string" and snapshot.title ~= "" then
		return snapshot.title
	end

	return "Quest " .. tostring(numericQuestId)
end

function QuestTogether:IsPlaceholderQuestTitle(questId, title)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return false
	end

	return type(title) == "string" and title == ("Quest " .. tostring(numericQuestId))
end

function QuestTogether:NormalizeQuestProgressPercent(progressValue)
	local numericProgress = self:SafeToNumber(progressValue)
	if numericProgress == nil then
		return nil
	end

	-- Blizzard progress bars can return floating values; format chat/objectives as whole percents.
	if numericProgress < 0 then
		numericProgress = 0
	elseif numericProgress > 100 then
		numericProgress = 100
	end

	return math.floor(numericProgress + 0.5)
end

function QuestTogether:StripTrailingParentheticalPercent(objectiveText)
	if type(objectiveText) ~= "string" or objectiveText == "" or self:IsSecretValue(objectiveText) then
		return objectiveText
	end

	local strippedText = string.gsub(objectiveText, "%s*%(%d+%%%s*%)%s*$", "")
	if strippedText == "" then
		return objectiveText
	end

	return strippedText
end

function QuestTogether:GetQuestLogIndexForQuest(questId, questInfo)
	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then return nil end
	local questLogIndex = questInfo and self:SafeToNumber(questInfo.questLogIndex) or nil
	if questLogIndex ~= nil then
		questLogIndex = math.floor(questLogIndex + 0.5)
		if questLogIndex <= 0 then
			questLogIndex = nil
		end
	end

	if questLogIndex then
		local row = self.API and self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex)
		if not row or self:NormalizeQuestID(row.questID) ~= self:NormalizeQuestID(questId) then
			questLogIndex = nil
		end
	end

	if not questLogIndex and self.API and self.API.GetQuestLogIndexForQuestID then
		local normalizedQuestId = self:NormalizeQuestID(questId)
		if normalizedQuestId then
			local resolvedQuestLogIndex = self.API.GetQuestLogIndexForQuestID(normalizedQuestId)
			questLogIndex = self:SafeToNumber(resolvedQuestLogIndex)
			if questLogIndex ~= nil then
				questLogIndex = math.floor(questLogIndex + 0.5)
				if questLogIndex <= 0 then
					questLogIndex = nil
				end
			end
		end
	end

	return questLogIndex
end

function QuestTogether:GetNormalizedQuestObjectiveInfo(questId, objectiveIndex, displayComplete)
	local objectiveText, objectiveType, finished, currentValue = nil, nil, nil, nil
	if self.API and self.API.GetQuestObjectiveInfo then
		objectiveText, objectiveType, finished, currentValue =
			self.API.GetQuestObjectiveInfo(questId, objectiveIndex, displayComplete)
	end
	if objectiveText == nil and objectiveType == nil and currentValue == nil then
		objectiveText = ""
	end

	if objectiveType == "progressbar" then
		local baseObjectiveText = self:StripTrailingParentheticalPercent(objectiveText)
		if type(baseObjectiveText) ~= "string" then
			baseObjectiveText = type(objectiveText) == "string" and objectiveText or ""
		end

		local progress = self.API and self.API.GetQuestProgressBarPercent and self.API.GetQuestProgressBarPercent(questId)
		local roundedProgress = self:NormalizeQuestProgressPercent(progress)
		if roundedProgress ~= nil then
			if baseObjectiveText ~= "" then
				objectiveText = tostring(roundedProgress) .. "% " .. baseObjectiveText
			else
				objectiveText = tostring(roundedProgress) .. "%"
			end
			currentValue = roundedProgress
		else
			objectiveText = baseObjectiveText
		end
	end

	return objectiveText, objectiveType, finished, currentValue
end

function QuestTogether:NormalizeNameplateOptions()
	local profile = self.db.profile
	if not self:IsNameplateQuestIconStyle(profile.nameplateQuestIconStyle) then
		profile.nameplateQuestIconStyle = self.DEFAULTS.profile.nameplateQuestIconStyle
	end
end

function QuestTogether:NormalizeAnnouncementDisplayOptions()
	local profile = self.db.profile
	if profile.emoteOnQuestCompletion == nil then
		profile.emoteOnQuestCompletion = self.DEFAULTS.profile.emoteOnQuestCompletion
	end
	if profile.emoteOnNearbyPlayerQuestCompletion == nil then
		profile.emoteOnNearbyPlayerQuestCompletion = self.DEFAULTS.profile.emoteOnNearbyPlayerQuestCompletion
	end
	if not self:IsChatLogDestination(profile.chatLogDestination) then
		profile.chatLogDestination = self.DEFAULTS.profile.chatLogDestination
	end
	if profile.mirrorChatLogsToMainChat == nil then
		profile.mirrorChatLogsToMainChat = self.DEFAULTS.profile.mirrorChatLogsToMainChat
	end
	if not self:IsShowProgressFor(profile.showProgressFor) then
		profile.showProgressFor = self.DEFAULTS.profile.showProgressFor
	end
	profile.chatBubbleSize = self:NormalizeChatBubbleSizeValue(profile.chatBubbleSize)
		or self.DEFAULTS.profile.chatBubbleSize
	profile.chatBubbleDuration = self:NormalizeChatBubbleDurationValue(profile.chatBubbleDuration)
		or self.DEFAULTS.profile.chatBubbleDuration
end

function QuestTogether:GetOption(key)
	if not self.db or not self.db.profile then
		return nil
	end
	if key == "chatLogDestination" then
		return self:GetResolvedChatLogDestination()
	end
	return self.db.profile[key]
end

function QuestTogether:SetOption(key, value)
	if not self.db or not self.db.profile then
		return false
	end
	if key == "showProgressFor" and not self:IsShowProgressFor(value) then
		self:Debugf("options", "Rejected option change key=%s invalidValue=%s", tostring(key), FormatDebugValue(value))
		return false
	end
	if key == "chatLogDestination" and not self:IsChatLogDestination(value) then
		self:Debugf("options", "Rejected option change key=%s invalid chat destination=%s", tostring(key), tostring(value))
		return false
	end
	if key == "chatBubbleSize" then
		value = self:NormalizeChatBubbleSizeValue(value)
		if not value then
			self:Debugf("options", "Rejected option change key=%s invalid bubble size", tostring(key))
			return false
		end
	end
	if key == "chatBubbleDuration" then
		value = self:NormalizeChatBubbleDurationValue(value)
		if not value then
			self:Debugf("options", "Rejected option change key=%s invalid bubble duration", tostring(key))
			return false
		end
	end
	if key == "nameplateQuestIconStyle" and not self:IsNameplateQuestIconStyle(value) then
		self:Debugf("options", "Rejected option change key=%s invalid icon style=%s", tostring(key), tostring(value))
		return false
	end
	self.db.profile[key] = value
	if key == "nameplateQuestIconStyle" then
		self:NormalizeNameplateOptions()
	end
	if
		key == "chatLogDestination"
		or key == "mirrorChatLogsToMainChat"
		or key == "showProgressFor"
		or key == "chatBubbleSize"
		or key == "chatBubbleDuration"
	then
		self:NormalizeAnnouncementDisplayOptions()
	end
	if key == "chatLogDestination" and value == "separate" then
		local chatFrame = self:EnsureQuestLogChatFrame()
		if chatFrame then
			self:ApplyMainChatFontSizeToChatFrame(chatFrame)
			if self.isEnabled and self.hasLoggedIn then
				self:PrintChatLogDestinationMessage()
			end
		end
	end
	if key == "chatLogDestination" and value == "main" then
		self:CloseQuestLogChatFrame()
	end
	if
		key == "showChatBubbles"
		or key == "hideMyOwnChatBubbles"
		or key == "chatBubbleSize"
		or key == "chatBubbleDuration"
	then
		if self.RefreshActiveAnnouncementBubbles then
			self:RefreshActiveAnnouncementBubbles()
		end
		if self.RefreshPersonalBubbleAnchorVisualState then
			self:RefreshPersonalBubbleAnchorVisualState()
		end
		if self.RefreshPersonalBubbleEditModeDialog then
			self:RefreshPersonalBubbleEditModeDialog()
		end
	end
	if
		key == "nameplateQuestIconEnabled"
		or key == "nameplateQuestIconStyle"
		or key == "nameplateQuestHealthColorEnabled"
		or key == "nameplateQuestHealthColor"
	then
		if self.RefreshNameplateAugmentation then
			self:RefreshNameplateAugmentation()
		end
	end
	return true
end

-- Compatibility helpers so old option-style code still works.
function QuestTogether:GetValue(infoOrKey)
	local key = infoOrKey
	if type(infoOrKey) == "table" then
		key = infoOrKey[#infoOrKey]
	end
	return self:GetOption(key)
end

function QuestTogether:SetValue(infoOrKey, value)
	local key = infoOrKey
	if type(infoOrKey) == "table" then
		key = infoOrKey[#infoOrKey]
	end
	return self:SetOption(key, value)
end

function QuestTogether:GetPlayerTracker()
	local characterKey = self.activeCharacterKey or self:GetCurrentCharacterKey() or self:GetPlayerName() or "Unknown"
	if not self.db.global.questTrackers[characterKey] then
		self.db.global.questTrackers[characterKey] = {}
	end
	return self.db.global.questTrackers[characterKey]
end

function QuestTogether:QueueQuestLogTask(taskFn)
	if type(taskFn) == "function" then
		table.insert(self.onQuestLogUpdate, taskFn)
		if self.ScheduleQuestLogTaskDrain then
			self:ScheduleQuestLogTaskDrain("QueueQuestLogTask")
		end
	end
end

function QuestTogether:ResetQuestEventState()
	self.onQuestLogUpdate = {}
	self.questsCompleted = {}
	self.pendingQuestRemovals = {}
	self.pendingQuestAcceptances = {}
	self.retiredQuestIds = {}
end

-- SavedVariables initializer.
function QuestTogether:InitializeDatabase()
	if type(_G.QuestTogetherDB) ~= "table" then
		_G.QuestTogetherDB = {}
	end
	self.db = _G.QuestTogetherDB

	if type(self.db.global) ~= "table" then
		self.db.global = {}
	end
	self:ApplyDefaults(self.db.global, self.DEFAULTS.global)
	self.db.global.debugLogLines = nil
	if type(self.db.global.debugLogSearchFilter) ~= "string" then
		if type(self.db.global.debugLogPrefixFilter) == "string" then
			self.db.global.debugLogSearchFilter = self.db.global.debugLogPrefixFilter
		else
			self.db.global.debugLogSearchFilter = self.db.global.debugLogSearchFilter ~= nil
				and tostring(self.db.global.debugLogSearchFilter)
				or ""
		end
	end
	if type(self.db.global.debugLogCategoryFilter) ~= "string" then
		self.db.global.debugLogCategoryFilter = self.DEBUG_ALL_CATEGORIES
	end
	self.debugLogLines = {}
	self.debugLogStoreNormalized = false
	self.debugLogTextLengthSum = 0
	self:EnsureProfileStorage()

	local characterKey = self:GetCurrentCharacterKey()
	local defaultProfileKey = NormalizeProfileKey(characterKey) or "Character"
	local assignedProfileKey = NormalizeProfileKey(self.db.profileKeys[characterKey])
	if not assignedProfileKey then
		assignedProfileKey = defaultProfileKey
		self.db.profileKeys[characterKey] = assignedProfileKey
	end

	if type(self.db.profiles[assignedProfileKey]) ~= "table" then
		self.db.profiles[assignedProfileKey] = self:DeepCopy(self.DEFAULTS.profile)
	end

	self.activeCharacterKey = characterKey
	self.activeProfileKey = assignedProfileKey
	self.db.profile = self.db.profiles[assignedProfileKey]
	self:ApplyDefaults(self.db.profile, self.DEFAULTS.profile)

	self:NormalizeAnnouncementDisplayOptions()
	self:NormalizeNameplateOptions()
end

function QuestTogether:RegisterRuntimeEvents()
	self.registeredRuntimeEvents = self.registeredRuntimeEvents or {}
	wipe(self.registeredRuntimeEvents)

	for _, eventName in ipairs(self.runtimeEvents) do
		-- Event lists vary slightly by client flavor/build; register best-effort.
		local ok = pcall(self.eventFrame.RegisterEvent, self.eventFrame, eventName)
		if ok then
			self.registeredRuntimeEvents[eventName] = true
		else
			self:Debugf("events", "Skipping unavailable runtime event=%s", tostring(eventName))
		end
	end
end

function QuestTogether:UnregisterRuntimeEvents()
	for eventName in pairs(self.registeredRuntimeEvents or {}) do
		-- Unregister should not block disable if Blizzard already removed an event.
		pcall(self.eventFrame.UnregisterEvent, self.eventFrame, eventName)
	end

	if self.registeredRuntimeEvents then
		wipe(self.registeredRuntimeEvents)
	end
end

function QuestTogether:Enable()
	self.db.profile.enabled = true

	if not self.hasLoggedIn then
		-- We only fully enable after PLAYER_LOGIN when WoW APIs are guaranteed to be ready.
		return true
	end
	if self.isEnabled then
		return true
	end

	self:RegisterRuntimeEvents()
	self.API.RegisterAddonPrefix(self.commPrefix)
	self.isEnabled = true
	self:ResetQuestEventState()
	-- Events may have been missed while disabled/offline, including a repeatable
	-- quest being accepted again. Start a fresh observation lifetime on enable.
	wipe(self:GetPlayerTracker())
	if self.ResetTaskAreaStateStore then
		self:ResetTaskAreaStateStore()
	end
	if self.ResetRuntimeWorkStateStore then
		self:ResetRuntimeWorkStateStore()
	end
	if self.EnsureAnnouncementChannelJoined then
		self:EnsureAnnouncementChannelJoined()
	end
	if self.RefreshTaskAreaStates then
		self:RefreshTaskAreaStates(false)
	end

	if self.EnableNameplateAugmentation then
		self:EnableNameplateAugmentation()
	end
	if self.TryInstallPersonalBubbleEditModeHooks then
		self:TryInstallPersonalBubbleEditModeHooks()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end

	self:Debug("Addon enabled.", "core")

	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end

	-- Delay initial scan briefly so quest log APIs are stable right after login/reload.
	local enabledWorkState = self:GetDeferredWorkStateStore()
	self.API.Delay(0.25, function()
		if self.isEnabled and self:GetDeferredWorkStateStore() == enabledWorkState then
			self:ScanQuestLog()
		end
	end)

	return true
end

function QuestTogether:Disable()
	self.db.profile.enabled = false

	if not self.isEnabled then
		return true
	end

	self:UnregisterRuntimeEvents()
	self.isEnabled = false
	self:ResetQuestEventState()
	if self.ResetTaskAreaStateStore then
		self:ResetTaskAreaStateStore()
	end
	if self.ResetRuntimeWorkStateStore then
		self:ResetRuntimeWorkStateStore()
	end
	if self.LeaveAnnouncementChannel then
		self:LeaveAnnouncementChannel()
	end

	if self.DisableNameplateAugmentation then
		self:DisableNameplateAugmentation()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end

	self:Debug("Addon disabled.", "core")
	return true
end

function QuestTogether:OpenHudEditMode()
	if not EditModeManagerFrame then
		pcall(UIParentLoadAddOn, "Blizzard_EditMode")
	end

	if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
		return false
	end

	if not EditModeManagerFrame then
		return false
	end
	if not self:CanAccessForeignFrame(EditModeManagerFrame) then
		return false
	end

	if type(EditModeManagerFrame.EnterEditMode) ~= "function" then
		return false
	end

	local ok = pcall(EditModeManagerFrame.EnterEditMode, EditModeManagerFrame)
	return ok
end

function QuestTogether:InitializeSlashCommands()
	SLASH_QUESTTOGETHER1 = "/qt"
	SLASH_QUESTTOGETHER2 = "/questtogether"
	SLASH_QUESTTOGETHER3 = "/questogether"

	SlashCmdList.QUESTTOGETHER = function(input)
		QuestTogether:HandleSlashCommand(input or "")
	end

	SLASH_QUESTTOGETHERDUMP1 = "/qtd"
	SlashCmdList.QUESTTOGETHERDUMP = function(input)
		local normalizedInput = QuestTogether:SafeTrimString(input, "")
		if normalizedInput ~= "" then
			QuestTogether:HandleSlashCommand("dump " .. normalizedInput)
			return
		end
		QuestTogether:ShowDebugWindow()
	end
end

function QuestTogether:ParseBoolean(text)
	if not text then
		return nil
	end
	local normalized = string.lower(text)
	if normalized == "true" or normalized == "1" or normalized == "on" or normalized == "yes" then
		return true
	end
	if normalized == "false" or normalized == "0" or normalized == "off" or normalized == "no" then
		return false
	end
	return nil
end

function QuestTogether:PrintHelp()
	self:Print("Commands:")
	self:Print("/qt options - Open the QuestTogether options window")
	self:Print("/qt enable | disable - Enable or disable runtime behavior")
	self:Print("/qt debug - Open the shared QuestTogether debug window")
	self:Print("/qt devlogall [on|off|toggle] - Show or control dev all-announcements logging")
	self:Print("/qt set <option> <value> - Set a boolean option (e.g. emoteOnQuestCompletion off)")
	self:Print("/qt get <option> - Read an option value")
	self:Print("/qt scan - Rescan your quest log now")
	self:Print("/qt ping - Request pong metadata from all QuestTogether clients in the shared channel")
	self:Print("/qt bubbletest <text> - Send a QUEST_PROGRESS test event as your current target")
	self:Print("/qt bubbletest <player> <text> - Send a QUEST_PROGRESS test event as a nearby visible player")
	self:Print("/qt test - Run in-game unit tests, then open /qt dump filtered to TEST")
	self:Print("/qt dump [clear|CATEGORY] - Open the shared QuestTogether debug window")
	self:Print("/qt diagnostics [questID] - Copy client, runtime, and recent event diagnostics")
	self:Print("/qtd - Shortcut for /qt dump")
end

function QuestTogether:HandleSlashCommand(input)
	local command, rest = SafeMatch(input, "^(%S*)%s*(.-)$")
	command = string.lower(command or "")

	if command == "" or command == "options" then
		self:OpenOptionsWindow()
		return
	end

	-- Generic debug commands and their presentation belong to the shared controller.
	local debugCommand = command == "debuglog" and "dump" or command
	if (debugCommand == "dump" or debugCommand == "debug") and rest ~= "" then
		debugCommand = "dump " .. rest
	end
	local handled = self:GetDebugController():HandleCommand(debugCommand, rest)
	if handled then
		return
	end

	if command == "help" then
		self:PrintHelp()
		return
	end

	if command == "enable" then
		self:Enable()
		self:Print("QuestTogether enabled.")
		return
	end

	if command == "disable" then
		self:Disable()
		self:Print("QuestTogether disabled.")
		return
	end

	if command == "devlogall" then
		local flag = string.lower(rest or "")
		if flag == "" then
			self:Print("devLogAllAnnouncements = " .. tostring(self:GetOption("devLogAllAnnouncements")))
			return
		end
		if flag == "toggle" then
			self:SetOption("devLogAllAnnouncements", not self:GetOption("devLogAllAnnouncements"))
		else
			local boolValue = self:ParseBoolean(flag)
			if boolValue == nil then
				self:Print("Usage: /qt devlogall on|off|toggle")
				return
			end
			self:SetOption("devLogAllAnnouncements", boolValue)
		end
		self:Print("devLogAllAnnouncements = " .. tostring(self:GetOption("devLogAllAnnouncements")))
		return
	end


	if command == "set" then
		local optionKey, optionValueText = SafeMatch(rest, "^(%S+)%s+(.+)$")
		if not optionKey or not optionValueText then
			self:Print("Usage: /qt set <option> <value>")
			return
		end
		local boolValue = self:ParseBoolean(optionValueText)
		if boolValue == nil then
			self:Print("Only boolean values are supported here: true/false, on/off, 1/0")
			return
		end
		if self:GetOption(optionKey) == nil then
			self:Print("Unknown option key: " .. tostring(optionKey))
			return
		end
		self:SetOption(optionKey, boolValue)
		self:Print(optionKey .. " = " .. tostring(self:GetOption(optionKey)))
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		return
	end

	if command == "get" then
		local optionKey = SafeMatch(rest, "^(%S+)$")
		if not optionKey then
			self:Print("Usage: /qt get <option>")
			return
		end
		self:Print(optionKey .. " = " .. tostring(self:GetOption(optionKey)))
		return
	end

	if command == "scan" then
		self:ScanQuestLog()
		return
	end

	if command == "ping" then
		if not self.SendPingRequest then
			self:Print("Ping is unavailable.")
			return
		end

		local ok, requestIdOrError = self:SendPingRequest()
		if not ok then
			self:Print(tostring(requestIdOrError))
			return
		end

		self:PrintChatLogSystemMessage("Ping sent.")
		return
	end

	if command == "bubbletest" then
		if rest == nil or rest == "" then
			self:Print("Usage: /qt bubbletest <text>")
			self:Print("   or: /qt bubbletest <player> <text>")
			return
		end
		if not self.SendBubbleAnnouncementTest then
			self:Print("Bubble test is unavailable.")
			return
		end

		local senderName = nil
		local testText = rest
		if not (self.API.UnitExists and self.API.UnitExists("target")) then
			local explicitSenderName, explicitText = SafeMatch(rest, "^(%S+)%s+(.+)$")
			if not explicitSenderName or not explicitText then
				self:Print("Usage without a target: /qt bubbletest <player> <text>")
				return
			end
			senderName = explicitSenderName
			testText = explicitText
		end

		local ok, senderNameOrError = self:SendBubbleAnnouncementTest(testText, senderName)
		if not ok then
			self:Print(senderNameOrError)
			return
		end
		self:Print("Sent bubble test announcement for " .. tostring(self:GetShortDisplayName(senderNameOrError)))
		return
	end


	self:Print("Unknown command: " .. tostring(command))
	self:PrintHelp()
end

-- Full quest log scan to build local objective snapshots.
function QuestTogether:ScanQuestLog()
	if not self.db or not self.db.global then
		return
	end

	if self.IsWorkBlocked and self:IsWorkBlocked("quest_log_drain") then
		self:ScheduleDeferredWork("quest_log_drain", "full_scan", function() self:ScanQuestLog() end)
		return
	end
	if self.RebuildQuestSnapshotStore then
		local snapshot = self:RebuildQuestSnapshotStore()
		if snapshot and snapshot.lastUnreadableRow then
			return
		end
	end

	local tracker = self:GetPlayerTracker()
	local seenQuestIDs = {}
	local questsTracked = 0

	local snapshotByQuestID = self.GetQuestSnapshotByQuestID and self:GetQuestSnapshotByQuestID() or nil
	local snapshotOrder = self.GetQuestSnapshotOrder and self:GetQuestSnapshotOrder() or nil
	for index = 1, #(snapshotOrder or {}) do
		local questID = snapshotOrder[index]
		local questInfo = snapshotByQuestID and snapshotByQuestID[questID] or nil
		if questInfo and questInfo.isHidden ~= true and not (self.retiredQuestIds and self.retiredQuestIds[questID]) then
			self:WatchQuest(questID, questInfo)
			seenQuestIDs[questID] = true
			questsTracked = questsTracked + 1
		end
	end

	if self.RefreshTaskAreaStates then
		self:RefreshTaskAreaStates(false)
	end

	-- Area task quests can exist outside normal quest-log rows.
	-- Add them explicitly so progress announcements can still operate on them.
	if self.GetActiveWorldQuestAreaSnapshot then
		for questId, questTitle in pairs(self:GetActiveWorldQuestAreaSnapshot()) do
			seenQuestIDs[questId] = true
			if not tracker[questId] then
				self:WatchQuest(questId, { title = questTitle })
				if tracker[questId] then
					questsTracked = questsTracked + 1
				end
			end
		end
	end
	if self.GetActiveBonusObjectiveAreaSnapshot then
		for questId, questTitle in pairs(self:GetActiveBonusObjectiveAreaSnapshot()) do
			seenQuestIDs[questId] = true
			if not tracker[questId] then
				self:WatchQuest(questId, { title = questTitle })
				if tracker[questId] then
					questsTracked = questsTracked + 1
				end
			end
		end
	end

	for questID in pairs(tracker) do
		if not seenQuestIDs[questID] then
			tracker[questID] = nil
		end
	end
	local scanMessage = questsTracked .. " quests are being monitored by QuestTogether."
	self:PrintConsoleAnnouncement(scanMessage)
	if self.BuildLocalAnnouncementEvent and self.SendAnnouncementWireEvent then
		local eventData = self:BuildLocalAnnouncementEvent("SCAN_STATUS", scanMessage)
		if eventData then
			self:SendAnnouncementWireEvent(eventData)
		end
	end
end

-- Store the current objective text state for one quest.
function QuestTogether:WatchQuest(questId, questInfo)
	local numericQuestId = self:NormalizeQuestID(questId)

	if not numericQuestId or (self.retiredQuestIds and self.retiredQuestIds[numericQuestId]) then
		return
	end

	if not questInfo and self.GetQuestSnapshot then
		questInfo = self:GetQuestSnapshot(numericQuestId)
	end
	if not questInfo then
		return
	end

	local tracker = self:GetPlayerTracker()
	local questLogIndex = self.GetQuestLogIndexForQuest and self:GetQuestLogIndexForQuest(numericQuestId, questInfo) or nil
	local questTitle = self:GetQuestTitle(numericQuestId, questInfo)
	local existingTrackedQuest = tracker[numericQuestId]
	if self:IsPlaceholderQuestTitle(numericQuestId, questTitle) then
		local existingTitle = existingTrackedQuest and existingTrackedQuest.title or nil
		if type(existingTitle) == "string" and existingTitle ~= "" and not self:IsPlaceholderQuestTitle(numericQuestId, existingTitle) then
			questTitle = existingTitle
		end
	end
	local initialStatusState = self.GetTrackedQuestStatusState and self:GetTrackedQuestStatusState(numericQuestId, true) or nil

	tracker[numericQuestId] = {
		title = questTitle,
		taskAnnouncementType = self:GetTaskAnnouncementType(numericQuestId),
		objectives = {},
		-- Cached numeric objective values used to gate progress announcements.
		-- This avoids noisy chat lines caused by text-only objective rewrites.
		objectiveValues = {},
		objectiveProgressHighWater = existingTrackedQuest and existingTrackedQuest.objectiveProgressHighWater or {},
		isComplete = initialStatusState and initialStatusState.isComplete == true or false,
		isReadyForTurnIn = initialStatusState and initialStatusState.isReadyForTurnIn == true or false,
	}

	if not questLogIndex then
		return
	end

	local numObjectives = self.API and self.API.GetNumQuestLeaderBoards and self.API.GetNumQuestLeaderBoards(questLogIndex)
		or 0
	for objectiveIndex = 1, numObjectives do
		local objectiveText, _, _, currentValue = self:GetNormalizedQuestObjectiveInfo(numericQuestId, objectiveIndex, false)
		if self.UpdateTrackedObjectiveProgress then
			self:UpdateTrackedObjectiveProgress(tracker[numericQuestId], objectiveIndex, objectiveText, currentValue)
		else
			tracker[numericQuestId].objectives[objectiveIndex] = objectiveText
			tracker[numericQuestId].objectiveValues[objectiveIndex] = self:SafeToNumber(currentValue)
		end
	end
end

function QuestTogether:OnInitialize()
	self:InitializeDatabase()
	if self.EnsureRuntimeStateStore then
		self:EnsureRuntimeStateStore()
	end
	if self.InitializePartyState then
		self:InitializePartyState()
	end
	if self.TryInstallNameplateHooks then
		self:TryInstallNameplateHooks()
	end
	if self.TryInstallPersonalBubbleEditModeHooks then
		self:TryInstallPersonalBubbleEditModeHooks()
	end
	self:TryInstallChatLogLinkHandler()
	self:TryInstallChatWindowHooks()
	self:InitializeSlashCommands()
	if self.InitializeOptionsWindow then
		self:InitializeOptionsWindow()
	end
	self.isInitialized = true
end

function QuestTogether:OnLogin()
	self.hasLoggedIn = true
	self.isLoggingOut = false
	self:ReconcileQuestLogChatDestination()
	if self.db.profile.enabled then
		self:Enable()
	end
	self:PrintWelcomeMessage()
end

-- Bootstrap event handlers always registered.
function QuestTogether:ADDON_LOADED(_, loadedAddonName)
	if self.TryInstallNameplateHooks and self.isInitialized then
		self:TryInstallNameplateHooks()
	end
	if loadedAddonName == "Blizzard_EditMode" and self.TryInstallPersonalBubbleEditModeHooks then
		self:TryInstallPersonalBubbleEditModeHooks()
	end

	if loadedAddonName ~= self.addonName then
		return
	end
	if not self.isInitialized then
		self:OnInitialize()
	end
end

function QuestTogether:PLAYER_LOGIN()
	if not self.isInitialized then
		self:OnInitialize()
	end
	self:OnLogin()
end

function QuestTogether:PLAYER_ENTERING_WORLD()
	self.isLoggingOut = false
end

function QuestTogether:PLAYER_LEAVING_WORLD()
	self.isLoggingOut = true
end

function QuestTogether:PLAYER_LOGOUT()
	self.isLoggingOut = true
end

-- Shared event dispatcher for all WoW events this addon listens for.
local function DispatchEvent(_, eventName, ...)
	local handler = QuestTogether[eventName]
	if type(handler) ~= "function" then
		return
	end

	local ok, err
	if QuestTogether.RunGuardedCallback then
		ok, err = QuestTogether:RunGuardedCallback(eventName, handler, QuestTogether, eventName, ...)
	else
		ok, err = pcall(handler, QuestTogether, eventName, ...)
	end
	if not ok then
		if type(geterrorhandler) == "function" then geterrorhandler()(err) end
	end
end

QuestTogether.eventFrame = QuestTogether.eventFrame or CreateFrame("Frame")
QuestTogether.eventFrame:SetScript("OnEvent", DispatchEvent)
QuestTogether.eventFrame:RegisterEvent("ADDON_LOADED")
QuestTogether.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LOGIN")
QuestTogether.eventFrame:RegisterEvent("PLAYER_LOGOUT")

QuestTogether.eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
QuestTogether.eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
