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
		tracker = {},
		onQuestLogUpdate = {},
		pendingQuestRemovals = {},
		pendingQuestAcceptances = {},
		questsCompleted = {},
		retiredQuestIds = {},
		delayed = {},
		announcements = {},
		area = { world = {}, bonus = {} },
		liveText = "80% Locations Photographed",
		liveValue = 80,
		objectiveCount = 1,
	}, { __index = QuestTogether })
	addon.API = {
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
	function addon:QueueQuestLogTask(callback)
		self.onQuestLogUpdate[#self.onQuestLogUpdate + 1] = callback
	end
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
	addon:DrainQueuedQuestLogTasks()
	AssertEqual(addon.tracker[12345].objectives[1], nil)
	addon.objectiveCount = 1
	addon.liveText, addon.liveValue = "0% Locations Photographed", 0
	addon:UNIT_QUEST_LOG_CHANGED(nil, "player")
	addon:DrainQueuedQuestLogTasks()
	addon.liveText, addon.liveValue = "80% Locations Photographed", 80
	addon:UNIT_QUEST_LOG_CHANGED(nil, "player")
	addon:DrainQueuedQuestLogTasks()
	AssertEqual(#addon.announcements, 0)
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
	addon.resolver = { resolvedByQuestID = {}, resolutionOrder = {}, generation = 0 }
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
