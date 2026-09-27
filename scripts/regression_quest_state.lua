-- Additional live-safe regressions. These use private addon fixtures and never
-- replace Blizzard globals, shared UI tables, or secure-adjacent API functions.
local QuestTogether = _G.QuestTogether

local function AssertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function NewQuestFixture()
	local addon = setmetatable({
		isEnabled = true,
		workState = { entries = {}, generations = {} },
		combat = false,
		tracker = {},
		onQuestLogUpdate = {},
		pendingQuestRemovals = {},
		pendingQuestAcceptances = {},
		questsCompleted = {},
		retiredQuestIds = {},
		delayed = {},
		announcements = {},
		area = { world = {}, bonus = {} },
		taskArea = { displayAsObjectiveByQuestID = {}, isWorldQuestByQuestID = {}, resolvedByQuestID = {} },
		liveText = "80% Locations Photographed",
		liveValue = 80,
		objectiveCount = 1,
	}, { __index = QuestTogether })
	addon.API = {
		InCombatLockdown = function() return addon.combat end,
		IsWorldMapVisible = function() return false end,
		Delay = function(_, callback)
			addon.delayed[#addon.delayed + 1] = callback
		end,
		GetQuestLogIndexForQuestID = function()
			return 1
		end,
		GetQuestLogInfo = function()
			return { questID = 12345, title = "Photo Quest" }
		end,
		GetNumQuestLeaderBoards = function()
			return addon.objectiveCount
		end,
	}
	function addon:GetPlayerTracker()
		return self.tracker
	end
	function addon:GetQuestTitle()
		return "Photo Quest"
	end
	function addon:GetTaskAnnouncementType()
		return nil
	end
	function addon:GetTrackedQuestAnnouncementIcon()
		return nil, nil
	end
	function addon:GetAnnouncementIconInfo()
		return nil, nil
	end
	function addon:GetTaskAreaStateStore(taskType)
		return self.area[taskType]
	end
	function addon:GetTaskAreaSubsystemStateStore()
		return self.taskArea
	end
	function addon:RefreshTaskAreaStates()
		return false -- Simulate a deferred refresh without touching real UI.
	end
	function addon:PublishAnnouncementEvent(eventType, text, questId)
		self.announcements[#self.announcements + 1] = { eventType, text, questId }
	end
	function addon:HandleQuestCompleted(title, questId)
		self:PublishAnnouncementEvent("QUEST_COMPLETED", title, questId)
	end
	function addon:Debugf() end
	function addon:GetDeferredWorkStateStore() return self.workState end
	function addon:IsRuntimeRestrictionTypeActive() return false end
	function addon:ScheduleTaskAreaRefresh() end
	function addon:GetQuestLogIndexForQuest()
		return 1
	end
	function addon:GetNormalizedQuestObjectiveInfo()
		return self.liveText, "progressbar", false, self.liveValue
	end
	function addon:GetTrackedQuestStatusState()
		return { isComplete = false, isReadyForTurnIn = false }
	end
	function addon:WatchQuest(questId, questInfo)
		self.tracker[questId] = { title = questInfo.title, objectives = {}, objectiveValues = {} }
		self:UpdateTrackedObjectiveProgress(self.tracker[questId], 1, self.liveText, self.liveValue)
	end
	return addon
end

local function NewObjectiveProgressFixture()
	local addon = NewQuestFixture()
	addon.liveText = "Locations Photographed"
	addon.liveType = "progressbar"
	-- The objective counter and percentage come from independent APIs. A
	-- progressbar's numFulfilled can stay readable while its percent is absent.
	addon.liveObjectiveValue = 0
	addon.API.GetQuestObjectiveInfo = function()
		return addon.liveText, addon.liveType, false, addon.liveObjectiveValue
	end
	addon.API.GetQuestProgressBarPercent = function()
		return addon.liveValue
	end
	-- Exercise the real normalization contract (all-missing data becomes "")
	-- and tracker initialization, using only private API fixtures.
	addon.GetNormalizedQuestObjectiveInfo = QuestTogether.GetNormalizedQuestObjectiveInfo
	addon.WatchQuest = QuestTogether.WatchQuest
	return addon
end

local function ObserveObjectiveUpdate(addon)
	addon:UNIT_QUEST_LOG_CHANGED(nil, "player")
	AssertEqual(#addon.onQuestLogUpdate, 1, "progress waits for the readable-log event")
	addon:QUEST_LOG_UPDATE()
	AssertEqual(#addon.onQuestLogUpdate, 0)
end

local function NewTaskLifecycleFixture(taskType)
	local clock = QuestTogether:CreateTestClock(100)
	local addon = setmetatable({
		runtimeStateStore = {}, db = { global = {}, profile = {} }, isEnabled = true,
		questsCompleted = {}, retiredQuestIds = {}, announcements = {}, tracker = {},
		pendingQuestRemovals = {}, pendingQuestAcceptances = {}, onQuestLogUpdate = {},
		worldQuestAreaStateByQuestID = {}, bonusObjectiveAreaStateByQuestID = {},
		questSnapshotByQuestID = {}, questSnapshotOrder = {}, objectiveValue = 1,
		rows = { { questID = 99999, questLogIndex = 1, title = "Existing ordinary quest" } },
		worldClassification = taskType == "world", bonusClassification = taskType == "bonus",
		IsWorkBlocked = function(self) return self.blocked == true end,
		RefreshNameplatesForQuestStateChange = function() end,
		Debug = function() end, Debugf = function() end,
		GetAnnouncementIconInfo = function() end,
		GetTrackedQuestAnnouncementIcon = function() end,
		GetTrackedQuestStatusState = function() return { isComplete = false, isReadyForTurnIn = false } end,
		PickRandomCompletionEmote = function() return "cheer" end,
		PlayLocalCompletionEmote = function() end,
	}, { __index = QuestTogether })
	addon.API = {
		Delay = function(delay, callback) clock:After(delay, callback) end,
		GetTime = function() return clock:GetTime() end,
		GetNumQuestLogEntries = function() return #addon.rows end,
		GetQuestLogInfo = function(index) return addon.rows[index] end,
		GetQuestLogIndexForQuestID = function(id)
			for index, row in ipairs(addon.rows) do if row.questID == id then return index end end
		end,
		GetNumQuestLeaderBoards = function() return 1 end,
		GetQuestObjectiveInfo = function()
			return tostring(addon.objectiveValue) .. "/3 Beasts slain", "monster", false, addon.objectiveValue
		end,
		IsWorldQuest = function(id) if id == 12345 then return addon.worldClassification end; return false end,
		GetTaskQuestInfoByQuestID = function(id)
			if id ~= 12345 then return { displayAsObjective = false } end
			return { displayAsObjective = addon.bonusClassification }
		end,
	}
	function addon:GetPlayerTracker() return self.tracker end
	function addon:PublishAnnouncementEvent(event) self.announcements[#self.announcements + 1] = event end
	function addon:AddQuest(hidden)
		self.rows[2] = { questID = 12345, questLogIndex = 2, title = "New Task", isTask = taskType ~= "quest",
			isOnMap = true, isHidden = hidden }
	end
	function addon:RefreshSnapshot()
		self:ScheduleQuestStateRefreshWork("QUEST_LOG_UPDATE", 1)
		clock:Advance(1)
	end
	addon:EnsureRuntimeStateStore()
	addon:RebuildQuestSnapshotStore()
	return addon, clock
end

local function NewInitialScanRecoveryFixture(unavailable)
	local addon, clock = NewTaskLifecycleFixture("quest")
	addon:AddQuest(false)
	addon.isEnabled, addon.hasLoggedIn = false, true
	addon:ResetQuestSnapshotStateStore()
	addon.unavailable, addon.logReads, addon.scanMessages = unavailable, 0, {}
	local getInfo, getCount = addon.API.GetQuestLogInfo, addon.API.GetNumQuestLogEntries
	addon.API.GetQuestLogInfo = function(index)
		addon.logReads = addon.logReads + 1
		if addon.unavailable ~= "row" then return getInfo(index) end
	end
	addon.API.GetNumQuestLogEntries = function()
		addon.logReads = addon.logReads + 1
		if addon.unavailable ~= "count" then return getCount() end
	end
	addon.IsWorkBlocked = nil -- Exercise the real restriction policy and scheduler.
	addon.IsRuntimeRestrictionTypeActive = function(self, kind) return self.restriction == kind end
	addon.API.InCombatLockdown = function() return addon.restriction == "combat" end
	addon.API.IsWorldMapVisible = function() return addon.mapVisible == true end
	addon.CreateMapWorkWakeFrame = function()
		return { SetScript = function(_, kind, callback)
			assert(kind == "OnUpdate")
			addon.mapUpdate = callback
		end }
	end
	-- Enable, scan, log callbacks, snapshot and progress initialization use the
	-- production methods. Status stays fixed by NewTaskLifecycleFixture; native
	-- readiness semantics are covered separately in regression_core_state.lua.
	addon.RegisterRuntimeEvents = function() end
	addon.UnregisterRuntimeEvents = function() end
	addon.API.RegisterAddonPrefix = function() return true end
	addon.EnsureAnnouncementChannelJoined = function() end
	addon.LeaveAnnouncementChannel = function() end
	addon.EnableNameplateAugmentation = function() end
	addon.DisableNameplateAugmentation = function() end
	addon.TryInstallPersonalBubbleEditModeHooks = function() end
	addon.RefreshPersonalBubbleAnchorVisualState = function() end
	addon.RefreshPartyRoster = function() end
	addon.PrintConsoleAnnouncement = function(self, message) self.scanMessages[#self.scanMessages + 1] = message end
	addon.BuildLocalAnnouncementEvent = function() return nil end
	addon.InvalidateNameplateQuestState = function() end
	addon:Enable()
	clock:Advance(0.25)
	AssertEqual(next(addon.tracker), nil)
	AssertEqual(addon:GetQuestSnapshotStateStore().lastUnreadableRow, unavailable == "row" and 1 or "count")
	return addon, clock
end

QuestTogether:RegisterTest("failed initial scans recover tracking on readable log events without polling or repeated scans", function()
	for _, unavailable in ipairs({ "row", "count" }) do
		local addon, clock = NewInitialScanRecoveryFixture(unavailable)
		addon:QUEST_LOG_UPDATE()
		addon:HandleNameplateEvent("QUEST_LOG_UPDATE")
		clock:Drain()
		local reads = addon.logReads
		clock:Advance(10)
		AssertEqual(addon.logReads, reads, "unreadable data must wait for another real log event")
		AssertEqual(next(addon.tracker), nil)
		AssertEqual(#addon.scanMessages, 0)
		addon.unavailable = nil
		addon:QUEST_LOG_UPDATE()
		addon:HandleNameplateEvent("QUEST_LOG_UPDATE")
		clock:Drain()
		AssertEqual(addon:GetQuestSnapshot(12345).title, "New Task")
		assert(addon.tracker[12345] and addon.tracker[99999], "recovery must initialize all existing quests")
		AssertEqual(#addon.scanMessages, 1)
		local tracked = addon.tracker[12345]
		addon:QUEST_LOG_UPDATE()
		clock:Drain()
		AssertEqual(addon.tracker[12345], tracked, "ordinary log events must not rescan after success")
		AssertEqual(#addon.scanMessages, 1)
		addon.objectiveValue = 2
		ObserveObjectiveUpdate(addon)
		AssertEqual(addon.announcements[1], "QUEST_PROGRESS")
	end
end)

QuestTogether:RegisterTest("initial scan recovery waits through runtime restrictions and visible map closure", function()
	for _, restriction in ipairs({ "combat", "encounter", "challenge", "pvp", "map" }) do
		for _, releaseOrder in ipairs({ "map_hidden", "restriction_first", "map_first" }) do
			local addon, clock = NewInitialScanRecoveryFixture("row")
			addon.unavailable, addon.restriction, addon.mapVisible = nil, restriction, releaseOrder ~= "map_hidden"
			local reads = addon.logReads
			addon:QUEST_LOG_UPDATE()
			clock:Drain()
			AssertEqual(addon.logReads, reads, restriction)
			if releaseOrder == "map_first" then
				addon.mapVisible = false
				assert(addon.mapUpdate, "blocked scan must use the addon-owned map watcher")
				addon.mapUpdate(nil, 0.2)
				clock:Drain()
				AssertEqual(addon.logReads, reads, "runtime restriction must still block after map closure")
			end
			addon.restriction = nil
			addon:ADDON_RESTRICTION_STATE_CHANGED()
			clock:Drain()
			if releaseOrder == "restriction_first" then
				AssertEqual(addon.logReads, reads, "map visibility still blocks recovered data")
				AssertEqual(next(addon.tracker), nil)
				addon.mapVisible = false
				assert(addon.mapUpdate, "blocked scan must use the addon-owned map watcher")
				addon.mapUpdate(nil, 0.2)
				clock:Drain()
			end
			assert(addon.tracker[12345], "restriction release must complete the pending scan")
			AssertEqual(#addon.scanMessages, 1)
		end
	end
end)

QuestTogether:RegisterTest("disabled scan recovery cannot run in the next enabled lifetime", function()
	local addon, clock = NewInitialScanRecoveryFixture("row")
	addon.restriction = "combat"
	addon:QUEST_LOG_UPDATE()
	addon:Disable()
	addon.unavailable, addon.restriction = nil, nil
	clock:Advance(0.05)
	addon:PLAYER_REGEN_ENABLED()
	AssertEqual(#addon.scanMessages, 0)
	addon:Enable()
	clock:Advance(0.1) -- The disabled lifetime's area timer was due by now.
	AssertEqual(#addon.scanMessages, 0)
	AssertEqual(next(addon.tracker), nil)
	clock:Advance(0.16)
	assert(addon.tracker[12345], "new enable must perform its own initial scan")
	AssertEqual(#addon.scanMessages, 1)
	addon:QUEST_LOG_UPDATE()
	clock:Drain()
	AssertEqual(#addon.scanMessages, 1, "old retry intent must not survive reenable")
end)

QuestTogether:RegisterTest("scan recovery preserves newly accepted quest announcements through deferred draining", function()
	for _, restricted in ipairs({ false, true }) do
		local addon, clock = NewInitialScanRecoveryFixture("row")
		addon.unavailable = nil
		addon.rows[3] = { questID = 54321, questLogIndex = 3, title = "Accepted during recovery" }
		addon:QUEST_ACCEPTED(nil, 54321)
		if restricted then addon.restriction = "combat" end
		addon:QUEST_LOG_UPDATE()
		clock:Drain()
		if restricted then
			AssertEqual(#addon.announcements, 0)
			addon.restriction = nil
			addon:PLAYER_REGEN_ENABLED()
			clock:Drain()
		end
		assert(addon.tracker[12345] and addon.tracker[54321])
		AssertEqual(#addon.announcements, 1, "recovery must not consume or duplicate acceptance")
		AssertEqual(addon.announcements[1], "QUEST_ACCEPTED")
		AssertEqual(#addon.scanMessages, 1)
	end
end)

QuestTogether:RegisterTest("initial scan recovery cannot resurrect a quest removed while data was unreadable", function()
	local addon, clock = NewInitialScanRecoveryFixture("row")
	addon:QUEST_REMOVED(nil, 12345)
	addon.unavailable = nil -- The readable log can temporarily retain the removed row.
	addon:QUEST_LOG_UPDATE()
	clock:Drain()
	assert(addon.tracker[99999], "other quests must recover")
	AssertEqual(addon.tracker[12345], nil)
	AssertEqual(#addon.announcements, 0)
	AssertEqual(#addon.scanMessages, 1)
end)

QuestTogether:RegisterTest("scan recovery leaves unreadable acceptances pending while recovering other quests", function()
	local addon, clock = NewInitialScanRecoveryFixture("row")
	addon.unavailable = nil
	addon.rows[3] = { questID = 54321, questLogIndex = 3 }
	addon:QUEST_ACCEPTED(nil, 54321)
	addon:QUEST_LOG_UPDATE()
	clock:Drain()
	assert(addon.tracker[12345], "an unreadable new acceptance must not block existing quest recovery")
	AssertEqual(addon.tracker[54321], nil, "scan must not initialize an acceptance before its own readiness checks")
	assert(addon.pendingQuestAcceptances[54321])
	AssertEqual(#addon.announcements, 0)
	addon.rows[3].title = "Finally readable acceptance"
	addon:QUEST_LOG_UPDATE()
	clock:Drain()
	assert(addon.tracker[54321])
	AssertEqual(addon.pendingQuestAcceptances[54321], nil)
	AssertEqual(#addon.announcements, 1)
	AssertEqual(addon.announcements[1], "QUEST_ACCEPTED")
end)

QuestTogether:RegisterTest("scan recovery preserves area entry when task classification recovers after acceptance reads", function()
	for _, earlierAcceptance in ipairs({ false, true }) do
		local addon, clock = NewInitialScanRecoveryFixture("row")
		addon.unavailable = nil
		addon.rows[3] = { questID = 54321, questLogIndex = 3, title = "Pending bonus area",
			isTask = true, isHidden = true, isOnMap = true }
		local classificationReadable = false
		addon.API.GetTaskQuestInfoByQuestID = function(id)
			if id == 54321 then
				if classificationReadable then return { displayAsObjective = true } end
				return nil
			end
			return { displayAsObjective = id == 11111 }
		end
		-- The scan reader gets newer metadata than the queued acceptance. Keep
		-- this transition independent of the number of intermediate API calls.
		addon.ScanQuestLog = function(self, ...)
			classificationReadable = true
			return QuestTogether.ScanQuestLog(self, ...)
		end
		if earlierAcceptance then
			addon.rows[4] = { questID = 11111, questLogIndex = 4, title = "Already readable bonus area",
				isTask = true, isHidden = true, isOnMap = true }
			addon:QUEST_ACCEPTED(nil, 11111)
		end
		addon:QUEST_ACCEPTED(nil, 54321)
		addon:QUEST_LOG_UPDATE()
		clock:Drain()
		assert(addon.tracker[12345], "ordinary quests must recover independently")
		AssertEqual(addon.tracker[54321], nil, "area tracking cannot bypass pending acceptance readiness")
		assert(addon.pendingQuestAcceptances[54321])
		local expectedEntries = earlierAcceptance and 2 or 1
		AssertEqual(#addon.announcements, expectedEntries, "an earlier area refresh must not consume recovery announcement intent")
		for _, event in ipairs(addon.announcements) do AssertEqual(event, "BONUS_OBJECTIVE_ENTERED") end
		addon:QUEST_LOG_UPDATE()
		clock:Drain()
		assert(addon.tracker[54321])
		AssertEqual(addon.pendingQuestAcceptances[54321], nil)
		AssertEqual(#addon.announcements, expectedEntries, "acceptance must not replay an area already announced")
		addon.objectiveValue = 2
		ObserveObjectiveUpdate(addon)
		local bonusProgress = 0
		for _, event in ipairs(addon.announcements) do
			if event == "BONUS_OBJECTIVE_PROGRESS" then bonusProgress = bonusProgress + 1 end
		end
		AssertEqual(bonusProgress, expectedEntries)
	end
end)

QuestTogether:RegisterTest("fresh bonus acceptance resolves current metadata before hidden and ordinary quest decisions", function()
	for _, hidden in ipairs({ false, true }) do
		for _, initiallyUnknown in ipairs({ false, true }) do
			local addon, clock = NewTaskLifecycleFixture("bonus")
			addon:AddQuest(hidden)
			if initiallyUnknown then addon.bonusClassification = nil end
			addon:QUEST_ACCEPTED(nil, 12345)
			addon:QUEST_LOG_UPDATE()
			if initiallyUnknown then
				AssertEqual(addon.tracker[12345], nil)
				AssertEqual(#addon.onQuestLogUpdate, 1, "unknown task classification must retain one acceptance retry")
				AssertEqual(#addon.announcements, 0)
				addon.bonusClassification = true
				addon:QUEST_LOG_UPDATE()
			end
			addon:RefreshSnapshot()
			clock:Drain()
			AssertEqual(addon.tracker[12345] ~= nil, true, "hidden bonus objectives must be tracked too")
			AssertEqual(addon.pendingQuestAcceptances[12345], nil)
			AssertEqual(#addon.announcements, 1, "bonus acceptance must not emit ordinary QUEST_ACCEPTED")
			AssertEqual(addon.announcements[1], "BONUS_OBJECTIVE_ENTERED")
			addon.objectiveValue = 2
			ObserveObjectiveUpdate(addon)
			AssertEqual(addon.announcements[2], "BONUS_OBJECTIVE_PROGRESS")
		end
	end
end)

QuestTogether:RegisterTest("task acceptance classification waits until the real restriction release", function()
	local addon, clock = NewTaskLifecycleFixture("bonus")
	addon:AddQuest(true)
	local reads = 0
	local worldGetter, bonusGetter = addon.API.IsWorldQuest, addon.API.GetTaskQuestInfoByQuestID
	addon.API.IsWorldQuest = function(id) reads = reads + 1; return worldGetter(id) end
	addon.API.GetTaskQuestInfoByQuestID = function(id) reads = reads + 1; return bonusGetter(id) end
	addon.blocked = true
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:QUEST_LOG_UPDATE()
	clock:Advance(1)
	AssertEqual(reads, 0, "classification cannot bypass deferred-work restrictions")
	AssertEqual(addon.tracker[12345], nil)
	addon.blocked = false
	addon:PLAYER_REGEN_ENABLED()
	clock:Drain()
	AssertEqual(reads > 0, true)
	AssertEqual(addon.tracker[12345] ~= nil, true)
	AssertEqual(addon.announcements[1], "BONUS_OBJECTIVE_ENTERED")
end)

QuestTogether:RegisterTest("ordinary acceptance does not wait for unavailable task classification APIs", function()
	local addon, clock = NewTaskLifecycleFixture("quest")
	addon.API.IsWorldQuest, addon.API.GetTaskQuestInfoByQuestID = nil, nil
	addon:AddQuest(false)
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:QUEST_LOG_UPDATE()
	clock:Drain()
	AssertEqual(addon.tracker[12345] ~= nil, true)
	AssertEqual(#addon.onQuestLogUpdate, 0)
	AssertEqual(addon.announcements[1], "QUEST_ACCEPTED")
end)

QuestTogether:RegisterTest("explicit world quest row is classified without an isTask flag or live world API result", function()
	local addon, clock = NewTaskLifecycleFixture("quest")
	addon.worldClassification = nil
	addon:AddQuest(false)
	addon.rows[2].isWorldQuest = true
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:QUEST_LOG_UPDATE()
	clock:Drain()
	AssertEqual(addon.tracker[12345].taskAnnouncementType, "world")
	AssertEqual(#addon.announcements, 1)
	AssertEqual(addon.announcements[1], "WORLD_QUEST_ENTERED")
end)

QuestTogether:RegisterTest("reacceptance cannot use a retired world snapshot before the new row is readable", function()
	local addon, clock = NewTaskLifecycleFixture("world")
	addon:AddQuest(false)
	addon:RebuildQuestSnapshotStore()
	addon:RefreshTaskAreaStates(false)
	addon:WatchQuest(12345, addon.rows[2])
	addon.rows[2] = nil
	addon:QUEST_REMOVED(nil, 12345)
	clock:Advance(0)
	AssertEqual(addon:GetQuestSnapshot(12345).isWorldQuest, true, "the delayed snapshot still describes the old lifetime")
	addon.worldClassification, addon.bonusClassification = nil, nil
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:QUEST_LOG_UPDATE()
	AssertEqual(addon.tracker[12345], nil, "old world classification cannot create a tracker for unreadable reacceptance")
	AssertEqual(#addon.onQuestLogUpdate, 1)
	addon:AddQuest(false)
	addon.worldClassification = true
	addon:QUEST_LOG_UPDATE()
	clock:Drain()
	AssertEqual(addon.tracker[12345].taskAnnouncementType, "world")
	AssertEqual(addon.pendingQuestAcceptances[12345], nil)
end)

QuestTogether:RegisterTest("completion dispatch retains captured task type through both removal orders and expired live state", function()
	for _, taskType in ipairs({ "bonus", "world", "quest" }) do
		for _, turnInFirst in ipairs({ false, true }) do
			local addon, clock = NewTaskLifecycleFixture(taskType)
			addon:AddQuest(false)
			addon:RebuildQuestSnapshotStore()
			addon:RefreshTaskAreaStates(false)
			addon:WatchQuest(12345, addon.rows[2])
			if turnInFirst then addon:QUEST_TURNED_IN(nil, 12345) end
			addon.rows[2] = nil
			if not turnInFirst then
				addon:QUEST_REMOVED(nil, 12345)
				clock:Advance(0)
			end
			addon.worldClassification, addon.bonusClassification = nil, nil
			addon:RefreshSnapshot()
			addon:QUEST_POI_UPDATE()
			clock:Drain()
			addon:QUEST_TURNED_IN(nil, 12345)
			if turnInFirst then addon:QUEST_REMOVED(nil, 12345) end
			clock:Drain()
			local expected = taskType == "bonus" and "BONUS_OBJECTIVE_COMPLETED"
				or (taskType == "world" and "WORLD_QUEST_COMPLETED" or "QUEST_COMPLETED")
			AssertEqual(addon.announcements[#addon.announcements], expected, taskType)
			local eventCount = #addon.announcements
			addon:QUEST_TURNED_IN(nil, 12345)
			addon:QUEST_REMOVED(nil, 12345)
			clock:Drain()
			AssertEqual(#addon.announcements, eventCount, "retained type must not defeat completion deduplication")
		end
	end
end)

QuestTogether:RegisterTest("captured ordinary completion is not reclassified by later bonus metadata", function()
	local addon, clock = NewTaskLifecycleFixture("quest")
	addon:AddQuest(false)
	addon:WatchQuest(12345, addon.rows[2])
	addon:QUEST_TURNED_IN(nil, 12345)
	addon.rows[2].isTask, addon.bonusClassification = true, true
	addon:RebuildQuestSnapshotStore()
	-- Model a later positive source independently of the retired-row scan.
	addon:GetTaskAreaSubsystemStateStore().displayAsObjectiveByQuestID[12345] = true
	addon:QUEST_REMOVED(nil, 12345)
	clock:Drain()
	AssertEqual(addon.announcements[#addon.announcements], "QUEST_COMPLETED")
end)

QuestTogether:RegisterTest("untracked world turn-in uses readable classification without retaining retired history", function()
	local addon = NewTaskLifecycleFixture("world")
	addon:QUEST_TURNED_IN(nil, 12345)
	AssertEqual(addon.announcements[1], "WORLD_QUEST_COMPLETED")
	AssertEqual(addon:GetTaskAreaSubsystemStateStore().isWorldQuestByQuestID[12345], nil)
end)

QuestTogether:RegisterTest("retirement captures a world classification first observed by the area reader in both event orders", function()
	for _, eventOrder in ipairs({ "turn_in_first", "remove_before_timer", "remove_after_timer" }) do
		local turnInFirst = eventOrder == "turn_in_first"
		for _, latestValue in ipairs({ "unknown", false }) do
			local addon, clock = NewTaskLifecycleFixture("world")
			addon.worldClassification = nil
			addon:AddQuest(false)
			addon:RebuildQuestSnapshotStore()
			addon:WatchQuest(12345, addon.rows[2])
			AssertEqual(addon:GetQuestSnapshot(12345).isWorldQuest, nil)
			AssertEqual(addon.tracker[12345].taskAnnouncementType, nil)
			addon.worldClassification = true
			addon:QUEST_POI_UPDATE()
			clock:Drain()
			if latestValue == "unknown" then addon.worldClassification = nil
			else addon.worldClassification = latestValue end
			local expectedType = latestValue == "unknown" and "world" or nil
			local expectedEvent = expectedType and "WORLD_QUEST_COMPLETED" or "QUEST_COMPLETED"
			if turnInFirst then
				addon:QUEST_TURNED_IN(nil, 12345)
				AssertEqual(addon.questsCompleted[12345].taskAnnouncementType, expectedType)
				if latestValue == false then addon.worldClassification = true end
				addon:QUEST_REMOVED(nil, 12345)
			else
				addon:QUEST_REMOVED(nil, 12345)
				AssertEqual(addon.retiredQuestIds[12345].removalData.taskAnnouncementType, expectedType)
				addon:QUEST_REMOVED(nil, 12345)
				AssertEqual(addon.retiredQuestIds[12345].removalData.taskAnnouncementType, expectedType,
					"duplicate removal must retain the original capture")
				if latestValue == false then addon.worldClassification = true end
				if eventOrder == "remove_after_timer" then clock:Advance(0) end
				addon:QUEST_TURNED_IN(nil, 12345)
			end
			clock:Drain()
			AssertEqual(addon.announcements[#addon.announcements], expectedEvent)
		end
	end
end)

QuestTogether:RegisterTest("acceptance waits for readable quest data through the real event and scheduler path", function()
	local addon = NewQuestFixture()
	local index, row, reads = nil, nil, 0
	addon.API.GetQuestLogIndexForQuestID = function()
		reads = reads + 1
		return index
	end
	addon.API.GetQuestLogInfo = function() return row end
	addon:QUEST_ACCEPTED(nil, 12345)
	AssertEqual(reads, 0, "acceptance must not read before QUEST_LOG_UPDATE")
	addon:QUEST_LOG_UPDATE()
	AssertEqual(#addon.onQuestLogUpdate, 1, "unreadable index must retain one retry")
	AssertEqual(addon.pendingQuestAcceptances[12345] ~= nil, true)
	index = 1
	addon:QUEST_LOG_UPDATE()
	AssertEqual(#addon.onQuestLogUpdate, 1, "missing row must retain the acceptance")
	row = { questID = 99999, title = "Reused log slot" }
	addon:QUEST_LOG_UPDATE()
	AssertEqual(addon.tracker[12345], nil)
	for _, partialRow in ipairs({
		{ title = "Unreadable quest identity", isHeader = false },
		{ questID = 12345, title = "Zone header", isHeader = true },
		{ questID = 12345, isHeader = false },
		{ questID = 12345, title = "   ", isHeader = false },
	}) do
		row = partialRow
		addon:QUEST_LOG_UPDATE()
		AssertEqual(addon.tracker[12345], nil, "partial or header rows must not consume acceptance")
		AssertEqual(addon.pendingQuestAcceptances[12345] ~= nil, true)
		AssertEqual(#addon.onQuestLogUpdate, 1, "retain exactly one retry until a matching readable row arrives")
		AssertEqual(#addon.announcements, 0)
	end
	row = { questID = 12345, title = "Photo Quest" }
	addon:QUEST_LOG_UPDATE()
	AssertEqual(addon.tracker[12345].title, "Photo Quest")
	AssertEqual(addon.pendingQuestAcceptances[12345], nil)
	AssertEqual(#addon.onQuestLogUpdate, 0)
	AssertEqual(#addon.announcements, 1)
	addon:QUEST_LOG_UPDATE()
	AssertEqual(#addon.announcements, 1, "later updates must not duplicate acceptance")
end)

QuestTogether:RegisterTest("acceptance retries remain restricted until combat ends", function()
	local addon = NewQuestFixture()
	addon.combat = true
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:QUEST_LOG_UPDATE()
	AssertEqual(addon.tracker[12345], nil)
	addon.combat = false
	addon:PLAYER_REGEN_ENABLED()
	AssertEqual(addon.tracker[12345].title, "Photo Quest")
	AssertEqual(#addon.announcements, 1)
end)

QuestTogether:RegisterTest("removal cancels a transient acceptance retry without resurrecting it", function()
	local addon = NewQuestFixture()
	addon.API.GetQuestLogIndexForQuestID = function() return nil end
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:QUEST_LOG_UPDATE()
	AssertEqual(#addon.onQuestLogUpdate, 1)
	addon:QUEST_REMOVED(nil, 12345)
	addon.API.GetQuestLogIndexForQuestID = function() return 1 end
	addon:QUEST_LOG_UPDATE()
	AssertEqual(addon.tracker[12345], nil)
	AssertEqual(#addon.onQuestLogUpdate, 0)
	AssertEqual(#addon.announcements, 0)
end)

QuestTogether:RegisterTest("objective milestones do not replay after same-label progress rollback", function()
	local addon = NewQuestFixture()
	local quest = { objectives = { "80% Locations Photographed" }, objectiveValues = { 80 } }
	for _, value in ipairs({ 0, 20, 40, 60, 80, 0, 80 }) do
		AssertEqual(addon:UpdateTrackedObjectiveProgress(quest, 1, value .. "% Locations Photographed", value), false)
		AssertEqual(quest.objectiveValues[1], value, "current snapshot still follows live progress")
	end
	AssertEqual(addon:UpdateTrackedObjectiveProgress(quest, 1, "100% Locations Photographed", 100), true)
	AssertEqual(addon:UpdateTrackedObjectiveProgress(quest, 1, "100% Locations Photographed", 100), false)
end)

QuestTogether:RegisterTest("objective milestone identity includes target and survives temporary replacement", function()
	local addon = NewQuestFixture()
	local quest = { objectives = { "2/3 Gather Apples" }, objectiveValues = { 2 } }
	AssertEqual(addon:UpdateTrackedObjectiveProgress(quest, 1, "5/8 Rescue Villagers", 5), false)
	AssertEqual(addon:UpdateTrackedObjectiveProgress(quest, 1, "0/3 Gather Apples", 0), false)
	AssertEqual(addon:UpdateTrackedObjectiveProgress(quest, 1, "2/3 Gather Apples", 2), false)
	AssertEqual(addon:UpdateTrackedObjectiveProgress(quest, 1, "3/3 Gather Apples", 3), true)
	AssertEqual(addon:UpdateTrackedObjectiveProgress(quest, 1, "4/8 Gather Apples", 4), false)
end)

QuestTogether:RegisterTest("objective milestones survive an empty objective list", function()
	local addon = NewQuestFixture()
	addon:WatchQuest(12345, { title = "Photo Quest" })
	addon.objectiveCount = 0
	addon:UNIT_QUEST_LOG_CHANGED(nil, "player")
	addon:QUEST_LOG_UPDATE()
	AssertEqual(addon.tracker[12345].objectives[1], nil)
	addon.objectiveCount = 1
	addon.liveText, addon.liveValue = "0% Locations Photographed", 0
	addon:UNIT_QUEST_LOG_CHANGED(nil, "player")
	addon:QUEST_LOG_UPDATE()
	addon.liveText, addon.liveValue = "80% Locations Photographed", 80
	addon:UNIT_QUEST_LOG_CHANGED(nil, "player")
	addon:QUEST_LOG_UPDATE()
	AssertEqual(#addon.announcements, 0)
	addon.liveText, addon.liveValue = "100% Locations Photographed", 100
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 1, "new milestones still publish after recovery")
end)

QuestTogether:RegisterTest("objective recovery publishes new progress after unreadable rows and counts", function()
	for _, missingShape in ipairs({ "nil", "empty", "zero_count", "nil_count", "missing_value" }) do
		local addon = NewObjectiveProgressFixture()
		addon:WatchQuest(12345, { title = "Photo Quest" })
		AssertEqual(addon.tracker[12345].objectives[1], "80% Locations Photographed")
		if missingShape == "zero_count" then
			addon.objectiveCount = 0
		elseif missingShape == "nil_count" then
			addon.objectiveCount = nil
		elseif missingShape == "missing_value" then
			addon.liveValue = nil
		else
			addon.liveText = missingShape == "empty" and "" or nil
			addon.liveType, addon.liveValue = nil, nil
			addon.liveObjectiveValue = nil
		end
		ObserveObjectiveUpdate(addon)
		AssertEqual(#addon.announcements, 0, missingShape .. " must not invent progress")

		addon.objectiveCount = 1
		addon.liveText, addon.liveType, addon.liveValue = "Locations Photographed", "progressbar", 100
		ObserveObjectiveUpdate(addon)
		AssertEqual(#addon.announcements, 1, missingShape .. " must not consume the recovered milestone")
		AssertEqual(addon.announcements[1][1], "QUEST_PROGRESS")
		AssertEqual(addon.announcements[1][2], "100% Locations Photographed")
		ObserveObjectiveUpdate(addon)
		addon.liveValue = 80
		ObserveObjectiveUpdate(addon)
		addon.liveValue = 100
		ObserveObjectiveUpdate(addon)
		AssertEqual(#addon.announcements, 1, "recovery and rollback must not replay the milestone")
	end
end)

QuestTogether:RegisterTest("objective recovery retains the latest real stage through unreadable rows", function()
	local addon = NewObjectiveProgressFixture()
	addon.liveValue = 20
	addon:WatchQuest(12345, { title = "Photo Quest" })
	addon.liveValue = 40
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 1, "ordinary progress must still publish")

	addon.liveText, addon.liveValue = "Evidence Collected", 20
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 1, "a new stage establishes its own baseline")
	addon.liveText, addon.liveType, addon.liveValue = nil, nil, nil
	addon.liveObjectiveValue = nil
	ObserveObjectiveUpdate(addon)
	addon.liveText, addon.liveType, addon.liveValue = "Locations Photographed", "progressbar", 60
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 1, "returning to an older stage must not compare across the newer stage")
	addon.liveValue = 80
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 2)

	addon.liveText, addon.liveType, addon.liveValue = "2/3 Gather Apples", "monster", 2
	addon.liveObjectiveValue = 2
	ObserveObjectiveUpdate(addon)
	addon.objectiveCount = 0
	ObserveObjectiveUpdate(addon)
	addon.objectiveCount = 1
	addon.liveText, addon.liveValue = "4/8 Gather Apples", 4
	addon.liveObjectiveValue = 4
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 2, "a changed target is a new stage even after a missing row")
	addon.liveText, addon.liveValue = "5/8 Gather Apples", 5
	addon.liveObjectiveValue = 5
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 3)
end)

QuestTogether:RegisterTest("unavailable progress percent does not use the independent objective counter", function()
	for _, rawCounter in ipairs({ 0, 80 }) do
		local addon = NewObjectiveProgressFixture()
		addon.liveObjectiveValue = rawCounter
		addon:WatchQuest(12345, { title = "Photo Quest" })
		addon.liveValue = nil
		local text, objectiveType, _, progress = addon:GetNormalizedQuestObjectiveInfo(12345, 1, false)
		AssertEqual(text, "Locations Photographed")
		AssertEqual(objectiveType, "progressbar")
		AssertEqual(progress, nil, "numFulfilled is not a substitute for an unavailable percentage")
		ObserveObjectiveUpdate(addon)
		AssertEqual(#addon.announcements, 0)
		addon.liveValue = 100
		ObserveObjectiveUpdate(addon)
		AssertEqual(#addon.announcements, 1)
		AssertEqual(addon.announcements[1][2], "100% Locations Photographed")
		ObserveObjectiveUpdate(addon)
		AssertEqual(#addon.announcements, 1, "the recovered milestone must not replay")
	end
end)

QuestTogether:RegisterTest("a readable new objective label blocks recovery across stages without a numeric value", function()
	for _, unreadableValue in ipairs({ false, "unavailable" }) do
		local addon = NewObjectiveProgressFixture()
		addon:WatchQuest(12345, { title = "Photo Quest" })
		addon.liveText = "Evidence Collected"
		addon.liveValue = unreadableValue or nil
		ObserveObjectiveUpdate(addon)
		AssertEqual(addon.tracker[12345].objectives[1], "Evidence Collected")
		addon.liveText, addon.liveType, addon.liveValue = nil, nil, nil
		addon.liveObjectiveValue = nil
		ObserveObjectiveUpdate(addon)
		addon.liveText, addon.liveType, addon.liveValue = "Locations Photographed", "progressbar", 100
		ObserveObjectiveUpdate(addon)
		AssertEqual(#addon.announcements, 0, "a readable intervening label must invalidate the older stage comparison")
		addon.liveText, addon.liveValue = "Evidence Collected", 20
		ObserveObjectiveUpdate(addon)
		addon.liveValue = 40
		ObserveObjectiveUpdate(addon)
		AssertEqual(#addon.announcements, 1, "progress within the new stage still publishes")
		AssertEqual(addon.announcements[1][2], "40% Evidence Collected")
	end
end)

QuestTogether:RegisterTest("objective recovery history survives a scan but resets on reacceptance", function()
	local addon = NewObjectiveProgressFixture()
	addon:WatchQuest(12345, { title = "Photo Quest" })
	addon.objectiveCount = 0
	ObserveObjectiveUpdate(addon)
	addon:WatchQuest(12345, { title = "Photo Quest" })
	addon.objectiveCount, addon.liveValue = 1, 100
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 1, "rescan must retain the unreadable row's baseline")

	addon:QUEST_REMOVED(nil, 12345)
	addon.delayed[1]()
	addon.liveValue = 20
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:QUEST_LOG_UPDATE()
	addon.liveValue = 100
	ObserveObjectiveUpdate(addon)
	AssertEqual(#addon.announcements, 4, "new acceptance owns a fresh milestone history")
	AssertEqual(addon.announcements[4][1], "QUEST_PROGRESS")
	AssertEqual(addon.announcements[4][2], "100% Locations Photographed")
end)

QuestTogether:RegisterTest("quest removal invalidates acceptance queued before the log update", function()
	local addon = NewQuestFixture()
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:QUEST_REMOVED(nil, 12345)
	addon:DrainQueuedQuestLogTasks()
	AssertEqual(addon.tracker[12345], nil)
	AssertEqual(#addon.announcements, 0)
end)

QuestTogether:RegisterTest("stale removal timer cannot remove a newly accepted repeatable quest", function()
	local addon = NewQuestFixture()
	addon:WatchQuest(12345, { title = "Photo Quest" })
	addon:QUEST_REMOVED(nil, 12345)
	local oldTimer = addon.delayed[1]
	addon:QUEST_ACCEPTED(nil, 12345)
	addon:DrainQueuedQuestLogTasks()
	addon:QUEST_REMOVED(nil, 12345)
	local newRemoval = addon.pendingQuestRemovals[12345]
	oldTimer()
	AssertEqual(addon.pendingQuestRemovals[12345], newRemoval)
	AssertEqual(addon.tracker[12345] ~= nil, true)
	addon.delayed[2]()
	AssertEqual(addon.tracker[12345], nil)
end)

QuestTogether:RegisterTest("turn-in suppresses queued progress even while quest-log rows remain", function()
	local addon = NewQuestFixture()
	addon.liveText, addon.liveValue = "20% Locations Photographed", 20
	addon:WatchQuest(12345, { title = "Photo Quest" })
	addon:UNIT_QUEST_LOG_CHANGED(nil, "player")
	addon:QUEST_TURNED_IN(nil, 12345)
	addon.liveText, addon.liveValue = "80% Locations Photographed", 80
	addon:DrainQueuedQuestLogTasks()
	AssertEqual(#addon.announcements, 0)
end)

QuestTogether:RegisterTest("late quest turn-in still publishes completion once after removal timer", function()
	local addon = NewQuestFixture()
	addon:WatchQuest(12345, { title = "Photo Quest" })
	addon:QUEST_REMOVED(nil, 12345)
	addon.delayed[1]()
	AssertEqual(addon.announcements[1][1], "QUEST_REMOVED")
	addon:QUEST_TURNED_IN(nil, 12345)
	addon:QUEST_TURNED_IN(nil, 12345)
	AssertEqual(#addon.announcements, 2)
	AssertEqual(addon.announcements[2][1], "QUEST_COMPLETED")
	AssertEqual(addon.announcements[2][2], "Photo Quest")
end)

QuestTogether:RegisterTest("turn-in completes unreadable pending acceptance in either removal order exactly once", function()
	for _, removalFirst in ipairs({ false, true }) do
		local addon = NewObjectiveProgressFixture()
		addon.API.GetQuestLogIndexForQuestID = function() return nil end
		addon:QUEST_ACCEPTED(nil, 12345)
		addon:QUEST_LOG_UPDATE()
		AssertEqual(addon.tracker[12345], nil)
		AssertEqual(#addon.onQuestLogUpdate, 1, "acceptance is still waiting for readable data")
		if removalFirst then addon:QUEST_REMOVED(nil, 12345) end
		addon:QUEST_TURNED_IN(nil, 12345)
		if not removalFirst then addon:QUEST_REMOVED(nil, 12345) end
		addon:QUEST_TURNED_IN(nil, 12345)
		addon:QUEST_REMOVED(nil, 12345)
		addon:QUEST_LOG_UPDATE()
		AssertEqual(#addon.announcements, 1)
		AssertEqual(addon.announcements[1][1], "QUEST_COMPLETED")
		AssertEqual(addon.announcements[1][2], "Photo Quest")
		AssertEqual(addon.questsCompleted[12345], nil)
		AssertEqual(addon.pendingQuestRemovals[12345], nil)
		AssertEqual(addon.pendingQuestAcceptances[12345], nil)
		AssertEqual(addon.tracker[12345], nil)
		AssertEqual(#addon.onQuestLogUpdate, 0)

		addon.API.GetQuestLogIndexForQuestID = function() return 1 end
		addon:QUEST_ACCEPTED(nil, 12345)
		addon:QUEST_LOG_UPDATE()
		AssertEqual(addon.tracker[12345] ~= nil, true, "reacceptance starts a fresh quest lifetime")
		addon:QUEST_TURNED_IN(nil, 12345)
		addon:QUEST_REMOVED(nil, 12345)
		for _, callback in ipairs(addon.delayed) do callback() end
		AssertEqual(#addon.announcements, 3)
		AssertEqual(addon.announcements[2][1], "QUEST_ACCEPTED")
		AssertEqual(addon.announcements[3][1], "QUEST_COMPLETED")
	end
end)

QuestTogether:RegisterTest("untracked turn-in uses an unknown-title fallback and ignores duplicate events", function()
	local addon = NewQuestFixture()
	addon.GetQuestTitle = function() return nil end
	-- Title and task classification are stubbed in this handler-only fixture.
	-- These tripwires cover direct log/index reads, not lower-level metadata APIs.
	addon.API.GetQuestLogInfo = function() error("turn-in must not add quest log reads") end
	addon.API.GetQuestLogIndexForQuestID = function() error("turn-in must not add quest index reads") end
	addon:QUEST_TURNED_IN(nil, 54321)
	addon:QUEST_REMOVED(nil, 54321)
	addon:QUEST_TURNED_IN(nil, 54321)
	AssertEqual(#addon.announcements, 1)
	AssertEqual(addon.announcements[1][1], "QUEST_COMPLETED")
	AssertEqual(addon.announcements[1][2], "Quest 54321")
	AssertEqual(addon.questsCompleted[54321], nil)
	AssertEqual(addon.retiredQuestIds[54321].completionAnnounced, true)
end)

QuestTogether:RegisterTest("completed area quest clears active state before restricted refresh", function()
	local addon = NewQuestFixture()
	addon:WatchQuest(12345, { title = "Photo Quest" })
	addon.area.world[12345] = "Photo Quest"
	addon:QUEST_TURNED_IN(nil, 12345)
	addon:QUEST_REMOVED(nil, 12345)
	addon.delayed[1]()
	AssertEqual(addon.area.world[12345], nil)
	AssertEqual(addon.questsCompleted[12345], nil)
end)

QuestTogether:RegisterTest("failed quest-log callback does not lose later queued callbacks", function()
	local addon = NewQuestFixture()
	local executed = false
	addon:QueueQuestLogTask(function()
		error("simulated transient quest API failure")
	end)
	addon:QueueQuestLogTask(function()
		executed = true
	end)
	AssertEqual(addon:DrainQueuedQuestLogTasks(), 2)
	AssertEqual(executed, true)
end)

QuestTogether:RegisterTest("entering world clears logout and stale area announcement intent", function()
	local addon = NewQuestFixture()
	addon.isEnabled = false
	addon.isLoggingOut = true
	addon.pendingAnnounce = true
	function addon:SetRuntimeFlag(name, value)
		AssertEqual(name, "pendingScheduledTaskAreaRefreshShouldAnnounce")
		self.pendingAnnounce = value
	end
	function addon:RefreshTaskAreaStates(announce)
		AssertEqual(announce, false)
		AssertEqual(self.pendingAnnounce, false)
	end
	addon:PLAYER_ENTERING_WORLD()
	AssertEqual(addon.isLoggingOut, false)
end)

local function NewTaskAreaFixture()
	local addon = NewQuestFixture()
	addon.resolver = { resolvedByQuestID = {}, resolutionOrder = {}, generation = 0,
		displayAsObjectiveByQuestID = {}, isWorldQuestByQuestID = {} }
	addon.debugCount = 0
	addon.API.GetNumQuestLogEntries = function()
		return 1
	end
	addon.API.GetQuestLogInfo = function()
		return { questID = 12345, title = "Photo Quest", isTask = true, isWorldQuest = true, isOnMap = true }
	end
	function addon:Debugf()
		self.debugCount = self.debugCount + 1
	end
	function addon:EnsureQuestSnapshotStore() end
	function addon:GetQuestSnapshotByQuestID()
		return {}
	end
	function addon:GetTaskAreaSubsystemStateStore()
		return self.resolver
	end
	function addon:IsWorldQuest()
		return true
	end
	return addon
end

QuestTogether:RegisterTest("task area ignores retired quest rows and logs only changed scans", function()
	local addon = NewTaskAreaFixture()
	addon:RebuildTaskAreaResolverStore()
	AssertEqual(addon.resolver.resolvedByQuestID[12345].includeWorld, true)
	local firstDebugCount = addon.debugCount
	addon:RebuildTaskAreaResolverStore()
	AssertEqual(addon.debugCount, firstDebugCount)
	addon.retiredQuestIds[12345] = {}
	addon:RebuildTaskAreaResolverStore()
	AssertEqual(addon.resolver.resolvedByQuestID[12345], nil)
end)

QuestTogether:RegisterTest("failed task area scan preserves last complete resolver snapshot", function()
	local addon = NewTaskAreaFixture()
	addon:RebuildTaskAreaResolverStore()
	local previousResolved = addon.resolver.resolvedByQuestID
	addon.API.GetQuestLogInfo = function()
		error("simulated quest read failure")
	end
	local _, rebuilt = addon:RebuildTaskAreaResolverStore()
	AssertEqual(rebuilt, false)
	AssertEqual(addon.resolver.resolvedByQuestID, previousResolved)
	AssertEqual(addon.resolver.resolvedByQuestID[12345].includeWorld, true)
end)

QuestTogether:RegisterTest(
	"unknown task area count preserves active state and pending announcements without retry loop",
	function()
		local addon = NewTaskAreaFixture()
		addon:RebuildTaskAreaResolverStore()
		addon.area.world[12345] = "Photo Quest"
		addon.flags = {}
		addon.RefreshTaskAreaStates = QuestTogether.RefreshTaskAreaStates
		function addon:IsWorkBlocked()
			return false
		end
		function addon:GetRuntimeFlag(key, fallback)
			local value = self.flags[key]
			if value == nil then
				return fallback
			end
			return value
		end
		function addon:SetRuntimeFlag(key, value)
			self.flags[key] = value
		end
		function addon:ScheduleTaskAreaRefresh()
			error("unreadable data must wait for a normal event")
		end
		addon.API.GetNumQuestLogEntries = function()
			return nil
		end
		AssertEqual(addon:RefreshTaskAreaStates(true), false)
		AssertEqual(addon.area.world[12345], "Photo Quest")
		AssertEqual(#addon.announcements, 0)
		AssertEqual(addon.flags.pendingScheduledTaskAreaRefreshShouldAnnounce, true)
		-- A confirmed empty log is authoritative and consumes the pending intent.
		addon.API.GetNumQuestLogEntries = function()
			return 0
		end
		AssertEqual(addon:RefreshTaskAreaStates(false), true)
		AssertEqual(addon.area.world[12345], nil)
		AssertEqual(#addon.announcements, 1)
		AssertEqual(addon.announcements[1][1], "WORLD_QUEST_LEFT")
		AssertEqual(addon.flags.pendingScheduledTaskAreaRefreshShouldAnnounce, false)
	end
)

QuestTogether:RegisterTest("incomplete task area row preserves the last complete resolver", function()
	local addon = NewTaskAreaFixture()
	addon:RebuildTaskAreaResolverStore()
	local previousResolved = addon.resolver.resolvedByQuestID
	local previousGeneration = addon.resolver.generation
	addon.API.GetQuestLogInfo = function()
		return { title = "Unloaded quest", isHeader = false }
	end
	local _, rebuilt = addon:RebuildTaskAreaResolverStore()
	AssertEqual(rebuilt, false)
	AssertEqual(addon.resolver.resolvedByQuestID, previousResolved)
	AssertEqual(addon.resolver.generation, previousGeneration)
	addon.API.GetQuestLogInfo = function()
		return nil
	end
	_, rebuilt = addon:RebuildTaskAreaResolverStore()
	AssertEqual(rebuilt, false)
	AssertEqual(addon.resolver.resolvedByQuestID, previousResolved)
end)

local function NewAreaLocationFixture(taskType)
	local addon, clock = NewTaskLifecycleFixture(taskType)
	addon:AddQuest(false)
	addon.rows[2].hasLocalPOI = false
	function addon:ObserveLocationChange()
		self:RefreshSnapshot()
		self:QUEST_POI_UPDATE()
		clock:Drain()
	end
	function addon:CountAreaAnnouncements(suffix)
		local event = (taskType == "world" and "WORLD_QUEST_" or "BONUS_OBJECTIVE_") .. suffix
		local count = 0
		for _, announced in ipairs(self.announcements) do if announced == event then count = count + 1 end end
		return count
	end
	addon:RebuildQuestSnapshotStore()
	AssertEqual(addon:RefreshTaskAreaStates(false), true)
	return addon, clock
end

QuestTogether:RegisterTest("unknown location fields retain task areas through scheduled snapshot and area refreshes", function()
	for _, taskType in ipairs({ "world", "bonus" }) do
		local fields = taskType == "world" and { "isOnMap" } or { "isOnMap", "hasLocalPOI" }
		for _, field in ipairs(fields) do
			local addon = NewAreaLocationFixture(taskType)
			local row = addon.rows[2]
			row.isOnMap, row.hasLocalPOI = false, false
			row[field] = true
			addon:ObserveLocationChange()
			AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], "New Task")
			for _, unreadable in ipairs({ "missing", "invalid" }) do
				row[field] = unreadable == "invalid" and "unavailable" or nil
				addon:ObserveLocationChange()
				AssertEqual(addon:GetQuestSnapshot(12345)[field], nil, "snapshot must preserve unknown " .. field)
				AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], "New Task", taskType .. "/" .. field)
				AssertEqual(addon:CountAreaAnnouncements("LEFT"), 0)
				row[field] = true
				addon:ObserveLocationChange()
				AssertEqual(addon:CountAreaAnnouncements("ENTERED"), 0, "recovery must not replay entry")
			end
			row[field] = false
			addon:ObserveLocationChange()
			AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], nil, "explicit false must still exit")
			AssertEqual(addon:CountAreaAnnouncements("LEFT"), 1)
			row[field] = nil
			addon:ObserveLocationChange()
			AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], nil, "unknown must not undo a confirmed exit")
			row[field] = true
			addon:ObserveLocationChange()
			AssertEqual(addon:CountAreaAnnouncements("ENTERED"), 1, "real later entry still announces")
		end
	end
end)

QuestTogether:RegisterTest("unknown location starts inactive and readable bonus flags independently establish area presence", function()
	for _, taskType in ipairs({ "world", "bonus" }) do
		local addon = NewAreaLocationFixture(taskType)
		addon:ResetTaskAreaStateStore()
		addon.rows[2].isOnMap, addon.rows[2].hasLocalPOI = nil, nil
		addon:ObserveLocationChange()
		AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], nil)
		AssertEqual(addon:CountAreaAnnouncements("ENTERED"), 0)
		addon.rows[2].hasLocalPOI = true
		addon:ObserveLocationChange()
		AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], taskType == "bonus" and "New Task" or nil)
		addon.rows[2].isOnMap = true
		addon:ObserveLocationChange()
		AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], "New Task")
		AssertEqual(addon:CountAreaAnnouncements("ENTERED"), 1)
	end
end)

QuestTogether:RegisterTest("task area location retention ends on removal acceptance and state reset", function()
	for _, taskType in ipairs({ "world", "bonus" }) do
		for _, boundary in ipairs({ "removal", "snapshot_removal", "acceptance", "reset" }) do
			local addon, clock = NewAreaLocationFixture(taskType)
			local row = addon.rows[2]
			row.isOnMap, row.hasLocalPOI = nil, nil
			if boundary == "removal" then
				addon.rows[2] = nil
				addon:QUEST_REMOVED(nil, 12345)
				clock:Drain()
				addon:ObserveLocationChange()
				AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], nil)
				addon.rows[2] = row
				addon:QUEST_ACCEPTED(nil, 12345)
			elseif boundary == "snapshot_removal" then
				addon.rows[2] = nil
				addon:RefreshSnapshot()
				addon.rows[2] = row
			elseif boundary == "acceptance" then
				addon:QUEST_ACCEPTED(nil, 12345)
			else
				addon:ResetTaskAreaStateStore()
			end
			addon:QUEST_LOG_UPDATE()
			clock:Drain()
			addon:ObserveLocationChange()
			AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], nil, taskType .. "/" .. boundary)
			AssertEqual(addon:CountAreaAnnouncements("ENTERED"), 0, "new lifetime must not inherit old location")
			row.isOnMap = true
			addon:ObserveLocationChange()
			AssertEqual(addon:CountAreaAnnouncements("ENTERED"), 1)
		end
	end
end)

QuestTogether:RegisterTest("duplicate acceptance preserves watched task area observations while metadata is unavailable", function()
	for _, taskType in ipairs({ "world", "bonus" }) do
		local addon, clock = NewAreaLocationFixture(taskType)
		addon:WatchQuest(12345, addon.rows[2])
		local tracked = addon.tracker[12345]
		addon.rows[2].isOnMap, addon.rows[2].hasLocalPOI = nil, nil
		addon.worldClassification, addon.bonusClassification = nil, nil
		addon:QUEST_ACCEPTED(nil, 12345)
		addon:QUEST_LOG_UPDATE()
		clock:Drain()
		addon:ObserveLocationChange()
		AssertEqual(addon.tracker[12345], tracked, "duplicate acceptance keeps the existing tracker")
		AssertEqual(addon:GetTaskAreaStateStore(taskType)[12345], "New Task")
		AssertEqual(addon:CountAreaAnnouncements("LEFT"), 0)
		addon.rows[2].isOnMap = true
		addon:ObserveLocationChange()
		AssertEqual(addon:CountAreaAnnouncements("ENTERED"), 0, "recovery must not replay entry after duplicate acceptance")
	end
end)
