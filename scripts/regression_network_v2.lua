-- End-to-end communication tests use only private peers and engine adapters.
local QT = _G.QuestTogether
local function Equal(actual, expected, detail)
	assert(actual == expected, (detail or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

QT:RegisterTest("party quest snapshots use group transport with repair and remain compatible with private peers", function()
	for _, mode in ipairs({ "PARTY", "RAID", "INSTANCE_CHAT", "legacy", "private" }) do
		local net = QT:CreateTestNetwork({ fps = 20 })
		local distribution = mode == "legacy" and "PARTY" or mode ~= "private" and mode or nil
		local settings = distribution and { group = "questers", distribution = distribution } or {}
		local a, b, other = net:AddPeer("Alice-Realm", settings), net:AddPeer("Bob-Realm", settings),
			net:AddPeer("Other-Realm", settings)
		for _, peer in ipairs({ a, b, other }) do
			peer.API.IsInInstanceGroup = function() return distribution == "INSTANCE_CHAT" end
			net:SetQuestLog(peer, { { questID = 42, title = "A party quest" } })
			net:StartPeer(peer)
		end
		if mode == "legacy" then
			function b:GetQuestCompareRoutes(target)
				return { { distribution = "WHISPER", target = target, requiresGroup = true } }
			end
		end
		function b:ReadQuestCompareObjectives(id)
			local objectives = {}
			for index = 1, 4 do
				objectives[index] = { questId = id, objectiveIndex = index, text = string.rep("Objective ", 12) .. index,
					kind = "item", current = index, required = 8, finished = false }
			end
			return objectives
		end
		local responseParts, routes, done, expired, requestId = {}, {}, 0, 0, nil
		function other:HandleQuestCompareResponse(data, sender)
			assert(data.requestId ~= requestId, "an unrelated group member installed a private response")
			return QT.HandleQuestCompareResponse(self, data, sender)
		end
		local relevant = { QCMP = true, QCRS = true, FXEND = true, FXACK = true, FXMISS = true, FXSTAT = true }
		net.sendRule = function(packet)
			local frame = a:DecodeCommFrame(packet.wire)
			if relevant[frame.operation] then
				routes[#routes + 1] = packet
				if mode ~= "legacy" and mode ~= "private" then
					Equal(packet.route, distribution)
					Equal(packet.target, nil, "group sends must not pass a whisper target to the native API")
				elseif mode == "private" then Equal(packet.route, "WHISPER") end
			end
			return 0
		end
		net.deliveryRule = function(packet, receiver)
			local frame = a:DecodeCommFrame(packet.wire)
			if frame.operation == "QCRS" and frame.requestId == requestId and receiver == a then
				responseParts[frame.part] = (responseParts[frame.part] or 0) + 1
				if frame.part == 2 and responseParts[2] == 1 then return { drop = true } end
			end
		end
		local accepted
		accepted, requestId = a:RequestQuestCompare(b.name, { objectiveQuestId = 42,
			onEntry = function(entry) Equal(#entry.objectives, 4); Equal(entry.objectives[4].current, 4) end,
			onDone = function() done = done + 1 end, onTimeout = function() expired = expired + 1 end })
		assert(accepted)
		net:Advance(20)
		Equal(done, 1, "snapshot must finish over " .. mode)
		Equal(expired, 0)
		Equal(responseParts[2], 2)
		assert(#routes > 4)
		for _, job in ipairs(b.commTransferState.outgoing) do
			assert(job.operation ~= "QCRS" or job.requestId ~= requestId,
				"acknowledged snapshot must release its repair copy")
		end
	end
end, { offline = true })

QT:RegisterTest("five player quest views and objective updates finish when whisper and channel sends are rejected", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local party, quests = {}, {}
	for id = 1, 30 do quests[id] = { questID = id, title = "A shared quest " .. id .. string.rep(" with a useful title", 3) } end
	for index = 1, 5 do
		local peer = net:AddPeer("Party" .. index .. "-Realm", { group = "questers" })
		net:SetQuestLog(peer, quests)
		peer.db.profile.compareAutoRefresh = false
		party[index] = peer
	end
	for _, peer in ipairs(party) do net:StartPeer(peer) end
	local viewer, responder = party[1], party[2]
	function responder:ReadQuestCompareObjectives(id)
		return { { questId = id, objectiveIndex = 1, text = "Supplies: 1/8", kind = "item", current = 1, required = 8,
			finished = false } }
	end
	local rejected = 0
	net.sendRule = function(packet)
		if packet.route == "WHISPER" or packet.route == "CHANNEL" then rejected = rejected + 1; return 7 end
		return 0
	end
	assert(viewer:RefreshPartyQuestCompare())
	local detail = viewer:AcquirePartyQuestProgress(responder.name, 1, {}, function() end, true)
	local complete = false
	for _ = 1, 90 do
		net:Advance(1)
		complete = detail.hasEntry == true
		for _, member in ipairs(viewer.partyQuestCompareSession.members) do
			if member.state ~= "ready" then complete = false end
		end
		if complete then break end
	end
	assert(complete, "party views must finish without a working whisper or public channel route")
	assert(rejected > 0, "the scenario must include rejected unrelated traffic")
	for _, member in ipairs(viewer.partyQuestCompareSession.members) do
		local count = 0
		for _ in pairs(member.entries) do count = count + 1 end
		Equal(count, 30)
	end
	Equal(detail.objectives[1].current, 1)
	assert(responder:Emit("ANN", { eventType = "QUEST_PROGRESS", senderName = responder.name, classFile = "MAGE",
		questId = "1", text = "Supplies: 3/8", occurredAt = responder.API.GetServerTime(),
		eventFacts = responder:BuildAnnouncementFacts("QUEST_PROGRESS", 1, "item", false, 3, 8) },
		{ { distribution = "PARTY", requiresGroup = true } }))
	net:Advance(5)
	Equal(detail.objectives[1].current, 3)
end, { offline = true })

QT:RegisterTest("single packet group quest replies replay without rebuilding and rejected requests finish promptly", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local a = net:AddPeer("Alice-Realm", { group = "questers" })
	local b = net:AddPeer("Bob-Realm", { group = "questers" })
	local builds, done, dropped, requestId = 0, 0, false, nil
	function b:BuildRevisionedQuestCompareEntries(objectiveQuestId)
		-- Count this request's read, not the independent background summaries.
		if objectiveQuestId == 42 then builds = builds + 1 end
		return {}
	end
	net:StartPeer(a); net:StartPeer(b)
	net.deliveryRule = function(packet, receiver)
		local frame = a:DecodeCommFrame(packet.wire)
		if frame.operation == "QCRS" and frame.requestId == requestId and receiver == a and not dropped then
			Equal(frame.total, 1)
			dropped = true
			return { drop = true }
		end
	end
	local accepted
	accepted, requestId = a:RequestQuestCompare(b.name, { objectiveQuestId = 42, onEntry = function() end,
		onDone = function() done = done + 1 end, onTimeout = function() error("cached reply timed out") end })
	assert(accepted)
	net:Advance(12)
	assert(dropped)
	Equal(done, 1)
	Equal(builds, 1, "same request identity must reuse its single-packet group reply")
	local expired = 0
	net.sendRule = function(packet)
		local frame = a:DecodeCommFrame(packet.wire)
		return frame.operation == "QCMP" and 7 or 0
	end
	local accepted, id = a:RequestQuestCompare(b.name, { onEntry = function() end, onDone = function() end,
		onTimeout = function() expired = expired + 1 end })
	assert(accepted)
	net:Advance(2)
	Equal(expired, 1)
	Equal(a:GetPendingQuestCompare(id), nil)
	Equal(a.communicationState.requests[id], nil)
	net:Advance(181)
	Equal(expired, 1, "native failure and expiry must not notify the viewer twice")
	function b:HandleQuestCompareRequest() return true end
	for _, outcome in ipairs({ "ambiguous", "mixed" }) do
		local notifications = 0
		net.sendRule = function(packet)
			local frame = a:DecodeCommFrame(packet.wire)
			if frame.operation ~= "QCMP" then return 0 end
			if outcome == "ambiguous" then return 8 end
			return packet.route == "WHISPER" and 7 or 0
		end
		local routes = a:GetQuestCompareRoutes(b.name, true)
		if outcome == "mixed" then routes[#routes + 1] = { distribution = "WHISPER", target = b.name } end
		local sent, _, _, requestId = a:Request("QCMP", { targetName = b.name }, routes,
			{ onExpire = function() notifications = notifications + 1 end })
		assert(sent)
		net:Advance(2)
		assert(a.communicationState.requests[requestId], "a possibly delivered request must remain correlated")
		Equal(notifications, 0)
		a:CancelCommRequest(requestId)
	end
end, { offline = true })

QT:RegisterTest("network fixture rounds timers to frames and defers nested callbacks", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local peer = net:AddPeer("Timer-Realm")
	local calls = {}
	peer.API.Delay(0.01, function()
		calls[#calls + 1] = net.now
		peer.API.Delay(0, function()
			calls[#calls + 1] = net.now
		end)
	end)
	Equal(#calls, 0)
	net:Step()
	Equal(#calls, 1)
	assert(calls[1] >= 100.1 - 1e-9)
	net:Step()
	Equal(#calls, 2)
	assert(calls[2] - calls[1] >= 0.1 - 1e-9)
	net:SetFPS(60)
	local start = net.now
	peer.API.Delay(0.01, function()
		calls[#calls + 1] = net.now
	end)
	net:Step()
	Equal(#calls, 3)
	assert(calls[3] - start < 0.02)
end)

QT:RegisterTest("network fixture separates accepted packets from asynchronous receipt and loss", function()
	local net = QT:CreateTestNetwork({ latency = 0 })
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	local received = {}
	function b:OnCommReceived(_, wire)
		received[#received + 1] = wire
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "first", "WHISPER", b.name), 0)
	Equal(net.metrics.accepted, 1)
	Equal(#received, 0, "native acceptance must not call receiver inline")
	net:Step()
	Equal(received[1], "first")
	net.deliveryRule = function()
		return { drop = true }
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "lost", "WHISPER", b.name), 0)
	net:Step()
	Equal(net.metrics.accepted, 2)
	Equal(#received, 1)
	Equal(net.metrics.dropped, 1)
	net.sendRule = function()
		return 3
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "throttled", "WHISPER", b.name), 3)
	Equal(net.metrics.accepted, 2)
	Equal(#net.pending, 0)
end)

QT:RegisterTest("network fixture reorders duplicates and respects channel readiness and audience", function()
	local net = QT:CreateTestNetwork({ fps = 20, joinDelay = 0.1 })
	local a, b, outsider = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm"), net:AddPeer("Other-Realm")
	local received = {}
	function a:OnCommReceived() end
	function b:OnCommReceived(_, wire, route, sender, id, channel)
		received[#received + 1] = { wire, route, sender, id, channel }
	end
	function outsider:OnCommReceived()
		error("unsubscribed peer received channel packet")
	end
	net:Join(a, "TestChannel")
	net:Join(b, "TestChannel")
	Equal(a.API.GetChannelName("TestChannel"), nil)
	local ruleCalls = 0
	net.sendRule = function()
		ruleCalls = ruleCalls + 1
		return 0
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "unjoined", "CHANNEL", 7), false)
	Equal(ruleCalls, 0, "a successful fault policy cannot manufacture a ready channel")
	Equal(#net.pending, 0)
	net:Advance(0.1)
	assert(a.joined.TestChannel and b.joined.TestChannel and a.joined.TestChannel ~= b.joined.TestChannel)
	net.deliveryRule = function(packet)
		return packet.wire == "slow" and { delay = 0.2 } or { delay = 0.05, copies = 2 }
	end
	a.API.SendAddonMessage(a.commPrefix, "slow", "CHANNEL", a.joined.TestChannel)
	a.API.SendAddonMessage(a.commPrefix, "fast", "CHANNEL", a.joined.TestChannel)
	net:Advance(0.2)
	Equal(#received, 3)
	Equal(received[1][1], "fast")
	Equal(received[2][1], "fast")
	Equal(received[3][1], "slow")
	Equal(received[1][4], b.joined.TestChannel, "receiver must see its own local channel ID")
	a.API.SendAddonMessage(a.commPrefix, "slow", "CHANNEL", a.joined.TestChannel)
	net:Leave(b, "TestChannel")
	net:Advance(0.2)
	Equal(#received, 3)
	a.connected = false
	local before = ruleCalls
	Equal(a.API.SendAddonMessage(a.commPrefix, "disconnected", "WHISPER", b.name), false)
	Equal(ruleCalls, before, "a successful fault policy cannot send from a disconnected peer")
	Equal(#net.pending, 0)
end)

QT:RegisterTest("network fixture clocks randomness and state are private to each network", function()
	local a, b = QT:CreateTestNetwork({ seed = 91 }), QT:CreateTestNetwork({ seed = 91 })
	local peer = a:AddPeer("Clock-Realm", { clockOffset = -40, serverOffset = 7 })
	local other = b:AddPeer("Clock-Realm")
	for _ = 1, 20 do
		Equal(a:Random(2, 50), b:Random(2, 50))
	end
	Equal(peer.API.GetTime(), 60)
	Equal(peer.API.GetServerTime(), 1800000107)
	peer.db.profile.sharePlayerLocation = false
	Equal(other.db.profile.sharePlayerLocation, true)
	Equal(rawget(peer, "transportState"), nil)
	Equal(peer.transportState, nil, "live addon state cannot be inherited")
	a:Advance(1)
	assert(math.abs(peer.API.GetTime() - 61) < 1e-8)
	Equal(other.API.GetTime(), 100)
end)

QT:RegisterTest("network fixture runs the production coordinator and fences retired frame callbacks", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local peer = net:AddPeer("Runtime-Realm")
	Equal(peer.UpdatePlayerCommunications, QT.UpdatePlayerCommunications)
	Equal(peer.UpdateGeographicComms, QT.UpdateGeographicComms)
	Equal(peer.DrainTransport, QT.DrainTransport)
	net:StartPeer(peer)
	local frame = peer.runtimeCoordinatorFrame
	local stale = frame.scripts.OnUpdate
	assert(type(stale) == "function")
	net:Advance(3)
	assert((peer.apiCalls.map or 0) > 0, "coordinator should acquire actual producer observations")
	local reads = peer.apiCalls.map
	peer:ResetRuntimeCoordinator()
	stale(frame, 1)
	Equal(peer.apiCalls.map, reads, "retired coordinator must reject a captured callback")
	Equal(frame.scripts.OnUpdate, nil)
end)

-- Full multi-peer, multi-frame network simulations run offline.
QT:RegisterTest("network runtime discovers local peers through real producers and asynchronous delivery", function()
	for _, fps in ipairs({ 5, 60 }) do
		local net = QT:CreateTestNetwork({ fps = fps, seed = 9, latency = 0.05, joinDelay = 0.1 })
		local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm", { x = 0.6 })
		net:StartPeer(a)
		net:StartPeer(b)
		Equal(#a:GetVisiblePlayerLocations("map"), 0)
		net:Advance(20)
		local aRows, bRows = a:GetVisiblePlayerLocations("map"), b:GetVisiblePlayerLocations("map")
		Equal(#aRows, 1)
		Equal(#bRows, 1)
		Equal(aRows[1].name, b.name)
		Equal(bRows[1].name, a.name)
		Equal(aRows[1].x, 0.6)
		Equal(bRows[1].x, 0.4)
		assert(net.metrics.accepted > 0 and net.metrics.delivered > 0)
		for _, trace in ipairs(net.trace) do
			if trace.kind == "delivered" then
				assert(trace.at > trace.packet.at, "network receipt must occur after native acceptance")
			end
		end
	end
end, { offline = true })

QT:RegisterTest("network runtime progresses communications each frame while pacing observations", function()
	local net = QT:CreateTestNetwork({ fps = 60 })
	local peer = net:AddPeer("Runtime-Realm")
	local networkTicks, observations = 0, 0
	local update, observe = peer.UpdateCommunicationRuntime, peer.UpdatePlayerCommunications
	function peer:UpdateCommunicationRuntime()
		networkTicks = networkTicks + 1
		return update(self)
	end
	function peer:UpdatePlayerCommunications()
		observations = observations + 1
		return observe(self)
	end
	net:StartPeer(peer)
	for _ = 1, 30 do
		net:Step()
	end
	Equal(networkTicks, 30)
	Equal(observations, 2)
	local oldFrame = peer.runtimeCoordinatorFrame
	local oldUpdate = oldFrame.scripts.OnUpdate
	peer:ResetRuntimeCoordinator()
	oldUpdate(oldFrame, 1)
	Equal(networkTicks, 30)
end)

QT:RegisterTest("network v2 rejects legacy prefixes and legacy bodies without side effects", function()
	local net = QT:CreateTestNetwork()
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	net:StartPeer(a)
	net:StartPeer(b)
	net:Join(a, a.announcementChannelName, true)
	local announcements = 0
	function a:HandleAnnouncementEvent()
		announcements = announcements + 1
	end
	local old = "ANN|3,QUEST_PROGRESS,,MAGE,Bob-Realm,Legacy progress,,,,,,,,,,,"
	net:Inject(a, "QuestTogether", old, "CHANNEL", b.name, { channel = a.announcementChannelName })
	net:Inject(a, "QuestTogether2", old, "CHANNEL", b.name, { channel = a.announcementChannelName })
	net:Advance(0.1)
	Equal(announcements, 0)
	Equal(a:IsKnownQTPlayer(b.name), false)
end)

-- Full multi-peer, multi-frame network simulations run offline.
QT:RegisterTest("network v2 correlates and repairs a typed response through the complete runtime", function()
	for _, fps in ipairs({ 5, 60 }) do
		local net = QT:CreateTestNetwork({ fps = fps, seed = 32, latency = 0.05 })
		local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
		net:StartPeer(a)
		net:StartPeer(b)
		local calls, initialPartTwo = 0, 0
		function b:HandlePartyVisualRosterRequest(request, sender)
			local members = {}
			for index = 1, 30 do
				members[index] = { name = "Member" .. index .. "-Realm", classFile = "MAGE" }
			end
			return self:Respond(
				"QPGM",
				{ requestId = request.requestId, revision = "fixture", members = members },
				{ { distribution = "WHISPER", target = sender } },
				{ expires = self.API.GetTime() + 120 }
			)
		end
		net.deliveryRule = function(packet)
			local frame = a:DecodeCommFrame(packet.wire)
			assert(frame, "all runtime producers must use the versioned protocol")
			if frame.operation == "QPGM" and frame.part == 2 then
				initialPartTwo = initialPartTwo + 1
				if initialPartTwo == 1 then
					return { drop = true }
				end
			end
		end
		local accepted = a:Request("QPGR", { targetName = b.name }, { { distribution = "WHISPER", target = b.name } }, {
			expires = a.API.GetTime() + 120,
			onResponse = function(record, sender)
				Equal(sender, b.name)
				Equal(#record.members, 30)
				calls = calls + 1
				a:CancelCommRequest(record.requestId)
				return true
			end,
		})
		assert(accepted)
		net:Advance(45)
		Equal(calls, 1)
		Equal(initialPartTwo, 2)
		Equal(b:GetCommTransferMetrics().outgoing, 0)
		for _, peer in ipairs({ a, b }) do
			local bytes = 0
			for _, packet in ipairs(peer.sent) do
				bytes = bytes + #packet.wire + #packet.prefix + 40
			end
			assert(bytes <= 800 * 45 + 1600, "native byte budget must include every runtime producer")
			assert(#peer.sent <= 4 * 45 + 4, "native packet budget must include every runtime producer")
		end
	end
end, { offline = true })

QT:RegisterTest("network v2 retires throttled work at world departure and resumes with fresh traffic", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	net:StartPeer(a)
	net:StartPeer(b)
	local blocked, completions = false, {}
	net.sendRule = function(_, _, peer)
		if peer == a and not blocked then
			blocked = true
			return 3
		end
		return 0
	end
	assert(a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = b.name } }, {
		onComplete = function(ok, reason)
			completions[#completions + 1] = { ok, reason }
		end,
	}))
	net:Advance(0.3)
	assert(blocked)
	Equal(#a.sent, 0)
	Equal(#completions, 0, "a native throttle is not completion")
	a:EndCommunicationSession()
	Equal(#completions, 1)
	Equal(completions[1][1], false)
	local attempts = #a.attempts
	net:Advance(2)
	Equal(#a.attempts, attempts, "active frame callbacks cannot send a departed generation")
	a:ResumeCommunicationSession()
	assert(a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = b.name } }))
	net:Advance(2)
	assert(#a.sent > 0)
	Equal(#completions, 1)
	assert(b:IsKnownQTPlayer(a.name))
end)

QT:RegisterTest("network v2 queued coordinates cannot cross a privacy change", function()
	local net = QT:CreateTestNetwork({ fps = 5 })
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	net:StartPeer(a)
	net:StartPeer(b)
	local completed = {}
	assert(a:Emit("STATE", {
		records = {
			{ topic = "QTPR", data = { active = true }, sampledAt = a.API.GetServerTime() },
			{
				topic = "LOC",
				data = { session = "privacy-test", sequence = 1, mask = 3, mapID = 12, x = 0.9, y = 0.8 },
				sampledAt = a.API.GetServerTime(),
			},
		},
	}, { { distribution = "WHISPER", target = b.name } }, {
		onComplete = function(ok, reason)
			completed[#completed + 1] = { ok, reason }
		end,
	}))
	a.db.profile.sharePlayerLocation = false
	net:Advance(20)
	Equal(#completed, 1)
	Equal(completed[1][1], false)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	for _, packet in ipairs(a.sent) do
		Equal(
			packet.route == "WHISPER" and packet.target == b.name,
			false,
			"private work must be cancelled before native send"
		)
	end
end)

QT:RegisterTest("network v2 queued party focus cannot follow the sender into another group", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local a = net:AddPeer("Alice-Realm", { group = "old" })
	local b = net:AddPeer("Bob-Realm", { group = "old" })
	local c = net:AddPeer("Carol-Realm", { group = "new" })
	for _, peer in ipairs({ a, b, c }) do
		net:StartPeer(peer)
	end
	local completions = {}
	local accepted, _, context = a:Emit("QTN2", { session = "old-focus", sequence = 1, questID = 123 }, {
		{ distribution = "PARTY" },
	}, {
		onComplete = function(ok, reason)
			completions[#completions + 1] = { ok, reason }
		end,
	})
	assert(accepted)
	net:SetGroup(a, "new")
	net:Advance(2)
	Equal(#completions, 1)
	Equal(completions[1][1], false)
	for _, packet in ipairs(a.sent) do
		local frame = assert(a:DecodeCommFrame(packet.wire))
		assert(
			frame.session ~= context.session or frame.messageId ~= context.messageId,
			"old group focus reached native send"
		)
	end
end)

-- Full multi-peer, multi-frame network simulations run offline.
QT:RegisterTest("network v2 completes party logs and a diagnostic report while movement remains active", function()
	for _, fps in ipairs({ 5, 60 }) do
		local net = QT:CreateTestNetwork({ fps = fps, seed = 71 })
		local party = {}
		for index = 1, 5 do
			local peer = net:AddPeer("Player" .. index .. "-Realm", { group = "party" })
			local quests = {}
			for quest = 1, 30 do
				quests[quest] = {
					questID = index * 1000 + quest,
					title = "Quest " .. quest .. ": " .. string.rep("A meaningful quest title ", 4),
					isComplete = quest % 3 == 0,
				}
			end
			net:SetQuestLog(peer, quests)
			peer.db.profile.compareAutoRefresh = false
			party[index] = peer
			net:StartPeer(peer)
		end
		local viewer, responder = party[1], party[2]
		viewer.isLocalDeveloper = true
		-- Cryptographic correctness has its own real-key suite. This private
		-- engine seam still yields so authentication runs through the runtime.
		function viewer:SignDeveloperRequest()
			return string.rep("s", 64)
		end
		responder.developerPublicKeyHex = string.rep("0", 64)
		responder.Ed25519 = {
			NewVerification = function()
				return coroutine.create(function()
					for _ = 1, 17 do
						coroutine.yield()
					end
					return true
				end)
			end,
		}
		local reports, snapshots, pongs = {}, 0, 0
		local report = string.rep("Diagnostic fixture state.\n", 1200)
		function responder:BuildDeveloperDiagnosticSnapshot()
			snapshots = snapshots + 1
			return report
		end
		function viewer:GetDebugController()
			return {
				ShowReport = function(_, text, sender)
					reports[#reports + 1] = { text = text, sender = sender, at = net.now }
				end,
			}
		end
		function viewer:PrintPingResponse()
			pongs = pongs + 1
		end
		assert(viewer:RefreshPartyQuestCompare())
		assert(viewer:SendPingRequest(responder.name, true))
		local started, logsAt = net.now, nil
		for tick = 1, 240 do
			responder.position.x = 0.2 + tick % 30 / 100
			net:Advance(1)
			local complete = true
			for _, member in ipairs(viewer.partyQuestCompareSession.members) do
				if member.state ~= "ready" then
					complete = false
				end
			end
			if complete and not logsAt then
				logsAt = net.now
			end
			if complete and #reports == 1 then
				break
			end
		end
		local statuses = {}
		for _, member in ipairs(viewer.partyQuestCompareSession.members) do
			statuses[#statuses + 1] = member.name .. ":" .. member.state
		end
		assert(
			logsAt and logsAt - started < 90,
			"five-player PQL must make progress beside diagnostics: "
				.. table.concat(statuses, ",")
				.. " completion="
				.. tostring(logsAt and logsAt - started)
		)
		Equal(#reports, 1, "diagnostic report must finish at " .. fps .. " FPS; snapshots=" .. snapshots
			.. " pongs=" .. pongs .. " responderOutgoing=" .. responder:GetCommTransferMetrics().outgoing
			.. " viewerIncoming=" .. viewer:GetCommTransferMetrics().incoming)
		Equal(reports[1].text, report)
		Equal(reports[1].sender, responder.name)
		Equal(snapshots, 1, "diagnostic snapshot must be sampled once")
		Equal(pongs, 1, "diagnostic pong must complete")
		for _, member in ipairs(viewer.partyQuestCompareSession.members) do
			local count = 0
			for _ in pairs(member.entries) do
				count = count + 1
			end
			Equal(count, 30)
		end
		local location = viewer:GetPlayerLocationState().peers[responder.name]
		assert(
			location and viewer.API.GetTime() - location.receivedAt < 10,
			"bulk traffic must not starve moving peers"
		)
		for _, peer in ipairs(party) do
			local bytes = 0
			for _, packet in ipairs(peer.sent) do
				bytes = bytes + #packet.wire + #packet.prefix + 40
			end
			assert(bytes <= 800 * (net.now - started) + 1600)
			assert(#peer.sent <= 4 * (net.now - started) + 4)
		end
	end
end, { offline = true })

-- Full multi-peer, multi-frame network simulations run offline.
QT:RegisterTest("network v2 accepts a late correlated pong without reviving its old coordinates", function()
	local net = QT:CreateTestNetwork({ fps = 5 })
	local a, b = net:AddPeer("Developer-Realm"), net:AddPeer("Friend-Realm")
	a.isLocalDeveloper = true
	function a:SignDeveloperRequest()
		return string.rep("s", 64)
	end
	local received = {}
	function a:PrintPingResponse(record)
		received[#received + 1] = record
	end
	b.db.profile.sharePlayerLocation = false
	b.db.profile.shareDeveloperDiagnostics = false
	net:StartPeer(a)
	net:StartPeer(b)
	local accepted, requestId = a:SendPingRequest(b.name, false)
	assert(accepted)
	local sampledAt = b.API.GetServerTime()
	net:Advance(605)
	Equal(#received, 0)
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	local record = {
		requestId = requestId,
		senderName = b.name,
		sampledAt = sampledAt,
		mapID = "12",
		coordX = "42",
		coordY = "63",
		locationShared = true,
		addonVersion = "7.0.0",
	}
	assert(b:Respond("PONG", record, { { distribution = "WHISPER", target = a.name } }))
	net:Advance(3)
	Equal(#received, 1)
	Equal(received[1].requestId, requestId)
	Equal(#a:GetVisiblePlayerLocations("map"), 0, "late reply receipt is not a new location sample")
	record.requestId = "unknown-ping"
	record.sampledAt = b.API.GetServerTime()
	assert(b:Respond("PONG", record, { { distribution = "WHISPER", target = a.name } }))
	net:Advance(3)
	Equal(#received, 1, "late acceptance still requires an owned request identity")
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
end, { offline = true })

QT:RegisterTest("native announcement receipt updates subscribed quest progress before chat and bubble presentation", function()
	local net = QT:CreateTestNetwork({fps=20})
	local a=net:AddPeer("Alice-Realm",{group="questers"})
	local b=net:AddPeer("Bob-Realm",{group="questers"})
	for _, peer in ipairs({ a, b }) do net:SetQuestLog(peer, { { questID = 42, title = "Bandanas" } }) end
	local progress = 1
	function b:ReadQuestCompareObjectives(id)
		return { { questId = id, objectiveIndex = 1, text = "Bandanas: " .. progress .. "/8", kind = "item",
			current = progress, required = 8, finished = false } }
	end
	net:StartPeer(a); net:StartPeer(b)
	local updates, presented = 0, 0
	function a:QueuePartyQuestCompareRender() updates=updates+1 end
	assert(a:RefreshPartyQuestCompare(nil, nil, true))
	net:Advance(5)
	a:TogglePartyQuestObjectives(42)
	local member = a.partyQuestCompareSession.byName[b.name]
	local record=member.objectiveDetails[42]
	Equal(record.objectives[1].current, 1)
	function a:HandleAnnouncementEvent(event)
		-- This is where chat option checks, title waits and bubbles start.
		Equal(record.objectives[1].current,7)
		presented=presented+1
	end
	local data={eventType="QUEST_PROGRESS",senderName=b.name,classFile="MAGE",questId="42",
		text="Bandanas: 7/8",occurredAt=100,eventFacts=b:BuildAnnouncementFacts("QUEST_PROGRESS",1,"item",false,7,8)}
	progress = 7
	assert(b:Emit("ANN",data,{{distribution="PARTY",requiresGroup=true}}))
	net:Advance(5)
	Equal(presented,1)
	assert(updates>=1)
	Equal(record.objectives[1].current,7)
	a:EndCommsWorldSession()
	Equal(member.objectiveDetails[42],nil)
	Equal(a.partyQuestProgress,nil)
	a:ResumeCommsWorldSession()
	local current = a.partyQuestCompareSession.byName[b.name]
	assert(current ~= member, "world resume must bind views to the new party lifetime")
	net:Advance(10)
	assert(current.objectiveDetails[42] and current.objectiveDetails[42] ~= record)
	Equal(current.objectiveDetails[42].state, "ready")
	Equal(current.objectiveDetails[42].objectives[1].current, 7)
end)
