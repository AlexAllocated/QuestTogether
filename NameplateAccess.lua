-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
QuestTogether.NameplateServices = {}
local Services = QuestTogether.NameplateServices
local SafeText
local SafeUiNumber
local ResolveNameplateUnitToken
local QUEST_STATE_SETTLE_SECONDS = 1.0

-- Original icon used by this addon's first nameplate implementation.
QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE = "Interface\\OPTIONSFRAME\\UI-OptionsFrame-NewFeatureIcon"
QuestTogether.NAMEPLATE_PLAYER_ICON_TEXTURE = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon"
QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS = nil
QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS = nil
QuestTogether.NAMEPLATE_QUEST_ICON_WIDTH = 21
QuestTogether.NAMEPLATE_QUEST_ICON_HEIGHT = 21

-- Default burnt-orange tint for quest-objective units.
QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR = {
	r = 0.95,
	g = 0.45,
	b = 0.05,
}
QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS = "UI-HUD-CoolDownManager-Bar"
local function ClampColorComponent(value, fallback)
	local numberValue = SafeUiNumber and SafeUiNumber(value, nil) or nil
	if not numberValue then
		return fallback
	end
	if numberValue < 0 then
		return 0
	end
	if numberValue > 1 then
		return 1
	end
	return numberValue
end

local function IsNonEmptyString(value)
	return QuestTogether:CanAccessValue(value) and type(value) == "string" and value ~= ""
end

local function PrintOneShotNameplateDebug(addon, key, message)
	if not addon or not addon.GetRuntimeFlag or not addon.SetRuntimeFlag then
		return
	end
	if addon:GetRuntimeFlag(key, false) then
		return
	end
	addon:SetRuntimeFlag(key, true)
	if addon.LogDebugLine then
		addon:LogDebugLine(SafeText(message, ""), {
			category = "nameplate",
		})
	elseif addon.AppendDebugLogLine then
		addon:AppendDebugLogLine(SafeText(message, ""))
	end
end

local function ShouldSuppressStructuredQuestTooltipSource(addon)
	if not addon or not addon.CanUseStructuredQuestTooltipAPI then
		return false
	end

	-- The retail structured tooltip path is only risky while Blizzard's shared
	-- world-map tooltip/widget flow is active.
	if not addon:CanUseStructuredQuestTooltipAPI() then
		return false
	end

	if addon.API and type(addon.API.IsWorldMapVisible) == "function" then
		return addon.API.IsWorldMapVisible() == true
	end

	return false
end

local function IsFrameForbidden(frame)
	return QuestTogether:IsForbiddenFrame(frame)
end
local function CanMutateFrame(frame)
	return QuestTogether:CanAccessForeignFrame(frame)
		and not (QuestTogether:IsProtectedFrame(frame) and QuestTogether:IsRuntimeRestricted())
end

local function GetAccessibleChildFrame(frame, memberName)
	local child = select(1, QuestTogether:GetAccessibleFrameMember(frame, memberName))
	if QuestTogether:CanAccessForeignFrame(child) then
		return child
	end
	return nil
end

local function CallAccessibleFrameMethod(frame, methodName)
	local method = select(1, QuestTogether:GetAccessibleFrameMember(frame, methodName))
	if type(method) ~= "function" then
		return nil
	end
	local ok, value = pcall(method, frame)
	if ok and QuestTogether:CanAccessValue(value) then
		return value
	end
	return nil
end

SafeText = function(value, fallback)
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

local function SafeTrimText(text)
	return QuestTogether:SafeTrimString(text, "")
end

local function SafeFindPlain(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, index = pcall(string.find, safeText, pattern, 1, true)
	if not ok then
		return nil
	end

	return index
end

SafeUiNumber = function(value, fallback)
	local numericValue = nil
	if QuestTogether and QuestTogether.SafeToNumber then
		numericValue = QuestTogether:SafeToNumber(value)
	end
	if numericValue == nil then
		return fallback
	end
	return numericValue
end

-- Returns true only for the dynamic nameplate unit tokens (nameplate1, nameplate2, ...).
function QuestTogether:IsNameplateUnitToken(unitToken)
	if not self:CanAccessValue(unitToken) or type(unitToken) ~= "string" then
		return false
	end

	local ok, isMatch = pcall(string.find, unitToken, "^nameplate%d+$")
	return ok and isMatch ~= nil
end

function QuestTogether:DoesNameplateUnitExist(unitToken)
	if self.API and self.API.UnitExists then
		return self.API.UnitExists(unitToken)
	end
	local ok, exists = pcall(UnitExists, unitToken)
	return ok and exists and true or false
end

function QuestTogether:GetNameplateUnitGuid(unitToken)
	if self.API and self.API.UnitGUID then
		local unitGuid = self.API.UnitGUID(unitToken)
		if not IsNonEmptyString(unitGuid) then
			return nil
		end
		return unitGuid
	end

	-- Nameplate unit tokens can disappear between frames; guard transient UnitGUID errors.
	local ok, unitGuid = pcall(UnitGUID, unitToken)
	if self:IsSecretValue(unitGuid) then
		return nil
	end
	if not ok or not IsNonEmptyString(unitGuid) then
		return nil
	end
	return unitGuid
end

function QuestTogether:GetAccessibleNameplateFrameForUnit(unitToken, requireShown)
	if not self:IsNameplateUnitToken(unitToken) then
		return nil, nil
	end
	if not (self.API and type(self.API.GetNamePlateForUnit) == "function") then
		return nil, nil
	end

	local namePlateFrameBase = self.API.GetNamePlateForUnit(unitToken)
	if not self:CanAccessForeignFrame(namePlateFrameBase) then
		return nil, nil
	end
	local unitFrame, memberReadable = self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame")
	if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
		return nil, nil
	end
	if requireShown and not self:CanAccessForeignFrame(namePlateFrameBase, true) then
		return nil, nil
	end

	return namePlateFrameBase, unitFrame
end

-- Quest objective detection is explicitly open-world-only. The tooltip-driven
-- quest cache follows the same instance policy as Plater's update_quest_cache
-- in local retail Plater.lua:11373-11376.
function QuestTogether:IsNameplateAugmentationBlockedInCurrentContext()
	local isInInstance = self.API and self.API.IsInInstance and self.API.IsInInstance()
	return isInInstance and true or false
end

function QuestTogether:GetNameplateContextInfo()
	local isInInstance = self.API and self.API.IsInInstance and self.API.IsInInstance() and true or false
	local instanceType = ""
	local instanceInfo = self.API and self.API.GetInstanceInfo and self.API.GetInstanceInfo() or nil
	if type(instanceInfo) == "table" then
		instanceType = string.lower(SafeText(instanceInfo.instanceType, ""))
	end
	if instanceType == "none" then
		instanceType = ""
	end

	return {
		isInInstance = isInInstance,
		instanceType = instanceType,
	}
end

-- Personal bubbles are fully addon-owned. Nearby-player bubbles attach to
-- foreign nameplates, so keep them out of every restricted runtime state.
function QuestTogether:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(unitToken)
	if unitToken == "player" then
		return false
	end
	return self.IsWorkBlocked and self:IsWorkBlocked("foreign_frame_mutation") or false
end

function QuestTogether:IsNearbyPlayerAnnouncementBubbleAugmentationBlockedInCurrentContext()
	local contextInfo = self.GetNameplateContextInfo and self:GetNameplateContextInfo() or nil
	if type(contextInfo) ~= "table" or contextInfo.isInInstance ~= true then
		return false
	end

	local instanceType = SafeText(contextInfo.instanceType, "")
	return instanceType == "party" or instanceType == "raid" or instanceType == "arena" or instanceType == "pvp"
end

local function BuildCapabilityStatusLabel(isAvailable)
	if isAvailable then
		return "|cff33ff99" .. L("available") .. "|r", "available"
	end

	return "|cffff4444" .. L("unavailable") .. "|r", "unavailable"
end

local function BuildCapabilityStatusLine(label, isAvailable)
	local renderedStatus, plainStatus = BuildCapabilityStatusLabel(isAvailable)
	local renderedLabel = "|cffffd200" .. SafeText(label, "") .. ": |r"
	local plainLabel = SafeText(label, "")
	return renderedLabel .. renderedStatus, plainLabel .. ": " .. plainStatus
end

function QuestTogether:GetNameplateCapabilityNoticeReport()
	if not self.isEnabled then
		return nil
	end

	local wantsQuestPlates = self.GetOption and self:GetOption("nameplateQuestIconEnabled") == true or false
	local wantsChatBubbles = self.GetOption and self:GetOption("showChatBubbles") == true or false
	local wantsNearbyPlayerBubbles = wantsChatBubbles
	local wantsPersonalBubble = self:ShouldShowOwnChatBubble()

	local questPlatesBlocked = wantsQuestPlates and self:IsNameplateAugmentationBlockedInCurrentContext() or false
	local nearbyPlayerBubblesBlocked = wantsNearbyPlayerBubbles
			and self:IsNearbyPlayerAnnouncementBubbleAugmentationBlockedInCurrentContext()
		or false
	local personalBubbleBlocked = wantsPersonalBubble
			and self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext("player")
		or false

	local lines = {}
	local keyParts = {}
	local hasLimitedFunctionality = false

	if wantsQuestPlates then
		local isAvailable = not questPlatesBlocked
		local renderedLine, plainLine = BuildCapabilityStatusLine(L("Quest Plates"), isAvailable)
		if not isAvailable then
			hasLimitedFunctionality = true
		end
		lines[#lines + 1] = renderedLine
		keyParts[#keyParts + 1] = plainLine
	end

	if wantsPersonalBubble then
		local isAvailable = not personalBubbleBlocked
		local renderedLine, plainLine = BuildCapabilityStatusLine(L("Personal Announcement Bubbles"), isAvailable)
		if not isAvailable then
			hasLimitedFunctionality = true
		end
		lines[#lines + 1] = renderedLine
		keyParts[#keyParts + 1] = plainLine
	end

	if wantsNearbyPlayerBubbles then
		local isAvailable = not nearbyPlayerBubblesBlocked
		local renderedLine, plainLine = BuildCapabilityStatusLine(L("Nearby-Player Announcement Bubbles"), isAvailable)
		if not isAvailable then
			hasLimitedFunctionality = true
		end
		lines[#lines + 1] = renderedLine
		keyParts[#keyParts + 1] = plainLine
	end

	if not hasLimitedFunctionality or #lines == 0 then
		if #lines == 0 then
			return nil
		end
	end

	local mode = hasLimitedFunctionality and "limited" or "full"
	local header = hasLimitedFunctionality and L("QuestTogether detects limited functionality in the current instance.")
		or L("Full QuestTogether functionality is available again.")
	local capabilityKey = header .. "\n" .. table.concat(keyParts, "\n")
	return {
		mode = mode,
		header = header,
		lines = lines,
		key = capabilityKey,
	}
end

function QuestTogether:MaybeAnnounceNameplateCapabilityContextChange()
	local noticeKey = "nameplateCapabilityNoticeKey"
	local noticeModeKey = "nameplateCapabilityNoticeMode"
	if not self.isEnabled then
		self:SetRuntimeFlag(noticeKey, nil)
		self:SetRuntimeFlag(noticeModeKey, nil)
		return false
	end

	local report = self:GetNameplateCapabilityNoticeReport()
	if type(report) ~= "table" or type(report.key) ~= "string" or report.key == "" then
		self:SetRuntimeFlag(noticeKey, nil)
		self:SetRuntimeFlag(noticeModeKey, nil)
		return false
	end

	local previousKey = self:GetRuntimeFlag(noticeKey, nil)
	local previousMode = self:GetRuntimeFlag(noticeModeKey, nil)
	if previousKey == report.key and previousMode == report.mode then
		return false
	end

	self:SetRuntimeFlag(noticeKey, report.key)
	self:SetRuntimeFlag(noticeModeKey, report.mode)

	local shouldAnnounce = report.mode == "limited" or previousMode == "limited"
	if not shouldAnnounce then
		return false
	end

	if report.mode == "limited" then
		if self.PrintChatLogWarningMessage then
			self:PrintChatLogWarningMessage(report.header)
			if type(report.lines) == "table" then
				for index = 1, #report.lines do
					local line = report.lines[index]
					if type(line) == "string" and line ~= "" then
						if self.PrintChatLogWarningDetailMessage then
							self:PrintChatLogWarningDetailMessage(line)
						else
							self:PrintChatLogWarningMessage(line)
						end
					end
				end
			end
		elseif self.PrintChatLogSystemMessage then
			self:PrintChatLogSystemMessage(report.header)
		else
			self:PrintRaw("QuestTogether: " .. report.header)
		end
		return true
	end

	if self.PrintChatLogInfoMessage then
		self:PrintChatLogInfoMessage(report.header)
		if type(report.lines) == "table" then
			for index = 1, #report.lines do
				local line = report.lines[index]
				if type(line) == "string" and line ~= "" then
					if self.PrintChatLogInfoDetailMessage then
						self:PrintChatLogInfoDetailMessage(line)
					else
						self:PrintChatLogInfoMessage(line)
					end
				end
			end
		end
	elseif self.PrintChatLogSystemMessage then
		self:PrintChatLogSystemMessage(report.header)
	else
		self:PrintRaw("QuestTogether: " .. report.header)
	end
	return true
end

function QuestTogether:IsNameplateUnitPlayer(unitToken)
	if self.API and self.API.UnitIsPlayer then
		return self.API.UnitIsPlayer(unitToken)
	end
	local ok, isPlayer = pcall(UnitIsPlayer, unitToken)
	return ok and self:CanAccessValue(isPlayer) and isPlayer == true
end

function QuestTogether:IsNameplateUnitConnected(unitToken)
	local ok, isConnected = pcall(UnitIsConnected, unitToken)
	return ok and self:CanAccessValue(isConnected) and isConnected == true
end

function QuestTogether:IsNameplateUnitDead(unitToken)
	local ok, isDead = pcall(UnitIsDead, unitToken)
	return ok and self:CanAccessValue(isDead) and isDead == true
end

function QuestTogether:IsNameplateUnitTapDenied(unitToken)
	local ok, isTapDenied = pcall(UnitIsTapDenied, unitToken)
	return not ok or not self:CanAccessValue(isTapDenied) or isTapDenied == true
end

function QuestTogether:GetNameplateQuestHealthColor()
	local fallback = self.NAMEPLATE_QUEST_HEALTH_COLOR
	local configured = self:GetOption("nameplateQuestHealthColor")
	if type(configured) ~= "table" then
		return { r = fallback.r, g = fallback.g, b = fallback.b }
	end

	return {
		r = ClampColorComponent(configured.r, fallback.r),
		g = ClampColorComponent(configured.g, fallback.g),
		b = ClampColorComponent(configured.b, fallback.b),
	}
end

function QuestTogether:CreateNameplateHealthOverlayTexture(parentFrame, drawLayer, subLevel)
	if not CanMutateFrame(parentFrame) then
		return nil
	end
	local createTexture = select(1, self:GetAccessibleFrameMember(parentFrame, "CreateTexture"))
	if type(createTexture) ~= "function" then
		return nil
	end

	local ok, texture = pcall(createTexture, parentFrame, nil, drawLayer or "ARTWORK", nil, subLevel or 0)
	if not ok or not CanMutateFrame(texture) then
		return nil
	end

	if texture.SetAtlas then
		texture:SetAtlas(self.NAMEPLATE_HEALTH_FILL_ATLAS, true)
	else
		texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	end

	return texture
end

-- Mirrors the unfinished-objective checks in Plater.IsQuestObjective
-- (local retail Plater.lua:11256-11315): only x/y and percent progress count.
ResolveNameplateUnitToken = function(namePlateFrameBase, unitFrame)
	local plateFrameToken = namePlateFrameBase
			and select(1, QuestTogether:GetAccessibleFrameMember(namePlateFrameBase, "namePlateUnitToken"))
		or nil
	if QuestTogether:IsNameplateUnitToken(plateFrameToken) then
		return plateFrameToken
	end

	local plateFrameGetUnitToken = nil
	local getUnitMethod = namePlateFrameBase
			and select(1, QuestTogether:GetAccessibleFrameMember(namePlateFrameBase, "GetUnit"))
		or nil
	if type(getUnitMethod) == "function" then
		local okUnit, resolvedUnitToken = pcall(getUnitMethod, namePlateFrameBase)
		if okUnit and QuestTogether:CanAccessValue(resolvedUnitToken) then
			plateFrameGetUnitToken = resolvedUnitToken
		end
	end
	if QuestTogether:IsNameplateUnitToken(plateFrameGetUnitToken) then
		return plateFrameGetUnitToken
	end

	local unitFrameNamePlateToken = unitFrame
			and select(1, QuestTogether:GetAccessibleFrameMember(unitFrame, "namePlateUnitToken"))
		or nil
	if QuestTogether:IsNameplateUnitToken(unitFrameNamePlateToken) then
		return unitFrameNamePlateToken
	end

	local unitFrameUnitToken = unitFrame and select(1, QuestTogether:GetAccessibleFrameMember(unitFrame, "unit")) or nil
	if QuestTogether:IsNameplateUnitToken(unitFrameUnitToken) then
		return unitFrameUnitToken
	end

	local displayedUnitToken = unitFrame
			and select(1, QuestTogether:GetAccessibleFrameMember(unitFrame, "displayedUnit"))
		or nil
	if QuestTogether:IsNameplateUnitToken(displayedUnitToken) then
		return displayedUnitToken
	end

	return nil
end

Services.Access = {
	CallAccessibleFrameMethod = CallAccessibleFrameMethod,
	CanMutateFrame = CanMutateFrame,
	GetAccessibleChildFrame = GetAccessibleChildFrame,
	IsFrameForbidden = IsFrameForbidden,
	IsNonEmptyString = IsNonEmptyString,
	PrintOneShotNameplateDebug = PrintOneShotNameplateDebug,
	QUEST_STATE_SETTLE_SECONDS = QUEST_STATE_SETTLE_SECONDS,
	ResolveNameplateUnitToken = ResolveNameplateUnitToken,
	SafeFindPlain = SafeFindPlain,
	SafeMatch = SafeMatch,
	SafeText = SafeText,
	SafeTrimText = SafeTrimText,
	SafeUiNumber = SafeUiNumber,
	ShouldSuppressStructuredQuestTooltipSource = ShouldSuppressStructuredQuestTooltipSource,
}
