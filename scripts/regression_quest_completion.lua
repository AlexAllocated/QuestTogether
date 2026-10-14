local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Quest(id)
	return { questId = id, questTitle = "Quest " .. id, isPushable = true }
end
local function Fixture()
	local a = QT:CreateTestPartyQuestCompareFixture({ Quest(1) })
	a.API.GetServerTime = function() return 1800000000 + math.floor(a.now) end
	a.history, a.historyReads = {}, 0
	a.API.GetCharacterQuestHistoryStatus = function(id)
		a.historyReads = a.historyReads + 1
		return a.history[id] or "unknown"
	end
	a.visible = true
	a.partyQuestCompareWindow = { IsVisible = function() return a.visible end }
	function a:CanMutateOwnedUI() return not self.blocked end
	local own = { name = a.name, isLocal = true, entries = { [1] = Quest(1) }, state = "ready", questHistory = {} }
	local friend = { name = "Friend-Realm", entries = {}, state = "ready", supportsQuestHistory = true, questHistory = {} }
	a.partyQuestCompareSession = {
		playerName = a.name, members = { own, friend }, byName = { [a.name] = own, [friend.name] = friend },
		mode = "party", expandedQuestIds = {}, search = "",
	}
	return a, own, friend
end
local function Response(a, member, states)
	return a:HandleQuestCompareResponse(assert(a:CopyCommRecord("QCRS", {
		requestId = member.historyRequestId, snapshotId = "history", supportsQuestHistory = true,
		count = #states, entries = {}, historyStates = states,
	})), member.name)
end

QT:RegisterTest("quest history uses bounded requested character evidence without changing active snapshots", function()
	local a, own, friend = Fixture()
	local b = QT:CreateTestPartyQuestCompareFixture()
	b.name = friend.name
	b.API.GetServerTime = a.API.GetServerTime
	b.historyReads = 0
	b.API.GetCharacterQuestHistoryStatus = function(id)
		b.historyReads = b.historyReads + 1
		return id == 1 and "completed" or "incomplete"
	end
	b:Roster(a.name, b.name)
	local interest = {}
	for id = 1, 110 do interest[#interest + 1] = id end
	a:SetPartyQuestCompletionInterest(interest)
	Equal(#a.partyQuestCompareSession.historyInterestOrder, 100)
	a:UpdatePartyQuestCompletion()
	Equal(a.historyReads, 8)
	local request = a.wire[#a.wire]
	Equal(request.operation, "QCMP")
	Equal(#request.record.historyQuestIds, 32)
	Equal(b:OnCommReceived(nil, request, "WHISPER", a.name), true)
	Equal(b.historyReads, 8)
	Equal(#b.wire, 0)
	for _ = 1, 3 do b:Advance(1) end
	Equal(b.historyReads, 32)
	Equal(#b.wire, 1)
	local snapshot = friend.entries
	Equal(a:OnCommReceived(nil, b.wire[1], "WHISPER", friend.name), true)
	Equal(friend.entries, snapshot)
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Completed")
	Equal(a:GetPartyQuestAbsenceState(friend, 2), "Missing")
	Equal(a:GetPartyQuestAbsenceState(own, 2), "Absent")
	Equal(a:BuildPartyQuestDiffRows()[1].cells[1], "Have")
	Equal(a:BuildPartyQuestDiffRows()[1].action, nil)
	local renders = a.renders
	a:Advance(61)
	a:UpdatePartyQuestCompletion() -- The replacement response is deliberately lost.
	assert(a.renders > renders)
	Equal(friend.questHistory[1], nil)
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Absent")
end)

QT:RegisterTest("completion history keeps older peers honest and active repeatable and unknown states distinct", function()
	local a, own, friend = Fixture()
	friend.supportsQuestHistory = false
	a:SetPartyQuestCompletionInterest({ 1 })
	a:UpdatePartyQuestCompletion()
	Equal(#a.wire, 0)
	Equal(a:BuildPartyQuestDiffRows()[1].cells[2], "Absent")
	friend.questHistory[1] = { status = "repeatable", sampledAt = a.now }
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Missing")
	friend.questHistory[1].status = "completed"
	friend.entries[1] = Quest(1)
	Equal(a:BuildPartyQuestDiffRows()[1].cells[2], "Have")
	friend.entries[1].isComplete = true
	Equal(a:BuildPartyQuestDiffRows()[1].cells[2], "Ready")
	friend.entries[1] = nil
	friend.questHistory[1].status = "active"
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Unknown")
	friend.questHistory[1].status = "unknown"
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Absent")
	friend.state = "timeout"
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Unknown")
	friend.state = "loading"
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Loading")
	friend.state, friend.questHistory[1].status = "ready", "completed"
	a.options.compareQuestOwnership = "someoneMissing"
	Equal(#a:BuildPartyQuestDiffRows(), 0)
	a.options.compareQuestOwnership, a.options.compareQuestProgress = "all", "ready"
	Equal(#a:BuildPartyQuestDiffRows(), 0)
	Equal(own.entries[1].questTitle, "Quest 1")
	local summary, state = a:GetPartyQuestReadiness({ cells = { "Ready", "Completed" } })
	Equal(summary, "1/2 ready · 1 completed")
	Equal(state, "Have")
	summary, state = a:GetPartyQuestReadiness({ cells = { "Completed", "Completed" } })
	Equal(summary, "2 completed")
	Equal(state, "Completed")
	summary, state = a:GetPartyQuestReadiness({ cells = { "Ready", "Absent" } })
	Equal(summary, "1/2 ready · 1 not in log")
	Equal(state, "Absent")
end)

QT:RegisterTest("quest history rejects unsolicited conflicting stale and retired-view replies", function()
	local a, _, friend = Fixture()
	a:SetPartyQuestCompletionInterest({ 1 })
	a:UpdatePartyQuestCompletion()
	local requestId = friend.historyRequestId
	assert(requestId)
	Equal(Response(a, friend, { { questId = 2, status = "completed" } }), false)
	Equal(Response(a, friend, { { questId = 1, status = "forged" } }), false)
	Equal(friend.historyRequestId, requestId)
	Equal(Response(a, friend, { { questId = 1, status = "completed", sampledAt = a.API.GetServerTime() - 61 } }), true)
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Absent")
	a:Advance(16)
	a:UpdatePartyQuestCompletion()
	local pending = assert(a:GetPendingQuestCompare(friend.historyRequestId))
	local id = friend.historyRequestId
	a.visible = false -- Alt+Z hides through the parent; IsShown would still be true.
	Equal(Response(a, friend, { { questId = 1, status = "completed", sampledAt = a.API.GetServerTime() } }), false)
	a:UpdatePartyQuestCompletion()
	Equal(friend.historyRequestId, nil)
	Equal(a:GetPendingQuestCompare(id), nil)
	pending.receiver.onHistory({ { questId = 1, status = "completed", sampledAt = a.API.GetServerTime() } })
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Absent")
	a.visible = true
	a:Advance(16)
	a:UpdatePartyQuestCompletion()
	local old = assert(a:GetPendingQuestCompare(friend.historyRequestId))
	a:SetPartyQuestMemberSnapshot(friend, {}, "replacement", a.now)
	old.receiver.onHistory({ { questId = 1, status = "completed", sampledAt = a.API.GetServerTime() } })
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Absent")
	a:Advance(16)
	a:UpdatePartyQuestCompletion()
	local ignored = assert(a:GetPendingQuestCompare(friend.historyRequestId))
	a.ignored = friend.name
	ignored.receiver.onHistory({ { questId = 1, status = "completed", sampledAt = a.API.GetServerTime() } })
	Equal(a:GetPartyQuestAbsenceState(friend, 1), "Absent")
end)

QT:RegisterTest("quest history limits native work malformed requests and removes scrolled-away interests", function()
	local a, _, friend = Fixture()
	Equal(a:ValidateQuestHistoryQuery({ { questId = 1 }, { questId = 1 } }), nil)
	Equal(a:ValidateQuestHistoryQuery({ { questId = 1.5 } }), nil)
	Equal(a:ValidateQuestHistoryQuery({}), nil)
	Equal(a:RequestQuestCompare(a.name, { historyQuestIds = { { questId = 1 } } }), false)
	a:SetPartyQuestCompletionInterest({ 1 })
	a:UpdatePartyQuestCompletion()
	assert(friend.historyRequestId)
	local retired = assert(a:GetPendingQuestCompare(friend.historyRequestId))
	a:SetPartyQuestCompletionInterest({ 2 })
	Equal(friend.historyRequestId, nil)
	a:SetPartyQuestCompletionInterest({ 1 })
	a:Advance(16)
	a:UpdatePartyQuestCompletion()
	local replacement = assert(friend.historyRequestId)
	retired.receiver.onHistory({ { questId = 1, status = "completed", sampledAt = a.API.GetServerTime() } })
	retired.receiver.onTimeout()
	Equal(friend.historyRequestId, replacement)
	Equal(friend.questHistory[1], nil)
	a:SetPartyQuestCompletionInterest({ 2 })
	friend.questHistory[2] = { status = "completed", sampledAt = a.now }
	a:SetPartyQuestCompletionInterest({ 3 })
	Equal(friend.questHistory[2], nil)
	a.blocked = true
	local reads, sends = a.historyReads, #a.wire
	a:Advance(16)
	a:UpdatePartyQuestCompletion()
	Equal(a.historyReads, reads)
	Equal(#a.wire, sends)
end)

QT:RegisterTest("native share feedback remains per player and never certifies an individual quest request", function()
	local a, _, friend = Fixture()
	a.API.GetQuestShareResultFormats = function()
		return { ERR_QUEST_PUSH_ACCEPTED_S = "%s has accepted your quest.",
			ERR_QUEST_PUSH_LOG_FULL_S = "%1$s's quest log is full.",
			UNSUPPORTED = "%s shared %s.", PLAIN = "No recipient." }
	end
	a.partyQuestShareState = { outgoing = { test = { target = friend.name, questId = 1, status = "sent", expires = 150 } } }
	assert(a:HandleQuestShareSystemMessage("Friend's quest log is full."))
	Equal(a:GetLatestQuestShareResultText(friend.name), "Latest share result: Friend's quest log is full.")
	Equal(a:GetPartyQuestShareStatus(1), "Share attempted")
	Equal(a.questShareNativeResults[friend.name].questId, nil)
	assert(a:HandleQuestShareSystemMessage("Friend-Realm has accepted your quest."))
	Equal(a:GetPartyQuestShareStatus(1), "Share attempted")
	Equal(a:HandleQuestShareSystemMessage("Stranger has accepted your quest."), false)
	Equal(a:HandleQuestShareSystemMessage("Friend shared Something."), false)
	a:Roster(a.name, friend.name, "Friend-OtherRealm")
	Equal(a:HandleQuestShareSystemMessage("Friend has accepted your quest."), false)
	assert(a:HandleQuestShareSystemMessage("Friend-Realm has accepted your quest."))
	a.ignored = friend.name
	Equal(a:GetLatestQuestShareResultText(friend.name), nil)
	Equal(a:HandleQuestShareSystemMessage("Friend has accepted your quest."), false)
	Equal(a:HandleQuestShareSystemMessage("Friend-Realm has accepted your quest."), false)
	a.ignored = nil
	assert(a:HandleQuestShareSystemMessage("Friend-Realm has accepted your quest."))
	a:Advance(61)
	Equal(a:GetLatestQuestShareResultText(friend.name), nil)
end)

QT:RegisterTest("share requests carry exact owner eligibility explanations while old responses remain usable", function()
	local a, _, friend = Fixture()
	a.partyQuestShareState = { outgoing = { request = { target = friend.name, questId = 1, status = "request", expires = 150 } } }
	local record = assert(a:CopyCommRecord("QSHR", {
		requestId = "request", targetName = a.name, questID = 1, status = "unavailable", reasonCode = "not_owned",
	}))
	assert(a:HandlePartyQuestShareMessage(record, friend.name, "WHISPER"))
	Equal(a:GetPartyQuestShareStatus(1), "The other player no longer has this quest.")
	a.partyQuestShareState.outgoing.request.status = "request"
	record.reasonCode = nil
	assert(a:HandlePartyQuestShareMessage(record, friend.name, "WHISPER"))
	Equal(a:GetPartyQuestShareStatus(1), "Sharing unavailable")
	a.partyQuestShareState.outgoing.request.status = "request"
	record.reasonCode = "unknown-future-code"
	assert(a:HandlePartyQuestShareMessage(record, friend.name, "WHISPER"))
	Equal(a:GetPartyQuestShareStatus(1), "Sharing unavailable")
	local index, _, code = a:GetQuestShareAvailability(1)
	Equal(index, 1)
	Equal(code, nil)
	a.entries = {}
	index, _, code = a:GetQuestShareAvailability(1)
	Equal(index, nil)
	Equal(code, "not_owned")
end)
