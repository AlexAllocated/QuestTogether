-- Shared QT-owned Edit Mode settings shell. Features own selection and saved
-- values; this module owns scroll artwork, controls, layout and drag behavior.
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate

function QuestTogether:EnsureHUDEditSelection(hostFrame, label)
	if not hostFrame or hostFrame.Selection then
		return hostFrame and hostFrame.Selection or nil
	end

	-- EditMode templates can be unavailable on some clients/states; fail soft and skip selection chrome.
	local ok, selection = pcall(self.CreateOwnedWindowFrame, self, "Frame", nil, hostFrame, "EditModeSystemSelectionTemplate")
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
				return label
			end,
		})
	elseif selection.SetGetLabelTextFunction then
		selection:SetGetLabelTextFunction(function()
			return label
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


function QuestTogether:ConfigureHUDEditDropdown(setting, label, options, getValue, onChanged)
	setting.Label:SetText(label)
	setting.Dropdown:SetupMenu(function(_, root)
		for _, option in ipairs(options) do
			local value = option.value
			root:CreateRadio(option.text, function() return getValue() == value end,
				function() onChanged(value) end)
		end
	end)
	setting:Show()
end

function QuestTogether:ConfigureHUDEditCheckbox(setting, label, checked, onChanged)
	setting.Label:SetText(label)
	setting.Checkbox:SetChecked(checked)
	setting.Checkbox:SetScript("OnClick", function(button) onChanged(button:GetChecked() == true) end)
	setting:Show()
end

function QuestTogether:ConfigureHUDEditSlider(settingFrame, settingData, onValueChanged)
	if not settingFrame then
		return
	end

	if settingFrame.cbrHandles then
		settingFrame.cbrHandles:Unregister()
	end

	local callbackHandles = settingFrame.qtEditSliderHandles
	if not callbackHandles then
		callbackHandles = EventUtil.CreateCallbackHandleContainer()
		settingFrame.qtEditSliderHandles = callbackHandles
	end
	callbackHandles:Unregister()
	callbackHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnValueChanged,
		function(_, value)
			if not settingFrame.initInProgress and type(onValueChanged) == "function" then
				onValueChanged(value)
			end
		end,
		settingFrame
	)
	callbackHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnInteractStart,
		function() end,
		settingFrame
	)
	callbackHandles:RegisterCallback(
		settingFrame.Slider,
		MinimalSliderWithSteppersMixin.Event.OnInteractEnd,
		function() end,
		settingFrame
	)

	settingFrame.OnSliderValueChanged = function() end
	settingFrame.OnSliderInteractEnd = function() end
	settingFrame.OnSliderInteractStart = function() end
	settingFrame:SetupSetting(settingData)
	settingFrame:Show()
end

function QuestTogether:LayoutHUDEditDialog(dialog)
	-- SetupSetting restores Blizzard's fixed track width on every refresh.
	-- Reserve a value column inside our content bounds after that setup runs.
	for _, setting in ipairs(dialog.Settings) do
		setting:SetWidth(dialog.contentWidth)
		local label, slider = setting.Label, setting.Slider
		if label and slider and slider.RightText then
			label:ClearAllPoints()
			label:SetPoint("LEFT", setting, "LEFT", 0, 0)
			label:SetWidth(120)
			label:SetWordWrap(true)
			local height = math.max(32, label:GetStringHeight())
			label:SetHeight(height)
			setting:SetHeight(height)
			slider:ClearAllPoints()
			slider:SetPoint("LEFT", label, "RIGHT", 16, 0)
			slider:SetWidth(dialog.contentWidth - 120 - 16 - 12 - 64)
			slider.RightText:ClearAllPoints()
			slider.RightText:SetPoint("RIGHT", setting, "RIGHT", 0, 0)
			slider.RightText:SetWidth(64)
			slider.RightText:SetJustifyH("RIGHT")
		elseif label and setting.Checkbox then
			setting.Checkbox:ClearAllPoints()
			setting.Checkbox:SetPoint("LEFT", setting, "LEFT", 0, 0)
			setting.Checkbox:SetSize(24, 24)
			label:ClearAllPoints()
			label:SetPoint("LEFT", setting.Checkbox, "RIGHT", 8, 0)
			label:SetWidth(dialog.contentWidth - 32)
			label:SetJustifyH("LEFT")
			label:SetWordWrap(true)
			setting:SetHeight(math.max(32, label:GetStringHeight()))
			setting.Checkbox:SetHitRectInsets(0, -(dialog.contentWidth - 24), 0, 0)
		elseif label and setting.Dropdown then
			label:ClearAllPoints()
			label:SetPoint("LEFT", setting, "LEFT", 0, 0)
			label:SetWidth(120)
			label:SetWordWrap(true)
			setting:SetHeight(math.max(32, label:GetStringHeight()))
			setting.Dropdown:ClearAllPoints()
			setting.Dropdown:SetPoint("LEFT", label, "RIGHT", 16, 0)
			setting.Dropdown:SetWidth(dialog.contentWidth - 136)
		end
	end
	local height = dialog.contentTop
	for i, setting in ipairs(dialog.Settings) do
		height = height + setting:GetHeight() + (i > 1 and 24 or 0)
	end
	dialog:SetHeight(height + 20 + dialog.SaveStatus:GetStringHeight() + 24 + 68 + dialog.contentBottom)
	self:FitScrollDialog(dialog)
end

function QuestTogether:CreateHUDEditDialog(title, sliderKeys, callbacks)
	local addon = self
	local dialog = addon:CreateScrollDialog(500, 344, title)
	if not dialog then
		return nil
	end
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(250)
	dialog:SetClampedToScreen(true)
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:EnableKeyboard(true)
	dialog:Hide()

	dialog.Title = dialog.title

	local closeButton = addon:CreateOwnedWindowFrame("Button", nil, dialog, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -10, -8)
	closeButton:SetScript("OnClick", function()
		callbacks.close()
	end)
	dialog.CloseButton = closeButton

	local dragHandle = addon:CreateOwnedWindowFrame("Frame", nil, dialog)
	dragHandle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -8)
	dragHandle:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", -4, -8)
	dragHandle:SetHeight(28)
	dragHandle:EnableMouse(true)
	dragHandle:RegisterForDrag("LeftButton")
	dragHandle:SetScript("OnDragStart", function()
		if not addon:IsWorkBlocked("foreign_frame_mutation") then
			addon:StartWindowDrag(dialog)
		end
	end)
	dragHandle:SetScript("OnDragStop", function()
		addon:StopWindowDrag(dialog)
		if callbacks.moved then
			callbacks.moved(dialog)
		end
	end)
	dialog.DragHandle = dragHandle

	dialog.Settings = {}
	local previous
	for _, spec in ipairs(sliderKeys) do
		local dropdown = type(spec) == "table" and spec.kind == "dropdown"
		local checkbox = type(spec) == "table" and spec.kind == "checkbox"
		local key = type(spec) == "table" and spec.key or spec
		local setting = addon:CreateOwnedWindowFrame("Frame", nil, dialog, not (dropdown or checkbox) and "EditModeSettingSliderTemplate" or nil)
		if dropdown then
			-- Native dropdown artwork without the native Edit Mode callbacks,
			-- which write into Blizzard's selected-system settings.
			setting.Label = setting:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
			setting.Dropdown = addon:CreateOwnedWindowFrame("DropdownButton", nil, setting, "WowStyle1DropdownTemplate")
		end
		if checkbox then
			setting.Label = setting:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
			setting.Checkbox = addon:CreateOwnedWindowFrame("CheckButton", nil, setting, "MinimalCheckboxTemplate")
		end
		if previous then
			setting:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -24)
		else
			setting:SetPoint("TOPLEFT", dialog, "TOPLEFT", dialog.contentInset, -dialog.contentTop)
		end
		dialog[key] = setting
		dialog.Settings[#dialog.Settings + 1] = setting
		previous = setting
	end

	local saveStatus = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	saveStatus:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -20)
	saveStatus:SetWidth(dialog.contentWidth)
	saveStatus:SetJustifyH("LEFT")
	dialog.SaveStatus = saveStatus
	addon:AddScrollDialogLabel(dialog, saveStatus, "muted")

	local saveButton = addon:CreateOwnedWindowFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	saveButton:SetSize(dialog.contentWidth, 28)
	saveButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", dialog.contentInset, dialog.contentBottom + 40)
	saveButton:SetText(L("Save Changes"))
	saveButton:SetScript("OnClick", function()
		callbacks.save()
	end)
	dialog.SaveButton = saveButton

	local revertButton = addon:CreateOwnedWindowFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	revertButton:SetSize((dialog.contentWidth - 12) / 2, 28)
	revertButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", dialog.contentInset, dialog.contentBottom)
	revertButton:SetText(L("Revert Changes"))
	revertButton:SetScript("OnClick", function()
		callbacks.revert()
	end)
	dialog.RevertButton = revertButton

	local resetButton = addon:CreateOwnedWindowFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	resetButton:SetSize((dialog.contentWidth - 12) / 2, 28)
	resetButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -dialog.contentInset, dialog.contentBottom)
	resetButton:SetText(L("Reset To Default"))
	resetButton:SetScript("OnClick", function()
		callbacks.reset()
	end)
	dialog.ResetButton = resetButton

	dialog:SetScript("OnDragStart", function(frame)
		if not addon:IsWorkBlocked("foreign_frame_mutation") then
			addon:StartWindowDrag(frame)
		end
	end)
	dialog:SetScript("OnDragStop", function(frame)
		addon:StopWindowDrag(frame)
		if callbacks.moved then
			callbacks.moved(frame)
		end
	end)
	dialog:SetScript("OnHide", function(frame)
		addon:StopWindowDrag(frame)
	end)
	dialog.escapeAction = function()
		callbacks.close()
	end
	dialog.LayoutManagedWindow = function()
		addon:LayoutHUDEditDialog(dialog)
	end

	return dialog
end

function QuestTogether:ThemeHUDEditDialog(dialog)
	for _, setting in ipairs(dialog.Settings) do
		if setting.Label and not setting.qtThemeRegistered then
			self:AddScrollDialogLabel(dialog, setting.Label)
			if setting.Slider then
				for _, key in ipairs({ "LeftText", "RightText", "TopText", "MinText", "MaxText" }) do
					local label = setting.Slider[key]
					if label then
						self:AddScrollDialogLabel(dialog, label)
					end
				end
			end
			setting.qtThemeRegistered = true
		end
	end
	self:ApplyScrollDialogTheme(dialog)
end
