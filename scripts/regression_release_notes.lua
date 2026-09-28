-- Live-safe controller fixtures: no client globals, real frames or timers.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Notes(version)
	return {
		version = version,
		welcome = "Welcome to QuestTogether.",
		sections = {
			{ title = "Changes", items = { "Compare party quests." } },
		},
	}
end

local function Fixture(version, global)
	local addon = setmetatable({
		version = version or "5.9.2",
		db = { global = global or {}, profile = { enabled = true } },
		messages = {},
		presentations = {},
		eventsCreated = 0,
	}, { __index = QT })
	addon.releaseNotes = Notes(addon.version)
	local parent = {
		shown = true,
		IsForbidden = function(self)
			return self.forbidden == true
		end,
		IsShown = function(self)
			return self.shown
		end,
	}
	addon.parent = parent
	function addon:GetAddonVersion()
		return self.version
	end
	function addon:GetReleaseNotesUIParent()
		return parent
	end
	function addon:IsRuntimeRestricted()
		return self.blocked == true
	end
	function addon:ReconcileQuestLogChatDestination() end
	function addon:InitializeMinimapLauncher() end
	function addon:Enable()
		self.isEnabled = true
	end
	function addon:Print(message)
		self.messages[#self.messages + 1] = message
	end
	function addon:RenderReleaseNotesWindow(notes, shownVersion, firstUse)
		self.presentations[#self.presentations + 1] = { notes = notes, version = shownVersion, firstUse = firstUse }
		if self.renderThrows then
			error("fixture UI unavailable")
		end
		return self.renderResult ~= false
	end
	function addon:CreateReleaseNotesWakeFrame()
		self.eventsCreated = self.eventsCreated + 1
		return {
			scripts = {},
			events = {},
			IsForbidden = function()
				return false
			end,
			IsProtected = function()
				return false
			end,
			SetScript = function(self, name, callback)
				self.scripts[name] = callback
			end,
			RegisterEvent = function(self, event)
				self.events[event] = true
			end,
			UnregisterAllEvents = function(self)
				self.events = {}
			end,
		}
	end
	return addon
end

QT:RegisterTest("release notes first use is account wide and replaces the chat welcome", function()
	local a = Fixture()
	a:OnLogin()
	Equal(a.isEnabled, true)
	Equal(#a.messages, 0)
	Equal(#a.presentations, 1)
	Equal(a.presentations[1].firstUse, true)
	Equal(a.db.global.releaseNotesSeenVersion, "5.9.2")
	Equal(rawget(a, "pendingReleaseNotes"), nil)
	Equal(a.releaseNotesWakeFrame.scripts.OnUpdate, nil)
	Equal(next(a.releaseNotesWakeFrame.events), nil)
	a:OnLogin()
	Equal(#a.presentations, 1)
	local alt = Fixture("5.9.2", a.db.global)
	alt.db.profile.enabled = false
	alt:OnLogin()
	Equal(#alt.presentations, 0)
	Equal(alt.eventsCreated, 0)
	alt.db.profile = { enabled = true }
	alt:InitializeReleaseNotes()
	Equal(#alt.presentations, 0)
end)

QT:RegisterTest("release notes automatic version gate ignores patches prerelease promotions and downgrades", function()
	for _, item in ipairs({
		{ "", "5.9.2", true },
		{ "5.8.99", "5.9.0", true },
		{ "5.9.2", "5.10.0", true },
		{ "5.99.99", "6.0.0", true },
		{ "5.9.1", "5.9.2", false },
		{ "5.9.2", "5.9.1", false },
		{ "6.0.0", "5.10.0", false },
		{ "5.10.0", "5.9.9", false },
		{ "5.9.0-alpha.1", "5.9.0-beta.1", false },
		{ "5.9.0-beta.1", "5.9.0", false },
		{ "5.8.2", "5.9.0-beta.1", true },
		{ "legacy", "5.9.2", true },
		{ "5.8.0", "", false },
		{ "5.8.0", "5.9", false },
		{ "5.8.0", "5.9.0garbage", false },
	}) do
		local a = Fixture(item[2], { releaseNotesSeenVersion = item[1] })
		Equal(a:ShouldShowReleaseNotes(item[2]), item[3])
	end
end)

QT:RegisterTest("release notes aliases reopen silent patch releases and later minor upgrades still pop up", function()
	local a = Fixture("5.9.3", { releaseNotesSeenVersion = "5.9.2" })
	a.db.profile.enabled = false
	a:OnLogin()
	Equal(#a.presentations, 0)
	Equal(a.eventsCreated, 0)
	for _, command in ipairs({ "notes", "changelog", "  PATCHNOTES  " }) do
		assert(a:HandleSlashCommand(command))
		Equal(a.presentations[#a.presentations].version, "5.9.3")
		Equal(a.presentations[#a.presentations].firstUse, false)
	end
	Equal(#a.presentations, 3)
	Equal(a.db.global.releaseNotesSeenVersion, "5.9.3")
	a.version, a.releaseNotes = "5.10.0", Notes("5.10.0")
	assert(a:InitializeReleaseNotes())
	Equal(#a.presentations, 4)
	Equal(a.db.global.releaseNotesSeenVersion, "5.10.0")
	Equal(#a.messages, 0)
end)

QT:RegisterTest("release notes defer restrictions and hidden UI without marking the version seen", function()
	for _, condition in ipairs({ "restricted", "hidden", "forbidden" }) do
		local a = Fixture()
		a.db.profile.enabled = false
		if condition == "restricted" then
			a.blocked = true
		elseif condition == "hidden" then
			a.parent.shown = false
		else
			a.parent.forbidden = true
		end
		a:OnLogin()
		local frame = a.releaseNotesWakeFrame
		assert(frame.events.PLAYER_REGEN_ENABLED and frame.events.ADDON_RESTRICTION_STATE_CHANGED)
		frame.scripts.OnUpdate(frame, 1)
		Equal(#a.presentations, 0)
		Equal(a.db.global.releaseNotesSeenVersion, nil)
		a.blocked, a.parent.shown, a.parent.forbidden = false, true, false
		frame.scripts.OnUpdate(frame, 1)
		Equal(#a.presentations, 1)
		Equal(a.db.global.releaseNotesSeenVersion, "5.9.2")
		Equal(frame.scripts.OnUpdate, nil)
		Equal(next(frame.events), nil)
	end
end)

QT:RegisterTest("release notes failed rendering leaves startup active and does not poll failed builds", function()
	for _, failure in ipairs({ "throws", "not visible" }) do
		local a = Fixture()
		a.renderThrows, a.renderResult = failure == "throws", false
		a:OnLogin()
		Equal(a.isEnabled, true)
		Equal(#a.presentations, 1)
		Equal(a.db.global.releaseNotesSeenVersion, nil)
		Equal(a.releaseNotesWakeFrame.scripts.OnUpdate, nil)
		Equal(#a.messages, 0)
		a.renderThrows, a.renderResult = false, true
		a.releaseNotesWakeFrame.scripts.OnEvent()
		Equal(#a.presentations, 2)
		Equal(a.db.global.releaseNotesSeenVersion, "5.9.2")
	end
end)

QT:RegisterTest("release notes reject missing mismatched and invalid content without acknowledging it", function()
	for _, invalid in ipairs({ "missing", "mismatch", "empty", "version" }) do
		local a = Fixture()
		if invalid == "missing" then
			a.releaseNotes = nil
		elseif invalid == "mismatch" then
			a.releaseNotes.version = "5.8.0"
		elseif invalid == "empty" then
			a.releaseNotes.sections = {}
		else
			a.version = "not a version"
		end
		a:OnLogin()
		Equal(#a.presentations, 0)
		Equal(#a.messages, 0)
		Equal(a.eventsCreated, 0)
		Equal(a.db.global.releaseNotesSeenVersion, nil)
		Equal(a:OpenReleaseNotes(), false)
		Equal(#a.messages, 1)
	end
end)

QT:RegisterTest("release notes manual downgrade viewing never lowers the remembered release series", function()
	local a = Fixture("5.9.2", { releaseNotesSeenVersion = "6.0.0" })
	a:OnLogin()
	Equal(#a.presentations, 0)
	assert(a:OpenReleaseNotes())
	Equal(#a.presentations, 1)
	Equal(a.db.global.releaseNotesSeenVersion, "6.0.0")
	a.version, a.releaseNotes = "6.0.1", Notes("6.0.1")
	Equal(a:InitializeReleaseNotes(), false)
	Equal(#a.presentations, 1)
end)

QT:RegisterTest("release notes pending work cancels on logout or replacement content", function()
	for _, reason in ipairs({ "logout", "version", "seen" }) do
		local a = Fixture()
		a.blocked = true
		a:OnLogin()
		local frame = a.releaseNotesWakeFrame
		if reason == "logout" then
			a.isLoggingOut = true
		elseif reason == "version" then
			a.version, a.releaseNotes = "5.10.0", Notes("5.10.0")
		else
			a.db.global.releaseNotesSeenVersion = a.version
		end
		frame.scripts.OnEvent()
		Equal(rawget(a, "pendingReleaseNotes"), nil)
		Equal(frame.scripts.OnUpdate, nil)
		Equal(next(frame.events), nil)
		Equal(#a.presentations, 0)
	end
end)

QT:RegisterTest("Discord support uses the exact invite with a private copy window and guarded fallback", function()
	local a = Fixture()
	local urls = {}
	function a:RenderDiscordSupportLink(url)
		urls[#urls + 1] = url
		if self.copyThrows then
			error("copy window unavailable")
		end
		return self.copyResult ~= false
	end
	assert(a:OpenDiscordSupport())
	Equal(urls[1], "https://discord.gg/Uxyyvhfva9")
	Equal(#a.messages, 0)
	a.blocked = true
	Equal(a:OpenDiscordSupport(), false)
	Equal(#urls, 1)
	a.blocked, a.parent.forbidden = false, true
	Equal(a:OpenDiscordSupport(), false)
	Equal(#urls, 1)
	a.parent.forbidden, a.copyThrows = false, true
	Equal(a:OpenDiscordSupport(), false)
	assert(a.messages[1]:find("https://discord.gg/Uxyyvhfva9", 1, true))
end)
