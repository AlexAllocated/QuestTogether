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
function methods:CreateFontString(_, _, fontObject)
	local region = Region("FontString")
	region.parent, region.fontObject = self, fontObject
	return region
end
function methods:CreateTexture()
	local region = Region("Texture")
	region.parent = self
	return region
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
	"SetTextInsets", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetClampedToScreen", "SetDrawLayer",
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
function methods:ClearAllPoints() self.points, self.allPoints = {}, nil end
function methods:SetAllPoints(relative) self.allPoints = relative or self.parent end
function methods:SetAtlas(atlas) self.atlas, self.texture = atlas, nil end
function methods:SetTexture(texture) self.texture, self.atlas = texture, nil end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetDrawLayer(layer, sublevel) self.drawLayer, self.drawSublevel = layer, sublevel end
function methods:SetFontObject(fontObject) self.fontObject = fontObject end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetFont(path, height, flags) self.fontPath, self.fontHeight, self.fontFlags = path, height, flags end
function methods:SetTextHeight(height) self.fontHeight = height end
function methods:SetJustifyH(justify) self.justifyH = justify end
function methods:SetWordWrap(wrap) self.wordWrap = wrap end
function methods:GetJustifyH() return self.justifyH or "LEFT" end
function methods:GetJustifyV() return self.justifyV or "MIDDLE" end
function methods:SetScale(scale) self.scale = scale end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale()
	return self:GetScale() * (self.parent and self.parent.GetEffectiveScale and self.parent:GetEffectiveScale() or 1)
end
function methods:RegisterEvent(event)
	self.events = self.events or {}
	self.events[event] = true
end
function methods:UnregisterEvent(event) if self.events then self.events[event] = nil end end
function methods:SetWidth(width) self.width = width end
function methods:GetWidth() return self.allPoints and self.allPoints:GetWidth() or self.width end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetHeight(height) self.height = height end
function methods:GetHeight() return self.allPoints and self.allPoints:GetHeight() or self.height end
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
function methods:GetStringHeight() return self.fontHeight or 16 end
function methods:GetStringWidth() return #(self.text or "") * (self.fontHeight or 12) * 0.5 end
function methods:GetFont() return self.fontPath or "font", self.fontHeight or 12, self.fontFlags or "" end
function methods:GetFrameStrata() return "LOW" end
function methods:GetFrameLevel() return 0 end
function methods:IsVisible()
	local frame = self
	while frame do
		if frame.hidden then return false end
		frame = frame.parent
	end
	return true
end
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
print("Accessibility and player-location settings constructors and callbacks passed")

assert(QuestTogether.playerLocationsControls.shareDeveloperDiagnostics == nil)
local diagnostics = QuestTogether.developerControls.shareDeveloperDiagnostics
assert(diagnostics.checked == true)
diagnostics.checked = false
diagnostics.scripts.OnClick(diagnostics)
assert(QuestTogether:GetOption("shareDeveloperDiagnostics") == false)
QuestTogether:SetOption("shareDeveloperDiagnostics", true)
QuestTogether.developerFrame.scripts.OnShow()
assert(diagnostics.checked == true)
print("Developer diagnostic preference and profile refresh passed")

QuestTogether:InitializeProfilesWindow({})
QuestTogether:InitializeAnnouncementsWindow({})
QuestTogether:InitializeWhereToAnnounceWindow({})
QuestTogether:InitializeQuestPlatesWindow({})
QuestTogether:InitializeQuestPlatesWindow({}, true)
local dropdownCount = 0

-- Check the controls exposed by each initialized settings page, rather than
-- pinning how many dropdowns happen to exist in this version of the addon.
for name, controls in pairs(QuestTogether) do
	if type(name) == "string" and name:match("Controls$") and type(controls) == "table" then
		for key, region in pairs(controls) do
			if type(key) == "string" and key:match("Dropdown$") then
				dropdownCount = dropdownCount + 1
				assert(region.template == "SettingsDropdownWithButtonsTemplate", name .. "." .. key)
				assert(region.Dropdown.menuAnchor[1] == "TOPRIGHT")
				assert(region.Dropdown.scripts.OnEnter and region.IncrementButton.scripts.OnEnter
					and region.DecrementButton.scripts.OnEnter)
			end
		end
	end
end
assert(dropdownCount > 0, "settings pages must expose their dropdown controls")
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
print("Native settings dropdowns, profile changes, and disabled controls passed")

local autoThankBuffs = assert(QuestTogether.whereToAnnounceControls.autoThankBuffs)
assert(autoThankBuffs.template == "MinimalCheckboxTemplate")
assert(autoThankBuffs.Label.text == "Automatically thank players for buffs")
assert(autoThankBuffs:GetChecked() == true, "buff thanks starts enabled")
autoThankBuffs:SetChecked(false)
autoThankBuffs.scripts.OnClick(autoThankBuffs)
assert(QuestTogether:GetOption("autoThankBuffs") == false, "the checkbox must persist the opt-out")
assert(QuestTogether:SetActiveProfile("Dropdown test profile"))
assert(autoThankBuffs:GetChecked() == true, "buff thanks follows the newly selected profile")
assert(QuestTogether:SetActiveProfile(firstProfile))
assert(autoThankBuffs:GetChecked() == false, "returning to a profile preserves its buff-thanks choice")
local autoThanksPoint = autoThankBuffs.points[#autoThankBuffs.points]
assert(autoThankBuffs.parent == QuestTogether.whereToAnnounceControls.emoteOnNearbyPlayerLevelUp.parent,
	"buff thanks belongs to the same native settings navigation container as the other emotes")
assert(autoThankBuffs.parent:GetHeight() >= -autoThanksPoint[5] + 48,
	"the emote settings content must leave space below the buff-thanks checkbox")
autoThankBuffs:SetChecked(true)
autoThankBuffs.scripts.OnClick(autoThankBuffs)
print("Buff-thanks opt-out, profile refresh, and scrollable native checkbox placement passed")

local ownBubble = QuestTogether.whereToAnnounceControls.ownChatBubbleModeDropdown
assert(QuestTogether.whereToAnnounceControls.hideMyOwnChatBubbles == nil)
assert(ownBubble.title.text == "My chat bubble")
assert(ownBubble.Dropdown.text == "Show always")
ownBubble.Dropdown.menu[2].func()
assert(QuestTogether:GetOwnChatBubbleMode() == "solo")
assert(ownBubble.Dropdown.text == "Show only when solo")
QuestTogether:SetOption("showChatBubbles", false)
QuestTogether:RefreshWhereToAnnounceWindow()
assert(ownBubble:IsShown() and ownBubble.title:IsShown())
assert(not ownBubble.Dropdown:IsEnabled() and not ownBubble.DecrementButton:IsEnabled()
	and not ownBubble.IncrementButton:IsEnabled())
assert(QuestTogether:GetOwnChatBubbleMode() == "solo")
QuestTogether:SetOption("showChatBubbles", true)
QuestTogether:RefreshWhereToAnnounceWindow()
assert(ownBubble.Dropdown:IsEnabled() and ownBubble.Dropdown.menu[2].selected())
assert(QuestTogether:SetActiveProfile("Dropdown test profile"))
assert(ownBubble.Dropdown.text == "Show always")
assert(QuestTogether:SetActiveProfile(firstProfile))
assert(ownBubble.Dropdown.text == "Show only when solo")
ownBubble.IncrementButton.scripts.OnClick()
assert(QuestTogether:GetOwnChatBubbleMode() == "hidden" and ownBubble.Dropdown.text == "Hide always")
ownBubble.Dropdown.menu[1].func()
assert(QuestTogether:GetOwnChatBubbleMode() == "always")
print("Personal bubble dropdown preserves profile choices and follows the bubble master switch")

local playerTooltip = QuestTogether.playerPlateControls.playerTooltipIdentifierDropdown
assert(playerTooltip.title.text == "QuestTogether tooltip")
assert(playerTooltip.Dropdown.text == "Hide for friends")
local tooltipChoices = {
	{ "all", "Show for everyone" }, { "friends", "Hide for friends" },
	{ "party", "Hide for party members" }, { "friends_party", "Hide for friends and party members" },
	{ "hidden", "Hide for everyone" },
}
assert(#playerTooltip.Dropdown.menu == #tooltipChoices)
for index, choice in ipairs(tooltipChoices) do
	assert(playerTooltip.Dropdown.menu[index].text == choice[2])
	playerTooltip.Dropdown.menu[index].func()
	assert(QuestTogether:GetPlayerTooltipIdentifierMode() == choice[1])
	assert(playerTooltip.Dropdown.text == choice[2] and playerTooltip.Dropdown.menu[index].selected())
end
QuestTogether:SetOption("nameplatePlayerIconEnabled", false)
QuestTogether:RefreshQuestPlatesWindow(true)
assert(playerTooltip.Dropdown:IsEnabled(), "tooltip visibility is independent of nameplate icons")
assert(QuestTogether:SetActiveProfile("Dropdown test profile"))
assert(playerTooltip.Dropdown.text == "Hide for friends")
assert(QuestTogether:SetActiveProfile(firstProfile))
assert(playerTooltip.Dropdown.text == "Hide for everyone")
playerTooltip.Dropdown.menu[2].func()
QuestTogether:SetOption("nameplatePlayerIconEnabled", true)
print("Player tooltip identifier controls preserve profile choices independently of nameplate visibility")

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
assert(checkboxCount > 0 and scrollbarCount > 0 and swatch)
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
startupTips:SetChecked(false)
startupTips.scripts.OnClick(startupTips)
assert(QuestTogether:GetOption("showStartupTips") == false)
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.optionsFrame.scripts.OnShow()
assert(startupTips:GetChecked() == true, "the home checkbox must refresh from the current profile")
print("Startup tip opt-out and profile refresh passed")

local home = QuestTogether.homeControls
local theme = assert(home.themeDropdown)
assert(home.lightMode == nil, "the old Light mode checkbox must not remain beside the dropdown")
assert(theme.template == "SettingsDropdownWithButtonsTemplate" and theme.title.text == "Theme")
assert(theme.Dropdown.menuAnchor[1] == "TOPRIGHT" and theme.Dropdown.menuAnchor[3] == "BOTTOMRIGHT")
assert(#theme.Dropdown.menu == 2 and theme.Dropdown.menu[1].text == "Dark" and theme.Dropdown.menu[2].text == "Light")
local themesRefreshed, refreshThemes = 0, QuestTogether.RefreshWindowThemes
QuestTogether.RefreshWindowThemes = function() themesRefreshed = themesRefreshed + 1 end
assert(QuestTogether:SetOption("lightMode", "true") == false, "theme preference requires a boolean")
assert(QuestTogether:GetOption("lightMode") == false and themesRefreshed == 0,
	"invalid theme values must not change the preference or refresh windows")
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
local wasEnabled = QuestTogether.isEnabled
QuestTogether.isEnabled = not wasEnabled
QuestTogether.optionsFrame.scripts.OnUpdate(QuestTogether.optionsFrame, 1)
assert(home.statusText.text:find("QuestTogether: " .. (QuestTogether.isEnabled and "Enabled" or "Disabled"), 1, true))
QuestTogether.isEnabled = wasEnabled
print("Home runtime status and native Theme dropdown/profile effects passed")

local brokerChoices = {
	{ "pql", "Party Quest Log" }, { "menu", "Menu" },
	{ "partners", "Looking for Questing Partners" }, { "settings", "Settings" }, { "none", "None" },
}
assert(home.dataBrokerHeader.text == "Data Broker")
assert(home.dataBrokerHint.text:find("LibDataBroker", 1, true))
assert(home.brokerLeftClickDropdown.Dropdown.text == "Party Quest Log")
assert(home.brokerRightClickDropdown.Dropdown.text == "Menu")
local brokerWrites, brokerSetOption = { brokerLeftClick = 0, brokerRightClick = 0 }, QuestTogether.SetOption
QuestTogether.SetOption = function(self, key, value)
	if brokerWrites[key] then brokerWrites[key] = brokerWrites[key] + 1 end
	return brokerSetOption(self, key, value)
end
for _, key in ipairs({ "brokerLeftClick", "brokerRightClick" }) do
	local control = assert(home[key .. "Dropdown"])
	assert(control.template == "SettingsDropdownWithButtonsTemplate")
	assert(control.Dropdown:IsEnabled(), "broker clicks can be configured without an installed broker display")
	assert(control.Dropdown.menuAnchor[1] == "TOPRIGHT" and control.Dropdown.menuAnchor[3] == "BOTTOMRIGHT")
	assert(control.Dropdown.scripts.OnEnter and control.IncrementButton.scripts.OnEnter
		and control.DecrementButton.scripts.OnEnter)
	assert(#control.Dropdown.menu == #brokerChoices)
	for index, choice in ipairs(brokerChoices) do
		local writes = brokerWrites[key]
		assert(control.Dropdown.menu[index].text == choice[2])
		control.Dropdown.menu[index].func()
		assert(QuestTogether:GetOption(key) == choice[1] and control.Dropdown.text == choice[2])
		assert(control.Dropdown.menu[index].selected() and brokerWrites[key] == writes + 1,
			"a broker action selection must save once and refresh the native control")
	end
end
local brokerProfile = QuestTogether.db.profile
local leftWrites, rightWrites = brokerWrites.brokerLeftClick, brokerWrites.brokerRightClick
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.db.profile.brokerLeftClick = "settings"
QuestTogether.db.profile.brokerRightClick = "partners"
QuestTogether.optionsFrame.scripts.OnShow()
assert(home.brokerLeftClickDropdown.Dropdown.text == "Settings"
	and home.brokerRightClickDropdown.Dropdown.text == "Looking for Questing Partners")
assert(home.brokerLeftClickDropdown.Dropdown.menu[4].selected()
	and home.brokerRightClickDropdown.Dropdown.menu[3].selected())
assert(brokerWrites.brokerLeftClick == leftWrites and brokerWrites.brokerRightClick == rightWrites,
	"profile refresh must not persist broker click selections")
QuestTogether.SetOption = brokerSetOption
QuestTogether.db.profile = brokerProfile
QuestTogether:RefreshHomeWindow()
assert(home.brokerLeftClickDropdown.Dropdown.text == "None" and home.brokerRightClickDropdown.Dropdown.text == "None")
print("Optional Data Broker native click settings and profile refresh passed")

local tracker = QuestTogether.questTrackerModeDropdown
assert(tracker)
assert(QuestTogether:GetQuestTrackerMode() == "hover")
QuestTogether:RefreshGroupsWindow()
assert(tracker.Dropdown.text == "Hovered Quest")
assert(#tracker.Dropdown.menu == 4)
tracker.Dropdown.menu[1].func()
assert(QuestTogether:GetQuestTrackerMode() == "hidden")
QuestTogether:RefreshGroupsWindow()
assert(tracker.Dropdown.text == "Hidden")
assert(QuestTogether:ValidateSetting("questTrackerMode", "invalid") == nil)
for _, mode in ipairs({ "hidden", "focus", "hover", "both" }) do
	QuestTogether.db.profile.questTrackerMode = mode
	QuestTogether:NormalizeSettingsProfile()
	assert(QuestTogether:GetQuestTrackerMode() == mode, "saved display choices must survive normalization")
end
for _, value in ipairs({ false, "invalid" }) do
	QuestTogether.db.profile.questTrackerMode = value or nil
	assert(QuestTogether:GetQuestTrackerMode() == "hover", "missing or invalid modes fall back to hover")
	QuestTogether:NormalizeSettingsProfile()
	assert(QuestTogether:GetQuestTrackerMode() == "hover")
end
QuestTogether.db.profile.showQuestFocusWindow = false
QuestTogether.db.profile.questTrackerMode = "both"
QuestTogether:NormalizeSettingsProfile()
assert(QuestTogether:GetQuestTrackerMode() == "hidden")
assert(QuestTogether.db.profile.showQuestFocusWindow == nil)
QuestTogether:SetOption("questTrackerMode", "hover")
QuestTogether:NormalizeSettingsProfile()
assert(QuestTogether:GetQuestTrackerMode() == "hover")
QuestTogether:SetOption("questTrackerMode", "both")
print("Party Objective Tracker display choices, invalid values and checkbox migration passed")

local hideSolo = assert(QuestTogether.groupsControls.questTrackerHideSolo)
QuestTogether:RefreshGroupsWindow()
assert(hideSolo:GetChecked() == true, "new profiles hide POT while solo")
hideSolo:SetChecked(false)
hideSolo.scripts.OnClick(hideSolo)
assert(QuestTogether:GetOption("questTrackerHideSolo") == false)
QuestTogether:SetOption("questTrackerHideSolo", true)
QuestTogether:RefreshGroupsWindow()
assert(hideSolo:GetChecked() == true, "settings reflects changes from Edit Mode")
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.db.profile.questTrackerHideSolo = false
QuestTogether.groupsFrame.scripts.OnShow()
assert(hideSolo:GetChecked() == false, "checkbox follows the active profile")
print("Party Objective Tracker solo visibility uses the shared setting and refreshes across profiles")

local hideTooltip = assert(QuestTogether.groupsControls.questTrackerHideBlizzardTooltip)
QuestTogether:RefreshGroupsWindow()
assert(hideTooltip:GetChecked() == true, "new profiles hide the matching Blizzard quest tooltip while POT is visible")
hideTooltip:SetChecked(false)
hideTooltip.scripts.OnClick(hideTooltip)
assert(QuestTogether:GetOption("questTrackerHideBlizzardTooltip") == false)
QuestTogether:SetOption("questTrackerHideBlizzardTooltip", true)
QuestTogether:RefreshGroupsWindow()
assert(hideTooltip:GetChecked() == true, "settings reflects the tooltip option changed in Edit Mode")
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.db.profile.questTrackerHideBlizzardTooltip = false
QuestTogether.groupsFrame.scripts.OnShow()
assert(hideTooltip:GetChecked() == false, "tooltip checkbox follows the active profile")
QuestTogether:ApplyDefaults(QuestTogether.db.profile, QuestTogether.DEFAULTS.profile)
QuestTogether:NormalizeSettingsProfile()
assert(QuestTogether:GetOption("questTrackerHideBlizzardTooltip") == false, "saved show-both choices survive defaults and normalization")
QuestTogether.db.profile.questTrackerHideBlizzardTooltip = nil
QuestTogether:NormalizeSettingsProfile()
assert(QuestTogether:GetOption("questTrackerHideBlizzardTooltip") == true, "unset tooltip choices receive the new default")
print("Party Objective Tracker tooltip visibility uses the shared setting and refreshes across profiles")

local placement = assert(QuestTogether.questTrackerTooltipPlacementDropdown)
QuestTogether:RefreshGroupsWindow()
assert(placement.Dropdown.text == "Top", "POT tooltip placement defaults to top")
assert(#placement.Dropdown.menu == 3)
for index, value in ipairs({ "top", "bottom", "side" }) do
	placement.Dropdown.menu[index].func()
	assert(QuestTogether:GetQuestTrackerTooltipPlacement() == value)
	QuestTogether:NormalizeSettingsProfile()
	assert(QuestTogether:GetQuestTrackerTooltipPlacement() == value, "saved placement survives normalization")
end
assert(QuestTogether:ValidateSetting("questTrackerTooltipPlacement", "invalid") == nil)
for _, value in ipairs({ false, "invalid" }) do
	QuestTogether.db.profile.questTrackerTooltipPlacement = value or nil
	assert(QuestTogether:GetQuestTrackerTooltipPlacement() == "top")
	QuestTogether:NormalizeSettingsProfile()
	assert(QuestTogether:GetOption("questTrackerTooltipPlacement") == "top")
end
QuestTogether:SetOption("questTrackerTooltipPlacement", "bottom")
QuestTogether:RefreshGroupsWindow()
assert(placement.Dropdown.text == "Bottom", "settings reflects Edit Mode placement changes")
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.db.profile.questTrackerTooltipPlacement = "side"
QuestTogether.groupsFrame.scripts.OnShow()
assert(placement.Dropdown.text == "Side", "placement dropdown follows the active profile")
print("Party Objective Tracker tooltip placement validates choices and refreshes across profiles")

local audio = assert(QuestTogether.audioControls)
assert(QuestTogether.audioCategory and #audio.rows == 8)
local audioWasEnabled = QuestTogether.isEnabled
QuestTogether.isEnabled = true
local supportsAudioVolume, previewAudioCue = QuestTogether.SupportsAudioVolume, QuestTogether.PreviewAudioCue
QuestTogether.SupportsAudioVolume = function() return true end
local previewed
QuestTogether.PreviewAudioCue = function(_, key) previewed = key end
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.audioFrame.scripts.OnShow()
assert(audio.master:GetChecked() and not audio.muteCombat:GetChecked())
assert(audio.volume.Slider.value == 50 and audio.volume.RightText.text == "50%")
assert(audio.interval.Slider.value == 0.75 and audio.interval.RightText.text == "0.75 sec")
for _, row in ipairs(audio.rows) do
	assert(row.enabled:GetChecked() == (row.cue.key == "attention" or row.cue.key == "focus"))
	assert(row.preview:IsEnabled() and row.volume.Slider:IsEnabled() and row.sound.Dropdown:IsEnabled(),
		"disabled events remain configurable and can be previewed")
	assert(#row.sound.Dropdown.menu == #QuestTogether:GetAudioSoundOptions())
end
local row = audio.rows[#audio.rows]
row.enabled:SetChecked(false)
row.enabled.scripts.OnClick(row.enabled)
row.volume.Slider:SetValue(35)
assert(QuestTogether:GetAudioVolume(row.cue.volumeKey) == 35)
row.sound.Dropdown.menu[2].func()
assert(QuestTogether:GetAudioSound(row.cue.key) == QuestTogether:GetAudioSoundOptions()[2].value)
row.preview.scripts.OnClick()
assert(previewed == row.cue.key)
QuestTogether.isEnabled = false
QuestTogether:RefreshOptionsWindow()
assert(not row.preview:IsEnabled(), "disabling QuestTogether disables Audio previews")
QuestTogether.isEnabled = true
QuestTogether:RefreshOptionsWindow()
assert(row.preview:IsEnabled(), "enabling QuestTogether restores Audio previews")
audio.master:SetChecked(false)
audio.master.scripts.OnClick(audio.master)
assert(not row.preview:IsEnabled() and row.volume.Slider:IsEnabled())
audio.master:SetChecked(true)
audio.master.scripts.OnClick(audio.master)
audio.interval.Forward.scripts.OnClick()
assert(QuestTogether:GetOption("audioInterval") == 1 and audio.interval.RightText.text == "1.00 sec")
audio.volume.Slider:SetValue(65)
QuestTogether.SupportsAudioVolume = function() return false end
QuestTogether:RefreshAudioWindow()
assert(audio.unavailable:IsShown() and not audio.volume.Slider:IsEnabled()
	and not audio.volume.Back:IsEnabled() and not audio.volume.Forward:IsEnabled())
assert(not row.volume.Slider:IsEnabled() and not row.preview:IsEnabled(), "unavailable playback disables preview and volume controls")
audio.volume.Slider:SetValue(25)
assert(QuestTogether:GetAudioVolume("audioVolume") == 65, "unavailable volume controls cannot persist changes")
QuestTogether.SupportsAudioVolume = function() return true end
QuestTogether:RefreshAudioWindow()
assert(audio.volume.Slider.value == 65 and not audio.unavailable:IsShown())
QuestTogether:SetOption("windowScale", 120)
audio.reset.scripts.OnClick()
assert(QuestTogether:GetOption("windowScale") == 120, "audio reset leaves other settings alone")
assert(audio.volume.Slider.value == 50 and audio.interval.Slider.value == 0.75)
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
QuestTogether.db.profile.audioEnabled = false
QuestTogether.db.profile.audioVolume = 80
QuestTogether.db.profile[row.cue.volumeKey] = 45
QuestTogether.audioFrame.scripts.OnShow()
assert(not audio.master:GetChecked() and audio.volume.Slider.value == 80 and row.volume.Slider.value == 45)
assert(not row.preview:IsEnabled(), "audio controls follow the active profile")
assert(audio.content:GetHeight() > audio.scroll:GetHeight(), "all cue controls remain in scrollable settings content")
QuestTogether.SupportsAudioVolume, QuestTogether.PreviewAudioCue = supportsAudioVolume, previewAudioCue
QuestTogether.isEnabled = audioWasEnabled
print("Audio settings use native controls, respect volume support and master previews, and preserve unrelated preferences")

-- Exercise actual owned preview constructors and their refresh path. No native
-- nameplate templates, live unit frames, or shared client tables are involved.
local originalCVar, originalRegional, originalLevel = QuestTogether.API.GetCVar,
	QuestTogether.API.RegionalUniqueNamesEnabled, QuestTogether.API.UnitLevel
local previewProfile = QuestTogether.db.profile
QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
local foreverPreview, previewCVarReads = true, 0
local thinStyle = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Thin or 1
local modernStyle = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Modern or 0
local previewCVars = {
	nameplateStyle = thinStyle,
	nameplateSize = 2,
	nameplateInfoDisplay = 3,
	nameplateShowOnlyNameForFriendlyPlayerUnits = 0,
}
QuestTogether.API.GetCVar = function(key)
	previewCVarReads = previewCVarReads + 1
	if previewCVars[key] ~= nil then return tostring(previewCVars[key]) end
	return originalCVar and originalCVar(key)
end
QuestTogether.API.RegionalUniqueNamesEnabled = function() return foreverPreview end
QuestTogether.API.UnitLevel = function(unit) assert(unit == "player"); return 31 end
local playerPreview, questPreview = QuestTogether.playerPlateControls, QuestTogether.questPlateControls
local playerSettings, questSettings = QuestTogether.playerPlatesFrame, QuestTogether.questPlatesFrame
assert(playerPreview and questPreview and playerSettings and questSettings)
local namesOnlyNotice = assert(playerPreview.namesOnlyNotice)
assert(not questPreview.namesOnlyNotice, "the names-only explanation belongs only on Player Plates")
local function RefreshPlatePreviews()
	QuestTogether:RefreshQuestPlatesWindow(false)
	QuestTogether:RefreshQuestPlatesWindow(true)
end
local function LatestPoint(region)
	assert(region.points and #region.points > 0, "preview region must have an anchor")
	return region.points[#region.points]
end
local function SamePoint(first, second)
	for index = 1, 5 do assert(first[index] == second[index], "left and prefix must share the same name-only anchor") end
end
local function AssertCenteredAboveHealth(controls)
	local unit, name = controls.previewUnitFrame, controls.previewUnitFrame.name
	assert(name:GetJustifyH() == "CENTER", "Forever names above the bar must be centered")
	assert(name:GetWidth() <= unit.HealthBarsContainer:GetWidth(),
		"the name region must not extend over the level badge")
	local point = LatestPoint(name)
	assert(point[2] == unit.HealthBarsContainer, "name anchoring must not include the level badge")
	assert((point[1] == "BOTTOM" and point[3] == "TOP")
		or (point[1] == "BOTTOMLEFT" and point[3] == "TOPLEFT"))
	assert(point[4] == 0)
end
for _, frame in ipairs({ playerSettings, questSettings }) do
	frame:Show()
	assert(frame.scripts.OnShow and frame.scripts.OnHide and frame.scripts.OnEvent)
	frame.scripts.OnShow(frame)
	assert(frame.events and frame.events.CVAR_UPDATE, "visible preview pages must react to native nameplate settings")
end
assert(not namesOnlyNotice:IsShown(), "the note must stay hidden while friendly health bars are enabled")
local normalContentHeight = playerPreview.content:GetHeight()
local normalTooltipY = LatestPoint(playerPreview.playerTooltipHeader)[5]
for _, controls in ipairs({ playerPreview, questPreview }) do
	local unit = controls.previewUnitFrame
	local badge = assert(unit.PlayerLevelDiffFrame, "both Forever previews need the native level badge")
	assert(controls.previewIconFrame.parent == unit
		and controls.previewIconFrame:GetEffectiveScale() == unit:GetEffectiveScale(),
		"the preview logo and native artwork must share one uniform scale")
	AssertCenteredAboveHealth(controls)
	assert(unit.healthBar:IsVisible() and badge:IsVisible() and unit.name:IsVisible())
	assert(badge.playerLevelDiffIcon.atlas == "ui-hud-nameplates-levelindicator")
	assert(tostring(badge.playerLevelDiffText.text) == "31", "badge must show the guarded sample player level")
	assert(badge.playerLevelDiffText.fontObject == "SystemFont_NamePlateLevel")
	assert(unit.name.fontObject == "SystemFont_NamePlate_Outlined")
	assert(#badge.points == 2)
	for index, anchor in ipairs({ { "TOPLEFT", "TOPRIGHT", 3 }, { "BOTTOMLEFT", "BOTTOMRIGHT", -2 } }) do
		local point = badge.points[index]
		assert(point[1] == anchor[1] and point[2] == unit.healthBar and point[3] == anchor[2])
		assert(point[4] == 5 and point[5] == anchor[3], "badge should use native health-bar offsets")
	end
end
QuestTogether.API.UnitLevel = function() return 35 end
for _, frame in ipairs({ playerSettings, questSettings }) do
	assert(frame.events.PLAYER_LEVEL_UP, "visible previews must refresh their level sample")
	frame.scripts.OnEvent(frame, "PLAYER_LEVEL_UP", 35)
end
for _, controls in ipairs({ playerPreview, questPreview }) do
	assert(tostring(controls.previewUnitFrame.PlayerLevelDiffFrame.playerLevelDiffText.text) == "35")
end
QuestTogether.API.UnitLevel = function() return nil end
RefreshPlatePreviews()
for _, controls in ipairs({ playerPreview, questPreview }) do
	local levelText = controls.previewUnitFrame.PlayerLevelDiffFrame.playerLevelDiffText.text
	assert(tonumber(levelText) and tonumber(levelText) > 0, "unavailable native levels need a readable preview sample")
end
QuestTogether.API.UnitLevel = function() return 31 end
QuestTogether.db.profile.nameplatePlayerIconStyle = "right"
QuestTogether.db.profile.nameplateQuestIconStyle = "right"
RefreshPlatePreviews()
for _, controls in ipairs({ playerPreview, questPreview }) do
	assert(LatestPoint(controls.previewIconFrame)[2] == controls.previewUnitFrame.PlayerLevelDiffFrame,
		"normal right-position icons must clear the level badge")
end

previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 1
playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "nameplateShowOnlyNameForFriendlyPlayerUnits", "1")
questSettings.scripts.OnEvent(questSettings, "CVAR_UPDATE", "nameplateShowOnlyNameForFriendlyPlayerUnits", "1")
local playerUnit, questUnit = playerPreview.previewUnitFrame, questPreview.previewUnitFrame
assert(playerUnit.showOnlyName == true and not playerUnit.healthBar:IsVisible()
	and not playerUnit.PlayerLevelDiffFrame:IsVisible() and playerUnit.name:IsVisible())
assert(not playerUnit.questPreviewHealthText:IsVisible(), "name-only mode must hide health values too")
assert(questUnit.showOnlyName ~= true and questUnit.healthBar:IsVisible()
	and questUnit.PlayerLevelDiffFrame:IsVisible(), "friendly-player name-only settings must not alter quest mobs")
assert(namesOnlyNotice:IsVisible() and playerPreview.content:GetHeight() > normalContentHeight,
	"names-only mode must reveal its explanation and extend the scrollable content")
assert(LatestPoint(playerPreview.playerTooltipHeader)[5] < normalTooltipY)
local noteHeight, contentHeight = namesOnlyNotice:GetHeight(), playerPreview.content:GetHeight()
local bodyHeight = namesOnlyNotice.body:GetStringHeight()
namesOnlyNotice.body.GetStringHeight = function() return bodyHeight + 48 end
QuestTogether:RefreshQuestPlatesWindow(true)
assert(namesOnlyNotice:GetHeight() == noteHeight + 48 and playerPreview.content:GetHeight() == contentHeight + 48,
	"wrapped translations must grow the note and move following controls out of the way")
namesOnlyNotice.body.GetStringHeight = nil
local savedOpenNameplates, opens = QuestTogether.API.OpenNativeFriendlyNameplateSettings, 0
QuestTogether.API.OpenNativeFriendlyNameplateSettings = function() opens = opens + 1; return true end
namesOnlyNotice.settingsButton.scripts.OnClick()
assert(opens == 1 and previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits == 1,
	"the note's button opens native settings without changing the player's names-only choice")
local nameOnlyLeft
for _, style in ipairs({ "left", "right", "top", "prefix" }) do
	QuestTogether.db.profile.nameplatePlayerIconStyle = style
	QuestTogether:RefreshQuestPlatesWindow(true)
	local point = LatestPoint(playerPreview.previewIconFrame)
	assert(point[2] == playerUnit.name, "every name-only position must use the same live name-layout path")
	assert(point[1] == (style == "right" and "LEFT" or style == "top" and "BOTTOM" or "RIGHT"))
	assert(QuestTogether:GetNameplatePlayerIconStyle() == style, "preview refresh must preserve the chosen setting")
	if style == "left" then nameOnlyLeft = point elseif style == "prefix" then SamePoint(nameOnlyLeft, point) end
end
previewCVars.nameplateStyle = modernStyle
playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "nameplateStyle", tostring(modernStyle))
assert(playerUnit.name:GetJustifyH() == "CENTER" and not playerUnit.healthBar:IsVisible())
previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 0
local prepareHide = QuestTogether.PrepareGamepadControlHide
QuestTogether.PrepareGamepadControlHide = function(_, control, fallback)
	assert(control == namesOnlyNotice and fallback == playerPreview.nameplatePlayerIconEnabled)
	return false
end
playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "nameplateShowOnlyNameForFriendlyPlayerUnits", "0")
assert(namesOnlyNotice:IsShown(), "a selected controller control must not disappear before safe focus handoff")
QuestTogether.PrepareGamepadControlHide = prepareHide
playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "nameplateShowOnlyNameForFriendlyPlayerUnits", "0")
assert(not namesOnlyNotice:IsShown() and playerPreview.content:GetHeight() == normalContentHeight
	and LatestPoint(playerPreview.playerTooltipHeader)[5] == normalTooltipY,
	"disabling names-only must remove the note and restore the compact layout")
namesOnlyNotice.settingsButton.scripts.OnClick()
assert(opens == 1, "a hidden settings link must not dispatch a stale click")
QuestTogether.API.OpenNativeFriendlyNameplateSettings = savedOpenNameplates
assert(playerUnit.healthBar:IsVisible() and playerUnit.PlayerLevelDiffFrame:IsVisible())
assert(playerUnit.name:GetJustifyH() == "LEFT", "Modern keeps Blizzard's normal inside-bar name layout")
previewCVars.nameplateInfoDisplay = 0
playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "nameplateInfoDisplay", "0")
local nameWithoutHealthText = playerUnit.name:GetWidth()
assert(not playerUnit.questPreviewHealthText:IsVisible())
previewCVars.nameplateInfoDisplay = 3
playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "nameplateInfoDisplay", "3")
assert(playerUnit.questPreviewHealthText:IsVisible() and playerUnit.name:GetWidth() < nameWithoutHealthText,
	"inside-bar names reserve space only for visible native health text")
assert(playerUnit.questPreviewHealthText.fontObject == "SystemFont_NamePlate_Outlined")
QuestTogether.db.profile.nameplatePlayerIconStyle = "right"
QuestTogether:RefreshQuestPlatesWindow(true)
assert(LatestPoint(playerPreview.previewIconFrame)[2] == playerUnit.PlayerLevelDiffFrame)

-- Older saved styles can still select Classic even though Forever's current
-- style selector omits it. Its fixed border and bar offsets must also retire.
previewCVars.nameplateStyle = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Classic or 6
RefreshPlatePreviews()
for _, controls in ipairs({ playerPreview, questPreview }) do
	local unit = controls.previewUnitFrame
	AssertCenteredAboveHealth(controls)
	assert(unit.questPreviewHealthBackground.texture == "Interface\\Tooltips\\Nameplate-Border")
	assert(unit.questPreviewHealthBackground.texCoord[3] == 0.5
		and unit.questPreviewHealthBackground.texCoord[4] == 1)
	assert(unit.questPreviewHealthBackground.drawLayer == "ARTWORK")
	assert(unit.questPreviewBaseFillTexture.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
	assert(unit.questPreviewClassicLevel:IsVisible() and not unit.questPreviewDeselectedOverlay:IsVisible())
	assert(not unit.healthBar.allPoints and #unit.healthBar.points == 2)
	assert(unit.healthBar.points[1][4] == 3.5 and unit.healthBar.points[2][4] == -20.75,
		"Classic preview health must fit its fixed native border")
end
previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 1
RefreshPlatePreviews()
assert(playerUnit.name:IsVisible() and not playerUnit.questPreviewHealthBackground:IsVisible()
	and not playerUnit.questPreviewBaseFillTexture:IsVisible() and not playerUnit.questPreviewClassicLevel:IsVisible()
	and not playerUnit.PlayerLevelDiffFrame:IsVisible(), "names-only must hide every Classic health decoration")
assert(questUnit.questPreviewHealthBackground:IsVisible() and questUnit.questPreviewClassicLevel:IsVisible()
	and questUnit.PlayerLevelDiffFrame:IsVisible(), "names-only must leave Classic quest preview artwork alone")
previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 0
previewCVars.nameplateStyle = thinStyle
RefreshPlatePreviews()
for _, controls in ipairs({ playerPreview, questPreview }) do
	local unit = controls.previewUnitFrame
	AssertCenteredAboveHealth(controls)
	assert(unit.questPreviewHealthBackground.atlas == "UI-HUD-CoolDownManager-Bar-BG"
		and unit.questPreviewHealthBackground.texCoord[3] == 0
		and unit.questPreviewHealthBackground.drawLayer == "BACKGROUND")
	assert(unit.questPreviewBaseFillTexture.atlas == (QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS or "UI-HUD-CoolDownManager-Bar"))
	assert(not unit.questPreviewClassicLevel:IsVisible() and unit.questPreviewDeselectedOverlay:IsVisible())
	assert(unit.healthBar.allPoints == unit.HealthBarsContainer and #unit.healthBar.points == 0,
		"returning from Classic must clear its health-bar offsets")
end
local readsBeforeUnrelated = previewCVarReads
playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "Sound_EnableAllSound", "0")
assert(previewCVarReads == readsBeforeUnrelated, "unrelated CVar notifications must not rebuild the preview")

playerSettings.scripts.OnHide(playerSettings)
playerSettings:Hide()
assert(not playerSettings.events.CVAR_UPDATE and not playerSettings.events.PLAYER_LEVEL_UP,
	"hidden preview pages must stop listening to native updates")
previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 1
local readsBeforeHidden = previewCVarReads
playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "nameplateShowOnlyNameForFriendlyPlayerUnits", "1")
playerSettings.scripts.OnEvent(playerSettings, "PLAYER_LEVEL_UP", 36)
assert(previewCVarReads == readsBeforeHidden and playerUnit.showOnlyName ~= true,
	"late notifications after hiding must not update retired previews")
playerSettings:Show()
playerSettings.scripts.OnShow(playerSettings)
assert(playerSettings.events.CVAR_UPDATE and playerUnit.showOnlyName
	and not playerUnit.healthBar:IsVisible(), "reopening must read the current native setting")
assert(namesOnlyNotice:IsShown(), "reopening Player Plates must restore the note for changes made in Blizzard settings")
previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 0
previewCVars.nameplateStyle = thinStyle
foreverPreview = false
do
	-- Audited Retail 12.1.5 (70783), client-source commit 297d7aaaa736:
	-- NamePlateConstants, Driver:GetNamePlateScale/UpdateNamePlateOptions, and
	-- UnitFrame:ApplyFrameOptions/UpdateAnchors. These checks exercise the owned
	-- preview constructor; they never run native nameplate mixins on fake units.
	local scales = { { 0.75, 0.8 }, { 1, 1 }, { 1.25, 1.25 }, { 1.4, 1.4 }, { 1.6, 1.6 } }
	local function Near(actual, expected, context)
		assert(math.abs(actual - expected) < 0.00001, context .. ": expected " .. expected .. ", got " .. actual)
	end
	local function HasAnchor(region, point, relative, relativePoint, x, y)
		for _, anchor in ipairs(region.points or {}) do
			if anchor[1] == point and anchor[2] == relative and anchor[3] == relativePoint
				and math.abs(anchor[4] - x) < 0.00001 and math.abs(anchor[5] - y) < 0.00001 then return true end
		end
		return false
	end
	local savedClassColor = QuestTogether.API.GetPlayerNameplatePreviewClassColor
	QuestTogether.API.GetPlayerNameplatePreviewClassColor = function() return 0.25, 0.5, 0.75 end
	previewCVars.nameplateShowFriendlyClassColor = 0
	previewCVars.nameplateUseClassColorForFriendlyPlayerUnitNames = 0
	QuestTogether.db.profile.nameplatePlayerIconStyle = "right"
	QuestTogether.db.profile.nameplateQuestIconStyle = "right"
	-- Include a final Modern pass so stale Classic artwork is exercised too.
	for _, style in ipairs({ 0, 1, 2, 3, 4, 5, 6, 0 }) do
		local classic, inside, large = style == 6, style == 0 or style == 2, style == 0 or style == 2 or style == 3
		previewCVars.nameplateStyle = style
		for size, scale in ipairs(scales) do
			local horizontal, vertical = classic and size == 1 and 0.8 or scale[1], scale[2]
			previewCVars.nameplateSize, previewCVars.nameplateInfoDisplay = size, 0
			RefreshPlatePreviews()
			for _, controls in ipairs({ playerPreview, questPreview }) do
				local unit = controls.previewUnitFrame
				local label = "Retail style " .. style .. ", size " .. size
				Near(unit.HealthBarsContainer:GetWidth(), ((classic and 152 or 230) - 24) * horizontal, label .. " bar width")
				Near(unit.HealthBarsContainer:GetHeight(), (large and 20 or 10) * vertical, label .. " bar height")
				Near(unit.name.fontHeight, (classic and 10 or 12) * vertical, label .. " name font size")
				Near(unit.questPreviewHealthText.fontHeight, (classic and 10 or 12) * vertical, label .. " health font size")
				assert(unit.name.wordWrap == false and unit.questPreviewHealthText.wordWrap == false,
					label .. " constrained native text rows must remain single-line")
				assert(unit.name.fontObject == (inside and "SystemFont_NamePlate_Outlined" or "SystemFont_NamePlate"),
					label .. " must use Retail's name font, with outlines only inside bars")
				assert(unit.questPreviewHealthText.fontObject == ((inside or classic) and "SystemFont_NamePlate_Outlined" or "SystemFont_NamePlate"),
					label .. " must use the health-text font for its own row")
				assert(unit.name:GetJustifyH() == (classic and "CENTER" or "LEFT"), label .. " name justification")
				assert(HasAnchor(unit.name, inside and "LEFT" or classic and "BOTTOM" or "BOTTOMLEFT",
					unit.HealthBarsContainer, inside and "LEFT" or classic and "TOP" or "TOPLEFT",
					classic and 0 or 4, inside and 0 or (classic and 4 or 2) * vertical), label .. " name anchor")
				assert(HasAnchor(unit.questPreviewHealthText, (inside or classic) and "RIGHT" or "BOTTOMRIGHT",
					unit.healthBar, (inside or classic) and "RIGHT" or "TOPRIGHT", -4, classic and -0.5 or inside and 0 or 2),
					label .. " health text must match the native inside/above row")
				assert(unit.healthBar:IsVisible() and not unit.PlayerLevelDiffFrame:IsVisible(),
					label .. " same-level samples must not inherit Forever's external level badge")
				assert(unit.questPreviewClassicLevel:IsVisible() == classic, label .. " inline level is Classic-only")
				if classic then
					assert(unit.questPreviewHealthBackground.texture == "Interface\\Tooltips\\Nameplate-Border")
					assert(unit.questPreviewHealthBackground.texCoord[3] == 0.5 and unit.questPreviewHealthBackground.texCoord[4] == 1)
					Near(unit.questPreviewHealthBackground:GetWidth(), 128 * horizontal, label .. " Classic border width")
					Near(unit.questPreviewHealthBackground:GetHeight(), 16 * vertical, label .. " Classic border height")
					assert(unit.questPreviewBaseFillTexture.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
					assert(HasAnchor(unit.healthBar, "TOPLEFT", unit.HealthBarsContainer, "TOPLEFT", 3.5 * horizontal, 0.5 * vertical))
					assert(HasAnchor(unit.healthBar, "BOTTOMRIGHT", unit.HealthBarsContainer, "BOTTOMRIGHT", -20.75 * horizontal, 0.5 * vertical))
					assert(tostring(unit.questPreviewClassicLevel.text) == "31", label .. " inline level must use the sample player level")
					Near(unit.questPreviewClassicLevel.fontHeight, 10 * vertical, label .. " level text size")
					assert(not unit.questPreviewDeselectedOverlay:IsVisible())
				else
					assert(unit.questPreviewHealthBackground.atlas == "UI-HUD-CoolDownManager-Bar-BG")
					assert(unit.questPreviewHealthBackground.texCoord[3] == 0 and unit.questPreviewHealthBackground.drawLayer == "BACKGROUND")
					assert(unit.questPreviewBaseFillTexture.atlas == "UI-HUD-CoolDownManager-Bar")
					assert(unit.healthBar.allPoints == unit.HealthBarsContainer and #unit.healthBar.points == 0)
					assert(unit.questPreviewDeselectedOverlay:IsVisible())
				end
				assert(LatestPoint(controls.previewIconFrame)[2] == unit.healthBar,
					label .. " right-position QT icons must use the actual Retail bar")
			end
		end
		previewCVars.nameplateSize, previewCVars.nameplateInfoDisplay = 2, 0
		RefreshPlatePreviews()
		local emptyNameWidths = { playerUnit.name:GetWidth(), questUnit.name:GetWidth() }
		-- CVar indexes 1/2 map to mask bits 1/2; bit 4 is rarity only.
		for _, mask in ipairs({ 1, 2, 3, 4, 0 }) do
			previewCVars.nameplateInfoDisplay = mask
			RefreshPlatePreviews()
			for index, unit in ipairs({ playerUnit, questUnit }) do
				local text, shown = unit.questPreviewHealthText, mask > 0 and mask < 4
				assert(text:IsVisible() == shown, "Retail health display must honor only the health mask bits")
				if shown then
					assert((text.text:find("%%") ~= nil) == (mask == 1 or mask == 3), "percent must match its CVar bit")
					assert((text.text:find("241", 1, true) ~= nil) == (mask == 2 or mask == 3), "numeric value must match its CVar bit")
				end
				if shown and not classic then
					assert(unit.name:GetWidth() < emptyNameWidths[index], "shared Retail name/health rows must reserve visible text width")
				else
					Near(unit.name:GetWidth(), emptyNameWidths[index], "hidden health text or a separate Classic row must not consume name width")
				end
			end
		end
		previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 1
		RefreshPlatePreviews()
		assert(playerUnit.name:IsVisible() and playerUnit.name:GetJustifyH() == "CENTER" and namesOnlyNotice:IsVisible())
		assert(not playerUnit.healthBar:IsVisible() and not playerUnit.PlayerLevelDiffFrame:IsVisible()
			and not playerUnit.questPreviewClassicLevel:IsVisible() and not playerUnit.questPreviewHealthText:IsVisible(),
			"Retail names-only must retire all player health/level decorations")
		assert(questUnit.healthBar:IsVisible() and not questUnit.showOnlyName and questUnit.questPreviewClassicLevel:IsVisible() == classic,
			"Retail friendly names-only must not change Quest Plates")
		local left
		for _, position in ipairs({ "left", "right", "top", "prefix" }) do
			QuestTogether.db.profile.nameplatePlayerIconStyle = position
			QuestTogether:RefreshQuestPlatesWindow(true)
			local anchor = LatestPoint(playerPreview.previewIconFrame)
			assert(anchor[2] == playerUnit.name, "Retail names-only icon positions must use the rendered name")
			assert(anchor[1] == (position == "right" and "LEFT" or position == "top" and "BOTTOM" or "RIGHT"))
			if position == "left" then left = anchor elseif position == "prefix" then SamePoint(left, anchor) end
		end
		QuestTogether.db.profile.nameplatePlayerIconStyle = "right"
		previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 0
		RefreshPlatePreviews()
		assert(not namesOnlyNotice:IsShown() and playerUnit.healthBar:IsVisible())
	end
	local function ColorMatches(actual, expected, label)
		assert(actual, label .. " color must be set")
		for index = 1, 3 do Near(actual[index], expected[index], label) end
	end
	previewCVars.nameplateStyle = thinStyle
	RefreshPlatePreviews()
	local questNameColor, questBarColor = questUnit.name.textColor, questUnit.questPreviewBaseFillTexture.vertexColor
	local classColor, friendlyColor, white = { 0.25, 0.5, 0.75 }, { 0.22, 0.80, 0.22 }, { 1, 1, 1 }
	ColorMatches(playerUnit.name.textColor, white, "ordinary Retail player name")
	ColorMatches(playerUnit.questPreviewBaseFillTexture.vertexColor, friendlyColor, "ordinary Retail friendly health")
	previewCVars.nameplateShowFriendlyClassColor = 1
	playerSettings.scripts.OnEvent(playerSettings, "CVAR_UPDATE", "nameplateShowFriendlyClassColor", "1")
	ColorMatches(playerUnit.questPreviewBaseFillTexture.vertexColor, classColor, "Retail friendly class-colored health")
	ColorMatches(playerUnit.name.textColor, white, "health coloring must not enable class-colored names")
	previewCVars.nameplateShowFriendlyClassColor = 0
	previewCVars.nameplateUseClassColorForFriendlyPlayerUnitNames = 1
	RefreshPlatePreviews()
	ColorMatches(playerUnit.name.textColor, classColor, "Retail friendly class-colored name")
	ColorMatches(playerUnit.questPreviewBaseFillTexture.vertexColor, friendlyColor, "name coloring must not enable class-colored health")
	ColorMatches(questUnit.name.textColor, questNameColor, "friendly name coloring must not alter quest mobs")
	ColorMatches(questUnit.questPreviewBaseFillTexture.vertexColor, questBarColor, "friendly health coloring must not alter quest tint")
	previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 1
	RefreshPlatePreviews()
	assert(playerUnit.name:IsVisible() and not playerUnit.healthBar:IsVisible())
	ColorMatches(playerUnit.name.textColor, classColor, "names-only must retain its chosen class color")
	QuestTogether.API.GetPlayerNameplatePreviewClassColor = function() return nil end
	previewCVars.nameplateShowOnlyNameForFriendlyPlayerUnits = 0
	previewCVars.nameplateShowFriendlyClassColor = 1
	RefreshPlatePreviews()
	ColorMatches(playerUnit.name.textColor, white, "unavailable class data must restore the normal name color")
	ColorMatches(playerUnit.questPreviewBaseFillTexture.vertexColor, friendlyColor, "unavailable class data must restore friendly health")
	QuestTogether.API.GetPlayerNameplatePreviewClassColor = function() return 0.25, 0.5, 0.75 end
	previewCVars.nameplateShowFriendlyClassColor = 0
	previewCVars.nameplateUseClassColorForFriendlyPlayerUnitNames = 0
	previewCVars.nameplateStyle = 5
	RefreshPlatePreviews()
	ColorMatches(playerUnit.name.textColor, friendlyColor, "Legacy restores native friendly reaction name coloring")
	ColorMatches(questUnit.name.textColor, { 1, 0, 0 }, "Legacy restores native hostile reaction name coloring")
	QuestTogether.API.GetPlayerNameplatePreviewClassColor = savedClassColor
end
QuestTogether.API.GetCVar, QuestTogether.API.RegionalUniqueNamesEnabled, QuestTogether.API.UnitLevel =
	originalCVar, originalRegional, originalLevel
QuestTogether.db.profile = previewProfile
RefreshPlatePreviews()
print("Forever and Retail player/quest previews match native style, size, fonts, level artwork, health text, names-only positions and CVar lifecycle")
