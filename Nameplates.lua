local L = _G.QuestTogether.Translate
--[[
QuestTogether Nameplate Augmentation

Purpose:
- Add a quest icon on Blizzard default nameplates for quest-objective units.
- Optionally tint quest-objective health bars using an addon overlay, without mutating Blizzard bar colors.

Design constraints:
- Keep the implementation minimal and non-invasive.
- Do not replace Blizzard templates or secure handlers.
- Hook post-update paths so Blizzard remains source-of-truth for baseline behavior.
]]

local QuestTogether = _G.QuestTogether
local PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS = 1.0
local PLATER_INITIAL_QUEST_LOG_UPDATED_DELAY_SECONDS = 4.1
local PLATER_INITIAL_FULL_REFRESH_DELAY_SECONDS = 5.1
local NAMEPLATE_TOOLTIP_RETRY_DELAY_SECONDS = 0.2
local NAMEPLATE_TOOLTIP_RETRY_MAX_ATTEMPTS = 4
local NAMEPLATE_SCAN_TOOLTIP_NAME = "QuestTogetherNameplateScanTooltip"
local ANNOUNCEMENT_BUBBLE_Y_OFFSET = 22
local ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS = 0.2
local ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS = 0.4
local PERSONAL_BUBBLE_SETTINGS_DIALOG_WIDTH = 380
local PERSONAL_BUBBLE_SETTINGS_DIALOG_HEIGHT = 220
local ApplyQuestIconVisual
local EnsureQuestIcon
local ResolveNameplateUnitToken
local SafeUiNumber
local SafeText

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
	if QuestTogether and QuestTogether.IsForbiddenFrame then
		return QuestTogether:IsForbiddenFrame(frame)
	end

	local frameType = type(frame)
	if not frame or (frameType ~= "table" and frameType ~= "userdata") then
		return false
	end
	if not frame.IsForbidden then
		return false
	end

	-- An unreadable permission check cannot authorize a foreign-frame write.
	local ok, forbidden = pcall(frame.IsForbidden, frame)
	return not ok or forbidden == true
end

local function CanMutateFrame(frame)
	if QuestTogether and QuestTogether.CanAccessForeignFrame then
		if not QuestTogether:CanAccessForeignFrame(frame) then
			return false
		end
		local isProtected = QuestTogether.IsProtectedFrame and QuestTogether:IsProtectedFrame(frame) or false
		if isProtected and QuestTogether.IsRuntimeRestricted and QuestTogether:IsRuntimeRestricted() then
			return false
		end
		return true
	end
	return frame ~= nil and not IsFrameForbidden(frame)
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

function SafeText(value, fallback)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, fallback or "")
	end

	local ok, text = pcall(tostring, value)
	if ok then
		return text
	end
	return fallback or ""
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
	if QuestTogether and QuestTogether.SafeTrimString then
		return QuestTogether:SafeTrimString(text, "")
	end
	return SafeText(text, "")
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

if QuestTogether.EnsureRuntimeStateStore then
	QuestTogether:EnsureRuntimeStateStore()
end
if not QuestTogether.GetNameplateStateStore then
	QuestTogether.nameplateQuestTextCache = QuestTogether.nameplateQuestTextCache or {}
	QuestTogether.nameplateQuestStateByGuid = QuestTogether.nameplateQuestStateByGuid or {}
	QuestTogether.nameplateQuestStateByUnitToken = QuestTogether.nameplateQuestStateByUnitToken or {}
	QuestTogether.nameplateQuestGuidByUnitToken = QuestTogether.nameplateQuestGuidByUnitToken or {}
	QuestTogether.nameplateIconByUnitFrame = QuestTogether.nameplateIconByUnitFrame
		or setmetatable({}, { __mode = "k" })
	QuestTogether.nameplateHealthOverlayByUnitFrame = QuestTogether.nameplateHealthOverlayByUnitFrame
		or setmetatable({}, { __mode = "k" })
	QuestTogether.nameplateBubbleByUnitFrame = QuestTogether.nameplateBubbleByUnitFrame
		or setmetatable({}, { __mode = "k" })
	QuestTogether.nameplateBubbleStateByFrame = QuestTogether.nameplateBubbleStateByFrame
		or setmetatable({}, { __mode = "k" })
	QuestTogether.personalBubbleSliderHandlesByFrame = QuestTogether.personalBubbleSliderHandlesByFrame
		or setmetatable({}, { __mode = "k" })
	QuestTogether.personalBubbleDialogPositionByFrame = QuestTogether.personalBubbleDialogPositionByFrame
		or setmetatable({}, { __mode = "k" })
	QuestTogether.nameplateRefreshPendingByUnitToken = QuestTogether.nameplateRefreshPendingByUnitToken or {}
	QuestTogether.nameplateRefreshGenerationByUnitToken = QuestTogether.nameplateRefreshGenerationByUnitToken or {}
	QuestTogether.nameplateHealthTintRefreshPendingByUnitToken =
		QuestTogether.nameplateHealthTintRefreshPendingByUnitToken or {}
	QuestTogether.nameplateFullRefreshGeneration = QuestTogether.nameplateFullRefreshGeneration or 0
end

local function GetAnnouncementBubbleLifetimeSeconds()
	local configuredDuration = QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
	if not configuredDuration or configuredDuration <= 0 then
		configuredDuration = QuestTogether.DEFAULTS.profile.chatBubbleDuration
	end
	return SafeUiNumber(configuredDuration, QuestTogether.DEFAULTS.profile.chatBubbleDuration)
end

local function GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame or IsFrameForbidden(hostFrame) then
		return nil
	end

	local unitFrame, memberReadable = QuestTogether:GetAccessibleFrameMember(hostFrame, "UnitFrame")
	if not memberReadable then
		return nil
	end
	unitFrame = unitFrame or hostFrame
	if not QuestTogether:CanAccessForeignFrame(unitFrame) then
		return nil
	end
	return unitFrame
end

local function GetSavedPersonalBubbleDialogPosition(dialog)
	if not dialog or not QuestTogether.personalBubbleDialogPositionByFrame then
		return nil
	end
	return QuestTogether.personalBubbleDialogPositionByFrame[dialog]
end

local function SetSavedPersonalBubbleDialogPosition(dialog, position)
	if not dialog or type(position) ~= "table" then
		return
	end
	QuestTogether.personalBubbleDialogPositionByFrame[dialog] = position
end

local function GetAnnouncementBubbleState(bubble)
	if not bubble or not QuestTogether.nameplateBubbleStateByFrame then
		return nil
	end
	return QuestTogether.nameplateBubbleStateByFrame[bubble]
end

local function SetAnnouncementBubbleState(bubble, state)
	if not bubble or type(state) ~= "table" then
		return nil
	end
	QuestTogether.nameplateBubbleStateByFrame[bubble] = state
	return state
end

local function ClearAnnouncementBubbleState(bubble)
	if not bubble or not QuestTogether.nameplateBubbleStateByFrame then
		return
	end
	QuestTogether.nameplateBubbleStateByFrame[bubble] = nil
end

local function DeferAnnouncementBubbleCleanup(addon, bubble)
	if bubble then
		local state = addon:GetNameplateStateStore()
		state.pendingVisualCleanupByFrame = state.pendingVisualCleanupByFrame or {}
		state.pendingVisualCleanupByFrame[bubble] = "bubble"
		addon.pendingNameplateVisualCleanup = true
	end
	return false
end

function QuestTogether:CompleteAnnouncementBubblePlayback(bubble)
	local bubbleState = GetAnnouncementBubbleState(bubble)
	local unitToken = bubbleState and bubbleState.unitToken or nil
	if bubbleState and bubbleState.text then
		self:Debugf("bubble", "playback_complete unit=%s event=%s", SafeText(unitToken, ""), SafeText(bubbleState.eventType, ""))
	end
	ClearAnnouncementBubbleState(bubble)
	if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(unitToken) then
		return false
	end
	if not CanMutateFrame(bubble) then
		return false
	end

	bubble:SetAlpha(0)
	bubble:Hide()
	return true
end

function QuestTogether:StopAndHideAnnouncementBubblePlayback(bubble, reason)
	local bubbleState = GetAnnouncementBubbleState(bubble)
	local unitToken = bubbleState and bubbleState.unitToken or nil
	if bubbleState and bubbleState.text then
		self:Debugf("bubble", "playback_stop unit=%s event=%s reason=%s", SafeText(unitToken, ""),
			SafeText(bubbleState.eventType, ""), SafeText(reason, "hide"))
	end
	-- Teardown only touches this addon-owned bubble and its animation. Unlike
	-- starting/reparenting playback, hiding an accessible unprotected region is
	-- safe during combat. Do not leave old playback attached to a reused base.
	if not CanMutateFrame(bubble) then
		ClearAnnouncementBubbleState(bubble)
		return DeferAnnouncementBubbleCleanup(self, bubble)
	end
	if
		bubble.animationGroup
		and type(bubble.animationGroup.IsPlaying) == "function"
		and bubble.animationGroup:IsPlaying()
	then
		bubble.animationGroup:Stop()
	end
	-- Stop invokes OnStop synchronously. It can clear playback state; recheck
	-- the handle before further writes without relying on the retired token.
	ClearAnnouncementBubbleState(bubble)
	if not CanMutateFrame(bubble) then
		return DeferAnnouncementBubbleCleanup(self, bubble)
	end
	bubble:SetAlpha(0)
	bubble:Hide()
	self:CancelNameplateVisualCleanup(bubble)
	return true
end

local function ScaleBubbleMetric(baseValue, sizeScale, minimumValue)
	local scaledValue = math.floor((baseValue * sizeScale) + 0.5)
	if minimumValue then
		return math.max(minimumValue, scaledValue)
	end
	return scaledValue
end

local function GetPersonalBubbleAnchorFontDefinition()
	if ChatBubbleFont and ChatBubbleFont.GetFont then
		local fontPath, _, fontFlags = ChatBubbleFont:GetFont()
		if fontPath and fontPath ~= "" then
			return fontPath, fontFlags
		end
	end

	if GameFontHighlightMedium and GameFontHighlightMedium.GetFont then
		local fontPath, _, fontFlags = GameFontHighlightMedium:GetFont()
		if fontPath and fontPath ~= "" then
			return fontPath, fontFlags
		end
	end

	return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", ""
end

local function GetAnnouncementBubbleVisualConfig()
	local configuredSize = QuestTogether:NormalizeChatBubbleSizeValue(QuestTogether:GetOption("chatBubbleSize"))
		or QuestTogether.DEFAULTS.profile.chatBubbleSize
	local sizeScale = configuredSize / 100

	return {
		fontSize = ScaleBubbleMetric(14, sizeScale, 10),
		iconSize = ScaleBubbleMetric(18, sizeScale, 12),
		iconGap = ScaleBubbleMetric(8, sizeScale, 4),
		minTextWidth = ScaleBubbleMetric(48, sizeScale, 40),
		maxTextWidth = ScaleBubbleMetric(220, sizeScale, 160),
		inset = ScaleBubbleMetric(16, sizeScale, 12),
	}
end

local function EstimateBubbleTextWidth(text, fontSize, minTextWidth, maxTextWidth)
	local textValue = type(text) == "string" and text or ""
	if textValue == "" then
		return minTextWidth
	end

	local characterWidth = math.max(5, fontSize * 0.55)
	local estimatedWidth = math.floor((string.len(textValue) * characterWidth) + 0.5)
	return math.min(maxTextWidth, math.max(minTextWidth, estimatedWidth))
end

local function EstimateBubbleTextHeight(text, textWidth, fontSize)
	local textValue = type(text) == "string" and text or ""
	local lineHeight = math.max(fontSize, math.floor((fontSize * 1.2) + 0.5))
	if textValue == "" then
		return lineHeight
	end

	local characterWidth = math.max(5, fontSize * 0.55)
	local maxCharsPerLine = math.max(1, math.floor(textWidth / characterWidth))
	local lineCount = math.max(1, math.ceil(string.len(textValue) / maxCharsPerLine))
	return lineCount * lineHeight
end

local function EnsurePersonalBubbleAnchorSelection(hostFrame)
	if not hostFrame or hostFrame.Selection then
		return hostFrame and hostFrame.Selection or nil
	end
	if not EditModeManagerFrame then
		return nil
	end

	-- EditMode templates can be unavailable on some clients/states; fail soft and skip selection chrome.
	local ok, selection = pcall(CreateFrame, "Frame", nil, hostFrame, "EditModeSystemSelectionTemplate")
	if not ok or not selection then
		return nil
	end

	selection:SetAllPoints()
	selection:SetFrameLevel(hostFrame:GetFrameLevel() + 20)
	selection:EnableMouse(false)
	selection:Hide()
	if selection.SetSystem then
		selection:SetSystem({
			GetSystemName = function()
				return L("QuestTogether Bubble")
			end,
		})
	elseif selection.SetGetLabelTextFunction then
		selection:SetGetLabelTextFunction(function()
			return L("QuestTogether Bubble")
		end)
	end
	if selection.Label then
		selection.Label:Hide()
	end
	selection.UpdateLabelVisibility = function(frame)
		if frame.Label then
			frame.Label:Hide()
		end
		if frame.HorizontalLabel then
			frame.HorizontalLabel:Hide()
		end
		if frame.VerticalLabel then
			frame.VerticalLabel:Hide()
		end
	end

	hostFrame.Selection = selection
	return selection
end

local function GetPersonalBubbleAnchorDialogAttachPoint()
	if QuestTogether:CanAccessForeignFrame(EditModeManagerFrame, true) then
		return "TOPLEFT", EditModeManagerFrame, "TOPRIGHT", 16, -40
	end
	return "CENTER", UIParent, "CENTER", 420, 40
end

local function SavePersonalBubbleDialogPosition(dialog)
	if not dialog then
		return
	end

	local point, _, relativePoint, offsetX, offsetY = dialog:GetPoint(1)
	if not point or not relativePoint then
		return
	end

	SetSavedPersonalBubbleDialogPosition(dialog, {
		point = point,
		relativePoint = relativePoint,
		x = offsetX,
		y = offsetY,
	})
end

function QuestTogether:GetPersonalBubbleEditSession()
	local session = self.personalBubbleEditSession
	if session and session.profile ~= (self.db and self.db.profile) then
		self.personalBubbleEditSession = nil
		self.personalBubbleEditSessionRestoring = false
		return nil
	end
	return session
end

local function GetPersonalBubbleEditSession()
	return QuestTogether:GetPersonalBubbleEditSession()
end

local function EnsurePersonalBubbleEditSession()
	local currentSession = GetPersonalBubbleEditSession()
	if currentSession then
		return currentSession
	end

	local session = {
		profile = QuestTogether.db and QuestTogether.db.profile,
		saved = {
			chatBubbleSize = QuestTogether:NormalizeChatBubbleSizeValue(QuestTogether:GetOption("chatBubbleSize"))
				or QuestTogether.DEFAULTS.profile.chatBubbleSize,
			chatBubbleDuration = QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
				or QuestTogether.DEFAULTS.profile.chatBubbleDuration,
			anchor = QuestTogether:DeepCopy(QuestTogether:GetPersonalBubbleAnchor()),
		},
		pending = false,
	}

	QuestTogether.personalBubbleEditSession = session
	return session
end


local function IsPersonalBubbleEditSnapshotEqual(snapshot)
	if type(snapshot) ~= "table" then
		return true
	end

	local currentSize = QuestTogether:NormalizeChatBubbleSizeValue(QuestTogether:GetOption("chatBubbleSize"))
		or QuestTogether.DEFAULTS.profile.chatBubbleSize
	local currentDuration = QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
		or QuestTogether.DEFAULTS.profile.chatBubbleDuration
	local currentAnchor = QuestTogether:GetPersonalBubbleAnchor()
	local savedAnchor = snapshot.anchor or QuestTogether.DEFAULT_PERSONAL_BUBBLE_ANCHOR

	return currentSize == snapshot.chatBubbleSize
		and currentDuration == snapshot.chatBubbleDuration
		and currentAnchor.point == savedAnchor.point
		and currentAnchor.relativePoint == savedAnchor.relativePoint
		and currentAnchor.x == savedAnchor.x
		and currentAnchor.y == savedAnchor.y
end

local function IsPersonalBubbleAtDefaultState()
	local defaults = QuestTogether.DEFAULTS.profile
	local anchorDefaults = QuestTogether.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	local currentSize = QuestTogether:NormalizeChatBubbleSizeValue(QuestTogether:GetOption("chatBubbleSize"))
		or defaults.chatBubbleSize
	local currentDuration = QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
		or defaults.chatBubbleDuration
	local currentAnchor = QuestTogether:GetPersonalBubbleAnchor()

	return currentSize == defaults.chatBubbleSize
		and currentDuration == defaults.chatBubbleDuration
		and currentAnchor.point == anchorDefaults.point
		and currentAnchor.relativePoint == anchorDefaults.relativePoint
		and currentAnchor.x == anchorDefaults.x
		and currentAnchor.y == anchorDefaults.y
end

local function UpdatePersonalBubbleEditSessionDirtyState()
	local session = EnsurePersonalBubbleEditSession()
	session.pending = not IsPersonalBubbleEditSnapshotEqual(session.saved)
	if
		QuestTogether.personalBubbleEditModeDialog
		and QuestTogether.personalBubbleEditModeDialog.RevertButton
	then
		QuestTogether.personalBubbleEditModeDialog.RevertButton:SetEnabled(session.pending)
		QuestTogether.personalBubbleEditModeDialog.ResetButton:SetEnabled(not IsPersonalBubbleAtDefaultState())
	end
end

local function ConfigureEditModeSlider(settingFrame, settingData, onValueChanged)
	if not settingFrame then
		return
	end

	if settingFrame.cbrHandles then
		settingFrame.cbrHandles:Unregister()
	end

	local callbackHandles = QuestTogether.personalBubbleSliderHandlesByFrame[settingFrame]
	if not callbackHandles then
		callbackHandles = EventUtil.CreateCallbackHandleContainer()
		QuestTogether.personalBubbleSliderHandlesByFrame[settingFrame] = callbackHandles
	end
	callbackHandles:Unregister()
	callbackHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnValueChanged,
		function(_, value)
			if type(onValueChanged) == "function" then
				onValueChanged(value)
			end
		end,
		settingFrame
	)
	callbackHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnInteractStart,
		function()
		end,
		settingFrame
	)
	callbackHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnInteractEnd,
		function()
		end,
		settingFrame
	)

	settingFrame.OnSliderValueChanged = function()
	end
	settingFrame.OnSliderInteractEnd = function()
	end
	settingFrame.OnSliderInteractStart = function()
	end
	settingFrame:SetupSetting(settingData)
	settingFrame:Show()
end

function QuestTogether:ApplyPersonalBubbleEditSnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	self.personalBubbleEditSessionRestoring = true

	if snapshot.chatBubbleSize then
		self:SetOption("chatBubbleSize", snapshot.chatBubbleSize)
	end
	if snapshot.chatBubbleDuration then
		self:SetOption("chatBubbleDuration", snapshot.chatBubbleDuration)
	end
	if snapshot.anchor then
		self:SetPersonalBubbleAnchor(
			snapshot.anchor.point,
			snapshot.anchor.relativePoint,
			snapshot.anchor.x,
			snapshot.anchor.y
		)
	end

	self.personalBubbleEditSessionRestoring = false
	self:RefreshPersonalBubbleAnchorVisualState()
	self:AttachPersonalBubbleEditModeDialog()
	self:RefreshPersonalBubbleEditModeDialog()
end

function QuestTogether:CommitPersonalBubbleEditSession()
	self.personalBubbleEditSession = nil
	self.personalBubbleEditSessionRestoring = false
	if self.personalBubbleEditModeDialog and self.personalBubbleEditModeDialog.RevertButton then
		self.personalBubbleEditModeDialog.RevertButton:SetEnabled(false)
	end
end

function QuestTogether:RevertPersonalBubbleEditSession()
	local session = self:GetPersonalBubbleEditSession()
	if not session then
		return
	end

	self:ApplyPersonalBubbleEditSnapshot(session.saved)
	session.pending = false
	if self.personalBubbleEditModeDialog and self.personalBubbleEditModeDialog.RevertButton then
		self.personalBubbleEditModeDialog.RevertButton:SetEnabled(false)
	end
end

function QuestTogether:ResetPersonalBubbleEditSessionToDefaults()
	self.personalBubbleEditSessionRestoring = true
	self:SetOption("chatBubbleSize", self.DEFAULTS.profile.chatBubbleSize)
	self:SetOption("chatBubbleDuration", self.DEFAULTS.profile.chatBubbleDuration)
	self:ResetPersonalBubbleAnchor()
	self.personalBubbleEditSessionRestoring = false

	UpdatePersonalBubbleEditSessionDirtyState()
	self:RefreshPersonalBubbleAnchorVisualState()
	self:AttachPersonalBubbleEditModeDialog()
	self:RefreshPersonalBubbleEditModeDialog()
end

local function EnsurePersonalBubbleEditModeDialog()
	if QuestTogether.personalBubbleEditModeDialog then
		return QuestTogether.personalBubbleEditModeDialog
	end
	if not EditModeManagerFrame then
		return nil
	end

	local dialog = CreateFrame("Frame", "QuestTogetherPersonalBubbleSettingsDialog", UIParent)
	dialog:SetSize(PERSONAL_BUBBLE_SETTINGS_DIALOG_WIDTH, PERSONAL_BUBBLE_SETTINGS_DIALOG_HEIGHT)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(250)
	dialog:SetClampedToScreen(true)
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:EnableKeyboard(true)
	dialog:Hide()

	local border = CreateFrame("Frame", nil, dialog, "DialogBorderTranslucentTemplate")
	border:SetAllPoints()
	dialog.Border = border

	local title = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", dialog, "TOP", 0, -15)
	title:SetText(L("QuestTogether Bubble"))
	dialog.Title = title

	local closeButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", dialog, "TOPRIGHT")
	closeButton:SetScript("OnClick", function()
		QuestTogether:DeselectPersonalBubbleAnchor()
	end)
	dialog.CloseButton = closeButton

	local dragHandle = CreateFrame("Frame", nil, dialog)
	dragHandle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -8)
	dragHandle:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", -4, -8)
	dragHandle:SetHeight(28)
	dragHandle:EnableMouse(true)
	dragHandle:RegisterForDrag("LeftButton")
	dragHandle:SetScript("OnDragStart", function()
		dialog:StartMoving()
	end)
	dragHandle:SetScript("OnDragStop", function()
		dialog:StopMovingOrSizing()
		SavePersonalBubbleDialogPosition(dialog)
	end)
	dialog.DragHandle = dragHandle

	local sizeSlider = CreateFrame("Frame", nil, dialog, "EditModeSettingSliderTemplate")
	sizeSlider:SetPoint("TOPLEFT", dialog, "TOPLEFT", 24, -48)
	dialog.SizeSlider = sizeSlider

	local durationSlider = CreateFrame("Frame", nil, dialog, "EditModeSettingSliderTemplate")
	durationSlider:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -18)
	dialog.DurationSlider = durationSlider

	local revertButton = CreateFrame("Button", nil, dialog, "EditModeSystemSettingsDialogButtonTemplate")
	revertButton:SetSize(160, 28)
	revertButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 24, 18)
	revertButton:SetText(L("Revert Changes"))
	revertButton:SetScript("OnClick", function()
		QuestTogether:RevertPersonalBubbleEditSession()
	end)
	dialog.RevertButton = revertButton

	local resetButton = CreateFrame("Button", nil, dialog, "EditModeSystemSettingsDialogButtonTemplate")
	resetButton:SetSize(160, 28)
	resetButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -24, 18)
	resetButton:SetText(L("Reset To Default"))
	resetButton:SetScript("OnClick", function()
		QuestTogether:ResetPersonalBubbleEditSessionToDefaults()
	end)
	dialog.ResetButton = resetButton

	dialog:SetScript("OnDragStart", function(frame)
		frame:StartMoving()
	end)
	dialog:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		SavePersonalBubbleDialogPosition(frame)
	end)
	dialog:SetScript("OnHide", function(frame)
		frame:StopMovingOrSizing()
	end)
	dialog:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then
			QuestTogether:DeselectPersonalBubbleAnchor()
		end
	end)

	QuestTogether.personalBubbleEditModeDialog = dialog
	return dialog
end

local function GetAnnouncementBubbleScreenHostFrame()
	if QuestTogether.announcementBubbleScreenHostFrame then
		return QuestTogether.announcementBubbleScreenHostFrame
	end
	if QuestTogether.IsRuntimeRestricted and QuestTogether:IsRuntimeRestricted() then
		-- Constructing and laying out UI can wait; do not create even addon-owned
		-- frames for the first time from a restricted callback path.
		return nil
	end

	local parentFrame = UIParent or (C_UI and C_UI.GetUIParent and C_UI.GetUIParent()) or nil
	if not parentFrame then
		return nil
	end

	local hostFrame = CreateFrame("Frame", "QuestTogetherPersonalBubbleAnchor", parentFrame)
	hostFrame:SetSize(1, 1)
	hostFrame:SetFrameStrata("LOW")
	hostFrame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
	hostFrame:SetClampedToScreen(true)
	hostFrame:SetMovable(true)
	hostFrame:RegisterForDrag("LeftButton")
	hostFrame:EnableMouse(false)

	local background = hostFrame:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 6, -6)
	background:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", -6, 6)
	background:SetColorTexture(0.03, 0.03, 0.03, 0.68)
	background:Hide()
	hostFrame.EditBackground = background

	local border = hostFrame:CreateTexture(nil, "BORDER")
	border:SetPoint("TOPLEFT", background, "TOPLEFT", 0, 0)
	border:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", 0, 0)
	border:SetColorTexture(0.45, 0.52, 0.6, 0.35)
	border:Hide()
	hostFrame.EditBorder = border

	local icon = hostFrame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(16, 16)
	icon:SetPoint("LEFT", hostFrame, "LEFT", 16, 0)
	ApplyQuestIconVisual(icon)
	icon:Hide()
	hostFrame.EditIcon = icon

	local label = hostFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	label:SetJustifyH("LEFT")
	label:SetJustifyV("MIDDLE")
	label:SetTextColor(1, 0.82, 0, 1)
	label:SetText(L("QuestTogether Bubble"))
	label:Hide()
	hostFrame.EditLabel = label

	hostFrame:SetScript("OnEnter", function()
		QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	end)
	hostFrame:SetScript("OnLeave", function()
		QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	end)
	hostFrame:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		QuestTogether:SelectPersonalBubbleAnchor()
	end)
	hostFrame:SetScript("OnDragStart", function(frame)
		if not QuestTogether:IsPersonalBubbleAnchorInEditMode() then
			return
		end
		QuestTogether:SelectPersonalBubbleAnchor()
		frame:StartMoving()
	end)
	hostFrame:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		QuestTogether:SavePersonalBubbleAnchorFromFrame(frame)
		QuestTogether:AttachPersonalBubbleEditModeDialog()
	end)

	QuestTogether.announcementBubbleScreenHostFrame = hostFrame
	QuestTogether:ApplySavedPersonalBubbleAnchor()
	QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	hostFrame:Show()

	return hostFrame
end

function QuestTogether:IsPersonalBubbleAnchorInEditMode()
	return (self.isEnabled and self:CanAccessForeignFrame(EditModeManagerFrame, true) and self:GetOption("showChatBubbles"))
		and true or false
end

function QuestTogether:ApplySavedPersonalBubbleAnchor()
	local hostFrame = self.announcementBubbleScreenHostFrame
	if not hostFrame then
		return
	end

	local parentFrame = hostFrame:GetParent() or UIParent
	local anchor = self:GetPersonalBubbleAnchor()
	hostFrame:ClearAllPoints()
	hostFrame:SetPoint(anchor.point, parentFrame, anchor.relativePoint, anchor.x, anchor.y)
	if self.personalBubbleEditModeDialog and self.personalBubbleEditModeDialog:IsShown() then
		self:AttachPersonalBubbleEditModeDialog()
	end
end

local function RoundOffset(value)
	local numberValue = SafeUiNumber(value, 0)
	if numberValue >= 0 then
		return math.floor(numberValue + 0.5)
	end
	return math.ceil(numberValue - 0.5)
end

function QuestTogether:SavePersonalBubbleAnchorFromFrame(hostFrame)
	if not hostFrame then
		return false
	end

	local point, _, relativePoint, offsetX, offsetY = hostFrame:GetPoint(1)
	if not point or not relativePoint then
		return false
	end

	local changed = self:SetPersonalBubbleAnchor(point, relativePoint, RoundOffset(offsetX), RoundOffset(offsetY))
	if changed and self:IsPersonalBubbleAnchorInEditMode() and not self.personalBubbleEditSessionRestoring then
		UpdatePersonalBubbleEditSessionDirtyState()
		self:RefreshPersonalBubbleEditModeDialog()
	end
	return changed
end

function QuestTogether:AttachPersonalBubbleEditModeDialog()
	local dialog = self.personalBubbleEditModeDialog
	if not dialog then
		return
	end

	local savedPosition = GetSavedPersonalBubbleDialogPosition(dialog)
	if savedPosition then
		dialog:ClearAllPoints()
		dialog:SetPoint(
			savedPosition.point,
			UIParent,
			savedPosition.relativePoint,
			savedPosition.x,
			savedPosition.y
		)
		return
	end

	local point, relativeTo, relativePoint, offsetX, offsetY = GetPersonalBubbleAnchorDialogAttachPoint()
	dialog:ClearAllPoints()
	dialog:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
end

function QuestTogether:RefreshPersonalBubbleEditModeDialog()
	local dialog = EnsurePersonalBubbleEditModeDialog()
	if not dialog then
		return
	end

	local session = GetPersonalBubbleEditSession()

	local function FormatDurationLabel(value)
		local normalized = self:NormalizeChatBubbleDurationValue(value) or self.DEFAULTS.profile.chatBubbleDuration
		if math.abs(normalized - math.floor(normalized)) < 0.001 then
			return string.format(L("%d sec"), normalized)
		end
		return string.format(L("%.1f sec"), normalized)
	end

	ConfigureEditModeSlider(dialog.SizeSlider, {
		displayInfo = {
			setting = "chatBubbleSize",
			formatter = function(value)
				local normalized = self:NormalizeChatBubbleSizeValue(value) or self.DEFAULTS.profile.chatBubbleSize
				return self:GetChatBubbleSizeLabel(normalized)
			end,
			minValue = self.CHAT_BUBBLE_SIZE_MIN,
			maxValue = self.CHAT_BUBBLE_SIZE_MAX,
			stepSize = self.CHAT_BUBBLE_SIZE_STEP,
		},
		currentValue = self:NormalizeChatBubbleSizeValue(self:GetOption("chatBubbleSize")) or self.DEFAULTS.profile.chatBubbleSize,
		settingName = L("Font Size"),
	}, function(value)
		if self:SetOption("chatBubbleSize", value) and not self.personalBubbleEditSessionRestoring then
			UpdatePersonalBubbleEditSessionDirtyState()
			self:RefreshPersonalBubbleAnchorVisualState()
			self:AttachPersonalBubbleEditModeDialog()
		end
	end)

	ConfigureEditModeSlider(dialog.DurationSlider, {
		displayInfo = {
			setting = "chatBubbleDuration",
			formatter = FormatDurationLabel,
			minValue = self.CHAT_BUBBLE_DURATION_MIN,
			maxValue = self.CHAT_BUBBLE_DURATION_MAX,
			stepSize = self.CHAT_BUBBLE_DURATION_STEP,
		},
		currentValue = self:NormalizeChatBubbleDurationValue(self:GetOption("chatBubbleDuration"))
			or self.DEFAULTS.profile.chatBubbleDuration,
		settingName = L("Display Duration"),
	}, function(value)
		if self:SetOption("chatBubbleDuration", value) and not self.personalBubbleEditSessionRestoring then
			UpdatePersonalBubbleEditSessionDirtyState()
			self:RefreshPersonalBubbleAnchorVisualState()
			self:AttachPersonalBubbleEditModeDialog()
		end
	end)

	if dialog.RevertButton then
		dialog.RevertButton:SetEnabled(session and session.pending or false)
	end
	if dialog.ResetButton then
		dialog.ResetButton:SetEnabled(not IsPersonalBubbleAtDefaultState())
	end
end

function QuestTogether:SelectPersonalBubbleAnchor()
	if not self:IsPersonalBubbleAnchorInEditMode() then
		return
	end

	EnsurePersonalBubbleEditSession()

	local hostFrame = GetAnnouncementBubbleScreenHostFrame()
	if not hostFrame then
		return
	end

	if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
		EditModeManagerFrame:ClearSelectedSystem()
	end

	self.personalBubbleAnchorSelected = true
	self:RefreshPersonalBubbleAnchorVisualState()
	self:AttachPersonalBubbleEditModeDialog()
	self:RefreshPersonalBubbleEditModeDialog()

	local dialog = EnsurePersonalBubbleEditModeDialog()
	if dialog then
		dialog:Show()
	end
end

function QuestTogether:DeselectPersonalBubbleAnchor()
	self.personalBubbleAnchorSelected = false
	if self.personalBubbleEditModeDialog then
		self.personalBubbleEditModeDialog:Hide()
	end
	self:RefreshPersonalBubbleAnchorVisualState()
end

function QuestTogether:RefreshPersonalBubbleAnchorVisualState()
	local hostFrame = self.announcementBubbleScreenHostFrame
	if not hostFrame then
		return
	end

	EnsurePersonalBubbleAnchorSelection(hostFrame)

	local editModeActive = self:IsPersonalBubbleAnchorInEditMode()
	local uiParentLevel = SafeUiNumber(
		(UIParent and UIParent.GetFrameLevel and UIParent:GetFrameLevel()) or 0,
		0
	)
	if editModeActive then
		hostFrame:SetFrameStrata("HIGH")
		hostFrame:SetFrameLevel(uiParentLevel + 80)
		local visualConfig = GetAnnouncementBubbleVisualConfig()
		local fontPath, fontFlags = GetPersonalBubbleAnchorFontDefinition()
		hostFrame.EditLabel:SetFont(fontPath, visualConfig.fontSize, fontFlags)
		hostFrame.EditLabel:SetWidth(0)
		hostFrame.EditLabel:SetText(L("QuestTogether Bubble"))

		local labelWidth = hostFrame.EditLabel.GetUnboundedStringWidth and hostFrame.EditLabel:GetUnboundedStringWidth() or 0
		labelWidth = SafeUiNumber(labelWidth, 0)
		local labelHeight = SafeUiNumber(hostFrame.EditLabel:GetStringHeight(), visualConfig.fontSize)
		labelWidth = math.max(visualConfig.minTextWidth, math.min(visualConfig.maxTextWidth, labelWidth))
		local anchorWidth = labelWidth + visualConfig.iconSize + visualConfig.iconGap + (visualConfig.inset * 2)
		local anchorHeight = math.max(visualConfig.iconSize, labelHeight) + (visualConfig.inset * 2)

		hostFrame:SetSize(anchorWidth, anchorHeight)

		hostFrame.EditIcon:SetSize(visualConfig.iconSize, visualConfig.iconSize)
		hostFrame.EditIcon:ClearAllPoints()
		hostFrame.EditIcon:SetPoint("LEFT", hostFrame, "LEFT", visualConfig.inset, 0)

		hostFrame.EditLabel:ClearAllPoints()
		hostFrame.EditLabel:SetPoint("LEFT", hostFrame.EditIcon, "RIGHT", visualConfig.iconGap, 0)
		hostFrame.EditLabel:SetWidth(labelWidth)
	else
		hostFrame:SetFrameStrata("LOW")
		hostFrame:SetFrameLevel(uiParentLevel + 5)
		hostFrame:SetSize(1, 1)
	end

	local activeBubble = self.nameplateBubbleByUnitFrame and self.nameplateBubbleByUnitFrame[hostFrame]
	if activeBubble then
		activeBubble:SetFrameStrata(hostFrame:GetFrameStrata() or "LOW")
		activeBubble:SetFrameLevel(SafeUiNumber(hostFrame:GetFrameLevel(), 0) + 20)
	end
	hostFrame:EnableMouse(editModeActive)

	local visibleFields = {
		hostFrame.EditBackground,
		hostFrame.EditBorder,
		hostFrame.EditIcon,
		hostFrame.EditLabel,
	}

	for _, field in ipairs(visibleFields) do
		if field then
			if editModeActive then
				field:Show()
			else
				field:Hide()
			end
		end
	end

	if hostFrame.Selection then
		if editModeActive then
			if self.personalBubbleAnchorSelected then
				hostFrame.Selection:ShowSelected()
			else
				hostFrame.Selection:ShowHighlighted()
			end
		else
			hostFrame.Selection:Hide()
		end
	end

	if not editModeActive then
		self.personalBubbleAnchorSelected = false
		if self.personalBubbleEditModeDialog then
			self.personalBubbleEditModeDialog:Hide()
		end
	end

	hostFrame:Show()
end

function QuestTogether:TryInstallPersonalBubbleEditModeHooks()
	if self.personalBubbleEditModeHooksInstalled then
		return
	end

	if self:IsWorkBlocked("foreign_frame_mutation") or not CanMutateFrame(EditModeManagerFrame) then
		return
	end
	local hookScript = select(1, self:GetAccessibleFrameMember(EditModeManagerFrame, "HookScript"))
	if type(hookScript) ~= "function" then
		return
	end

	GetAnnouncementBubbleScreenHostFrame()
	EnsurePersonalBubbleEditModeDialog()

	EditModeManagerFrame:HookScript("OnShow", function()
		EnsurePersonalBubbleEditSession()
		QuestTogether:RefreshPersonalBubbleAnchorVisualState()
		QuestTogether:RefreshPersonalBubbleEditModeDialog()
	end)
	EditModeManagerFrame:HookScript("OnHide", function()
		QuestTogether:DeselectPersonalBubbleAnchor()
		-- Addon settings persist immediately. Keep dirty/revert state entirely
		-- addon-owned instead of writing Blizzard's shared layout manager.
		QuestTogether:CommitPersonalBubbleEditSession()
	end)

	hooksecurefunc(EditModeManagerFrame, "SelectSystem", function(_, systemFrame)
		local hostFrame = QuestTogether.announcementBubbleScreenHostFrame
		if hostFrame and systemFrame ~= hostFrame then
			QuestTogether:DeselectPersonalBubbleAnchor()
		end
	end)
	hooksecurefunc(EditModeManagerFrame, "ClearSelectedSystem", function()
		QuestTogether:DeselectPersonalBubbleAnchor()
	end)
	hooksecurefunc(EditModeManagerFrame, "SaveLayouts", function()
		QuestTogether:CommitPersonalBubbleEditSession()
	end)
	hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", function()
		QuestTogether:RevertPersonalBubbleEditSession()
	end)
	local revertButton = GetAccessibleChildFrame(EditModeManagerFrame, "RevertAllChangesButton")
	if CanMutateFrame(revertButton) and type(select(1, self:GetAccessibleFrameMember(revertButton, "HookScript"))) == "function" then
		revertButton:HookScript("OnClick", function()
			QuestTogether:RevertPersonalBubbleEditSession()
		end)
	end

	self.personalBubbleEditModeHooksInstalled = true
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
		return "|cff33ff99available|r", "available"
	end

	return "|cffff4444unavailable|r", "unavailable"
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
	local wantsPersonalBubble = wantsChatBubbles and not (self.GetOption and self:GetOption("hideMyOwnChatBubbles") == true)

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
	local header = hasLimitedFunctionality
		and L("QuestTogether detects limited functionality in the current instance.")
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
local function GetObjectiveProgressState(text)
	if type(text) ~= "string" or text == "" then
		return "unknown"
	end

	local amountCurrent, amountTotal = SafeMatch(text, "(%d+)%s*/%s*(%d+)")
	if amountCurrent and amountTotal then
		local currentValue = SafeUiNumber(amountCurrent, nil)
		local totalValue = SafeUiNumber(amountTotal, nil)
		if currentValue == nil or totalValue == nil then
			return "unknown"
		end
		if currentValue < totalValue then
			return "unfinished"
		end
		return "complete"
	end

	local percentText = SafeMatch(text, "(%d+)%%")
	if percentText then
		local percentValue = SafeUiNumber(percentText, nil)
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
	local trimmedText = SafeTrimText(text)
	if trimmedText == "" then
		return false
	end
	return QuestTogether and QuestTogether.nameplateQuestTextCache and QuestTogether.nameplateQuestTextCache[trimmedText]
		or false
end

local function IsTooltipQuestObjectiveLineType(lineType)
	if not QuestTogether:CanAccessValue(lineType) then
		return false
	end

	local normalizedType = SafeText(lineType, "")
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

	local normalizedType = SafeText(lineType, "")
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

	local normalizedType = SafeText(lineType, "")
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

	candidateText = SafeTrimText(candidateText)
	if candidateText == "" then
		return nil, false
	end

	return candidateText, false
end

local TOOLTIP_ARGUMENT_TEXT_FIELDS = { "leftText", "text", "rightText", "stringVal", "name", "unitName", "title", "value" }
local TOOLTIP_LINE_TEXT_FIELDS = { "leftText", "text", "rightText" }
local function GetTooltipStructuredArgText(addon, argData, depth)
	addon = addon or QuestTogether
	depth = SafeUiNumber(depth, 0) or 0
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

	return SafeTrimText(text) == SafeTrimText(THREAT_TOOLTIP)
end

local function GetTooltipQuestLeftText(addon, lineData)
	local leftText = GetTooltipQuestLinePrimaryText(lineData, addon)
	if type(leftText) ~= "string" then
		return ""
	end

	return SafeTrimText(leftText)
end

local function NormalizeTooltipObjectiveEvidenceText(text)
	local normalizedText = SafeTrimText(text)
	if normalizedText == "" then
		return ""
	end

	normalizedText = string.gsub(normalizedText, "^[-%*%+%s]+", "")

	local leadingAmountSuffix = SafeMatch(normalizedText, "^%d+%s*/%s*%d+%s+(.+)$")
	if type(leadingAmountSuffix) == "string" and leadingAmountSuffix ~= "" then
		normalizedText = SafeTrimText(leadingAmountSuffix)
	end

	local leadingPercentSuffix = SafeMatch(normalizedText, "^%d+%%%s+(.+)$")
	if type(leadingPercentSuffix) == "string" and leadingPercentSuffix ~= "" then
		normalizedText = SafeTrimText(leadingPercentSuffix)
	end

	local trimmedPrefix = SafeMatch(normalizedText, "^(.-):%s*%d+%s*/%s*%d+$")
	if type(trimmedPrefix) == "string" and trimmedPrefix ~= "" then
		normalizedText = SafeTrimText(trimmedPrefix)
	end

	local percentPrefix = SafeMatch(normalizedText, "^(.-)%s*%(%d+%%%s*%)$")
	if type(percentPrefix) == "string" and percentPrefix ~= "" then
		normalizedText = SafeTrimText(percentPrefix)
	end

	return normalizedText
end

local function AddNameplateQuestTextToCache(cache, text)
	if type(cache) ~= "table" then
		return
	end

	local trimmedText = SafeTrimText(text)
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
	local primaryText = SafeTrimText(text)
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
			if type(quest) == "table" and SafeTrimText(quest.title) == text then
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
	local playerText = SafeTrimText((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
	for fullName, member in pairs(addon.partyMembers or {}) do
		if type(fullName) == "string" then
			local shortName = SafeMatch(fullName, "^([^%-]+)%-") or fullName
			if playerText == fullName or playerText == shortName
				or (type(member) == "table" and playerText == member.displayName) then
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
			if hasQuestBlockBoundary and not matchedQuestBlock and matchedQuestText ~= nil
				and progressState == "unknown"
				and not IsTooltipQuestObjectiveLineType(lineType)
				and not IsTooltipQuestPlayerLineType(lineType)
				and IsKnownTooltipQuestTitle(self, primaryText) then
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
			if not matchedQuestBlock and matchesTitlelessQuestText and self:TooltipLineHasUnfinishedObjectiveEvidence(lineData) then
				return true
			end
			if matchedQuestBlock then
				if IsThreatTooltipMarkerText(primaryText) then
					matchedQuestBlock = false
					hasQuestBlockBoundary = true
				elseif self:TooltipLineHasUnfinishedObjectiveEvidence(lineData) then
					return true
				elseif progressState == "unknown" and matchedQuestText == nil
					and not IsTooltipQuestObjectiveLineType(lineType)
					and not IsTooltipQuestPlayerLineType(lineType)
					and not IsKnownTooltipQuestPlayerText(self, primaryText) then
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
	wipe(self.nameplateQuestStateByUnitToken)
	wipe(self.nameplateQuestGuidByUnitToken)
end

-- Invalidate both spawn and NPC completion evidence when quest state changes,
-- so new/reaccepted quests can make the same creature relevant again.
function QuestTogether:ClearNameplateQuestDetectionCache()
	wipe(self.nameplateQuestStateByGuid)
	wipe(self:GetNameplateStateStore().completedByNpcID)
	wipe(self.nameplateTooltipResolveRetryCountByUnitToken)
end

function QuestTogether:ForgetResolvedNameplateQuestState(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	self.nameplateQuestStateByUnitToken[unitToken] = nil
	self.nameplateQuestGuidByUnitToken[unitToken] = nil
end

function QuestTogether:GetNameplateTooltipResolveRetryCount(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return 0
	end

	local retryCounts = self.nameplateTooltipResolveRetryCountByUnitToken
	if type(retryCounts) ~= "table" then
		return 0
	end

	return SafeUiNumber(retryCounts[unitToken], 0) or 0
end

function QuestTogether:ClearNameplateTooltipResolveRetryCount(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local retryCounts = self.nameplateTooltipResolveRetryCountByUnitToken
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

	self.nameplateTooltipResolveRetryCountByUnitToken[unitToken] = retryCount + 1
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
	local kind = SafeMatch(unitGuid, "^([^-]+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then
		return nil
	end
	local npcIdText = SafeMatch(unitGuid, "^[^-]+%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
	local npcId = SafeUiNumber(npcIdText, nil)
	return npcId and npcId > 0 and npcId or nil
end

function QuestTogether:RememberNameplateNpcCompletion(unitGuid, completed)
	local npcID = GetNpcIdFromUnitGuid(unitGuid)
	if npcID then
		self:GetNameplateStateStore().completedByNpcID[npcID] = completed and true or nil
	end
end

function QuestTogether:StoreResolvedNameplateQuestState(unitToken, unitGuid, isQuestObjective)
	if not IsNonEmptyString(unitGuid) then
		return
	end

	self.nameplateQuestStateByGuid[unitGuid] = isQuestObjective and true or false
	if self:IsNameplateUnitToken(unitToken) then
		self.nameplateQuestStateByUnitToken[unitToken] = isQuestObjective and true or false
		self.nameplateQuestGuidByUnitToken[unitToken] = unitGuid
		if isQuestObjective then
			self:ClearNameplateTooltipResolveRetryCount(unitToken)
		end
	end
end

function QuestTogether:TryGetCachedQuestObjectiveStateForGuid(unitGuid)
	if not IsNonEmptyString(unitGuid) then
		return false, nil
	end
	local npcID = GetNpcIdFromUnitGuid(unitGuid)
	if npcID and self:GetNameplateStateStore().completedByNpcID[npcID] then
		-- Confirmed completion takes precedence over an older positive spawn.
		return true, false
	end

	local cachedQuestObjective = self.nameplateQuestStateByGuid[unitGuid]
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

	local questLogIndex = addon.GetQuestLogIndexForQuest
		and addon:GetQuestLogIndexForQuest(questID, questDetails)
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
	wipe(self.nameplateQuestTextCache)

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
			AddNameplateQuestTextToCache(self.nameplateQuestTextCache, questDetails.title)
			AddLiveQuestObjectiveTextsToNameplateCache(self, self.nameplateQuestTextCache, questID, questDetails)
		end
	end

	AddTrackedQuestObjectiveTextsToNameplateCache(self, self.nameplateQuestTextCache)
	self:SetRuntimeFlag("nameplateQuestTextCacheSuppressed", false)
end

function QuestTogether:TryGetReusableCachedNameplateQuestState(unitToken, unitGuid)
	local hasCachedQuestState, cachedQuestState = self:TryGetCachedQuestObjectiveStateForGuid(unitGuid)
	if not hasCachedQuestState then
		return false, nil
	end

	if self:IsNameplateUnitToken(unitToken) then
		self.nameplateQuestStateByUnitToken[unitToken] = cachedQuestState and true or false
		self.nameplateQuestGuidByUnitToken[unitToken] = unitGuid
	end

	return true, cachedQuestState
end

-- Unit tokens and frames are recycled independently. Only a readable live GUID
-- owns cached quest state. Token tooltip scans can still resolve without it.
function QuestTogether:GetNameplateTooltipScanGuid(unitToken, _unitFrame)
	local liveGuid = self:GetNameplateUnitGuid(unitToken)
	if IsNonEmptyString(liveGuid) then
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
	normalizedText = SafeTrimText(normalizedText)
	if normalizedText == "" then
		return nil
	end

	return normalizedText
end

function QuestTogether:SanitizeTooltipQuestLineText(textValue)
	if self:IsSecretValue(textValue) or type(textValue) ~= "string" then
		return nil
	end

	local trimmedValue = SafeTrimText(textValue)
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
		elseif
			IsTooltipQuestObjectiveLineType(rawLine.type)
			or IsTooltipQuestPlayerLineType(rawLine.type)
		then
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
	if ShouldSuppressStructuredQuestTooltipSource(self) then
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
		return { {
			name = "structured_unit",
			resolve = function()
				return self:GetStructuredQuestObjectiveTooltipLines(unitToken, unitGuid, "unit")
			end,
		} }
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
	local firstIndex = SafeUiNumber(startIndex, 1) or 1
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
	if scanTooltip and IsFrameForbidden(scanTooltip) then
		scanTooltip = nil
	end
	if scanTooltip then
		return scanTooltip
	end

	local existingTooltip = _G and _G[NAMEPLATE_SCAN_TOOLTIP_NAME] or nil
	if existingTooltip and not IsFrameForbidden(existingTooltip) then
		self.nameplateScanTooltip = existingTooltip
		return existingTooltip
	end

	if type(CreateFrame) ~= "function" then
		return nil
	end

	local parentFrame = UIParent or WorldFrame or nil
	local ok, createdTooltip = pcall(
		CreateFrame,
		"GameTooltip",
		NAMEPLATE_SCAN_TOOLTIP_NAME,
		parentFrame,
		"GameTooltipTemplate"
	)
	if not ok or not createdTooltip or IsFrameForbidden(createdTooltip) then
		return nil
	end

	self.nameplateScanTooltip = createdTooltip
	return createdTooltip
end

function QuestTogether:GetNameplateScanTooltipLineCount(scanTooltip)
	if not scanTooltip or IsFrameForbidden(scanTooltip) or not scanTooltip.NumLines then
		return nil
	end

	local ok, lineCount = pcall(scanTooltip.NumLines, scanTooltip)
	if not ok or self:IsSecretValue(lineCount) then
		return nil
	end

	return SafeUiNumber(lineCount, nil)
end

function QuestTogether:GetNameplateScanTooltipFontString(scanTooltip, lineIndex)
	if not scanTooltip or IsFrameForbidden(scanTooltip) or type(lineIndex) ~= "number" then
		return nil
	end

	local tooltipName = nil
	if scanTooltip.GetName then
		local ok, resolvedName = pcall(scanTooltip.GetName, scanTooltip)
		if ok and not self:IsSecretValue(resolvedName) and IsNonEmptyString(resolvedName) then
			tooltipName = resolvedName
		end
	end
	if not IsNonEmptyString(tooltipName) then
		return nil
	end

	return _G and _G[tooltipName .. "TextLeft" .. tostring(lineIndex)] or nil
end

function QuestTogether:GetNameplateScanTooltipLeftText(scanTooltip, lineIndex)
	local fontString = self:GetNameplateScanTooltipFontString(scanTooltip, lineIndex)
	if not self:CanAccessValue(fontString) or not fontString or IsFrameForbidden(fontString) or not fontString.GetText then
		return nil
	end

	local ok, textValue = pcall(fontString.GetText, fontString)
	if not ok or not self:CanAccessValue(textValue) or type(textValue) ~= "string" then
		return nil
	end

	return textValue
end

function QuestTogether:ReadNameplateScanTooltipLines(scanTooltip, unitToken, unitGuid)
	if not scanTooltip or IsFrameForbidden(scanTooltip) then
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
				local leftText = SafeTrimText(rawText)
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

	if not IsNonEmptyString(unitGuid) then
		unitGuid = self:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	end
	if self:IsSecretValue(unitGuid) then
		return false, false, nil
	end
	if not IsNonEmptyString(unitGuid) then
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
		local isQuestObjective, allObjectivesComplete, hasCompleteData = self:EvaluateTooltipQuestObjectiveLines(tooltipLines)
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
	if not unitFrame or IsFrameForbidden(unitFrame) then
		return false, false, nil
	end

	local unitGuid = self:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	if self:IsSecretValue(unitGuid) then
		unitGuid = nil
	end
	if not IsNonEmptyString(unitGuid) then
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
		if IsNonEmptyString(resolvedUnitGuid or unitGuid) then
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
	if not IsNonEmptyString(expectedUnitGuid) then
		return true, nil
	end
	if not self:IsNameplateUnitToken(unitToken) then
		return false, nil
	end

	local liveUnitGuid = self:GetNameplateUnitGuid(unitToken)
	if self:IsSecretValue(liveUnitGuid) or not IsNonEmptyString(liveUnitGuid) then
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

	local liveUnitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
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
			liveUnitToken, reason or "ResolveNameplateQuestStateForUnitToken", resolvedUnitGuid or unitGuid
		)
		self:ForgetResolvedNameplateQuestState(liveUnitToken)
		self:HideNameplateIcon(namePlateFrameBase)
		if not hasRetryScheduled then
			PrintOneShotNameplateDebug(
				self,
				string.format(
					"debugResolverUnresolved:%s:%s",
					SafeText(liveUnitToken, "<nil>"),
					SafeText(reason or "ResolveNameplateQuestStateForUnitToken", "<nil>")
				),
				string.format(
					"resolver_unresolved unit=%s reason=%s retry=%s",
					SafeText(liveUnitToken, ""),
					SafeText(reason, ""),
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
	if not isQuestObjective or not IsNonEmptyString(resolvedUnitGuid or unitGuid) then
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
	local hasResolvedQuestState, isQuestObjective = self:TryResolveNameplateQuestObjectiveState(unitToken, unitFrame, false)
	if not hasResolvedQuestState then
		return false
	end

	return isQuestObjective
end

function QuestTogether:ShouldShowQuestNameplateIconForResolvedState(unitToken, unitFrame, isQuestObjective)
	if not self:GetOption("nameplateQuestIconEnabled") then
		return false
	end

	return self:ShouldApplyResolvedQuestVisualState(unitToken, unitFrame, isQuestObjective)
end

local function DeferBlockedQuestPlatePresentation(addon, plate, unitToken)
	if not addon:IsWorkBlocked("nameplate_refresh") then
		return false
	end
	addon:HideNameplateIcon(plate)
	if addon.isEnabled and addon:IsNameplateUnitToken(unitToken)
		and not addon.nameplateRefreshPendingByUnitToken[unitToken] then
		addon:ScheduleNameplateRefresh(unitToken)
	end
	return true
end

function QuestTogether:ApplyResolvedQuestStateToNameplate(
	namePlateFrameBase,
	unitToken,
	unitFrame,
	isQuestObjective,
	scheduleTintFollowUp,
	resolvedUnitGuid
)
	if not namePlateFrameBase or not unitFrame then
		return
	end

	local resolvedUnitToken = unitToken
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	end
	if self:IsNameplateUnitToken(resolvedUnitToken) and self:IsNameplateUnitPlayer(resolvedUnitToken) then
		self:RefreshQTPlayerNameplate(namePlateFrameBase, resolvedUnitToken, unitFrame)
		return
	end
	-- Cached NPC relevance can reach this presenter directly from a plate-added
	-- event, without passing through the deferred-work policy. Cleanup is safe
	-- when its owned regions are mutable; layout/show must wait for the same
	-- policy as scheduled presentation, including map and encounter restrictions.
	if DeferBlockedQuestPlatePresentation(self, namePlateFrameBase, resolvedUnitToken) then
		return
	end
	if not IsNonEmptyString(resolvedUnitGuid) and self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitGuid = self:GetNameplateTooltipScanGuid(resolvedUnitToken, unitFrame)
	end

	local shouldShow = self:ShouldShowQuestNameplateIconForResolvedState(resolvedUnitToken, unitFrame, isQuestObjective)
	local icon = self.nameplateIconByUnitFrame[unitFrame]
	if resolvedUnitToken and resolvedUnitGuid then
		self:StoreResolvedNameplateQuestState(resolvedUnitToken, resolvedUnitGuid, isQuestObjective)
	end

	local canScheduleTintFollowUp = scheduleTintFollowUp and IsNonEmptyString(resolvedUnitGuid)
	self:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective, canScheduleTintFollowUp == true)
	if
		canScheduleTintFollowUp
		and isQuestObjective
		and type(resolvedUnitToken) == "string"
		and resolvedUnitToken ~= ""
	then
		self:ScheduleNameplateHealthTintRefresh(resolvedUnitToken, 0.05, true)
	end

	if shouldShow then
		if icon then
			if not self:SetNameplateIconKind(icon, "quest") then
				self:HideNameplateIcon(namePlateFrameBase)
				return
			end
			self:ApplyNameplateQuestIconStyle(icon, unitFrame)
		else
			icon = EnsureQuestIcon(unitFrame)
		end
		if not icon then
			return
		end
		if CanMutateFrame(icon) then
			self:CancelNameplateVisualCleanup(icon)
			icon:Show()
		end
	elseif icon then
		if CanMutateFrame(icon) then
			icon:Hide()
		end
		if isQuestObjective ~= true then
			self:RestoreNameplateHealthColor(unitFrame)
		end
	end
end

function QuestTogether:ShouldApplyResolvedQuestVisualState(unitToken, unitFrame, isQuestObjective)
	if not self.isEnabled then
		return false
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false
	end
	if isQuestObjective ~= true then
		return false
	end

	if not unitFrame then
		return false
	end
	if IsFrameForbidden(unitFrame) then
		return false
	end

	local resolvedUnitToken = unitToken
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitToken = ResolveNameplateUnitToken(nil, unitFrame)
	end
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		return false
	end

	if not GetAccessibleChildFrame(unitFrame, "healthBar") then
		return false
	end

	if not self:DoesNameplateUnitExist(resolvedUnitToken) then
		return false
	end

	-- Never tint players; this is intended for quest mobs/NPCs.
	if self:IsNameplateUnitPlayer(resolvedUnitToken) then
		return false
	end

	-- Plater's quest-color path only suppresses tap-denied hostile units
	-- (local retail Plater.lua:8993-9004). It does not gate quest visuals on
	-- dead or disconnected state, so keep the visual decision aligned here.
	if self:IsNameplateUnitTapDenied(resolvedUnitToken) then
		return false
	end

	return true
end

-- Keep tinting conservative so we do not override important Blizzard states.
function QuestTogether:ShouldApplyQuestHealthTint(frame, isQuestObjective)
	if not self:GetOption("nameplateQuestHealthColorEnabled") then
		return false
	end

	local resolvedUnitToken = ResolveNameplateUnitToken(nil, frame)
	if not resolvedUnitToken then
		return false
	end

	if isQuestObjective ~= nil then
		return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, isQuestObjective)
	end

	local cachedQuestObjective = self.nameplateQuestStateByUnitToken[resolvedUnitToken]
	local cachedUnitGuid = self.nameplateQuestGuidByUnitToken[resolvedUnitToken]
	if cachedQuestObjective ~= nil and IsNonEmptyString(cachedUnitGuid) then
		local hasCachedQuestState, resolvedCachedQuestState =
			self:TryGetReusableCachedNameplateQuestState(resolvedUnitToken, cachedUnitGuid)
		if hasCachedQuestState then
			return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, resolvedCachedQuestState)
		end
	end

	local hasResolvedQuestState, isQuestObjectiveNameplate = self:TryResolveNameplateQuestObjectiveState(
		resolvedUnitToken,
		frame,
		false
	)
	if not hasResolvedQuestState then
		return false
	end

	return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, isQuestObjectiveNameplate)
end

local function GetIconBarAnchor(unitFrame)
	return GetAccessibleChildFrame(unitFrame, "healthBar")
		or GetAccessibleChildFrame(unitFrame, "HealthBarsContainer")
		or unitFrame
end

local function GetPlayerBuffIconAnchor(unitFrame)
	-- Current Retail/Forever buffs grow left from the classification marker.
	-- Empty lists stay shown with a nonzero width, so check visible children,
	-- never aura contents, frame pools, or Blizzard's layout helpers.
	local auras = GetAccessibleChildFrame(unitFrame, "AurasFrame")
	if CallAccessibleFrameMethod(auras, "IsShown") ~= true then
		return nil
	end
	local buffs = GetAccessibleChildFrame(auras, "BuffListFrame")
	if CallAccessibleFrameMethod(buffs, "IsShown") ~= true then
		return nil
	end
	local count = SafeUiNumber(CallAccessibleFrameMethod(buffs, "GetNumChildren"))
	local getChildren = select(1, QuestTogether:GetAccessibleFrameMember(buffs, "GetChildren"))
	-- Blizzard currently displays at most two. Bound work if another layout
	-- changes this container; older/unknown layouts keep the normal bar anchor.
	if not count or count < 1 or count > 8 or count % 1 ~= 0 or type(getChildren) ~= "function" then
		return nil
	end
	local ok, children = pcall(function()
		return { getChildren(buffs) }
	end)
	if not ok then
		return nil
	end
	local occupied, border = false, 2
	local unitScale = SafeUiNumber(CallAccessibleFrameMethod(unitFrame, "GetEffectiveScale"), 0)
	for index = 1, count do
		local child = children[index]
		if QuestTogether:CanAccessValue(child) and CallAccessibleFrameMethod(child, "IsShown") == true then
			occupied = true
			-- Keep a compact gap around the buff artwork, scaled to the logo
			-- parent without reading aura data.
			local childScale = SafeUiNumber(CallAccessibleFrameMethod(child, "GetEffectiveScale"), 0)
			if unitScale > 0 and childScale > 0 then
				border = math.max(border, SafeUiNumber(2 * childScale / unitScale, 2))
			end
		end
	end
	if occupied then
		-- Anchor to the stable list, not a pooled aura child that can be reused.
		return buffs, border + 2
	end
	return nil
end

local function GetNameplateNameTextAnchor(unitFrame)
	local healthBar = GetAccessibleChildFrame(unitFrame, "healthBar")
	return GetAccessibleChildFrame(unitFrame, "unitName")
		or GetAccessibleChildFrame(unitFrame, "name")
		or GetAccessibleChildFrame(healthBar, "unitName")
		or GetAccessibleChildFrame(healthBar, "name")
end

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

	local unitFrameUnitToken = unitFrame
		and select(1, QuestTogether:GetAccessibleFrameMember(unitFrame, "unit"))
		or nil
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

function QuestTogether:SetQTPlayerIconLookingForPartners(iconFrame, looking)
	if not CanMutateFrame(iconFrame) then
		return false
	end
	looking = looking == true
	local glow = iconFrame.qtPartnerGlow
	if looking and self:IsWorkBlocked("nameplate_refresh") then
		return false
	end
	if not glow and not looking then
		iconFrame.qtLookingForPartners = false
		return true
	end
	if not glow then
		glow = {}
		iconFrame.qtPartnerGlow = glow
	end
	-- Offset translucent copies of the transparent logo create a contour glow.
	-- These owned background layers leave the original artwork and anchor alone.
	if looking and not iconFrame.qtPartnerGlowReady then
		for index = 1, 8 do
			if not glow[index] then
				local ok, layer = pcall(iconFrame.CreateTexture, iconFrame, nil, "BACKGROUND")
				if not ok or not CanMutateFrame(layer) then
					return false
				end
				layer:Hide()
				glow[index] = layer
			end
		end
		for _, layer in ipairs(glow) do
			if not CanMutateFrame(layer) then
				return false
			end
		end
		for index, layer in ipairs(glow) do
			local angle = (index - 1) * math.pi / 4
			local x, y = 2 * math.cos(angle), 2 * math.sin(angle)
			layer:SetTexture(self.NAMEPLATE_PLAYER_ICON_TEXTURE)
			layer:SetTexCoord(0, 1, 0, 1)
			layer:SetVertexColor(1, 0.78, 0.12, 0.35)
			layer:SetBlendMode("ADD")
			layer:ClearAllPoints()
			layer:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", x, y)
			layer:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", x, y)
		end
		iconFrame.qtPartnerGlowReady = true
	end
	for _, layer in ipairs(glow) do
		if not CanMutateFrame(layer) then
			return false
		end
	end
	if iconFrame.qtLookingForPartners ~= looking then
		for _, layer in ipairs(glow) do
			if looking then
				layer:Show()
			else
				layer:Hide()
			end
		end
		iconFrame.qtLookingForPartners = looking
	end
	return true
end

function QuestTogether:SetNameplateIconKind(iconFrame, kind)
	if not CanMutateFrame(iconFrame) then
		return false
	end
	local texture = iconFrame.Icon
	if not texture or not CanMutateFrame(texture) then
		return false
	end
	if kind ~= "player" and not self:SetQTPlayerIconLookingForPartners(iconFrame, false) then
		return false
	end
	if iconFrame.qtIconKind == kind then
		return true
	end
	if kind == "player" then
		texture:SetTexture(self.NAMEPLATE_PLAYER_ICON_TEXTURE)
		texture:SetTexCoord(0, 1, 0, 1)
	elseif texture.SetAtlas and self.NAMEPLATE_QUEST_ICON_ATLAS then
		texture:SetAtlas(self.NAMEPLATE_QUEST_ICON_ATLAS, true)
		texture:SetTexCoord(0, 1, 0, 1)
	else
		texture:SetTexture(self.NAMEPLATE_QUEST_ICON_TEXTURE)
		local coords = self.NAMEPLATE_QUEST_ICON_TEX_COORDS
		if coords then
			texture:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
		else
			texture:SetTexCoord(0, 1, 0, 1)
		end
	end
	iconFrame.qtIconKind = kind
	return true
end

function QuestTogether:ApplyNameplateQuestIconStyle(iconFrame, unitFrame)
	if not iconFrame or not unitFrame then
		return
	end
	if not CanMutateFrame(iconFrame) or not self:CanAccessForeignFrame(unitFrame) then
		return
	end

	local icon = iconFrame.Icon or iconFrame
	if not CanMutateFrame(icon) then
		return
	end
	local healthBarsContainer = GetAccessibleChildFrame(unitFrame, "HealthBarsContainer")
	local style = iconFrame.qtIconKind == "player" and self:GetNameplatePlayerIconStyle()
		or self:GetNameplateQuestIconStyle()
	local playerIcon = iconFrame.qtIconKind == "player"
	local gap = playerIcon and 4 or 1
	local width = self.NAMEPLATE_QUEST_ICON_WIDTH
	local height = self.NAMEPLATE_QUEST_ICON_HEIGHT
	local buffAnchor, buffGap
	if playerIcon and style == "left" then
		buffAnchor, buffGap = GetPlayerBuffIconAnchor(unitFrame)
	end

	iconFrame:ClearAllPoints()

	if style == "left" then
		local barAnchor = buffAnchor or GetIconBarAnchor(unitFrame)
		if IsFrameForbidden(barAnchor) then
			barAnchor = unitFrame
		end
		iconFrame:SetPoint("RIGHT", barAnchor, "LEFT", -(buffGap or gap), 0)
	elseif style == "right" then
		local barAnchor = GetIconBarAnchor(unitFrame)
		if IsFrameForbidden(barAnchor) then
			barAnchor = unitFrame
		end
		iconFrame:SetPoint("LEFT", barAnchor, "RIGHT", gap, 0)
	elseif style == "prefix" then
		local nameText = GetNameplateNameTextAnchor(unitFrame)
		if nameText then
			-- Keep the prefix icon large enough to remain legible on live nameplates.
			width = math.max(14, math.floor(width * 0.8 + 0.5))
			height = math.max(14, math.floor(height * 0.8 + 0.5))
			iconFrame:SetPoint("RIGHT", nameText, "LEFT", playerIcon and -4 or -2, 0)
		elseif healthBarsContainer then
			iconFrame:SetPoint("BOTTOM", healthBarsContainer, "TOP", 0, 11)
		else
			iconFrame:SetPoint("TOP", unitFrame, "TOP", 0, 7)
		end
	else
		if healthBarsContainer then
			iconFrame:SetPoint("BOTTOM", healthBarsContainer, "TOP", 0, 11)
		else
			iconFrame:SetPoint("TOP", unitFrame, "TOP", 0, 7)
		end
	end

	iconFrame:SetSize(width, height)
	if icon and icon.SetAllPoints then
		icon:SetAllPoints(iconFrame)
	end
end

function QuestTogether:CreateNameplateQuestIconFrame(unitFrame)
	if not CanMutateFrame(unitFrame) then
		return nil
	end
	local ok, iconFrame = pcall(CreateFrame, "Frame", nil, unitFrame)
	if not ok or not CanMutateFrame(iconFrame) then
		return nil
	end
	return iconFrame
end

EnsureQuestIcon = function(unitFrame, kind)
	kind = kind or "quest"
	if not unitFrame then
		return nil
	end
	if not CanMutateFrame(unitFrame) then
		return nil
	end

	local existingIcon = QuestTogether.nameplateIconByUnitFrame[unitFrame]
	if existingIcon then
		if not QuestTogether:SetNameplateIconKind(existingIcon, kind) then
			return nil
		end
		QuestTogether:ApplyNameplateQuestIconStyle(existingIcon, unitFrame)
		return existingIcon
	end

	local iconFrame = QuestTogether:CreateNameplateQuestIconFrame(unitFrame)
	if not iconFrame or not CanMutateFrame(iconFrame) then
		return nil
	end
	iconFrame:SetFrameStrata(CallAccessibleFrameMethod(unitFrame, "GetFrameStrata") or "LOW")
	iconFrame:SetFrameLevel(SafeUiNumber(CallAccessibleFrameMethod(unitFrame, "GetFrameLevel"), 0) + 30)

	local icon = iconFrame:CreateTexture(nil, "ARTWORK")
	iconFrame.Icon = icon
	QuestTogether.nameplateIconByUnitFrame[unitFrame] = iconFrame

	iconFrame:Hide()
	if not QuestTogether:SetNameplateIconKind(iconFrame, kind) then
		return nil
	end
	QuestTogether:ApplyNameplateQuestIconStyle(iconFrame, unitFrame)

	return iconFrame
end

local function EnsureQuestHealthOverlay(unitFrame)
	local healthBar = GetAccessibleChildFrame(unitFrame, "healthBar")
	if not healthBar then
		return nil
	end
	if not CanMutateFrame(unitFrame) or not CanMutateFrame(healthBar) then
		return nil
	end

	local existingOverlay = QuestTogether.nameplateHealthOverlayByUnitFrame[unitFrame]
	if existingOverlay then
		return existingOverlay
	end

	local fillTexture = QuestTogether:CreateNameplateHealthOverlayTexture(healthBar, "ARTWORK", 0)
	local highlight = healthBar:CreateTexture(nil, "ARTWORK", nil, 1)
	if not fillTexture or not highlight then
		return nil
	end

	local overlay = {
		FillTexture = fillTexture,
		Highlight = highlight,
	}

	if fillTexture.Hide then
		fillTexture:Hide()
	end

	if highlight.SetBlendMode then
		highlight:SetBlendMode("ADD")
	end
	if highlight.Hide then
		highlight:Hide()
	end

	QuestTogether.nameplateHealthOverlayByUnitFrame[unitFrame] = overlay
	return overlay
end

local function AnchorQuestHealthFillTexture(texture, anchorTarget)
	if not texture or not anchorTarget then
		return
	end
	if not CanMutateFrame(texture) or IsFrameForbidden(anchorTarget) then
		return
	end

	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 0, 0)
	texture:SetPoint("BOTTOMLEFT", anchorTarget, "BOTTOMLEFT", 0, 0)
	texture:SetPoint("TOPRIGHT", anchorTarget, "TOPRIGHT", 0, 0)
	texture:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", 0, 0)
end

local function GetQuestHealthOverlayAnchorTarget(unitFrame)
	local healthBar = GetAccessibleChildFrame(unitFrame, "healthBar")
	if not healthBar or not QuestTogether:CanAccessForeignFrame(healthBar, true) then
		return nil
	end

	local liveFillTexture = CallAccessibleFrameMethod(healthBar, "GetStatusBarTexture")
	if not QuestTogether:CanAccessForeignFrame(liveFillTexture, true) then
		return nil
	end
	return liveFillTexture
end

ApplyQuestIconVisual = function(texture)
	if not texture then
		return
	end

	if texture.SetAtlas and QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS then
		texture:SetAtlas(QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS, true)
		texture:SetTexCoord(0, 1, 0, 1)
	else
		texture:SetTexture(QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE)
		local coords = QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS
		if coords then
			texture:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
		else
			texture:SetTexCoord(0, 1, 0, 1)
		end
	end
end

local function ApplyAnnouncementIconVisual(texture, eventType, iconAsset, iconKind)
	if not texture then
		return
	end

	if type(iconAsset) == "string" and iconAsset ~= "" then
		if iconKind == "atlas" and texture.SetAtlas then
			texture:SetAtlas(iconAsset, true)
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end

		texture:SetTexture(iconAsset)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	if QuestTogether.IsWorldQuestAnnouncementType and QuestTogether:IsWorldQuestAnnouncementType(eventType) then
		if texture.SetAtlas then
			texture:SetAtlas("worldquest-icon", true)
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end
	end
	if QuestTogether.IsBonusObjectiveAnnouncementType and QuestTogether:IsBonusObjectiveAnnouncementType(eventType) then
		if texture.SetAtlas then
			texture:SetAtlas("Bonus-Objective-Star", true)
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end
	end

	ApplyQuestIconVisual(texture)
end

local function CreateAnnouncementBubbleFrame(parentFrame)
	-- ChatBubbleTemplate is not guaranteed in all UI states; degrade to a plain frame bubble.
	local ok, bubble = pcall(CreateFrame, "Frame", nil, parentFrame, "ChatBubbleTemplate")
	if ok and bubble then
		return bubble
	end

	local fallbackBubble = CreateFrame("Frame", nil, parentFrame)
	local background = fallbackBubble:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(1, 1, 1, 0.92)
	fallbackBubble.Background = background

	local text = fallbackBubble:CreateFontString(nil, "ARTWORK", "ChatBubbleFont")
	fallbackBubble.String = text
	if text.SetNonSpaceWrap then
		text:SetNonSpaceWrap(true)
	end

	local tail = fallbackBubble:CreateTexture(nil, "ARTWORK")
	fallbackBubble.Tail = tail
	tail:SetColorTexture(1, 1, 1, 0.92)
	tail:SetSize(10, 10)
	tail:SetPoint("TOP", fallbackBubble, "BOTTOM", 0, 4)
	tail:SetRotation(math.rad(45))

	local icon = fallbackBubble:CreateTexture(nil, "ARTWORK")
	fallbackBubble.Icon = icon
	ApplyAnnouncementIconVisual(icon, nil)

	return fallbackBubble
end

local function ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, bubble)
	if not hostFrame or not unitFrame or not bubble then
		return
	end
	if not CanMutateFrame(hostFrame) or not CanMutateFrame(unitFrame) or not CanMutateFrame(bubble) then
		return
	end

	local frameStrata = "LOW"
	local getFrameStrata = select(1, QuestTogether:GetAccessibleFrameMember(hostFrame, "GetFrameStrata"))
	if type(getFrameStrata) == "function" then
		local okStrata, resolvedStrata = pcall(getFrameStrata, hostFrame)
		if okStrata then
			frameStrata = SafeTrimText(resolvedStrata)
			if frameStrata == "" then
				frameStrata = "LOW"
			end
		end
	end

	local frameLevel = 20
	local getFrameLevel = select(1, QuestTogether:GetAccessibleFrameMember(unitFrame, "GetFrameLevel"))
	if type(getFrameLevel) == "function" then
		local okLevel, resolvedLevel = pcall(getFrameLevel, unitFrame)
		if okLevel then
			frameLevel = SafeUiNumber(resolvedLevel, 0) + 20
		end
	end
	bubble:SetFrameStrata(frameStrata)
	bubble:SetFrameLevel(frameLevel)
end

local function EnsureAnnouncementBubble(hostFrame)
	if not CanMutateFrame(hostFrame) then
		return nil
	end

	local unitFrame = GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame or not unitFrame then
		return nil
	end

	local existingBubble = QuestTogether.nameplateBubbleByUnitFrame[unitFrame]
	if existingBubble then
		if not CanMutateFrame(existingBubble) then
			return nil
		end
		-- Blizzard pools UnitFrames independently from the base nameplates.
		-- Our cache follows the UnitFrame; our bubble must follow its new host.
		if CallAccessibleFrameMethod(existingBubble, "GetParent") ~= hostFrame then
			local setParent = select(1, QuestTogether:GetAccessibleFrameMember(existingBubble, "SetParent"))
			if type(setParent) ~= "function" then
				return nil
			end
			local ok = pcall(setParent, existingBubble, hostFrame)
			if not ok or not CanMutateFrame(existingBubble) then
				return nil
			end
		end
		ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, existingBubble)
		return existingBubble
	end

	local bubble = CreateAnnouncementBubbleFrame(hostFrame)
	if not bubble or not bubble.String then
		return nil
	end
	if not CanMutateFrame(bubble) or not CanMutateFrame(bubble.String) then
		return nil
	end

	ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, bubble)
	bubble:SetAlpha(0)
	bubble:Hide()

	bubble:ClearAllPoints()

	bubble.String:ClearAllPoints()
	bubble.String:SetJustifyH("LEFT")
	bubble.String:SetJustifyV("MIDDLE")
	bubble.String:SetTextColor(1, 0.82, 0, 1)
	if bubble.String.SetNonSpaceWrap then
		bubble.String:SetNonSpaceWrap(true)
	end
	if bubble.String.SetSpacing then
		bubble.String:SetSpacing(1)
	end

	if not bubble.Icon then
		local icon = bubble:CreateTexture(nil, "ARTWORK", nil, 1)
		bubble.Icon = icon
	end
	ApplyAnnouncementIconVisual(bubble.Icon, nil)

	if bubble.Tail then
		bubble.Tail:ClearAllPoints()
		bubble.Tail:SetPoint("TOP", bubble, "BOTTOM", 0, 6)
	end

	local animationGroup = bubble:CreateAnimationGroup()
	local fadeIn = animationGroup:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetDuration(ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS)
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)

	local hold = animationGroup:CreateAnimation("Alpha")
	hold:SetOrder(2)
	local lifetimeSeconds = SafeUiNumber(GetAnnouncementBubbleLifetimeSeconds(), QuestTogether.DEFAULTS.profile.chatBubbleDuration)
	hold:SetDuration(
		math.max(
			0,
			lifetimeSeconds - ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS - ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS
		)
	)
	hold:SetFromAlpha(1)
	hold:SetToAlpha(1)

	local fadeOut = animationGroup:CreateAnimation("Alpha")
	fadeOut:SetOrder(3)
	fadeOut:SetDuration(ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS)
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)

	animationGroup:SetScript("OnFinished", function()
		QuestTogether:CompleteAnnouncementBubblePlayback(bubble)
	end)
	animationGroup:SetScript("OnStop", function()
		QuestTogether:CompleteAnnouncementBubblePlayback(bubble)
	end)
	bubble.animationGroup = animationGroup
	bubble.fadeInAnimation = fadeIn
	bubble.holdAnimation = hold
	bubble.fadeOutAnimation = fadeOut

	QuestTogether.nameplateBubbleByUnitFrame[unitFrame] = bubble
	return bubble
end

function QuestTogether:HideAnnouncementBubble(hostFrame)
	local unitFrame = GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame or not unitFrame then
		return
	end

	local bubble = self.nameplateBubbleByUnitFrame[unitFrame]
	if not bubble then
		return
	end
	self:StopAndHideAnnouncementBubblePlayback(bubble)
end

function QuestTogether:ClearIgnoredAnnouncementBubbles()
	local discarded = 0
	for bubble, state in pairs(self.nameplateBubbleStateByFrame or {}) do
		if state.unitToken ~= "player" and IsNonEmptyString(state.senderName)
			and self:IsIgnoredPlayerName(state.senderName) then
			discarded = discarded + 1
			-- The copied sender identity is addon-owned. Never resolve the old
			-- nameplate just to discard playback after its sender is ignored.
			if self:StopAndHideAnnouncementBubblePlayback(bubble, "ignored") then
				self:CancelNameplateVisualCleanup(bubble)
			else
				-- Stop already removed replayable data, even when the attached
				-- visual is forbidden or restricted. Finish hiding it when safe.
				local nameplateState = self:GetNameplateStateStore()
				nameplateState.pendingVisualCleanupByFrame = nameplateState.pendingVisualCleanupByFrame or {}
				nameplateState.pendingVisualCleanupByFrame[bubble] = "bubble"
				self.pendingNameplateVisualCleanup = true
			end
		end
	end
	return discarded
end

function QuestTogether:RefreshActiveAnnouncementBubbles()
	for unitFrame, bubble in pairs(self.nameplateBubbleByUnitFrame) do
		local bubbleState = GetAnnouncementBubbleState(bubble)
		local unitToken = bubbleState and bubbleState.unitToken or nil
		if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(unitToken) then
			if bubbleState then
				if bubbleState.text then
					self:Debugf("bubble", "playback_discard unit=%s reason=restricted", SafeText(unitToken, ""))
				end
				-- Discard replayable data immediately; the addon-owned side tables
				-- are safe even when the attached visual cannot be touched yet.
				SetAnnouncementBubbleState(bubble, { unitToken = unitToken })
			end
		else
			local shouldHide = not self.isEnabled
				or not self:GetOption("showChatBubbles")
				or not bubbleState
				or not IsNonEmptyString(bubbleState.text)
				or (unitToken == "player" and self:GetOption("hideMyOwnChatBubbles"))
			if not shouldHide and bubbleState and bubbleState.senderName and self.ShouldShowAnnouncementsForRemoteSender then
				shouldHide = not self:ShouldShowAnnouncementsForRemoteSender(bubbleState.senderName, true)
			end
			if not shouldHide and bubbleState then
				local hostFrame = unitToken and self:GetAnnouncementBubbleHostFrameForUnit(unitToken) or nil
				shouldHide = not hostFrame or GetAnnouncementBubbleUnitFrame(hostFrame) ~= unitFrame
				if not shouldHide and unitToken ~= "player" then
					shouldHide = not self:CanAccessForeignFrame(hostFrame, true)
						or not bubbleState.unitGUID
						or self:GetNameplateUnitGuid(unitToken) ~= bubbleState.unitGUID
				end
			end
			if not shouldHide then
				-- A settings/context refresh is never a new announcement. A stopped
				-- animation or a lost completion callback must not replay old text.
				shouldHide = not (bubble.animationGroup and bubble.animationGroup:IsPlaying())
			end
			if shouldHide then
				self:StopAndHideAnnouncementBubblePlayback(bubble, "refresh_policy_identity_or_finished")
			end
		end
	end
end

function QuestTogether:GetAnnouncementBubbleHostFrameForUnit(unitToken)
	if unitToken == "player" then
		return GetAnnouncementBubbleScreenHostFrame()
	end

	local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
	return namePlateFrameBase
end

function QuestTogether:TryShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
	local hostFrame = self:GetAnnouncementBubbleHostFrameForUnit(unitToken)
	if hostFrame then
		if not self:ShowAnnouncementBubbleOnNameplate(hostFrame, text, eventType, iconAsset, iconKind) then
			self:Debugf("bubble", "Failed to show bubble on host for unit=%s", SafeText(unitToken, ""))
			return false, L("Unable to show a bubble on that nameplate.")
		end
		local unitName = self:GetUnitFullName(unitToken)
		return true, unitName or unitToken
	end

	if unitToken ~= "player" then
		return false, L("No visible nameplate found for that unit.")
	end
	return false, L("Your personal bubble anchor is unavailable.")
end

function QuestTogether:ShowAnnouncementBubbleOnNameplate(namePlateFrameBase, text, eventType, iconAsset, iconKind, senderName)
	local isPersonalBubble = namePlateFrameBase == self.announcementBubbleScreenHostFrame
	local normalizedSenderName = not isPersonalBubble and self:NormalizeMemberName(senderName) or nil
	if normalizedSenderName and self:IsIgnoredPlayerName(normalizedSenderName) then
		return false
	end
	local policyUnitToken = isPersonalBubble and "player" or "nameplate"
	if not self.isEnabled or not self:GetOption("showChatBubbles") then
		self:Debug("show_suppressed reason=bubbles_disabled", "bubble")
		return false
	end
	if isPersonalBubble and self:GetOption("hideMyOwnChatBubbles") then
		self:Debug("show_suppressed unit=player reason=hide_own", "bubble")
		return false
	end
	if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(policyUnitToken) then
		self:Debugf("bubble", "show_suppressed unit=%s reason=restricted", policyUnitToken)
		return false
	end

	local unitFrame = GetAnnouncementBubbleUnitFrame(namePlateFrameBase)
	if not namePlateFrameBase or not unitFrame then
		return false
	end
	if not CanMutateFrame(namePlateFrameBase) or not CanMutateFrame(unitFrame) then
		return false
	end
	local message = SafeTrimText(text)
	if message == "" then
		return false
	end

	local bubble = EnsureAnnouncementBubble(namePlateFrameBase)
	if not bubble or not bubble.String then
		self:Debug("Failed to create or resolve bubble frame", "bubble")
		return false
	end
	if not CanMutateFrame(bubble) or not CanMutateFrame(bubble.String) then
		return false
	end

	local bubbleUnitToken = nil
	if isPersonalBubble then
		bubbleUnitToken = "player"
	else
		bubbleUnitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	end
	if not IsNonEmptyString(bubbleUnitToken) then
		return false
	end
	local bubbleUnitGUID = not isPersonalBubble and self:GetNameplateUnitGuid(bubbleUnitToken) or nil
	if not isPersonalBubble and not bubbleUnitGUID then
		return false
	end
	if bubble.animationGroup and bubble.animationGroup:IsPlaying() then
		bubble.animationGroup:Stop()
	end

	local anchorFrame, anchorReadable = self:GetAccessibleFrameMember(unitFrame, "HealthBarsContainer")
	if not anchorReadable then
		return false
	end
	anchorFrame = anchorFrame or unitFrame
	if not self:CanAccessForeignFrame(anchorFrame) then
		anchorFrame = unitFrame
	end
	if not self:CanAccessForeignFrame(anchorFrame) then
		return false
	end
	local visualConfig = GetAnnouncementBubbleVisualConfig()
	local inset = SafeUiNumber(visualConfig.inset, 16)
	local minTextWidth = SafeUiNumber(visualConfig.minTextWidth, 48)
	local maxTextWidth = SafeUiNumber(visualConfig.maxTextWidth, 220)
	local iconSize = SafeUiNumber(visualConfig.iconSize, 18)
	local iconGap = SafeUiNumber(visualConfig.iconGap, 8)
	local fontSize = SafeUiNumber(visualConfig.fontSize, 14)
	local lifetimeSeconds = SafeUiNumber(GetAnnouncementBubbleLifetimeSeconds(), QuestTogether.DEFAULTS.profile.chatBubbleDuration)

	if bubble.holdAnimation then
		local holdSeconds = math.max(
			0,
			lifetimeSeconds - ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS - ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS
		)
		bubble.holdAnimation:SetDuration(holdSeconds)
	end

	local fontPath, _, fontFlags = bubble.String:GetFont()
	if fontPath and bubble.String.SetFont then
		bubble.String:SetFont(fontPath, fontSize, fontFlags)
	end

	bubble.String:SetWidth(maxTextWidth)
	bubble.String:SetText(message)

	local measuredUnboundedWidth = nil
	if bubble.String.GetUnboundedStringWidth then
		local okWidth, widthValue = pcall(bubble.String.GetUnboundedStringWidth, bubble.String)
		if okWidth then
			measuredUnboundedWidth = SafeUiNumber(widthValue, nil)
		end
	end
	local unboundedWidth = measuredUnboundedWidth
		or EstimateBubbleTextWidth(message, fontSize, minTextWidth, maxTextWidth)
	local targetTextWidth = math.min(
		maxTextWidth,
		math.max(minTextWidth, unboundedWidth)
	)
	bubble.String:SetWidth(targetTextWidth)

	local measuredTextHeight = nil
	if bubble.String.GetStringHeight then
		local okHeight, textHeightValue = pcall(bubble.String.GetStringHeight, bubble.String)
		if okHeight then
			measuredTextHeight = SafeUiNumber(textHeightValue, nil)
		end
	end
	local textHeight = measuredTextHeight
		or EstimateBubbleTextHeight(message, targetTextWidth, fontSize)
	local contentHeight = math.max(iconSize, textHeight)
	local contentWidth = iconSize + iconGap + targetTextWidth
	local bubbleWidth = contentWidth + (inset * 2)
	local bubbleHeight = contentHeight + (inset * 2)
	bubble:ClearAllPoints()
	bubble:SetPoint("BOTTOM", anchorFrame, "TOP", 0, ANNOUNCEMENT_BUBBLE_Y_OFFSET)
	bubble:SetSize(bubbleWidth, bubbleHeight)

	if bubble.Icon then
		ApplyAnnouncementIconVisual(bubble.Icon, eventType, iconAsset, iconKind)
		bubble.Icon:ClearAllPoints()
		bubble.Icon:SetSize(iconSize, iconSize)
		bubble.Icon:SetPoint("CENTER", bubble, "CENTER", -((iconGap + targetTextWidth) / 2), 0)
		bubble.Icon:Show()
	end

	bubble.String:ClearAllPoints()
	bubble.String:SetWidth(targetTextWidth)
	bubble.String:SetPoint("CENTER", bubble, "CENTER", ((iconSize + iconGap) / 2), 0)

	if bubble.SetClampRectInsets then
		bubble:SetClampRectInsets(0, 0, 0, 0)
	end

	SetAnnouncementBubbleState(bubble, {
		text = message,
		eventType = type(eventType) == "string" and eventType ~= "" and eventType or nil,
		iconAsset = type(iconAsset) == "string" and iconAsset ~= "" and iconAsset or nil,
		iconKind = type(iconKind) == "string" and iconKind ~= "" and iconKind or nil,
		unitToken = bubbleUnitToken,
		unitGUID = bubbleUnitGUID,
		senderName = normalizedSenderName,
	})
	bubble:SetAlpha(0)
	self:CancelNameplateVisualCleanup(bubble)
	bubble:Show()
	if bubble.Tail then
		bubble.Tail:Show()
	end
	if bubble.animationGroup then
		bubble.animationGroup:Play()
	end
	self:Debugf("bubble", "playback_start unit=%s guid=%s event=%s duration=%.1f text=%s",
		bubbleUnitToken, SafeText(bubbleUnitGUID, ""), SafeText(eventType, ""), lifetimeSeconds, message)
	return true
end

function QuestTogether:ShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
	if type(unitToken) ~= "string" or unitToken == "" then
		return false, L("No unit token was provided.")
	end
	if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(unitToken) then
		return false, L("Announcement bubbles are unavailable in the current context.")
	end

	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
		if unitToken ~= "player" then
			return false, L("Nameplates are unavailable.")
		end
	end

	return self:TryShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
end

function QuestTogether:ShowAnnouncementBubbleOnRandomVisiblePlayer(text)
	if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext("nameplate") then
		return false, L("Announcement bubbles are unavailable in the current context.")
	end

	local candidateNameplates = {}

	self:ForEachVisibleNamePlate(function(frame)
		local unitFrame, memberReadable = self:GetAccessibleFrameMember(frame, "UnitFrame")
		if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
			return
		end

		local unitToken = ResolveNameplateUnitToken(frame, unitFrame)
		if not unitToken or not self:IsNameplateUnitToken(unitToken) then
			return
		end
		if not self:IsNameplateUnitPlayer(unitToken) then
			return
		end
		if self.API.UnitIsUnit and self.API.UnitIsUnit(unitToken, "player") then
			return
		end

		candidateNameplates[#candidateNameplates + 1] = frame
	end)

	if #candidateNameplates == 0 then
		return false, L("No visible player nameplates found.")
	end

	local randomIndex = self.API.Random(1, #candidateNameplates)
	local namePlateFrameBase = candidateNameplates[randomIndex]
	if not self:ShowAnnouncementBubbleOnNameplate(namePlateFrameBase, text) then
		return false, L("Unable to show a bubble on the selected nameplate.")
	end

	local unitFrame = select(1, self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame"))
	local unitToken = unitFrame and ResolveNameplateUnitToken(namePlateFrameBase, unitFrame) or nil
	local unitName = unitToken and self:GetUnitFullName(unitToken) or nil
	return true, unitName or L("Unknown")
end

function QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	if not unitFrame then
		return false
	end
	local healthBar = GetAccessibleChildFrame(unitFrame, "healthBar")
	if not healthBar or not CanMutateFrame(unitFrame) or not CanMutateFrame(healthBar) then
		return false
	end

	local overlay = EnsureQuestHealthOverlay(unitFrame)
	if not overlay then
		return false
	end

	local color = self:GetNameplateQuestHealthColor()
	local highlightRed = math.min(1, color.r + 0.18)
	local highlightGreen = math.min(1, color.g + 0.18)
	local highlightBlue = math.min(1, color.b + 0.12)
	local anchorTarget = GetQuestHealthOverlayAnchorTarget(unitFrame)
	if not anchorTarget then
		self:RestoreNameplateHealthColor(unitFrame)
		return false
	end
	AnchorQuestHealthFillTexture(overlay.FillTexture, anchorTarget)
	AnchorQuestHealthFillTexture(overlay.Highlight, anchorTarget)

	if overlay.FillTexture then
		if overlay.FillTexture.SetVertexColor and CanMutateFrame(overlay.FillTexture) then
			overlay.FillTexture:SetVertexColor(color.r, color.g, color.b, 1)
		end
		if CanMutateFrame(overlay.FillTexture) then
			self:CancelNameplateVisualCleanup(overlay.FillTexture)
			overlay.FillTexture:Show()
		end
	end
	if overlay.Highlight and CanMutateFrame(overlay.Highlight) then
		overlay.Highlight:SetColorTexture(highlightRed, highlightGreen, highlightBlue, 0.14)
		self:CancelNameplateVisualCleanup(overlay.Highlight)
		overlay.Highlight:Show()
	end

	if healthBar then
		local alpha = SafeUiNumber(CallAccessibleFrameMethod(healthBar, "GetAlpha"), 1)
		if overlay.FillTexture and overlay.FillTexture.SetAlpha and CanMutateFrame(overlay.FillTexture) then
			overlay.FillTexture:SetAlpha(alpha)
		end
		if overlay.Highlight and overlay.Highlight.SetAlpha and CanMutateFrame(overlay.Highlight) then
			overlay.Highlight:SetAlpha(alpha)
		end
	end

	return true
end

function QuestTogether:RestoreNameplateHealthColor(unitFrame)
	if not unitFrame then
		return
	end
	if IsFrameForbidden(unitFrame) then
		return
	end

	local overlay = self.nameplateHealthOverlayByUnitFrame[unitFrame]
	if overlay then
		if overlay.FillTexture and overlay.FillTexture.Hide and CanMutateFrame(overlay.FillTexture) then
			overlay.FillTexture:Hide()
		end
		if overlay.Highlight and overlay.Highlight.Hide and CanMutateFrame(overlay.Highlight) then
			overlay.Highlight:Hide()
		end
	end
end

function QuestTogether:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective, retryOnFailure)
	if not self:CanAccessForeignFrame(namePlateFrameBase) then
		return
	end
	local unitFrame, memberReadable = self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame")
	if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
		return
	end

	local unitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	local shouldTint = self:ShouldApplyQuestHealthTint(unitFrame, isQuestObjective)
	if shouldTint then
		local applied = self:ApplyQuestTintToNameplate(unitFrame)
		if not applied and retryOnFailure ~= false and type(unitToken) == "string" and unitToken ~= "" then
			self:ScheduleNameplateHealthTintRefresh(unitToken, 0.05, true)
		end
	else
		self:RestoreNameplateHealthColor(unitFrame)
	end
end

function QuestTogether:ScheduleNameplateHealthTintRefresh(unitToken, delaySeconds, _preferCachedQuestState)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local function refreshTint()
		local namePlateFrameBase, unitFrame = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
		if not namePlateFrameBase or not unitFrame then
			return
		end

		local liveUnitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
		if not liveUnitToken then
			self:ForgetResolvedNameplateQuestState(unitToken)
			self:RestoreNameplateHealthColor(unitFrame)
			return
		end

		if liveUnitToken ~= unitToken then
			self:ForgetResolvedNameplateQuestState(unitToken)
		end
		if self:IsNameplateUnitPlayer(liveUnitToken) then
			self:RefreshQTPlayerNameplate(namePlateFrameBase, liveUnitToken, unitFrame)
			return
		end

		local hasResolvedQuestState, isQuestObjective, unitGuid = self:TryResolveNameplateQuestObjectiveState(
			liveUnitToken,
			unitFrame,
			false
		)
		if not hasResolvedQuestState then
			self:ForgetResolvedNameplateQuestState(liveUnitToken)
			self:HideNameplateIcon(namePlateFrameBase)
			if self.ScheduleNameplateTooltipResolution then
				self:ScheduleNameplateTooltipResolution(liveUnitToken, self:GetNameplateTooltipScanGuid(liveUnitToken, unitFrame), 0, "ScheduleNameplateHealthTintRefresh")
			end
			return
		end

		-- Both visuals follow the same result. Health/threat events may be the
		-- first opportunity to repair a newly visible plate's missing icon.
		self:ApplyResolvedQuestStateToNameplate(namePlateFrameBase, liveUnitToken, unitFrame, isQuestObjective, false, unitGuid)
	end

	if self.ScheduleDeferredWork then
		self:ScheduleDeferredWork("nameplate_tint_refresh", unitToken, refreshTint, delaySeconds, "ScheduleNameplateHealthTintRefresh")
		return
	end

	refreshTint()
end

function QuestTogether:ScheduleNameplateRefresh(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local delayFn = self.API and self.API.Delay
	local generations = self.nameplateRefreshGenerationByUnitToken
	local generation = (self.nameplateRefreshGenerationByUnitToken[unitToken] or 0) + 1
	self.nameplateRefreshGenerationByUnitToken[unitToken] = generation
	self.nameplateRefreshPendingByUnitToken[unitToken] = true

	-- Give Blizzard one frame to finish building/restyling the plate. The
	-- generation check also cancels work for removed or recycled unit tokens.
	local function refreshScheduledNameplate()
		if self.nameplateRefreshGenerationByUnitToken ~= generations
			or generations[unitToken] ~= generation then
			return
		end
		self.nameplateRefreshPendingByUnitToken[unitToken] = nil
		if not self.isEnabled then
			return
		end
		if self.IsWorkBlocked and self:IsWorkBlocked("nameplate_refresh") then
			self:ScheduleDeferredWork("nameplate_refresh", unitToken, refreshScheduledNameplate, 0, "ScheduleNameplateRefresh")
			return
		end

		local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
		if not namePlateFrameBase then
			self:MaybeScheduleNameplateTooltipRetry(unitToken, "ScheduleNameplateRefresh")
			return
		end

		self:RefreshNameplateIcon(namePlateFrameBase)
	end

	if type(delayFn) ~= "function" then
		refreshScheduledNameplate()
		return
	end

	delayFn(0, function()
		refreshScheduledNameplate()
	end)
end

function QuestTogether:HideQTPlayerIcon(icon)
	if self.qtPlayerIconStateByFrame then
		self.qtPlayerIconStateByFrame[icon] = nil
	end
	if CanMutateFrame(icon) then
		icon:Hide()
		self:CancelNameplateVisualCleanup(icon)
	else
		local state = self:GetNameplateStateStore()
		state.pendingVisualCleanupByFrame = state.pendingVisualCleanupByFrame or {}
		state.pendingVisualCleanupByFrame[icon] = "icon"
		self.pendingNameplateVisualCleanup = true
	end
end

function QuestTogether:RefreshQTPlayerPlatePresence()
	for icon, info in pairs(self.qtPlayerIconStateByFrame or {}) do
		if not self:ShouldShowQTPlayerLogoForName(info.name) then
			self:HideQTPlayerIcon(icon)
		end
	end
	if self.isEnabled and self.nameplateRegisteredEvents and self.nameplateRegisteredEvents.NAME_PLATE_UNIT_ADDED then
		self:ScheduleNameplatePresentationRefresh("QT player presence", 0)
	end
end

function QuestTogether:RefreshQTPlayerPartnerIndicators()
	if not self.isEnabled then
		return false
	end
	local scheduled = false
	for _, info in pairs(self.qtPlayerIconStateByFrame or {}) do
		local looking = self:IsPlayerLookingForQuestPartners(info.name) == true
		if
			(info.partnerIndicatorPending == true or (info.lookingForPartners == true) ~= looking)
			and self:IsNameplateUnitToken(info.unitToken)
			and not self.nameplateRefreshPendingByUnitToken[info.unitToken]
		then
			self:ScheduleNameplateRefresh(info.unitToken)
			scheduled = true
		end
	end
	return scheduled
end

function QuestTogether:GetFriendlyPlayerNameplateVisibility()
	local getter = self.API and self.API.GetCVar
	if not self:CanAccessValue(getter) or type(getter) ~= "function" then
		return nil
	end
	-- Retail/Forever use the player-specific CVar. An explicit modern value
	-- takes precedence; only an absent key permits the older client fallback.
	for _, key in ipairs({ "nameplateShowFriendlyPlayers", "nameplateShowFriends" }) do
		local ok, value, readable = pcall(getter, key)
		if
			not ok
			or not self:CanAccessValue(value)
			or not self:CanAccessValue(readable)
			or (readable ~= nil and readable ~= true)
		then
			return nil, key
		end
		if value ~= nil then
			if value == "1" then
				return true, key
			end
			if value == "0" then
				return false, key
			end
			return nil, key
		end
	end
	return nil
end

function QuestTogether:RefreshQTPlayerNameplate(plate, unitToken, unitFrame)
	local icon = self.nameplateIconByUnitFrame[unitFrame]
	self:ForgetResolvedNameplateQuestState(unitToken)
	self:ClearNameplateTooltipResolveRetryCount(unitToken)
	-- Only restore an old quest overlay; the player path never creates a tint.
	self:RestoreNameplateHealthColor(unitFrame)
	-- Direct plate-added and presentation calls do not pass through the work
	-- scheduler. Apply its policy before creating or laying out a player icon;
	-- safe stale-visual cleanup remains allowed while presentation is deferred.
	if self:IsWorkBlocked("nameplate_refresh") then
		if icon then
			self:HideQTPlayerIcon(icon)
		end
		if self.isEnabled then
			self:ScheduleNameplateRefresh(unitToken)
		end
		return false
	end
	local show, name, guid = false, nil, nil
	if
		self.isEnabled
		and self:GetOption("nameplatePlayerIconEnabled") == true
		and not self:IsNameplateAugmentationBlockedInCurrentContext()
		and self:CanAccessForeignFrame(plate, true)
		and self:CanAccessForeignFrame(unitFrame)
		and self:GetFriendlyPlayerNameplateVisibility() == true
	then
		show, name = self:IsFriendlyQTPlayerUnit(unitToken)
		if show then
			guid = self:GetNameplateUnitGuid(unitToken)
			show = IsNonEmptyString(guid)
		end
	end
	if not show then
		if icon then
			self:HideQTPlayerIcon(icon)
		end
		return false
	end
	if not CanMutateFrame(unitFrame) or (icon and not CanMutateFrame(icon)) then
		if icon then
			self:HideQTPlayerIcon(icon)
		end
		return false
	end
	local readyIcon = EnsureQuestIcon(unitFrame, "player")
	if not readyIcon then
		if icon then self:HideQTPlayerIcon(icon) end
		return false
	end
	icon = readyIcon
	local lookingForPartners = self:IsPlayerLookingForQuestPartners(name) == true
	self.qtPlayerIconStateByFrame = self.qtPlayerIconStateByFrame or setmetatable({}, { __mode = "k" })
	local info = { name = name, unitToken = unitToken, guid = guid, lookingForPartners = lookingForPartners }
	if not self:SetQTPlayerIconLookingForPartners(icon, lookingForPartners) then
		self:HideQTPlayerIcon(icon)
		-- A quarantined child can recover while its plate stays visible. Keep
		-- only owned identity/retry state so the normal presence prune retries
		-- presentation; removal and disable still discard this record.
		info.lookingForPartners, info.partnerIndicatorPending = false, true
		self.qtPlayerIconStateByFrame[icon] = info
		return false
	end
	self.qtPlayerIconStateByFrame[icon] = info
	self:CancelNameplateVisualCleanup(icon)
	icon:Show()
	return true
end

function QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
	if not self:CanAccessForeignFrame(namePlateFrameBase) then
		return
	end
	local unitFrame, memberReadable = self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame")
	if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
		return
	end
	local unitToken = ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	if self:IsNameplateUnitToken(unitToken) and self:IsNameplateUnitPlayer(unitToken) then
		self:RefreshQTPlayerNameplate(namePlateFrameBase, unitToken, unitFrame)
		return
	end
	-- Defer before resolving negative caches or spending a tooltip retry. A
	-- presentation refresh advances the token generation and would invalidate
	-- a retry queued immediately before it. Resume discovery after restrictions.
	if DeferBlockedQuestPlatePresentation(self, namePlateFrameBase, unitToken) then
		return
	end
	local existing = self.nameplateIconByUnitFrame[unitFrame]
	if existing and self.qtPlayerIconStateByFrame then
		self.qtPlayerIconStateByFrame[existing] = nil
	end
	local hasResolvedQuestState, isQuestObjective, resolvedUnitGuid =
		self:TryResolveNameplateQuestObjectiveState(unitToken, unitFrame, false)
	if not hasResolvedQuestState then
		self:ForgetResolvedNameplateQuestState(unitToken)
		self:HideNameplateIcon(namePlateFrameBase)
		if self.ScheduleNameplateTooltipResolution then
			self:ScheduleNameplateTooltipResolution(
				unitToken,
				self:GetNameplateTooltipScanGuid(unitToken, unitFrame),
				0,
				"RefreshNameplateIcon"
			)
		end
		return
	end
	if isQuestObjective then
		self:ClearNameplateTooltipResolveRetryCount(unitToken)
	else
		-- Keep the negative fallback, but let fresh tooltip evidence reveal a
		-- newly relevant quest or unfinished party objective. Retries stay bounded.
		self:MaybeScheduleNameplateTooltipRetry(unitToken, "RefreshNameplateIcon", resolvedUnitGuid)
	end

	self:ApplyResolvedQuestStateToNameplate(
		namePlateFrameBase,
		unitToken,
		unitFrame,
		isQuestObjective,
		true,
		resolvedUnitGuid
	)
end

function QuestTogether:HideNameplateIcon(namePlateFrameBase)
	if not self:CanAccessForeignFrame(namePlateFrameBase) then
		return
	end
	local unitFrame, memberReadable = self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame")
	if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
		return
	end

	local icon = self.nameplateIconByUnitFrame[unitFrame]
	if icon and CanMutateFrame(icon) then
		icon:Hide()
	end
	self:RestoreNameplateHealthColor(unitFrame)
end

function QuestTogether:HideTapDeniedNameplateVisuals(unitToken)
	if self:IsNameplateUnitToken(unitToken) and self:IsNameplateUnitPlayer(unitToken) then return end
	if not self:IsNameplateUnitToken(unitToken) or not self:IsNameplateUnitTapDenied(unitToken) then
		return
	end

	-- Tap ownership can change after quest detection and while combat defers
	-- normal plate refreshes. Hide our existing visuals without a tooltip scan
	-- or layout work; HideNameplateIcon guards forbidden/protected objects.
	local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, false)
	if namePlateFrameBase then
		self:HideNameplateIcon(namePlateFrameBase)
	end
end

function QuestTogether:RefreshNameplateForUnitAlias(unitAlias)
	local unitGuid = self:GetNameplateUnitGuid(unitAlias)
	if not IsNonEmptyString(unitGuid) then
		return
	end

	self:ForEachVisibleNamePlate(function(frame)
		local unitFrame = GetAccessibleChildFrame(frame, "UnitFrame")
		local unitToken = ResolveNameplateUnitToken(frame, unitFrame)
		if self:IsNameplateUnitToken(unitToken) and self:GetNameplateUnitGuid(unitToken) == unitGuid then
			self:ClearNameplateTooltipResolveRetryCount(unitToken)
			self:ScheduleNameplateRefresh(unitToken)
		end
	end)
end

function QuestTogether:ForEachVisibleNamePlate(callback)
	if type(callback) ~= "function" or not (self.API and type(self.API.GetNamePlates) == "function") then
		return
	end

	local nameplates = self.API.GetNamePlates()
	if not self:CanAccessTable(nameplates) then
		return
	end

	for _, frame in pairs(nameplates) do
		if self:CanAccessForeignFrame(frame) then
			callback(frame)
		end
	end
end

function QuestTogether:FindVisiblePlayerNameplateForSender(senderGUID, senderName)
	if self.IsWorkBlocked and self:IsWorkBlocked("foreign_frame_mutation") then
		return nil
	end

	local normalizedSenderName = self:NormalizeMemberName(senderName)
	local matchedFrame = nil

	self:ForEachVisibleNamePlate(function(frame)
		if matchedFrame or not frame then
			return
		end
		local unitFrame, memberReadable = self:GetAccessibleFrameMember(frame, "UnitFrame")
		if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
			return
		end

		local unitToken = ResolveNameplateUnitToken(frame, unitFrame)
		if not unitToken or not self:IsNameplateUnitToken(unitToken) then
			return
		end
		if not self:IsNameplateUnitPlayer(unitToken) then
			return
		end

		local unitGUID = self:GetNameplateUnitGuid(unitToken)
		local fullUnitName = self:GetUnitFullName(unitToken)
		local normalizedUnitName = fullUnitName and self:NormalizeMemberName(fullUnitName) or nil

		if self:DoesResolvedUnitIdentityMatchSender(unitGUID, normalizedUnitName, senderGUID, normalizedSenderName) then
			matchedFrame = frame
			return
		end
	end)

	return matchedFrame
end

function QuestTogether:DoesResolvedUnitIdentityMatchSender(unitGUID, normalizedUnitName, senderGUID, normalizedSenderName)
	local hasUnitGUID = type(unitGUID) == "string" and unitGUID ~= ""
	local hasSenderGUID = type(senderGUID) == "string" and senderGUID ~= ""

	-- If both sides expose a GUID, a mismatch is definitive. Falling back to the
	-- name here can attach an announcement to an unrelated recycled nameplate.
	if hasUnitGUID and hasSenderGUID and unitGUID ~= senderGUID then
		return false
	end

	if normalizedSenderName then
		return normalizedUnitName ~= nil and normalizedUnitName == normalizedSenderName
	end

	return hasUnitGUID and hasSenderGUID and unitGUID == senderGUID
end

function QuestTogether:DoesUnitTokenMatchSender(unitToken, senderGUID, senderName)
	if type(unitToken) ~= "string" or unitToken == "" then
		return false
	end
	if not self.API.UnitExists or not self.API.UnitExists(unitToken) then
		return false
	end
	if not self:IsNameplateUnitPlayer(unitToken) then
		return false
	end

	local unitGUID = nil
	if self.API.UnitGUID then
		local okGuid, guidValue = pcall(self.API.UnitGUID, unitToken)
		if okGuid and not self:IsSecretValue(guidValue) then
			unitGUID = guidValue
		end
	end
	local normalizedSenderName = self:NormalizeMemberName(senderName)

	local fullUnitName = self:GetUnitFullName(unitToken)

	local normalizedUnitName = fullUnitName and self:NormalizeMemberName(fullUnitName) or nil
	return self:DoesResolvedUnitIdentityMatchSender(unitGUID, normalizedUnitName, senderGUID, normalizedSenderName)
end

function QuestTogether:FindNearbyPlayerUnitTokenForSender(senderGUID, senderName)
	local candidateUnits = {
		"target",
		"mouseover",
		"focus",
	}

	for _, unitToken in ipairs(candidateUnits) do
		if self:DoesUnitTokenMatchSender(unitToken, senderGUID, senderName) then
			return unitToken
		end
	end

	return nil
end

function QuestTogether:RefreshNameplateAugmentation()
	self:MaybeAnnounceNameplateCapabilityContextChange()
	self:RefreshActiveAnnouncementBubbles()

	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self:ClearNameplateQuestDetectionCache()
		wipe(self.nameplateQuestStateByUnitToken)
		wipe(self.nameplateQuestGuidByUnitToken)
		self:ForEachVisibleNamePlate(function(frame)
			self:HideNameplateIcon(frame)
		end)
		return
	end

	self:ForEachVisibleNamePlate(function(frame)
		self:RefreshNameplateIcon(frame)
	end)
end

-- Mirrors Plater.UpdateAllPlates() (Plater.lua:6681-6692): refresh all visible plates
-- against the current quest cache without rebuilding quest-log title inputs.
function QuestTogether:RefreshVisibleNameplates(_reason)
	self:ClearNameplateResolvedQuestState()
	self:RefreshNameplateAugmentation()
	return true
end

function QuestTogether:RefreshNameplatesForQuestStateChange(_reason)
	self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
	self:RebuildNameplateQuestTextCache()
	self:ClearNameplateQuestDetectionCache()
	self:ClearNameplateResolvedQuestState()
	self:RefreshNameplateAugmentation()
	return true
end

function QuestTogether:InvalidateNameplateQuestState(reason)
	-- These are addon-owned caches. Retire stale positives immediately, even
	-- when rebuilding the quest log must wait for a restricted context to end.
	self:ClearNameplateQuestDetectionCache()
	self:ClearNameplateResolvedQuestState()
	self:ScheduleDeferredWork("nameplate_quest_refresh", "quest_relevance", function()
		-- This work class permits readable structured unit tooltips in ordinary
		-- combat. Map/encounter/PvP restrictions and per-frame guards still apply.
		-- Health events may have repopulated the cache before new quest tooltip
		-- lines arrived, so the delayed pass must discard that interim evidence.
		self:ClearNameplateQuestDetectionCache()
		self:RefreshVisibleNameplates(reason)
	end, PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS, reason)
end

function QuestTogether:ScheduleDeferredNameplateQuestStateRefresh(reason, delaySeconds)
	self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", true)
	if self.ScheduleQuestStateRefreshWork then
		self:ScheduleQuestStateRefreshWork(reason, delaySeconds or PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS)
		return
	end

	self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
	self:RefreshNameplatesForQuestStateChange(reason)
end

function QuestTogether:ScheduleNameplateContextRefresh(reason, delaySeconds)
	if self:GetRuntimeFlag("nameplateQuestTextCacheSuppressed", false)
		and not self:IsNameplateAugmentationBlockedInCurrentContext() then
		-- Instance policy discarded the known quest text. Presentation alone
		-- cannot recover it, even with readable outdoor tooltips. Reuse the
		-- guarded snapshot work and coalesce world/zone events until it runs.
		if not self:GetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false) then
			self:ScheduleDeferredNameplateQuestStateRefresh(reason, delaySeconds)
		end
		return
	end
	self:ScheduleNameplatePresentationRefresh(reason, delaySeconds)
end

function QuestTogether:SchedulePlaterStartupNameplateRefreshes()
	if not self.API or type(self.API.Delay) ~= "function" then
		return false
	end
	local startupState = self.nameplateRefreshGenerationByUnitToken

	-- Mirrors Plater startup bootstrap in local retail Plater.lua:6357-6362:
	-- queue QuestLogUpdated() after 4.1 seconds, which then waits the standard
	-- 1-second quest-cache throttle, and separately trigger FullRefreshAllPlates()
	-- at 5.1 seconds after initialization.
	self.API.Delay(PLATER_INITIAL_QUEST_LOG_UPDATED_DELAY_SECONDS, function()
		if not self.isEnabled or self.nameplateRefreshGenerationByUnitToken ~= startupState then
			return
		end
		QuestTogether:ScheduleDeferredNameplateQuestStateRefresh(
			"EnableNameplateAugmentationStartup",
			PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS
		)
	end)
	self.API.Delay(PLATER_INITIAL_FULL_REFRESH_DELAY_SECONDS, function()
		if not self.isEnabled or self.nameplateRefreshGenerationByUnitToken ~= startupState then
			return
		end
		QuestTogether:FullRefreshVisibleNameplates("EnableNameplateAugmentationStartupFullRefresh")
	end)

	return true
end

-- Mirrors the per-plate pass in Plater.FullRefreshAllPlates()
-- (local retail Plater.lua:6697-6701) rather than routing through UpdateAllPlates().
function QuestTogether:FullRefreshVisibleNameplates(reason)
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return self:RefreshVisibleNameplates(reason)
	end

	self:ClearNameplateResolvedQuestState()
	self:ForEachVisibleNamePlate(function(frame)
		self:RefreshNameplateIcon(frame)
	end)

	return true
end

function QuestTogether:ScheduleFullNameplateRefresh(delaySeconds)
	if self.ScheduleNameplatePresentationRefresh then
		self:ScheduleNameplatePresentationRefresh("ScheduleFullNameplateRefresh", delaySeconds)
		return
	end

	self:RefreshVisibleNameplates("ScheduleFullNameplateRefresh")
end

function QuestTogether:OnNameplateAdded(unitToken)
	if not self.isEnabled then
		return
	end

	if not self:IsNameplateUnitToken(unitToken) then
		return
	end
	self.nameplateRefreshGenerationByUnitToken[unitToken] =
		(self.nameplateRefreshGenerationByUnitToken[unitToken] or 0) + 1
	self.nameplateRefreshPendingByUnitToken[unitToken] = nil
	self:ClearNameplateTooltipResolveRetryCount(unitToken)
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self:ForgetResolvedNameplateQuestState(unitToken)
		local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, false)
		if namePlateFrameBase then
			-- Nameplate frames are recycled across zone and instance transitions.
			-- In blocked contexts like arenas, clear any stale quest visuals immediately.
			self:HideNameplateIcon(namePlateFrameBase)
			self:HideAnnouncementBubble(namePlateFrameBase)
		end
		return
	end

	local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, false)

	self:ForgetResolvedNameplateQuestState(unitToken)

	if namePlateFrameBase then
		-- Nameplate frames are recycled. Clear any stale icon/tint immediately so visuals
		-- from a previous unit cannot carry over before the live refresh resolves.
		self:HideNameplateIcon(namePlateFrameBase)
		self:HideAnnouncementBubble(namePlateFrameBase)
		self:RefreshNameplateIcon(namePlateFrameBase)
		return
	end

	self:ScheduleNameplateRefresh(unitToken)
end

function QuestTogether:OnNameplateRemoved(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	self:ForgetResolvedNameplateQuestState(unitToken)
	self:ClearNameplateTooltipResolveRetryCount(unitToken)
	self.nameplateRefreshPendingByUnitToken[unitToken] = nil
	-- Never reuse a generation after a token is removed and assigned again.
	self.nameplateRefreshGenerationByUnitToken[unitToken] = (self.nameplateRefreshGenerationByUnitToken[unitToken] or 0)
		+ 1
	self.nameplateHealthTintRefreshPendingByUnitToken[unitToken] = nil

	local namePlateFrameBase = self.API and self.API.GetNamePlateForUnit and self.API.GetNamePlateForUnit(unitToken)
		or nil
	if namePlateFrameBase then
		self:HideNameplateIcon(namePlateFrameBase)
		self:HideAnnouncementBubble(namePlateFrameBase)
	end
	for icon, info in pairs(self.qtPlayerIconStateByFrame or {}) do
		if info.unitToken == unitToken then
			self:HideQTPlayerIcon(icon)
		end
	end
	-- The public lookup may already be empty by NAME_PLATE_UNIT_REMOVED.
	-- Find playback through addon-owned state, without reading the old frame.
	for bubble, state in pairs(self.nameplateBubbleStateByFrame) do
		if state.unitToken == unitToken then
			self:StopAndHideAnnouncementBubblePlayback(bubble)
		end
	end
end

function QuestTogether:TryInstallNameplateHooks()
	if self.nameplateHooksInstalled then
		return
	end

	-- Avoid secure add/remove hooks into Blizzard's nameplate setup path. The one safe hook we
	-- do want is the global options-update pass, so we can reapply our quest visuals after
	-- Blizzard restyles all visible nameplates.
	if
		not self.nameplateOptionsHookInstalled
		and type(hooksecurefunc) == "function"
		and type(NamePlateDriverMixin) == "table"
		and type(NamePlateDriverMixin.UpdateNamePlateOptions) == "function"
	then
		hooksecurefunc(NamePlateDriverMixin, "UpdateNamePlateOptions", function()
			QuestTogether:ScheduleFullNameplateRefresh(0.05)
		end)
		self.nameplateOptionsHookInstalled = true
	end

	self.nameplateHooksInstalled = true
end

function QuestTogether:HandleNameplateEvent(eventName, ...)
	if self.pendingNameplateVisualCleanup then
		self:RetryPendingNameplateVisualCleanup()
		if not self.isEnabled then
			if not self.pendingNameplateVisualCleanup and self.nameplateEventFrame then
				self.nameplateEventFrame:UnregisterAllEvents()
				wipe(self.nameplateRegisteredEvents)
			end
			return
		end
	end
	if not self.isEnabled then
		return
	end
	if eventName == "NAME_PLATE_UNIT_ADDED" then
		self:OnNameplateAdded(...)
	elseif eventName == "NAME_PLATE_UNIT_REMOVED" then
		self:OnNameplateRemoved(...)
	elseif eventName == "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED" then
		local unitToken, isBehindCamera = ...
		if self:IsNameplateUnitToken(unitToken) and self:CanAccessValue(isBehindCamera) and isBehindCamera == false then
			self:ClearNameplateTooltipResolveRetryCount(unitToken)
			self:ScheduleNameplateRefresh(unitToken)
		end
	elseif eventName == "PLAYER_TARGET_CHANGED" then
		self:RefreshNameplateForUnitAlias("target")
	elseif eventName == "UNIT_NAME_UPDATE" then
		local unitToken = ...
		if self:IsNameplateUnitToken(unitToken) then
			self:ScheduleNameplateRefresh(unitToken)
		end
	elseif eventName == "UNIT_AURA" then
		local unitToken = ...
		if self:IsNameplateUnitToken(unitToken) and self:GetNameplatePlayerIconStyle() == "left" then
			-- Only existing player logos need this layout update. Do not turn
			-- every NPC aura tick into quest detection/tooltip work. Defer until
			-- Blizzard has laid out the buffs, and coalesce same-frame events.
			for _, info in pairs(self.qtPlayerIconStateByFrame or {}) do
				if info.unitToken == unitToken then
					if not self.nameplateRefreshPendingByUnitToken[unitToken] and self:IsNameplateUnitPlayer(unitToken) then
						self:ScheduleNameplateRefresh(unitToken)
					end
					break
				end
			end
		end
	elseif eventName == "UPDATE_MOUSEOVER_UNIT" then
		self:RefreshNameplateForUnitAlias("mouseover")
	elseif eventName == "PLAYER_ENTERING_WORLD" then
		self:ScheduleNameplateContextRefresh("PLAYER_ENTERING_WORLD", 1)
	elseif
			eventName == "ZONE_CHANGED_NEW_AREA"
			or eventName == "ZONE_CHANGED_INDOORS"
			or eventName == "ZONE_CHANGED"
	then
		self:ScheduleNameplateContextRefresh(eventName, 0)
	elseif eventName == "PLAYER_REGEN_DISABLED" or eventName == "PLAYER_REGEN_ENABLED" then
		if eventName == "PLAYER_REGEN_ENABLED" then
			self:TryInstallPersonalBubbleEditModeHooks()
		end
		self:ScheduleNameplatePresentationRefresh(eventName, 0)
	elseif
			eventName == "QUEST_LOG_UPDATE"
			or eventName == "QUEST_REMOVED"
			or eventName == "QUEST_ACCEPTED"
			or eventName == "QUEST_ACCEPT_CONFIRM"
			or eventName == "QUEST_COMPLETE"
			or eventName == "QUEST_POI_UPDATE"
			or eventName == "QUEST_QUERY_COMPLETE"
			or eventName == "QUEST_DETAIL"
			or eventName == "QUEST_FINISHED"
			or eventName == "QUEST_GREETING"
	then
		self:InvalidateNameplateQuestState(eventName)
		self:ScheduleQuestStateRefreshWork(eventName, PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS)
	elseif eventName == "DISPLAY_SIZE_CHANGED" then
		self:ScheduleFullNameplateRefresh(0.05)
	elseif eventName == "CVAR_UPDATE" then
		local cvarName = ...
		if SafeFindPlain(string.lower(SafeText(cvarName, "")), "nameplate") then
			self:ScheduleFullNameplateRefresh(0.05)
		end
	elseif
		eventName == "UNIT_HEALTH"
		or eventName == "UNIT_MAXHEALTH"
		or eventName == "UNIT_CONNECTION"
		or eventName == "UNIT_THREAT_LIST_UPDATE"
		or eventName == "UNIT_THREAT_SITUATION_UPDATE"
		or eventName == "UNIT_FACTION"
		or eventName == "UNIT_FLAGS"
	then
		-- Combat threat styling can swap the live health-fill texture on Blizzard nameplates.
		-- Re-anchor our overlay on the same unit-token events so the tint survives combat.
		local unitToken = ...
		if self:IsNameplateUnitToken(unitToken) then
			self:HideTapDeniedNameplateVisuals(unitToken)
			if eventName == "UNIT_FACTION" or eventName == "UNIT_FLAGS" then
				-- Refresh both decorations when ownership changes, including when
				-- a previously denied tap becomes eligible again.
				self:ScheduleNameplateRefresh(unitToken)
			else
				self:ScheduleNameplateHealthTintRefresh(unitToken, nil, true)
			end
		end
	elseif eventName == "UNIT_QUEST_LOG_CHANGED" then
		self:InvalidateNameplateQuestState(eventName)
		self:ScheduleQuestStateRefreshWork(eventName, PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS)
	end
end

function QuestTogether:EnableNameplateAugmentation()
	self:SetRuntimeFlag("nameplateQuestTextCacheSuppressed", false)
	if not self.nameplateEventFrame then
		self.nameplateEventFrame = CreateFrame("Frame")
		self.nameplateRegisteredEvents = self.nameplateRegisteredEvents or {}
		self.nameplateEventFrame:SetScript("OnEvent", function(_, eventName, ...)
			if self.RunGuardedCallback then
				local ok, err = self:RunGuardedCallback("nameplate:" .. eventName, self.HandleNameplateEvent, self, eventName, ...)
				if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
			else
				self:HandleNameplateEvent(eventName, ...)
			end
		end)
	end

	local function RegisterNameplateEvent(addon, eventName)
		-- Event availability differs by client build; keep registration best-effort.
		local ok = pcall(addon.nameplateEventFrame.RegisterEvent, addon.nameplateEventFrame, eventName)
		if ok then
			addon.nameplateRegisteredEvents[eventName] = true
		else
			addon.nameplateRegisteredEvents[eventName] = nil
		end
	end

	self:TryInstallNameplateHooks()
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_ADDED")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_REMOVED")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED")
	RegisterNameplateEvent(self, "PLAYER_TARGET_CHANGED")
	RegisterNameplateEvent(self, "UPDATE_MOUSEOVER_UNIT")
	RegisterNameplateEvent(self, "QUEST_LOG_UPDATE")
	RegisterNameplateEvent(self, "QUEST_REMOVED")
	RegisterNameplateEvent(self, "QUEST_ACCEPTED")
	RegisterNameplateEvent(self, "QUEST_ACCEPT_CONFIRM")
	RegisterNameplateEvent(self, "QUEST_COMPLETE")
	RegisterNameplateEvent(self, "QUEST_POI_UPDATE")
	RegisterNameplateEvent(self, "QUEST_QUERY_COMPLETE")
	RegisterNameplateEvent(self, "QUEST_DETAIL")
	RegisterNameplateEvent(self, "QUEST_FINISHED")
	RegisterNameplateEvent(self, "QUEST_GREETING")
	RegisterNameplateEvent(self, "UNIT_QUEST_LOG_CHANGED")
	RegisterNameplateEvent(self, "UNIT_HEALTH")
	RegisterNameplateEvent(self, "UNIT_MAXHEALTH")
	RegisterNameplateEvent(self, "UNIT_CONNECTION")
	RegisterNameplateEvent(self, "UNIT_NAME_UPDATE")
	RegisterNameplateEvent(self, "UNIT_AURA")
	RegisterNameplateEvent(self, "UNIT_THREAT_LIST_UPDATE")
	RegisterNameplateEvent(self, "UNIT_THREAT_SITUATION_UPDATE")
	RegisterNameplateEvent(self, "UNIT_FACTION")
	RegisterNameplateEvent(self, "UNIT_FLAGS")
	RegisterNameplateEvent(self, "PLAYER_ENTERING_WORLD")
	RegisterNameplateEvent(self, "ZONE_CHANGED_NEW_AREA")
	RegisterNameplateEvent(self, "ZONE_CHANGED_INDOORS")
	RegisterNameplateEvent(self, "ZONE_CHANGED")
	RegisterNameplateEvent(self, "PLAYER_REGEN_DISABLED")
	RegisterNameplateEvent(self, "PLAYER_REGEN_ENABLED")
	RegisterNameplateEvent(self, "ADDON_RESTRICTION_STATE_CHANGED")
	RegisterNameplateEvent(self, "DISPLAY_SIZE_CHANGED")
	RegisterNameplateEvent(self, "CVAR_UPDATE")
	self:ScheduleDeferredNameplateQuestStateRefresh(
		"EnableNameplateAugmentation",
		PLATER_QUEST_STATE_REFRESH_DELAY_SECONDS
	)
	self:SchedulePlaterStartupNameplateRefreshes()
end

function QuestTogether:CancelNameplateVisualCleanup(visual)
	local state = self.runtimeStateStore and self.runtimeStateStore.nameplate
	local pending = state and state.pendingVisualCleanupByFrame
	if pending then
		-- This handle now presents a new live state. A previous disabled
		-- lifetime must never hide it after its protection/forbidden state clears.
		pending[visual] = nil
		self.pendingNameplateVisualCleanup = next(pending) ~= nil
	end
end

function QuestTogether:RetryPendingNameplateVisualCleanup()
	local pending = self:GetNameplateStateStore().pendingVisualCleanupByFrame
	for visual, kind in pairs(pending or {}) do
		local hidden = false
		if kind == "bubble" then
			hidden = self:StopAndHideAnnouncementBubblePlayback(visual, "disable")
		elseif CanMutateFrame(visual) then
			visual:Hide()
			hidden = true
		end
		if hidden then pending[visual] = nil end
	end
	self.pendingNameplateVisualCleanup = pending ~= nil and next(pending) ~= nil
	return not self.pendingNameplateVisualCleanup
end

function QuestTogether:HideAllNameplateVisuals()
	local state = self:GetNameplateStateStore()
	state.pendingVisualCleanupByFrame = state.pendingVisualCleanupByFrame or {}
	local pending = state.pendingVisualCleanupByFrame
	-- Capture the disabled lifetime once. Subsequent events retry only failed
	-- handles, so one quarantined frame cannot hide unrelated current visuals.
	for _, bubble in pairs(self.nameplateBubbleByUnitFrame) do pending[bubble] = "bubble" end
	for _, icon in pairs(self.nameplateIconByUnitFrame) do pending[icon] = "icon" end
	for _, overlay in pairs(self.nameplateHealthOverlayByUnitFrame) do
		for _, texture in pairs(overlay) do pending[texture] = "texture" end
	end
	return self:RetryPendingNameplateVisualCleanup()
end

function QuestTogether:DisableNameplateAugmentation()
	self:SetRuntimeFlag("nameplateQuestTextCacheSuppressed", false)
	self.pendingNameplateVisualCleanup = not self:HideAllNameplateVisuals()
	self.qtPlayerIconStateByFrame = nil
	if self.pendingNameplateVisualCleanup then
		self:Debug("visual_cleanup deferred until restrictions end", "nameplate")
	end
	if not self.nameplateEventFrame then
		return
	end

	for eventName in pairs(self.nameplateRegisteredEvents or {}) do
		-- Unregister should never break disable flow if an event was already invalidated.
		pcall(self.nameplateEventFrame.UnregisterEvent, self.nameplateEventFrame, eventName)
	end
	if self.nameplateRegisteredEvents then
		wipe(self.nameplateRegisteredEvents)
	end
	if self.pendingNameplateVisualCleanup then
		-- The normal runtime scheduler is stopped while disabled. Keep only
		-- event-driven teardown until protected visuals can be hidden safely.
		for _, eventName in ipairs({ "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
			if pcall(self.nameplateEventFrame.RegisterEvent, self.nameplateEventFrame, eventName) then
				self.nameplateRegisteredEvents[eventName] = true
			end
		end
	end

	-- Hide our icon overlays and clear cached quest objective state.
	self:ClearNameplateQuestDetectionCache()
	self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
	self:SetRuntimeFlag("deferredNameplateQuestStateRefreshGeneration", 0)
	self:ForEachVisibleNamePlate(function(frame)
		self:HideNameplateIcon(frame)
	end)
	if self.ResetNameplateStateStore then
		self:ResetNameplateStateStore()
	end
end
