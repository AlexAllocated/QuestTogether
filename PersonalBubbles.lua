-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Services = QuestTogether.NameplateServices
local function GetAnnouncementBubbleLifetimeSeconds()
	local configuredDuration =
		QuestTogether:NormalizeChatBubbleDurationValue(QuestTogether:GetOption("chatBubbleDuration"))
	if not configuredDuration or configuredDuration <= 0 then
		configuredDuration = QuestTogether.DEFAULTS.profile.chatBubbleDuration
	end
	return Services.Access.SafeUiNumber(configuredDuration, QuestTogether.DEFAULTS.profile.chatBubbleDuration)
end

local function GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame or Services.Access.IsFrameForbidden(hostFrame) then
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
	if not dialog or not QuestTogether:GetPersonalBubbleStateStore().dialogPositionByFrame then
		return nil
	end
	return QuestTogether:GetPersonalBubbleStateStore().dialogPositionByFrame[dialog]
end

local function SetSavedPersonalBubbleDialogPosition(dialog, position)
	if not dialog or type(position) ~= "table" then
		return
	end
	QuestTogether:GetPersonalBubbleStateStore().dialogPositionByFrame[dialog] = position
end

local function GetAnnouncementBubbleState(bubble)
	if not bubble or not QuestTogether:GetNameplateStateStore().bubbleStateByFrame then
		return nil
	end
	return QuestTogether:GetNameplateStateStore().bubbleStateByFrame[bubble]
end

local function SetAnnouncementBubbleState(bubble, state)
	if not bubble or type(state) ~= "table" then
		return nil
	end
	QuestTogether:GetNameplateStateStore().bubbleStateByFrame[bubble] = state
	return state
end

local function ClearAnnouncementBubbleState(bubble)
	if not bubble or not QuestTogether:GetNameplateStateStore().bubbleStateByFrame then
		return
	end
	QuestTogether:GetNameplateStateStore().bubbleStateByFrame[bubble] = nil
end

local function DeferAnnouncementBubbleCleanup(addon, bubble)
	if bubble then
		addon:QueueNameplateVisualCleanup(bubble, "bubble")
	end
	return false
end

function QuestTogether:CompleteAnnouncementBubblePlayback(bubble)
	local bubbleState = GetAnnouncementBubbleState(bubble)
	local unitToken = bubbleState and bubbleState.unitToken or nil
	if bubbleState and bubbleState.text then
		self:Debugf(
			"bubble",
			"playback_complete unit=%s event=%s",
			Services.Access.SafeText(unitToken, ""),
			Services.Access.SafeText(bubbleState.eventType, "")
		)
	end
	ClearAnnouncementBubbleState(bubble)
	if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(unitToken) then
		return false
	end
	if not Services.Access.CanMutateFrame(bubble) then
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
		self:Debugf(
			"bubble",
			"playback_stop unit=%s event=%s reason=%s",
			Services.Access.SafeText(unitToken, ""),
			Services.Access.SafeText(bubbleState.eventType, ""),
			Services.Access.SafeText(reason, "hide")
		)
	end
	-- Teardown only touches this addon-owned bubble and its animation. Unlike
	-- starting/reparenting playback, hiding an accessible unprotected region is
	-- safe during combat. Do not leave old playback attached to a reused base.
	if not Services.Access.CanMutateFrame(bubble) then
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
	if not Services.Access.CanMutateFrame(bubble) then
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

function QuestTogether:EnsurePersonalBubbleEditSession()
	local currentSession = self:GetPersonalBubbleEditSession()
	if currentSession then
		return currentSession
	end

	local session = {
		profile = self.db and self.db.profile,
		saved = {
			chatBubbleSize = self:NormalizeChatBubbleSizeValue(self:GetOption("chatBubbleSize"))
				or self.DEFAULTS.profile.chatBubbleSize,
			chatBubbleDuration = self:NormalizeChatBubbleDurationValue(self:GetOption("chatBubbleDuration"))
				or self.DEFAULTS.profile.chatBubbleDuration,
			anchor = self:DeepCopy(self:GetPersonalBubbleAnchor()),
		},
		pending = false,
	}

	self.personalBubbleEditSession = session
	return session
end

local function EnsurePersonalBubbleEditSession()
	return QuestTogether:EnsurePersonalBubbleEditSession()
end

local function IsPersonalBubbleEditSnapshotEqual(addon, snapshot)
	if type(snapshot) ~= "table" then
		return true
	end

	local currentSize = addon:NormalizeChatBubbleSizeValue(addon:GetOption("chatBubbleSize"))
		or addon.DEFAULTS.profile.chatBubbleSize
	local currentDuration = addon:NormalizeChatBubbleDurationValue(addon:GetOption("chatBubbleDuration"))
		or addon.DEFAULTS.profile.chatBubbleDuration
	local currentAnchor = addon:GetPersonalBubbleAnchor()
	local savedAnchor = snapshot.anchor or addon.DEFAULT_PERSONAL_BUBBLE_ANCHOR

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
	local currentDuration = QuestTogether:NormalizeChatBubbleDurationValue(
		QuestTogether:GetOption("chatBubbleDuration")
	) or defaults.chatBubbleDuration
	local currentAnchor = QuestTogether:GetPersonalBubbleAnchor()

	return currentSize == defaults.chatBubbleSize
		and currentDuration == defaults.chatBubbleDuration
		and currentAnchor.point == anchorDefaults.point
		and currentAnchor.relativePoint == anchorDefaults.relativePoint
		and currentAnchor.x == anchorDefaults.x
		and currentAnchor.y == anchorDefaults.y
end

function QuestTogether:RefreshPersonalBubbleEditSaveState()
	local session = self:GetPersonalBubbleEditSession()
	local pending = session and not IsPersonalBubbleEditSnapshotEqual(self, session.saved) or false
	if session then
		session.pending = pending
	end
	local dialog = self.personalBubbleEditModeDialog
	if not dialog then
		return
	end
	if dialog.SaveButton then
		dialog.SaveButton:SetEnabled(pending)
	end
	if dialog.RevertButton then
		dialog.RevertButton:SetEnabled(pending)
	end
	if dialog.SaveStatus then
		dialog.SaveStatus:SetText(
			pending and L("Changes applied automatically. Save Changes sets the point Revert returns to.")
				or L("QuestTogether settings saved. Blizzard's Save button is not needed.")
		)
	end
end

local function UpdatePersonalBubbleEditSessionDirtyState()
	EnsurePersonalBubbleEditSession()
	QuestTogether:RefreshPersonalBubbleEditSaveState()
	local dialog = QuestTogether.personalBubbleEditModeDialog
	if dialog and dialog.ResetButton then
		dialog.ResetButton:SetEnabled(not IsPersonalBubbleAtDefaultState())
	end
end

-- Compatibility seams for the bubble's private preview/test adapters.
function QuestTogether:ConfigurePersonalBubbleDialogSlider(frame, data, callback)
	self:ConfigureHUDEditSlider(frame, data, callback)
end
function QuestTogether:LayoutPersonalBubbleDialog(dialog)
	self:LayoutHUDEditDialog(dialog)
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
	-- Capture the new baseline before the next slider/anchor edit, not after it.
	self:EnsurePersonalBubbleEditSession()
	self:RefreshPersonalBubbleEditSaveState()
end

function QuestTogether:RevertPersonalBubbleEditSession()
	local session = self:GetPersonalBubbleEditSession()
	if not session then
		return
	end

	self:ApplyPersonalBubbleEditSnapshot(session.saved)
	session.pending = false
	self:RefreshPersonalBubbleEditSaveState()
	if self.personalBubbleEditModeDialog and self.personalBubbleEditModeDialog.RevertButton then
		self.personalBubbleEditModeDialog.RevertButton:SetEnabled(false)
	end
end

function QuestTogether:ResetPersonalBubbleEditSessionToDefaults()
	self:EnsurePersonalBubbleEditSession()
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

local function EnsurePersonalBubbleEditModeDialog(addon, preview)
	local key = preview and "personalBubbleEditModePreviewDialog" or "personalBubbleEditModeDialog"
	if rawget(addon, key) then
		return addon[key]
	end
	if not preview and not EditModeManagerFrame then
		return nil
	end
	local dialog = addon:CreateHUDEditDialog(L("QuestTogether Bubble"), { "SizeSlider", "DurationSlider" }, {
		close = function()
			if preview then
				addon[key]:Hide()
			else
				addon:DeselectPersonalBubbleAnchor()
			end
		end,
		save = function()
			if not preview then
				addon:CommitPersonalBubbleEditSession()
			end
		end,
		revert = function()
			if not preview then
				addon:RevertPersonalBubbleEditSession()
			end
		end,
		reset = function()
			if not preview then
				addon:ResetPersonalBubbleEditSessionToDefaults()
			end
		end,
		moved = function(frame)
			if not preview then
				SavePersonalBubbleDialogPosition(frame)
			end
		end,
	})
	if dialog then
		dialog:EnableKeyboard(not preview)
	end
	addon[key] = dialog
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
	Services.Decorations.ApplyQuestIconVisual(icon)
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
	return (
		self.isEnabled
		and self:CanAccessForeignFrame(EditModeManagerFrame, true)
		and self:GetOption("showChatBubbles")
	)
			and true
		or false
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
	local numberValue = Services.Access.SafeUiNumber(value, 0)
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

	if self:IsPersonalBubbleAnchorInEditMode() then
		self:EnsurePersonalBubbleEditSession()
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
		dialog:SetPoint(savedPosition.point, UIParent, savedPosition.relativePoint, savedPosition.x, savedPosition.y)
		return
	end

	local point, relativeTo, relativePoint, offsetX, offsetY = GetPersonalBubbleAnchorDialogAttachPoint()
	dialog:ClearAllPoints()
	dialog:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
end

function QuestTogether:RefreshPersonalBubbleEditModeDialog(preview)
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	local dialog = EnsurePersonalBubbleEditModeDialog(self, preview)
	if not dialog then
		return
	end

	local function FormatDurationLabel(value)
		local normalized = self:NormalizeChatBubbleDurationValue(value) or self.DEFAULTS.profile.chatBubbleDuration
		if math.abs(normalized - math.floor(normalized)) < 0.001 then
			return string.format(L("%d sec"), normalized)
		end
		return string.format(L("%.1f sec"), normalized)
	end

	self:ConfigurePersonalBubbleDialogSlider(dialog.SizeSlider, {
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
		currentValue = self:NormalizeChatBubbleSizeValue(self:GetOption("chatBubbleSize"))
			or self.DEFAULTS.profile.chatBubbleSize,
		settingName = L("Font Size"),
	}, function(value)
		if preview then
			return
		end
		self:EnsurePersonalBubbleEditSession()
		if self:SetOption("chatBubbleSize", value) and not self.personalBubbleEditSessionRestoring then
			UpdatePersonalBubbleEditSessionDirtyState()
			self:RefreshPersonalBubbleAnchorVisualState()
			self:AttachPersonalBubbleEditModeDialog()
		end
	end)

	self:ConfigurePersonalBubbleDialogSlider(dialog.DurationSlider, {
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
		if preview then
			return
		end
		self:EnsurePersonalBubbleEditSession()
		if self:SetOption("chatBubbleDuration", value) and not self.personalBubbleEditSessionRestoring then
			UpdatePersonalBubbleEditSessionDirtyState()
			self:RefreshPersonalBubbleAnchorVisualState()
			self:AttachPersonalBubbleEditModeDialog()
		end
	end)

	if preview then
		dialog.SaveStatus:SetText(L("Preview - no settings will change."))
		dialog.SaveButton:SetEnabled(false)
		dialog.RevertButton:SetEnabled(false)
		dialog.ResetButton:SetEnabled(false)
	else
		self:RefreshPersonalBubbleEditSaveState()
	end
	self:LayoutPersonalBubbleDialog(dialog)
	self:ThemeHUDEditDialog(dialog)
	if not preview and dialog.ResetButton then
		dialog.ResetButton:SetEnabled(not IsPersonalBubbleAtDefaultState())
	end
end

function QuestTogether:ShowPersonalBubbleSettingsPreview()
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return false
	end
	local ok = pcall(self.RefreshPersonalBubbleEditModeDialog, self, true)
	local dialog = rawget(self, "personalBubbleEditModePreviewDialog")
	if not ok or not dialog or not self.LibChev.CanMutateOwnedRegion(dialog) then
		if dialog and self.LibChev.CanMutateOwnedRegion(dialog) then
			dialog:Hide()
		end
		self:Print(L("Bubble settings preview is unavailable on this client."))
		return false
	end
	dialog:ClearAllPoints()
	dialog:SetPoint("CENTER")
	dialog:Show()
	return true
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

	self:DeselectQuestFocusWindow()
	self.personalBubbleAnchorSelected = true
	self:RefreshPersonalBubbleAnchorVisualState()
	self:AttachPersonalBubbleEditModeDialog()
	self:RefreshPersonalBubbleEditModeDialog()

	local dialog = EnsurePersonalBubbleEditModeDialog(self)
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

	if EditModeManagerFrame then
		self:EnsureHUDEditSelection(hostFrame, L("QuestTogether Bubble"))
	end

	local editModeActive = self:IsPersonalBubbleAnchorInEditMode()
	local uiParentLevel =
		Services.Access.SafeUiNumber((UIParent and UIParent.GetFrameLevel and UIParent:GetFrameLevel()) or 0, 0)
	if editModeActive then
		hostFrame:SetFrameStrata("HIGH")
		hostFrame:SetFrameLevel(uiParentLevel + 80)
		local visualConfig = GetAnnouncementBubbleVisualConfig()
		local fontPath, fontFlags = GetPersonalBubbleAnchorFontDefinition()
		hostFrame.EditLabel:SetFont(fontPath, visualConfig.fontSize, fontFlags)
		hostFrame.EditLabel:SetWidth(0)
		hostFrame.EditLabel:SetText(L("QuestTogether Bubble"))

		local labelWidth = hostFrame.EditLabel.GetUnboundedStringWidth and hostFrame.EditLabel:GetUnboundedStringWidth()
			or 0
		labelWidth = Services.Access.SafeUiNumber(labelWidth, 0)
		local labelHeight = Services.Access.SafeUiNumber(hostFrame.EditLabel:GetStringHeight(), visualConfig.fontSize)
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

	local activeBubble = self:GetNameplateStateStore().bubbleByUnitFrame
		and self:GetNameplateStateStore().bubbleByUnitFrame[hostFrame]
	if activeBubble then
		activeBubble:SetFrameStrata(hostFrame:GetFrameStrata() or "LOW")
		activeBubble:SetFrameLevel(Services.Access.SafeUiNumber(hostFrame:GetFrameLevel(), 0) + 20)
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

-- Production supplies access-checked frames; private tests supply owned fixtures.
function QuestTogether:BindPersonalBubbleEditModeCallbacks(manager, revertButton, hookMethod)
	manager:HookScript("OnShow", function()
		self:EnsurePersonalBubbleEditSession()
		self:RefreshPersonalBubbleAnchorVisualState()
		self:RefreshPersonalBubbleEditModeDialog()
	end)
	manager:HookScript("OnHide", function()
		self:DeselectPersonalBubbleAnchor()
		-- Blizzard temporarily hides and locks Edit Mode when opening settings
		-- or Quick Keybind mode. That is still the same editing/revert session.
		local isActive = self:GetAccessibleFrameMember(manager, "IsEditModeActive")
		if type(isActive) == "function" then
			local ok, active = pcall(isActive, manager)
			if ok and self:CanAccessValue(active) and active == true then
				return
			end
		end
		-- Addon settings persist immediately. Keep dirty/revert state entirely
		-- addon-owned instead of writing Blizzard's shared layout manager.
		self:CommitPersonalBubbleEditSession()
		self.personalBubbleEditSession = nil
	end)

	hookMethod(manager, "SelectSystem", function(_, systemFrame)
		local hostFrame = self.announcementBubbleScreenHostFrame
		if hostFrame and systemFrame ~= hostFrame then
			self:DeselectPersonalBubbleAnchor()
		end
	end)
	hookMethod(manager, "ClearSelectedSystem", function()
		self:DeselectPersonalBubbleAnchor()
	end)
	hookMethod(manager, "SaveLayouts", function()
		self:CommitPersonalBubbleEditSession()
	end)
	-- Native ExitEditMode calls RevertAllChanges even on ordinary close.
	-- Only the explicit Revert button may roll back QT's immediately saved data.
	if revertButton then
		revertButton:HookScript("OnClick", function()
			self:RevertPersonalBubbleEditSession()
		end)
	end
end

function QuestTogether:TryInstallPersonalBubbleEditModeHooks()
	if self.personalBubbleEditModeHooksInstalled then
		return
	end

	if self:IsWorkBlocked("foreign_frame_mutation") or not Services.Access.CanMutateFrame(EditModeManagerFrame) then
		return
	end
	local hookScript = select(1, self:GetAccessibleFrameMember(EditModeManagerFrame, "HookScript"))
	if type(hookScript) ~= "function" then
		return
	end

	GetAnnouncementBubbleScreenHostFrame()
	EnsurePersonalBubbleEditModeDialog(self)

	local revertButton = Services.Access.GetAccessibleChildFrame(EditModeManagerFrame, "RevertAllChangesButton")
	if
		not Services.Access.CanMutateFrame(revertButton)
		or type(select(1, self:GetAccessibleFrameMember(revertButton, "HookScript"))) ~= "function"
	then
		revertButton = nil
	end
	self:BindPersonalBubbleEditModeCallbacks(EditModeManagerFrame, revertButton, hooksecurefunc)

	self.personalBubbleEditModeHooksInstalled = true
end

Services.Personal = {
	EstimateBubbleTextHeight = EstimateBubbleTextHeight,
	EstimateBubbleTextWidth = EstimateBubbleTextWidth,
	GetAnnouncementBubbleLifetimeSeconds = GetAnnouncementBubbleLifetimeSeconds,
	GetAnnouncementBubbleScreenHostFrame = GetAnnouncementBubbleScreenHostFrame,
	GetAnnouncementBubbleState = GetAnnouncementBubbleState,
	GetAnnouncementBubbleUnitFrame = GetAnnouncementBubbleUnitFrame,
	GetAnnouncementBubbleVisualConfig = GetAnnouncementBubbleVisualConfig,
	SetAnnouncementBubbleState = SetAnnouncementBubbleState,
}
