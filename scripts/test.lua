-- Offline WoW test environment. Never load this script from the addon TOC.
-- Run from the repository root: lua scripts/test.lua
local addonRoot = arg[1] or "."
QuestTogether = nil
QuestTogetherDB = nil
issecretvalue = function()
	return false
end
canaccessvalue = function()
	return true
end
canaccesstable = function()
	return true
end
wipe = function(value)
	for key in pairs(value) do
		value[key] = nil
	end
	return value
end
strsplit = function(delimiter, value)
	if delimiter == "-" then
		local first, second = string.match(value or "", "^([^-]*)%-?(.*)$")
		return first, second ~= "" and second or nil
	end
	return value
end
Ambiguate = function(name)
	return (string.match(name or "", "^([^-]+)")) or name
end
UnitExists = function()
	return false
end
UnitGUID = function()
	return nil
end
UnitFullName = function(unit)
	if unit == "player" then
		return "MyPlayer", "Realm"
	end
	return nil, nil
end
UnitName = function(unit)
	if unit == "player" then
		return "MyPlayer"
	end
	return nil
end
UnitIsUnit = function()
	return false
end
GetRealmName = function()
	return "Realm"
end
GetTime = function()
	return 100
end
InCombatLockdown = function()
	return false
end
IsInInstance = function()
	return false, "none"
end
GetInstanceInfo = function()
	return nil, "none"
end
C_Timer = {
	After = function(_, callback)
		callback()
	end,
}
C_NamePlate = {}
C_RestrictedActions = {}
Enum = {
	AddOnRestrictionType = {},
	QuestClassification = { Legendary = 1, Recurring = 2, Important = 3, Meta = 4, Campaign = 5, Calling = 6 },
	QuestTagType = { Dungeon = 6 },
	TooltipDataLineType = { QuestTitle = 1, QuestObjective = 2 },
}
THREAT_TOOLTIP = "Threat"
LinkProcessorResponse = { Handled = true }
local Frame = {}
Frame.__index = Frame
function Frame:SetScript() end
function Frame:RegisterEvent() end
function Frame:UnregisterEvent() end
function Frame:IsShown()
	return false
end
function Frame:IsForbidden()
	return false
end
function Frame:IsProtected()
	return false, false
end
CreateFrame = function()
	return setmetatable({}, Frame)
end
UIParent = setmetatable({}, Frame)
for _, file in ipairs({
	"Core.lua",
	"HotPathState.lua",
	"HotPathRuntime.lua",
	"TaskArea.lua",
	"Nameplates.lua",
	"PartyState.lua",
	"Comms.lua",
	"EventHandlers.lua",
	"Options.lua",
	"Diagnostics.lua",
}) do
	local chunk, err = loadfile(addonRoot .. "/" .. file)
	assert(chunk, err)
	chunk("QuestTogether", {})
end
local testsFile = assert(io.open(addonRoot .. "/Tests.lua", "r"))
local testsSource = testsFile:read("*a")
testsFile:close()
testsSource = assert(testsSource:gsub("local function WithIsolatedState", "function WithIsolatedState", 1))
local testsChunk, testsErr = (loadstring or load)(testsSource, "@Tests.lua")
assert(testsChunk, testsErr)
testsChunk("QuestTogether", {})
QuestTogether:InitializeDatabase()
QuestTogether:EnsureRuntimeStateStore()
QuestTogether.isInitialized = true
for _, file in ipairs({
	"regression_runtime",
	"regression_core_state",
	"regression_quest_state",
	"regression_nameplates",
	"regression_comms",
}) do
	local path = addonRoot .. "/scripts/" .. file .. ".lua"
	local probe = io.open(path, "r")
	if probe then
		probe:close()
		assert(loadfile(path))()
	end
end
-- Reverse order helps expose state leaking between otherwise independent tests.
if arg[2] == "reverse" then
	local cases = QuestTogether.tests
	for index = 1, math.floor(#cases / 2) do
		cases[index], cases[#cases - index + 1] = cases[#cases - index + 1], cases[index]
	end
end
local passed, failed = 0, 0
for _, testCase in ipairs(QuestTogether.tests) do
	local ok, err = pcall(function()
		WithIsolatedState(testCase.fn)
	end)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("[FAIL] " .. testCase.name .. " -> " .. tostring(err))
	end
end
print("registered=" .. tostring(#QuestTogether.tests))
print("Test summary: " .. passed .. " passed, " .. failed .. " failed.")
os.exit(failed == 0 and 0 or 1)
