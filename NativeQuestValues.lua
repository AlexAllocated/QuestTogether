-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local Access = QuestTogether.NativeAccess
local CanAccessForeignValue, CanAccessForeignTable = Access.Value, Access.Table

local function NormalizeQuestInfoFlagValue(rawValue)
	if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
		return nil
	end
	if type(rawValue) == "boolean" then
		return rawValue
	end
	local numericFlag = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue) or nil
	if numericFlag ~= nil then
		return numericFlag ~= 0
	end
	return nil
end

local function NormalizeQuestLocationFlag(rawValue)
	if not CanAccessForeignValue(rawValue) then
		return nil
	end
	return NormalizeQuestInfoFlagValue(rawValue)
end

local function MergeQuestLocationFlag(primaryValue, fallbackValue)
	if primaryValue ~= nil then
		return primaryValue
	end
	return fallbackValue
end

local function NormalizeQuestCompletionValue(rawValue)
	if not CanAccessForeignValue(rawValue) then
		return nil
	end
	if type(rawValue) == "boolean" then
		return rawValue
	end
	local numericValue = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue) or nil
	if numericValue ~= nil then
		-- GetQuestLogTitle returns 1 for completed and -1 for failed quests.
		return numericValue == 1
	end
	return nil
end

-- GetUserWaypoint returns a plain UiMapPoint; its position need not carry
-- Vector2DMixin methods. Called through pcall so a malformed waypoint cannot
-- interrupt the independent quest-focus observation.
local function ReadPartyWaypoint(point)
	if not CanAccessForeignTable(point) then
		return nil
	end
	local position = point.position
	if not CanAccessForeignTable(position) then
		return nil
	end
	local map = QuestTogether:SafeToNumber(point.uiMapID)
	local x, y = position.x, position.y
	if not CanAccessForeignValue(x) or not CanAccessForeignValue(y) then
		return nil
	end
	if x == nil and y == nil then
		local getter = position.GetXY
		if not CanAccessForeignValue(getter) or type(getter) ~= "function" then
			return nil
		end
		x, y = getter(position)
	end
	x, y = QuestTogether:SafeToNumber(x), QuestTogether:SafeToNumber(y)
	if
		not map
		or map <= 0
		or map > 1000000
		or map ~= math.floor(map)
		or not x
		or not y
		or x < 0
		or x > 1
		or y < 0
		or y > 1
	then
		return nil
	end
	return map, x, y
end

---@return string?
local function ReadOptionalString(value)
	if not CanAccessForeignValue(value) or type(value) ~= "string" then
		return nil
	end
	return value
end

local function SanitizeQuestInfoEnumValue(rawValue)
	if not CanAccessForeignValue(rawValue) then
		return nil
	end
	local numericValue = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawValue) or nil
	if numericValue == nil then
		return nil
	end
	numericValue = math.floor(numericValue + 0.5)
	if numericValue < 0 then
		return nil
	end
	return numericValue
end

local function SanitizeQuestLevel(rawValue)
	local level = QuestTogether and QuestTogether:SafeToNumber(rawValue)
	return level and level > 0 and level <= 1000 and level == math.floor(level) and level or nil
end

local function SanitizeSuggestedQuestGroup(rawValue)
	local size = QuestTogether and QuestTogether:SafeToNumber(rawValue)
	if size and size >= 0 and size <= 40 and size == math.floor(size) then
		return size > 1
	end
	return nil
end

local function IsLegacyEliteQuestTag(tag)
	if not CanAccessForeignValue(tag) or type(tag) ~= "string" then
		return nil
	end
	if (type(ELITE) == "string" and tag == ELITE) or (type(GROUP) == "string" and tag == GROUP) then
		return true
	end
	return nil
end

local function BuildSanitizedQuestLogInfoRecord(
	questLogIndex,
	titleValue,
	isHeaderValue,
	isHiddenValue,
	isTaskValue,
	isOnMapValue,
	hasLocalPOIValue,
	isCompleteValue,
	questIDValue,
	displayQuestIDValue,
	isWorldQuestValue,
	levelValue,
	suggestedGroupValue,
	questTagValue
)
	local numericQuestLogIndex = QuestTogether
			and QuestTogether.SafeToNumber
			and QuestTogether:SafeToNumber(questLogIndex)
		or nil
	if not numericQuestLogIndex or numericQuestLogIndex <= 0 then
		return nil
	end

	local titleIsSecret = QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(titleValue)
	local sanitizedInfo = {
		title = (type(titleValue) == "string" and not titleIsSecret) and titleValue or nil,
		questLogIndex = math.floor(numericQuestLogIndex + 0.5),
		questLevel = SanitizeQuestLevel(levelValue),
		questGroupRecommended = SanitizeSuggestedQuestGroup(suggestedGroupValue),
		isHeader = NormalizeQuestInfoFlagValue(isHeaderValue) == true,
		isHidden = NormalizeQuestInfoFlagValue(isHiddenValue) == true,
		isTask = NormalizeQuestInfoFlagValue(isTaskValue) == true,
		isOnMap = NormalizeQuestLocationFlag(isOnMapValue),
		hasLocalPOI = NormalizeQuestLocationFlag(hasLocalPOIValue),
		isComplete = NormalizeQuestCompletionValue(isCompleteValue) == true,
	}
	if IsLegacyEliteQuestTag(questTagValue) then
		sanitizedInfo.questGroupRecommended = true
	end

	local numericQuestID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(questIDValue)
		or nil
	if not numericQuestID or numericQuestID <= 0 then
		numericQuestID = QuestTogether
				and QuestTogether.SafeToNumber
				and QuestTogether:SafeToNumber(displayQuestIDValue)
			or nil
	end
	if numericQuestID and numericQuestID > 0 then
		sanitizedInfo.questID = math.floor(numericQuestID + 0.5)
	end

	local normalizedIsWorldQuest = NormalizeQuestInfoFlagValue(isWorldQuestValue)
	if normalizedIsWorldQuest ~= nil then
		sanitizedInfo.isWorldQuest = normalizedIsWorldQuest
	end

	return sanitizedInfo
end

local function BuildSanitizedQuestLogInfoFromRawInfo(questLogIndex, rawInfo)
	if not CanAccessForeignTable(rawInfo) then
		return nil
	end

	local sanitizedInfo = BuildSanitizedQuestLogInfoRecord(
		questLogIndex,
		rawInfo.title,
		rawInfo.isHeader,
		rawInfo.isHidden,
		rawInfo.isTask,
		rawInfo.isOnMap,
		rawInfo.hasLocalPOI,
		rawInfo.isComplete,
		rawInfo.questID,
		rawInfo.displayQuestID,
		rawInfo.isWorldQuest,
		rawInfo.level,
		rawInfo.suggestedGroup
	)
	if not sanitizedInfo then
		return nil
	end

	-- Some modern records omit completion altogether. Preserve that absence
	-- until the legacy fallback is merged, while retaining explicit false.
	sanitizedInfo.isComplete = NormalizeQuestCompletionValue(rawInfo.isComplete)
	sanitizedInfo.campaignID = SanitizeQuestInfoEnumValue(rawInfo.campaignID)
	sanitizedInfo.frequency = SanitizeQuestInfoEnumValue(rawInfo.frequency)
	sanitizedInfo.questClassification = SanitizeQuestInfoEnumValue(rawInfo.questClassification)
	return sanitizedInfo
end

local function MergeSanitizedQuestLogInfo(primaryInfo, fallbackInfo)
	if type(primaryInfo) ~= "table" then
		return type(fallbackInfo) == "table" and fallbackInfo or nil
	end
	if type(fallbackInfo) ~= "table" then
		primaryInfo.isComplete = primaryInfo.isComplete == true
		return primaryInfo
	end

	local mergedInfo = {}
	mergedInfo.questLogIndex = primaryInfo.questLogIndex or fallbackInfo.questLogIndex
	mergedInfo.title = primaryInfo.title or fallbackInfo.title
	mergedInfo.questLevel = primaryInfo.questLevel or fallbackInfo.questLevel
	mergedInfo.questGroupRecommended = primaryInfo.questGroupRecommended
	if mergedInfo.questGroupRecommended == nil then
		mergedInfo.questGroupRecommended = fallbackInfo.questGroupRecommended
	end
	mergedInfo.questID = primaryInfo.questID or fallbackInfo.questID
	mergedInfo.isHeader = primaryInfo.isHeader == true or fallbackInfo.isHeader == true
	mergedInfo.isHidden = primaryInfo.isHidden == true or fallbackInfo.isHidden == true
	mergedInfo.isTask = primaryInfo.isTask == true or fallbackInfo.isTask == true
	mergedInfo.isOnMap = MergeQuestLocationFlag(primaryInfo.isOnMap, fallbackInfo.isOnMap)
	mergedInfo.hasLocalPOI = MergeQuestLocationFlag(primaryInfo.hasLocalPOI, fallbackInfo.hasLocalPOI)
	if primaryInfo.isComplete ~= nil then
		mergedInfo.isComplete = primaryInfo.isComplete == true
	else
		mergedInfo.isComplete = fallbackInfo.isComplete == true
	end
	mergedInfo.campaignID = primaryInfo.campaignID or fallbackInfo.campaignID
	mergedInfo.frequency = primaryInfo.frequency or fallbackInfo.frequency
	mergedInfo.questClassification = primaryInfo.questClassification or fallbackInfo.questClassification
	if primaryInfo.isWorldQuest ~= nil then
		mergedInfo.isWorldQuest = primaryInfo.isWorldQuest == true
	elseif fallbackInfo.isWorldQuest ~= nil then
		mergedInfo.isWorldQuest = fallbackInfo.isWorldQuest == true
	end

	return mergedInfo
end

QuestTogether.NativeQuestValues = {
	NormalizeQuestInfoFlagValue = NormalizeQuestInfoFlagValue,
	NormalizeQuestLocationFlag = NormalizeQuestLocationFlag,
	MergeQuestLocationFlag = MergeQuestLocationFlag,
	NormalizeQuestCompletionValue = NormalizeQuestCompletionValue,
	ReadPartyWaypoint = ReadPartyWaypoint,
	ReadOptionalString = ReadOptionalString,
	SanitizeQuestInfoEnumValue = SanitizeQuestInfoEnumValue,
	SanitizeQuestLevel = SanitizeQuestLevel,
	SanitizeSuggestedQuestGroup = SanitizeSuggestedQuestGroup,
	IsLegacyEliteQuestTag = IsLegacyEliteQuestTag,
	BuildSanitizedQuestLogInfoRecord = BuildSanitizedQuestLogInfoRecord,
	BuildSanitizedQuestLogInfoFromRawInfo = BuildSanitizedQuestLogInfoFromRawInfo,
	MergeSanitizedQuestLogInfo = MergeSanitizedQuestLogInfo,
}
