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
local function Region(kind)
	local f = setmetatable({ kind = kind, scripts = {}, value = 0 }, { __index = methods })
	regions[#regions + 1] = f
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
function methods:SetChecked(v)
	self.checked = v
end
function methods:GetChecked()
	return self.checked
end
function methods:SetValue(v)
	self.value = v
	if self.scripts.OnValueChanged then
		self.scripts.OnValueChanged(self, v)
	end
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
	"SetScrollChild",
	"SetOrientation",
	"SetObeyStepOnDrag",
	"SetColorTexture",
	"SetTexture",
	"SetThumbTexture",
}) do
	methods[key] = function() end
end
function methods:SetWidth(width) self.width = width end
function methods:GetWidth() return self.width end
function methods:Hide() self.hidden = true end
function methods:Show() self.hidden = false end
function methods:SetShown(shown) self.hidden = not shown end
function methods:GetText() return self.text end
function methods:GetStringHeight() return 16 end
function methods:GetFont() return "font", 12, "" end
function methods:GetFrameStrata() return "LOW" end
function methods:GetFrameLevel() return 0 end
function methods:IsVisible() return not self.hidden end
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
CreateFrame = function(kind, _, _, template)
	local frame = Region(kind)
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
	end
	return frame
end
AnchorUtil = { CreateAnchor = function(...) return { ... } end }
Settings = {
	RegisterCanvasLayoutSubcategory = function(_, _, name)
		return { name = name }
	end,
	RegisterAddOnCategory = function() end,
}
QuestTogether:InitializeDatabase()
QuestTogether:InitializeAccessibilityWindow({})
QuestTogether:InitializePlayerLocationsWindow({})
QuestTogether:InitializeDeveloperWindow({})
assert(QuestTogether.accessibilityFrame and QuestTogether.playerLocationsFrame)
QuestTogether.accessibilityFrame.scripts.OnShow()
local slider
for _, f in ipairs(regions) do
	if f.kind == "Slider" then
		slider = f
	end
end
assert(slider and slider.minimum == 80 and slider.maximum == 150)
local range = QuestTogether:GetOption("nearbyAnnouncementRange")
slider:SetValue(125)
assert(QuestTogether:GetOption("windowScale") == 125)
assert(QuestTogether:GetOption("nearbyAnnouncementRange") == range)
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
assert(#menu == 5)
for _, case in ipairs({
	{ 5, "None", false, false, false, false },
	{ 4, "Party only", true, true, false, false },
	{ 2, "Players looking for questing partners + my party", true, false, true, true },
	{ 3, "Players looking for questing partners", true, false, true, false },
	{ 1, "All QuestTogether players", true, false, false, false },
}) do
	filter.Dropdown.menu[case[1]].func()
	assert(filter.Dropdown.text == case[2] and filter.Dropdown.menu[case[1]].selected())
	assert(QuestTogether:GetOption("showPlayerLocations") == case[3])
	assert(QuestTogether:GetOption("mapPartyOnly") == case[4])
	assert(QuestTogether:GetOption("onlyShowQuestPartners") == case[5])
	assert(QuestTogether:GetOption("mapAlwaysShowParty") == case[6])
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
QuestTogether:SetOption("mapAlwaysShowParty", true)
QuestTogether:RefreshPlayerLocationsWindow()
assert(filter.Dropdown.menu[2].selected())
QuestTogether:SetOption("showPlayerLocations", false)
QuestTogether:RefreshPlayerLocationsWindow()
assert(filter.Dropdown.text == "None" and filter.Dropdown.menu[5].selected())
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
