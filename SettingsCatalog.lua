-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Access = QuestTogether.NativeAccess
local SafeText = Access.Text
local tostring = SafeText

QuestTogether.DEFAULTS = {
	profile = {
		enabled = true,
		announceAccepted = true,
		announceQuestStarterItems = true,
		announceCompleted = true,
		announceReadyToTurnIn = true,
		announceRemoved = true,
		announceProgress = true,
		announceQuestPartners = true,
		announceWorldQuestAreaEnter = true,
		announceWorldQuestAreaLeave = true,
		announceWorldQuestProgress = true,
		announceWorldQuestCompleted = true,
		announceBonusObjectiveAreaEnter = true,
		announceBonusObjectiveAreaLeave = true,
		announceBonusObjectiveProgress = true,
		announceBonusObjectiveCompleted = true,
		showChatBubbles = true,
		ownChatBubbleMode = "always",
		announceToNonQTParty = true,
		hidePartyChatReminder = false,
		showChatLogs = true,
		showQTChat = true,
		qtChatScope = "global",
		chatLogDestination = "main",
		mirrorChatLogsToMainChat = false,
		showProgressFor = "party_nearby",
		nearbyAnnouncementRange = 25,
		devLogAllAnnouncements = false,
		chatBubbleSize = 100,
		chatBubbleDuration = 3,
		emoteOnQuestCompletion = true,
		autoThankBuffs = true,
		emoteOnNearbyPlayerQuestCompletion = true,
		emoteOnLevelUp = true,
		compareHideOtherQuests = false,
		lightMode = false,
		windowScale = 100,
		nativeGamepadNavigation = true,
		questTrackerMode = "hover",
		questTrackerHideSolo = true,
		questTrackerSnapToBlizzard = true,
		questTrackerHideBlizzardTooltip = true,
		questTrackerTooltipPlacement = "top",
		questFocusOpacity = 75,
		reduceMotion = false,
		compareAutoRefresh = false,
		experimentalLayerDetection = true,
		compareQuestOwnership = "all",
		compareQuestProgress = "all",
		compareQuestAction = "all",
		compareQuestArea = "all",
		compareQuestLevel = "all",
		compareQuestSort = "all",
		compareGroupByChain = false,
		compareHideFutureQuestNames = true,
		autoAcceptPartyShareRequests = false,
		sharePartyFocus = true,
		skipPartyFocusFollowConfirmation = false,
		sharePartyWaypoint = true,
		showPartyWaypoints = true,
		autoInviteFriends = false,
		autoInviteWhileLFG = false,
		lookingForQuestPartners = false,
		stopLookingForPartnersOnJoin = false,
		showMinimapButton = true,
		showStartupTips = true,
		minimapButtonPosition = 225,
		brokerLeftClick = "pql",
		brokerRightClick = "menu",
		sharePlayerLocation = true,
		shareDeveloperDiagnostics = true,
		showPlayerLocations = true,
		showWorldMapData = true,
		clusterPlayerLocations = true,
		onlyShowQuestPartners = false,
		emoteOnNearbyPlayerLevelUp = true,
		nameplateQuestIconEnabled = true,
		nameplatePlayerIconEnabled = true,
		playerTooltipIdentifierMode = "friends",
		nameplatePlayerIconStyle = "left",
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
		releaseNotesSeenVersion = "",
		availableAddonVersion = "",
		addonUpdateAvailable = false,
		questTrackers = {},
		personalBubbleAnchors = {},
		playerNotes = {},
		recentCompanions = {},
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
	return L(self.chatLogDestinationLabels[value]) or tostring(value)
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

function QuestTogether:IsNameplateQuestIconStyle(styleKey)
	for _, candidate in ipairs(self.nameplateQuestIconStyleOrder) do
		if candidate == styleKey then
			return true
		end
	end
	return false
end

function QuestTogether:GetNameplateQuestIconStyleLabel(styleKey)
	return L(self.nameplateQuestIconStyleLabels[styleKey]) or tostring(styleKey)
end

function QuestTogether:GetNameplateQuestIconStyle()
	local configured = self:GetOption("nameplateQuestIconStyle")
	if self:IsNameplateQuestIconStyle(configured) then
		return configured
	end
	return self.DEFAULTS.profile.nameplateQuestIconStyle
end

function QuestTogether:GetNameplatePlayerIconStyle()
	local configured = self:GetOption("nameplatePlayerIconStyle")
	return self:IsNameplateQuestIconStyle(configured) and configured or self.DEFAULTS.profile.nameplatePlayerIconStyle
end

function QuestTogether:GetShowProgressForLabel(value)
	return L(self.showProgressForLabels[value]) or tostring(value)
end

function QuestTogether:GetChatBubbleSizeLabel(sizeKey)
	local numericValue = self:NormalizeChatBubbleSizeValue(sizeKey)
	if not numericValue then
		return tostring(sizeKey)
	end

	return tostring(numericValue) .. "%"
end


local validators = {
	sharingAudience = function(_, v)
		if v == "normal" or v == "party" then
			return v
		end
	end,
	ownChatBubbleMode = function(a, v)
		return a:IsOwnChatBubbleMode(v) and v or nil
	end,
	playerTooltipIdentifierMode = function(a, v)
		return a:IsPlayerTooltipIdentifierMode(v) and v or nil
	end,
	brokerLeftClick = function(a, v)
		return a:IsDataBrokerAction(v) and v or nil
	end,
	brokerRightClick = function(a, v)
		return a:IsDataBrokerAction(v) and v or nil
	end,
	questTrackerMode = function(a, v)
		return a:IsQuestTrackerMode(v) and v or nil
	end,
	questTrackerTooltipPlacement = function(a, v)
		return a:IsQuestTrackerTooltipPlacement(v) and v or nil
	end,
	questFocusOpacity = function(a, v)
		local n = a:SafeToNumber(v)
		if n and n >= 0 and n <= 100 then
			return n
		end
	end,
	showProgressFor = function(a, v)
		return a:IsShowProgressFor(v) and v or nil
	end,
	chatLogDestination = function(a, v)
		return a:IsChatLogDestination(v) and v or nil
	end,
	qtChatScope = function(_, v)
		if v == "global" or v == "zone_only" then
			return v
		end
	end,
	nearbyAnnouncementRange = function(a, v)
		return a:NormalizeNearbyAnnouncementRange(v)
	end,
	chatBubbleSize = function(a, v)
		return a:NormalizeChatBubbleSizeValue(v)
	end,
	chatBubbleDuration = function(a, v)
		return a:NormalizeChatBubbleDurationValue(v)
	end,
	nameplateQuestIconStyle = function(a, v)
		return a:IsNameplateQuestIconStyle(v) and v or nil
	end,
	nameplatePlayerIconStyle = function(a, v)
		return a:IsNameplateQuestIconStyle(v) and v or nil
	end,
	windowScale = function(a, v)
		local n = a:SafeToNumber(v)
		if n and n >= 80 and n <= 150 then
			return n
		end
	end,
	minimapButtonPosition = function(a, v)
		local n = a:SafeToNumber(v)
		if n and n ~= math.huge and n ~= -math.huge then
			return n % 360
		end
	end,
	nameplateQuestHealthColor = function(a, v)
		if not a:CanAccessTable(v) or type(v) ~= "table" then
			return nil
		end
		local color = {}
		for _, key in ipairs({ "r", "g", "b" }) do
			local n = a:SafeToNumber(v[key])
			if not n or n < 0 or n > 1 then
				return nil
			end
			color[key] = n
		end
		return color
	end,
}
for key, group in pairs({
	compareQuestOwnership = "ownership",
	compareQuestProgress = "progress",
	compareQuestAction = "action",
	compareQuestArea = "area",
	compareQuestLevel = "level",
	compareQuestSort = "sort",
}) do
	local filterGroup = group
	validators[key] = function(a, v)
		return a:IsPartyQuestCompareFilterValue(filterGroup, v) and v or nil
	end
end

-- All profile options have one definition used by validation, defaults and UI.
local presentation = {}
local definitions = {}
QuestTogether.SettingDefinitions = definitions
function QuestTogether:RegisterSetting(key, definition)
	assert(definitions[key] == nil, "duplicate setting: " .. key)
	assert(definition.default ~= nil, "setting requires a default: " .. key)
	for name, value in pairs(presentation[key] or {}) do
		definition[name] = value
	end
	definitions[key] = definition
	self.DEFAULTS.profile[key] = definition.default
end
for key, default in pairs(QuestTogether.DEFAULTS.profile) do
	QuestTogether:RegisterSetting(key, { default = default, validate = validators[key] })
end
function QuestTogether:GetSettingDefinition(key)
	return definitions[key]
end
function QuestTogether:ValidateSetting(key, value)
	local definition = type(key) == "string" and definitions[key]
	if not definition or not self:CanAccessValue(value) then
		return nil
	end
	if definition.validate then
		return definition.validate(self, value)
	end
	if type(definition.default) == "boolean" and type(value) == "boolean" then
		return value
	end
end
function QuestTogether:GetSettingPresentation(key)
	local definition = assert(self:GetSettingDefinition(key), "unknown setting: " .. key)
	return assert(definition.label, "setting label missing: " .. key),
		assert(definition.tooltip, "setting tooltip missing: " .. key)
end

local defaults = {
	showAutomaticReleaseNotes = true,
	showUpdateNotifications = true,
	showWorldMapButton = true,
	showDataBrokerLauncher = true,
	showTrackerFocusIndicators = true,
	automaticGamepadLauncher = true,
	allowIncomingShareRequests = true,
	allowFocusSuggestions = true,
	sharingAudience = "normal",
	automaticLeaderFocus = false,
}
for key, value in pairs(defaults) do
	QuestTogether:RegisterSetting(key, { default = value, validate = validators[key] })
end

presentation = {
	showChatLogs = {
		label = L("Show Chat Logs"),
		tooltip = L("Print QuestTogether announcements in chat when the sender is grouped or nearby."),
		category = "InitializeWhereToAnnounceWindow",
	},
	mirrorChatLogsToMainChat = {
		label = L("Also Print To Main Chat If Docked As A Tab"),
		tooltip = L(
			"Only applies when the separate QuestTogether chat window is docked as a tab. If it is floating in its own window, logs stay there only."
		),
		category = "InitializeWhereToAnnounceWindow",
	},
	announceToNonQTParty = {
		label = L("Also send announcements to party chat if any party members are not running QuestTogether"),
		tooltip = L(
			"Send your enabled event announcements to party chat when a member has not been recognized as a QuestTogether user. Also announce requests to join when you cannot invite and the party leader is not known to use QT. Everyone in the party sees these messages. Does not post to raids."
		),
		category = "InitializeWhereToAnnounceWindow",
	},
	showQTChat = {
		label = L("Show QuestTogether Chat"),
		tooltip = L(
			"Show conversations from the QuestTogether channel in enabled chat logs and bubbles. Quest announcements are unaffected."
		),
		category = "InitializeWhereToAnnounceWindow",
	},
	hidePartyChatReminder = {
		label = L("Hide party-chat reminders"),
		tooltip = L(
			"Hide reminders that your announcements are being sent to party members who do not use QT. This does not turn off party-chat announcements."
		),
		category = "InitializeWhereToAnnounceWindow",
	},
	showChatBubbles = {
		label = L("Show Chat Bubbles"),
		tooltip = L("Display QuestTogether bubbles over nearby players and on your personal bubble anchor."),
		category = "InitializeWhereToAnnounceWindow",
	},
	emoteOnQuestCompletion = {
		label = L("Emote On Quest Completion"),
		tooltip = L("If disabled, this character never performs local quest completion emotes."),
		category = "InitializeEmotesWindow",
	},
	emoteOnNearbyPlayerQuestCompletion = {
		label = L("Emote On Nearby Player Quest Completion"),
		tooltip = L("If disabled, this character will not mirror nearby players' quest completion emotes."),
		category = "InitializeEmotesWindow",
	},
	emoteOnLevelUp = {
		label = L("Emote On Level Up"),
		tooltip = L("Perform a celebration emote when this character levels up."),
		category = "InitializeEmotesWindow",
	},
	emoteOnNearbyPlayerLevelUp = {
		label = L("Emote On Nearby Player Level Up"),
		tooltip = L("Mirror nearby QuestTogether players' level-up emotes, respecting your player scope setting."),
		category = "InitializeEmotesWindow",
	},
	autoThankBuffs = {
		label = L("Automatically thank players for buffs"),
		tooltip = L(
			"After a short, random pause, thank a nearby player who gives you a lasting buff outside combat. Repeated buffs are grouped and thanks are rate-limited."
		),
		category = "InitializeEmotesWindow",
	},
	nameplateQuestHealthColorEnabled = {
		label = L("Quest Objective Health Color"),
		tooltip = L("Tint quest-objective nameplate health bars with your selected quest color."),
		category = "InitializeQuestPlatesWindow",
	},
	experimentalLayerDetection = {
		label = L("Detect different layers"),
		tooltip = L(
			"Estimate nearby players' layers using NPCs and visible players. Requires location sharing and compatible QT clients. NPC inference is available in Forever's open world. Missing players alone never prove a different layer."
		),
		category = "InitializeExperimentalWindow",
	},
	lookingForQuestPartners = {
		label = L("Looking for Questing Partners"),
		tooltip = L(
			"Show that you're looking for questing partners. Turning this on announces your search throughout your zone when location sharing is enabled. Saved per profile; toggle with /qt lfg."
		),
		category = "InitializeGroupsWindow",
	},
	autoInviteWhileLFG = {
		label = L("Automatically invite others while looking for partners"),
		tooltip = L(
			"Approve join requests while Looking for Questing Partners is on. You must have permission and room to invite."
		),
		category = "InitializeGroupsWindow",
	},
	stopLookingForPartnersOnJoin = {
		label = L("Stop looking for partners when joining a group"),
		tooltip = L(
			"Turn off Looking for Questing Partners when you join or form a party or raid. You can turn it back on to recruit more players."
		),
		category = "InitializeGroupsWindow",
	},
	autoInviteFriends = {
		label = L("Automatically invite friends who request to join"),
		tooltip = L(
			"Approve join requests from your character friends list. Otherwise, ask first. Does not accept invitations or leave your current party."
		),
		category = "InitializeGroupsWindow",
	},
	allowIncomingShareRequests = {
		label = L("Allow incoming QT quest-share requests"),
		tooltip = L(
			"Allow QT prompts asking you to share a quest. Disabled requests are declined; ordinary WoW quest sharing is unchanged."
		),
		category = "InitializeGroupsWindow",
	},
	allowFocusSuggestions = {
		label = L("Allow quest focus suggestions"),
		tooltip = L("Let party members following your quest focus suggest a different quest. You choose whether to change focus. Turning this off closes pending suggestions."),
		category = "InitializeGroupsWindow",
	},
	autoAcceptPartyShareRequests = {
		label = L("Always allow party share requests"),
		tooltip = L("Automatically share eligible quests when a party member requests them. Otherwise, ask first."),
		category = "InitializeGroupsWindow",
	},
	sharePartyFocus = {
		label = L("Share my focused quest"),
		tooltip = L(
			"Let your party see your active quest and choose to follow your quest focus. Works independently of public location sharing."
		),
		category = "InitializeTrackerSettingsWindow",
	},
	automaticLeaderFocus = {
		label = L("Automatically follow the party leader's quest focus"),
		tooltip = L(
			"Follow shared quests without asking. While the leader's focus is available, other focus selections are ignored. If unavailable, manual focus works until following resumes. Turn this option off to stop automatic following."
		),
		category = "InitializeTrackerSettingsWindow",
	},
	skipPartyFocusFollowConfirmation = {
		label = L("Skip confirmation when starting focus follow"),
		tooltip = L(
			"Follow a selected party member without the initial confirmation. Changing focus while already following still uses its normal safeguards."
		),
		category = "InitializeTrackerSettingsWindow",
	},
	showTrackerFocusIndicators = {
		label = L("Show party focus indicators on the quest tracker"),
		tooltip = L(
			"Show class-colored focus and follower indicators beside quests in Blizzard's objective tracker. Turning them off does not stop focus sharing or following."
		),
		category = "InitializeTrackerSettingsWindow",
	},
	questTrackerHideSolo = {
		label = L("Hide when not in a party"),
		tooltip = L(
			"Hide the Party Objective Tracker while solo. Its placement preview remains visible in HUD Edit Mode."
		),
		category = "InitializeTrackerSettingsWindow",
	},
	questTrackerHideBlizzardTooltip = {
		label = L("Hide Blizzard quest tooltip"),
		tooltip = L("Hide Blizzard's quest tooltip while Party Objective Tracker shows the hovered quest."),
		category = "InitializeTrackerSettingsWindow",
	},
	audioEnabled = {
		label = L("Enable QT sounds"),
		tooltip = L("Turn all QT sound cues on or off."),
		category = "InitializeAudioWindow",
	},
	audioMuteInCombat = {
		label = L("Mute QT sounds in combat"),
		tooltip = L("Silence QT sound cues and previews while you are in combat."),
		category = "InitializeAudioWindow",
	},
	showWorldMapData = {
		label = L("Show QT world-map overlays"),
		tooltip = L(
			"Show QT player markers and shared waypoints on the world map. Turning this off leaves minimap markers and outgoing sharing unchanged."
		),
		category = "InitializePlayerLocationsWindow",
	},
	showWorldMapButton = {
		label = L("Show the QT world-map button"),
		tooltip = L(
			"Show the QT button on the world map so you can toggle its overlays there. Hiding the button does not turn off the overlays themselves."
		),
		category = "InitializePlayerLocationsWindow",
	},
	sharePlayerLocation = {
		label = L("Share my location on the map and minimap"),
		tooltip = L("Let other QuestTogether players see my location on both the world map and minimap."),
		category = "InitializePlayerLocationsWindow",
	},
	clusterPlayerLocations = {
		label = L("Cluster nearby players on the world map"),
		tooltip = L(
			"Group overlapping world-map dots. Click a cluster to expand individual players. Minimap dots are unchanged."
		),
		category = "InitializePlayerLocationsWindow",
	},
	sharePartyWaypoint = {
		label = L("Share my waypoint"),
		tooltip = L("Automatically share your normal map pin with your party when you place, move, or clear it."),
		category = "InitializePlayerLocationsWindow",
	},
	showPartyWaypoints = {
		label = L("Show party waypoints"),
		tooltip = L(
			"Show your party's shared pins on the world map and nearby on the minimap. Receiving a pin never changes your navigation."
		),
		category = "InitializePlayerLocationsWindow",
	},
	shareDeveloperDiagnostics = {
		label = L("Share diagnostic data with the developer"),
		tooltip = L(
			"Share QT diagnostics and in-game character/location data with the developer, independently of public location sharing."
		),
		category = "InitializeDeveloperWindow",
	},
	reduceMotion = {
		label = L("Reduce motion"),
		tooltip = L("Expand objectives and quest chains, and scroll immediately, without animated transitions."),
		category = "InitializeAccessibilityWindow",
	},
	nativeGamepadNavigation = {
		label = L("Enable native gamepad navigation"),
		tooltip = L(
			"Use the game's controller navigation in QT windows when Gamepad UI is enabled. Existing controller keybindings are preserved."
		),
		category = "InitializeLauncherSettingsWindow",
	},
	automaticGamepadLauncher = {
		label = L("Automatically add the PQL controller shortcut"),
		tooltip = L(
			"Install the PQL shortcut only in an empty default controller slot. Turning this off removes only an unchanged shortcut placed by QT; custom macros and bindings stay yours."
		),
		category = "InitializeLauncherSettingsWindow",
	},
	showMinimapButton = {
		label = L("Show minimap icon"),
		tooltip = L("Show the QuestTogether minimap menu. Drag the button to move it around the minimap."),
		category = "InitializeLauncherSettingsWindow",
	},
	showDataBrokerLauncher = {
		label = L("Show the Data Broker launcher"),
		tooltip = L(
			"Offer QT to compatible toolbar addons through LibDataBroker. A toolbar addon is required to display it. If already registered, turning this off may require Reload UI to remove it."
		),
		category = "InitializeDataBrokerWindow",
	},
	showStartupTips = {
		label = L("Show tips on login"),
		tooltip = L(
			"Show a QuestTogether tip when you log in or reload. You can still use /qt tip or /qt hint at any time."
		),
		category = "InitializeOptionsWindow",
	},
	showAutomaticReleaseNotes = {
		label = L("Show patch notes automatically"),
		tooltip = L(
			"Open patch notes once after a new major or minor release. Patch-only updates do not open them automatically. You can still open Patch Notes yourself when this is off."
		),
		category = "InitializeOptionsWindow",
	},
	showUpdateNotifications = {
		label = L("Show update notifications"),
		tooltip = L(
			"Print a chat notice when QT learns that a newer stable version is available. This does not download updates or control the patch-notes window."
		),
		category = "InitializeOptionsWindow",
	},
}
for key, fields in pairs(presentation) do
	local definition = QuestTogether.SettingDefinitions[key]
	if definition then
		for name, value in pairs(fields) do
			definition[name] = value
		end
	end
end
