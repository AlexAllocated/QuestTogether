-- Private clients, chat sinks and clocks. No native UI or global API replacement.
local QT = _G.QuestTogether
local function Fixture(global)
	local a = setmetatable({
		hasLoggedIn = true,
		isEnabled = true,
		isLoggingOut = false,
		db = { global = global or {}, profile = { enabled = true } },
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

QT:RegisterTest("hints gate optional features and retain remote information and ordinary controls", function()
	local a = Fixture()
	local eligible, byID = {}, {}
	for _, hint in ipairs(a:GetHintCatalog()) do
		assert(not byID[hint.id], "stable hint IDs must be unique")
		assert(not hint.text:find("💡", 1, true), "prefix belongs to presentation")
		byID[hint.id] = hint
		if not hint.feature and not hint.menu then
			eligible[hint.id] = true
		end
	end
	for _ in pairs(eligible) do
		assert(a:ShowHint() and eligible[a.db.global.hintPool.last])
	end
	assert(eligible.hint009 and eligible.hint014 and eligible.hint147 and eligible.hint150 and eligible.hint151)
	assert(not eligible.hint134 and not eligible.hint161 and not eligible.hint162 and not eligible.hint163)
	-- Enabling a capability makes that topic available without resetting common draws.
	a.capabilities.details, a.capabilities.menu = true, true
	for _, hint in pairs(byID) do
		if not hint.feature then
			a.db.global.hintPool.seen[hint.id] = true
		end
	end
	assert(a:ShowHint() and a.db.global.hintPool.last == "hint134")
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

QT:RegisterTest("client locale renders hint prefix body command help and meta tip", function()
	local a = Fixture()
	a.pickLast = true
	a:HandleSlashCommand("tip")
	local body = QT.Translate("Type /qt tip or /qt hint to see another QuestTogether tip whenever you like.")
	assert(a.messages[1] == "💡 " .. QT.Translate("Tip:") .. " " .. body)
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
