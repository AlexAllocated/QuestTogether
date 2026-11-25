local L = _G.QuestTogether.Translate
--[[
QuestTogether Options Panel (Esc > Options > AddOns)
]]

local QuestTogether = _G.QuestTogether

QuestTogether.announcementControls = QuestTogether.announcementControls or {}
QuestTogether.whereToAnnounceControls = QuestTogether.whereToAnnounceControls or {}
QuestTogether.questPlateControls = QuestTogether.questPlateControls or {}
QuestTogether.groupsControls = QuestTogether.groupsControls or {}
QuestTogether.homeControls = QuestTogether.homeControls or {}
QuestTogether.profileControls = QuestTogether.profileControls or {}
QuestTogether.profileUIState = QuestTogether.profileUIState or {}

local function SafeText(value, fallback)
	return QuestTogether:SafeToString(value, fallback or "")
end

local function IsFrameMutable(frame)
	if QuestTogether and QuestTogether.CanAccessForeignFrame then
		return QuestTogether:CanAccessForeignFrame(frame)
	end

	if not frame then
		return false
	end

	if frame.IsForbidden and frame:IsForbidden() then
		return false
	end

	return true
end

local QUEST_PLATE_PREVIEW_SCALE = 1.35
local QUEST_PLATE_PREVIEW_FRAME_HEIGHT = 195
local QUEST_PLATE_PREVIEW_RANDOM_NAMES = {
	"Koda Bug",
	"Rue Angel",
	"Pi Floof",
	"Sammy Bear",
	"Cinder Kitten",
	"Lilly Pig",
	"Booker Bean",
	"Piper Hippo",
	"Wifebeast",
	"Husblebee",
}
local NAMEPLATE_STYLE_MODERN = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Modern or 0
local NAMEPLATE_STYLE_BLOCK = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Block or 2
local NAMEPLATE_STYLE_HEALTH_FOCUS = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.HealthFocus or 3
local NAMEPLATE_STYLE_LEGACY = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Legacy or 5
local NAMEPLATE_STYLE_CLASSIC = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Classic or 6
local NAMEPLATE_SIZE_MEDIUM = Enum and Enum.NamePlateSize and Enum.NamePlateSize.Medium or 2
local NAMEPLATE_INFO_PERCENT = Enum and Enum.NamePlateInfoDisplay and Enum.NamePlateInfoDisplay.CurrentHealthPercent or 1
local NAMEPLATE_INFO_VALUE = Enum and Enum.NamePlateInfoDisplay and Enum.NamePlateInfoDisplay.CurrentHealthValue or 2

local NAMEPLATE_PREVIEW_SCALES = {
	[1] = { horizontal = 0.75, vertical = 0.8 },
	[2] = { horizontal = 1.0, vertical = 1.0 },
	[3] = { horizontal = 1.25, vertical = 1.25 },
	[4] = { horizontal = 1.4, vertical = 1.4 },
	[5] = { horizontal = 1.6, vertical = 1.6 },
}

local function HasBit(mask, bitValue)
	if type(mask) ~= "number" or type(bitValue) ~= "number" or bitValue <= 0 then
		return false
	end

	if bit and bit.band then
		return bit.band(mask, bitValue) ~= 0
	end
	if bit32 and bit32.band then
		return bit32.band(mask, bitValue) ~= 0
	end

	local remainder = mask % (bitValue * 2)
	return remainder >= bitValue
end

local function GetNumericCVarValue(cvarName, fallbackValue)
	if not (QuestTogether and QuestTogether.API and type(QuestTogether.API.GetCVar) == "function") then
		return fallbackValue
	end

	local rawValue = QuestTogether.API.GetCVar(cvarName)
	local numericValue = QuestTogether:SafeToNumber(rawValue)
	if numericValue == nil then
		return fallbackValue
	end

	return numericValue
end

local function AnchorPreviewFillTexture(texture, healthBar)
	if not (texture and healthBar and texture.ClearAllPoints and texture.SetPoint) then
		return
	end

	local fillTexture = healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture() or nil
	if not fillTexture then
		return
	end

	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", fillTexture, "TOPLEFT", 0, 0)
	texture:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMLEFT", 0, 0)
	texture:SetPoint("TOPRIGHT", fillTexture, "TOPRIGHT", 0, 0)
	texture:SetPoint("BOTTOMRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
end

local function GetRandomQuestPlatePreviewName()
	local totalNames = #QUEST_PLATE_PREVIEW_RANDOM_NAMES
	if totalNames <= 0 then
		return L("Quest Mob")
	end

	if not (math and type(math.random) == "function") then
		return QUEST_PLATE_PREVIEW_RANDOM_NAMES[1]
	end

	local randomIndex = math.random(totalNames)
	if type(randomIndex) ~= "number" or randomIndex < 1 or randomIndex > totalNames then
		randomIndex = 1
	end

	return QUEST_PLATE_PREVIEW_RANDOM_NAMES[randomIndex]
end

local function ApplyAnnouncementGroupIcon(texture, iconType)
	if not texture then
		return
	end

	if iconType == "world" and texture.SetAtlas then
		texture:SetAtlas("worldquest-icon", true)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	if iconType == "bonus" and texture.SetAtlas then
		texture:SetAtlas("Bonus-Objective-Star", true)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	if iconType == "quest" then
		texture:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	if QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS and texture.SetAtlas then
		texture:SetAtlas(QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS, true)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end

	texture:SetTexture(QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE)
	if QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS then
		local coords = QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS
		texture:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
	else
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

local function CreateAnnouncementGroupHeader(parent, text, iconType, x, y, width)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	icon:SetSize(16, 16)
	ApplyAnnouncementGroupIcon(icon, iconType)

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	label:SetText(text)

	local divider = parent:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
	divider:SetSize(width or 620, 1)
	divider:SetColorTexture(1, 1, 1, 0.12)

	return label
end

function QuestTogether:GetSettingsTooltipParent()
	return UIParent
end

function QuestTogether:CreateSettingsTooltipFrame(parent)
	return CreateFrame("Frame", nil, parent, "BackdropTemplate")
end

function QuestTogether:GetSettingsTooltipCursorPosition(parent, owner)
	if self:IsNativeGamepadMode()
		and (not self.API.IsMouseOverPartyQuestWindow or not self.API.IsMouseOverPartyQuestWindow(owner)) then return end
	return self:GetChatLogTooltipCursorPosition(parent)
end

function QuestTogether:HideSettingsTooltip(owner)
	if owner and rawget(self, "settingsTooltipOwner") ~= owner then return end
	self.settingsTooltipOwner, self.settingsTooltipSession = nil, nil
	local tooltip = rawget(self, "settingsTooltip")
	self:QueueOwnedUICleanup(tooltip, function(frame)
		frame:SetScript("OnUpdate", nil)
		frame:Hide()
	end)
end

function QuestTogether:ShowSettingsTooltip(owner, title, text)
	if self:IsRuntimeRestricted() or not self.LibChev.CanMutateOwnedRegion(owner) or not owner:IsVisible() then
		self:HideSettingsTooltip()
		return false
	end
	local parent = self:GetSettingsTooltipParent()
	if not self:CanAccessForeignFrame(parent) then return false end
	local tooltip = rawget(self, "settingsTooltip")
	if not tooltip then
		tooltip = self:CreateSettingsTooltipFrame(parent)
		if not self.LibChev.CanMutateOwnedRegion(tooltip) then return false end
		self.settingsTooltip = tooltip
		tooltip:Hide()
		tooltip:SetFrameStrata("TOOLTIP")
		tooltip:SetFrameLevel(100)
		tooltip:SetClampedToScreen(true)
		tooltip:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		tooltip:SetBackdropColor(0.04, 0.05, 0.07, 0.97)
		tooltip.title = tooltip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		tooltip.title:SetPoint("TOPLEFT", 12, -12)
		tooltip.title:SetWidth(296)
		tooltip.title:SetJustifyH("LEFT")
		tooltip.title:SetWordWrap(true)
		tooltip.text = tooltip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tooltip.text:SetPoint("TOPLEFT", tooltip.title, "BOTTOMLEFT", 0, -8)
		tooltip.text:SetWidth(296)
		tooltip.text:SetJustifyH("LEFT")
		tooltip.text:SetWordWrap(true)
	end
	if not self.LibChev.CanMutateOwnedRegion(tooltip)
		or not self.LibChev.CanMutateOwnedRegion(tooltip.title)
		or not self.LibChev.CanMutateOwnedRegion(tooltip.text) then return false end
	tooltip.title:SetText(title)
	tooltip.text:SetText(text)
	tooltip:SetSize(320, tooltip.title:GetStringHeight() + tooltip.text:GetStringHeight() + 32)
	local session = {}
	self.settingsTooltipOwner, self.settingsTooltipSession = owner, session
	self:CancelOwnedUICleanup(tooltip)
	local relative, point, offsetX, offsetY
	local function Position()
		local x, y = self:GetSettingsTooltipCursorPosition(parent, owner)
		x, y = self:SafeToNumber(x), self:SafeToNumber(y)
		local anchor, anchorPoint, relativePoint = owner, "TOPLEFT", "BOTTOMLEFT"
		if x and y then
			anchor, anchorPoint, relativePoint = parent, "BOTTOMLEFT", "BOTTOMLEFT"
			x, y = x + 12, y + 12
		else
			x, y = 8, -8
		end
		if relative == anchor and point == anchorPoint and offsetX == x and offsetY == y then return end
		tooltip:ClearAllPoints()
		tooltip:SetPoint(anchorPoint, anchor, relativePoint, x, y)
		relative, point, offsetX, offsetY = anchor, anchorPoint, x, y
	end
	Position()
	tooltip:SetScript("OnUpdate", function()
		if rawget(self, "settingsTooltipSession") ~= session then return end
		local current = rawget(self, "settingsTooltipOwner")
		if self:IsRuntimeRestricted()
			or not self.LibChev.CanMutateOwnedRegion(tooltip) or not self:CanAccessForeignFrame(parent)
			or not self.LibChev.CanMutateOwnedRegion(current) or not current:IsVisible() then
			self:HideSettingsTooltip()
			return
		end
		Position()
	end)
	tooltip:Show()
	return true
end

-- Only attach to controls created by this addon. No shared GameTooltip state.
function QuestTogether:AttachSettingsTooltip(control, title, text)
	assert(type(text) == "string" and text ~= "" and text ~= title, "settings controls require explanatory tooltip text")
	control:EnableMouse(true)
	if control.SetMotionScriptsWhileDisabled then control:SetMotionScriptsWhileDisabled(true) end
	control:HookScript("OnEnter", function() self:ShowSettingsTooltip(control, title, text) end)
	control:HookScript("OnLeave", function() self:HideSettingsTooltip(control) end)
	control:HookScript("OnHide", function() self:HideSettingsTooltip(control) end)
end

local function CreateDescribedCheckbox(parent, optionKey, labelText, tooltipText, x, y)
	local checkbox = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
	checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
	label:SetWidth(math.max(360, 600 - x))
	label:SetJustifyH("LEFT")
	label:SetWordWrap(true)
	label:SetMaxLines(2)
	label:SetText(labelText)
	checkbox.Label = label
	checkbox.qtOptionKey = optionKey
	checkbox:SetChecked(QuestTogether:GetOption(optionKey) == true)
	checkbox:HookScript("OnShow", function(self)
		self:SetChecked(QuestTogether:GetOption(optionKey) == true)
	end)

	checkbox:SetHitRectInsets(0, -(math.max(360, 600 - x) + 6), 0, 0)
	QuestTogether:AttachSettingsTooltip(checkbox, labelText, tooltipText)

	checkbox:SetScript("OnClick", function(self)
		QuestTogether:SetOption(optionKey, self:GetChecked() == true)
		QuestTogether:RefreshOptionsWindow()
	end)

	return checkbox
end

local function CreateCheckbox(parent, key, x, y)
	local label, tooltip = QuestTogether:GetSettingPresentation(key)
	return CreateDescribedCheckbox(parent, key, label, tooltip, x, y)
end


local function ClampColorComponent(value, fallback)
	local numberValue = QuestTogether:SafeToNumber(value)
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

local function ColorsNearlyEqual(left, right)
	return math.abs((left or 0) - (right or 0)) < 0.001
end

local function GetColorOption(optionKey, fallbackColor)
	local configuredColor = QuestTogether:GetOption(optionKey)
	if type(configuredColor) ~= "table" then
		return {
			r = fallbackColor.r,
			g = fallbackColor.g,
			b = fallbackColor.b,
		}
	end

	return {
		r = ClampColorComponent(configuredColor.r, fallbackColor.r),
		g = ClampColorComponent(configuredColor.g, fallbackColor.g),
		b = ClampColorComponent(configuredColor.b, fallbackColor.b),
	}
end

local function IsColorOptionAtDefault(optionKey, fallbackColor)
	local current = GetColorOption(optionKey, fallbackColor)
	return ColorsNearlyEqual(current.r, fallbackColor.r)
		and ColorsNearlyEqual(current.g, fallbackColor.g)
		and ColorsNearlyEqual(current.b, fallbackColor.b)
end

function QuestTogether:CreateProfileOptionEditCallback(optionKey)
	local profile = self.db and self.db.profile
	local editToken = {}
	self.profileOptionEditToken = editToken
	return function(value)
		-- A picker can outlive a profile switch, copy/reset, or another picker.
		-- Table identity also catches replacement of a profile with the same name.
		if type(profile) ~= "table" or not self.db or self.db.profile ~= profile
			or self.profileOptionEditToken ~= editToken then
			return false
		end
		return self:SetOption(optionKey, value)
	end
end

local function CreateColorSwatch(parent, optionKey, labelText, tooltipText, fallbackColor, x, y)
	local swatchButton = CreateFrame("Button", nil, parent, "ColorSwatchTemplate")
	swatchButton:SetSize(22, 22)
	swatchButton:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", swatchButton, "RIGHT", 8, 0)
	label:SetText(labelText)

	swatchButton:SetHitRectInsets(0, -120, 0, 0)
	QuestTogether:AttachSettingsTooltip(swatchButton, labelText, tooltipText)

	swatchButton:SetScript("OnClick", function()
		if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
			QuestTogether:Print(L("Color picker is unavailable right now."))
			return
		end
		local applyOption = QuestTogether:CreateProfileOptionEditCallback(optionKey)
		local function SetColorOption(r, g, b)
			if applyOption({
				r = ClampColorComponent(r, fallbackColor.r),
				g = ClampColorComponent(g, fallbackColor.g),
				b = ClampColorComponent(b, fallbackColor.b),
			}) then
				QuestTogether:RefreshOptionsWindow()
			end
		end

		local currentColor = GetColorOption(optionKey, fallbackColor)
		local previousColor = {
			r = currentColor.r,
			g = currentColor.g,
			b = currentColor.b,
		}

		local info = {}
		info.r = currentColor.r
		info.g = currentColor.g
		info.b = currentColor.b
		info.hasOpacity = false
		info.swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			SetColorOption(r, g, b)
		end
		info.cancelFunc = function()
			SetColorOption(previousColor.r, previousColor.g, previousColor.b)
		end
		ColorPickerFrame:SetupColorPickerAndShow(info)
	end)

	local startingColor = GetColorOption(optionKey, fallbackColor)
	swatchButton:SetColorRGB(startingColor.r, startingColor.g, startingColor.b)

	return swatchButton
end

local function BuildDropdownEntries(dropdown)
	dropdown.entries = {}
	dropdown.initializeMenu(dropdown)
	return dropdown.entries
end

local function CreateDropdown(parent, titleText, tooltipText, x, y, width, initializeMenu)
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	title:SetText(titleText)

	local control = CreateFrame("Frame", nil, parent, "SettingsDropdownWithButtonsTemplate")
	control:SetSize((width or 180) + 62, 25)
	control:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	control.initializeMenu = initializeMenu
	control.title = title
	control.Label:Hide()
	local dropdown = control.Dropdown
	dropdown:SetWidth(width or 180)
	dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2))
	for _, region in ipairs({ dropdown, control.DecrementButton, control.IncrementButton }) do
		QuestTogether:AttachSettingsTooltip(region, titleText, tooltipText)
	end
	local function Populate(_, root)
		root:SetMinimumWidth(dropdown:GetWidth())
		for _, entry in ipairs(BuildDropdownEntries(control)) do
			root:CreateHighlightRadio(entry.text, entry.checked, entry.func)
		end
	end
	control.gamepadGenerator = Populate
	local choice = QuestTogether:ConfigureGamepadDropdown(dropdown, Populate, nil, "settings")
	if choice then QuestTogether:AttachSettingsTooltip(choice, titleText, tooltipText) end
	QuestTogether:ConfigureGamepadDropdownSteppers(control, function() return BuildDropdownEntries(control) end)
	return control
end

local function CreateSettingsSlider(parent, titleText, tooltipText, x, y, minimum, maximum, step, plainNumber, formatter)
	local control = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	control:SetSize(360, 20)
	control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	local title = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("BOTTOMLEFT", control, "TOPLEFT", 0, 8)
	title:SetText(titleText)
	control.title = title
	control:Init(minimum, minimum, maximum, (maximum - minimum) / step, {
		[MinimalSliderWithSteppersMixin.Label.Right] = formatter or function(value)
			return string.format(plainNumber and "%d" or "%d%%", math.floor(value + 0.5))
		end,
	})
	if control.Slider.SetNarrationLabelRegion then control.Slider:SetNarrationLabelRegion(title) end
	for _, region in ipairs({ control.Slider, control.Back, control.Forward }) do
		QuestTogether:AttachSettingsTooltip(region, titleText, tooltipText)
	end
	return control
end

-- The native control owns formatting, arrows and interaction scripts. Profile
-- refreshes use its value API without persisting the resulting callback.
local function ConfigureSettingsSlider(control, getValue, onValueChanged)
	control.RefreshValue = function(self)
		self.qtRefreshing = true
		self:SetValue(getValue())
		self.qtRefreshing = nil
	end
	control:RegisterCallback("OnValueChanged", function(self, value)
		if not self.qtRefreshing then onValueChanged(value) end
	end, control)
	control:RefreshValue()
end

function QuestTogether:CreateQuestFocusSlider(parent, title, x, y, minimum, maximum, step, getValue, setValue, percent, tooltip)
	local slider = CreateSettingsSlider(parent, title, tooltip, x, y, minimum, maximum, step, not percent)
	ConfigureSettingsSlider(slider, getValue, setValue)
	return slider
end

local scrollPanelSequence = 0
local function CreateScrollablePanelContent(parent, minimumHeight)
	local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
	scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 0)

	local content = CreateFrame("Frame", nil, scrollFrame)
	content:SetSize(672, minimumHeight or 600)
	scrollFrame:SetScrollChild(content)
	scrollPanelSequence = scrollPanelSequence + 1
	local workKey = "settings_scrollbar_" .. scrollPanelSequence
	local scrollbar, refreshing
	local function RefreshScroll(value)
		if refreshing then return end
		if not QuestTogether:CanMutateOwnedUI(scrollFrame) or not QuestTogether:CanMutateOwnedUI(content) then
			QuestTogether:ScheduleRuntimeWork("foreign_frame_mutation", workKey, function() RefreshScroll() end,
				{ lifetime = "ui", reason = "settings scrollbar refresh" })
			return
		end
		refreshing = true
		content:SetWidth(math.max(672, scrollFrame:GetWidth() - 8))
		if not scrollbar then
			scrollbar = QuestTogether:CreateOwnedScrollBar(QuestTogether.CreateOwnedWindowFrame, parent, false,
				function(offset) RefreshScroll(offset) end)
			scrollbar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 10, -4)
			scrollbar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 10, 4)
			scrollFrame.ScrollBar = scrollbar
		end
		local maximum = math.max(0, scrollFrame:GetVerticalScrollRange())
		local offset = math.max(0, math.min(maximum, value or scrollFrame:GetVerticalScroll()))
		scrollFrame:SetVerticalScroll(offset)
		QuestTogether:UpdateOwnedScrollBar(scrollbar, offset, maximum, scrollFrame:GetHeight(), 30)
		refreshing = nil
	end
	scrollFrame:SetScript("OnSizeChanged", function() RefreshScroll() end)
	scrollFrame:SetScript("OnScrollRangeChanged", function() RefreshScroll() end)
	scrollFrame:SetScript("OnVerticalScroll", function() RefreshScroll() end)
	scrollFrame:SetScript("OnShow", function() RefreshScroll() end)
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", function(_, delta)
		if QuestTogether:CanMutateOwnedUI(scrollFrame) then RefreshScroll(scrollFrame:GetVerticalScroll() - delta * 30) end
	end)
	RefreshScroll()

	return scrollFrame, content
end

function QuestTogether:ApplyOptionsDropdownSelection(optionKey, value)
	-- This choice opens/closes native chat windows. A stale Settings dropdown
	-- must recheck restrictions just like the minimap and chat context menus.
	if optionKey == "chatLogDestination" and self:IsRuntimeRestricted() then return false end
	if not self:SetOption(optionKey, value) then return false end
	self:RefreshOptionsWindow()
	return true
end

local function CreateOptionDropdown(parent, titleText, tooltipText, x, y, width, values, getLabel, optionKey, currentValueGetter)
	return CreateDropdown(
		parent,
		titleText,
		tooltipText,
		x,
		y,
		width,
		function(dropdown)
			for _, value in ipairs(values) do
				local info = {}
				info.text = getLabel(value)
				info.func = function()
					QuestTogether:ApplyOptionsDropdownSelection(optionKey, value)
				end
				info.checked = function() return currentValueGetter() == value end
				dropdown.entries[#dropdown.entries + 1] = info
			end
		end
	)
end

local function CreateShowProgressForDropdown(parent, x, y)
	return CreateOptionDropdown(
		parent,
		L("Show Announcements For"),
		L("Party Only shows announcements from your group. Party and Nearby also includes players within your Nearby Range or visible nearby. Looking-for-partners announcements reach the whole zone."),
		x,
		y,
		200,
		QuestTogether.showProgressForOrder,
		function(value)
			return QuestTogether:GetShowProgressForLabel(value)
		end,
		"showProgressFor",
		function()
			return QuestTogether:GetOption("showProgressFor")
		end
	)
end

local function OwnChatBubbleModeLabel(mode)
	if mode == "solo" then return L("Show only when solo") end
	if mode == "party" then return L("Show only when in a party") end
	if mode == "hidden" then return L("Hide always") end
	return L("Show always")
end

local function CreateQTChatScopeDropdown(parent, x, y)
	return CreateOptionDropdown(parent, L("QT Chat Scope"),
		L("Global shows all received QT chat. Zone Only shows players whose recent shared location is in your zone; unknown or stale locations are hidden."),
		x, y, 140, { "zone_only", "global" },
		function(value) return value == "zone_only" and L("Zone Only") or L("Global") end,
		"qtChatScope", function() return QuestTogether:GetOption("qtChatScope") end)
end

local function CreateChatLogDestinationDropdown(parent, x, y)
	return CreateOptionDropdown(
		parent,
		L("Chat Log Destination"),
		L("Choose whether QuestTogether chat logs print to your main chat frame or a dedicated QuestTogether chat frame."),
		x,
		y,
		190,
		QuestTogether.chatLogDestinationOrder,
		function(value)
			return QuestTogether:GetChatLogDestinationLabel(value)
		end,
		"chatLogDestination",
		function()
			return QuestTogether:GetOption("chatLogDestination")
		end
	)
end

local function CreateNameplateIconStyleDropdown(parent, x, y, playerPlates)
	return CreateOptionDropdown(
		parent,
		playerPlates and L("Player Icon Style") or L("Quest Icon Style"),
		L("Left, Right and Top position the icon around the health bar. Prefix puts it beside the name. On names-only player plates, all positions use the name instead; Left and Prefix match."),
		x,
		y,
		140,
		QuestTogether.nameplateQuestIconStyleOrder,
		function(styleKey)
			return QuestTogether:GetNameplateQuestIconStyleLabel(styleKey)
		end,
		playerPlates and "nameplatePlayerIconStyle" or "nameplateQuestIconStyle",
		function()
			return playerPlates and QuestTogether:GetNameplatePlayerIconStyle()
				or QuestTogether:GetNameplateQuestIconStyle()
		end
	)
end

-- Every boolean control uses the same schema as SetOption. Adding a setting
-- must not require a second, manually maintained list just to display its value.
local function RefreshCheckboxOptions(controls, addon)
	if type(controls) ~= "table" then return end
	addon = addon or QuestTogether
	for key, control in pairs(controls) do
		if type(addon.DEFAULTS.profile[key]) == "boolean" and type(control) == "table"
			and type(control.SetChecked) == "function" then
			control:SetChecked(addon:GetOption(key) == true)
		end
	end
end

local function RefreshDropdownControl(dropdown, labelText)
	if dropdown.gamepadGenerator then QuestTogether:ConfigureGamepadDropdown(dropdown.Dropdown, dropdown.gamepadGenerator) end
	dropdown.Dropdown:SetDefaultText(labelText)
	if not QuestTogether:IsNativeGamepadMode() then dropdown.Dropdown:GenerateMenu()
	else dropdown:UpdateSteppers() end
end

local function SetLabeledControlShown(control, shown)
	if not control then
		return
	end
	if not shown and not QuestTogether:PrepareGamepadControlHide(control) then return end

	if control.SetShown then
		control:SetShown(shown)
	end
	if control.Label and control.Label.SetShown then
		control.Label:SetShown(shown)
	end
	if control.title and control.title.SetShown then
		control.title:SetShown(shown)
	end
end

local function RefreshPlayerPlateNamesOnlyNotice(controls, namesOnly)
	local notice = controls.namesOnlyNotice
	if not notice then return end
	if not QuestTogether:CanMutateOwnedUI(notice)
		or (not namesOnly and notice:IsShown()
			and not QuestTogether:PrepareGamepadControlHide(notice, controls.nameplatePlayerIconEnabled)) then
		QuestTogether:ScheduleRuntimeWork("foreign_frame_mutation", "player_names_only_notice", function()
			QuestTogether:RefreshQuestPlatesWindow(true)
		end, { lifetime = "ui", reason = "player nameplate notice refresh" })
		return
	end
	local extraHeight = 0
	if namesOnly then
		-- Measure wrapped localized text instead of reserving an English-only row.
		notice:SetHeight(12 + notice.heading:GetStringHeight() + 6 + notice.body:GetStringHeight() + 12 + 24 + 12)
		notice.settingsButton:SetWidth(math.min(596, math.max(220, notice.settingsButton:GetFontString():GetStringWidth() + 32)))
		extraHeight = notice:GetHeight() + 16
	end
	notice:SetShown(namesOnly)
	controls.playerTooltipHeader:ClearAllPoints()
	controls.playerTooltipHeader:SetPoint("TOPLEFT", controls.content, "TOPLEFT", 16, -428 - extraHeight)
	controls.playerTooltipIdentifierDropdown.title:ClearAllPoints()
	controls.playerTooltipIdentifierDropdown.title:SetPoint("TOPLEFT", controls.content, "TOPLEFT", 16, -456 - extraHeight)
	controls.content:SetHeight(560 + extraHeight)
end

local function RefreshQuestPlatesPreview(controls)
	if type(controls) ~= "table" then
		return
	end

	local previewFrame = controls.previewFrame
	local previewUnitFrame = controls.previewUnitFrame
	if not IsFrameMutable(previewUnitFrame) or not previewUnitFrame.healthBar then
		return
	end

	if previewUnitFrame.SetScale then
		previewUnitFrame:SetScale(QUEST_PLATE_PREVIEW_SCALE)
	end

	local nameplateStyle = GetNumericCVarValue("nameplateStyle", NAMEPLATE_STYLE_MODERN)
	local nameplateSize = GetNumericCVarValue("nameplateSize", NAMEPLATE_SIZE_MEDIUM)
	local infoDisplayMask = GetNumericCVarValue("nameplateInfoDisplay", 0)
	local forever = QuestTogether:UsesRegionalPlayerNames()
	local namesOnly = controls.playerPlates == true
		and GetNumericCVarValue("nameplateShowOnlyNameForFriendlyPlayerUnits", 0) == 1
	RefreshPlayerPlateNamesOnlyNotice(controls, namesOnly)
	-- This frame and all its members are QT-owned. Reuse the live icon geometry
	-- without registering a native preview unit or editing Blizzard setup tables.
	previewUnitFrame.showOnlyName = namesOnly
	local scaleData = NAMEPLATE_PREVIEW_SCALES[nameplateSize] or NAMEPLATE_PREVIEW_SCALES[NAMEPLATE_SIZE_MEDIUM]
	local horizontalScale = scaleData.horizontal or 1
	local verticalScale = scaleData.vertical or 1
	local classic = nameplateStyle == NAMEPLATE_STYLE_CLASSIC
	if classic and nameplateSize == 1 then horizontalScale = verticalScale end
	local largeHealthBar = nameplateStyle == NAMEPLATE_STYLE_MODERN
		or nameplateStyle == NAMEPLATE_STYLE_BLOCK
		or nameplateStyle == NAMEPLATE_STYLE_HEALTH_FOCUS
	local nameInsideHealthBar = nameplateStyle == NAMEPLATE_STYLE_MODERN or nameplateStyle == NAMEPLATE_STYLE_BLOCK
	-- Retail's outer plate includes two 12-pixel scaled content insets.
	-- Enlarge the entire sample uniformly, not just the health bar.
	local barWidth = ((classic and 152 or 230) - 24) * horizontalScale
	local barHeight = (largeHealthBar and 20 or 10) * verticalScale
	local nameFontSize = (classic and 10 or 12) * verticalScale
	if forever then
		-- Camelot constants: 190-wide plate (152 in Classic), 12-pixel side
		-- insets, 13/20-pixel health, 14-point names. Scale the whole preview
		-- uniformly, rather than enlarging only the bar relative to its text.
		barWidth = ((classic and 152 or 190) - 24) * horizontalScale
		barHeight = (classic and 10 or largeHealthBar and 20 or 13) * verticalScale
		-- The enlarged friendly-player sample uses a smaller label; real native
		-- nameplate fonts are never modified by this preview.
		nameFontSize = (classic and 10 or controls.playerPlates and 12 or 14) * verticalScale
	end

	local healthContainer = previewUnitFrame.HealthBarsContainer
	if healthContainer and healthContainer.SetSize then
		healthContainer:SetSize(barWidth, barHeight)
		healthContainer:ClearAllPoints()
		healthContainer:SetPoint("CENTER", previewUnitFrame, "CENTER", 0, nameInsideHealthBar and 0 or -6)
	end

	if previewUnitFrame.SetSize then
		local frameWidth = barWidth + 140
		local frameHeight = math.max(72, barHeight + (nameInsideHealthBar and 34 or 50))
		previewUnitFrame:SetSize(frameWidth, frameHeight)
	end
	if previewFrame and previewUnitFrame.ClearAllPoints and previewUnitFrame.SetPoint then
		previewUnitFrame:ClearAllPoints()
		previewUnitFrame:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)
	end

	local nameLabel = previewUnitFrame.name
	local healthText = previewUnitFrame.questPreviewHealthText
	local healthInsideBar = nameInsideHealthBar or forever or classic
	local nameFont = (forever or nameInsideHealthBar) and "SystemFont_NamePlate_Outlined" or "SystemFont_NamePlate"
	local classR, classG, classB
	if not forever and controls.playerPlates then
		classR, classG, classB = QuestTogether.API.GetPlayerNameplatePreviewClassColor()
	end
	if nameLabel then
		if nameLabel.SetFontObject then
			nameLabel:SetFontObject(nameFont)
		end
		local fontPath, _, fontFlags = nameLabel:GetFont()
		if fontPath and nameLabel.SetFont then
			nameLabel:SetFont(fontPath, nameFontSize, fontFlags)
		end
		nameLabel:ClearAllPoints()
		if nameLabel.SetDrawLayer then
			nameLabel:SetDrawLayer("OVERLAY", 7)
		end
		local centered = namesOnly or classic or (forever and not nameInsideHealthBar)
		if nameLabel.SetJustifyH then nameLabel:SetJustifyH(centered and "CENTER" or "LEFT") end
		if nameLabel.SetWidth then nameLabel:SetWidth(math.max(1, barWidth - 8)) end
		if centered and healthContainer then
			-- Center on the health bar, not on the combined bar and level badge.
			if nameInsideHealthBar then
				nameLabel:SetPoint("CENTER", healthContainer, "CENTER", 0, 0)
			else
				nameLabel:SetPoint("BOTTOM", healthContainer, "TOP", 0, namesOnly and 2 or (classic and 4 or 2) * verticalScale)
			end
		elseif nameInsideHealthBar and healthContainer then
			nameLabel:SetPoint("LEFT", healthContainer, "LEFT", 4, 0)
		elseif healthContainer then
			nameLabel:SetPoint("BOTTOMLEFT", healthContainer, "TOPLEFT", 4, 2 * verticalScale)
		else
			nameLabel:SetPoint("TOP", previewUnitFrame, "TOP", 0, 0)
		end
		if classR and GetNumericCVarValue("nameplateUseClassColorForFriendlyPlayerUnitNames", 0) == 1 then
			nameLabel:SetTextColor(classR, classG, classB, 1)
		elseif nameplateStyle == NAMEPLATE_STYLE_LEGACY and nameLabel.SetTextColor then
			if controls.playerPlates then
				nameLabel:SetTextColor(0.22, 0.80, 0.22, 1)
			else
				nameLabel:SetTextColor(1, 0, 0, 1)
			end
		elseif nameLabel.SetTextColor then
			nameLabel:SetTextColor(1, 1, 1, 1)
		end
	end

	local healthBar = previewUnitFrame.healthBar
	healthBar:SetShown(not namesOnly)
	local baseFill = previewUnitFrame.questPreviewBaseFillTexture
	local tintOverlay = previewUnitFrame.questPreviewTintTexture
	local tintHighlight = previewUnitFrame.questPreviewTintHighlight
	local background = previewUnitFrame.questPreviewHealthBackground
	healthBar:ClearAllPoints()
	if classic then
		healthBar:SetPoint("TOPLEFT", healthContainer, "TOPLEFT", 3.5 * horizontalScale, 0.5 * verticalScale)
		healthBar:SetPoint("BOTTOMRIGHT", healthContainer, "BOTTOMRIGHT", -20.75 * horizontalScale, 0.5 * verticalScale)
	else
		healthBar:SetAllPoints(healthContainer)
	end
	if background then
		background:ClearAllPoints()
		if classic then
			background:SetTexture("Interface\\Tooltips\\Nameplate-Border")
			background:SetTexCoord(0, 1, 0.5, 1)
			if background.SetTextureSliceMargins then background:SetTextureSliceMargins(0, 0, 0, 0) end
			background:SetDrawLayer("ARTWORK", 1)
			background:SetPoint("CENTER", healthContainer, "CENTER", 0, 0)
			background:SetSize(128 * horizontalScale, 16 * verticalScale)
		else
			background:SetAtlas("UI-HUD-CoolDownManager-Bar-BG", true)
			background:SetTexCoord(0, 1, 0, 1)
			background:SetDrawLayer("BACKGROUND")
			background:SetPoint("TOPLEFT", healthBar, "TOPLEFT", -2, 3)
			background:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 6, -6)
		end
	end
	if previewUnitFrame.questPreviewDeselectedOverlay then
		previewUnitFrame.questPreviewDeselectedOverlay:SetShown(not classic)
	end
	if healthBar and healthBar.SetMinMaxValues and healthBar.SetValue then
		healthBar:SetMinMaxValues(0, 100)
		healthBar:SetValue(100)
	end
	if baseFill then
		if classic then baseFill:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
		else baseFill:SetAtlas(QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS or "UI-HUD-CoolDownManager-Bar", true) end
		AnchorPreviewFillTexture(baseFill, healthBar)
		baseFill:Show()
	end
	if tintOverlay then
		AnchorPreviewFillTexture(tintOverlay, healthBar)
	end
	if tintHighlight then
		AnchorPreviewFillTexture(tintHighlight, healthBar)
	end
	local level = previewUnitFrame.PlayerLevelDiffFrame
	local sampleLevel
	if forever or classic then
		sampleLevel = QuestTogether:SafeToNumber(QuestTogether.API.UnitLevel("player"))
		if not sampleLevel or sampleLevel < 1 or sampleLevel > 1000 then sampleLevel = 20 end
		sampleLevel = tostring(math.floor(sampleLevel))
	end
	if level then
		level:SetShown(forever and not namesOnly)
		if forever then
			level.playerLevelDiffIcon:SetAtlas("ui-hud-nameplates-levelindicator", true)
			level:ClearAllPoints()
			level:SetWidth(28 * horizontalScale)
			level:SetPoint("TOPLEFT", healthBar, "TOPRIGHT", 5, 3)
			level:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMRIGHT", 5, -2)
			level.playerLevelDiffText:SetText(sampleLevel)
			level.playerLevelDiffText:SetFontObject("SystemFont_NamePlateLevel")
			local path, _, flags = level.playerLevelDiffText:GetFont()
			if path then level.playerLevelDiffText:SetFont(path, 10 * verticalScale, flags) end
			-- A same-level quest mob is fair difficulty; friendly levels are white.
			level.playerLevelDiffText:SetTextColor(1, controls.playerPlates and 1 or 0.82, controls.playerPlates and 1 or 0, 1)
		end
	end
	local classicLevel = previewUnitFrame.questPreviewClassicLevel
	if classicLevel then
		classicLevel:SetShown(classic and not namesOnly)
		if classic then
			classicLevel:ClearAllPoints()
			classicLevel:SetPoint("CENTER", background, "RIGHT", -11 * horizontalScale, 0)
			classicLevel:SetText(sampleLevel)
			classicLevel:SetFontObject("SystemFont_NamePlateLevel")
			local path, _, flags = classicLevel:GetFont()
			if path then classicLevel:SetFont(path, 10 * verticalScale, flags) end
			classicLevel:SetTextColor(1, controls.playerPlates and 1 or 0.82, controls.playerPlates and 1 or 0, 1)
		end
	end

	local tintEnabled = not controls.playerPlates
		and QuestTogether:GetOption("nameplateQuestHealthColorEnabled") == true
	local enemyBarColor = { r = 0.82, g = 0.14, b = 0.14 }
	local previewBarColor = controls.playerPlates and { r = 0.22, g = 0.80, b = 0.22 } or enemyBarColor
	if classR and GetNumericCVarValue("nameplateShowFriendlyClassColor", 0) == 1 then
		previewBarColor = { r = classR, g = classG, b = classB }
	end
	if tintEnabled then
		previewBarColor = GetColorOption("nameplateQuestHealthColor", QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR)
	end
	if baseFill and baseFill.SetVertexColor then
		baseFill:SetVertexColor(previewBarColor.r, previewBarColor.g, previewBarColor.b, 1)
	end

	-- For preview accuracy keep the fill opaque and avoid additive tints.
	if tintOverlay and tintOverlay.Hide then
		tintOverlay:Hide()
	end
	if tintHighlight and tintHighlight.Hide then
		tintHighlight:Hide()
	end

	if healthText then
		healthText:SetFontObject(healthInsideBar and "SystemFont_NamePlate_Outlined" or "SystemFont_NamePlate")
		local path, _, flags = healthText:GetFont()
		if path then healthText:SetFont(path, nameFontSize, flags) end
		if healthText.SetDrawLayer then
			healthText:SetDrawLayer("OVERLAY", 7)
		end
		if healthText.SetJustifyH then
			healthText:SetJustifyH("RIGHT")
		end
		healthText:ClearAllPoints()
		if healthInsideBar and healthContainer then
			healthText:SetPoint("RIGHT", healthBar, "RIGHT", -4, not forever and classic and -0.5 or 0)
		elseif healthContainer then
			healthText:SetPoint("BOTTOMRIGHT", healthBar, "TOPRIGHT", -4, 2)
		end

		local showPercent = HasBit(infoDisplayMask, NAMEPLATE_INFO_PERCENT)
		local showValue = HasBit(infoDisplayMask, NAMEPLATE_INFO_VALUE)
		if not namesOnly and (showPercent or showValue) then
			if showPercent and showValue then
				healthText:SetText("241 K  100%")
			elseif showValue then
				healthText:SetText("241 K")
			else
				healthText:SetText("100%")
			end
			healthText:Show()
		else
			healthText:Hide()
		end
		if (nameInsideHealthBar or not healthInsideBar) and not namesOnly and nameLabel then
			local reserved = healthText:IsShown() and ((QuestTogether:SafeToNumber(healthText:GetStringWidth()) or 0) + 2) or 0
			nameLabel:SetWidth(math.max(1, barWidth - 8 - reserved))
		end
	end

	local previewIconFrame = controls.previewIconFrame
	local previewIcon = controls.previewIconTexture
	if not previewIconFrame or controls.previewIconOwner ~= previewUnitFrame then
		local iconParent = previewUnitFrame
		previewIconFrame = CreateFrame("Frame", nil, iconParent)
		previewIconFrame:SetFrameStrata("HIGH")
		local parentFrameLevel = 0
		if healthContainer and healthContainer.GetFrameLevel and QuestTogether.SafeToNumber then
			parentFrameLevel = QuestTogether:SafeToNumber(healthContainer:GetFrameLevel()) or 0
		elseif iconParent and iconParent.GetFrameLevel and QuestTogether.SafeToNumber then
			parentFrameLevel = QuestTogether:SafeToNumber(iconParent:GetFrameLevel()) or 0
		end
		previewIconFrame:SetFrameLevel(parentFrameLevel + 30)

		previewIcon = previewIconFrame:CreateTexture(nil, "OVERLAY")
		previewIcon:SetAllPoints()
		previewIconFrame.Icon = previewIcon

		controls.previewIconFrame = previewIconFrame
		controls.previewIconTexture = previewIcon
		controls.previewIconOwner = previewUnitFrame
	end

	local showIcon = QuestTogether:GetOption(
		controls.playerPlates and "nameplatePlayerIconEnabled" or "nameplateQuestIconEnabled"
	) == true
	if showIcon then
		if controls.playerPlates then
			QuestTogether:SetNameplateIconKind(previewIconFrame, "player")
		else
			ApplyAnnouncementGroupIcon(previewIcon, "nameplatePreview")
		end
		if QuestTogether.ApplyNameplateQuestIconStyle then
			QuestTogether:ApplyNameplateQuestIconStyle(previewIconFrame, previewUnitFrame)
		else
			previewIconFrame:ClearAllPoints()
			previewIconFrame:SetPoint("BOTTOM", previewUnitFrame.HealthBarsContainer, "TOP", 0, 11)
		end
		previewIconFrame:Show()
	else
		previewIconFrame:Hide()
	end

	if IsFrameMutable(previewFrame) and previewFrame.Preview then
		previewFrame.Preview:SetText(
			controls.playerPlates and L("Previewing - QuestTogether Player") or L("Previewing - Quest Mob")
		)
	end
end

function QuestTogether:RefreshOptionsWindow()
	self:RefreshWindowThemes()
	self:RefreshHomeWindow()
	self:RefreshAnnouncementsWindow()
	self:RefreshWhereToAnnounceWindow()
	self:RefreshQuestPlatesWindow()
	self:RefreshQuestPlatesWindow(true)
	self:RefreshGroupsWindow()
	self:RefreshTrackerSettingsWindow()
	self:RefreshLauncherSettingsWindow()
	self:RefreshDataBrokerWindow()
	self:RefreshAccessibilityWindow()
	self:RefreshEmotesWindow()
	self:RefreshAudioWindow()
	RefreshCheckboxOptions(self.experimentalControls)
	RefreshCheckboxOptions(self.developerControls, self)
	self:RefreshPlayerLocationsWindow()
end

local function GetPlayerLocationFilterChoice(addon)
	return addon:GetPlayerMapVisibilityChoice()
end

local function GetPlayerLocationFilterLabels()
	return { L("All QuestTogether players"), L("Players looking for questing partners"), L("None") }
end

function QuestTogether:RefreshPlayerLocationsWindow()
	if not self.playerLocationsFrame then return end
	RefreshCheckboxOptions(self.playerLocationsControls, self)
	local filter = self.playerLocationsControls.filterDropdown
	if filter then
		RefreshDropdownControl(filter, GetPlayerLocationFilterLabels()[GetPlayerLocationFilterChoice(self)])
	end
	if self.playerLocationsControls.Layout then self.playerLocationsControls:Layout() end
end

-- Only addon runtime/profile metadata belongs on the home page. Feature choices
-- live in their settings categories; do not maintain a second summary dashboard.
function QuestTogether:GetHomeStatusText()
	local function Line(label, value) return label .. ": " .. value end
	local text = Line(L("QuestTogether"), self.isEnabled and L("Enabled") or L("Disabled"))
		.. " · " .. Line(L("Active profile"), SafeText(self:GetCurrentProfileKey() or self.activeProfileKey, L("Unknown")))
		.. " · " .. Line(L("Version"), SafeText(self:GetAddonVersion(), L("Unknown")))
	local update = self:GetAvailableAddonUpdate()
	if update then text = text .. "\n" .. Line(L("Newer version detected"), SafeText(update)) end
	return text
end

function QuestTogether:RefreshHomeWindow()
	if not self.optionsFrame then return end
	local ui = self.homeControls
	RefreshCheckboxOptions(ui, self)
	local _, label = self:GetMatchingPreset()
	ui.presets:SetText(L("Presets") .. ": " .. label)
	ui.statusText:SetText(self:GetHomeStatusText())
	ui:Layout()
end

function QuestTogether:RefreshLauncherSettingsWindow()
	if not self.launcherSettingsFrame then return end
	RefreshCheckboxOptions(self.launcherSettingsControls, self)
	self.launcherSettingsControls:Layout()
end

function QuestTogether:RefreshDataBrokerWindow()
	if not self.dataBrokerFrame then return end
	local ui = self.dataBrokerControls
	RefreshCheckboxOptions(ui, self)
	ui.reload:SetShown(self.dataBrokerReloadRequired == true)
	for _, key in ipairs({ "brokerLeftClick", "brokerRightClick" }) do
		local action = self:GetDataBrokerAction(key)
		for _, option in ipairs(self:GetDataBrokerActionOptions()) do
			if option.value == action then RefreshDropdownControl(ui[key .. "Dropdown"], option.text); break end
		end
	end
	ui:Layout()
end

function QuestTogether:RefreshAccessibilityWindow()
	if not self.accessibilityFrame then return end
	local ui = self.accessibilityControls
	RefreshCheckboxOptions(ui, self)
	ui.scale:RefreshValue()
	RefreshDropdownControl(ui.themeDropdown, self:GetOption("lightMode") == true and L("Light") or L("Dark"))
	ui:Layout()
end

function QuestTogether:RefreshEmotesWindow()
	if not self.emotesFrame then return end
	RefreshCheckboxOptions(self.emotesControls, self)
	self.emotesControls:Layout()
end

function QuestTogether:RefreshWhereToAnnounceWindow()
	if not self.whereToAnnounceFrame then
		return
	end

	local controls = self.whereToAnnounceControls
	RefreshCheckboxOptions(controls)

	if controls.chatLogDestinationDropdown then
		RefreshDropdownControl(
			controls.chatLogDestinationDropdown,
			self:GetChatLogDestinationLabel(self:GetOption("chatLogDestination"))
		)
	end

	if controls.qtChatScopeDropdown then
		RefreshDropdownControl(controls.qtChatScopeDropdown, self:GetOption("qtChatScope") == "zone_only" and L("Zone Only") or L("Global"))
	end
	local showBubbleControls = self:GetOption("showChatBubbles") and true or false
	if controls.ownChatBubbleModeDropdown then
		local dropdown = controls.ownChatBubbleModeDropdown
		RefreshDropdownControl(dropdown, OwnChatBubbleModeLabel(self:GetOwnChatBubbleMode()))
		dropdown:SetEnabled(showBubbleControls)
		dropdown:SetAlpha(showBubbleControls and 1 or 0.5)
		dropdown.title:SetAlpha(showBubbleControls and 1 or 0.5)
	end
	if controls.personalBubbleEditHint then
		controls.personalBubbleEditHint:SetShown(showBubbleControls)
	end
	if controls.openHudEditMode then
		SetLabeledControlShown(controls.openHudEditMode, showBubbleControls)
	end

	local showChatLogControls = self:GetOption("showChatLogs")
	local showMirrorChatLogControl = showChatLogControls and self:GetOption("chatLogDestination") == "separate"
	if controls.chatLogDestinationDropdown then
		controls.chatLogDestinationDropdown:SetEnabled(showChatLogControls)
		controls.chatLogDestinationDropdown:SetAlpha(showChatLogControls and 1 or 0.5)
		if controls.chatLogDestinationDropdown.title then
			controls.chatLogDestinationDropdown.title:SetAlpha(showChatLogControls and 1 or 0.5)
		end
	end
	if controls.mirrorChatLogsToMainChat then
		SetLabeledControlShown(controls.mirrorChatLogsToMainChat, showMirrorChatLogControl)
	end
end

function QuestTogether:RefreshQuestPlatesWindow(playerPlates)
	if not self[playerPlates and "playerPlatesFrame" or "questPlatesFrame"] then
		return
	end

	local controls = self[playerPlates and "playerPlateControls" or "questPlateControls"]
	RefreshCheckboxOptions(controls)
	if controls.playerTooltipIdentifierDropdown then
		RefreshDropdownControl(controls.playerTooltipIdentifierDropdown, self:GetPlayerTooltipIdentifierModeLabel())
	end

	if controls.nameplateQuestIconStyleDropdown then
		RefreshDropdownControl(
			controls.nameplateQuestIconStyleDropdown,
			self:GetNameplateQuestIconStyleLabel(
				playerPlates and self:GetNameplatePlayerIconStyle() or self:GetNameplateQuestIconStyle()
			)
		)
	end

	if not controls.nameplateQuestHealthColor then
		RefreshQuestPlatesPreview(controls)
		return
	end
	local color = GetColorOption("nameplateQuestHealthColor", self.NAMEPLATE_QUEST_HEALTH_COLOR)
	controls.nameplateQuestHealthColor:SetColorRGB(color.r, color.g, color.b)

	if controls.resetNameplateQuestHealthColor then
		if IsColorOptionAtDefault("nameplateQuestHealthColor", self.NAMEPLATE_QUEST_HEALTH_COLOR) then
			if self:PrepareGamepadControlHide(controls.resetNameplateQuestHealthColor, controls.nameplateQuestHealthColor) then
				controls.resetNameplateQuestHealthColor:Hide()
			end
		else
			controls.resetNameplateQuestHealthColor:Show()
		end
	end

	RefreshQuestPlatesPreview(controls)
end

function QuestTogether:RefreshGroupsWindow()
	if not self.groupsFrame then return end
	local ui = self.groupsControls
	RefreshCheckboxOptions(ui, self)
	if ui.audience then
		RefreshDropdownControl(ui.audience, self:GetOption("sharingAudience") == "party" and L("Party only") or L("Normal sharing"))
	end
	if ui.Layout then ui:Layout() end
end

function QuestTogether:RefreshTrackerSettingsWindow()
	if not self.trackerSettingsFrame then return end
	local ui = self.trackerSettingsControls
	RefreshCheckboxOptions(ui, self)
	if self.questFocusOpacitySlider then self.questFocusOpacitySlider:RefreshValue() end
	if self.questTrackerModeDropdown then RefreshDropdownControl(self.questTrackerModeDropdown, self:GetQuestTrackerModeLabel()) end
	if self.questTrackerTooltipPlacementDropdown then RefreshDropdownControl(self.questTrackerTooltipPlacementDropdown, self:GetQuestTrackerTooltipPlacementLabel()) end
	ui:Layout()
end

-- This callback seam configures only QT-owned controls; live tests pass private
-- slider fixtures and never patch native slider mixins or globals.
function QuestTogether:ConfigureNearbyRangeSlider(slider)
	local addon = self
	-- Keep the instance in the closure; private fixtures must not consult QT's profile.
	ConfigureSettingsSlider(slider, function() return addon:GetNearbyAnnouncementRange() end, function(value)
		value = addon:NormalizeNearbyAnnouncementRange(value)
		if value then addon:SetOption("nearbyAnnouncementRange", value) end
	end)
	slider.RefreshNearbyRange = slider.RefreshValue
end

local function CreateNearbyRangeSlider(parent, x, y)
	local tooltip = L("Choose how far away to show quest updates within your current zone. The maximum includes the entire zone. Group members and visible nameplates are always included.")
	local slider = CreateSettingsSlider(parent, L("Nearby Range"), tooltip, x, y,
		QuestTogether.NEARBY_RANGE_MIN, QuestTogether.NEARBY_RANGE_MAX, 1)
	local minimum = slider.MinText
	minimum:ClearAllPoints()
	minimum:SetPoint("TOPLEFT", slider.Slider, "BOTTOMLEFT", 0, -6)
	minimum:SetText(L("Nearby"))
	minimum:Show()
	local maximum = slider.MaxText
	maximum:ClearAllPoints()
	maximum:SetPoint("TOPRIGHT", slider.Slider, "BOTTOMRIGHT", 0, -6)
	maximum:SetText(L("Entire Zone"))
	maximum:Show()
	local hint = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -28)
	hint:SetWidth(590)
	hint:SetJustifyH("LEFT")
	hint:SetText(tooltip)
	QuestTogether:ConfigureNearbyRangeSlider(slider)
	return slider
end

function QuestTogether:RefreshAnnouncementsWindow()
	if not self.announcementsFrame then
		return
	end

	RefreshCheckboxOptions(self.announcementControls)
	if self.announcementControls.nearbyRangeSlider then self.announcementControls.nearbyRangeSlider:RefreshNearbyRange() end

	if self.announcementControls.showProgressForDropdown then
		RefreshDropdownControl(
			self.announcementControls.showProgressForDropdown,
			self:GetShowProgressForLabel(self:GetOption("showProgressFor"))
		)
	end
end

local function RegisterSubcategory(parentCategory, frame, categoryName)
	if not (Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory and frame) then
		return nil
	end

	local subcategory = nil
	local ok, categoryOrError =
		pcall(Settings.RegisterCanvasLayoutSubcategory, parentCategory, frame, categoryName, categoryName)
	if ok then
		subcategory = categoryOrError
	end
	if not subcategory then
		-- Older signatures omit the extra name parameter.
		ok, categoryOrError = pcall(Settings.RegisterCanvasLayoutSubcategory, parentCategory, frame, categoryName)
		if ok then
			subcategory = categoryOrError
		end
	end
	if not subcategory then
		return nil
	end

	if Settings.RegisterAddOnCategory then
		Settings.RegisterAddOnCategory(subcategory)
	end
	return subcategory
end

-- These pages use measured rows so relocated controls keep their labels together
-- in every locale. All regions belong to QT; profile reads never apply values.
local function CreateFeatureSettingsPage(name, titleText, descriptionText)
	local frame = CreateFrame("Frame", name)
	frame.name, frame.parent = titleText, "QuestTogether"
	local _, content = CreateScrollablePanelContent(frame, 300)
	local ui = { content = content, rows = {} }
	function ui:Add(control, kind, gap, indent)
		self.rows[#self.rows + 1] = { control = control, kind = kind, gap = gap or 12, indent = indent or 16 }
		return control
	end
	function ui:Text(text, heading)
		local label = content:CreateFontString(nil, "OVERLAY", heading and "GameFontNormal" or "GameFontHighlightSmall")
		label:SetText(text); label:SetWidth(640); label:SetJustifyH("LEFT"); label:SetWordWrap(true)
		return self:Add(label, "text", heading and 22 or 12)
	end
	function ui:Check(key)
		local control = CreateCheckbox(content, key, 16, 0)
		control.Label:SetMaxLines(0)
		self[key] = self:Add(control, "checkbox")
		return control
	end
	function ui:Action(key, label, hint, callback)
		local control = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		control:SetSize(340, 26); control:SetText(label)
		QuestTogether:AttachSettingsTooltip(control, label, hint)
		control:SetScript("OnClick", callback)
		self[key] = self:Add(control, "button")
		return control
	end
	function ui:Layout()
		local y = 0
		for _, row in ipairs(self.rows) do
			local control = row.control
			-- IsShown is local visibility, so hidden parent panels still lay out.
			if control:IsShown() then
				y = y + row.gap
				local anchor = (row.kind == "dropdown" or row.kind == "slider") and control.title or control
				anchor:ClearAllPoints(); anchor:SetPoint("TOPLEFT", content, "TOPLEFT", row.indent, -y)
				if row.kind == "checkbox" then
					local height = math.max(control:GetHeight(), control.Label:GetStringHeight())
					control:ClearAllPoints(); control:SetPoint("TOPLEFT", content, "TOPLEFT", row.indent,
						-y - (height - control:GetHeight()) / 2)
					y = y + height
				elseif row.kind == "dropdown" or row.kind == "slider" then
					control:ClearAllPoints(); control:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
					y = y + anchor:GetStringHeight() + 8 + control:GetHeight()
				elseif row.kind == "text" then y = y + control:GetStringHeight()
				else y = y + control:GetHeight() end
			end
		end
		content:SetHeight(y + 32)
	end
	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetText(titleText); title:SetWidth(640); title:SetJustifyH("LEFT"); title:SetWordWrap(true)
	ui:Add(title, "text", 16)
	ui.description = ui:Text(descriptionText)
	return frame, ui
end

local function BuildProfileKeyList(excludedKey)
	local profileKeys = QuestTogether:GetProfileKeys()
	local filtered = {}
	for _, profileKey in ipairs(profileKeys) do
		if profileKey ~= excludedKey then
			filtered[#filtered + 1] = profileKey
		end
	end
	return filtered
end

function QuestTogether:RefreshProfilesWindow()
	if not self.profilesFrame then
		return
	end

	local controls = self.profileControls
	local uiState = self.profileUIState or {}
	self.profileUIState = uiState

	local currentProfileKey = self:GetCurrentProfileKey()
	local allProfileKeys = self:GetProfileKeys()
	local nonActiveProfileKeys = BuildProfileKeyList(currentProfileKey)

	if not uiState.copyFromProfileKey or uiState.copyFromProfileKey == currentProfileKey then
		uiState.copyFromProfileKey = nonActiveProfileKeys[1]
	end
	if not uiState.deleteProfileKey or uiState.deleteProfileKey == currentProfileKey then
		uiState.deleteProfileKey = nonActiveProfileKeys[1]
	end

	RefreshDropdownControl(controls.currentProfileDropdown, currentProfileKey or L("None"))
	RefreshDropdownControl(controls.copyFromProfileDropdown, uiState.copyFromProfileKey or L("No Other Profiles"))
	RefreshDropdownControl(controls.deleteProfileDropdown, uiState.deleteProfileKey or L("No Other Profiles"))

	local canCopy = uiState.copyFromProfileKey ~= nil
	local canDelete = uiState.deleteProfileKey ~= nil

	controls.copyFromProfileDropdown:SetEnabled(canCopy)
	controls.deleteProfileDropdown:SetEnabled(canDelete)

	controls.copyButton:SetEnabled(canCopy)
	controls.deleteButton:SetEnabled(canDelete)

	local characterKey = SafeText(self.activeCharacterKey or self:GetCurrentCharacterKey() or L("Unknown"), L("Unknown"))
	controls.profileSummary:SetText(
		string.format(
			L("Character: %s\nActive profile: %s\nSaved profiles: %d"),
			characterKey,
			SafeText(currentProfileKey, ""),
			#allProfileKeys
		)
	)
end

function QuestTogether:InitializeProfilesWindow(parentCategory)
	if self.profilesFrame then
		return
	end

	local frame = CreateFrame("Frame", "QuestTogetherProfilesPanel")
	frame.name = L("Profiles")
	frame.parent = "QuestTogether"

	local _, content = CreateScrollablePanelContent(frame, 560)

	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
	title:SetText(L("QuestTogether Profiles"))

	local description = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText(
		L("QuestTogether now defaults each character to its own profile. Use this page to switch, copy, create, reset, or delete profiles.")
	)

	local currentProfileDropdown = CreateDropdown(
		content,
		L("Current Profile"),
		L("Switch this character to another profile."),
		16,
		-92,
		240,
		function(dropdown)
			local currentProfileKey = QuestTogether:GetCurrentProfileKey()
			for _, profileKey in ipairs(QuestTogether:GetProfileKeys()) do
				local info = {}
				info.text = profileKey
				info.checked = function() return QuestTogether:GetCurrentProfileKey() == profileKey end
				info.func = function()
					local ok, err = QuestTogether:SetActiveProfile(profileKey)
					if not ok then
						QuestTogether:Print(SafeText(err, L("Unknown error")))
					end
					QuestTogether:RefreshProfilesWindow()
				end
				dropdown.entries[#dropdown.entries + 1] = info
			end
		end
	)

	local copyFromDropdown = CreateDropdown(
		content,
		L("Copy Into Current Profile"),
		L("Copy all settings from the selected profile into your current profile, replacing its settings."),
		16,
		-160,
		240,
		function(dropdown)
			local currentProfileKey = QuestTogether:GetCurrentProfileKey()
			for _, profileKey in ipairs(BuildProfileKeyList(currentProfileKey)) do
				local info = {}
				info.text = profileKey
				info.checked = function() return QuestTogether.profileUIState.copyFromProfileKey == profileKey end
				info.func = function()
					QuestTogether.profileUIState.copyFromProfileKey = profileKey
					QuestTogether:RefreshProfilesWindow()
				end
				dropdown.entries[#dropdown.entries + 1] = info
			end
		end
	)

	local copyButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	copyButton:SetSize(90, 22)
	if copyFromDropdown and copyFromDropdown.IncrementButton then
		copyButton:SetPoint("LEFT", copyFromDropdown.IncrementButton, "RIGHT", 16, 0)
	else
		copyButton:SetPoint("TOPLEFT", content, "TOPLEFT", 280, -185)
	end
	copyButton:SetText(L("Copy"))
	self:AttachSettingsTooltip(copyButton, L("Copy"), L("Copy all settings from the selected profile into your current profile, replacing its settings."))
	copyButton:SetScript("OnClick", function()
		local sourceProfileKey = QuestTogether.profileUIState.copyFromProfileKey
		local ok, err = QuestTogether:CopyProfileIntoActiveProfile(sourceProfileKey)
		if not ok then
			QuestTogether:Print(SafeText(err, L("Unknown error")))
			return
		end
		QuestTogether:Print(L("Copied profile settings from ") .. SafeText(sourceProfileKey, "") .. ".")
		QuestTogether:RefreshProfilesWindow()
	end)

	local createProfileTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	createProfileTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -240)
	createProfileTitle:SetText(L("Create And Switch To New Profile"))

	local createProfileEdit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	createProfileEdit:SetAutoFocus(false)
	createProfileEdit:SetSize(240, 24)
	createProfileEdit:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -264)
	createProfileEdit:SetTextInsets(6, 6, 0, 0)

	local createProfileButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	createProfileButton:SetSize(90, 22)
	createProfileButton:SetPoint("TOPLEFT", content, "TOPLEFT", 280, -266)
	createProfileButton:SetText(L("Create"))
	self:AttachSettingsTooltip(createProfileEdit, L("Create And Switch To New Profile"), L("Enter a name to create a copy of your current settings and switch to the new profile."))
	self:AttachSettingsTooltip(createProfileButton, L("Create"), L("Enter a name to create a copy of your current settings and switch to the new profile."))

	local function CreateAndActivateProfile()
		local requestedProfileName = createProfileEdit:GetText() or ""
		local ok, err = QuestTogether:CreateProfile(requestedProfileName, QuestTogether:GetCurrentProfileKey())
		if not ok then
			QuestTogether:Print(SafeText(err, L("Unknown error")))
			return
		end

		local switchOk, switchErr = QuestTogether:SetActiveProfile(requestedProfileName)
		if not switchOk then
			QuestTogether:Print(SafeText(switchErr, L("Unknown error")))
			return
		end

		createProfileEdit:SetText("")
		QuestTogether:Print(L("Created and switched to profile ") .. SafeText(QuestTogether:GetCurrentProfileKey(), "") .. ".")
		QuestTogether:RefreshProfilesWindow()
	end

	createProfileButton:SetScript("OnClick", CreateAndActivateProfile)
	createProfileEdit:SetScript("OnEnterPressed", function(editBox)
		CreateAndActivateProfile()
		editBox:ClearFocus()
	end)

	local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetButton:SetSize(180, 22)
	resetButton:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -314)
	resetButton:SetText(L("Reset Active Profile"))
	self:AttachSettingsTooltip(resetButton, L("Reset Active Profile"), L("Restore all settings in the current profile to their defaults."))
	resetButton:SetScript("OnClick", function()
		local ok, err = QuestTogether:ResetActiveProfile()
		if not ok then
			QuestTogether:Print(SafeText(err, L("Unknown error")))
			return
		end
		QuestTogether:Print(L("Reset profile ") .. SafeText(QuestTogether:GetCurrentProfileKey(), "") .. L(" to defaults."))
		QuestTogether:RefreshProfilesWindow()
	end)

	local deleteProfileDropdown = CreateDropdown(
		content,
		L("Delete Profile"),
		L("Choose another profile to delete. You cannot delete the active profile."),
		16,
		-370,
		240,
		function(dropdown)
			local currentProfileKey = QuestTogether:GetCurrentProfileKey()
			for _, profileKey in ipairs(BuildProfileKeyList(currentProfileKey)) do
				local info = {}
				info.text = profileKey
				info.checked = function() return QuestTogether.profileUIState.deleteProfileKey == profileKey end
				info.func = function()
					QuestTogether.profileUIState.deleteProfileKey = profileKey
					QuestTogether:RefreshProfilesWindow()
				end
				dropdown.entries[#dropdown.entries + 1] = info
			end
		end
	)

	local deleteButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	deleteButton:SetSize(90, 22)
	if deleteProfileDropdown and deleteProfileDropdown.IncrementButton then
		deleteButton:SetPoint("LEFT", deleteProfileDropdown.IncrementButton, "RIGHT", 16, 0)
	else
		deleteButton:SetPoint("TOPLEFT", content, "TOPLEFT", 280, -395)
	end
	deleteButton:SetText(L("Delete"))
	self:AttachSettingsTooltip(deleteButton, L("Delete"), L("Delete the selected profile and its saved settings. You cannot delete the active profile."))
	deleteButton:SetScript("OnClick", function()
		local deleteProfileKey = QuestTogether.profileUIState.deleteProfileKey
		local ok, err = QuestTogether:DeleteProfile(deleteProfileKey)
		if not ok then
			QuestTogether:Print(SafeText(err, L("Unknown error")))
			return
		end
		QuestTogether:Print(L("Deleted profile ") .. SafeText(deleteProfileKey, "") .. ".")
		QuestTogether.profileUIState.deleteProfileKey = nil
		QuestTogether.profileUIState.copyFromProfileKey = nil
		QuestTogether:RefreshProfilesWindow()
	end)

	local profileSummary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profileSummary:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -448)
	profileSummary:SetWidth(640)
	profileSummary:SetJustifyH("LEFT")
	profileSummary:SetText("")

	self.profileControls = {
		currentProfileDropdown = currentProfileDropdown,
		copyFromProfileDropdown = copyFromDropdown,
		copyButton = copyButton,
		createProfileEdit = createProfileEdit,
		createProfileButton = createProfileButton,
		resetButton = resetButton,
		deleteProfileDropdown = deleteProfileDropdown,
		deleteButton = deleteButton,
		profileSummary = profileSummary,
	}
	self.profilesFrame = frame

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshProfilesWindow()
	end)

	local profileCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	if not profileCategory and Settings and Settings.RegisterCanvasLayoutCategory then
		profileCategory = Settings.RegisterCanvasLayoutCategory(frame, L("QuestTogether Profiles"), L("QuestTogether Profiles"))
	end

	self.profilesCategory = profileCategory
	self:RefreshProfilesWindow()
end

function QuestTogether:InitializeAnnouncementsWindow(parentCategory)
	if self.announcementsFrame then
		return
	end

	local function AnnouncementCheckbox(parent, key, label, help, x, y)
		return CreateDescribedCheckbox(parent, key, label, help .. "\n\n" .. L("Uses your enabled chat and bubble outputs for the players selected above. Also controls announcements sent to party chat. Quest-data sharing continues when this is off."), x, y)
	end

	local frame = CreateFrame("Frame", "QuestTogetherAnnouncementsPanel")
	frame.name = L("What to Announce")
	frame.parent = "QuestTogether"

	local _, content = CreateScrollablePanelContent(frame, 928)

	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
	title:SetText(L("What To Announce"))

	local description = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText(L("Choose which event announcements you see. These choices also control announcements sent to party chat."))

	CreateAnnouncementGroupHeader(content, L("Announcement Scope"), "quest", 16, -82, 620)
	local showProgressForDropdown = CreateShowProgressForDropdown(content, 32, -112)
	local nearbyRangeSlider = CreateNearbyRangeSlider(content, 32, -184)

	CreateAnnouncementGroupHeader(content, L("Quests"), "quest", 16, -290, 620)
	local announceAccepted = AnnouncementCheckbox(content, "announceAccepted", L("Announce Quest Acceptance"), L("Show an announcement when a player accepts a quest."), 32, -320)
	local announceCompleted = AnnouncementCheckbox(content, "announceCompleted", L("Announce Quest Completion"), L("Show an announcement when a player turns in a completed quest."), 32, -348)
	local announceReadyToTurnIn = AnnouncementCheckbox(content, "announceReadyToTurnIn", L("Announce Ready To Turn In"), L("Show an announcement when all quest objectives are done and the quest is ready to turn in."), 32, -376)
	local announceRemoved = AnnouncementCheckbox(content, "announceRemoved", L("Announce Quest Removal"), L("Show an announcement when a player abandons or removes a quest."), 32, -404)
	local announceProgress = AnnouncementCheckbox(content, "announceProgress", L("Announce Quest Progress"), L("Show updates as players make progress on quest objectives, such as collecting items or defeating enemies."), 32, -432)

	local announceQuestStarterItems = AnnouncementCheckbox(content, "announceQuestStarterItems", L("Announce Quest-Starting Items"), L("Announce newly looted items that Blizzard identifies as starting an available quest. Ordinary quest items, bag moves and items already owned at login do not trigger this."), 32, -460)

	CreateAnnouncementGroupHeader(content, L("World Quests"), "world", 16, -506, 620)
	local announceWorldQuestAreaEnter =
		AnnouncementCheckbox(content, "announceWorldQuestAreaEnter", L("Announce Area Enter"), L("Show an announcement when a player enters a world quest area."), 32, -536)
	local announceWorldQuestAreaLeave =
		AnnouncementCheckbox(content, "announceWorldQuestAreaLeave", L("Announce Area Leave"), L("Show an announcement when a player leaves a world quest area."), 32, -564)
	local announceWorldQuestProgress = AnnouncementCheckbox(content, "announceWorldQuestProgress", L("Announce Progress"), L("Show progress updates for world quest objectives."), 32, -592)
	local announceWorldQuestCompleted =
		AnnouncementCheckbox(content, "announceWorldQuestCompleted", L("Announce Completion"), L("Show an announcement when a player finishes a world quest."), 32, -620)

	CreateAnnouncementGroupHeader(content, L("Bonus Objectives"), "bonus", 16, -666, 620)
	local announceBonusObjectiveAreaEnter =
		AnnouncementCheckbox(content, "announceBonusObjectiveAreaEnter", L("Announce Area Enter"), L("Show an announcement when a player enters a bonus objective area."), 32, -696)
	local announceBonusObjectiveAreaLeave =
		AnnouncementCheckbox(content, "announceBonusObjectiveAreaLeave", L("Announce Area Leave"), L("Show an announcement when a player leaves a bonus objective area."), 32, -724)
	local announceBonusObjectiveProgress =
		AnnouncementCheckbox(content, "announceBonusObjectiveProgress", L("Announce Progress"), L("Show progress updates for bonus objectives."), 32, -752)
	local announceBonusObjectiveCompleted =
		AnnouncementCheckbox(content, "announceBonusObjectiveCompleted", L("Announce Completion"), L("Show an announcement when a player finishes a bonus objective."), 32, -780)
	CreateAnnouncementGroupHeader(content, L("Finding Partners"), "quest", 16, -826, 620)
	local announceQuestPartners = AnnouncementCheckbox(content, "announceQuestPartners", L("Announce Looking for Questing Partners"),
		L("Send and show announcements when players start looking for questing partners. Their status and glowing icons remain visible when this is off."), 32, -856)

	self.announcementControls = {
		announceQuestPartners = announceQuestPartners,
		nearbyRangeSlider = nearbyRangeSlider,
		showProgressForDropdown = showProgressForDropdown,
		announceAccepted = announceAccepted,
		announceQuestStarterItems = announceQuestStarterItems,
		announceCompleted = announceCompleted,
		announceReadyToTurnIn = announceReadyToTurnIn,
		announceRemoved = announceRemoved,
		announceProgress = announceProgress,
		announceWorldQuestAreaEnter = announceWorldQuestAreaEnter,
		announceWorldQuestAreaLeave = announceWorldQuestAreaLeave,
		announceWorldQuestProgress = announceWorldQuestProgress,
		announceWorldQuestCompleted = announceWorldQuestCompleted,
		announceBonusObjectiveAreaEnter = announceBonusObjectiveAreaEnter,
		announceBonusObjectiveAreaLeave = announceBonusObjectiveAreaLeave,
		announceBonusObjectiveProgress = announceBonusObjectiveProgress,
		announceBonusObjectiveCompleted = announceBonusObjectiveCompleted,
	}

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshAnnouncementsWindow()
	end)

	self.announcementsFrame = frame
	self.announcementsCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshAnnouncementsWindow()
end

function QuestTogether:InitializeWhereToAnnounceWindow(parentCategory)
	if self.whereToAnnounceFrame then
		return
	end

	local frame = CreateFrame("Frame", "QuestTogetherWhereToAnnouncePanel")
	frame.name = L("Where to Announce")
	frame.parent = "QuestTogether"

	local _, content = CreateScrollablePanelContent(frame, 652)

	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
	title:SetText(L("Where To Announce"))

	local description = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText(L("Choose where quest updates and QT conversations appear."))

	local chatLogHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	chatLogHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -82)
	chatLogHeader:SetText(L("Chat Log Output"))

	local showChatLogs = CreateCheckbox(content, "showChatLogs", 16, -106)
	local chatLogDestinationDropdown = CreateChatLogDestinationDropdown(content, 36, -152)
	local mirrorChatLogsToMainChat = CreateCheckbox(content, "mirrorChatLogsToMainChat", 56, -198)

	local announceToNonQTParty = CreateCheckbox(content, "announceToNonQTParty", 16, -238)

	local showQTChat = CreateCheckbox(content, "showQTChat", 16, -278)

	local qtChatScopeDropdown = CreateQTChatScopeDropdown(content, 36, -318)

	local hidePartyChatReminder = CreateCheckbox(content, "hidePartyChatReminder", 16, -366)
	local bubbleHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bubbleHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -424)
	bubbleHeader:SetText(L("Chat Bubbles"))

	local showChatBubbles = CreateCheckbox(content, "showChatBubbles", 16, -448)
	local ownChatBubbleModeDropdown = CreateOptionDropdown(
		content,
		L("My chat bubble"),
		L("Choose when to show your own QuestTogether bubbles. Solo means outside a party or raid; party mode includes raids. Show Chat Bubbles must also be enabled. This only changes your display; your announcements are still shared."),
		36,
		-484,
		240,
		{ "always", "solo", "party", "hidden" },
		OwnChatBubbleModeLabel,
		"ownChatBubbleMode",
		function() return QuestTogether:GetOwnChatBubbleMode() end
	)

	local openHudEditMode = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	openHudEditMode:SetSize(180, 24)
	openHudEditMode:SetPoint("TOPLEFT", content, "TOPLEFT", 36, -552)
	openHudEditMode:SetText(L("Open HUD Edit Mode"))
	self:AttachSettingsTooltip(openHudEditMode, L("Open HUD Edit Mode"), L("Use HUD Edit Mode to move your personal bubble and adjust its size and duration from the QuestTogether Bubble settings panel."))
	openHudEditMode:SetScript("OnClick", function()
		if not QuestTogether:OpenHudEditMode() then
			QuestTogether:Print(L("HUD Edit Mode is unavailable right now."))
		end
	end)

	local personalBubbleEditHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	personalBubbleEditHint:SetPoint("TOPLEFT", content, "TOPLEFT", 36, -584)
	personalBubbleEditHint:SetJustifyH("LEFT")
	personalBubbleEditHint:SetWidth(560)
	personalBubbleEditHint:SetText(
		L("Use HUD Edit Mode to move your personal bubble and adjust its size and duration from the QuestTogether Bubble settings panel.")
	)

	self.whereToAnnounceControls = {
		hidePartyChatReminder = hidePartyChatReminder,
		showQTChat = showQTChat,
		qtChatScopeDropdown = qtChatScopeDropdown,
		showChatBubbles = showChatBubbles,
		ownChatBubbleModeDropdown = ownChatBubbleModeDropdown,
		showChatLogs = showChatLogs,
		announceToNonQTParty = announceToNonQTParty,
		chatLogDestinationDropdown = chatLogDestinationDropdown,
		mirrorChatLogsToMainChat = mirrorChatLogsToMainChat,
		openHudEditMode = openHudEditMode,
		personalBubbleEditHint = personalBubbleEditHint,
	}
	self.whereToAnnounceFrame = frame

	frame:SetScript("OnShow", function()
		QuestTogether:RefreshWhereToAnnounceWindow()
	end)

	self.whereToAnnounceCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshWhereToAnnounceWindow()
end

function QuestTogether:InitializeEmotesWindow(parentCategory)
	if self.emotesFrame then return end
	local frame, ui = CreateFeatureSettingsPage("QuestTogetherEmotesPanel", L("Emotes"),
		L("Choose automatic celebrations and friendly thanks. These settings do not change QT sounds."))
	ui:Text(L("Celebration Emotes"), true)
	ui:Check("emoteOnQuestCompletion")
	ui:Check("emoteOnNearbyPlayerQuestCompletion")
	ui:Check("emoteOnLevelUp")
	ui:Check("emoteOnNearbyPlayerLevelUp")
	ui:Check("autoThankBuffs")
	self.emotesFrame, self.emotesControls = frame, ui
	frame:SetScript("OnShow", function() self:RefreshEmotesWindow() end)
	self.emotesCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshEmotesWindow()
end

function QuestTogether:InitializeQuestPlatesWindow(parentCategory, playerPlates)
	local frameKey = playerPlates and "playerPlatesFrame" or "questPlatesFrame"
	local controlsKey = playerPlates and "playerPlateControls" or "questPlateControls"
	local enabledKey = playerPlates and "nameplatePlayerIconEnabled" or "nameplateQuestIconEnabled"
	if self[frameKey] then
		return
	end

	local frame =
		CreateFrame("Frame", playerPlates and "QuestTogetherPlayerPlatesPanel" or "QuestTogetherQuestPlatesPanel")
	frame.name = playerPlates and L("Player Plates") or L("Quest Plates")
	frame.parent = "QuestTogether"

	local _, content = CreateScrollablePanelContent(frame, 560)

	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
	title:SetText(frame.name)

	local description = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText(
		playerPlates
				and L("Identify friendly QuestTogether players with the scroll logo. Enable friendly nameplates in WoW to see them. Ignored players are hidden; location sharing is not required.")
			or L("Customize quest objective visuals on Blizzard nameplates.")
	)

	local nameplateQuestIconEnabled = CreateDescribedCheckbox(
		content,
		enabledKey,
		playerPlates and L("QuestTogether Player Icon") or L("Quest Objective Icon"),
		playerPlates and L("Show the QuestTogether logo beside friendly players who are using QuestTogether.")
			or L("Show a quest icon on default Blizzard nameplates when a unit is a quest objective."),
		16,
		-82
	)
	local nameplateQuestIconStyleDropdown = CreateNameplateIconStyleDropdown(content, 36, -108, playerPlates)
	local playerTooltipIdentifierDropdown, playerTooltipHeader
	if playerPlates then
		playerTooltipHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		playerTooltipHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -428)
		playerTooltipHeader:SetText(L("Player tooltips"))
		playerTooltipIdentifierDropdown = CreateOptionDropdown(content, L("QuestTogether tooltip"),
			L("Choose when to show the QuestTogether section below player tooltips, including its logo, quest-partner status, and private notes. It is always hidden on your own character."),
			16, -456, 320, { "all", "friends", "party", "friends_party", "hidden" },
			function(value) return QuestTogether:GetPlayerTooltipIdentifierModeLabel(value) end,
			"playerTooltipIdentifierMode", function() return QuestTogether:GetPlayerTooltipIdentifierMode() end)
	end
	local nameplateQuestHealthColorEnabled, nameplateQuestHealthColor, resetNameplateQuestHealthColor
	if not playerPlates then
		nameplateQuestHealthColorEnabled = CreateCheckbox(content, "nameplateQuestHealthColorEnabled", 16, -150)
		nameplateQuestHealthColor = CreateColorSwatch(
			content,
			"nameplateQuestHealthColor",
			L("Quest Health Color"),
			L("Choose the color used to tint quest-objective nameplate health bars."),
			QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR,
			36,
			-177
		)
		resetNameplateQuestHealthColor = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		resetNameplateQuestHealthColor:SetSize(70, 20)
		resetNameplateQuestHealthColor:SetPoint("LEFT", nameplateQuestHealthColor, "RIGHT", 140, 0)
		resetNameplateQuestHealthColor:SetText(L("Reset"))
		self:AttachSettingsTooltip(resetNameplateQuestHealthColor, L("Reset"), L("Restore the default quest health-bar color."))
		resetNameplateQuestHealthColor:SetScript("OnClick", function()
			local defaults = QuestTogether.DEFAULTS.profile.nameplateQuestHealthColor
				or QuestTogether.NAMEPLATE_QUEST_HEALTH_COLOR
			QuestTogether:SetOption("nameplateQuestHealthColor", {
				r = defaults.r,
				g = defaults.g,
				b = defaults.b,
			})
			QuestTogether:RefreshOptionsWindow()
		end)
	end
	local previewHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	previewHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, playerPlates and -164 or -238)
	previewHeader:SetText(L("Preview"))

	local previewHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	previewHint:SetPoint("TOPLEFT", previewHeader, "BOTTOMLEFT", 0, -4)
	previewHint:SetWidth(640)
	previewHint:SetJustifyH("LEFT")
	previewHint:SetText(L("Preview your icon with the current WoW nameplate style."))

	-- Use an isolated local frame instead of Blizzard's script nameplate preview template.
	-- This avoids registering a real preview nameplate/unit token and reduces taint risk.
	local previewFrame = CreateFrame("Frame", nil, content)
	previewFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 16, playerPlates and -206 or -280)
	previewFrame:SetSize(620, QUEST_PLATE_PREVIEW_FRAME_HEIGHT)

	local previewBackground = previewFrame:CreateTexture(nil, "BACKGROUND")
	previewBackground:SetAllPoints()
	previewBackground:SetColorTexture(0.03, 0.03, 0.05, 0.62)

	local namesOnlyNotice
	if playerPlates then
		namesOnlyNotice = CreateFrame("Frame", nil, content, "BackdropTemplate")
		namesOnlyNotice:SetPoint("TOPLEFT", previewFrame, "BOTTOMLEFT", 0, -16)
		namesOnlyNotice:SetSize(620, 116)
		namesOnlyNotice:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		namesOnlyNotice:SetBackdropColor(0.12, 0.10, 0.05, 0.85)
		namesOnlyNotice:SetBackdropBorderColor(0.65, 0.52, 0.25, 0.8)
		namesOnlyNotice:Hide()
		local heading = namesOnlyNotice:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		heading:SetPoint("TOPLEFT", 12, -12)
		heading:SetWidth(596)
		heading:SetJustifyH("LEFT")
		heading:SetWordWrap(true)
		heading:SetText(L("Names-only mode is enabled"))
		local body = namesOnlyNotice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		body:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
		body:SetWidth(596)
		body:SetJustifyH("LEFT")
		body:SetWordWrap(true)
		body:SetText(L("WoW is set to show only names for friendly players. Health bars and level badges are hidden, so QT positions its icon around the name."))
		local settingsButton = CreateFrame("Button", nil, namesOnlyNotice, "UIPanelButtonTemplate")
		settingsButton:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -12)
		settingsButton:SetSize(300, 24)
		settingsButton:SetText(L("Open Blizzard nameplate settings"))
		self:AttachSettingsTooltip(settingsButton, L("Open Blizzard nameplate settings"), L("Open WoW's nameplate settings to change names-only mode or health bars. QT does not change those settings for you."))
		settingsButton:SetScript("OnClick", function()
			if namesOnlyNotice:IsVisible() then QuestTogether.API.OpenNativeFriendlyNameplateSettings() end
		end)
		namesOnlyNotice.heading, namesOnlyNotice.body, namesOnlyNotice.settingsButton = heading, body, settingsButton
	end

	local previewCaption = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	previewCaption:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 16, -14)
	previewCaption:SetText(playerPlates and L("Previewing - QuestTogether Player") or L("Previewing - Quest Mob"))
	previewFrame.Preview = previewCaption

	local fallbackUnitFrame = CreateFrame("Frame", nil, previewFrame)
	fallbackUnitFrame:SetSize(360, 92)
	fallbackUnitFrame:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)

	local fallbackHealthBarsContainer = CreateFrame("Frame", nil, fallbackUnitFrame)
	fallbackHealthBarsContainer:SetSize(260, 18)
	fallbackHealthBarsContainer:SetPoint("TOP", fallbackUnitFrame, "TOP", 0, -26)
	fallbackUnitFrame.HealthBarsContainer = fallbackHealthBarsContainer

	local fallbackHealthBar = CreateFrame("StatusBar", nil, fallbackHealthBarsContainer)
	fallbackHealthBar:SetAllPoints()
	fallbackHealthBar:SetMinMaxValues(0, 100)
	fallbackHealthBar:SetValue(100)
	fallbackHealthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	fallbackHealthBar:SetStatusBarColor(0, 0, 0, 0)
	fallbackUnitFrame.healthBar = fallbackHealthBar
	fallbackHealthBarsContainer.healthBar = fallbackHealthBar

	-- Camelot's level badge is an ordinary owned rendering here, not a copy of
	-- Blizzard's mixin (which would register unit/CVar callbacks).
	local levelBadge = CreateFrame("Frame", nil, fallbackUnitFrame)
	levelBadge:SetFrameLevel(fallbackHealthBar:GetFrameLevel() + 20)
	levelBadge:Hide()
	levelBadge.playerLevelDiffIcon = levelBadge:CreateTexture(nil, "BACKGROUND")
	levelBadge.playerLevelDiffIcon:SetAllPoints()
	levelBadge.playerLevelDiffText = levelBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	levelBadge.playerLevelDiffText:SetPoint("CENTER", levelBadge, "CENTER", 0, 0)
	levelBadge.playerLevelDiffText:SetJustifyH("CENTER")
	fallbackUnitFrame.PlayerLevelDiffFrame = levelBadge

	local fallbackHealthBarBackground = fallbackHealthBar:CreateTexture(nil, "BACKGROUND")
	fallbackUnitFrame.questPreviewHealthBackground = fallbackHealthBarBackground
	fallbackHealthBarBackground:SetPoint("TOPLEFT", fallbackHealthBar, "TOPLEFT", -2, 3)
	fallbackHealthBarBackground:SetPoint("BOTTOMRIGHT", fallbackHealthBar, "BOTTOMRIGHT", 6, -6)
	if fallbackHealthBarBackground.SetAtlas then
		fallbackHealthBarBackground:SetAtlas("UI-HUD-CoolDownManager-Bar-BG", true)
	else
		fallbackHealthBarBackground:SetColorTexture(0.10, 0.10, 0.10, 0.82)
	end

	local fallbackBaseFill = nil
	if QuestTogether.CreateNameplateHealthOverlayTexture then
		fallbackBaseFill = QuestTogether:CreateNameplateHealthOverlayTexture(fallbackHealthBar, "ARTWORK", 0)
	end
	if not fallbackBaseFill then
		fallbackBaseFill = fallbackHealthBar:CreateTexture(nil, "ARTWORK", nil, 0)
		if fallbackBaseFill.SetAtlas then
			fallbackBaseFill:SetAtlas(QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS or "UI-HUD-CoolDownManager-Bar", true)
		else
			fallbackBaseFill:SetTexture("Interface\\Buttons\\WHITE8X8")
		end
	end
	if fallbackBaseFill then
		fallbackBaseFill:SetVertexColor(0.22, 0.80, 0.22, 1)
		fallbackUnitFrame.questPreviewBaseFillTexture = fallbackBaseFill
	end

	local fallbackTintOverlay = nil
	if QuestTogether.CreateNameplateHealthOverlayTexture then
		fallbackTintOverlay = QuestTogether:CreateNameplateHealthOverlayTexture(fallbackHealthBar, "ARTWORK", 1)
	end
	if not fallbackTintOverlay then
		fallbackTintOverlay = fallbackHealthBar:CreateTexture(nil, "ARTWORK", nil, 1)
		if fallbackTintOverlay.SetAtlas then
			fallbackTintOverlay:SetAtlas(
				QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS or "UI-HUD-CoolDownManager-Bar",
				true
			)
		else
			fallbackTintOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
		end
	end
	fallbackTintOverlay:SetVertexColor(1, 0.5, 0.1, 0.32)
	fallbackTintOverlay:Hide()
	fallbackUnitFrame.questPreviewTintTexture = fallbackTintOverlay

	local fallbackTintHighlight = fallbackHealthBar:CreateTexture(nil, "ARTWORK", nil, 2)
	fallbackTintHighlight:SetAllPoints()
	fallbackTintHighlight:SetBlendMode("ADD")
	fallbackTintHighlight:SetColorTexture(1, 0.75, 0.35, 0.16)
	fallbackTintHighlight:Hide()
	fallbackUnitFrame.questPreviewTintHighlight = fallbackTintHighlight

	local fallbackDeselectedOverlay = fallbackHealthBar:CreateTexture(nil, "OVERLAY", nil, 3)
	if fallbackDeselectedOverlay.SetAtlas then
		fallbackDeselectedOverlay:SetAtlas("ui-hud-nameplates-deselected-overlay", true)
	else
		fallbackDeselectedOverlay:SetColorTexture(0.95, 0.95, 0.95, 0.16)
	end
	fallbackDeselectedOverlay:SetPoint("TOPLEFT", fallbackHealthBar, "TOPLEFT", 0, 1)
	fallbackDeselectedOverlay:SetPoint("BOTTOMRIGHT", fallbackHealthBar, "BOTTOMRIGHT", 0, -1)
	fallbackUnitFrame.questPreviewDeselectedOverlay = fallbackDeselectedOverlay

	local fallbackSelectedBorder = fallbackHealthBar:CreateTexture(nil, "OVERLAY", nil, 4)
	if fallbackSelectedBorder.SetAtlas then
		fallbackSelectedBorder:SetAtlas("UI-HUD-Nameplates-Selected", true)
	else
		fallbackSelectedBorder:SetColorTexture(0.95, 0.95, 0.95, 0.22)
	end
	fallbackSelectedBorder:SetPoint("TOPLEFT", fallbackHealthBarBackground, "TOPLEFT", -1, 1)
	fallbackSelectedBorder:SetPoint("BOTTOMRIGHT", fallbackHealthBarBackground, "BOTTOMRIGHT", -3, 3)
	fallbackSelectedBorder:Hide()
	fallbackUnitFrame.questPreviewSelectedBorder = fallbackSelectedBorder
	local classicLevel = fallbackHealthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	classicLevel:SetJustifyH("CENTER")
	classicLevel:Hide()
	fallbackUnitFrame.questPreviewClassicLevel = classicLevel

	local fallbackTextOverlay = CreateFrame("Frame", nil, fallbackHealthBarsContainer)
	fallbackTextOverlay:SetAllPoints()
	fallbackTextOverlay:SetFrameStrata(fallbackHealthBarsContainer:GetFrameStrata() or "LOW")
	fallbackTextOverlay:SetFrameLevel((fallbackHealthBar:GetFrameLevel() or 0) + 20)
	fallbackUnitFrame.questPreviewTextOverlay = fallbackTextOverlay

	local fallbackName = fallbackTextOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fallbackName:SetPoint("LEFT", fallbackHealthBarsContainer, "LEFT", 6, 0)
	fallbackName:SetJustifyH("LEFT")
	fallbackName:SetWordWrap(false)
	fallbackName:SetMaxLines(1)
	fallbackName:SetWidth(160)
	fallbackName:SetText(playerPlates and L("QuestTogether Player") or GetRandomQuestPlatePreviewName())
	fallbackUnitFrame.name = fallbackName

	local fallbackHealthValue = fallbackTextOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fallbackHealthValue:SetPoint("LEFT", fallbackHealthBarsContainer, "RIGHT", 8, 0)
	fallbackHealthValue:SetText("241 K")
	fallbackHealthValue:SetJustifyH("RIGHT")
	fallbackHealthValue:SetWordWrap(false)
	fallbackUnitFrame.questPreviewHealthText = fallbackHealthValue

	self[controlsKey] = {
		playerPlates = playerPlates == true,
		content = content,
		namesOnlyNotice = namesOnlyNotice,
		playerTooltipHeader = playerTooltipHeader,
		[enabledKey] = nameplateQuestIconEnabled,
		nameplateQuestIconStyleDropdown = nameplateQuestIconStyleDropdown,
		playerTooltipIdentifierDropdown = playerTooltipIdentifierDropdown,
		nameplateQuestHealthColorEnabled = nameplateQuestHealthColorEnabled,
		nameplateQuestHealthColor = nameplateQuestHealthColor,
		resetNameplateQuestHealthColor = resetNameplateQuestHealthColor,
		previewFrame = previewFrame,
		previewNamePlate = nil,
		previewNameLabel = fallbackName,
		previewUnitFrame = fallbackUnitFrame,
	}
	self[frameKey] = frame

	frame:SetScript("OnShow", function()
		frame:RegisterEvent("CVAR_UPDATE")
		frame:RegisterEvent("PLAYER_LEVEL_UP")
		local controls = QuestTogether[controlsKey]
		if controls and controls.previewNameLabel then
			controls.previewNameLabel:SetText(
				playerPlates and L("QuestTogether Player") or GetRandomQuestPlatePreviewName()
			)
		end
		QuestTogether:RefreshQuestPlatesWindow(playerPlates)
	end)
	frame:SetScript("OnHide", function()
		frame:UnregisterEvent("CVAR_UPDATE")
		frame:UnregisterEvent("PLAYER_LEVEL_UP")
	end)
	frame:SetScript("OnEvent", function(_, event, cvar)
		if not frame:IsShown() then return end
		if event == "CVAR_UPDATE" then
			cvar = QuestTogether:SafeToString(cvar, ""):lower()
			if not cvar:find("nameplate", 1, true) then return end
		end
		-- Refresh only this owned preview. Reopening the settings panel also
		-- samples changes made while its event subscriptions were retired.
		RefreshQuestPlatesPreview(QuestTogether[controlsKey])
	end)

	self[playerPlates and "playerPlatesCategory" or "questPlatesCategory"] =
		RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshQuestPlatesWindow(playerPlates)
end

function QuestTogether:InitializeExperimentalWindow(parentCategory)
	if self.experimentalFrame then return end
	local frame = CreateFrame("Frame", "QuestTogetherExperimentalPanel")
	frame.name, frame.parent = L("Experimental"), "QuestTogether"
	local _, content = CreateScrollablePanelContent(frame, 400)
	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L("Experimental"))
	local description = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	description:SetPoint("TOPLEFT", 16, -50)
	description:SetWidth(600)
	description:SetJustifyH("LEFT")
	description:SetText(L("Features in testing. Turn them off if they cause problems."))
	self.experimentalControls = {
		experimentalLayerDetection = CreateCheckbox(content, "experimentalLayerDetection", 16, -110),
	}
	self.experimentalFrame = frame
	frame:SetScript("OnShow", function() RefreshCheckboxOptions(QuestTogether.experimentalControls) end)
	self.experimentalCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	RefreshCheckboxOptions(self.experimentalControls)
end

function QuestTogether:InitializeGroupsWindow(parentCategory)
	if self.groupsFrame then return end
	local frame, ui = CreateFeatureSettingsPage("QuestTogetherGroupsPanel", L("Groups & Sharing"),
		L("Find questing partners and choose how to handle join and quest-sharing requests."))
	local content = ui.content
	ui:Text(L("Sharing audience"), true)
	ui.audience = ui:Add(CreateOptionDropdown(content, L("Sharing audience"),
		L("Party only keeps quest, focus, waypoint and location reporting within your current group and disables public discovery."),
		16, 0, 246, { "normal", "party" }, function(value) return value == "party" and L("Party only") or L("Normal sharing") end,
		"sharingAudience", function() return self:GetOption("sharingAudience") end), "dropdown")
	ui:Text(L("Finding Partners"), true)
	ui:Check("lookingForQuestPartners")
	ui:Check("autoInviteWhileLFG")
	ui:Check("stopLookingForPartnersOnJoin")
	ui:Text(L("Join Requests"), true)
	ui:Check("autoInviteFriends")
	ui:Text(L("Quest Sharing"), true)
	ui:Check("allowIncomingShareRequests")
	ui:Check("allowFocusSuggestions")
	ui:Check("autoAcceptPartyShareRequests")
	self.groupsFrame, self.groupsControls = frame, ui
	frame:SetScript("OnShow", function() self:RefreshGroupsWindow() end)
	self.groupsCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshGroupsWindow()
end

function QuestTogether:InitializeTrackerSettingsWindow(parentCategory)
	if self.trackerSettingsFrame then return end
	local frame, ui = CreateFeatureSettingsPage("QuestTogetherTrackerSettingsPanel", L("Party Tracker & Focus"),
		L("Choose how your party's objectives and quest focus appear, and whose focus you follow."))
	local content = ui.content
	ui:Text(L("Party Navigation"), true)
	ui:Check("sharePartyFocus")
	ui:Check("automaticLeaderFocus")
	ui:Check("skipPartyFocusFollowConfirmation")
	ui:Check("showTrackerFocusIndicators")
	ui:Text(L("Party Objective Tracker"), true)
	self.questTrackerModeDropdown = CreateDropdown(content, L("Display"),
		L("Choose whether the Party Objective Tracker shows your focused quest, the quest you hover, or both. In Focus and Hover, hovering temporarily overrides focus."),
		16, 0, 240, function(dropdown)
			for _, option in ipairs(self:GetQuestTrackerModeOptions()) do
				local value = option.value
				dropdown.entries[#dropdown.entries + 1] = {
					text = option.text,
					checked = function() return self:GetQuestTrackerMode() == value end,
					func = function() self:ApplyOptionsDropdownSelection("questTrackerMode", value) end,
				}
			end
		end)
	self.questTrackerTooltipPlacementDropdown = CreateDropdown(content, L("Tooltip placement"),
		L("Choose whether Party Objective Tracker appears above, below, or beside Blizzard's quest tooltip when snapping is enabled. QT uses another side if the chosen placement would go off-screen."),
		16, 0, 240, function(dropdown)
			for _, option in ipairs(self:GetQuestTrackerTooltipPlacementOptions()) do
				local value = option.value
				dropdown.entries[#dropdown.entries + 1] = {
					text = option.text,
					checked = function() return self:GetQuestTrackerTooltipPlacement() == value end,
					func = function() self:ApplyOptionsDropdownSelection("questTrackerTooltipPlacement", value) end,
				}
			end
		end)
	self.questFocusOpacitySlider = self:CreateQuestFocusSlider(content, L("Background opacity"), 16, 0, 0, 100, 5,
		function() return self:GetQuestFocusOpacity() end, function(value) self:SetOption("questFocusOpacity", value) end, true,
		L("Adjust the Party Objective Tracker background from transparent to opaque. Quest text and player indicators keep their normal visibility."))
	ui:Add(self.questTrackerModeDropdown, "dropdown")
	ui:Add(self.questTrackerTooltipPlacementDropdown, "dropdown")
	ui:Check("questTrackerHideSolo")
	ui:Check("questTrackerHideBlizzardTooltip")
	ui:Add(self.questFocusOpacitySlider, "slider", 24)
	ui:Action("edit", L("Open HUD Edit Mode"), L("Open the tracker placement preview to move or resize it, adjust its background, or snap it to Blizzard's objective tracker."), function() self:OpenHudEditMode() end)
	self.trackerSettingsFrame, self.trackerSettingsControls = frame, ui
	frame:SetScript("OnShow", function() self:RefreshTrackerSettingsWindow() end)
	self.trackerSettingsCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshTrackerSettingsWindow()
end

local function SetAudioSliderEnabled(slider, enabled)
	slider.Slider:SetEnabled(enabled)
	local value = slider.Slider:GetValue()
	slider.Back:SetEnabled(enabled and value > slider.audioMinimum)
	slider.Forward:SetEnabled(enabled and value < slider.audioMaximum)
	slider:SetAlpha(enabled and 1 or 0.5)
end

function QuestTogether:LayoutAudioWindow()
	local ui = self.audioControls
	if not ui then return end
	local function Place(region, x, y)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", ui.content, "TOPLEFT", x, y)
	end
	local y = -48 - ui.description:GetStringHeight() - 20
	Place(ui.master, 16, y)
	y = y - 58
	Place(ui.volume, 16, y)
	y = y - 48
	Place(ui.muteCombat, 16, y)
	y = y - 64
	Place(ui.interval, 16, y)
	y = y - 42
	if ui.unavailable:IsShown() then
		Place(ui.unavailable, 16, y)
		y = y - ui.unavailable:GetStringHeight() - 14
	end
	Place(ui.previewHint, 16, y)
	y = y - ui.previewHint:GetStringHeight() - 14
	Place(ui.gameHint, 16, y)
	y = y - ui.gameHint:GetStringHeight() - 30
	for _, row in ipairs(ui.rows) do
		Place(row.enabled, 16, y)
		y = y - math.max(24, row.enabled.Label:GetStringHeight()) - 10
		Place(row.description, 44, y)
		y = y - row.description:GetStringHeight() - 20
		Place(row.sound.title, 44, y)
		Place(row.preview, 292, y - 22)
		Place(row.volume, 410, y - 28)
		y = y - 92
	end
	Place(ui.reset, 16, y)
	ui.content:SetHeight(-y + 66)
end

function QuestTogether:RefreshAudioWindow()
	if not self.audioFrame then return end
	local ui, enabled, volumeSupported = self.audioControls, self:GetOption("audioEnabled") == true, self:SupportsAudioVolume()
	ui.master:SetChecked(enabled)
	ui.muteCombat:SetChecked(self:GetOption("audioMuteInCombat") == true)
	ui.volume:RefreshValue()
	SetAudioSliderEnabled(ui.volume, volumeSupported)
	ui.interval:RefreshValue()
	ui.unavailable:SetShown(not volumeSupported)
	local sounds = self:GetAudioSoundOptions()
	for _, row in ipairs(ui.rows) do
		local cue = row.cue
		row.enabled:SetChecked(self:GetOption(cue.enabledKey) == true)
		row.volume:RefreshValue()
		SetAudioSliderEnabled(row.volume, volumeSupported)
		local selected = self:GetAudioSound(cue.key)
		for _, sound in ipairs(sounds) do
			if sound.value == selected then
				RefreshDropdownControl(row.sound, sound.text)
				break
			end
		end
		row.preview:SetEnabled(self.isEnabled == true and enabled and volumeSupported)
	end
	self:LayoutAudioWindow()
end

function QuestTogether:InitializeAudioWindow(parentCategory)
	if self.audioFrame then return end
	local frame = CreateFrame("Frame", "QuestTogetherAudioPanel")
	frame.name, frame.parent = L("Audio"), "QuestTogether"
	local scroll, content = CreateScrollablePanelContent(frame, 1800)
	local ui = { rows = {}, content = content, scroll = scroll }
	self.audioControls = ui
	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L("Audio"))
	local function Text(text, width)
		local label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetWidth(width or 640)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(true)
		label:SetText(text)
		return label
	end
	ui.description = Text(L("Choose sounds for QT events. All event cues are enabled by default; your saved choices are preserved. Turn off individual cues below or use the master switch to silence QT.")
		.. "\n" .. L("All cues use original QuestTogether sounds."))
	ui.description:SetPoint("TOPLEFT", 16, -48)
	ui.master = CreateCheckbox(content, "audioEnabled", 16, 0)
	ui.muteCombat = CreateCheckbox(content, "audioMuteInCombat", 16, 0)
	local function Volume(key, titleText, tooltip, width)
		local slider = CreateSettingsSlider(content, titleText, tooltip, 16, 0, 0, 100, 5)
		slider.audioMinimum, slider.audioMaximum = 0, 100
		slider:SetWidth(width or 360)
		ConfigureSettingsSlider(slider, function() return self:GetAudioVolume(key) end, function(value)
			if self:SupportsAudioVolume() then self:SetOption(key, value) end
		end)
		return slider
	end
	ui.volume = Volume("audioVolume", L("Master volume"), L("Adjust the volume of all QT sound cues."))
	ui.interval = CreateSettingsSlider(content, L("Minimum time between sounds"), L("Keep repeated events from playing sounds too close together."),
		16, 0, 0.25, 3, 0.25, true, function(value) return string.format(L("%.2f sec"), value) end)
	ConfigureSettingsSlider(ui.interval, function() return self:GetOption("audioInterval") or 0.75 end,
		function(value) self:SetOption("audioInterval", value) end)
	ui.unavailable = Text(L("QuestTogether sounds are unavailable in this client."))
	ui.previewHint = Text(L("Preview plays the selected sound even if that event is disabled. It respects QT's master sound switch, volume and combat mute setting."))
	ui.gameHint = Text(L("QT cues also follow WoW's Sound Effects volume and mute settings. Other interface sounds and emote audio remain controlled by WoW.") .. "\n" .. L("Native focus click uses WoW's Sound Effects volume. QT volume sliders mute it at zero; other values do not change its loudness."))
	for _, entry in ipairs(self:GetAudioCueCatalog()) do
		local cue = entry
		local row = { cue = cue }
		row.enabled = CreateDescribedCheckbox(content, cue.enabledKey, cue.label, cue.description, 16, 0)
		row.description = Text(cue.description, 600)
		row.volume = Volume(cue.volumeKey, L("Volume"), L("Adjust this event's volume relative to QT's master volume."), 200)
		row.sound = CreateDropdown(content, L("Sound"), L("Choose the sound for this event. Use Preview to listen before changing its volume or enabling the event."), 44, 0, 180, function(dropdown)
			for _, option in ipairs(self:GetAudioSoundOptions()) do
				local sound = option.value
				dropdown.entries[#dropdown.entries + 1] = {
					text = option.text,
					checked = function() return self:GetAudioSound(cue.key) == sound end,
					func = function() self:ApplyOptionsDropdownSelection(cue.soundKey, sound) end,
				}
			end
		end)
		row.preview = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		row.preview:SetSize(108, 24)
		row.preview:SetText(L("Preview"))
		self:AttachSettingsTooltip(row.preview, L("Preview"), L("Preview plays the selected sound even if that event is disabled. It respects QT's master sound switch, volume and combat mute setting."))
		row.preview:SetScript("OnClick", function() self:PreviewAudioCue(cue.key) end)
		ui.rows[#ui.rows + 1] = row
	end
	ui.reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	ui.reset:SetSize(240, 24)
	ui.reset:SetText(L("Reset audio defaults"))
	self:AttachSettingsTooltip(ui.reset, L("Reset audio defaults"), L("Restore only QT sound settings, including event switches, sounds, volumes and timing. Emotes and other preferences are unchanged."))
	ui.reset:SetScript("OnClick", function() self:ResetAudioSettings(); self:RefreshAudioWindow() end)
	self.audioFrame = frame
	frame:SetScript("OnShow", function() self:RefreshAudioWindow() end)
	self.audioCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshAudioWindow()
end

local SETTINGS_CATEGORY_FIELDS = {
	general = "optionsCategory", announcements = "announcementsCategory", whereToAnnounce = "whereToAnnounceCategory",
	questPlates = "questPlatesCategory", playerPlates = "playerPlatesCategory", playerLocations = "playerLocationsCategory",
	groups = "groupsCategory", tracker = "trackerSettingsCategory", launchers = "launcherSettingsCategory",
	data_broker = "dataBrokerCategory",
	emotes = "emotesCategory", audio = "audioCategory", accessibility = "accessibilityCategory", profiles = "profilesCategory",
	developer = "developerCategory", experimental = "experimentalCategory",
}

function QuestTogether:OpenSettingsCategory(key)
	local field = SETTINGS_CATEGORY_FIELDS[key]
	if not field or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	if not self.optionsCategory and not self.optionsFrame then
		self:InitializeOptionsWindow()
	end
	local category = self[field]
	if not (Settings and type(Settings.OpenToCategory) == "function" and category and type(category.GetID) == "function") then
		self:Print(L("Settings API is unavailable; unable to open options."))
		return false
	end
	local ok, id = pcall(category.GetID, category)
	if not ok or not self:CanAccessValue(id) or (type(id) ~= "number" and type(id) ~= "string") then return false end
	return pcall(Settings.OpenToCategory, id)
end

function QuestTogether:OpenOptionsWindow()
	return self:OpenSettingsCategory("general")
end

function QuestTogether:InitializePlayerLocationsWindow(parentCategory)
	if self.playerLocationsFrame then return end
	local frame, ui = CreateFeatureSettingsPage("QuestTogetherPlayerLocationsPanel", L("Maps & Minimap"),
		L("Choose map overlays, player markers and shared waypoints. Display settings are independent of what you share."))
	local content = ui.content
	ui:Text(L("World map"), true)
	ui:Check("showWorldMapData")
	ui:Check("showWorldMapButton")
	ui:Text(L("Player Locations"), true)
	ui:Check("sharePlayerLocation")
	ui.filterDropdown = CreateDropdown(content, L("Players shown on maps"),
		L("Choose all QT players, only players looking for partners, or no QT player markers. Applies to the world map and minimap; Blizzard markers are unchanged. This does not change who can see your location."),
		16, 0, 310, function(dropdown)
			for i, label in ipairs(GetPlayerLocationFilterLabels()) do
				local choice = i
				local info = {}
				info.text = label
				info.checked = function() return GetPlayerLocationFilterChoice(QuestTogether) == choice end
				info.func = function()
					QuestTogether:SetOptions({ onlyShowQuestPartners = choice == 2, showPlayerLocations = choice ~= 3 })
					QuestTogether:RefreshPlayerLocationsWindow()
				end
				dropdown.entries[#dropdown.entries + 1] = info
			end
		end)
	ui.clusterPlayerLocations = CreateCheckbox(content, "clusterPlayerLocations", 16, 0)
	ui.clusterPlayerLocations.Label:SetMaxLines(0)
	ui:Add(ui.filterDropdown, "dropdown")
	ui:Add(ui.clusterPlayerLocations, "checkbox")
	ui:Text(L("Party waypoints"), true)
	ui:Check("sharePartyWaypoint")
	ui:Check("showPartyWaypoints")
	self.playerLocationsFrame, self.playerLocationsControls = frame, ui
	frame:SetScript("OnShow", function() self:RefreshPlayerLocationsWindow() end)
	self.playerLocationsCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshPlayerLocationsWindow()
end

function QuestTogether:InitializeDeveloperWindow(parentCategory)
	if self.developerFrame then return end
	local frame = CreateFrame("Frame", "QuestTogetherDeveloperPanel")
	frame.name, frame.parent = L("Developer"), "QuestTogether"
	local _, content = CreateScrollablePanelContent(frame, 320)
	local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L("Developer"))
	local description = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", 16, -48)
	description:SetWidth(640)
	description:SetJustifyH("LEFT")
	description:SetText(L("Debugging tools and diagnostic sharing."))
	self.developerControls = {
		shareDeveloperDiagnostics = CreateCheckbox(content, "shareDeveloperDiagnostics", 16, -92),
	}
	local troubleshooting = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	troubleshooting:SetPoint("TOPLEFT", 16, -154)
	troubleshooting:SetText(L("Troubleshooting"))
	local function Action(key, label, tooltip, y, callback)
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetPoint("TOPLEFT", 16, y)
		button:SetSize(300, 26)
		button:SetText(label)
		QuestTogether:AttachSettingsTooltip(button, label, tooltip)
		button:SetScript("OnClick", callback)
		self.developerControls[key] = button
	end
	Action("debugButton", L("Open Debug Window"),
		L("Open diagnostic logs and tests to help troubleshoot addon problems."), -184,
		function() QuestTogether:ShowDebugWindow() end)
	Action("rescanQuestLog", L("Rescan Quest Log"),
		L("Refresh QuestTogether's quest information from your current quest log."), -226,
		function() QuestTogether:ScanQuestLog() end)
	self.developerFrame = frame
	frame:SetScript("OnShow", function() RefreshCheckboxOptions(QuestTogether.developerControls) end)
	self.developerCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	RefreshCheckboxOptions(self.developerControls, self)
end

function QuestTogether:InitializeAccessibilityWindow(parentCategory)
	if self.accessibilityFrame then return end
	local frame, ui = CreateFeatureSettingsPage("QuestTogetherAccessibilityPanel", L("Appearance & Accessibility"),
		L("Choose QT's theme, text size and motion, or restore your window layouts."))
	local content = ui.content
	ui.themeDropdown = ui:Add(CreateOptionDropdown(content, L("Theme"),
		L("Choose light parchment with dark text or dark parchment with light text for QT windows."),
		16, 0, 140, { false, true }, function(value) return value and L("Light") or L("Dark") end,
		"lightMode", function() return self:GetOption("lightMode") end), "dropdown")
	ui.scale = ui:Add(CreateSettingsSlider(content, L("Window scale"),
		L("Increase text and control size together. The scale is capped when needed to keep the entire window on screen."),
		16, 0, 80, 150, 5), "slider", 24)
	ConfigureSettingsSlider(ui.scale, function() return self:GetOption("windowScale") or 100 end, function(value)
		self:SetOption("windowScale", math.floor(value / 5 + 0.5) * 5)
	end)
	ui:Check("reduceMotion")
	ui:Action("reset", L("Reset window layout"), L("Also available with /qt resetlayout. Saved windows are fitted automatically after display size or UI scale changes."),
		function() self:ResetWindowLayouts() end)
	ui:Text(L("Also available with /qt resetlayout. Saved windows are fitted automatically after display size or UI scale changes."))
	self.accessibilityFrame, self.accessibilityControls = frame, ui
	frame:SetScript("OnShow", function() self:RefreshAccessibilityWindow() end)
	self.accessibilityCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshAccessibilityWindow()
end

function QuestTogether:InitializeLauncherSettingsWindow(parentCategory)
	if self.launcherSettingsFrame then return end
	local frame, ui = CreateFeatureSettingsPage("QuestTogetherLauncherSettingsPanel", L("Controls & Launchers"),
		L("Choose how to open QT and navigate its windows with a controller."))
	local content = ui.content
	ui:Text(L("Controller"), true)
	ui:Check("nativeGamepadNavigation")
	ui:Check("automaticGamepadLauncher")
	ui.gamepadHint = ui:Text(L("With Forever's default controls, QT adds a PQL macro with a quest-book icon to LT + RT + D-pad Up on action page 1 if empty. Moving or removing only its button keeps your layout. Deleting the macro itself lets QT recreate and rebind it if that slot is empty. Existing actions and edited macros are preserved.") .. "\n\n" .. L("Assign Open QuestTogether Menu in WoW Key Bindings for actions on the selected quest or map marker and for pending requests. Text entry and HUD placement keep their existing controls."))
	ui:Action("gamepadBindings", L("Key Bindings"), L("Open WoW key bindings to assign or change QT shortcuts. Opening this page does not change your existing bindings."), function() self.API.OpenKeyBindings() end)
	ui:Text(L("Minimap"), true)
	ui:Check("showMinimapButton")
	self.launcherSettingsFrame, self.launcherSettingsControls = frame, ui
	frame:SetScript("OnShow", function() self:RefreshLauncherSettingsWindow() end)
	self.launcherSettingsCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshLauncherSettingsWindow()
end

function QuestTogether:InitializeDataBrokerWindow(parentCategory)
	if self.dataBrokerFrame then return end
	local frame, ui = CreateFeatureSettingsPage("QuestTogetherDataBrokerPanel", L("Data Broker"),
		L("QuestTogether appears in compatible toolbars when another addon provides LibDataBroker. No extra dependency is required."))
	local content = ui.content
	ui:Check("showDataBrokerLauncher")
	for _, entry in ipairs({ { "brokerLeftClick", L("Left-click") }, { "brokerRightClick", L("Right-click") } }) do
		local key = entry[1]
		ui[key .. "Dropdown"] = ui:Add(CreateDropdown(content, entry[2],
			L("Choose what clicking QuestTogether on a data broker display does."), 16, 0, 246,
			function(dropdown)
				for _, option in ipairs(self:GetDataBrokerActionOptions()) do
					local value = option.value
					dropdown.entries[#dropdown.entries + 1] = {
						text = option.text, checked = function() return self:GetDataBrokerAction(key) == value end,
						func = function() self:ApplyOptionsDropdownSelection(key, value) end,
					}
				end
			end), "dropdown")
	end
	ui:Action("reload", L("Reload UI"), L("Reload WoW's interface to remove the already registered Data Broker launcher. Your saved settings are kept; this reloads all addons."), function() if not self:IsRuntimeRestricted() then self.API.ReloadUI() end end)
	self.dataBrokerFrame, self.dataBrokerControls = frame, ui
	frame:SetScript("OnShow", function() self:RefreshDataBrokerWindow() end)
	self.dataBrokerCategory = RegisterSubcategory(parentCategory, frame, frame.name)
	self:RefreshDataBrokerWindow()
end

function QuestTogether:InitializeOptionsWindow()
	if self.optionsFrame then return end
	local frame, ui = CreateFeatureSettingsPage("QuestTogetherOptionsPanel", "QuestTogether",
		L("QuestTogether shares quest progress between party members and nearby players so everyone can see objectives move in real time."))
	ui.statusText = ui:Text("")
	ui:Action("presets", L("Presets"), L("Choose how much QuestTogether you want to see. Every choice is a set of ordinary settings you can change later."),
		function() self:OpenPresetWindow() end)
	ui:Text(L("Startup & Updates"), true)
	ui:Check("showStartupTips")
	ui:Check("showAutomaticReleaseNotes")
	ui:Check("showUpdateNotifications")
	ui:Text(L("Quick links"), true)
	ui:Action("comparePartyQuests", L("Party Quest Log"),
		L("Compare your party's quests and share quests that other members are missing."),
		function() QuestTogether:OpenPartyQuestCompare() end)
	ui:Action("patchNotes", L("Patch Notes"),
		L("Read the latest QuestTogether changes and new features."),
		function() QuestTogether:OpenReleaseNotes() end)
	ui:Action("discord", L("Discord — Feedback & Support"),
		L("Open the Discord invite link to share feedback or ask for help."),
		function() QuestTogether:OpenDiscordSupport() end)
	ui:Action("vip", L("How to become a VIP"),
		L("Learn about VIP rewards, contact @chevcast, and activate your cosmetics."),
		function() QuestTogether:OpenVIPWindow() end)

	self.optionsFrame, self.homeControls = frame, ui
	frame:SetScript("OnShow", function() self:RefreshHomeWindow() end)
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= 1 then elapsed = 0; self:RefreshHomeWindow() end
	end)
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		self:Print(L("Settings API is unavailable; addon options could not be registered."))
		self.optionsCategory = nil
		return
	end

	local category = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name)
	Settings.RegisterAddOnCategory(category)
	self.optionsCategory = category

	-- Register subcategories in the same order they should appear in the left nav.
	self:InitializeGroupsWindow(category)
	self:InitializeTrackerSettingsWindow(category)
	self:InitializePlayerLocationsWindow(category)
	self:InitializeLauncherSettingsWindow(category)
	self:InitializeDataBrokerWindow(category)
	self:InitializeAnnouncementsWindow(category)
	self:InitializeWhereToAnnounceWindow(category)
	self:InitializeQuestPlatesWindow(category)
	self:InitializeQuestPlatesWindow(category, true)
	self:InitializeEmotesWindow(category)
	self:InitializeAudioWindow(category)
	self:InitializeAccessibilityWindow(category)
	self:InitializeExperimentalWindow(category)
	self:InitializeProfilesWindow(category)
	self:InitializeDeveloperWindow(category)

	self:RefreshOptionsWindow()
	self:RefreshProfilesWindow()
end
