-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Access = QuestTogether.NativeAccess
local SafeText = Access.Text
local tostring = SafeText
local LibChev = QuestTogether.LibChev

-- The runtime event list that should only be registered while the addon is enabled.
QuestTogether.runtimeEvents = {
	"UNIT_AURA",
	"CHAT_MSG_ADDON",
	"CHAT_MSG_CHANNEL_NOTICE",
	"CHAT_MSG_SYSTEM",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
	"PLAYER_TARGET_CHANGED",
	"UPDATE_MOUSEOVER_UNIT",
	"NAME_PLATE_UNIT_ADDED",
	"FRIENDLIST_UPDATE",
	"BN_FRIEND_LIST_SIZE_CHANGED",
	"BN_FRIEND_INFO_CHANGED",
	"BN_FRIEND_ACCOUNT_ONLINE",
	"BN_FRIEND_ACCOUNT_OFFLINE",
	"CHANNEL_COUNT_UPDATE",
	"PLAYER_LEVEL_UP",
	"QUEST_ACCEPTED",
	"QUEST_TURNED_IN",
	"QUEST_REMOVED",
	"UNIT_QUEST_LOG_CHANGED",
	"QUEST_LOG_UPDATE",
	"QUEST_DATA_LOAD_RESULT",
	"QUEST_POI_UPDATE",
	"AREA_POIS_UPDATED",
	"PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED",
	"ZONE_CHANGED",
	"ZONE_CHANGED_INDOORS",
	"ZONE_CHANGED_NEW_AREA",
	"SHARD_TRANSFER",
	"SHARD_TRANSFER_IMMINENT",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_REGEN_DISABLED",
	"ADDON_RESTRICTION_STATE_CHANGED",
	"SUPER_TRACKING_CHANGED",
	"USER_WAYPOINT_UPDATED",
	"GROUP_JOINED",
	"GROUP_ROSTER_UPDATE",
	"IGNORELIST_UPDATE",
}

function QuestTogether:RegisterRuntimeEvents()
	self.registeredRuntimeEvents = self.registeredRuntimeEvents or {}
	wipe(self.registeredRuntimeEvents)

	for _, eventName in ipairs(self.runtimeEvents) do
		-- Event lists vary slightly by client flavor/build; register best-effort.
		local ok
		if eventName == "UNIT_AURA" and type(self.eventFrame.RegisterUnitEvent) == "function" then
			ok = pcall(self.eventFrame.RegisterUnitEvent, self.eventFrame, eventName, "player")
		else
			ok = pcall(self.eventFrame.RegisterEvent, self.eventFrame, eventName)
		end
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
	if self.IsWelcomeSetupPending and self:IsWelcomeSetupPending() then
		return false
	end
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
	self:InitializeQTAudio()
	self:InitializeAutoThanks()
	self:RefreshAudioWindow()
	self:RefreshDataBroker()
	self:ResumeCommsWorldSession()
	self:RefreshMinimapPartnerGlow()
	self:ResetQuestEventState()
	-- Events may have been missed while disabled/offline, including a repeatable
	-- quest being accepted again. Start a fresh observation lifetime on enable.
	wipe(self:GetPlayerTracker())
	self:ResetTaskAreaStateStore()
	self:ResetRuntimeWorkStateStore()
	self:InitializeTransport()
	self:InitializeGeographicComms()
	if self.API.LeaveChannelByName then
		pcall(self.API.LeaveChannelByName, self.retiredAnnouncementChannelName)
	end
	self:EnsureMeshDirectoryJoined(self.announcementChannelName)
	self:RefreshTaskAreaStates(false)

	self:EnableNameplateAugmentation()
	self:TryInstallPersonalBubbleEditModeHooks()
	self:RefreshPersonalBubbleAnchorVisualState()

	self:Debug(L("Addon enabled."), "core")

	self:RefreshPartyRoster()

	-- Delay initial scan briefly so quest log APIs are stable right after login/reload.
	local enabledWorkState = self:GetDeferredWorkStateStore()
	self.API.Delay(0.25, function()
		if self.isEnabled and self:GetDeferredWorkStateStore() == enabledWorkState then
			self:ScanQuestLog()
		end
	end)
	self:InitializePlayerLocations()
	self:InitializeRuntimeCoordinator()

	return true
end

function QuestTogether:Disable()
	self.db.profile.enabled = false
	self:ResetQTAudio()
	self:ResetAutoThanks()
	self.pendingQuestScanAnnouncement = nil

	if not self.isEnabled then
		return true
	end
	self:RecordRecentCompanions(true)
	self:ResetRecentCompanionObservation()
	self:DismissRecentCompanions()
	self:WithdrawPartyNavigation()
	self:EndCommsWorldSession()
	self:BroadcastQTPlayerPresence(true)
	self:BroadcastPlayerLocation(true, true)
	self:FlushGeographicDeparture()

	self:UnregisterRuntimeEvents()
	self:ResetRuntimeCoordinator()
	self.isEnabled = false
	self:RefreshAudioWindow()
	self:RefreshDataBroker()
	self:RefreshMinimapPartnerGlow()
	self:ResetQuestEventState()
	self:ResetTaskAreaStateStore()
	self:ResetRuntimeWorkStateStore()
	self:LeaveAnnouncementChannel()

	self:DisableNameplateAugmentation()
	self:RefreshPersonalBubbleAnchorVisualState()

	self:Debug(L("Addon disabled."), "core")
	return true
end

function QuestTogether:OnInitialize()
	self:InitializeDatabase()
	if self.InitializeGamepadIntegration then
		self:InitializeGamepadIntegration()
	end
	if self.InitializeGamepadTracker then
		self:InitializeGamepadTracker()
	end
	if self.InitializeGamepadMap then
		self:InitializeGamepadMap()
	end
	self:EnsureRuntimeStateStore()
	self:InitializePartyState()
	self:TryInstallNameplateHooks()
	self:TryInstallPersonalBubbleEditModeHooks()
	self:TryInstallChatLogLinkHandler()
	self:TryInstallChatWindowHooks()
	self:InitializeSlashCommands()
	self:InitializeOptionsWindow()
	self.isInitialized = true
end

function QuestTogether:OnLogin()
	self.hasLoggedIn = true
	self.isLoggingOut = false
	if self:IsWelcomeSetupPending() then
		self:RetirePublicSharingChannels()
		self:InitializePresetWelcome()
		return
	end
	self:RetirePublicSharingChannels()
	self:BeginAnnouncementChannelStartup()
	-- Preserve ordinary whisper intent before a disabled profile is enabled.
	-- This passive observer/filter does not initialize transport or send data.
	self:RegisterAddonWhisperChatFilter()
	self:ReconcileQuestLogChatDestination()
	if self.db.profile.enabled then
		self:Enable()
	end
	self:InitializeMinimapLauncher()
	self:RefreshDataBroker()
	self:NotifyAddonUpdate()
	self:InitializeReleaseNotes()
	self:ScheduleStartupHint()
end

-- Bootstrap event handlers always registered.
function QuestTogether:ADDON_LOADED(_, loadedAddonName)
	if self.OnQuestChainDataEvent then
		self:OnQuestChainDataEvent("ADDON_LOADED", loadedAddonName)
	end
	if self.isInitialized and self.InitializeGamepadIntegration then
		self:InitializeGamepadIntegration()
	end
	if self.hasLoggedIn then
		self:RefreshDataBroker()
	end
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
	self:ResetPlayerPhases()
	self.isLoggingOut = false
	self:ResumeAnnouncementChannelJoins()
	if not self.isEnabled then
		return
	end
	self:InitializeAutoThanks()
	if not rawget(self, "audioState") then
		self:InitializeQTAudio()
	end
	self:RefreshPartyRoster()
	self:ResumeCommsWorldSession()
	if self.ResumePartyQuestChains then
		self:ResumePartyQuestChains()
	end
	-- Refresh after loading screens without synthetic enter/leave announcements.
	self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false)
	self:RefreshTaskAreaStates(false)
	if self.EnsureMeshDirectoryJoined and self.isEnabled then
		self:EnsureMeshDirectoryJoined(self.announcementChannelName)
	end
end

function QuestTogether:PLAYER_LEAVING_WORLD()
	self:SuspendAnnouncementChannelJoins()
	self:ResetAutoThanks()
	if self.RetirePartyQuestChains then
		self:RetirePartyQuestChains()
	end
	self:ResetQTAudio()
	self:ResetPlayerPhases()
	self:ResetObjectiveAnnouncements()
	self:RecordRecentCompanions(true)
	self:ResetRecentCompanionObservation()
	if self.isEnabled then
		self:EndCommsWorldSession(true)
		self:BroadcastQTPlayerPresence(true)
		self:BroadcastPlayerLocation(true, true)
		self:FlushGeographicDeparture()
	end
	self.isLoggingOut = true
end

function QuestTogether:PLAYER_LOGOUT()
	self:ResetAutoThanks()
	if self.RetirePartyQuestChains then
		self:RetirePartyQuestChains()
	end
	self:ResetQTAudio()
	self:RecordRecentCompanions(true)
	self:ResetRecentCompanionObservation()
	self:SavePlayerLocationCache()
	self.isLoggingOut = true
end

-- Shared event dispatcher for all WoW events this addon listens for.
local function DispatchEvent(addon, eventName, ...)
	local handler = addon[eventName]
	if type(handler) ~= "function" then
		return
	end

	local ok, err
	if addon.RunGuardedCallback then
		ok, err = addon:RunGuardedCallback(eventName, handler, addon, eventName, ...)
	else
		ok, err = pcall(handler, addon, eventName, ...)
	end
	if not ok then
		if type(geterrorhandler) == "function" then
			geterrorhandler()(err)
		end
	end
end

-- Bootstrap lifecycle and diagnostic events outlive the enabled runtime. Keep
-- registration on the addon-owned frame so private tests use this exact path.
function QuestTogether:RegisterBootstrapEvents()
	self.eventFrame:SetScript("OnEvent", function(_, eventName, ...)
		DispatchEvent(self, eventName, ...)
	end)
	for _, eventName in ipairs({
		"ADDON_LOADED",
		"PLAYER_ENTERING_WORLD",
		"PLAYER_LEAVING_WORLD",
		"PLAYER_LOGIN",
		"PLAYER_LOGOUT",
		"ADDON_ACTION_BLOCKED",
		"ADDON_ACTION_FORBIDDEN",
	}) do
		self.eventFrame:RegisterEvent(eventName)
	end
	for _, eventName in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
		pcall(self.eventFrame.RegisterEvent, self.eventFrame, eventName)
	end
	pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUESTLINE_UPDATE")
end

function QuestTogether:QUESTLINE_UPDATE(_, ...)
	if self.OnQuestChainDataEvent then
		self:OnQuestChainDataEvent("QUESTLINE_UPDATE", ...)
	end
end

QuestTogether.eventFrame = QuestTogether.eventFrame or CreateFrame("Frame")
QuestTogether:RegisterBootstrapEvents()
