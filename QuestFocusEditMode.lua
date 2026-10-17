-- Edit Mode's frame is observed, never registered into or modified. QT owns the
-- preview, controls and revert baseline, as with its personal bubble anchor.
local QT = _G.QuestTogether
local L = QT.Translate
function QT:GetQuestTrackerModeOptions()
	return {
		{ value = "hidden", text = L("Hidden") },
		{ value = "focus", text = L("Focused Quest") },
		{ value = "hover", text = L("Hovered Quest") },
		{ value = "both", text = L("Focus and Hover") },
	}
end
function QT:IsQuestTrackerMode(value)
	return value == "hidden" or value == "focus" or value == "hover" or value == "both"
end
function QT:GetQuestTrackerMode()
	local value = self:GetOption("questTrackerMode")
	return self:IsQuestTrackerMode(value) and value or "both"
end
function QT:GetQuestTrackerModeLabel()
	local mode = self:GetQuestTrackerMode()
	for _, option in ipairs(self:GetQuestTrackerModeOptions()) do
		if option.value == mode then return option.text end
	end
end
function QT:IsQuestTrackerSnapped()
	return self:GetOption("questTrackerSnapToBlizzard") ~= false
end
function QT:GetQuestFocusOpacity()
	local n = self:SafeToNumber(self:GetOption("questFocusOpacity")) or 75
	return math.max(0, math.min(100, n))
end
function QT:GetQuestFocusEditManager()
	local manager = EditModeManagerFrame
	if self:IsWorkBlocked("foreign_frame_mutation") or not self:CanAccessForeignFrame(manager) then
		return
	end
	return manager
end
function QT:CaptureQuestFocusEditLayout()
	local profile = self.db and self.db.profile
	if not profile then
		return
	end
	local layouts = type(profile.windowLayouts) == "table" and profile.windowLayouts or {}
	self.questFocusEditBaseline =
		{ profile = profile, layout = self:DeepCopy(layouts.questFocus), opacity = self:GetQuestFocusOpacity(), mode = self:GetQuestTrackerMode(), hideSolo = self:GetOption("questTrackerHideSolo") == true, snap = self:IsQuestTrackerSnapped() }
end
function QT:RevertQuestFocusEditLayout()
	local baseline = self.questFocusEditBaseline
	if not baseline or baseline.profile ~= self.db.profile or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	self.db.profile.windowLayouts = self.db.profile.windowLayouts or {}
	self.db.profile.windowLayouts.questFocus = self:DeepCopy(baseline.layout)
	self:SetOptions({ questFocusOpacity = baseline.opacity, questTrackerMode = baseline.mode, questTrackerHideSolo = baseline.hideSolo, questTrackerSnapToBlizzard = baseline.snap })
	local frame = rawget(self, "questFocusWindow")
	if frame then
		local info = self.managedWindows[frame]
		if info then
			info.resetRequested = not baseline.layout
		end
		self:ApplyWindowLayout(frame, true)
	end
	self:QueueQuestFocusRefresh()
end
function QT:BindQuestFocusEditCallbacks(manager, hookMethod)
	for _, method in ipairs({ "SelectSystem", "ClearSelectedSystem" }) do
		if type(self:GetAccessibleFrameMember(manager, method)) == "function" then
			hookMethod(manager, method, function()
				self:DeselectQuestFocusWindow()
			end)
		end
	end
	manager:HookScript("OnHide", function()
		self:DeselectQuestFocusWindow()
	end)
	hookMethod(manager, "SaveLayouts", function()
		if self.questFocusEditing then
			self:CaptureQuestFocusEditLayout()
		end
	end)
	local revert = self:GetAccessibleFrameMember(manager, "RevertAllChangesButton")
	if
		self:CanAccessForeignFrame(revert)
		and type(self:GetAccessibleFrameMember(revert, "HookScript")) == "function"
	then
		revert:HookScript("OnClick", function()
			self:RevertQuestFocusEditLayout()
		end)
	end
end
function QT:UpdateQuestFocusEditMode()
	local manager = self:GetQuestFocusEditManager()
	local editing = false
	local visible = manager and self:GetAccessibleFrameMember(manager, "IsVisible")
	if type(visible) == "function" then
		local ok, value = pcall(visible, manager)
		editing = ok and self:CanAccessValue(value) and value == true
	end
	if
		manager
		and not self.questFocusEditHooksInstalled
		and type(self:GetAccessibleFrameMember(manager, "SaveLayouts")) == "function"
	then
		self:BindQuestFocusEditCallbacks(manager, hooksecurefunc)
		self.questFocusEditHooksInstalled = true
	end
	if editing and (not self.questFocusEditBaseline or self.questFocusEditBaseline.profile ~= self.db.profile) then
		self:CaptureQuestFocusEditLayout()
	end
	if not editing and self.questFocusEditBaseline then
		local method = manager and self:GetAccessibleFrameMember(manager, "IsEditModeActive")
		local active = false
		if type(method) == "function" then
			local ok, value = pcall(method, manager)
			active = ok and self:CanAccessValue(value) and value == true
		end
		if not active then
			self.questFocusEditBaseline = nil
		end
	end
	self.questFocusEditing = editing
	if not editing then
		self:DeselectQuestFocusWindow()
	end
end

function QT:RefreshQuestFocusSelection(frame, editing)
	if not frame then return end
	if self:IsWorkBlocked("foreign_frame_mutation") then
		if frame.Selection then self:HideOwnedUI(frame.Selection) end
		return
	end
	local selection = frame.Selection
	if editing then
		selection = selection or self:EnsureHUDEditSelection(frame, L("Quest Tracker"))
	end
	if selection and self:CanMutateOwnedUI(selection) then
		if editing then
			selection:SetFrameLevel(frame:GetFrameLevel() + 20)
			if frame.editSelected then selection:ShowSelected() else selection:ShowHighlighted() end
		else
			selection:Hide()
		end
	end
end

function QT:DeselectQuestFocusWindow()
	local frame = rawget(self, "questFocusWindow")
	if not frame then
		return
	end
	frame.editSelected = nil
	self:RefreshQuestFocusSelection(frame, self.questFocusEditing == true)
	if frame.editControls then
		self:HideOwnedUI(frame.editControls)
	end
end

function QT:SelectQuestFocusWindow()
	local frame = rawget(self, "questFocusWindow")
	if not frame or not self.questFocusEditing or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	local manager = self:GetQuestFocusEditManager()
	local clear = manager and self:GetAccessibleFrameMember(manager, "ClearSelectedSystem")
	if type(clear) == "function" then
		clear(manager)
	end
	self:DeselectPersonalBubbleAnchor()
	frame.editSelected = true
	self:RefreshQuestFocusSelection(frame, true)
	self:RefreshQuestFocusEditControls(frame, true)
end

local defaults = { width = 340, height = 600, x = 0.78, y = 0.6 }
local function SameLayout(a, b)
	for key, fallback in pairs(defaults) do
		if
			math.abs(
				(QT:SafeToNumber(type(a) == "table" and a[key]) or fallback)
					- (QT:SafeToNumber(type(b) == "table" and b[key]) or fallback)
			) > 0.001
		then
			return false
		end
	end
	return true
end

function QT:ResetQuestFocusEditLayout()
	if not self.questFocusEditing or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	local frame = rawget(self, "questFocusWindow")
	self.db.profile.windowLayouts = self.db.profile.windowLayouts or {}
	self.db.profile.windowLayouts.questFocus = nil
	self:SetOptions({ questFocusOpacity = 75, questTrackerMode = "both", questTrackerHideSolo = false, questTrackerSnapToBlizzard = true })
	if frame and self.managedWindows[frame] then
		self.managedWindows[frame].resetRequested = true
		self:ApplyWindowLayout(frame, true)
	end
	self:QueueQuestFocusRefresh()
end

function QT:RefreshQuestFocusEditControls(frame, editing)
	if not editing or not frame.editSelected then
		if frame.editControls then
			frame.editControls:Hide()
		end
		return
	end
	local panel = frame.editControls
	if not panel then
		panel = self:CreateHUDEditDialog(L("Quest Tracker"), { { key = "ModeDropdown", kind = "dropdown" }, { key = "HideSoloCheckbox", kind = "checkbox" }, { key = "SnapCheckbox", kind = "checkbox" }, "WidthSlider", "HeightSlider", "OpacitySlider" }, {
			close = function()
				self:DeselectQuestFocusWindow()
			end,
			save = function()
				self:CaptureQuestFocusEditLayout()
				self:QueueQuestFocusRefresh()
			end,
			revert = function()
				self:RevertQuestFocusEditLayout()
			end,
			reset = function()
				self:ResetQuestFocusEditLayout()
			end,
			moved = function(dialog)
				self:SaveWindowLayout(dialog)
			end,
		})
		if not panel then
			return
		end
		frame.editControls = panel
		self.managedWindows[panel].key = "questFocusSettings"
		self:ApplyWindowLayout(panel, true)
		local saved = self.db.profile.windowLayouts and self.db.profile.windowLayouts.questFocusSettings
		if not saved then
			local manager = self:GetQuestFocusEditManager()
			panel:ClearAllPoints()
			if manager then
				panel:SetPoint("TOPLEFT", manager, "TOPRIGHT", 16, -40)
			else
				panel:SetPoint("CENTER", self:GetOwnedUIParent(), "CENTER", 420, 40)
			end
		end
	end
	local function Configure(key, title, minimum, maximum, step, value, apply, percent)
		self:ConfigureHUDEditSlider(panel[key], {
			settingName = title,
			currentValue = value,
			displayInfo = {
				setting = key,
				minValue = minimum,
				maxValue = maximum,
				stepSize = step,
				formatter = function(n)
					return tostring(math.floor(n + 0.5)) .. (percent and "%" or "")
				end,
			},
		}, function(n)
			if not self.questFocusEditing or not self:CanMutateOwnedUI(frame) then
				return
			end
			apply(n)
			self:QueueQuestFocusRefresh()
		end)
	end
	Configure("WidthSlider", L("Width"), 240, 720, 10, frame:GetWidth(), function(value)
		frame:SetWidth(value)
		self:SaveWindowLayout(frame)
	end)
	Configure("HeightSlider", L("Max height"), 120, 800, 10, frame:GetHeight(), function(value)
		frame:SetHeight(value)
		self:SaveWindowLayout(frame)
	end)
	Configure("OpacitySlider", L("Background opacity"), 0, 100, 5, self:GetQuestFocusOpacity(), function(value)
		self:SetOption("questFocusOpacity", value)
	end, true)
	local profile = self.db.profile
	self:ConfigureHUDEditDropdown(panel.ModeDropdown, L("Display"), self:GetQuestTrackerModeOptions(),
		function() return self:GetQuestTrackerMode() end, function(value)
			if self.db.profile ~= profile or not self.questFocusEditing or not frame.editSelected
				or self:IsWorkBlocked("foreign_frame_mutation") then return end
			self:SetOption("questTrackerMode", value)
		end)
	local hideSolo = self:GetOption("questTrackerHideSolo") == true
	self:ConfigureHUDEditCheckbox(panel.HideSoloCheckbox, L("Hide when not in a party"), hideSolo, function(value)
		if self.db.profile ~= profile or not self.questFocusEditing or not frame.editSelected
			or self:IsWorkBlocked("foreign_frame_mutation") then return end
		self:SetOption("questTrackerHideSolo", value)
	end)
	local snap = self:IsQuestTrackerSnapped()
	self:ConfigureHUDEditCheckbox(panel.SnapCheckbox, L("Snap to Blizzard's Objective Tracker"), snap, function(value)
		if self.db.profile ~= profile or not self.questFocusEditing or not frame.editSelected
			or self:IsWorkBlocked("foreign_frame_mutation") or not self:CanMutateOwnedUI(frame) then return end
		self:StopWindowInteraction(frame)
		self:SetOption("questTrackerSnapToBlizzard", value)
		-- Enabling replaces the old position with the native tracker anchor.
		-- Disabling leaves QT where it is, ready for manual placement.
		self:ApplyQuestTrackerDefaultAnchor(frame)
		self:SaveWindowLayout(frame)
	end)
	local baseline = self.questFocusEditBaseline
	local layout = self.db.profile.windowLayouts and self.db.profile.windowLayouts.questFocus
	local pending = baseline
			and (not SameLayout(layout, baseline.layout) or self:GetQuestFocusOpacity() ~= baseline.opacity or self:GetQuestTrackerMode() ~= baseline.mode or hideSolo ~= baseline.hideSolo or snap ~= baseline.snap)
		or false
	panel.SaveButton:SetEnabled(pending)
	panel.RevertButton:SetEnabled(pending)
	panel.ResetButton:SetEnabled(not SameLayout(layout, nil) or self:GetQuestFocusOpacity() ~= 75 or self:GetQuestTrackerMode() ~= "both" or hideSolo or not snap)
	panel.SaveStatus:SetText(
		pending and L("Changes applied automatically. Save Changes sets the point Revert returns to.")
			or L("QuestTogether settings saved. Blizzard's Save button is not needed.")
	)
	self:LayoutHUDEditDialog(panel)
	self:ThemeHUDEditDialog(panel)
	panel:Show()
end
