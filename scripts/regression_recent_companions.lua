-- Private stores and owned frame fixtures; safe in the in-game runner.
local QT = _G.QuestTogether
local function Fixture(global)
	local a = setmetatable({ isEnabled = true, now = 1700000000, realm = "Home Realm", namespace = "1:US:realm",
		db = { global = global or {}, profile = {} }, partyMembers = {}, runtimeStateStore = {} }, { __index = QT })
	a.API = {
		GetPlayerNotesNamespace = function() return a.namespace end,
		GetRealmName = function() return a.realm end,
		GetServerTime = function() return a.now end,
		GetTime = function() return 100 end,
		RegionalUniqueNamesEnabled = function() return a.regional == true end,
		CreateContextMenu = function(owner, generate)
			local menu = { entries = {} }
			function menu:CreateTitle(text) self.title = text end
			function menu:CreateDivider() end
			function menu:CreateButton(text, run) self.entries[#self.entries + 1] = { text = text, run = run } end
			generate(owner, menu)
			a.menu = menu
			return true
		end,
	}
	function a:GetPlayerFullName() return self:GetPlayerNoteIdentity("Self") end
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:IsWorkBlocked() return self.blocked == true end
	function a:GetOption(key) return key == "windowScale" and 100 or false end
	for _, method in ipairs({ "Publish", "Emit", "Request", "Respond" }) do
		a[method] = function() error("private companion history must not use communications") end
	end
	function a:GetClassColorCode() return "|cffffffff" end
	function a:PopulateChatLogSpeakerMenu(menu, owner, name)
		self.menuName, self.menuOwner = name, owner
		menu:CreateButton("Shared player actions", function() end)
	end
	a.parent = QT:CreateTestUIRegion(a)
	a.parent:SetSize(1024, 768)
	function a:GetOwnedUIParent() return self.parent end
	function a:CreateOwnedWindowFrame(kind, _, parent, template)
		return self:ApplyTestUITemplate(self:CreateTestUIRegion(self, parent, kind), template)
	end
	function a:CreateOwnedUICleanupFrame() return self:CreateTestUIRegion({}) end
	return a
end

QT:RegisterTest("recent companions only remember actual group members and preserve full identities", function()
	local a = Fixture()
	a.partyMembers = {
		["Self-HomeRealm"] = { classFile = "MAGE" },
		["Alice-HomeRealm"] = { classFile = "PRIEST" },
		["Alice-OtherRealm"] = { classFile = "DRUID" },
		["|Hplayer:Bad|h"] = { classFile = "MAGE" },
	}
	a.playerLocationState = { peers = { ["Nearby-HomeRealm"] = {} } }
	assert(a:RecordRecentCompanions())
	local rows = a:GetRecentCompanions()
	assert(#rows == 2 and rows[1].name == "Alice-HomeRealm" and rows[2].name == "Alice-OtherRealm")
	assert(rows[1].classFile == "PRIEST" and rows[1].lastGrouped == a.now)
	rows[1].classFile = "WARRIOR"
	assert(a:GetRecentCompanions()[1].classFile == "PRIEST", "query leaked private mutable record")
	a.now = a.now + 60
	a.partyMembers = { ["Alice-HomeRealm"] = {} }
	a:RecordRecentCompanions()
	assert(a:GetRecentCompanions()[1].lastGrouped == a.now and a:GetRecentCompanions()[1].classFile == "PRIEST")
	a.isEnabled = false
	a.now = a.now + 60
	assert(not a:RecordRecentCompanions() and a:GetRecentCompanions()[1].lastGrouped == a.now - 60)
end)

QT:RegisterTest("recent companion history is account wide private and client realm scoped", function()
	local global, a = {}, nil
	a = Fixture(global)
	a.partyMembers["Alice-HomeRealm"] = { classFile = "PRIEST" }
	a:RecordRecentCompanions()
	local other = Fixture(global)
	other.db.profile = { copied = true }
	assert(#other:GetRecentCompanions() == 1)
	other.realm = "Other Realm"
	assert(#other:GetRecentCompanions() == 0)
	other.realm, other.namespace = a.realm, "2:US:realm"
	assert(#other:GetRecentCompanions() == 0)
	a.regional = true
	a.partyMembers = { ["Alice Windrunner"] = { classFile = "MAGE" } }
	a:RecordRecentCompanions()
	assert(a:GetRecentCompanions()[1].name == "Alice Windrunner")
end)

QT:RegisterTest("recent companion history bounds retention repairs corrupt entries and limits count", function()
	local a = Fixture()
	for index = 1, 105 do
		a.partyMembers = { ["Player" .. index .. "-HomeRealm"] = { classFile = "DRUID" } }
		a.now = a.now + 1
		a:RecordRecentCompanions()
	end
	local rows = a:GetRecentCompanions()
	assert(#rows == 100 and rows[1].name == "Player105-HomeRealm" and rows[100].name == "Player6-HomeRealm")
	local store = a.db.global.recentCompanions["1:US:realm:HomeRealm"]
	store["Corrupt-HomeRealm"] = false
	store["Future-HomeRealm"] = { lastGrouped = a.now + 3600 }
	store["Old-HomeRealm"] = { lastGrouped = a.now - 91 * 86400 }
	store["|bad"] = { lastGrouped = a.now }
	assert(#a:GetRecentCompanions() == 100 and not store["Corrupt-HomeRealm"] and not store["Future-HomeRealm"])
	a.now = a.now + 91 * 86400
	assert(#a:GetRecentCompanions() == 0 and next(store) == nil)
end)

QT:RegisterTest("removing recent companions keeps notes and survives current roster refresh", function()
	local a = Fixture()
	a.partyMembers = { ["Alice-HomeRealm"] = { classFile = "DRUID" } }
	a:RecordRecentCompanions()
	assert(a:SetPlayerNote("Alice", "Private memory"))
	assert(a:RemoveRecentCompanion("Alice"))
	a:RecordRecentCompanions()
	assert(#a:GetRecentCompanions() == 0 and a:GetPlayerNote("Alice") == "Private memory")
	a.partyMembers = {}
	a:RecordRecentCompanions()
	a.partyMembers = { ["Alice-HomeRealm"] = { classFile = "DRUID" } }
	a:RecordRecentCompanions()
	assert(#a:GetRecentCompanions() == 1)
	assert(a:ClearRecentCompanions())
	a:RecordRecentCompanions()
	assert(#a:GetRecentCompanions() == 0 and a:GetPlayerNote("Alice") == "Private memory")
end)

QT:RegisterTest("recent companions stamp only observed rosters across departure disable and logout", function()
	local a = Fixture()
	a.partyMembers = { ["Alice-HomeRealm"] = { classFile = "DRUID" } }
	assert(not a:RecordRecentCompanions(true), "a retained but unobserved roster must not become history")
	assert(a:RecordRecentCompanions())
	local first = a.now
	a.now = first + 10
	assert(a:RecordRecentCompanions(true))
	a:ResetRecentCompanionObservation()
	assert(a:GetRecentCompanions()[1].lastGrouped == first + 10)
	-- Disabled time and a re-enable pre-refresh cannot renew the old party.
	a.isEnabled, a.now = false, first + 100
	assert(not a:RecordRecentCompanions(true))
	a.isEnabled = true
	assert(not a:RecordRecentCompanions(true))
	a.partyMembers = {}
	assert(a:RecordRecentCompanions())
	assert(a:GetRecentCompanions()[1].lastGrouped == first + 10)
	-- Leaving the world records once; logout cannot stamp that roster again.
	a.partyMembers = { ["Bob-HomeRealm"] = { classFile = "MAGE" } }
	assert(a:RecordRecentCompanions())
	a.now = first + 120
	assert(a:RecordRecentCompanions(true))
	a:ResetRecentCompanionObservation()
	a.isLoggingOut, a.now = true, first + 180
	assert(not a:RecordRecentCompanions(true) and not a:RecordRecentCompanions())
	assert(a:GetRecentCompanions()[1].lastGrouped == first + 120)
end)

QT:RegisterTest("recent companion departure observations cannot cross roster or namespace identity", function()
	local a = Fixture()
	a.partyMembers = { ["Alice-HomeRealm"] = {} }
	a:RecordRecentCompanions()
	a.partyMembers = { ["Bob-HomeRealm"] = {} }
	a.now = a.now + 10
	assert(not a:RecordRecentCompanions(true))
	assert(#a:GetRecentCompanions() == 1)
	a:RecordRecentCompanions()
	a.realm = "Another Realm"
	assert(not a:RecordRecentCompanions(true))
	assert(#a:GetRecentCompanions() == 0)
end)

QT:RegisterTest("recent companion world lifecycle rebuilds real rosters without renewing departed players", function()
	local a = Fixture()
	a.units = {
		player = { name = "Self", classFile = "PRIEST" },
		party1 = { name = "Alice", classFile = "DRUID" },
	}
	a.API.UnitExists = function(unit) return a.units[unit] ~= nil end
	a.API.UnitFullName = function(unit)
		local member = a.units[unit]
		return member and member.name, member and "HomeRealm"
	end
	a.API.UnitClass = function(unit)
		local member = a.units[unit]
		return member and member.classFile, member and member.classFile
	end
	a.API.IsInRaid = function() return false end
	-- Group identity and the world event handlers remain real. Their unrelated
	-- communication/nameplate/quest work uses owned no-op adapters in this case.
	for _, method in ipairs({ "ResetPlayerPhases", "ResetObjectiveAnnouncements", "ResumeCommsWorldSession",
		"EndCommsWorldSession", "SetRuntimeFlag", "RefreshTaskAreaStates", "EnsureAnnouncementChannelJoined",
		"ScheduleAnnouncementChannelOrder", "BroadcastQTPlayerPresence", "BroadcastPlayerLocation",
		"FlushGeographicDeparture", "SavePlayerLocationCache" }) do
		a[method] = function() end
	end
	a:RefreshPartyRoster()
	assert(a.partyMembers["Alice-HomeRealm"] and #a:GetRecentCompanions() == 1)
	local started = a.now
	a.now = started + 10
	a:PLAYER_LEAVING_WORLD()
	assert(a.isLoggingOut and not a.recentCompanionObservation)
	assert(a:GetRecentCompanions()[1].lastGrouped == started + 10)
	-- The retained Lua roster still says Alice while the actual new world has Bob.
	a.units.party1 = { name = "Bob", classFile = "MAGE" }
	a.now = started + 100
	assert(a.partyMembers["Alice-HomeRealm"] and not a.partyMembers["Bob-HomeRealm"])
	a:PLAYER_ENTERING_WORLD()
	assert(not a.isLoggingOut and not a.partyMembers["Alice-HomeRealm"] and a.partyMembers["Bob-HomeRealm"])
	local entries = a:GetRecentCompanions()
	assert(#entries == 2 and entries[1].name == "Bob-HomeRealm" and entries[1].lastGrouped == started + 100)
	assert(entries[2].name == "Alice-HomeRealm" and entries[2].lastGrouped == started + 10)
	a.now = started + 110
	a:PLAYER_LEAVING_WORLD()
	a.now = started + 150
	a:PLAYER_LOGOUT()
	assert(a:GetRecentCompanions()[1].lastGrouped == started + 110, "logout renewed an already departed roster")
end)

QT:RegisterTest("recent companion private history never enters developer diagnostic snapshots", function()
	local sentinel = "CompanionPrivacySentinel-Realm"
	QT.API.GetPlayerNotesNamespace = function() return "companion-privacy-fixture" end
	QT.API.GetRealmName = function() return "Realm" end
	QT.API.GetServerTime = function() return 1700000000 end
	QT.GetPlayerFullName = function() return "Self-Realm" end
	QT.isEnabled, QT.isLoggingOut = true, false
	QT.partyMembers = { [sentinel] = { classFile = "PRIEST" } }
	assert(QT:RecordRecentCompanions())
	QT.partyMembers = {}
	assert(QT:GetRecentCompanions()[1].name == sentinel)
	local report = QT:BuildDeveloperDiagnosticSnapshot()
	assert(type(report) == "string" and #report > 0)
	assert(not report:find(sentinel, 1, true), "private group history leaked into a developer report")
	assert(not report:find("recentCompanions", 1, true))
end)

QT:RegisterTest("recent companions window has empty state scrolling shared actions and safe lifetime", function()
	local a = Fixture()
	assert(a:OpenRecentCompanions())
	local frame = a.recentCompanionsWindow
	assert(frame.empty:IsShown() and not frame.clear.enabled)
	for index = 1, 12 do a.partyMembers["Player" .. index .. "-HomeRealm"] = { classFile = "MAGE" } end
	a:RecordRecentCompanions()
	assert(not frame.empty:IsShown() and frame.clear.enabled and frame.rows[8].identity)
	frame.list:RunScript("OnMouseWheel", -1)
	assert(frame.offset == 3)
	local name = frame.rows[1].identity
	frame.rows[1]:Click()
	assert(a.menuName == name and a.menuOwner == frame.rows[1])
	local remove = a.menu.entries[#a.menu.entries].run
	a.parent:Hide()
	remove()
	assert(#a:GetRecentCompanions() == 12)
	a.parent:Show()
	assert(frame.session and frame:IsVisible())
	a:DismissRecentCompanions()
	assert(not frame.session and not frame:IsShown())
	a:OpenRecentCompanions()
	remove()
	assert(#a:GetRecentCompanions() == 12, "a dismissed menu altered a later window session")
	frame.rows[1]:Click()
	a.menu.entries[#a.menu.entries].run()
	assert(#a:GetRecentCompanions() == 11)
	a.blocked = true
	assert(not a:OpenRecentCompanions())
	frame.clear:Click()
	assert(#a:GetRecentCompanions() == 11 and (a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("recent companions UI stops before mutating a forbidden child", function()
	local a = Fixture()
	a:OpenRecentCompanions()
	a.recentCompanionsWindow.rows[1].name.forbidden = true
	assert(not a:RefreshRecentCompanionsWindow() and not a:OpenRecentCompanions())
	assert((a.invalidCalls or 0) == 0)
end)
