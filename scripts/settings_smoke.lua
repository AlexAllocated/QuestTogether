-- Offline only: exercise real settings constructors, never load in /qt test.
local root = arg[1] or "."
local file = assert(io.open(root .. "/scripts/test.lua"))
local setup = file:read("*a")
file:close()
assert((loadstring or load)(assert(setup:match("^(.-)local clientChecks ="))))()
local namespace = {}
for line in io.lines(root .. "/QuestTogether.toc") do
	local name = line:match("^%s*(.-)%s*$")
	if name:match("%.lua$") and name ~= "Tests.lua" and not name:match("^scripts/") then
		assert(loadfile(root .. "/" .. name))("QuestTogether", namespace)
	end
end
local regions, methods = {}, {}
local function Region(kind, parent)
	local f = setmetatable({ kind = kind, parent = parent, children = {}, scripts = {}, value = 0, width = 700, height = 400 }, { __index = methods })
	regions[#regions + 1] = f
	if parent then parent.children[#parent.children + 1] = f end
	return f
end
function methods:CreateFontString()
	return Region("FontString")
end
function methods:CreateTexture()
	return Region("Texture")
end
function methods:SetScript(key, fn)
	self.scripts[key] = fn
end
function methods:GetScript(key) return self.scripts[key] end
function methods:HasScript() return self.kind ~= "FontString" and self.kind ~= "Texture" end
function methods:GetChildren() return (unpack or table.unpack)(self.children) end
function methods:GetRegions() end
function methods:HookScript(key, fn)
	local previous = self.scripts[key]
	self.scripts[key] = function(...)
		if previous then
			previous(...)
		end
		fn(...)
	end
end
function methods:SetText(text)
	self.text = text
end
function methods:GetFontString()
	if not self.fontString then self.fontString = Region("FontString", self) end
	return self.fontString
end
function methods:SetChecked(v)
	self.checked = v
end
function methods:GetChecked()
	return self.checked
end
function methods:SetValue(v)
	if self.Slider then return self.Slider:SetValue(v) end
	if self.minimum then v = math.max(self.minimum, math.min(self.maximum, v)) end
	self.value = v
	if self.scripts.OnValueChanged then
		self.scripts.OnValueChanged(self, v)
	end
end
function methods:GetValue() return self.value end
function methods:RegisterCallback(event, callback, owner)
	self.callbacks = self.callbacks or {}
	assert(not self.callbacks[event], "settings slider callbacks must not accumulate")
	self.callbacks[event] = { callback, owner }
end
function methods:Init(value, minimum, maximum, steps, formatters)
	if self.kind == "EventFrame" then
		self.visibleExtent, self.panExtent, self.percentage = value, minimum, 0
		return
	end
	self.Slider:SetMinMaxValues(minimum, maximum)
	self.Slider:SetValueStep((maximum - minimum) / steps)
	self.Slider:SetValue(value)
	local function Update(_, current)
		self.RightText:SetText(formatters[MinimalSliderWithSteppersMixin.Label.Right](current))
		self.Back:SetEnabled(current > minimum)
		self.Forward:SetEnabled(current < maximum)
		local listener = self.callbacks and self.callbacks.OnValueChanged
		if listener then listener[1](listener[2], current) end
	end
	Update(nil, value)
	self.nativeOnValueChanged = Update
	self.Slider:SetScript("OnValueChanged", Update)
end
function methods:SetMinMaxValues(lo, hi)
	self.minimum, self.maximum = lo, hi
end
function methods:SetValueStep(v)
	self.step = v
end
function methods:IsForbidden()
	return false
end
function methods:IsProtected()
	return false
end
for _, key in ipairs({
	"SetTextInsets", "SetBackdrop", "SetBackdropColor", "SetClampedToScreen", "SetDrawLayer",
	"SetFont", "SetFrameLevel", "SetFrameStrata", "SetHighlightFontObject", "SetNormalFontObject",
	"SetScale", "SetStatusBarColor", "SetStatusBarTexture", "SetTextColor", "SetNameplateIconKind",
	"SetAutoFocus", "SetMaxLetters", "ClearFocus", "SetAlpha", "ClearAllPoints",
	"SetAllPoints", "SetAtlas", "SetTexCoord", "SetVertexColor", "SetBlendMode",
	"SetSpacing", "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetDisabledTexture",
	"SetPoint",
	"SetSize",
	"SetWidth",
	"SetHeight",
	"SetJustifyH",
	"SetWordWrap",
	"SetMaxLines",
	"SetHitRectInsets",
	"EnableMouse",
	"EnableMouseWheel",
	"SetScrollChild",
	"SetOrientation",
	"SetObeyStepOnDrag",
	"SetColorTexture",
	"SetTexture",
	"SetThumbTexture",
}) do
	methods[key] = function() end
end
function methods:SetPoint(...)
	self.points = self.points or {}
	self.points[#self.points + 1] = { ... }
end
function methods:ClearAllPoints() self.points = {} end
function methods:SetWidth(width) self.width = width end
function methods:GetWidth() return self.width end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetHeight(height) self.height = height end
function methods:GetHeight() return self.height end
function methods:SetScrollChild(child) self.child = child end
function methods:GetVerticalScrollRange() return math.max(0, self.child.height - self.height) end
function methods:GetVerticalScroll() return self.offset or 0 end
function methods:SetVerticalScroll(value)
	self.offset = value
	if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, value) end
end
function methods:SetInterpolateScroll(value) self.interpolate = value end
function methods:SetHideIfUnscrollable(value) self.hideIfUnscrollable = value end
function methods:SetVisibleExtentPercentage(value)
	self.visibleExtent = value
	if self.hideIfUnscrollable then self:SetShown(value > 0 and value < 1) end
end
function methods:SetPanExtentPercentage(value) self.panExtent = value end
function methods:SetScrollPercentage(value)
	self.percentage = value
	local listener = self.callbacks and self.callbacks.OnScroll
	if listener then listener[1](listener[2], value) end
end
function methods:UnregisterUpdate() self.scripts.OnUpdate = nil end
function methods:SetColorRGB(r, g, b) self.color = { r = r, g = g, b = b } end
function methods:Hide() self.hidden = true end
function methods:Show() self.hidden = false end
function methods:SetShown(shown) self.hidden = not shown end
function methods:GetText() return self.text end
function methods:GetStringHeight() return 16 end
function methods:GetFont() return "font", 12, "" end
function methods:GetFrameStrata() return "LOW" end
function methods:GetFrameLevel() return 0 end
function methods:IsVisible() return not self.hidden end
function methods:IsShown() return not self.hidden end
function methods:SetEnabled(enabled)
	self.enabled = enabled
	if self.Dropdown then self.Dropdown:SetEnabled(enabled); self:UpdateSteppers() end
end
function methods:IsEnabled() return self.enabled ~= false end
function methods:SetDefaultText(text) self.defaultText = text end
function methods:SetMenuAnchor(anchor) self.menuAnchor = anchor end
function methods:SetupMenu(generate)
	self.generate = generate
	self:GenerateMenu()
end
function methods:GenerateMenu()
	local menu = {}
	local rootDescription = {}
	function rootDescription:SetMinimumWidth(width) self.minimumWidth = width end
	function rootDescription:CreateHighlightRadio(text, selected, action)
		menu[#menu + 1] = { text = text, selected = selected, func = action }
	end
	self.generate(self, rootDescription)
	self.menu = menu
	self.text = self.defaultText
	for _, entry in ipairs(menu) do if entry.selected() then self.text = entry.text end end
	self.owner:UpdateSteppers()
end
function methods:UpdateSteppers()
	local index
	for i, entry in ipairs(self.Dropdown.menu or {}) do if entry.selected() then index = i end end
	self.DecrementButton:SetEnabled(self.Dropdown:IsEnabled() and index ~= nil and index > 1)
	self.IncrementButton:SetEnabled(self.Dropdown:IsEnabled() and index ~= nil and index < #self.Dropdown.menu)
end
CreateFrame = function(kind, _, parent, template)
	local frame = Region(kind, parent)
	frame.template = template
	if template == "SettingsDropdownWithButtonsTemplate" then
		frame.Dropdown, frame.Label = Region("DropdownButton"), Region("FontString")
		frame.Dropdown.owner = frame
		frame.DecrementButton, frame.IncrementButton = Region("Button"), Region("Button")
		local function Step(delta)
			if not frame.Dropdown:IsEnabled() then return end
			for i, entry in ipairs(frame.Dropdown.menu) do
				if entry.selected() then
					local nextEntry = frame.Dropdown.menu[i + delta]
					if nextEntry then nextEntry.func() end
					return
				end
			end
		end
		frame.IncrementButton:SetScript("OnClick", function() Step(1) end)
		frame.DecrementButton:SetScript("OnClick", function() Step(-1) end)
	elseif template == "MinimalSliderWithSteppersTemplate" then
		frame.Slider, frame.Back, frame.Forward = Region("Slider"), Region("Button"), Region("Button")
		frame.RightText, frame.MinText, frame.MaxText = Region("FontString"), Region("FontString"), Region("FontString")
		frame.Slider:SetScript("OnEnter", function() frame.nativeHover = true end)
		frame.Slider:SetScript("OnLeave", function() frame.nativeHover = false end)
		local function Step(button, direction)
			if button:IsEnabled() then frame:SetValue(frame.Slider.value + direction * frame.Slider.step) end
		end
		frame.Back:SetScript("OnClick", function() Step(frame.Back, -1) end)
		frame.Forward:SetScript("OnClick", function() Step(frame.Forward, 1) end)
	elseif template == "ColorSwatchTemplate" then
		frame:SetScript("OnEnter", function() frame.nativeHover = true end)
		frame:SetScript("OnLeave", function() frame.nativeHover = false end)
	elseif template == "MinimalScrollBar" then
		frame.Track, frame.Back, frame.Forward = Region("Frame", frame), Region("Button", frame), Region("Button", frame)
		frame.Track.Thumb = Region("Button", frame.Track)
	end
	return frame
end
AnchorUtil = { CreateAnchor = function(...) return { ... } end }
MinimalSliderWithSteppersMixin = { Label = { Right = 2 }, Event = { OnValueChanged = "OnValueChanged" } }
Settings = {
	RegisterCanvasLayoutCategory = function(_, name)
		return { name = name }
	end,
	RegisterCanvasLayoutSubcategory = function(_, _, name)
		return { name = name }
	end,
	RegisterAddOnCategory = function() end,
}
QuestTogether:InitializeDatabase()
local nativeSetOption, settingWrites = QuestTogether.SetOption, {}
QuestTogether.SetOption = function(self, key, value)
	settingWrites[key] = (settingWrites[key] or 0) + 1
	return nativeSetOption(self, key, value)
end
QuestTogether:InitializeAccessibilityWindow({})
QuestTogether:InitializeAnnouncementsWindow({})
QuestTogether:InitializePlayerLocationsWindow({})
QuestTogether:InitializeDeveloperWindow({})
assert(QuestTogether.accessibilityFrame and QuestTogether.playerLocationsFrame)
QuestTogether.accessibilityFrame.scripts.OnShow()
local scale, nearby, sliderCount
sliderCount = 0
for _, f in ipairs(regions) do
	if f.template == "MinimalSliderWithSteppersTemplate" then
		sliderCount = sliderCount + 1
		if f.Slider.minimum == 80 then scale = f else nearby = f end
	end
end
assert(sliderCount == 2, "both numeric settings must use Blizzard's native slider template")
assert(scale and scale.Slider.minimum == 80 and scale.Slider.maximum == 150 and scale.Slider.step == 5)
assert(nearby and nearby.Slider.minimum == 5 and nearby.Slider.maximum == 100 and nearby.Slider.step == 1)
assert(scale.RightText.text == "100%" and nearby.RightText.text == "25%")
assert(not settingWrites.windowScale and not settingWrites.nearbyAnnouncementRange,
	"initializing and showing settings must not persist slider values")
local range = QuestTogether:GetOption("nearbyAnnouncementRange")
scale.Slider:SetValue(125) -- Native drag callback, not an addon-installed child script.
assert(QuestTogether:GetOption("windowScale") == 125)
assert(QuestTogether:GetOption("nearbyAnnouncementRange") == range)
assert(scale.RightText.text == "125%" and settingWrites.windowScale == 1)
scale.Forward.scripts.OnClick()
assert(QuestTogether:GetOption("windowScale") == 130 and scale.RightText.text == "130%")
nearby.Slider:SetValue(60)
nearby.Back.scripts.OnClick()
assert(QuestTogether:GetOption("nearbyAnnouncementRange") == 59 and nearby.RightText.text == "59%")
assert(QuestTogether:GetOption("windowScale") == 130)
for _, control in ipairs({ scale, nearby }) do
	assert(control.Slider.scripts.OnValueChanged == control.nativeOnValueChanged,
		"addon configuration must preserve the native slider value handler")
	control.Slider:SetValue(control.Slider.minimum)
	assert(not control.Back:IsEnabled() and control.Forward:IsEnabled())
	control.Back.scripts.OnClick()
	assert(control.Slider.value == control.Slider.minimum)
	control.Slider:SetValue(control.Slider.maximum)
	assert(control.Back:IsEnabled() and not control.Forward:IsEnabled())
	control.Forward.scripts.OnClick()
	assert(control.Slider.value == control.Slider.maximum)
	for _, region in ipairs({ control.Slider, control.Back, control.Forward }) do
		assert(region.scripts.OnEnter and region.scripts.OnLeave, "slider and both arrows require tooltips")
	end
end
local savedProfile = QuestTogether.db.profile
local scaleWrites, rangeWrites = settingWrites.windowScale, settingWrites.nearbyAnnouncementRange
QuestTogether.db.profile = QuestTogether:DeepCopy(savedProfile)
QuestTogether.db.profile.windowScale, QuestTogether.db.profile.nearbyAnnouncementRange = 85, 10
QuestTogether.accessibilityFrame.scripts.OnShow()
nearby:RefreshNearbyRange()
assert(scale.RightText.text == "85%" and nearby.RightText.text == "10%")
assert(settingWrites.windowScale == scaleWrites and settingWrites.nearbyAnnouncementRange == rangeWrites,
	"profile refresh must update values without saving them back")
QuestTogether.db.profile = savedProfile
QuestTogether.accessibilityFrame.scripts.OnShow()
nearby:RefreshNearbyRange()
local showTooltip, hideTooltip = QuestTogether.ShowSettingsTooltip, QuestTogether.HideSettingsTooltip
local tooltipOwner
QuestTogether.ShowSettingsTooltip = function(_, owner) tooltipOwner = owner end
QuestTogether.HideSettingsTooltip = function(_, owner) assert(tooltipOwner == owner); tooltipOwner = nil end
for _, control in ipairs({ scale, nearby }) do
	control.Slider.scripts.OnEnter(control.Slider)
	assert(control.nativeHover and tooltipOwner == control.Slider, "tooltips must preserve native hover interaction")
	control.Slider.scripts.OnLeave(control.Slider)
	assert(not control.nativeHover and not tooltipOwner)
end
QuestTogether.ShowSettingsTooltip, QuestTogether.HideSettingsTooltip = showTooltip, hideTooltip
QuestTogether.SetOption = nativeSetOption
print("Native settings sliders, stepper bounds, profile refresh, and tooltip interaction passed")
assert(QuestTogether.playerLocationsControls.showPlayerLocations == nil)
assert(QuestTogether.playerLocationsControls.mapAlwaysShowParty == nil)
assert(QuestTogether:GetOption("sharePlayerLocation") == true)
local filter = QuestTogether.playerLocationsControls.filterDropdown
assert(filter and filter.template == "SettingsDropdownWithButtonsTemplate")
assert(filter.Dropdown.width == 310)
assert(filter.Dropdown.menuAnchor[1] == "TOPRIGHT" and filter.Dropdown.menuAnchor[2] == filter.Dropdown
	and filter.Dropdown.menuAnchor[3] == "BOTTOMRIGHT")
assert(filter.Dropdown.text == "All QuestTogether players")
assert(filter.title.text == "Players shown on maps")
assert(filter.Dropdown.scripts.OnEnter and filter.Dropdown.scripts.OnLeave)
local menu = filter.Dropdown.menu
assert(menu[1].selected() and not menu[2].selected() and not menu[3].selected())
for _, f in ipairs(regions) do
	if f.Label and f.Label.text == "Reduce motion" then
		f.checked = true
		f.scripts.OnClick(f)
	end
end
assert(#menu == 3)
for _, case in ipairs({
	{ 3, "None", false, false },
	{ 2, "Players looking for questing partners", true, true },
	{ 1, "All QuestTogether players", true, false },
}) do
	filter.Dropdown.menu[case[1]].func()
	assert(filter.Dropdown.text == case[2] and filter.Dropdown.menu[case[1]].selected())
	assert(QuestTogether:GetOption("showPlayerLocations") == case[3])
	assert(QuestTogether:GetOption("onlyShowQuestPartners") == case[4])
	assert(QuestTogether:GetOption("mapPartyOnly") == nil and QuestTogether:GetOption("mapAlwaysShowParty") == nil)
	assert(QuestTogether:GetOption("sharePlayerLocation") == true)
end
-- Native steppers use the same selection actions and stop at the ends.
assert(not filter.DecrementButton:IsEnabled() and filter.IncrementButton:IsEnabled())
filter.IncrementButton.scripts.OnClick()
assert(filter.Dropdown.menu[2].selected() and QuestTogether:GetOption("onlyShowQuestPartners"))
filter.DecrementButton.scripts.OnClick()
assert(filter.Dropdown.menu[1].selected())
filter:SetEnabled(false)
assert(not filter.DecrementButton:IsEnabled() and not filter.IncrementButton:IsEnabled())
filter.IncrementButton.scripts.OnClick()
assert(filter.Dropdown.menu[1].selected())
filter:SetEnabled(true)
-- Existing preferences and profile changes map to the matching selection.
QuestTogether:SetOption("onlyShowQuestPartners", true)
QuestTogether:RefreshPlayerLocationsWindow()
assert(filter.Dropdown.menu[2].selected())
QuestTogether:SetOption("showPlayerLocations", false)
QuestTogether:RefreshPlayerLocationsWindow()
assert(filter.Dropdown.text == "None" and filter.Dropdown.menu[3].selected())
assert(QuestTogether:GetOption("reduceMotion"))
local found = false
for _, f in ipairs(regions) do
	if f.text == "Reset window layout" then
		f.scripts.OnClick()
		found = true
	end
end
assert(found)
print("Accessibility and player-location settings constructors and callbacks passed")

assert(QuestTogether.developerCategory.name == "Developer")
assert(QuestTogether.playerLocationsControls.shareDeveloperDiagnostics == nil)
local diagnostics = QuestTogether.developerControls.shareDeveloperDiagnostics
assert(diagnostics.checked == true)
diagnostics.checked = false
diagnostics.scripts.OnClick(diagnostics)
assert(QuestTogether:GetOption("shareDeveloperDiagnostics") == false)
QuestTogether:SetOption("shareDeveloperDiagnostics", true)
QuestTogether.developerFrame.scripts.OnShow()
assert(diagnostics.checked == true)
local opened, rescanned = false, false
QuestTogether.ShowDebugWindow = function() opened = true end
QuestTogether.ScanQuestLog = function() rescanned = true end
QuestTogether.developerControls.debugButton.scripts.OnClick()
QuestTogether.developerControls.rescanQuestLog.scripts.OnClick()
assert(opened and rescanned)
print("Developer settings category, diagnostic preference, and troubleshooting actions passed")

QuestTogether:InitializeProfilesWindow({})
QuestTogether:InitializeAnnouncementsWindow({})
QuestTogether:InitializeWhereToAnnounceWindow({})
QuestTogether:InitializeQuestPlatesWindow({})
QuestTogether:InitializeQuestPlatesWindow({}, true)
local dropdownCount = 0
for _, region in ipairs(regions) do
	if region.template == "SettingsDropdownWithButtonsTemplate" then
		dropdownCount = dropdownCount + 1
		assert(region.Dropdown.menuAnchor[1] == "TOPRIGHT")
		assert(region.Dropdown.scripts.OnEnter and region.IncrementButton.scripts.OnEnter
			and region.DecrementButton.scripts.OnEnter)
	end
end
assert(dropdownCount == 9, "all nine settings dropdowns must use the native template")
local profileControls = QuestTogether.profileControls
assert(not profileControls.copyFromProfileDropdown.Dropdown:IsEnabled())
assert(not profileControls.copyFromProfileDropdown.IncrementButton:IsEnabled())
-- Profile persistence is real; keep gameplay services outside this UI harness.
QuestTogether.ApplyActiveProfileState = function(self)
	self:RefreshOptionsWindow()
	self:RefreshProfilesWindow()
end
local firstProfile = QuestTogether:GetCurrentProfileKey()
assert(QuestTogether:CreateProfile("Dropdown test profile"))
QuestTogether:RefreshProfilesWindow()
local profiles = profileControls.currentProfileDropdown
assert(#profiles.Dropdown.menu == 2)
for _, entry in ipairs(profiles.Dropdown.menu) do
	if entry.text == firstProfile then entry.func(); break end
end
assert(QuestTogether:GetCurrentProfileKey() == firstProfile)
assert(profiles.Dropdown.text == firstProfile)
local chat = QuestTogether.whereToAnnounceControls.chatLogDestinationDropdown
QuestTogether:SetOption("showChatLogs", false)
QuestTogether:RefreshWhereToAnnounceWindow()
assert(not chat.Dropdown:IsEnabled() and not chat.IncrementButton:IsEnabled()
	and not chat.DecrementButton:IsEnabled())
QuestTogether:SetOption("showChatLogs", true)
QuestTogether:RefreshWhereToAnnounceWindow()
assert(chat.Dropdown:IsEnabled())
local scope = QuestTogether.whereToAnnounceControls.qtChatScopeDropdown
scope.Dropdown.menu[2].func()
assert(QuestTogether:GetOption("qtChatScope") == "global")
assert(scope.Dropdown.text == "Global")
scope.DecrementButton.scripts.OnClick()
assert(QuestTogether:GetOption("qtChatScope") == "zone_only")
print("All nine native settings dropdowns, profile changes, and disabled controls passed")

local checkboxCount, scrollbarCount, swatch = 0, 0
for _, region in ipairs(regions) do
	if region.kind == "CheckButton" then
		checkboxCount = checkboxCount + 1
		assert(region.template == "MinimalCheckboxTemplate")
	elseif region.kind == "ScrollFrame" then
		local bar = region.ScrollBar
		assert(bar and bar.template == "MinimalScrollBar" and not bar.interpolate)
		scrollbarCount = scrollbarCount + 1
		local maximum = region:GetVerticalScrollRange()
		local halfway = maximum / 2
		bar:SetScrollPercentage(0.5)
		assert(math.abs(region:GetVerticalScroll() - halfway) < 0.000001)
		region.scripts.OnMouseWheel(region, -1)
		assert(math.abs(region:GetVerticalScroll() - math.min(maximum, halfway + 30)) < 0.000001)
		-- Resize while scrolled: clamp the model and hide an unnecessary bar.
		region:SetHeight(region.child.height + 50)
		region:SetWidth(900)
		region.scripts.OnSizeChanged(region)
		assert(region:GetVerticalScroll() == 0 and bar.percentage == 0 and bar.hidden)
		assert(region.child.width == 892)
		region:SetHeight(200)
		region.scripts.OnSizeChanged(region)
		assert(not bar.hidden and bar.visibleExtent == 200 / region.child.height)
	elseif region.template == "ColorSwatchTemplate" then
		swatch = region
	end
end
assert(checkboxCount > 20 and scrollbarCount == 8 and swatch)
local scrollFrame
for _, region in ipairs(regions) do
	if region.kind == "ScrollFrame" then scrollFrame = region; break end
end
local isRestricted, schedule = QuestTogether.IsRuntimeRestricted, QuestTogether.ScheduleRuntimeWork
local pending
QuestTogether.IsRuntimeRestricted = function() return true end
QuestTogether.ScheduleRuntimeWork = function(_, kind, key, run, options)
	assert(kind == "foreign_frame_mutation" and type(key) == "string" and options.lifetime == "ui")
	pending = run
end
scrollFrame:SetWidth(1000)
scrollFrame.scripts.OnSizeChanged(scrollFrame)
assert(pending and scrollFrame.child.width == 892, "restricted resize must defer native layout changes")
QuestTogether.IsRuntimeRestricted, QuestTogether.ScheduleRuntimeWork = isRestricted, schedule
pending()
assert(scrollFrame.child.width == 992, "deferred refresh must use the latest settings panel width")
local previous = QuestTogether:DeepCopy(QuestTogether:GetOption("nameplateQuestHealthColor"))
local picker
ColorPickerFrame = {
	SetupColorPickerAndShow = function(_, info) picker = info end,
	GetColorRGB = function() return 0.2, 0.4, 0.6 end,
}
swatch.scripts.OnClick(swatch)
picker.swatchFunc()
assert(swatch.color.r == 0.2 and swatch.color.g == 0.4 and swatch.color.b == 0.6)
picker.cancelFunc()
assert(swatch.color.r == previous.r and swatch.color.g == previous.g and swatch.color.b == previous.b)
local activeProfile = QuestTogether.db.profile
swatch.scripts.OnClick(swatch)
QuestTogether.db.profile = QuestTogether:DeepCopy(activeProfile)
picker.swatchFunc()
assert(QuestTogether:GetOption("nameplateQuestHealthColor").r == previous.r,
	"an old color picker must not write to a newly selected profile")
QuestTogether.db.profile = activeProfile
QuestTogether.ShowSettingsTooltip = function(_, owner) tooltipOwner = owner end
QuestTogether.HideSettingsTooltip = function() tooltipOwner = nil end
swatch.scripts.OnEnter(swatch)
assert(swatch.nativeHover and tooltipOwner == swatch)
swatch.scripts.OnLeave(swatch)
assert(not swatch.nativeHover and not tooltipOwner)
QuestTogether.ShowSettingsTooltip, QuestTogether.HideSettingsTooltip = showTooltip, hideTooltip
print("Native checkboxes, swatch cancel/profile safety, and settings scrollbar resize/wheel behavior passed")

QuestTogether:InitializeOptionsWindow()
QuestTogether.optionsFrame.scripts.OnShow()
local startupTips = assert(QuestTogether.homeControls.showStartupTips)
assert(startupTips.template == "MinimalCheckboxTemplate")
assert(startupTips.Label.text == "Show tips on login" and startupTips:GetChecked() == true)
local capturedTooltip
QuestTogether.ShowSettingsTooltip = function(_, owner, title, text)
	assert(owner == startupTips and title == "Show tips on login")
	capturedTooltip = text
end
startupTips.scripts.OnEnter(startupTips)
QuestTogether.ShowSettingsTooltip = showTooltip
assert(capturedTooltip == "Show a QuestTogether tip when you log in or reload. You can still use /qt tip or /qt hint at any time.")
startupTips:SetChecked(false)
startupTips.scripts.OnClick(startupTips)
assert(QuestTogether:GetOption("showStartupTips") == false)
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.optionsFrame.scripts.OnShow()
assert(startupTips:GetChecked() == true, "the home checkbox must refresh from the current profile")
print("Startup tip checkbox, explanatory tooltip, saved opt-out, and profile refresh passed")

local home = QuestTogether.homeControls
assert(home.generalHeader.points[1][2] == home.description)
assert(home.showMinimapButton.points[1][2] == home.generalHeader)
assert(home.showStartupTips.points[1][2] == home.showMinimapButton)
local theme = assert(home.themeDropdown)
assert(home.lightMode == nil, "the old Light mode checkbox must not remain beside the dropdown")
assert(theme.template == "SettingsDropdownWithButtonsTemplate" and theme.title.text == "Theme")
assert(theme.title.points[1][2] == home.showStartupTips)
assert(home.statusPanel.points[1][2] == theme, "General settings must come before the status overview")
assert(home.tipsHeader.points[1][2] == home.statusPanel)
assert(theme.Dropdown.menuAnchor[1] == "TOPRIGHT" and theme.Dropdown.menuAnchor[3] == "BOTTOMRIGHT")
assert(#theme.Dropdown.menu == 2 and theme.Dropdown.menu[1].text == "Dark" and theme.Dropdown.menu[2].text == "Light")
local themesRefreshed, refreshThemes = 0, QuestTogether.RefreshWindowThemes
QuestTogether.RefreshWindowThemes = function() themesRefreshed = themesRefreshed + 1 end
local themeWrites, setOption = 0, QuestTogether.SetOption
QuestTogether.SetOption = function(self, key, value)
	if key == "lightMode" then themeWrites = themeWrites + 1 end
	return setOption(self, key, value)
end
theme.Dropdown.menu[2].func()
assert(QuestTogether:GetOption("lightMode") == true and theme.Dropdown.text == "Light")
assert(theme.Dropdown.menu[2].selected() and not theme.IncrementButton:IsEnabled())
assert(themeWrites == 1 and themesRefreshed > 0)
local firstRefreshes = themesRefreshed
theme.DecrementButton.scripts.OnClick()
assert(QuestTogether:GetOption("lightMode") == false and theme.Dropdown.text == "Dark")
assert(theme.Dropdown.menu[1].selected() and not theme.DecrementButton:IsEnabled())
assert(themeWrites == 2 and themesRefreshed > firstRefreshes, "each selection must save once and apply theme effects")
QuestTogether.RefreshWindowThemes = refreshThemes
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.db.profile.lightMode = true
local writesBeforeRefresh = themeWrites
QuestTogether.optionsFrame.scripts.OnShow()
assert(theme.Dropdown.text == "Light" and theme.Dropdown.menu[2].selected())
assert(themeWrites == writesBeforeRefresh, "profile refresh must not write the theme selection back")
QuestTogether.SetOption = setOption

assert(#home.statusGroups == 7 and home.statusPanel.height == 304)
assert(home.statusPanel.height >= home.actionsPanel.height, "footer must clear the adjacent action buttons")
assert(not home.statusGroups[1].text.hidden and home.statusGroups[1].text.text:find("Active profile", 1, true))
for index = 2, #home.statusGroups do
	assert(home.statusGroups[index].text.hidden and home.statusGroups[index].frame.height == 22)
end
local partners = home.statusGroups[2]
QuestTogether.ShowSettingsTooltip = function(_, owner, title, text)
	assert(owner == partners.button and title == "Finding Partners")
	capturedTooltip = text
end
partners.button.scripts.OnEnter(partners.button)
assert(capturedTooltip:find("Looking for Questing Partners: Off", 1, true))
QuestTogether.db.profile.lookingForQuestPartners = true
QuestTogether.optionsFrame.scripts.OnUpdate(QuestTogether.optionsFrame, 1)
partners.button.scripts.OnEnter(partners.button)
assert(capturedTooltip:find("Looking for Questing Partners: On", 1, true), "hover details must follow current settings")
assert(capturedTooltip:find("Open the settings for this section.", 1, true))
QuestTogether.ShowSettingsTooltip = showTooltip
print("General-first home layout, compact live status tooltips, and native Theme dropdown/profile effects passed")
