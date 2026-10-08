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
