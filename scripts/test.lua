-- Offline WoW test environment. Never load this script from the addon TOC.
-- Run from the repository root: lua scripts/test.lua
local addonRoot = arg[1] or "."
-- Forever's embedded formatter narrows integer conversions to 32 bits, while
-- the host Lua builds use wider integers. Model that engine contract offline so
-- epoch milliseconds cannot pass CI and then fail during addon initialization.
local nativeFormat = string.format
string.format = function(format, ...)
	local values, argument, cursor = { ... }, 0, 1
	while type(format) == "string" do
		local start = format:find("%", cursor, true)
		if not start then
			break
		end
		if format:sub(start + 1, start + 1) == "%" then
			cursor = start + 2
		else
			local conversion, finish = format:sub(start):match("^%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs])()")
			if not conversion then
				break
			end -- The native formatter diagnoses invalid formats.
			argument = argument + 1
			cursor = start + finish - 1
			if conversion:find("[diouxX]") then
				local value = tonumber(values[argument])
				local maximum = (conversion == "d" or conversion == "i") and 2147483647 or 4294967295
				if value and (value < -2147483648 or value > maximum or value ~= value) then
					error("integer overflow in 32-bit WoW string.format", 2)
				end
			end
		end
	end
	return nativeFormat(format, ...)
end
assert(not pcall(string.format, "%d", 1791753535000), "offline formatter must reject the reported Forever overflow")
assert(string.format("%.0f", 1791753535000) == "1791753535000")
assert(string.format("%%d %s %04d", "label", 42) == "%d label 0042")
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
GetLocale = function()
	return os.getenv("QT_TEST_LOCALE") or "enUS"
end
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
-- True NaN fixtures belong only to host Lua: Forever rejects their construction
-- as division by zero. These checks remain mandatory in every offline run.
assert(loadfile(addonRoot .. "/scripts/offline_numeric_tests.lua"))()(QuestTogether)
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
C_SuperTrack.SetSuperTrackedQuestID = RejectEngineCall("C_SuperTrack.SetSuperTrackedQuestID")
C_Map = C_Map or {}
C_Map.GetUserWaypoint = RejectEngineCall("C_Map.GetUserWaypoint")
QuestLogPushQuest = RejectEngineCall("QuestLogPushQuest")
QuestMapFrame_OpenToQuestDetails = RejectEngineCall("QuestMapFrame_OpenToQuestDetails")
OpenQuestLog = RejectEngineCall("OpenQuestLog")
MenuUtil = { CreateContextMenu = RejectEngineCall("CreateContextMenu") }
-- A real /qt test starts after gameplay has created lazy stores. Keep populated
-- structured owners present even offline: replacing these with {} in a fixture
-- must fail here instead of passing only because a fresh process has nil state.
local livePhaseState = {
	peers = { ["LivePeer-Realm"] = { at = 100 } },
	attempts = { ["LivePeer-Realm"] = { id = "live-phase-request" } },
	replies = {},
	nextScan = 101,
}
local liveTargetState = { button = { Hide = RejectEngineCall("live target button") } }
QuestTogether.playerPhaseState = livePhaseState
QuestTogether.locationTargetState = liveTargetState

local function CheckLiveStructuredStores()
	assert(QuestTogether.playerPhaseState == livePhaseState, "phase owner replaced by test fixture")
	assert(
		livePhaseState.attempts["LivePeer-Realm"].id == "live-phase-request",
		"live phase request changed by fixture"
	)
	assert(QuestTogether.locationTargetState == liveTargetState, "target owner replaced by test fixture")
end

-- Exercise the same controller and QT-owned isolation used by the live command.
-- The live modes also model independent frame callbacks and real addon work
-- between cases. Engine replacements remain confined to this offline harness.
local success, passed, failed, result
if arg[2] == "live" or arg[2] == "live-reverse" then
	local callbacks, frames, maxCaseSeconds = {}, 0, 0
	local api = {}
	for key, value in pairs(QuestTogether.API) do
		api[key] = value
	end
	api.Delay = function(delay, callback)
		assert(delay == 0, "the live runner must schedule a later frame")
		callbacks[#callbacks + 1] = callback
	end
	QuestTogether.API = api
	QuestTogether.isRunningTests = false
	QuestTogether.suppressLocalAnnouncementDisplayDuringTests = false
	local db, runtime, registry = QuestTogether.db, QuestTogether.runtimeStateStore, QuestTogether.tests
	local controller = QuestTogether:GetDebugController()
	-- Presentation is tested separately with owned UI fixtures. The actual
	-- report and progress storage still run here without touching native UI.
	controller.ShowLog = function()
		return true
	end
	success, passed, failed, result = QuestTogether:RunTests(arg[2] == "live-reverse", true)
	assert(success and result.status == "running" and result.completed == 0, "test start must yield before any cases")
	local selected = 0
	for _, case in ipairs(registry) do
		if not case.offline then
			selected = selected + 1
		end
	end
	assert(
		result.total == selected and result.skipped == #registry - selected,
		"live selection must report offline coverage honestly"
	)
	assert(controller:RunTests() == false, "overlapping runs must not enter the live singleton")
	while result.status == "running" do
		frames = frames + 1
		assert(frames <= selected + 1, "staggered run failed to complete")
		local current = callbacks
		callbacks = {}
		assert(#current == 1, "each frame must run exactly one callback")
		local started = os.clock()
		current[1]()
		maxCaseSeconds = math.max(maxCaseSeconds, os.clock() - started)
		assert(
			QuestTogether.API == api and QuestTogether.db == db and QuestTogether.runtimeStateStore == runtime,
			"live stores or APIs leaked an isolated fixture between frames"
		)
		assert(QuestTogether.tests == registry, "test registry must survive the run")
		CheckLiveStructuredStores()
		assert(
			QuestTogether.isRunningTests == false and QuestTogether.suppressLocalAnnouncementDisplayDuringTests == false,
			"real addon behavior remained suppressed between frames"
		)
		assert(
			db.profile.runnerSmokeFrame == (frames > 1 and frames - 1 or nil),
			"live work was overwritten by a later test"
		)
		db.profile.runnerSmokeFrame = frames
	end
	assert(result.completed == selected and frames == selected, "one complete case must run per frame")
	assert(controller.runningTests == false and #callbacks == 0, "completed run must retire its scheduled work")
	success, passed, failed = result.failed == 0, result.passed, result.failed
	print(controller:GetText("TEST", ""))
	print(string.format("liveFrames=%d offlineOnly=%d maxFrameCPU=%.4fs", frames, result.skipped, maxCaseSeconds))
else
	success, passed, failed, result = QuestTogether:RunTests(arg[2] == "reverse", false)
end
assert(result, "Shared debug controller did not return a test result")
CheckLiveStructuredStores()
assert(#engineBoundaryCalls == 0, "live-test isolation failure: " .. table.concat(engineBoundaryCalls, ", "))
-- The shared headless runner already prints failures and the summary through
-- QT's console adapter; avoid duplicating its presentation here.
print("registered=" .. tostring(result.total))
local presentationCases = 0
for _, case in ipairs(QuestTogether.tests) do
	if case.locale == "client" then
		presentationCases = presentationCases + 1
	end
end
assert(presentationCases >= 6, "client-locale presentation coverage must be registered")
print("presentationLocale=" .. QuestTogether.locale .. " cases=" .. presentationCases)
os.exit(success and 0 or 1)
