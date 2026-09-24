--[[
QuestTogether Task Area Subsystem

This subsystem owns task-area truth for world quests and bonus objectives.
It resolves active area state from addon-owned quest snapshots only.
All other addon code should consume the resolver snapshot or the active
world/bonus state stores exposed here.
]]

local QuestTogether = _G.QuestTogether

local function SafeText(value, fallback)
	return QuestTogether:SafeToString(value, fallback or "")
end

local function NormalizeQuestId(addon, questId)
	if not addon then
		return nil
	end

	if addon.NormalizeQuestID then
		return addon:NormalizeQuestID(questId)
	end

	local numericQuestId = addon.SafeToNumber and addon:SafeToNumber(questId) or nil
	if not numericQuestId or numericQuestId <= 0 then
		return nil
	end

	return math.floor(numericQuestId + 0.5)
end

local function CountKeys(tableValue)
	local count = 0
	for _ in pairs(tableValue or {}) do
		count = count + 1
	end
	return count
end

local function SortedQuestIdKeys(tableValue)
	local keys = {}
	for questId in pairs(tableValue or {}) do
		keys[#keys + 1] = questId
	end
	table.sort(keys, function(a, b)
		local aNum = QuestTogether:SafeToNumber(a)
		local bNum = QuestTogether:SafeToNumber(b)
		if aNum ~= nil and bNum ~= nil then
			return aNum < bNum
		end
		return SafeText(a, "") < SafeText(b, "")
	end)
	return keys
end

local function BuildTaskAreaStateSummary(stateByQuestId)
	local parts = {}
	local keys = SortedQuestIdKeys(stateByQuestId)
	local maxParts = math.min(#keys, 5)
	for index = 1, maxParts do
		local questId = keys[index]
		local questTitle = stateByQuestId and stateByQuestId[questId] or nil
		parts[#parts + 1] = tostring(questId) .. ":" .. SafeText(questTitle, "Unknown")
	end
	if #keys > maxParts then
		parts[#parts + 1] = string.format("...(%d more)", #keys - maxParts)
	end
	return table.concat(parts, " | ")
end

local function BuildMergedTaskAreaQuestInfo(addon, questId, liveQuestInfo, snapshotInfo)
	local mergedQuestInfo = {}
	local liveInfo = type(liveQuestInfo) == "table" and liveQuestInfo or nil
	local snapshot = type(snapshotInfo) == "table" and snapshotInfo or nil

	mergedQuestInfo.questID = liveInfo and liveInfo.questID or (snapshot and snapshot.questID) or questId
	mergedQuestInfo.title = liveInfo and liveInfo.title or (snapshot and snapshot.title) or nil
	mergedQuestInfo.questLogIndex = liveInfo and liveInfo.questLogIndex or (snapshot and snapshot.questLogIndex) or nil
	mergedQuestInfo.isHeader = liveInfo and liveInfo.isHeader == true or false
	mergedQuestInfo.isTask = liveInfo and liveInfo.isTask == true or (snapshot and snapshot.isTask == true) or false
	mergedQuestInfo.isOnMap = liveInfo and liveInfo.isOnMap == true or false
	mergedQuestInfo.hasLocalPOI = liveInfo and liveInfo.hasLocalPOI == true or false
	mergedQuestInfo.isComplete = liveInfo and liveInfo.isComplete == true or (snapshot and snapshot.isComplete == true) or false
	mergedQuestInfo.isWorldQuest = liveInfo and liveInfo.isWorldQuest == true or (snapshot and snapshot.isWorldQuest == true) or false
	mergedQuestInfo.displayAsObjective = snapshot and snapshot.displayAsObjective == true or false
	mergedQuestInfo.isBonusObjective = snapshot and snapshot.isBonusObjective == true or false
	mergedQuestInfo.taskAnnouncementType = snapshot and snapshot.taskAnnouncementType or nil

	local shouldTreatHiddenAsRelevant = mergedQuestInfo.isTask == true
		or mergedQuestInfo.isWorldQuest == true
		or mergedQuestInfo.displayAsObjective == true
		or mergedQuestInfo.isBonusObjective == true
		or mergedQuestInfo.taskAnnouncementType == "world"
		or mergedQuestInfo.taskAnnouncementType == "bonus"

	if liveInfo and liveInfo.isHidden == true and not shouldTreatHiddenAsRelevant then
		mergedQuestInfo.isHidden = true
	else
		mergedQuestInfo.isHidden = false
	end

	if mergedQuestInfo.isWorldQuest ~= true and addon and addon.API and addon.API.IsWorldQuest then
		mergedQuestInfo.isWorldQuest = addon.API.IsWorldQuest(questId) == true
	end

	if
		mergedQuestInfo.isWorldQuest ~= true
		and mergedQuestInfo.displayAsObjective ~= true
		and mergedQuestInfo.isBonusObjective ~= true
		and addon
		and addon.API
		and addon.API.GetTaskQuestInfoByQuestID
	then
		local taskQuestInfo = addon.API.GetTaskQuestInfoByQuestID(questId)
		if type(taskQuestInfo) == "table" and taskQuestInfo.displayAsObjective == true then
			mergedQuestInfo.displayAsObjective = true
			mergedQuestInfo.isBonusObjective = true
		end
	end

	return mergedQuestInfo
end

local function BuildQuestLogQuestInfoIndex(addon)
	local questInfoByQuestId = {}

	if not (addon and addon.API and addon.API.GetNumQuestLogEntries and addon.API.GetQuestLogInfo) then
		return nil, "api_unavailable"
	end

	if addon.EnsureQuestSnapshotStore then
		addon:EnsureQuestSnapshotStore()
	end
	local snapshotByQuestID = addon.GetQuestSnapshotByQuestID and addon:GetQuestSnapshotByQuestID() or nil

	local totalEntries = addon:SafeToNumber(addon.API.GetNumQuestLogEntries())
	if totalEntries == nil or totalEntries < 0 then
		return nil, "count"
	end
	totalEntries = math.floor(totalEntries + 0.5)
	for entryIndex = 1, totalEntries do
		local liveQuestInfo = addon.API.GetQuestLogInfo(entryIndex)
		if type(liveQuestInfo) ~= "table" then
			return nil, "row:" .. tostring(entryIndex)
		end
		if type(liveQuestInfo) == "table" then
			local normalizedQuestId = NormalizeQuestId(addon, liveQuestInfo.questID)
			if liveQuestInfo.isHeader ~= true and not normalizedQuestId then
				return nil, "row:" .. tostring(entryIndex)
			end
			if normalizedQuestId
				and not questInfoByQuestId[normalizedQuestId]
				and not (addon.retiredQuestIds and addon.retiredQuestIds[normalizedQuestId])
			then
				local snapshotInfo = snapshotByQuestID and snapshotByQuestID[normalizedQuestId] or nil
				local mergedQuestInfo = BuildMergedTaskAreaQuestInfo(addon, normalizedQuestId, liveQuestInfo, snapshotInfo)
				if mergedQuestInfo.isHeader ~= true and mergedQuestInfo.isHidden ~= true then
					questInfoByQuestId[normalizedQuestId] = mergedQuestInfo
				end
			end
		end
	end

	return questInfoByQuestId
end

local function BuildTaskAreaCandidateQuestIds(addon, questInfoByQuestId)
	local candidateQuestIds = {}

	for normalizedQuestId in pairs(questInfoByQuestId or {}) do
		candidateQuestIds[normalizedQuestId] = true
	end

	return candidateQuestIds
end

local function BuildActiveTaskAreaSnapshot(taskAreaState, taskType)
	local activeByQuestId = {}
	if type(taskAreaState) ~= "table" then
		return activeByQuestId
	end

	local resolvedByQuestID = taskAreaState.resolvedByQuestID or {}
	local resolutionOrder = taskAreaState.resolutionOrder or {}
	for index = 1, #resolutionOrder do
		local questId = resolutionOrder[index]
		local resolution = resolvedByQuestID[questId]
		if type(resolution) == "table" then
			if taskType == "bonus" then
				if resolution.includeBonus then
					activeByQuestId[questId] = resolution.title
				end
			elseif resolution.includeWorld then
				activeByQuestId[questId] = resolution.title
			end
		end
	end

	return activeByQuestId
end

local function ResolveQuestAreaSignals(addon, taskType, questInfo, normalizedQuestId, isBonusObjective)
	local isOnMap = questInfo and questInfo.isOnMap == true or false
	local hasLocalPOI = questInfo and questInfo.hasLocalPOI == true or false
	local mapFlags = (isOnMap or hasLocalPOI) and true or false

	local areaActive = false
	if taskType == "world" then
		areaActive = isOnMap
	elseif mapFlags and isBonusObjective == true then
		areaActive = true
	end

	return {
		mapFlags = mapFlags,
		areaActive = areaActive and true or false,
		taskActiveForArea = false,
		canUseTaskActiveWorldFallback = false,
	}
end

local function BuildTaskAreaResolution(addon, normalizedQuestId, questInfo)
	local title = addon:GetQuestTitle(normalizedQuestId, questInfo)
	local explicitWorld = questInfo and questInfo.isWorldQuest == true or false
	local explicitTask = questInfo and questInfo.isTask == true or false
	local fallbackWorld = addon:IsWorldQuest(normalizedQuestId)
	local isWorldQuest = explicitWorld or fallbackWorld
	local explicitBonus = questInfo and (questInfo.isBonusObjective == true or questInfo.displayAsObjective == true) or false
	local isBonusObjective = isWorldQuest ~= true and explicitBonus
	local taskAnnouncementType = isWorldQuest and "world" or (isBonusObjective and "bonus" or nil)
	local isTask = explicitTask or isWorldQuest or isBonusObjective

	local worldSignals = ResolveQuestAreaSignals(addon, "world", questInfo, normalizedQuestId, isBonusObjective)
	local bonusSignals = ResolveQuestAreaSignals(addon, "bonus", questInfo, normalizedQuestId, isBonusObjective)

	local isWorldQuestByActiveTaskFallback = false
	if not isWorldQuest and worldSignals.canUseTaskActiveWorldFallback and not isBonusObjective then
		isWorldQuest = true
		isWorldQuestByActiveTaskFallback = true
	end

	local shouldPromoteToTask = worldSignals.areaActive == true or bonusSignals.areaActive == true
	if bonusSignals.taskActiveForArea == true then
		shouldPromoteToTask = true
	end
	if not isTask and shouldPromoteToTask then
		isTask = true
	end

	local includeWorld = isTask and worldSignals.areaActive == true and isWorldQuest == true
	local includeBonus = isTask and bonusSignals.areaActive == true and isWorldQuest ~= true

	return {
		questID = normalizedQuestId,
		title = title,
		taskAnnouncementType = taskAnnouncementType,
		explicitWorld = explicitWorld,
		fallbackWorld = fallbackWorld,
		explicitTask = explicitTask,
		explicitBonus = explicitBonus,
		isWorldQuest = isWorldQuest and true or false,
		isBonusObjective = isBonusObjective and true or false,
		isTask = isTask and true or false,
		isWorldQuestByActiveTaskFallback = isWorldQuestByActiveTaskFallback,
		includeWorld = includeWorld and true or false,
		includeBonus = includeBonus and true or false,
		worldSignals = worldSignals,
		bonusSignals = bonusSignals,
	}
end

function QuestTogether:RebuildTaskAreaResolverStore()
	local taskAreaState = self.GetTaskAreaSubsystemStateStore and self:GetTaskAreaSubsystemStateStore() or nil
	if type(taskAreaState) ~= "table" then
		return nil, false
	end

	-- Keep the last complete resolver snapshot if a transient read fails.
	local previousResolved = taskAreaState.resolvedByQuestID or {}
	local resolvedByQuestID = {}
	local resolutionOrder = {}

	local scanOK, questInfoByQuestId, failureReason = pcall(BuildQuestLogQuestInfoIndex, self)
	if not scanOK or not questInfoByQuestId then
		local reason = scanOK and failureReason or ("read_error:" .. SafeText(questInfoByQuestId, "unknown"))
		if taskAreaState.lastScanFailure ~= reason then
			self:Debugf("QUEST", "task_area_deferred reason=%s generation=%d", reason, taskAreaState.generation or 0)
		end
		taskAreaState.lastScanFailure = reason
		return taskAreaState, false
	end
	local candidateQuestIds = BuildTaskAreaCandidateQuestIds(self, questInfoByQuestId)

	local candidateOrder = SortedQuestIdKeys(candidateQuestIds)
	local scanSignature = table.concat(candidateOrder, ",")
	if taskAreaState.lastScanSignature ~= scanSignature then
		self:Debugf("DEBUG", "task_area_scan rows=%d candidates=%d", CountKeys(questInfoByQuestId), #candidateOrder)
	end

	for _, normalizedQuestId in ipairs(candidateOrder) do
		local questInfo = questInfoByQuestId[normalizedQuestId]
		local resolution = BuildTaskAreaResolution(self, normalizedQuestId, questInfo)
		local previous = previousResolved[normalizedQuestId]
		if resolution.taskAnnouncementType and (
			not previous or previous.includeWorld ~= resolution.includeWorld
			or previous.includeBonus ~= resolution.includeBonus
			or previous.taskAnnouncementType ~= resolution.taskAnnouncementType
		) then
			self:Debugf("DEBUG", "task_area_resolve questId=%s type=%s includeWorld=%s includeBonus=%s title=%s",
				tostring(normalizedQuestId), resolution.taskAnnouncementType,
				tostring(resolution.includeWorld), tostring(resolution.includeBonus), SafeText(resolution.title, "Unknown"))
		end
		resolvedByQuestID[normalizedQuestId] = resolution
		resolutionOrder[#resolutionOrder + 1] = normalizedQuestId
	end

	taskAreaState.lastScanSignature = scanSignature
	taskAreaState.lastScanFailure = nil
	taskAreaState.resolvedByQuestID = resolvedByQuestID
	taskAreaState.resolutionOrder = resolutionOrder
	taskAreaState.generation = (taskAreaState.generation or 0) + 1
	return taskAreaState, true
end

function QuestTogether:GetTaskAreaSnapshot(taskType)
	local taskAreaState = self.GetTaskAreaSubsystemStateStore and self:GetTaskAreaSubsystemStateStore() or nil
	if type(taskAreaState) ~= "table" then
		return {}
	end

	local sourceState = self.GetTaskAreaStateStore and self:GetTaskAreaStateStore(taskType) or {}
	local activeByQuestId = {}
	for questId, questTitle in pairs(sourceState) do
		local normalizedQuestId = NormalizeQuestId(self, questId)
		if normalizedQuestId then
			activeByQuestId[normalizedQuestId] = questTitle
		end
	end

	return activeByQuestId
end

function QuestTogether:GetActiveWorldQuestAreaSnapshot()
	return self:GetTaskAreaSnapshot("world")
end

function QuestTogether:GetActiveBonusObjectiveAreaSnapshot()
	return self:GetTaskAreaSnapshot("bonus")
end

function QuestTogether:RefreshTaskAreaState(taskType, shouldAnnounce)
	local configByType = {
		world = {
			enterEvent = "WORLD_QUEST_ENTERED",
			leftEvent = "WORLD_QUEST_LEFT",
			enterPrefix = "World Quest Entered: ",
			leftPrefix = "Left World Quest: ",
			debugLabel = "World quest",
		},
		bonus = {
			enterEvent = "BONUS_OBJECTIVE_ENTERED",
			leftEvent = "BONUS_OBJECTIVE_LEFT",
			enterPrefix = "Bonus Objective Entered: ",
			leftPrefix = "Left Bonus Objective: ",
			debugLabel = "Bonus objective",
		},
	}

	local config = configByType[taskType]
	if not config then
		return
	end

	local taskAreaState = self.GetTaskAreaSubsystemStateStore and self:GetTaskAreaSubsystemStateStore() or nil
	local previousStateRaw = self.GetTaskAreaStateStore and self:GetTaskAreaStateStore(taskType) or {}
	local currentStateRaw = BuildActiveTaskAreaSnapshot(taskAreaState, taskType)
	local previousState = {}
	local currentState = {}

	for questId, questTitle in pairs(previousStateRaw) do
		local normalizedQuestId = NormalizeQuestId(self, questId)
		if normalizedQuestId then
			previousState[normalizedQuestId] = questTitle
		end
	end

	for questId, questTitle in pairs(currentStateRaw) do
		local normalizedQuestId = NormalizeQuestId(self, questId)
		if normalizedQuestId then
			currentState[normalizedQuestId] = questTitle
		end
	end

	local worldSignature = table.concat(SortedQuestIdKeys(currentState), ",")
	if taskType == "world" and taskAreaState and taskAreaState.lastWorldAreaDebugSignature ~= worldSignature then
		taskAreaState.lastWorldAreaDebugSignature = worldSignature
		self:Debugf(
			"DEBUG",
			"world_area_state announce=%s prev=%d curr=%d current=%s",
			tostring(shouldAnnounce and true or false),
			CountKeys(previousState),
			CountKeys(currentState),
			BuildTaskAreaStateSummary(currentState)
		)
	end

	if taskAreaState and self.GetTaskAreaStateStore then
		local stateStore = self:GetTaskAreaStateStore(taskType)
		wipe(stateStore)
		for questId, questTitle in pairs(currentState) do
			stateStore[questId] = questTitle
		end
	end

	for questId, questTitle in pairs(currentState) do
		if not previousState[questId] and shouldAnnounce then
			if taskType == "world" then
				self:Debugf(
					"DEBUG",
					"world_area_enter questId=%s title=%s",
					tostring(questId),
					SafeText(questTitle, "Unknown")
				)
			end
			self:PublishAnnouncementEvent(config.enterEvent, config.enterPrefix .. SafeText(questTitle, "Unknown"), questId)
		end
	end

	for questId, previousTitle in pairs(previousState) do
			if not currentState[questId] then
				local wasCompleted = self.questsCompleted[questId] ~= nil
				if shouldAnnounce and not wasCompleted then
					local questTitle = previousTitle or self:GetQuestTitle(questId)
					if taskType == "world" then
						self:Debugf(
							"DEBUG",
							"world_area_left questId=%s title=%s",
							tostring(questId),
							SafeText(questTitle, "Unknown")
						)
					end
					self:PublishAnnouncementEvent(config.leftEvent, config.leftPrefix .. SafeText(questTitle, "Unknown"), questId)
				end
			end
	end

end

function QuestTogether:RefreshWorldQuestAreaState(shouldAnnounce)
	self:RefreshTaskAreaState("world", shouldAnnounce)
end

function QuestTogether:RefreshBonusObjectiveAreaState(shouldAnnounce)
	self:RefreshTaskAreaState("bonus", shouldAnnounce)
end

function QuestTogether:ScheduleTaskAreaRefresh(shouldAnnounce, delaySeconds)
	if delaySeconds ~= nil and delaySeconds <= 0 then
		delaySeconds = nil
	end

	if self.ScheduleTaskAreaRefreshWork then
		self:ScheduleTaskAreaRefreshWork(shouldAnnounce, delaySeconds, "ScheduleTaskAreaRefresh")
		return
	end

	self:RefreshTaskAreaStates(shouldAnnounce)
end

function QuestTogether:RefreshTaskAreaStates(shouldAnnounce)
	if self.IsWorkBlocked and self:IsWorkBlocked("task_area_refresh") then
		if shouldAnnounce then
			self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", true)
		end
		self:ScheduleTaskAreaRefresh(shouldAnnounce)
		return false
	end

	local pendingAnnounce = self:GetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false)
	local resolvedShouldAnnounce = shouldAnnounce or (pendingAnnounce and true or false)
	local _, rebuilt = self:RebuildTaskAreaResolverStore()
	if rebuilt == false then
		-- Keep the last confirmed state and announcement intent for a later normal
		-- quest event. Do not turn an unreadable log into synthetic exits or loop.
		self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", resolvedShouldAnnounce and true or false)
		return false
	end
	self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false)
	self:RefreshWorldQuestAreaState(resolvedShouldAnnounce)
	self:RefreshBonusObjectiveAreaState(resolvedShouldAnnounce)
	return true
end
