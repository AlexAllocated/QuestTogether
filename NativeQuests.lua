-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local Access = QuestTogether.NativeAccess
local CanAccessForeignValue, CanAccessForeignTable = Access.Value, Access.Table
local Values = QuestTogether.NativeQuestValues
local ReadPartyWaypoint = Values.ReadPartyWaypoint
local ReadOptionalString = Values.ReadOptionalString
local SanitizeQuestInfoEnumValue = Values.SanitizeQuestInfoEnumValue
local SanitizeQuestLevel = Values.SanitizeQuestLevel
local SanitizeSuggestedQuestGroup = Values.SanitizeSuggestedQuestGroup
local BuildSanitizedQuestLogInfoRecord = Values.BuildSanitizedQuestLogInfoRecord
local BuildSanitizedQuestLogInfoFromRawInfo = Values.BuildSanitizedQuestLogInfoFromRawInfo
local MergeSanitizedQuestLogInfo = Values.MergeSanitizedQuestLogInfo

local function CanCallNativeMapLua(func)
	return CanAccessForeignValue(func)
		and type(func) == "function"
		and CanAccessForeignValue(securecallfunction)
		and type(securecallfunction) == "function"
end

local function CallNativeMapLua(func, ...)
	if QuestTogether:IsWorkBlocked("foreign_frame_mutation") or not CanCallNativeMapLua(func) then
		return false
	end
	-- Pass Blizzard's function itself, never a QT closure. Its Lua helpers write
	-- map/pin state that the native UI later reuses in combat. A direct call can
	-- contaminate that state even though the original action was out of combat.
	return pcall(securecallfunction, func, ...)
end

local function QuestChainID(value)
	local id = QuestTogether:SafeToNumber(value)
	return id and id >= 1 and id <= 1000000000 and id % 1 == 0 and id or nil
end

local function ReadQuestChainLine(info)
	if not CanAccessForeignTable(info) then
		return nil
	end
	local result = {}
	for _, key in ipairs({ "questLineID", "questID", "startMapID" }) do
		result[key] = QuestChainID(info[key])
	end
	if not result.questLineID then
		return nil
	end
	for _, key in ipairs({ "questLineName", "questName" }) do
		local text = ReadOptionalString(info[key])
		if text and #text <= 1024 then
			result[key] = text
		end
	end
	for _, key in ipairs({ "x", "y" }) do
		local value = QuestTogether:SafeToNumber(info[key])
		if value and value >= 0 and value <= 1 then
			result[key] = value
		end
	end
	return result
end

local function ReadQuestChainNative(method, ...)
	if QuestTogether:IsRuntimeRestricted() or not CanAccessForeignTable(C_QuestLine) then
		return nil
	end
	local fn = C_QuestLine[method]
	if not CanAccessForeignValue(fn) or type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	return ok and CanAccessForeignValue(result) and result or nil
end

QuestTogether:RegisterNativeAPI("quests", {
	GetQuestLogIndexForQuestID = function(questID)
		if QuestTogether:IsWorkBlocked("quest_progress_read") then
			return nil
		end
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		local snapshotState = QuestTogether
				and QuestTogether.GetQuestSnapshotStateStore
				and QuestTogether:GetQuestSnapshotStateStore()
			or nil
		local snapshotByQuestID = snapshotState and snapshotState.byQuestID or nil
		local snapshot = snapshotByQuestID and snapshotByQuestID[numericQuestID] or nil
		if type(snapshot) == "table" then
			local snapshotQuestLogIndex = QuestTogether
					and QuestTogether.SafeToNumber
					and QuestTogether:SafeToNumber(snapshot.questLogIndex)
				or nil
			if snapshotQuestLogIndex and snapshotQuestLogIndex > 0 then
				local rowIndex = math.floor(snapshotQuestLogIndex + 0.5)
				local row = QuestTogether.API.GetQuestLogInfo(rowIndex)
				if row and QuestTogether:NormalizeQuestID(row.questID) == numericQuestID then
					return rowIndex
				end
			end
		end
		local rawCount = QuestTogether
				and QuestTogether.API
				and QuestTogether.API.GetNumQuestLogEntries
				and QuestTogether.API.GetNumQuestLogEntries()
			or 0
		local numericCount = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawCount)
			or nil
		if numericCount and numericCount > 0 then
			numericCount = math.floor(numericCount + 0.5)
			for questLogIndex = 1, numericCount do
				local entryInfo = QuestTogether
						and QuestTogether.API
						and QuestTogether.API.GetQuestLogInfo
						and QuestTogether.API.GetQuestLogInfo(questLogIndex)
					or nil
				local normalizedEntryQuestID = entryInfo
						and QuestTogether
						and QuestTogether.NormalizeQuestID
						and QuestTogether:NormalizeQuestID(entryInfo.questID)
					or nil
				if normalizedEntryQuestID == numericQuestID then
					return questLogIndex
				end
			end
		end
		return nil
	end,
	IsQuestFlaggedCompleted = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
			local ok, isCompleted = pcall(C_QuestLog.IsQuestFlaggedCompleted, numericQuestID)
			if ok and CanAccessForeignValue(isCompleted) and type(isCompleted) == "boolean" then
				return isCompleted
			end
			return nil
		end
		return nil
	end,
	GetQuestChainClient = function()
		if QuestTogether:UsesRegionalPlayerNames() then
			return "forever"
		end
		if
			CanAccessForeignValue(WOW_PROJECT_ID)
			and CanAccessForeignValue(WOW_PROJECT_MAINLINE)
			and type(WOW_PROJECT_MAINLINE) == "number"
			and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
		then
			return "retail"
		end
		return "unsupported"
	end,
	CanReadNativeQuestChains = function()
		if QuestTogether:IsRuntimeRestricted() or not CanAccessForeignTable(C_QuestLine) then
			return false
		end
		for _, method in ipairs({ "GetQuestLineInfo", "GetQuestLineQuests" }) do
			local fn = C_QuestLine[method]
			if not CanAccessForeignValue(fn) or type(fn) ~= "function" then
				return false
			end
		end
		return true
	end,
	GetQuestLineInfo = function(questID, mapID)
		local id = QuestChainID(questID)
		if not id then
			return nil
		end
		local raw = ReadQuestChainNative("GetQuestLineInfo", id, QuestChainID(mapID), false)
		local ok, result = pcall(ReadQuestChainLine, raw)
		return ok and result or nil
	end,
	GetQuestLineQuests = function(lineID)
		local id = QuestChainID(lineID)
		if not id then
			return nil
		end
		local raw = ReadQuestChainNative("GetQuestLineQuests", id)
		if not CanAccessForeignTable(raw) then
			return nil
		end
		local result, seen = {}, {}
		local ok = pcall(function()
			for index = 1, 10001 do
				local value = raw[index]
				if value == nil then
					return
				end
				local quest = QuestChainID(value)
				if not quest or index > 10000 then
					error("invalid quest line", 0)
				end
				if not seen[quest] then
					seen[quest], result[#result + 1] = true, quest
				end
			end
		end)
		return ok and result or nil
	end,
	GetAvailableQuestLines = function(mapID)
		local id = QuestChainID(mapID)
		if not id then
			return nil
		end
		local raw = ReadQuestChainNative("GetAvailableQuestLines", id)
		if not CanAccessForeignTable(raw) then
			return nil
		end
		local result = {}
		local ok = pcall(function()
			for index = 1, 1001 do
				if raw[index] == nil then
					return
				end
				if index > 1000 then
					error("invalid quest lines", 0)
				end
				local line = ReadQuestChainLine(raw[index])
				if line then
					result[#result + 1] = line
				end
			end
		end)
		return ok and result or nil
	end,
	RequestQuestLinesForMap = function(mapID)
		local id = QuestChainID(mapID)
		if not id or QuestTogether:IsRuntimeRestricted() or not CanAccessForeignTable(C_QuestLine) then
			return false
		end
		local fn = C_QuestLine.RequestQuestLinesForMap
		return CanAccessForeignValue(fn) and type(fn) == "function" and pcall(fn, id) or false
	end,
	RequestQuestChainQuestData = function(questID)
		local id = QuestChainID(questID)
		if not id or QuestTogether:IsRuntimeRestricted() or not CanAccessForeignTable(C_QuestLog) then
			return false
		end
		local fn = C_QuestLog.RequestLoadQuestByID
		return CanAccessForeignValue(fn) and type(fn) == "function" and pcall(fn, id) or false
	end,
	GetQuestChainQuestTitle = function(questID)
		local id = QuestChainID(questID)
		if not id or QuestTogether:IsRuntimeRestricted() or not CanAccessForeignTable(C_QuestLog) then
			return nil
		end
		local fn = C_QuestLog.GetTitleForQuestID
		if not CanAccessForeignValue(fn) or type(fn) ~= "function" then
			return nil
		end
		local ok, value = pcall(fn, id)
		local title = ok and ReadOptionalString(value)
		return title and #title <= 1024 and title or nil
	end,
	GetQuestChainUnitInfo = function(unitToken)
		if
			type(unitToken) ~= "string"
			or not (unitToken == "player" or unitToken == "target" or unitToken:match("^party[1-4]$") or unitToken:match(
				"^raid%d%d?$"
			))
			or QuestTogether:IsRuntimeRestricted()
		then
			return nil
		end
		local result = {}
		local ok, _, class, classID = pcall(UnitClass, unitToken)
		if ok then
			result.classFile, result.classID = ReadOptionalString(class), QuestChainID(classID)
		end
		local raceOK, _, _, raceID = pcall(UnitRace, unitToken)
		if raceOK then
			result.raceID = QuestChainID(raceID)
		end
		local levelOK, level = pcall(UnitLevel, unitToken)
		if levelOK then
			result.level = QuestChainID(level)
		end
		local factionOK, faction = pcall(UnitFactionGroup, unitToken)
		if factionOK then
			result.faction = ReadOptionalString(faction)
		end
		return result
	end,
	OpenQuestChainMap = function(mapID)
		local id = QuestChainID(mapID)
		if not id or QuestTogether:IsWorkBlocked("foreign_frame_mutation") or not CanAccessForeignTable(C_Map) then
			return false
		end
		local fn = C_Map.OpenWorldMap
		if not CanAccessForeignValue(fn) or type(fn) ~= "function" or not QuestTogether.API.GetMapInfo(id) then
			return false
		end
		return pcall(fn, id)
	end,
	GetCharacterQuestHistoryStatus = function(questID)
		local id = QuestTogether:SafeToNumber(questID)
		if
			not id
			or id < 1
			or id > 1000000000
			or id % 1 ~= 0
			or QuestTogether:IsRuntimeRestricted()
			or not CanAccessForeignTable(C_QuestLog)
		then
			return "unknown"
		end
		local function Read(method)
			local fn = C_QuestLog[method]
			if not CanAccessForeignValue(fn) or type(fn) ~= "function" then
				return nil
			end
			local ok, value = pcall(fn, id)
			if ok and CanAccessForeignValue(value) and type(value) == "boolean" then
				return value
			end
			return nil
		end
		-- Absence from the active log is not itself evidence of completion.
		local active = Read("IsOnQuest")
		if active == true then
			return "active"
		end
		if active ~= false then
			return "unknown"
		end
		local repeatable = Read("IsRepeatableQuest")
		if repeatable == true then
			return "repeatable"
		end
		if repeatable ~= false then
			return "unknown"
		end
		local completed = Read("IsQuestFlaggedCompleted")
		if completed == true then
			return "completed"
		end
		return completed == false and "incomplete" or "unknown"
	end,
	IsQuestReadyForTurnIn = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		if
			CanAccessForeignTable(C_QuestLog)
			and CanAccessForeignValue(C_QuestLog.ReadyForTurnIn)
			and type(C_QuestLog.ReadyForTurnIn) == "function"
		then
			local ok, isReady = pcall(C_QuestLog.ReadyForTurnIn, numericQuestID)
			if ok and CanAccessForeignValue(isReady) and type(isReady) == "boolean" then
				return isReady
			end
			return nil
		end
		return nil
	end,
	IsQuestComplete = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		if
			CanAccessForeignTable(C_QuestLog)
			and CanAccessForeignValue(C_QuestLog.IsComplete)
			and type(C_QuestLog.IsComplete) == "function"
		then
			local ok, isComplete = pcall(C_QuestLog.IsComplete, numericQuestID)
			if ok and CanAccessForeignValue(isComplete) and type(isComplete) == "boolean" then
				return isComplete
			end
			return nil
		end
		return nil
	end,
	GetQuestClassification = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end

		if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
			local ok, classification = pcall(C_QuestInfoSystem.GetQuestClassification, numericQuestID)
			if ok and CanAccessForeignValue(classification) then
				local normalizedClassification = QuestTogether
						and QuestTogether.SafeToNumber
						and QuestTogether:SafeToNumber(classification)
					or nil
				if normalizedClassification ~= nil and normalizedClassification >= 0 then
					return math.floor(normalizedClassification + 0.5)
				end
			end
		end

		local questLogIndex = QuestTogether
				and QuestTogether.API
				and QuestTogether.API.GetQuestLogIndexForQuestID
				and QuestTogether.API.GetQuestLogIndexForQuestID(numericQuestID)
			or nil
		if not questLogIndex then
			return nil
		end

		local questInfo = QuestTogether
				and QuestTogether.API
				and QuestTogether.API.GetQuestLogInfo
				and QuestTogether.API.GetQuestLogInfo(questLogIndex)
			or nil
		if type(questInfo) ~= "table" then
			return nil
		end

		return SanitizeQuestInfoEnumValue(questInfo.questClassification)
	end,
	GetQuestFrequency = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end

		local questLogIndex = QuestTogether
				and QuestTogether.API
				and QuestTogether.API.GetQuestLogIndexForQuestID
				and QuestTogether.API.GetQuestLogIndexForQuestID(numericQuestID)
			or nil
		if not questLogIndex then
			return nil
		end

		local questInfo = QuestTogether
				and QuestTogether.API
				and QuestTogether.API.GetQuestLogInfo
				and QuestTogether.API.GetQuestLogInfo(questLogIndex)
			or nil
		if type(questInfo) ~= "table" then
			return nil
		end

		return SanitizeQuestInfoEnumValue(questInfo.frequency)
	end,
	GetQuestTagAtlas = function(tagID, worldQuestType)
		if type(QuestUtils_GetQuestTagAtlas) ~= "function" then
			return nil
		end

		local normalizedTagID = SanitizeQuestInfoEnumValue(tagID)
		local normalizedWorldQuestType = SanitizeQuestInfoEnumValue(worldQuestType)
		local ok, atlas = pcall(QuestUtils_GetQuestTagAtlas, normalizedTagID, normalizedWorldQuestType)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(atlas) then
			return nil
		end
		if type(atlas) ~= "string" or atlas == "" then
			return nil
		end

		return atlas
	end,
	GetQuestPoiTagType = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end

		local currentMapID = QuestTogether
				and QuestTogether.API
				and QuestTogether.API.GetPlayerMapID
				and QuestTogether.API.GetPlayerMapID("player")
			or nil
		if not currentMapID then
			return nil
		end

		local questPois = QuestTogether
				and QuestTogether.API
				and QuestTogether.API.GetQuestPOIsOnMap
				and QuestTogether.API.GetQuestPOIsOnMap(currentMapID)
			or nil
		if type(questPois) ~= "table" then
			return nil
		end

		for index = 1, #questPois do
			local poiInfo = questPois[index]
			if type(poiInfo) == "table" then
				local poiQuestID = QuestTogether
						and QuestTogether.NormalizeQuestID
						and QuestTogether:NormalizeQuestID(poiInfo.questID)
					or nil
				if poiQuestID == numericQuestID then
					return SanitizeQuestInfoEnumValue(poiInfo.questTagType)
				end
			end
		end

		return nil
	end,
	IsQuestOnMap = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return false
		end
		if C_QuestLog and C_QuestLog.IsOnMap then
			local ok, isOnMap = pcall(C_QuestLog.IsOnMap, numericQuestID)
			if not ok then
				return false
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isOnMap) then
				return false
			end
			if type(isOnMap) == "boolean" then
				return isOnMap
			end
			local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(isOnMap)
				or nil
			if numericFlag ~= nil then
				return numericFlag ~= 0
			end
		end
		return false
	end,
	IsWorldQuest = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		if C_QuestLog and C_QuestLog.IsWorldQuest then
			local ok, isWorldQuest = pcall(C_QuestLog.IsWorldQuest, numericQuestID)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isWorldQuest) then
				return nil
			end
			if type(isWorldQuest) == "boolean" then
				return isWorldQuest
			end
			local numericFlag = QuestTogether
					and QuestTogether.SafeToNumber
					and QuestTogether:SafeToNumber(isWorldQuest)
				or nil
			if numericFlag ~= nil then
				return numericFlag ~= 0
			end
		end
		return nil
	end,
	IsTaskQuestActive = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		if C_TaskQuest and C_TaskQuest.IsActive then
			local ok, isActive = pcall(C_TaskQuest.IsActive, numericQuestID)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(isActive) then
				return nil
			end
			if type(isActive) == "boolean" then
				return isActive
			end
			local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(isActive)
				or nil
			if numericFlag ~= nil then
				return numericFlag ~= 0
			end
		end
		return nil
	end,
	GetTaskQuestInfoByQuestID = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		if not (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID) then
			return nil
		end

		local ok, rawQuestTitle, factionID, capped, displayAsObjective =
			pcall(C_TaskQuest.GetQuestInfoByQuestID, numericQuestID)
		if not ok then
			return nil
		end

		local function NormalizeBooleanFlag(rawValue)
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
				return nil
			end
			if type(rawValue) == "boolean" then
				return rawValue
			end
			local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue)
				or nil
			if numericFlag ~= nil then
				return numericFlag ~= 0
			end
			return nil
		end

		local questTitle = ReadOptionalString(rawQuestTitle)
		if questTitle == "" then
			questTitle = nil
		end

		local normalizedFactionID = QuestTogether
				and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(factionID)
			or nil
		if normalizedFactionID ~= nil then
			normalizedFactionID = math.floor(normalizedFactionID + 0.5)
			if normalizedFactionID <= 0 then
				normalizedFactionID = nil
			end
		end

		return {
			questTitle = questTitle,
			factionID = normalizedFactionID,
			capped = NormalizeBooleanFlag(capped),
			displayAsObjective = NormalizeBooleanFlag(displayAsObjective),
		}
	end,
	GetTaskInfo = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil, nil, nil, nil, nil
		end
		if type(GetTaskInfo) ~= "function" then
			return nil, nil, nil, nil, nil
		end

		local ok, isInArea, isOnMap, numObjectives, taskName, displayAsObjective = pcall(GetTaskInfo, numericQuestID)
		if not ok then
			return nil, nil, nil, nil, nil
		end

		local function NormalizeBooleanFlag(rawValue)
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
				return nil
			end
			if type(rawValue) == "boolean" then
				return rawValue
			end
			local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue)
				or nil
			if numericFlag ~= nil then
				return numericFlag ~= 0
			end
			return nil
		end

		local normalizedInArea = NormalizeBooleanFlag(isInArea)
		local normalizedOnMap = NormalizeBooleanFlag(isOnMap)
		local normalizedDisplayAsObjective = NormalizeBooleanFlag(displayAsObjective)

		local normalizedObjectiveCount = nil
		if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(numObjectives)) then
			normalizedObjectiveCount = QuestTogether
					and QuestTogether.SafeToNumber
					and QuestTogether:SafeToNumber(numObjectives)
				or nil
			if normalizedObjectiveCount ~= nil then
				normalizedObjectiveCount = math.floor(normalizedObjectiveCount + 0.5)
				if normalizedObjectiveCount < 0 then
					normalizedObjectiveCount = 0
				end
			end
		end

		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(taskName) then
			taskName = nil
		end
		if type(taskName) ~= "string" or taskName == "" then
			taskName = nil
		end

		return normalizedInArea, normalizedOnMap, normalizedObjectiveCount, taskName, normalizedDisplayAsObjective
	end,
	GetLocalTaskQuests = function()
		if type(GetTasksTable) ~= "function" then
			return nil
		end

		-- Blizzard's objective tracker uses GetTasksTable() as the local-area task list.
		-- Call it behind pcall for transient quest-log races, then copy only scalar quest IDs
		-- out so we never retain Blizzard-owned tables.
		local ok, tasks = pcall(GetTasksTable)
		if not ok or (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tasks)) then
			return nil
		end
		if type(tasks) ~= "table" then
			return nil
		end

		local questIds = {}
		for index = 1, #tasks do
			local questID = tasks[index]
			if not (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questID)) then
				local numericQuestID = QuestTogether
						and QuestTogether.SafeToNumber
						and QuestTogether:SafeToNumber(questID)
					or nil
				if numericQuestID and numericQuestID > 0 then
					questIds[#questIds + 1] = math.floor(numericQuestID + 0.5)
				end
			end
		end

		return questIds
	end,
	GetTaskQuestsOnMap = function(mapID)
		local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
		if not numericMapID or numericMapID <= 0 then
			return nil
		end
		numericMapID = math.floor(numericMapID + 0.5)

		if not C_TaskQuest then
			return nil
		end
		local getTaskQuestsForMap = C_TaskQuest.GetQuestsOnMap
		local questIDField = "questID"
		if type(getTaskQuestsForMap) ~= "function" then
			getTaskQuestsForMap = C_TaskQuest.GetQuestsForPlayerByMapID
			questIDField = "questId"
		end
		if type(getTaskQuestsForMap) ~= "function" then
			return nil
		end

		local ok, tasks = pcall(getTaskQuestsForMap, numericMapID)
		if not ok or not CanAccessForeignTable(tasks) then
			return nil
		end

		local questIds = {}
		for index = 1, #tasks do
			local taskInfo = tasks[index]
			if CanAccessForeignTable(taskInfo) then
				local questID = taskInfo[questIDField]
				if CanAccessForeignValue(questID) then
					local numericQuestID = QuestTogether
							and QuestTogether.SafeToNumber
							and QuestTogether:SafeToNumber(questID)
						or nil
					if numericQuestID and numericQuestID > 0 then
						questIds[#questIds + 1] = math.floor(numericQuestID + 0.5)
					end
				end
			end
		end

		return questIds
	end,
	GetTaskQuestTitle = function(questID)
		local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questID)
			or nil
		if not numericQuestID or numericQuestID <= 0 then
			return nil
		end
		numericQuestID = math.floor(numericQuestID + 0.5)

		if not (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID) then
			return nil
		end

		local ok, questTitle = pcall(C_TaskQuest.GetQuestInfoByQuestID, numericQuestID)
		if not ok or (QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(questTitle)) then
			return nil
		end
		if type(questTitle) ~= "string" or questTitle == "" then
			return nil
		end

		return questTitle
	end,
	GetQuestPOIsOnMap = function(mapID)
		local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
		if not numericMapID or numericMapID <= 0 then
			return nil
		end
		numericMapID = math.floor(numericMapID + 0.5)

		if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
			return nil
		end

		local ok, pois = pcall(C_QuestLog.GetQuestsOnMap, numericMapID)
		if not ok or not CanAccessForeignTable(pois) then
			return nil
		end

		local sanitized = {}
		for index = 1, #pois do
			local poi = pois[index]
			if CanAccessForeignTable(poi) then
				local questID = poi.questID
				if CanAccessForeignValue(questID) then
					local numericQuestID = QuestTogether
							and QuestTogether.SafeToNumber
							and QuestTogether:SafeToNumber(questID)
						or nil
					if numericQuestID and numericQuestID > 0 then
						local function NormalizeBool(rawValue)
							if not CanAccessForeignValue(rawValue) then
								return nil
							end
							if type(rawValue) == "boolean" then
								return rawValue
							end
							local numericFlag = QuestTogether
									and QuestTogether.SafeToNumber
									and QuestTogether:SafeToNumber(rawValue)
								or nil
							if numericFlag ~= nil then
								return numericFlag ~= 0
							end
							return nil
						end

						local questTagType = nil
						if CanAccessForeignValue(poi.questTagType) then
							questTagType = QuestTogether
									and QuestTogether.SafeToNumber
									and QuestTogether:SafeToNumber(poi.questTagType)
								or nil
							if questTagType ~= nil then
								questTagType = math.floor(questTagType + 0.5)
							end
						end

						sanitized[#sanitized + 1] = {
							questID = math.floor(numericQuestID + 0.5),
							inProgress = NormalizeBool(poi.inProgress),
							isQuestStart = NormalizeBool(poi.isQuestStart),
							isMapIndicatorQuest = NormalizeBool(poi.isMapIndicatorQuest),
							questTagType = questTagType,
						}
					end
				end
			end
		end

		return sanitized
	end,
	IsOnQuest = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		if C_QuestLog and C_QuestLog.IsOnQuest then
			local ok, isOnQuest = pcall(C_QuestLog.IsOnQuest, numericQuestID)
			if ok and CanAccessForeignValue(isOnQuest) and type(isOnQuest) == "boolean" then
				return isOnQuest
			end
			return nil
		end
		return nil
	end,
	IsPushableQuest = function(questID)
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end
		if C_QuestLog and C_QuestLog.IsPushableQuest then
			local ok, isPushable = pcall(C_QuestLog.IsPushableQuest, numericQuestID)
			if ok and CanAccessForeignValue(isPushable) and type(isPushable) == "boolean" then
				return isPushable
			end
			return nil
		end
		-- Classic's legacy query applies to the selected quest. Read it only
		-- when selection already matches; never move the user's selection.
		if type(GetQuestLogSelection) == "function" and type(GetQuestLogPushable) == "function" then
			local selectionOK, selection = pcall(GetQuestLogSelection)
			local index = selectionOK and QuestTogether:SafeToNumber(selection) or nil
			local row = index and index > 0 and QuestTogether.API.GetQuestLogInfo(index) or nil
			if row and QuestTogether:NormalizeQuestID(row.questID) == numericQuestID then
				local ok, pushable = pcall(GetQuestLogPushable)
				if ok and CanAccessForeignValue(pushable) and type(pushable) == "boolean" then
					return pushable
				end
			end
		end
		return nil
	end,
	CanShareQuests = function()
		-- Retail/Forever share by log index. Do not fall back to moving the
		-- selected quest on clients with only the legacy sharing API.
		return type(QuestLogPushQuest) == "function"
			and C_QuestLog ~= nil
			and type(C_QuestLog.GetLogIndexForQuestID) == "function"
			and type(C_QuestLog.GetInfo) == "function"
			and type(C_QuestLog.IsPushableQuest) == "function"
	end,
	GetQuestShareResultFormats = function()
		local result = {}
		if QuestTogether:IsRuntimeRestricted() then
			return result
		end
		for _, suffix in ipairs({
			"ACCEPTED",
			"ALREADY_DONE",
			"BUSY",
			"CLASS",
			"DEAD",
			"DECLINED",
			"DIFFERENT_SERVER_DAILY",
			"EXPANSION",
			"HIGH_FACTION",
			"HIGH_LEVEL",
			"INVALID",
			"LOG_FULL",
			"LOW_FACTION",
			"LOW_LEVEL",
			"NEW_PLAYER_EXPERIENCE",
			"NOT_ALLOWED",
			"NOT_DAILY",
			"NOT_GARRISON_OWNER",
			"NOT_IN_PARTY",
			"ONQUEST",
			"PREREQUISITE",
			"RACE",
			"SUCCESS",
			"TIMER_EXPIRED",
			"TOO_FAR",
			"WRONG_COVENANT",
			"WRONG_FACTION",
		}) do
			local key = "ERR_QUEST_PUSH_" .. suffix .. "_S"
			local value = _G[key]
			if CanAccessForeignValue(value) and type(value) == "string" and #value > 0 and #value <= 1024 then
				result[key] = value
			end
		end
		return result
	end,
	GetQuestLogIndexForSharing = function(questID)
		local id = QuestTogether:SafeToNumber(questID)
		if not id or id <= 0 or id ~= math.floor(id) or not QuestTogether.API.CanShareQuests() then
			return nil
		end
		-- Resolve live data, not a cached index or the currently selected quest.
		local ok, rawIndex = pcall(C_QuestLog.GetLogIndexForQuestID, id)
		local index = ok and QuestTogether:SafeToNumber(rawIndex) or nil
		if not index or index <= 0 or index ~= math.floor(index) then
			return nil
		end
		local rowOK, row = pcall(C_QuestLog.GetInfo, index)
		if not rowOK or not CanAccessForeignTable(row) then
			return nil
		end
		if
			not CanAccessForeignValue(row.isHeader)
			or row.isHeader == true
			or QuestTogether:SafeToNumber(row.questID) ~= id
		then
			return nil
		end
		return index
	end,
	PushQuestToParty = function(questLogIndex)
		local index = QuestTogether:SafeToNumber(questLogIndex)
		if not index or index <= 0 or index ~= math.floor(index) or not QuestTogether.API.CanShareQuests() then
			return false
		end
		-- The caller rechecks eligibility and restrictions immediately before
		-- dispatch. A successful invocation is an attempt, not acceptance.
		local ok = pcall(QuestLogPushQuest, index)
		return ok
	end,
	CanOpenQuestDetails = function()
		return C_TooltipInfo ~= nil and type(C_TooltipInfo.GetHyperlink) == "function"
	end,
	GetQuestDetailsLink = function(questID)
		local id = QuestTogether:SafeToNumber(questID)
		if
			not id
			or id <= 0
			or id > 2147483647
			or id ~= math.floor(id)
			or QuestTogether:IsWorkBlocked("foreign_frame_mutation")
			or not QuestTogether.API.CanOpenQuestDetails()
		then
			return nil
		end
		-- Preserve native scaling fields when available; an unowned quest may
		-- not have a cached link. Reading details never opens Blizzard's UI.
		if type(GetQuestLink) == "function" then
			local ok, nativeText = pcall(GetQuestLink, id)
			if ok and CanAccessForeignValue(nativeText) and type(nativeText) == "string" then
				local nativeLink, nativeID = nativeText:match("|H(quest:(%d+):[%d:%-]*)|h[^|]*|h")
				if nativeLink and tonumber(nativeID) == id then
					return nativeLink
				end
			end
		end
		return string.format("quest:%d:0", id)
	end,
	CanOpenQuestJournal = function()
		if
			not CanCallNativeMapLua(QuestMapFrame_OpenToQuestDetails)
			or type(QuestMapFrame_GetDetailQuestID) ~= "function"
			or not QuestTogether:CanAccessForeignFrame(QuestMapFrame)
		then
			return false
		end
		local details = QuestTogether:GetAccessibleFrameMember(QuestMapFrame, "DetailsFrame")
		return QuestTogether:CanAccessForeignFrame(details)
			and (WorldMapFrame == nil or QuestTogether:CanAccessForeignFrame(WorldMapFrame))
	end,
	OpenQuestJournal = function(questID)
		local id = QuestTogether:SafeToNumber(questID)
		if
			not id
			or id <= 0
			or id ~= math.floor(id)
			or QuestTogether:IsRuntimeRestricted()
			or not QuestTogether.API.CanOpenQuestJournal()
		then
			return false
		end
		-- Use the same quest-by-ID entry point as Blizzard's tracker. It opens
		-- the journal and selects the details without writing our own frame state.
		local ok = CallNativeMapLua(QuestMapFrame_OpenToQuestDetails, id)
		if
			not ok
			or not QuestTogether:CanAccessForeignFrame(WorldMapFrame, true)
			or not QuestTogether:CanAccessForeignFrame(QuestMapFrame, true)
			or not QuestTogether.API.CanOpenQuestJournal()
		then
			return false
		end
		local selectedOK, selectedID = pcall(QuestMapFrame_GetDetailQuestID)
		return selectedOK and QuestTogether:SafeToNumber(selectedID) == id
	end,
	CanOpenQuestJournalWindow = function()
		return CanCallNativeMapLua(OpenQuestLog)
			and QuestTogether:CanAccessForeignFrame(WorldMapFrame)
			and QuestTogether:CanAccessForeignFrame(QuestMapFrame)
	end,
	OpenQuestJournalWindow = function()
		if QuestTogether:IsRuntimeRestricted() or not QuestTogether.API.CanOpenQuestJournalWindow() then
			return false
		end
		-- Retail/Forever expose this non-toggle opener with the world map.
		-- Leave the user's selected quest and journal tab to the native UI.
		local ok = CallNativeMapLua(OpenQuestLog)
		-- The native opener returns nil and can decline to show its panel.
		return ok
			and QuestTogether:CanAccessForeignFrame(WorldMapFrame, true)
			and QuestTogether:CanAccessForeignFrame(QuestMapFrame, true)
	end,
	GetQuestGroupRecommended = function(questID)
		if QuestTogether:IsRuntimeRestricted() then
			return nil
		end
		local id = QuestTogether:NormalizeQuestID(questID)
		if not id then
			return nil
		end
		-- The native level suffix uses IsEliteQuest. Its explicit false is
		-- authoritative; older clients may only expose tags or a group size.
		if C_QuestLog and type(C_QuestLog.IsEliteQuest) == "function" then
			local ok, elite = pcall(C_QuestLog.IsEliteQuest, id)
			if ok and CanAccessForeignValue(elite) and type(elite) == "boolean" then
				return elite
			end
		end
		if C_QuestLog and type(C_QuestLog.GetQuestTagInfo) == "function" then
			local ok, info = pcall(C_QuestLog.GetQuestTagInfo, id)
			if ok and CanAccessForeignTable(info) then
				local tag = QuestTogether:SafeToNumber(info.tagID)
				-- Enum.QuestTag.Group / the native elite quest tag is 1.
				if tag == 1 or (CanAccessForeignValue(info.isElite) and info.isElite == true) then
					return true
				end
			end
		end
		if C_QuestLog and type(C_QuestLog.GetSuggestedGroupSize) == "function" then
			local ok, size = pcall(C_QuestLog.GetSuggestedGroupSize, id)
			if ok then
				return SanitizeSuggestedQuestGroup(size)
			end
		end
		return nil
	end,
	GetQuestDifficultyLevel = function(questID)
		if QuestTogether:IsRuntimeRestricted() then
			return nil
		end
		local id = QuestTogether:NormalizeQuestID(questID)
		if not id or not (C_QuestLog and type(C_QuestLog.GetQuestDifficultyLevel) == "function") then
			return nil
		end
		local ok, level = pcall(C_QuestLog.GetQuestDifficultyLevel, id)
		return ok and SanitizeQuestLevel(level) or nil
	end,
	GetQuestDifficultyColor = function(level)
		if QuestTogether:IsRuntimeRestricted() then
			return nil
		end
		level = SanitizeQuestLevel(level)
		if not level or type(GetQuestDifficultyColor) ~= "function" then
			return nil
		end
		local ok, color = pcall(GetQuestDifficultyColor, level)
		if not ok or not CanAccessForeignTable(color) then
			return nil
		end
		local r, g, b =
			QuestTogether:SafeToNumber(color.r),
			QuestTogether:SafeToNumber(color.g),
			QuestTogether:SafeToNumber(color.b)
		if not r or not g or not b or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then
			return nil
		end
		return { r = r, g = g, b = b }
	end,
	GetNumQuestLogEntries = function()
		local getter = type(GetNumQuestLogEntries) == "function" and GetNumQuestLogEntries
			or (C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
		if type(getter) ~= "function" then
			return nil
		end
		local ok, count = pcall(getter)
		local numericCount = ok and QuestTogether:SafeToNumber(count) or nil
		if numericCount == nil or numericCount < 0 then
			return nil
		end
		return math.floor(numericCount + 0.5)
	end,
	GetQuestLogInfo = function(questLogIndex)
		local numericQuestLogIndex = QuestTogether
				and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(questLogIndex)
			or nil
		if numericQuestLogIndex == nil then
			return nil
		end
		numericQuestLogIndex = math.floor(numericQuestLogIndex + 0.5)
		if numericQuestLogIndex <= 0 then
			return nil
		end

		local titleInfo = nil
		if type(GetQuestLogTitle) == "function" then
			local okTitle, title, level, questTag, isHeader, _, isComplete, _, questID, _, displayQuestID, isOnMap, hasLocalPOI, isTask, _ =
				pcall(GetQuestLogTitle, numericQuestLogIndex)
			if okTitle then
				titleInfo = BuildSanitizedQuestLogInfoRecord(
					numericQuestLogIndex,
					title,
					isHeader,
					nil,
					isTask,
					isOnMap,
					hasLocalPOI,
					isComplete,
					questID,
					displayQuestID,
					nil,
					level,
					nil,
					questTag
				)
			end
		end

		if C_QuestLog and C_QuestLog.GetInfo then
			local okInfo, rawInfo = pcall(C_QuestLog.GetInfo, numericQuestLogIndex)
			if okInfo then
				local sanitizedInfo = BuildSanitizedQuestLogInfoFromRawInfo(numericQuestLogIndex, rawInfo)
				if sanitizedInfo then
					titleInfo = MergeSanitizedQuestLogInfo(sanitizedInfo, titleInfo)
				end
			end
		end

		if titleInfo and titleInfo.questID then
			local recommended = QuestTogether.API.GetQuestGroupRecommended(titleInfo.questID)
			if recommended ~= nil then
				titleInfo.questGroupRecommended = recommended
			end
		end
		return titleInfo
	end,
	GetNumQuestLeaderBoards = function(questLogIndex, requireReadable)
		local unavailable = 0
		if requireReadable then
			unavailable = nil
		end
		if QuestTogether:IsWorkBlocked("quest_progress_read") then
			return unavailable
		end
		local numericQuestLogIndex = QuestTogether
				and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(questLogIndex)
			or nil
		if numericQuestLogIndex == nil then
			return unavailable
		end
		numericQuestLogIndex = math.floor(numericQuestLogIndex + 0.5)
		if numericQuestLogIndex <= 0 then
			return unavailable
		end
		local ok, objectiveCount
		if type(GetNumQuestLeaderBoards) == "function" then
			ok, objectiveCount = pcall(GetNumQuestLeaderBoards, numericQuestLogIndex)
		elseif CanAccessForeignTable(C_QuestLog) and type(C_QuestLog.GetQuestObjectives) == "function" then
			local row = QuestTogether.API.GetQuestLogInfo(numericQuestLogIndex)
			local id = row and QuestTogether:NormalizeQuestID(row.questID)
			if not id then
				return unavailable
			end
			local readOK, objectives = pcall(C_QuestLog.GetQuestObjectives, id)
			if readOK and CanAccessForeignTable(objectives) then
				ok, objectiveCount = true, #objectives
			end
		end
		if not ok then
			return unavailable
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(objectiveCount) then
			return unavailable
		end
		local numericObjectiveCount = QuestTogether
				and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(objectiveCount)
			or nil
		if numericObjectiveCount == nil then
			return unavailable
		end
		if numericObjectiveCount < 0 or numericObjectiveCount > 100 or numericObjectiveCount % 1 ~= 0 then
			return unavailable
		end
		return math.floor(numericObjectiveCount + 0.5)
	end,
	GetActiveTrackedQuestID = function()
		-- Scalar navigation state does not query quest tooltips or mutate the map.
		if QuestTogether:IsRuntimeRestricted() or not CanAccessForeignTable(C_SuperTrack) then
			return nil
		end
		local isQuest, getQuest = C_SuperTrack.IsSuperTrackingQuest, C_SuperTrack.GetSuperTrackedQuestID
		if
			not CanAccessForeignValue(isQuest)
			or type(isQuest) ~= "function"
			or not CanAccessForeignValue(getQuest)
			or type(getQuest) ~= "function"
		then
			return nil
		end
		local ok, active = pcall(isQuest)
		if not ok or not CanAccessForeignValue(active) or active ~= true then
			return nil
		end
		local got, id = pcall(getQuest)
		if got then
			id = QuestTogether:SafeToNumber(id)
			if id and id >= 1 and id <= 1000000000 and id == math.floor(id) then
				return id
			end
		end
	end,
	GetPartyNavigationNativeState = function()
		if QuestTogether:IsRuntimeRestricted() then
			return nil
		end
		local result = { questID = -1, mapID = -1, x = 0, y = 0 }
		if
			CanAccessForeignTable(C_SuperTrack)
			and CanAccessForeignValue(C_SuperTrack.IsSuperTrackingQuest)
			and type(C_SuperTrack.IsSuperTrackingQuest) == "function"
			and CanAccessForeignValue(C_SuperTrack.GetSuperTrackedQuestID)
			and type(C_SuperTrack.GetSuperTrackedQuestID) == "function"
		then
			local ok, active = pcall(C_SuperTrack.IsSuperTrackingQuest)
			if not ok or not CanAccessForeignValue(active) or type(active) ~= "boolean" then
				return nil
			end
			if active then
				local id = QuestTogether.API.GetActiveTrackedQuestID()
				if not id then
					return nil
				end
				result.questID = id
			else
				result.questID = 0
				local anything = C_SuperTrack.IsSuperTrackingAnything
				if CanAccessForeignValue(anything) and type(anything) == "function" then
					local got, tracking = pcall(anything)
					if not got or not CanAccessForeignValue(tracking) or type(tracking) ~= "boolean" then
						return nil
					end
					result.questCleared = tracking == false
				end
			end
		end
		if
			CanAccessForeignTable(C_Map)
			and CanAccessForeignValue(C_Map.GetUserWaypoint)
			and type(C_Map.GetUserWaypoint) == "function"
		then
			local ok, point = pcall(C_Map.GetUserWaypoint)
			if not ok or not CanAccessForeignValue(point) then
				return result
			end
			if point == nil then
				result.mapID = 0
			else
				local got, map, x, y = pcall(ReadPartyWaypoint, point)
				if got and map then
					result.mapID, result.x, result.y = map, x, y
				end
			end
		end
		return result
	end,
	SetPartyNavigationQuest = function(questID)
		if QuestTogether:IsRuntimeRestricted() or not CanAccessForeignTable(C_SuperTrack) then
			return false
		end
		local setter = C_SuperTrack.SetSuperTrackedQuestID
		if not CanAccessForeignValue(setter) or type(setter) ~= "function" then
			return false
		end
		local id = QuestTogether:SafeToNumber(questID)
		if id == 0 then
			local anything = C_SuperTrack.IsSuperTrackingAnything
			if not CanAccessForeignValue(anything) or type(anything) ~= "function" then
				return false
			end
			local ok = pcall(setter, 0)
			if not ok then
				return false
			end
			local got, tracking = pcall(anything)
			return got and CanAccessForeignValue(tracking) and tracking == false
		end
		id = QuestTogether:NormalizeQuestID(id)
		if not id then
			return false
		end
		if QuestTogether.API.IsOnQuest(id) ~= true then
			return false
		end
		local ok = pcall(setter, id)
		return ok and QuestTogether.API.GetActiveTrackedQuestID() == id
	end,
	GetLocalizedQuestTitle = function(questID)
		local id = QuestTogether:SafeToNumber(questID)
		if
			not id
			or id <= 0
			or id > 1000000000
			or id ~= math.floor(id)
			or QuestTogether:IsWorkBlocked("quest_snapshot_refresh")
		then
			return nil
		end
		local function Title(value)
			if
				not CanAccessForeignValue(value)
				or type(value) ~= "string"
				or #value > 512
				or value:find("[%z\001-\031\127]")
			then
				return nil
			end
			-- Native tooltip headers can be colored. Never retain links, textures,
			-- or other markup in a title that will be put into our own quest link.
			local title = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			title = QuestTogether:SafeTrimString(title, "")
			if
				title == ""
				or title:find("|", 1, true)
				or title:match("^%d+$")
				or QuestTogether:IsPlaceholderQuestTitle(id, title)
			then
				return nil
			end
			for _, key in ipairs({ "RETRIEVING_DATA", "LOADING", "UNKNOWN", "UNKNOWNOBJECT" }) do
				local placeholder = _G[key]
				if CanAccessForeignValue(placeholder) and type(placeholder) == "string" and title == placeholder then
					return nil
				end
			end
			return title
		end
		local ok, title = pcall(function()
			if CanAccessForeignTable(C_QuestLog) then
				local getter = C_QuestLog.GetTitleForQuestID
				if CanAccessForeignValue(getter) and type(getter) == "function" then
					local got, value = pcall(getter, id)
					local nativeTitle = got and Title(value)
					if nativeTitle then
						return nativeTitle
					end
				end
			end
			-- Some clients cache a local hyperlink/tooltip before the quest-title
			-- getter is populated. Read native data only; never select or show UI.
			local hyperlink = string.format("quest:%d:0", id)
			if CanAccessForeignValue(GetQuestLink) and type(GetQuestLink) == "function" then
				local got, link = pcall(GetQuestLink, id)
				if got and CanAccessForeignValue(link) and type(link) == "string" and #link <= 1024 then
					link = link:gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("|r$", "")
					local nativeLink, nativeID, rawTitle = link:match("^|H(quest:(%d+):[%d:%-]+)|h%[([^|%[%]]+)%]|h$")
					local validFields = nativeLink ~= nil
					if nativeLink then
						for field in nativeLink:sub(#nativeID + 8):gmatch("[^:]+") do
							if not field:match("^%-?%d+$") then
								validFields = false
								break
							end
						end
					end
					if validFields and tonumber(nativeID) == id then
						hyperlink = nativeLink
						local nativeTitle = Title(rawTitle)
						if nativeTitle then
							return nativeTitle
						end
					end
				end
			end
			if not CanAccessForeignTable(C_TooltipInfo) then
				return nil
			end
			local getter = C_TooltipInfo.GetHyperlink
			if
				not CanAccessForeignValue(getter)
				or type(getter) ~= "function"
				or not CanAccessForeignTable(Enum)
				or not CanAccessForeignTable(Enum.TooltipDataType)
				or not CanAccessForeignTable(Enum.TooltipDataLineType)
			then
				return nil
			end
			local questType = QuestTogether:SafeToNumber(Enum.TooltipDataType.Quest)
			local titleType = QuestTogether:SafeToNumber(Enum.TooltipDataLineType.QuestTitle)
			local genericType = QuestTogether:SafeToNumber(Enum.TooltipDataLineType.None)
			if not questType or not titleType then
				return nil
			end
			local data = QuestTogether.API.GetTooltipDataForHyperlink(hyperlink)
			if
				not CanAccessForeignTable(data)
				or not CanAccessForeignValue(data.type)
				or data.type ~= questType
				or not CanAccessForeignValue(data.id)
				or (data.id ~= nil and QuestTogether:SafeToNumber(data.id) ~= id)
				or not CanAccessForeignTable(data.lines)
			then
				return nil
			end
			-- The first line is the header. Skipping a missing/loading header to
			-- use a later line could cache objective prose as the quest's name.
			local header = data.lines[1]
			if
				not CanAccessForeignTable(header)
				or not CanAccessForeignValue(header.type)
				or (header.type ~= titleType and (genericType == nil or header.type ~= genericType))
			then
				return nil
			end
			return Title(header.leftText)
		end)
		if ok then
			return title
		end
	end,
	RequestLocalizedQuestTitle = function(questID)
		local id = QuestTogether:SafeToNumber(questID)
		if
			not id
			or id <= 0
			or id > 1000000000
			or id ~= math.floor(id)
			or QuestTogether:IsWorkBlocked("quest_snapshot_refresh")
			or not CanAccessForeignTable(C_QuestLog)
		then
			return false
		end
		local request = C_QuestLog.RequestLoadQuestByID
		if not CanAccessForeignValue(request) or type(request) ~= "function" then
			return false
		end
		return pcall(request, id)
	end,
	GetQuestObjectiveInfo = function(questID, objectiveIndex, displayComplete, questLogIndex)
		if QuestTogether:IsWorkBlocked("quest_progress_read") then
			return nil, nil, nil, nil
		end
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil, nil, nil, nil
		end

		local numericObjectiveIndex = QuestTogether
				and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(objectiveIndex)
			or nil
		if numericObjectiveIndex == nil then
			return nil, nil, nil, nil
		end
		numericObjectiveIndex = math.floor(numericObjectiveIndex + 0.5)
		if numericObjectiveIndex <= 0 then
			return nil, nil, nil, nil
		end

		local ok, text, objectiveType, finished, currentValue, requiredValue
		if CanAccessForeignValue(GetQuestObjectiveInfo) and type(GetQuestObjectiveInfo) == "function" then
			ok, text, objectiveType, finished, currentValue, requiredValue =
				pcall(GetQuestObjectiveInfo, numericQuestID, numericObjectiveIndex, displayComplete)
		elseif
			CanAccessForeignTable(C_QuestLog)
			and CanAccessForeignValue(C_QuestLog.GetQuestObjectives)
			and type(C_QuestLog.GetQuestObjectives) == "function"
		then
			local queryOK, objectives = pcall(C_QuestLog.GetQuestObjectives, numericQuestID)
			if not queryOK or not CanAccessForeignTable(objectives) then
				return nil, nil, nil, nil
			end
			local objective = objectives[numericObjectiveIndex]
			if not CanAccessForeignTable(objective) then
				return nil, nil, nil, nil
			end
			ok, text, objectiveType, finished, currentValue, requiredValue =
				true, objective.text, objective.type, objective.finished, objective.numFulfilled, objective.numRequired
		elseif type(GetQuestLogLeaderBoard) == "function" then
			-- A caller can reuse a captured index, but native row identity must
			-- still match before the legacy index-based objective read.
			local index = QuestTogether:SafeToNumber(questLogIndex)
			if index and index > 0 and index == math.floor(index) then
				local row = QuestTogether.API.GetQuestLogInfo(index)
				if not CanAccessForeignTable(row) or QuestTogether:NormalizeQuestID(row.questID) ~= numericQuestID then
					index = nil
				end
			else
				index = nil
			end
			index = index or QuestTogether.API.GetQuestLogIndexForQuestID(numericQuestID)
			if not index then
				return nil, nil, nil, nil
			end
			ok, text, objectiveType, finished = pcall(GetQuestLogLeaderBoard, numericObjectiveIndex, index)
		end
		if not ok then
			return nil, nil, nil, nil
		end
		if not CanAccessForeignValue(text) then
			text = nil
		end
		if not CanAccessForeignValue(objectiveType) then
			objectiveType = nil
		end
		if not CanAccessForeignValue(finished) then
			finished = nil
		end
		if not CanAccessForeignValue(currentValue) then
			currentValue = nil
		end
		if not CanAccessForeignValue(requiredValue) then
			requiredValue = nil
		end
		-- Some clients expose the legacy text API and the structured API together.
		-- Only supplement counters when both reads describe the identical row.
		if
			type(GetQuestObjectiveInfo) == "function"
			and requiredValue == nil
			and type(text) == "string"
			and CanAccessForeignTable(C_QuestLog)
			and type(C_QuestLog.GetQuestObjectives) == "function"
		then
			local readOK, rows = pcall(C_QuestLog.GetQuestObjectives, numericQuestID)
			local row = readOK and CanAccessForeignTable(rows) and rows[numericObjectiveIndex] or nil
			if
				CanAccessForeignTable(row)
				and CanAccessForeignValue(row.text)
				and CanAccessForeignValue(row.type)
				and row.text == text
				and row.type == objectiveType
				and CanAccessForeignValue(row.numFulfilled)
				and CanAccessForeignValue(row.numRequired)
				and (currentValue == nil or row.numFulfilled == currentValue)
			then
				currentValue, requiredValue = row.numFulfilled, row.numRequired
			end
		end
		if not CanAccessForeignValue(requiredValue) then
			requiredValue = nil
		end
		return text, objectiveType, finished, currentValue, requiredValue
	end,
	GetQuestProgressBarPercent = function(questID)
		if QuestTogether:IsWorkBlocked("quest_progress_read") then
			return nil
		end
		local numericQuestID = QuestTogether
				and QuestTogether.NormalizeQuestID
				and QuestTogether:NormalizeQuestID(questID)
			or nil
		if not numericQuestID then
			return nil
		end

		if type(GetQuestProgressBarPercent) ~= "function" then
			return nil
		end
		local ok, progressValue = pcall(GetQuestProgressBarPercent, numericQuestID)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(progressValue) then
			return nil
		end
		return progressValue
	end,
})
