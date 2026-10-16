-- Addon-owned fixtures only. Native adapter contracts live in client_profiles.lua.
local QT = _G.QuestTogether
local function Fixture()
	local a = setmetatable(
		{ now = 100, reads = 0, loads = 0, blocked = false, snapshots = {}, titles = {} },
		{ __index = QT }
	)
	a.API = {
		GetTime = function()
			return a.now
		end,
		GetLocalizedQuestTitle = function(id)
			a.reads = a.reads + 1
			return a.titles[id]
		end,
		RequestLocalizedQuestTitle = function()
			a.loads = a.loads + 1
		end,
	}
	function a:GetQuestSnapshot(id)
		return self.snapshots[id]
	end
	function a:IsWorkBlocked()
		return self.blocked
	end
	return a
end
local function Event(kind, facts, text)
	return {
		eventType = kind or "QUEST_PROGRESS",
		questId = "12345",
		senderName = "Friend-Realm",
		text = text or "Wolves slain: 3/8",
		eventFacts = facts or "1:deDE:c:2:3:8",
	}
end

local function RoundTrip(a, event)
	local owned = assert(a:SanitizeAnnouncementEventData(event))
	return assert(a:DecodeCommRecord("ANN", assert(a:EncodeCommRecord("ANN", owned))))
end

local function PresentationFixture()
	local a, clock = Fixture(), QT:CreateTestClock(100)
	a.isEnabled, a.chat, a.bubbles, a.emotes = true, {}, {}, 0
	a.work = { entries = {}, generations = {} }
	a.API.GetTime = function() return clock:GetTime() end
	a.API.Delay = function(delay, callback) clock:After(delay, callback) end
	function a:GetDeferredWorkStateStore() return self.work end
	function a:IsWorkBlocked(kind) return kind ~= "announcement_presentation" and self.blocked end
	function a:ShouldDisplayAnnouncementType() return not self.suppressed end
	function a:IsIgnoredPlayerName() return self.ignored == true end
	function a:NormalizeMemberName(name) return name end
	function a:GetGroupedSenderClassFile() return "MAGE" end
	function a:FindVisiblePlayerNameplateForSender() return {} end
	function a:GetAccessibleFrameMember() end
	function a:IsGroupedSender() return self.inScope ~= false end
	function a:ShouldShowAnnouncementsForRemoteSender() return self.inScope ~= false end
	function a:GetOption(key) return key == "showChatLogs" or key == "showChatBubbles" end
	function a:PrintConsoleAnnouncement(text) self.chat[#self.chat + 1] = text end
	function a:ShowAnnouncementBubbleOnNameplate(_, text) self.bubbles[#self.bubbles + 1] = text end
	function a:PlayRemoteCelebrationEmote() self.emotes = self.emotes + 1 end
	function a:RecordCommsDiagnostic() end
	function a:Debugf(_, _, err) error(tostring(err)) end
	return a, clock
end

local function KoreanQuest(kind)
	kind = kind or "QUEST_COMPLETED"
	local prefix = kind == "QUEST_ACCEPTED" and "Quest Accepted: " or "Quest Completed: "
	return Event(kind, "1:koKR:q:::", QT.TranslateForLocale(prefix, "koKR") .. "결속")
end

QT:RegisterTest("cold foreign quest announcements wait for one local title before printing exactly once", function()
	local a, clock = PresentationFixture()
	local accepted, completed = KoreanQuest("QUEST_ACCEPTED"), KoreanQuest()
	assert(a:HandleAnnouncementEvent(accepted, false))
	assert(a:HandleAnnouncementEvent(completed, false))
	assert(#a.chat == 0 and #a.bubbles == 0 and a.emotes == 0 and a.loads == 1)
	a.titles[12345] = "The Binding"
	a:QUEST_DATA_LOAD_RESULT(nil, 12345, true)
	assert(#a.chat == 0, "load event must defer guarded presentation to the next frame")
	clock:Advance(0)
	assert(a.chat[1] == "Quest Accepted: The Binding" and a.chat[2] == "Quest Completed: The Binding")
	assert(a.bubbles[1] == a.chat[1] and a.bubbles[2] == a.chat[2] and a.emotes == 1)
	a:QUEST_DATA_LOAD_RESULT(nil, 12345, true)
	clock:Advance(2)
	assert(#a.chat == 2 and a.localizedQuestTitles.waitingCount == 0 and a.emotes == 1)
	assert(completed.text:find("결속", 1, true), "incoming event must retain its original wire text")
end)

QT:RegisterTest("pending quest announcements preserve order through title readiness and progress", function()
	local a, clock = PresentationFixture()
	a:HandleAnnouncementEvent(KoreanQuest("QUEST_ACCEPTED"), false)
	a:HandleAnnouncementEvent(Event("QUEST_PROGRESS", "1:koKR:c:1:1:2", "First objective: 1/2"), false)
	a.titles[12345] = "The Binding"
	a:QUEST_DATA_LOAD_RESULT(nil, 12345, true)
	-- The cache is ready before the next-frame presentation callback runs.
	a:HandleAnnouncementEvent(KoreanQuest(), false)
	assert(#a.chat == 0 and #a.bubbles == 0 and a.localizedQuestTitles.waitingCount == 3)
	clock:Advance(0)
	assert(table.concat(a.chat, " | ") == "Quest Accepted: The Binding | First objective: 1/2 | Quest Completed: The Binding")
	assert(table.concat(a.bubbles, " | ") == table.concat(a.chat, " | ") and a.emotes == 1)
	clock:Advance(2)
	assert(#a.chat == 3 and a.localizedQuestTitles.waitingCount == 0)
end)

QT:RegisterTest("quest announcement cohorts retain their deadline without blocking other senders or quests", function()
	local a, clock = PresentationFixture()
	a:HandleAnnouncementEvent(KoreanQuest("QUEST_ACCEPTED"), false)
	clock:Advance(1.9)
	a:HandleAnnouncementEvent(Event("QUEST_PROGRESS", "1:koKR:c:1:1:2", "Own cohort: 1/2"), false)
	local other = Event("QUEST_PROGRESS", "1:koKR:c:1:1:2", "Other sender: 1/2")
	other.senderName = "Other-Realm"
	a:HandleAnnouncementEvent(other, false)
	other = Event("QUEST_PROGRESS", "1:koKR:c:1:1:2", "Other quest: 1/2")
	other.questId = "54321"
	a:HandleAnnouncementEvent(other, false)
	assert(#a.chat == 2 and a.chat[1] == "Other sender: 1/2" and a.chat[2] == "Other quest: 1/2")
	clock:Advance(0.11)
	assert(a.chat[3] == "Quest Accepted: 결속" and a.chat[4] == "Own cohort: 1/2")
	assert(a.localizedQuestTitles.waitingCount == 0 and a.loads == 1)
end)

QT:RegisterTest("quest announcement overflow flushes predecessors once and rechecks the final event", function()
	for _, stop in ipairs({ false, true }) do
		local a, clock = PresentationFixture()
		a:HandleAnnouncementEvent(KoreanQuest("QUEST_ACCEPTED"), false)
		local stale = clock.timers[1].callback
		for i = 1, 31 do
			a:HandleAnnouncementEvent(Event("QUEST_PROGRESS", "1:koKR:c:1:1:2", "Progress " .. i), false)
		end
		assert(a.localizedQuestTitles.waitingCount == 32 and #a.chat == 0)
		if stop then
			function a:PrintConsoleAnnouncement(text)
				self.chat[#self.chat + 1] = text
				if #self.chat == 32 then self.ignored = true end
			end
		end
		a:HandleAnnouncementEvent(KoreanQuest(), false)
		assert(a.localizedQuestTitles.waitingCount == 0 and #a.chat == (stop and 32 or 33))
		assert(a.chat[1] == "Quest Accepted: 결속")
		for i = 1, 31 do assert(a.chat[i + 1] == "Progress " .. i) end
		if not stop then assert(a.chat[33] == "Quest Completed: 결속") end
		stale()
		clock:Advance(2)
		assert(#a.chat == (stop and 32 or 33), "retired timeout cannot replay the flushed cohort")
	end
end)

QT:RegisterTest("retired announcement cohorts release payloads and cannot consume a replacement cohort", function()
	local a, clock = PresentationFixture()
	a:HandleAnnouncementEvent(KoreanQuest("QUEST_ACCEPTED"), false)
	local stale, retired = clock.timers[1].callback, next(a.localizedQuestTitles.waiting)
	retired = a.localizedQuestTitles.waiting[retired]
	for i = 1, 32 do
		a:HandleAnnouncementEvent(Event("QUEST_PROGRESS", "1:koKR:c:1:1:2", "Progress " .. i), false)
	end
	assert(#a.chat == 33 and retired.events == nil and retired.owner.active == false)
	a:HandleAnnouncementEvent(KoreanQuest("QUEST_ACCEPTED"), false)
	assert(a.localizedQuestTitles.waitingCount == 1)
	stale()
	assert(#a.chat == 33 and a.localizedQuestTitles.waitingCount == 1)
	-- A new packet can arrive after the deadline but before that frame's timer.
	clock.now = 103
	a:HandleAnnouncementEvent(Event("QUEST_PROGRESS", "1:koKR:c:1:1:2", "After deadline: 1/2"), false)
	assert(a.chat[34] == "Quest Accepted: 결속" and a.chat[35] == "After deadline: 1/2")
	clock:Advance(0)
	assert(#a.chat == 35 and a.localizedQuestTitles.waitingCount == 0)
end)

QT:RegisterTest("quest announcement timeout checks newly cached tooltip data and preserves unavailable titles", function()
	for _, loaded in ipairs({ false, true }) do
		local a, clock = PresentationFixture()
		assert(a:HandleAnnouncementEvent(KoreanQuest(), false))
		clock:Advance(1.99)
		assert(#a.chat == 0)
		if loaded then a.titles[12345] = "The Binding" end
		clock:Advance(0.02)
		assert(#a.chat == 1 and a.chat[1] == "Quest Completed: " .. (loaded and "The Binding" or "결속"))
		assert(a.loads == 1, "timeout must reuse the native request budget")
		a.titles[12345] = "The Binding"
		a:QUEST_DATA_LOAD_RESULT(nil, 12345, true)
		clock:Advance(10)
		assert(#a.chat == 1 and a.emotes == 1, "late success must not double-print or repeat emotes")
	end
	local a, clock = PresentationFixture()
	a:HandleAnnouncementEvent(KoreanQuest(), false)
	a:QUEST_DATA_LOAD_RESULT(nil, 12345, false)
	clock:Advance(0)
	assert(#a.chat == 1 and a.chat[1] == "Quest Completed: 결속")
end)

QT:RegisterTest("pending localized announcements recheck consent scope and lifetime before presentation", function()
	for _, change in ipairs({ "ignored", "suppressed", "scope", "disabled", "logout", "reset", "zoning" }) do
		local a, clock = PresentationFixture()
		a:HandleAnnouncementEvent(KoreanQuest(), false)
		local stale = clock.timers[1].callback
		if change == "ignored" or change == "suppressed" then a[change] = true
		elseif change == "scope" then a.inScope = false
		elseif change == "disabled" then a.isEnabled = false
		elseif change == "logout" then a.isLoggingOut = true
		elseif change == "zoning" then
			function a:EndCommunicationSession() end
			a:EndCommsWorldSession()
		else a:ResetLocalizedQuestTitles() end
		a.titles[12345] = "The Binding"
		a:QUEST_DATA_LOAD_RESULT(nil, 12345, true)
		clock:Advance(2)
		stale()
		assert(#a.chat == 0 and #a.bubbles == 0 and a.emotes == 0, change)
	end
end)

QT:RegisterTest("local title waiting is bounded and does not delay same-language progress or restricted display", function()
	local a, clock = PresentationFixture()
	for _ = 1, 40 do a:HandleAnnouncementEvent(KoreanQuest(), false) end
	assert(a.localizedQuestTitles.waitingCount == 7 and #a.chat == 33 and a.loads == 1)
	clock:Advance(2)
	assert(#a.chat == 40 and a.localizedQuestTitles.waitingCount == 0)
	a, clock = PresentationFixture()
	a:HandleAnnouncementEvent(Event("QUEST_COMPLETED", "1:enUS:q:::", "Quest Completed: The Binding"), false)
	a:HandleAnnouncementEvent(Event("QUEST_PROGRESS", "1:koKR:c:1:1:2", "Native objective: 1/2"), false)
	assert(#a.chat == 2 and #clock.timers == 0)
	a.blocked = true
	local reads, loads, event = a.reads, a.loads, KoreanQuest()
	local original = event.text
	a:HandleAnnouncementEvent(event, false)
	assert(#a.chat == 3 and a.chat[3] == "Quest Completed: 결속", "restricted reads must not hold up localized chat")
	assert(a.reads == reads and a.loads == loads and event.text == original)
	a, clock = PresentationFixture()
	for id = 1, 10 do a:GetLocalizedQuestTitle(id) end
	a:HandleAnnouncementEvent(KoreanQuest(), false)
	assert(#a.chat == 1 and #clock.timers == 0 and a.loads == 10, "budget rejection must not wait")
	a, clock = PresentationFixture()
	a.API.RequestLocalizedQuestTitle = function() return false end
	a:HandleAnnouncementEvent(KoreanQuest(), false)
	assert(#a.chat == 1 and #clock.timers == 0, "unavailable native loading must not wait")
end)

QT:RegisterTest("retired title callbacks cannot consume a replacement wait or keep presentation blocked in combat", function()
	local a, clock = PresentationFixture()
	a:HandleAnnouncementEvent(KoreanQuest(), false)
	local stale = clock.timers[1].callback
	a:ResetLocalizedQuestTitles()
	a:HandleAnnouncementEvent(KoreanQuest(), false)
	stale()
	assert(#a.chat == 0 and a.localizedQuestTitles.waitingCount == 1)
	a.titles[12345] = "The Binding"
	a:QUEST_DATA_LOAD_RESULT(nil, 12345, true)
	clock:Advance(0)
	clock:Advance(2)
	assert(#a.chat == 1 and a.chat[1] == "Quest Completed: The Binding")
	a, clock = PresentationFixture()
	a:HandleAnnouncementEvent(KoreanQuest(), false)
	a.blocked = true
	clock:Advance(2)
	assert(#a.chat == 1 and a.chat[1] == "Quest Completed: 결속" and a.localizedQuestTitles.waitingCount == 0)
	a.blocked = false
	clock:Advance(30)
	assert(#a.chat == 1)
end)

QT:RegisterTest("ready announcements replace a captured placeholder with a loaded local title", function()
	local a = Fixture()
	a.pendingQuestRemovals, a.questsCompleted = {}, {}
	local tracker = { [12345] = { title = "Quest 12345", isReadyForTurnIn = false } }
	a.snapshots[12345] = { title = "Correct local title" }
	function a:GetPlayerTracker()
		return tracker
	end
	function a:QueueQuestLogTask(callback)
		callback()
	end
	function a:GetQuestLogIndexForQuest()
		return 1
	end
	function a:GetTrackedQuestStatusState()
		return { isComplete = true, isReadyForTurnIn = true }
	end
	function a:GetTaskAnnouncementType()
		return nil
	end
	function a:PublishAnnouncementEvent(kind, text)
		self.sent = { kind = kind, text = text }
	end
	a.API.GetNumQuestLeaderBoards = function()
		return 0
	end
	a:UNIT_QUEST_LOG_CHANGED(nil, "player")
	assert(a.sent.kind == "QUEST_READY_TO_TURN_IN" and a.sent.text == "Ready to Turn In: Correct local title")
end)

QT:RegisterTest("localized titles use current task trackers but reject saved or other locale titles", function()
	local a = Fixture()
	a.db = { global = {} }
	local tracker = {}
	function a:GetPlayerTracker()
		return tracker
	end
	function a:GetQuestLogIndexForQuest()
		return nil
	end
	function a:GetTaskAnnouncementType()
		return "world"
	end
	function a:GetTrackedQuestStatusState()
		return {}
	end
	function a:GetRuntimeFlag()
		return self.ready == true
	end
	a:WatchQuest(12345, { title = "Local world quest" })
	assert(tracker[12345].titleLocale == "enUS")
	assert(a:GetLocalizedQuestTitle(12345) == nil, "uninitialized saved data must not supply localized titles")
	a.ready = true
	assert(a:GetLocalizedQuestTitle(12345) == "Local world quest")
	tracker[12345].titleLocale = "deDE"
	assert(a:GetLocalizedQuestTitle(12345) == nil)
	a:WatchQuest(12345, { title = "Quest 12345" })
	assert(a:GetLocalizedQuestTitle(12345) == nil, "refresh must not relabel another locale's retained title")
	a:WatchQuest(12345, { title = "Current task title" })
	a:WatchQuest(12345, { title = "Quest 12345" })
	assert(a:GetLocalizedQuestTitle(12345) == "Current task title")
end)

QT:RegisterTest("event facts round trip counters percentages completion and native locales", function()
	local a = Fixture()
	for _, row in ipairs({
		{ "QUEST_ACCEPTED", nil, nil, nil, nil, nil, "q" },
		{ "QUEST_PROGRESS", 2, "monster", false, 3, 8, "c" },
		{ "WORLD_QUEST_PROGRESS", 1, "progressbar", false, 47, 900, "p" },
		{ "BONUS_OBJECTIVE_PROGRESS", 3, "event", true, nil, nil, "o" },
		{ "PLAYER_LEVEL_UP", nil, nil, nil, 42, nil, "l" },
	}) do
		local value = a:BuildAnnouncementFacts(row[1], row[2], row[3], row[4], row[5], row[6])
		local fact = assert(a:DecodeAnnouncementFacts(value))
		assert(fact.kind == row[7] and fact.locale == "enUS")
		local event = Event(row[1], value)
		local decoded = assert(RoundTrip(a, event))
		assert(decoded.eventFacts == value and decoded.text == event.text)
	end
	a.localizationTestLocale = "esMX"
	assert(a:BuildAnnouncementFacts("QUEST_REMOVED") == "1:esMX:q:::")
end)

QT:RegisterTest("malformed event facts and mismatched kinds fall back without losing legacy text", function()
	local a = Fixture()
	for _, value in ipairs({
		"",
		"2:deDE:c:2:3:8",
		"1:xxXX:c:2:3:8",
		"1:deDE:c:2:9:8",
		"1:deDE:c:0:3:8",
		"1:deDE:c:2:3:0",
		"1:deDE:p:2:101:",
		"1:deDE:q::1:",
		"1:deDE:l::0:",
		"1:deDE:c:2:3.5:8",
		"1:deDE:o:2:2:",
		"1:deDE:c:2:1e3:",
		string.rep("x", 81),
	}) do
		assert(a:DecodeAnnouncementFacts(value) == nil)
		local event = Event(nil, value)
		assert(a:LocalizeAnnouncementEvent(event) == event.text)
		local decoded = assert(RoundTrip(a, event))
		assert(decoded.eventFacts == "" and decoded.text == event.text)
	end
	for _, event in ipairs({
		Event("QUEST_ACCEPTED"),
		Event("QUEST_PROGRESS", "1:deDE:q:::"),
		Event("UNKNOWN", "1:deDE:q:::"),
	}) do
		assert(a:LocalizeAnnouncementEvent(event) == event.text)
	end
	local secret = {}
	function a:CanAccessValue(v)
		return v ~= secret
	end
	assert(a:DecodeAnnouncementFacts(secret) == nil)
	assert(a:BuildAnnouncementFacts("QUEST_PROGRESS", secret, "monster", false, 2, 5) == nil)
	assert(a:BuildAnnouncementFacts("QUEST_PROGRESS", 1, "progressbar", false, secret, 5) == nil)
end)

QT:RegisterTest("progress preserves sender prose across locales and never borrows local objectives", function()
	local a = Fixture()
	a.snapshots[12345] = { title = "Local quest", objectives = { "Stage 4: Other monsters slain: 7/8" } }
	a.API.GetQuestObjectiveInfo = function()
		error("receiver must not read own objective counters")
	end
	function a:GetLocalizedQuestTitle()
		error("progress must not request a title just to replace readable source text")
	end
	for _, kind in ipairs({ "QUEST_PROGRESS", "WORLD_QUEST_PROGRESS", "BONUS_OBJECTIVE_PROGRESS" }) do
		for _, row in ipairs({
			{ "1:deDE:c:2:3:8", "Wölfe besiegt: 3/8" },
			{ "1:deDE:p:1:47:", "Angriff zurückgeschlagen: 47%" },
			{ "1:deDE:c:3:9:", "Kristalle gesammelt: 9" },
			{ "1:deDE:o:4:1:", "Mit dem Hauptmann gesprochen" },
			{ "1:deDE:o:4:0:", "Den Hauptmann finden" },
			{ "1:enUS:c:2:3:8", "Wolves slain: 3/8" },
			{ "", "Wölfe besiegt: 3/8" },
		}) do
			local event = Event(kind, row[1], row[2])
			local decoded = assert(RoundTrip(a, event))
			assert(a:LocalizeAnnouncementEvent(decoded) == row[2])
			assert(event.text == row[2])
		end
	end
	assert(a.reads == 0 and a.loads == 0)
end)

QT:RegisterTest("unavailable quest titles preserve wire text across quest event kinds and restricted reads", function()
	for _, condition in ipairs({ "missing", "blocked", "failed", "placeholder" }) do
		local a = Fixture()
		a.blocked = condition == "blocked"
		if condition == "failed" then
			a.API.GetLocalizedQuestTitle = function()
				error("quest data unavailable")
			end
		elseif condition == "placeholder" then
			a.titles[12345] = "Quest 12345"
		end
		for _, kind in ipairs({
			"QUEST_ACCEPTED",
			"QUEST_COMPLETED",
			"QUEST_READY_TO_TURN_IN",
			"QUEST_REMOVED",
			"WORLD_QUEST_ENTERED",
			"WORLD_QUEST_LEFT",
			"WORLD_QUEST_COMPLETED",
			"BONUS_OBJECTIVE_ENTERED",
			"BONUS_OBJECTIVE_LEFT",
			"BONUS_OBJECTIVE_COMPLETED",
			"QUEST_PROGRESS",
			"WORLD_QUEST_PROGRESS",
			"BONUS_OBJECTIVE_PROGRESS",
		}) do
			local facts = kind:match("PROGRESS$") and "1:deDE:c:1:5:7" or "1:deDE:q:::"
			local event = Event(kind, facts, "Wölfe besiegt: 5/7, 50%")
			local decoded = assert(RoundTrip(a, event))
			assert(a:LocalizeAnnouncementEvent(decoded) == event.text, kind .. " must preserve source text")
		end
		if a.blocked then
			assert(a.reads == 0 and a.loads == 0)
		end
	end
end)

QT:RegisterTest("localized quest lookup is bounded cached restriction guarded and resettable", function()
	local a = Fixture()
	a.blocked = true
	assert(a:GetLocalizedQuestTitle(12345) == nil and a.reads == 0 and a.loads == 0)
	a.blocked = false
	for id = 1, 300 do
		assert(a:GetLocalizedQuestTitle(id) == nil)
	end
	assert(a.loads == 10 and #a.localizedQuestTitles.order == 256)
	local count = 0
	for _ in pairs(a.localizedQuestTitles.entries) do
		count = count + 1
	end
	assert(count == 256)
	local reads = a.reads
	a:GetLocalizedQuestTitle(300)
	assert(a.reads == reads)
	a.now = 130
	a:GetLocalizedQuestTitle(300)
	assert(a.loads == 11)
	a.titles[300] = "Loaded title"
	a.now = 135
	assert(a:GetLocalizedQuestTitle(300) == "Loaded title")
	a.now = 140
	reads = a.reads
	assert(a:GetLocalizedQuestTitle(300) == "Loaded title" and a.reads == reads)
	function a:ResetPartyJoin() end
	function a:ResetPlayerLocations() end
	function a:ResetPartyQuestCompare() end
	a:ResetCommsState()
	assert(a.localizedQuestTitles == nil)
end)

QT:RegisterTest("typed announcement fragmentation preserves UTF8 prose and locale facts", function()
	local a = Fixture()
	local event = Event("QUEST_ACCEPTED", "1:deDE:q:::", string.rep("猎人任务", 35))
	event.senderName = string.rep("长", 20)
	event.senderGUID = string.rep("g", 50)
	event.zoneName = string.rep("地区", 30)
	local owned = assert(a:SanitizeAnnouncementEventData(event))
	local frames = assert(a:BuildCommFrames("ANN", owned, { session = "100-1", messageId = "1", stamp = 1700000100 }))
	assert(#frames > 1)
	local parts = {}
	for _, wire in ipairs(frames) do
		assert(#wire <= 255)
		local frame, body = a:DecodeCommFrame(wire)
		parts[frame.part] = body
	end
	local decoded = assert(a:DecodeCommRecord("ANN", table.concat(parts)))
	assert(decoded.text == owned.text and decoded.eventFacts == event.eventFacts and #decoded.text % 3 == 0)
	assert(a:DecodeCommFrame("ANN|3,oldwire") == nil)
end)

QT:RegisterTest("remote chat and bubbles preserve readable source progress without mutating packet text", function()
	local a = Fixture()
	a.snapshots[12345] = { title = "Local title" }
	function a:ShouldDisplayAnnouncementType()
		return true
	end
	function a:IsIgnoredPlayerName()
		return false
	end
	function a:NormalizeMemberName(name)
		return name
	end
	function a:GetGroupedSenderClassFile()
		return "MAGE"
	end
	function a:FindVisiblePlayerNameplateForSender()
		return {}
	end
	function a:IsGroupedSender()
		return true
	end
	function a:ShouldShowAnnouncementsForRemoteSender()
		return true
	end
	function a:GetOption(key)
		return key == "showChatLogs" or key == "showChatBubbles"
	end
	function a:PrintConsoleAnnouncement(text)
		self.chat = text
	end
	function a:ShowAnnouncementBubbleOnNameplate(_, text)
		self.bubble = text
	end
	function a:RecordCommsDiagnostic() end
	local event = Event(nil, "1:deDE:c:2:3:8", "Wölfe besiegt: 3/8")
	assert(a:HandleAnnouncementEvent(event, false))
	assert(a.chat == "Wölfe besiegt: 3/8" and a.bubble == a.chat)
	assert(event.text == "Wölfe besiegt: 3/8")
	-- The same receive path must retain the sender's text in both surfaces
	-- when this client's quest data cannot supply a localized title.
	a.snapshots[12345] = nil
	assert(a:HandleAnnouncementEvent(event, false))
	assert(a.chat == event.text and a.bubble == event.text)
	a.chat, a.bubble = nil, nil
	function a:IsIgnoredPlayerName()
		return true
	end
	assert(not a:HandleAnnouncementEvent(event, false))
	assert(a.chat == nil and a.bubble == nil)
end)

QT:RegisterTest("local publication attaches facts while keeping source text and party chat unchanged", function()
	local a = Fixture()
	function a:GetPlayerFullName()
		return "Me-Realm"
	end
	function a:GetPlayerClassFile()
		return "MAGE"
	end
	function a:GetAnnouncementIconInfo()
		return "", ""
	end
	function a:CanPublishPlayerLocation()
		return false
	end
	local event = assert(a:BuildLocalAnnouncementEvent("QUEST_ACCEPTED", "Quest Accepted: Source title", 12345))
	assert(event.eventFacts == "1:enUS:q:::" and event.text == "Quest Accepted: Source title")
	local facts = a:BuildAnnouncementFacts("QUEST_PROGRESS", 2, "monster", false, 3, 8)
	event = assert(a:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Native source text", 12345, { eventFacts = facts }))
	assert(event.eventFacts == facts and event.text == "Native source text")
	a.isEnabled = true
	a.suppressLocalAnnouncementDisplayDuringTests = false
	function a:SendAnnouncementWireEvent(data)
		self.sent = data
		return true
	end
	function a:AnnounceToNonQTParty(data)
		self.public = data.text
	end
	function a:HandleAnnouncementEvent(data, isLocal)
		assert(isLocal)
		self.localText = data.text
	end
	function a:Debugf() end
	a:PublishAnnouncementEvent("QUEST_PROGRESS", "Native source text", 12345, { eventFacts = facts })
	assert(a.sent.text == "Native source text" and a.sent.eventFacts == facts)
	assert(a.public == a.sent.text and a.localText == a.sent.text)
end)

QT:RegisterTest("localized event prefixes keep only the quest title inside clickable brackets", function()
	local a = Fixture()
	local captured
	function a:BuildChatLogQuestLabel(id, title)
		assert(id == 12345)
		captured = title
		return "[" .. title .. "]"
	end
	local previous = QT.localizationTestLocale
	for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		QT.localizationTestLocale = locale
		for _, event in ipairs({
			"QUEST_ACCEPTED",
			"QUEST_COMPLETED",
			"QUEST_READY_TO_TURN_IN",
			"QUEST_REMOVED",
			"WORLD_QUEST_ENTERED",
			"WORLD_QUEST_LEFT",
			"WORLD_QUEST_COMPLETED",
			"BONUS_OBJECTIVE_ENTERED",
			"BONUS_OBJECTIVE_LEFT",
			"BONUS_OBJECTIVE_COMPLETED",
		}) do
			local prefix = assert(a:GetLocalizedEventPrefix(event))
			local message = a:DecorateAnnouncementMessageWithQuestLink(prefix .. "Title: Part 2", event, 12345)
			assert(captured == "Title: Part 2" and message == prefix .. "[Title: Part 2]")
		end
	end
	QT.localizationTestLocale = previous
end)

QT:RegisterTest("quest title request pacing survives eviction and cached titles remain safe in combat", function()
	local a = Fixture()
	a:GetLocalizedQuestTitle(1)
	a.now = 129
	for id = 2, 300 do
		a:GetLocalizedQuestTitle(id)
	end
	assert(a.loads == 10)
	a.now = 130
	a:GetLocalizedQuestTitle(400)
	assert(a.loads == 11, "only the oldest request may leave the rolling window")
	a:GetLocalizedQuestTitle(2)
	assert(a.loads == 11, "eviction cannot renew a recent request")
	a.titles[400] = "Cached title"
	a.now = 135
	assert(a:GetLocalizedQuestTitle(400) == "Cached title")
	local reads = a.reads
	a.blocked = true
	assert(a:GetLocalizedQuestTitle(400) == "Cached title")
	assert(a:GetLocalizedQuestTitle(999) == nil and a.reads == reads and a.loads == 11)
end)

QT:RegisterTest("quest labels localize across all wire locales even without optional facts or native titles", function()
	for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		for _, kind in ipairs({
			"QUEST_ACCEPTED",
			"QUEST_COMPLETED",
			"QUEST_READY_TO_TURN_IN",
			"QUEST_REMOVED",
			"WORLD_QUEST_ENTERED",
			"WORLD_QUEST_LEFT",
			"WORLD_QUEST_COMPLETED",
			"BONUS_OBJECTIVE_ENTERED",
			"BONUS_OBJECTIVE_LEFT",
			"BONUS_OBJECTIVE_COMPLETED",
		}) do
			local a = Fixture()
			a.localizationTestLocale = locale == "enUS" and "deDE" or "enUS"
			local targetPrefix = a:GetLocalizedEventPrefix(kind)
			-- Get the canonical source key independently of the target language.
			a.localizationTestLocale = "enUS"
			local sourcePrefix = QT.TranslateForLocale(a:GetLocalizedEventPrefix(kind), locale)
			a.localizationTestLocale = locale == "enUS" and "deDE" or "enUS"
			for _, facts in ipairs({ "", "1:" .. locale .. ":q:::" }) do
				local event = Event(kind, facts, sourcePrefix .. "Original title: Part 2")
				local decoded = assert(RoundTrip(a, event))
				assert(a:LocalizeAnnouncementEvent(decoded) == targetPrefix .. "Original title: Part 2")
				a.snapshots[12345] = { title = "Local title" }
				assert(a:LocalizeAnnouncementEvent(decoded) == targetPrefix .. "Local title")
				a.snapshots[12345] = nil
			end
		end
	end
end)

QT:RegisterTest("missing facts never guess objective counters or strip unknown source labels", function()
	local a = Fixture()
	assert(
		a:LocalizeAnnouncementEvent(Event("QUEST_ACCEPTED", "", "Custom announcement: A: B"))
			== "Custom announcement: A: B"
	)
	a.snapshots[12345] = { title = "Local title" }
	assert(a:LocalizeAnnouncementEvent(Event("QUEST_PROGRESS", "", "Wölfe besiegt: 5/7")) == "Wölfe besiegt: 5/7")
end)

QT:RegisterTest("scan facts preserve source text and translate bounded counts without a quest ID", function()
	local a = Fixture()
	for _, count in ipairs({ 0, 1, 2, 5, 11, 17, 21, 22, 10000 }) do
		a.localizationTestLocale = "deDE"
		local facts = assert(a:BuildAnnouncementFacts("SCAN_STATUS", nil, nil, nil, count))
		assert(facts == "1:deDE:s::" .. count .. ":")
		local text = string.format(QT.TranslateForLocale("Quests monitored by QuestTogether: %d", "deDE"), count)
		local event = { eventType = "SCAN_STATUS", text = text, eventFacts = facts, senderName = "Friend-Realm" }
		local received = assert(RoundTrip(a, event))
		assert(received.text == text and received.eventFacts == facts)
		a.localizationTestLocale = "enUS"
		assert(a:LocalizeAnnouncementEvent(received) == "Quests monitored by QuestTogether: " .. count)
		assert(received.text == text and a.reads == 0)
	end
	for _, count in ipairs({ -1, 1.5, 10001, "nonsense" }) do
		assert(a:BuildAnnouncementFacts("SCAN_STATUS", nil, nil, nil, count) == nil)
	end
	for _, facts in ipairs({ "1:deDE:s::10001:", "1:deDE:s:1:17:", "1:deDE:s::17:1", "1:deDE:s:::" }) do
		assert(a:DecodeAnnouncementFacts(facts) == nil)
	end
	for _, facts in ipairs({ "", "1:deDE:q:::", "2:deDE:s::17:" }) do
		local event = { eventType = "SCAN_STATUS", text = "Original count message", eventFacts = facts }
		assert(a:LocalizeAnnouncementEvent(event) == event.text)
	end
	assert(a:LocalizeAnnouncementEvent(Event("QUEST_COMPLETED", "1:deDE:s::17:")) == "Wolves slain: 3/8")
end)

QT:RegisterTest("quest scan attaches its monitored count to the real outgoing announcement", function()
	local sent
	QT.PrintConsoleAnnouncement = function() end
	QT.SendAnnouncementWireEvent = function(_, event)
		sent = event
	end
	QT:ScanQuestLog(false)
	assert(sent and sent.eventType == "SCAN_STATUS")
	local facts = assert(QT:DecodeAnnouncementFacts(sent.eventFacts))
	assert(facts.kind == "s" and facts.current == QT:GetMonitoredQuestCount())
end)

QT:RegisterTest(
	"same locale lifecycle repairs placeholder titles but preserves detailed progress and source fallback",
	function()
		local a = Fixture()
		a.titles[12345] = "Resolved local title"
		for _, kind in ipairs({
			"QUEST_ACCEPTED",
			"QUEST_COMPLETED",
			"QUEST_REMOVED",
			"QUEST_READY_TO_TURN_IN",
			"WORLD_QUEST_COMPLETED",
			"BONUS_OBJECTIVE_ENTERED",
		}) do
			local event = Event(kind, "1:enUS:q:::", a:GetLocalizedEventPrefix(kind) .. "Quest 12345")
			assert(a:LocalizeAnnouncementEvent(event) == a:GetLocalizedEventPrefix(kind) .. "Resolved local title")
			assert(event.text:find("Quest 12345", 1, true))
		end
		local reads = a.reads
		assert(a:LocalizeAnnouncementEvent(Event("QUEST_PROGRESS", "1:enUS:c:2:3:8")) == "Wolves slain: 3/8")
		assert(a.reads == reads)
		local b = Fixture()
		b.blocked = true
		local event = Event("QUEST_COMPLETED", "1:enUS:q:::", "Quest Completed: Readable sent title")
		assert(b:LocalizeAnnouncementEvent(event) == event.text and b.reads == 0)
	end
)

QT:RegisterTest(
	"quest presentation shares native title lookup fallback normalization cache and restrictions",
	function()
		local a = Fixture()
		a.titles[12345] = "Local title"
		function a:GetQuestStatusLabel()
			return "Not Started"
		end
		function a:GetQuestShareableStatusLabel()
			return "Unknown"
		end
		local fallback = "|Hquesttogetherquest:12345|h[Gesendeter Titel]|h"
		assert(a:GetChatLogQuestTooltipRow(12345, fallback).name == "Local title")
		assert(a:BuildQuestStatusMessage(12345, fallback):find("[Local title]", 1, true))
		assert(
			a:BuildQuestCompareMessage("Friend-Realm", { questId = 12345, questTitle = "Gesendeter Titel" })
				:find("[Local title]", 1, true)
		)
		assert(a.reads == 1)
		a.blocked = true
		assert(a:GetQuestDisplayTitle(12345, fallback) == "Local title")
		assert(a:GetQuestDisplayTitle(54321, "[Readable sender title]") == "Readable sender title")
		assert(a.reads == 1)
		a.snapshots[54321] = { title = "Owned snapshot title" }
		assert(a:GetQuestDisplayTitle(54321, fallback) == "Owned snapshot title")
	end
)

QT:RegisterTest("quest display title normalization is bounded single-line and idempotent", function()
	local a = Fixture()
	local mixed = "|cffff0000|Hquest:1:0|h[결속]|h|r|TIcon:16|t|AAtlas:16|a\nNext\tpart"
	for _, input in ipairs({
		"|Hquest:1|h|Hitem:2|hName|h|h",
		"|Hquest:1|hName |Hitem:2|hInner|h Tail|h",
		mixed,
		"Two || pipes | lone",
		"任务 결속\000\012\n\t\127Quest",
		"||Hquest:1|hEscaped|h",
		string.rep("|", 512),
		string.rep("|TIcon:16|t", 60) .. "Readable title",
	}) do
		local plain = a:NormalizeQuestDisplayTitleText(input)
		assert(#plain <= 1024 and not plain:find("[%c]"))
		assert(a:NormalizeQuestDisplayTitleText(plain) == plain, "reusing a display title must not change it")
		assert(not plain:gsub("||", ""):find("|", 1, true), "remaining pipes must be escaped")
	end
	assert(a:NormalizeQuestDisplayTitleText(mixed) == "[결속] Next part")
	assert(a:NormalizeQuestDisplayTitleText("Two || pipes | lone") == "Two || pipes || lone")
	for _, input in ipairs({ string.rep("x", 513), string.rep("x", 1025), {} }) do
		assert(a:NormalizeQuestDisplayTitleText(input) == "")
	end
	local inaccessible = {}
	function a:CanAccessValue(value) return value ~= inaccessible end
	assert(a:NormalizeQuestDisplayTitleText(inaccessible) == "")
end)
