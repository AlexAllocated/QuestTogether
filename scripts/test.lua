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
local clientChecks = arg[3] and assert(loadfile(addonRoot .. "/scripts/client_profiles.lua"))()(arg[3])
local namespace = {}
for _, file in ipairs({
	"Libs/libchev/libchev.lua",
	"Libs/libchev/Debug.lua",
	"Libs/libchev/DebugWindow.lua",
	"Libs/libchev/ReportWindow.lua",
	"Libs/libchev/SelfTests.lua",
	"Core.lua",
	"Debug.lua",
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
	chunk("QuestTogether", namespace)
end
local testsChunk, testsErr = loadfile(addonRoot .. "/Tests.lua")
assert(testsChunk, testsErr)
testsChunk("QuestTogether", namespace)
QuestTogether:InitializeDatabase()
QuestTogether:EnsureRuntimeStateStore()
QuestTogether.isInitialized = true
if clientChecks then
	clientChecks(QuestTogether)
	os.exit(0)
end
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
-- Exercise the same controller and QT-owned isolation used by the live command.
local success, passed, failed, result = QuestTogether:RunTests(arg[2] == "reverse", false)
assert(result, "Shared debug controller did not return a test result")
-- The shared headless runner already prints failures and the summary through
-- QT's console adapter; avoid duplicating its presentation here.
print("registered=" .. tostring(result.total))
os.exit(success and 0 or 1)
