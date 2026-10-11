-- End-to-end communication tests use only private peers and engine adapters.
local QT = _G.QuestTogether
local function Equal(actual, expected, detail)
	assert(actual == expected, (detail or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

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
		Equal(#reports, 1)
		Equal(reports[1].text, report)
		Equal(reports[1].sender, responder.name)
		Equal(snapshots, 1)
		Equal(pongs, 1)
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
