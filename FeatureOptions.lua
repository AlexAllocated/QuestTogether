-- SPDX-License-Identifier: GPL-3.0-only
-- Independently editable feature policies, shared by settings and services.
local QT = _G.QuestTogether
local defaults = {
	showAutomaticReleaseNotes = true, showUpdateNotifications = true,
	showWorldMapButton = true, showDataBrokerLauncher = true, showTrackerFocusIndicators = true,
	automaticGamepadLauncher = true, allowIncomingShareRequests = true,
	sharingAudience = "normal", automaticLeaderFocus = false,
}
for key, value in pairs(defaults) do QT.DEFAULTS.profile[key] = value end
function QT:IsPublicSharingAllowed()
	return not self:IsWelcomeSetupPending() and self:GetOption("sharingAudience") ~= "party"
end
function QT:IsSharingRouteAllowed(route)
	if self:IsWelcomeSetupPending() then return false end
	if self:GetOption("sharingAudience") ~= "party" then return true end
	if type(route) ~= "table" or route.meshTraffic or route.developerAnnouncement then return false end
	local kind = route.distribution
	if kind == "PARTY" or kind == "RAID" or kind == "INSTANCE_CHAT" then
		return kind == self:GetGroupAnnouncementDistribution()
			and (not route.recipient or self:IsGroupedSender(route.recipient))
	end
	return kind == "WHISPER" and self:IsGroupedSender(route.target) == true
end
function QT:IsSharingSenderAllowed(sender, distribution)
	if self:IsWelcomeSetupPending() then return false end
	if self:GetOption("sharingAudience") ~= "party" then return true end
	return (distribution == "WHISPER" or distribution == "PARTY" or distribution == "RAID" or distribution == "INSTANCE_CHAT")
		and self:IsGroupedSender(sender) == true
end
function QT:RetirePublicSharingChannels()
	if self:IsPublicSharingAllowed() then return end
	local names = { [self.announcementChannelName] = true }
	local geography = rawget(self, "geographicCommsState")
	for name in pairs(geography and geography.subscriptions or {}) do names[name] = true end
	self:RunOrDeferWork("foreign_frame_mutation", "private_directories", function()
		if self:IsPublicSharingAllowed() or not self.API.LeaveChannelByName then return end
		if self.API.GetChatChannelList then
			local ok, channels = pcall(self.API.GetChatChannelList)
			if ok and self:CanAccessTable(channels) and #channels <= 90 and #channels % 3 == 0 then
				for i = 2, #channels, 3 do
					local name = self:SafeToString(channels[i], "")
					if name:lower() == "questtogether3" or name:lower():match("^questtogether3?z[1-9]%d*$") then names[name] = true end
				end
			end
		end
		for name in pairs(names) do pcall(self.API.LeaveChannelByName, name) end
		self.announcementChannelLocalID = nil
	end, 0, "private directories")
end
function QT:ApplyFeaturePolicies(changed, all)
	local function Has(key) return all or changed[key] end
	if Has("sharingAudience") and self.isEnabled and (rawget(self, "communicationState") or rawget(self, "geographicCommsState")) then
		-- Retiring communication lifetimes prevents already admitted public work
		-- from surviving a permission change. Ordinary group sync restarts below.
		if self.EndCommsWorldSession then self:EndCommsWorldSession(false) end
		if not self:IsPublicSharingAllowed() then
			self:RetirePublicSharingChannels()
			self:ResetGeographicComms(true)
		end
		if self.isEnabled and self.ResumeCommsWorldSession then
			self:InitializeGeographicComms()
			self:ResumeCommsWorldSession()
		end
	end
	if Has("showAutomaticReleaseNotes") and self:GetOption("showAutomaticReleaseNotes") == false then
		self:StopReleaseNotesWakeup()
		if self.releaseNotesAutomatic and rawget(self, "releaseNotesWindow") then self:DismissManagedWindow(self.releaseNotesWindow) end
	end
	if Has("showTrackerFocusIndicators") and self:GetOption("showTrackerFocusIndicators") == false then self:ResetPartyQuestFocusIndicators() end
	if (Has("showChatLogs") or Has("showQTChat")) and self:GetOption("showChatLogs") == false and self:GetOption("showQTChat") == false then
		self.pendingQuestScanAnnouncement = nil
		self:RunOrDeferWork("foreign_frame_mutation", "chat_visibility", function()
			if self:GetOption("showChatLogs") == false and self:GetOption("showQTChat") == false then self:CloseQuestLogChatFrame() end
		end, 0, "chat visibility")
	end
	if Has("showWorldMapButton") then self:RefreshQuestTogetherMapControl() end
	if Has("showDataBrokerLauncher") then
		self.dataBrokerReloadRequired = self:GetOption("showDataBrokerLauncher") == false
			and rawget(self, "dataBrokerState") ~= nil and (self.dataBrokerState.object ~= nil or self.dataBrokerState.candidate ~= nil)
		self:RefreshDataBroker()
	end
	if Has("automaticGamepadLauncher") and self.RefreshAutomaticGamepadLauncher then self:RefreshAutomaticGamepadLauncher() end
	if Has("automaticLeaderFocus") and self.isEnabled and self.ReconcileAutomaticLeaderFocus
		and (self:GetOption("automaticLeaderFocus") == true or rawget(self, "partyFocusController")) then self:ReconcileAutomaticLeaderFocus() end
	if Has("allowIncomingShareRequests") and self:GetOption("allowIncomingShareRequests") == false then
		local state = rawget(self, "partyQuestShareState")
		local requests = {}
		for _, request in pairs(state and state.incoming or {}) do requests[#requests + 1] = request end
		for _, request in ipairs(requests) do self:FinishPartyQuestShare(request, "declined") end
	end
end
