-- Settings transactions use private services and never touch live frames.
local QT = _G.QuestTogether

QT:RegisterTest("focus suggestions preserve existing prompt opt-outs only at profile migration", function()
	local disabled = { allowIncomingShareRequests = false }
	QT:MigrateFocusSuggestionOption(disabled)
	assert(disabled.allowFocusSuggestions == false)
	disabled.allowFocusSuggestions = true
	QT:MigrateFocusSuggestionOption(disabled)
	assert(disabled.allowFocusSuggestions == true)
	local normal = { allowIncomingShareRequests = true }
	QT:MigrateFocusSuggestionOption(normal)
	assert(normal.allowFocusSuggestions == nil)
	local a = setmetatable({db = { profiles = { Child = { allowIncomingShareRequests = false } } }}, {__index = QT})
	assert(a:EnsureProfileStorage())
	assert(a.db.profiles.Child.allowFocusSuggestions == false)
end)

QT:RegisterTest("preset bundles preserve unrelated preferences and kid emotes", function()
	local a = setmetatable({ db = { profile = QT:DeepCopy(QT.DEFAULTS.profile), global = {} } }, { __index = QT })
	function a:IsRuntimeRestricted() return false end
	function a:ApplySettingsTransaction(changed) self.applied = changed; return true end
	function a:RefreshOptionsWindow() end
	a.db.profile.lightMode, a.db.profile.windowScale, a.db.profile.compareGroupByChain = true, 125, true
	a.db.profile.enabled = false
	assert(a:ApplyPreset("kid", true))
	assert(a:GetOption("automaticLeaderFocus") and a:GetOption("sharingAudience") == "party")
	assert(a:GetOption("autoThankBuffs") and a:GetOption("emoteOnQuestCompletion") and a:GetOption("emoteOnLevelUp"))
	assert(not a:GetOption("showTrackerFocusIndicators") and not a:GetOption("showMinimapButton"))
	assert(not a:GetOption("showChatLogs") and not a:GetOption("showQTChat") and not a:GetOption("audioEnabled"))
	assert(a.db.profile.enabled == false and a.db.profile.lightMode and a.db.profile.windowScale == 125 and a.db.profile.compareGroupByChain)
	assert(a:GetMatchingPreset() == "kid" and a.db.global.defaultPreset == "kid")
	local new = a:CreateDefaultProfile()
	assert(new.enabled and new.automaticLeaderFocus and new.windowScale == 100)
	assert(a:SetOption("showMinimapButton", true) and a:GetMatchingPreset() == nil)
	assert(a:ApplyPreset("full", false) and a:GetMatchingPreset() == "full")
	assert(a.db.global.defaultPreset == "kid" and not a.db.profile.enabled and a.db.profile.windowScale == 125)
	for _, entry in ipairs(a:GetPresetDefinitions()) do
		local values = a:GetPresetValues(entry.id)
		for key, value in pairs(values) do assert(a:ValidateSetting(key, value) ~= nil, key) end
	end
	assert(a:GetPresetValues("unknown") == nil and not a:ApplyPreset("unknown"))
end)

QT:RegisterTest("preset detail lists cover every applied option with actual values and usage scenarios", function()
	local seenNames = {}
	for _, preset in ipairs(QT:GetPresetDefinitions()) do
		assert(preset.scenario and #preset.scenario > 40 and preset.description ~= preset.scenario)
		assert(not seenNames[preset.title]); seenNames[preset.title] = true
		local expected, seen = QT:GetPresetValues(preset.id), {}
		for _, group in ipairs(QT:GetPresetSettingDetails(preset.id)) do
			assert(group.title ~= "" and #group.entries > 0)
			for _, entry in ipairs(group.entries) do
				assert(not seen[entry.key], "duplicate detail: " .. entry.key)
				seen[entry.key] = true
				assert(expected[entry.key] ~= nil and expected[entry.key] == entry.value, entry.key)
				assert(entry.label ~= "" and entry.text ~= "" and entry.text ~= QT:Translate("Unknown"), entry.key)
			end
		end
		for key in pairs(expected) do assert(seen[key], "missing detail: " .. key) end
	end
	assert(QT:GetPresetSettingDetails("unknown") == nil)
end, { locale = "client" })

QT:RegisterTest("welcome detects genuinely fresh storage and acknowledges only successful setup", function()
	local function Model(db)
		local a = setmetatable({}, { __index = QT })
		function a:GetCurrentCharacterKey() return "NewCharacter" end
		function a:RefreshOptionsWindow() end
		function a:ApplySettingsTransaction() return true end
		function a:IsRuntimeRestricted() return self.restricted == true end
		function a:OnLogin() self.logins = (self.logins or 0) + 1 end
		function a:GetAddonVersion() return "10.1.0" end
		a:InitializeDatabase(db)
		return a
	end
	local a = Model({})
	assert(a:IsWelcomeSetupPending() and not a:IsPublicSharingAllowed())
	a.restricted = true
	assert(not a:ApplyPreset("kid") and a:IsWelcomeSetupPending())
	a.restricted = false
	assert(a:ApplyPreset("kid") and not a:IsWelcomeSetupPending())
	assert(a.logins == 1 and a.db.global.releaseNotesSeenVersion == "10.1.0")
	local existing = Model({global = {releaseNotesSeenVersion = ""}, profiles = {}})
	assert(not existing:IsWelcomeSetupPending())
	local inherited = Model({global = {welcomeSetupComplete = true, defaultPreset = "kid"}})
	assert(not inherited:IsWelcomeSetupPending() and inherited:GetOption("automaticLeaderFocus"))
end)

QT:RegisterTest("sharing audience fences routes senders discovery and setup independently of presets", function()
	local a = setmetatable({db = {profile = {sharingAudience = "party"}, global = {}}}, {__index = QT})
	function a:GetGroupAnnouncementDistribution() return "PARTY" end
	function a:IsGroupedSender(name) return name == "Parent" end
	assert(not a:IsPublicSharingAllowed())
	for _, route in ipairs({{distribution="MESH",scope="global"}, {distribution="CHANNEL",target=1},
		{distribution="WHISPER",target="Stranger"}, {distribution="WHISPER",target="Parent",meshTraffic=true},
		{distribution="RAID"}, {distribution="PARTY",recipient="Stranger"}}) do assert(not a:IsSharingRouteAllowed(route)) end
	assert(a:IsSharingRouteAllowed({distribution="PARTY"}) and a:IsSharingRouteAllowed({distribution="WHISPER",target="Parent"}))
	assert(a:IsSharingSenderAllowed("Parent", "PARTY") and not a:IsSharingSenderAllowed("Stranger", "PARTY"))
	assert(not a:IsSharingSenderAllowed("Parent", "CHANNEL"))
	a.db.global.welcomeSetupComplete = false
	assert(not a:IsSharingRouteAllowed({distribution="PARTY"}) and not a:IsSharingSenderAllowed("Parent", "WHISPER"))
	a.db.global.welcomeSetupComplete = true
	a.db.profile.sharingAudience = "normal"
	assert(a:IsPublicSharingAllowed() and a:IsSharingRouteAllowed({distribution="MESH",scope="global"}))
end)
QT:RegisterTest("welcome pending startup cannot register launchers or emit runtime announcements", function()
	local a = setmetatable({db={global={welcomeSetupComplete=false},profile={enabled=true}}}, {__index=QT})
	local attempts = 0
	for _, key in ipairs({"BeginAnnouncementChannelStartup", "RegisterAddonWhisperChatFilter", "ReconcileQuestLogChatDestination",
		"InitializeMinimapLauncher", "RefreshDataBroker", "NotifyAddonUpdate", "InitializeReleaseNotes", "ScheduleStartupHint"}) do
		a[key] = function() attempts = attempts + 1 end
	end
	function a:RetirePublicSharingChannels() self.retired = true end
	function a:InitializePresetWelcome() self.welcome = true end
	a:OnLogin()
	assert(a.welcome and a.retired and attempts == 0 and not a:Enable() and not rawget(a, "isEnabled"))
end)
QT:RegisterTest("preset values match manual option transactions and keep copied profiles independent", function()
	for _, entry in ipairs(QT:GetPresetDefinitions()) do
		local function Model()
			local a = setmetatable({db={profile=QT:DeepCopy(QT.DEFAULTS.profile),global={}}}, {__index=QT})
			function a:IsRuntimeRestricted() return false end
			function a:ApplySettingsTransaction() return true end
			function a:RefreshOptionsWindow() end
			return a
		end
		local bundled, manual = Model(), Model()
		assert(bundled:ApplyPreset(entry.id))
		assert(manual:SetOptions(manual:GetPresetValues(entry.id)))
		for key, value in pairs(bundled.db.profile) do
			if type(value) ~= "table" then assert(manual:GetOption(key) == value, key) end
		end
		bundled.db.global.defaultPreset = "kid"
		local copy = bundled:DeepCopy(bundled.db.profile)
		bundled.db.profiles = {Existing=copy}
		bundled:EnsureProfile("Existing")
		assert(bundled.db.profiles.Existing == copy and copy.automaticLeaderFocus == (entry.id == "kid"))
	end
end)

local function Fixture()
	local a = setmetatable(
		{ db = { profile = QT:DeepCopy(QT.DEFAULTS.profile), global = {} }, effects = {} },
		{ __index = QT }
	)
	for _, method in ipairs({
		"RefreshWindowThemes",
		"RefreshManagedWindowLayouts",
		"OnPlayerLocationOptionsChanged",
		"RefreshPlayerLocationPins",
		"RefreshPartyWaypointPins",
		"RefreshQuestTogetherMapControl",
		"RefreshMinimapButton",
		"RefreshDataBroker",
		"BroadcastPlayerLocation",
		"RefreshMinimapPartnerGlow",
		"RefreshPartyRoster",
		"RefreshOptionsWindow",
		"RefreshProfilesWindow",
		"RefreshNameplateAugmentation",
		"UpdatePlayerTooltipBadge",
		"QueuePartyNavigationUpdate",
		"RefreshActiveAnnouncementBubbles",
		"RefreshPersonalBubbleAnchorVisualState",
		"RefreshPersonalBubbleEditModeDialog",
		"UpdatePartyChatReminder",
		"BroadcastQuestPartnerStatus",
		"AnnounceQuestPartnerSearch",
		"CloseQuestLogChatFrame",
	}) do
		local name = method
		a[name] = function()
			a.effects[name] = (a.effects[name] or 0) + 1
		end
	end
	function a:CancelDeveloperDiagnosticReplies()
		self.effects.CancelDeveloperDiagnosticReplies = (self.effects.CancelDeveloperDiagnosticReplies or 0) + 1
		return QT.CancelDeveloperDiagnosticReplies(self)
	end
	function a:Debugf() end
	return a
end

QT:RegisterTest("map filter transactions preserve outgoing leases and do not publish", function()
	local a = Fixture()
	a.isEnabled = true
	a.OnPlayerLocationOptionsChanged = QT.OnPlayerLocationOptionsChanged
	local wanted, outgoing = {}, {}
	a.nearbyStreamState = { wanted = { viewer = wanted }, subscribers = { subscriber = outgoing }, nextCapability = 130 }
	local cancelled = {}
	function a:CancelCommunicationOwner(owner) cancelled[owner] = true end
	-- The settings dropdown submits both options without a single-option key.
	assert(a:SetOptions({ onlyShowQuestPartners = true, showPlayerLocations = true }))
	assert(cancelled[wanted] and not cancelled[outgoing])
	assert(a.nearbyStreamState.subscribers.subscriber == outgoing and a.nearbyStreamState.nextCapability == 130)
	assert(not a.effects.BroadcastPlayerLocation and not a.effects.BroadcastQuestPartnerStatus)
	assert(a.effects.RefreshPlayerLocationPins == 1)
end)

QT:RegisterTest("batched sharing changes revoke leases and publish once independent of transaction reason", function()
	for _, reason in ipairs({ "preset", "sharePlayerLocation" }) do
		local a = Fixture()
		a.isEnabled = true
		a.OnPlayerLocationOptionsChanged = QT.OnPlayerLocationOptionsChanged
		local outgoing = {}
		a.nearbyStreamState = { wanted = {}, subscribers = { subscriber = outgoing }, nextCapability = 130 }
		function a:CancelCommunicationOwner(owner) self.cancelled = owner end
		assert(a:SetOptions({ sharePlayerLocation = false, lookingForQuestPartners = false,
			clusterPlayerLocations = false, showWorldMapData = false, showWorldMapButton = false,
			showDataBrokerLauncher = false }, reason))
		assert(a.cancelled == outgoing and not next(a.nearbyStreamState.subscribers))
		assert(a.nearbyStreamState.nextCapability == 0)
		assert(a.effects.BroadcastPlayerLocation == 1 and a.effects.BroadcastQuestPartnerStatus == 1)
		assert(a.effects.RefreshPlayerLocationPins == 1)
		assert(a.effects.RefreshQuestTogetherMapControl == 1 and a.effects.RefreshDataBroker == 1)
	end
end)

QT:RegisterTest("settings batches validate all inputs before persistence or effects", function()
	local a = Fixture()
	assert(not a:SetOptions({ lightMode = true, windowScale = 900 }))
	assert(a.db.profile.lightMode == false and a.db.profile.windowScale == 100 and not next(a.effects))
	for _, bad in ipairs({ "false", 0, {} }) do
		assert(not a:SetOption("announceAccepted", bad))
	end
	assert(not a:SetOption("unknownOption", true))
	assert(not a:SetOption("mapPartyOnly", true))
	assert(not a:SetOption("shareLocationOnMap", true))
	assert(not a:SetOption("compareQuestAction", "delete"))
	assert(a:SetOptions({ showPlayerLocations = true, onlyShowQuestPartners = true }))
	assert(a.effects.OnPlayerLocationOptionsChanged == 1)
	assert(a:SetOptions({ lightMode = true, reduceMotion = true }))
	assert(a.effects.RefreshWindowThemes == 1)
end)

QT:RegisterTest("player tooltip identifier modes default to hiding friends and persist through profile normalization", function()
	local a = Fixture()
	assert(a:GetPlayerTooltipIdentifierMode() == "friends")
	for index, mode in ipairs({ "all", "friends", "party", "friends_party", "hidden" }) do
		assert(a:SetOption("playerTooltipIdentifierMode", mode))
		a:NormalizeSettingsProfile()
		assert(a:GetPlayerTooltipIdentifierMode() == mode)
		assert(a.effects.UpdatePlayerTooltipBadge == index)
	end
	for _, invalid in ipairs({ false, true, 3, {}, "unsupported" }) do
		assert(not a:SetOption("playerTooltipIdentifierMode", invalid))
	end
	assert(a:GetPlayerTooltipIdentifierMode() == "hidden")
	a.db.profile.playerTooltipIdentifierMode = nil
	a:NormalizeSettingsProfile()
	assert(a:GetPlayerTooltipIdentifierMode() == "friends")
	assert(not a.effects.OnPlayerLocationOptionsChanged and not a.effects.BroadcastQuestPartnerStatus)
end)

QT:RegisterTest("profile activation applies the same appearance privacy and navigation effects as edits", function()
	local a = Fixture()
	a.isEnabled = true
	a.hasLoggedIn = false
	a.developerRequestState = { jobs = {}, seen = {}, pendingSenders = {}, failures = {} }
	a.db.profile.lightMode, a.db.profile.reduceMotion, a.db.profile.windowScale = true, true, 125
	assert(a:ApplyActiveProfileState("test"))
	assert(a.effects.RefreshWindowThemes == 1 and a.effects.RefreshManagedWindowLayouts == 1)
	assert(a.effects.QueuePartyNavigationUpdate == 1)
	assert(a.effects.OnPlayerLocationOptionsChanged == 1)
	assert(a.effects.RefreshPlayerLocationPins == 1)
	assert(a.effects.RefreshQuestTogetherMapControl == 1 and a.effects.RefreshDataBroker == 1)
	assert(a.effects.BroadcastQuestPartnerStatus == 1)
	assert(a.effects.CancelDeveloperDiagnosticReplies == 1 and a.developerRequestState == nil)
	assert(not a.effects.AnnounceQuestPartnerSearch, "profile activation does not announce a new search")
end)

QT:RegisterTest("settings copy color values and normalize persisted values through their edit schema", function()
	local a = Fixture()
	local color = { r = 0.3, g = 0.5, b = 0.7 }
	assert(a:SetOption("nameplateQuestHealthColor", color))
	color.r = 1
	assert(a.db.profile.nameplateQuestHealthColor.r == 0.3)
	a.db.profile.windowScale = 999
	a.db.profile.announceProgress = "yes"
	a.db.profile.compareQuestOwnership = "unsupported"
	a.db.profile.minimapButtonPosition = -45
	a:NormalizeSettingsProfile()
	assert(a.db.profile.windowScale == 100 and a.db.profile.announceProgress == true)
	assert(a.db.profile.compareQuestOwnership == "all" and a.db.profile.minimapButtonPosition == 315)
end)

QT:RegisterTest("map clustering defaults on and toggles presentation without publication effects", function()
	local a = Fixture()
	a.db.profile.clusterPlayerLocations = nil
	a:NormalizeSettingsProfile()
	assert(a:GetOption("clusterPlayerLocations") == true)
	a.playerLocationClusterExpansion = { key = "old", page = 2 }
	assert(a:SetOption("clusterPlayerLocations", false))
	assert(a:GetOption("clusterPlayerLocations") == false and not a.playerLocationClusterExpansion)
	assert(a.effects.RefreshPlayerLocationPins == 1)
	assert(not a.effects.OnPlayerLocationOptionsChanged and not a.effects.BroadcastQuestPartnerStatus)
	assert(not a.effects.QueuePartyNavigationUpdate)
	a:NormalizeSettingsProfile()
	assert(a:GetOption("clusterPlayerLocations") == false, "saved opt-out must survive normalization")
	assert(not a:SetOption("clusterPlayerLocations", "false"))
	assert(a:SetOption("clusterPlayerLocations", true))
	assert(a.effects.RefreshPlayerLocationPins == 2 and not a.effects.OnPlayerLocationOptionsChanged)
end)

QT:RegisterTest("world map overlay visibility is saved per profile without changing sharing", function()
	local a = Fixture()
	a.db.profile.showWorldMapData = nil
	a:NormalizeSettingsProfile()
	assert(a:GetOption("showWorldMapData") == true)
	assert(a:SetOption("showWorldMapData", false))
	a:NormalizeSettingsProfile()
	assert(a:GetOption("showWorldMapData") == false)
	assert(a.effects.RefreshPlayerLocationPins == 1 and a.effects.RefreshPartyWaypointPins == 1)
	assert(a.effects.RefreshQuestTogetherMapControl == 1)
	assert(not a.effects.OnPlayerLocationOptionsChanged and not a.effects.BroadcastQuestPartnerStatus)
	assert(not a.effects.QueuePartyNavigationUpdate)
	assert(not a:SetOption("showWorldMapData", "false"))
	a.db.profile = QT:DeepCopy(QT.DEFAULTS.profile)
	assert(a:GetOption("showWorldMapData") == true)
end)

QT:RegisterTest("profile replacement retires expanded map clusters independently of the new preference", function()
	local a = Fixture()
	a.hasLoggedIn, a.isEnabled = false, true
	a.playerLocationClusterExpansion = { key = "old", page = 2 }
	a.db.profile.clusterPlayerLocations = true
	assert(a:ApplyActiveProfileState("switch"))
	assert(not a.playerLocationClusterExpansion)
	a.playerLocationClusterExpansion = { key = "another", page = 1 }
	a.db.profile.clusterPlayerLocations = false
	assert(a:ApplyActiveProfileState("copy"))
	assert(not a.playerLocationClusterExpansion and a:GetOption("clusterPlayerLocations") == false)
end)

QT:RegisterTest(
	"settings diagnostics revocation cancels requests and never reuses an old permission lifetime",
	function()
		local a = Fixture()
		a.developerRequestState = { jobs = {}, seen = {}, pendingSenders = {}, failures = {} }
		assert(a:SetOption("shareDeveloperDiagnostics", false))
		assert(a.developerRequestState == nil and a.effects.CancelDeveloperDiagnosticReplies == 1)
		assert(a:SetOption("shareDeveloperDiagnostics", true))
		assert(a.developerRequestState == nil and a.effects.CancelDeveloperDiagnosticReplies == 1)
	end
)

QT:RegisterTest("own bubble modes migrate active inactive and copied profiles before defaults", function()
	local a = Fixture()
	function a:GetCurrentCharacterKey() return "OwnBubble-Realm" end
	function a:ApplyActiveProfileState()
		self:NormalizeSettingsProfile()
		return true
	end
	local detached = { hideMyOwnChatBubbles = true }
	a:InitializeDatabase({
		profile = detached,
		profileKeys = { ["OwnBubble-Realm"] = "Active" },
		profiles = {
			Active = { hideMyOwnChatBubbles = true },
			Visible = { hideMyOwnChatBubbles = false },
			Missing = {},
			Solo = { ownChatBubbleMode = "solo", hideMyOwnChatBubbles = true },
			Party = { ownChatBubbleMode = "party", hideMyOwnChatBubbles = true },
			Always = { ownChatBubbleMode = "always", hideMyOwnChatBubbles = true },
			Hidden = { ownChatBubbleMode = "hidden", hideMyOwnChatBubbles = false },
			Invalid = { ownChatBubbleMode = "unsupported", hideMyOwnChatBubbles = true },
		},
	})
	for key, expected in pairs({ Active = "hidden", Visible = "always", Missing = "always", Solo = "solo", Party = "party",
		Always = "always", Hidden = "hidden", Invalid = "hidden" }) do
		assert(a.db.profiles[key].ownChatBubbleMode == expected, key)
		assert(a.db.profiles[key].hideMyOwnChatBubbles == nil, key .. " retained legacy key")
	end
	assert(detached.ownChatBubbleMode == "hidden" and detached.hideMyOwnChatBubbles == nil)
	assert(a:GetOwnChatBubbleMode() == "hidden")
	local _, imported = a:EnsureProfile("Imported", { hideMyOwnChatBubbles = true })
	assert(imported.ownChatBubbleMode == "hidden" and imported.hideMyOwnChatBubbles == nil)
	assert(a:CreateProfile("Copied", "Solo"))
	assert(a.db.profiles.Copied.ownChatBubbleMode == "solo")
	assert(a:SetActiveProfile("Visible") and a:GetOwnChatBubbleMode() == "always")
	assert(a:CopyProfileIntoActiveProfile("Imported") and a:GetOwnChatBubbleMode() == "hidden")
	assert(a:ResetActiveProfile() and a:GetOwnChatBubbleMode() == "always")
end)

QT:RegisterTest("own bubble settings validate modes and refresh presentation without publication", function()
	local a = Fixture()
	assert(QT.DEFAULTS.profile.ownChatBubbleMode == "always" and QT.DEFAULTS.profile.hideMyOwnChatBubbles == nil)
	for _, value in ipairs({ "always", "solo", "party", "hidden" }) do
		assert(a:SetOption("ownChatBubbleMode", value))
		assert(a:GetOwnChatBubbleMode() == value)
	end
	for _, value in ipairs({ true, false, "", "sometimes", 0, {} }) do
		assert(not a:SetOption("ownChatBubbleMode", value))
	end
	assert(not a:SetOption("hideMyOwnChatBubbles", true))
	assert(a.effects.RefreshActiveAnnouncementBubbles == 4)
	assert(a.effects.RefreshPersonalBubbleAnchorVisualState == 4 and a.effects.RefreshPersonalBubbleEditModeDialog == 4)
	assert(not a.effects.OnPlayerLocationOptionsChanged and not a.effects.BroadcastQuestPartnerStatus)
	assert(not a.effects.QueuePartyNavigationUpdate)
	a.db.profile.ownChatBubbleMode = "invalid"
	assert(a:GetOwnChatBubbleMode() == "always")
	a:NormalizeSettingsProfile()
	assert(a.db.profile.ownChatBubbleMode == "always")
end)

QT:RegisterTest("own bubble conditional policy reads current native membership and fails closed on unknown state", function()
	local a = Fixture()
	local grouped = false
	a.API = { IsInAnyGroup = function() return grouped end }
	for _, mode in ipairs({ "always", "solo", "party", "hidden" }) do
		a.db.profile.ownChatBubbleMode = mode
		for _, membership in ipairs({ false, true }) do
			grouped = membership
			assert(a:ShouldShowOwnChatBubble() == (mode == "always" or (mode == "solo" and not membership) or (mode == "party" and membership)))
		end
		a.db.profile.showChatBubbles = false
		assert(a:ShouldShowOwnChatBubble() == false)
		a.db.profile.showChatBubbles = true
	end
	for _, mode in ipairs({ "solo", "party" }) do
	a.db.profile.ownChatBubbleMode = mode
	a.API.IsInAnyGroup = function() return grouped end
	for _, invalid in ipairs({ "false", 0, {} }) do
		grouped = invalid
		assert(a:ShouldShowOwnChatBubble() == false)
	end
	grouped = nil
	assert(a:ShouldShowOwnChatBubble() == false)
	local secret = {}
	grouped = secret
	function a:CanAccessValue(value) return value ~= secret end
	assert(a:ShouldShowOwnChatBubble() == false)
	a.API.IsInAnyGroup = function() error("native membership unavailable") end
	assert(a:ShouldShowOwnChatBubble() == false)
	a.API.IsInAnyGroup = nil
	assert(a:ShouldShowOwnChatBubble() == false)
	end
end)

_G.QuestTogether:RecordTestModule("scripts/regression_settings.lua")
