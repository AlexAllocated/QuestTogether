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
UnitGUID = function(unit)
	-- A real client can have a player on the token used by creature fixtures.
	-- Keep that collision present so missing fixture overrides fail offline too.
	if unit == "nameplate9" then
		return "Player-0-OFFLINE-NEARBY"
	end
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
-- A client timer never executes inside C_Timer.After. Live-safe fixtures use
-- their own controllable clocks; accidental engine timers remain queued here.
local engineTimers = {}
C_Timer = {
	After = function(delay, callback)
		engineTimers[#engineTimers + 1] = { delay = delay, callback = callback }
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
-- Match the pure Lua formatter in the installed Retail/Forever LinkUtil.lua.
-- Keeping it available offline exercises real hyperlink display boundaries.
LinkUtil = {
	FormatLink = function(linkType, displayText, ...)
		local link = "|H" .. table.concat({ linkType, ... }, ":")
		return link .. (displayText and ("|h" .. displayText .. "|h") or "|h")
	end,
}
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
-- Load the exact live manifest. Missing/omitted test modules must not be hidden
-- by a second, independently maintained offline file list.
GetLocale = function() return os.getenv("QT_TEST_LOCALE") or "enUS" end
for line in io.lines(addonRoot .. "/QuestTogether.toc") do
	local file = line:match("^%s*(.-)%s*$")
	if file ~= "" and not file:match("^#") then
		assert(file:match("%.lua$"), "unsupported manifest entry: " .. file)
		local path = addonRoot .. "/" .. file:gsub("\\", "/")
		local chunk, err = loadfile(path)
		assert(chunk, err)
		chunk("QuestTogether", namespace)
	end
end
QuestTogether:InitializeDatabase()
QuestTogether:EnsureRuntimeStateStore()
QuestTogether.isInitialized = true
local selectedTestLocale = os.getenv("QT_TEST_LOCALE") or "enUS"
local expectedTestLocale = selectedTestLocale == "enGB" and "enUS" or selectedTestLocale
assert(QuestTogether.locale == expectedTestLocale, "client locale must survive addon initialization")
if clientChecks then
	clientChecks(QuestTogether)
	os.exit(0)
end
-- Offline-only tripwires: live tests must use their private adapters and frames.
-- Count even protected calls whose error is swallowed by production pcall.
local engineBoundaryCalls = {}
local function RejectEngineCall(name)
	return function()
		engineBoundaryCalls[#engineBoundaryCalls + 1] = name
		error("test crossed engine boundary: " .. name)
	end
end
SendChatMessage = RejectEngineCall("SendChatMessage")
GetServerTime = RejectEngineCall("GetServerTime")
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.SendChatMessage = RejectEngineCall("C_ChatInfo.SendChatMessage")
CreateFrame = RejectEngineCall("CreateFrame")
hooksecurefunc = RejectEngineCall("hooksecurefunc")
C_Timer.After = RejectEngineCall("C_Timer.After")
C_RestrictedActions.GetAddOnRestrictionState = RejectEngineCall("GetAddOnRestrictionState")
Enum.AddOnRestrictionType = { Combat = 1, Encounter = 2, ChallengeMode = 3, PvPMatch = 4, Map = 5 }
UnitIsTapDenied = RejectEngineCall("UnitIsTapDenied")
QuestieLoader = { _modules = { QuestieTooltips = { GetTooltip = RejectEngineCall("Questie.GetTooltip") } } }
C_AddOns = C_AddOns or {}
C_AddOns.LoadAddOn = RejectEngineCall("C_AddOns.LoadAddOn")
LoadAddOn = RejectEngineCall("LoadAddOn")
UIParentLoadAddOn = RejectEngineCall("UIParentLoadAddOn")
ShowUIPanel = RejectEngineCall("ShowUIPanel")
C_QuestLog = C_QuestLog or {}
C_QuestLog.GetTitleForQuestID = RejectEngineCall("C_QuestLog.GetTitleForQuestID")
C_QuestLog.RequestLoadQuestByID = RejectEngineCall("C_QuestLog.RequestLoadQuestByID")
C_SuperTrack = C_SuperTrack or {}
C_SuperTrack.IsSuperTrackingQuest = RejectEngineCall("C_SuperTrack.IsSuperTrackingQuest")
C_SuperTrack.GetSuperTrackedQuestID = RejectEngineCall("C_SuperTrack.GetSuperTrackedQuestID")
QuestLogPushQuest = RejectEngineCall("QuestLogPushQuest")
QuestMapFrame_OpenToQuestDetails = RejectEngineCall("QuestMapFrame_OpenToQuestDetails")
OpenQuestLog = RejectEngineCall("OpenQuestLog")
MenuUtil = { CreateContextMenu = RejectEngineCall("CreateContextMenu") }
-- Exercise the same controller and QT-owned isolation used by the live command.
local success, passed, failed, result = QuestTogether:RunTests(arg[2] == "reverse", false)
assert(result, "Shared debug controller did not return a test result")
assert(#engineBoundaryCalls == 0, "live-test isolation failure: " .. table.concat(engineBoundaryCalls, ", "))
-- The shared headless runner already prints failures and the summary through
-- QT's console adapter; avoid duplicating its presentation here.
print("registered=" .. tostring(result.total))
os.exit(success and 0 or 1)
