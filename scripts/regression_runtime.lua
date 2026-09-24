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
	assert(addon.state.entries["quest_log_drain::scan"] ~= nil)
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
	local addon = setmetatable({ API = {
		UnitExists = function() return true end,
		UnitGUID = function() return "Player-1-FRIEND" end,
		UnitFullName = function() return "Friend", "OtherRealm" end,
		GetRealmName = function() return "HomeRealm" end,
	} }, { __index = QT })
	function addon:IsNameplateUnitPlayer() return true end
	Equal(addon:DoesUnitTokenMatchSender("target", "Player-1-FRIEND", "Friend-OtherRealm"), true)
	Equal(addon:DoesUnitTokenMatchSender("target", "Player-1-FRIEND", "Friend-HomeRealm"), false)
end)

QT:RegisterTest("audit log entries are timestamped bounded and report dropped history", function()
	local addon = setmetatable(
		{
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
		},
		{ __index = QT }
	)
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
	local addon = setmetatable(
		{
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
		},
		{ __index = QT }
	)
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
