local QuestTogether = _G.QuestTogether

local function NewWeakKeyTable()
	return setmetatable({}, { __mode = "k" })
end

local function EnsureWeakKeyTable(value)
	if type(value) == "table" then
		return value
	end
	return NewWeakKeyTable()
end

local function BindRuntimeReferenceAliases(self, state)
	self.worldQuestAreaStateByQuestID = state.taskArea.worldByQuestID
	self.bonusObjectiveAreaStateByQuestID = state.taskArea.bonusByQuestID
	self.questSnapshotByQuestID = state.questSnapshot.byQuestID
	self.questSnapshotOrder = state.questSnapshot.order

	self.nameplateQuestTextCache = state.nameplate.textCache
	self.nameplateQuestStateByGuid = state.nameplate.questStateByGuid
	self.nameplateQuestStateByUnitToken = state.nameplate.questStateByUnitToken
	self.nameplateQuestGuidByUnitToken = state.nameplate.questGuidByUnitToken
	self.nameplateIconByUnitFrame = state.nameplate.iconByUnitFrame
	self.nameplateHealthOverlayByUnitFrame = state.nameplate.healthOverlayByUnitFrame
	self.nameplateBubbleByUnitFrame = state.nameplate.bubbleByUnitFrame
	self.nameplateBubbleStateByFrame = state.nameplate.bubbleStateByFrame
	self.nameplateRefreshPendingByUnitToken = state.nameplate.refreshPendingByUnitToken
	self.nameplateRefreshGenerationByUnitToken = state.nameplate.refreshGenerationByUnitToken
	self.nameplateHealthTintRefreshPendingByUnitToken = state.nameplate.healthTintRefreshPendingByUnitToken
	self.nameplateTooltipResolveRetryCountByUnitToken = state.nameplate.tooltipResolveRetryCountByUnitToken

	self.personalBubbleSliderHandlesByFrame = state.personalBubble.sliderHandlesByFrame
	self.personalBubbleDialogPositionByFrame = state.personalBubble.dialogPositionByFrame

	self.deferredWorkState = state.runtime.deferredWorkState
end

function QuestTogether:EnsureRuntimeStateStore()
	local state = self.runtimeStateStore
	if type(state) ~= "table" then
		state = {}
		self.runtimeStateStore = state
	end

	if type(state.taskArea) ~= "table" then
		state.taskArea = {}
	end
	if type(state.taskArea.worldByQuestID) ~= "table" then
		state.taskArea.worldByQuestID = type(self.worldQuestAreaStateByQuestID) == "table"
				and self.worldQuestAreaStateByQuestID
			or {}
	end
	if type(state.taskArea.bonusByQuestID) ~= "table" then
		state.taskArea.bonusByQuestID = type(self.bonusObjectiveAreaStateByQuestID) == "table"
				and self.bonusObjectiveAreaStateByQuestID
			or {}
	end
	if type(state.taskArea.resolvedByQuestID) ~= "table" then
		state.taskArea.resolvedByQuestID = {}
	end
	if type(state.taskArea.resolutionOrder) ~= "table" then
		state.taskArea.resolutionOrder = {}
	end
	if type(state.taskArea.generation) ~= "number" then
		state.taskArea.generation = 0
	end
	if state.taskArea.pendingAnnounce ~= true then
		state.taskArea.pendingAnnounce = false
	end

	if type(state.questSnapshot) ~= "table" then
		state.questSnapshot = {}
	end
	if type(state.questSnapshot.byQuestID) ~= "table" then
		state.questSnapshot.byQuestID = type(self.questSnapshotByQuestID) == "table" and self.questSnapshotByQuestID
			or {}
	end
	if type(state.questSnapshot.order) ~= "table" then
		state.questSnapshot.order = type(self.questSnapshotOrder) == "table" and self.questSnapshotOrder or {}
	end
	if type(state.questSnapshot.generation) ~= "number" then
		state.questSnapshot.generation = 0
	end

	if type(state.nameplate) ~= "table" then
		state.nameplate = {}
	end
	if type(state.nameplate.questStateByGuid) ~= "table" then
		state.nameplate.questStateByGuid = type(self.nameplateQuestStateByGuid) == "table"
				and self.nameplateQuestStateByGuid
			or {}
	end
	if type(state.nameplate.questStateByUnitToken) ~= "table" then
		state.nameplate.questStateByUnitToken = type(self.nameplateQuestStateByUnitToken) == "table"
				and self.nameplateQuestStateByUnitToken
			or {}
	end
	if type(state.nameplate.questGuidByUnitToken) ~= "table" then
		state.nameplate.questGuidByUnitToken = type(self.nameplateQuestGuidByUnitToken) == "table"
				and self.nameplateQuestGuidByUnitToken
			or {}
	end
	if type(state.nameplate.textCache) ~= "table" then
		state.nameplate.textCache = type(self.nameplateQuestTextCache) == "table" and self.nameplateQuestTextCache or {}
	end
	if type(state.nameplate.refreshGenerationByUnitToken) ~= "table" then
		state.nameplate.refreshGenerationByUnitToken = type(self.nameplateRefreshGenerationByUnitToken) == "table"
				and self.nameplateRefreshGenerationByUnitToken
			or {}
	end
	if type(state.nameplate.refreshPendingByUnitToken) ~= "table" then
		state.nameplate.refreshPendingByUnitToken = type(self.nameplateRefreshPendingByUnitToken) == "table"
				and self.nameplateRefreshPendingByUnitToken
			or {}
	end
	if type(state.nameplate.healthTintRefreshPendingByUnitToken) ~= "table" then
		state.nameplate.healthTintRefreshPendingByUnitToken = type(self.nameplateHealthTintRefreshPendingByUnitToken)
					== "table"
				and self.nameplateHealthTintRefreshPendingByUnitToken
			or {}
	end
	if type(state.nameplate.tooltipResolveRetryCountByUnitToken) ~= "table" then
		state.nameplate.tooltipResolveRetryCountByUnitToken = type(self.nameplateTooltipResolveRetryCountByUnitToken)
					== "table"
				and self.nameplateTooltipResolveRetryCountByUnitToken
			or {}
	end
	if type(state.nameplate.iconByUnitFrame) ~= "table" then
		state.nameplate.iconByUnitFrame = EnsureWeakKeyTable(self.nameplateIconByUnitFrame)
	end
	if type(state.nameplate.healthOverlayByUnitFrame) ~= "table" then
		state.nameplate.healthOverlayByUnitFrame = EnsureWeakKeyTable(self.nameplateHealthOverlayByUnitFrame)
	end
	if type(state.nameplate.bubbleByUnitFrame) ~= "table" then
		state.nameplate.bubbleByUnitFrame = EnsureWeakKeyTable(self.nameplateBubbleByUnitFrame)
	end
	if type(state.nameplate.bubbleStateByFrame) ~= "table" then
		state.nameplate.bubbleStateByFrame = EnsureWeakKeyTable(self.nameplateBubbleStateByFrame)
	end

	if type(state.personalBubble) ~= "table" then
		state.personalBubble = {}
	end
	if type(state.personalBubble.sliderHandlesByFrame) ~= "table" then
		state.personalBubble.sliderHandlesByFrame = EnsureWeakKeyTable(self.personalBubbleSliderHandlesByFrame)
	end
	if type(state.personalBubble.dialogPositionByFrame) ~= "table" then
		state.personalBubble.dialogPositionByFrame = EnsureWeakKeyTable(self.personalBubbleDialogPositionByFrame)
	end

	if type(state.runtime) ~= "table" then
		state.runtime = {}
	end
	if state.runtime.pendingScheduledTaskAreaRefreshShouldAnnounce ~= true then
		state.runtime.pendingScheduledTaskAreaRefreshShouldAnnounce = false
	end
	if state.runtime.pendingDeferredNameplateQuestStateRefresh ~= true then
		state.runtime.pendingDeferredNameplateQuestStateRefresh = false
	end
	if type(state.runtime.deferredNameplateQuestStateRefreshGeneration) ~= "number" then
		state.runtime.deferredNameplateQuestStateRefreshGeneration = 0
	end
	if type(state.runtime.nameplateFullRefreshGeneration) ~= "number" then
		state.runtime.nameplateFullRefreshGeneration = 0
	end
	if type(state.runtime.deferredWorkState) ~= "table" then
		state.runtime.deferredWorkState = type(self.deferredWorkState) == "table" and self.deferredWorkState or {}
	end
	if type(state.runtime.deferredWorkState.generations) ~= "table" then
		state.runtime.deferredWorkState.generations = {}
	end
	if type(state.runtime.deferredWorkState.entries) ~= "table" then
		state.runtime.deferredWorkState.entries = {}
	end
	if state.runtime.pendingWaypointIntent ~= nil and type(state.runtime.pendingWaypointIntent) ~= "table" then
		state.runtime.pendingWaypointIntent = nil
	end

	BindRuntimeReferenceAliases(self, state)
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

function QuestTogether:GetTaskAreaResolutionOrder()
	return self:GetTaskAreaSubsystemStateStore().resolutionOrder
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
	state.generation = 0
	return state
end

function QuestTogether:ResetTaskAreaStateStore()
	local state = self:EnsureRuntimeStateStore()
	wipe(state.taskArea.worldByQuestID)
	wipe(state.taskArea.bonusByQuestID)
	wipe(state.taskArea.resolvedByQuestID)
	wipe(state.taskArea.resolutionOrder)
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
	wipe(state.nameplate.questStateByUnitToken)
	wipe(state.nameplate.questGuidByUnitToken)
	wipe(state.nameplate.textCache)
	state.nameplate.refreshGenerationByUnitToken = {}
	wipe(state.nameplate.refreshPendingByUnitToken)
	wipe(state.nameplate.healthTintRefreshPendingByUnitToken)
	wipe(state.nameplate.tooltipResolveRetryCountByUnitToken)
	BindRuntimeReferenceAliases(self, state)
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
	local runtimeState = self:GetRuntimeWorkStateStore()
	runtimeState.pendingWaypointIntent = nil
	runtimeState.pendingScheduledTaskAreaRefreshShouldAnnounce = false
	runtimeState.pendingDeferredNameplateQuestStateRefresh = false
	runtimeState.deferredNameplateQuestStateRefreshGeneration = 0
	runtimeState.nameplateFullRefreshGeneration = 0
	runtimeState.deferredWorkState = {
		generations = {},
		entries = {},
	}
	BindRuntimeReferenceAliases(self, self:EnsureRuntimeStateStore())
	return runtimeState
end

QuestTogether:EnsureRuntimeStateStore()
