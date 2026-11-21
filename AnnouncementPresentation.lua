-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Access = QuestTogether.NativeAccess
local CanAccessForeignValue, CanAccessForeignTable = Access.Value, Access.Table
local SafeText, SafeMatch = Access.Text, Access.Match
local tostring = SafeText
local Values = QuestTogether.NativeQuestValues
local ReadOptionalString = Values.ReadOptionalString
local SanitizeQuestInfoEnumValue = Values.SanitizeQuestInfoEnumValue

function QuestTogether:GetDefaultAnnouncementIconChatTag(size, targetName)
	local asset, kind = self:ResolvePlayerAnnouncementIcon(self.NAMEPLATE_PLAYER_ICON_TEXTURE, "texture", targetName)
	return self:GetIconChatTagFromAsset(asset, kind, size)
end

function QuestTogether:GetIconChatTagFromAsset(iconAsset, iconKind, size)
	local asset = tostring(iconAsset or "")
	if asset == "" then
		return ""
	end

	local iconSize = math.max(1, math.floor((self:SafeToNumber(size) or 14)))
	if iconKind == "atlas" then
		return "|A:" .. asset .. ":" .. tostring(iconSize) .. ":" .. tostring(iconSize) .. "|a"
	end

	return string.format("|T%s:%d:%d:0:0|t", asset, iconSize, iconSize)
end

function QuestTogether:GetClassColorCode(classFile)
	if not CanAccessForeignValue(classFile) or type(classFile) ~= "string" then
		return "|cffffffff"
	end
	-- CUSTOM_CLASS_COLORS is an optional addon integration, not a Blizzard API.
	-- Validate both the registry and its entry before reading display values.
	local colorTable = nil
	if CanAccessForeignTable(CUSTOM_CLASS_COLORS) then
		local customColor = CUSTOM_CLASS_COLORS[classFile]
		if CanAccessForeignTable(customColor) then
			colorTable = customColor
		end
	end
	if not colorTable and CanAccessForeignTable(RAID_CLASS_COLORS) then
		local defaultColor = RAID_CLASS_COLORS[classFile]
		if CanAccessForeignTable(defaultColor) then
			colorTable = defaultColor
		end
	end

	if not colorTable then
		return "|cffffffff"
	end
	local colorString = ReadOptionalString(colorTable.colorStr)
	if not colorString or not colorString:match("^%x%x%x%x%x%x%x%x$") then
		return "|cffffffff"
	end
	return "|c" .. colorString
end

function QuestTogether:GetPlayerClassFile()
	local _, classFile = self.API.UnitClass("player")
	return classFile or "PRIEST"
end

function QuestTogether:GetAddonVersion()
	local metadata = self.API and self.API.GetAddOnMetadata and self.API.GetAddOnMetadata(self.addonName, "Version")
	if type(metadata) ~= "string" then
		return ""
	end

	local version = self:SafeTrimString(metadata, "")
	if version == "" then
		return ""
	end

	return version
end

function QuestTogether:GetShortDisplayName(name)
	name = self:SafeTrimString(name, "")
	if name == "" then
		return L("Unknown")
	end
	if self:UsesRegionalPlayerNames() then
		local fullName = self:NormalizeMemberName(name) or name
		if self:IsSelfSender(fullName) then
			local getter = self.API and self.API.ShouldDisplaySurname
			local ok, showSurname = false, nil
			if type(getter) == "function" then
				ok, showSurname = pcall(getter)
			end
			if not ok or not self:CanAccessValue(showSurname) or showSurname ~= true then
				return SafeMatch(fullName, "^(%S+)") or fullName
			end
		end
		return fullName
	end

	local ambiguate = self.API.Ambiguate or Ambiguate
	if type(ambiguate) == "function" then
		local ok, displayName = pcall(ambiguate, name, "short")
		if ok then
			return self:SafeTrimString(displayName, name)
		end
	end
	return name
end

function QuestTogether:NormalizeAnnouncementWarModeValue(warMode)
	if not self:CanAccessValue(warMode) then
		return nil
	end
	if type(warMode) == "boolean" then
		return warMode
	end
	if type(warMode) == "string" then
		local normalized = string.lower(warMode)
		if warMode == "1" or normalized == "true" then
			return true
		end
		if warMode == "0" or normalized == "false" then
			return false
		end
	end
	return nil
end

function QuestTogether:SupportsWarMode()
	-- Forever uses regional full names and character roles, not Retail's War
	-- Mode. Shared Mainline exports alone do not establish feature support.
	if self:UsesRegionalPlayerNames() then
		return false
	end
	local getter = self.API and self.API.IsWarModeFeatureEnabled
	if type(getter) ~= "function" then
		return nil
	end
	local ok, enabled = pcall(getter)
	if ok and self:CanAccessValue(enabled) and type(enabled) == "boolean" then
		return enabled
	end
	return nil
end

local function IsQuestRecurringFrequency(frequency)
	local frequencyEnum = Enum and Enum.QuestFrequency or nil
	if not frequencyEnum or frequency == nil then
		return false
	end

	return frequency == frequencyEnum.Daily
		or frequency == frequencyEnum.Weekly
		or frequency == frequencyEnum.ResetByScheduler
end

local function GetQuestClassificationFlags(classification)
	local classificationEnum = Enum and Enum.QuestClassification or nil
	if not classificationEnum or classification == nil then
		return {
			isLegendary = false,
			isRepeatable = false,
			isImportant = false,
			isMeta = false,
			isCampaign = false,
			isCalling = false,
		}
	end

	return {
		isLegendary = classification == classificationEnum.Legendary,
		isRepeatable = classification == classificationEnum.Recurring,
		isImportant = classification == classificationEnum.Important,
		isMeta = classification == classificationEnum.Meta,
		isCampaign = classification == classificationEnum.Campaign,
		isCalling = classification == classificationEnum.Calling,
	}
end

local function ResolveQuestOfferAnnouncementIcon(classification, frequency)
	local flags = GetQuestClassificationFlags(classification)
	if flags.isCampaign then
		return "CampaignAvailableQuestIcon", "atlas"
	elseif flags.isLegendary then
		return "legendaryavailablequesticon", "atlas"
	elseif flags.isCalling then
		return "CampaignAvailableDailyQuestIcon", "atlas"
	elseif flags.isImportant then
		return "importantavailablequesticon", "atlas"
	elseif flags.isMeta then
		return "Wrapperavailablequesticon", "atlas"
	elseif IsQuestRecurringFrequency(frequency) then
		return "Recurringavailablequesticon", "atlas"
	elseif flags.isRepeatable then
		return "Interface/GossipFrame/DailyActiveQuestIcon", "texture"
	end

	return "Interface/GossipFrame/AvailableQuestIcon", "texture"
end

local function ResolveQuestActiveAnnouncementIcon(classification, frequency, isComplete)
	local flags = GetQuestClassificationFlags(classification)
	if isComplete then
		if flags.isCampaign then
			return "CampaignActiveQuestIcon", "atlas"
		elseif flags.isCalling then
			return "CampaignActiveDailyQuestIcon", "atlas"
		elseif IsQuestRecurringFrequency(frequency) then
			return "Recurringactivequesticon", "atlas"
		elseif flags.isLegendary then
			return "legendaryactivequesticon", "atlas"
		elseif flags.isImportant then
			return "importantactivequesticon", "atlas"
		elseif flags.isMeta then
			return "Wrapperactivequesticon", "atlas"
		end

		return "Interface/GossipFrame/ActiveQuestIcon", "texture"
	end

	if flags.isCampaign or flags.isCalling then
		return "CampaignInProgressQuestIcon", "atlas"
	elseif IsQuestRecurringFrequency(frequency) then
		return "RepeatableInProgressquesticon", "atlas"
	elseif flags.isLegendary then
		return "legendaryInProgressquesticon", "atlas"
	elseif flags.isImportant then
		return "importantInProgressquesticon", "atlas"
	elseif flags.isMeta then
		return "WrapperInProgressquesticon", "atlas"
	end

	return "SideInProgressquesticon", "atlas"
end

local function GetQuestAnnouncementLookInfo(addon, questId)
	local numericQuestId = addon and addon.NormalizeQuestID and addon:NormalizeQuestID(questId) or nil
	if not numericQuestId then
		return nil, nil
	end

	local classification = addon.API
			and addon.API.GetQuestClassification
			and addon.API.GetQuestClassification(numericQuestId)
		or nil
	local frequency = addon.API and addon.API.GetQuestFrequency and addon.API.GetQuestFrequency(numericQuestId) or nil
	if classification ~= nil and frequency ~= nil then
		return classification, frequency
	end

	local questLogIndex = addon.API
			and addon.API.GetQuestLogIndexForQuestID
			and addon.API.GetQuestLogIndexForQuestID(numericQuestId)
		or nil
	if not questLogIndex then
		return classification, frequency
	end

	local questInfo = addon.API and addon.API.GetQuestLogInfo and addon.API.GetQuestLogInfo(questLogIndex) or nil
	if type(questInfo) ~= "table" then
		return classification, frequency
	end

	if classification == nil then
		classification = SanitizeQuestInfoEnumValue(questInfo.questClassification)
	end
	if frequency == nil then
		frequency = SanitizeQuestInfoEnumValue(questInfo.frequency)
	end

	return classification, frequency
end

function QuestTogether:GetQuestStateAnnouncementIconInfo(eventType, questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if numericQuestId and self.API then
		local classification, frequency = GetQuestAnnouncementLookInfo(self, numericQuestId)
		local iconAsset = nil
		local iconKind = nil
		if eventType == "QUEST_ACCEPTED" then
			iconAsset, iconKind = ResolveQuestOfferAnnouncementIcon(classification, frequency)
		else
			local useCompleteIcon = eventType == "QUEST_COMPLETED" or eventType == "QUEST_READY_TO_TURN_IN"
			iconAsset, iconKind = ResolveQuestActiveAnnouncementIcon(classification, frequency, useCompleteIcon)
		end
		if type(iconAsset) == "string" and iconAsset ~= "" then
			return iconAsset, iconKind
		end
	end

	local texturePath = self.NAMEPLATE_PLAYER_ICON_TEXTURE
	if type(texturePath) ~= "string" or texturePath == "" then
		return nil, nil
	end

	return texturePath, "texture"
end

function QuestTogether:GetWorldQuestAnnouncementIconInfo(questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return "worldquest-icon", "atlas"
	end

	local questTagType = self.API and self.API.GetQuestPoiTagType and self.API.GetQuestPoiTagType(numericQuestId) or nil
	if questTagType ~= nil and self.API and self.API.GetQuestTagAtlas then
		local atlas = self.API.GetQuestTagAtlas(nil, questTagType)
		if type(atlas) == "string" and atlas ~= "" then
			return atlas, "atlas"
		end
	end

	return "worldquest-icon", "atlas"
end

function QuestTogether:GetBonusObjectiveAnnouncementIconInfo(eventType, questId)
	local numericQuestId = self:NormalizeQuestID(questId)
	if not numericQuestId then
		return "Bonus-Objective-Star", "atlas"
	end

	local questStateEventType = eventType
	if eventType == "BONUS_OBJECTIVE_ENTERED" then
		questStateEventType = "QUEST_ACCEPTED"
	elseif eventType == "BONUS_OBJECTIVE_PROGRESS" or eventType == "BONUS_OBJECTIVE_LEFT" then
		questStateEventType = "QUEST_PROGRESS"
	elseif eventType == "BONUS_OBJECTIVE_COMPLETED" then
		questStateEventType = "QUEST_COMPLETED"
	end

	local asset, kind = self:GetQuestStateAnnouncementIconInfo(questStateEventType, numericQuestId)
	if type(asset) == "string" and asset ~= "" then
		return asset, kind
	end

	return "Bonus-Objective-Star", "atlas"
end

function QuestTogether:GetAnnouncementIconInfo(eventType, questId)
	if eventType == "QT_CHAT" then
		return "Interface\\AddOns\\QuestTogether\\Media\\ChatBubbleIcon", "texture"
	end
	if eventType == "LOOKING_FOR_QUEST_PARTNERS" then
		return "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon", "texture"
	end
	if self:IsWorldQuestAnnouncementType(eventType) then
		return self:GetWorldQuestAnnouncementIconInfo(questId)
	end
	if self:IsBonusObjectiveAnnouncementType(eventType) then
		return self:GetBonusObjectiveAnnouncementIconInfo(eventType, questId)
	end

	return self:GetQuestStateAnnouncementIconInfo(eventType, questId)
end

function QuestTogether:ResolveAnnouncementDisplayIcon(eventType, iconAsset, iconKind)
	if eventType == "LOOKING_FOR_QUEST_PARTNERS" then
		return self.PLAYER_PARTNER_ICON_TEXTURE, "texture"
	end
	if type(iconAsset) == "string" and iconAsset ~= "" then
		-- Earlier clients explicitly sent the generic exclamation mark. Treat
		-- that decoration as a fallback too; retain actual quest-specific icons.
		if iconKind ~= "atlas" and iconAsset:lower():gsub("/", "\\") == self.NAMEPLATE_QUEST_ICON_TEXTURE:lower() then
			return self.NAMEPLATE_PLAYER_ICON_TEXTURE, "texture"
		end
		return iconAsset, iconKind
	end
	return self:GetAnnouncementIconInfo(eventType, nil)
end

function QuestTogether:ResolvePlayerAnnouncementIcon(asset, kind, targetName)
	-- Only QT logos carry identity/status decoration. Quest-specific and chat
	-- icons keep their meaning, and received artwork never proves developer identity.
	if kind == "atlas" or type(asset) ~= "string" then
		return asset, kind
	end
	local path = asset:lower():gsub("/", "\\"):gsub("%.tga$", "")
	local looking = path == self.PLAYER_PARTNER_ICON_TEXTURE:lower()
		or path == self.PLAYER_DEVELOPER_PARTNER_ICON_TEXTURE:lower()
		or path == self.PLAYER_VIP_PARTNER_ICON_TEXTURE:lower()
	if
		not looking
		and path ~= self.NAMEPLATE_PLAYER_ICON_TEXTURE:lower()
		and path ~= self.PLAYER_DEVELOPER_ICON_TEXTURE:lower()
		and path ~= self.PLAYER_VIP_ICON_TEXTURE:lower()
	then
		return asset, kind
	end
	looking = looking or (targetName and self:IsPlayerLookingForQuestPartners(targetName))
	if targetName and self:IsVerifiedDeveloper(targetName) then
		return looking and self.PLAYER_DEVELOPER_PARTNER_ICON_TEXTURE or self.PLAYER_DEVELOPER_ICON_TEXTURE, "texture"
	end
	if targetName and self:IsVerifiedVIP(targetName) then
		return looking and self.PLAYER_VIP_PARTNER_ICON_TEXTURE or self.PLAYER_VIP_ICON_TEXTURE, "texture"
	end
	return looking and self.PLAYER_PARTNER_ICON_TEXTURE or self.NAMEPLATE_PLAYER_ICON_TEXTURE, "texture"
end

function QuestTogether:GetAnnouncementIconChatTag(eventType, size, iconAsset, iconKind, targetName)
	local asset, kind = self:ResolveAnnouncementDisplayIcon(eventType, iconAsset, iconKind)
	asset, kind = self:ResolvePlayerAnnouncementIcon(asset, kind, targetName)
	if type(asset) == "string" and asset ~= "" then
		return self:GetIconChatTagFromAsset(asset, kind, size)
	end
	return self:GetDefaultAnnouncementIconChatTag(size, targetName)
end

function QuestTogether:GetPlayerAnnouncementLocationInfo()
	local mapID = self.API.GetBestMapForUnit and self.API.GetBestMapForUnit("player") or nil
	local zoneName = nil
	if mapID and self.API.GetMapInfo then
		local mapInfo = self.API.GetMapInfo(mapID)
		if type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
			zoneName = mapInfo.name
		end
	end

	local coordX = nil
	local coordY = nil
	if mapID and self.API.GetPlayerMapPosition then
		local position = self.API.GetPlayerMapPosition(mapID, "player")
		if position then
			local rawX = position.x or (position.GetXY and select(1, position:GetXY())) or nil
			local rawY = position.y or (position.GetXY and select(2, position:GetXY())) or nil
			local numericX = self:SafeToNumber(rawX)
			local numericY = self:SafeToNumber(rawY)
			if numericX and numericY then
				coordX = numericX * 100
				coordY = numericY * 100
			end
		end
	end

	local warModeActive
	if self:SupportsWarMode() == true and self.API.IsWarModeActive then
		warModeActive = self:NormalizeAnnouncementWarModeValue(self.API.IsWarModeActive())
	end
	return {
		mapID = mapID,
		zoneName = zoneName or "",
		coordX = coordX,
		coordY = coordY,
		warMode = warModeActive,
	}
end

function QuestTogether:NormalizeNearbyAnnouncementRange(value)
	local number = self:SafeToNumber(value)
	if not number or number < self.NEARBY_RANGE_MIN or number > self.NEARBY_RANGE_MAX then
		return nil
	end
	return math.floor(number + 0.5)
end

function QuestTogether:GetNearbyAnnouncementRange()
	return self:NormalizeNearbyAnnouncementRange(self:GetOption("nearbyAnnouncementRange"))
		or self.DEFAULTS.profile.nearbyAnnouncementRange
end

function QuestTogether:IsAnnouncementSenderNearbyByLocation(locationInfo, entireZone)
	if type(locationInfo) ~= "table" then
		return false
	end

	local localInfo = self.GetPlayerAnnouncementLocationInfo and self:GetPlayerAnnouncementLocationInfo() or nil
	if type(localInfo) ~= "table" then
		return false
	end

	local function ReadMapID(value)
		local mapID = self:SafeToNumber(value)
		if mapID and mapID > 0 and mapID == math.floor(mapID) then
			return mapID
		end
		return nil
	end
	local localMapID = ReadMapID(localInfo.mapID)
	local remoteMapID = ReadMapID(locationInfo.mapID)
	if localMapID and remoteMapID then
		if localMapID ~= remoteMapID then
			return false
		end
	else
		-- Legacy announcements have no map ID; retain their zone-label fallback.
		local localZoneName = type(localInfo.zoneName) == "string" and localInfo.zoneName or ""
		local remoteZoneName = type(locationInfo.zoneName) == "string" and locationInfo.zoneName or ""
		if localZoneName == "" or remoteZoneName == "" or localZoneName ~= remoteZoneName then
			return false
		end
	end

	local supportsWarMode = self:SupportsWarMode()
	if supportsWarMode == nil then
		-- Unknown capability must not establish shared Retail surroundings.
		return false
	elseif supportsWarMode then
		local localWarMode = self:NormalizeAnnouncementWarModeValue(localInfo.warMode)
		local remoteWarMode = self:NormalizeAnnouncementWarModeValue(locationInfo.warMode)
		if localWarMode == nil or remoteWarMode == nil or localWarMode ~= remoteWarMode then
			return false
		end
	end

	-- Partner searches need only a matching zone; ordinary updates retain the
	-- configured radius and coordinate validation below.
	if entireZone then
		return true
	end
	local localCoordX = self:SafeToNumber(localInfo.coordX)
	local localCoordY = self:SafeToNumber(localInfo.coordY)
	local remoteCoordX = self:SafeToNumber(locationInfo.coordX)
	local remoteCoordY = self:SafeToNumber(locationInfo.coordY)
	if not localCoordX or not localCoordY or not remoteCoordX or not remoteCoordY then
		return false
	end

	for _, value in ipairs({ localCoordX, localCoordY, remoteCoordX, remoteCoordY }) do
		if value < 0 or value > 100 then
			return false
		end
	end
	local deltaX, deltaY = localCoordX - remoteCoordX, localCoordY - remoteCoordY
	local oldRange = self.ANNOUNCEMENT_NEARBY_RADIUS
	local inOldRange = deltaX * deltaX + deltaY * deltaY <= oldRange * oldRange
	local range = self:GetNearbyAnnouncementRange()
	-- The slider's minimum exactly preserves the former coordinate check.
	if range == self.NEARBY_RANGE_MIN then
		return inOldRange
	end
	-- Convert both axes to yards so rectangular maps use a circular physical
	-- radius. Percentages describe distance across the full map diagonal, not area.
	local ok, width, height = pcall(self.GetLocationPinMapWorldSize, self, localMapID or remoteMapID)
	width, height = self:SafeToNumber(width), self:SafeToNumber(height)
	if not ok or not width or not height or width <= 0 or height <= 0 then
		return inOldRange
	end
	if width > 1000000 or height > 1000000 then
		return inOldRange
	end
	local radiusSquared = (width * width + height * height) * (range / 100) ^ 2
	deltaX, deltaY = deltaX * width / 100, deltaY * height / 100
	return deltaX * deltaX + deltaY * deltaY <= radiusSquared
end

function QuestTogether:BuildAnnouncementLocationSuffix(locationInfo)
	if type(locationInfo) ~= "table" then
		return ""
	end

	local parts = {}
	local zoneName = type(locationInfo.zoneName) == "string" and locationInfo.zoneName or ""
	if zoneName ~= "" then
		parts[#parts + 1] = zoneName
	end

	local coordX = self:SafeToNumber(locationInfo.coordX)
	local coordY = self:SafeToNumber(locationInfo.coordY)
	if coordX and coordY then
		parts[#parts + 1] = string.format("%.1f, %.1f", coordX, coordY)
	end

	local warMode = self:NormalizeAnnouncementWarModeValue(locationInfo.warMode)
	if self:SupportsWarMode() == true and warMode ~= nil then
		parts[#parts + 1] = warMode and L("WM On") or L("WM Off")
	end

	if #parts == 0 then
		return ""
	end

	return " |cff999999[" .. table.concat(parts, " | ") .. "]|r"
end

function QuestTogether:BuildChatLogSpeakerLabel(targetName, classFile)
	local trimmedTargetName = self:GetShortDisplayName(targetName)
	local speakerLabel = trimmedTargetName ~= "" and trimmedTargetName or "QT"
	local speakerColor = self:GetClassColorCode(classFile)

	if LinkUtil and LinkUtil.FormatLink then
		local linkDisplayText = "[" .. speakerLabel .. "]"
		local linkText =
			LinkUtil.FormatLink(self.chatLogLinkType or "questtogetherlog", linkDisplayText, tostring(targetName or ""))
		return speakerColor .. linkText .. "|r"
	end

	return speakerColor .. speakerLabel .. "|r"
end

function QuestTogether:BuildChatLogQuestLabel(questId, questTitle)
	local numericQuestId = self:SafeToNumber(questId)
	local titleText = tostring(questTitle or "")
	if not numericQuestId or titleText == "" or not LinkUtil or not LinkUtil.FormatLink then
		return titleText
	end

	local linkDisplayText = "[" .. titleText .. "]"
	return LinkUtil.FormatLink(
		self.chatLogQuestLinkType or "questtogetherquest",
		linkDisplayText,
		tostring(numericQuestId)
	)
end

function QuestTogether:DecorateAnnouncementMessageWithQuestLink(message, eventType, questId)
	if not self.questTitleLinkEventTypes or not self.questTitleLinkEventTypes[eventType] then
		return self:SafeToString(message, "")
	end

	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return self:SafeToString(message, "")
	end

	local messageText = self:SafeToString(message, "")
	if string.find(messageText, "|H" .. (self.chatLogQuestLinkType or "questtogetherquest") .. ":", 1, true) then
		return messageText
	end
	local prefixText, questTitle
	local translatedPrefix = self.GetLocalizedEventPrefix and self:GetLocalizedEventPrefix(eventType)
	if translatedPrefix and messageText:sub(1, #translatedPrefix) == translatedPrefix then
		prefixText, questTitle = translatedPrefix, messageText:sub(#translatedPrefix + 1)
	else
		prefixText, questTitle = SafeMatch(messageText, "^(.-:%s+)(.+)$")
	end
	if not prefixText or not questTitle or questTitle == "" then
		return messageText
	end

	return prefixText .. self:BuildChatLogQuestLabel(numericQuestId, questTitle)
end

function QuestTogether:GetQuestStatusLabel(questId)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return "Unknown"
	end

	local statusState = self.GetTrackedQuestStatusState and self:GetTrackedQuestStatusState(numericQuestId, true) or nil
	if type(statusState) == "table" then
		if statusState.isFlaggedCompleted == true then
			return "Completed"
		end
		if statusState.isReadyForTurnIn == true then
			return "Ready to Turn In"
		end
		if statusState.isComplete == true then
			return "Objectives Complete"
		end
		if statusState.isTracked == true or statusState.isOnQuest == true then
			return "In Progress"
		end
	end

	return "Not Started"
end

function QuestTogether:GetTrackedQuestStatusState(questId, allowLiveFallback)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return nil
	end

	local tracker = self.GetPlayerTracker and self:GetPlayerTracker() or nil
	local trackedQuest = tracker and tracker[numericQuestId] or nil
	local state = {
		isTracked = trackedQuest ~= nil,
		isComplete = trackedQuest and trackedQuest.isComplete == true or false,
		-- Unknown readiness must not establish an unfinished baseline.
		isReadyForTurnIn = trackedQuest and trackedQuest.isReadyForTurnIn,
		isFlaggedCompleted = false,
		isOnQuest = false,
	}

	if type(trackedQuest) == "table" then
		state.isOnQuest = true
	end

	if self.EnsureQuestSnapshotStore then
		self:EnsureQuestSnapshotStore()
	end
	local snapshot = self.GetQuestSnapshot and self:GetQuestSnapshot(numericQuestId) or nil
	if type(snapshot) == "table" then
		state.isTracked = true
		state.isOnQuest = true
		if state.isComplete ~= true then
			state.isComplete = snapshot.isComplete == true
		end
	end

	if allowLiveFallback ~= true then
		return state
	end

	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
		return state
	end

	for field, method in pairs({
		isFlaggedCompleted = "IsQuestFlaggedCompleted",
		isReadyForTurnIn = "IsQuestReadyForTurnIn",
		isComplete = "IsQuestComplete",
		isOnQuest = "IsOnQuest",
	}) do
		if self.API and type(self.API[method]) == "function" then
			local value = self.API[method](numericQuestId)
			if self:CanAccessValue(value) and type(value) == "boolean" then
				state[field] = value
			end
		end
	end
	if not state.isOnQuest then
		local questLogIndex = self.API
			and self.API.GetQuestLogIndexForQuestID
			and self.API.GetQuestLogIndexForQuestID(numericQuestId)
		local isOnQuest = self.API and self.API.IsOnQuest and self.API.IsOnQuest(numericQuestId)
		state.isOnQuest = (questLogIndex ~= nil) or (isOnQuest and true or false)
	end

	return state
end

function QuestTogether:GetQuestShareableStatusLabel(questId)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return "Unknown"
	end

	local statusState = self:GetTrackedQuestStatusState(numericQuestId, true)
	if type(statusState) ~= "table" or statusState.isOnQuest ~= true then
		return "Unknown"
	end

	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
		return "Unknown"
	end

	local pushable = self.API and self.API.IsPushableQuest and self.API.IsPushableQuest(numericQuestId)
	if not self:CanAccessValue(pushable) or type(pushable) ~= "boolean" then
		return "Unknown"
	end
	return pushable and "Yes" or "No"
end

-- UI text only: never rewrite received snapshots or their revision inputs.
-- Keep quest names bounded and single-line; escaped output is idempotent.
function QuestTogether:NormalizeQuestDisplayTitleText(value)
	if not self:CanAccessValue(value) or type(value) ~= "string" or #value > 1024 then
		return ""
	end
	local text = value:gsub("||", "|")
	local previous
	repeat
		previous = text
		text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		text = text:gsub("|K.-|k", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	-- Removing malformed nested markup may expose another tag. Every
	-- changed pass shortens the bounded input; normalize to a fixed point.
	until text == previous
	text = self:SafeTrimString(text:gsub("[%c]", " "), "")
	if #text > 512 then
		return ""
	end
	return text:gsub("|", "||")
end

function QuestTogether:NormalizeQuestLinkTitleText(titleText, questId)
	local normalizedText = self:SafeTrimString(titleText, "")
	if string.find(normalizedText, "|H", 1, true) then
		-- Chat hyperlink callbacks may supply the complete formatted message,
		-- including speaker, quest and coordinate links. Only the clicked quest's
		-- display text is a title; never wrap the whole message in another link.
		local numericQuestId = self:SafeToNumber(questId)
		local questLinkType = self.chatLogQuestLinkType or "questtogetherquest"
		local matchedTitle
		for linkType, options, displayStart in string.gmatch(normalizedText, "|H([^:|]+):([^|]*)|h()") do
			if linkType == questLinkType and numericQuestId and self:SafeToNumber(options) == numericQuestId then
				local displayEnd = string.find(normalizedText, "|h", displayStart, true)
				local display = displayEnd and string.sub(normalizedText, displayStart, displayEnd - 1)
				-- Skip malformed outer wrappers from older status messages, but
				-- keep scanning their inner links to recover the actual quest title.
				if display and not string.find(display, "|H", 1, true) then
					matchedTitle = display
					break
				end
			end
		end
		if not matchedTitle then
			return ""
		end
		normalizedText = matchedTitle
	end
	normalizedText = normalizedText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	normalizedText = self:SafeTrimString(normalizedText, "")
	if SafeMatch(normalizedText, "^%[.+%]$") then
		normalizedText = string.sub(normalizedText, 2, -2)
	end
	return normalizedText
end

function QuestTogether:BuildQuestStatusMessage(questId, fallbackTitle)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId then
		return L("Quest status unavailable.")
	end

	local questTitle = self:GetQuestDisplayTitle(numericQuestId, fallbackTitle)
	local statusLabel = self:GetQuestStatusLabel(numericQuestId)
	local shareableLabel = self:GetQuestShareableStatusLabel(numericQuestId)
	local questLabel = self:BuildChatLogQuestLabel(numericQuestId, questTitle)
	return L("Quest Status: ")
		.. questLabel
		.. " - "
		.. tostring(L(statusLabel))
		.. L(" | Shareable: ")
		.. tostring(L(shareableLabel))
end

function QuestTogether:GetQuestStatusAnnouncementEventType(questId)
	local statusLabel = self:GetQuestStatusLabel(questId)
	if statusLabel == "Completed" or statusLabel == "Objectives Complete" then
		return "QUEST_COMPLETED"
	end
	if statusLabel == "Ready to Turn In" then
		return "QUEST_READY_TO_TURN_IN"
	end
	if statusLabel == "In Progress" then
		return "QUEST_PROGRESS"
	end
	if statusLabel == "Not Started" then
		return "QUEST_ACCEPTED"
	end

	return "QUEST_PROGRESS"
end

function QuestTogether:GetTrackedQuestAnnouncementIcon(questData)
	if type(questData) ~= "table" then
		return nil, nil
	end

	local iconAsset = tostring(questData.iconAsset or "")
	if iconAsset == "" then
		return nil, nil
	end

	local iconKind = tostring(questData.iconKind or "")
	if iconKind == "" then
		return iconAsset, nil
	end

	return iconAsset, iconKind
end

function QuestTogether:RefreshTrackedQuestAnnouncementIcon(questId, questData, eventType)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or type(questData) ~= "table" then
		return nil, nil
	end

	local resolvedEventType = eventType or self:GetQuestStatusAnnouncementEventType(numericQuestId)
	local iconAsset, iconKind = self:GetAnnouncementIconInfo(resolvedEventType, numericQuestId)
	questData.iconAsset = iconAsset or nil
	questData.iconKind = iconKind or nil
	return iconAsset, iconKind
end

function QuestTogether:PrintQuestStatus(questId, fallbackTitle)
	local message = self:BuildQuestStatusMessage(questId, fallbackTitle)
	local eventType = self:GetQuestStatusAnnouncementEventType(questId)
	self:PrintConsoleAnnouncement(message, nil, nil, eventType)
end

function QuestTogether:GetQuestCompareRemoteStatusLabel(isComplete)
	if isComplete then
		return "Complete"
	end

	return "In Progress"
end

function QuestTogether:GetQuestCompareShareableToYouLabel(isPushable)
	if type(isPushable) == "boolean" then
		return isPushable and "Yes" or "No"
	end

	if type(isPushable) == "string" then
		local normalized = string.lower(isPushable)
		if isPushable == "1" or normalized == "true" then
			return "Yes"
		end
		if isPushable == "0" or normalized == "false" then
			return "No"
		end
	end

	return "Unknown"
end

function QuestTogether:BuildQuestCompareMessage(_remoteName, compareEntry)
	if type(compareEntry) ~= "table" then
		return L("Quest comparison unavailable.")
	end

	local questId = self:SafeToNumber(compareEntry.questId)
	local questTitle = self:GetQuestDisplayTitle(questId, compareEntry.questTitle)
	local localStatus = self:GetQuestStatusLabel(questId)
	local shareableLabel = self:GetQuestCompareShareableToYouLabel(compareEntry.isPushable)
	local remoteStatus = self:GetQuestCompareRemoteStatusLabel(compareEntry.isComplete)
	local decoratedQuestTitle = self:BuildChatLogQuestLabel(questId, questTitle)

	return tostring(decoratedQuestTitle)
		.. L(" | Them: ")
		.. tostring(L(remoteStatus))
		.. L(" | You: ")
		.. tostring(L(localStatus))
		.. L(" | Shareable to You: ")
		.. tostring(L(shareableLabel))
end

function QuestTogether:PrintQuestCompareMessage(remoteName, compareEntry, classFile)
	local eventType = compareEntry and compareEntry.isComplete and "QUEST_COMPLETED" or "QUEST_PROGRESS"
	local locationInfo = {
		questId = compareEntry and compareEntry.questId or nil,
	}
	self:PrintConsoleAnnouncement(
		self:BuildQuestCompareMessage(remoteName, compareEntry),
		remoteName,
		classFile,
		eventType,
		nil,
		nil,
		locationInfo
	)
end

function QuestTogether:PrintQuestCompareStart(remoteName, classFile)
	self:PrintConsoleAnnouncement(L("Comparing quests..."), remoteName, classFile, "QUEST_PROGRESS")
end

function QuestTogether:PrintQuestCompareDone(remoteName, count, classFile)
	local suffix = ""
	local numericCount = self:SafeToNumber(count)
	if numericCount then
		suffix = string.format(L(" (%d quests)"), numericCount)
	end
	self:PrintConsoleAnnouncement(
		L("Finished comparing quests") .. suffix .. ".",
		remoteName,
		classFile,
		"QUEST_COMPLETED"
	)
end

function QuestTogether:BuildConsoleAnnouncementMessage(
	targetName,
	message,
	classFile,
	eventType,
	iconAsset,
	iconKind,
	locationInfo
)
	local iconTag = self:GetAnnouncementIconChatTag(eventType, 14, iconAsset, iconKind, targetName)
	local questId = type(locationInfo) == "table" and locationInfo.questId or nil
	local trimmedMessage = self:DecorateAnnouncementMessageWithQuestLink(tostring(message or ""), eventType, questId)
	local body = trimmedMessage
	local speakerText = self:BuildChatLogSpeakerLabel(targetName, classFile)
	local textColor = eventType == "QT_CHAT" and "|cffffffff" or "|cffffd200"

	if iconTag ~= "" then
		return iconTag .. speakerText .. textColor .. ": " .. body .. "|r"
	end

	return speakerText .. textColor .. ": " .. body .. "|r"
end

function QuestTogether:BuildPingResponseMessage(pongData)
	if type(pongData) ~= "table" then
		return L("|cff33ff99QuestTogether|r: Pong: <invalid payload>")
	end

	local senderName = pongData.senderName or L("Unknown")
	local speakerLabel = self:GetShortDisplayName(senderName)
	local speakerColor = self:GetClassColorCode(pongData.classFile)
	local coloredName = speakerColor .. tostring(speakerLabel or L("Unknown")) .. "|r"
	local realmName = tostring(pongData.realmName or "")
	local identityOK, raceName, className = pcall(
		self.GetPlayerTooltipIdentity,
		self,
		{ name = senderName, race = pongData.raceName, className = pongData.className, classFile = pongData.classFile }
	)
	if not identityOK then
		raceName, className = pongData.raceName, pongData.className
	end
	raceName, className = tostring(raceName or ""), tostring(className or pongData.classFile or "")
	local level = self:SafeToNumber(pongData.level)

	local parts = {}
	parts[#parts + 1] = coloredName
	if not self:UsesRegionalPlayerNames() and realmName ~= "" then
		parts[#parts + 1] = "(" .. realmName .. ")"
	end
	if level then
		parts[#parts + 1] = L("Lvl ") .. tostring(math.floor(level))
	end
	if raceName ~= "" then
		parts[#parts + 1] = raceName
	end
	if className ~= "" then
		parts[#parts + 1] = className
	end
	local addonVersion = tostring(pongData.addonVersion or "")
	if addonVersion ~= "" then
		parts[#parts + 1] = L("QT v") .. addonVersion
	end

	local locationBits = {}
	local zoneName = tostring(pongData.zoneName or "")
	local mapID = self:SafeToNumber(pongData.mapID)
	if
		not self:IsRuntimeRestricted()
		and mapID
		and mapID > 0
		and mapID == math.floor(mapID)
		and self.API.GetMapInfo
	then
		local ok, info = pcall(self.API.GetMapInfo, mapID)
		if ok and self:CanAccessTable(info) then
			local localized = self:SafeTrimString(info.name, "")
			if localized ~= "" then
				zoneName = localized
			end
		end
	end
	if zoneName ~= "" then
		locationBits[#locationBits + 1] = zoneName
	end
	local coordX = self:SafeToNumber(pongData.coordX)
	local coordY = self:SafeToNumber(pongData.coordY)
	if coordX and coordY then
		locationBits[#locationBits + 1] = self:BuildPingCoordinateLabel(pongData.mapID, coordX, coordY)
	end
	local warMode = self:NormalizeAnnouncementWarModeValue(pongData.warMode)
	if self:SupportsWarMode() == true and warMode ~= nil then
		locationBits[#locationBits + 1] = warMode and L("WM On") or L("WM Off")
	end
	if #locationBits > 0 then
		parts[#parts + 1] = "- " .. table.concat(locationBits, " | ")
	end
	if pongData.developer then
		parts[#parts + 1] = "- " .. L("Share my location") .. ": " .. (pongData.locationShared and L("On") or L("Off"))
	end

	return L("|cff33ff99QuestTogether|r: Pong: ") .. table.concat(parts, " ")
end

function QuestTogether:BuildPingCoordinateLabel(mapID, coordX, coordY)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericX or not numericY then
		return ""
	end

	local bracketedText = string.format("[%.1f, %.1f]", numericX, numericY)
	local numericMapID = self:SafeToNumber(mapID)
	if not numericMapID or not LinkUtil or not LinkUtil.FormatLink then
		return bracketedText
	end

	local linkData = string.format("%d:%.1f:%.1f", numericMapID, numericX, numericY)
	return LinkUtil.FormatLink(self.chatLogCoordLinkType or "questtogethercoord", bracketedText, linkData)
end

function QuestTogether:PrintPingResponse(pongData)
	self:PrintChatLogRaw(self:BuildPingResponseMessage(pongData))
end
