-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local Services = QuestTogether.NameplateServices
local NAMEPLATE_SCAN_TOOLTIP_NAME = "QuestTogetherNameplateScanTooltip"
local NAMEPLATE_TOOLTIP_RETRY_MAX_ATTEMPTS = 4
local NAMEPLATE_TOOLTIP_RETRY_DELAY_SECONDS = 0.2
local function GetObjectiveProgressState(text)
	if type(text) ~= "string" or text == "" then
		return "unknown"
	end

	local amountCurrent, amountTotal = Services.Access.SafeMatch(text, "(%d+)%s*/%s*(%d+)")
	if amountCurrent and amountTotal then
		local currentValue = Services.Access.SafeUiNumber(amountCurrent, nil)
		local totalValue = Services.Access.SafeUiNumber(amountTotal, nil)
		if currentValue == nil or totalValue == nil then
			return "unknown"
		end
		if currentValue < totalValue then
			return "unfinished"
		end
		return "complete"
	end

	local percentText = Services.Access.SafeMatch(text, "(%d+)%%")
	if percentText then
		local percentValue = Services.Access.SafeUiNumber(percentText, nil)
		if percentValue == nil then
			return "unknown"
		end
		if percentValue < 100 then
			return "unfinished"
		end
		return "complete"
	end

	return "unknown"
end

local function IsKnownNameplateQuestText(text)
	local trimmedText = Services.Access.SafeTrimText(text)
	if trimmedText == "" then
		return false
	end
	return QuestTogether
			and QuestTogether:GetNameplateStateStore().textCache
			and QuestTogether:GetNameplateStateStore().textCache[trimmedText]
		or false
end

local function IsTooltipQuestObjectiveLineType(lineType)
	if not QuestTogether:CanAccessValue(lineType) then
		return false
	end

	local normalizedType = Services.Access.SafeText(lineType, "")
	if normalizedType == "QuestObjective" then
		return true
	end

	if Enum and Enum.TooltipDataLineType then
		return Enum.TooltipDataLineType.QuestObjective ~= nil and lineType == Enum.TooltipDataLineType.QuestObjective
	end

	return false
end

local function IsTooltipQuestPlayerLineType(lineType)
	if not QuestTogether:CanAccessValue(lineType) then
		return false
	end

	local normalizedType = Services.Access.SafeText(lineType, "")
	if normalizedType == "QuestPlayer" then
		return true
	end

	if Enum and Enum.TooltipDataLineType then
		return Enum.TooltipDataLineType.QuestPlayer ~= nil and lineType == Enum.TooltipDataLineType.QuestPlayer
	end

	return false
end

local function IsTooltipQuestTitleLineType(lineType)
	if not QuestTogether:CanAccessValue(lineType) then
		return false
	end

	local normalizedType = Services.Access.SafeText(lineType, "")
	if normalizedType == "QuestTitle" then
		return true
	end

	if Enum and Enum.TooltipDataLineType then
		return Enum.TooltipDataLineType.QuestTitle ~= nil and lineType == Enum.TooltipDataLineType.QuestTitle
	end

	return false
end

local function TryGetTooltipCandidateText(addon, candidateText)
	if not addon:CanAccessValue(candidateText) then
		return nil, true
	end
	if type(candidateText) ~= "string" then
		return nil, false
	end

	candidateText = Services.Access.SafeTrimText(candidateText)
	if candidateText == "" then
		return nil, false
	end

	return candidateText, false
end

local TOOLTIP_ARGUMENT_TEXT_FIELDS =
	{ "leftText", "text", "rightText", "stringVal", "name", "unitName", "title", "value" }
local TOOLTIP_LINE_TEXT_FIELDS = { "leftText", "text", "rightText" }
local function GetTooltipStructuredArgText(addon, argData, depth)
	addon = addon or QuestTogether
	depth = Services.Access.SafeUiNumber(depth, 0) or 0
	if depth > 2 or not addon:CanAccessValue(argData) then
		return nil, true
	end
	if type(argData) == "string" then
		return TryGetTooltipCandidateText(addon, argData)
	end
	if type(argData) ~= "table" then
		return nil, false
	end
	if not addon:CanAccessTable(argData) then
		return nil, true
	end

	local hasUnavailableText = false
	for _, field in ipairs(TOOLTIP_ARGUMENT_TEXT_FIELDS) do
		local candidateText, unavailable = TryGetTooltipCandidateText(addon, argData[field])
		hasUnavailableText = hasUnavailableText or unavailable
		if candidateText then
			return candidateText, hasUnavailableText
		end
	end

	for key, value in pairs(argData) do
		if not addon:CanAccessValue(key) then
			hasUnavailableText = true
		elseif key ~= "field" and key ~= "key" then
			local directValue, unavailable = TryGetTooltipCandidateText(addon, value)
			hasUnavailableText = hasUnavailableText or unavailable
			if directValue then
				return directValue, hasUnavailableText
			end
			if not unavailable and type(value) == "table" then
				local nestedText, nestedUnavailable = GetTooltipStructuredArgText(addon, value, depth + 1)
				hasUnavailableText = hasUnavailableText or nestedUnavailable
				if nestedText then
					return nestedText, hasUnavailableText
				end
			end
		end
	end

	return nil, hasUnavailableText
end

local function GetTooltipQuestLinePrimaryText(lineData, addon)
	addon = addon or QuestTogether
	if not addon:CanAccessTable(lineData) then
		return nil, true
	end

	local hasUnavailableText = false
	for _, field in ipairs(TOOLTIP_LINE_TEXT_FIELDS) do
		local candidateText, unavailable = TryGetTooltipCandidateText(addon, lineData[field])
		hasUnavailableText = hasUnavailableText or unavailable
		if candidateText then
			return candidateText, hasUnavailableText
		end
	end

	local argsText, argsUnavailable = GetTooltipStructuredArgText(addon, lineData.args, 0)
	return argsText, hasUnavailableText or argsUnavailable
end

local function IsThreatTooltipMarkerText(text)
	if type(text) ~= "string" or text == "" then
		return false
	end
	if type(THREAT_TOOLTIP) ~= "string" or THREAT_TOOLTIP == "" then
		return false
	end

	return Services.Access.SafeTrimText(text) == Services.Access.SafeTrimText(THREAT_TOOLTIP)
end

local function GetTooltipQuestLeftText(addon, lineData)
	local leftText = GetTooltipQuestLinePrimaryText(lineData, addon)
	if type(leftText) ~= "string" then
		return ""
	end

	return Services.Access.SafeTrimText(leftText)
end

local function NormalizeTooltipObjectiveEvidenceText(text)
	local normalizedText = Services.Access.SafeTrimText(text)
	if normalizedText == "" then
		return ""
	end

	normalizedText = string.gsub(normalizedText, "^[-%*%+%s]+", "")

	local leadingAmountSuffix = Services.Access.SafeMatch(normalizedText, "^%d+%s*/%s*%d+%s+(.+)$")
	if type(leadingAmountSuffix) == "string" and leadingAmountSuffix ~= "" then
		normalizedText = Services.Access.SafeTrimText(leadingAmountSuffix)
	end

	local leadingPercentSuffix = Services.Access.SafeMatch(normalizedText, "^%d+%%%s+(.+)$")
	if type(leadingPercentSuffix) == "string" and leadingPercentSuffix ~= "" then
		normalizedText = Services.Access.SafeTrimText(leadingPercentSuffix)
	end

	local trimmedPrefix = Services.Access.SafeMatch(normalizedText, "^(.-):%s*%d+%s*/%s*%d+$")
	if type(trimmedPrefix) == "string" and trimmedPrefix ~= "" then
		normalizedText = Services.Access.SafeTrimText(trimmedPrefix)
	end

	local percentPrefix = Services.Access.SafeMatch(normalizedText, "^(.-)%s*%(%d+%%%s*%)$")
	if type(percentPrefix) == "string" and percentPrefix ~= "" then
		normalizedText = Services.Access.SafeTrimText(percentPrefix)
	end

	return normalizedText
end

local function AddNameplateQuestTextToCache(cache, text)
	if type(cache) ~= "table" then
		return
	end

	local trimmedText = Services.Access.SafeTrimText(text)
	if trimmedText == "" then
		return
	end

	cache[trimmedText] = true

	local normalizedText = NormalizeTooltipObjectiveEvidenceText(trimmedText)
	if normalizedText ~= "" then
		cache[normalizedText] = true
	end
end

local function GetKnownTooltipQuestText(text)
	local primaryText = Services.Access.SafeTrimText(text)
	if primaryText == "" then
		return nil
	end
	if IsKnownNameplateQuestText(primaryText) then
		return primaryText
	end

	local normalizedText = NormalizeTooltipObjectiveEvidenceText(primaryText)
	if normalizedText ~= "" and IsKnownNameplateQuestText(normalizedText) then
		return normalizedText
	end

	return nil
end

local function IsKnownTooltipQuestTitle(addon, text)
	-- The text cache also contains objective labels. Only an actual title may
	-- reopen a terminated raw block; use owned quest records, never live APIs.
	local function ContainsTitle(quests)
		if type(quests) ~= "table" then
			return false
		end
		for _, quest in pairs(quests) do
			if type(quest) == "table" and Services.Access.SafeTrimText(quest.title) == text then
				return true
			end
		end
		return false
	end
	local snapshot = addon.GetQuestSnapshotByQuestID and addon:GetQuestSnapshotByQuestID() or nil
	if ContainsTitle(snapshot) then
		return true
	end
	-- A captured character key keeps GetPlayerTracker on its owned-data path.
	local tracker = addon.activeCharacterKey and addon.GetPlayerTracker and addon:GetPlayerTracker() or nil
	return ContainsTitle(tracker)
end

local function IsKnownTooltipQuestPlayerText(addon, text)
	-- Raw tooltip sources do not identify player rows. Only a current, copied
	-- roster identity may carry a quest block across an otherwise unknown label.
	-- Do not query unit APIs or shared tooltip state while interpreting text.
	if type(text) ~= "string" or text == "" then
		return false
	end
	local playerText = Services.Access.SafeTrimText((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
	for fullName, member in pairs(addon.partyMembers or {}) do
		if type(fullName) == "string" then
			local shortName = Services.Access.SafeMatch(fullName, "^([^%-]+)%-") or fullName
			if
				playerText == fullName
				or playerText == shortName
				or (type(member) == "table" and playerText == member.displayName)
			then
				return true
			end
		end
	end
	return false
end

local function AddTooltipQuestBoundary(tooltipLines, unavailable)
	-- Missing leading data may own the next objective. Keep that boundary even
	-- before any readable output, without classifying ordinary raw unit headers.
	if
		(#tooltipLines > 0 or unavailable)
		and (#tooltipLines == 0 or tooltipLines[#tooltipLines].type ~= "QuestBoundary")
	then
		tooltipLines[#tooltipLines + 1] = { type = "QuestBoundary" }
	end
end

-- Mirrors Plater's tooltip-driven objective detection while broadening the
-- addon-owned known-text cache to include active quest objective texts.
function QuestTogether:TooltipLineHasUnfinishedObjectiveEvidence(lineData)
	if not self:CanAccessTable(lineData) then
		return false
	end
	local leftText = GetTooltipQuestLeftText(self, lineData)
	local progressState = leftText ~= "" and GetObjectiveProgressState(leftText) or "unknown"
	if leftText ~= "" and progressState == "unfinished" then
		return true
	end

	if
		leftText ~= ""
		and IsTooltipQuestObjectiveLineType(lineData.type)
		and progressState ~= "complete"
		and GetKnownTooltipQuestText(leftText) ~= nil
	then
		return true
	end

	return false
end

function QuestTogether:ShouldKeepTooltipLineForQuestDetection(lineData)
	if not self:CanAccessTable(lineData) then
		return false
	end

	local leftText = self:SanitizeTooltipQuestLineText(GetTooltipQuestLinePrimaryText(lineData, self))
	if not leftText then
		return false
	end
	if GetKnownTooltipQuestText(leftText) ~= nil then
		return true
	end

	return GetObjectiveProgressState(leftText) ~= "unknown"
end

function QuestTogether:EvaluateTooltipQuestObjectiveLines(tooltipLines)
	if not self:CanAccessTable(tooltipLines) then
		return false
	end

	local matchedQuestBlock = false
	local hasQuestBlockBoundary = false
	local hasCompletedObjective = false
	local canConfirmCompletion = tooltipLines.hasIncompleteQuestData ~= true

	for _, lineData in ipairs(tooltipLines) do
		if not self:CanAccessTable(lineData) then
			canConfirmCompletion = false
			break
		end

		local lineType = lineData.type
		if not self:CanAccessValue(lineType) then
			canConfirmCompletion = false
			break
		end

		local primaryText = GetTooltipQuestLinePrimaryText(lineData)
		local matchedQuestText = GetKnownTooltipQuestText(primaryText)
		local progressState = GetObjectiveProgressState(primaryText)
		if lineType == "QuestBoundary" then
			matchedQuestBlock = false
			hasQuestBlockBoundary = true
		elseif IsTooltipQuestTitleLineType(lineType) then
			-- Party progress belongs to the current quest, not every quest below
			-- the first recognized title in the tooltip.
			matchedQuestBlock = matchedQuestText ~= nil
			hasQuestBlockBoundary = true
		else
			if
				hasQuestBlockBoundary
				and not matchedQuestBlock
				and matchedQuestText ~= nil
				and progressState == "unknown"
				and not IsTooltipQuestObjectiveLineType(lineType)
				and not IsTooltipQuestPlayerLineType(lineType)
				and IsKnownTooltipQuestTitle(self, primaryText)
			then
				matchedQuestBlock = true
			end
			-- Objective wording is shared across quests. A known objective can
			-- stand alone, but cannot reopen an explicit or raw unmatched block.
			local matchesTitlelessQuestText = not hasQuestBlockBoundary and matchedQuestText ~= nil
			if (matchedQuestBlock or matchesTitlelessQuestText) and progressState == "complete" then
				hasCompletedObjective = true
			end
			if IsTooltipQuestObjectiveLineType(lineType) and progressState == "unknown" then
				canConfirmCompletion = false
			end
			if
				not matchedQuestBlock
				and matchesTitlelessQuestText
				and self:TooltipLineHasUnfinishedObjectiveEvidence(lineData)
			then
				return true
			end
			if matchedQuestBlock then
				if IsThreatTooltipMarkerText(primaryText) then
					matchedQuestBlock = false
					hasQuestBlockBoundary = true
				elseif self:TooltipLineHasUnfinishedObjectiveEvidence(lineData) then
					return true
				elseif
					progressState == "unknown"
					and matchedQuestText == nil
					and not IsTooltipQuestObjectiveLineType(lineType)
					and not IsTooltipQuestPlayerLineType(lineType)
					and not IsKnownTooltipQuestPlayerText(self, primaryText)
				then
					-- An untyped unknown title must not donate its progress to the
					-- preceding known quest. Typed/roster-backed player rows survive.
					matchedQuestBlock = false
					hasQuestBlockBoundary = true
				end
			elseif matchesTitlelessQuestText then
				matchedQuestBlock = true
			end
		end
	end

	return false, hasCompletedObjective and canConfirmCompletion, canConfirmCompletion
end

function QuestTogether:ClearNameplateResolvedQuestState()
	wipe(self:GetNameplateStateStore().questStateByUnitToken)
	wipe(self:GetNameplateStateStore().questGuidByUnitToken)
end

-- Invalidate both spawn and NPC completion evidence when quest state changes,
-- so new/reaccepted quests can make the same creature relevant again.
function QuestTogether:ClearNameplateQuestDetectionCache()
	wipe(self:GetNameplateStateStore().questStateByGuid)
	wipe(self:GetNameplateStateStore().completedByNpcID)
	wipe(self:GetNameplateStateStore().tooltipResolveRetryCountByUnitToken)
end

function QuestTogether:ForgetResolvedNameplateQuestState(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	self:GetNameplateStateStore().questStateByUnitToken[unitToken] = nil
	self:GetNameplateStateStore().questGuidByUnitToken[unitToken] = nil
end

function QuestTogether:GetNameplateTooltipResolveRetryCount(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return 0
	end

	local retryCounts = self:GetNameplateStateStore().tooltipResolveRetryCountByUnitToken
	if type(retryCounts) ~= "table" then
		return 0
	end

	return Services.Access.SafeUiNumber(retryCounts[unitToken], 0) or 0
end

function QuestTogether:ClearNameplateTooltipResolveRetryCount(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local retryCounts = self:GetNameplateStateStore().tooltipResolveRetryCountByUnitToken
	if type(retryCounts) == "table" then
		retryCounts[unitToken] = nil
	end
end

function QuestTogether:MaybeScheduleNameplateTooltipRetry(unitToken, reason, unitGuid)
	if not self:IsNameplateUnitToken(unitToken) then
		return false
	end

	local retryCount = self:GetNameplateTooltipResolveRetryCount(unitToken)
	if retryCount >= NAMEPLATE_TOOLTIP_RETRY_MAX_ATTEMPTS then
		return false
	end

	self:GetNameplateStateStore().tooltipResolveRetryCountByUnitToken[unitToken] = retryCount + 1
	if self.ScheduleNameplateTooltipResolution then
		self:ScheduleNameplateTooltipResolution(
			unitToken,
			unitGuid,
			NAMEPLATE_TOOLTIP_RETRY_DELAY_SECONDS,
			reason or "NameplateTooltipRetry"
		)
		return true
	end

	return false
end

-- Derive creature identity from a readable GUID, never from a recycled frame.
-- Completion applies to other spawns of this NPC, not to players or pets.
local function GetNpcIdFromUnitGuid(unitGuid)
	if not QuestTogether:CanAccessValue(unitGuid) or type(unitGuid) ~= "string" then
		return nil
	end
	local kind = Services.Access.SafeMatch(unitGuid, "^([^-]+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then
		return nil
	end
	local npcIdText = Services.Access.SafeMatch(unitGuid, "^[^-]+%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
	local npcId = Services.Access.SafeUiNumber(npcIdText, nil)
	return npcId and npcId > 0 and npcId or nil
end

function QuestTogether:RememberNameplateNpcCompletion(unitGuid, completed)
	local npcID = GetNpcIdFromUnitGuid(unitGuid)
	if npcID then
		self:GetNameplateStateStore().completedByNpcID[npcID] = completed and true or nil
	end
end

function QuestTogether:StoreResolvedNameplateQuestState(unitToken, unitGuid, isQuestObjective)
	if not Services.Access.IsNonEmptyString(unitGuid) then
		return
	end

	self:GetNameplateStateStore().questStateByGuid[unitGuid] = isQuestObjective and true or false
	if self:IsNameplateUnitToken(unitToken) then
		self:GetNameplateStateStore().questStateByUnitToken[unitToken] = isQuestObjective and true or false
		self:GetNameplateStateStore().questGuidByUnitToken[unitToken] = unitGuid
		if isQuestObjective then
			self:ClearNameplateTooltipResolveRetryCount(unitToken)
		end
	end
end

function QuestTogether:TryGetCachedQuestObjectiveStateForGuid(unitGuid)
	if not Services.Access.IsNonEmptyString(unitGuid) then
		return false, nil
	end
	local npcID = GetNpcIdFromUnitGuid(unitGuid)
	if npcID and self:GetNameplateStateStore().completedByNpcID[npcID] then
		-- Confirmed completion takes precedence over an older positive spawn.
		return true, false
	end

	local cachedQuestObjective = self:GetNameplateStateStore().questStateByGuid[unitGuid]
	if cachedQuestObjective == nil then
		return false, nil
	end

	return true, cachedQuestObjective == true
end

local function AddTrackedQuestObjectiveTextsToNameplateCache(addon, cache)
	if not addon or type(cache) ~= "table" or not addon.GetPlayerTracker then
		return
	end

	local tracker = addon:GetPlayerTracker()
	if type(tracker) ~= "table" then
		return
	end

	for _, trackedQuest in pairs(tracker) do
		if type(trackedQuest) == "table" then
			AddNameplateQuestTextToCache(cache, trackedQuest.title)
			if trackedQuest.isComplete ~= true and trackedQuest.isReadyForTurnIn ~= true then
				local objectives = trackedQuest.objectives
				if type(objectives) == "table" then
					for objectiveIndex = 1, #objectives do
						AddNameplateQuestTextToCache(cache, objectives[objectiveIndex])
					end
				end
			end
		end
	end
end

local function AddLiveQuestObjectiveTextsToNameplateCache(addon, cache, questID, questDetails)
	if not addon or type(cache) ~= "table" or type(questDetails) ~= "table" then
		return
	end

	local api = addon.API
	if type(api) ~= "table" then
		return
	end

	local questLogIndex = addon.GetQuestLogIndexForQuest and addon:GetQuestLogIndexForQuest(questID, questDetails)
		or nil
	if questLogIndex == nil then
		return
	end

	local rawObjectiveCount = api.GetNumQuestLeaderBoards and api.GetNumQuestLeaderBoards(questLogIndex) or 0
	local objectiveCount = addon.SafeToNumber and addon:SafeToNumber(rawObjectiveCount) or nil
	if objectiveCount == nil then
		return
	end
	objectiveCount = math.floor(objectiveCount + 0.5)
	if objectiveCount <= 0 then
		return
	end

	for objectiveIndex = 1, objectiveCount do
		local objectiveText, _, finished = addon:GetNormalizedQuestObjectiveInfo(questID, objectiveIndex, false)
		if finished ~= true then
			AddNameplateQuestTextToCache(cache, objectiveText)
		end
	end
end

-- QuestTogether keeps the nameplate quest-text cache on addon-owned quest-log
-- state only. Plater also adds current-map world quest data from C_TaskQuest
-- map arrays, but those map-owned tables taint Blizzard POI/widget paths on the
-- default UI.
function QuestTogether:RebuildNameplateQuestTextCache()
	wipe(self:GetNameplateStateStore().textCache)

	local isInInstance = self.API and self.API.IsInInstance and self.API.IsInInstance()
	if isInInstance then
		self:SetRuntimeFlag("nameplateQuestTextCacheSuppressed", true)
		return
	end

	if self.EnsureQuestSnapshotStore then
		self:EnsureQuestSnapshotStore()
	end

	local snapshotByQuestID = self.GetQuestSnapshotByQuestID and self:GetQuestSnapshotByQuestID() or nil
	local snapshotOrder = self.GetQuestSnapshotOrder and self:GetQuestSnapshotOrder() or nil
	if type(snapshotOrder) ~= "table" then
		return
	end

	for index = 1, #snapshotOrder do
		local questID = snapshotOrder[index]
		local questDetails = snapshotByQuestID and snapshotByQuestID[questID] or nil
		if questDetails then
			AddNameplateQuestTextToCache(self:GetNameplateStateStore().textCache, questDetails.title)
			AddLiveQuestObjectiveTextsToNameplateCache(
				self,
				self:GetNameplateStateStore().textCache,
				questID,
				questDetails
			)
		end
	end

	AddTrackedQuestObjectiveTextsToNameplateCache(self, self:GetNameplateStateStore().textCache)
	self:SetRuntimeFlag("nameplateQuestTextCacheSuppressed", false)
end

function QuestTogether:TryGetReusableCachedNameplateQuestState(unitToken, unitGuid)
	local hasCachedQuestState, cachedQuestState = self:TryGetCachedQuestObjectiveStateForGuid(unitGuid)
	if not hasCachedQuestState then
		return false, nil
	end

	if self:IsNameplateUnitToken(unitToken) then
		self:GetNameplateStateStore().questStateByUnitToken[unitToken] = cachedQuestState and true or false
		self:GetNameplateStateStore().questGuidByUnitToken[unitToken] = unitGuid
	end

	return true, cachedQuestState
end

-- Unit tokens and frames are recycled independently. Only a readable live GUID
-- owns cached quest state. Token tooltip scans can still resolve without it.
function QuestTogether:GetNameplateTooltipScanGuid(unitToken, _unitFrame)
	local liveGuid = self:GetNameplateUnitGuid(unitToken)
	if Services.Access.IsNonEmptyString(liveGuid) then
		return liveGuid
	end
	return nil
end

-- Questie normalization mirrors the cleanup Plater applies in local retail
-- Plater.lua:11211-11217 before it matches titles against QuestCache.
local function NormalizeQuestieTooltipQuestLineText(textValue)
	if type(textValue) ~= "string" or textValue == "" then
		return nil
	end

	local normalizedText = string.gsub(textValue, "|c%x%x%x%x%x%x%x%x", "")
	normalizedText = string.gsub(normalizedText, "|r", "")
	normalizedText = string.gsub(normalizedText, "%[.*%] ", "")
	normalizedText = string.gsub(normalizedText, " %(%d+%)", "")
	normalizedText = Services.Access.SafeTrimText(normalizedText)
	if normalizedText == "" then
		return nil
	end

	return normalizedText
end

function QuestTogether:SanitizeTooltipQuestLineText(textValue)
	if self:IsSecretValue(textValue) or type(textValue) ~= "string" then
		return nil
	end

	local trimmedValue = Services.Access.SafeTrimText(textValue)
	if trimmedValue == "" then
		return nil
	end

	return trimmedValue
end

-- Plater keeps only QuestObjective, QuestTitle, and QuestPlayer lines from
-- C_TooltipInfo in local retail Plater.lua:11197-11203. QuestTogether mirrors
-- that default filter, but also preserves generic lines that already look like
-- quest titles or objective progress after addon-owned normalization.
function QuestTogether:SanitizeTooltipLineForQuestDetection(lineData)
	if not self:CanAccessTable(lineData) then
		return nil
	end

	local lineType = lineData.type
	if not self:CanAccessValue(lineType) then
		return nil
	end
	if
		not IsTooltipQuestObjectiveLineType(lineType)
		and not IsTooltipQuestTitleLineType(lineType)
		and not IsTooltipQuestPlayerLineType(lineType)
		and not self:ShouldKeepTooltipLineForQuestDetection(lineData)
	then
		local playerText = self:SanitizeTooltipQuestLineText(GetTooltipQuestLinePrimaryText(lineData, self))
		if not IsKnownTooltipQuestPlayerText(self, playerText) then
			return nil
		end
		lineType = "QuestPlayer"
	end

	local primaryText, unavailable = GetTooltipQuestLinePrimaryText(lineData, self)
	local leftText = self:SanitizeTooltipQuestLineText(primaryText)
	if not leftText then
		return nil
	end

	return {
		type = lineType,
		leftText = leftText,
	}, unavailable
end

function QuestTogether:ExtractQuestObjectiveTooltipLinesFromTooltipData(tooltipData)
	if not self:CanAccessTable(tooltipData) then
		return nil
	end
	if self.API and type(self.API.SurfaceTooltipDataArgs) == "function" then
		local surfacedTooltipData = self.API.SurfaceTooltipDataArgs(tooltipData)
		if self:CanAccessTable(surfacedTooltipData) then
			tooltipData = surfacedTooltipData
		end
	end

	local tooltipLineData = tooltipData.lines
	if not self:CanAccessTable(tooltipLineData) then
		return nil
	end

	local tooltipLines = {}
	for lineIndex = 1, #tooltipLineData do
		local rawLine = tooltipLineData[lineIndex]
		local sanitizedLine, unavailable = self:SanitizeTooltipLineForQuestDetection(rawLine)
		if sanitizedLine then
			if unavailable then
				tooltipLines.hasIncompleteQuestData = true
				AddTooltipQuestBoundary(tooltipLines, true)
			end
			tooltipLines[#tooltipLines + 1] = sanitizedLine
		elseif not self:CanAccessTable(rawLine) or not self:CanAccessValue(rawLine.type) then
			tooltipLines.hasIncompleteQuestData = true
			AddTooltipQuestBoundary(tooltipLines, true)
		elseif IsTooltipQuestTitleLineType(rawLine.type) then
			-- Even a first unreadable title owns the following objectives. Retain
			-- an unmatched title without copying inaccessible text, so shared
			-- objective wording cannot be mistaken for titleless quest evidence.
			tooltipLines.hasIncompleteQuestData = true
			tooltipLines[#tooltipLines + 1] = { type = "QuestTitle" }
		elseif IsTooltipQuestObjectiveLineType(rawLine.type) or IsTooltipQuestPlayerLineType(rawLine.type) then
			tooltipLines.hasIncompleteQuestData = true
			AddTooltipQuestBoundary(tooltipLines, true)
		else
			local primaryText, unavailable = GetTooltipQuestLinePrimaryText(rawLine, self)
			if unavailable then
				tooltipLines.hasIncompleteQuestData = true
				AddTooltipQuestBoundary(tooltipLines, true)
			elseif self:SanitizeTooltipQuestLineText(primaryText) then
				-- Filtering a generic unknown title must not join two quest blocks.
				AddTooltipQuestBoundary(tooltipLines)
			end
		end
	end

	return tooltipLines
end

function QuestTogether:GetStructuredQuestObjectiveTooltipLinesFromUnit(unitToken)
	if type(unitToken) ~= "string" or unitToken == "" then
		return nil
	end
	if not self:IsNameplateUnitToken(unitToken) then
		return nil
	end
	if not self.API or type(self.API.GetTooltipDataForUnit) ~= "function" then
		return nil
	end

	return self.API.GetTooltipDataForUnit(unitToken)
end

function QuestTogether:GetStructuredQuestObjectiveTooltipLinesFromHyperlink(unitGuid)
	if type(unitGuid) ~= "string" or unitGuid == "" then
		return nil
	end
	if not self.API or type(self.API.GetTooltipDataForHyperlink) ~= "function" then
		return nil
	end

	return self.API.GetTooltipDataForHyperlink("unit:" .. unitGuid)
end

-- Questie is Plater's first quest-tooltip source in local retail Plater.lua:11191-11196.
-- We mirror that source order, but read the Questie module through guarded accessors.
function QuestTogether:GetQuestieTooltipDataForNpc(npcId)
	local questieLoader = _G and _G.QuestieLoader or nil
	if not self:CanAccessTable(questieLoader) then
		return nil
	end

	local modules = questieLoader._modules
	if not self:CanAccessTable(modules) then
		return nil
	end

	local questieTooltips = modules["QuestieTooltips"]
	if not self:CanAccessTable(questieTooltips) then
		return nil
	end
	local getTooltip = questieTooltips.GetTooltip
	if not self:CanAccessValue(getTooltip) or type(getTooltip) ~= "function" then
		return nil
	end

	local ok, tooltipData = pcall(getTooltip, "m_" .. tostring(npcId))
	if not ok or not self:CanAccessTable(tooltipData) then
		return nil
	end
	return tooltipData
end

function QuestTogether:GetQuestieQuestObjectiveTooltipLines(unitGuid)
	local npcId = GetNpcIdFromUnitGuid(unitGuid)
	if not npcId then
		return nil
	end
	local tooltipData = self:GetQuestieTooltipDataForNpc(npcId)
	if not self:CanAccessTable(tooltipData) then
		return nil
	end

	local tooltipLines = {}
	for lineIndex = 1, #tooltipData do
		local rawLine = tooltipData[lineIndex]
		if not self:CanAccessValue(rawLine) or type(rawLine) ~= "string" then
			tooltipLines.hasIncompleteQuestData = true
			AddTooltipQuestBoundary(tooltipLines, true)
		else
			local normalizedText = NormalizeQuestieTooltipQuestLineText(rawLine)
			if normalizedText then
				tooltipLines[#tooltipLines + 1] = { leftText = normalizedText }
			end
		end
	end

	if #tooltipLines > 0 or tooltipLines.hasIncompleteQuestData then
		return tooltipLines
	end

	return nil
end

-- Structured Blizzard tooltip data is Plater's second source on retail/mainline
-- in local retail Plater.lua:11208-11218 after Questie.
function QuestTogether:GetStructuredQuestObjectiveTooltipLines(unitToken, unitGuid, structuredSource)
	if Services.Access.ShouldSuppressStructuredQuestTooltipSource(self) then
		return nil
	end

	if type(unitGuid) ~= "string" or unitGuid == "" then
		if structuredSource ~= "unit" then
			return nil
		end
	end
	if not self.API then
		return nil
	end

	local tooltipData = nil
	local sourceLabel = structuredSource
	if sourceLabel == "unit" then
		tooltipData = self:GetStructuredQuestObjectiveTooltipLinesFromUnit(unitToken)
	elseif sourceLabel == "hyperlink" or sourceLabel == nil then
		tooltipData = self:GetStructuredQuestObjectiveTooltipLinesFromHyperlink(unitGuid)
		if sourceLabel == nil then
			sourceLabel = "hyperlink"
		end
	else
		return nil
	end

	if tooltipData ~= nil then
		local tooltipLines = self:ExtractQuestObjectiveTooltipLinesFromTooltipData(tooltipData)
		if type(tooltipLines) == "table" and (#tooltipLines > 0 or tooltipLines.hasIncompleteQuestData) then
			return tooltipLines
		end
	end

	return nil
end

-- The hidden GameTooltip scan is only the non-mainline branch in Plater.IsQuestObjective
-- at local retail Plater.lua:11219-11226. On retail clients, Plater stops after C_TooltipInfo.
function QuestTogether:GetHiddenQuestObjectiveTooltipLines(unitToken, unitGuid)
	if (type(unitToken) ~= "string" or unitToken == "") and (type(unitGuid) ~= "string" or unitGuid == "") then
		return nil
	end

	local scanTooltip = self:GetOrCreateNameplateScanTooltip()
	if not scanTooltip then
		return nil
	end

	return self:ReadNameplateScanTooltipLines(scanTooltip, unitToken, unitGuid)
end

function QuestTogether:GetQuestObjectiveTooltipLineSources(unitToken, unitGuid)
	if type(unitGuid) ~= "string" or unitGuid == "" then
		if not self:IsNameplateUnitToken(unitToken) then
			return {}
		end
	end

	local sourceOrder = {}
	if self:IsRuntimeRestricted() then
		-- During combat use only the data API for the accessible live token.
		-- Questie callbacks and hidden GameTooltip scans can mutate shared UI.
		return {
			{
				name = "structured_unit",
				resolve = function()
					return self:GetStructuredQuestObjectiveTooltipLines(unitToken, unitGuid, "unit")
				end,
			},
		}
	end

	sourceOrder[#sourceOrder + 1] = {
		name = "questie",
		resolve = function()
			return self:GetQuestieQuestObjectiveTooltipLines(unitGuid)
		end,
	}
	sourceOrder[#sourceOrder + 1] = {
		name = "structured_unit",
		resolve = function()
			return self:GetStructuredQuestObjectiveTooltipLines(unitToken, unitGuid, "unit")
		end,
	}
	sourceOrder[#sourceOrder + 1] = {
		name = "structured_hyperlink",
		resolve = function()
			return self:GetStructuredQuestObjectiveTooltipLines(unitToken, unitGuid, "hyperlink")
		end,
	}

	if self:IsNameplateTooltipScanEnabled() then
		sourceOrder[#sourceOrder + 1] = {
			name = "hidden",
			resolve = function()
				return self:GetHiddenQuestObjectiveTooltipLines(unitToken, unitGuid)
			end,
		}
	end

	return sourceOrder
end

function QuestTogether:CanUseStructuredQuestTooltipAPI()
	if not self.API then
		return false
	end

	return type(self.API.GetTooltipDataForUnit) == "function" or type(self.API.GetTooltipDataForHyperlink) == "function"
end

-- Test/helper entry point that mirrors Plater's source order for the current
-- client. Structured-tooltip clients use Questie -> C_TooltipInfo, while
-- older clients fall back to the addon-owned hidden GameTooltip path.
function QuestTogether:GetQuestObjectiveTooltipLines(unitToken, unitGuid, startIndex)
	local sources = self:GetQuestObjectiveTooltipLineSources(unitToken, unitGuid)
	local firstIndex = Services.Access.SafeUiNumber(startIndex, 1) or 1
	if firstIndex < 1 then
		firstIndex = 1
	end
	for index = firstIndex, #sources do
		local source = sources[index]
		local tooltipLines = nil
		if type(source) == "table" then
			if type(source.resolve) == "function" then
				tooltipLines = source.resolve()
			else
				tooltipLines = source.lines
			end
		end
		if type(tooltipLines) == "table" and (#tooltipLines > 0 or tooltipLines.hasIncompleteQuestData) then
			return tooltipLines, source.name, index
		end
	end

	return nil
end

function QuestTogether:GetOrCreateNameplateScanTooltip()
	local scanTooltip = self.nameplateScanTooltip
	if scanTooltip and Services.Access.IsFrameForbidden(scanTooltip) then
		scanTooltip = nil
	end
	if scanTooltip then
		return scanTooltip
	end

	local existingTooltip = _G and _G[NAMEPLATE_SCAN_TOOLTIP_NAME] or nil
	if existingTooltip and not Services.Access.IsFrameForbidden(existingTooltip) then
		self.nameplateScanTooltip = existingTooltip
		return existingTooltip
	end

	if type(CreateFrame) ~= "function" then
		return nil
	end

	local parentFrame = UIParent or WorldFrame or nil
	local ok, createdTooltip =
		pcall(CreateFrame, "GameTooltip", NAMEPLATE_SCAN_TOOLTIP_NAME, parentFrame, "GameTooltipTemplate")
	if not ok or not createdTooltip or Services.Access.IsFrameForbidden(createdTooltip) then
		return nil
	end

	self.nameplateScanTooltip = createdTooltip
	return createdTooltip
end

function QuestTogether:GetNameplateScanTooltipLineCount(scanTooltip)
	if not scanTooltip or Services.Access.IsFrameForbidden(scanTooltip) or not scanTooltip.NumLines then
		return nil
	end

	local ok, lineCount = pcall(scanTooltip.NumLines, scanTooltip)
	if not ok or self:IsSecretValue(lineCount) then
		return nil
	end

	return Services.Access.SafeUiNumber(lineCount, nil)
end

function QuestTogether:GetNameplateScanTooltipFontString(scanTooltip, lineIndex)
	if not scanTooltip or Services.Access.IsFrameForbidden(scanTooltip) or type(lineIndex) ~= "number" then
		return nil
	end

	local tooltipName = nil
	if scanTooltip.GetName then
		local ok, resolvedName = pcall(scanTooltip.GetName, scanTooltip)
		if ok and not self:IsSecretValue(resolvedName) and Services.Access.IsNonEmptyString(resolvedName) then
			tooltipName = resolvedName
		end
	end
	if not Services.Access.IsNonEmptyString(tooltipName) then
		return nil
	end

	return _G and _G[tooltipName .. "TextLeft" .. tostring(lineIndex)] or nil
end

function QuestTogether:GetNameplateScanTooltipLeftText(scanTooltip, lineIndex)
	local fontString = self:GetNameplateScanTooltipFontString(scanTooltip, lineIndex)
	if
		not self:CanAccessValue(fontString)
		or not fontString
		or Services.Access.IsFrameForbidden(fontString)
		or not fontString.GetText
	then
		return nil
	end

	local ok, textValue = pcall(fontString.GetText, fontString)
	if not ok or not self:CanAccessValue(textValue) or type(textValue) ~= "string" then
		return nil
	end

	return textValue
end

function QuestTogether:ReadNameplateScanTooltipLines(scanTooltip, unitToken, unitGuid)
	if not scanTooltip or Services.Access.IsFrameForbidden(scanTooltip) then
		return nil
	end

	if scanTooltip.Hide then
		pcall(scanTooltip.Hide, scanTooltip)
	end
	if scanTooltip.ClearLines then
		pcall(scanTooltip.ClearLines, scanTooltip)
	end

	local ownerFrame = WorldFrame or UIParent or nil
	if ownerFrame and scanTooltip.SetOwner then
		pcall(scanTooltip.SetOwner, scanTooltip, ownerFrame, "ANCHOR_NONE")
	end
	local ok = false
	if
		type(unitToken) == "string"
		and unitToken ~= ""
		and self:IsNameplateUnitToken(unitToken)
		and scanTooltip.SetUnit
	then
		ok = pcall(scanTooltip.SetUnit, scanTooltip, unitToken)
	end
	if (not ok) and type(unitGuid) == "string" and unitGuid ~= "" and scanTooltip.SetHyperlink then
		ok = pcall(scanTooltip.SetHyperlink, scanTooltip, "unit:" .. unitGuid)
	end
	if not ok then
		if scanTooltip.Hide then
			pcall(scanTooltip.Hide, scanTooltip)
		end
		if scanTooltip.ClearLines then
			pcall(scanTooltip.ClearLines, scanTooltip)
		end
		return nil
	end

	local tooltipLines = {}
	local lineCount = self:GetNameplateScanTooltipLineCount(scanTooltip)
	if lineCount == nil then
		tooltipLines.hasIncompleteQuestData = true
	else
		for lineIndex = 1, lineCount do
			local rawText = self:GetNameplateScanTooltipLeftText(scanTooltip, lineIndex)
			if not self:CanAccessValue(rawText) or type(rawText) ~= "string" then
				tooltipLines.hasIncompleteQuestData = true
				AddTooltipQuestBoundary(tooltipLines, true)
			else
				local leftText = Services.Access.SafeTrimText(rawText)
				if leftText ~= "" then
					tooltipLines[#tooltipLines + 1] = { leftText = leftText }
				end
			end
		end
	end

	if scanTooltip.Hide then
		pcall(scanTooltip.Hide, scanTooltip)
	end
	if scanTooltip.ClearLines then
		pcall(scanTooltip.ClearLines, scanTooltip)
	end

	return tooltipLines
end

function QuestTogether:IsNameplateTooltipScanEnabled()
	return true
end

-- Mirrors Plater's source order while keeping live tooltip resolution disabled
-- in map-sensitive runtime contexts.
-- On the default UI, live unit-tooltip reads while AreaPOI/GameTooltip widget sets are
-- active can taint Blizzard's shared world-map tooltip/widget path, so the tooltip
-- evaluator reports "unresolved" there and lets the cache-driven resolver decide.
function QuestTogether:TryEvaluateQuestObjectiveViaTooltip(unitToken, unitFrame, unitGuid)
	if not unitToken then
		return false, false, nil
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false, false, nil
	end

	if not Services.Access.IsNonEmptyString(unitGuid) then
		unitGuid = self:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	end
	if self:IsSecretValue(unitGuid) then
		return false, false, nil
	end
	if not Services.Access.IsNonEmptyString(unitGuid) then
		unitGuid = nil
	end
	if not unitGuid and not self:IsNameplateUnitToken(unitToken) then
		return false, false, nil
	end
	if self.IsWorkBlocked and self:IsWorkBlocked("nameplate_tooltip_resolve") then
		return false, false, unitGuid
	end

	local resolvedAnyTooltipLines = false
	local hasCompletedObjective = false
	local canConfirmCompletion = true
	local nextSourceIndex = 1
	while true do
		local tooltipLines, _sourceName, resolvedSourceIndex =
			self:GetQuestObjectiveTooltipLines(unitToken, unitGuid, nextSourceIndex)
		if type(tooltipLines) ~= "table" or (#tooltipLines == 0 and not tooltipLines.hasIncompleteQuestData) then
			break
		end

		resolvedAnyTooltipLines = true
		local isQuestObjective, allObjectivesComplete, hasCompleteData =
			self:EvaluateTooltipQuestObjectiveLines(tooltipLines)
		if isQuestObjective then
			self:RememberNameplateNpcCompletion(unitGuid, false)
			return true, true, unitGuid
		end
		hasCompletedObjective = hasCompletedObjective or allObjectivesComplete == true
		canConfirmCompletion = canConfirmCompletion and hasCompleteData ~= false
		if type(resolvedSourceIndex) ~= "number" then
			break
		end
		nextSourceIndex = resolvedSourceIndex + 1
	end

	if not resolvedAnyTooltipLines or not canConfirmCompletion then
		return false, false, unitGuid
	end
	if hasCompletedObjective then
		self:RememberNameplateNpcCompletion(unitGuid, true)
	end

	return true, false, unitGuid
end

function QuestTogether:IsQuestObjectiveViaTooltip(unitToken, unitFrame)
	local hasResolvedQuestState, isQuestObjective, unitGuid =
		self:TryEvaluateQuestObjectiveViaTooltip(unitToken, unitFrame)
	if hasResolvedQuestState then
		return isQuestObjective
	end

	local hasCachedQuestState, cachedQuestState = self:TryGetReusableCachedNameplateQuestState(unitToken, unitGuid)
	if hasCachedQuestState then
		return cachedQuestState
	end

	return false
end

function QuestTogether:TryResolveNameplateQuestObjectiveState(unitToken, unitFrame, allowLiveScan)
	if not self.isEnabled then
		return false, false, nil
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false, false, nil
	end
	if not self:IsNameplateUnitToken(unitToken) then
		return false, false, nil
	end
	if not unitFrame or Services.Access.IsFrameForbidden(unitFrame) then
		return false, false, nil
	end

	local unitGuid = self:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	if self:IsSecretValue(unitGuid) then
		unitGuid = nil
	end
	if not Services.Access.IsNonEmptyString(unitGuid) then
		unitGuid = nil
	end
	if not unitGuid and not allowLiveScan then
		return false, false, nil
	end

	local hasCachedQuestState, cachedQuestState = false, nil
	if unitGuid then
		hasCachedQuestState, cachedQuestState = self:TryGetReusableCachedNameplateQuestState(unitToken, unitGuid)
		if hasCachedQuestState and (cachedQuestState or not allowLiveScan) then
			return true, cachedQuestState, unitGuid
		end
	end

	if not allowLiveScan then
		return false, false, unitGuid
	end

	local hasResolvedQuestState, isQuestObjective, resolvedUnitGuid =
		self:TryEvaluateQuestObjectiveViaTooltip(unitToken, unitFrame, unitGuid)
	if hasResolvedQuestState then
		if Services.Access.IsNonEmptyString(resolvedUnitGuid or unitGuid) then
			self:StoreResolvedNameplateQuestState(unitToken, resolvedUnitGuid or unitGuid, isQuestObjective)
		end
		return true, isQuestObjective, resolvedUnitGuid or unitGuid
	end
	if hasCachedQuestState then
		return true, cachedQuestState, unitGuid
	end

	return false, false, resolvedUnitGuid or unitGuid
end

function QuestTogether:DoesNameplateUnitTokenMatchExpectedGuid(unitToken, expectedUnitGuid)
	if not Services.Access.IsNonEmptyString(expectedUnitGuid) then
		return true, nil
	end
	if not self:IsNameplateUnitToken(unitToken) then
		return false, nil
	end

	local liveUnitGuid = self:GetNameplateUnitGuid(unitToken)
	if self:IsSecretValue(liveUnitGuid) or not Services.Access.IsNonEmptyString(liveUnitGuid) then
		return false, nil
	end

	return liveUnitGuid == expectedUnitGuid, liveUnitGuid
end

function QuestTogether:ResolveNameplateQuestStateForUnitToken(unitToken, unitGuid, reason)
	if not self.isEnabled or self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false
	end
	if not self:IsNameplateUnitToken(unitToken) then
		return false
	end

	local namePlateFrameBase, unitFrame = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
	if not namePlateFrameBase or not unitFrame then
		self:MaybeScheduleNameplateTooltipRetry(unitToken, reason, unitGuid)
		return false
	end

	local liveUnitToken = Services.Access.ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	if not self:IsNameplateUnitToken(liveUnitToken) then
		liveUnitToken = unitToken
	end
	local tokenMatchesExpectedGuid = self:DoesNameplateUnitTokenMatchExpectedGuid(liveUnitToken, unitGuid)
	if not tokenMatchesExpectedGuid then
		return false
	end

	local hasResolvedQuestState, isQuestObjective, resolvedUnitGuid =
		self:TryResolveNameplateQuestObjectiveState(liveUnitToken, unitFrame, true)
	if not hasResolvedQuestState then
		local hasRetryScheduled = self:MaybeScheduleNameplateTooltipRetry(
			liveUnitToken,
			reason or "ResolveNameplateQuestStateForUnitToken",
			resolvedUnitGuid or unitGuid
		)
		self:ForgetResolvedNameplateQuestState(liveUnitToken)
		self:HideNameplateIcon(namePlateFrameBase)
		if not hasRetryScheduled then
			Services.Access.PrintOneShotNameplateDebug(
				self,
				string.format(
					"debugResolverUnresolved:%s:%s",
					Services.Access.SafeText(liveUnitToken, "<nil>"),
					Services.Access.SafeText(reason or "ResolveNameplateQuestStateForUnitToken", "<nil>")
				),
				string.format(
					"resolver_unresolved unit=%s reason=%s retry=%s",
					Services.Access.SafeText(liveUnitToken, ""),
					Services.Access.SafeText(reason, ""),
					tostring(hasRetryScheduled)
				)
			)
		end
		return false
	end

	self:ApplyResolvedQuestStateToNameplate(
		namePlateFrameBase,
		liveUnitToken,
		unitFrame,
		isQuestObjective,
		true,
		resolvedUnitGuid or unitGuid
	)
	if not isQuestObjective or not Services.Access.IsNonEmptyString(resolvedUnitGuid or unitGuid) then
		-- Quest lines can arrive after the name/GUID. A negative first read is
		-- retried briefly, without turning non-quest mobs into an endless poll.
		self:MaybeScheduleNameplateTooltipRetry(liveUnitToken, reason, resolvedUnitGuid or unitGuid)
	end
	return true
end

-- Plater's quest-unit decision is tooltip-driven in local retail
-- Plater.IsQuestObjective (Plater.lua:11169-11347). We keep QuestTogether on
-- that same narrow path on purpose and do not layer extra Blizzard quest APIs,
-- assist-token fallbacks, or foreign-frame flags on top of it.
function QuestTogether:IsQuestObjectiveUnit(unitToken, unitFrame)
	if not unitToken then
		return false
	end

	return self:IsQuestObjectiveViaTooltip(unitToken, unitFrame)
end

function QuestTogether:IsQuestObjectiveNameplate(unitToken, unitFrame)
	local hasResolvedQuestState, isQuestObjective =
		self:TryResolveNameplateQuestObjectiveState(unitToken, unitFrame, false)
	if not hasResolvedQuestState then
		return false
	end

	return isQuestObjective
end

Services.Quests = {
	NAMEPLATE_TOOLTIP_RETRY_MAX_ATTEMPTS = NAMEPLATE_TOOLTIP_RETRY_MAX_ATTEMPTS,
}
