-- SPDX-License-Identifier: GPL-3.0-only
-- Presets write ordinary profile options once. Runtime services never read a
-- preset identity; the account choice only seeds newly created profiles.
local QT = _G.QuestTogether
local L = QT.Translate
local definitions = {
	{ id = "full", scenario = L("For players who want QT's full set of shared questing tools, whether adventuring with friends or meeting nearby questers. Keep player maps, nameplate markers, the party tracker, chat updates, bubbles, sounds and celebration emotes. Open the Party Quest Log whenever you want to compare quests or help someone catch up. You choose your own quest focus; automatic leader-follow is off."), title = L("Full Adventure"), description = L("All the usual QuestTogether features. Customize any option later.") },
	{ id = "quiet", scenario = L("For players who enjoy seeing what their companions are doing but prefer a quieter adventure. Keep player maps, nameplate markers, the party tracker and the Party Quest Log. Automatic chat output, bubbles, sounds, emotes, login tips and update interruptions are turned off. Quest-sharing requests can still ask for your approval, and you can open patch notes yourself whenever you like."), title = L("Quiet Questing"), description = L("Keep maps, nameplates and party tools, without automatic messages, sounds or emotes.") },
	{ id = "log", scenario = L("For players who mainly want to compare their party's quests without extra information around the game world. Open the Party Quest Log from the minimap button, controller shortcut or a command when you need it. Map overlays, nameplate additions, QT tooltip identifiers, the party tracker and automatic output are hidden or disabled. QT still shares your progress, but incoming QT requests to share a quest do not interrupt you."), title = L("Quest Log Only"), description = L("Open the Party Quest Log when you need it. Keep the minimap and controller shortcuts; hide other additions.") },
	{ id = "kid", scenario = L("For a younger player adventuring with a parent who handles the party's quest planning. QT stays out of sight: no automatic windows, map additions, nameplate markers or launch buttons. Progress is shared only with the party, and the child's quest focus follows the party leader when both have that quest. Friendly thanks and celebration emotes stay on. If the leader's focus is unavailable, manual focus works until following can resume. Change these choices later through WoW Options."), title = L("Little Sidekick"), description = L("Share with your party quietly and follow the leader's quests automatically. Keep friendly thanks and celebration emotes.") },
}
local quiet = {
	showChatBubbles = false, ownChatBubbleMode = "hidden", showChatLogs = false, showQTChat = false,
	announceToNonQTParty = false, hidePartyChatReminder = true, showStartupTips = false,
	showAutomaticReleaseNotes = false, showUpdateNotifications = false, audioEnabled = false,
	emoteOnQuestCompletion = false, emoteOnNearbyPlayerQuestCompletion = false,
	emoteOnLevelUp = false, emoteOnNearbyPlayerLevelUp = false, autoThankBuffs = false,
}
local log = {
	showPlayerLocations = false, showWorldMapData = false, showPartyWaypoints = false,
	showWorldMapButton = false, showDataBrokerLauncher = false,
	nameplateQuestIconEnabled = false, nameplatePlayerIconEnabled = false,
	nameplateQuestHealthColorEnabled = false, playerTooltipIdentifierMode = "hidden",
	questTrackerMode = "hidden", showTrackerFocusIndicators = false, allowIncomingShareRequests = false,
}
local kid = {
	showMinimapButton = false, automaticGamepadLauncher = false, sharingAudience = "party",
	shareDeveloperDiagnostics = false, automaticLeaderFocus = true,
}
local managed = {
	showMinimapButton = true, automaticGamepadLauncher = true, sharingAudience = true,
	shareDeveloperDiagnostics = true, automaticLeaderFocus = true, sharePartyFocus = true,
	sharePartyWaypoint = true, sharePlayerLocation = true, lookingForQuestPartners = true,
	autoInviteFriends = true, autoInviteWhileLFG = true, autoAcceptPartyShareRequests = true,
}
for _, bundle in ipairs({ quiet, log, kid }) do for key in pairs(bundle) do managed[key] = true end end
function QT:GetPresetDefinitions()
	local result = {}
	for i, entry in ipairs(definitions) do
		result[i] = { id = entry.id, title = entry.title, description = entry.description, scenario = entry.scenario }
	end
	return result
end
function QT:GetPresetValues(id)
	if id ~= "full" and id ~= "quiet" and id ~= "log" and id ~= "kid" then return nil end
	local values = {}
	for key in pairs(managed) do values[key] = self.DEFAULTS.profile[key] end
	local function Merge(bundle) for key, value in pairs(bundle) do values[key] = value end end
	if id ~= "full" then Merge(quiet) end
	if id == "log" or id == "kid" then Merge(log) end
	if id == "kid" then
		Merge(kid)
		for key in pairs(quiet) do
			if key == "autoThankBuffs" or key:match("^emoteOn") then values[key] = self.DEFAULTS.profile[key] end
		end
	end
	return values
end
-- Labels mirror the ordinary settings; values always come from the bundle.
local settingGroups = {
	{ title = L("Groups & Sharing"), entries = {
		{ "questTrackerMode", L("Party Objective Tracker") },
		{ "showTrackerFocusIndicators", L("Show party focus indicators on the quest tracker") },
		{ "automaticLeaderFocus", L("Automatically follow the party leader's quest focus") },
		{ "allowIncomingShareRequests", L("Allow incoming QT quest-share requests") },
		{ "autoAcceptPartyShareRequests", L("Always allow party share requests") },
		{ "lookingForQuestPartners", L("Looking for Questing Partners") },
		{ "autoInviteWhileLFG", L("Automatically invite others while looking for partners") },
		{ "autoInviteFriends", L("Automatically invite friends who request to join") },
	} },
	{ title = L("Maps & nameplates"), entries = {
		{ "showPlayerLocations", L("Show player markers") },
		{ "showWorldMapData", L("Show QT world-map overlays") },
		{ "showPartyWaypoints", L("Show party waypoints") },
		{ "nameplatePlayerIconEnabled", L("QuestTogether Player Icon") },
		{ "nameplateQuestIconEnabled", L("Quest Objective Icon") },
		{ "nameplateQuestHealthColorEnabled", L("Quest Objective Health Color") },
		{ "playerTooltipIdentifierMode", L("QuestTogether tooltip") },
	} },
	{ title = L("Launchers"), entries = {
		{ "showMinimapButton", L("Show minimap icon") },
		{ "showWorldMapButton", L("Show the QT world-map button") },
		{ "showDataBrokerLauncher", L("Show the Data Broker launcher") },
		{ "automaticGamepadLauncher", L("Automatically add the PQL controller shortcut") },
	} },
	{ title = L("Chat & notifications"), entries = {
		{ "showChatLogs", L("Show Chat Logs") },
		{ "showQTChat", L("Show QuestTogether Chat") },
		{ "showChatBubbles", L("Show Chat Bubbles") },
		{ "ownChatBubbleMode", L("My chat bubble") },
		{ "announceToNonQTParty", L("Also send announcements to party chat if any party members are not running QuestTogether") },
		{ "hidePartyChatReminder", L("Hide party-chat reminders") },
		{ "showStartupTips", L("Show tips on login") },
		{ "showAutomaticReleaseNotes", L("Show patch notes automatically") },
		{ "showUpdateNotifications", L("Show update notifications") },
	} },
	{ title = L("Sounds & emotes"), entries = {
		{ "audioEnabled", L("Enable QT sounds") },
		{ "autoThankBuffs", L("Automatically thank players for buffs") },
		{ "emoteOnQuestCompletion", L("Emote On Quest Completion") },
		{ "emoteOnNearbyPlayerQuestCompletion", L("Emote On Nearby Player Quest Completion") },
		{ "emoteOnLevelUp", L("Emote On Level Up") },
		{ "emoteOnNearbyPlayerLevelUp", L("Emote On Nearby Player Level Up") },
	} },
	{ title = L("Sharing & privacy"), entries = {
		{ "sharingAudience", L("Sharing audience") },
		{ "sharePartyFocus", L("Share my focused quest") },
		{ "sharePartyWaypoint", L("Share my waypoint") },
		{ "sharePlayerLocation", L("Share my location on the map and minimap") },
		{ "shareDeveloperDiagnostics", L("Share diagnostic data with the developer") },
	} },
}
function QT:GetPresetSettingDetails(id)
	local values = self:GetPresetValues(id)
	if not values then return nil end
	local groups = {}
	for _, group in ipairs(settingGroups) do
		local result = { title = group.title, entries = {} }
		for _, entry in ipairs(group.entries) do
			local key, value = entry[1], values[entry[1]]
			local text
			if type(value) == "boolean" then text = value and L("Enabled") or L("Disabled")
			elseif key == "sharingAudience" then text = value == "party" and L("Party only") or L("Normal sharing")
			elseif key == "ownChatBubbleMode" then
				text = value == "always" and L("Show always") or value == "solo" and L("Show only when solo") or value == "party" and L("Show only when in a party") or L("Hide always")
			elseif key == "playerTooltipIdentifierMode" then text = self:GetPlayerTooltipIdentifierModeLabel(value)
			elseif key == "questTrackerMode" then
				for _, option in ipairs(self:GetQuestTrackerModeOptions()) do if option.value == value then text = option.text; break end end
			end
			result.entries[#result.entries + 1] = { key = key, label = entry[2], value = value, text = text or L("Unknown") }
		end
		groups[#groups + 1] = result
	end
	return groups
end
function QT:GetMatchingPreset()
	for _, entry in ipairs(definitions) do
		local matches = true
		for key, value in pairs(self:GetPresetValues(entry.id)) do
			if self:GetOption(key) ~= value then matches = false; break end
		end
		if matches then return entry.id, entry.title end
	end
	return nil, L("Custom")
end
function QT:CreateDefaultProfile()
	local profile = self:DeepCopy(self.DEFAULTS.profile)
	local values = self:GetPresetValues(self.db and self.db.global and self.db.global.defaultPreset or "full")
	for key, value in pairs(values or {}) do profile[key] = value end
	return profile
end
function QT:IsWelcomeSetupPending()
	local db = rawget(self, "db")
	return db and db.global and db.global.welcomeSetupComplete == false or false
end
function QT:ApplyPreset(id, useForNewCharacters)
	local values = self:GetPresetValues(id)
	if not values or not self.db or not self.db.global or self:IsRuntimeRestricted() then return false end
	local first = self:IsWelcomeSetupPending()
	if not self:SetOptions(values, "preset") then return false end
	if useForNewCharacters or first then self.db.global.defaultPreset = id end
	if first then
		self.db.global.welcomeSetupComplete = true
		self.db.global.releaseNotesSeenVersion = self:GetAddonVersion()
		self:OnLogin()
	end
	self:RefreshOptionsWindow()
	return true
end
