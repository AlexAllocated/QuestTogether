-- Settings transactions use private services and never touch live frames.
local QT = _G.QuestTogether
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
		"RefreshMinimapPartnerGlow",
		"RefreshPartyRoster",
		"RefreshOptionsWindow",
		"RefreshProfilesWindow",
		"RefreshNameplateAugmentation",
		"QueuePartyNavigationUpdate",
		"RefreshActiveAnnouncementBubbles",
		"RefreshPersonalBubbleAnchorVisualState",
		"RefreshPersonalBubbleEditModeDialog",
		"UpdatePartyChatReminder",
		"BroadcastQuestPartnerStatus",
		"AnnounceQuestPartnerSearch",
		"CancelDeveloperDiagnosticReplies",
		"CloseQuestLogChatFrame",
	}) do
		local name = method
		a[name] = function()
			a.effects[name] = (a.effects[name] or 0) + 1
		end
	end
	function a:Debugf() end
	return a
end

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

QT:RegisterTest("profile activation applies the same appearance privacy and navigation effects as edits", function()
	local a = Fixture()
	a.isEnabled = true
	a.hasLoggedIn = false
	a.developerRequestState = {}
	a.db.profile.lightMode, a.db.profile.reduceMotion, a.db.profile.windowScale = true, true, 125
	assert(a:ApplyActiveProfileState("test"))
	assert(a.effects.RefreshWindowThemes == 1 and a.effects.RefreshManagedWindowLayouts == 1)
	assert(a.effects.QueuePartyNavigationUpdate == 1)
	assert(a.effects.OnPlayerLocationOptionsChanged == 1)
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
		a.developerRequestState = {}
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
			Always = { ownChatBubbleMode = "always", hideMyOwnChatBubbles = true },
			Hidden = { ownChatBubbleMode = "hidden", hideMyOwnChatBubbles = false },
			Invalid = { ownChatBubbleMode = "unsupported", hideMyOwnChatBubbles = true },
		},
	})
	for key, expected in pairs({ Active = "hidden", Visible = "always", Missing = "always", Solo = "solo",
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
	for _, value in ipairs({ "always", "solo", "hidden" }) do
		assert(a:SetOption("ownChatBubbleMode", value))
		assert(a:GetOwnChatBubbleMode() == value)
	end
	for _, value in ipairs({ true, false, "", "sometimes", 0, {} }) do
		assert(not a:SetOption("ownChatBubbleMode", value))
	end
	assert(not a:SetOption("hideMyOwnChatBubbles", true))
	assert(a.effects.RefreshActiveAnnouncementBubbles == 3)
	assert(a.effects.RefreshPersonalBubbleAnchorVisualState == 3 and a.effects.RefreshPersonalBubbleEditModeDialog == 3)
	assert(not a.effects.OnPlayerLocationOptionsChanged and not a.effects.BroadcastQuestPartnerStatus)
	assert(not a.effects.QueuePartyNavigationUpdate)
	a.db.profile.ownChatBubbleMode = "invalid"
	assert(a:GetOwnChatBubbleMode() == "always")
	a:NormalizeSettingsProfile()
	assert(a.db.profile.ownChatBubbleMode == "always")
end)

QT:RegisterTest("own bubble solo policy reads current native membership and fails closed on unknown state", function()
	local a = Fixture()
	local grouped = false
	a.API = { IsInAnyGroup = function() return grouped end }
	for _, mode in ipairs({ "always", "solo", "hidden" }) do
		a.db.profile.ownChatBubbleMode = mode
		for _, membership in ipairs({ false, true }) do
			grouped = membership
			assert(a:ShouldShowOwnChatBubble() == (mode == "always" or (mode == "solo" and not membership)))
		end
		a.db.profile.showChatBubbles = false
		assert(a:ShouldShowOwnChatBubble() == false)
		a.db.profile.showChatBubbles = true
	end
	a.db.profile.ownChatBubbleMode = "solo"
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
end)
