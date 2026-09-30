-- Private-fixture regressions for quest snapshots, observation lifetimes, and
-- waypoint work. No Blizzard globals or shared UI/API tables are replaced.
local QT = _G.QuestTogether
local function Equal(actual, expected, message)
	assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function Noop() end

local function NewFixture()
	local addon = setmetatable({
		runtimeStateStore = {},
		tracker = {},
		rows = { { questID = 12345, questLogIndex = 1, title = "Photo Quest" } },
		snapshot = { byQuestID = {}, order = {}, generation = 0 },
		runtime = { deferredWorkState = { entries = {}, generations = {} } },
		retiredQuestIds = {},
		pendingQuestRemovals = {},
		pendingQuestAcceptances = {},
		questsCompleted = {},
		onQuestLogUpdate = {},
		delayed = {},
		liveReady = false,
		liveComplete = false,
		liveValue = 80,
		db = { profile = {}, global = {} },
		isEnabled = true,
		hasLoggedIn = true,
		blocked = false,
	}, { __index = QT })
	addon.API = {
		GetNumQuestLogEntries = function()
			if addon.unreadableCount then
				return nil
			end
			return #addon.rows
		end,
		GetQuestLogInfo = function(index)
			return addon.rows[index]
		end,
		IsWorldQuest = function()
			return false
		end,
		GetQuestLogIndexForQuestID = function(questId)
			for index, row in ipairs(addon.rows) do
				if row.questID == questId then
					return index
				end
			end
		end,
		GetNumQuestLeaderBoards = function()
			return 1
		end,
		IsQuestReadyForTurnIn = function()
			return addon.liveReady
		end,
		IsQuestComplete = function()
			return addon.liveComplete
		end,
		IsQuestFlaggedCompleted = function()
			return false
		end,
		IsOnQuest = function()
			return true
		end,
		RegisterAddonPrefix = Noop,
		Delay = function(_, callback)
			addon.delayed[#addon.delayed + 1] = callback
		end,
	}
	function addon:GetPlayerTracker()
		return self.tracker
	end
	function addon:GetQuestSnapshotStateStore()
		return self.snapshot
	end
	function addon:GetQuestSnapshotByQuestID()
		return self.snapshot.byQuestID
	end
	function addon:GetQuestSnapshotOrder()
		return self.snapshot.order
	end
	function addon:GetQuestSnapshot(questId)
		return self.snapshot.byQuestID[questId]
	end
	function addon:EnsureQuestSnapshotStore()
		return self.snapshot
	end
	function addon:IsWorkBlocked()
		return self.blocked
	end
	function addon:GetQuestTitle(_, info)
		return info and info.title or "Photo Quest"
	end
	function addon:GetTaskAnnouncementType()
		return nil
	end
	function addon:GetNormalizedQuestObjectiveInfo()
		return self.liveValue .. "% Locations Photographed", "progressbar", false, self.liveValue
	end
	function addon:GetActiveWorldQuestAreaSnapshot()
		return {}
	end
	function addon:GetActiveBonusObjectiveAreaSnapshot()
		return {}
	end
	function addon:GetRuntimeWorkStateStore()
		return self.runtime
	end
	function addon:GetDeferredWorkStateStore()
		return self.runtime.deferredWorkState
	end
	function addon:ResetRuntimeWorkStateStore()
		self.runtime = { deferredWorkState = { entries = {}, generations = {} } }
	end
	addon.Debug = Noop
	addon.Debugf = Noop
	addon.PrintConsoleAnnouncement = Noop
	addon.BuildLocalAnnouncementEvent = function()
		return nil
	end
	addon.RegisterRuntimeEvents = Noop
	addon.ResetTaskAreaStateStore = Noop
	addon.RefreshTaskAreaStates = Noop
	addon.EnsureAnnouncementChannelJoined = Noop
	addon.EnableNameplateAugmentation = Noop
	addon.TryInstallPersonalBubbleEditModeHooks = Noop
	addon.RefreshPersonalBubbleAnchorVisualState = Noop
	addon.RefreshPartyRoster = Noop
	return addon
end

local function SeedSnapshot(addon)
	local quest = { questID = 99999, questLogIndex = 1, title = "Previously Known Quest" }
	addon.snapshot.byQuestID[99999] = quest
	addon.snapshot.order[1] = 99999
	addon.snapshot.generation = 7
	return quest
end

local function NewTaskClassificationFixture()
	local clock = QT:CreateTestClock(100)
	local addon = setmetatable({
		runtimeStateStore = {}, db = { global = {}, profile = {} },
		isEnabled = true, questsCompleted = {}, retiredQuestIds = {}, announcements = {},
		worldQuestAreaStateByQuestID = {}, bonusObjectiveAreaStateByQuestID = {},
		questSnapshotByQuestID = {}, questSnapshotOrder = {},
		row = { questID = 12345, questLogIndex = 1, title = "Bonus Area", isTask = true, isOnMap = true, hasLocalPOI = false },
		taskInfo = { displayAsObjective = true },
		worldClassification = false, tracker = {},
		IsWorkBlocked = function() return false end,
		RefreshNameplatesForQuestStateChange = Noop,
		Debug = Noop, Debugf = Noop,
	}, { __index = QT })
	addon.API = {
		Delay = function(delay, callback) clock:After(delay, callback) end,
		GetTime = function() return clock:GetTime() end,
		GetNumQuestLogEntries = function() return addon.row and 1 or 0 end,
		GetQuestLogInfo = function() return addon.row end,
		IsWorldQuest = function()
			if addon.worldReadQueue and #addon.worldReadQueue > 0 then
				local observation = table.remove(addon.worldReadQueue, 1)
				if observation == "unknown" then return nil end
				return observation
			end
			return addon.worldClassification
		end,
		GetTaskQuestInfoByQuestID = function()
			if addon.taskInfoReadQueue and #addon.taskInfoReadQueue > 0 then
				local observation = table.remove(addon.taskInfoReadQueue, 1)
				return observation or nil -- false is a queued unavailable read.
			end
			return addon.taskInfo
		end,
	}
	function addon:PublishAnnouncementEvent(event)
		self.announcements[#self.announcements + 1] = event
	end
	function addon:GetPlayerTracker() return self.tracker end
	function addon:ObserveTaskAreaChange()
		self:ScheduleQuestStateRefreshWork("QUEST_LOG_UPDATE", 1)
		clock:Advance(1)
		self:QUEST_POI_UPDATE()
		clock:Drain()
	end
	addon:EnsureRuntimeStateStore()
	return addon
end

QT:RegisterTest("unavailable bonus metadata preserves confirmed area through real scheduled refreshes", function()
	local addon = NewTaskClassificationFixture()
	addon:RebuildQuestSnapshotStore()
	Equal(addon:RefreshTaskAreaStates(false), true)
	for _, shape in ipairs({ "missing_record", "missing_flag", "invalid_flag" }) do
		if shape == "missing_record" then addon.taskInfo = nil
		elseif shape == "missing_flag" then addon.taskInfo = { questTitle = "Bonus Area" }
		else addon.taskInfo = { displayAsObjective = "unknown" } end
		addon:ObserveTaskAreaChange()
		Equal(addon:GetTaskAreaStateStore("bonus")[12345], "Bonus Area", shape)
		Equal(#addon.announcements, 0, "unavailable metadata must not invent an exit")
	end
	addon.taskInfo = { displayAsObjective = true }
	addon:ObserveTaskAreaChange()
	Equal(#addon.announcements, 0, "metadata recovery must not replay area entry")
	addon.row.isOnMap = false
	addon:ObserveTaskAreaChange()
	Equal(addon.announcements[1], "BONUS_OBJECTIVE_LEFT", "a real area exit must still publish")
end)

QT:RegisterTest("bonus classification distinguishes unknown from explicit false across both readers", function()
	local addon = NewTaskClassificationFixture()
	addon.taskInfo = nil
	addon:RebuildQuestSnapshotStore()
	Equal(addon:GetQuestSnapshot(12345).displayAsObjective, nil, "unknown classification must remain unknown")
	addon.taskInfo = { displayAsObjective = true }
	addon:RefreshTaskAreaStates(false)
	Equal(addon:GetTaskAreaStateStore("bonus")[12345], "Bonus Area")
	addon.taskInfo = nil
	addon:ObserveTaskAreaChange()
	Equal(addon:GetTaskAreaStateStore("bonus")[12345], "Bonus Area", "retain a classification first observed by the area reader")
	Equal(#addon.announcements, 0)
	addon.taskInfo = { displayAsObjective = false }
	addon:ObserveTaskAreaChange()
	Equal(addon:GetTaskAreaStateStore("bonus")[12345], nil, "explicit false must clear prior classification")
	Equal(addon:GetQuestSnapshot(12345).isBonusObjective, false)
	Equal(addon.announcements[1], "BONUS_OBJECTIVE_LEFT")
	addon.taskInfo = nil
	addon:ObserveTaskAreaChange()
	Equal(#addon.announcements, 1, "unknown after explicit false must not restore the old positive")
	addon.row = nil
	addon:ObserveTaskAreaChange()
	Equal(addon:GetTaskAreaResolution(12345), nil, "confirmed quest removal retires classification history")
end)

QT:RegisterTest("independent task classification readers retain the newest confirmed value in either order", function()
	for _, original in ipairs({ true, false }) do
		for _, reader in ipairs({ "snapshot", "resolver" }) do
			local addon = NewTaskClassificationFixture()
			addon.taskInfo = { displayAsObjective = original }
			addon:RebuildQuestSnapshotStore()
			addon:RefreshTaskAreaStates(false)
			Equal(addon:GetTaskAreaResolution(12345).displayAsObjective, original)

			local updated = { displayAsObjective = not original }
			-- These are independent API observations in the same scheduled refresh.
			-- Either reader can see the transition while the other is unavailable.
			addon.taskInfo = nil
			addon.taskInfoReadQueue = reader == "snapshot" and { updated, false } or { false, updated }
			addon:ObserveTaskAreaChange()
			Equal(#addon.taskInfoReadQueue, 0, "both real readers must consume their independent observation")
			Equal(addon:GetTaskAreaResolution(12345).displayAsObjective, not original, reader)
			Equal(addon:IsBonusObjective(12345), not original, "public classification must use the latest confirmed value")
			Equal(addon:GetTaskAnnouncementType(12345), not original and "bonus" or nil,
				"announcements must use the latest confirmed classification")
			Equal(addon:GetTaskAreaStateStore("bonus")[12345] ~= nil, not original, reader)
			Equal(#addon.announcements, 1, "a confirmed classification transition publishes exactly once")
			Equal(addon.announcements[1], original and "BONUS_OBJECTIVE_LEFT" or "BONUS_OBJECTIVE_ENTERED")

			addon:ObserveTaskAreaChange()
			Equal(addon:GetTaskAreaResolution(12345).displayAsObjective, not original,
				"unavailable reads must retain the newest observation, whichever reader observed it")
			Equal(#addon.announcements, 1, "older reader state must not replay the opposite transition")
		end
	end
end)

QT:RegisterTest("confirmed task removal does not lend its classification to a returning unreadable row", function()
	local addon = NewTaskClassificationFixture()
	addon:RebuildQuestSnapshotStore()
	addon:RefreshTaskAreaStates(false)
	local row = addon.row
	addon.row = nil
	addon:ObserveTaskAreaChange()
	Equal(addon:GetTaskAreaStateStore("bonus")[12345], nil)
	Equal(addon.announcements[1], "BONUS_OBJECTIVE_LEFT")
	addon.row, addon.taskInfo = row, nil
	addon:ObserveTaskAreaChange()
	Equal(addon:GetTaskAreaStateStore("bonus")[12345], nil)
	Equal(addon:GetTaskAnnouncementType(12345), nil)
	Equal(#addon.announcements, 1, "a fresh unknown task must not inherit the removed task's classification")
	addon.taskInfo = { displayAsObjective = true }
	addon:ObserveTaskAreaChange()
	Equal(addon.announcements[2], "BONUS_OBJECTIVE_ENTERED")
end)

QT:RegisterTest("unavailable world classification preserves active area and accepts explicit false", function()
	local addon = NewTaskClassificationFixture()
	addon.worldClassification, addon.taskInfo = true, { displayAsObjective = false }
	addon:RebuildQuestSnapshotStore()
	addon:RefreshTaskAreaStates(false)
	addon.worldClassification = nil
	addon:ObserveTaskAreaChange()
	Equal(addon:GetTaskAreaStateStore("world")[12345], "Bonus Area")
	Equal(addon:GetTaskAnnouncementType(12345), "world")
	Equal(#addon.announcements, 0, "unavailable world metadata must not invent an exit")
	addon.worldClassification = false
	addon:ObserveTaskAreaChange()
	Equal(addon:GetTaskAreaStateStore("world")[12345], nil)
	Equal(addon:GetTaskAnnouncementType(12345), nil)
	Equal(addon.announcements[1], "WORLD_QUEST_LEFT")
	addon.worldClassification = nil
	addon:ObserveTaskAreaChange()
	Equal(#addon.announcements, 1, "unknown must not resurrect the old positive")
end)

QT:RegisterTest("independent world classification readers use the newest boolean in either order", function()
	for _, original in ipairs({ true, false }) do
		for _, reader in ipairs({ "snapshot", "resolver" }) do
			local addon = NewTaskClassificationFixture()
			addon.worldClassification, addon.taskInfo = original, { displayAsObjective = false }
			addon:RebuildQuestSnapshotStore()
			addon:RefreshTaskAreaStates(false)
			addon.worldClassification = nil
			addon.worldReadQueue = reader == "snapshot"
				and { not original, "unknown", "unknown" } or { "unknown", not original, "unknown" }
			addon:ObserveTaskAreaChange()
			Equal(#addon.worldReadQueue, 0, "the independent snapshot, merge, and public reader all run")
			Equal(addon:IsWorldQuest(12345), not original, reader)
			Equal(addon:GetTaskAnnouncementType(12345), not original and "world" or nil, reader)
			Equal(addon:GetTaskAreaStateStore("world")[12345] ~= nil, not original, reader)
			Equal(#addon.announcements, 1)
			Equal(addon.announcements[1], original and "WORLD_QUEST_LEFT" or "WORLD_QUEST_ENTERED")
			addon:ObserveTaskAreaChange()
			Equal(#addon.announcements, 1, "unknown after the newest observation must not replay transitions")
		end
	end
end)

QT:RegisterTest("world classification starts unknown and resets on removal acceptance and runtime boundaries", function()
	for _, boundary in ipairs({ "removal", "acceptance", "runtime" }) do
		local addon = NewTaskClassificationFixture()
		addon.worldClassification, addon.taskInfo = nil, { displayAsObjective = false }
		addon:RebuildQuestSnapshotStore()
		Equal(addon:GetQuestSnapshot(12345).isWorldQuest, nil, "a first unknown read is not explicit false")
		addon.worldClassification = true
		addon:ObserveTaskAreaChange()
		Equal(addon:GetTaskAreaStateStore("world")[12345], "Bonus Area")
		if boundary == "removal" then
			local row = addon.row
			addon.row = nil
			addon:ObserveTaskAreaChange()
			addon.row = row
		elseif boundary == "acceptance" then
			addon.pendingQuestRemovals, addon.onQuestLogUpdate = {}, {}
			addon:QUEST_ACCEPTED(nil, 12345)
		else
			addon:ResetTaskAreaStateStore()
		end
		addon.worldClassification = nil
		addon:ObserveTaskAreaChange()
		Equal(addon:GetTaskAreaStateStore("world")[12345], nil, boundary)
		Equal(addon:GetTaskAnnouncementType(12345), nil, boundary)
	end
end)

QT:RegisterTest("task classification resets with the runtime and fresh acceptance lifetimes", function()
	for _, boundary in ipairs({ "runtime", "acceptance" }) do
		local addon = NewTaskClassificationFixture()
		addon:RebuildQuestSnapshotStore()
		addon:RefreshTaskAreaStates(false)
		addon.taskInfo = nil
		if boundary == "runtime" then
			addon:ResetTaskAreaStateStore()
		else
			addon.pendingQuestRemovals, addon.onQuestLogUpdate = {}, {}
			addon:QUEST_ACCEPTED(nil, 12345)
		end
		addon:ObserveTaskAreaChange()
		Equal(addon:GetTaskAreaStateStore("bonus")[12345], nil, boundary)
		Equal(addon:GetTaskAnnouncementType(12345), nil, boundary)
		addon.taskInfo = { displayAsObjective = true }
		addon:ObserveTaskAreaChange()
		Equal(addon:GetTaskAreaStateStore("bonus")[12345], "Bonus Area", boundary)
		Equal(addon.announcements[#addon.announcements], "BONUS_OBJECTIVE_ENTERED", boundary)
	end
end)

local function NewEnabledOptionFixture(enabled)
	local addon = NewFixture()
	addon.isEnabled = enabled ~= false
	addon.db.profile.enabled = addon.isEnabled
	addon.events, addon.messages = {}, {}
	addon.registeredRuntimeEvents = {}
	addon.eventFrame = {
		scripts = {},
		SetScript = function(frame, event, callback) frame.scripts[event] = callback end,
		RegisterEvent = function(_, event) addon.events[event] = true end,
		UnregisterEvent = function(_, event) addon.events[event] = nil end,
	}
	addon.RegisterRuntimeEvents = QT.RegisterRuntimeEvents
	addon.EnableNameplateAugmentation = function() addon.visualsEnabled = true end
	addon.DisableNameplateAugmentation = function() addon.visualsEnabled = false end
	addon.LeaveAnnouncementChannel = function() addon:ResetCommsState() end
	addon.GetDebugController = function() return { HandleCommand = function() return false end } end
	addon.Print = function(_, message) addon.messages[#addon.messages + 1] = message end
	addon.RefreshOptionsWindow = Noop
	addon.ReconcileQuestLogChatDestination = Noop
	addon.InitializeReleaseNotes = Noop
	addon.visualsEnabled = addon.isEnabled
	addon:RegisterBootstrapEvents()
	if addon.isEnabled then addon:RegisterRuntimeEvents() end
	function addon:DeliverRegisteredEvent(event, ...)
		if not self.events[event] then return false end
		self.eventFrame.scripts.OnEvent(self.eventFrame, event, ...)
		return true
	end
	return addon
end

local function AssertRuntimeEventsUnregistered(addon)
	for _, event in ipairs(addon.runtimeEvents) do
		Equal(addon.events[event], nil, "disabled runtime event " .. event)
	end
	Equal(addon.events.PLAYER_ENTERING_WORLD, true)
	Equal(addon.events.PLAYER_LEAVING_WORLD, true)
end

QT:RegisterTest("generic enabled option applies the actual disable and enable lifecycles", function()
	local addon = NewEnabledOptionFixture()
	local priorWorkState = addon:GetDeferredWorkStateStore()
	addon.pendingQuestAcceptances[12345] = {}
	addon.questCompareResponseQueue = { jobs = {} }
	addon:HandleSlashCommand("set enabled off")
	Equal(addon.db.profile.enabled, false)
	Equal(addon.isEnabled, false)
	AssertRuntimeEventsUnregistered(addon)
	Equal(next(addon.registeredRuntimeEvents), nil)
	Equal(next(addon.pendingQuestAcceptances), nil)
	Equal(addon.questCompareResponseQueue, nil)
	Equal(addon.visualsEnabled, false)
	assert(addon:GetDeferredWorkStateStore() ~= priorWorkState, "disable must invalidate pending callbacks")
	Equal(addon.messages[#addon.messages], "enabled = false")
	addon:HandleSlashCommand("set enabled on")
	Equal(addon.db.profile.enabled, true)
	Equal(addon.isEnabled, true)
	Equal(addon.events.QUEST_LOG_UPDATE, true)
	Equal(addon.registeredRuntimeEvents.QUEST_LOG_UPDATE, true)
	Equal(addon.visualsEnabled, true)
	Equal(#addon.delayed, 1, "enable must arrange the initial scan")
	Equal(addon.messages[#addon.messages], "enabled = true")
	addon:HandleSlashCommand("set enabled on")
	Equal(#addon.delayed, 1, "idempotent enabling must not duplicate initialization")
end)

QT:RegisterTest("enabled option preserves pre-login deferral and rejects nonbooleans", function()
	local addon = NewEnabledOptionFixture()
	addon:Disable()
	addon.hasLoggedIn = false
	Equal(addon:SetOption("enabled", true), true)
	Equal(addon.db.profile.enabled, true)
	Equal(addon.isEnabled, false)
	AssertRuntimeEventsUnregistered(addon)
	Equal(#addon.delayed, 0)
	for _, value in ipairs({ "false", 0, {} }) do
		Equal(addon:SetOption("enabled", value), false)
		Equal(addon.db.profile.enabled, true)
	end
	Equal(addon:SetOption("enabled", nil), false)
	addon:OnLogin()
	Equal(addon.isEnabled, true)
	Equal(addon.events.QUEST_LOG_UPDATE, true)
end)

local function ObserveWorldLifecycleWork(addon)
	local calls = { refresh = 0, join = 0, presence = 0, location = 0 }
	addon.RefreshTaskAreaStates = function() calls.refresh = calls.refresh + 1 end
	addon.EnsureAnnouncementChannelJoined = function() calls.join = calls.join + 1 end
	addon.BroadcastQTPlayerPresence = function() calls.presence = calls.presence + 1 end
	addon.BroadcastPlayerLocation = function() calls.location = calls.location + 1 end
	addon.InitializeMinimapLauncher, addon.NotifyAddonUpdate = Noop, Noop
	addon.InitializePlayerLocations = Noop
	return calls
end

QT:RegisterTest("bootstrap world events survive disable and re-enable without disabled runtime work", function()
	local addon = NewEnabledOptionFixture()
	local calls = ObserveWorldLifecycleWork(addon)
	Equal(addon:DeliverRegisteredEvent("PLAYER_LEAVING_WORLD"), true)
	Equal(addon.isLoggingOut, true)
	Equal(calls.presence, 1)
	Equal(calls.location, 1)
	Equal(addon:DeliverRegisteredEvent("PLAYER_ENTERING_WORLD"), true)
	Equal(addon.isLoggingOut, false)
	Equal(calls.refresh, 1)
	Equal(calls.join, 1)
	addon:Disable()
	calls = ObserveWorldLifecycleWork(addon)
	Equal(addon:DeliverRegisteredEvent("PLAYER_LEAVING_WORLD"), true)
	Equal(addon.isLoggingOut, true)
	Equal(addon:DeliverRegisteredEvent("PLAYER_ENTERING_WORLD"), true)
	Equal(addon.isLoggingOut, false, "disabled zoning must clear the leaving-world flag")
	Equal(addon:DeliverRegisteredEvent("QUEST_LOG_UPDATE"), false)
	for name, count in pairs(calls) do Equal(count, 0, "disabled " .. name) end
	addon:Enable()
	Equal(addon.isEnabled, true)
	Equal(addon.isLoggingOut, false, "re-enable must not inherit a completed loading screen")
	Equal(addon.events.QUEST_LOG_UPDATE, true)
	Equal(addon.registeredRuntimeEvents.PLAYER_ENTERING_WORLD, nil, "bootstrap event must have one lifecycle owner")
	Equal(calls.refresh, 1)
	Equal(calls.join, 1)
end)

QT:RegisterTest("initially disabled login and zoning retain bootstrap state without runtime work", function()
	local addon = NewEnabledOptionFixture(false)
	local calls = ObserveWorldLifecycleWork(addon)
	Equal(addon:DeliverRegisteredEvent("PLAYER_LOGIN"), true)
	Equal(addon.isEnabled, false)
	for _ = 1, 2 do
		Equal(addon:DeliverRegisteredEvent("PLAYER_LEAVING_WORLD"), true)
		Equal(addon.isLoggingOut, true)
		Equal(addon:DeliverRegisteredEvent("PLAYER_ENTERING_WORLD"), true)
		Equal(addon.isLoggingOut, false)
	end
	for name, count in pairs(calls) do Equal(count, 0, "initially disabled " .. name) end
	Equal(next(addon.registeredRuntimeEvents), nil)
	Equal(addon.events.QUEST_LOG_UPDATE, nil)
	addon:Enable()
	Equal(addon.isEnabled, true)
	Equal(addon.isLoggingOut, false)
	Equal(calls.refresh, 1)
	Equal(calls.join, 1)
	Equal(addon:DeliverRegisteredEvent("PLAYER_ENTERING_WORLD"), true)
	Equal(calls.refresh, 2, "enabled world entry must retain the runtime refresh")
	Equal(calls.join, 2)
end)

local function NewProfileDeletionFixture()
	local main = { enabled = true }
	local addon = setmetatable({
		activeCharacterKey = "Main-Realm", activeProfileKey = "Main-Realm",
		db = {
			global = {}, profile = main,
			profiles = { ["Main-Realm"] = main, ["Alt-Realm"] = { showChatBubbles = false } },
			profileKeys = { ["Main-Realm"] = "Main-Realm", ["Alt-Realm"] = "Alt-Realm" },
		},
	}, { __index = QT })
	return addon
end

QT:RegisterTest("deleting an assigned character profile persists until that character initializes", function()
	local addon = NewProfileDeletionFixture()
	local main = addon.db.profile
	Equal(addon:DeleteProfile("Alt-Realm"), true)
	Equal(addon.db.profiles["Alt-Realm"], nil)
	Equal(addon.db.profileKeys["Alt-Realm"], nil)
	Equal(#addon:GetProfileKeys(), 1)
	Equal(addon.db.profile, main)
	Equal(addon.db.profileKeys["Main-Realm"], "Main-Realm")
	Equal(addon:DeleteProfile("Main-Realm"), false)
	-- Exercise the real initializer against private saved data, never _G.
	local returningAlt = setmetatable({
		GetCurrentCharacterKey = function() return "Alt-Realm" end,
	}, { __index = QT })
	returningAlt:InitializeDatabase({ global = {}, profiles = addon.db.profiles, profileKeys = addon.db.profileKeys })
	Equal(returningAlt.activeProfileKey, "Alt-Realm")
	Equal(returningAlt.db.profile.showChatBubbles, QT.DEFAULTS.profile.showChatBubbles)
	Equal(returningAlt.db.profiles["Main-Realm"], main)
end)

QT:RegisterTest("deleting a shared profile clears all assignments without recreating other defaults", function()
	local addon = NewProfileDeletionFixture()
	local altDefault = addon.db.profiles["Alt-Realm"]
	addon.db.profiles.Shared = { showChatBubbles = true }
	addon.db.profileKeys["Alt-Realm"] = "Shared"
	addon.db.profileKeys["Another-Realm"] = "Shared"
	Equal(addon:DeleteProfile("Shared"), true)
	Equal(addon.db.profiles.Shared, nil)
	Equal(addon.db.profileKeys["Alt-Realm"], nil)
	Equal(addon.db.profileKeys["Another-Realm"], nil)
	Equal(addon.db.profiles["Alt-Realm"], altDefault)
	Equal(addon.db.profiles["Another-Realm"], nil)
	local returningAlt = setmetatable({
		GetCurrentCharacterKey = function() return "Alt-Realm" end,
	}, { __index = QT })
	returningAlt:InitializeDatabase({ global = {}, profiles = addon.db.profiles, profileKeys = addon.db.profileKeys })
	Equal(returningAlt.db.profile, altDefault)
	Equal(returningAlt.db.profile.showChatBubbles, false, "existing character default must retain its settings")
end)

QT:RegisterTest("audit unknown quest-log count preserves existing snapshot", function()
	local addon = NewFixture()
	local priorQuest = SeedSnapshot(addon)
	addon.unreadableCount = true
	addon:RebuildQuestSnapshotStore()
	Equal(addon.snapshot.byQuestID[99999], priorQuest)
	Equal(addon.snapshot.order[1], 99999)
	Equal(addon.snapshot.generation, 7)
	Equal(addon.snapshot.lastUnreadableRow, "count")
end)

QT:RegisterTest("audit incomplete quest-log row cannot commit partial snapshot", function()
	local addon = NewFixture()
	local priorQuest = SeedSnapshot(addon)
	addon.rows[2] = { title = "Data Not Ready", isHeader = false }
	addon:RebuildQuestSnapshotStore()
	Equal(addon.snapshot.byQuestID[99999], priorQuest)
	Equal(addon.snapshot.byQuestID[12345], nil)
	Equal(addon.snapshot.generation, 7)
	Equal(addon.snapshot.lastUnreadableRow, 2)
end)

QT:RegisterTest("audit confirmed empty quest log clears previous snapshot", function()
	local addon = NewFixture()
	SeedSnapshot(addon)
	addon.rows = {}
	addon:RebuildQuestSnapshotStore()
	Equal(next(addon.snapshot.byQuestID), nil)
	Equal(#addon.snapshot.order, 0)
	Equal(addon.snapshot.generation, 8)
	Equal(addon.snapshot.lastUnreadableRow, nil)
end)

QT:RegisterTest("audit restricted snapshot refresh performs no quest API reads", function()
	local addon = NewFixture()
	local priorQuest = SeedSnapshot(addon)
	addon.blocked = true
	addon.API.GetNumQuestLogEntries = function()
		error("restricted count read")
	end
	addon.API.GetQuestLogInfo = function()
		error("restricted row read")
	end
	Equal(addon:RebuildQuestSnapshotStore(), addon.snapshot)
	Equal(addon.snapshot.byQuestID[99999], priorQuest)
	Equal(addon.snapshot.generation, 7)
end)

QT:RegisterTest("audit live false clears cached quest completion and readiness", function()
	local addon = NewFixture()
	addon.tracker[12345] = { isComplete = true, isReadyForTurnIn = true }
	addon.snapshot.byQuestID[12345] = { isComplete = true }
	local state = addon:GetTrackedQuestStatusState(12345, true)
	Equal(state.isComplete, false)
	Equal(state.isReadyForTurnIn, false)
end)

QT:RegisterTest("audit unknown or restricted live status retains known completion", function()
	local addon = NewFixture()
	addon.tracker[12345] = { isComplete = true, isReadyForTurnIn = true }
	addon.liveReady, addon.liveComplete = nil, nil
	local state = addon:GetTrackedQuestStatusState(12345, true)
	Equal(state.isComplete, true)
	Equal(state.isReadyForTurnIn, true)
	addon.blocked = true
	addon.API.IsQuestReadyForTurnIn = function()
		error("restricted status read")
	end
	addon.API.IsQuestComplete = function()
		error("restricted status read")
	end
	state = addon:GetTrackedQuestStatusState(12345, true)
	Equal(state.isComplete, true)
	Equal(state.isReadyForTurnIn, true)
end)

QT:RegisterTest("audit full scans preserve already-observed objective milestones", function()
	local addon = NewFixture()
	addon:WatchQuest(12345, addon.rows[1])
	local history = addon.tracker[12345].objectiveProgressHighWater
	addon.liveValue = 0
	addon:ScanQuestLog()
	Equal(addon.tracker[12345].objectiveProgressHighWater, history)
	Equal(addon.tracker[12345].objectiveValues[1], 0)
	Equal(addon:UpdateTrackedObjectiveProgress(addon.tracker[12345], 1, "80% Locations Photographed", 80), false)
	Equal(addon:UpdateTrackedObjectiveProgress(addon.tracker[12345], 1, "100% Locations Photographed", 100), true)
end)

QT:RegisterTest("audit enabling starts fresh objective history after missed acceptance events", function()
	local addon = NewFixture()
	addon:WatchQuest(12345, addon.rows[1])
	local oldHistory = addon.tracker[12345].objectiveProgressHighWater
	addon.isEnabled = false
	addon.liveValue = 0
	addon:Enable()
	Equal(addon.tracker[12345], nil)
	Equal(#addon.delayed, 1)
	addon.delayed[1]()
	Equal(addon.tracker[12345] ~= nil, true)
	Equal(addon.tracker[12345].objectiveProgressHighWater ~= oldHistory, true)
	Equal(addon:UpdateTrackedObjectiveProgress(addon.tracker[12345], 1, "20% Locations Photographed", 20), true)
end)

QT:RegisterTest("audit supplied cached quest-log index is revalidated after rows shift", function()
	local addon = NewFixture()
	addon.rows = {
		{ questID = 54321, title = "Other Quest", questLogIndex = 1 },
		{ questID = 12345, title = "Photo Quest", questLogIndex = 2 },
	}
	Equal(addon:GetQuestLogIndexForQuest(12345, { questID = 12345, questLogIndex = 1 }), 2)
end)

QT:RegisterTest("audit immediate waypoint mutation runs exactly once", function()
	local addon = NewFixture()
	local points, writes, tracking = 0, 0, 0
	addon.API.CanSetUserWaypointOnMap = function(mapID)
		Equal(mapID, 100)
		return true
	end
	addon.API.CreateUiMapPoint = function(mapID, x, y)
		points = points + 1
		Equal(mapID, 100)
		Equal(x, 0.25)
		Equal(y, 0.50)
		return { mapID = mapID, x = x, y = y }
	end
	addon.API.SetUserWaypoint = function()
		writes = writes + 1
		return true
	end
	addon.API.SetSuperTrackedUserWaypoint = function(enabled)
		Equal(enabled, true)
		tracking = tracking + 1
	end
	Equal(addon:CreateBlizzardWaypoint(100, 25, 50), true)
	Equal(points, 1)
	Equal(writes, 1)
	Equal(tracking, 1)
	Equal(addon.runtime.pendingWaypointIntent, nil)
	Equal(next(addon.runtime.deferredWorkState.entries), nil)
end)

QT:RegisterTest("rejected waypoint writes cannot report success or track the previous pin", function()
	for _, result in ipairs({ "accept", "reject", "missing", "throw", "secret", "wrong type" }) do
		local addon = NewFixture()
		local secret, oldPoint = {}, { mapID = 7 }
		local currentPoint, writes, tracks = oldPoint, 0, 0
		local canAccessValue = addon.CanAccessValue
		addon.CanAccessValue = function(self, value)
			return value ~= secret and canAccessValue(self, value)
		end
		addon.API.CanSetUserWaypointOnMap = function() return true end
		addon.API.CreateUiMapPoint = function(mapID, x, y) return { mapID = mapID, x = x, y = y } end
		addon.API.SetUserWaypoint = function(point)
			writes = writes + 1
			if result == "throw" then error("waypoint rejected") end
			if result == "secret" then return secret end
			if result == "wrong type" then return "true" end
			if result == "missing" then return nil end
			if result == "reject" then return false end
			currentPoint = point
			return true
		end
		addon.API.SetSuperTrackedUserWaypoint = function() tracks = tracks + 1 end
		Equal(addon:CreateBlizzardWaypoint(100, 25, 50), result == "accept", result)
		Equal(writes, 1)
		Equal(tracks, result == "accept" and 1 or 0)
		Equal(currentPoint.mapID, result == "accept" and 100 or 7)
		Equal(addon.runtime.pendingWaypointIntent, nil)
		Equal(next(addon:GetDeferredWorkStateStore().entries), nil)
	end
end)

local function NewWaypointLifecycleFixture(restriction)
	local addon = NewEnabledOptionFixture()
	local clock = QT:CreateTestClock(0)
	addon.restriction = restriction
	addon.IsWorkBlocked = QT.IsWorkBlocked
	addon.IsRuntimeRestrictionTypeActive = function(self, kind) return self.restriction == kind end
	addon.API.InCombatLockdown = function() return addon.restriction == "combat" end
	addon.API.IsWorldMapVisible = function() return false end
	addon.API.Delay = function(delay, callback) clock:After(delay, callback) end
	addon.API.GetTime = function() return clock:GetTime() end
	addon.API.CanSetUserWaypointOnMap = function() return true end
	addon.API.CreateUiMapPoint = function(mapID, x, y) return { mapID = mapID, x = x, y = y } end
	addon.waypointWrites, addon.waypointTracks = {}, 0
	addon.API.SetUserWaypoint = function(point)
		addon.waypointWrites[#addon.waypointWrites + 1] = point
		return true
	end
	addon.API.SetSuperTrackedUserWaypoint = function() addon.waypointTracks = addon.waypointTracks + 1 end
	addon.RefreshNameplatesForQuestStateChange = Noop
	addon.OnNameplatePlayerRegenEnabled = Noop
	addon.FlushPendingAnnouncementIntents = Noop
	return addon, clock
end

QT:RegisterTest("disabled restricted waypoint clicks are rejected across real disable and enable", function()
	for _, restriction in ipairs({ "combat", "encounter", "challenge", "pvp", "map" }) do
		local addon, clock = NewWaypointLifecycleFixture(restriction)
		addon:Disable()
		Equal(addon.events.PLAYER_REGEN_ENABLED, nil)
		Equal(addon.events.ADDON_RESTRICTION_STATE_CHANGED, nil)
		Equal(addon:CreateBlizzardWaypoint(84, 10, 20), false, restriction)
		Equal(addon.runtime.pendingWaypointIntent, nil)
		Equal(next(addon:GetDeferredWorkStateStore().entries), nil)
		clock:Advance(1)
		addon.restriction = nil
		addon:DeliverRegisteredEvent("PLAYER_REGEN_ENABLED")
		addon:DeliverRegisteredEvent("ADDON_RESTRICTION_STATE_CHANGED")
		clock:Advance(60)
		Equal(#addon.waypointWrites, 0)
		-- A new unrestricted click works without enabling background runtime.
		Equal(addon:CreateBlizzardWaypoint(85, 30, 40), true)
		Equal(addon.isEnabled, false)
		AssertRuntimeEventsUnregistered(addon)
		Equal(#addon.waypointWrites, 1)
		Equal(addon.waypointWrites[1].mapID, 85)
		addon:Enable()
		clock:Advance(1)
		Equal(#addon.waypointWrites, 1, "re-enabling must not resurrect the rejected click")
		Equal(addon.waypointTracks, 1)
	end
end)

QT:RegisterTest("enabled waypoint clicks resume once through registered restriction release events", function()
	for _, restriction in ipairs({ "combat", "encounter", "challenge", "pvp", "map" }) do
		local addon, clock = NewWaypointLifecycleFixture(restriction)
		Equal(addon.events.PLAYER_REGEN_ENABLED, true)
		Equal(addon.events.ADDON_RESTRICTION_STATE_CHANGED, true)
		Equal(addon:CreateBlizzardWaypoint(84, 10, 20), true)
		Equal(addon:CreateBlizzardWaypoint(85, 30, 40), true)
		clock:Advance(1)
		Equal(#addon.waypointWrites, 0)
		addon.restriction = nil
		addon:DeliverRegisteredEvent(restriction == "combat" and "PLAYER_REGEN_ENABLED" or "ADDON_RESTRICTION_STATE_CHANGED")
		clock:Advance(60)
		Equal(#addon.waypointWrites, 1)
		Equal(addon.waypointWrites[1].mapID, 85, "latest accepted click replaces older intent")
		Equal(addon.waypointTracks, 1)
		Equal(addon.runtime.pendingWaypointIntent, nil)
		Equal(next(addon:GetDeferredWorkStateStore().entries), nil)
	end
end)

QT:RegisterTest("deferred waypoint rejection leaves tracking untouched and permits an explicit retry", function()
	local addon, clock = NewWaypointLifecycleFixture("combat")
	local attempts = 0
	addon.API.SetUserWaypoint = function()
		attempts = attempts + 1
		return false
	end
	Equal(addon:CreateBlizzardWaypoint(84, 10, 20), true, "restricted enabled click accepts a deferred attempt")
	clock:Advance(1)
	Equal(attempts, 0)
	addon.restriction = nil
	addon:DeliverRegisteredEvent("PLAYER_REGEN_ENABLED")
	clock:Advance(1)
	Equal(attempts, 1)
	Equal(addon.waypointTracks, 0)
	Equal(addon.runtime.pendingWaypointIntent, nil)
	Equal(next(addon:GetDeferredWorkStateStore().entries), nil)
	addon:DeliverRegisteredEvent("PLAYER_REGEN_ENABLED")
	Equal(attempts, 1, "native rejection must not produce an automatic retry loop")
	addon.API.SetUserWaypoint = function() attempts = attempts + 1; return true end
	Equal(addon:CreateBlizzardWaypoint(84, 10, 20), true)
	Equal(attempts, 2)
	Equal(addon.waypointTracks, 1)
end)

QT:RegisterTest("audit WatchQuest does not restore stale snapshot completion over live false", function()
	local addon = NewFixture()
	addon.rows[1].isComplete = true
	addon.liveComplete = false
	addon:WatchQuest(12345, addon.rows[1])
	Equal(addon.tracker[12345].isComplete, false)
end)

QT:RegisterTest("audit color edit callback cannot write into a switched or replaced profile", function()
	local addon = NewFixture()
	local writes = 0
	function addon:SetOption(key, value)
		writes = writes + 1
		self.db.profile[key] = value
		return true
	end
	local origin = addon.db.profile
	local applyColor = addon:CreateProfileOptionEditCallback("nameplateQuestHealthColor")
	local selected = { r = 1, g = 0, b = 0 }
	Equal(applyColor(selected), true)
	Equal(origin.nameplateQuestHealthColor, selected)
	addon.db.profile = { nameplateQuestHealthColor = { r = 0, g = 0, b = 1 } }
	local replacement = addon.db.profile.nameplateQuestHealthColor
	Equal(applyColor({ r = 0, g = 1, b = 0 }), false)
	Equal(addon.db.profile.nameplateQuestHealthColor, replacement)
	Equal(writes, 1)
	-- Copy/reset replaces a profile table even when its selected name is unchanged.
	addon.activeProfileKey = "Same Profile"
	local replacementEditor = addon:CreateProfileOptionEditCallback("nameplateQuestHealthColor")
	addon.db.profile = {}
	Equal(replacementEditor(selected), false)
	Equal(writes, 1)
end)

QT:RegisterTest("audit newer color picker invalidates callbacks from an older picker", function()
	local addon = NewFixture()
	local writes = 0
	function addon:SetOption() writes = writes + 1; return true end
	local oldEditor = addon:CreateProfileOptionEditCallback("nameplateQuestHealthColor")
	local newEditor = addon:CreateProfileOptionEditCallback("nameplateQuestHealthColor")
	Equal(oldEditor({ r = 1, g = 0, b = 0 }), false)
	Equal(newEditor({ r = 0, g = 1, b = 0 }), true)
	Equal(writes, 1)
end)

QT:RegisterTest("audit bubble edit revert cannot restore another profile's settings", function()
	local addon = NewFixture()
	local originalProfile = addon.db.profile
	addon.personalBubbleEditSession = {
		profile = originalProfile,
		saved = { chatBubbleSize = 140, chatBubbleDuration = 5 },
		pending = true,
	}
	addon.db.profile = { chatBubbleSize = 80, chatBubbleDuration = 2 }
	function addon:ApplyPersonalBubbleEditSnapshot() error("stale profile snapshot applied") end
	addon:RevertPersonalBubbleEditSession()
	Equal(addon.db.profile.chatBubbleSize, 80)
	Equal(addon.db.profile.chatBubbleDuration, 2)
	Equal(rawget(addon, "personalBubbleEditSession"), nil)
	Equal(addon.personalBubbleEditSessionRestoring, false)
end)

QT:RegisterTest("audit bubble edit revert still applies the current profile snapshot", function()
	local addon = NewFixture()
	local writes = 0
	function addon:SetOption(key, value)
		writes = writes + 1
		self.db.profile[key] = value
		return true
	end
	addon.AttachPersonalBubbleEditModeDialog = Noop
	addon.RefreshPersonalBubbleEditModeDialog = Noop
	-- False shadows a possible live dialog on the prototype during /qt test.
	addon.personalBubbleEditModeDialog = false
	addon.personalBubbleEditSession = {
		profile = addon.db.profile,
		saved = { chatBubbleSize = 140, chatBubbleDuration = 5 },
		pending = true,
	}
	addon:RevertPersonalBubbleEditSession()
	Equal(addon.db.profile.chatBubbleSize, 140)
	Equal(addon.db.profile.chatBubbleDuration, 5)
	Equal(writes, 2)
	Equal(addon.personalBubbleEditSession.pending, false)
end)

QT:RegisterTest("moved celebration and general controls preserve existing profile values", function()
	local addon = QT
	local function Checkbox()
		return { SetChecked = function(self, value) self.checked = value end }
	end
	local emotes = { "emoteOnQuestCompletion", "emoteOnNearbyPlayerQuestCompletion", "emoteOnLevelUp", "emoteOnNearbyPlayerLevelUp" }
	addon.whereToAnnounceFrame, addon.whereToAnnounceControls = {}, {}
	addon.optionsFrame, addon.homeControls = {}, { showMinimapButton = Checkbox() }
	for i, key in ipairs(emotes) do
		addon.db.profile[key] = i % 2 == 1
		addon.whereToAnnounceControls[key] = Checkbox()
	end
	addon.db.profile.showMinimapButton = false
	addon:RefreshOptionsWindow()
	for i, key in ipairs(emotes) do assert(addon.whereToAnnounceControls[key].checked == (i % 2 == 1)) end
	assert(addon.homeControls.showMinimapButton.checked == false)
	for i, key in ipairs(emotes) do addon.db.profile[key] = i % 2 == 0 end
	addon.db.profile.showMinimapButton = true
	addon:RefreshOptionsWindow()
	for i, key in ipairs(emotes) do assert(addon.whereToAnnounceControls[key].checked == (i % 2 == 0)) end
	assert(addon.homeControls.showMinimapButton.checked == true)
end)

QT:RegisterTest("home status distinguishes runtime state and conditional sharing preferences", function()
	local addon = NewFixture()
	local options = {
		showPlayerLocations = true, onlyShowQuestPartners = true, sharePlayerLocation = false,
		lookingForQuestPartners = false, autoInviteWhileLFG = true, autoInviteFriends = false,
		showChatLogs = false, chatLogDestination = "separate", mirrorChatLogsToMainChat = true,
	}
	addon.GetOption = function(_, key) return options[key] end
	addon.GetCurrentProfileKey = function() return "Private fixture" end
	addon.GetAddonVersion = function() return "5.16.2" end
	addon.GetShowProgressForLabel = function() return "Everyone" end
	addon.GetChatLogDestinationLabel = function() return "DESTINATION_SENTINEL" end
	addon.isEnabled = false
	addon.db.global.availableAddonVersion = "5.16.3"
	local L = QT.Translate
	local groups = addon:GetHomeStatusGroups()
	assert(groups[1].text:find(L("Disabled"), 1, true))
	assert(groups[1].text:find(L("Saved preferences below apply when QuestTogether is enabled."), 1, true))
	assert(groups[1].text:find("5.16.3", 1, true))
	assert(groups[2].text:find(L("Other requests while looking for partners"), 1, true))
	assert(groups[3].text:find(L("Questing partners only"), 1, true))
	assert(groups[4].text == L("Ask before sharing quests"))
	assert(not groups[5].text:find("DESTINATION_SENTINEL", 1, true))
	for _, group in ipairs(groups) do assert(type(group.categoryKey) == "string") end

	addon.isEnabled = true
	addon.db.global.availableAddonVersion = "5.16.2"
	options.showPlayerLocations, options.showChatLogs = false, true
	options.autoInviteWhileLFG, options.autoAcceptPartyShareRequests = false, true
	groups = addon:GetHomeStatusGroups()
	assert(not groups[1].text:find(L("Newer version detected"), 1, true))
	assert(not groups[1].text:find(L("Saved preferences below apply when QuestTogether is enabled."), 1, true))
	assert(groups[2].text:find(L("Ask first"), 1, true))
	assert(not groups[3].text:find(L("Questing partners only"), 1, true))
	assert(groups[4].text == L("Automatically approve party share requests"))
	assert(groups[5].text:find("DESTINATION_SENTINEL", 1, true))
end)

QT:RegisterTest("home status layout grows for wrapped translations and shrinks after refresh", function()
	local addon = NewFixture()
	addon.optionsFrame = {}
	local textHeight = 70
	local function Sized()
		return { SetHeight = function(self, height) self.height = height end }
	end
	local rows = {}
	for i = 1, 7 do
		rows[i] = {
			frame = Sized(), button = { SetText = Noop },
			text = { SetText = Noop, GetStringHeight = function() return textHeight end },
		}
	end
	local groups = {}
	for i = 1, 7 do groups[i] = { title = "Section", text = "Wrapped text", categoryKey = "groupsCategory" } end
	addon.GetHomeStatusGroups = function() return groups end
	addon.homeControls = {
		statusGroups = rows, statusPanel = Sized(), content = Sized(),
		description = { GetStringHeight = function() return 40 end },
		tipsText = { GetStringHeight = function() return 60 end },
	}
	addon:RefreshHomeWindow()
	local expanded = addon.homeControls.statusPanel.height
	assert(expanded >= 7 * (70 + 26 + 12))
	assert(addon.homeControls.content.height >= expanded + 400)
	for _, row in ipairs(rows) do assert(row.frame.height >= textHeight + 26) end
	textHeight = 14
	addon:RefreshHomeWindow()
	assert(addon.homeControls.statusPanel.height < expanded)
	assert(addon.homeControls.statusPanel.height >= 304)
end)
