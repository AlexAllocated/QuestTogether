local QuestTogether = _G.QuestTogether
local LibChev = QuestTogether.LibChev

-- This is transient per-instance state, never a SavedVariables migration.
-- Visual handles survive domain resets until restricted teardown can finish.
function QuestTogether:NewRuntimeStateStore()
	local weak = LibChev.WeakKeys
	local state = {
		taskArea = {
			worldByQuestID = {},
			bonusByQuestID = {},
			resolvedByQuestID = {},
			resolutionOrder = {},
			generation = 0,
			pendingAnnounce = false,
		},
		questSnapshot = { byQuestID = {}, order = {}, generation = 0 },
		nameplate = {
			questStateByGuid = {},
			completedByNpcID = {},
			questStateByUnitToken = {},
			questGuidByUnitToken = {},
			textCache = {},
			identityGenerationByUnitToken = {},
			refreshGenerationByUnitToken = {},
			refreshPendingByUnitToken = {},
			healthTintRefreshPendingByUnitToken = {},
			tooltipResolveRetryCountByUnitToken = {},
			workOwnersByUnitToken = {},
			iconByUnitFrame = weak(),
			healthOverlayByUnitFrame = weak(),
			bubbleByUnitFrame = weak(),
			bubbleStateByFrame = weak(),
		},
		personalBubble = { dialogPositionByFrame = weak() },
		runtime = {
			pendingScheduledTaskAreaRefreshShouldAnnounce = false,
			pendingDeferredNameplateQuestStateRefresh = false,
			deferredNameplateQuestStateRefreshGeneration = 0,
			nameplateFullRefreshGeneration = 0,
			deferredWorkState = LibChev.NewWorkState(),
		},
	}
	return state
end

function QuestTogether:EnsureRuntimeStateStore()
	local state = rawget(self, "runtimeStateStore")
	if not state then
		state = self:NewRuntimeStateStore()
		self.runtimeStateStore = state
	end
	return state
end

function QuestTogether:GetTaskAreaStateStore(taskType)
	local state = self:EnsureRuntimeStateStore()
	if taskType == "bonus" then
		return state.taskArea.bonusByQuestID
	end
	return state.taskArea.worldByQuestID
end

function QuestTogether:GetTaskAreaSubsystemStateStore()
	return self:EnsureRuntimeStateStore().taskArea
end

function QuestTogether:GetTaskAreaResolverStore()
	return self:GetTaskAreaSubsystemStateStore().resolvedByQuestID
end

function QuestTogether:GetTaskAreaResolution(questID)
	local numericQuestID = self.NormalizeQuestID and self:NormalizeQuestID(questID) or nil
	if not numericQuestID then
		return nil
	end
	return self:GetTaskAreaResolverStore()[numericQuestID]
end

function QuestTogether:GetQuestSnapshotStateStore()
	return self:EnsureRuntimeStateStore().questSnapshot
end

function QuestTogether:GetQuestSnapshotByQuestID()
	return self:GetQuestSnapshotStateStore().byQuestID
end

function QuestTogether:GetQuestSnapshotOrder()
	return self:GetQuestSnapshotStateStore().order
end

function QuestTogether:GetQuestSnapshot(questID)
	local numericQuestID = self.NormalizeQuestID and self:NormalizeQuestID(questID) or nil
	if not numericQuestID then
		return nil
	end
	return self:GetQuestSnapshotByQuestID()[numericQuestID]
end

function QuestTogether:ResetQuestSnapshotStateStore()
	local state = self:GetQuestSnapshotStateStore()
	wipe(state.byQuestID)
	wipe(state.order)
	self:ResetQuestClassifications()
	state.generation = 0
	return state
end

function QuestTogether:ResetTaskAreaStateStore()
	local state = self:EnsureRuntimeStateStore()
	wipe(state.taskArea.worldByQuestID)
	wipe(state.taskArea.bonusByQuestID)
	wipe(state.taskArea.resolvedByQuestID)
	wipe(state.taskArea.resolutionOrder)
	self:ResetQuestClassifications()
	state.taskArea.generation = 0
	state.taskArea.pendingAnnounce = false
	return state.taskArea
end

function QuestTogether:GetNameplateStateStore()
	return self:EnsureRuntimeStateStore().nameplate
end

-- Visual handles survive cache resets so restricted teardown can finish later.
function QuestTogether:ResetNameplateStateStore()
	local state = self:EnsureRuntimeStateStore()
	wipe(state.nameplate.questStateByGuid)
	wipe(state.nameplate.completedByNpcID)
	wipe(state.nameplate.questStateByUnitToken)
	wipe(state.nameplate.questGuidByUnitToken)
	wipe(state.nameplate.textCache)
	for _, owner in pairs(state.nameplate.workOwnersByUnitToken or {}) do
		self:CancelRuntimeWorkOwner(owner)
	end
	state.nameplate.workOwnersByUnitToken = {}
	state.nameplate.identityGenerationByUnitToken = {}
	state.nameplate.refreshGenerationByUnitToken = {}
	wipe(state.nameplate.refreshPendingByUnitToken)
	wipe(state.nameplate.healthTintRefreshPendingByUnitToken)
	wipe(state.nameplate.tooltipResolveRetryCountByUnitToken)

	return state.nameplate
end

function QuestTogether:GetPersonalBubbleStateStore()
	return self:EnsureRuntimeStateStore().personalBubble
end

function QuestTogether:GetRuntimeWorkStateStore()
	return self:EnsureRuntimeStateStore().runtime
end

function QuestTogether:GetDeferredWorkStateStore()
	return self:GetRuntimeWorkStateStore().deferredWorkState
end

function QuestTogether:GetRuntimeFlag(key, fallback)
	local runtimeState = self:GetRuntimeWorkStateStore()
	local value = runtimeState[key]
	if value == nil then
		return fallback
	end
	return value
end

function QuestTogether:SetRuntimeFlag(key, value)
	local runtimeState = self:GetRuntimeWorkStateStore()
	runtimeState[key] = value
	return value
end

function QuestTogether:SetPendingWaypointIntent(intent)
	local runtimeState = self:GetRuntimeWorkStateStore()
	if type(intent) == "table" then
		runtimeState.pendingWaypointIntent = intent
	else
		runtimeState.pendingWaypointIntent = nil
	end
	return runtimeState.pendingWaypointIntent
end

function QuestTogether:ResetRuntimeWorkStateStore()
	if self.StopMapWorkWakeup then
		self:StopMapWorkWakeup()
	end
	local runtimeState = self:GetRuntimeWorkStateStore()
	runtimeState.pendingWaypointIntent = nil
	runtimeState.pendingQuestLogScan = false
	runtimeState.questTrackerReady = false
	runtimeState.pendingScheduledTaskAreaRefreshShouldAnnounce = false
	runtimeState.pendingDeferredNameplateQuestStateRefresh = false
	runtimeState.deferredNameplateQuestStateRefreshGeneration = 0
	runtimeState.nameplateFullRefreshGeneration = 0
	runtimeState.deferredWorkState = LibChev.NewWorkState()

	return runtimeState
end

QuestTogether:EnsureRuntimeStateStore()
