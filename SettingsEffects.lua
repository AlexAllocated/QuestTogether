-- SPDX-License-Identifier: GPL-3.0-only
-- Ordered revocation and presentation effects of one validated transaction.
local QuestTogether = _G.QuestTogether
local QT = QuestTogether

function QT:ApplyFeaturePolicies(changed, all)
	local function Has(key)
		return all or changed[key]
	end
	if
		Has("sharingAudience")
		and self.isEnabled
		and (rawget(self, "communicationState") or rawget(self, "geographicCommsState"))
	then
		-- Retiring communication lifetimes prevents already admitted public work
		-- from surviving a permission change. Ordinary group sync restarts below.
		self:EndCommsWorldSession(false)
		if not self:IsPublicSharingAllowed() then
			self:RetirePublicSharingChannels()
			self:ResetGeographicComms(true)
		end
		if self.isEnabled then
			self:InitializeGeographicComms()
			self:ResumeCommsWorldSession()
		end
	end
	if Has("showAutomaticReleaseNotes") and self:GetOption("showAutomaticReleaseNotes") == false then
		self:StopReleaseNotesWakeup()
		if self.releaseNotesAutomatic and rawget(self, "releaseNotesWindow") then
			self:DismissManagedWindow(self.releaseNotesWindow)
		end
	end
	if Has("showTrackerFocusIndicators") and self:GetOption("showTrackerFocusIndicators") == false then
		self:ResetPartyQuestFocusIndicators()
	end
	if
		(Has("showChatLogs") or Has("showQTChat"))
		and self:GetOption("showChatLogs") == false
		and self:GetOption("showQTChat") == false
	then
		self.pendingQuestScanAnnouncement = nil
		self:RunOrDeferWork("foreign_frame_mutation", "chat_visibility", function()
			if self:GetOption("showChatLogs") == false and self:GetOption("showQTChat") == false then
				self:CloseQuestLogChatFrame()
			end
		end, 0, "chat visibility")
	end
	if Has("showDataBrokerLauncher") then
		self.dataBrokerReloadRequired = self:GetOption("showDataBrokerLauncher") == false
			and rawget(self, "dataBrokerState") ~= nil
			and (self.dataBrokerState.object ~= nil or self.dataBrokerState.candidate ~= nil)
	end
	if Has("automaticGamepadLauncher") then
		self:RefreshAutomaticGamepadLauncher()
	end
	if
		Has("automaticLeaderFocus")
		and self.isEnabled
		and (self:GetOption("automaticLeaderFocus") == true or rawget(self, "partyFocusController"))
	then
		self:ReconcileAutomaticLeaderFocus()
	end
	if Has("allowIncomingShareRequests") and self:GetOption("allowIncomingShareRequests") == false then
		local state = rawget(self, "partyQuestShareState")
		local requests = {}
		for _, request in pairs(state and state.incoming or {}) do
			requests[#requests + 1] = request
		end
		for _, request in ipairs(requests) do
			self:FinishPartyQuestShare(request, "declined")
		end
	end
	if Has("allowFocusSuggestions") then
		self:UpdatePartyFocusSuggestion()
	end
end

local function Invoke(addon, method, ...)
	local action = assert(addon[method], "missing settings effect: " .. method)
	return action(addon, ...)
end

function QuestTogether:ApplySettingsTransaction(changed, context)
	context = context or {}
	local all = context.replace == true
	local compareFrame, compareTarget, resumeCompare, compareProfile
	if all then
		compareProfile = self.db and self.db.profile
		local session = rawget(self, "partyQuestCompareSession")
		compareFrame = rawget(self, "partyQuestCompareWindow")
		if session and compareFrame and type(compareFrame.IsShown) == "function" then
			local ok, shown = pcall(compareFrame.IsShown, compareFrame)
			resumeCompare, compareTarget = ok and shown == true, session.targetName
		end
		if session then
			Invoke(self, "CancelPartyQuestCompare")
		end
	end
	local function Has(...)
		if all then
			return true
		end
		for i = 1, select("#", ...) do
			if changed[select(i, ...)] then
				return true
			end
		end
		return false
	end
	-- Revocation must happen before any restart or asynchronous effect.
	self:ApplyFeaturePolicies(changed, all)
	if Has("autoThankBuffs") then
		Invoke(self, "InitializeAutoThanks")
	end
	if all then
		Invoke(self, "ResetObjectiveAnnouncements")
		Invoke(self, "ResetQuestStarterItems")
		Invoke(self, "InvalidateQuestCompareSnapshot")
	end
	if Has("clusterPlayerLocations", "showWorldMapData") then
		Invoke(self, "ClearPlayerLocationClusterExpansion")
	end
	if Has("showWorldMapData") then
		Invoke(self, "ClearPlayerMapSelection")
	end
	if all or (changed.shareDeveloperDiagnostics and self:GetOption("shareDeveloperDiagnostics") ~= true) then
		Invoke(self, "CancelDeveloperDiagnosticReplies")
	end
	if Has("enabled") and (not all or self.hasLoggedIn) then
		if self.db.profile.enabled then
			self:Enable()
		else
			self:Disable()
		end
	end
	if all then
		Invoke(self, "RefreshPartyRoster")
	end
	if (not all or self.isEnabled) and Has("sharePartyFocus", "sharePartyWaypoint", "showPartyWaypoints", "allowFocusSuggestions") then
		Invoke(self, "QueuePartyNavigationUpdate")
	end
	if Has("experimentalLayerDetection", "sharePlayerLocation") then
		Invoke(self, "ResetPlayerPhases")
	end
	if Has("lightMode", "reduceMotion") then
		Invoke(self, "RefreshWindowThemes")
	end
	if
		Has(
			"questTrackerMode",
			"questFocusOpacity",
			"questTrackerHideSolo",
			"questTrackerSnapToBlizzard",
			"questTrackerHideBlizzardTooltip",
			"questTrackerTooltipPlacement"
		)
	then
		Invoke(self, "QueueQuestFocusRefresh", true)
	end
	if Has("nativeGamepadNavigation") then
		Invoke(self, "SetGamepadIntegrationEnabled", self:GetOption("nativeGamepadNavigation") ~= false)
	end
	if Has("windowScale") then
		Invoke(self, "RefreshManagedWindowLayouts")
	end
	if Has("announceToNonQTParty", "hidePartyChatReminder") then
		Invoke(self, "UpdatePartyChatReminder")
	end
	if Has("lookingForQuestPartners") then
		Invoke(self, "RefreshMinimapPartnerGlow")
	end
	if Has("showDataBrokerLauncher", "lookingForQuestPartners", "brokerLeftClick", "brokerRightClick") then
		Invoke(self, "RefreshDataBroker")
	end
	if context.startedLooking then
		Invoke(self, "AnnounceQuestPartnerSearch")
	end
	if Has("sharePlayerLocation", "showPlayerLocations", "onlyShowQuestPartners") then
		Invoke(self, "OnPlayerLocationOptionsChanged", Has("sharePlayerLocation"))
	end
	if Has("lookingForQuestPartners", "sharePlayerLocation") then
		Invoke(self, "BroadcastQuestPartnerStatus", true)
	end
	-- Each presentation effect runs once against the final option values.
	if Has("experimentalLayerDetection", "sharePlayerLocation", "showPlayerLocations",
		"onlyShowQuestPartners", "clusterPlayerLocations", "showWorldMapData") then
		Invoke(self, "RefreshPlayerLocationPins")
	end
	if Has("showWorldMapData") then
		Invoke(self, "RefreshPartyWaypointPins")
	end
	if Has("showWorldMapData", "showWorldMapButton") then
		Invoke(self, "RefreshQuestTogetherMapControl")
	end
	if Has("showMinimapButton", "minimapButtonPosition") then
		Invoke(self, "RefreshMinimapButton")
	end
	if Has("chatLogDestination") then
		if self.db.profile.chatLogDestination == "separate" then
			local frame = self:EnsureQuestLogChatFrame()
			if frame then
				self:ApplyMainChatFontSizeToChatFrame(frame)
				if not all and self.isEnabled and self.hasLoggedIn then
					self:PrintChatLogDestinationMessage()
				end
			end
		else
			self:CloseQuestLogChatFrame()
		end
	end
	if Has("showChatBubbles", "ownChatBubbleMode", "chatBubbleSize", "chatBubbleDuration") then
		Invoke(self, "RefreshActiveAnnouncementBubbles")
		Invoke(self, "RefreshPersonalBubbleAnchorVisualState")
		Invoke(self, "RefreshPersonalBubbleEditModeDialog")
	end
	if Has("playerTooltipIdentifierMode") then
		Invoke(self, "UpdatePlayerTooltipBadge")
	end
	if
		Has(
			"nameplateQuestIconEnabled",
			"nameplatePlayerIconEnabled",
			"nameplatePlayerIconStyle",
			"nameplateQuestIconStyle",
			"nameplateQuestHealthColorEnabled",
			"nameplateQuestHealthColor"
		)
	then
		Invoke(self, "RefreshNameplateAugmentation")
	end
	local audioChanged = all
	for key in pairs(changed) do
		if self:IsAudioSetting(key) then
			audioChanged = true
		end
	end
	if audioChanged then
		Invoke(self, "ApplyAudioSettings", all)
	end
	if all then
		Invoke(self, "RefreshOptionsWindow")
		Invoke(self, "RefreshProfilesWindow")
		self:Debugf(
			"profile",
			"Applied active profile state reason=%s character=%s profile=%s",
			tostring(context.reason or "unknown"),
			tostring(self.activeCharacterKey),
			tostring(self.activeProfileKey)
		)
	end
	if resumeCompare and self.isEnabled then
		self:ScheduleDeferredWork("quest_snapshot_refresh", "party_compare_profile", function()
			if
				self.isEnabled
				and not self.isLoggingOut
				and rawget(self, "partyQuestCompareWindow") == compareFrame
				and (self.db and self.db.profile) == compareProfile
				and not rawget(self, "partyQuestCompareSession")
			then
				local ok, shown = pcall(compareFrame.IsShown, compareFrame)
				if ok and shown == true then
					self:RefreshPartyQuestCompare(nil, compareTarget, true)
				end
			end
		end, 0, "party compare profile replacement")
	end
	return true
end
