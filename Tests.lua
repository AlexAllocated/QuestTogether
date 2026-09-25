--[[
QuestTogether In-Game Test Runner
]]

local QuestTogether = _G.QuestTogether
local LibChev = QuestTogether.LibChev

QuestTogether.tests = QuestTogether.tests or {}

function QuestTogether:RegisterTest(name, fn)
	self.tests[#self.tests + 1] = {
		name = name,
		fn = fn,
	}
end

for _, case in ipairs(LibChev.SelfTests()) do
	QuestTogether:RegisterTest(case.name, case.run)
end

local function AssertTrue(value, message)
	if not value then
		error(message or "Expected true but got false/nil")
	end
end

local function AssertFalse(value, message)
	if value then
		error(message or "Expected false but got true")
	end
end

local AssertEquals = LibChev.AssertEqual

local function CreateApiWithOverrides(overrides)
	local merged = {}
	for key, value in pairs(QuestTogether.API) do
		merged[key] = value
	end
	local safeFixtureDefaults = {
		-- Fixture tokens can also identify real nearby players. Tests must supply
		-- their own GUIDs instead of inheriting the live client's unit identities.
		UnitGUID = function()
			return nil
		end,
		-- Existing fixtures use retail Name-Realm identities independently of
		-- the live client's naming mode or the user's surname preference.
		RegionalUniqueNamesEnabled = function()
			return false
		end,
		ShouldDisplaySurname = function()
			return true
		end,
		GetTaskInfo = function()
			return nil, nil, nil, nil, nil
		end,
		GetPlayerMapID = function()
			return nil
		end,
		GetLocalTaskQuests = function()
			return nil
		end,
		GetTaskQuestsOnMap = function()
			return nil
		end,
		GetQuestPOIsOnMap = function()
			return nil
		end,
		IsModifiedClick = function()
			return false
		end,
		IsWorldMapVisible = function()
			return false
		end,
		IsTaskQuestActive = function()
			return nil
		end,
		IsWorldQuest = function()
			return nil
		end,
		GetQuestClassification = function()
			return nil
		end,
		GetQuestFrequency = function()
			return nil
		end,
		GetQuestPoiTagType = function()
			return nil
		end,
		GetTaskQuestInfoByQuestID = function()
			return nil
		end,
		IsQuestOnMap = function()
			return nil
		end,
		GetInstanceInfo = function()
			return nil
		end,
		IsInInstance = function()
			return false
		end,
	}
	for key, value in pairs(safeFixtureDefaults) do
		merged[key] = value
	end
	for key, value in pairs(overrides or {}) do
		merged[key] = value
	end
	return merged
end

local function WithPatchedMethod(targetTable, methodName, replacement, fn)
	local original = targetTable[methodName]
	targetTable[methodName] = replacement

	local ok, err = pcall(fn)

	targetTable[methodName] = original

	if not ok then
		error(err, 0)
	end
end

local function WithIsolatedState(testFn)
	if not QuestTogether.db then
		QuestTogether:OnInitialize()
	end

	local originalProfile = QuestTogether:DeepCopy(QuestTogether.db.profile)
	local originalGlobal = QuestTogether:DeepCopy(QuestTogether.db.global)
	local originalProfiles = QuestTogether:DeepCopy(QuestTogether.db.profiles or {})
	local originalProfileKeys = QuestTogether:DeepCopy(QuestTogether.db.profileKeys or {})
	local originalActiveProfileKey = QuestTogether.activeProfileKey
	local originalActiveCharacterKey = QuestTogether.activeCharacterKey
	local originalSavedVariables = _G.QuestTogetherDB
	local originalAPI = QuestTogether.API
	local originalPrint = QuestTogether.Print
	local originalPrintRaw = QuestTogether.PrintRaw
	local originalPrintChatLogRaw = QuestTogether.PrintChatLogRaw
	local originalPartyMembers = QuestTogether.partyMembers
	local originalPartyMemberOrder = QuestTogether.partyMemberOrder
	local originalPartyRosterFingerprint = QuestTogether.partyRosterFingerprint
	local originalDiagnostics = {}
	local diagnosticFields = {"diagnosticLogSequence", "diagnosticDroppedLogLines", "diagnosticErrorCount", "diagnosticLastError"}
	for _, key in ipairs(diagnosticFields) do originalDiagnostics[key] = QuestTogether[key]; QuestTogether[key] = nil end
	local originalDebugLogLines = QuestTogether.debugLogLines
	local originalDebugLogTextLengthSum = QuestTogether.debugLogTextLengthSum
	local originalDebugLogStoreNormalized = QuestTogether.debugLogStoreNormalized
	local originalIsEnabled = QuestTogether.isEnabled
	local originalSuppressLocalAnnouncementDisplayDuringTests = QuestTogether.suppressLocalAnnouncementDisplayDuringTests
	local originalProfileEnabled = QuestTogether.db.profile.enabled
	local originalRuntimeStateStore = QuestTogether.runtimeStateStore
	local originalNameplateTooltipGuidByUnitToken = QuestTogether.nameplateTooltipGuidByUnitToken
	local originalNameplateScanTooltip = QuestTogether.nameplateScanTooltip
	local originalPendingNameplateVisualCleanup = QuestTogether.pendingNameplateVisualCleanup
	local originalAnnouncementBubbleScreenHostFrame = QuestTogether.announcementBubbleScreenHostFrame
	local originalAnnouncementChannelLocalID = QuestTogether.announcementChannelLocalID
	local originalDebugController = QuestTogether.debugController
	-- Detach the live console before teardown can emit logs or refresh a view.
	QuestTogether.debugController = nil
	local originalPendingPingRequests = QuestTogether.pendingPingRequests
	local originalPendingQuestCompareRequests = QuestTogether.pendingQuestCompareRequests
	local originalRecentCommMessageSignatures = QuestTogether.recentCommMessageSignatures
	local originalPendingQuestRemovals = QuestTogether.pendingQuestRemovals
	local originalQuestEventState = {}
	for _, key in ipairs({"onQuestLogUpdate", "questsCompleted", "pendingQuestAcceptances", "retiredQuestIds"}) do
		originalQuestEventState[key] = QuestTogether[key]
		QuestTogether[key] = {}
	end
	local originalIsLoggingOut = QuestTogether.isLoggingOut
	local originalQuestLogChatFrameID = QuestTogether.db.profile.questLogChatFrameID
	local originalPendingScheduledTaskAreaRefreshShouldAnnounce =
		QuestTogether:GetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false)
	local originalPendingDeferredNameplateQuestStateRefresh =
		QuestTogether:GetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
	local originalDeferredNameplateQuestStateRefreshGeneration =
		QuestTogether:GetRuntimeFlag("deferredNameplateQuestStateRefreshGeneration", 0)
	local originalDeferredWorkState = QuestTogether.deferredWorkState
	local originalPendingWaypointIntent = QuestTogether:GetRuntimeWorkStateStore().pendingWaypointIntent

	if QuestTogether.UnregisterRuntimeEvents then
		QuestTogether:UnregisterRuntimeEvents()
	end
	if QuestTogether.DisableNameplateAugmentation then
		QuestTogether:DisableNameplateAugmentation()
	end

	QuestTogether.db.profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile)
	QuestTogether.db.global = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.global)
	QuestTogether.db.profiles = {
		["MyPlayer-Realm"] = QuestTogether.db.profile,
	}
	QuestTogether.db.profileKeys = {
		["MyPlayer-Realm"] = "MyPlayer-Realm",
	}
	QuestTogether.activeCharacterKey = "MyPlayer-Realm"
	QuestTogether.activeProfileKey = "MyPlayer-Realm"
	_G.QuestTogetherDB = QuestTogether.db
	QuestTogether.db.profile.enabled = false
	QuestTogether.isEnabled = false
	QuestTogether.debugLogLines = {}
	QuestTogether.debugLogTextLengthSum = 0
	QuestTogether.debugLogStoreNormalized = true
	QuestTogether.partyMembers = {}
	QuestTogether.partyMemberOrder = {}
	QuestTogether.partyRosterFingerprint = ""
	-- Detach every compatibility alias before building private test state.
	for _, key in ipairs({"worldQuestAreaStateByQuestID", "bonusObjectiveAreaStateByQuestID", "questSnapshotByQuestID", "questSnapshotOrder", "nameplateQuestTextCache", "nameplateQuestStateByGuid", "nameplateQuestStateByUnitToken", "nameplateQuestGuidByUnitToken", "nameplateIconByUnitFrame", "nameplateHealthOverlayByUnitFrame", "nameplateBubbleByUnitFrame", "nameplateBubbleStateByFrame", "nameplateRefreshPendingByUnitToken", "nameplateRefreshGenerationByUnitToken", "nameplateHealthTintRefreshPendingByUnitToken", "nameplateTooltipResolveRetryCountByUnitToken", "personalBubbleSliderHandlesByFrame", "personalBubbleDialogPositionByFrame", "deferredWorkState"}) do
		QuestTogether[key] = nil
	end
	QuestTogether.runtimeStateStore = nil
	if QuestTogether.EnsureRuntimeStateStore then
		QuestTogether:EnsureRuntimeStateStore()
	end
	if QuestTogether.ResetQuestSnapshotStateStore then
		QuestTogether:ResetQuestSnapshotStateStore()
	end
	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	end
	if QuestTogether.ResetNameplateStateStore then
		QuestTogether:ResetNameplateStateStore()
	end
	if QuestTogether.ResetRuntimeWorkStateStore then
		QuestTogether:ResetRuntimeWorkStateStore()
	end
	QuestTogether.nameplateTooltipGuidByUnitToken = nil
	QuestTogether.nameplateScanTooltip = nil
	QuestTogether.pendingNameplateVisualCleanup = false
	QuestTogether.announcementBubbleScreenHostFrame = nil
	QuestTogether.announcementChannelLocalID = nil
	QuestTogether.debugController = nil
	QuestTogether.pendingPingRequests = {}
	QuestTogether.pendingQuestCompareRequests = {}
	QuestTogether.recentCommMessageSignatures = {}
	QuestTogether.pendingQuestRemovals = {}
	QuestTogether.isLoggingOut = false
	QuestTogether.API = CreateApiWithOverrides({})

	local ok, err = pcall(testFn)

	local createdQuestLogChatFrameID = QuestTogether.db
		and QuestTogether.db.profile
		and QuestTogether.db.profile.questLogChatFrameID
	if
		createdQuestLogChatFrameID
		and createdQuestLogChatFrameID ~= originalQuestLogChatFrameID
		and QuestTogether.CloseQuestLogChatFrame
	then
		pcall(QuestTogether.CloseQuestLogChatFrame, QuestTogether)
	end

	QuestTogether.db.global = originalGlobal
	QuestTogether.db.profiles = originalProfiles
	QuestTogether.db.profileKeys = originalProfileKeys
	QuestTogether.activeProfileKey = originalActiveProfileKey
	QuestTogether.activeCharacterKey = originalActiveCharacterKey
	_G.QuestTogetherDB = originalSavedVariables
	if
		originalActiveProfileKey
		and QuestTogether.db.profiles
		and type(QuestTogether.db.profiles[originalActiveProfileKey]) == "table"
	then
		QuestTogether.db.profile = QuestTogether.db.profiles[originalActiveProfileKey]
	else
		QuestTogether.db.profile = originalProfile
	end
	QuestTogether.API = originalAPI
	QuestTogether.Print = originalPrint
	QuestTogether.PrintRaw = originalPrintRaw
	QuestTogether.PrintChatLogRaw = originalPrintChatLogRaw
	QuestTogether.debugLogLines = originalDebugLogLines
	for _, key in ipairs(diagnosticFields) do QuestTogether[key] = originalDiagnostics[key] end
	QuestTogether.debugLogTextLengthSum = originalDebugLogTextLengthSum
	QuestTogether.debugLogStoreNormalized = originalDebugLogStoreNormalized
	QuestTogether.partyMembers = originalPartyMembers
	QuestTogether.partyMemberOrder = originalPartyMemberOrder
	QuestTogether.partyRosterFingerprint = originalPartyRosterFingerprint
	if QuestTogether.db.profile then
		QuestTogether.db.profile.enabled = originalProfileEnabled
	end
	QuestTogether.isEnabled = originalIsEnabled
	QuestTogether.suppressLocalAnnouncementDisplayDuringTests = originalSuppressLocalAnnouncementDisplayDuringTests
	QuestTogether.runtimeStateStore = originalRuntimeStateStore
	if QuestTogether.EnsureRuntimeStateStore then
		QuestTogether:EnsureRuntimeStateStore()
	end
	QuestTogether.nameplateTooltipGuidByUnitToken = originalNameplateTooltipGuidByUnitToken
	QuestTogether.nameplateScanTooltip = originalNameplateScanTooltip
	QuestTogether.pendingNameplateVisualCleanup = originalPendingNameplateVisualCleanup
	QuestTogether.announcementBubbleScreenHostFrame = originalAnnouncementBubbleScreenHostFrame
	QuestTogether.announcementChannelLocalID = originalAnnouncementChannelLocalID
	QuestTogether.debugController = originalDebugController
	QuestTogether.pendingPingRequests = originalPendingPingRequests
	QuestTogether.pendingQuestCompareRequests = originalPendingQuestCompareRequests
	QuestTogether.recentCommMessageSignatures = originalRecentCommMessageSignatures
	QuestTogether.pendingQuestRemovals = originalPendingQuestRemovals
	for _, key in ipairs({"onQuestLogUpdate", "questsCompleted", "pendingQuestAcceptances", "retiredQuestIds"}) do
		QuestTogether[key] = originalQuestEventState[key]
	end
	QuestTogether.isLoggingOut = originalIsLoggingOut
	if QuestTogether.SetRuntimeFlag then
		QuestTogether:SetRuntimeFlag(
			"pendingScheduledTaskAreaRefreshShouldAnnounce",
			originalPendingScheduledTaskAreaRefreshShouldAnnounce
		)
		QuestTogether:SetRuntimeFlag(
			"pendingDeferredNameplateQuestStateRefresh",
			originalPendingDeferredNameplateQuestStateRefresh
		)
		QuestTogether:SetRuntimeFlag(
			"deferredNameplateQuestStateRefreshGeneration",
			originalDeferredNameplateQuestStateRefreshGeneration
		)
	end
	QuestTogether:SetPendingWaypointIntent(originalPendingWaypointIntent)
	QuestTogether:GetRuntimeWorkStateStore().deferredWorkState = originalDeferredWorkState
	QuestTogether.deferredWorkState = originalDeferredWorkState

	if originalIsEnabled then
		if QuestTogether.RegisterRuntimeEvents then
			QuestTogether:RegisterRuntimeEvents()
		end
		if QuestTogether.EnableNameplateAugmentation then
			QuestTogether:EnableNameplateAugmentation()
		end
	end

	if not ok then
		error(err, 0)
	end
end

function QuestTogether:GetDebugTestOptions()
	return { run = WithIsolatedState }
end

function QuestTogether:RunTests(reverse, present)
	return self:GetDebugController():RunTests(reverse, present)
end

QuestTogether:RegisterTest("debug window category filter and search support fuzzy and quoted exact matches", function()
	WithIsolatedState(function()
		QuestTogether:ClearDebugLog()
		QuestTogether:LogDebugLine("alpha one", {
			category = "quest",
		})
		QuestTogether:LogDebugLine("beta two", {
			category = "test",
		})
		QuestTogether:LogDebugLine("alpha three", {
			category = "quest",
		})

		local fuzzyText = QuestTogether:GetDebugLogText("QUEST", "ath")
		AssertFalse(string.find(fuzzyText, "alpha one", 1, true) ~= nil)
		AssertTrue(string.find(fuzzyText, "alpha three", 1, true) ~= nil)
		AssertFalse(string.find(fuzzyText, "beta two", 1, true) ~= nil)

		local exactText = QuestTogether:GetDebugLogText("QUEST", "\"alpha t\"")
		AssertFalse(string.find(exactText, "alpha one", 1, true) ~= nil)
		AssertTrue(string.find(exactText, "alpha three", 1, true) ~= nil)
		AssertFalse(string.find(exactText, "beta two", 1, true) ~= nil)

		local shownCount, _, totalCount = QuestTogether:GetDebugLogMetrics("QUEST", "\"alpha\"")
		AssertEquals(shownCount, 2)
		AssertEquals(totalCount, 3)

		QuestTogether:SetDebugLogCategoryFilter("quest")
		AssertEquals(QuestTogether:GetDebugLogCategoryFilter(), "QUEST")
		QuestTogether:SetDebugLogSearchFilter("\"alpha t\"")
		AssertEquals(QuestTogether:GetDebugLogSearchFilter(), "\"alpha t\"")
	end)
end)

QuestTogether:RegisterTest("debug window clear resets filters and stale categories fall back to ALL", function()
	WithIsolatedState(function()
		QuestTogether:ClearDebugLog()
		QuestTogether:LogDebugLine("alpha quest", {
			category = "quest",
		})
		QuestTogether:LogDebugLine("beta test", {
			category = "test",
		})

		QuestTogether:SetDebugLogCategoryFilter("test")
		AssertEquals(QuestTogether:GetDebugLogCategoryFilter(), "TEST")
		QuestTogether:RemoveDebugLogEntriesByCategory("test")
		AssertEquals(QuestTogether:GetDebugLogCategoryFilter(), "ALL")

		QuestTogether:SetDebugLogCategoryFilter("quest")
		QuestTogether:SetDebugLogSearchFilter("alpha")
		QuestTogether:ClearDebugWindow()
		AssertEquals(QuestTogether:GetDebugLogCategoryFilter(), "ALL")
		AssertEquals(QuestTogether:GetDebugLogSearchFilter(), "")
		AssertEquals(#QuestTogether:GetDebugLogStore(), 0)
	end)
end)

QuestTogether:RegisterTest("debug window logs are runtime-only and reset on database init", function()
	WithIsolatedState(function()
		QuestTogether.db.global.debugLogLines = {
			{
				text = "persisted line",
				category = "test",
			},
		}
		QuestTogether.debugLogLines = QuestTogether.db.global.debugLogLines
		QuestTogether.debugLogStoreNormalized = false

		QuestTogether:InitializeDatabase()

		AssertEquals(QuestTogether.db.global.debugLogLines, nil)
		AssertEquals(#QuestTogether:GetDebugLogStore(), 0)
	end)
end)

QuestTogether:RegisterTest("debug window ALL category stays selected when already open during test runs", function()
	WithIsolatedState(function()
		QuestTogether.db.global.debugLogCategoryFilter = QuestTogether.DEBUG_ALL_CATEGORIES
		local controller = QuestTogether:GetDebugController()
		controller.policy.ui.restricted = function() return false end
		controller.window = {
			IsForbidden = function() return false end,
			IsProtected = function() return false end,
			IsShown = function()
				return true
			end,
		}

		AssertTrue(QuestTogether:IsDebugWindowShowingAllCategory())
	end)
end)

QuestTogether:RegisterTest("WatchQuest stores tracker entries under normalized numeric quest ids", function()
	local tracker = QuestTogether:GetPlayerTracker()
	QuestTogether:WatchQuest("12345", { title = "Any Quest" })

	AssertTrue(tracker[12345] ~= nil)
	AssertEquals(tracker["12345"], nil)

	QuestTogether:WatchQuest("bad-id", { title = "Ignored Quest" })
	AssertEquals(tracker["bad-id"], nil)
end)

QuestTogether:RegisterTest("quest trackers are isolated by full character key", function()
	QuestTogether.activeCharacterKey = "SameName-FirstRealm"
	local firstTracker = QuestTogether:GetPlayerTracker()
	firstTracker[12345] = {
		title = "First Character Quest",
	}

	QuestTogether.activeCharacterKey = "SameName-SecondRealm"
	local secondTracker = QuestTogether:GetPlayerTracker()

	AssertTrue(firstTracker ~= secondTracker)
	AssertEquals(secondTracker[12345], nil)
end)

QuestTogether:RegisterTest("WatchQuest seeds ready-to-turn-in baseline from live status", function()
	local tracker = QuestTogether:GetPlayerTracker()

	QuestTogether.API = CreateApiWithOverrides({
		IsQuestReadyForTurnIn = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		IsQuestComplete = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 12345)
			return 1
		end,
	})

	QuestTogether:WatchQuest(12345, {
		title = "Ready Quest",
		questLogIndex = 1,
	})

	AssertTrue(tracker[12345] ~= nil)
	AssertTrue(tracker[12345].isReadyForTurnIn)
end)

QuestTogether:RegisterTest("WatchQuest does not refresh announcement icon metadata during tracker sync", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 12345)
			return nil
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshTrackedQuestAnnouncementIcon", function()
		error("WatchQuest should not refresh announcement icon metadata during tracker sync")
	end, function()
		QuestTogether:WatchQuest(12345, {
			title = "Any Quest",
		})
	end)
end)

QuestTogether:RegisterTest("UNIT_QUEST_LOG_CHANGED does not refresh announcement icon metadata during status sync", function()
	local tracker = QuestTogether:GetPlayerTracker()
	tracker[12345] = {
		title = "Any Quest",
		objectives = {},
		objectiveValues = {},
		isComplete = false,
		isReadyForTurnIn = false,
	}
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 12345)
			return 1
		end,
		GetNumQuestLeaderBoards = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return 0
		end,
	})

	WithPatchedMethod(QuestTogether, "QueueQuestLogTask", function(_, taskFn)
		taskFn()
	end, function()
		WithPatchedMethod(QuestTogether, "GetTrackedQuestStatusState", function(_, questId, allowLiveFallback)
			AssertEquals(questId, 12345)
			AssertTrue(allowLiveFallback)
			return {
				isComplete = true,
				isReadyForTurnIn = true,
			}
		end, function()
			WithPatchedMethod(QuestTogether, "RefreshTrackedQuestAnnouncementIcon", function()
				error("UNIT_QUEST_LOG_CHANGED should not refresh announcement icon metadata during status sync")
			end, function()
				WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function() end, function()
					QuestTogether:UNIT_QUEST_LOG_CHANGED(nil, "player")
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("objective progress identity follows the objective label instead of its count", function()
	AssertEquals(
		QuestTogether:GetObjectiveProgressIdentity("1/3 Gather Apples"),
		QuestTogether:GetObjectiveProgressIdentity("2/3 Gather Apples")
	)
	AssertEquals(
		QuestTogether:GetObjectiveProgressIdentity("34% Fill the vial"),
		QuestTogether:GetObjectiveProgressIdentity("80% Fill the vial")
	)
	AssertTrue(
		QuestTogether:GetObjectiveProgressIdentity("1/3 Gather Apples")
			~= QuestTogether:GetObjectiveProgressIdentity("5/8 Rescue Villagers")
	)
end)

QuestTogether:RegisterTest("objective progress rejects increases from a replaced objective slot", function()
	AssertTrue(
		QuestTogether:DidObjectiveProgressIncrease(
			"1/3 Gather Apples",
			1,
			"2/3 Gather Apples",
			2
		)
	)
	AssertFalse(
		QuestTogether:DidObjectiveProgressIncrease(
			"1/3 Gather Apples",
			1,
			"5/8 Rescue Villagers",
			5
		)
	)
end)

QuestTogether:RegisterTest("UNIT_QUEST_LOG_CHANGED does not announce a replaced objective slot", function()
	local tracker = QuestTogether:GetPlayerTracker()
	tracker[12345] = {
		title = "Changing Objectives",
		objectives = {
			"1/3 Gather Apples",
		},
		objectiveValues = {
			1,
		},
		isComplete = false,
		isReadyForTurnIn = false,
	}
	local published = 0

	QuestTogether.API = CreateApiWithOverrides({
		GetQuestLogIndexForQuestID = function()
			return 1
		end,
		GetNumQuestLeaderBoards = function()
			return 1
		end,
		GetQuestObjectiveInfo = function()
			return "5/8 Rescue Villagers", "monster", false, 5
		end,
	})

	WithPatchedMethod(QuestTogether, "QueueQuestLogTask", function(_, taskFn)
		taskFn()
	end, function()
		WithPatchedMethod(QuestTogether, "GetTrackedQuestStatusState", function()
			return {
				isComplete = false,
				isReadyForTurnIn = false,
			}
		end, function()
			WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function()
				published = published + 1
			end, function()
				QuestTogether:UNIT_QUEST_LOG_CHANGED(nil, "player")
			end)
		end)
	end)

	AssertEquals(published, 0)
	AssertEquals(tracker[12345].objectives[1], "5/8 Rescue Villagers")
	AssertEquals(tracker[12345].objectiveValues[1], 5)
end)

QuestTogether:RegisterTest("Safe conversions short-circuit values marked secret", function()
	WithPatchedMethod(QuestTogether, "IsSecretValue", function(_, value)
		return value == "secret-text" or value == 99
	end, function()
		AssertEquals(QuestTogether:SafeToNumber(99), nil)
		AssertEquals(QuestTogether:SafeToNumber("secret-text"), nil)
		AssertEquals(QuestTogether:SafeToString("secret-text", "fallback"), "fallback")
		AssertEquals(QuestTogether:SafeTrimString("secret-text", "fallback"), "fallback")
		AssertEquals(QuestTogether:SafeStripWhitespace("secret-text", "fallback"), "fallback")
	end)
end)

QuestTogether:RegisterTest("safe conversions and frame reads reject inaccessible values", function()
	local inaccessibleValue = "inaccessible-value"
	local fakeFrame = {
		UnitFrame = inaccessibleValue,
	}

	WithPatchedMethod(QuestTogether, "CanAccessValue", function(_, value)
		return value ~= inaccessibleValue
	end, function()
		AssertEquals(QuestTogether:SafeToNumber(inaccessibleValue), nil)
		AssertEquals(QuestTogether:SafeToString(inaccessibleValue, "fallback"), "fallback")
		AssertEquals(QuestTogether:SafeTrimString(inaccessibleValue, "fallback"), "fallback")
		AssertEquals(QuestTogether:SafeStripWhitespace(inaccessibleValue, "fallback"), "fallback")

		local memberValue, memberReadable = QuestTogether:GetAccessibleFrameMember(fakeFrame, "UnitFrame")
		AssertEquals(memberValue, nil)
		AssertFalse(memberReadable)
	end)
end)

QuestTogether:RegisterTest("nameplate tooltip scan guid does not write custom fields or cache guid state", function()
	local unitToken = "nameplate9"
	local unitFrame = {
		namePlateUnitGUID = "Creature-0-0-0-0-99999-0000000000",
	}

	local guid = QuestTogether:GetNameplateTooltipScanGuid(unitToken, unitFrame)
	AssertEquals(guid, "Creature-0-0-0-0-99999-0000000000")
	AssertEquals(unitFrame.qtTooltipScanGuid, nil)
	AssertEquals(QuestTogether.nameplateTooltipGuidByUnitToken, nil)

	QuestTogether:OnNameplateRemoved(unitToken)
	AssertEquals(QuestTogether.nameplateTooltipGuidByUnitToken, nil)
end)

QuestTogether:RegisterTest("profile assignment is stored per character key", function()
	QuestTogether.db.profiles = {}
	QuestTogether.db.profileKeys = {}
	QuestTogether.activeCharacterKey = "Alpha-Realm"
	QuestTogether.activeProfileKey = nil

	local applyCalls = 0
	WithPatchedMethod(QuestTogether, "ApplyActiveProfileState", function()
		applyCalls = applyCalls + 1
		return true
	end, function()
		local okAlpha, errAlpha = QuestTogether:SetActiveProfile("Alpha-Realm")
		AssertTrue(okAlpha, errAlpha)
		AssertEquals(QuestTogether.db.profileKeys["Alpha-Realm"], "Alpha-Realm")

		QuestTogether.activeCharacterKey = "Beta-Realm"
		local okBeta, errBeta = QuestTogether:SetActiveProfile("Beta-Realm")
		AssertTrue(okBeta, errBeta)
		AssertEquals(QuestTogether.db.profileKeys["Beta-Realm"], "Beta-Realm")
	end)

	AssertTrue(QuestTogether.db.profiles["Alpha-Realm"] ~= nil)
	AssertTrue(QuestTogether.db.profiles["Beta-Realm"] ~= nil)
	AssertEquals(applyCalls, 2)
end)

QuestTogether:RegisterTest("profile operations support create, copy, reset, and delete", function()
	QuestTogether.db.profiles = {
		["MyPlayer-Realm"] = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile),
		Template = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile),
	}
	QuestTogether.db.profileKeys = {
		["MyPlayer-Realm"] = "MyPlayer-Realm",
	}
	QuestTogether.activeCharacterKey = "MyPlayer-Realm"
	QuestTogether.activeProfileKey = "MyPlayer-Realm"
	QuestTogether.db.profile = QuestTogether.db.profiles["MyPlayer-Realm"]

	QuestTogether.db.profiles.Template.showChatLogs = false
	QuestTogether.db.profiles.Template.showChatBubbles = false
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = true

	local applyCalls = 0
	WithPatchedMethod(QuestTogether, "ApplyActiveProfileState", function()
		applyCalls = applyCalls + 1
		return true
	end, function()
		local createOk, createErr = QuestTogether:CreateProfile("Disposable", "Template")
		AssertTrue(createOk, createErr)
		AssertTrue(QuestTogether.db.profiles.Disposable ~= nil)

		local copyOk, copyErr = QuestTogether:CopyProfileIntoActiveProfile("Template")
		AssertTrue(copyOk, copyErr)
		AssertFalse(QuestTogether.db.profile.showChatLogs)
		AssertFalse(QuestTogether.db.profile.showChatBubbles)

		QuestTogether.db.profile.showChatLogs = false
		local resetOk, resetErr = QuestTogether:ResetActiveProfile()
		AssertTrue(resetOk, resetErr)
		AssertEquals(QuestTogether.db.profile.showChatLogs, QuestTogether.DEFAULTS.profile.showChatLogs)

		local deleteActiveOk = QuestTogether:DeleteProfile("MyPlayer-Realm")
		AssertFalse(deleteActiveOk)

		local deleteOk, deleteErr = QuestTogether:DeleteProfile("Disposable")
		AssertTrue(deleteOk, deleteErr)
		AssertEquals(QuestTogether.db.profiles.Disposable, nil)
	end)

AssertEquals(applyCalls, 2)
end)

QuestTogether:RegisterTest("task area refresh defers during combat and resumes on regen", function()
	local refreshCalls = {}
	local deferredEntry = nil
	QuestTogether.isEnabled = true

	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 0
		end,
		InCombatLockdown = function()
			return true
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshWorldQuestAreaState", function(_, shouldAnnounce)
		refreshCalls[#refreshCalls + 1] = "world:" .. tostring(shouldAnnounce)
	end, function()
		WithPatchedMethod(QuestTogether, "RefreshBonusObjectiveAreaState", function(_, shouldAnnounce)
			refreshCalls[#refreshCalls + 1] = "bonus:" .. tostring(shouldAnnounce)
		end, function()
			AssertFalse(QuestTogether:RefreshTaskAreaStates(true))
			AssertEquals(#refreshCalls, 0)
			deferredEntry = QuestTogether:GetDeferredWorkStateStore().entries[LibChev.WorkKey(
				"task_area_refresh",
				"task_area_refresh"
			)]
			AssertTrue(deferredEntry ~= nil)
			AssertTrue(QuestTogether:GetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false))

			QuestTogether.API = CreateApiWithOverrides({
				InCombatLockdown = function()
					return false
				end,
			})

			QuestTogether:PLAYER_REGEN_ENABLED()
			AssertEquals(refreshCalls[1], "world:true")
			AssertEquals(refreshCalls[2], "bonus:true")
			AssertEquals(
				QuestTogether:GetDeferredWorkStateStore().entries[LibChev.WorkKey(
					"task_area_refresh",
					"task_area_refresh"
				)],
				nil
			)
			AssertFalse(QuestTogether:GetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false))
		end)
	end)
end)

QuestTogether:RegisterTest("task area refresh defers through runtime gate and resumes when it clears", function()
	local refreshCalls = {}

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 0
		end,
		Delay = function(_, callback)
			callback()
		end,
	})

	WithPatchedMethod(QuestTogether, "IsWorkBlocked", function(_, workClass)
		return workClass == "task_area_refresh"
	end, function()
		WithPatchedMethod(QuestTogether, "RefreshWorldQuestAreaState", function(_, shouldAnnounce)
			refreshCalls[#refreshCalls + 1] = "world:" .. tostring(shouldAnnounce)
		end, function()
			WithPatchedMethod(QuestTogether, "RefreshBonusObjectiveAreaState", function(_, shouldAnnounce)
				refreshCalls[#refreshCalls + 1] = "bonus:" .. tostring(shouldAnnounce)
			end, function()
				AssertFalse(QuestTogether:RefreshTaskAreaStates(true))
				AssertEquals(#refreshCalls, 0)

				WithPatchedMethod(QuestTogether, "IsWorkBlocked", function()
					return false
				end, function()
					QuestTogether:FlushDeferredWork("task_area_runtime_gate")
				end)
			end)
		end)
	end)

	AssertEquals(refreshCalls[1], "world:true")
	AssertEquals(refreshCalls[2], "bonus:true")
end)

QuestTogether:RegisterTest("task area snapshot falls back to IsWorldQuest when questInfo world flag is falsey", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 12345,
				title = "Fallback Classified World Quest",
				isHeader = false,
				isHidden = false,
				isTask = true,
				isOnMap = true,
				hasLocalPOI = true,
				isWorldQuest = false,
			}
		end,
		GetLocalTaskQuests = function()
			error("GetLocalTaskQuests should not be called")
		end,
		GetTaskInfo = function()
			error("GetTaskInfo should not be called")
		end,
		IsTaskQuestActive = function()
			error("IsTaskQuestActive should not be called")
		end,
		IsWorldQuest = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
	})

	QuestTogether:RefreshTaskAreaStates(false)
	local worldSnapshot = QuestTogether:GetTaskAreaSnapshot("world")
	local bonusSnapshot = QuestTogether:GetTaskAreaSnapshot("bonus")
	AssertEquals(worldSnapshot[12345], "Fallback Classified World Quest")
	AssertEquals(bonusSnapshot[12345], nil)
end)

QuestTogether:RegisterTest("task area snapshot ignores live task helper APIs and out-of-area world quests", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 22222,
				title = "Snapshot Out Of Area World Quest",
				isHeader = false,
				isHidden = false,
				isTask = true,
				isOnMap = false,
				hasLocalPOI = false,
				isWorldQuest = true,
			}
		end,
		GetLocalTaskQuests = function()
			error("GetLocalTaskQuests should not be called")
		end,
		GetTaskInfo = function()
			error("GetTaskInfo should not be called")
		end,
		IsTaskQuestActive = function()
			error("IsTaskQuestActive should not be called")
		end,
		IsQuestOnMap = function()
			error("IsQuestOnMap should not be called")
		end,
	})

	QuestTogether:RefreshTaskAreaStates(false)
	local worldSnapshot = QuestTogether:GetTaskAreaSnapshot("world")
	AssertEquals(worldSnapshot[22222], nil)
end)

QuestTogether:RegisterTest("task area snapshot includes world quests from snapshot map flags only", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 22230,
				title = "Snapshot In Area World Quest",
				isHeader = false,
				isHidden = false,
				isTask = true,
				isOnMap = true,
				hasLocalPOI = false,
				isWorldQuest = true,
			}
		end,
		GetLocalTaskQuests = function()
			error("GetLocalTaskQuests should not be called")
		end,
		GetTaskInfo = function()
			error("GetTaskInfo should not be called")
		end,
		IsTaskQuestActive = function()
			error("IsTaskQuestActive should not be called")
		end,
	})

	QuestTogether:RefreshTaskAreaStates(false)
	local worldSnapshot = QuestTogether:GetTaskAreaSnapshot("world")
	AssertEquals(worldSnapshot[22230], "Snapshot In Area World Quest")
end)

QuestTogether:RegisterTest("task area snapshot prefers live quest log rows over cached snapshot state", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 22231,
				title = "Live In Area World Quest",
				isHeader = false,
				isHidden = false,
				isTask = true,
				isOnMap = true,
				hasLocalPOI = false,
				isWorldQuest = false,
			}
		end,
		IsWorldQuest = function(questId)
			AssertEquals(questId, 22231)
			return true
		end,
	})

	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	end
	if QuestTogether.ResetQuestSnapshotStore then
		QuestTogether:ResetQuestSnapshotStore()
	end

	local snapshotState = QuestTogether:GetQuestSnapshotStateStore()
	snapshotState.byQuestID[22231] = {
		questID = 22231,
		title = "Stale Out Of Area World Quest",
		isHidden = false,
		isTask = true,
		isOnMap = false,
		hasLocalPOI = false,
		isWorldQuest = true,
	}
	snapshotState.order[1] = 22231

	QuestTogether:RefreshTaskAreaStates(false)
	local worldSnapshot = QuestTogether:GetTaskAreaSnapshot("world")
	AssertEquals(worldSnapshot[22231], "Live In Area World Quest")
end)

QuestTogether:RegisterTest("task area snapshot treats world quests as tasks when task flag is falsey", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 33333,
				title = "World Quest Without Task Flag",
				isHeader = false,
				isHidden = false,
				isTask = false,
				isOnMap = true,
				hasLocalPOI = false,
				isWorldQuest = false,
			}
		end,
		GetLocalTaskQuests = function()
			error("GetLocalTaskQuests should not be called")
		end,
		GetTaskInfo = function()
			error("GetTaskInfo should not be called")
		end,
		IsTaskQuestActive = function()
			error("IsTaskQuestActive should not be called")
		end,
		IsWorldQuest = function(questId)
			AssertEquals(questId, 33333)
			return true
		end,
	})

	QuestTogether:RefreshTaskAreaStates(false)
	local worldSnapshot = QuestTogether:GetTaskAreaSnapshot("world")
	AssertEquals(worldSnapshot[33333], "World Quest Without Task Flag")
end)

QuestTogether:RegisterTest("task area snapshot derives bonus objectives from displayAsObjective plus snapshot map flags", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 33335,
				title = "Bonus Objective Without Live Helpers",
				isHeader = false,
				isHidden = false,
				isTask = true,
				isOnMap = false,
				hasLocalPOI = true,
				isWorldQuest = false,
			}
		end,
		GetLocalTaskQuests = function()
			error("GetLocalTaskQuests should not be called")
		end,
		GetTaskInfo = function()
			error("GetTaskInfo should not be called")
		end,
		IsTaskQuestActive = function()
			error("IsTaskQuestActive should not be called")
		end,
		GetTaskQuestInfoByQuestID = function(questId)
			AssertEquals(questId, 33335)
			return {
				displayAsObjective = true,
			}
		end,
	})

	WithPatchedMethod(QuestTogether, "IsWorldQuest", function(_, questId)
		AssertEquals(questId, 33335)
		return false
	end, function()
		QuestTogether:RefreshTaskAreaStates(false)
		local bonusSnapshot = QuestTogether:GetTaskAreaSnapshot("bonus")
		AssertEquals(bonusSnapshot[33335], "Bonus Objective Without Live Helpers")
		AssertTrue(QuestTogether:IsBonusObjective(33335))
		AssertEquals(QuestTogether:GetTaskAnnouncementType(33335), "bonus")
	end)
end)

QuestTogether:RegisterTest("task area snapshot does not classify normal task quests as bonus objectives", function()
	local events = {}

	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 33336,
				title = "Normal Task Quest",
				isHeader = false,
				isHidden = false,
				isTask = true,
				isOnMap = true,
				hasLocalPOI = true,
				isWorldQuest = false,
			}
		end,
		GetTaskQuestInfoByQuestID = function(questId)
			AssertEquals(questId, 33336)
			return {
				displayAsObjective = false,
			}
		end,
	})

	WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
		events[#events + 1] = {
			eventType = eventType,
			text = text,
			questId = questId,
		}
	end, function()
		WithPatchedMethod(QuestTogether, "IsWorldQuest", function(_, questId)
			AssertEquals(questId, 33336)
			return false
		end, function()
			QuestTogether:RefreshTaskAreaStates(true)
			local bonusSnapshot = QuestTogether:GetTaskAreaSnapshot("bonus")
			AssertEquals(bonusSnapshot[33336], nil)
			AssertFalse(QuestTogether:IsBonusObjective(33336))
			AssertEquals(QuestTogether:GetTaskAnnouncementType(33336), nil)
		end)
	end)

	AssertEquals(#events, 0)
end)

QuestTogether:RegisterTest("quest-blob state change refreshes task area states with announcements", function()
	local refreshCalls = 0
	local scheduledCalls = 0

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(seconds, callback)
			scheduledCalls = scheduledCalls + 1
			AssertEquals(seconds, 0.1)
			callback()
		end,
	})
	QuestTogether.isEnabled = true
	QuestTogether:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", nil)

	WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function(_, shouldAnnounce)
		AssertTrue(shouldAnnounce)
		refreshCalls = refreshCalls + 1
	end, function()
		QuestTogether:PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", 22233, true)
	end)

	AssertEquals(scheduledCalls, 1)
	AssertEquals(refreshCalls, 1)
end)

QuestTogether:RegisterTest("task area snapshot treats world quests as tasks when task flag is falsey", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 33333,
				title = "World Quest Without Task Flag",
				isHeader = false,
				isHidden = false,
				isTask = false,
				isOnMap = true,
				hasLocalPOI = false,
				isWorldQuest = false,
			}
		end,
		GetLocalTaskQuests = function()
			error("GetLocalTaskQuests should not be called")
		end,
		GetTaskInfo = function()
			error("GetTaskInfo should not be called")
		end,
		IsTaskQuestActive = function()
			error("IsTaskQuestActive should not be called")
		end,
	})

	WithPatchedMethod(QuestTogether, "IsWorldQuest", function(_, questId)
		AssertEquals(questId, 33333)
		return true
	end, function()
		QuestTogether:RefreshTaskAreaStates(false)
		local worldSnapshot = QuestTogether:GetTaskAreaSnapshot("world")
		AssertEquals(worldSnapshot[33333], "World Quest Without Task Flag")
	end)
end)

QuestTogether:RegisterTest("task area snapshot does not use task-active fallback without snapshot map flags", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 33334,
				title = "World Quest Without Snapshot Map Flags",
				isHeader = false,
				isHidden = false,
				isTask = false,
				isOnMap = false,
				hasLocalPOI = false,
				isWorldQuest = false,
			}
		end,
		GetLocalTaskQuests = function()
			error("GetLocalTaskQuests should not be called")
		end,
		GetTaskInfo = function()
			error("GetTaskInfo should not be called")
		end,
		IsTaskQuestActive = function()
			error("IsTaskQuestActive should not be called")
		end,
		IsQuestOnMap = function()
			error("IsQuestOnMap should not be called")
		end,
	})

	WithPatchedMethod(QuestTogether, "IsWorldQuest", function(_, questId)
		AssertEquals(questId, 33334)
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "IsBonusObjective", function(_, questId)
			AssertEquals(questId, 33334)
			return false
		end, function()
			QuestTogether:RefreshTaskAreaStates(false)
			local worldSnapshot = QuestTogether:GetTaskAreaSnapshot("world")
			local bonusSnapshot = QuestTogether:GetTaskAreaSnapshot("bonus")
			AssertEquals(worldSnapshot[33334], nil)
			AssertEquals(bonusSnapshot[33334], nil)
		end)
	end)
end)

QuestTogether:RegisterTest("task area snapshot avoids map task API reads that taint Blizzard map pins", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				questID = 33335,
				title = "Bonus Objective Without Map Arrays",
				isHeader = false,
				isHidden = false,
				isTask = true,
				isOnMap = false,
				hasLocalPOI = true,
				isWorldQuest = false,
			}
		end,
		GetLocalTaskQuests = function()
			error("GetLocalTaskQuests should not be called")
		end,
		GetTaskInfo = function()
			error("GetTaskInfo should not be called")
		end,
		IsTaskQuestActive = function()
			error("IsTaskQuestActive should not be called")
		end,
		GetTaskQuestsOnMap = function()
			error("GetTaskQuestsOnMap should not be called")
		end,
		GetQuestPOIsOnMap = function()
			error("GetQuestPOIsOnMap should not be called")
		end,
		GetTaskQuestInfoByQuestID = function(questId)
			AssertEquals(questId, 33335)
			return {
				displayAsObjective = true,
			}
		end,
	})

	QuestTogether:RefreshTaskAreaStates(false)
	local bonusSnapshot = QuestTogether:GetTaskAreaSnapshot("bonus")
	AssertEquals(bonusSnapshot[33335], "Bonus Objective Without Map Arrays")
end)

QuestTogether:RegisterTest("task announcement type falls back to IsWorldQuest API when snapshots are falsey", function()
	QuestTogether.API = CreateApiWithOverrides({
		IsWorldQuest = function(questId)
			AssertEquals(questId, 44444)
			return true
		end,
	})

	QuestTogether:ResetTaskAreaStateStore()
	if QuestTogether.ResetQuestSnapshotStore then
		QuestTogether:ResetQuestSnapshotStore()
	end

	AssertEquals(QuestTogether:GetTaskAnnouncementType(44444), "world")
end)

QuestTogether:RegisterTest("world quest area refresh publishes enter and leave events from snapshot diffs", function()
	local events = {}
	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	else
		QuestTogether.worldQuestAreaStateByQuestID = {}
	end

	local resolverState = QuestTogether:GetTaskAreaSubsystemStateStore()
	WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
		events[#events + 1] = {
			eventType = eventType,
			text = text,
			questId = questId,
		}
	end, function()
		resolverState.resolvedByQuestID = {
			[12345] = {
				questID = 12345,
				title = "Snapshot World Quest",
				includeWorld = true,
				includeBonus = false,
			},
		}
		resolverState.resolutionOrder = { 12345 }
		QuestTogether:RefreshWorldQuestAreaState(true)

		resolverState.resolvedByQuestID = {}
		resolverState.resolutionOrder = {}
		QuestTogether:RefreshWorldQuestAreaState(true)
	end)

	AssertEquals(events[1].eventType, "WORLD_QUEST_ENTERED")
	AssertEquals(events[1].questId, 12345)
	AssertTrue(string.find(events[1].text, "Snapshot World Quest", 1, true) ~= nil)
AssertEquals(events[2].eventType, "WORLD_QUEST_LEFT")
AssertEquals(events[2].questId, 12345)
AssertTrue(string.find(events[2].text, "Snapshot World Quest", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("task area refresh reacts to live world area changes across repeated refreshes", function()
	local events = {}
	local liveQuestInfo = {
		questID = 55555,
		title = "Fresh World Quest Area State",
		isHeader = false,
		isHidden = false,
		isTask = true,
		isOnMap = false,
		hasLocalPOI = false,
		isWorldQuest = false,
	}

	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return liveQuestInfo
		end,
		IsWorldQuest = function(questId)
			AssertEquals(questId, 55555)
			return true
		end,
	})

	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	end
	if QuestTogether.ResetQuestSnapshotStore then
		QuestTogether:ResetQuestSnapshotStore()
	end

	WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
		events[#events + 1] = {
			eventType = eventType,
			text = text,
			questId = questId,
		}
	end, function()
		QuestTogether:RefreshTaskAreaStates(false)

		liveQuestInfo = {
			questID = 55555,
			title = "Fresh World Quest Area State",
			isHeader = false,
			isHidden = false,
			isTask = true,
			isOnMap = true,
			hasLocalPOI = false,
			isWorldQuest = false,
		}
		QuestTogether:RefreshTaskAreaStates(true)

		liveQuestInfo = {
			questID = 55555,
			title = "Fresh World Quest Area State",
			isHeader = false,
			isHidden = false,
			isTask = true,
			isOnMap = false,
			hasLocalPOI = false,
			isWorldQuest = false,
		}
		QuestTogether:RefreshTaskAreaStates(true)
	end)

	AssertEquals(events[1].eventType, "WORLD_QUEST_ENTERED")
	AssertEquals(events[1].questId, 55555)
	AssertTrue(string.find(events[1].text, "Fresh World Quest Area State", 1, true) ~= nil)
	AssertEquals(events[2].eventType, "WORLD_QUEST_LEFT")
	AssertEquals(events[2].questId, 55555)
	AssertTrue(string.find(events[2].text, "Fresh World Quest Area State", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("clearing tracked world quest state preserves prior area snapshot for left announcement diff", function()
	local events = {}

	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 0
		end,
	})

	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	end

	local worldState = QuestTogether:GetTaskAreaStateStore("world")
	worldState[66666] = "Tracked World Quest"
	QuestTogether:GetPlayerTracker()[66666] = {
		title = "Tracked World Quest",
		taskAnnouncementType = "world",
	}

	WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
		events[#events + 1] = {
			eventType = eventType,
			text = text,
			questId = questId,
		}
	end, function()
		QuestTogether:ClearTrackedQuestState(66666)
	end)

	AssertEquals(events[1].eventType, "WORLD_QUEST_LEFT")
	AssertEquals(events[1].questId, 66666)
	AssertTrue(string.find(events[1].text, "Tracked World Quest", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("clearing tracked completed world quest state suppresses left announcement diff", function()
	local events = {}

	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 0
		end,
	})

	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	end

	local worldState = QuestTogether:GetTaskAreaStateStore("world")
	worldState[66667] = "Completed World Quest"
	QuestTogether:GetPlayerTracker()[66667] = {
		title = "Completed World Quest",
		taskAnnouncementType = "world",
	}
	QuestTogether.questsCompleted[66667] = {
		questId = 66667,
		title = "Completed World Quest",
		taskAnnouncementType = "world",
	}

	WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
		events[#events + 1] = {
			eventType = eventType,
			text = text,
			questId = questId,
		}
	end, function()
		QuestTogether:ClearTrackedQuestState(66667)
	end)

	AssertEquals(#events, 0)
	AssertEquals(QuestTogether.questsCompleted[66667], nil)
end)

QuestTogether:RegisterTest("task area refresh reacts to live bonus area changes across repeated refreshes", function()
	local events = {}
	local liveQuestInfo = {
		questID = 77770,
		title = "Fresh Bonus Objective Area State",
		isHeader = false,
		isHidden = false,
		isTask = true,
		isOnMap = false,
		hasLocalPOI = false,
		isWorldQuest = false,
	}

	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return liveQuestInfo
		end,
		GetTaskQuestInfoByQuestID = function(questId)
			AssertEquals(questId, 77770)
			return {
				displayAsObjective = true,
			}
		end,
		IsWorldQuest = function(questId)
			AssertEquals(questId, 77770)
			return false
		end,
	})

	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	end
	if QuestTogether.ResetQuestSnapshotStore then
		QuestTogether:ResetQuestSnapshotStore()
	end

	WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
		events[#events + 1] = {
			eventType = eventType,
			text = text,
			questId = questId,
		}
	end, function()
		QuestTogether:RefreshTaskAreaStates(false)

		liveQuestInfo = {
			questID = 77770,
			title = "Fresh Bonus Objective Area State",
			isHeader = false,
			isHidden = false,
			isTask = true,
			isOnMap = false,
			hasLocalPOI = true,
			isWorldQuest = false,
		}
		QuestTogether:RefreshTaskAreaStates(true)

		liveQuestInfo = {
			questID = 77770,
			title = "Fresh Bonus Objective Area State",
			isHeader = false,
			isHidden = false,
			isTask = true,
			isOnMap = false,
			hasLocalPOI = false,
			isWorldQuest = false,
		}
		QuestTogether:RefreshTaskAreaStates(true)
	end)

	AssertEquals(events[1].eventType, "BONUS_OBJECTIVE_ENTERED")
	AssertEquals(events[1].questId, 77770)
	AssertTrue(string.find(events[1].text, "Fresh Bonus Objective Area State", 1, true) ~= nil)
	AssertEquals(events[2].eventType, "BONUS_OBJECTIVE_LEFT")
	AssertEquals(events[2].questId, 77770)
	AssertTrue(string.find(events[2].text, "Fresh Bonus Objective Area State", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("clearing tracked bonus objective state preserves prior area snapshot for left announcement diff", function()
	local events = {}

	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 0
		end,
	})

	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	end

	local bonusState = QuestTogether:GetTaskAreaStateStore("bonus")
	bonusState[77771] = "Tracked Bonus Objective"
	QuestTogether:GetPlayerTracker()[77771] = {
		title = "Tracked Bonus Objective",
		taskAnnouncementType = "bonus",
	}

	WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
		events[#events + 1] = {
			eventType = eventType,
			text = text,
			questId = questId,
		}
	end, function()
		QuestTogether:ClearTrackedQuestState(77771)
	end)

	AssertEquals(events[1].eventType, "BONUS_OBJECTIVE_LEFT")
	AssertEquals(events[1].questId, 77771)
	AssertTrue(string.find(events[1].text, "Tracked Bonus Objective", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("clearing tracked completed bonus objective state suppresses left announcement diff", function()
	local events = {}

	QuestTogether.API = CreateApiWithOverrides({
		GetNumQuestLogEntries = function()
			return 0
		end,
	})

	if QuestTogether.ResetTaskAreaStateStore then
		QuestTogether:ResetTaskAreaStateStore()
	end

	local bonusState = QuestTogether:GetTaskAreaStateStore("bonus")
	bonusState[77772] = "Completed Bonus Objective"
	QuestTogether:GetPlayerTracker()[77772] = {
		title = "Completed Bonus Objective",
		taskAnnouncementType = "bonus",
	}
	QuestTogether.questsCompleted[77772] = {
		questId = 77772,
		title = "Completed Bonus Objective",
		taskAnnouncementType = "bonus",
	}

	WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
		events[#events + 1] = {
			eventType = eventType,
			text = text,
			questId = questId,
		}
	end, function()
		QuestTogether:ClearTrackedQuestState(77772)
	end)

	AssertEquals(#events, 0)
	AssertEquals(QuestTogether.questsCompleted[77772], nil)
end)

QuestTogether:RegisterTest("super tracking changed defers task area refresh off the live event stack", function()
	local refreshCalls = 0
	local scheduledCalls = 0

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(seconds, callback)
			scheduledCalls = scheduledCalls + 1
			AssertEquals(seconds, 0.1)
			callback()
		end,
	})
	QuestTogether.isEnabled = true

	WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function(_, shouldAnnounce)
		AssertTrue(shouldAnnounce)
		refreshCalls = refreshCalls + 1
	end, function()
		QuestTogether:SUPER_TRACKING_CHANGED()
	end)

	AssertEquals(scheduledCalls, 1)
	AssertEquals(refreshCalls, 1)
end)

QuestTogether:RegisterTest("quest poi update defers task area refresh off the live event stack", function()
	local refreshCalls = 0
	local scheduledCalls = 0

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(seconds, callback)
			scheduledCalls = scheduledCalls + 1
			AssertEquals(seconds, 0.1)
			callback()
		end,
	})
	QuestTogether.isEnabled = true
	QuestTogether:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", nil)

	WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function(_, shouldAnnounce)
		AssertTrue(shouldAnnounce)
		refreshCalls = refreshCalls + 1
	end, function()
		QuestTogether:QUEST_POI_UPDATE()
	end)

	AssertEquals(scheduledCalls, 1)
	AssertEquals(refreshCalls, 1)
end)

QuestTogether:RegisterTest("quest log queued tasks defer during combat and resume on regen", function()
	local ranTask = false
	QuestTogether.onQuestLogUpdate = {}
	QuestTogether.isEnabled = true
	table.insert(QuestTogether.onQuestLogUpdate, function()
		ranTask = true
	end)

	QuestTogether.API = CreateApiWithOverrides({
		InCombatLockdown = function()
			return true
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function()
		return false
	end, function()
		QuestTogether:QUEST_LOG_UPDATE()
	end)

	AssertFalse(ranTask)
	AssertEquals(#QuestTogether.onQuestLogUpdate, 1)

	QuestTogether.API = CreateApiWithOverrides({
		InCombatLockdown = function()
			return false
		end,
	})
	QuestTogether:PLAYER_REGEN_ENABLED()

	AssertTrue(ranTask)
	AssertEquals(#QuestTogether.onQuestLogUpdate, 0)
end)

QuestTogether:RegisterTest("quest log queued tasks drain immediately out of combat", function()
	local runCount = 0
	QuestTogether.onQuestLogUpdate = {}
	QuestTogether.isEnabled = true
	table.insert(QuestTogether.onQuestLogUpdate, function()
		runCount = runCount + 1
	end)

	QuestTogether.API = CreateApiWithOverrides({
		InCombatLockdown = function()
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function()
		return true
	end, function()
		QuestTogether:QUEST_LOG_UPDATE()
	end)

	AssertEquals(runCount, 1)
	AssertEquals(#QuestTogether.onQuestLogUpdate, 0)
end)

QuestTogether:RegisterTest("quest log queued tasks defer through runtime gate and resume when it clears", function()
	local ranTask = false

	QuestTogether.onQuestLogUpdate = {}
	QuestTogether.isEnabled = true
	table.insert(QuestTogether.onQuestLogUpdate, function()
		ranTask = true
	end)

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			callback()
		end,
	})

	WithPatchedMethod(QuestTogether, "IsWorkBlocked", function(_, workClass)
		return workClass == "quest_log_drain"
	end, function()
		WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function()
			return false
		end, function()
			QuestTogether:QUEST_LOG_UPDATE()
		end)
	end)

	AssertFalse(ranTask)
	AssertEquals(#QuestTogether.onQuestLogUpdate, 1)

	WithPatchedMethod(QuestTogether, "IsWorkBlocked", function()
		return false
	end, function()
		QuestTogether:FlushDeferredWork("quest_log_runtime_gate")
	end)

	AssertTrue(ranTask)
	AssertEquals(#QuestTogether.onQuestLogUpdate, 0)
end)

QuestTogether:RegisterTest("quest status uses ready to turn in announcement event", function()
	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function()
			return false
		end,
		IsQuestReadyForTurnIn = function()
			return true
		end,
		GetQuestLogIndexForQuestID = function()
			return 1
		end,
		IsOnQuest = function()
			return true
		end,
		IsQuestComplete = function()
			return true
		end,
	})

	AssertEquals(QuestTogether:GetQuestStatusAnnouncementEventType(12345), "QUEST_READY_TO_TURN_IN")
end)

QuestTogether:RegisterTest("quest completion publishes and plays the same emote token", function()
	local published = nil
	local played = nil

	WithPatchedMethod(QuestTogether, "PickRandomCompletionEmote", function()
		return "cheer"
	end, function()
		WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId, extraData)
			published = {
				eventType = eventType,
				text = text,
				questId = questId,
				extraData = extraData,
			}
		end, function()
			WithPatchedMethod(QuestTogether, "PlayLocalCompletionEmote", function(_, emoteToken)
				played = emoteToken
			end, function()
				QuestTogether:HandleQuestCompleted("Test Quest", 12345)
			end)
		end)
	end)

	AssertEquals(published.eventType, "QUEST_COMPLETED")
	AssertEquals(published.questId, 12345)
	AssertEquals(published.extraData.emoteToken, "cheer")
	AssertEquals(played, "cheer")
end)

QuestTogether:RegisterTest("local completion emotes are suppressed during test runs", function()
	local emoteCalls = 0

	QuestTogether.db.profile.emoteOnQuestCompletion = true
	QuestTogether.suppressLocalAnnouncementDisplayDuringTests = true
	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function()
			emoteCalls = emoteCalls + 1
		end,
	})

	AssertFalse(QuestTogether:PlayLocalCompletionEmote("cheer"))
	AssertEquals(emoteCalls, 0)
end)

QuestTogether:RegisterTest("quest completion preserves cached quest icon metadata", function()
	local published = nil
	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function() end,
	})

	WithPatchedMethod(QuestTogether, "PickRandomCompletionEmote", function()
		return "cheer"
	end, function()
		WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId, extraData)
			published = {
				eventType = eventType,
				text = text,
				questId = questId,
				extraData = extraData,
			}
		end, function()
			QuestTogether:HandleQuestCompleted("Test Quest", 12345, {
				iconAsset = "CampaignCompletedQuestIcon",
				iconKind = "atlas",
			})
		end)
	end)

	AssertEquals(published.eventType, "QUEST_COMPLETED")
	AssertEquals(published.questId, 12345)
	AssertEquals(published.extraData.iconAsset, "CampaignCompletedQuestIcon")
	AssertEquals(published.extraData.iconKind, "atlas")
	AssertEquals(published.extraData.emoteToken, "cheer")
end)

QuestTogether:RegisterTest("quest completion strips non allowlisted announcement metadata", function()
	local published = nil
	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function() end,
	})

	WithPatchedMethod(QuestTogether, "PickRandomCompletionEmote", function()
		return "cheer"
	end, function()
		WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, _, _, _, extraData)
			published = extraData
		end, function()
			QuestTogether:HandleQuestCompleted("Test Quest", 12345, {
				iconAsset = "CampaignCompletedQuestIcon",
				iconKind = "atlas",
				unexpected = "drop-me",
				nested = {
					flag = true,
				},
			})
		end)
	end)

	AssertTrue(published ~= nil)
	AssertEquals(published.iconAsset, "CampaignCompletedQuestIcon")
	AssertEquals(published.iconKind, "atlas")
	AssertEquals(published.emoteToken, "cheer")
	AssertEquals(published.unexpected, nil)
	AssertEquals(published.nested, nil)
end)

QuestTogether:RegisterTest("quest turn in followed by removal announces completion once", function()
	local delayed = {}
	local completed = nil
	local removed = nil
	local refreshCalls = 0

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			delayed[#delayed + 1] = callback
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerName", function()
		return "Tester"
	end, function()
		local tracker = QuestTogether:GetPlayerTracker()
		tracker[12345] = {
			title = "Test Quest",
			iconAsset = "CampaignActiveQuestIcon",
			iconKind = "atlas",
		}

		WithPatchedMethod(QuestTogether, "HandleQuestCompleted", function(_, questTitle, questId, extraData)
			completed = {
				questTitle = questTitle,
				questId = questId,
				extraData = extraData,
			}
		end, function()
			WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
				removed = {
					eventType = eventType,
					text = text,
					questId = questId,
				}
			end, function()
				WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function()
					refreshCalls = refreshCalls + 1
				end, function()
					WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
						AssertEquals(eventType, "QUEST_READY_TO_TURN_IN")
						AssertEquals(questId, 12345)
						return "CampaignTurnInQuestIcon", "atlas"
					end, function()
						QuestTogether:QUEST_TURNED_IN(nil, 12345)
						QuestTogether:QUEST_REMOVED(nil, 12345)
						AssertEquals(#delayed, 1)
						delayed[1]()
					end)
				end)
			end)
		end)

		AssertTrue(completed ~= nil)
		AssertEquals(completed.questTitle, "Test Quest")
		AssertEquals(completed.questId, 12345)
		AssertEquals(completed.extraData.iconAsset, "CampaignTurnInQuestIcon")
		AssertEquals(completed.extraData.iconKind, "atlas")
		AssertEquals(removed, nil)
		AssertEquals(tracker[12345], nil)
		AssertEquals(QuestTogether.pendingQuestRemovals[12345], nil)
		AssertEquals(QuestTogether.questsCompleted[12345], nil)
		AssertEquals(refreshCalls, 1)
	end)
end)

QuestTogether:RegisterTest("world quest turn in preserves world quest completion icon", function()
	local delayed = {}
	local completed = nil

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			delayed[#delayed + 1] = callback
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerName", function()
		return "Tester"
	end, function()
		local tracker = QuestTogether:GetPlayerTracker()
		tracker[54321] = {
			title = "Test World Quest",
			iconAsset = "worldquest-icon",
			iconKind = "atlas",
		}

		WithPatchedMethod(QuestTogether, "GetTaskAnnouncementType", function(_, questId)
			AssertEquals(questId, 54321)
			return "world"
		end, function()
			WithPatchedMethod(QuestTogether, "HandleQuestCompleted", function(_, questTitle, questId, extraData)
				completed = {
					questTitle = questTitle,
					questId = questId,
					extraData = extraData,
				}
			end, function()
				WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function() end, function()
					WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function() end, function()
						WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
							AssertEquals(eventType, "WORLD_QUEST_COMPLETED")
							AssertEquals(questId, 54321)
							return "worldquest-icon", "atlas"
						end, function()
							QuestTogether:QUEST_TURNED_IN(nil, 54321)
							QuestTogether:QUEST_REMOVED(nil, 54321)
							AssertEquals(#delayed, 1)
							delayed[1]()
						end)
					end)
				end)
			end)
		end)

		AssertTrue(completed ~= nil)
		AssertEquals(completed.questTitle, "Test World Quest")
		AssertEquals(completed.questId, 54321)
		AssertEquals(completed.extraData.iconAsset, "worldquest-icon")
		AssertEquals(completed.extraData.iconKind, "atlas")
	end)
end)

QuestTogether:RegisterTest("quest removal before turn in still resolves as completion", function()
	local delayed = {}
	local completed = nil
	local removed = nil

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			delayed[#delayed + 1] = callback
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerName", function()
		return "Tester"
	end, function()
		local tracker = QuestTogether:GetPlayerTracker()
		tracker[12345] = {
			title = "Test Quest",
			iconAsset = "CampaignActiveQuestIcon",
			iconKind = "atlas",
		}

		WithPatchedMethod(QuestTogether, "HandleQuestCompleted", function(_, questTitle, questId, extraData)
			completed = {
				questTitle = questTitle,
				questId = questId,
				extraData = extraData,
			}
		end, function()
			WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType)
				removed = eventType
			end, function()
				WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function() end, function()
					QuestTogether:QUEST_REMOVED(nil, 12345)
					AssertEquals(#delayed, 1)
					AssertTrue(QuestTogether.pendingQuestRemovals[12345] ~= nil)
					WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
						AssertEquals(eventType, "QUEST_READY_TO_TURN_IN")
						AssertEquals(questId, 12345)
						return "CampaignTurnInQuestIcon", "atlas"
					end, function()
						QuestTogether:QUEST_TURNED_IN(nil, 12345)
					end)
					AssertTrue(completed ~= nil)
					AssertEquals(completed.questTitle, "Test Quest")
					AssertEquals(completed.questId, 12345)
					AssertEquals(completed.extraData.iconAsset, "CampaignTurnInQuestIcon")
					AssertEquals(completed.extraData.iconKind, "atlas")
					AssertEquals(QuestTogether.pendingQuestRemovals[12345], nil)
					delayed[1]()
				end)
			end)
		end)

		AssertEquals(removed, nil)
		AssertEquals(tracker[12345], nil)
		AssertEquals(QuestTogether.questsCompleted[12345], nil)
	end)
end)

QuestTogether:RegisterTest("quest removal without turn in announces removal", function()
	local delayed = {}
	local completed = nil
	local removed = nil

	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			delayed[#delayed + 1] = callback
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerName", function()
		return "Tester"
	end, function()
		local tracker = QuestTogether:GetPlayerTracker()
		tracker[12345] = {
			title = "Test Quest",
			iconAsset = "CampaignActiveQuestIcon",
			iconKind = "atlas",
		}

		WithPatchedMethod(QuestTogether, "HandleQuestCompleted", function()
			completed = true
		end, function()
			WithPatchedMethod(QuestTogether, "PublishAnnouncementEvent", function(_, eventType, text, questId)
				removed = {
					eventType = eventType,
					text = text,
					questId = questId,
				}
			end, function()
				WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function() end, function()
					QuestTogether:QUEST_REMOVED(nil, 12345)
					AssertEquals(#delayed, 1)
					delayed[1]()
				end)
			end)
		end)

		AssertEquals(completed, nil)
		AssertTrue(removed ~= nil)
		AssertEquals(removed.eventType, "QUEST_REMOVED")
		AssertTrue(string.find(removed.text, "Test Quest", 1, true) ~= nil)
		AssertEquals(removed.questId, 12345)
		AssertEquals(tracker[12345], nil)
		AssertEquals(QuestTogether.pendingQuestRemovals[12345], nil)
	end)
end)

QuestTogether:RegisterTest("quest acceptance keeps Classic quest ID separate from log index", function()
	local addon = setmetatable({ pendingQuestRemovals = {}, questsCompleted = {}, pendingQuestAcceptances = {} }, { __index = QuestTogether })
	function addon:QueueQuestLogTask() end
	function addon:Debugf() end
	addon:QUEST_ACCEPTED("QUEST_ACCEPTED", 7, 12345)
	AssertTrue(addon.pendingQuestAcceptances[12345] ~= nil)
	AssertEquals(addon.pendingQuestAcceptances[7], nil)
	addon:QUEST_ACCEPTED("QUEST_ACCEPTED", 54321)
	AssertTrue(addon.pendingQuestAcceptances[54321] ~= nil)
	local secret = {}
	addon.CanAccessValue = function(_, value) return value ~= secret end
	addon:QUEST_ACCEPTED("QUEST_ACCEPTED", 8, secret)
	AssertEquals(addon.pendingQuestAcceptances[8], nil)
	addon:QUEST_ACCEPTED("QUEST_ACCEPTED", 9, false)
	AssertEquals(addon.pendingQuestAcceptances[9], nil)
end)

QuestTogether:RegisterTest("quest sharing distinguishes unavailable from not shareable", function()
	local addon = setmetatable({ API = {} }, { __index = QuestTogether })
	function addon:GetTrackedQuestStatusState() return { isOnQuest = true } end
	function addon:IsWorkBlocked() return false end
	addon.API.IsPushableQuest = function() return nil end
	AssertEquals(addon:GetQuestShareableStatusLabel(12345), "Unknown")
	addon.API.IsPushableQuest = function() return false end
	AssertEquals(addon:GetQuestShareableStatusLabel(12345), "No")
	addon.API.IsPushableQuest = function() return true end
	AssertEquals(addon:GetQuestShareableStatusLabel(12345), "Yes")
end)

QuestTogether:RegisterTest("quest accepted task refresh uses combat-safe wrapper", function()
	local wrappedRefreshCalls = 0

	QuestTogether.API = CreateApiWithOverrides({
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 12345)
			return 1
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 1)
			return {
				title = "Test Task",
				isHidden = false,
			}
		end,
	})

	WithPatchedMethod(QuestTogether, "QueueQuestLogTask", function(_, callback)
		callback()
	end, function()
		WithPatchedMethod(QuestTogether, "GetPlayerTracker", function()
			return {}
		end, function()
			WithPatchedMethod(QuestTogether, "GetTaskAnnouncementType", function(_, questId)
				AssertEquals(questId, 12345)
				return "world"
			end, function()
				WithPatchedMethod(QuestTogether, "WatchQuest", function() end, function()
					WithPatchedMethod(QuestTogether, "RefreshTaskAreaState", function()
						error("QUEST_ACCEPTED task flow should not call RefreshTaskAreaState directly")
					end, function()
						WithPatchedMethod(QuestTogether, "RefreshTaskAreaStates", function(_, shouldAnnounce)
							AssertTrue(shouldAnnounce)
							wrappedRefreshCalls = wrappedRefreshCalls + 1
						end, function()
							QuestTogether:QUEST_ACCEPTED(nil, 12345)
						end)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(wrappedRefreshCalls, 1)
end)

QuestTogether:RegisterTest("chat bubble option validation rejects unknown values", function()
	AssertTrue(QuestTogether:SetOption("chatBubbleSize", 140))
	AssertEquals(QuestTogether:GetOption("chatBubbleSize"), 140)
	AssertFalse(QuestTogether:SetOption("chatBubbleSize", 999))
	AssertEquals(QuestTogether:GetOption("chatBubbleSize"), 140)

	AssertTrue(QuestTogether:SetOption("chatBubbleDuration", 4.5))
	AssertEquals(QuestTogether:GetOption("chatBubbleDuration"), 4.5)
	AssertFalse(QuestTogether:SetOption("chatBubbleDuration", 9))
	AssertEquals(QuestTogether:GetOption("chatBubbleDuration"), 4.5)

	AssertTrue(QuestTogether:SetOption("showProgressFor", "party_only"))
	AssertEquals(QuestTogether:GetOption("showProgressFor"), "party_only")
	AssertFalse(QuestTogether:SetOption("showProgressFor", "everyone"))
	AssertEquals(QuestTogether:GetOption("showProgressFor"), "party_only")

	WithPatchedMethod(QuestTogether, "EnsureQuestLogChatFrame", function()
		return {
			AddMessage = function() end,
		}, 3
	end, function()
		WithPatchedMethod(QuestTogether, "GetResolvedChatLogDestination", function()
			return QuestTogether.db.profile.chatLogDestination
		end, function()
			AssertTrue(QuestTogether:SetOption("chatLogDestination", "separate"))
			AssertEquals(QuestTogether:GetOption("chatLogDestination"), "separate")
			AssertFalse(QuestTogether:SetOption("chatLogDestination", "guild"))
			AssertEquals(QuestTogether:GetOption("chatLogDestination"), "separate")
		end)
	end)
end)

QuestTogether:RegisterTest("progressbar objective text strips trailing parenthetical percent", function()
	AssertEquals(
		QuestTogether:StripTrailingParentheticalPercent("Fill the vial (34%)"),
		"Fill the vial"
	)
	AssertEquals(
		QuestTogether:StripTrailingParentheticalPercent("Refine potadpalate"),
		"Refine potadpalate"
	)
end)

QuestTogether:RegisterTest("normalized quest objective info formats progressbar objectives consistently", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestObjectiveInfo = function(questID, objectiveIndex, displayComplete)
			AssertEquals(questID, 40404)
			AssertEquals(objectiveIndex, 1)
			AssertEquals(displayComplete, false)
			return "Emerald Dreamway cleared (28%)", "progressbar", false, nil
		end,
		GetQuestProgressBarPercent = function(questID)
			AssertEquals(questID, 40404)
			return 28
		end,
	})

	local objectiveText, objectiveType, finished, currentValue =
		QuestTogether:GetNormalizedQuestObjectiveInfo(40404, 1, false)

	AssertEquals(objectiveText, "28% Emerald Dreamway cleared")
	AssertEquals(objectiveType, "progressbar")
	AssertFalse(finished)
	AssertEquals(currentValue, 28)
end)

QuestTogether:RegisterTest("quest nameplate icon display no longer requires attackable units", function()
	QuestTogether.isEnabled = true
	QuestTogether.db.profile.nameplateQuestIconEnabled = true
	local unitFrame = {
		namePlateUnitToken = "nameplate1",
		healthBar = {},
	}
	QuestTogether.API = CreateApiWithOverrides({
		IsAddOnLoaded = function()
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "CanPlayerAttackNameplateUnit", function()
		error("attackable-unit gating should not run for quest icon display")
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
				AssertEquals(unitToken, "nameplate1")
				return true
			end, function()
				WithPatchedMethod(QuestTogether, "IsNameplateUnitPlayer", function(_, unitToken)
					AssertEquals(unitToken, "nameplate1")
					return false
				end, function()
					WithPatchedMethod(QuestTogether, "IsNameplateUnitConnected", function(_, unitToken)
						AssertEquals(unitToken, "nameplate1")
						return true
					end, function()
						WithPatchedMethod(QuestTogether, "IsNameplateUnitDead", function(_, unitToken)
							AssertEquals(unitToken, "nameplate1")
							return false
						end, function()
							WithPatchedMethod(QuestTogether, "IsNameplateUnitTapDenied", function(_, unitToken)
								AssertEquals(unitToken, "nameplate1")
								return false
							end, function()
								AssertTrue(QuestTogether:ShouldShowQuestNameplateIconForResolvedState(nil, unitFrame, true))
								AssertTrue(QuestTogether:ShouldApplyQuestHealthTint(unitFrame, true))
							end)
						end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("tooltip quest detection uses isolated tooltip line scan for objectives", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function(_, unitGuid)
					AssertEquals(unitGuid, "Creature-0-0-0-0-12345-0000000000")
					return nil
				end, function()
					WithPatchedMethod(
						QuestTogether,
						"GetStructuredQuestObjectiveTooltipLines",
						function(_, unitToken, unitGuid)
							AssertEquals(unitToken, "nameplate1")
							AssertEquals(unitGuid, "Creature-0-0-0-0-12345-0000000000")
							return {
								{
									type = titleLineType,
									leftText = "Tracking the Trail",
								},
								{
									type = objectiveLineType,
									leftText = "1/8 Digested Object",
								},
							}
						end,
						function()
							WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function()
								error("hidden tooltip fallback should not run when structured data succeeds")
							end, function()
								AssertTrue(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
							end)
						end
					)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("tooltip quest detection recognizes fallback-style progress lines", function()
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
					return nil
				end, function()
					WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function(_, unitToken, unitGuid)
						AssertEquals(unitToken, "nameplate1")
						AssertEquals(unitGuid, "Creature-0-0-0-0-12345-0000000000")
						return {
							{
								leftText = "Tracking the Trail",
							},
							{
								leftText = "- Subdue Creatures or Kill Players (40%)",
							},
							}
						end, function()
							WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function()
								error("hidden tooltip fallback should not run when structured tooltip lines were returned")
							end, function()
								AssertTrue(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
							end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("tooltip quest detection does not iterate tooltip arg payloads", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	local poisonedArgs = setmetatable({}, {
		__index = function()
			error("tooltip arg payload should not be indexed")
		end,
		__pairs = function()
			error("tooltip arg payload should not be iterated")
		end,
	})
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
					return nil
				end, function()
					WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function()
						return {
							{
								type = titleLineType,
								leftText = "Tracking the Trail",
							},
							{
								type = objectiveLineType,
								leftText = "1/8 Digested Object",
								args = poisonedArgs,
							},
						}
					end, function()
						WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function()
							error("hidden tooltip fallback should not run when structured data succeeds")
						end, function()
							AssertTrue(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
						end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("tooltip quest detection blocks live scans while map-sensitive runtime gate is active", function()
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true
	QuestTogether.API = CreateApiWithOverrides({
		IsWorldMapVisible = function()
			return true
		end,
	})

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
					error("map-sensitive runtime gate should not touch Questie or tooltip APIs")
				end, function()
					WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function()
						error("map-sensitive runtime gate should not touch live structured tooltip scans")
					end, function()
						WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function()
							error("map-sensitive runtime gate should not touch hidden tooltip fallback")
						end, function()
							AssertFalse(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
						end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("tooltip quest detection defers live scans in combat even when map is closed", function()
	local hiddenScanCount = 0
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true
	QuestTogether.API = CreateApiWithOverrides({
		InCombatLockdown = function()
			return true
		end,
		IsWorldMapVisible = function()
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
					return nil
				end, function()
					WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function()
						return nil
					end, function()
						WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function()
							hiddenScanCount = hiddenScanCount + 1
							return {
								{
									leftText = "Tracking the Trail",
								},
								{
									leftText = "1/8 Digested Object",
								},
							}
						end, function()
							AssertFalse(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
						end)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(hiddenScanCount, 0)
end)

QuestTogether:RegisterTest("tooltip quest detection reuses cached state while runtime gate blocks live scans", function()
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true
	QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-12345-0000000000"] = true
	QuestTogether.nameplateQuestStateByUnitToken["nameplate1"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate1"] = "Creature-0-0-0-0-12345-0000000000"

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "IsWorkBlocked", function(_, workClass)
					return workClass == "nameplate_tooltip_resolve"
				end, function()
					WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
						error("runtime-gated detection should not touch Questie or tooltip APIs")
					end, function()
						WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function()
							error("runtime-gated detection should not touch live structured tooltip scans")
						end, function()
							AssertTrue(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
						end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("tooltip quest detection skips live scans while runtime gate blocks them without cache", function()
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "IsWorkBlocked", function(_, workClass)
					return workClass == "nameplate_tooltip_resolve"
				end, function()
					WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
						error("runtime-gated detection should not touch Questie or tooltip APIs")
					end, function()
						WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function()
							error("runtime-gated detection should not touch live structured tooltip scans")
						end, function()
							WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function()
								error("runtime-gated detection should not touch hidden tooltip scans")
							end, function()
								AssertFalse(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
							end)
						end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("nameplate quest detection cache is keyed by guid and reused across token churn", function()
	local scanCalls = 0
	local firstUnitFrame = {}
	local secondUnitFrame = {}

	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true
	QuestTogether.isEnabled = true

	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function(_, unitToken)
			if unitToken == "nameplate1" or unitToken == "nameplate2" then
				return "Creature-0-0-0-0-12345-0000000000"
			end
			return nil
		end, function()
			WithPatchedMethod(QuestTogether, "GetQuestObjectiveTooltipLines", function(_, unitToken, unitGuid)
				AssertEquals(unitGuid, "Creature-0-0-0-0-12345-0000000000")
				scanCalls = scanCalls + 1
				return {
					{
						leftText = "Tracking the Trail",
					},
					{
						leftText = "1/8 Digested Object",
					},
				}
			end, function()
				local hasResolvedFirst, isQuestObjectiveFirst = QuestTogether:TryResolveNameplateQuestObjectiveState(
					"nameplate1",
					firstUnitFrame,
					true
				)
				local hasResolvedSecond, isQuestObjectiveSecond = QuestTogether:TryResolveNameplateQuestObjectiveState(
					"nameplate2",
					secondUnitFrame,
					true
				)

				AssertTrue(hasResolvedFirst)
				AssertTrue(isQuestObjectiveFirst)
				AssertTrue(hasResolvedSecond)
				AssertTrue(isQuestObjectiveSecond)
				AssertEquals(scanCalls, 1)
				AssertEquals(QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-12345-0000000000"], true)
				AssertEquals(QuestTogether.nameplateQuestGuidByUnitToken["nameplate2"], "Creature-0-0-0-0-12345-0000000000")
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("deferred nameplate resolution ignores recycled tokens whose live guid no longer matches", function()
	local namePlateFrameBase = {
		namePlateUnitToken = "nameplate1",
		UnitFrame = {},
	}

	QuestTogether.isEnabled = true

	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "GetAccessibleNameplateFrameForUnit", function(_, unitToken, requireShown)
			AssertEquals(unitToken, "nameplate1")
			AssertEquals(requireShown, true)
			return namePlateFrameBase, namePlateFrameBase.UnitFrame
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateUnitGuid", function(_, unitToken)
				AssertEquals(unitToken, "nameplate1")
				return "Player-0-0-0-0-99999-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "TryResolveNameplateQuestObjectiveState", function()
					error("recycled token should be rejected before live resolution")
				end, function()
					WithPatchedMethod(QuestTogether, "HideNameplateIcon", function()
						error("recycled token should not mutate the current frame")
					end, function()
						AssertFalse(
							QuestTogether:ResolveNameplateQuestStateForUnitToken(
								"nameplate1",
								"Creature-0-0-0-0-12345-0000000000",
								"test"
							)
						)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("nameplate guid retry schedules a delayed visible refresh even before the unit token is queryable", function()
	local scheduledReason = nil
	local scheduledDelay = nil

	WithPatchedMethod(QuestTogether, "IsNameplateUnitToken", function(_, unitToken)
		return unitToken == "nameplate1"
	end, function()
		WithPatchedMethod(QuestTogether, "ScheduleNameplatePresentationRefresh", function(_, reason, delaySeconds)
			scheduledReason = reason
			scheduledDelay = delaySeconds
		end, function()
			AssertTrue(QuestTogether:MaybeScheduleNameplateTooltipGuidRetry("nameplate1", "RefreshNameplateIcon"))
		end)
	end)

	AssertEquals(scheduledReason, "RefreshNameplateIcon")
	AssertEquals(scheduledDelay, 0.2)
	AssertEquals(QuestTogether.nameplateTooltipResolveRetryCountByUnitToken["nameplate1"], 1)
end)

QuestTogether:RegisterTest("tooltip quest detection reuses cached results while map-sensitive runtime gate blocks rescanning", function()
	local structuredScanCount = 0
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true
	QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-12345-0000000000"] = true
	QuestTogether.nameplateQuestStateByUnitToken["nameplate1"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate1"] = "Creature-0-0-0-0-12345-0000000000"
	QuestTogether.API = CreateApiWithOverrides({
		IsWorldMapVisible = function()
			return true
		end,
	})

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
					error("map-sensitive runtime gate should reuse cached state instead of scanning")
				end, function()
					WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function()
						structuredScanCount = structuredScanCount + 1
						error("map-sensitive runtime gate should reuse cached state instead of rescanning")
					end, function()
						AssertTrue(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
						AssertTrue(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
						AssertEquals(structuredScanCount, 0)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(structuredScanCount, 0)
end)

QuestTogether:RegisterTest("tooltip quest detection rescans after an initial false result", function()
	local structuredScanCount = 0
	local hiddenScanCount = 0
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
					WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
						return nil
					end, function()
						WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function()
							structuredScanCount = structuredScanCount + 1
							if structuredScanCount <= 2 then
								return nil
							end
								return {
									{
										leftText = "Tracking the Trail",
								},
								{
									leftText = "- Subdue Creatures or Kill Players (40%)",
								},
							}
						end, function()
							WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function(_, unitToken, unitGuid)
								AssertEquals(unitToken, "nameplate1")
								AssertEquals(unitGuid, "Creature-0-0-0-0-12345-0000000000")
								hiddenScanCount = hiddenScanCount + 1
								return nil
							end, function()
								AssertFalse(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
								AssertTrue(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
								end)
							end)
					end)
				end)
			end)
		end)

		AssertEquals(structuredScanCount, 3)
		AssertEquals(hiddenScanCount, 1)
end)

QuestTogether:RegisterTest("quest objective detection uses tooltip parsing as the only decision path", function()
	local tooltipChecked = false
	local unitFrame = {}

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsQuestObjectiveViaTooltip", function(_, unitToken, candidateFrame)
			AssertEquals(unitToken, "nameplate1")
			AssertEquals(candidateFrame, unitFrame)
			tooltipChecked = true
			return true
		end, function()
			AssertTrue(QuestTogether:IsQuestObjectiveUnit("nameplate1", unitFrame))
		end)
	end)

	AssertTrue(tooltipChecked)
end)

QuestTogether:RegisterTest("quest objective detection returns false when tooltip parsing returns false", function()
	local unitFrame = {}

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsQuestObjectiveViaTooltip", function(_, unitToken, candidateFrame)
			AssertEquals(unitToken, "nameplate1")
			AssertEquals(candidateFrame, unitFrame)
			return false
		end, function()
			AssertFalse(QuestTogether:IsQuestObjectiveUnit("nameplate1", unitFrame))
		end)
	end)
end)

QuestTogether:RegisterTest("quest objective detection ignores false frame flags and still uses tooltip parsing", function()
	local tooltipChecked = false
	local unitFrame = {
		namePlateIsQuestObjective = false,
		isQuestObjective = false,
	}

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsQuestObjectiveViaTooltip", function(_, unitToken, candidateFrame)
			AssertEquals(unitToken, "nameplate1")
			AssertEquals(candidateFrame, unitFrame)
			tooltipChecked = true
			return true
		end, function()
			AssertTrue(QuestTogether:IsQuestObjectiveUnit("nameplate1", unitFrame))
		end)
	end)

	AssertTrue(tooltipChecked)
end)

QuestTogether:RegisterTest("tooltip quest detection prefers current unit identity over a recycled frame hint", function()
	local unitFrame = {
		namePlateUnitGUID = "Creature-0-0-0-0-12345-0000000000",
	}

	WithPatchedMethod(QuestTogether, "GetNameplateUnitGuid", function()
		return "Creature-0-0-0-0-67890-0000000000"
	end, function()
		AssertEquals(
			QuestTogether:GetNameplateTooltipScanGuid("nameplate1", unitFrame),
			"Creature-0-0-0-0-67890-0000000000"
		)
			end)
end)

QuestTogether:RegisterTest("tooltip quest detection falls back to frame identity when live identity is unavailable", function()
	local unitFrame = {
		unitGUID = "Creature-0-0-0-0-12345-0000000000",
	}

	WithPatchedMethod(QuestTogether, "GetNameplateUnitGuid", function()
		return nil
	end, function()
		AssertEquals(
			QuestTogether:GetNameplateTooltipScanGuid("nameplate1", unitFrame),
			"Creature-0-0-0-0-12345-0000000000"
		)
	end)
end)

QuestTogether:RegisterTest("tooltip quest detection can resolve live scans without a guid when unit tooltip sources succeed", function()
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true
	QuestTogether.isEnabled = true

	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
			return nil
		end, function()
			WithPatchedMethod(QuestTogether, "GetQuestObjectiveTooltipLines", function(_, unitToken, unitGuid)
				AssertEquals(unitToken, "nameplate1")
				AssertEquals(unitGuid, nil)
				return {
					{
						leftText = "Tracking the Trail",
					},
					{
						leftText = "1/8 Digested Object",
					},
				}, "structured_unit", 1
			end, function()
				local hasResolved, isQuestObjective, resolvedGuid =
					QuestTogether:TryResolveNameplateQuestObjectiveState("nameplate1", {}, true)

				AssertTrue(hasResolved)
				AssertTrue(isQuestObjective)
				AssertEquals(resolvedGuid, nil)
				AssertEquals(QuestTogether.nameplateQuestGuidByUnitToken["nameplate1"], nil)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("hidden tooltip quest scan uses addon-owned helpers", function()
	local unitGuid = "Creature-0-0-0-0-12345-0000000000"
	local fakeTooltip = {
		hideCount = 0,
		clearCount = 0,
		owner = nil,
		anchor = nil,
		unitToken = nil,
		hyperlink = nil,
		Hide = function(self)
			self.hideCount = self.hideCount + 1
		end,
		ClearLines = function(self)
			self.clearCount = self.clearCount + 1
		end,
		SetOwner = function(self, owner, anchor)
			self.owner = owner
			self.anchor = anchor
		end,
		SetUnit = function(self, unitToken)
			self.unitToken = unitToken
		end,
		SetHyperlink = function(self, hyperlink)
			self.hyperlink = hyperlink
		end,
	}
	QuestTogether.API = CreateApiWithOverrides({
		GetTooltipDataForHyperlink = false,
		GetTooltipDataForUnit = false,
	})

	WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "GetOrCreateNameplateScanTooltip", function()
			return fakeTooltip
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateScanTooltipLineCount", function(_, scanTooltip)
				AssertEquals(scanTooltip, fakeTooltip)
				return 2
			end, function()
				WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
					AssertEquals(unitToken, "nameplate1")
					return true
				end, function()
					WithPatchedMethod(QuestTogether, "GetNameplateScanTooltipLeftText", function(_, scanTooltip, lineIndex)
						AssertEquals(scanTooltip, fakeTooltip)
						if lineIndex == 1 then
							return "Gnarlidin Trophies"
						end
						if lineIndex == 2 then
							return "0/35 Gnarlidin Trophies"
						end
						return nil
					end, function()
						local tooltipLines = QuestTogether:GetQuestObjectiveTooltipLines("nameplate1", unitGuid)
						AssertEquals(fakeTooltip.unitToken, "nameplate1")
						AssertEquals(fakeTooltip.hyperlink, nil)
						AssertEquals(fakeTooltip.anchor, "ANCHOR_NONE")
						AssertEquals(type(tooltipLines), "table")
						AssertEquals(#tooltipLines, 2)
						AssertEquals(tooltipLines[1].type, nil)
						AssertEquals(tooltipLines[1].leftText, "Gnarlidin Trophies")
						AssertEquals(tooltipLines[2].type, nil)
						AssertEquals(tooltipLines[2].leftText, "0/35 Gnarlidin Trophies")
						AssertEquals(fakeTooltip.hideCount, 2)
						AssertEquals(fakeTooltip.clearCount, 2)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("structured-tooltip clients suppress Blizzard tooltip quest scans for map safety", function()
	local unitGuid = "Creature-0-0-0-0-12345-0000000000"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	local poisonedArgs = setmetatable({}, {
		__index = function()
			error("tooltip args should not be indexed")
		end,
		__pairs = function()
			error("tooltip args should not be iterated")
		end,
	})

	QuestTogether.API = CreateApiWithOverrides({
		IsWorldMapVisible = function()
			return true
		end,
		GetTooltipDataForHyperlink = function(hyperlink)
			AssertEquals(hyperlink, "unit:" .. unitGuid)
			return {
				lines = {
					{
						type = "UnitName",
						leftText = "Should Be Ignored",
					},
					{
						type = objectiveLineType,
						leftText = "0/35 Gnarlidin Trophies",
						args = poisonedArgs,
					},
				},
			}
		end,
		GetTooltipDataForUnit = function()
			error("unit tooltip fallback should not run when hyperlink tooltip data is available")
		end,
	})

	WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "GetOrCreateNameplateScanTooltip", function()
			error("hidden tooltip fallback should not run when structured tooltip data is available")
		end, function()
			local tooltipLines = QuestTogether:GetStructuredQuestObjectiveTooltipLines("nameplate1", unitGuid)
			AssertEquals(tooltipLines, nil)
		end)
	end)
end)

QuestTogether:RegisterTest("structured tooltip suppression still falls back to hidden tooltip when both structured sources fail", function()
	local unitGuid = "Creature-0-0-0-0-12345-0000000000"
	local hiddenTooltipCalls = 0

	QuestTogether.API = CreateApiWithOverrides({
		GetTooltipDataForHyperlink = function(hyperlink)
			AssertEquals(hyperlink, "unit:" .. unitGuid)
			return nil
		end,
		GetTooltipDataForUnit = function(unitToken)
			AssertEquals(unitToken, "nameplate1")
			return nil
		end,
	})

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function(_, candidateUnitToken, candidateGuid)
			AssertEquals(candidateUnitToken, "nameplate1")
			AssertEquals(candidateGuid, unitGuid)
			hiddenTooltipCalls = hiddenTooltipCalls + 1
			return {
				{
					leftText = "0/35 Gnarlidin Trophies",
				},
			}
		end, function()
			local tooltipLines = QuestTogether:GetQuestObjectiveTooltipLines("nameplate1", unitGuid)
			AssertEquals(type(tooltipLines), "table")
			AssertEquals(#tooltipLines, 1)
			AssertEquals(tooltipLines[1].leftText, "0/35 Gnarlidin Trophies")
		end)
	end)

	AssertEquals(hiddenTooltipCalls, 1)
end)

QuestTogether:RegisterTest("structured-tooltip clients allow Blizzard tooltip scans when map is closed", function()
	local unitGuid = "Creature-0-0-0-0-12345-0000000000"
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"

	QuestTogether.API = CreateApiWithOverrides({
		IsWorldMapVisible = function()
			return false
		end,
		GetTooltipDataForUnit = function(unitToken)
			AssertEquals(unitToken, "nameplate1")
			return {
				lines = {
					{
						type = titleLineType,
						leftText = "Tracking the Trail",
					},
					{
						type = objectiveLineType,
						leftText = "1/8 Digested Object",
					},
				},
			}
		end,
		GetTooltipDataForHyperlink = function()
			error("unit-token structured tooltip should win before hyperlink fallback")
		end,
	})
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function()
			return nil
		end, function()
			local tooltipLines = QuestTogether:GetStructuredQuestObjectiveTooltipLines("nameplate1", unitGuid, "unit")
			AssertEquals(type(tooltipLines), "table")
			AssertEquals(#tooltipLines, 2)
			AssertEquals(tooltipLines[1].leftText, "Tracking the Trail")
			AssertEquals(tooltipLines[2].leftText, "1/8 Digested Object")
		end)
	end)
end)

QuestTogether:RegisterTest("structured-tooltip clients fall back from unit payloads to hyperlink payloads", function()
	local unitGuid = "Creature-0-0-0-0-12345-0000000000"
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"

	QuestTogether.API = CreateApiWithOverrides({
		IsWorldMapVisible = function()
			return false
		end,
		GetTooltipDataForUnit = function(unitToken)
			AssertEquals(unitToken, "nameplate1")
			return nil
		end,
		GetTooltipDataForHyperlink = function(hyperlink)
			AssertEquals(hyperlink, "unit:" .. unitGuid)
			return {
				lines = {
					{
						type = titleLineType,
						leftText = "Tracking the Trail",
					},
					{
						type = objectiveLineType,
						leftText = "1/8 Digested Object",
					},
				},
			}
		end,
	})
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		local tooltipLines = QuestTogether:GetQuestObjectiveTooltipLines("nameplate1", unitGuid)
		AssertEquals(type(tooltipLines), "table")
		AssertEquals(#tooltipLines, 2)
		AssertEquals(tooltipLines[1].leftText, "Tracking the Trail")
		AssertEquals(tooltipLines[2].leftText, "1/8 Digested Object")
	end)
end)

QuestTogether:RegisterTest("tooltip quest detection prefers Questie lines before Blizzard tooltip APIs", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateTooltipScanGuid", function()
				return "Creature-0-0-0-0-12345-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "GetQuestieQuestObjectiveTooltipLines", function(_, unitGuid)
					AssertEquals(unitGuid, "Creature-0-0-0-0-12345-0000000000")
					return {
						{
							type = titleLineType,
							leftText = "Tracking the Trail",
						},
						{
							leftText = "1/8 Digested Object",
						},
					}
				end, function()
					WithPatchedMethod(QuestTogether, "GetStructuredQuestObjectiveTooltipLines", function()
						error("structured tooltip fallback should not run when Questie data is available")
					end, function()
						WithPatchedMethod(QuestTogether, "GetHiddenQuestObjectiveTooltipLines", function()
							error("hidden tooltip fallback should not run when Questie data is available")
						end, function()
							AssertTrue(QuestTogether:IsQuestObjectiveViaTooltip("nameplate1", {}))
						end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("structured tooltip clients keep the hidden tooltip fallback available", function()
	QuestTogether.API = CreateApiWithOverrides()
	AssertTrue(QuestTogether:IsNameplateTooltipScanEnabled())
end)

QuestTogether:RegisterTest("hidden tooltip fallback stays enabled when structured tooltip APIs are unavailable", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetTooltipDataForHyperlink = false,
		GetTooltipDataForUnit = false,
	})
	AssertTrue(QuestTogether:IsNameplateTooltipScanEnabled())
end)

QuestTogether:RegisterTest("nameplate quest text cache uses quest log titles without reading map task arrays", function()
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return false
		end,
		GetPlayerMapID = function(unitToken)
			error("map task text cache reads should stay disabled for Blizzard map safety")
		end,
		GetTaskQuestsOnMap = function(mapID)
			error("map task text cache reads should stay disabled for Blizzard map safety")
		end,
		GetTaskQuestTitle = function(questID)
			error("map task text cache reads should stay disabled for Blizzard map safety")
		end,
	})
	local snapshotState = QuestTogether:GetQuestSnapshotStateStore()
	snapshotState.byQuestID = {
		[10101] = {
			questID = 10101,
			title = "Log Quest",
			isHeader = false,
			isHidden = false,
		},
	}
	snapshotState.order = { 10101 }

	WithPatchedMethod(QuestTogether, "GetActiveWorldQuestAreaSnapshot", function()
		error("area snapshot fallback is not part of Plater's quest cache")
	end, function()
		WithPatchedMethod(QuestTogether, "GetQuestTitle", function()
			error("quest-title fallback is not part of Plater's world quest cache")
		end, function()
			QuestTogether:RebuildNameplateQuestTextCache()
		end)
	end)

	AssertTrue(QuestTogether.nameplateQuestTextCache["Log Quest"])
	AssertEquals(QuestTogether.nameplateQuestTextCache["Tracked Quest"], nil)
	AssertEquals(QuestTogether.nameplateQuestTextCache["Bonus Objective"], nil)
end)

QuestTogether:RegisterTest("nameplate quest text cache includes hidden quest log titles like Plater", function()
	local snapshotState = QuestTogether:GetQuestSnapshotStateStore()
	snapshotState.byQuestID = {
		[20202] = {
			questID = 20202,
			title = "Hidden Quest",
			isHeader = false,
			isHidden = true,
		},
	}
	snapshotState.order = { 20202 }
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return false
		end,
	})

	QuestTogether:RebuildNameplateQuestTextCache()

	AssertTrue(QuestTogether.nameplateQuestTextCache["Hidden Quest"])
end)

QuestTogether:RegisterTest("nameplate quest text cache includes live unfinished objective texts", function()
	local snapshotState = QuestTogether:GetQuestSnapshotStateStore()
	local tracker = QuestTogether:GetPlayerTracker()
	wipe(tracker)
	snapshotState.byQuestID = {
		[30303] = {
			questID = 30303,
			title = "QT Live Objective Cache Test",
			questLogIndex = 7,
			isHeader = false,
			isHidden = false,
		},
	}
	snapshotState.order = { 30303 }
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return false
		end,
		GetQuestLogInfo = function(questLogIndex)
			AssertEquals(questLogIndex, 7)
			return snapshotState.byQuestID[30303]
		end,
		GetNumQuestLeaderBoards = function(questLogIndex)
			AssertEquals(questLogIndex, 7)
			return 2
		end,
		GetQuestObjectiveInfo = function(questID, objectiveIndex, displayComplete)
			AssertEquals(questID, 30303)
			AssertEquals(displayComplete, false)
			if objectiveIndex == 1 then
				return "QT unfinished objective sentinel", "monster", false, 0
			end
			return "QT finished objective sentinel", "event", true, 1
		end,
	})

	QuestTogether:RebuildNameplateQuestTextCache()

	AssertTrue(QuestTogether.nameplateQuestTextCache["QT Live Objective Cache Test"])
	AssertTrue(QuestTogether.nameplateQuestTextCache["QT unfinished objective sentinel"])
	AssertEquals(QuestTogether.nameplateQuestTextCache["QT finished objective sentinel"], nil)
end)

QuestTogether:RegisterTest("nameplate quest text cache normalizes live progressbar objective texts", function()
	local snapshotState = QuestTogether:GetQuestSnapshotStateStore()
	local tracker = QuestTogether:GetPlayerTracker()
	wipe(tracker)
	snapshotState.byQuestID = {
		[40404] = {
			questID = 40404,
			title = "Step Into the Life",
			isHeader = false,
			isHidden = false,
		},
	}
	snapshotState.order = { 40404 }
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return false
		end,
		GetQuestLogIndexForQuestID = function(questID)
			AssertEquals(questID, 40404)
			return 9
		end,
		GetNumQuestLeaderBoards = function(questLogIndex)
			AssertEquals(questLogIndex, 9)
			return 1
		end,
		GetQuestObjectiveInfo = function(questID, objectiveIndex, displayComplete)
			AssertEquals(questID, 40404)
			AssertEquals(objectiveIndex, 1)
			AssertEquals(displayComplete, false)
			return "Emerald Dreamway cleared (28%)", "progressbar", false, nil
		end,
		GetQuestProgressBarPercent = function(questID)
			AssertEquals(questID, 40404)
			return 28
		end,
	})

	QuestTogether:RebuildNameplateQuestTextCache()

	AssertTrue(QuestTogether.nameplateQuestTextCache["Step Into the Life"])
	AssertTrue(QuestTogether.nameplateQuestTextCache["28% Emerald Dreamway cleared"])
	AssertTrue(QuestTogether.nameplateQuestTextCache["Emerald Dreamway cleared"])
end)

QuestTogether:RegisterTest("nameplate quest text cache stays empty in instances", function()
	QuestTogether.nameplateQuestTextCache["Stale Quest"] = true
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return true
		end,
		GetNumQuestLogEntries = function()
			error("quest log should not be read while in an instance")
		end,
	})

	QuestTogether:RebuildNameplateQuestTextCache()

	AssertEquals(QuestTogether.nameplateQuestTextCache["Stale Quest"], nil)
end)

QuestTogether:RegisterTest("nameplate quest text cache includes active tracked objective texts", function()
	local tracker = QuestTogether:GetPlayerTracker()
	tracker[30303] = {
		title = "Old War Grudge",
		objectives = {
			"In War Mode obtain Hardin Steellock's Head",
		},
		isComplete = false,
		isReadyForTurnIn = false,
	}
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return false
		end,
	})

	QuestTogether:RebuildNameplateQuestTextCache()

	AssertTrue(QuestTogether.nameplateQuestTextCache["Old War Grudge"])
	AssertTrue(QuestTogether.nameplateQuestTextCache["In War Mode obtain Hardin Steellock's Head"])
end)

QuestTogether:RegisterTest("structured tooltip extraction surfaces args text when leftText is missing", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	local tooltipLines = QuestTogether:ExtractQuestObjectiveTooltipLinesFromTooltipData({
		lines = {
			{
				type = titleLineType,
				args = {
					{
						field = "leftText",
						stringVal = "Tracking the Trail",
					},
				},
			},
			{
				type = objectiveLineType,
				args = {
					{
						field = "leftText",
						stringVal = "1/8 Digested Object",
					},
				},
			},
		},
	})

	AssertEquals(type(tooltipLines), "table")
	AssertEquals(#tooltipLines, 2)
	AssertEquals(tooltipLines[1].leftText, "Tracking the Trail")
	AssertEquals(tooltipLines[2].leftText, "1/8 Digested Object")
	AssertTrue(QuestTogether:EvaluateTooltipQuestObjectiveLines(tooltipLines))
end)

QuestTogether:RegisterTest("structured tooltip extraction surfaces tooltip args through the API helper", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	local tooltipData = {
		lines = {
			{
				type = titleLineType,
				args = {},
			},
			{
				type = objectiveLineType,
				args = {},
			},
		},
	}
	QuestTogether.API = CreateApiWithOverrides({
		SurfaceTooltipDataArgs = function(candidateTooltipData)
			AssertEquals(candidateTooltipData, tooltipData)
			candidateTooltipData.lines[1].leftText = "Tracking the Trail"
			candidateTooltipData.lines[2].leftText = "1/8 Digested Object"
			return candidateTooltipData
		end,
	})

	local tooltipLines = QuestTogether:ExtractQuestObjectiveTooltipLinesFromTooltipData(tooltipData)

	AssertEquals(type(tooltipLines), "table")
	AssertEquals(#tooltipLines, 2)
	AssertEquals(tooltipLines[1].leftText, "Tracking the Trail")
	AssertEquals(tooltipLines[2].leftText, "1/8 Digested Object")
	AssertTrue(QuestTogether:EvaluateTooltipQuestObjectiveLines(tooltipLines))
end)

QuestTogether:RegisterTest("announcement refresh discards stopped addon-owned playback state without replay", function()
	local hidden, shows = false, 0
	local unitFrame = {}
	local bubble = {
		SetAlpha = function() end,
		Hide = function() hidden = true end,
	}
	local host = { UnitFrame = unitFrame }
	QuestTogether.isEnabled = true
	QuestTogether.announcementBubbleScreenHostFrame = host
	QuestTogether.nameplateBubbleByUnitFrame[unitFrame] = bubble
	QuestTogether.nameplateBubbleStateByFrame[bubble] = {
		unitToken = "player", text = "Quest Completed: Widgets", eventType = "QUEST_COMPLETED",
	}
	WithPatchedMethod(QuestTogether, "GetAnnouncementBubbleHostFrameForUnit", function() return host end, function()
		WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnNameplate", function() shows = shows + 1 end, function()
			QuestTogether:RefreshActiveAnnouncementBubbles()
		end)
	end)
	AssertTrue(hidden)
	AssertEquals(shows, 0)
	AssertEquals(QuestTogether.nameplateBubbleStateByFrame[bubble], nil)
	AssertEquals(bubble.qtCurrentText, nil)
	AssertEquals(bubble.qtHostFrame, nil)
end)

QuestTogether:RegisterTest("tooltip objective evaluation accepts party-member progress lines within matched quest blocks", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	local playerLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestPlayer or "QuestPlayer"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = titleLineType,
			leftText = "Tracking the Trail",
		},
		{
			type = objectiveLineType,
			leftText = "0/8 Digested Object",
		},
		{
			type = playerLineType,
			leftText = "Friend-Realm",
		},
		{
			type = objectiveLineType,
			leftText = "3/8 Digested Object",
		},
	})

	AssertTrue(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation accepts normalized string line types inside matched quest blocks", function()
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = "QuestTitle",
			leftText = "Tracking the Trail",
		},
		{
			type = "QuestPlayer",
			leftText = "Friend-Realm",
		},
		{
			type = "QuestObjective",
			leftText = "3/8 Digested Object",
		},
	})

	AssertTrue(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation ignores complete-only objective blocks", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	local playerLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestPlayer or "QuestPlayer"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = titleLineType,
			leftText = "Tracking the Trail",
		},
		{
			type = objectiveLineType,
			leftText = "8/8 Digested Object",
		},
		{
			type = playerLineType,
			leftText = "Friend-Realm",
		},
		{
			type = objectiveLineType,
			leftText = "8/8 Digested Object",
		},
	})

	AssertFalse(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation ignores quest-title-only lines", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = titleLineType,
			leftText = "Tracking the Trail",
		},
	})

	AssertFalse(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation requires matched known quest text before progress", function()
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = objectiveLineType,
			leftText = "0/8 Digested Object",
		},
	})

	AssertFalse(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation accepts standalone tracked objective lines", function()
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	QuestTogether.nameplateQuestTextCache["In War Mode obtain Hardin Steellock's Head"] = true

	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = objectiveLineType,
			leftText = "0/1 In War Mode obtain Hardin Steellock's Head",
		},
	})

	AssertTrue(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation ignores complete standalone tracked objective lines", function()
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	QuestTogether.nameplateQuestTextCache["In War Mode obtain Hardin Steellock's Head"] = true

	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = objectiveLineType,
			leftText = "1/1 In War Mode obtain Hardin Steellock's Head",
		},
	})

	AssertFalse(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation ignores unmatched quest title blocks", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = titleLineType,
			leftText = "A Different Quest",
		},
		{
			type = objectiveLineType,
			leftText = "0/8 Digested Object",
		},
	})

	AssertFalse(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation stops at threat marker", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
		{
			type = titleLineType,
			leftText = "Tracking the Trail",
		},
		{
			type = objectiveLineType,
			leftText = THREAT_TOOLTIP or "Threat",
		},
		{
			type = objectiveLineType,
			leftText = "0/8 Digested Object",
		},
	})

	AssertFalse(hasObjective)
end)

QuestTogether:RegisterTest("tooltip objective evaluation stops when tooltip line metadata is secret", function()
	local titleLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
	local objectiveLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
	local secretLine = {}
	setmetatable(secretLine, {
		__index = function()
			error("secret line should not be indexed")
		end,
	})
	QuestTogether.nameplateQuestTextCache["Tracking the Trail"] = true

	WithPatchedMethod(QuestTogether, "IsSecretValue", function(_, value)
		return value == secretLine
	end, function()
		local hasObjective = QuestTogether:EvaluateTooltipQuestObjectiveLines({
			secretLine,
			{
				type = titleLineType,
				leftText = "Tracking the Trail",
			},
			{
				type = objectiveLineType,
				leftText = "1/2 Should Never Be Read",
			},
		})
		AssertFalse(hasObjective)
	end)
end)

QuestTogether:RegisterTest("tooltip quest scan guid does not fall back to stale token cache state", function()
	QuestTogether.nameplateTooltipGuidByUnitToken = {
		nameplate1 = "Creature-0-0-0-0-11111-0000000000",
	}

	WithPatchedMethod(QuestTogether, "GetNameplateUnitGuid", function()
		return nil
	end, function()
		AssertEquals(QuestTogether:GetNameplateTooltipScanGuid("nameplate1", {}), nil)
	end)
end)

QuestTogether:RegisterTest("personal bubble anchor persists per character and resets to defaults", function()
	WithPatchedMethod(QuestTogether, "GetPlayerFullName", function()
		return "MyPlayer-Realm"
	end, function()
		local defaults = QuestTogether.DEFAULT_PERSONAL_BUBBLE_ANCHOR
		local initialAnchor = QuestTogether:GetPersonalBubbleAnchor()
		AssertEquals(initialAnchor.point, defaults.point)
		AssertEquals(initialAnchor.relativePoint, defaults.relativePoint)
		AssertEquals(initialAnchor.x, defaults.x)
		AssertEquals(initialAnchor.y, defaults.y)

		AssertTrue(QuestTogether:SetPersonalBubbleAnchor("TOP", "TOP", 10, -25))

		local savedAnchor = QuestTogether:GetPersonalBubbleAnchor()
		AssertEquals(savedAnchor.point, "TOP")
		AssertEquals(savedAnchor.relativePoint, "TOP")
		AssertEquals(savedAnchor.x, 10)
		AssertEquals(savedAnchor.y, -25)

		AssertTrue(QuestTogether:ResetPersonalBubbleAnchor())

		local resetAnchor = QuestTogether:GetPersonalBubbleAnchor()
		AssertEquals(resetAnchor.point, defaults.point)
		AssertEquals(resetAnchor.relativePoint, defaults.relativePoint)
		AssertEquals(resetAnchor.x, defaults.x)
		AssertEquals(resetAnchor.y, defaults.y)
	end)
end)

QuestTogether:RegisterTest("announcement bubbles use their own context policy instead of quest-nameplate instance policy", function()
	local delegated = 0

	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "IsAnnouncementBubbleAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "TryShowAnnouncementBubbleOnUnitNameplate", function(_, unitToken, text, eventType, iconAsset, iconKind)
				delegated = delegated + 1
				AssertEquals(unitToken, "player")
				AssertEquals(text, "Test bubble")
				AssertEquals(eventType, "QUEST_PROGRESS")
				AssertEquals(iconAsset, "Interface\\Icons\\INV_Misc_QuestionMark")
				AssertEquals(iconKind, "texture")
				return true, "player"
			end, function()
				local ok, unitName = QuestTogether:ShowAnnouncementBubbleOnUnitNameplate(
					"player",
					"Test bubble",
					"QUEST_PROGRESS",
					"Interface\\Icons\\INV_Misc_QuestionMark",
					"texture"
				)
				AssertTrue(ok)
				AssertEquals(unitName, "player")
			end)
		end)
	end)

	AssertEquals(delegated, 1)
end)

QuestTogether:RegisterTest("announcement bubbles can still be blocked by their own context policy", function()
	local delegated = 0

	WithPatchedMethod(QuestTogether, "IsAnnouncementBubbleAugmentationBlockedInCurrentContext", function()
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "TryShowAnnouncementBubbleOnUnitNameplate", function()
			delegated = delegated + 1
			return true, "player"
		end, function()
			local ok, reason = QuestTogether:ShowAnnouncementBubbleOnUnitNameplate("player", "Test bubble")
			AssertFalse(ok)
			AssertEquals(reason, "Announcement bubbles are unavailable in the current context.")
		end)
	end)

	AssertEquals(delegated, 0)
end)

QuestTogether:RegisterTest("nearby bubbles honor runtime restrictions while personal bubbles remain addon-owned", function()
	WithPatchedMethod(QuestTogether, "IsWorkBlocked", function(_, workClass)
		AssertEquals(workClass, "foreign_frame_mutation")
		return true
	end, function()
		AssertTrue(QuestTogether:IsAnnouncementBubbleAugmentationBlockedInCurrentContext("nameplate1"))
		AssertFalse(QuestTogether:IsAnnouncementBubbleAugmentationBlockedInCurrentContext("player"))
	end)
end)

QuestTogether:RegisterTest("personal bubble host construction waits until runtime restrictions end", function()
	QuestTogether.announcementBubbleScreenHostFrame = nil
	WithPatchedMethod(QuestTogether, "IsRuntimeRestricted", function()
		return true
	end, function()
		AssertEquals(QuestTogether:GetAnnouncementBubbleHostFrameForUnit("player"), nil)
	end)
	AssertEquals(QuestTogether.announcementBubbleScreenHostFrame, nil)
end)

QuestTogether:RegisterTest("nameplate capability notice reports quest plates unavailable while quest bubbles remain available in scenario-like instances", function()
	QuestTogether.isEnabled = true
	QuestTogether.db.profile.nameplateQuestIconEnabled = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.hideMyOwnChatBubbles = false
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return true
		end,
		GetInstanceInfo = function()
			return {
				instanceType = "scenario",
			}
		end,
	})

	local report = QuestTogether:GetNameplateCapabilityNoticeReport()

	AssertTrue(report ~= nil)
	AssertEquals(report.header, "QuestTogether detects limited functionality in the current instance.")
	AssertEquals(#report.lines, 3)
	AssertEquals(report.lines[1], "|cffffd200Quest Plates: |r|cffff4444unavailable|r")
	AssertEquals(report.lines[2], "|cffffd200Personal Announcement Bubbles: |r|cff33ff99available|r")
	AssertEquals(report.lines[3], "|cffffd200Nearby-Player Announcement Bubbles: |r|cff33ff99available|r")
	AssertEquals(
		report.key,
		"QuestTogether detects limited functionality in the current instance.\n"
			.. "Quest Plates: unavailable\n"
			.. "Personal Announcement Bubbles: available\n"
			.. "Nearby-Player Announcement Bubbles: available"
	)
end)

QuestTogether:RegisterTest("nameplate capability notice reports group-instance bubble limits separately from quest plates", function()
	QuestTogether.isEnabled = true
	QuestTogether.db.profile.nameplateQuestIconEnabled = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.hideMyOwnChatBubbles = false
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return true
		end,
		GetInstanceInfo = function()
			return {
				instanceType = "party",
			}
		end,
	})

	local report = QuestTogether:GetNameplateCapabilityNoticeReport()

	AssertTrue(report ~= nil)
	AssertEquals(report.header, "QuestTogether detects limited functionality in the current instance.")
	AssertEquals(#report.lines, 3)
	AssertEquals(report.lines[1], "|cffffd200Quest Plates: |r|cffff4444unavailable|r")
	AssertEquals(report.lines[2], "|cffffd200Personal Announcement Bubbles: |r|cff33ff99available|r")
	AssertEquals(report.lines[3], "|cffffd200Nearby-Player Announcement Bubbles: |r|cffff4444unavailable|r")
	AssertEquals(
		report.key,
		"QuestTogether detects limited functionality in the current instance.\n"
			.. "Quest Plates: unavailable\n"
			.. "Personal Announcement Bubbles: available\n"
			.. "Nearby-Player Announcement Bubbles: unavailable"
	)
end)

QuestTogether:RegisterTest("nameplate capability report ignores features disabled by user options", function()
	QuestTogether.isEnabled = true
	QuestTogether.db.profile.nameplateQuestIconEnabled = false
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.hideMyOwnChatBubbles = true
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return true
		end,
		GetInstanceInfo = function()
			return {
				instanceType = "party",
			}
		end,
	})

	local report = QuestTogether:GetNameplateCapabilityNoticeReport()

	AssertTrue(report ~= nil)
	AssertEquals(report.header, "QuestTogether detects limited functionality in the current instance.")
	AssertEquals(#report.lines, 1)
	AssertEquals(report.lines[1], "|cffffd200Nearby-Player Announcement Bubbles: |r|cffff4444unavailable|r")
end)

QuestTogether:RegisterTest("nameplate capability report returns full availability status when enabled features are available", function()
	QuestTogether.isEnabled = true
	QuestTogether.db.profile.nameplateQuestIconEnabled = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.hideMyOwnChatBubbles = false
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return false
		end,
		GetInstanceInfo = function()
			return {
				instanceType = "",
			}
		end,
	})

	local report = QuestTogether:GetNameplateCapabilityNoticeReport()

	AssertTrue(report ~= nil)
	AssertEquals(report.mode, "full")
	AssertEquals(report.header, "Full QuestTogether functionality is available again.")
	AssertEquals(#report.lines, 3)
	AssertEquals(report.lines[1], "|cffffd200Quest Plates: |r|cff33ff99available|r")
	AssertEquals(report.lines[2], "|cffffd200Personal Announcement Bubbles: |r|cff33ff99available|r")
	AssertEquals(report.lines[3], "|cffffd200Nearby-Player Announcement Bubbles: |r|cff33ff99available|r")
	AssertEquals(
		report.key,
		"Full QuestTogether functionality is available again.\n"
			.. "Quest Plates: available\n"
			.. "Personal Announcement Bubbles: available\n"
			.. "Nearby-Player Announcement Bubbles: available"
	)
end)

QuestTogether:RegisterTest("nameplate capability notices are one-shot per blocked context and reset when availability returns", function()
	local warnings = {}
	local warningDetails = {}
	local infos = {}
	local infoDetails = {}

	QuestTogether.isEnabled = true
	QuestTogether.db.profile.nameplateQuestIconEnabled = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.hideMyOwnChatBubbles = false
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstance = function()
			return true
		end,
		GetInstanceInfo = function()
			return {
				instanceType = "scenario",
			}
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintChatLogSystemMessage", function(_, message)
		warnings[#warnings + 1] = message
	end, function()
		WithPatchedMethod(QuestTogether, "PrintChatLogWarningMessage", function(_, message)
			warnings[#warnings + 1] = message
		end, function()
			WithPatchedMethod(QuestTogether, "PrintChatLogWarningDetailMessage", function(_, message)
				warningDetails[#warningDetails + 1] = message
				return true
			end, function()
				WithPatchedMethod(QuestTogether, "PrintChatLogInfoMessage", function(_, message)
					infos[#infos + 1] = message
				end, function()
					WithPatchedMethod(QuestTogether, "PrintChatLogInfoDetailMessage", function(_, message)
						infoDetails[#infoDetails + 1] = message
						return true
					end, function()
						WithPatchedMethod(QuestTogether, "ForEachVisibleNamePlate", function() end, function()
							WithPatchedMethod(QuestTogether, "RefreshActiveAnnouncementBubbles", function() end, function()
								QuestTogether:RefreshNameplateAugmentation()
								QuestTogether:RefreshNameplateAugmentation()

								QuestTogether.API = CreateApiWithOverrides({
									IsInInstance = function()
										return false
									end,
									GetInstanceInfo = function()
										return {
											instanceType = "",
										}
									end,
								})
								QuestTogether:RefreshNameplateAugmentation()

								QuestTogether.API = CreateApiWithOverrides({
									IsInInstance = function()
										return true
									end,
									GetInstanceInfo = function()
										return {
											instanceType = "scenario",
										}
									end,
								})
								QuestTogether:RefreshNameplateAugmentation()
							end)
						end)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(#warnings, 2)
	AssertEquals(#warningDetails, 6)
	AssertEquals(#infos, 1)
	AssertEquals(#infoDetails, 3)
	AssertEquals(
		warnings[1],
		"QuestTogether detects limited functionality in the current instance."
	)
	AssertEquals(warnings[2], warnings[1])
	AssertEquals(warningDetails[1], "|cffffd200Quest Plates: |r|cffff4444unavailable|r")
	AssertEquals(warningDetails[2], "|cffffd200Personal Announcement Bubbles: |r|cff33ff99available|r")
	AssertEquals(warningDetails[3], "|cffffd200Nearby-Player Announcement Bubbles: |r|cff33ff99available|r")
	AssertEquals(warningDetails[4], warningDetails[1])
	AssertEquals(warningDetails[5], warningDetails[2])
	AssertEquals(warningDetails[6], warningDetails[3])
	AssertEquals(infos[1], "Full QuestTogether functionality is available again.")
	AssertEquals(infoDetails[1], "|cffffd200Quest Plates: |r|cff33ff99available|r")
	AssertEquals(infoDetails[2], "|cffffd200Personal Announcement Bubbles: |r|cff33ff99available|r")
	AssertEquals(infoDetails[3], "|cffffd200Nearby-Player Announcement Bubbles: |r|cff33ff99available|r")
end)

QuestTogether:RegisterTest("chat log warning message uses warning styling", function()
	local printed = {}
	local expectedIcon = QuestTogether:GetQuestIconChatTag(14)

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	QuestTogether:PrintChatLogWarningMessage("Quest plates are unavailable here.")

	AssertEquals(#printed, 1)
	AssertEquals(
		printed[1],
		expectedIcon .. "|cffff8800Warning:|r |cffffd200Quest plates are unavailable here.|r"
	)
end)

QuestTogether:RegisterTest("chat log warning detail message uses report styling", function()
	local printed = {}

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	QuestTogether:PrintChatLogWarningDetailMessage("|cffffd200Quest Plates: |r|cffff4444unavailable|r")

	AssertEquals(#printed, 1)
	AssertEquals(
		printed[1],
		"|cffff8800 - |r|cffffd200Quest Plates: |r|cffff4444unavailable|r"
	)
end)

QuestTogether:RegisterTest("chat log info message uses info styling", function()
	local printed = {}
	local expectedIcon = QuestTogether:GetQuestIconChatTag(14)

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	QuestTogether:PrintChatLogInfoMessage("Full QuestTogether functionality is available again.")

	AssertEquals(#printed, 1)
	AssertEquals(
		printed[1],
		expectedIcon .. "|cff33ff99Info:|r |cffffd200Full QuestTogether functionality is available again.|r"
	)
end)

QuestTogether:RegisterTest("chat log info detail message uses report styling", function()
	local printed = {}

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	QuestTogether:PrintChatLogInfoDetailMessage("|cffffd200Quest Plates: |r|cff33ff99available|r")

	AssertEquals(#printed, 1)
	AssertEquals(
		printed[1],
		"|cff33ff99 - |r|cffffd200Quest Plates: |r|cff33ff99available|r"
	)
end)

QuestTogether:RegisterTest("console announcement message includes icon and player name", function()
	local message = QuestTogether:BuildConsoleAnnouncementMessage("MyPlayer-Realm", "hello there", "MAGE")
	AssertTrue(string.find(message, "|T" .. QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE, 1, true) ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
	AssertTrue(string.find(message, "|cffffd200: hello there|r", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("chat log speaker link handler opens QuestTogether menu", function()
	local capturedOwner = nil
	local capturedSpeaker = nil

	WithPatchedMethod(QuestTogether, "ShowChatLogSpeakerMenu", function(_, ownerFrame, speakerName)
		capturedOwner = ownerFrame
		capturedSpeaker = speakerName
		return true
	end, function()
		local response = QuestTogether:HandleChatLogSpeakerLink(
			nil,
			nil,
			{ options = "MyPlayer-Realm" },
			{ frame = "ChatFrame1" }
		)
		AssertEquals(response, LinkProcessorResponse.Handled)
	end)

	AssertEquals(capturedOwner, "ChatFrame1")
	AssertEquals(capturedSpeaker, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log quest link handler prints local quest status", function()
	local printed = {}
	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
		IsQuestReadyForTurnIn = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 12345)
			return 7
		end,
		IsOnQuest = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		IsQuestComplete = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		IsPushableQuest = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
	})

	WithPatchedMethod(QuestTogether, "GetQuestTitle", function(_, questId)
		AssertEquals(questId, 12345)
		return "Test Quest"
	end, function()
		local response = QuestTogether:HandleChatLogQuestLink(
			nil,
			nil,
			{ options = "12345" },
			{ frame = "ChatFrame1" }
		)
		AssertEquals(response, LinkProcessorResponse.Handled)
	end)

	AssertEquals(#printed, 1)
	AssertTrue(string.find(printed[1] or "", "Test Quest", 1, true) ~= nil)
	AssertTrue(string.find(printed[1] or "", "Ready to Turn In", 1, true) ~= nil)
	AssertTrue(string.find(printed[1] or "", "Quest Status:", 1, true) ~= nil)
	AssertTrue(string.find(printed[1] or "", "Shareable: Yes", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("chat log quest link handler falls back to clicked quest title text", function()
	local printed = {}
	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
		IsQuestReadyForTurnIn = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 28831)
			return nil
		end,
		IsOnQuest = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
		IsQuestComplete = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
		IsPushableQuest = function(questId)
			AssertEquals(questId, 28831)
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "GetQuestTitle", function(_, questId)
		AssertEquals(questId, 28831)
		return "Quest 28831"
	end, function()
		local response = QuestTogether:HandleChatLogQuestLink(
			nil,
			"[Damn You, Frostilicus]",
			{ options = "28831" },
			{ frame = "ChatFrame1" }
		)
		AssertEquals(response, LinkProcessorResponse.Handled)
	end)

	AssertEquals(#printed, 1)
	AssertTrue(string.find(printed[1] or "", "Damn You, Frostilicus", 1, true) ~= nil)
	AssertFalse(string.find(printed[1] or "", "Quest 28831", 1, true) ~= nil)
	AssertTrue(string.find(printed[1] or "", "Not Started", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("chat log coord link handler opens ping waypoint", function()
	local opened = nil
	WithPatchedMethod(QuestTogether, "OpenPingWaypoint", function(_, mapID, coordX, coordY)
		opened = { mapID = mapID, coordX = coordX, coordY = coordY }
		return true
	end, function()
		local response = QuestTogether:HandleChatLogCoordLink(
			nil,
			nil,
			{ options = "999:47.1:69.9" },
			{ frame = "ChatFrame1" }
		)
		AssertEquals(response, LinkProcessorResponse.Handled)
	end)

	AssertEquals(opened.mapID, "999")
	AssertEquals(opened.coordX, "47.1")
	AssertEquals(opened.coordY, "69.9")
end)

QuestTogether:RegisterTest("open ping waypoint prefers TomTom and falls back to Blizzard waypoint", function()
	local calls = {}

	QuestTogether.API = CreateApiWithOverrides({
		IsAddOnLoaded = function(addonName)
			AssertEquals(addonName, "TomTom")
			return false
		end,
		CanSetUserWaypointOnMap = function(mapID)
			AssertEquals(mapID, 999)
			return true
		end,
		CreateUiMapPoint = function(mapID, x, y)
			calls[#calls + 1] = string.format("point:%d:%.3f:%.3f", mapID, x, y)
			return { mapID = mapID, x = x, y = y }
		end,
		SetUserWaypoint = function(point)
			calls[#calls + 1] = string.format("set:%d:%.3f:%.3f", point.mapID, point.x, point.y)
		end,
		SetSuperTrackedUserWaypoint = function(shouldTrack)
			calls[#calls + 1] = "track:" .. tostring(shouldTrack)
		end,
	})

	AssertTrue(QuestTogether:OpenPingWaypoint("999", "47.1", "69.9"))
	AssertEquals(calls[1], "point:999:0.471:0.699")
	AssertEquals(calls[2], "set:999:0.471:0.699")
	AssertEquals(calls[3], "track:true")
end)

QuestTogether:RegisterTest("ping response message includes addon version when available", function()
	local message = QuestTogether:BuildPingResponseMessage({
		senderName = "Remote-Realm",
		classFile = "MAGE",
		className = "Mage",
		level = "80",
		realmName = "Realm",
		addonVersion = "3.0.0",
	})

	AssertTrue(string.find(message, "Remote", 1, true) ~= nil)
	AssertTrue(string.find(message, "QT v3.0.0", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("player ping metadata includes addon version", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetAddOnMetadata = function(addonName, fieldName)
			AssertEquals(addonName, QuestTogether.addonName)
			AssertEquals(fieldName, "Version")
			return " 3.0.0 "
		end,
		UnitFullName = function()
			return "Local", "Realm"
		end,
		GetRealmName = function()
			return "Realm"
		end,
		UnitClass = function()
			return "Mage", "MAGE"
		end,
		UnitRace = function()
			return "Human"
		end,
		UnitLevel = function()
			return 80
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerFullName", function()
		return "Local-Realm"
	end, function()
		WithPatchedMethod(QuestTogether, "GetPlayerAnnouncementLocationInfo", function()
			return {}
		end, function()
			local metadata = QuestTogether:GetPlayerPingMetadata()
			AssertEquals(metadata.addonVersion, "3.0.0")
		end)
	end)
end)

QuestTogether:RegisterTest("ping response payload round trip preserves addon version", function()
	local payload = QuestTogether:EncodePingResponsePayload({
		requestId = "req-1",
		senderName = "Remote-Realm",
		realmName = "Realm",
		raceName = "Human",
		classFile = "MAGE",
		className = "Mage",
		level = "80",
		zoneName = "Stormwind",
		coordX = "12.3",
		coordY = "45.6",
		warMode = "0",
		mapID = "84",
		addonVersion = "3.0.0",
	})
	local decoded = QuestTogether:DecodePingResponsePayload(payload)

	AssertTrue(decoded ~= nil)
	AssertEquals(decoded.addonVersion, "3.0.0")
end)

QuestTogether:RegisterTest("announcement decode rejects nonnumeric version without raw tonumber fallback", function()
	WithPatchedMethod(QuestTogether, "SafeToNumber", function(_, value)
		AssertEquals(value, "secret")
		return nil
	end, function()
		AssertEquals(QuestTogether:DecodeAnnouncementPayload("secret,event,senderGuid,MAGE,Sender,text"), nil)
	end)
end)

QuestTogether:RegisterTest("quest compare done rejects invalid counts instead of completing an empty result", function()
	WithPatchedMethod(QuestTogether, "SafeToNumber", function(_, value)
		if value == "1" then
			return 1
		end
		if value == "secret" then
			return nil
		end
		return tonumber(value)
	end, function()
		local decoded = QuestTogether:DecodeQuestCompareDonePayload("1,req,Remote-Realm,secret")
		AssertEquals(decoded, nil)
	end)
end)

QuestTogether:RegisterTest("chat log speaker menu includes player actions", function()
	local titles = {}
	local buttons = {}
	local dividers = 0
	local fakeRoot = {
		CreateTitle = function(_, text)
			titles[#titles + 1] = text
		end,
		CreateButton = function(_, text, callback)
			buttons[#buttons + 1] = {
				text = text,
				callback = callback,
			}
		end,
		CreateDivider = function()
			dividers = dividers + 1
		end,
	}

	WithPatchedMethod(QuestTogether, "IsIgnoredPlayerName", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "GetOption", function(_, key)
			if key == "chatLogDestination" then
				return "main"
			end
			return QuestTogether.db.profile[key]
		end, function()
			QuestTogether:PopulateChatLogSpeakerMenu(fakeRoot, "ChatFrame1", "MyPlayer-Realm")
		end)
	end)

	AssertEquals(titles[1], "MyPlayer")
	AssertEquals(buttons[1].text, "Invite")
	AssertEquals(buttons[2].text, "Whisper")
	AssertEquals(buttons[3].text, "Add Friend")
	AssertEquals(buttons[4].text, "Ignore")
	AssertEquals(buttons[5].text, "Compare Quests")
	AssertEquals(buttons[6].text, "Move QuestTogether Logs to Separate Window")
	AssertEquals(dividers, 1)
end)

QuestTogether:RegisterTest("chat log speaker menu compare quests action uses full speaker name", function()
	local comparedName = nil
	WithPatchedMethod(QuestTogether, "RequestQuestCompare", function(_, speakerName)
		comparedName = speakerName
		return true
	end, function()
		AssertTrue(QuestTogether:CompareQuestsWithChatLogSpeaker("MyPlayer-Realm"))
	end)
	AssertEquals(comparedName, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log speaker menu invite action uses full speaker name", function()
	local invitedName = nil
	WithPatchedMethod(QuestTogether.API, "InviteUnit", function(name)
		invitedName = name
	end, function()
		AssertTrue(QuestTogether:InviteChatLogSpeaker("MyPlayer-Realm"))
	end)
	AssertEquals(invitedName, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log speaker menu whisper action uses owner frame", function()
	local whisperedName = nil
	local whisperedFrame = nil
	WithPatchedMethod(QuestTogether.API, "SendTell", function(name, chatFrame)
		whisperedName = name
		whisperedFrame = chatFrame
	end, function()
		AssertTrue(QuestTogether:WhisperChatLogSpeaker("MyPlayer-Realm", "ChatFrame9"))
	end)
	AssertEquals(whisperedName, "MyPlayer-Realm")
	AssertEquals(whisperedFrame, "ChatFrame9")
end)

QuestTogether:RegisterTest("chat log speaker menu add friend action uses full speaker name", function()
	local friendName = nil
	WithPatchedMethod(QuestTogether.API, "AddFriend", function(name)
		friendName = name
	end, function()
		AssertTrue(QuestTogether:AddFriendFromChatLogSpeaker("MyPlayer-Realm"))
	end)
	AssertEquals(friendName, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log speaker menu ignore action uses full speaker name", function()
	local ignoredName = nil
	WithPatchedMethod(QuestTogether.API, "AddOrDelIgnore", function(name)
		ignoredName = name
	end, function()
		AssertTrue(QuestTogether:ToggleIgnoreChatLogSpeaker("MyPlayer-Realm"))
	end)
	AssertEquals(ignoredName, "MyPlayer-Realm")
end)

QuestTogether:RegisterTest("chat log speaker menu shows unignore for ignored speaker", function()
	local buttons = {}
	local fakeRoot = {
		CreateTitle = function() end,
		CreateButton = function(_, text)
			buttons[#buttons + 1] = text
		end,
		CreateDivider = function() end,
	}

	WithPatchedMethod(QuestTogether, "IsIgnoredPlayerName", function(_, speakerName)
		AssertEquals(speakerName, "Ignored-Realm")
		return true
	end, function()
		QuestTogether:PopulateChatLogSpeakerMenu(fakeRoot, "ChatFrame1", "Ignored-Realm")
	end)

	AssertEquals(buttons[4], "Unignore")
end)

QuestTogether:RegisterTest("request quest compare sends compare request for remote speaker", function()
	local sent = {}
	local startedWith = nil
	local startedClass = nil

	QuestTogether.isEnabled = true
	QuestTogether.partyMembers = {
		["Remote-Realm"] = {
			fullName = "Remote-Realm",
			classFile = "DRUID",
		},
	}
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return false
		end,
		GetChannelName = function(channelName)
			AssertEquals(channelName, QuestTogether.announcementChannelName)
			return 9
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
		Delay = function() end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "LocalPlayer", "Realm"
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintQuestCompareStart", function(_, remoteName, classFile)
		startedWith = remoteName
		startedClass = classFile
	end, function()
		AssertTrue(QuestTogether:RequestQuestCompare("Remote-Realm"))
	end)

	AssertEquals(startedWith, "Remote-Realm")
	AssertEquals(startedClass, "DRUID")
	AssertEquals(#sent, 1)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "CHANNEL")
	AssertEquals(sent[1].target, 9)
	AssertTrue(string.find(sent[1].message, "^QCMP|", 1) ~= nil)
end)

QuestTogether:RegisterTest("quest compare entry prints local status and shareable state", function()
	local printed = {}
	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
		IsQuestReadyForTurnIn = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
		GetQuestLogIndexForQuestID = function(questId)
			AssertEquals(questId, 12345)
			return 4
		end,
		IsOnQuest = function(questId)
			AssertEquals(questId, 12345)
			return true
		end,
		IsQuestComplete = function(questId)
			AssertEquals(questId, 12345)
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintConsoleAnnouncement", function(_, message, targetName, classFile, eventType)
		printed[#printed + 1] = {
			message = message,
			targetName = targetName,
			classFile = classFile,
			eventType = eventType,
		}
	end, function()
		QuestTogether:PrintQuestCompareMessage("Remote-Realm", {
			questId = "12345",
			questTitle = "Test Quest",
			isComplete = true,
			isPushable = true,
		}, "WARRIOR")
	end)

	AssertEquals(#printed, 1)
	AssertEquals(printed[1].targetName, "Remote-Realm")
	AssertEquals(printed[1].classFile, "WARRIOR")
	AssertEquals(printed[1].eventType, "QUEST_COMPLETED")
	AssertTrue(string.find(printed[1].message, "Test Quest", 1, true) ~= nil)
	AssertTrue(string.find(printed[1].message, "Them: Complete", 1, true) ~= nil)
	AssertTrue(string.find(printed[1].message, "You: In Progress", 1, true) ~= nil)
	AssertTrue(string.find(printed[1].message, "Shareable to You: Yes", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("quest compare response prints entries and clears pending request on done", function()
	local printed = {}
	QuestTogether.pendingQuestCompareRequests = {
		["qcmp-123"] = {
			targetName = "Remote-Realm",
			classFile = nil,
			count = 0,
		},
	}

	QuestTogether.API = CreateApiWithOverrides({
		IsQuestFlaggedCompleted = function()
			return false
		end,
		IsQuestReadyForTurnIn = function()
			return false
		end,
		GetQuestLogIndexForQuestID = function()
			return nil
		end,
		IsOnQuest = function()
			return false
		end,
		IsQuestComplete = function()
			return false
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintConsoleAnnouncement", function(_, message, targetName, classFile, eventType)
		printed[#printed + 1] = {
			message = message,
			targetName = targetName,
			classFile = classFile,
			eventType = eventType,
		}
	end, function()
		AssertTrue(QuestTogether:HandleQuestCompareEntry({
			requestId = "qcmp-123",
			senderName = "Remote-Realm",
			classFile = "WARRIOR",
			questId = "12345",
			questTitle = "Remote Quest",
			isComplete = false,
			isPushable = false,
		}))
		AssertTrue(QuestTogether:HandleQuestCompareDone({
			requestId = "qcmp-123",
			senderName = "Remote-Realm",
			classFile = "",
			count = 1,
		}))
	end)

	AssertEquals(#printed, 2)
	AssertEquals(printed[1].targetName, "Remote-Realm")
	AssertEquals(printed[1].classFile, "WARRIOR")
	AssertEquals(printed[1].eventType, "QUEST_PROGRESS")
	AssertTrue(string.find(printed[1].message, "Remote Quest", 1, true) ~= nil)
	AssertEquals(printed[2].targetName, "Remote-Realm")
	AssertEquals(printed[2].classFile, "WARRIOR")
	AssertEquals(printed[2].eventType, "QUEST_COMPLETED")
	AssertTrue(string.find(printed[2].message, "Finished comparing quests", 1, true) ~= nil)
	AssertEquals(QuestTogether.pendingQuestCompareRequests["qcmp-123"], nil)
end)

QuestTogether:RegisterTest("world quest console announcement uses world quest icon", function()
	local message =
		QuestTogether:BuildConsoleAnnouncementMessage("MyPlayer-Realm", "entered the area", "MAGE", "WORLD_QUEST_ENTERED")
	AssertTrue(string.find(message, "|A:worldquest%-icon:14:14|a") ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
	AssertTrue(string.find(message, "|cffffd200: entered the area|r", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("bonus objective console announcement uses bonus objective icon", function()
	local message = QuestTogether:BuildConsoleAnnouncementMessage(
		"MyPlayer-Realm",
		"entered the area",
		"MAGE",
		"BONUS_OBJECTIVE_ENTERED"
	)
	AssertTrue(string.find(message, "|A:Bonus%-Objective%-Star:14:14|a") ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
	AssertTrue(string.find(message, "|cffffd200: entered the area|r", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("world quest announcement icon info prefers owned POI tag atlas", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestPoiTagType = function(questID)
			AssertEquals(questID, 12345)
			return Enum and Enum.QuestTagType and Enum.QuestTagType.Dungeon or 6
		end,
		GetQuestTagAtlas = function(tagID, worldQuestType)
			AssertEquals(tagID, nil)
			AssertEquals(worldQuestType, Enum and Enum.QuestTagType and Enum.QuestTagType.Dungeon or 6)
			return "worldquest-icon-dungeon"
		end,
	})

	local asset, kind = QuestTogether:GetAnnouncementIconInfo("WORLD_QUEST_PROGRESS", 12345)
	AssertEquals(asset, "worldquest-icon-dungeon")
	AssertEquals(kind, "atlas")
end)

QuestTogether:RegisterTest("world quest announcement icon info falls back to static atlas", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestPoiTagType = function()
			return nil
		end,
		GetQuestTagAtlas = function()
			return nil
		end,
	})

	local asset, kind = QuestTogether:GetAnnouncementIconInfo("WORLD_QUEST_PROGRESS", 12345)
	AssertEquals(asset, "worldquest-icon")
	AssertEquals(kind, "atlas")
end)

QuestTogether:RegisterTest("bonus objective announcement icon info prefers owned quest state icon fallback", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestClassification = function(questID)
			AssertEquals(questID, 54321)
			return Enum and Enum.QuestClassification and Enum.QuestClassification.Important or nil
		end,
		GetQuestFrequency = function(questID)
			AssertEquals(questID, 54321)
			return nil
		end,
	})

	local asset, kind = QuestTogether:GetAnnouncementIconInfo("BONUS_OBJECTIVE_PROGRESS", 54321)
	AssertEquals(asset, "importantInProgressquesticon")
	AssertEquals(kind, "atlas")
end)

QuestTogether:RegisterTest("bonus objective announcement icon info falls back to static atlas without quest id", function()
	local asset, kind = QuestTogether:GetAnnouncementIconInfo("BONUS_OBJECTIVE_PROGRESS", nil)
	AssertEquals(asset, "Bonus-Objective-Star")
	AssertEquals(kind, "atlas")
end)

QuestTogether:RegisterTest("quest accepted announcement icon info uses owned classification resolver", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestClassification = function(questID)
			AssertEquals(questID, 12345)
			return Enum and Enum.QuestClassification and Enum.QuestClassification.Campaign or nil
		end,
		GetQuestFrequency = function(questID)
			AssertEquals(questID, 12345)
			return nil
		end,
	})

	local asset, kind = QuestTogether:GetAnnouncementIconInfo("QUEST_ACCEPTED", 12345)
	AssertEquals(asset, "CampaignAvailableQuestIcon")
	AssertEquals(kind, "atlas")
end)

QuestTogether:RegisterTest("quest progress announcement icon info uses owned classification resolver", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestClassification = function(questID)
			AssertEquals(questID, 12345)
			return Enum and Enum.QuestClassification and Enum.QuestClassification.Important or nil
		end,
		GetQuestFrequency = function(questID)
			AssertEquals(questID, 12345)
			return nil
		end,
	})

	local asset, kind = QuestTogether:GetAnnouncementIconInfo("QUEST_PROGRESS", 12345)
	AssertEquals(asset, "importantInProgressquesticon")
	AssertEquals(kind, "atlas")
end)

QuestTogether:RegisterTest("quest completion announcement icon info uses owned classification resolver", function()
	QuestTogether.API = CreateApiWithOverrides({
		GetQuestClassification = function(questID)
			AssertEquals(questID, 12345)
			return Enum and Enum.QuestClassification and Enum.QuestClassification.Campaign or nil
		end,
		GetQuestFrequency = function(questID)
			AssertEquals(questID, 12345)
			return nil
		end,
	})

	local asset, kind = QuestTogether:GetAnnouncementIconInfo("QUEST_COMPLETED", 12345)
	AssertEquals(asset, "CampaignActiveQuestIcon")
	AssertEquals(kind, "atlas")
end)

QuestTogether:RegisterTest("console announcement uses sender provided quest icon asset", function()
	local message = QuestTogether:BuildConsoleAnnouncementMessage(
		"MyPlayer-Realm",
		"1/3 Objectives",
		"MAGE",
		"QUEST_PROGRESS",
		"CampaignInProgressQuestIcon",
		"atlas"
	)
	AssertTrue(string.find(message, "|A:CampaignInProgressQuestIcon:14:14|a") ~= nil)
	AssertTrue(string.find(message, "MyPlayer", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("dev log all announcements does not append location metadata to chat logs", function()
	QuestTogether.db.profile.devLogAllAnnouncements = true

	local message = QuestTogether:BuildConsoleAnnouncementMessage(
		"MyPlayer-Realm",
		"hello there",
		"MAGE",
		"QUEST_PROGRESS",
		nil,
		nil,
		{
			zoneName = "Silvermoon City",
			coordX = "45.2",
			coordY = "31.8",
			warMode = "1",
		}
	)

	AssertFalse(string.find(message, "Silvermoon City", 1, true) ~= nil)
	AssertFalse(string.find(message, "45.2, 31.8", 1, true) ~= nil)
	AssertFalse(string.find(message, "WM On", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("dev log all announcements omits missing war mode metadata", function()
	QuestTogether.db.profile.devLogAllAnnouncements = true

	local message = QuestTogether:BuildConsoleAnnouncementMessage(
		"MyPlayer-Realm",
		"hello there",
		"MAGE",
		"QUEST_PROGRESS",
		nil,
		nil,
		{
			zoneName = "",
			coordX = "",
			coordY = "",
			warMode = "",
		}
	)

	AssertFalse(string.find(message, "WM Off", 1, true) ~= nil)
	AssertFalse(string.find(message, " |cff999999[", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("local announcement event includes resolved icon metadata", function()
	QuestTogether.API = CreateApiWithOverrides({
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
		AssertEquals(eventType, "QUEST_PROGRESS")
		AssertEquals(questId, 12345)
		return "CampaignInProgressQuestIcon", "atlas"
	end, function()
		local eventData = QuestTogether:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "1/3 Objectives", 12345)
		AssertEquals(eventData.questId, "12345")
		AssertEquals(eventData.iconAsset, "CampaignInProgressQuestIcon")
		AssertEquals(eventData.iconKind, "atlas")
	end)
end)

QuestTogether:RegisterTest("local announcement event prefers provided icon metadata overrides", function()
	QuestTogether.API = CreateApiWithOverrides({
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
		AssertEquals(eventType, "QUEST_COMPLETED")
		AssertEquals(questId, 12345)
		return "QuestNormal", "texture"
	end, function()
		local eventData = QuestTogether:BuildLocalAnnouncementEvent("QUEST_COMPLETED", "Quest Completed: Test Quest", 12345, {
			iconAsset = "CampaignCompletedQuestIcon",
			iconKind = "atlas",
		})
		AssertEquals(eventData.iconAsset, "CampaignCompletedQuestIcon")
		AssertEquals(eventData.iconKind, "atlas")
	end)
end)

QuestTogether:RegisterTest("local announcement event ignores non primitive metadata overrides", function()
	QuestTogether.API = CreateApiWithOverrides({
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function(_, eventType, questId)
		AssertEquals(eventType, "QUEST_COMPLETED")
		AssertEquals(questId, 12345)
		return "QuestNormal", "texture"
	end, function()
		local eventData = QuestTogether:BuildLocalAnnouncementEvent("QUEST_COMPLETED", "Quest Completed: Test Quest", 12345, {
			iconAsset = {},
			iconKind = {},
			emoteToken = {},
		})
		AssertEquals(eventData.iconAsset, "QuestNormal")
		AssertEquals(eventData.iconKind, "texture")
		AssertEquals(eventData.emoteToken, "")
	end)
end)

QuestTogether:RegisterTest("announcement decode sanitizes invalid quest and location metadata", function()
	local decoded = QuestTogether:DecodeAnnouncementPayload(
		"3,QUEST_PROGRESS,Player-1-ABC,MAGE,Remote-Realm,1%2F3%20Objectives,badquest,CampaignCompletedQuestIcon,atlas,Stormwind,north,45.678,maybe,cheer"
	)

	AssertTrue(decoded ~= nil)
	AssertEquals(decoded.questId, "")
	AssertEquals(decoded.coordX, "")
	AssertEquals(decoded.coordY, "45.7")
	AssertEquals(decoded.warMode, "")
	AssertEquals(decoded.iconAsset, "CampaignCompletedQuestIcon")
	AssertEquals(decoded.iconKind, "atlas")
end)

QuestTogether:RegisterTest("local announcement event includes location metadata", function()
	QuestTogether.API = CreateApiWithOverrides({
		UnitGUID = function()
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerFullName", function()
		return "MyPlayer-Realm"
	end, function()
		WithPatchedMethod(QuestTogether, "GetAnnouncementIconInfo", function()
			return nil, nil
		end, function()
			WithPatchedMethod(QuestTogether, "GetPlayerAnnouncementLocationInfo", function()
				return {
					zoneName = "Eversong Woods",
					coordX = 12.3,
					coordY = 45.6,
					warMode = false,
				}
			end, function()
				local eventData = QuestTogether:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "1/3 Objectives", 12345)
				AssertEquals(eventData.zoneName, "Eversong Woods")
				AssertEquals(eventData.coordX, "12.3")
				AssertEquals(eventData.coordY, "45.6")
				AssertEquals(eventData.warMode, "0")
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("console announcements use separate QuestTogether chat frame when configured", function()
	local printedToFrame = {}
	local fallbackPrinted = {}
	local fakeFrame = {
		AddMessage = function(_, message)
			printedToFrame[#printedToFrame + 1] = message
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "separate"
	QuestTogether.PrintRaw = function(_, message)
		fallbackPrinted[#fallbackPrinted + 1] = message
	end

	WithPatchedMethod(QuestTogether, "EnsureQuestLogChatFrame", function()
		return fakeFrame, 3
	end, function()
		WithPatchedMethod(QuestTogether, "GetResolvedChatLogDestination", function()
			return "separate"
		end, function()
			QuestTogether:PrintConsoleAnnouncement("hello there", "MyPlayer-Realm", "MAGE")
		end)
	end)

	AssertEquals(#printedToFrame, 1)
	AssertEquals(#fallbackPrinted, 0)
	AssertTrue(string.find(printedToFrame[1], "hello there", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("separate QuestTogether chat logs can also print to main chat", function()
	local printedToSeparate = {}
	local printedToMain = {}
	local fallbackPrinted = {}
	local separateFrame = {
		isDocked = true,
		AddMessage = function(_, message)
			printedToSeparate[#printedToSeparate + 1] = message
		end,
	}
	local mainFrame = {
		AddMessage = function(_, message)
			printedToMain[#printedToMain + 1] = message
		end,
	}

	QuestTogether.db.profile.mirrorChatLogsToMainChat = true
	QuestTogether.PrintRaw = function(_, message)
		fallbackPrinted[#fallbackPrinted + 1] = message
	end

	WithPatchedMethod(QuestTogether, "GetResolvedChatLogDestination", function()
		return "separate"
	end, function()
		WithPatchedMethod(QuestTogether, "FindVisibleQuestLogChatFrame", function()
			return separateFrame
		end, function()
			WithPatchedMethod(QuestTogether, "GetChatLogFrame", function()
				return separateFrame
			end, function()
				WithPatchedMethod(QuestTogether, "GetMainChatFrame", function()
					return mainFrame
				end, function()
					QuestTogether:PrintConsoleAnnouncement("hello there", "MyPlayer-Realm", "MAGE")
				end)
			end)
		end)
	end)

	AssertEquals(#printedToSeparate, 1)
	AssertEquals(#printedToMain, 1)
	AssertEquals(#fallbackPrinted, 0)
	AssertTrue(string.find(printedToSeparate[1], "hello there", 1, true) ~= nil)
	AssertTrue(string.find(printedToMain[1], "hello there", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("undocked separate QuestTogether chat logs do not also print to main chat", function()
	local printedToSeparate = {}
	local printedToMain = {}
	local fallbackPrinted = {}
	local separateFrame = {
		isDocked = false,
		AddMessage = function(_, message)
			printedToSeparate[#printedToSeparate + 1] = message
		end,
	}
	local mainFrame = {
		AddMessage = function(_, message)
			printedToMain[#printedToMain + 1] = message
		end,
	}

	QuestTogether.db.profile.mirrorChatLogsToMainChat = true
	QuestTogether.PrintRaw = function(_, message)
		fallbackPrinted[#fallbackPrinted + 1] = message
	end

	WithPatchedMethod(QuestTogether, "GetResolvedChatLogDestination", function()
		return "separate"
	end, function()
		WithPatchedMethod(QuestTogether, "FindVisibleQuestLogChatFrame", function()
			return separateFrame
		end, function()
			WithPatchedMethod(QuestTogether, "GetChatLogFrame", function()
				return separateFrame
			end, function()
				WithPatchedMethod(QuestTogether, "GetMainChatFrame", function()
					return mainFrame
				end, function()
					QuestTogether:PrintConsoleAnnouncement("hello there", "MyPlayer-Realm", "MAGE")
				end)
			end)
		end)
	end)

	AssertEquals(#printedToSeparate, 1)
	AssertEquals(#printedToMain, 0)
	AssertEquals(#fallbackPrinted, 0)
	AssertTrue(string.find(printedToSeparate[1], "hello there", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("main chat log destination does not duplicate mirrored writes", function()
	local printedToMain = {}
	local fallbackPrinted = {}
	local mainFrame = {
		AddMessage = function(_, message)
			printedToMain[#printedToMain + 1] = message
		end,
	}

	QuestTogether.db.profile.mirrorChatLogsToMainChat = true
	QuestTogether.PrintRaw = function(_, message)
		fallbackPrinted[#fallbackPrinted + 1] = message
	end

	WithPatchedMethod(QuestTogether, "GetResolvedChatLogDestination", function()
		return "main"
	end, function()
		WithPatchedMethod(QuestTogether, "GetChatLogFrame", function()
			return mainFrame
		end, function()
			WithPatchedMethod(QuestTogether, "GetMainChatFrame", function()
				return mainFrame
			end, function()
				QuestTogether:PrintConsoleAnnouncement("main only", "MyPlayer-Realm", "MAGE")
			end)
		end)
	end)

	AssertEquals(#printedToMain, 1)
	AssertEquals(#fallbackPrinted, 0)
	AssertTrue(string.find(printedToMain[1], "main only", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("generic print uses resolved QuestTogether chat frame", function()
	local printedToFrame = {}
	local fakeFrame = {
		AddMessage = function(_, message)
			printedToFrame[#printedToFrame + 1] = message
		end,
	}

	WithPatchedMethod(QuestTogether, "GetChatLogFrame", function()
		return fakeFrame
	end, function()
		QuestTogether:Print("separate frame only")
	end)

	AssertEquals(#printedToFrame, 1)
	AssertTrue(string.find(printedToFrame[1], "separate frame only", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("chat log raw falls back when resolved chat frame is forbidden", function()
	local fallbackPrinted = {}
	local frameWrites = 0
	local forbiddenFrame = {
		IsForbidden = function()
			return true
		end,
		AddMessage = function()
			frameWrites = frameWrites + 1
		end,
	}

	WithPatchedMethod(QuestTogether, "GetChatLogFrame", function()
		return forbiddenFrame
	end, function()
		WithPatchedMethod(QuestTogether, "PrintRaw", function(_, message)
			fallbackPrinted[#fallbackPrinted + 1] = message
		end, function()
			QuestTogether:PrintChatLogRaw("forbidden frame fallback")
		end)
	end)

	AssertEquals(frameWrites, 0)
	AssertEquals(#fallbackPrinted, 1)
	AssertEquals(fallbackPrinted[1], "forbidden frame fallback")
end)

QuestTogether:RegisterTest("nameplate health tint helpers use overlays without touching status bars", function()
	local setColorCalls = 0
	local createdTextures = {}
	local liveFillTexture = {
		IsShown = function() return true end,
		points = {},
		SetPoint = function(self, ...)
			self.points[#self.points + 1] = { ... }
		end,
		ClearAllPoints = function(self)
			self.points = {}
		end,
	}
	local unitFrame = {
		unit = "nameplate1",
		healthBar = {
			IsShown = function() return true end,
			SetStatusBarColor = function()
				setColorCalls = setColorCalls + 1
			end,
			GetStatusBarTexture = function()
				return liveFillTexture
			end,
			CreateTexture = function()
				local texture = {
					shown = false,
					color = nil,
					points = {},
					allPointsTarget = nil,
					SetPoint = function(self, ...)
						self.points[#self.points + 1] = { ... }
					end,
					ClearAllPoints = function(self)
						self.points = {}
					end,
					SetAllPoints = function(self, target)
						self.allPointsTarget = target
					end,
					SetColorTexture = function(self, ...)
						self.color = { ... }
					end,
					SetTexture = function(self, asset)
						self.textureAsset = asset
					end,
					SetAtlas = function(self, asset, useAtlasSize)
						self.atlasAsset = asset
						self.useAtlasSize = useAtlasSize
					end,
					SetTexCoord = function(self, ...)
						self.texCoord = { ... }
					end,
					SetVertexColor = function(self, ...)
						self.vertexColor = { ... }
					end,
					SetBlendMode = function(self, blendMode)
						self.blendMode = blendMode
					end,
					Show = function(self)
						self.shown = true
					end,
					Hide = function(self)
						self.shown = false
					end,
					SetAlpha = function(self, value)
						self.alpha = value
					end,
				}
				createdTextures[#createdTextures + 1] = texture
				return texture
			end,
			GetAlpha = function()
				return 0.8
			end,
		},
	}

	WithPatchedMethod(QuestTogether, "CreateNameplateHealthOverlayTexture", function(_, parentFrame)
		AssertTrue(parentFrame ~= nil)
		local texture = {
			shown = false,
			color = nil,
			points = {},
			allPointsTarget = nil,
			SetPoint = function(self, ...)
				self.points[#self.points + 1] = { ... }
			end,
			ClearAllPoints = function(self)
				self.points = {}
			end,
			SetAllPoints = function(self, target)
				self.allPointsTarget = target
			end,
			SetColorTexture = function(self, ...)
				self.color = { ... }
			end,
			SetTexture = function(self, asset)
				self.textureAsset = asset
			end,
			SetAtlas = function(self, asset, useAtlasSize)
				self.atlasAsset = asset
				self.useAtlasSize = useAtlasSize
			end,
			SetTexCoord = function(self, ...)
				self.texCoord = { ... }
			end,
			SetVertexColor = function(self, ...)
				self.vertexColor = { ... }
			end,
			SetBlendMode = function(self, blendMode)
				self.blendMode = blendMode
			end,
			Show = function(self)
				self.shown = true
			end,
			Hide = function(self)
				self.shown = false
			end,
			SetAlpha = function(self, value)
				self.alpha = value
			end,
		}
		texture:SetAtlas(QuestTogether.NAMEPLATE_HEALTH_FILL_ATLAS, true)
		createdTextures[#createdTextures + 1] = texture
		return texture
	end, function()
		QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	end)

	AssertEquals(#createdTextures, 2)

	local overlay = QuestTogether.nameplateHealthOverlayByUnitFrame[unitFrame]
	AssertTrue(overlay ~= nil)
	AssertEquals(overlay.FillTexture, createdTextures[1])
	AssertEquals(overlay.Highlight, createdTextures[2])

	AssertTrue(overlay.FillTexture.shown)
	AssertTrue(overlay.Highlight.shown)
	AssertEquals(#overlay.FillTexture.points, 4)
	AssertEquals(overlay.FillTexture.points[1][2], liveFillTexture)
	AssertEquals(overlay.Highlight.blendMode, "ADD")
	AssertEquals(#overlay.Highlight.points, 4)
	AssertEquals(overlay.FillTexture.alpha, 0.8)
	AssertEquals(overlay.Highlight.alpha, 0.8)
	AssertEquals(overlay.FillTexture.atlasAsset, "UI-HUD-CoolDownManager-Bar")
	AssertEquals(overlay.FillTexture.useAtlasSize, true)
	AssertTrue(overlay.FillTexture.vertexColor ~= nil)
	AssertTrue(overlay.Highlight.color ~= nil)
	AssertEquals(overlay.Highlight.color[4], 0.14)

	QuestTogether:RestoreNameplateHealthColor(unitFrame)

	AssertEquals(setColorCalls, 0)
	AssertEquals(QuestTogether.nameplateHealthOverlayByUnitFrame[unitFrame], overlay)
	AssertFalse(overlay.FillTexture.shown)
	AssertFalse(overlay.Highlight.shown)
end)

QuestTogether:RegisterTest("nameplate health tint hides overlay when live fill texture is unavailable", function()
	local unitFrame = {
		unit = "nameplate1",
		healthBar = {
			GetStatusBarTexture = function()
				return nil
			end,
			CreateTexture = function()
				return {
					SetAllPoints = function() end,
					SetTexture = function() end,
					SetAtlas = function() end,
					SetTexCoord = function() end,
					SetVertexColor = function() end,
					SetBlendMode = function() end,
					Show = function() end,
					Hide = function() end,
					SetAlpha = function() end,
					SetPoint = function() end,
					ClearAllPoints = function() end,
				}
			end,
		},
	}

	local restoredUnitFrame = nil
	WithPatchedMethod(QuestTogether, "RestoreNameplateHealthColor", function(_, candidateFrame)
		restoredUnitFrame = candidateFrame
	end, function()
		QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	end)

	AssertEquals(restoredUnitFrame, unitFrame)
end)

QuestTogether:RegisterTest("nameplate health tint schedules a bounded retry when live fill texture is unavailable", function()
	local scheduledUnitToken = nil
	local scheduledDelay = nil
	local namePlateFrameBase = {
		UnitFrame = {
			unit = "nameplate1",
			healthBar = {},
		},
	}

	WithPatchedMethod(QuestTogether, "ShouldApplyQuestHealthTint", function(_, unitFrame, isQuestObjective)
		AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
		AssertEquals(isQuestObjective, true)
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "ApplyQuestTintToNameplate", function(_, unitFrame)
			AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "ScheduleNameplateHealthTintRefresh", function(_, unitToken, delaySeconds)
				scheduledUnitToken = unitToken
				scheduledDelay = delaySeconds
			end, function()
				QuestTogether:RefreshNameplateHealthTint(namePlateFrameBase, true)
			end)
		end)
	end)

	AssertEquals(scheduledUnitToken, "nameplate1")
	AssertEquals(scheduledDelay, 0.05)
end)

QuestTogether:RegisterTest("nameplate icon refresh schedules a short follow-up tint refresh for quest units", function()
	local scheduledUnitToken = nil
	local scheduledDelay = nil
	local namePlateFrameBase = {
		GetUnit = function()
			return "nameplate1"
		end,
		UnitFrame = {
			unit = "nameplate1",
			healthBar = {
			},
		},
	}

	QuestTogether.isEnabled = true
	WithPatchedMethod(QuestTogether, "ShouldShowQuestNameplateIconForResolvedState", function(_, unitToken, unitFrame, isQuestObjective)
		AssertEquals(unitToken, "nameplate1")
		AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
		AssertEquals(isQuestObjective, true)
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "TryResolveNameplateQuestObjectiveState", function(_, unitToken, unitFrame, allowLiveScan)
			AssertEquals(unitToken, "nameplate1")
			AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
			AssertEquals(allowLiveScan, false)
			return true, true, "Creature-0-0-0-0-11111-0000000000"
		end, function()
			WithPatchedMethod(QuestTogether, "RefreshNameplateHealthTint", function(_, frameBase, isQuestObjective)
				AssertEquals(frameBase, namePlateFrameBase)
				AssertEquals(isQuestObjective, true)
			end, function()
		WithPatchedMethod(QuestTogether, "ScheduleNameplateHealthTintRefresh", function(_, unitToken, delaySeconds)
			scheduledUnitToken = unitToken
			scheduledDelay = delaySeconds
		end, function()
					QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
				end)
			end)
		end)
	end)

	AssertEquals(scheduledUnitToken, "nameplate1")
	AssertEquals(scheduledDelay, 0.05)
end)

QuestTogether:RegisterTest("nameplate health tint uses resolved quest state from icon refresh", function()
	local appliedUnitFrame = nil
	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({})
	local namePlateFrameBase = {
		GetUnit = function()
			return "nameplate1"
		end,
		UnitFrame = {
			unit = "nameplate1",
			healthBar = {},
		},
	}

	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "ShouldShowQuestNameplateIconForResolvedState", function(_, unitToken, unitFrame, isQuestObjective)
			AssertEquals(unitToken, "nameplate1")
			AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
			AssertEquals(isQuestObjective, true)
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "TryResolveNameplateQuestObjectiveState", function(_, unitToken, unitFrame, allowLiveScan)
				AssertEquals(unitToken, "nameplate1")
				AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
				AssertEquals(allowLiveScan, false)
				return true, true, "Creature-0-0-0-0-11111-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "ApplyQuestTintToNameplate", function(_, unitFrame)
					appliedUnitFrame = unitFrame
					return true
				end, function()
					WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
						return true
					end, function()
						WithPatchedMethod(QuestTogether, "IsNameplateUnitPlayer", function()
							return false
						end, function()
							WithPatchedMethod(QuestTogether, "IsNameplateUnitConnected", function()
								return true
							end, function()
								WithPatchedMethod(QuestTogether, "IsNameplateUnitDead", function()
									return false
								end, function()
									WithPatchedMethod(QuestTogether, "IsNameplateUnitTapDenied", function()
										return false
									end, function()
										QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
									end)
								end)
							end)
						end)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(appliedUnitFrame, namePlateFrameBase.UnitFrame)
	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate1"], true)
end)

QuestTogether:RegisterTest("nameplate icon refresh resolves namePlateUnitToken like Plater", function()
	local resolvedUnitToken = nil
	local namePlateFrameBase = {
		UnitFrame = {
			namePlateUnitToken = "nameplate9",
			healthBar = {},
		},
	}

	QuestTogether.isEnabled = true
	WithPatchedMethod(QuestTogether, "TryResolveNameplateQuestObjectiveState", function(_, unitToken, unitFrame, allowLiveScan)
		resolvedUnitToken = unitToken
		AssertEquals(unitFrame, namePlateFrameBase.UnitFrame)
		AssertEquals(allowLiveScan, false)
		return true, false, nil
	end, function()
		WithPatchedMethod(QuestTogether, "RefreshNameplateHealthTint", function() end, function()
			QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
		end)
	end)

	AssertEquals(resolvedUnitToken, "nameplate9")
end)

QuestTogether:RegisterTest("nameplate icon refresh uses cached state without queuing resolver", function()
	local appliedQuestState = nil
	local resolverUnitToken = nil
	local namePlateFrameBase = {
		UnitFrame = {
			namePlateUnitToken = "nameplate9",
			namePlateUnitGUID = "Creature-0-0-0-0-99999-0000000000",
			healthBar = {},
		},
	}

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({})
	QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-99999-0000000000"] = true
	QuestTogether.nameplateQuestStateByUnitToken["nameplate9"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate9"] = "Creature-0-0-0-0-99999-0000000000"

	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "ApplyResolvedQuestStateToNameplate", function(_, frameBase, unitToken, unitFrame, isQuestObjective, scheduleTintFollowUp)
			appliedQuestState = isQuestObjective
		end, function()
			WithPatchedMethod(QuestTogether, "TryEvaluateQuestObjectiveViaTooltip", function()
				error("cached icon refresh should not perform a live quest scan")
			end, function()
				WithPatchedMethod(QuestTogether, "ScheduleNameplateTooltipResolution", function(_, unitToken)
					resolverUnitToken = unitToken
				end, function()
					QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
				end)
			end)
		end)
	end)

	AssertEquals(appliedQuestState, true)
	AssertEquals(resolverUnitToken, nil)
end)

QuestTogether:RegisterTest("nameplate icon refresh queues resolver when cached state is missing", function()
	local scheduledUnitToken = nil
	local hiddenFrame = nil
	local namePlateFrameBase = {
		UnitFrame = {
			namePlateUnitToken = "nameplate9",
			namePlateUnitGUID = "Creature-0-0-0-0-99999-0000000000",
			healthBar = {},
		},
	}

	QuestTogether.isEnabled = true

	WithPatchedMethod(QuestTogether, "ApplyResolvedQuestStateToNameplate", function()
		error("uncached icon refresh should not mutate from an uncached live scan")
	end, function()
		WithPatchedMethod(QuestTogether, "TryEvaluateQuestObjectiveViaTooltip", function()
			error("uncached icon refresh should not perform a live quest scan")
		end, function()
			WithPatchedMethod(QuestTogether, "HideNameplateIcon", function(_, frameBase)
				hiddenFrame = frameBase
			end, function()
				WithPatchedMethod(QuestTogether, "ScheduleNameplateTooltipResolution", function(_, unitToken)
					scheduledUnitToken = unitToken
				end, function()
					QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
				end)
			end)
		end)
	end)

	AssertEquals(hiddenFrame, namePlateFrameBase)
	AssertEquals(scheduledUnitToken, "nameplate9")
end)

QuestTogether:RegisterTest("nameplate health tint no longer requires attackable units", function()
	local unitFrame = {
		unit = "nameplate1",
		healthBar = {},
	}

	QuestTogether.isEnabled = true
	QuestTogether.db.profile.nameplateQuestHealthColorEnabled = true

	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function()
			return true
		end, function()
			WithPatchedMethod(QuestTogether, "IsNameplateUnitPlayer", function()
				return false
			end, function()
				WithPatchedMethod(QuestTogether, "IsNameplateUnitConnected", function()
					return true
				end, function()
					WithPatchedMethod(QuestTogether, "IsNameplateUnitDead", function()
						return false
					end, function()
						WithPatchedMethod(QuestTogether, "IsNameplateUnitTapDenied", function()
							return false
						end, function()
							WithPatchedMethod(QuestTogether, "CanPlayerAttackNameplateUnit", function()
								error("attackable-unit gating should not run for quest tinting")
							end, function()
								AssertTrue(QuestTogether:ShouldApplyQuestHealthTint(unitFrame, true))
							end)
						end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("quest nameplate visuals no longer suppress dead or disconnected units", function()
	QuestTogether.isEnabled = true
	QuestTogether.db.profile.nameplateQuestIconEnabled = true
	QuestTogether.db.profile.nameplateQuestHealthColorEnabled = true
	local unitFrame = {
		namePlateUnitToken = "nameplate1",
		healthBar = {},
	}

	WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "DoesNameplateUnitExist", function(_, unitToken)
			AssertEquals(unitToken, "nameplate1")
			return true
		end, function()
			WithPatchedMethod(QuestTogether, "IsNameplateUnitPlayer", function(_, unitToken)
				AssertEquals(unitToken, "nameplate1")
				return false
			end, function()
				WithPatchedMethod(QuestTogether, "IsNameplateUnitConnected", function()
					error("dead/disconnected gating should not run for quest visuals")
				end, function()
					WithPatchedMethod(QuestTogether, "IsNameplateUnitDead", function()
						error("dead/disconnected gating should not run for quest visuals")
					end, function()
						WithPatchedMethod(QuestTogether, "IsNameplateUnitTapDenied", function(_, unitToken)
							AssertEquals(unitToken, "nameplate1")
							return false
						end, function()
							AssertTrue(QuestTogether:ShouldShowQuestNameplateIconForResolvedState(nil, unitFrame, true))
							AssertTrue(QuestTogether:ShouldApplyQuestHealthTint(unitFrame, true))
						end)
					end)
				end)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("blocked-context nameplate add clears recycled quest visuals immediately", function()
	local hiddenFrame = nil
	local scheduledUnitToken = nil
	local namePlateFrameBase = {
		UnitFrame = {
			unit = "nameplate1",
			healthBar = {},
		},
	}

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		GetNamePlateForUnit = function(unitToken)
			AssertEquals(unitToken, "nameplate1")
			return namePlateFrameBase
		end,
	})

	WithPatchedMethod(QuestTogether, "IsNameplateUnitToken", function(_, unitToken)
		return unitToken == "nameplate1"
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return true
		end, function()
			WithPatchedMethod(QuestTogether, "HideNameplateIcon", function(_, frameBase)
				hiddenFrame = frameBase
			end, function()
				WithPatchedMethod(QuestTogether, "ScheduleNameplateRefresh", function(_, unitToken)
					scheduledUnitToken = unitToken
				end, function()
					QuestTogether:OnNameplateAdded("nameplate1")
				end)
			end)
		end)
	end)

	AssertEquals(hiddenFrame, namePlateFrameBase)
	AssertEquals(scheduledUnitToken, nil)
	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate1"], nil)
	AssertEquals(QuestTogether.nameplateQuestGuidByUnitToken["nameplate1"], nil)
end)

QuestTogether:RegisterTest("nameplate icon hide restores stale health tint when quest state resolves false", function()
	local restoredUnitFrame = nil
	local iconHidden = false
	QuestTogether.isEnabled = true
	local icon = {
		Hide = function()
			iconHidden = true
		end,
	}
	local unitFrame = {
		unit = "nameplate1",
		healthBar = {},
	}
	local namePlateFrameBase = {
		GetUnit = function()
			return "nameplate1"
		end,
		UnitFrame = unitFrame,
	}
	QuestTogether.nameplateIconByUnitFrame[unitFrame] = icon

	WithPatchedMethod(QuestTogether, "ShouldShowQuestNameplateIconForResolvedState", function(_, unitToken, candidateFrame, isQuestObjective)
		AssertEquals(unitToken, "nameplate1")
		AssertEquals(candidateFrame, unitFrame)
		AssertEquals(isQuestObjective, false)
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "TryResolveNameplateQuestObjectiveState", function(_, unitToken, candidateFrame, allowLiveScan)
			AssertEquals(unitToken, "nameplate1")
			AssertEquals(candidateFrame, unitFrame)
			AssertEquals(allowLiveScan, false)
			return true, false, "Creature-0-0-0-0-11111-0000000000"
		end, function()
			WithPatchedMethod(QuestTogether, "RefreshNameplateHealthTint", function(_, frameBase, isQuestObjective)
				AssertEquals(frameBase, namePlateFrameBase)
				AssertEquals(isQuestObjective, false)
			end, function()
				WithPatchedMethod(QuestTogether, "RestoreNameplateHealthColor", function(_, candidateFrame)
					restoredUnitFrame = candidateFrame
				end, function()
					QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
				end)
			end)
		end)
	end)

	AssertTrue(iconHidden)
	AssertEquals(restoredUnitFrame, unitFrame)
	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate1"], false)
end)

QuestTogether:RegisterTest("nameplate threat events schedule tint refresh for nameplate units", function()
	QuestTogether.isEnabled = true
	local scheduled = {}

	WithPatchedMethod(QuestTogether, "IsNameplateUnitToken", function(_, unitToken)
		return unitToken == "nameplate7" or unitToken == "nameplate8"
	end, function()
		WithPatchedMethod(QuestTogether, "ScheduleNameplateHealthTintRefresh", function(_, unitToken, delaySeconds, preferCachedQuestState)
			scheduled[#scheduled + 1] = {
				unitToken = unitToken,
				delaySeconds = delaySeconds,
				preferCachedQuestState = preferCachedQuestState,
			}
		end, function()
			QuestTogether:HandleNameplateEvent("UNIT_THREAT_SITUATION_UPDATE", "nameplate7")
			QuestTogether:HandleNameplateEvent("UNIT_THREAT_LIST_UPDATE", "nameplate8")
			QuestTogether:HandleNameplateEvent("UNIT_THREAT_SITUATION_UPDATE", "target")
		end)
	end)

	AssertEquals(scheduled[1].unitToken, "nameplate7")
	AssertEquals(scheduled[1].delaySeconds, nil)
	AssertEquals(scheduled[1].preferCachedQuestState, true)
	AssertEquals(scheduled[2].unitToken, "nameplate8")
	AssertEquals(scheduled[2].delaySeconds, nil)
	AssertEquals(scheduled[2].preferCachedQuestState, true)
	AssertEquals(#scheduled, 2)
end)

QuestTogether:RegisterTest("nameplate add clears stale visuals and refreshes immediately", function()
	local hiddenFrame = nil
	local refreshedFrame = nil
	local scheduledUnitToken = nil
	local unitFrame = {
		unit = "nameplate12",
		healthBar = {},
	}
	local namePlateFrameBase = {
		UnitFrame = unitFrame,
		GetUnit = function()
			return "nameplate12"
		end,
	}

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({})
	QuestTogether.nameplateQuestStateByUnitToken["nameplate12"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate12"] = "Creature-0-0-0-0-121212-0000000000"

	WithPatchedMethod(QuestTogether, "IsNameplateUnitToken", function(_, unitToken)
		return unitToken == "nameplate12"
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetAccessibleNameplateFrameForUnit", function(_, unitToken, requireShown)
				AssertEquals(unitToken, "nameplate12")
				AssertEquals(requireShown, false)
				return namePlateFrameBase, unitFrame
			end, function()
				WithPatchedMethod(QuestTogether, "HideNameplateIcon", function(_, frameBase)
					hiddenFrame = frameBase
				end, function()
					WithPatchedMethod(QuestTogether, "RefreshNameplateIcon", function(_, frameBase)
						refreshedFrame = frameBase
					end, function()
						WithPatchedMethod(QuestTogether, "ScheduleNameplateRefresh", function(_, unitToken)
							scheduledUnitToken = unitToken
						end, function()
							QuestTogether:OnNameplateAdded("nameplate12")
						end)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate12"], nil)
	AssertEquals(QuestTogether.nameplateQuestGuidByUnitToken["nameplate12"], nil)
	AssertEquals(hiddenFrame, namePlateFrameBase)
	AssertEquals(refreshedFrame, namePlateFrameBase)
	AssertEquals(scheduledUnitToken, nil)
end)

QuestTogether:RegisterTest("combat nameplate remove clears cached quest state", function()
	local hiddenFrame = nil
	local unitFrame = {
		unit = "nameplate13",
		healthBar = {},
	}
	local namePlateFrameBase = {
		UnitFrame = unitFrame,
	}

	QuestTogether.nameplateQuestStateByUnitToken["nameplate13"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate13"] = "Creature-0-0-0-0-131313-0000000000"
	QuestTogether.nameplateRefreshPendingByUnitToken["nameplate13"] = true
	QuestTogether.nameplateRefreshGenerationByUnitToken["nameplate13"] = 7
	QuestTogether.nameplateHealthTintRefreshPendingByUnitToken["nameplate13"] = true
	QuestTogether.API = CreateApiWithOverrides({
		InCombatLockdown = function()
			return true
		end,
		GetNamePlateForUnit = function(unitToken)
			AssertEquals(unitToken, "nameplate13")
			return namePlateFrameBase
		end,
	})

	WithPatchedMethod(QuestTogether, "IsNameplateUnitToken", function(_, unitToken)
		return unitToken == "nameplate13"
	end, function()
		WithPatchedMethod(QuestTogether, "HideNameplateIcon", function(_, frameBase)
			hiddenFrame = frameBase
		end, function()
			QuestTogether:OnNameplateRemoved("nameplate13")
		end)
	end)

	AssertEquals(hiddenFrame, namePlateFrameBase)
	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate13"], nil)
	AssertEquals(QuestTogether.nameplateQuestGuidByUnitToken["nameplate13"], nil)
	AssertEquals(QuestTogether.nameplateRefreshPendingByUnitToken["nameplate13"], nil)
	AssertEquals(QuestTogether.nameplateRefreshGenerationByUnitToken["nameplate13"], 8)
	AssertEquals(QuestTogether.nameplateHealthTintRefreshPendingByUnitToken["nameplate13"], nil)
end)

QuestTogether:RegisterTest("combat enter and leave schedule full nameplate refreshes", function()
	QuestTogether.isEnabled = true
	local scheduled = {}

	WithPatchedMethod(QuestTogether, "ScheduleNameplatePresentationRefresh", function(_, reason, delaySeconds)
		scheduled[#scheduled + 1] = {
			reason = reason,
			delaySeconds = delaySeconds,
		}
	end, function()
		WithPatchedMethod(QuestTogether, "TryInstallPersonalBubbleEditModeHooks", function() end, function()
			QuestTogether:HandleNameplateEvent("PLAYER_REGEN_DISABLED")
			QuestTogether:HandleNameplateEvent("PLAYER_REGEN_ENABLED")
		end)
	end)

	AssertEquals(scheduled[1].reason, "PLAYER_REGEN_DISABLED")
	AssertEquals(scheduled[1].delaySeconds, 0)
	AssertEquals(scheduled[2].reason, "PLAYER_REGEN_ENABLED")
	AssertEquals(scheduled[2].delaySeconds, 0)
	AssertEquals(#scheduled, 2)
end)

QuestTogether:RegisterTest("nameplate quest state refresh uses scheduler and shared worker", function()
	local rebuildCalls = 0
	local clearCalls = 0
	local augmentationCalls = 0

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(delaySeconds, callback)
			callback()
		end,
	})

	WithPatchedMethod(QuestTogether, "RebuildNameplateQuestTextCache", function()
		rebuildCalls = rebuildCalls + 1
	end, function()
		WithPatchedMethod(QuestTogether, "ClearNameplateResolvedQuestState", function()
			clearCalls = clearCalls + 1
		end, function()
			WithPatchedMethod(QuestTogether, "RefreshNameplateAugmentation", function()
				augmentationCalls = augmentationCalls + 1
			end, function()
				AssertTrue(QuestTogether:RefreshNameplatesForQuestStateChange("QUEST_POI_UPDATE"))
				AssertEquals(rebuildCalls, 1)
				AssertEquals(clearCalls, 1)
				AssertEquals(augmentationCalls, 1)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("nameplate quest state refresh clears guid detection cache", function()
	local rebuildCalls = 0
	local augmentationCalls = 0

	QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-12345-0000000000"] = true
	QuestTogether.nameplateQuestStateByUnitToken["nameplate1"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate1"] = "Creature-0-0-0-0-12345-0000000000"
	QuestTogether.isEnabled = true

	WithPatchedMethod(QuestTogether, "RebuildNameplateQuestTextCache", function()
		rebuildCalls = rebuildCalls + 1
	end, function()
		WithPatchedMethod(QuestTogether, "RefreshNameplateAugmentation", function()
			augmentationCalls = augmentationCalls + 1
		end, function()
			AssertTrue(QuestTogether:RefreshNameplatesForQuestStateChange("QUEST_LOG_UPDATE"))
		end)
	end)

	AssertEquals(rebuildCalls, 1)
	AssertEquals(augmentationCalls, 1)
	AssertEquals(QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-12345-0000000000"], nil)
	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate1"], nil)
	AssertEquals(QuestTogether.nameplateQuestGuidByUnitToken["nameplate1"], nil)
end)

QuestTogether:RegisterTest("visible nameplate refresh clears cache and refreshes immediately", function()
	local clearCalls = 0
	local augmentationCalls = 0

	QuestTogether.isEnabled = true

	WithPatchedMethod(QuestTogether, "ClearNameplateResolvedQuestState", function()
		clearCalls = clearCalls + 1
	end, function()
		WithPatchedMethod(QuestTogether, "RefreshNameplateAugmentation", function()
			augmentationCalls = augmentationCalls + 1
		end, function()
			AssertTrue(QuestTogether:RefreshVisibleNameplates("PLAYER_ENTERING_WORLD"))
		end)
	end)

	AssertEquals(clearCalls, 1)
	AssertEquals(augmentationCalls, 1)
end)

QuestTogether:RegisterTest("zone changed new area schedules nameplate presentation refresh through shared runtime", function()
	QuestTogether.isEnabled = true
	local scheduledReason = nil
	local scheduledDelay = nil

	WithPatchedMethod(QuestTogether, "ScheduleNameplatePresentationRefresh", function(_, reason, delaySeconds)
		scheduledReason = reason
		scheduledDelay = delaySeconds
	end, function()
		QuestTogether:HandleNameplateEvent("ZONE_CHANGED_NEW_AREA")
	end)

	AssertEquals(scheduledReason, "ZONE_CHANGED_NEW_AREA")
	AssertEquals(scheduledDelay, 0)
end)

QuestTogether:RegisterTest("scheduled nameplate tint refresh can preserve cached quest state", function()
	local appliedUnitFrame = nil
	local liveObjectiveChecks = 0
	local healthBar = {}
	local unitFrame = {
		unit = "nameplate9",
		healthBar = healthBar,
	}
	local namePlateFrameBase = {
		UnitFrame = unitFrame,
		GetUnit = function()
			return "nameplate9"
		end,
		IsShown = function()
			return true
		end,
	}

	QuestTogether.isEnabled = true
	QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-99999-0000000000"] = true
	QuestTogether.nameplateQuestStateByUnitToken["nameplate9"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate9"] = "Creature-0-0-0-0-99999-0000000000"
	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			callback()
		end,
		GetNamePlateForUnit = function(unitToken)
			AssertEquals(unitToken, "nameplate9")
			return namePlateFrameBase
		end,
	})

	WithPatchedMethod(QuestTogether, "IsNameplateUnitToken", function(_, unitToken)
		return unitToken == "nameplate9"
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateUnitGuid", function(_, unitToken)
				AssertEquals(unitToken, "nameplate9")
				return "Creature-0-0-0-0-99999-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "TryEvaluateQuestObjectiveViaTooltip", function()
					liveObjectiveChecks = liveObjectiveChecks + 1
					return true, false, "Creature-0-0-0-0-99999-0000000000"
				end, function()
					WithPatchedMethod(QuestTogether, "ShouldApplyQuestHealthTint", function(_, candidateFrame, isQuestObjective)
						AssertEquals(candidateFrame, unitFrame)
						AssertEquals(isQuestObjective, true)
						return true
					end, function()
						WithPatchedMethod(QuestTogether, "ApplyQuestTintToNameplate", function(_, candidateFrame)
							appliedUnitFrame = candidateFrame
							return true
						end, function()
							QuestTogether:ScheduleNameplateHealthTintRefresh("nameplate9", 0, true)
						end)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(liveObjectiveChecks, 0)
	AssertEquals(appliedUnitFrame, unitFrame)
	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate9"], true)
end)

QuestTogether:RegisterTest("scheduled nameplate tint refresh queues resolver when cached state is unavailable", function()
	local appliedUnitFrame = nil
	local scheduledUnitToken = nil
	local healthBar = {}
	local unitFrame = {
		unit = "nameplate9",
		namePlateUnitGUID = "Creature-0-0-0-0-11111-0000000000",
		healthBar = healthBar,
	}
	local namePlateFrameBase = {
		UnitFrame = unitFrame,
		GetUnit = function()
			return "nameplate9"
		end,
		IsShown = function()
			return true
		end,
	}

	QuestTogether.isEnabled = true
	QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-11111-0000000000"] = true
	QuestTogether.nameplateQuestStateByUnitToken["nameplate9"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate9"] = "Creature-0-0-0-0-11111-0000000000"
	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			callback()
		end,
		GetNamePlateForUnit = function(unitToken)
			AssertEquals(unitToken, "nameplate9")
			return namePlateFrameBase
		end,
	})

	WithPatchedMethod(QuestTogether, "IsNameplateUnitToken", function(_, unitToken)
		return unitToken == "nameplate9"
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateUnitGuid", function(_, unitToken)
				AssertEquals(unitToken, "nameplate9")
				return "Creature-0-0-0-0-11111-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "TryResolveNameplateQuestObjectiveState", function()
					return false, false, "Creature-0-0-0-0-11111-0000000000"
				end, function()
					WithPatchedMethod(QuestTogether, "ShouldApplyQuestHealthTint", function(_, candidateFrame, isQuestObjective)
						AssertEquals(candidateFrame, unitFrame)
						AssertEquals(isQuestObjective, nil)
						return false
					end, function()
						WithPatchedMethod(QuestTogether, "ApplyQuestTintToNameplate", function(_, candidateFrame)
							appliedUnitFrame = candidateFrame
							return true
						end, function()
							WithPatchedMethod(QuestTogether, "ScheduleNameplateTooltipResolution", function(_, unitToken)
								scheduledUnitToken = unitToken
							end, function()
								QuestTogether:ScheduleNameplateHealthTintRefresh("nameplate9", 0, true)
							end)
						end)
					end)
				end)
			end)
		end)
	end)
	AssertEquals(appliedUnitFrame, nil)
	AssertEquals(scheduledUnitToken, "nameplate9")
end)

QuestTogether:RegisterTest("scheduled nameplate tint refresh ignores cached quest state when unit guid changes", function()
	local restoredUnitFrame = nil
	local liveObjectiveChecks = 0
	local healthBar = {}
	local unitFrame = {
		unit = "nameplate10",
		healthBar = healthBar,
	}
	local namePlateFrameBase = {
		UnitFrame = unitFrame,
		GetUnit = function()
			return "nameplate10"
		end,
		IsShown = function()
			return true
		end,
	}

	QuestTogether.isEnabled = true
	QuestTogether.nameplateQuestStateByGuid["Creature-0-0-0-0-11111-0000000000"] = true
	QuestTogether.nameplateQuestStateByUnitToken["nameplate10"] = true
	QuestTogether.nameplateQuestGuidByUnitToken["nameplate10"] = "Creature-0-0-0-0-11111-0000000000"
	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			callback()
		end,
		GetNamePlateForUnit = function(unitToken)
			AssertEquals(unitToken, "nameplate10")
			return namePlateFrameBase
		end,
	})

	WithPatchedMethod(QuestTogether, "IsNameplateUnitToken", function(_, unitToken)
		return unitToken == "nameplate10"
	end, function()
		WithPatchedMethod(QuestTogether, "IsNameplateAugmentationBlockedInCurrentContext", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "GetNameplateUnitGuid", function(_, unitToken)
				AssertEquals(unitToken, "nameplate10")
				return "Creature-0-0-0-0-22222-0000000000"
			end, function()
				WithPatchedMethod(QuestTogether, "TryEvaluateQuestObjectiveViaTooltip", function(_, unitToken, candidateFrame, unitGuid)
					AssertEquals(unitToken, "nameplate10")
					AssertEquals(candidateFrame, unitFrame)
					AssertEquals(unitGuid, "Creature-0-0-0-0-22222-0000000000")
					liveObjectiveChecks = liveObjectiveChecks + 1
					return true, false, "Creature-0-0-0-0-22222-0000000000"
				end, function()
					WithPatchedMethod(QuestTogether, "ShouldApplyQuestHealthTint", function(_, candidateFrame, isQuestObjective)
						AssertEquals(candidateFrame, unitFrame)
						AssertEquals(isQuestObjective, false)
						return false
					end, function()
						WithPatchedMethod(QuestTogether, "RestoreNameplateHealthColor", function(_, candidateFrame)
							restoredUnitFrame = candidateFrame
						end, function()
							QuestTogether:ScheduleNameplateHealthTintRefresh("nameplate10", 0, true)
						end)
					end)
				end)
			end)
		end)
	end)

	AssertEquals(liveObjectiveChecks, 1)
	AssertEquals(restoredUnitFrame, unitFrame)
	AssertEquals(QuestTogether.nameplateQuestStateByUnitToken["nameplate10"], false)
	AssertEquals(QuestTogether.nameplateQuestGuidByUnitToken["nameplate10"], "Creature-0-0-0-0-22222-0000000000")
end)

QuestTogether:RegisterTest("separate chat window inherits main chat font size when enabled", function()
	local appliedFontSize = nil
	local fakeMainFrame = {
		GetID = function()
			return 1
		end,
	}
	local fakeQuestFrame = {
		GetID = function()
			return 3
		end,
	}

	QuestTogether.API = CreateApiWithOverrides({
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 1 then
				return "General", 18
			end
			if chatFrameID == 3 then
				return "QuestTogether", 14
			end
			return nil
		end,
		SetChatWindowFontSize = function(chatFrame, fontSize)
			appliedFontSize = {
				frameID = chatFrame:GetID(),
				fontSize = fontSize,
			}
		end,
	})

	local ok, err = pcall(function()
		WithPatchedMethod(QuestTogether, "GetMainChatFrame", function()
			return fakeMainFrame
		end, function()
			WithPatchedMethod(QuestTogether, "EnsureQuestLogChatFrame", function()
				return fakeQuestFrame, 3
			end, function()
				AssertTrue(QuestTogether:SetOption("chatLogDestination", "separate"))
			end)
		end)
	end)
	if not ok then
		error(err, 0)
	end

	AssertTrue(appliedFontSize ~= nil)
	AssertEquals(appliedFontSize.frameID, 3)
	AssertEquals(appliedFontSize.fontSize, 18)
end)

QuestTogether:RegisterTest("switching chat logs back to main closes QuestTogether chat window", function()
	local closeCalls = {}
	local fakeQuestFrame = {
		GetID = function()
			return 3
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "separate"
	QuestTogether.db.profile.questLogChatFrameID = 3
	QuestTogether.API = CreateApiWithOverrides({
		GetChatFrameByID = function(chatFrameID)
			if chatFrameID == 3 then
				return fakeQuestFrame
			end
			return nil
		end,
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 3 then
				return "QuestTogether", 18
			end
			return nil
		end,
		CloseChatWindow = function(chatFrame)
			closeCalls[#closeCalls + 1] = chatFrame:GetID()
		end,
	})

	AssertTrue(QuestTogether:SetOption("chatLogDestination", "main"))
	AssertEquals(#closeCalls, 1)
	AssertEquals(closeCalls[1], 3)
	AssertEquals(QuestTogether.db.profile.questLogChatFrameID, nil)
end)

QuestTogether:RegisterTest("closing QuestTogether chat window reverts chat log destination to main", function()
	local refreshed = 0
	local fakeQuestFrame = {
		GetID = function()
			return 3
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "separate"
	QuestTogether.db.profile.questLogChatFrameID = 3
	QuestTogether.API = CreateApiWithOverrides({
		Delay = function(_, callback)
			callback()
		end,
		GetNumChatWindows = function()
			return 0
		end,
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 3 then
				return "QuestTogether", 18
			end
			return nil
		end,
		GetChatFrameByID = function(chatFrameID)
			if chatFrameID == 3 then
				return fakeQuestFrame
			end
			return nil
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshOptionsWindow", function()
		refreshed = refreshed + 1
	end, function()
		AssertTrue(QuestTogether:HandleQuestLogChatFrameClosed(fakeQuestFrame))
	end)

	AssertEquals(QuestTogether:GetOption("chatLogDestination"), "main")
	AssertEquals(QuestTogether.db.profile.questLogChatFrameID, nil)
	AssertEquals(refreshed, 1)
end)

QuestTogether:RegisterTest("login adopts visible QuestTogether chat window as separate destination", function()
	local refreshed = 0
	local visibleFrame = {
		GetID = function()
			return 4
		end,
		GetName = function()
			return "ChatFrame4"
		end,
		IsShown = function()
			return true
		end,
	}

	QuestTogether.db.profile.chatLogDestination = "main"
	QuestTogether.db.profile.questLogChatFrameID = nil

	QuestTogether.API = CreateApiWithOverrides({
		GetNumChatWindows = function()
			return 4
		end,
		GetChatWindowInfo = function(chatFrameID)
			if chatFrameID == 4 then
				return "QuestTogether", 18
			end
			return nil
		end,
		GetChatFrameByID = function(chatFrameID)
			if chatFrameID == 4 then
				return visibleFrame
			end
			return nil
		end,
	})

	WithPatchedMethod(QuestTogether, "RefreshOptionsWindow", function()
		refreshed = refreshed + 1
	end, function()
		AssertTrue(QuestTogether:ReconcileQuestLogChatDestination())
	end)

	AssertEquals(QuestTogether:GetOption("chatLogDestination"), "separate")
	AssertEquals(QuestTogether.db.profile.questLogChatFrameID, 4)
	AssertEquals(refreshed, 1)
end)

QuestTogether:RegisterTest("bubble test announcement uses target player when available", function()
	local sent = {}
	QuestTogether.isEnabled = true
		QuestTogether.API = CreateApiWithOverrides({
			IsInInstanceGroup = function()
				return false
			end,
			IsInRaid = function()
				return false
			end,
			IsInParty = function()
				return false
			end,
			GetChannelName = function(channelName)
				AssertEquals(channelName, QuestTogether.announcementChannelName)
				return 7
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "MyPlayer", "Realm"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Mage", "MAGE"
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	local success = QuestTogether:SendAnnouncementEvent("QUEST_PROGRESS", "8/8 Lightblooming Bulb")
	AssertTrue(success)
	AssertEquals(#sent, 1)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "CHANNEL")
	AssertEquals(sent[1].target, 7)
	AssertTrue(string.find(sent[1].message, "^ANN|", 1) ~= nil)
end)

QuestTogether:RegisterTest("announcement wire uses both party and channel routes when grouped", function()
	local sent = {}
	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return true
		end,
		GetChannelName = function(channelName)
			AssertEquals(channelName, QuestTogether.announcementChannelName)
			return 8
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "MyPlayer", "Realm"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Mage", "MAGE"
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	local success = QuestTogether:SendAnnouncementEvent("QUEST_PROGRESS", "9/9 Things")
	AssertTrue(success)
	AssertEquals(#sent, 2)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "PARTY")
	AssertEquals(sent[1].target, nil)
	AssertTrue(string.find(sent[1].message, "^ANN|", 1) ~= nil)
	AssertEquals(sent[2].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[2].channel, "CHANNEL")
	AssertEquals(sent[2].target, 8)
	AssertTrue(string.find(sent[2].message, "^ANN|", 1) ~= nil)
end)

QuestTogether:RegisterTest("ping request uses both party and channel routes when grouped", function()
	local sent = {}
	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return true
		end,
		GetChannelName = function(channelName)
			AssertEquals(channelName, QuestTogether.announcementChannelName)
			return 12
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
		Delay = function() end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "MyPlayer", "Realm"
		end,
		UnitName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "MyPlayer"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Mage", "MAGE"
		end,
		UnitRace = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Human"
		end,
		UnitLevel = function(unitToken)
			AssertEquals(unitToken, "player")
			return 70
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerAnnouncementLocationInfo", function()
		return {}
	end, function()
		WithPatchedMethod(QuestTogether, "HandlePingResponse", function()
			return true
		end, function()
			local success, requestId = QuestTogether:SendPingRequest()
			AssertTrue(success)
			AssertTrue(type(requestId) == "string" and requestId ~= "")
		end)
	end)

	AssertEquals(#sent, 2)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "PARTY")
	AssertEquals(sent[1].target, nil)
	AssertTrue(string.find(sent[1].message, "^PING|", 1) ~= nil)
	AssertEquals(sent[2].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[2].channel, "CHANNEL")
	AssertEquals(sent[2].target, 12)
	AssertTrue(string.find(sent[2].message, "^PING|", 1) ~= nil)
end)

QuestTogether:RegisterTest("ping request still sends to group when channel join is unavailable", function()
	local sent = {}
	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return true
		end,
		GetChannelName = function()
			return nil
		end,
		JoinPermanentChannel = function() end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
		Delay = function() end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "MyPlayer", "Realm"
		end,
		UnitName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "MyPlayer"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Mage", "MAGE"
		end,
		UnitRace = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Human"
		end,
		UnitLevel = function(unitToken)
			AssertEquals(unitToken, "player")
			return 70
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "player")
			return "Player-1-ABC"
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerAnnouncementLocationInfo", function()
		return {}
	end, function()
		WithPatchedMethod(QuestTogether, "HandlePingResponse", function()
			return true
		end, function()
			local success, requestId = QuestTogether:SendPingRequest()
			AssertTrue(success)
			AssertTrue(type(requestId) == "string" and requestId ~= "")
		end)
	end)

	AssertEquals(#sent, 1)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "PARTY")
	AssertEquals(sent[1].target, nil)
	AssertTrue(string.find(sent[1].message, "^PING|", 1) ~= nil)
end)

QuestTogether:RegisterTest("ping response uses both party and channel routes when grouped", function()
	local sent = {}
	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return true
		end,
		GetChannelName = function(channelName)
			AssertEquals(channelName, QuestTogether.announcementChannelName)
			return 14
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
	})

	WithPatchedMethod(QuestTogether, "BuildPingResponse", function(_, requestId)
		return {
			requestId = requestId,
			senderName = "LocalPlayer-Realm",
			realmName = "Realm",
			raceName = "Human",
			classFile = "MAGE",
			className = "Mage",
			level = "70",
			zoneName = "Elwynn Forest",
			coordX = "50.0",
			coordY = "50.0",
			warMode = "0",
			mapID = "37",
			addonVersion = "1.0.0",
		}
	end, function()
		AssertTrue(QuestTogether:SendPingResponse("ping-2"))
	end)

	AssertEquals(#sent, 2)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "PARTY")
	AssertEquals(sent[1].target, nil)
	AssertTrue(string.find(sent[1].message, "^PONG|", 1) ~= nil)
	AssertEquals(sent[2].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[2].channel, "CHANNEL")
	AssertEquals(sent[2].target, 14)
	AssertTrue(string.find(sent[2].message, "^PONG|", 1) ~= nil)
end)

QuestTogether:RegisterTest("quest compare request uses both party and channel routes when grouped", function()
	local sent = {}
	QuestTogether.isEnabled = true
	QuestTogether.partyMembers = {
		["Remote-Realm"] = {
			fullName = "Remote-Realm",
			classFile = "DRUID",
		},
	}
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return true
		end,
		GetChannelName = function(channelName)
			AssertEquals(channelName, QuestTogether.announcementChannelName)
			return 13
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
		Delay = function() end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "LocalPlayer", "Realm"
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintQuestCompareStart", function() end, function()
		AssertTrue(QuestTogether:RequestQuestCompare("Remote-Realm"))
	end)

	AssertEquals(#sent, 2)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "PARTY")
	AssertEquals(sent[1].target, nil)
	AssertTrue(string.find(sent[1].message, "^QCMP|", 1) ~= nil)
	AssertEquals(sent[2].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[2].channel, "CHANNEL")
	AssertEquals(sent[2].target, 13)
	AssertTrue(string.find(sent[2].message, "^QCMP|", 1) ~= nil)
end)

QuestTogether:RegisterTest("quest compare request still sends to group when channel join is unavailable", function()
	local sent = {}
	QuestTogether.isEnabled = true
	QuestTogether.partyMembers = {
		["Remote-Realm"] = {
			fullName = "Remote-Realm",
			classFile = "DRUID",
		},
	}
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return true
		end,
		GetChannelName = function()
			return nil
		end,
		JoinPermanentChannel = function() end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
		Delay = function() end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "player")
			return "LocalPlayer", "Realm"
		end,
	})

	WithPatchedMethod(QuestTogether, "PrintQuestCompareStart", function() end, function()
		AssertTrue(QuestTogether:RequestQuestCompare("Remote-Realm"))
	end)

	AssertEquals(#sent, 1)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "PARTY")
	AssertEquals(sent[1].target, nil)
	AssertTrue(string.find(sent[1].message, "^QCMP|", 1) ~= nil)
end)

QuestTogether:RegisterTest("quest compare entry and done use both party and channel routes when grouped", function()
	local sent = {}
	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return true
		end,
		GetChannelName = function(channelName)
			AssertEquals(channelName, QuestTogether.announcementChannelName)
			return 15
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
	})

	WithPatchedMethod(QuestTogether, "GetPlayerFullName", function()
		return "LocalPlayer-Realm"
	end, function()
		WithPatchedMethod(QuestTogether, "GetPlayerName", function()
			return "LocalPlayer"
		end, function()
			WithPatchedMethod(QuestTogether, "GetPlayerClassFile", function()
				return "MAGE"
			end, function()
				AssertTrue(QuestTogether:SendQuestCompareEntry("qcmp-1", {
					questId = "12345",
					questTitle = "A Test Quest",
					isComplete = false,
					isPushable = true,
				}))
				AssertTrue(QuestTogether:SendQuestCompareDone("qcmp-1", 1))
			end)
		end)
	end)

	AssertEquals(#sent, 4)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "PARTY")
	AssertTrue(string.find(sent[1].message, "^QCQE|", 1) ~= nil)
	AssertEquals(sent[2].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[2].channel, "CHANNEL")
	AssertEquals(sent[2].target, 15)
	AssertTrue(string.find(sent[2].message, "^QCQE|", 1) ~= nil)
	AssertEquals(sent[3].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[3].channel, "PARTY")
	AssertTrue(string.find(sent[3].message, "^QCDN|", 1) ~= nil)
	AssertEquals(sent[4].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[4].channel, "CHANNEL")
	AssertEquals(sent[4].target, 15)
	AssertTrue(string.find(sent[4].message, "^QCDN|", 1) ~= nil)
end)

QuestTogether:RegisterTest("announcement comm filter accepts grouped distributions", function()
	AssertTrue(QuestTogether:IsAnnouncementChannelEvent("PARTY"))
	AssertTrue(QuestTogether:IsAnnouncementChannelEvent("RAID"))
	AssertTrue(QuestTogether:IsAnnouncementChannelEvent("INSTANCE_CHAT"))
	AssertFalse(QuestTogether:IsAnnouncementChannelEvent("SAY"))
end)

QuestTogether:RegisterTest("incoming announcements use the transport sender name", function()
	QuestTogether.isEnabled = true
	local handledEvent = nil
	local payload = QuestTogether:EncodeAnnouncementPayload({
		version = 3,
		eventType = "QUEST_PROGRESS",
		senderGUID = "Player-2-DEF",
		classFile = "WARRIOR",
		senderName = "Forged-Realm",
		text = "2/3 Gather Apples",
		questId = "12345",
		iconAsset = "",
		iconKind = "",
		zoneName = "",
		coordX = "",
		coordY = "",
		warMode = "0",
		emoteToken = "",
	})
	local wireMessage = QuestTogether:SerializeWireMessage("ANN", payload)

	WithPatchedMethod(QuestTogether, "IsSelfSender", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "IsIgnoredPlayerName", function()
			return false
		end, function()
			WithPatchedMethod(QuestTogether, "HandleAnnouncementEvent", function(_, eventData)
				handledEvent = eventData
				return true
			end, function()
				QuestTogether:OnCommReceived(
					QuestTogether.commPrefix,
					wireMessage,
					"PARTY",
					"Actual-Realm",
					nil,
					nil
				)
			end)
		end)
	end)

	AssertTrue(handledEvent ~= nil)
	AssertEquals(handledEvent.senderName, "Actual-Realm")
end)

QuestTogether:RegisterTest("publish announcement sends even when local option is disabled", function()
	local sent = {}
	local printed = {}
	QuestTogether.isEnabled = true
	QuestTogether.db.profile.announceRemoved = false
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showChatLogs = true

	QuestTogether.API = CreateApiWithOverrides({
		IsInInstanceGroup = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInParty = function()
			return false
		end,
		GetChannelName = function()
			return 4
		end,
		SendAddonMessage = function(_, message)
			sent[#sent + 1] = message
			return 0
		end,
		UnitFullName = function()
			return "MyPlayer", "Realm"
		end,
		UnitClass = function()
			return "Mage", "MAGE"
		end,
		UnitGUID = function()
			return "Player-1-ABC"
		end,
	})
	QuestTogether.PrintRaw = function(_, message)
		printed[#printed + 1] = message
	end

	local success = QuestTogether:PublishAnnouncementEvent("QUEST_REMOVED", "Quest Removed: Test Quest")
	AssertTrue(success)
	AssertEquals(#sent, 1)
	AssertEquals(#printed, 0)
end)

QuestTogether:RegisterTest("duplicate announcements from party and channel are processed once", function()
	local handledCount = 0
	QuestTogether.isEnabled = true
	QuestTogether.announcementChannelLocalID = 6

	local payload = QuestTogether:EncodeAnnouncementPayload({
		version = 3,
		eventType = "QUEST_PROGRESS",
		senderGUID = "Player-2-DEF",
		classFile = "WARRIOR",
		senderName = "Friend-Realm",
		text = "6/8 Things",
		questId = "12345",
		iconAsset = "",
		iconKind = "",
		zoneName = "",
		coordX = "",
		coordY = "",
		warMode = "0",
		emoteToken = "",
	})
	local wireMessage = QuestTogether:SerializeWireMessage("ANN", payload)

	WithPatchedMethod(QuestTogether, "IsSelfSender", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "HandleAnnouncementEvent", function()
			handledCount = handledCount + 1
			return true
		end, function()
			QuestTogether:OnCommReceived(
				QuestTogether.commPrefix,
				wireMessage,
				"PARTY",
				"Friend-Realm",
				nil,
				nil
			)
			QuestTogether:OnCommReceived(
				QuestTogether.commPrefix,
				wireMessage,
				"CHANNEL",
				"Friend-Realm",
				6,
				QuestTogether.announcementChannelName
			)
		end)
	end)

	AssertEquals(handledCount, 1)
end)

QuestTogether:RegisterTest("duplicate ping responses from party and channel are processed once", function()
	local handledCount = 0
	QuestTogether.isEnabled = true
	QuestTogether.announcementChannelLocalID = 6
	QuestTogether.pendingPingRequests = {
		["ping-1"] = true,
	}

	local payload = QuestTogether:EncodePingResponsePayload({
		version = 2,
		requestId = "ping-1",
		senderName = "Friend-Realm",
		realmName = "Realm",
		raceName = "Night Elf",
		classFile = "DRUID",
		className = "Druid",
		level = "70",
		zoneName = "Elwynn Forest",
		coordX = "50.0",
		coordY = "50.0",
		warMode = "0",
		mapID = "37",
		addonVersion = "1.0.0",
	})
	local wireMessage = QuestTogether:SerializeWireMessage("PONG", payload)

	WithPatchedMethod(QuestTogether, "IsSelfSender", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "HandlePingResponse", function()
			handledCount = handledCount + 1
			return true
		end, function()
			QuestTogether:OnCommReceived(
				QuestTogether.commPrefix,
				wireMessage,
				"PARTY",
				"Friend-Realm",
				nil,
				nil
			)
			QuestTogether:OnCommReceived(
				QuestTogether.commPrefix,
				wireMessage,
				"CHANNEL",
				"Friend-Realm",
				6,
				QuestTogether.announcementChannelName
			)
		end)
	end)

	AssertEquals(handledCount, 1)
end)

QuestTogether:RegisterTest("duplicate quest compare entries from party and channel are processed once", function()
	local handledCount = 0
	QuestTogether.isEnabled = true
	QuestTogether.announcementChannelLocalID = 6
	QuestTogether.pendingQuestCompareRequests = {
		["qcmp-dup"] = {
			targetName = "Friend-Realm",
			classFile = "WARRIOR",
			count = 0,
		},
	}

	local payload = QuestTogether:EncodeQuestCompareEntryPayload({
		version = 1,
		requestId = "qcmp-dup",
		senderName = "Friend-Realm",
		classFile = "WARRIOR",
		questId = "12345",
		questTitle = "Test Quest",
		isComplete = false,
		isPushable = false,
	})
	local wireMessage = QuestTogether:SerializeWireMessage("QCQE", payload)

	WithPatchedMethod(QuestTogether, "IsSelfSender", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "HandleQuestCompareEntry", function()
			handledCount = handledCount + 1
			return true
		end, function()
			QuestTogether:OnCommReceived(
				QuestTogether.commPrefix,
				wireMessage,
				"PARTY",
				"Friend-Realm",
				nil,
				nil
			)
			QuestTogether:OnCommReceived(
				QuestTogether.commPrefix,
				wireMessage,
				"CHANNEL",
				"Friend-Realm",
				6,
				QuestTogether.announcementChannelName
			)
		end)
	end)

	AssertEquals(handledCount, 1)
end)

QuestTogether:RegisterTest("publish announcement is suppressed while player is dead", function()
	local sent = 0
	local handled = 0

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		GetChannelName = function()
			return 4
		end,
		SendAddonMessage = function()
			sent = sent + 1
			return 0
		end,
		UnitFullName = function()
			return "MyPlayer", "Realm"
		end,
		UnitClass = function()
			return "Mage", "MAGE"
		end,
		UnitGUID = function()
			return "Player-1-ABC"
		end,
		UnitIsDeadOrGhost = function(unitToken)
			AssertEquals(unitToken, "player")
			return true
		end,
	})

	WithPatchedMethod(QuestTogether, "HandleAnnouncementEvent", function()
		handled = handled + 1
		return true
	end, function()
		local success = QuestTogether:PublishAnnouncementEvent("WORLD_QUEST_ENTERED", "World Quest Entered: Test Quest", 12345)
		AssertFalse(success)
	end)

	AssertEquals(sent, 0)
	AssertEquals(handled, 0)
end)

QuestTogether:RegisterTest("announcement channel chat filter hides QuestTogether channel messages", function()
	AssertTrue(
		QuestTogether:AnnouncementChannelChatFilter(
			nil,
			"CHAT_MSG_CHANNEL_NOTICE_USER",
			"JOINED",
			"Azethmis",
			"",
			QuestTogether.announcementChannelName,
			"",
			"",
			"",
			"1. " .. QuestTogether.announcementChannelName
		)
	)
	AssertFalse(QuestTogether:AnnouncementChannelChatFilter(nil, "CHAT_MSG_CHANNEL_NOTICE_USER", "JOINED", "Azethmis", "", "General"))
end)

QuestTogether:RegisterTest("joining announcement channel removes it from chat windows", function()
	local removed = {}

	QuestTogether.isEnabled = true
	QuestTogether.API = CreateApiWithOverrides({
		GetChannelName = function(name)
			AssertEquals(name, QuestTogether.announcementChannelName)
			return 7
		end,
		JoinPermanentChannel = function() end,
		GetNumChatWindows = function()
			return 2
		end,
		GetChatFrameByID = function(chatFrameID)
			return {
				GetID = function()
					return chatFrameID
				end,
				RemoveChannel = function(_, channelName)
					removed[#removed + 1] = tostring(chatFrameID) .. ":" .. tostring(channelName)
				end,
			}
		end,
		RemoveChatWindowChannel = function(chatFrame, channelName)
			chatFrame:RemoveChannel(channelName)
		end,
		AddMessageEventFilter = function() end,
	})

	AssertTrue(QuestTogether:EnsureAnnouncementChannelJoined())
	AssertEquals(#removed, 2)
	AssertEquals(removed[1], "1:" .. QuestTogether.announcementChannelName)
	AssertEquals(removed[2], "2:" .. QuestTogether.announcementChannelName)
end)

QuestTogether:RegisterTest("target test announcement sends target payload and handles locally as remote", function()
	local sent = {}
	local handledEvent = nil

	QuestTogether.isEnabled = true
		QuestTogether.API = CreateApiWithOverrides({
			IsInInstanceGroup = function()
				return false
			end,
			IsInRaid = function()
				return false
			end,
			IsInParty = function()
				return false
			end,
			UnitExists = function(unitToken)
				AssertEquals(unitToken, "target")
				return true
		end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "target")
			return "Nearby", "Realm"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "target")
			return "Mage", "MAGE"
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "target")
			return "Player-2-XYZ"
		end,
		UnitIsPlayer = function(unitToken)
			AssertEquals(unitToken, "target")
			return true
		end,
		GetChannelName = function()
			return 8
		end,
		SendAddonMessage = function(prefix, message, channel, target)
			sent[#sent + 1] = {
				prefix = prefix,
				message = message,
				channel = channel,
				target = target,
			}
			return 0
		end,
	})

	WithPatchedMethod(QuestTogether, "HandleAnnouncementEvent", function(_, eventData, isLocal)
		handledEvent = {
			eventType = eventData.eventType,
			senderGUID = eventData.senderGUID,
			classFile = eventData.classFile,
			senderName = eventData.senderName,
			text = eventData.text,
			isLocal = isLocal,
		}
		return true
	end, function()
		local ok, senderName = QuestTogether:SendBubbleAnnouncementTest("Testing nearby player bubble")
		AssertTrue(ok)
		AssertEquals(senderName, "Nearby-Realm")
	end)
	AssertEquals(#sent, 1)
	AssertEquals(sent[1].prefix, QuestTogether.commPrefix)
	AssertEquals(sent[1].channel, "CHANNEL")
	AssertEquals(sent[1].target, 8)
	AssertTrue(string.find(sent[1].message, "^ANN|", 1) ~= nil)
	AssertEquals(handledEvent.eventType, "QUEST_PROGRESS")
	AssertEquals(handledEvent.senderGUID, "Player-2-XYZ")
	AssertEquals(handledEvent.classFile, "MAGE")
	AssertEquals(handledEvent.senderName, "Nearby-Realm")
	AssertEquals(handledEvent.text, "Testing nearby player bubble")
	AssertFalse(handledEvent.isLocal)
end)

QuestTogether:RegisterTest("bubble test announcement uses explicit visible player name without target", function()
	local sentEvent = nil
	local handledEvent = nil
	local nearbyFrame = {
		GetUnit = function()
			return "nameplate7"
		end,
	}
	QuestTogether.isEnabled = true

	QuestTogether.API = CreateApiWithOverrides({
		UnitExists = function(unitToken)
			AssertEquals(unitToken, "target")
			return false
		end,
		UnitFullName = function(unitToken)
			AssertEquals(unitToken, "nameplate7")
			return "Nearby", "Realm"
		end,
		UnitClass = function(unitToken)
			AssertEquals(unitToken, "nameplate7")
			return "Mage", "MAGE"
		end,
		UnitGUID = function(unitToken)
			AssertEquals(unitToken, "nameplate7")
			return "Player-2-XYZ"
		end,
	})

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function(_, senderGUID, senderName)
		AssertEquals(senderGUID, "")
		AssertEquals(senderName, "Nearby")
		return nearbyFrame
	end, function()
		WithPatchedMethod(QuestTogether, "SendAnnouncementWireEvent", function(_, eventData)
			sentEvent = {
				eventType = eventData.eventType,
				senderGUID = eventData.senderGUID,
				classFile = eventData.classFile,
				senderName = eventData.senderName,
				text = eventData.text,
			}
			return true
		end, function()
			WithPatchedMethod(QuestTogether, "HandleAnnouncementEvent", function(_, eventData, isLocal)
				handledEvent = {
					eventType = eventData.eventType,
					senderGUID = eventData.senderGUID,
					classFile = eventData.classFile,
					senderName = eventData.senderName,
					text = eventData.text,
					isLocal = isLocal,
				}
				return true
			end, function()
				local ok, senderName = QuestTogether:SendBubbleAnnouncementTest("Testing nearby player bubble", "Nearby")
				AssertTrue(ok)
				AssertEquals(senderName, "Nearby-Realm")
			end)
		end)
	end)

	AssertTrue(sentEvent ~= nil)
	AssertEquals(sentEvent.eventType, "QUEST_PROGRESS")
	AssertEquals(sentEvent.senderGUID, "Player-2-XYZ")
	AssertEquals(sentEvent.classFile, "MAGE")
	AssertEquals(sentEvent.senderName, "Nearby-Realm")
	AssertEquals(sentEvent.text, "Testing nearby player bubble")
	AssertEquals(handledEvent.eventType, "QUEST_PROGRESS")
	AssertEquals(handledEvent.senderGUID, "Player-2-XYZ")
	AssertEquals(handledEvent.classFile, "MAGE")
	AssertEquals(handledEvent.senderName, "Nearby-Realm")
	AssertEquals(handledEvent.text, "Testing nearby player bubble")
	AssertFalse(handledEvent.isLocal)
end)

QuestTogether:RegisterTest("remote grouped sender prints chat log without nearby nameplate", function()
	local printed = {}
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_only"
	QuestTogether.partyMembers = {
		["Friend-Realm"] = {
			fullName = "Friend-Realm",
			classFile = "WARRIOR",
		},
	}

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	local handled = QuestTogether:HandleAnnouncementEvent({
		eventType = "QUEST_PROGRESS",
		senderGUID = "Player-2-DEF",
		classFile = "WARRIOR",
		senderName = "Friend-Realm",
		text = "6/8 Things",
	}, false)

	AssertTrue(handled)
	AssertEquals(#printed, 1)
	AssertTrue(string.find(printed[1], "Friend", 1, true) ~= nil)
	AssertTrue(string.find(printed[1], "|cffffd200: 6/8 Things|r", 1, true) ~= nil)
end)

QuestTogether:RegisterTest("remote nearby nongroup sender is filtered by party only scope", function()
	local printed = 0
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_only"

	QuestTogether.PrintChatLogRaw = function()
		printed = printed + 1
	end

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return { UnitFrame = {} }
	end, function()
		local handled = QuestTogether:HandleAnnouncementEvent({
			eventType = "QUEST_PROGRESS",
			senderGUID = "Player-3-GHI",
			classFile = "DRUID",
			senderName = "Nearby-Realm",
			text = "2/4 Crates",
		}, false)

		AssertFalse(handled)
		AssertEquals(printed, 0)
	end)
end)

QuestTogether:RegisterTest("remote nearby sender shows bubble and chat log for party & nearby scope", function()
	local printed = {}
	local bubbleText = nil
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.showProgressFor = "party_nearby"

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	local nearbyFrame = { UnitFrame = {} }

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function(_, senderGUID, senderName)
		AssertEquals(senderGUID, "Player-4-JKL")
		AssertEquals(senderName, "Nearby-Realm")
		return nearbyFrame
	end, function()
		WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnNameplate", function(_, frame, text)
			AssertTrue(frame == nearbyFrame)
			bubbleText = text
			return true
		end, function()
			local handled = QuestTogether:HandleAnnouncementEvent({
				eventType = "QUEST_PROGRESS",
				senderGUID = "Player-4-JKL",
				classFile = "PRIEST",
				senderName = "Nearby-Realm",
				text = "4/4 Widgets",
			}, false)

			AssertTrue(handled)
			AssertEquals(#printed, 1)
			AssertEquals(bubbleText, "4/4 Widgets")
		end)
	end)
end)

QuestTogether:RegisterTest("remote nearby completion plays synced emote", function()
	local emoteCalls = {}
	QuestTogether.db.profile.emoteOnNearbyPlayerQuestCompletion = true

	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function(token, target)
			emoteCalls[#emoteCalls + 1] = token .. ":" .. tostring(target)
		end,
	})

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function(_, senderGUID, senderName)
			AssertEquals(senderGUID, "Player-4-JKL")
			AssertEquals(senderName, "Nearby-Realm")
			return "target"
		end, function()
			WithPatchedMethod(QuestTogether, "PrintConsoleAnnouncement", function() end, function()
				AssertTrue(QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_COMPLETED",
					senderGUID = "Player-4-JKL",
					classFile = "MAGE",
					senderName = "Nearby-Realm",
					text = "Quest Completed: Widgets",
					emoteToken = "cheer",
				}, false))
			end)
		end)
	end)

	AssertEquals(#emoteCalls, 1)
	AssertEquals(emoteCalls[1], "cheer:target")
end)

QuestTogether:RegisterTest("remote far completion does not play synced emote", function()
	local emoteCalls = 0
	QuestTogether.db.profile.emoteOnNearbyPlayerQuestCompletion = true

	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function()
			emoteCalls = emoteCalls + 1
		end,
	})

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function()
			return nil
		end, function()
			WithPatchedMethod(QuestTogether, "IsAnnouncementSenderNearbyByLocation", function()
				return false
			end, function()
				AssertFalse(QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_COMPLETED",
					senderGUID = "Player-4-JKL",
					classFile = "MAGE",
					senderName = "Faraway-Realm",
					text = "Quest Completed: Widgets",
					emoteToken = "cheer",
					zoneName = "Elsewhere",
					coordX = "1.0",
					coordY = "1.0",
					warMode = "1",
				}, false))
			end)
		end)
	end)

	AssertEquals(emoteCalls, 0)
end)

QuestTogether:RegisterTest("remote nearby completion emote obeys nearby-player emote option", function()
	local emoteCalls = 0
	QuestTogether.db.profile.emoteOnNearbyPlayerQuestCompletion = false

	QuestTogether.API = CreateApiWithOverrides({
		DoEmote = function()
			emoteCalls = emoteCalls + 1
		end,
	})

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function()
			return "target"
		end, function()
			WithPatchedMethod(QuestTogether, "PrintConsoleAnnouncement", function() end, function()
				AssertTrue(QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_COMPLETED",
					senderGUID = "Player-4-JKL",
					classFile = "MAGE",
					senderName = "Nearby-Realm",
					text = "Quest Completed: Widgets",
					emoteToken = "cheer",
				}, false))
			end)
		end)
	end)

	AssertEquals(emoteCalls, 0)
end)

QuestTogether:RegisterTest("remote sender with matching target prints chat log without a nameplate", function()
	local printed = {}
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_nearby"

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function(_, senderGUID, senderName)
			AssertEquals(senderGUID, "Player-9-ZZZ")
			AssertEquals(senderName, "Targeted-Realm")
			return "target"
		end, function()
			local handled = QuestTogether:HandleAnnouncementEvent({
				eventType = "QUEST_PROGRESS",
				senderGUID = "Player-9-ZZZ",
				classFile = "DRUID",
				senderName = "Targeted-Realm",
				text = "7/7 Notes",
			}, false)

			AssertTrue(handled)
			AssertEquals(#printed, 1)
			AssertTrue(string.find(printed[1], "Targeted", 1, true) ~= nil)
			AssertTrue(string.find(printed[1], "|cffffd200: 7/7 Notes|r", 1, true) ~= nil)
		end)
	end)
end)

QuestTogether:RegisterTest("remote sender nearby by location prints chat log without nameplate", function()
	local printed = {}
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_nearby"

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function()
			return nil
		end, function()
			WithPatchedMethod(QuestTogether, "IsAnnouncementSenderNearbyByLocation", function(_, locationInfo)
				AssertEquals(locationInfo.zoneName, "Eversong Woods")
				AssertEquals(locationInfo.coordX, "41.0")
				AssertEquals(locationInfo.coordY, "52.0")
				AssertEquals(locationInfo.warMode, "1")
				return true
			end, function()
				local handled = QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_PROGRESS",
					senderGUID = "Player-8-LOC",
					classFile = "PALADIN",
					senderName = "NearbyCoords-Realm",
					text = "3/3 Crystals",
					zoneName = "Eversong Woods",
					coordX = "41.0",
					coordY = "52.0",
					warMode = "1",
				}, false)

				AssertTrue(handled)
				AssertEquals(#printed, 1)
				AssertTrue(string.find(printed[1], "NearbyCoords", 1, true) ~= nil)
				AssertTrue(string.find(printed[1], "|cffffd200: 3/3 Crystals|r", 1, true) ~= nil)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("remote sender with mismatched location signal stays filtered", function()
	local printed = 0
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = false
	QuestTogether.db.profile.showProgressFor = "party_nearby"

	QuestTogether.PrintChatLogRaw = function()
		printed = printed + 1
	end

	WithPatchedMethod(QuestTogether, "FindVisiblePlayerNameplateForSender", function()
		return nil
	end, function()
		WithPatchedMethod(QuestTogether, "FindNearbyPlayerUnitTokenForSender", function()
			return nil
		end, function()
			WithPatchedMethod(QuestTogether, "IsAnnouncementSenderNearbyByLocation", function()
				return false
			end, function()
				local handled = QuestTogether:HandleAnnouncementEvent({
					eventType = "QUEST_PROGRESS",
					senderGUID = "Player-8-FAR",
					classFile = "PALADIN",
					senderName = "FarCoords-Realm",
					text = "3/3 Crystals",
					zoneName = "Eversong Woods",
					coordX = "41.0",
					coordY = "52.0",
					warMode = "0",
				}, false)

				AssertFalse(handled)
				AssertEquals(printed, 0)
			end)
		end)
	end)
end)

QuestTogether:RegisterTest("dev log all announcements prints remote sender without nearby signal", function()
	local printed = {}
	local bubbleCalls = 0
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.showProgressFor = "party_only"
	QuestTogether.db.profile.devLogAllAnnouncements = true

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnNameplate", function()
		bubbleCalls = bubbleCalls + 1
		return true
	end, function()
		local handled = QuestTogether:HandleAnnouncementEvent({
			eventType = "QUEST_PROGRESS",
			senderGUID = "Player-7-DEV",
			classFile = "SHAMAN",
			senderName = "Faraway-Realm",
			text = "9/9 Mischief",
		}, false)

		AssertTrue(handled)
		AssertEquals(#printed, 1)
		AssertEquals(bubbleCalls, 0)
		AssertTrue(string.find(printed[1], "Faraway", 1, true) ~= nil)
		AssertTrue(string.find(printed[1], "|cffffd200: 9/9 Mischief|r", 1, true) ~= nil)
	end)
end)

QuestTogether:RegisterTest("local announcement hides own bubble when configured", function()
	local printed = {}
	local bubbleCalls = 0
	QuestTogether.db.profile.showChatLogs = true
	QuestTogether.db.profile.showChatBubbles = true
	QuestTogether.db.profile.hideMyOwnChatBubbles = true

	QuestTogether.PrintChatLogRaw = function(_, message)
		printed[#printed + 1] = message
	end

	WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnUnitNameplate", function()
		bubbleCalls = bubbleCalls + 1
		return true
	end, function()
		local handled = QuestTogether:HandleAnnouncementEvent({
			eventType = "QUEST_ACCEPTED",
			senderGUID = "Player-1-ABC",
			classFile = "MAGE",
			senderName = "MyPlayer-Realm",
			text = "Quest Accepted: Test Quest",
		}, true)

		AssertTrue(handled)
		AssertEquals(#printed, 1)
		AssertEquals(bubbleCalls, 0)
	end)
end)

QuestTogether:RegisterTest("resolved sender identity rejects a conflicting guid", function()
	AssertFalse(
		QuestTogether:DoesResolvedUnitIdentityMatchSender(
			"Player-1-LIVE",
			"Nearby-Realm",
			"Player-2-PAYLOAD",
			"Nearby-Realm"
		)
	)
	AssertTrue(
		QuestTogether:DoesResolvedUnitIdentityMatchSender(
			"Player-1-LIVE",
			"Nearby-Realm",
			"Player-1-LIVE",
			"Nearby-Realm"
		)
	)
end)

QuestTogether:RegisterTest("restricted sender lookup does not enumerate foreign nameplates", function()
	WithPatchedMethod(QuestTogether, "IsWorkBlocked", function(_, workClass)
		AssertEquals(workClass, "foreign_frame_mutation")
		return true
	end, function()
		WithPatchedMethod(QuestTogether, "ForEachVisibleNamePlate", function()
			error("restricted sender lookup must not enumerate nameplates")
		end, function()
			AssertEquals(
				QuestTogether:FindVisiblePlayerNameplateForSender("Player-1-LIVE", "Nearby-Realm"),
				nil
			)
		end)
	end)
end)

QuestTogether:RegisterTest("refresh active announcement bubbles does not replay an already playing personal bubble", function()
	QuestTogether.isEnabled = true
	local showCalls = 0
	local unitFrame = {}
	local bubble = {
		animationGroup = {
			IsPlaying = function()
				return true
			end,
		},
	}
	local screenHostFrame = {
		UnitFrame = unitFrame,
	}

	QuestTogether.announcementBubbleScreenHostFrame = screenHostFrame
	QuestTogether.nameplateBubbleByUnitFrame[unitFrame] = bubble
	QuestTogether.nameplateBubbleStateByFrame[bubble] = {
		text = "80% Locations Photographed",
		eventType = "QUEST_PROGRESS",
		unitToken = "player",
	}

	WithPatchedMethod(QuestTogether, "IsAnnouncementBubbleAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "GetAnnouncementBubbleHostFrameForUnit", function(_, unitToken)
			AssertEquals(unitToken, "player")
			return screenHostFrame
		end, function()
			WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnNameplate", function()
				showCalls = showCalls + 1
				return true
			end, function()
				QuestTogether:RefreshActiveAnnouncementBubbles()
			end)
		end)
	end)

	AssertEquals(showCalls, 0)
end)

QuestTogether:RegisterTest("restricted bubble refresh clears side-table state without mutating the visual", function()
	local unitFrame = {}
	local bubble = {
		animationGroup = {
			IsPlaying = function()
				error("restricted refresh must not inspect the animation")
			end,
			Stop = function()
				error("restricted refresh must not stop the animation")
			end,
		},
		SetAlpha = function()
			error("restricted refresh must not change visual alpha")
		end,
		Hide = function()
			error("restricted refresh must not hide the visual")
		end,
	}
	QuestTogether.nameplateBubbleByUnitFrame[unitFrame] = bubble
	QuestTogether.nameplateBubbleStateByFrame[bubble] = {
		text = "2/3 Gather Apples",
		eventType = "QUEST_PROGRESS",
		unitToken = "nameplate1",
	}

	WithPatchedMethod(QuestTogether, "IsAnnouncementBubbleAugmentationBlockedInCurrentContext", function(_, unitToken)
		AssertEquals(unitToken, "nameplate1")
		return true
	end, function()
		QuestTogether:RefreshActiveAnnouncementBubbles()
		local quiescedState = QuestTogether.nameplateBubbleStateByFrame[bubble]
		AssertTrue(quiescedState ~= nil)
		AssertEquals(quiescedState.unitToken, "nameplate1")
		AssertEquals(quiescedState.text, nil)

		-- The animation can finish while restrictions are still active. It must
		-- clear the final side-table marker without touching the visual.
		AssertFalse(QuestTogether:CompleteAnnouncementBubblePlayback(bubble))
	end)

	AssertEquals(QuestTogether.nameplateBubbleStateByFrame[bubble], nil)
end)

QuestTogether:RegisterTest("hide announcement bubble clears stored bubble state", function()
	local unitFrame = {}
	local bubble = {
		animationGroup = {
			IsPlaying = function()
				return false
			end,
		},
		SetAlpha = function() end,
		Hide = function() end,
	}
	local hostFrame = {
		UnitFrame = unitFrame,
	}

	QuestTogether.nameplateBubbleByUnitFrame[unitFrame] = bubble
	QuestTogether.nameplateBubbleStateByFrame[bubble] = {
		text = "80% Locations Photographed",
		eventType = "QUEST_PROGRESS",
		unitToken = "player",
	}

	QuestTogether:HideAnnouncementBubble(hostFrame)

	AssertEquals(QuestTogether.nameplateBubbleStateByFrame[bubble], nil)
end)

QuestTogether:RegisterTest("completed announcement bubble playback clears stored bubble state", function()
	local hidden = false
	local alpha = 1
	local showCalls = 0
	local unitFrame = {}
	local bubble = {
		SetAlpha = function(_, value)
			alpha = value
		end,
		Hide = function()
			hidden = true
		end,
	}
	QuestTogether.nameplateBubbleByUnitFrame[unitFrame] = bubble
	QuestTogether.nameplateBubbleStateByFrame[bubble] = {
		text = "2/3 Gather Apples",
		eventType = "QUEST_PROGRESS",
		unitToken = "nameplate1",
	}

	AssertTrue(QuestTogether:CompleteAnnouncementBubblePlayback(bubble))
	AssertEquals(QuestTogether.nameplateBubbleStateByFrame[bubble], nil)
	AssertEquals(alpha, 0)
	AssertTrue(hidden)

	WithPatchedMethod(QuestTogether, "IsAnnouncementBubbleAugmentationBlockedInCurrentContext", function()
		return false
	end, function()
		WithPatchedMethod(QuestTogether, "ShowAnnouncementBubbleOnNameplate", function()
			showCalls = showCalls + 1
		end, function()
			QuestTogether:RefreshActiveAnnouncementBubbles()
		end)
	end)
	AssertEquals(showCalls, 0)
end)

QuestTogether:RegisterTest("completed protected bubble playback avoids visual mutation while restricted", function()
	local bubble = {
		IsProtected = function()
			return true, false
		end,
		SetAlpha = function()
			error("restricted protected bubble must not change alpha")
		end,
		Hide = function()
			error("restricted protected bubble must not hide")
		end,
	}
	QuestTogether.nameplateBubbleStateByFrame[bubble] = {
		text = "2/3 Gather Apples",
		eventType = "QUEST_PROGRESS",
		unitToken = "nameplate1",
	}

	WithPatchedMethod(QuestTogether, "IsRuntimeRestricted", function()
		return true
	end, function()
		AssertFalse(QuestTogether:CompleteAnnouncementBubblePlayback(bubble))
	end)

	AssertEquals(QuestTogether.nameplateBubbleStateByFrame[bubble], nil)
end)
