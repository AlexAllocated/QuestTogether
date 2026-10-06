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
CreateFrame = function(kind)
	return Region(kind)
end
Settings = {
	RegisterCanvasLayoutSubcategory = function(_, _, name)
		return { name = name }
	end,
	RegisterAddOnCategory = function() end,
}
QuestTogether:InitializeDatabase()
QuestTogether:InitializeAccessibilityWindow({})
QuestTogether:InitializePlayerLocationsWindow({})
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
local control = QuestTogether.playerLocationsControls.showWorldMapPlayers
control.checked = false
control.scripts.OnClick(control)
assert(QuestTogether:GetOption("showWorldMapPlayers") == false)
assert(QuestTogether:GetOption("showMinimapPlayers") == true)
assert(QuestTogether:GetOption("sharePlayerLocation") == true)
local menu = {}
function QuestTogether:CreatePartyQuestFilterMenu(owner, generate)
	local node = {}
	function node:CreateButton(label, action)
		menu[#menu + 1] = { label = label, action = action }
	end
	generate(owner, node)
end
for _, f in ipairs(regions) do
	if f.text == "All QuestTogether players" then
		f.scripts.OnClick()
	end
	if f.Label and f.Label.text == "Reduce motion" then
		f.checked = true
		f.scripts.OnClick(f)
	end
end
assert(#menu == 3)
menu[3].action()
assert(QuestTogether:GetOption("mapPartyOnly") and not QuestTogether:GetOption("onlyShowQuestPartners"))
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
