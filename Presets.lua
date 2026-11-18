-- SPDX-License-Identifier: GPL-3.0-only
-- Presets write ordinary profile options once. Runtime services never read a
-- preset identity; the account choice only seeds newly created profiles.
local QT = _G.QuestTogether
local L = QT.Translate
local definitions = {
	{ id = "full", title = L("Full experience"), description = L("All the usual QuestTogether features. Customize any option later.") },
	{ id = "quiet", title = L("Quiet companion"), description = L("Keep maps, nameplates and party tools, without automatic messages, sounds or emotes.") },
	{ id = "log", title = L("Party log only"), description = L("Open the Party Quest Log when you need it. Keep the minimap and controller shortcuts; hide other additions.") },
	{ id = "kid", title = L("Kid mode"), description = L("Share with your party quietly and follow the leader's quests automatically. Keep friendly thanks and celebration emotes.") },
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
		result[i] = { id = entry.id, title = entry.title, description = entry.description }
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
