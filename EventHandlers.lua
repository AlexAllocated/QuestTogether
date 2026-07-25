--[[
QuestTogether Event Handlers

Responsibilities in this file:
- Detect local quest changes.
- Publish lightweight announcement events.
- Display local announcements according to local options.
]]

local QuestTogether = _G.QuestTogether

local function SafeText(value, fallback)
	return QuestTogether:SafeToString(value, fallback or "")
end

local function SafeMatch(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, first, second = pcall(string.match, safeText, pattern)
	if not ok then
		return nil
	end

	return first, second
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

local DrainQueuedQuestLogTasks

DrainQueuedQuestLogTasks = function(addon)
	if not addon then
		return 0
	end

	local queuedTasks = addon.onQuestLogUpdate
	if type(queuedTasks) ~= "table" or #queuedTasks == 0 then
		addon.onQuestLogUpdate = addon.onQuestLogUpdate or {}
		return 0
	end

	addon.onQuestLogUpdate = {}
	for index = 1, #queuedTasks do
		local taskFn = queuedTasks[index]
		if type(taskFn) == "function" then
			taskFn()
		end
	end

	return #queuedTasks
end

function QuestTogether:DrainQueuedQuestLogTasks()
	return DrainQueuedQuestLogTasks(self)
end

local function ParseObjectiveProgressFromText(objectiveText)
	if type(objectiveText) ~= "string" or objectiveText == "" then
		return nil
	end

	local amountCurrent = SafeMatch(objectiveText, "(%d+)%s*/%s*%d+")
	if amountCurrent then
		return QuestTogether:SafeToNumber(amountCurrent)
	end

	local percent = SafeMatch(objectiveText, "(%d+%.?%d*)%%")
	if percent then
		return QuestTogether:SafeToNumber(percent)
	end

	return nil
end

local function ResolveObjectiveProgressValue(objectiveText, currentValue)
	local numericValue = QuestTogether:SafeToNumber(currentValue)
	if numericValue ~= nil then
		return numericValue
	end
	return ParseObjectiveProgressFromText(objectiveText)
end

function QuestTogether:GetObjectiveProgressIdentity(objectiveText)
	local normalizedText = self:SafeTrimString(objectiveText, "")
	if normalizedText == "" then
		return nil
	end

	local okAmounts, withoutAmounts = pcall(string.gsub, normalizedText, "%d+%s*/%s*%d+", "#/#")
	if not okAmounts or type(withoutAmounts) ~= "string" then
		return nil
	end
	local okPercents, withoutPercents = pcall(string.gsub, withoutAmounts, "%d+%.?%d*%%", "#%%")
	if not okPercents or type(withoutPercents) ~= "string" then
		return nil
	end

	local identity = self:SafeTrimString(withoutPercents, "")
	local okLabel, label = pcall(string.gsub, identity, "[%s%p]+", "")
	if not okLabel or type(label) ~= "string" or label == "" then
		return nil
	end
	return identity
end

function QuestTogether:DidObjectiveProgressIncrease(oldText, oldValue, newText, newValue)
	local oldIdentity = self:GetObjectiveProgressIdentity(oldText)
	local newIdentity = self:GetObjectiveProgressIdentity(newText)
	if not oldIdentity or not newIdentity or oldIdentity ~= newIdentity then
		return false
	end

	local previousValue = QuestTogether:SafeToNumber(oldValue)
	if previousValue == nil then
		previousValue = ParseObjectiveProgressFromText(oldText)
	end

	local currentValue = ResolveObjectiveProgressValue(newText, newValue)
	if previousValue == nil or currentValue == nil then
		return false
	end

	return currentValue > previousValue
end

function QuestTogether:PickRandomCompletionEmote()
	if #self.completionEmotes == 0 then
		return "cheer"
	end
	local randomIndex = self.API.Random(1, #self.completionEmotes)
	return self.completionEmotes[randomIndex]
end

function QuestTogether:PlayLocalCompletionEmote(emoteToken)
	if not self:GetOption("emoteOnQuestCompletion") then
		return false
	end
	if self.suppressLocalAnnouncementDisplayDuringTests then
		return false
	end
	self.API.DoEmote(emoteToken, self:GetPlayerName())
	return true
end

function QuestTogether:HandleQuestCompleted(questTitle, questId, extraData)
	local completionEmote = self:PickRandomCompletionEmote()
	local announcementExtraData = self.SanitizeAnnouncementExtraData and self:SanitizeAnnouncementExtraData(extraData) or {}
	announcementExtraData.emoteToken = completionEmote
	if questId and self:IsWorldQuest(questId) then
		self:PublishAnnouncementEvent(
			"WORLD_QUEST_COMPLETED",
			"World Quest Completed: " .. SafeText(questTitle, "Unknown"),
			questId,
			announcementExtraData
		)
	elseif questId and self:IsBonusObjective(questId) then
		self:PublishAnnouncementEvent(
			"BONUS_OBJECTIVE_COMPLETED",
			"Bonus Objective Completed: " .. SafeText(questTitle, "Unknown"),
			questId,
			announcementExtraData
		)
	else
		self:PublishAnnouncementEvent(
			"QUEST_COMPLETED",
			"Quest Completed: " .. SafeText(questTitle, "Unknown"),
			questId,
			announcementExtraData
		)
	end

	self:PlayLocalCompletionEmote(completionEmote)
end

function QuestTogether:HandleQuestRemoved(questTitle)
	self:PublishAnnouncementEvent("QUEST_REMOVED", "Quest Removed: " .. SafeText(questTitle, "Unknown"))
end

function QuestTogether:ShouldPublishObjectiveProgress(currentValue)
	return currentValue and currentValue > 0
end

function QuestTogether:GetTaskAnnouncementType(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return nil
	end

	local worldState = self.GetTaskAreaStateStore and self:GetTaskAreaStateStore("world") or nil
	if type(worldState) == "table" and worldState[questId] then
		return "world"
	end

	local bonusState = self.GetTaskAreaStateStore and self:GetTaskAreaStateStore("bonus") or nil
	if type(bonusState) == "table" and bonusState[questId] then
		return "bonus"
	end

	local snapshot = self.GetQuestSnapshot and self:GetQuestSnapshot(questId) or nil
	if snapshot and type(snapshot.taskAnnouncementType) == "string" and snapshot.taskAnnouncementType ~= "" then
		return snapshot.taskAnnouncementType
	end

	if self:IsWorldQuest(questId) then
		return "world"
	end
	if self:IsBonusObjective(questId) then
		return "bonus"
	end
	return nil
end

function QuestTogether:BuildTrackedQuestRemovalData(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return nil
	end

	local tracker = self:GetPlayerTracker()
	local trackedQuest = tracker[questId]
	if not trackedQuest then
		return nil
	end

	local iconAsset, iconKind = self:GetTrackedQuestAnnouncementIcon(trackedQuest)
	local questTitle = trackedQuest.title
	if self.IsPlaceholderQuestTitle and self:IsPlaceholderQuestTitle(questId, questTitle) then
		local resolvedTitle = self:GetQuestTitle(questId)
		if type(resolvedTitle) == "string" and resolvedTitle ~= "" and not self:IsPlaceholderQuestTitle(questId, resolvedTitle) then
			questTitle = resolvedTitle
		end
	end
	return {
		questId = questId,
		title = questTitle or ("Quest " .. SafeText(questId, "?")),
		taskAnnouncementType = self:GetTaskAnnouncementType(questId),
		iconAsset = iconAsset,
		iconKind = iconKind,
	}
end

function QuestTogether:BuildTrackedQuestCompletionData(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return nil
	end

	local completionData = self:BuildTrackedQuestRemovalData(questId) or {
		questId = questId,
		title = self:GetQuestTitle(questId),
		taskAnnouncementType = self:GetTaskAnnouncementType(questId),
	}

	local completionEventType = "QUEST_READY_TO_TURN_IN"
	if completionData.taskAnnouncementType == "world" then
		completionEventType = "WORLD_QUEST_COMPLETED"
	elseif completionData.taskAnnouncementType == "bonus" then
		completionEventType = "BONUS_OBJECTIVE_COMPLETED"
	end

	local iconAsset, iconKind = self:GetAnnouncementIconInfo(completionEventType, questId)
	if type(iconAsset) == "string" and iconAsset ~= "" then
		completionData.iconAsset = iconAsset
		completionData.iconKind = iconKind
	end

	return completionData
end

function QuestTogether:ClearTrackedQuestState(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return
	end

	local tracker = self:GetPlayerTracker()
	tracker[questId] = nil
	self.pendingQuestRemovals[questId] = nil
	self:RefreshTaskAreaStates(true)
	self.questsCompleted[questId] = nil
end

function QuestTogether:ResolvePendingQuestRemoval(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return false
	end

	local removalData = self.pendingQuestRemovals[questId]
	if not removalData then
		return false
	end

	local completionData = self.questsCompleted[questId]
	local completed = completionData ~= nil
	local questTitle = removalData.title or (completionData and completionData.title) or ("Quest " .. SafeText(questId, "?"))
	local iconAsset = (completionData and completionData.iconAsset) or removalData.iconAsset
	local iconKind = (completionData and completionData.iconKind) or removalData.iconKind

	if completed then
		self:HandleQuestCompleted(questTitle, questId, {
			iconAsset = iconAsset,
			iconKind = iconKind,
		})
	elseif not removalData.taskAnnouncementType then
		self:PublishAnnouncementEvent("QUEST_REMOVED", "Quest Removed: " .. SafeText(questTitle, "Unknown"), questId)
	end

	self:ClearTrackedQuestState(questId)
	return true
end

function QuestTogether:HandleGroupRosterChanged(reason)
	local previousFingerprint = self:GetPartyRosterFingerprint()
	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end
end

function QuestTogether:PLAYER_REGEN_ENABLED()
	if self.FlushDeferredWork then
		self:FlushDeferredWork("PLAYER_REGEN_ENABLED")
	end
end

-- QUEST_ACCEPTED fires early; defer reads until QUEST_LOG_UPDATE.
function QuestTogether:QUEST_ACCEPTED(_, questId)
	local normalizedQuestId = NormalizeQuestId(self, questId)
	if not normalizedQuestId then
		return
	end

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()
		if tracker[normalizedQuestId] ~= nil then
			return
		end

		local taskAnnouncementType = self:GetTaskAnnouncementType(normalizedQuestId)
		local questLogIndex = self.API.GetQuestLogIndexForQuestID
			and self.API.GetQuestLogIndexForQuestID(normalizedQuestId)
				if not questLogIndex then
					if taskAnnouncementType then
						local taskQuestTitle = self:GetQuestTitle(normalizedQuestId)
						self:WatchQuest(normalizedQuestId, { title = taskQuestTitle })
						self:RefreshTaskAreaStates(true)
					end
					return
			end

		local questInfo = self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex)
		if not questInfo then
			return
		end

		if questInfo.isHidden and not taskAnnouncementType then
			return
		end

			if not taskAnnouncementType then
				self:PublishAnnouncementEvent(
					"QUEST_ACCEPTED",
					"Quest Accepted: " .. SafeText(questInfo.title, "Unknown"),
				normalizedQuestId
			)
		end

			self:WatchQuest(normalizedQuestId, questInfo)
			if taskAnnouncementType then
				self:RefreshTaskAreaStates(true)
			end
		end)
end

function QuestTogether:QUEST_TURNED_IN(_, questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return
	end

	local completionData = self:BuildTrackedQuestCompletionData(questId)
	self.questsCompleted[questId] = completionData
	if self.pendingQuestRemovals[questId] then
		self:ResolvePendingQuestRemoval(questId)
	end
end

function QuestTogether:QUEST_REMOVED(_, questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return
	end

	local removalData = self:BuildTrackedQuestRemovalData(questId)
	if not removalData then
		return
	end

	self.pendingQuestRemovals[questId] = removalData
	self.API.Delay(0, function()
		if QuestTogether.pendingQuestRemovals and QuestTogether.pendingQuestRemovals[questId] then
			QuestTogether:ResolvePendingQuestRemoval(questId)
		end
	end)
end

function QuestTogether:SUPER_TRACKING_CHANGED()
	self:ScheduleTaskAreaRefresh(true, 0)
end

-- UNIT_QUEST_LOG_CHANGED indicates objective and completion changes.
-- Emit local progress announcements only when numeric progress increases.
function QuestTogether:UNIT_QUEST_LOG_CHANGED(_, unit)
	if unit ~= "player" then
		return
	end

	self:QueueQuestLogTask(function()
		local tracker = self:GetPlayerTracker()

		for questId, questData in pairs(tracker) do
			local normalizedQuestId = NormalizeQuestId(self, questId)
			if normalizedQuestId then
				questId = normalizedQuestId
				local questLogIndex = self.GetQuestLogIndexForQuest and self:GetQuestLogIndexForQuest(questId)
				if questLogIndex then
					local numObjectives = self.API.GetNumQuestLeaderBoards and self.API.GetNumQuestLeaderBoards(questLogIndex)
						or 0

					for objectiveIndex = 1, numObjectives do
						local objectiveText, _, _, currentValue =
							self:GetNormalizedQuestObjectiveInfo(questId, objectiveIndex, false)

						questData.objectiveValues = questData.objectiveValues or {}
						local oldObjectiveText = questData.objectives[objectiveIndex]
						local oldObjectiveValue = questData.objectiveValues[objectiveIndex]
						if oldObjectiveText ~= objectiveText then
							local isInitialObjectiveBaseline = oldObjectiveText == nil and oldObjectiveValue == nil
							local hasForwardProgress =
								self:DidObjectiveProgressIncrease(oldObjectiveText, oldObjectiveValue, objectiveText, currentValue)
							local resolvedProgressValue = ResolveObjectiveProgressValue(objectiveText, currentValue)
							if
								(not isInitialObjectiveBaseline)
								and hasForwardProgress
								and self:ShouldPublishObjectiveProgress(resolvedProgressValue)
							then
								local taskAnnouncementType = self:GetTaskAnnouncementType(questId)
								local eventType = "QUEST_PROGRESS"
								if taskAnnouncementType == "world" then
									eventType = "WORLD_QUEST_PROGRESS"
								elseif taskAnnouncementType == "bonus" then
									eventType = "BONUS_OBJECTIVE_PROGRESS"
								end
								self:PublishAnnouncementEvent(eventType, objectiveText, questId)
							end
							questData.objectives[objectiveIndex] = objectiveText
							questData.objectiveValues[objectiveIndex] = resolvedProgressValue
						else
							questData.objectiveValues[objectiveIndex] =
								ResolveObjectiveProgressValue(objectiveText, currentValue)
						end
					end

					-- Objective list can shrink; emit explicit empty values for removed indices.
					local previousObjectiveCount = #questData.objectives
					if previousObjectiveCount > numObjectives then
						for objectiveIndex = numObjectives + 1, previousObjectiveCount do
							questData.objectives[objectiveIndex] = nil
							if questData.objectiveValues then
								questData.objectiveValues[objectiveIndex] = nil
							end
						end
					end

					local statusState = self.GetTrackedQuestStatusState
						and self:GetTrackedQuestStatusState(questId, true)
						or nil
					local currentIsComplete = statusState and statusState.isComplete == true or false
					local completionChanged = questData.isComplete ~= currentIsComplete
					if completionChanged then
						questData.isComplete = currentIsComplete
					end

					local currentReadyForTurnIn = statusState and statusState.isReadyForTurnIn == true or false
					local readyForTurnInChanged = questData.isReadyForTurnIn ~= currentReadyForTurnIn
					if readyForTurnInChanged then
						questData.isReadyForTurnIn = currentReadyForTurnIn
						if currentReadyForTurnIn and not self:GetTaskAnnouncementType(questId) then
							local questTitle = questData.title or self:GetQuestTitle(questId)
							self:PublishAnnouncementEvent(
								"QUEST_READY_TO_TURN_IN",
								"Ready to Turn In: " .. SafeText(questTitle, "Unknown"),
								questId
							)
						end
					end
				end
			end
		end
	end)
end

function QuestTogether:QUEST_LOG_UPDATE()
	if type(self.onQuestLogUpdate) == "table" and #self.onQuestLogUpdate > 0 then
		if self.ScheduleQuestLogTaskDrain then
			self:ScheduleQuestLogTaskDrain("QUEST_LOG_UPDATE")
		else
			DrainQueuedQuestLogTasks(self)
		end
	end

	self:ScheduleTaskAreaRefresh(true, 0)
end

function QuestTogether:QUEST_POI_UPDATE()
	self:ScheduleTaskAreaRefresh(true, 0)
end

function QuestTogether:PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED()
	self:ScheduleTaskAreaRefresh(true, 0)
end

function QuestTogether:AREA_POIS_UPDATED()
	self:ScheduleTaskAreaRefresh(true, 0)
end

function QuestTogether:ZONE_CHANGED()
	self:ScheduleTaskAreaRefresh(true, 0)
end

function QuestTogether:ZONE_CHANGED_INDOORS()
	self:ScheduleTaskAreaRefresh(true, 0)
end

function QuestTogether:ZONE_CHANGED_NEW_AREA()
	self:ScheduleTaskAreaRefresh(true, 0)
end

function QuestTogether:PLAYER_ENTERING_WORLD()
	-- Refresh state after loading screens without emitting synthetic enter/leave lines.
	self:RefreshTaskAreaStates(false)
	if self.EnsureAnnouncementChannelJoined and self.isEnabled then
		self:EnsureAnnouncementChannelJoined()
	end
end

function QuestTogether:GROUP_JOINED()
	self:HandleGroupRosterChanged("GROUP_JOINED")
end

function QuestTogether:GROUP_ROSTER_UPDATE()
	self:HandleGroupRosterChanged("GROUP_ROSTER_UPDATE")
end
