local L = _G.QuestTogether.Translate
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
			-- One transient API failure must not discard the rest of this batch.
			local ok, result
			if addon.RunGuardedCallback then
				ok, result = addon:RunGuardedCallback("quest_log_task", taskFn)
			else
				ok, result = pcall(taskFn)
			end
			if ok and result == false then
				-- An explicit retry stays queued for the next real log update.
				-- Never recursively drain unreadable data or start a timer loop.
				addon.onQuestLogUpdate[#addon.onQuestLogUpdate + 1] = taskFn
			elseif not ok and addon.Debugf then
				addon:Debugf("QUEST", "Quest log task failed: %s", SafeText(result, "unknown error"))
			end
		end
	end

	return #queuedTasks
end

function QuestTogether:DrainQueuedQuestLogTasks()
	local drained = DrainQueuedQuestLogTasks(self)
	-- Drain acceptance/progress first so a recovery scan cannot consume a new
	-- acceptance by populating its tracker before its queued event runs.
	if self:GetRuntimeFlag("pendingQuestLogScan", false) then
		-- The real log update requests area announcements even if an earlier
		-- acceptance in this batch has already consumed the area's pending flag.
		self:ScanQuestLog(true)
	end
	return drained
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

	-- A changed target can be a new quest stage even when its label is reused.
	local okAmounts, withoutAmounts = pcall(string.gsub, normalizedText, "%d+%s*/%s*(%d+)", "#/%1")
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

function QuestTogether:UpdateTrackedObjectiveProgress(questData, objectiveIndex, objectiveText, currentValue, questId)
	questData.objectives = questData.objectives or {}
	questData.objectiveValues = questData.objectiveValues or {}
	questData.objectiveProgressHighWater = questData.objectiveProgressHighWater or {}
	questData.objectiveProgressObservations = questData.objectiveProgressObservations or {}

	local oldText = questData.objectives[objectiveIndex]
	local oldValue = ResolveObjectiveProgressValue(oldText, questData.objectiveValues[objectiveIndex])
	local oldIdentity = self:GetObjectiveProgressIdentity(oldText)
	local lastObservation = questData.objectiveProgressObservations[objectiveIndex]
	if (not oldIdentity or oldValue == nil) and lastObservation then
		-- Missing rows can clear the displayed snapshot, but they do not establish
		-- a new quest stage. Compare recovery with the last readable observation.
		oldText = lastObservation.text
		oldValue = lastObservation.value
		oldIdentity = lastObservation.identity
	end
	local identity = self:GetObjectiveProgressIdentity(objectiveText)
	local progressValue = ResolveObjectiveProgressValue(objectiveText, currentValue)
	local highWaterByIdentity = questData.objectiveProgressHighWater[objectiveIndex] or {}
	questData.objectiveProgressHighWater[objectiveIndex] = highWaterByIdentity

	if oldIdentity and oldValue ~= nil then
		highWaterByIdentity[oldIdentity] = math.max(highWaterByIdentity[oldIdentity] or oldValue, oldValue)
	end
	local previousHighWater = identity and highWaterByIdentity[identity] or nil
	local shouldAnnounce = oldText ~= objectiveText
		and oldIdentity ~= nil
		and oldIdentity == identity
		and oldValue ~= nil
		and progressValue ~= nil
		and previousHighWater ~= nil
		and progressValue > previousHighWater
		and self:ShouldPublishObjectiveProgress(progressValue)

	if identity and progressValue ~= nil then
		highWaterByIdentity[identity] = math.max(previousHighWater or progressValue, progressValue)
	end
	-- When the percent API is unreadable, normalization leaves only the label.
	-- A different readable label still establishes a stage boundary even if its
	-- numeric progress is unavailable, so it must replace the older observation.
	local sameIdentityWithoutValue = identity == oldIdentity
		or (identity ~= nil and identity == SafeMatch(oldIdentity, "^#%%%s*(.+)$"))
	if identity and (progressValue ~= nil or not sameIdentityWithoutValue) then
		lastObservation = lastObservation or {}
		lastObservation.text = objectiveText
		lastObservation.value = progressValue
		lastObservation.identity = identity
		questData.objectiveProgressObservations[objectiveIndex] = lastObservation
	elseif oldIdentity and oldValue ~= nil and not lastObservation then
		-- Seed older trackers before their first unreadable observation.
		questData.objectiveProgressObservations[objectiveIndex] = {
			text = oldText,
			value = oldValue,
			identity = oldIdentity,
		}
	end
	if oldText ~= nil and oldText ~= objectiveText and self.Debugf then
		local reason
		if shouldAnnounce then
			reason = "advanced"
		elseif oldIdentity ~= identity then
			reason = "identity_changed"
		elseif progressValue ~= nil and oldValue ~= nil and progressValue < oldValue then
			reason = "regressed"
		elseif progressValue ~= nil and oldValue ~= nil and progressValue > oldValue then
			reason = "replayed_milestone"
		end
		if reason then
			self:Debugf(
				"QUEST", "objective_state questId=%s slot=%d reason=%s previous=%s current=%s highWater=%s identity=%s",
				SafeText(questId, "?"), objectiveIndex, reason, SafeText(oldValue, "?"),
				SafeText(progressValue, "?"), SafeText(previousHighWater, "?"), SafeText(identity, "?")
			)
		end
	end
	-- Keep the displayed snapshot current, but never replay a milestone after an
	-- API rollback, disappearing objective row, or temporary objective rewrite.
	-- A newly accepted quest gets a new tracker and a fresh milestone history.
	questData.objectives[objectiveIndex] = objectiveText
	questData.objectiveValues[objectiveIndex] = progressValue
	return shouldAnnounce and true or false
end

function QuestTogether:PickRandomCompletionEmote()
	if #self.completionEmotes == 0 then
		return "cheer"
	end
	local randomIndex = self.API.Random(1, #self.completionEmotes)
	return self.completionEmotes[randomIndex]
end

function QuestTogether:PlayLocalCelebrationEmote(emoteToken, optionKey)
	if not self:GetOption(optionKey) then
		return false
	end
	if self.suppressLocalAnnouncementDisplayDuringTests then
		return false
	end
	self.API.DoEmote(emoteToken, self:GetPlayerName())
	return true
end

function QuestTogether:PlayLocalCompletionEmote(emoteToken)
	return self:PlayLocalCelebrationEmote(emoteToken, "emoteOnQuestCompletion")
end

function QuestTogether:PLAYER_LEVEL_UP(_, newLevel)
	if not self.isEnabled then
		return false
	end
	local level = self:SafeToNumber(newLevel)
	if not level or level <= 0 or level ~= math.floor(level) then
		return false
	end

	local emoteToken = self:PickRandomCompletionEmote()
	-- Publish even when our own emotes are disabled; receivers choose whether to react.
	self:PublishAnnouncementEvent("PLAYER_LEVEL_UP", L("Level ") .. tostring(level), nil, { emoteToken = emoteToken, eventFacts = self:BuildAnnouncementFacts("PLAYER_LEVEL_UP", nil, nil, nil, level) })
	self:PlayLocalCelebrationEmote(emoteToken, "emoteOnLevelUp")
	return true
end

function QuestTogether:HandleQuestCompleted(questTitle, questId, extraData, capturedTaskType)
	local completionEmote = self:PickRandomCompletionEmote()
	local announcementExtraData = self.SanitizeAnnouncementExtraData and self:SanitizeAnnouncementExtraData(extraData) or {}
	announcementExtraData.emoteToken = completionEmote
	local taskType = capturedTaskType
	if taskType ~= "world" and taskType ~= "bonus" and taskType ~= "quest" then
		taskType = questId and self:GetTaskAnnouncementType(questId) or nil
	end
	if taskType == "world" then
		self:PublishAnnouncementEvent(
			"WORLD_QUEST_COMPLETED",
			L("World Quest Completed: ") .. SafeText(questTitle, L("Unknown")),
			questId,
			announcementExtraData
		)
	elseif taskType == "bonus" then
		self:PublishAnnouncementEvent(
			"BONUS_OBJECTIVE_COMPLETED",
			L("Bonus Objective Completed: ") .. SafeText(questTitle, L("Unknown")),
			questId,
			announcementExtraData
		)
	else
		self:PublishAnnouncementEvent(
			"QUEST_COMPLETED",
			L("Quest Completed: ") .. SafeText(questTitle, L("Unknown")),
			questId,
			announcementExtraData
		)
	end

	self:PlayLocalCompletionEmote(completionEmote)
end

function QuestTogether:HandleQuestRemoved(questTitle)
	self:PublishAnnouncementEvent("QUEST_REMOVED", L("Quest Removed: ") .. SafeText(questTitle, L("Unknown")))
end

function QuestTogether:ShouldPublishObjectiveProgress(currentValue)
	return currentValue and currentValue > 0
end

function QuestTogether:GetTaskAnnouncementType(questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return nil
	end

	if self:IsWorldQuest(questId) then
		return "world"
	end
	if self:IsBonusObjective(questId) then
		return "bonus"
	end
	return nil
end

local function ResolveCapturedQuestTitle(addon, questId, title)
	title = addon:SafeTrimString(title, "")
	if title ~= "" and not addon:IsPlaceholderQuestTitle(questId, title) then return title end
	-- A turn-in may outlive its quest-log snapshot. The existing guarded,
	-- bounded title reader can still resolve the ID without selecting a quest.
	local resolved = addon.GetLocalizedQuestTitle and addon:GetLocalizedQuestTitle(questId)
	return resolved or (title ~= "" and title or nil)
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
	questTitle = ResolveCapturedQuestTitle(self, questId, questTitle)
	return {
		questId = questId,
		title = questTitle or (L("Quest ") .. SafeText(questId, "?")),
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

	local retiredData = self.retiredQuestIds and self.retiredQuestIds[questId]
	local previousRemoval = type(retiredData) == "table" and retiredData.removalData or nil
	local completionData
	if previousRemoval then
		-- Removal already captured this lifetime, even if its timer has not
		-- cleared the tracker yet. Do not reclassify it from disappearing data.
		completionData = {
			questId = questId,
			title = previousRemoval.title,
			taskAnnouncementType = previousRemoval.taskAnnouncementType,
			iconAsset = previousRemoval.iconAsset,
			iconKind = previousRemoval.iconKind,
		}
	else
		completionData = self:BuildTrackedQuestRemovalData(questId)
	end
	completionData = completionData or {
		questId = questId,
		title = self:GetQuestTitle(questId),
		taskAnnouncementType = self:GetTaskAnnouncementType(questId),
	}

	completionData.title = ResolveCapturedQuestTitle(self, questId, completionData.title)

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
	if self.questsCompleted[questId] and self.GetTaskAreaStateStore then
		-- This is addon-owned state, so it is safe to clear while refresh work is
		-- restricted. Otherwise the deferred refresh mistakes completion for exit.
		self:GetTaskAreaStateStore("world")[questId] = nil
		self:GetTaskAreaStateStore("bonus")[questId] = nil
	end
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
	local questTitle = removalData.title
	if completionData and (not questTitle or questTitle == "" or self:IsPlaceholderQuestTitle(questId, questTitle)) then
		questTitle = completionData.title or questTitle
	end
	questTitle = questTitle or (L("Quest ") .. SafeText(questId, "?"))
	local iconAsset = (completionData and completionData.iconAsset) or removalData.iconAsset
	local iconKind = (completionData and completionData.iconKind) or removalData.iconKind

	if completed then
		local retiredData = self.retiredQuestIds and self.retiredQuestIds[questId]
		if type(retiredData) == "table" then
			retiredData.completionAnnounced = true
		end
		self:HandleQuestCompleted(questTitle, questId, {
			iconAsset = iconAsset,
			iconKind = iconKind,
		}, completionData.taskAnnouncementType or "quest")
	elseif not removalData.taskAnnouncementType then
		self:PublishAnnouncementEvent("QUEST_REMOVED", L("Quest Removed: ") .. SafeText(questTitle, L("Unknown")), questId)
	end

	self:ClearTrackedQuestState(questId)
	return true
end

function QuestTogether:HandleGroupRosterChanged(reason)
	local previousFingerprint = self.partyRosterFingerprint
	if self.RefreshPartyRoster then
		self:RefreshPartyRoster()
	end
	if self.isEnabled and rawget(self, "geographicCommsState") then self:BroadcastPartyVisualMetadata() end
	if self.isEnabled and self.partyRosterFingerprint ~= previousFingerprint and self.OnPartyQuestRosterChanged then
		self:OnPartyQuestRosterChanged()
	end
	if self.isEnabled and self.partyRosterFingerprint ~= previousFingerprint and self.InvalidateNameplateQuestState then
		-- Tooltip quest evidence includes unfinished objectives owned by grouped
		-- players. A membership change invalidates both positive and negative
		-- results, even when this player's quest log did not change.
		self:InvalidateNameplateQuestState(reason or "GROUP_ROSTER_UPDATE")
	end
end

function QuestTogether:PLAYER_REGEN_ENABLED()
	self:ScheduleAnnouncementChannelOrder()
	if self.FlushDeferredWork then
		self:FlushDeferredWork("PLAYER_REGEN_ENABLED")
	end
end

-- QUEST_ACCEPTED fires early; defer reads until QUEST_LOG_UPDATE.
function QuestTogether:QUEST_ACCEPTED(_, questIndexOrId, classicQuestId)
	-- Retail/Forever pass a quest ID; Classic also supplies the log index first.
	-- A present but unreadable second argument must not turn the index into an ID.
	if not self:CanAccessValue(classicQuestId) then return end
	local questId = questIndexOrId
	if classicQuestId ~= nil then questId = classicQuestId end
	local normalizedQuestId = NormalizeQuestId(self, questId)
	if not normalizedQuestId then
		return
	end

	-- A repeatable quest can be accepted before the previous removal timer runs.
	-- Finish the old lifecycle before installing the new acceptance token.
	if self.pendingQuestRemovals[normalizedQuestId] then
		self:ResolvePendingQuestRemoval(normalizedQuestId)
	end
	if self.retiredQuestIds and self.retiredQuestIds[normalizedQuestId] then
		self:GetPlayerTracker()[normalizedQuestId] = nil
		self.retiredQuestIds[normalizedQuestId] = nil
	end
	-- Duplicate acceptance events, or a scan that already watched this quest,
	-- must not erase an active observation and replay its area entry.
	if not self:GetPlayerTracker()[normalizedQuestId]
		and not (self.pendingQuestAcceptances and self.pendingQuestAcceptances[normalizedQuestId]) then
		self:GetTaskAreaSubsystemStateStore().displayAsObjectiveByQuestID[normalizedQuestId] = nil
		self:GetTaskAreaSubsystemStateStore().isWorldQuestByQuestID[normalizedQuestId] = nil
		self:ResetTaskQuestAreaObservation(normalizedQuestId)
	end
	self.questsCompleted[normalizedQuestId] = nil
	self.pendingQuestAcceptances = self.pendingQuestAcceptances or {}
	local acceptance = {}
	self.pendingQuestAcceptances[normalizedQuestId] = acceptance
	self:Debugf("QUEST", "quest_lifecycle questId=%s transition=acceptance_queued", tostring(normalizedQuestId))

	self:QueueQuestLogTask(function()
		if not self.pendingQuestAcceptances or self.pendingQuestAcceptances[normalizedQuestId] ~= acceptance then
			return
		end
		local tracker = self:GetPlayerTracker()
		if tracker[normalizedQuestId] ~= nil then
			self.pendingQuestAcceptances[normalizedQuestId] = nil
			return
		end

		local taskAnnouncementType
		local questLogIndex = self.API.GetQuestLogIndexForQuestID
			and self:SafeToNumber(self.API.GetQuestLogIndexForQuestID(normalizedQuestId))
		if not questLogIndex or questLogIndex <= 0 then
			-- Only current metadata or this acceptance lifetime may identify an
			-- off-log task. A delayed snapshot can still describe a retired quest.
			if self:ResolveTaskQuestIsWorldQuest(normalizedQuestId) == true then
				taskAnnouncementType = "world"
			elseif self:ResolveTaskQuestDisplayAsObjective(normalizedQuestId) == true then
				taskAnnouncementType = "bonus"
			end
			if taskAnnouncementType then
				local taskQuestTitle = self:GetQuestTitle(normalizedQuestId)
				self:WatchQuest(normalizedQuestId, { title = taskQuestTitle })
				self.pendingQuestAcceptances[normalizedQuestId] = nil
				self:RefreshTaskAreaStates(true)
				return
			end
			return false
		end

		local questInfo = self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex)
		if not self:CanAccessTable(questInfo) then
			return false
		end
		-- A recycled slot or a partially sanitized record is not evidence that
		-- this acceptance is ready. Supported adapters normalize legacy IDs too.
		if questInfo.isHeader == true or NormalizeQuestId(self, questInfo.questID) ~= normalizedQuestId then
			return false
		end
		local isWorldQuest = self:ResolveTaskQuestIsWorldQuest(normalizedQuestId, questInfo)
		if isWorldQuest == true then
			taskAnnouncementType = "world"
		elseif questInfo.isTask == true then
			-- Acceptance can drain before either area/snapshot reader has seen
			-- this task. Read its classification before deciding whether to hide
			-- it or announce an ordinary quest; unknown metadata stays queued.
			local isBonusObjective = self:ResolveTaskQuestDisplayAsObjective(normalizedQuestId)
			if isBonusObjective == true then
				taskAnnouncementType = "bonus"
			elseif isWorldQuest == nil or isBonusObjective == nil then
				return false
			else
				taskAnnouncementType = nil
			end
		end
		if questInfo.isHidden and not taskAnnouncementType then
			self.pendingQuestAcceptances[normalizedQuestId] = nil
			return
		end
		if type(questInfo.title) ~= "string" or self:SafeTrimString(questInfo.title, "") == "" then
			return false
		end
		self.pendingQuestAcceptances[normalizedQuestId] = nil

		if not taskAnnouncementType then
			self:PublishAnnouncementEvent(
				"QUEST_ACCEPTED",
				L("Quest Accepted: ") .. SafeText(questInfo.title, L("Unknown")),
				normalizedQuestId
			)
		end

		self:WatchQuest(normalizedQuestId, questInfo)
		self:Debugf("QUEST", "quest_lifecycle questId=%s transition=accepted title=%s", tostring(normalizedQuestId), SafeText(questInfo.title))
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

	self.retiredQuestIds = self.retiredQuestIds or {}
	local retiredData = self.retiredQuestIds[questId] or {}
	if self.pendingQuestAcceptances then
		self.pendingQuestAcceptances[questId] = nil
	end
	if retiredData.completionAnnounced or self.questsCompleted[questId] ~= nil then
		-- Preserve the first authoritative turn-in capture while removal is still
		-- pending; duplicate events can arrive after live metadata disappears.
		return
	end
	self:Debugf("QUEST", "quest_lifecycle questId=%s transition=turned_in pendingRemoval=%s", tostring(questId), tostring(self.pendingQuestRemovals[questId] ~= nil))

	local completionData = self:BuildTrackedQuestCompletionData(questId)
	-- Capture the latest known classification before retirement can prune it.
	self.retiredQuestIds[questId] = retiredData
	self.questsCompleted[questId] = completionData
	if self.pendingQuestRemovals[questId] then
		self:ResolvePendingQuestRemoval(questId)
	elseif not self:GetPlayerTracker()[questId] then
		-- QUEST_TURNED_IN can arrive after the one-frame removal fallback has
		-- drained, or before acceptance ever received a readable quest-log row.
		-- The turn-in is authoritative: use the completion data already built
		-- above instead of requiring a tracker that can no longer be populated.
		self.pendingQuestRemovals[questId] = retiredData.removalData or completionData
		self:ResolvePendingQuestRemoval(questId)
	end
end

function QuestTogether:QUEST_REMOVED(_, questId)
	questId = NormalizeQuestId(self, questId)
	if not questId then
		return
	end

	if self.pendingQuestAcceptances then
		self.pendingQuestAcceptances[questId] = nil
	end
	self.retiredQuestIds = self.retiredQuestIds or {}
	local retiredData = self.retiredQuestIds[questId] or {}
	if retiredData.completionAnnounced or retiredData.removalData then
		-- A duplicate removal belongs to the same lifetime; preserve its first
		-- capture and timer even when the quest's live metadata has disappeared.
		return
	end
	local removalData = self:BuildTrackedQuestRemovalData(questId)
	self.retiredQuestIds[questId] = retiredData
	self:Debugf("QUEST", "quest_lifecycle questId=%s transition=removed tracked=%s", tostring(questId), tostring(removalData ~= nil))
	if not removalData or retiredData.completionAnnounced then
		return
	end

	retiredData.removalData = removalData
	self.pendingQuestRemovals[questId] = removalData
	self.API.Delay(0, function()
		-- Compare the actual removal instance: an older timer must not consume a
		-- new acceptance/removal cycle for the same repeatable quest ID.
		if self.pendingQuestRemovals and self.pendingQuestRemovals[questId] == removalData then
			self:ResolvePendingQuestRemoval(questId)
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

	-- Every callback reads the current log, not the event-time state. Retain
	-- one progress scan while restrictions defer it, alongside independently
	-- queued acceptance lifetimes. Replacing the queue also resets this marker.
	local queue = self.onQuestLogUpdate
	if queue.progressScanQueued then return end
	queue.progressScanQueued = true
	self:QueueQuestLogTask(function()
		queue.progressScanQueued = nil
		local tracker = self:GetPlayerTracker()

		for questId, questData in pairs(tracker) do
			local normalizedQuestId = NormalizeQuestId(self, questId)
			if normalizedQuestId
				and not self.pendingQuestRemovals[normalizedQuestId]
				and not self.questsCompleted[normalizedQuestId]
				and not (self.retiredQuestIds and self.retiredQuestIds[normalizedQuestId])
			then
				questId = normalizedQuestId
				local questLogIndex = self.GetQuestLogIndexForQuest and self:GetQuestLogIndexForQuest(questId)
				if questLogIndex then
					local numObjectives = self.API.GetNumQuestLeaderBoards and self.API.GetNumQuestLeaderBoards(questLogIndex)
						or 0

					for objectiveIndex = 1, numObjectives do
						local objectiveText, objectiveType, finished, currentValue, requiredValue =
							self:GetNormalizedQuestObjectiveInfo(questId, objectiveIndex, false)

						if self:UpdateTrackedObjectiveProgress(questData, objectiveIndex, objectiveText, currentValue, questId) then
							local taskAnnouncementType = self:GetTaskAnnouncementType(questId)
							local eventType = "QUEST_PROGRESS"
							if taskAnnouncementType == "world" then
								eventType = "WORLD_QUEST_PROGRESS"
							elseif taskAnnouncementType == "bonus" then
								eventType = "BONUS_OBJECTIVE_PROGRESS"
							end
							self:PublishAnnouncementEvent(eventType, objectiveText, questId, {
								eventFacts = self:BuildAnnouncementFacts(eventType, objectiveIndex, objectiveType, finished, currentValue, requiredValue),
							})
						end
					end

					-- Retain milestone history when objective rows temporarily disappear.
					-- Only the current snapshot should shrink.
					questData.objectives = questData.objectives or {}
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

					local currentReadyForTurnIn = statusState and statusState.isReadyForTurnIn
					if type(currentReadyForTurnIn) == "boolean" then
						local wasNotReady = questData.isReadyForTurnIn == false
						local alreadyObserved = questData.readyForTurnInObserved == true
							or questData.isReadyForTurnIn == true
						questData.isReadyForTurnIn = currentReadyForTurnIn
						-- Unknown -> ready initializes silently. Once observed, a
						-- false/true API wobble must not replay this quest milestone.
						questData.readyForTurnInObserved = alreadyObserved or currentReadyForTurnIn
						if currentReadyForTurnIn and wasNotReady and not alreadyObserved
							and not self:GetTaskAnnouncementType(questId) then
							local questTitle = self:GetQuestDisplayTitle(questId, questData.title)
							self:PublishAnnouncementEvent(
								"QUEST_READY_TO_TURN_IN",
								L("Ready to Turn In: ") .. SafeText(questTitle, L("Unknown")),
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
	if self.OnPartyQuestLogChanged then self:OnPartyQuestLogChanged() end
	if (type(self.onQuestLogUpdate) == "table" and #self.onQuestLogUpdate > 0)
		or self:GetRuntimeFlag("pendingQuestLogScan", false) then
		if self.ScheduleQuestLogTaskDrain then
			self:ScheduleQuestLogTaskDrain("QUEST_LOG_UPDATE")
		else
			self:DrainQueuedQuestLogTasks()
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

function QuestTogether:GROUP_JOINED()
	self:StopLookingForPartnersOnGroupJoin()
	self:HandleGroupRosterChanged("GROUP_JOINED")
end

function QuestTogether:GROUP_ROSTER_UPDATE()
	self:HandleGroupRosterChanged("GROUP_ROSTER_UPDATE")
end

function QuestTogether:IGNORELIST_UPDATE()
	if self.PrunePartyJoin then self:PrunePartyJoin() end
	if self.PruneQTPlayerPresence then self:PruneQTPlayerPresence(true) end
	if self.ClearIgnoredAnnouncementBubbles then self:ClearIgnoredAnnouncementBubbles() end
	if self.PrunePlayerLocations then self:PrunePlayerLocations(true) end
	if self.RefreshPlayerLocationPins then self:RefreshPlayerLocationPins() end
	if self.CancelIgnoredPlayerQuestCompare then self:CancelIgnoredPlayerQuestCompare() end
end
