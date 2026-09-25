-- These fixtures call addon-owned methods only, both offline and in /qt test.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function NewRuntime()
	local addon = setmetatable({
		isEnabled = true,
		state = { entries = {}, generations = {} },
		delayed = {},
		errors = {},
		blocked = false,
	}, { __index = QT })
	addon.API = {
		Delay = function(_, fn)
			addon.delayed[#addon.delayed + 1] = fn
		end,
	}
	function addon:GetDeferredWorkStateStore()
		return self.state
	end
	function addon:IsWorkBlocked()
		return self.blocked
	end
	function addon:Debugf() end
	function addon:RecordDiagnosticError(context, err)
		self.errors[#self.errors + 1] = context
	end
	return addon
end

-- The console contract is exercised with private stores and a recording view;
-- these tests never construct a live frame or replace a Blizzard API.
local function NewDebugSession()
	local addon = setmetatable({
		isInitialized = true,
		isRunningTests = false,
		suppressLocalAnnouncementDisplayDuringTests = false,
		db = { global = { debugLogCategoryFilter = "ALL", debugLogSearchFilter = "" } },
		debugLogLines = {},
		debugLogStoreNormalized = true,
		debugLogTextLengthSum = 0,
		diagnosticLogSequence = 0,
		diagnosticDroppedLogLines = 0,
		API = {},
		tests = {},
		opened = {},
	}, { __index = QT })
	function addon:IsRuntimeRestricted()
		return false
	end
	local controller = addon:GetDebugController()
	function controller:Refresh() end
	function controller:ShowLog()
		addon.opened[#addon.opened + 1] = {
			text = self:GetText(),
			category = self:GetCategory(),
			search = self:GetSearch(),
		}
		return true
	end
	return addon
end

QT:RegisterTest("debug test command presents fresh results and preserves unrelated history", function()
	local addon = NewDebugSession()
	addon:LogDebugLine("keep domain event", { category = "QUEST" })
	addon:LogDebugLine("obsolete test result", { category = "TEST" })
	addon:SetDebugLogSearchFilter("hide all results")
	addon.tests = { { name = "private passing fixture", fn = function() end } }
	addon:HandleSlashCommand("test")
	Equal(#addon.opened, 1)
	Equal(addon.opened[1].category, "TEST")
	Equal(addon.opened[1].search, "")
	assert(addon.opened[1].text:find("1 passed, 0 failed", 1, true))
	local _, firstSummaryCount = addon.opened[1].text:gsub("Test summary:", "")
	Equal(firstSummaryCount, 1)
	assert(not addon:GetDebugLogText("ALL", ""):find("obsolete test result", 1, true))
	assert(addon:GetDebugLogText("QUEST", ""):find("keep domain event", 1, true))
	addon.tests = { {
		name = "private failing fixture",
		fn = function()
			error("fixture failure")
		end,
	} }
	Equal(addon:RunTests(false, true), false)
	Equal(#addon.opened, 2)
	assert(addon.opened[2].text:find("0 passed, 1 failed", 1, true))
	local _, secondSummaryCount = addon.opened[2].text:gsub("Test summary:", "")
	Equal(secondSummaryCount, 1)
	assert(addon.opened[2].text:find("private failing fixture", 1, true))
	assert(not addon.opened[2].text:find("1 passed, 0 failed", 1, true))
	Equal(addon.isRunningTests, false)
	Equal(addon.suppressLocalAnnouncementDisplayDuringTests, false)
end)

QT:RegisterTest("debug test presentation preserves a visible ALL view but clears its search", function()
	local addon = NewDebugSession()
	addon:GetDebugController().window = {
		IsForbidden = function()
			return false
		end,
		IsProtected = function()
			return false
		end,
		IsShown = function()
			return true
		end,
	}
	addon:LogDebugLine("domain event", { category = "QUEST" })
	addon:SetDebugLogSearchFilter("obsolete search")
	addon.tests = { { name = "private fixture", fn = function() end } }
	Equal(addon:RunTests(false, true), true)
	Equal(addon.opened[1].category, "ALL")
	Equal(addon.opened[1].search, "")
	assert(addon.opened[1].text:find("domain event", 1, true))
	assert(addon.opened[1].text:find("1 passed, 0 failed", 1, true))
end)

QT:RegisterTest("debug slash aliases display selected category and clear resets the view", function()
	local addon = NewDebugSession()
	addon:LogDebugLine("quest event", { category = "QUEST" })
	addon:LogDebugLine("comms event", { category = "COMMS" })
	addon:HandleSlashCommand("dump quest")
	Equal(addon.opened[1].category, "QUEST")
	assert(not addon.opened[1].text:find("comms event", 1, true))
	addon:HandleSlashCommand("debug ALL")
	Equal(addon.opened[2].category, "ALL")
	assert(addon.opened[2].text:find("comms event", 1, true))
	addon:SetDebugLogSearchFilter("quest")
	addon:HandleSlashCommand("debuglog clear")
	Equal(addon.opened[3].category, "ALL")
	Equal(addon.opened[3].search, "")
	Equal(addon.opened[3].text, "")
end)

QT:RegisterTest("headless debug tests leave visible history and filters untouched", function()
	local addon = NewDebugSession()
	function addon:Print() end
	addon:LogDebugLine("keep history", { category = "QUEST" })
	addon:SetDebugLogCategoryFilter("QUEST")
	addon:SetDebugLogSearchFilter("history")
	local log, sequence = addon:GetDebugLogText("ALL", ""), addon.diagnosticLogSequence
	addon.tests = { { name = "headless fixture", fn = function() end } }
	local success, passed, failed, result = addon:RunTests()
	Equal(success, true)
	Equal(passed, 1)
	Equal(failed, 0)
	Equal(result.total, 1)
	Equal(#addon.opened, 0)
	Equal(addon:GetDebugLogText("ALL", ""), log)
	Equal(addon.diagnosticLogSequence, sequence)
	Equal(addon:GetDebugLogCategoryFilter(), "QUEST")
	Equal(addon:GetDebugLogSearchFilter(), "history")
end)

QT:RegisterTest("diagnostic slash aliases rebuild the current domain report in the shared view", function()
	local addon = NewDebugSession()
	local reports, calls = {}, 0
	function addon:BuildDiagnosticReport(questId)
		calls = calls + 1
		return "fixture.quest=" .. questId .. "\nfixture.generation=" .. calls
	end
	local controller = addon:GetDebugController()
	function controller:ShowReport(text)
		reports[#reports + 1] = text
		return true
	end
	addon:LogDebugLine("recent fixture event", { category = "QUEST" })
	addon:HandleSlashCommand("diag 42")
	addon:HandleSlashCommand("diagnostics 43")
	Equal(#reports, 2)
	assert(reports[1]:find("fixture.quest=42", 1, true))
	assert(reports[2]:find("fixture.quest=43", 1, true))
	assert(reports[2]:find("fixture.generation=2", 1, true))
	assert(reports[2]:find("recent fixture event", 1, true))
end)

QT:RegisterTest("QT isolation detaches and restores the debug controller after a failing case", function()
	local controller = QT:GetDebugController()
	QT:LogDebugLine("outer private fixture history", { category = "QUEST" })
	local entries = QT:GetDebugLogStore()
	local originalText = QT:GetDebugLogText("ALL", "")
	local ok = pcall(QT:GetDebugTestOptions().run, function()
		assert(QT:GetDebugController() ~= controller)
		assert(QT:GetDebugLogStore() ~= entries)
		QT:LogDebugLine("inner private fixture history", { category = "TEST" })
		error("intentional private fixture failure")
	end)
	Equal(ok, false)
	Equal(QT:GetDebugController(), controller)
	Equal(QT:GetDebugLogStore(), entries)
	Equal(QT:GetDebugLogText("ALL", ""), originalText)
end)

QT:RegisterTest("audit reset invalidates scheduled callbacks even after reenable", function()
	local addon, calls = NewRuntime(), 0
	addon:ScheduleDeferredWork("nameplate_refresh", "plate", function()
		calls = calls + 1
	end, 1)
	addon.state = { entries = {}, generations = {} }
	addon.delayed[1]()
	Equal(calls, 0)
end)

QT:RegisterTest("audit immediate work replaces parked work with the same key", function()
	local addon, old, fresh = NewRuntime(), 0, 0
	addon.blocked = true
	addon:RunOrDeferWork("nameplate_refresh", "plate", function()
		old = old + 1
	end)
	addon.blocked = false
	addon:RunOrDeferWork("nameplate_refresh", "plate", function()
		fresh = fresh + 1
	end)
	addon:FlushDeferredWork()
	Equal(old, 0)
	Equal(fresh, 1)
end)

QT:RegisterTest("shared runtime permits explicit waypoint clicks while disabled but parks background work", function()
	local addon, waypointCalls, backgroundCalls = NewRuntime(), 0, 0
	addon.isEnabled = false
	Equal(
		addon:RunOrDeferWork("waypoint_mutation", "user_waypoint", function()
			waypointCalls = waypointCalls + 1
		end),
		true
	)
	Equal(
		addon:RunOrDeferWork("quest_snapshot_refresh", "snapshot", function()
			backgroundCalls = backgroundCalls + 1
		end),
		false
	)
	Equal(waypointCalls, 1)
	Equal(backgroundCalls, 0)
	Equal(addon:FlushDeferredWork(), false)
	addon.isEnabled = true
	addon:FlushDeferredWork()
	Equal(backgroundCalls, 1)
end)

QT:RegisterTest("shared runtime disabled waypoint exception does not bypass restrictions", function()
	local addon, calls = NewRuntime(), 0
	addon.isEnabled, addon.blocked = false, true
	Equal(
		addon:RunOrDeferWork("waypoint_mutation", "user_waypoint", function()
			calls = calls + 1
		end),
		false
	)
	Equal(calls, 0)
	addon.isEnabled = true
	addon:FlushDeferredWork()
	Equal(calls, 0)
	addon.blocked = false
	addon:FlushDeferredWork()
	Equal(calls, 1)
end)

QT:RegisterTest("shared runtime immediate waypoint consumes an older timer while disabled", function()
	local addon, calls = NewRuntime(), 0
	addon:ScheduleDeferredWork("waypoint_mutation", "user_waypoint", function()
		calls = calls + 100
	end, 1)
	addon.isEnabled = false
	addon:RunOrDeferWork("waypoint_mutation", "user_waypoint", function()
		calls = calls + 1
	end)
	addon.isEnabled = true
	addon.delayed[1]()
	Equal(calls, 1)
end)

QT:RegisterTest("shared runtime tolerates unavailable timer adapter", function()
	local addon, calls = NewRuntime(), 0
	addon.API.Delay = false
	addon:ScheduleDeferredWork("quest_log_drain", "scan", function()
		calls = calls + 1
	end, 1)
	Equal(calls, 1)
end)

QT:RegisterTest("audit flush does not resurrect entries consumed by another callback", function()
	local addon, stale, replacement = NewRuntime(), 0, 0
	addon.blocked = true
	addon:ScheduleDeferredWork("nameplate_refresh", "a", function() end)
	addon:ScheduleDeferredWork("nameplate_refresh", "b", function() end)
	local firstKey = next(addon.state.entries)
	local secondKey = next(addon.state.entries, firstKey)
	local first, second = addon.state.entries[firstKey], addon.state.entries[secondKey]
	first.callback = function()
		addon:ScheduleDeferredWork(second.workClass, second.key, function()
			replacement = replacement + 1
		end, 0)
	end
	second.callback = function()
		stale = stale + 1
	end
	addon.blocked = false
	addon:FlushDeferredWork()
	Equal(stale, 0)
	Equal(replacement, 1)
end)

QT:RegisterTest("audit deferred failure records error and does not discard other work", function()
	local addon, calls = NewRuntime(), 0
	addon.blocked = true
	addon:ScheduleDeferredWork("nameplate_refresh", "bad", function()
		error("fixture failure")
	end)
	addon:ScheduleDeferredWork("nameplate_refresh", "good", function()
		calls = calls + 1
	end)
	addon.blocked = false
	addon:FlushDeferredWork()
	Equal(calls, 1)
	Equal(#addon.errors, 1)
	Equal(next(addon.state.entries), nil)
end)

QT:RegisterTest("audit finished deferred keys do not accumulate generation state", function()
	local addon = NewRuntime()
	for i = 1, 200 do
		addon:ScheduleDeferredWork("nameplate_refresh", "guid" .. i, function() end, 0)
	end
	Equal(next(addon.state.entries), nil)
	Equal(next(addon.state.generations), nil)
end)

QT:RegisterTest("audit flush honors restrictions separately for each work class", function()
	local addon, calls = NewRuntime(), 0
	function addon:IsWorkBlocked(work)
		return work == "quest_log_drain"
	end
	addon:ScheduleDeferredWork("quest_log_drain", "scan", function()
		error("must stay parked")
	end)
	addon:ScheduleDeferredWork("nameplate_refresh", "plate", function()
		calls = calls + 1
	end, 1)
	addon:FlushDeferredWork()
	Equal(calls, 1)
	assert(addon.state.entries[QT.LibChev.WorkKey("quest_log_drain", "scan")] ~= nil)
end)

QT:RegisterTest("audit inaccessible frame methods fail closed", function()
	local frame = setmetatable({}, {
		__index = function()
			error("inaccessible")
		end,
	})
	Equal(QT:CanAccessForeignFrame(frame), false)
	Equal(QT:IsProtectedFrame(frame), true)
	Equal(
		QT:CanAccessForeignFrame({
			IsForbidden = function()
				error("blocked")
			end,
		}),
		false
	)
end)

QT:RegisterTest("audit inaccessible visibility result is not treated as shown", function()
	local addon = setmetatable({}, { __index = QT })
	Equal(
		addon:CanAccessForeignFrame({
			IsShown = function()
				error("inaccessible")
			end,
		}, true),
		false
	)
end)

QT:RegisterTest("audit same character name on another realm is not the local sender", function()
	local addon = setmetatable({}, { __index = QT })
	function addon:GetPlayerFullName()
		return "MyPlayer-HomeRealm"
	end
	Equal(addon:IsSelfSender("MyPlayer-OtherRealm"), false)
	Equal(addon:IsSelfSender("MyPlayer-HomeRealm"), true)
end)

QT:RegisterTest("audit nearby unit identity retains the remote realm return", function()
	local addon = setmetatable({
		API = {
			UnitExists = function()
				return true
			end,
			UnitGUID = function()
				return "Player-1-FRIEND"
			end,
			UnitFullName = function()
				return "Friend", "OtherRealm"
			end,
			GetRealmName = function()
				return "HomeRealm"
			end,
		},
	}, { __index = QT })
	function addon:IsNameplateUnitPlayer()
		return true
	end
	Equal(addon:DoesUnitTokenMatchSender("target", "Player-1-FRIEND", "Friend-OtherRealm"), true)
	Equal(addon:DoesUnitTokenMatchSender("target", "Player-1-FRIEND", "Friend-HomeRealm"), false)
end)

QT:RegisterTest("audit log entries are timestamped bounded and report dropped history", function()
	local addon = setmetatable({
		logs = {},
		DEBUG_LOG_MAX_LINES = 3,
		DEBUG_LOG_MAX_CHARS = 20000,
		diagnosticLogSequence = 0,
		diagnosticDroppedLogLines = 0,
		debugLogTextLengthSum = 0,
		API = {
			GetTime = function()
				return 123.5
			end,
		},
	}, { __index = QT })
	function addon:GetDebugLogStore()
		return self.logs
	end
	function addon:RequestDebugLogWindowRefresh() end
	for i = 1, 5 do
		addon:LogDebugLine("event" .. i, { category = "QUEST" })
	end
	Equal(#addon.logs, 3)
	Equal(addon.diagnosticDroppedLogLines, 2)
	Equal(addon.logs[1].sequence, 3)
	assert(addon:GetDebugLogEntryDisplayText(addon.logs[1]):find("123.500", 1, true))
	addon:LogDebugLine(string.rep("x", 10000))
	assert(#addon.logs[3].text < 4200)
end)

QT:RegisterTest("audit diagnostic report uses cached quest state without live quest reads", function()
	local addon = setmetatable({
		runtime = {
			questSnapshot = { byQuestID = {}, generation = 7 },
			taskArea = {},
			nameplate = {},
			runtime = { deferredWorkState = { entries = {} } },
		},
		API = {
			GetQuestLogInfo = function()
				error("must not read live quests")
			end,
		},
	}, { __index = QT })
	function addon:GetDiagnosticEnvironment()
		return { version = "1.60.1", build = "69977", interface = "16001", locale = "enUS" }
	end
	function addon:GetAddonVersion()
		return "audit"
	end
	function addon:EnsureRuntimeStateStore()
		return self.runtime
	end
	function addon:IsRuntimeRestricted()
		return true
	end
	function addon:IsMapTooltipSensitiveStateActive()
		return true
	end
	function addon:IsRuntimeRestrictionTypeActive()
		return true
	end
	function addon:GetOption()
		return false
	end
	function addon:GetPlayerTracker()
		return { [12] = { title = "Photo Quest", objectives = { "80% Photos" }, objectiveValues = { 80 } } }
	end
	function addon:GetCommsDiagnostics()
		return {}
	end
	function addon:GetDebugLogStore()
		return {}
	end
	local report = addon:BuildDiagnosticReport(12)
	assert(report:find("build=69977", 1, true))
	assert(report:find("objective.1=80% Photos", 1, true))
	assert(report:find("addon=QuestTogether", 1, true))
	assert(report:find("client.interface=16001", 1, true))
end)

QT:RegisterTest("shared diagnostic window export retains newest events within its copy budget", function()
	local addon = setmetatable({ entries = {} }, { __index = QT })
	function addon:GetDebugLogStore()
		return self.entries
	end
	function addon:BuildDiagnosticReport()
		return "addon=QuestTogether\nfixture=true"
	end
	for index = 1, 600 do
		addon.entries[index] = { category = "TEST", text = "event-" .. index .. ":" .. string.rep("x", 100) }
	end
	local exported = addon:BuildDiagnosticExport()
	assert(#exported <= 32768)
	assert(exported:find("event-600:", 1, true))
	assert(not exported:find("event-1:", 1, true))
	assert(exported:find("event-599:", 1, true) < exported:find("event-600:", 1, true))
end)

QT:RegisterTest("audit guarded callback records failures without replacing global handlers", function()
	local addon = NewRuntime()
	local ok = addon:RunGuardedCallback("fixture", function(value)
		Equal(value, 42)
		error("expected")
	end, 42)
	Equal(ok, false)
	Equal(addon.errors[1], "fixture")
end)

QT:RegisterTest("welcome login keeps startup active announces once and routes addon feedback", function()
	local addon = setmetatable({ addonName = "QuestTogether", db = { profile = { enabled = true } } }, { __index = QT })
	local messages, handler = {}, nil
	function addon:Print(text)
		messages[#messages + 1] = text
	end
	function addon:GetAddonVersion()
		return "fixture-version"
	end
	function addon:ReconcileQuestLogChatDestination() end
	function addon:Enable()
		self.isEnabled = true
	end
	function addon:GetWelcomeUIPolicy()
		return {
			restricted = function()
				return true
			end,
		}
	end
	function addon:RegisterWelcomeLink(kind, callback)
		Equal(kind, "questtogetherfeedback")
		handler = callback
		return true
	end
	addon:OnLogin()
	addon:OnLogin()
	Equal(addon.hasLoggedIn, true)
	Equal(addon.isEnabled, true)
	Equal(#messages, 1)
	assert(messages[1]:find("vfixture-version loaded!", 1, true))
	assert(messages[1]:find("Type /qt for settings.", 1, true))
	handler("questtogetherfeedback:curseforge")
	Equal(messages[2], "Feedback: https://www.curseforge.com/wow/addons/questtogether")
	handler("questtogetherfeedback:github")
	Equal(messages[3], "Feedback: https://github.com/AlexAllocated/QuestTogether")
	function addon:GetWelcomeController()
		error("welcome unavailable")
	end
	addon:OnLogin()
	Equal(addon.isEnabled, true)
	Equal(#messages, 3)
end)
