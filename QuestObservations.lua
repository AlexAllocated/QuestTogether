-- Owns native quest-log acquisition and confirmed classification history.
-- A complete scan publishes atomically; consumers never independently re-read
-- live classification. Event-time captures use ObserveQuestClassification.
local QuestTogether = _G.QuestTogether

local function ReadBoolean(addon, value)
	if addon:CanAccessValue(value) and type(value) == "boolean" then
		return value
	end
end

function QuestTogether:GetQuestClassification(questId)
	local state = self:GetQuestSnapshotStateStore()
	return state.classificationsByQuestID and state.classificationsByQuestID[questId]
end

local function ReadClassification(addon, questId, info)
	local retired = addon.retiredQuestIds and addon.retiredQuestIds[questId]
	local previous = not retired and addon:GetQuestClassification(questId) or nil
	local world = addon.API.IsWorldQuest and ReadBoolean(addon, addon.API.IsWorldQuest(questId))
	if world == nil then
		world = ReadBoolean(addon, info and info.isWorldQuest)
	end
	if world == nil and previous then
		world = previous.isWorldQuest
	end
	local bonus
	if world == true then
		bonus = false
	else
		local task = addon.API.GetTaskQuestInfoByQuestID and addon.API.GetTaskQuestInfoByQuestID(questId)
		if addon:CanAccessTable(task) and type(task) == "table" then
			bonus = ReadBoolean(addon, task.displayAsObjective)
		end
		if bonus == nil and previous then
			bonus = previous.displayAsObjective
		end
	end
	return { isWorldQuest = world, displayAsObjective = bonus }
end

function QuestTogether:ObserveQuestClassification(questId, info)
	local id = self:NormalizeQuestID(questId)
	if not id then
		return {}
	end
	local classification = ReadClassification(self, id, info)
	if not (self.retiredQuestIds and self.retiredQuestIds[id]) then
		local state = self:GetQuestSnapshotStateStore()
		state.classificationsByQuestID = state.classificationsByQuestID or {}
		state.classificationsByQuestID[id] = classification
	end
	return classification
end

function QuestTogether:ForgetQuestClassification(questId)
	local state = self:GetQuestSnapshotStateStore()
	if state.classificationsByQuestID then
		state.classificationsByQuestID[questId] = nil
	end
end

function QuestTogether:ResetQuestClassifications()
	self:GetQuestSnapshotStateStore().classificationsByQuestID = {}
end

function QuestTogether:RebuildQuestSnapshotStore()
	local snapshotState = self.GetQuestSnapshotStateStore and self:GetQuestSnapshotStateStore() or nil
	if type(snapshotState) ~= "table" then
		return nil
	end
	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
		return snapshotState, false
	end

	-- Build privately, then publish atomically. An unreadable row must not erase
	-- the previous snapshot or make an active quest look removed.
	local snapshotByQuestID = {}
	local snapshotOrder = {}
	local classifications = {}

	local totalEntries = self.API and self.API.GetNumQuestLogEntries and self.API.GetNumQuestLogEntries()
	totalEntries = self:SafeToNumber(totalEntries)
	if totalEntries == nil or totalEntries < 0 then
		if snapshotState.lastUnreadableRow ~= "count" then
			self:Debug("snapshot_deferred reason=unknown_count", "QUEST")
		end
		snapshotState.lastUnreadableRow = "count"
		return snapshotState, false
	end
	totalEntries = math.max(0, math.floor(totalEntries + 0.5))
	local sampleRows = {}

	for questLogIndex = 1, totalEntries do
		local questInfo = self.API.GetQuestLogInfo(questLogIndex)
		if
			type(questInfo) ~= "table"
			or not self:CanAccessTable(questInfo)
			or (questInfo.isHeader ~= true and not self:NormalizeQuestID(questInfo.questID))
		then
			if snapshotState.lastUnreadableRow ~= questLogIndex then
				self:Debugf(
					"quest",
					"snapshot_deferred unreadable_row=%d rows=%d generation=%d",
					questLogIndex,
					totalEntries,
					snapshotState.generation or 0
				)
			end
			snapshotState.lastUnreadableRow = questLogIndex
			return snapshotState, false
		end
		if questLogIndex <= 5 then
			sampleRows[#sampleRows + 1] = {
				index = questLogIndex,
				title = questInfo and questInfo.title or nil,
				isHeader = questInfo and questInfo.isHeader == true or false,
				questID = questInfo and questInfo.questID or nil,
				isTask = questInfo and questInfo.isTask == true or false,
				isOnMap = ReadBoolean(self, questInfo and questInfo.isOnMap),
				hasLocalPOI = ReadBoolean(self, questInfo and questInfo.hasLocalPOI),
			}
		end
		if questInfo and questInfo.isHeader ~= true then
			local numericQuestID = self:NormalizeQuestID(questInfo.questID)
			if numericQuestID then
				local classification = ReadClassification(self, numericQuestID, questInfo)
				if not (self.retiredQuestIds and self.retiredQuestIds[numericQuestID]) then
					classifications[numericQuestID] = classification
				end
				local isWorldQuest = classification.isWorldQuest
				local isTaskQuest = questInfo.isTask == true or isWorldQuest == true
				local displayAsObjective = classification.displayAsObjective

				local snapshot = {
					questID = numericQuestID,
					questLogIndex = self:SafeToNumber(questInfo.questLogIndex) or questLogIndex,
					title = type(questInfo.title) == "string" and questInfo.title or nil,
					isHidden = questInfo.isHidden == true,
					isTask = isTaskQuest and true or false,
					isOnMap = ReadBoolean(self, questInfo.isOnMap),
					hasLocalPOI = ReadBoolean(self, questInfo.hasLocalPOI),
					isComplete = questInfo.isComplete == true,
					isWorldQuest = isWorldQuest,
					displayAsObjective = displayAsObjective,
					isBonusObjective = displayAsObjective,
					tagInfo = nil,
					poiIcon = nil,
				}
				snapshot.taskAnnouncementType = snapshot.isWorldQuest and "world"
					or (snapshot.isBonusObjective and "bonus" or nil)

				snapshotByQuestID[numericQuestID] = snapshot
				snapshotOrder[#snapshotOrder + 1] = numericQuestID
			end
		end
	end

	snapshotState.classificationsByQuestID = classifications
	wipe(snapshotState.byQuestID)
	wipe(snapshotState.order)
	for questID, snapshot in pairs(snapshotByQuestID) do
		snapshotState.byQuestID[questID] = snapshot
	end
	for index, questID in ipairs(snapshotOrder) do
		snapshotState.order[index] = questID
	end
	snapshotState.lastUnreadableRow = nil
	snapshotState.generation = (snapshotState.generation or 0) + 1
	if self.OnQuestObservationsCommitted then
		self:OnQuestObservationsCommitted(snapshotState)
	end

	if totalEntries > 0 and #snapshotOrder == 0 and not snapshotState.didLogEmptyBuildDiagnostics then
		snapshotState.didLogEmptyBuildDiagnostics = true
		local sampleParts = {}
		for index = 1, #sampleRows do
			local row = sampleRows[index]
			sampleParts[#sampleParts + 1] = string.format(
				"#%d title=%s header=%s questID=%s task=%s onMap=%s poi=%s",
				row.index,
				self:SafeToString(row.title, "<nil>"),
				tostring(row.isHeader),
				self:SafeToString(row.questID, "<nil>"),
				tostring(row.isTask),
				tostring(row.isOnMap),
				tostring(row.hasLocalPOI)
			)
		end
		self:Debug(
			"empty quest snapshot. totalEntries="
				.. tostring(totalEntries)
				.. " samples: "
				.. table.concat(sampleParts, " | "),
			"quest"
		)
	elseif #snapshotOrder > 0 then
		snapshotState.didLogEmptyBuildDiagnostics = false
	end

	return snapshotState, true
end

function QuestTogether:EnsureQuestSnapshotStore()
	local snapshotState = self.GetQuestSnapshotStateStore and self:GetQuestSnapshotStateStore() or nil
	if type(snapshotState) ~= "table" then
		return nil
	end
	if (snapshotState.generation or 0) == 0 then
		if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
			return snapshotState, false
		end
		return self:RebuildQuestSnapshotStore()
	end
	return snapshotState, false
end

function QuestTogether:IsWorldQuest(questId)
	local id = self:NormalizeQuestID(questId)
	if not id then
		return false
	end
	local classification = self:GetQuestClassification(id)
	if classification and classification.isWorldQuest ~= nil then
		return classification.isWorldQuest == true
	end
	local tracker = self.GetPlayerTracker and self.db and self.db.global and self:GetPlayerTracker()
	return tracker and tracker[id] and tracker[id].taskAnnouncementType == "world" or false
end

function QuestTogether:IsBonusObjective(questId)
	local id = self:NormalizeQuestID(questId)
	if not id then
		return false
	end
	local classification = self:GetQuestClassification(id)
	if classification and classification.displayAsObjective ~= nil then
		return classification.displayAsObjective == true
	end
	local area = self.GetTaskAreaStateStore and self:GetTaskAreaStateStore("bonus")
	return area and area[id] ~= nil or false
end

-- Completion/removal events can arrive after the row disappears. Capture once
-- at that boundary; ordinary presentation readers remain snapshot-only.
function QuestTogether:ObserveQuestAnnouncementType(questId)
	local value = self:ObserveQuestClassification(questId)
	if value.isWorldQuest == true then
		return "world"
	end
	if value.displayAsObjective == true then
		return "bonus"
	end
	if value.isWorldQuest == nil and value.displayAsObjective == nil then
		return self:GetTaskAnnouncementType(questId)
	end
end
