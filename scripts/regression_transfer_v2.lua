-- Shared transfer tests use real framing, queues and asynchronous private peers.
local QT = _G.QuestTogether
local function Equal(a, b, message)
	assert(a == b, (message or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function Fixture(options)
	local net = QT:CreateTestNetwork(options)
	local a, b = net:AddPeer("Sender-Realm"), net:AddPeer("Receiver-Realm")
	for _, peer in ipairs({ a, b }) do
		peer.expected, peer.dispatched, peer.controls, peer.controlSequence = {}, {}, {}, 0
		peer.commPrefix = "QuestTogether3"
		peer:InitializeTransport()
		function peer:IsCommResponseExpected(frame, sender)
			local expiry = self.expected[sender .. ":" .. tostring(frame.requestId)]
			return expiry ~= nil and self.API.GetTime() < expiry, expiry
		end
		function peer:DispatchCommRecord(frame, record, sender)
			if self:GetCommOperation(frame.operation).semantic == "transfer" then
				return self:HandleCommTransferControl(frame.operation, record, sender)
			end
			self.dispatched[#self.dispatched + 1] = { frame = frame, record = record, sender = sender, at = net.now }
			return true
		end
		function peer:Emit(operation, record, routes, sendOptions)
			self.controlSequence = self.controlSequence + 1
			local frames = assert(self:BuildCommFrames(operation, record, {
				session = "control-session",
				messageId = "c" .. self.controlSequence,
				stamp = self.API.GetServerTime(),
			}))
			Equal(#frames, 1, "transfer controls must fit one native packet")
			self.controls[#self.controls + 1] = { operation = operation, record = record, at = net.now }
			return self:QueueTransportWire(frames[1], operation, routes[1], sendOptions)
		end
		function peer:OnCommReceived(_, wire, route, sender)
			local frame, body = self:DecodeCommFrame(wire)
			assert(frame)
			self:ReceiveCommFragment(frame, body, sender, { targeted = route == "WHISPER" })
		end
		local driver = net:CreateFrame(peer)
		driver:SetScript("OnUpdate", function()
			peer:UpdateCommTransfers()
			peer:DrainTransport()
		end)
	end
	return net, a, b
end
local function Frames(peer, operation, record, id)
	return assert(peer:BuildCommFrames(operation, record, {
		session = "sender-session",
		messageId = id or "object",
		requestId = record.requestId,
		stamp = peer.API.GetServerTime(),
	}))
end
local function Response(net, a, b, length, options)
	options = options or {}
	local id = options.id or "request1"
	b.expected[a.name .. ":" .. id] = options.expires or net.now + 180
	local frames = Frames(a, "DREPORT", { requestId = id, diagnosticText = string.rep("z", length or 1500) }, id)
	options.expires = options.expires or net.now + 180
	local admitted, reason, job =
		a:QueueCommTransfer(frames, "test response", { distribution = "WHISPER", target = b.name }, options)
	return admitted, reason, job, frames
end
local function CountControls(peer, op)
	local count = 0
	for _, row in ipairs(peer.controls) do
		if row.operation == op then
			count = count + 1
		end
	end
	return count
end

local function MeshAdmissionFixture()
	local net = QT:CreateTestNetwork()
	local receiver = net:AddPeer("Receiver-Realm")
	receiver:InitializeCommunications()
	receiver:InitializeMeshNetwork()
	local sequence = 0
	local function Partial(operation, record, sender)
		sequence = sequence + 1
		local frames = assert(receiver:BuildCommFrames(operation, record, {
			session = string.rep("s", 64),
			messageId = tostring(sequence),
			requestId = record.requestId,
			stamp = receiver.API.GetServerTime(),
		}))
		assert(#frames > 1, "exercise admission before a complete record can be validated")
		return receiver:ReceiveCommunication(receiver.commPrefix, frames[1], "WHISPER", sender)
	end
	local function Confirm(sender)
		-- These cases isolate assembly admission; genuine challenge and response
		-- handshakes are exercised by the independent network integration tests.
		receiver.meshNetworkState.neighbors[sender] = { name = sender, expires = net.now + 180 }
	end
	local function Publication(sender)
		return {
			origin = sender,
			session = "owner-session",
			id = "publication",
			operation = "QTCHAT",
			scope = "global",
			stamp = receiver.API.GetServerTime(),
			expiresAt = receiver.API.GetServerTime() + 60,
			body = assert(receiver:EncodeCommRecord("QTCHAT", { text = string.rep("x", 250) })),
			digest = string.rep("0", 128),
			leaseId = "lease",
			destination = receiver.name,
			zone = 0,
			hops = 8,
		}
	end
	return net, receiver, Partial, Confirm, Publication
end

QT:RegisterTest("transfer rejects unconfirmed mesh publications and interests before retaining partials", function()
	local _, receiver, partial, confirm, publication = MeshAdmissionFixture()
	local sender = "Candidate-Realm"
	local records = {
		MPUB = publication(sender),
		MINT = {
			leaseId = string.rep("l", 80),
			destination = string.rep("d", 120),
			zone = 0,
			expiresAt = receiver.API.GetServerTime() + 120,
			hops = 8,
		},
		MCAN = { leaseId = string.rep("l", 80), destination = string.rep("d", 120) },
	}
	for _ = 1, 5 do
		for operation, record in pairs(records) do
			assert(not partial(operation, record, sender))
		end
	end
	Equal(receiver:GetCommTransferMetrics().incoming, 0)
	Equal(receiver:GetCommTransferMetrics().bytes, 0)
	confirm(sender)
	for operation, record in pairs(records) do
		assert(partial(operation, record, sender))
	end
	Equal(receiver:GetCommTransferMetrics().incoming, 3)
	receiver.meshNetworkState.neighbors[sender] = nil
	receiver:UpdateCommTransfers()
	Equal(receiver:GetCommTransferMetrics().incoming, 0, "a retired edge cannot retain its incomplete records")
	Equal(receiver:GetCommTransferMetrics().bytes, 0)
end)

QT:RegisterTest("transfer reserves mesh assembly capacity against unconfirmed bootstrap requests", function()
	local _, receiver, partial, confirm, publication = MeshAdmissionFixture()
	local function Hello(id)
		return {
			requestId = string.rep("r", 70) .. id,
			version = string.rep("v", 40),
			protocol = 3,
			capabilities = "mesh1",
		}
	end
	local function Auth(id)
		return {
			requestId = string.rep("r", 70) .. id,
			session = string.rep("s", 64),
			items = { { id = string.rep("i", 64), operation = "QTCHAT", scope = "global" } },
		}
	end
	for index = 1, 4 do
		assert(
			partial(
				index % 2 == 0 and "MHEL" or "MAUTH",
				index % 2 == 0 and Hello(index) or Auth(index),
				"Bootstrap" .. index .. "-Realm"
			)
		)
	end
	assert(not partial("MHEL", Hello(5), "Bootstrap5-Realm"))
	assert(not partial("MAUTH", Auth(6), "Bootstrap6-Realm"))
	Equal(receiver:GetCommTransferMetrics().incoming, 4)
	for peer = 1, 3 do
		local sender = "Confirmed" .. peer .. "-Realm"
		confirm(sender)
		for _ = 1, 4 do
			assert(partial("MPUB", publication(sender), sender))
		end
	end
	Equal(receiver:GetCommTransferMetrics().incoming, 16, "confirmed neighbors retain twelve available slots")
end)

QT:RegisterTest("transfer admits only correlated native mesh replies outside the bootstrap sublimit", function()
	local _, receiver, partial = MeshAdmissionFixture()
	for index = 1, 4 do
		assert(partial("MAUTH", {
			requestId = "unsolicited" .. index,
			session = string.rep("s", 64),
			items = {
				{ id = string.rep("i", 64), operation = "QTCHAT", scope = "global" },
				{ id = string.rep("j", 64), operation = "QTCHAT", scope = "global" },
			},
		}, "Unknown" .. index .. "-Realm"))
	end
	for _, operation in ipairs({ "MHEL", "MAUTH" }) do
		local sender = operation .. "-Realm"
		local request = operation == "MHEL" and { protocol = 3, capabilities = "mesh1" }
			or { session = "owner-session", items = { { id = "publication", operation = "QTCHAT", scope = "global" } } }
		local admitted, _, _, requestId = receiver:Request(
			operation,
			request,
			{ { distribution = "WHISPER", target = sender } },
			{ owner = receiver }
		)
		assert(admitted)
		local deadline = receiver:GetCommunicationRequestDeadline(requestId)
		local response = operation == "MHEL" and "MACK" or "MAPRF"
		local record = response == "MACK"
				and {
					requestId = requestId,
					admitted = true,
					protocol = 3,
					capabilities = "mesh1",
					peers = { { name = string.rep("p", 120) }, { name = string.rep("q", 120) } },
				}
			or {
				requestId = requestId,
				session = "owner-session",
				items = {
					{
						id = "publication",
						operation = "QTCHAT",
						scope = "global",
						digest = string.rep("a", 128),
					},
				},
			}
		assert(
			not partial(response, record, "Impersonator-Realm"),
			"a copied request ID is not native sender correlation"
		)
		assert(partial(response, record, sender), "direct replies remain reachable without a graph edge")
		Equal(
			receiver:GetCommunicationRequestDeadline(requestId),
			deadline,
			"partial mesh replies cannot extend their lease"
		)
		receiver:CancelCommRequest(requestId, "test-cancel")
		receiver:UpdateCommTransfers()
		Equal(receiver:GetCommTransferMetrics().incoming, 4, "cancelling the request retires its incomplete reply")
		assert(not partial(response, record, sender), "expired request IDs cannot bypass the bootstrap sublimit")
	end
end)

QT:RegisterTest("transfer partial handshake replies expire without pinning a bootstrap request", function()
	local net, receiver, partial = MeshAdmissionFixture()
	local expired = 0
	local admitted, _, _, requestId = receiver:Request(
		"MHEL",
		{ protocol = 3, capabilities = "mesh1" },
		{ { distribution = "WHISPER", target = "Candidate-Realm" } },
		{
			owner = receiver,
			expires = net.now + 20,
			onExpire = function()
				expired = expired + 1
			end,
		}
	)
	assert(admitted)
	assert(
		partial(
			"MACK",
			{
				requestId = requestId,
				admitted = true,
				protocol = 3,
				capabilities = "mesh1",
				peers = { { name = string.rep("p", 120) }, { name = string.rep("q", 120) } },
			},
			"Candidate-Realm"
		)
	)
	Equal(receiver:GetCommTransferMetrics().incoming, 1)
	net:Advance(20.1)
	receiver:UpdateCommunicationRuntime()
	Equal(expired, 1)
	Equal(receiver:GetCommunicationRequestDeadline(requestId), nil)
	Equal(receiver:GetCommTransferMetrics().incoming, 0)
	Equal(receiver:GetCommTransferMetrics().bytes, 0)
end)

local function QuestResponse(net, a, b, id)
	b.expected[a.name .. ":" .. id] = net.now + 600
	local frames = Frames(a, "QCRS", {
		requestId = id,
		snapshotId = id,
		count = 1,
		entries = { { questId = 42, questTitle = string.rep("quest", 150) } },
	}, id)
	return a:QueueCommTransfer(
		frames,
		"quest response",
		{ distribution = "WHISPER", target = b.name },
		{ expires = net.now + 600 }
	)
end

QT:RegisterTest("abandoned quest snapshots cancel active senders and recover a lost cancellation", function()
	for _, loseNotice in ipairs({ false, true }) do
		local net, a, b = Fixture({ fps = 20 })
		local lost = false
		if loseNotice then
			net.deliveryRule = function(packet)
				local frame = a:DecodeCommFrame(packet.wire)
				if frame.operation == "FXACK" and not lost then
					lost = true
					return { drop = true }
				end
			end
		end
		local accepted, _, job = QuestResponse(net, a, b, "cancelled-detail")
		assert(accepted)
		net:Advance(0.6)
		assert(
			next(b.commTransferState.incoming) and not job.initialComplete,
			"cancellation must interrupt a partial snapshot before the sender finishes"
		)
		b:CancelIncomingCommResponses("cancelled-detail", "cancelled")
		net:Advance(8)
		Equal(#b.dispatched, 0)
		Equal(a:GetCommTransferMetrics().outgoing, 0)
		Equal(a:GetCommTransferMetrics().bytes, 0)
		if loseNotice then
			assert(
				lost and CountControls(b, "FXACK") >= 2,
				"late END must recover the lost cancellation without installing the snapshot"
			)
		else
			assert(CountControls(b, "FXACK") >= 1)
		end
	end
end)

QT:RegisterTest("retained quest repair copies yield capacity while active transfers stay protected", function()
	local net, a, b = Fixture({ fps = 10 })
	net.deliveryRule = function(packet)
		local frame = a:DecodeCommFrame(packet.wire)
		if frame.operation == "FXACK" then
			return { drop = true }
		end
	end
	for index = 1, 16 do
		assert(QuestResponse(net, a, b, "retained" .. index))
		net:Advance(3)
	end
	Equal(a:GetCommTransferMetrics().outgoing, 16)
	assert(QuestResponse(net, a, b, "fresh-detail"), "lost ACKs must not block new detail for ten minutes")
	net:Advance(3)
	local snapshots, unavailable = 0, 0
	for _, item in ipairs(b.dispatched) do
		if item.frame.operation == "QCRS" then
			snapshots = snapshots + 1
		end
		if item.frame.operation == "ERROR" and item.record.code == "capacity" then
			unavailable = unavailable + 1
		end
	end
	Equal(snapshots, 17)
	Equal(unavailable, 1, "an interested evicted receiver must be told its old snapshot is unavailable")
	Equal(a:GetCommTransferMetrics().recoveryEvicted, 1)

	local busy, sender, receiver = Fixture({ fps = 10 })
	for index = 1, 16 do
		assert(QuestResponse(busy, sender, receiver, "active" .. index))
	end
	local admitted, reason = QuestResponse(busy, sender, receiver, "overflow")
	Equal(admitted, false)
	Equal(reason, "capacity")
	Equal(sender:GetCommTransferMetrics().recoveryEvicted, nil)
	Equal(sender:GetCommTransferMetrics().outgoing, 16)
end, { offline = true })

QT:RegisterTest(
	"transfer protocol 3 finishes unsent fragments after an ambiguous submission without replaying it",
	function()
		for _, delivered in ipairs({ false, true }) do
			local net, a, b = Fixture({ fps = 10 })
			local frames = Frames(a, "STATE", {
				records = {
					{
						topic = "QTLQ",
						data = { title = string.rep("q", 700) },
						sampledAt = a.API.GetServerTime(),
						revision = 1,
					},
				},
			})
			assert(#frames > 2)
			local attempts, completed, outcome = {}, 0, nil
			net.sendRule = function(packet)
				local frame = a:DecodeCommFrame(packet.wire)
				attempts[frame.part] = (attempts[frame.part] or 0) + 1
				if frame.part == 1 then
					return 8, delivered
				end
				return 0
			end
			assert(a:QueueCommTransfer(frames, "state", { distribution = "WHISPER", target = b.name }, {
				expires = net.now + 30,
				onComplete = function(sent, reason)
					completed, outcome = completed + 1, reason
					assert(not sent, "ambiguous native acceptance must stay ambiguous")
				end,
			}))
			net:Advance(10)
			for index = 1, #frames do
				Equal(attempts[index], 1, "every fragment must be attempted exactly once")
			end
			Equal(completed, 1)
			Equal(outcome, "ambiguous")
			Equal(#b.dispatched, delivered and 1 or 0)
			net:Advance(31)
			Equal(a:GetCommTransferMetrics().bytes + b:GetCommTransferMetrics().bytes, 0)
			Equal(completed, 1)
		end
	end
)

QT:RegisterTest(
	"transfer protocol 3 publishes once after complete reordered duplicates and releases acknowledged payload",
	function()
		local net, a, b = Fixture({ latency = 0.05 })
		local completions = {}
		net.deliveryRule = function(packet)
			local frame = a:DecodeCommFrame(packet.wire)
			if frame.operation == "DREPORT" then
				return { delay = frame.part % 2 == 0 and 0.02 or 0.8, copies = 2 }
			end
		end
		assert(Response(net, a, b, 3000, {
			onComplete = function(ok, reason)
				completions[#completions + 1] = { ok, reason }
			end,
		}))
		net:Advance(20)
		Equal(#b.dispatched, 1)
		Equal(#b.dispatched[1].record.diagnosticText, 3000)
		Equal(#completions, 1)
		Equal(completions[1][1], true)
		Equal(completions[1][2], "accepted")
		Equal(a:GetCommTransferMetrics().outgoing, 0)
		Equal(a:GetCommTransferMetrics().bytes, 0)
		Equal(b:GetCommTransferMetrics().incoming, 0)
		Equal(b:GetCommTransferMetrics().bytes, 0)
	end
)

QT:RegisterTest("transfer protocol 3 repairs only missing accepted fragments after END within two rounds", function()
	local net, a, b = Fixture()
	local attempts, completions = {}, 0
	net.deliveryRule = function(packet)
		local frame = a:DecodeCommFrame(packet.wire)
		if frame.operation == "DREPORT" then
			attempts[frame.part] = (attempts[frame.part] or 0) + 1
			if frame.part == 2 and attempts[2] <= 2 then
				return { drop = true }
			end
		end
	end
	local _, _, _, frames = Response(net, a, b, 1200, {
		onComplete = function(ok)
			assert(ok)
			completions = completions + 1
		end,
	})
	net:Advance(20)
	Equal(#b.dispatched, 1)
	Equal(attempts[2], 3)
	for index = 1, #frames do
		if index ~= 2 then
			Equal(attempts[index], 1)
		end
	end
	Equal(CountControls(b, "FXMISS"), 2)
	Equal(completions, 1)
end)

QT:RegisterTest("transfer protocol 3 stops repair after two rounds and never extends request lifetime", function()
	local net, a, b = Fixture()
	local attempts, completions = 0, 0
	net.deliveryRule = function(packet)
		local frame = a:DecodeCommFrame(packet.wire)
		if frame.operation == "DREPORT" and frame.part == 2 then
			attempts = attempts + 1
			return { drop = true }
		end
	end
	assert(Response(net, a, b, 1200, {
		expires = net.now + 20,
		onComplete = function()
			completions = completions + 1
		end,
	}))
	net:Advance(21)
	Equal(attempts, 3)
	Equal(#b.dispatched, 0)
	Equal(completions, 1)
	Equal(a:GetCommTransferMetrics().outgoing, 0)
	Equal(b:GetCommTransferMetrics().incoming, 0)
	Equal(a:GetCommTransferMetrics().bytes + b:GetCommTransferMetrics().bytes, 0)
end)

-- Full transfer-capacity and multi-minute recovery simulations run offline.
QT:RegisterTest("transfer protocol 3 status probes distinguish a still queued sender from lost data", function()
	local net, a, b = Fixture()
	assert(Response(net, a, b, 40000, { expires = net.now + 180 }))
	-- A long native throttle leaves a valid partial object but no END.
	local accepted = 0
	net.sendRule = function(packet)
		local frame = a:DecodeCommFrame(packet.wire)
		if frame.operation == "DREPORT" then
			accepted = accepted + 1
			if accepted > 1 and net.now < 145 then
				return 3
			end
		end
		return 0
	end
	net:Advance(40)
	assert(CountControls(b, "FXSTAT") > 0)
	Equal(CountControls(b, "FXMISS"), 0)
	local sending = false
	for _, row in ipairs(a.controls) do
		if row.operation == "FXSTAT" and row.record.status == "sending" then
			sending = true
		end
	end
	assert(sending, "sender must explain queued progress without causing fragment replay")
	a:ResetCommTransfers()
	b:ResetCommTransfers()
	Equal(a:GetCommTransferMetrics().bytes + b:GetCommTransferMetrics().bytes, 0)
end, { offline = true })

QT:RegisterTest(
	"transfer protocol 3 currentness cancellation completes once and rejects stale native completion",
	function()
		local net, a, b = Fixture()
		local current, completions = true, {}
		assert(Response(net, a, b, 1200, {
			isCurrent = function()
				return current
			end,
			onComplete = function(ok, reason)
				completions[#completions + 1] = { ok, reason }
			end,
		}))
		a:UpdateCommTransfers()
		local stale = a:GetTransportState().queue[1].onComplete
		current = false
		a:UpdateCommTransfers()
		stale(true, "accepted")
		net:Advance(2)
		Equal(#completions, 1)
		Equal(completions[1][1], false)
		Equal(completions[1][2], "cancelled")
		Equal(#a.sent, 0)
		Equal(a:GetCommTransferMetrics().bytes, 0)
	end
)

QT:RegisterTest("transfer protocol 3 single packet responses need no recovery handshake", function()
	local net, a, b = Fixture({ latency = 0.5 })
	local callbackAt
	assert(Response(net, a, b, 1, {
		onComplete = function(ok)
			assert(ok)
			callbackAt = net.now
		end,
	}))
	net:Advance(2)
	Equal(#b.dispatched, 1)
	assert(callbackAt < b.dispatched[1].at, "native completion must remain distinct from remote completion")
	Equal(#a.controls + #b.controls, 0)
	Equal(a:GetCommTransferMetrics().outgoing, 0)
end)

-- Full transfer-capacity and multi-minute recovery simulations run offline.
QT:RegisterTest("transfer protocol 3 reserves inbound slots and bounds unsolicited per sender assemblies", function()
	local net, a, b = Fixture()
	local record = {
		records = { { topic = "QTLQ", sampledAt = a.API.GetServerTime(), data = { title = string.rep("x", 1000) } } },
	}
	for index = 1, 5 do
		local frame, body = a:DecodeCommFrame(Frames(a, "STATE", record, "own" .. index)[1])
		Equal(b:ReceiveCommFragment(frame, body, a.name, {}), index <= 4)
	end
	b:ResetCommTransfers()
	for index = 1, 48 do
		local frame, body = a:DecodeCommFrame(Frames(a, "STATE", record, "state" .. index)[1])
		assert(b:ReceiveCommFragment(frame, body, "Public" .. index .. "-Realm", {}))
	end
	local frame, body = a:DecodeCommFrame(Frames(a, "STATE", record, "blocked")[1])
	Equal(b:ReceiveCommFragment(frame, body, "Another-Realm", {}), false)
	for index = 1, 17 do
		local id = "response" .. index
		b.expected[a.name .. ":" .. id] = net.now + 20
		frame, body =
			a:DecodeCommFrame(Frames(a, "DREPORT", { requestId = id, diagnosticText = string.rep("x", 600) }, id)[1])
		Equal(b:ReceiveCommFragment(frame, body, a.name, { targeted = true }), index <= 16)
	end
	Equal(b:GetCommTransferMetrics().incoming, 64)
	net:Advance(31)
	Equal(b:GetCommTransferMetrics().incoming, 0)
	Equal(b:GetCommTransferMetrics().bytes, 0)
end, { offline = true })

QT:RegisterTest("transfer protocol 3 bounds retained outgoing objects and combined payload bytes", function()
	local net, a, b = Fixture()
	for index = 1, 6 do
		local admitted = Response(net, a, b, 90000, { id = "large" .. index })
		Equal(admitted, index <= 5)
	end
	assert(a:GetCommTransferMetrics().bytes <= 524288)
	a:ResetCommTransfers()
	for index = 1, 17 do
		Equal(Response(net, a, b, 600, { id = "small" .. index }), index <= 16)
	end
	Equal(a:GetCommTransferMetrics().outgoing, 16)
	a:ResetCommTransfers()
	Equal(a:GetCommTransferMetrics().bytes, 0)
end)

QT:RegisterTest("transfer protocol 3 conflicting fragments retire the object without partial dispatch", function()
	local _, a, b = Fixture()
	b.expected[a.name .. ":req"] = b.API.GetTime() + 20
	local frames = Frames(a, "DREPORT", { requestId = "req", diagnosticText = string.rep("x", 1000) })
	local frame, body = a:DecodeCommFrame(frames[1])
	assert(b:ReceiveCommFragment(frame, body, a.name, { targeted = true }))
	Equal(b:ReceiveCommFragment(frame, body .. "!", a.name, { targeted = true }), false)
	for _, wire in ipairs(frames) do
		frame, body = a:DecodeCommFrame(wire)
		b:ReceiveCommFragment(frame, body, a.name, { targeted = true })
	end
	Equal(#b.dispatched, 0)
	Equal(b:GetCommTransferMetrics().incoming, 0)
	Equal(b:GetCommTransferMetrics().bytes, 0)
end)

QT:RegisterTest("transfer protocol 3 recovers a lost END through a bounded status request", function()
	local net, a, b = Fixture()
	local attempts = 0
	net.deliveryRule = function(packet)
		local frame = a:DecodeCommFrame(packet.wire)
		if frame.operation == "FXEND" then
			return { drop = true }
		end
		if frame.operation == "DREPORT" and frame.part == 2 then
			attempts = attempts + 1
			if attempts == 1 then
				return { drop = true }
			end
		end
	end
	assert(Response(net, a, b, 1200))
	net:Advance(45)
	Equal(#b.dispatched, 1)
	Equal(attempts, 2)
	assert(CountControls(b, "FXSTAT") >= 1 and CountControls(b, "FXSTAT") <= 2)
	Equal(a:GetCommTransferMetrics().outgoing, 0)
end)

QT:RegisterTest(
	"transfer protocol 3 ignores unsolicited response fragments before allocating payload storage",
	function()
		local net, a, b = Fixture()
		local frame, body =
			a:DecodeCommFrame(Frames(a, "DREPORT", { requestId = "unknown", diagnosticText = string.rep("x", 600) })[1])
		Equal(b:ReceiveCommFragment(frame, body, a.name, { targeted = true }), false)
		Equal(b:GetCommTransferMetrics().incoming, 0)
		Equal(b:GetCommTransferMetrics().bytes, 0)
		b.expected[a.name .. ":unknown"] = net.now + 1
		assert(b:ReceiveCommFragment(frame, body, a.name, { targeted = true }))
		net:Advance(1.1)
		Equal(b:GetCommTransferMetrics().incoming, 0)
		Equal(b:ReceiveCommFragment(frame, body, a.name, { targeted = true }), false)
	end
)

QT:RegisterTest("transfer protocol 3 rotates concurrent objects with at most one queued fragment each", function()
	local net, a, b = Fixture()
	local _, _, large = Response(net, a, b, 40000, { id = "large" })
	local _, _, small = Response(net, a, b, 600, { id = "small" })
	a:UpdateCommTransfers()
	Equal(#a:GetTransportState().queue, 2)
	for _ = 1, 5 do
		a:UpdateCommTransfers()
	end
	Equal(#a:GetTransportState().queue, 2, "ticks cannot queue multiple fragments of one object")
	net:Advance(10)
	local completedSmall = false
	for _, received in ipairs(b.dispatched) do
		if received.record.requestId == "small" then
			completedSmall = true
		end
	end
	assert(completedSmall, "small object must not wait behind a complete large transfer")
	Equal(small.retired, true)
	Equal(large.initialComplete, nil)
	a:ResetCommTransfers()
	b:ResetCommTransfers()
end)

QT:RegisterTest("transfer protocol 3 replacement callbacks cannot resurrect an ended transfer runtime", function()
	local net, a, b = Fixture()
	local completions = 0
	assert(Response(net, a, b, 600, {
		key = "replace",
		onComplete = function(ok, reason)
			Equal(ok, false)
			Equal(reason, "superseded")
			completions = completions + 1
			a:ResetCommTransfers()
		end,
	}))
	local accepted, reason, replacement = Response(net, a, b, 600, { id = "replacement", key = "replace" })
	Equal(accepted, true)
	Equal(reason, "queued")
	Equal(replacement.retired, true)
	Equal(completions, 1)
	Equal(rawget(a, "commTransferState"), nil)
	net:Advance(2)
	Equal(#a.sent, 0)
end)

QT:RegisterTest("transfer protocol 3 reentrant supersession keeps only the newest object", function()
	local net, a, b = Fixture()
	local completed, newest = {}, nil
	local function Completion(name)
		return function(ok, reason, _, ticket)
			Equal(completed[name], nil, "completion must run once per admitted object")
			completed[name] = { ok = ok, reason = reason, ticket = ticket }
		end
	end
	local _, _, old = Response(net, a, b, 600, {
		id = "old",
		key = "replace",
		onComplete = function(ok, reason, code, ticket)
			Completion("old")(ok, reason, code, ticket)
			local accepted
			accepted, _, newest = Response(net, a, b, 600, {
				id = "newest",
				key = "replace",
				onComplete = Completion("newest"),
			})
			assert(accepted)
		end,
	})
	local accepted, _, outer = Response(net, a, b, 600, {
		id = "outer",
		key = "replace",
		onComplete = Completion("outer"),
	})
	assert(accepted)
	Equal(completed.old.reason, "superseded")
	Equal(completed.old.ticket, old)
	Equal(completed.outer.reason, "superseded")
	Equal(completed.outer.ticket, outer)
	Equal(#a.commTransferState.outgoing, 1)
	Equal(a.commTransferState.outgoing[1], newest)
	net:Advance(5)
	Equal(completed.newest.ok, true)
	Equal(completed.newest.ticket, newest)
	Equal(#b.dispatched, 1)
	Equal(b.dispatched[1].record.requestId, "newest")
end)
