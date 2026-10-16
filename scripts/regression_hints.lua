-- Private clients, chat sinks and clocks. No native UI or global API replacement.
local QT = _G.QuestTogether
local function Fixture(global)
	local a = setmetatable({
		hasLoggedIn = true,
		isEnabled = true,
		isLoggingOut = false,
		db = {
			global = global or {},
			profile = { enabled = true, showStartupTips = QT.DEFAULTS.profile.showStartupTips },
		},
		runtimeStateStore = {},
		messages = {},
		notices = {},
		capabilities = {},
		outputAttempts = 0,
	}, { __index = QT })
	local clock = QT:CreateTestClock(0)
	a.API = {
		Random = function(_, maximum)
			return a.pickLast and maximum or 1
		end,
		Delay = function(delay, callback)
			clock:After(delay, callback)
		end,
		GetHintCapabilities = function()
			return a.capabilities
		end,
	}
	function a:IsWorkBlocked()
		return self.blocked == true
	end
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	function a:CreateRuntimeUIWorkFrame()
		return QT:CreateTestUIRegion({})
	end
	function a:TryAddMessageToConfiguredChatLogFrames(text)
		self.outputAttempts = self.outputAttempts + 1
		if self.failOutput then
			return false
		end
		self.messages[#self.messages + 1] = text
		return true
	end
	function a:Print(text)
		self.notices[#self.notices + 1] = text
	end
	function a:SendChatMessage()
		error("tips must remain local")
	end
	function a:Emit()
		error("tips must not become network announcements")
	end
	function a:ReconcileQuestLogChatDestination()
		self.destinationReady = true
	end
	function a:Enable()
		self.isEnabled = true
	end
	function a:InitializeMinimapLauncher() end
	function a:NotifyAddonUpdate() end
	function a:InitializeReleaseNotes() end
	return a, clock
end

local function NavigationFixture()
	local a = Fixture()
	a.opened = {}
	a.capabilities.hud = true
	function a:OpenSettingsCategory(category)
		self.opened[#self.opened + 1] = "settings:" .. category
		return true
	end
	for method, destination in pairs({
		OpenPartyQuestCompare = "party_log",
		OpenReleaseNotes = "patch_notes",
		OpenDiscordSupport = "support",
		ShowDebugWindow = "debug",
		OpenHudEditMode = "hud_edit",
	}) do
		a[method] = function(self, ...)
			assert(select("#", ...) == 0, "links must not supply arbitrary navigation arguments")
			self.opened[#self.opened + 1] = destination
			return true
		end
	end
	a.API.OpenKeyBindings = function()
		a.opened[#a.opened + 1] = "keybindings"
		return true
	end
	function a:SetOption()
		error("hint links must not change settings")
	end
	function a:SetOptions()
		error("hint links must not change settings")
	end
	function a:HandleSlashCommand()
		error("hint links must not run arbitrary commands")
	end
	return a
end

QT:RegisterTest("hint links open only whitelisted windows and settings without executing commands", function()
	local a = NavigationFixture()
	local expected = {
		settings = "settings:general",
		announcements = "settings:announcements",
		where_to_announce = "settings:whereToAnnounce",
		quest_plates = "settings:questPlates",
		player_plates = "settings:playerPlates",
		player_locations = "settings:playerLocations",
		groups = "settings:groups",
		accessibility = "settings:accessibility",
		profiles = "settings:profiles",
		developer = "settings:developer",
		experimental = "settings:experimental",
		party_log = "party_log",
		patch_notes = "patch_notes",
		support = "support",
		debug = "debug",
		hud_edit = "hud_edit",
		keybindings = "keybindings",
	}
	for actionID, destination in pairs(expected) do
		assert(a:ParseHintActionLink("questtogethertip:" .. actionID) == actionID)
		local count = #a.opened
		assert(a:HandleHintActionLink(actionID))
		assert(#a.opened == count + 1 and a.opened[#a.opened] == destination)
	end
	assert(a.db.global.hintPool == nil and #a.messages == 0, "opening UI must not draw or transmit another tip")
end)

QT:RegisterTest("hint links reject forged arguments and recheck navigation restrictions and capabilities", function()
	local a = NavigationFixture()
	local inaccessible = setmetatable({}, {
		__index = function()
			error("unreadable")
		end,
	})
	function a:CanAccessValue(value)
		return value ~= inaccessible
	end
	for _, payload in ipairs({
		"",
		"unknown",
		"SetOption",
		"settings:enabled:true",
		"settings|h",
		"../settings",
		"/qt lfg on",
		string.rep("s", 65),
		false,
		{},
		inaccessible,
	}) do
		assert(a:GetHintActionInfo(payload) == nil and not a:HandleHintActionLink(payload))
	end
	assert(a:GetHintActionInfo(nil) == nil and not a:HandleHintActionLink(nil))
	for _, link in ipairs({
		"questtogethertip:unknown",
		"questtogethertip:settings:extra",
		"questtogethertip:SETTINGS",
		" questtogethertip:settings",
		"questtogethertip:settings|h",
		"other:settings",
		inaccessible,
	}) do
		assert(a:ParseHintActionLink(link) == nil)
	end
	a.blocked = true
	assert(not a:HandleHintActionLink("settings"))
	a.blocked, a.isLoggingOut = false, true
	assert(not a:HandleHintActionLink("settings"))
	a.isLoggingOut, a.hasLoggedIn = false, false
	assert(not a:HandleHintActionLink("settings"))
	a.hasLoggedIn, a.capabilities.hud = true, false
	assert(a:GetHintActionInfo("hud_edit") == nil and not a:HandleHintActionLink("hud_edit"))
	assert(a:FormatHintEntry({ text = "Text", actions = { "hud_edit", "unknown" } }) == a:FormatHint("Text"))
	a.API.OpenKeyBindings = function()
		return false
	end
	assert(not a:HandleHintActionLink("keybindings"))
	a.API.OpenKeyBindings = function()
		error("native UI unavailable")
	end
	assert(not a:HandleHintActionLink("keybindings"))
	assert(#a.opened == 0)
	a.isEnabled = false
	assert(a:HandleHintActionLink("settings"), "navigation to settings remains available while QT is disabled")
end)

QT:RegisterTest("client locale renders actionable tip labels and tooltips together", function()
	local a = NavigationFixture()
	assert(a:ShowHint())
	local action = assert(a:GetHintActionInfo("settings"))
	assert(action.label == QT.Translate("Settings") and action.tooltip == QT.Translate("Click to open."))
	local hint = a:GetHintCatalog()[1]
	assert(
		a.messages[1]
			== a:FormatHint(hint.text) .. " |cffffd100|Hquesttogethertip:settings|h[" .. action.label .. "]|h|r"
	)
end, { locale = "client" })

QT:RegisterTest("hints share a persisted no-repeat pool across loads commands and refills", function()
	local global, ids, last = {}, {}, nil
	local first = Fixture(global)
	local count = 0
	for _, hint in ipairs(first:GetHintCatalog()) do
		if not hint.feature and not hint.menu then
			count = count + 1
		end
	end
	for index = 1, count * 2 do
		local a, clock = Fixture(global)
		a.pickLast = index % 2 == 0
		if index % 3 == 0 then
			a:OnLogin()
			assert(a.destinationReady and #a.messages == 0, "startup must wait until a later frame")
			clock:Advance(0)
		else
			a:HandleSlashCommand(index % 2 == 0 and " HINT " or "tip")
		end
		assert(#a.messages == 1 and #a.notices == 0)
		local id = global.hintPool.last
		assert(id ~= last, "refill must not immediately repeat the last tip")
		if index == count + 1 then
			ids = {}
		end
		assert(not ids[id], "tip repeated before the eligible pool was exhausted")
		ids[id], last = true, id
	end
end)

QT:RegisterTest("hints normalize saved IDs and admit newly available tips without discarding progress", function()
	local a = Fixture({ hintPool = { seen = { hint001 = true, hint002 = "bad", retired = true }, last = "retired" } })
	a:HandleSlashCommand("hint")
	assert(a.db.global.hintPool.seen.hint001 and not a.db.global.hintPool.seen.retired)
	assert(a.db.global.hintPool.last ~= "hint001")
	a.capabilities.menu = true
	a:HandleSlashCommand("tip")
	assert(a.db.global.hintPool.last == "hint002", "newly eligible tip must join the existing pool")
	assert(a.db.global.hintPool.seen.hint001)
	for _, corrupt in ipairs({ true, 7, "bad", { seen = false, last = {} } }) do
		a.db.global.hintPool = corrupt
		assert(a:ShowHint())
		assert(a.db.global.hintPool.last == "hint001")
	end
end)

QT:RegisterTest("startup hints survive deferred UI work without repeating on another login callback", function()
	local a, clock = Fixture()
	a.blocked = true
	a:OnLogin()
	a:OnLogin()
	clock:Advance(0)
	assert(#a.messages == 0)
	a:ResetRuntimeWorkStateStore()
	a.blocked = false
	a:FlushRuntimeUIWork("restrictions cleared")
	assert(#a.messages == 1)
	a:OnLogin()
	a.isEnabled = false
	a:Enable()
	assert(not a:ScheduleStartupHint())
	clock:Drain()
	assert(#a.messages == 1)
	a:HandleSlashCommand("hint")
	assert(#a.messages == 2 and a.messages[1] ~= a.messages[2])
end)

QT:RegisterTest("startup hints retry missing chat output with a bound and never consume failed draws", function()
	local unavailable, unavailableClock = Fixture()
	local delay = unavailable.API.Delay
	unavailable.API.Delay = nil
	assert(not unavailable:ScheduleStartupHint() and not rawget(unavailable, "startupHintState"))
	unavailable.API.Delay = delay
	assert(unavailable:ScheduleStartupHint())
	unavailableClock:Advance(0)
	assert(#unavailable.messages == 1, "failed admission must allow a later startup attempt")
	local a, clock = Fixture()
	a.failOutput = true
	a:OnLogin()
	clock:Drain()
	assert(a.outputAttempts == 3 and #a.messages == 0 and not a.db.global.hintPool)
	a:HandleSlashCommand("tip")
	assert(a.notices[1] == QT.Translate("Tips are unavailable right now.") and not a.db.global.hintPool)
	a.failOutput = false
	a:HandleSlashCommand("hint")
	assert(#a.messages == 1 and a.db.global.hintPool.last == "hint001")
	local b, secondClock = Fixture()
	b.failOutput = true
	b:OnLogin()
	secondClock:Advance(0)
	b.failOutput = false
	secondClock:Advance(2)
	assert(#b.messages == 1 and b.outputAttempts == 2)
end)

QT:RegisterTest("startup hints cannot print after logout disable or owner cancellation", function()
	for _, retire in ipairs({
		function(a)
			a.isLoggingOut = true
		end,
		function(a)
			a.isEnabled = false
		end,
		function(a)
			a:CancelRuntimeWorkOwner(a.startupHintState)
		end,
	}) do
		local a, clock = Fixture()
		a:OnLogin()
		retire(a)
		clock:Drain()
		assert(#a.messages == 0 and not a.db.global.hintPool)
	end
	local a, clock = Fixture()
	a.db.profile.enabled, a.isEnabled = false, false
	a:OnLogin()
	clock:Drain()
	assert(#a.messages == 0)
	a:HandleSlashCommand("tip")
	assert(#a.messages == 1, "manual help stays available when runtime features are disabled")
	a.blocked = true
	a:HandleSlashCommand("hint")
	assert(#a.messages == 2, "manual tips only print chat; combat must not block them")
end)

QT:RegisterTest("startup tip preference skips automatic draws while keeping manual tips available", function()
	local a, clock = Fixture()
	assert(a:GetOption("showStartupTips") == true, "new profiles should show startup tips by default")
	assert(a:SetOption("showStartupTips", false))
	a:OnLogin()
	clock:Drain()
	assert(#a.messages == 0 and a.outputAttempts == 0 and not a.db.global.hintPool)
	a:HandleSlashCommand("tip")
	a:HandleSlashCommand("hint")
	assert(#a.messages == 2 and a.db.global.hintPool, "manual commands must ignore the automatic preference")
	assert(a:SetOption("showStartupTips", true))
	clock:Drain()
	assert(#a.messages == 2, "turning startup tips on must wait for the next login or reload")
end)

QT:RegisterTest("deferred startup tips recheck the current preference and profile without consuming a draw", function()
	for _, optOut in ipairs({
		function(a)
			assert(a:SetOption("showStartupTips", false))
		end,
		function(a)
			a.db.profile = { enabled = true, showStartupTips = false }
		end,
	}) do
		local a, clock = Fixture()
		a:OnLogin()
		optOut(a)
		clock:Drain()
		assert(#a.messages == 0 and a.outputAttempts == 0 and not a.db.global.hintPool)
		assert(a:SetOption("showStartupTips", true))
		clock:Drain()
		assert(#a.messages == 0, "enabling tips must not revive a skipped startup callback")
		assert(a:ShowHint() and #a.messages == 1)
	end
	local a, clock = Fixture()
	a.failOutput = true
	a:OnLogin()
	clock:Advance(0)
	assert(a.outputAttempts == 1 and not a.db.global.hintPool)
	assert(a:SetOption("showStartupTips", false))
	a.failOutput = false
	clock:Drain()
	assert(a.outputAttempts == 1 and #a.messages == 0 and not a.db.global.hintPool)
end)

QT:RegisterTest("client locale renders hint prefix body command help and meta tip", function()
	local a = Fixture()
	local meta
	for _, hint in ipairs(a:GetHintCatalog()) do
		if hint.id == "hint167" then meta = hint end
	end
	assert(meta, "the catalog must include the tip-command hint")
	function a:GetHintCatalog() return { meta } end
	a:HandleSlashCommand("tip")
	local body = QT.Translate("Type /qt tip or /qt hint to see another QuestTogether tip whenever you like.")
	local icon = "|TInterface\\AddOns\\QuestTogether\\Media\\QuestTogetherTipIcon:14:14:0:0|t"
	assert(a.messages[1] == icon .. " |cffffd100" .. QT.Translate("Tip:") .. "|r |cfffff2cc" .. body .. "|r")
	local _, textures = a.messages[1]:gsub("|T", "")
	assert(textures == 1, "chat tips must contain exactly one bundled tip icon")
	assert(not a.messages[1]:find("💡", 1, true), "chat tips must not rely on Unicode symbols")
	assert(a.db.global.hintPool.last == "hint167")
	a:PrintHelp()
	local found = false
	for _, text in ipairs(a.notices) do
		if text == QT.Translate("/qt tip | hint - Show another QuestTogether tip") then
			found = true
		end
	end
	assert(found)
end, { locale = "client" })
