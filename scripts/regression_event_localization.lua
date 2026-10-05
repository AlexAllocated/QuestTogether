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

QT:RegisterTest("ready announcements replace a captured placeholder with a loaded local title", function()
	local a = Fixture()
	a.pendingQuestRemovals, a.questsCompleted = {}, {}
	local tracker = { [12345] = { title = "Quest 12345", isReadyForTurnIn = false } }
	a.snapshots[12345] = { title = "Correct local title" }
	function a:GetPlayerTracker() return tracker end
	function a:QueueQuestLogTask(callback) callback() end
	function a:GetQuestLogIndexForQuest() return 1 end
	function a:GetTrackedQuestStatusState() return { isComplete = true, isReadyForTurnIn = true } end
	function a:GetTaskAnnouncementType() return nil end
	function a:PublishAnnouncementEvent(kind, text) self.sent = { kind = kind, text = text } end
	a.API.GetNumQuestLeaderBoards = function() return 0 end
	a:UNIT_QUEST_LOG_CHANGED(nil, "player")
	assert(a.sent.kind == "QUEST_READY_TO_TURN_IN" and a.sent.text == "Ready to Turn In: Correct local title")
end)

QT:RegisterTest("localized titles use current task trackers but reject saved or other locale titles", function()
	local a = Fixture()
	a.db = { global = {} }
	local tracker = {}
	function a:GetPlayerTracker() return tracker end
	function a:GetQuestLogIndexForQuest() return nil end
	function a:GetTaskAnnouncementType() return "world" end
	function a:GetTrackedQuestStatusState() return {} end
	function a:GetRuntimeFlag() return self.ready == true end
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
		local decoded = assert(a:DecodeAnnouncementPayload(a:EncodeAnnouncementPayload(event)))
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
		local decoded = assert(a:DecodeAnnouncementPayload(a:EncodeAnnouncementPayload(event)))
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

QT:RegisterTest("translated objectives always display sender counts and never reuse local stage prose", function()
	local a = Fixture()
	a.snapshots[12345] = { title = "Local quest", objectives = { "Stage 4: Other monsters slain: 7/8" } }
	a.API.GetQuestObjectiveInfo = function()
		error("receiver must not read own objective counters")
	end
	assert(a:LocalizeAnnouncementEvent(Event()) == "Local quest — Objective 2: 3/8")
	assert(a:LocalizeAnnouncementEvent(Event(nil, "1:deDE:p:1:47:")) == "Local quest — Objective 1: 47%")
	assert(a:LocalizeAnnouncementEvent(Event(nil, "1:deDE:c:3:9:")) == "Local quest — Objective 3: 9")
	assert(a:LocalizeAnnouncementEvent(Event(nil, "1:deDE:o:4:1:")) == "Local quest — Objective 4: Complete")
	assert(a:LocalizeAnnouncementEvent(Event(nil, "1:deDE:o:4:0:")) == "Local quest — Objective 4: Progress updated")
	assert(a:LocalizeAnnouncementEvent(Event(nil, "1:enUS:c:2:3:8")) == "Wolves slain: 3/8")
	assert(a.reads == 0)
end)

QT:RegisterTest("all translated locales render event labels titles and progress", function()
	local a = Fixture()
	a.snapshots[12345] = { title = "Local title" }
	local previous = QT.localizationTestLocale
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		QT.localizationTestLocale = locale
		local event = Event("QUEST_ACCEPTED", "1:enUS:q:::", "Quest Accepted: Original title")
		assert(a:LocalizeAnnouncementEvent(event) == QT.TranslateForLocale("Quest Accepted: ", locale) .. "Local title")
		assert(
			a:LocalizeAnnouncementEvent(Event(nil, "1:enUS:c:2:3:8"))
				== "Local title — "
					.. string.format(QT.TranslateForLocale("Objective %d: %d/%d", locale), 2, 3, 8)
		)
	end
	QT.localizationTestLocale = previous
end)

QT:RegisterTest("missing native quest data keeps source titles with localized labels until a local title loads", function()
	local a = Fixture()
	local original = QT.TranslateForLocale("Quest Completed: ", "deDE") .. "Eine Quest"
	assert(a:LocalizeAnnouncementEvent(Event("QUEST_COMPLETED", "1:deDE:q:::", original)) == "Quest Completed: Eine Quest")
	assert(a:LocalizeAnnouncementEvent(Event()) == "Wolves slain: 3/8")
	assert(a.reads == 1 and a.loads == 1)
	a.titles[12345] = "Local quest"
	a.now = a.now + 5
	assert(a:LocalizeAnnouncementEvent(Event()) == "Local quest — Objective 2: 3/8")
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
			local decoded = assert(a:DecodeAnnouncementPayload(a:EncodeAnnouncementPayload(event)))
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

QT:RegisterTest("legacy announcement versions and oversized UTF8 facts remain compatible", function()
	local a = Fixture()
	local event = Event("QUEST_ACCEPTED", "1:deDE:q:::", "Quest Accepted: Original")
	local payload = a:EncodeAnnouncementPayload(event)
	-- The pre-extension parser consumes the original first fifteen slots.
	local oldFields = {}
	for field in (payload .. ","):gmatch("(.-),") do
		oldFields[#oldFields + 1] = field
	end
	assert(oldFields[1] == "3" and a:UnescapePayload(oldFields[6]) == event.text)
	for version = 1, 3 do
		oldFields[1] = tostring(version)
		local decoded = assert(a:DecodeAnnouncementPayload(table.concat(oldFields, ",", 1, 15)))
		assert(decoded.eventFacts == "" and a:LocalizeAnnouncementEvent(decoded) == event.text)
	end
	event.text = string.rep("猎人任务", 35)
	event.senderName = string.rep("长", 20)
	event.senderGUID, event.iconAsset, event.zoneName =
		string.rep("g", 50), string.rep("i", 100), string.rep("地区", 30)
	payload = a:EncodeAnnouncementPayload(event)
	assert(#("ANN|" .. payload) <= 255)
	local decoded = assert(a:DecodeAnnouncementPayload(payload))
	assert(#decoded.text > 0 and #decoded.text % 3 == 0)
	assert(decoded.eventFacts == "" or decoded.eventFacts == event.eventFacts)
end)

QT:RegisterTest("remote chat and bubbles share localized presentation without mutating packet text", function()
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
	local event = Event()
	assert(a:HandleAnnouncementEvent(event, false))
	assert(a.chat == "Local title — Objective 2: 3/8" and a.bubble == a.chat)
	assert(event.text == "Wolves slain: 3/8")
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

QT:RegisterTest("wire completion titles survive unavailable receiver data and clickable chat formatting", function()
	local a = Fixture()
	function a:BuildChatLogQuestLabel(id, title)
		assert(id == 78146)
		return "[" .. title .. "]"
	end
	for _, locale in ipairs({ "enUS", "deDE" }) do
		a.localizationTestLocale = locale
		local event = Event("QUEST_COMPLETED", "1:enUS:q:::", "Quest Completed: Sender's quest name")
		event.questId = "78146"
		local decoded = assert(a:DecodeAnnouncementPayload(a:EncodeAnnouncementPayload(event)))
		local text = a:LocalizeAnnouncementEvent(decoded)
		local prefix = QT.TranslateForLocale("Quest Completed: ", locale)
		assert(text == prefix .. "Sender's quest name")
		assert(a:DecorateAnnouncementMessageWithQuestLink(text, decoded.eventType, decoded.questId)
			== prefix .. "[Sender's quest name]")
	end
end)

QT:RegisterTest("quest labels localize across all wire locales even without optional facts or native titles", function()
	for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		for _, kind in ipairs({ "QUEST_ACCEPTED", "QUEST_COMPLETED", "QUEST_READY_TO_TURN_IN", "QUEST_REMOVED",
			"WORLD_QUEST_ENTERED", "WORLD_QUEST_LEFT", "WORLD_QUEST_COMPLETED",
			"BONUS_OBJECTIVE_ENTERED", "BONUS_OBJECTIVE_LEFT", "BONUS_OBJECTIVE_COMPLETED" }) do
			local a = Fixture()
			a.localizationTestLocale = locale == "enUS" and "deDE" or "enUS"
			local targetPrefix = a:GetLocalizedEventPrefix(kind)
			-- Get the canonical source key independently of the target language.
			a.localizationTestLocale = "enUS"
			local sourcePrefix = QT.TranslateForLocale(a:GetLocalizedEventPrefix(kind), locale)
			a.localizationTestLocale = locale == "enUS" and "deDE" or "enUS"
			for _, facts in ipairs({ "", "1:" .. locale .. ":q:::" }) do
				local event = Event(kind, facts, sourcePrefix .. "Original title: Part 2")
				local decoded = assert(a:DecodeAnnouncementPayload(a:EncodeAnnouncementPayload(event)))
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
	assert(a:LocalizeAnnouncementEvent(Event("QUEST_ACCEPTED", "", "Custom announcement: A: B")) == "Custom announcement: A: B")
	a.snapshots[12345] = { title = "Local title" }
	assert(a:LocalizeAnnouncementEvent(Event("QUEST_PROGRESS", "", "Wölfe besiegt: 5/7")) == "Wölfe besiegt: 5/7")
end)

QT:RegisterTest("restricted receiver localizes known event labels without reading native quest data", function()
	local a = Fixture()
	a.blocked = true
	local event = Event("QUEST_ACCEPTED", "1:deDE:q:::", QT.TranslateForLocale("Quest Accepted: ", "deDE") .. "Detonation aus der Ferne")
	local originalText = event.text
	assert(a:LocalizeAnnouncementEvent(event) == "Quest Accepted: Detonation aus der Ferne")
	assert(a.reads == 0 and a.loads == 0)
	assert(event.text == originalText, "localization must not mutate source text")
end)

QT:RegisterTest("scan facts preserve source text and translate bounded counts without a quest ID", function()
	local a = Fixture()
	for _, count in ipairs({ 0, 1, 2, 5, 11, 17, 21, 22, 10000 }) do
		a.localizationTestLocale = "deDE"
		local facts = assert(a:BuildAnnouncementFacts("SCAN_STATUS", nil, nil, nil, count))
		assert(facts == "1:deDE:s::" .. count .. ":")
		local text = string.format(QT.TranslateForLocale("Quests monitored by QuestTogether: %d", "deDE"), count)
		local event = { eventType = "SCAN_STATUS", text = text, eventFacts = facts, senderName = "Friend-Realm" }
		local received = assert(a:DecodeAnnouncementPayload(a:EncodeAnnouncementPayload(event)))
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
	QT.SendAnnouncementWireEvent = function(_, event) sent = event end
	QT:ScanQuestLog(false)
	assert(sent and sent.eventType == "SCAN_STATUS")
	local facts = assert(QT:DecodeAnnouncementFacts(sent.eventFacts))
	assert(facts.kind == "s" and facts.current == QT:GetMonitoredQuestCount())
end)

QT:RegisterTest("same locale lifecycle repairs placeholder titles but preserves detailed progress and source fallback", function()
	local a = Fixture()
	a.titles[12345] = "Resolved local title"
	for _, kind in ipairs({ "QUEST_ACCEPTED", "QUEST_COMPLETED", "QUEST_REMOVED", "QUEST_READY_TO_TURN_IN", "WORLD_QUEST_COMPLETED", "BONUS_OBJECTIVE_ENTERED" }) do
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
end)

QT:RegisterTest("quest presentation shares native title lookup fallback normalization cache and restrictions", function()
	local a = Fixture()
	a.titles[12345] = "Local title"
	function a:GetQuestStatusLabel() return "Not Started" end
	function a:GetQuestShareableStatusLabel() return "Unknown" end
	local fallback = "|Hquesttogetherquest:12345|h[Gesendeter Titel]|h"
	assert(a:GetChatLogQuestTooltipRow(12345, fallback).name == "Local title")
	assert(a:BuildQuestStatusMessage(12345, fallback):find("[Local title]", 1, true))
	assert(a:BuildQuestCompareMessage("Friend-Realm", { questId = 12345, questTitle = "Gesendeter Titel" }):find("[Local title]", 1, true))
	assert(a.reads == 1)
	a.blocked = true
	assert(a:GetQuestDisplayTitle(12345, fallback) == "Local title")
	assert(a:GetQuestDisplayTitle(54321, "[Readable sender title]") == "Readable sender title")
	assert(a.reads == 1)
	a.snapshots[54321] = { title = "Owned snapshot title" }
	assert(a:GetQuestDisplayTitle(54321, fallback) == "Owned snapshot title")
end)
