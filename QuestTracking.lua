-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Access = QuestTogether.NativeAccess
local SafeText = Access.Text
local tostring = SafeText

function QuestTogether:GetQuestTitle(questId, questInfo)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return L("Quest ") .. tostring(questId)
	end

	if questInfo and type(questInfo.title) == "string" and questInfo.title ~= "" then
		return questInfo.title
	end

	if self.EnsureQuestSnapshotStore then
		self:EnsureQuestSnapshotStore()
	end
	local snapshot = self.GetQuestSnapshot and self:GetQuestSnapshot(numericQuestId) or nil
	if snapshot and type(snapshot.title) == "string" and snapshot.title ~= "" then
		return snapshot.title
	end

	return L("Quest ") .. tostring(numericQuestId)
end

function QuestTogether:IsPlaceholderQuestTitle(questId, title)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return false
	end

	return type(title) == "string" and title == (L("Quest ") .. tostring(numericQuestId))
end

function QuestTogether:NormalizeQuestProgressPercent(progressValue)
	local numericProgress = self:SafeToNumber(progressValue)
	if numericProgress == nil then
		return nil
	end

	-- Blizzard progress bars can return floating values; format chat/objectives as whole percents.
	if numericProgress < 0 then
		numericProgress = 0
	elseif numericProgress > 100 then
		numericProgress = 100
	end

	return math.floor(numericProgress + 0.5)
end

function QuestTogether:StripTrailingParentheticalPercent(objectiveText)
	if type(objectiveText) ~= "string" or objectiveText == "" or self:IsSecretValue(objectiveText) then
		return objectiveText
	end

	local strippedText = string.gsub(objectiveText, "%s*%(%d+%%%s*%)%s*$", "")
	if strippedText == "" then
		return objectiveText
	end

	return strippedText
end

function QuestTogether:GetQuestLogIndexForQuest(questId, questInfo)
	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
		return nil
	end
	local questLogIndex = questInfo and self:SafeToNumber(questInfo.questLogIndex) or nil
	if questLogIndex ~= nil then
		questLogIndex = math.floor(questLogIndex + 0.5)
		if questLogIndex <= 0 then
			questLogIndex = nil
		end
	end

	if questLogIndex then
		local row = self.API and self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex)
		if not row or self:NormalizeQuestID(row.questID) ~= self:NormalizeQuestID(questId) then
			questLogIndex = nil
		end
	end

	if not questLogIndex and self.API and self.API.GetQuestLogIndexForQuestID then
		local normalizedQuestId = self:NormalizeQuestID(questId)
		if normalizedQuestId then
			local resolvedQuestLogIndex = self.API.GetQuestLogIndexForQuestID(normalizedQuestId)
			questLogIndex = self:SafeToNumber(resolvedQuestLogIndex)
			if questLogIndex ~= nil then
				questLogIndex = math.floor(questLogIndex + 0.5)
				if questLogIndex <= 0 then
					questLogIndex = nil
				end
			end
		end
	end

	return questLogIndex
end

function QuestTogether:NormalizeQuestObjectiveCounters(kind, finished, current, required)
	-- Forever can report 1/1 for an unfinished one-step objective (for
	-- example, Use Walk on Air). Its explicit completion flag is authoritative.
	-- Percentage objectives have a separate source and must not use this rule.
	if kind ~= "progressbar" and finished == false and current == 1 and required == 1 then
		current = 0
	end
	return current, required
end

-- Read only already-tracked progress during ordinary combat. This does not
-- rebuild the log, initialize acceptances, select quests or query tooltips.
function QuestTogether:GetCombatQuestProgress(questId)
	if self:IsWorkBlocked("quest_progress_read") then
		return nil
	end
	local index = self.API.GetQuestLogIndexForQuestID(questId)
	if not index then
		return nil
	end
	local count = self.API.GetNumQuestLeaderBoards(index, true)
	if not count or count < 0 or count > 100 then
		return nil
	end
	local result = { objectives = {} }
	for slot = 1, count do
		local text, kind, finished, current, required =
			self:GetNormalizedQuestObjectiveInfo(questId, slot, false, index)
		-- An unreadable row must not erase the last known objective or advance
		-- its milestone. Keep the ordinary queued scan as the recovery path.
		if
			type(text) ~= "string"
			or text == ""
			or type(kind) ~= "string"
			or (kind == "progressbar" and current == nil)
		then
			return nil
		end
		result.objectives[slot] =
			{ text = text, kind = kind, finished = finished, current = current, required = required }
	end
	result.isComplete = self.API.IsQuestComplete and self.API.IsQuestComplete(questId)
	result.isReadyForTurnIn = self.API.IsQuestReadyForTurnIn and self.API.IsQuestReadyForTurnIn(questId)
	local row = self.API.GetQuestLogInfo(index)
	if not row or self:NormalizeQuestID(row.questID) ~= questId then
		return nil
	end
	return result
end

function QuestTogether:GetNormalizedQuestObjectiveInfo(questId, objectiveIndex, displayComplete, questLogIndex)
	local objectiveText, objectiveType, finished, currentValue, requiredValue = nil, nil, nil, nil, nil
	if self.API and self.API.GetQuestObjectiveInfo then
		objectiveText, objectiveType, finished, currentValue, requiredValue =
			self.API.GetQuestObjectiveInfo(questId, objectiveIndex, displayComplete, questLogIndex)
	end
	if objectiveText == nil and objectiveType == nil and currentValue == nil then
		objectiveText = ""
	end

	if objectiveType == "progressbar" then
		local baseObjectiveText = self:StripTrailingParentheticalPercent(objectiveText)
		if type(baseObjectiveText) ~= "string" then
			baseObjectiveText = type(objectiveText) == "string" and objectiveText or ""
		end

		local progress = self.API
			and self.API.GetQuestProgressBarPercent
			and self.API.GetQuestProgressBarPercent(questId)
		local roundedProgress = self:NormalizeQuestProgressPercent(progress)
		if roundedProgress ~= nil then
			if baseObjectiveText ~= "" then
				objectiveText = tostring(roundedProgress) .. "% " .. baseObjectiveText
			else
				objectiveText = tostring(roundedProgress) .. "%"
			end
			currentValue = roundedProgress
		else
			objectiveText = baseObjectiveText
			-- The objective counter is not a percentage when the percent read is unavailable.
			currentValue = nil
		end
	end

	currentValue, requiredValue =
		self:NormalizeQuestObjectiveCounters(objectiveType, finished, currentValue, requiredValue)
	return objectiveText, objectiveType, finished, currentValue, requiredValue
end

function QuestTogether:GetPlayerTracker()
	local characterKey = self.activeCharacterKey or self:GetCurrentCharacterKey() or self:GetPlayerName() or "Unknown"
	if not self.db.global.questTrackers[characterKey] then
		self.db.global.questTrackers[characterKey] = {}
	end
	return self.db.global.questTrackers[characterKey]
end

function QuestTogether:GetMonitoredQuestCount()
	if not self:GetRuntimeFlag("questTrackerReady", false) or not self.db or not self.db.global then
		return nil
	end
	local count = 0
	for id, quest in pairs(self:GetPlayerTracker()) do
		if self:NormalizeQuestID(id) and type(quest) == "table" then
			count = count + 1
		end
	end
	return count
end

function QuestTogether:QueueQuestLogTask(taskFn)
	if type(taskFn) == "function" then
		table.insert(self.onQuestLogUpdate, taskFn)
		-- QUEST_ACCEPTED and UNIT_QUEST_LOG_CHANGED can precede readable log
		-- data. Only QUEST_LOG_UPDATE may release this batch into the scheduler.
	end
end

function QuestTogether:ResetQuestEventState()
	self:ResetObjectiveAnnouncements()
	self.onQuestLogUpdate = {}
	self.questsCompleted = {}
	self.pendingQuestRemovals = {}
	self.pendingQuestAcceptances = {}
	self.retiredQuestIds = {}
end

-- Full quest log scan to build local objective snapshots.
function QuestTogether:ReconcileQuestTracking(snapshot)
	if
		not self:GetRuntimeFlag("questTrackerReady", false)
		or not self.db
		or not self.db.global
		or not snapshot
		or snapshot.lastUnreadableRow
	then
		return
	end
	local tracker = self:GetPlayerTracker()
	-- Later complete log data can contain quests missing from an initially
	-- empty/partial login snapshot. Initialize only missing entries; acceptance
	-- and removal events retain ownership of their own lifecycle and messages.
	for _, questID in ipairs(snapshot.order or {}) do
		local info = snapshot.byQuestID[questID]
		if
			info
			and not info.isHidden
			and not tracker[questID]
			and not (self.pendingQuestAcceptances and self.pendingQuestAcceptances[questID])
			and not (self.retiredQuestIds and self.retiredQuestIds[questID])
		then
			self:WatchQuest(questID, info)
		end
	end
end

function QuestTogether:PrintQuestScanAnnouncement(monitoredCount)
	if self:GetOption("showChatLogs") == false then
		self.pendingQuestScanAnnouncement = nil
		return
	end
	if self:IsLocalVIPVerificationPending() and not self:IsVerifiedDeveloper(self:GetPlayerFullName()) then
		-- Only the local presentation waits. Keep at most the latest scan count;
		-- quest tracking and the wire announcement retain their normal timing.
		self.pendingQuestScanAnnouncement = { count = monitoredCount, lifetime = self:GetDeferredWorkStateStore() }
		return
	end
	self.pendingQuestScanAnnouncement = nil
	self:PrintConsoleAnnouncement(self:GetMonitoredQuestCountText(monitoredCount))
end

function QuestTogether:FlushPendingQuestScanAnnouncement()
	if self:GetOption("showChatLogs") == false then
		self.pendingQuestScanAnnouncement = nil
		return
	end
	local pending = self.pendingQuestScanAnnouncement
	if not pending then
		return
	end
	if not self.isEnabled or self.isLoggingOut or pending.lifetime ~= self:GetDeferredWorkStateStore() then
		self.pendingQuestScanAnnouncement = nil
		return
	end
	if self:IsLocalVIPVerificationPending() then
		return
	end
	self.pendingQuestScanAnnouncement = nil
	self:PrintConsoleAnnouncement(self:GetMonitoredQuestCountText(pending.count))
end

function QuestTogether:ScanQuestLog(shouldAnnounceTaskAreas)
	if not self.db or not self.db.global then
		return
	end

	if self.IsWorkBlocked and self:IsWorkBlocked("quest_log_drain") then
		self:ScheduleDeferredWork("quest_log_drain", "full_scan", function()
			self:ScanQuestLog(shouldAnnounceTaskAreas)
		end)
		return
	end
	local snapshot
	if self.RebuildQuestSnapshotStore then
		snapshot = self:RebuildQuestSnapshotStore()
		if snapshot and snapshot.lastUnreadableRow then
			-- Keep one retry intent for the next real log update. A successful
			-- snapshot refresh alone does not initialize objective tracking.
			self:SetRuntimeFlag("pendingQuestLogScan", true)
			return
		end
	end
	self:SetRuntimeFlag("pendingQuestLogScan", false)

	local tracker = self:GetPlayerTracker()
	local pendingAcceptances = self.pendingQuestAcceptances or {}
	local seenQuestIDs = {}

	local snapshotByQuestID = self.GetQuestSnapshotByQuestID and self:GetQuestSnapshotByQuestID() or nil
	local snapshotOrder = self.GetQuestSnapshotOrder and self:GetQuestSnapshotOrder() or {}
	for index = 1, #snapshotOrder do
		local questID = snapshotOrder[index]
		local questInfo = snapshotByQuestID and snapshotByQuestID[questID] or nil
		if
			questInfo
			and questInfo.isHidden ~= true
			and not (self.retiredQuestIds and self.retiredQuestIds[questID])
		then
			seenQuestIDs[questID] = true
			-- Acceptance owns its readiness checks and announcement. A readable
			-- snapshot ID alone must not consume its still-unreadable title/type.
			if not pendingAcceptances[questID] then
				self:WatchQuest(questID, questInfo)
			end
		end
	end

	if self.RefreshTaskAreaStates then
		self:RefreshTaskAreaStates(shouldAnnounceTaskAreas == true, snapshot)
	end

	-- Area task quests can exist outside normal quest-log rows.
	-- Add them explicitly so progress announcements can still operate on them.
	if self.GetActiveWorldQuestAreaSnapshot then
		for questId, questTitle in pairs(self:GetActiveWorldQuestAreaSnapshot()) do
			seenQuestIDs[questId] = true
			if not tracker[questId] and not pendingAcceptances[questId] then
				self:WatchQuest(questId, { title = questTitle })
			end
		end
	end
	if self.GetActiveBonusObjectiveAreaSnapshot then
		for questId, questTitle in pairs(self:GetActiveBonusObjectiveAreaSnapshot()) do
			seenQuestIDs[questId] = true
			if not tracker[questId] and not pendingAcceptances[questId] then
				self:WatchQuest(questId, { title = questTitle })
			end
		end
	end

	for questID in pairs(tracker) do
		if not seenQuestIDs[questID] then
			tracker[questID] = nil
		end
	end
	self:SetRuntimeFlag("questTrackerReady", true)
	local monitoredCount = self:GetMonitoredQuestCount()
	local scanMessage = self:GetMonitoredQuestCountText(monitoredCount)
	self:PrintQuestScanAnnouncement(monitoredCount)
	if self.BuildLocalAnnouncementEvent and self.SendAnnouncementWireEvent then
		local eventData = self:BuildLocalAnnouncementEvent("SCAN_STATUS", scanMessage, nil, {
			eventFacts = self:BuildAnnouncementFacts("SCAN_STATUS", nil, nil, nil, monitoredCount),
		})
		if eventData then
			self:SendAnnouncementWireEvent(eventData)
		end
	end
end

-- Store the current objective text state for one quest.
function QuestTogether:WatchQuest(questId, questInfo)
	local numericQuestId = self:NormalizeQuestID(questId)

	if not numericQuestId or (self.retiredQuestIds and self.retiredQuestIds[numericQuestId]) then
		return
	end

	if not questInfo and self.GetQuestSnapshot then
		questInfo = self:GetQuestSnapshot(numericQuestId)
	end
	if not questInfo then
		return
	end

	local tracker = self:GetPlayerTracker()
	local questLogIndex = self.GetQuestLogIndexForQuest and self:GetQuestLogIndexForQuest(numericQuestId, questInfo)
		or nil
	local questTitle = self:GetQuestTitle(numericQuestId, questInfo)
	local existingTrackedQuest = tracker[numericQuestId]
	if self:IsPlaceholderQuestTitle(numericQuestId, questTitle) then
		local existingTitle = existingTrackedQuest and existingTrackedQuest.title or nil
		if
			type(existingTitle) == "string"
			and existingTitle ~= ""
			and not self:IsPlaceholderQuestTitle(numericQuestId, existingTitle)
		then
			if existingTrackedQuest.titleLocale == self:GetEventLocale() then
				questTitle = existingTitle
			end
		end
	end
	local initialStatusState = self.GetTrackedQuestStatusState and self:GetTrackedQuestStatusState(numericQuestId, true)
		or nil

	tracker[numericQuestId] = {
		title = questTitle,
		titleLocale = self:GetEventLocale(),
		taskAnnouncementType = self:GetTaskAnnouncementType(numericQuestId),
		objectives = {},
		-- Cached numeric objective values used to gate progress announcements.
		-- This avoids noisy chat lines caused by text-only objective rewrites.
		objectiveValues = {},
		objectiveProgressHighWater = existingTrackedQuest and existingTrackedQuest.objectiveProgressHighWater or {},
		objectiveProgressObservations = existingTrackedQuest and existingTrackedQuest.objectiveProgressObservations
			or {},
		isComplete = initialStatusState and initialStatusState.isComplete == true or false,
		isReadyForTurnIn = initialStatusState and initialStatusState.isReadyForTurnIn,
		-- Scans establish a silent baseline, including quests whose objectives
		-- are already complete before ReadyForTurnIn has caught up. Preserve
		-- the milestone across rescans and transient false live reads. A new
		-- acceptance or enable lifetime starts with a fresh tracker instead.
		readyForTurnInObserved = (
			existingTrackedQuest
			and (existingTrackedQuest.readyForTurnInObserved == true or existingTrackedQuest.isReadyForTurnIn == true)
		)
			or (initialStatusState and initialStatusState.isReadyForTurnIn == true)
			or (not existingTrackedQuest and ((initialStatusState and initialStatusState.isComplete == true) or questInfo.isComplete == true))
			or false,
	}

	if not questLogIndex then
		return
	end

	local numObjectives = self.API
			and self.API.GetNumQuestLeaderBoards
			and self.API.GetNumQuestLeaderBoards(questLogIndex)
		or 0
	for objectiveIndex = 1, numObjectives do
		local objectiveText, _, _, currentValue =
			self:GetNormalizedQuestObjectiveInfo(numericQuestId, objectiveIndex, false)
		if self.UpdateTrackedObjectiveProgress then
			self:UpdateTrackedObjectiveProgress(tracker[numericQuestId], objectiveIndex, objectiveText, currentValue)
		else
			tracker[numericQuestId].objectives[objectiveIndex] = objectiveText
			tracker[numericQuestId].objectiveValues[objectiveIndex] = self:SafeToNumber(currentValue)
		end
	end
end
