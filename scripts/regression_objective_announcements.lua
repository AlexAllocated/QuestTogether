-- Local producer, real publication boundary and shared scheduler, private sinks.
local QT = _G.QuestTogether

local function Equal(actual, expected, message)
	assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function Fixture()
	local clock = QT:CreateTestClock(100)
	local a = setmetatable({
		isEnabled = true, suppressLocalAnnouncementDisplayDuringTests = false,
		tracker = {}, work = { entries = {}, generations = {} },
		pendingQuestRemovals = {}, pendingQuestAcceptances = {}, retiredQuestIds = {}, questsCompleted = {},
		onQuestLogUpdate = {}, wire = {}, party = {}, display = {}, builds = 0,
	}, { __index = QT })
	a.API = {
		GetTime = function() return clock.now end,
		Delay = function(delay, callback) clock:After(delay, callback) end,
		UnitIsDeadOrGhost = function() return a.dead == true end,
	}
	function a:GetPlayerTracker() return self.tracker end
	function a:GetDeferredWorkStateStore() return self.work end
	function a:IsRuntimeRestricted() return self.restricted == true end
	function a:IsMapTooltipSensitiveStateActive() return false end
	function a:Debugf() end
	function a:RefreshTaskAreaStates() end
	function a:GetTaskAreaStateStore() return {} end
	function a:ForgetQuestCompletionClassification() end
	function a:BuildLocalAnnouncementEvent(kind, text, questID, extra)
		self.builds = self.builds + 1
		return {
			eventType = kind, text = text, questId = tostring(questID or ""),
			eventFacts = extra and extra.eventFacts, occurredAt = clock.now,
			coordX = self.coordX or "42", senderName = "Player-Realm", sample = self.builds,
		}
	end
	function a:SendAnnouncementWireEvent(event) self.wire[#self.wire + 1] = event; return true end
	function a:AnnounceToNonQTParty(event) self.party[#self.party + 1] = event; return true end
	function a:HandleAnnouncementEvent(event) self.display[#self.display + 1] = event; return true end
	function a:BuildTrackedQuestCompletionData(questID) return { questId = questID, title = "A quest" } end
	function a:BuildTrackedQuestRemovalData(questID) return { questId = questID, title = "A quest" } end
	function a:HandleQuestCompleted(title, questID) self:PublishAnnouncementEvent("QUEST_COMPLETED", title, questID) end
	function a:Observe(questID, index, value, options)
		options = options or {}
		local quest = self.tracker[questID]
		if not quest then
			quest = { objectives = {}, objectiveValues = {}, objectiveProgressHighWater = {} }
			self.tracker[questID] = quest
		end
		local text = options.text or ("Wolves slain: " .. value .. "/" .. (options.required or 20))
		quest.objectives[index] = text
		local kind = options.eventType or "QUEST_PROGRESS"
		return self:PublishAnnouncementEvent(kind, text, questID, {
			eventFacts = self:BuildAnnouncementFacts(kind, index, options.objectiveType or "monster", options.finished,
				value, options.required or 20),
			objectiveFinished = options.finished,
		})
	end
	return a, clock
end

QT:RegisterTest("objective bursts retain one half-second deadline and the latest captured record across all outputs", function()
	local a, clock = Fixture()
	assert(a:Observe(10, 1, 1))
	clock:Advance(0.2)
	a.coordX = "43"
	assert(a:Observe(10, 1, 2))
	clock:Advance(0.2)
	a.coordX = "44"
	assert(a:Observe(10, 1, 4))
	Equal(#a.wire, 0)
	Equal(#clock.timers, 1, "updates must not reset the deadline or add timers")
	clock:Advance(0.1)
	Equal(#a.wire, 1)
	Equal(a.wire[1].text, "Wolves slain: 4/20")
	Equal(a:DecodeAnnouncementFacts(a.wire[1].eventFacts).current, 4)
	Equal(a.wire[1].coordX, "44")
	assert(a.wire[1].occurredAt < clock.now, "dispatch must not resample the observation")
	Equal(a.wire[1], a.party[1])
	Equal(a.wire[1], a.display[1])
	Equal(a.builds, 3)
	Equal(a.objectiveAnnouncementState.count, 0)
	a:Observe(10, 1, 5)
	clock:Advance(0.5)
	Equal(#a.wire, 2, "later progress begins a new bounded window")
end)

QT:RegisterTest("native quest progress scans aggregate before every output and flush completion before ready", function()
	local a, clock = Fixture()
	function a:GetRuntimeFlag(_, fallback) return fallback end
	function a:GetQuestLogIndexForQuest() return 1 end
	function a:GetTaskAnnouncementType() return nil end
	function a:GetQuestDisplayTitle() return "Wolves at the gate" end
	function a:GetTrackedQuestStatusState()
		return { isComplete = self.current == 3, isReadyForTurnIn = self.current == 3 }
	end
	a.API.GetNumQuestLeaderBoards = function() return 1 end
	function a:GetNormalizedQuestObjectiveInfo()
		return "Wolves slain: " .. self.current .. "/3", "monster", self.current == 3, self.current, 3
	end
	a.tracker[10] = { isReadyForTurnIn = false }
	a:UpdateTrackedObjectiveProgress(a.tracker[10], 1, "Wolves slain: 0/3", 0, 10)
	for current = 1, 3 do
		a.current = current
		a:UNIT_QUEST_LOG_CHANGED(nil, "player")
		a:DrainQueuedQuestLogTasks()
		Equal(a.tracker[10].objectiveValues[1], current, "aggregation must not postpone the actual quest snapshot")
		if current < 3 then Equal(#a.wire, 0) end
		clock:Advance(0.1)
	end
	Equal(#a.wire, 2)
	Equal(a.wire[1].text, "Wolves slain: 3/3")
	Equal(a.wire[2].eventType, "QUEST_READY_TO_TURN_IN")
	Equal(#a.party, 2)
	Equal(#a.display, 2)
	clock:Advance(1)
	Equal(#a.wire, 2)
end)

QT:RegisterTest("objective bursts remain separate by player quest and objective with sender wording intact", function()
	local a, clock = Fixture()
	local b, otherClock = Fixture()
	a:Observe(10, 1, 1, { text = "Aufgewühlte Winde vernichtet: 1/6", required = 6 })
	a:Observe(10, 2, 1, { text = "Claws collected: 1/4", required = 4 })
	a:Observe(20, 1, 1)
	b:Observe(10, 1, 1)
	a:Observe(10, 1, 3, { text = "Aufgewühlte Winde vernichtet: 3/6", required = 6 })
	clock:Advance(0.5)
	Equal(#a.wire, 3)
	Equal(a.wire[1].text, "Aufgewühlte Winde vernichtet: 3/6")
	Equal(a.wire[2].text, "Claws collected: 1/4")
	Equal(a.wire[3].questId, "20")
	Equal(#b.wire, 0)
	otherClock:Advance(0.5)
	Equal(#b.wire, 1)
	Equal(b.wire[1].text, "Wolves slain: 1/20")
end)

QT:RegisterTest("completed objective bursts flush their latest counts before quest milestones", function()
	for _, kind in ipairs({ "QUEST_READY_TO_TURN_IN", "QUEST_COMPLETED", "WORLD_QUEST_COMPLETED", "BONUS_OBJECTIVE_COMPLETED" }) do
		local a, clock = Fixture()
		a:Observe(10, 1, 1)
		a:Observe(10, 2, 1, { text = "Claws collected: 1/2", required = 2 })
		a:Observe(10, 1, 20)
		Equal(#a.wire, 2, "completed count publishes immediately and flushes other queued objectives")
		Equal(a.wire[1].text, "Wolves slain: 20/20", "never print the replaced partial count")
		a:Observe(10, 2, 2, { text = "Claws collected: 2/2", required = 2 })
		Equal(#a.wire, 3)
		a:Observe(10, 3, 1)
		a:PublishAnnouncementEvent(kind, "Quest milestone", 10)
		Equal(a.wire[4].eventType, "QUEST_PROGRESS")
		Equal(a.wire[5].eventType, kind)
		clock:Advance(1)
		Equal(#a.wire, 5, "retired callbacks cannot repeat final progress")
	end
end)

QT:RegisterTest("world bonus percentage and native finished objectives use the same aggregation boundary", function()
	for _, kind in ipairs({ "QUEST_PROGRESS", "WORLD_QUEST_PROGRESS", "BONUS_OBJECTIVE_PROGRESS" }) do
		local a, clock = Fixture()
		a:Observe(10, 1, 30, { eventType = kind, text = "30% complete", objectiveType = "progressbar" })
		a:Observe(10, 1, 100, { eventType = kind, text = "100% complete", objectiveType = "progressbar" })
		Equal(#a.wire, 1)
		Equal(a.wire[1].text, "100% complete")
		a:Observe(20, 1, 1, { eventType = kind })
		a:Observe(20, 1, 2, { eventType = kind, finished = true })
		Equal(#a.wire, 2, "native finished wins when the numeric API has not caught up")
		clock:Advance(1)
		Equal(#a.wire, 2)
	end
end)

QT:RegisterTest("objective stage replacement drops queued old-stage progress without mixing descriptions", function()
	local a, clock = Fixture()
	a:Observe(10, 1, 2)
	local oldTimer = clock.timers[1].callback
	a:UpdateTrackedObjectiveProgress(a.tracker[10], 1, "Claws collected: 0/4", 0, 10)
	Equal(a.objectiveAnnouncementState.count, 0)
	a:Observe(10, 1, 1, { text = "Claws collected: 1/4", required = 4 })
	oldTimer()
	Equal(#a.wire, 0)
	clock:Advance(0.5)
	Equal(#a.wire, 1)
	Equal(a.wire[1].text, "Claws collected: 1/4")
	a:Observe(10, 1, 2, { text = "Claws collected: 2/4", required = 4 })
	a.tracker[10].objectives[1] = "An unread later stage"
	clock:Advance(0.5)
	Equal(#a.wire, 1, "currentness catches a stage change even without a producer callback")
end)

QT:RegisterTest("objective coalescing survives display rescans but never crosses repeatable quest lifetimes", function()
	local a, clock = Fixture()
	a:Observe(10, 1, 1)
	local prior = a.tracker[10]
	a.tracker[10] = { objectives = prior.objectives, objectiveProgressHighWater = prior.objectiveProgressHighWater }
	clock:Advance(0.5)
	Equal(#a.wire, 1, "a display rescan preserves the observation lifetime")
	a:Observe(10, 1, 2)
	local oldTimer = clock.timers[1].callback
	a.tracker[10] = nil
	a:Observe(10, 1, 1)
	oldTimer()
	Equal(#a.wire, 1)
	clock:Advance(0.5)
	Equal(#a.wire, 2)
	Equal(a.wire[2].text, "Wolves slain: 1/20")
end)

QT:RegisterTest("removal drops pending objective bursts and authoritative turn-in preserves milestone ordering", function()
	for _, removalFirst in ipairs({ false, true }) do
		local a, clock = Fixture()
		a:Observe(10, 1, 1)
		if removalFirst then a:QUEST_REMOVED(nil, 10) end
		a:QUEST_TURNED_IN(nil, 10)
		Equal(#a.wire, removalFirst and 2 or 1, "turn-in flushes progress and can resolve an already pending removal")
		Equal(a.wire[1].eventType, "QUEST_PROGRESS")
		if not removalFirst then a:QUEST_REMOVED(nil, 10) end
		clock:Advance(0)
		Equal(a.wire[2].eventType, "QUEST_COMPLETED")
		clock:Advance(1)
		Equal(#a.wire, 2)
		Equal(a.objectiveAnnouncementState.count, 0)
	end
	local a, clock = Fixture()
	a:Observe(10, 1, 1)
	a:QUEST_REMOVED(nil, 10)
	clock:Advance(1)
	Equal(#a.wire, 1)
	Equal(a.wire[1].eventType, "QUEST_REMOVED")
	Equal(a.objectiveAnnouncementState.count, 0)
end)

QT:RegisterTest("objective resets cancellation and logout reject deliberately executed stale callbacks", function()
	for _, action in ipairs({ "reset", "cancel", "disable", "logout" }) do
		local a, clock = Fixture()
		a:Observe(10, 1, 1)
		local oldTimer = clock.timers[1].callback
		if action == "reset" then a:ResetQuestEventState()
		elseif action == "cancel" then a:CancelObjectiveAnnouncements(10)
		elseif action == "disable" then a.isEnabled = false; a:ResetQuestEventState()
		else a.isLoggingOut = true; a:ResetObjectiveAnnouncements() end
		a.isEnabled, a.isLoggingOut = true, false
		a:Observe(10, 1, 2)
		oldTimer()
		Equal(#a.wire, 0, action)
		clock:Advance(0.5)
		Equal(#a.wire, 1, action)
		Equal(a.wire[1].text, "Wolves slain: 2/20")
	end
end)

QT:RegisterTest("objective aggregation obeys its time bound during combat and map restrictions", function()
	local a, clock = Fixture()
	a:Observe(10, 1, 1)
	a.restricted = true
	assert(not a:IsWorkBlocked("objective_announcement"), "publication has per-output guards and needs no global UI wait")
	clock:Advance(0.5)
	Equal(#a.wire, 1)
end)

QT:RegisterTest("profile replacement retires buffered objective publications before applying new preferences", function()
	local a, clock = Fixture()
	a.hasLoggedIn = false
	a.db = { profile = QT:DeepCopy(QT.DEFAULTS.profile), global = {} }
	for _, method in ipairs({
		"ClearPlayerMapSelection", "CancelDeveloperDiagnosticReplies", "RefreshPartyRoster", "QueuePartyNavigationUpdate",
		"ResetPlayerPhases", "RefreshPlayerLocationPins", "RefreshWindowThemes", "RefreshManagedWindowLayouts",
		"UpdatePartyChatReminder", "BroadcastQuestPartnerStatus", "RefreshMinimapPartnerGlow", "OnPlayerLocationOptionsChanged",
		"RefreshMinimapButton", "CloseQuestLogChatFrame", "RefreshActiveAnnouncementBubbles", "RefreshPersonalBubbleAnchorVisualState",
		"RefreshPersonalBubbleEditModeDialog", "RefreshNameplateAugmentation", "RefreshOptionsWindow", "RefreshProfilesWindow",
	}) do
		a[method] = function() end
	end
	a:Observe(10, 1, 1)
	local stale = clock.timers[1].callback
	assert(a:ApplySettingsTransaction({}, { replace = true, reason = "test_profile" }))
	Equal(a.objectiveAnnouncementState, nil)
	a:Observe(10, 1, 2)
	stale()
	Equal(#a.wire, 0)
	clock:Advance(0.5)
	Equal(#a.wire, 1)
	Equal(a.wire[1].text, "Wolves slain: 2/20")
end)

QT:RegisterTest("objective publication rechecks display preferences and public location sharing when the burst drains", function()
	local a, clock = Fixture()
	a.db = { profile = QT:DeepCopy(QT.DEFAULTS.profile), global = {} }
	a.db.profile.announceToNonQTParty = true
	a.SendAnnouncementWireEvent = QT.SendAnnouncementWireEvent
	a.HandleAnnouncementEvent = QT.HandleAnnouncementEvent
	a.AnnounceToNonQTParty = QT.AnnounceToNonQTParty
	function a:RecordCommsDiagnostic() end
	function a:CanPublishPlayerLocation() return self.db.profile.sharePlayerLocation == true end
	function a:Emit(_, record) self.wire[#self.wire + 1] = record; return true end
	a:Observe(10, 1, 1)
	assert(a:SetOption("announceProgress", false))
	-- Location-service withdrawal has its own coverage; exercise publication's
	-- final privacy recheck without invoking that fixture's live-facing effects.
	a.db.profile.sharePlayerLocation = false
	clock:Advance(0.5)
	Equal(#a.wire, 1, "display filters must not change public announcement routing")
	Equal(a.wire[1].coordX, "", "withdrawn coordinates must not survive the buffered source record")
	Equal(#a.display, 0)
	Equal(#a.party, 0)
end)

QT:RegisterTest("objective queue capacity falls back explicitly without dropping the new progress event", function()
	local a, clock = Fixture()
	for id = 1, 257 do a:Observe(id, 1, 1) end
	Equal(a.objectiveAnnouncementState.count, 256)
	Equal(#clock.timers, 256)
	Equal(#a.wire, 1)
	Equal(a.wire[1].questId, "257")
	clock:Advance(0.5)
	Equal(#a.wire, 257)
	Equal(a.objectiveAnnouncementState.count, 0)
end)

QT:RegisterTest("manual unknown and invalid objective facts never receive guessed aggregation identities", function()
	local a, clock = Fixture()
	for _, facts in ipairs({ "", "bad facts", "1:enUS:q:::" }) do
		a:PublishAnnouncementEvent("QUEST_PROGRESS", "Readable original text", 10, { eventFacts = facts })
	end
	a:PublishAnnouncementEvent("QUEST_PROGRESS", "An untracked quest: 1/5", 20,
		{ eventFacts = "1:enUS:c:1:1:5" })
	Equal(#a.wire, 4)
	a.retiredQuestIds[20] = {}
	assert(not a:PublishAnnouncementEvent("QUEST_PROGRESS", "A retired quest: 2/5", 20,
		{ eventFacts = "1:enUS:c:1:2:5" }))
	Equal(#a.wire, 4, "lack of a tracker must not bypass authoritative retirement")
	Equal(#clock.timers, 0)
	Equal(a.objectiveAnnouncementState, nil)
end)
