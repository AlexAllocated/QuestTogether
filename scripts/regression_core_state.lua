-- Private-fixture regressions for quest snapshots, observation lifetimes, and
-- waypoint work. No Blizzard globals or shared UI/API tables are replaced.
local QT = _G.QuestTogether
local function Equal(actual, expected, message)
	assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function Noop() end

local function NewFixture()
	local addon = setmetatable({
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
