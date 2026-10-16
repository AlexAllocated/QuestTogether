-- Private native adapters exercise the codec and coordinator with real queues.
local QT = _G.QuestTogether
local function Equal(a, b, message)
	assert(a == b, (message or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function Fixture(options)
	local net = QT:CreateTestNetwork(options)
	local a, b, c =
		net:AddPeer("Alice-Realm", { group = "party" }),
		net:AddPeer("Bob-Realm", { group = "party" }),
		net:AddPeer("Carol-Realm", { group = "party" })
	for _, peer in ipairs({ a, b, c }) do
		peer:InitializeCommunications()
		peer.errors = {}
		function peer:RecordDiagnosticError(label, detail)
			self.errors[#self.errors + 1] = { label, detail }
		end
		local frame = net:CreateFrame(peer)
		frame:SetScript("OnUpdate", function()
			peer:UpdateCommunicationRuntime()
		end)
	end
	return net, a, b, c
end
local function Route(peer)
	return { { distribution = "WHISPER", target = peer.name } }
end
local function Send(net, receiver, sender, operation, record, overrides)
	net.fixtureSequence = (net.fixtureSequence or 0) + 1
	local context = {
		session = "fixture-session",
		messageId = tostring(net.fixtureSequence),
		requestId = record.requestId,
		stamp = sender.API.GetServerTime(),
	}
	for key, value in pairs(overrides or {}) do
		context[key] = value
	end
	local frames = assert(sender:BuildCommFrames(operation, record, context))
	for _, wire in ipairs(frames) do
		net:Inject(receiver, receiver.commPrefix, wire, "WHISPER", sender.name)
	end
	net:Advance(0.1)
	return frames
end

QT:RegisterTest("protocol v2 copies declared fields and roundtrips nested false empty and delimiter values", function()
	local _, a = Fixture()
	local source = {
		requestId = "r1",
		snapshotId = "s1",
		count = 1,
		entries = {
			{
				questId = 42,
				questTitle = "a|b,:=\n",
				isComplete = false,
				isPushable = false,
				objectives = {
					{ questId = 42, objectiveIndex = 1, text = "0/2", finished = false, current = 0, required = 2 },
				},
				objectiveCount = 1,
			},
		},
		undeclared = "private",
	}
	local copy = assert(a:CopyCommRecord("QCRS", source))
	Equal(copy.entries[1].questTitle, source.entries[1].questTitle)
	Equal(copy.entries[1].isComplete, false)
	Equal(copy.entries[1].objectives[1].current, 0)
	Equal(copy.undeclared, nil)
	source.entries[1].questTitle = "mutated"
	assert(copy.entries[1].questTitle ~= "mutated")
	local state = assert(
		a:CopyCommRecord(
			"STATE",
			{ records = { { topic = "QTPR", data = { active = false }, sampledAt = 100, revision = 42 } } }
		)
	)
	Equal(state.records[1].revision, 42)
	Equal(state.records[1].data.active, false)
end)

QT:RegisterTest("protocol v2 rejects malformed bounded schema payloads without running domain code", function()
	local _, a = Fixture()
	local valid = assert(a:EncodeCommRecord("QTPR", { active = true }))
	for _, wire in ipairs({ "", valid .. valid, valid:sub(1, -2), "1=999999:0", "1=1:x", valid .. "bad", "1=1:\0" }) do
		Equal(a:DecodeCommRecord("QTPR", wire), nil)
	end
	Equal(assert(a:DecodeCommRecord("QTPR", valid .. "99=3:foo")).active, true)
	-- Forever traps division by zero; real NaN checks live in the offline harness.
	Equal(a:EncodeCommRecord("LOC", { mask = math.huge }), nil)
	Equal(a:EncodeCommRecord("QTPR", { active = "true" }), nil)
	Equal(a:EncodeCommRecord("STATE", { records = { { topic = "STATE", data = { records = {} } } } }), nil)
	Equal(
		a:EncodeCommRecord("STATE", {
			records = {
				{ topic = "QTPR", data = { active = true } },
				{ topic = "QTPR", data = { active = false } },
			},
		}),
		nil
	)
	Equal(
		a:EncodeCommRecord(
			"STATE",
			{ records = { { topic = "QTPR", data = { active = true }, revision = math.huge } } }
		),
		nil
	)
	for _, wire in ipairs({
		"1|QTPR|s|1||1|1|100|" .. valid,
		"2|QTPR|s|1||0|1|100|" .. valid,
		"2|QTPR|s|1||1|1025|100|" .. valid,
		"2|UNKNOWN|s|1||1|1|100|" .. valid,
		string.rep("x", 256),
	}) do
		Equal(a:DecodeCommFrame(wire), nil)
	end
end)

QT:RegisterTest("protocol v2 normalizes duplicate audiences before conserving completion callbacks", function()
	local net, a, b = Fixture()
	net:Join(a, a.announcementChannelName, true)
	net:Join(b, b.announcementChannelName, true)
	local completions = {}
	assert(a:Emit("QTPR", { active = true }, {
		{ distribution = "CHANNEL" },
		{ distribution = "CHANNEL", channelName = a.announcementChannelName },
		{ distribution = "WHISPER", target = "Bob" },
		{ distribution = "WHISPER", target = b.name },
	}, {
		onComplete = function(ok, reason)
			completions[#completions + 1] = { ok, reason }
		end,
	}))
	net:Advance(1)
	Equal(#a.sent, 2)
	Equal(#completions, 1)
	Equal(completions[1][1], true)
	Equal(a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = {} } }), false)
	Equal(#a.errors, 0)
end)

QT:RegisterTest(
	"protocol v2 mixed fanout failure reports the failure once even after another route succeeds",
	function()
		local net, a, b, c = Fixture()
		local completions = {}
		net.sendRule = function(packet)
			return packet.target == b.name and 8 or 0
		end
		assert(
			a:Emit(
				"QTPR",
				{ active = true },
				{ { distribution = "WHISPER", target = b.name }, { distribution = "WHISPER", target = c.name } },
				{
					onComplete = function(ok, reason)
						completions[#completions + 1] = { ok, reason }
					end,
				}
			)
		)
		net:Advance(2)
		Equal(#completions, 1)
		Equal(completions[1][1], false)
		Equal(completions[1][2], "ambiguous")
		Equal(#a.attempts, 2)
	end
)

QT:RegisterTest("protocol v2 binds native sender payload identity and request envelope before callbacks", function()
	local net, a, b, c = Fixture()
	local calls = 0
	function b:HandlePartyVisualRosterRequest()
		return true
	end
	local _, _, _, id = a:Request("QPGR", { targetName = b.name }, Route(b), {
		onResponse = function()
			calls = calls + 1
			return true
		end,
	})
	local data = { requestId = id, revision = "r", members = {} }
	Send(net, a, c, "QPGM", data)
	Equal(calls, 0)
	Send(net, a, b, "QPGM", data, { requestId = "other" })
	Equal(calls, 0)
	Send(net, a, b, "QPGM", data)
	Equal(calls, 1)
	local _, _, _, ping = a:Request("PING", {}, Route(b), {
		onResponse = function()
			calls = calls + 1
			return true
		end,
	})
	Send(net, a, b, "PONG", { requestId = ping, senderName = c.name })
	Equal(calls, 1)
	Equal(a:Respond("PONG", { requestId = ping }, Route(b), { requestId = "different" }), false)
end)

QT:RegisterTest("protocol v2 same operation responses require the live expected peer and request", function()
	for _, operation in ipairs({ "QJON", "QSHR", "QTPH" }) do
		local net, a, b, c = Fixture()
		local calls = 0
		local request = { targetName = b.name, status = "request", kind = "Q", questID = 42 }
		local _, _, _, id = a:Request(operation, request, Route(b), {
			onResponse = function()
				calls = calls + 1
				return true
			end,
		})
		local response = { requestId = id, targetName = a.name, status = "pending", kind = "R", questID = 42 }
		Send(net, a, c, operation, response)
		Equal(calls, 0)
		response.requestId = "unsolicited"
		Send(net, a, b, operation, response)
		Equal(calls, 0)
		response.requestId = id
		Send(net, a, b, operation, response)
		Equal(calls, 1)
	end
end)

QT:RegisterTest(
	"protocol v2 errors settle only their matching request and world retirement settles remaining consumers",
	function()
		local net, a, b = Fixture()
		local expired = {}
		function b:HandlePartyVisualRosterRequest()
			return true
		end
		local _, _, _, id = a:Request("QPGR", { targetName = b.name }, Route(b), {
			onExpire = function(reason)
				expired[#expired + 1] = reason
			end,
		})
		Send(net, a, b, "ERROR", { requestId = id, operation = "QCMP", code = "unavailable" })
		Equal(#expired, 0)
		assert(a.communicationState.requests[id])
		Send(
			net,
			a,
			b,
			"ERROR",
			{ requestId = id, operation = "QPGR", code = "unavailable", detail = "bounded detail" }
		)
		Equal(#expired, 1)
		Equal(expired[1], "unavailable")
		Equal(a.communicationState.requests[id], nil)
		assert(a:Request("QPGR", { targetName = b.name }, Route(b), {
			onExpire = function(reason)
				Equal(next(a.communicationState.requests), nil, "retire the whole batch before callback reentry")
				expired[#expired + 1] = reason
			end,
		}))
		a:EndCommunicationSession()
		a:EndCommunicationSession()
		Equal(#expired, 2)
	end
)

QT:RegisterTest("protocol v2 group requests expire across a roster lifetime without blocking unrelated work", function()
	local net, a, b = Fixture()
	local expired, calls = 0, 0
	function b:HandleQuestCompareRequest()
		return true
	end
	local _, _, _, id = a:Request(
		"QCMP",
		{ targetName = b.name },
		{ { distribution = "WHISPER", target = b.name, requiresGroup = true } },
		{
			onExpire = function()
				expired = expired + 1
			end,
			onResponse = function()
				calls = calls + 1
				return true
			end,
		}
	)
	assert(a.communicationState.requests[id].groupOnly)
	net:SetGroup(b, "other")
	Send(net, a, b, "QCRS", { requestId = id, snapshotId = "x", count = 0, entries = {} })
	Equal(calls, 0)
	Equal(expired, 1)
	net:Advance(1)
	Equal(expired, 1)
end)

-- Full loss, retry, and replay-capacity simulations run offline.
QT:RegisterTest("protocol v2 original request retry recovers loss and stops on response progress", function()
	local net, a, b = Fixture()
	local handled, calls, requests = 0, 0, {}
	function b:HandlePartyVisualRosterRequest(record, sender)
		handled = handled + 1
		return self:Respond(
			"QPGM",
			{ requestId = record.requestId, revision = "r", members = {} },
			{ { distribution = "WHISPER", target = sender } }
		)
	end
	net.deliveryRule = function(packet)
		local frame = a:DecodeCommFrame(packet.wire)
		if packet.sender == a.name and frame.operation == "QPGR" then
			requests[#requests + 1] = packet.wire
			if #requests == 1 then
				return { drop = true }
			end
		end
	end
	assert(a:Request("QPGR", { targetName = b.name }, Route(b), {
		onResponse = function()
			calls = calls + 1
			return true
		end,
	}))
	net:Advance(25)
	Equal(handled, 1)
	Equal(calls, 1)
	Equal(#requests, 2)
	Equal(requests[1], requests[2])
end, { offline = true })

-- Full loss, retry, and replay-capacity simulations run offline.
QT:RegisterTest(
	"protocol v2 lost single responses replay immutable outcomes without repeating domain actions",
	function()
		local net, a, b = Fixture()
		local handled, calls, responses = 0, 0, {}
		function b:HandlePartyVisualRosterRequest(record, sender)
			handled = handled + 1
			return self:Respond(
				"QPGM",
				{ requestId = record.requestId, revision = "r", members = {} },
				{ { distribution = "WHISPER", target = sender } }
			)
		end
		net.deliveryRule = function(packet)
			local frame = a:DecodeCommFrame(packet.wire)
			if packet.sender == b.name and frame.operation == "QPGM" then
				responses[#responses + 1] = packet.wire
				if #responses == 1 then
					return { drop = true }
				end
			end
		end
		assert(a:Request("QPGR", { targetName = b.name }, Route(b), {
			onResponse = function()
				calls = calls + 1
				return true
			end,
		}))
		net:Advance(25)
		Equal(handled, 1)
		Equal(calls, 1)
		Equal(#responses, 2)
		Equal(responses[1], responses[2])
		assert(
			b:GetCommTransferMetrics().bytes >= #responses[1],
			"single reply cache must share aggregate transfer accounting"
		)
		b:EndCommunicationSession()
		Equal(b:GetCommTransferMetrics().bytes, 0)
	end,
	{ offline = true }
)

QT:RegisterTest("protocol v2 source topic revisions prevent a newer envelope from reviving older state", function()
	local net, a, b = Fixture()
	local function Location(revision, x)
		Send(net, a, b, "STATE", {
			records = {
				{
					topic = "LOC",
					sampledAt = b.API.GetServerTime(),
					revision = revision,
					data = { mask = 3, mapID = 12, x = x, y = 0.5, classFile = "MAGE" },
				},
			},
		})
	end
	Location(20, 0.8)
	Equal(a:GetPlayerLocationState().peers[b.name].x, 0.8)
	Location(10, 0.2)
	Equal(a:GetPlayerLocationState().peers[b.name].x, 0.8)
	net:Advance(1)
	Location(21, 0.9)
	Equal(a:GetPlayerLocationState().peers[b.name].x, 0.9)
end)

-- Full loss, retry, and replay-capacity simulations run offline.
QT:RegisterTest("protocol v2 retries transient domain capacity without rebuilding accepted comparisons", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local peers, results = {}, {}
	for index = 1, 21 do
		local p = net:AddPeer("Capacity" .. index .. "-Realm")
		peers[index] = p
		p:InitializeCommunications()
		local driver = net:CreateFrame(p)
		driver:SetScript("OnUpdate", function()
			p:UpdateCommunicationRuntime()
		end)
	end
	local responder = peers[21]
	responder.restricted = true
	net:SetQuestLog(responder, { { questID = 42, title = "Capacity probe" } })
	for i = 1, 20 do
		local result = { entries = 0, done = 0 }
		results[i] = result
		assert(peers[i]:RequestQuestCompare(responder.name, {
			onEntry = function()
				result.entries = result.entries + 1
			end,
			onDone = function()
				result.done = result.done + 1
			end,
			onTimeout = function()
				error("temporary capacity must not consume the retry identity")
			end,
		}))
	end
	net:Advance(3)
	local jobs = 0
	for _ in pairs(responder.questCompareResponseCache) do
		jobs = jobs + 1
	end
	Equal(jobs, 16)
	responder.restricted = false
	net:Advance(30)
	for _, result in ipairs(results) do
		Equal(result.done, 1)
		Equal(result.entries, 1)
	end
	net:Advance(20)
	for _, result in ipairs(results) do
		Equal(result.done, 1)
		Equal(result.entries, 1)
	end
end, { offline = true })

QT:RegisterTest("protocol v2 ingress caps frame decode work and reserves room for selected and party peers", function()
	local net, a, b, c = Fixture({ fps = 20 })
	net:SetGroup(a, nil)
	net:SetGroup(b, nil)
	net:SetGroup(c, nil)
	local decoded = 0
	local decode = a.DecodeCommFrame
	function a:DecodeCommFrame(...)
		decoded = decoded + 1
		return decode(self, ...)
	end
	-- An explicit request grants only this known peer a small reserved audience.
	assert(a:Request("QPGR", { targetName = b.name }, Route(b), {
		onResponse = function()
			return true
		end,
	}))
	local function Noise(sender, distribution)
		return a:ReceiveCommunication(a.commPrefix, "invalid", distribution or "WHISPER", sender)
	end
	for index = 1, 300 do
		Equal(Noise("Noise" .. index .. "-Realm"), false)
	end
	Equal(decoded, 64)
	Equal(a:GetCommunicationMetrics().ingressDropped, 236)
	Equal(rawget(a, "commTransferState"), nil)
	Equal(rawget(a, "playerLocationState"), nil)
	-- Unknown whispers cannot consume the reserve, but a selected response can.
	local frame = assert(
		b:BuildCommFrames(
			"QTPR",
			{ active = true },
			{ session = "bounded", messageId = "1", stamp = b:GetAnnouncementServerTime() }
		)
	)[1]
	assert(a:ReceiveCommunication(a.commPrefix, frame, "WHISPER", b.name))
	for _ = 1, 31 do
		Noise(b.name)
	end
	Equal(decoded, 96)
	Noise(b.name)
	Equal(decoded, 96)
	local transfer = a:GetCommTransferMetrics()
	for index = 1, 1000 do
		Noise("Flood" .. index .. "-Realm")
	end
	Equal(decoded, 96)
	Equal(a:GetCommTransferMetrics().bytes, transfer.bytes)
	Equal(a:GetCommTransferMetrics().completed, transfer.completed)
	-- Only the actual runtime frame restores allowance; frame time needs no burst credit.
	net:Advance(0.05)
	local before = decoded
	for _ = 1, 64 do
		Noise(c.name)
	end
	Equal(decoded, before + 64)
	net:SetGroup(a, "party")
	net:SetGroup(c, "party")
	local partyFrame = assert(
		c:BuildCommFrames(
			"QTPR",
			{ active = true },
			{ session = "party", messageId = "1", stamp = c:GetAnnouncementServerTime() }
		)
	)[1]
	assert(a:ReceiveCommunication(a.commPrefix, partyFrame, "PARTY", c.name))
	Equal(decoded, before + 65)
end)

QT:RegisterTest("protocol v2 identifiers survive Forever timestamps and long client uptime", function()
	local _, a = Fixture({ now = 3000000 })
	a.communicationState = nil
	a.API.GetServerTime = function()
		return 1791753535
	end
	assert(a:GetCommunicationSession():match("^1791753535000%-%d+$"))
	function a:BuildQuestCompareResponseEntries()
		return {}
	end
	local entries = assert(a:BuildRevisionedQuestCompareEntries())
	assert(entries.revision:match("^1791753535%-3000000000%-%d+%-1$"))
	a.isLocalDeveloper = true
	a.SignDeveloperRequest = function()
		return string.rep("x", 64)
	end
	a.API.GetServerTime = function()
		return 2200000000
	end
	local request = assert(a:PrepareDeveloperPingRequest({}, "Bob-Realm", false))
	assert(request.requestId:match("^dev%-2200000000%-%d+%-%d+$"))
end)
