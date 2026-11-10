-- Authentication tests isolate routing decisions but run the production
-- canonical codec, cooperative hash, owner store and native confirmation path.
local QT = _G.QuestTogether
local function Peer(name)
	local a = QT:CreateTestNetwork():AddPeer(name)
	a:InitializeCommunications()
	a.delivered, a.forwarded = {}, {}
	function a:CanAcceptMeshPublicationRoute()
		return not self.routeRetired
	end
	function a:ShouldConsumeMeshPublicationRoute()
		return not self.routeRetired
	end
	function a:DispatchVerifiedMeshRecord(frame, data, origin)
		self.delivered[#self.delivered + 1] = { frame = frame, data = data, origin = origin }
	end
	function a:ForwardMeshPublication(publication, options)
		self.forwarded[#self.forwarded + 1] = publication
		if options.onComplete then
			options.onComplete(true, "accepted")
		end
		return true, "queued"
	end
	function a:Request(operation, data, routes, options)
		self.auth = { operation = operation, data = data, routes = routes, options = options }
		return true, "queued", {}, "auth-request"
	end
	return a
end
local function Finish(a)
	for _ = 1, 1000 do
		a:UpdateMeshPublications(a.now)
		local s = a.meshPublicationState
		if not s or #s.jobs == 0 then
			return
		end
	end
	error("bounded hash progression did not complete")
end
local function Publish(owner, operation, data, options)
	local context = {
		operation = operation,
		session = owner:GetCommunicationSession(),
		messageId = tostring(owner:NextCommunicationSequence()),
		stamp = owner:GetAnnouncementServerTime(),
	}
	options = options or { owner = owner, expires = owner.now + 30 }
	assert(owner:QueueMeshPublication(context, data, "global", options))
	Finish(owner)
	return assert(owner.forwarded[#owner.forwarded]), context
end
local function Proof(publication, digest)
	return {
		id = publication.id,
		operation = publication.operation,
		scope = tostring(publication.scope),
		digest = digest or publication.digest,
	}
end
local function Wire(publication)
	local wire = QT:DeepCopy(publication)
	wire.scope, wire.leaseId, wire.destination, wire.zone, wire.hops =
		tostring(wire.scope), "lease", "Receiver-Realm", 0, 8
	return wire
end
local function Rehash(wire)
	local fields = { "origin", "session", "id", "operation", "scope", "originRequestId", "stamp", "expiresAt", "body" }
	local cells = { "QTMESH3" }
	for _, field in ipairs(fields) do
		local value = wire[field] == nil and "" or tostring(wire[field])
		cells[#cells + 1] = #value .. ":" .. value
	end
	wire.digest = QT.Ed25519.Hash(table.concat(cells, "|")):gsub(".", function(c)
		return string.format("%02x", c:byte())
	end)
	return wire
end
local function AwaitAuth(receiver)
	Finish(receiver)
	receiver.now = receiver.now + 1
	receiver:UpdateMeshPublications(receiver.now)
	return assert(receiver.auth)
end

QT:RegisterTest("mesh publication native ownership and immutable hashes prevent relay impersonation", function()
	local owner = Peer("Owner-Realm")
	local publication = Publish(owner, "QTCHAT", { text = "Original public message" })
	local direct = Peer("Receiver-Realm")
	assert(direct:HandleMeshPublication(Wire(publication), owner.name))
	Finish(direct)
	assert(#direct.delivered == 1 and direct.delivered[1].origin == owner.name)
	assert(not direct.auth, "native owner delivery must not need another round trip")
	local altered = Peer("Receiver-Realm")
	local forged = Wire(publication)
	forged.body = assert(altered:EncodeCommRecord("QTCHAT", { text = "Forged public message" }))
	assert(altered:HandleMeshPublication(forged, "Relay-Realm"))
	Finish(altered)
	assert(
		#altered.delivered == 0 and #altered.forwarded == 0 and not altered.auth,
		"changing a body while copying its owner's digest must fail before authentication"
	)
	assert(altered:GetMeshPublicationMetrics().hashRejected == 1)
	local receiver = Peer("Receiver-Realm")
	assert(receiver:HandleMeshPublication(Wire(publication), "Relay-Realm"))
	local request = AwaitAuth(receiver)
	assert(#receiver.delivered == 0 and #receiver.forwarded == 0)
	local proof = { session = publication.session, items = { Proof(publication) } }
	assert(not request.options.onResponse(proof, "Relay-Realm"), "relay cannot confirm another owner's identity")
	assert(request.options.onResponse(proof, owner.name))
	assert(#receiver.delivered == 1 and receiver.delivered[1].data.text == "Original public message")
end)

QT:RegisterTest(
	"mesh publication abandoned native hops release partial slots without cancelling a replacement",
	function()
		for _, scenario in ipairs({ "normal", "lost-notice", "ambiguous" }) do
			local loseNotice = scenario == "lost-notice"
			local net = QT:CreateTestNetwork({ fps = 20, latency = 0.03 })
			local sender, receiver = net:AddPeer("Sender-Realm"), net:AddPeer("Receiver-Realm")
			for _, peer in ipairs({ sender, receiver }) do
				peer:InitializeCommunications()
				peer:InitializeMeshNetwork()
				local other = peer == sender and receiver or sender
				peer.meshNetworkState.neighbors[other.name] = { name = other.name, expires = net.now + 180 }
				peer.delivered = 0
				function peer:OnCommReceived(_, wire, _, nativeSender)
					local frame, body = assert(self:DecodeCommFrame(wire)), select(2, self:DecodeCommFrame(wire))
					return self:ReceiveCommFragment(
						frame,
						body,
						nativeSender,
						{ distribution = "WHISPER", targeted = true, meshTraffic = true }
					)
				end
				function peer:DispatchCommRecord(frame, data, nativeSender)
					if self:GetCommOperation(frame.operation).semantic == "transfer" then
						return self:HandleCommTransferControl(frame.operation, data, nativeSender)
					end
					self.delivered = self.delivered + 1
					return true
				end
				local driver = net:CreateFrame(peer)
				driver:SetScript("OnUpdate", function()
					peer:UpdateCommTransfers()
					peer:DrainTransport()
				end)
			end
			local publication = Wire(Publish(Peer(sender.name), "ANN", {
				eventType = "QUEST_PROGRESS",
				text = string.rep("x", 900),
			}))
			local starts = {}
			local function Queue(id)
				local frames = assert(sender:BuildCommFrames("MPUB", publication, {
					session = "hop-session",
					messageId = id,
					stamp = sender:GetAnnouncementServerTime(),
				}))
				local ok, _, job = sender:QueueCommTransfer(
					frames,
					"MPUB",
					{ distribution = "WHISPER", target = receiver.name },
					{
						key = id,
						meshTraffic = true,
						expires = sender.now + 90,
						onStarted = function()
							starts[id] = (starts[id] or 0) + 1
						end,
					}
				)
				assert(ok and #frames > 2)
				assert(not starts[id], "admission is not native progress")
				return job, frames
			end
			local lost = false
			local ambiguous = false
			net.sendRule = function(packet)
				if
					scenario == "ambiguous"
					and not ambiguous
					and sender:DecodeCommFrame(packet.wire).operation == "MPUB"
				then
					ambiguous = true
					return 8, true
				end
				return 0
			end
			net.deliveryRule = function(packet)
				local frame, body = sender:DecodeCommFrame(packet.wire)
				local record = frame.operation == "FXSTAT" and sender:DecodeCommRecord("FXSTAT", body)
				if loseNotice and not lost and record and record.status == "unavailable" then
					lost = true
					return { drop = true }
				end
			end
			local old, oldFrames = Queue("1")
			for _ = 1, 100 do
				net:Advance(0.05)
				if receiver.commTransferState and next(receiver.commTransferState.incoming) then
					break
				end
			end
			local key = sender.name .. ":hop-session:1"
			assert(receiver.commTransferState.incoming[key] and not old.initialComplete)
			assert(starts["1"] == 1, "possibly delivered bytes expose the source object exactly once")
			for _, invalid in ipairs({
				{ sender = "Other-Realm", session = "hop-session", id = "1" },
				{ sender = sender.name, session = "another-session", id = "1" },
				{ sender = sender.name, session = "hop-session", id = "2" },
			}) do
				assert(
					not receiver:HandleCommTransferControl(
						"FXSTAT",
						{ session = invalid.session, messageId = invalid.id, status = "unavailable" },
						invalid.sender
					)
				)
			end
			assert(receiver.commTransferState.incoming[key], "unrelated native controls cannot retire a partial")
			sender:CancelCommTransfers(function(job)
				return job == old
			end, "superseded")
			Queue("2")
			net:Advance(loseNotice and 45 or 20)
			assert(not receiver.commTransferState.incoming[key], "retired source must release its remote partial")
			assert(receiver.delivered == 1, "retirement must preserve the independently identified replacement")
			assert(starts["1"] == 1 and starts["2"] == 1, "repair and completion cannot restart the exposure callback")
			if scenario == "ambiguous" then
				assert(ambiguous)
			end
			assert((receiver:GetCommTransferMetrics().abandonedMeshRetired or 0) == 1)
			if loseNotice then
				assert(lost, "exercise recovery from a dropped abort notice")
			end
			local frame, body = receiver:DecodeCommFrame(oldFrames[1])
			assert(not receiver:ReceiveCommFragment(frame, body, sender.name, { meshTraffic = true, targeted = true }))
			assert(not receiver.commTransferState.incoming[key], "late old fragments cannot reopen a retired partial")
		end
	end,
	{ offline = true }
)

QT:RegisterTest(
	"mesh publication copied confirmations conflicts and stale route callbacks cannot install data",
	function()
		local owner = Peer("Owner-Realm")
		local original = Publish(owner, "QTCHAT", { text = "First" })
		local other = Publish(owner, "QTCHAT", { text = "Second" })
		for _, boundary in ipairs({ "digest", "route", "reset", "ignore", "expiry" }) do
			local receiver = Peer("Receiver-Realm")
			assert(receiver:HandleMeshPublication(Wire(original), "Relay-Realm"))
			local conflict = Wire(original)
			conflict.digest = other.digest
			assert(not receiver:HandleMeshPublication(conflict, "Relay-Realm"))
			local request = AwaitAuth(receiver)
			if boundary == "route" then
				receiver.routeRetired = true
			elseif boundary == "reset" then
				receiver:ResetMeshPublications()
			elseif boundary == "ignore" then
				receiver.ignored[owner.name] = true
			elseif boundary == "expiry" then
				receiver.now = receiver.now + 31
			end
			request.options.onResponse({
				session = original.session,
				items = { Proof(original, boundary == "digest" and other.digest or original.digest) },
			}, owner.name)
			assert(#receiver.delivered == 0 and #receiver.forwarded == 0, boundary)
		end
	end
)

QT:RegisterTest(
	"mesh publication owner confirmations survive producer completion but respect privacy withdrawal",
	function()
		local owner, completions, pending = Peer("Owner-Realm"), 0, true
		local publication = Publish(owner, "LOC", { mask = 3, mapID = 12, x = 0.4, y = 0.6 }, {
			owner = owner,
			expires = owner.now + 30,
			publishesLocation = true,
			isCurrent = function()
				return pending
			end,
			onComplete = function()
				completions = completions + 1
				pending = false
			end,
		})
		assert(completions == 1)
		function owner:Respond(_, data, _, options)
			self.reply, self.replyOptions = data, options
			return true
		end
		local request = { requestId = "request", session = publication.session, items = { Proof(publication) } }
		assert(owner:HandleMeshAuthenticationRequest(request, "Receiver-Realm"))
		assert(
			#owner.reply.items == 1 and owner.reply.items[1].digest == publication.digest,
			"completion must not erase still-valid immutable owner evidence"
		)
		local oldCallback = owner.replyOptions.isCurrent
		owner.db.profile.sharePlayerLocation = false
		owner:CancelMeshPublicationsWhere(function(options)
			return options.publishesLocation == true
		end)
		assert(not oldCallback(), "withdrawal cancels already queued owner confirmation")
		assert(owner:HandleMeshAuthenticationRequest(request, "Receiver-Realm"))
		assert(#owner.reply.items == 0 and completions == 1)
		assert(owner:GetMeshPublicationMetrics().retainedBytes == 0)
	end
)

QT:RegisterTest(
	"mesh publication pending bodies and hash work are bounded and private operations cannot relay",
	function()
		local owner, receiver = Peer("Owner-Realm"), Peer("Receiver-Realm")
		for index = 1, 80 do
			local publication =
				Publish(owner, "ANN", { eventType = "QUEST_PROGRESS", text = string.rep("x", 900) .. index })
			receiver:HandleMeshPublication(Wire(publication), "Relay-Realm")
		end
		local metrics = receiver:GetMeshPublicationMetrics()
		assert(metrics.pending <= 32 and metrics.retainedBytes <= 131072 and #receiver.meshPublicationState.jobs <= 16)
		assert((metrics.capacity or 0) > 0 and #receiver.delivered == 0)
		for _, operation in ipairs({ "DLOC", "PONG", "QCRS", "QPGM", "QTHD", "QTN2", "QSHR" }) do
			local context = {
				operation = operation,
				session = "session",
				messageId = "1",
				stamp = owner:GetAnnouncementServerTime(),
			}
			assert(not owner:QueueMeshPublication(context, {}, "global", { expires = owner.now + 30 }), operation)
		end
		receiver:ResetMeshPublications()
		assert(receiver:GetMeshPublicationMetrics().retainedBytes == 0 and receiver:GetCommTransferMetrics().bytes == 0)
	end,
	{ offline = true }
)

QT:RegisterTest(
	"mesh publication signed exceptions bind original metadata and never trust a native relay instead",
	function()
		local owner = Peer("Developer-Realm")
		local record = {
			requestId = "dev-" .. owner:GetAnnouncementServerTime() .. "-1234-5",
			issuedAt = owner:GetAnnouncementServerTime(),
			subscriptionSession = owner:GetCommunicationSession(),
			active = true,
			signature = string.rep("1", 128),
		}
		local publication = Publish(owner, "DEVANN", record)
		for _, forged in ipairs({ false, true }) do
			local receiver = Peer("Receiver-Realm")
			function receiver:QueueDeveloperAnnouncementVerification(data, sender, callback)
				self.verifier = { data = data, sender = sender, callback = callback }
				return true
			end
			local wire = Wire(publication)
			if forged then
				-- A genuine signed body cannot receive a new session/order just because
				-- its immediate sender owns the forged outer envelope.
				wire.session = "forged-session"
				Rehash(wire)
			end
			assert(receiver:HandleMeshPublication(wire, owner.name))
			Finish(receiver)
			assert(#receiver.delivered == 0 and not receiver.auth)
			if not forged then
				assert(receiver.verifier and receiver.verifier.sender == owner.name)
				receiver.verifier.callback(record)
				assert(#receiver.delivered == 1 and #receiver.forwarded == 1)
			else
				assert(not receiver.verifier)
			end
		end
	end
)

QT:RegisterTest("mesh publication envelopes preserve the catalog size limit through fragment assembly", function()
	local sender, receiver = Peer("Sender-Realm"), Peer("Receiver-Realm")
	receiver:InitializeMeshNetwork()
	receiver.meshNetworkState.neighbors[sender.name] = { name = sender.name, expires = receiver.now + 180 }
	local pub = Wire(Publish(sender, "ANN", {
		eventType = "QUEST_PROGRESS",
		text = string.rep("x", 1024),
		eventFacts = string.rep("y", 1024),
		zoneName = string.rep("z", 1024),
		senderGUID = string.rep("g", 800),
	}))
	local encoded = assert(sender:EncodeCommRecord("MPUB", pub))
	assert(#encoded > 4096 and #encoded <= 8192, "exercise an envelope larger than the ordinary event limit")
	local frames = assert(sender:BuildCommFrames("MPUB", pub, {
		session = "outer",
		messageId = "1",
		stamp = sender:GetAnnouncementServerTime(),
	}))
	local received
	function receiver:DispatchCommRecord(frame, record, nativeSender)
		assert(frame.operation == "MPUB" and nativeSender == sender.name)
		received = record
		return true
	end
	for _, wire in ipairs(frames) do
		local frame, body = receiver:DecodeCommFrame(wire)
		assert(
			receiver:ReceiveCommFragment(
				frame,
				body,
				sender.name,
				{ distribution = "WHISPER", targeted = true, meshTraffic = true }
			)
		)
	end
	assert(received and received.body == pub.body and received.digest == pub.digest)
	assert(receiver:GetCommTransferMetrics().incoming == 0)
end, { offline = true })

QT:RegisterTest("mesh publication identity and native confirmations bind both scope and operation", function()
	local owner, receiver = Peer("Owner-Realm"), Peer("Receiver-Realm")
	local context = {
		operation = "QTCHAT",
		session = owner:GetCommunicationSession(),
		messageId = "shared-id",
		stamp = owner:GetAnnouncementServerTime(),
	}
	for _, scope in ipairs({ "global", 12 }) do
		assert(
			owner:QueueMeshPublication(
				context,
				{ text = "Same immutable event, distinct audiences" },
				scope,
				{ expires = owner.now + 60 }
			)
		)
	end
	Finish(owner)
	assert(#owner.forwarded == 2 and owner:GetMeshPublicationMetrics().retained == 2)
	local byScope = {}
	for _, publication in ipairs(owner.forwarded) do
		byScope[publication.scope] = publication
		assert(receiver:HandleMeshPublication(Wire(publication), "Relay-Realm"))
	end
	assert(byScope.global.digest ~= byScope[12].digest)
	local auth = AwaitAuth(receiver)
	assert(#auth.data.items == 2, "one native owner confirmation may batch independently scoped objects")
	function owner:Respond(_, data)
		self.reply = data
		return true
	end
	auth.data.requestId = "scoped-auth"
	assert(owner:HandleMeshAuthenticationRequest(auth.data, receiver.name))
	assert(#owner.reply.items == 2)
	assert(auth.options.onResponse(owner.reply, owner.name))
	assert(#receiver.delivered == 2, "scoped digests cannot conflict or select an arbitrary retained sibling")
	for _, mismatch in ipairs({ { scope = "99", operation = "QTCHAT" }, { scope = "global", operation = "LOC" } }) do
		assert(owner:HandleMeshAuthenticationRequest({
			requestId = "wrong-object",
			session = context.session,
			items = { { id = context.messageId, scope = mismatch.scope, operation = mismatch.operation } },
		}, receiver.name))
		assert(#owner.reply.items == 0, "an ID alone cannot authorize another operation or audience")
	end
end)

QT:RegisterTest("mesh publication moving sources keep exposed proofs while coalescing unsent samples", function()
	local net = QT:CreateTestNetwork({ fps = 20, latency = 0.03, seed = 513 })
	local owner, bridge, viewer =
		net:AddPeer("Owner-Realm", { mapID = 12 }),
		net:AddPeer("Bridge-Realm", { mapID = 99 }),
		net:AddPeer("Viewer-Realm", { mapID = 12 })
	local arrivals, completions, proofs = {}, {}, 0
	for _, peer in ipairs({ owner, bridge, viewer }) do
		-- Isolate the sampled producer under test, while retaining real directory,
		-- interest, hashing, forwarding, authentication and native transfer pumps.
		function peer:UpdateGeographicComms()
			self:UpdateGeographicSubscriptions()
			return false
		end
	end
	net.deliveryRule = function(packet, receiver)
		local frame = owner:DecodeCommFrame(packet.wire)
		if not frame then
			return
		end
		if
			(frame.operation == "MHEL" or frame.operation == "MACK")
			and (
				(packet.sender == owner.name and receiver == viewer)
				or (packet.sender == viewer.name and receiver == owner)
			)
		then
			return { drop = true }
		end
		if frame.operation == "MAPRF" and packet.sender == owner.name and receiver == viewer then
			proofs = proofs + 1
			return { delay = 6 }
		end
	end
	local dispatch = viewer.DispatchVerifiedMeshRecord
	function viewer:DispatchVerifiedMeshRecord(frame, data, sender, context)
		if sender == owner.name and frame.operation == "LOC" then
			arrivals[#arrivals + 1] = { x = data.x, at = self.now }
		end
		return dispatch(self, frame, data, sender, context)
	end
	for _, peer in ipairs({ owner, bridge, viewer }) do
		net:StartPeer(peer)
	end
	net:Advance(45)
	assert(owner.meshNetworkState.neighbors[bridge.name] and viewer.meshNetworkState.neighbors[bridge.name])
	assert(not owner.meshNetworkState.neighbors[viewer.name])
	local generation, began = 0, owner.now
	for index = 1, 12 do
		generation = index
		assert(
			owner:Publish(
				"LOC",
				{ mask = 3, mapID = 12, x = 0.5 + index / 1000, y = 0.4 },
				{ { distribution = "MESH", scope = 12 } },
				{
					owner = "moving-fixture",
					key = "moving-fixture",
					publishesLocation = true,
					expires = owner.now + 30,
					isCurrent = function()
						return generation == index
					end,
					onComplete = function()
						completions[index] = (completions[index] or 0) + 1
					end,
				}
			)
		)
		net:Advance(5)
	end
	assert(
		#arrivals > 0 and arrivals[1].at < began + 60,
		"continuous five-second source replacement must not starve multihop delivery"
	)
	net:Advance(35)
	assert(proofs > 0 and #arrivals >= 2, "moving relays still require direct origin confirmation")
	local observed = viewer:GetPlayerLocationState().peers[owner.name]
	assert(observed and observed.x == 0.512, "latest source ordering must survive delayed older confirmations")
	for index = 1, 12 do
		assert(completions[index] == 1, "every producer completes exactly once")
	end
	assert(owner:GetMeshPublicationMetrics().retainedBytes == 0, "original expiry bounds immutable proof retention")
end, { offline = true })

QT:RegisterTest(
	"mesh shared delivery authenticates each consumer and cannot revive withdrawn data with a delayed proof",
	function()
		local net = QT:CreateTestNetwork({ now = 10000, fps = 20, latency = 0.03, seed = 1921 })
		local owner, hub, first, last =
			net:AddPeer("Owner-Realm"), net:AddPeer("Hub-Realm"), net:AddPeer("First-Realm"), net:AddPeer("Last-Realm")
		local peers = { owner, hub, first, last }
		for _, peer in ipairs(peers) do
			-- Fix only the confirmed topology and producer for this adversarial case.
			-- Actual routing, encoding, hashing, authentication, transfers and native
			-- delivery still run through independent coordinators and their clocks.
			peer.UpdatePlayerCommunications = function() end
			peer.UpdateMeshNetwork = function() end
			net:StartPeer(peer)
			peer:InitializeMeshNetwork()
		end
		local function Neighbor(a, b)
			a.meshNetworkState.neighbors[b.name] = {
				name = b.name,
				session = b:GetCommunicationSession(),
				sharedDelivery = true,
				expires = a.now + 500,
			}
		end
		for _, edge in ipairs({ { owner, hub }, { hub, first }, { hub, last } }) do
			Neighbor(edge[1], edge[2])
			Neighbor(edge[2], edge[1])
		end
		local wall = owner:GetAnnouncementServerTime()
		local function LocalInterest(peer, id, downstream)
			local lease = {
				id = id,
				destination = peer.name,
				zone = 0,
				expiresAt = wall + 120,
				downstreams = { [downstream.name] = true },
				hops = 8,
				renewAt = peer.now + 120,
			}
			peer.meshNetworkState.localInterests[0] = lease
			peer.meshNetworkState.localHistory[peer.name .. ":" .. id] = lease
			return lease
		end
		local h = LocalInterest(hub, "hub-interest", owner)
		local c = LocalInterest(first, "first-interest", hub)
		local d = LocalInterest(last, "last-interest", hub)
		local function ForeignInterest(peer, lease, upstream, downstream)
			peer.meshNetworkState.interests[lease.destination .. ":" .. lease.id] = {
				id = lease.id,
				destination = lease.destination,
				zone = 0,
				expiresAt = lease.expiresAt,
				upstream = upstream.name,
				downstreams = downstream and { [downstream.name] = true } or {},
				alternates = {},
				hops = 7,
			}
		end
		ForeignInterest(owner, h, hub)
		ForeignInterest(owner, c, hub)
		ForeignInterest(owner, d, hub)
		ForeignInterest(hub, c, first, owner)
		ForeignInterest(hub, d, last, owner)
		local received, sharedStates = {}, 0
		for _, peer in ipairs({ hub, first, last }) do
			received[peer.name] = {}
			local dispatch = peer.DispatchVerifiedMeshRecord
			function peer:DispatchVerifiedMeshRecord(frame, data, sender, context)
				if sender == owner.name and frame.operation == "STATE" then
					for _, record in ipairs(data.records) do
						if record.topic == "LOC" then
							received[self.name][#received[self.name] + 1] = record.data.mask
						end
					end
				end
				return dispatch(self, frame, data, sender, context)
			end
		end
		local handle = hub.HandleMeshPublication
		function hub:HandleMeshPublication(data, sender, context)
			if sender == owner.name and data.operation == "STATE" then
				sharedStates = sharedStates + 1
				assert(data.sharedDelivery == true)
			end
			return handle(self, data, sender, context)
		end
		local blockProof, savedProof = true, {}
		net.deliveryRule = function(packet, receiver)
			local frame = owner:DecodeCommFrame(packet.wire)
			if
				frame
				and frame.operation == "MAPRF"
				and packet.sender == owner.name
				and receiver == last
				and blockProof
			then
				savedProof[#savedProof + 1] = packet
				return { drop = true }
			end
		end
		local function PublishLocation(mask, revision)
			local data = { mask = mask }
			if mask == 3 then
				data.mapID, data.x, data.y = 12, 0.4, 0.6
			end
			assert(owner:Publish("STATE", {
				records = {
					{ topic = "LOC", data = data, sampledAt = owner:GetAnnouncementServerTime(), revision = revision },
				},
			}, { { distribution = "MESH", scope = "global" } }, {
				owner = "shared-security",
				key = "shared-security",
				publishesLocation = mask ~= 0,
				expires = owner.now + 110,
			}))
		end
		PublishLocation(3, 1)
		net:Advance(20)
		assert(sharedStates == 1, "three matching consumers must share one authenticated owner-to-hub bundle")
		assert(#received[hub.name] == 1 and #received[first.name] == 1)
		assert(
			#received[last.name] == 0 and #savedProof > 0,
			"the hub's authentication cannot authorize another consumer with a delayed owner proof"
		)
		assert(hub:GetPlayerLocationState().peers[owner.name] and first:GetPlayerLocationState().peers[owner.name])
		assert(not last:GetPlayerLocationState().peers[owner.name])
		for _, packet in ipairs(savedProof) do
			net:Inject(last, packet.prefix, packet.wire, "WHISPER", hub.name)
		end
		net:Advance(2)
		assert(#received[last.name] == 0, "copying a native owner proof through the hub cannot authenticate it")
		blockProof = false
		owner.db.profile.sharePlayerLocation = false
		owner:CancelMeshPublicationsWhere(function(descriptor)
			return descriptor.publishesLocation
		end)
		PublishLocation(0, 2)
		net:Advance(20)
		assert(
			#received[last.name] == 1 and received[last.name][1] == 0,
			"the recipient must accept the authenticated withdrawal while the old location is still quarantined"
		)
		for _, packet in ipairs(savedProof) do
			net:Inject(last, packet.prefix, packet.wire, "WHISPER", owner.name)
		end
		net:Advance(3)
		assert(
			#received[last.name] == 1 and not last:GetFreshPlayerLocation(owner.name, "map"),
			"even the real owner's delayed original proof must not revive withdrawn location data"
		)
	end,
	{ offline = true }
)

QT:RegisterTest("mesh publication one emission reaches global and zone audiences with scoped native proofs", function()
	local net = QT:CreateTestNetwork({ fps = 20, latency = 0.03, seed = 515 })
	local owner, bridge, viewer =
		net:AddPeer("Owner-Realm", { mapID = 12 }),
		net:AddPeer("Bridge-Realm", { mapID = 99 }),
		net:AddPeer("Viewer-Realm", { mapID = 12 })
	local scopes, completions = {}, 0
	net.deliveryRule = function(packet, receiver)
		local frame = owner:DecodeCommFrame(packet.wire)
		if
			frame
			and (frame.operation == "MHEL" or frame.operation == "MACK")
			and (
				(packet.sender == owner.name and receiver == viewer)
				or (packet.sender == viewer.name and receiver == owner)
			)
		then
			return { drop = true }
		end
	end
	for _, peer in ipairs({ owner, bridge, viewer }) do
		function peer:UpdateGeographicComms()
			self:UpdateGeographicSubscriptions()
			return false
		end
		local dispatch = peer.DispatchVerifiedMeshRecord
		function peer:DispatchVerifiedMeshRecord(frame, data, sender, context)
			if sender == owner.name and frame.operation == "QTCHAT" and data.text == "Both audiences" then
				scopes[self.name] = scopes[self.name] or {}
				scopes[self.name][context.scope] = true
			end
			return dispatch(self, frame, data, sender, context)
		end
		net:StartPeer(peer)
	end
	net:Advance(45)
	assert(not owner.meshNetworkState.neighbors[viewer.name])
	local ready
	for _ = 1, 90 do
		local viewerGlobal, viewerZone, bridgeGlobal = false, false, false
		for _, lease in pairs(owner.meshNetworkState.interests) do
			if lease.expiresAt > owner:GetAnnouncementServerTime() then
				viewerZone = viewerZone or lease.destination == viewer.name and lease.zone == 12
				bridgeGlobal = bridgeGlobal or lease.destination == bridge.name and lease.zone == 0
			end
		end
		for _, lease in pairs(bridge.meshNetworkState.interests) do
			viewerGlobal = viewerGlobal
				or lease.expiresAt > bridge:GetAnnouncementServerTime()
					and lease.destination == viewer.name
					and lease.zone == 0
		end
		ready = viewerGlobal and viewerZone and bridgeGlobal
		if ready then
			break
		end
		net:Advance(1)
	end
	assert(ready, "both scopes need live reverse paths; common global demand may terminate at the bridge")
	assert(
		owner:Emit(
			"QTCHAT",
			{ text = "Both audiences" },
			{ { distribution = "MESH", scope = "global" }, { distribution = "MESH", scope = 12 } },
			{
				expires = owner.now + 90,
				onComplete = function(ok)
					assert(ok)
					completions = completions + 1
				end,
			}
		)
	)
	net:Advance(85)
	assert(
		scopes[viewer.name] and scopes[viewer.name].global and scopes[viewer.name][12],
		"the same emitted identity must independently authenticate both logical audiences"
	)
	assert(
		scopes[bridge.name] and scopes[bridge.name].global and not scopes[bridge.name][12],
		"a relay must not consume an unrelated zone's public publication"
	)
	assert(completions == 1 and (owner:GetMeshPublicationMetrics().conflicts or 0) == 0)
end, { offline = true })

QT:RegisterTest("mesh publication exposed outbox survives replacement but not revoked consent", function()
	local owner = Peer("Owner-Realm")
	local generation, allowed, completions, hops = 0, true, {}, {}
	function owner:ForwardMeshPublication(publication, options)
		self.forwarded[#self.forwarded + 1] = publication
		return self:SendMeshPublicationToPeer(
			publication,
			"Relay-Realm",
			{ leaseId = "lease", destination = "Viewer-Realm", zone = 12, hops = 8 },
			options
		)
	end
	function owner:Emit(operation, _, _, options)
		assert(operation == "MPUB")
		hops[#hops + 1] = options
		options.onStarted()
		return true, "queued"
	end
	local first
	for index = 1, 3 do
		generation = index
		local context = {
			operation = "LOC",
			session = owner:GetCommunicationSession(),
			messageId = tostring(index),
			stamp = owner:GetAnnouncementServerTime(),
		}
		assert(owner:QueueMeshPublication(context, { mask = 3, mapID = 12, x = index / 10, y = 0.4 }, 12, {
			key = "location",
			expires = owner.now + 30,
			publishesLocation = true,
			isCurrent = function()
				return generation == index
			end,
			publicationCurrent = function()
				return allowed
			end,
			onComplete = function()
				completions[index] = (completions[index] or 0) + 1
			end,
		}))
		Finish(owner)
		first = first or owner.forwarded[1]
	end
	assert(#hops == 1 and hops[1].isCurrent(), "an exposed hop finishes while only the newest pending sample survives")
	assert(completions[1] == nil and completions[2] == 1 and completions[3] == nil)
	function owner:Respond(_, data, _, options)
		self.reply, self.proofOptions = data, options
		return true
	end
	assert(
		owner:HandleMeshAuthenticationRequest(
			{ requestId = "late-auth", session = first.session, items = { Proof(first) } },
			"Viewer-Realm"
		)
	)
	assert(
		#owner.reply.items == 1 and owner.reply.items[1].digest == first.digest,
		"a replacement cannot erase an already exposed immutable owner's proof"
	)
	local oldProof = owner.proofOptions
	hops[1].onComplete(true, "acknowledged")
	owner:UpdateMeshPublications(owner.now)
	assert(#hops == 2 and owner.forwarded[2].id == "3" and completions[1] == 1)
	allowed, owner.db.profile.sharePlayerLocation = false, false
	owner:UpdateMeshPublications(owner.now)
	assert(not oldProof.isCurrent() and not hops[2].isCurrent(), "revocation must fence pending proofs and fragments")
	hops[2].onComplete(true, "late-acknowledgement")
	assert(
		owner:HandleMeshAuthenticationRequest(
			{ requestId = "after-withdrawal", session = first.session, items = { Proof(first) } },
			"Viewer-Realm"
		)
	)
	assert(#owner.reply.items == 0 and owner:GetMeshPublicationMetrics().retainedBytes == 0)
	for index = 1, 3 do
		assert(completions[index] == 1, "late callbacks cannot complete a producer twice")
	end
end)

QT:RegisterTest("mesh publication native owners recover IDs occupied by unauthenticated relay claims", function()
	for _, stage in ipairs({ "hashing", "authentication" }) do
		local owner, receiver = Peer("Owner-Realm"), Peer("Receiver-Realm")
		local original = Publish(owner, "QTCHAT", { text = "Genuine public message" })
		local forged = Wire(original)
		forged.body = assert(receiver:EncodeCommRecord("QTCHAT", { text = "Forged relay claim" }))
		Rehash(forged)
		assert(receiver:HandleMeshPublication(forged, "Relay-Realm"))
		local poisoned = receiver.meshPublicationState.jobs[1]
		local oldAuth = stage == "authentication" and AwaitAuth(receiver) or nil
		assert(#receiver.delivered == 0)
		assert(receiver:HandleMeshPublication(Wire(original), owner.name))
		assert(poisoned.cancelled and poisoned.publication == nil and poisoned.hash == nil)
		assert(receiver:GetMeshPublicationMetrics().pending == 1)
		if oldAuth then
			assert(not oldAuth.options.isCurrent())
			assert(
				not oldAuth.options.onResponse({ session = original.session, items = { Proof(forged) } }, owner.name)
			)
			oldAuth.options.onExpire()
		end
		Finish(receiver)
		assert(#receiver.delivered == 1 and receiver.delivered[1].data.text == "Genuine public message")
		assert(receiver:GetMeshPublicationMetrics().unverifiedConflict == 1)
		assert(
			not receiver:HandleMeshPublication(forged, owner.name),
			"verified immutable identity cannot be rewritten"
		)
		assert(#receiver.delivered == 1 and receiver:GetMeshPublicationMetrics().pending == 0)
	end
end)

QT:RegisterTest("mesh publication expiry releases authentication batches and suspended payload references", function()
	local owner, receiver = Peer("Owner-Realm"), Peer("Receiver-Realm")
	local first = Publish(
		owner,
		"ANN",
		{ eventType = "QUEST_PROGRESS", text = string.rep("a", 1000) },
		{ expires = owner.now + 5 }
	)
	local second = Publish(
		owner,
		"ANN",
		{ eventType = "QUEST_PROGRESS", text = string.rep("b", 1000) },
		{ expires = owner.now + 30 }
	)
	assert(receiver:HandleMeshPublication(Wire(first), "Relay-Realm"))
	assert(receiver:HandleMeshPublication(Wire(second), "Relay-Realm"))
	local auth = AwaitAuth(receiver)
	local request
	for value in pairs(receiver.meshPublicationState.requests) do
		request = value
	end
	assert(request and #request.entries == 2)
	local expired
	for _, entry in ipairs(request.entries) do
		if entry.publication.id == first.id then
			expired = entry
		end
	end
	receiver.now = receiver.now + 6
	receiver:UpdateMeshPublications(receiver.now)
	assert(expired.cancelled and expired.publication == nil and expired.data == nil and expired.hash == nil)
	assert(#request.entries == 1 and request.entries[1].publication.id == second.id)
	assert(auth.options.isCurrent(), "one expired object must not cancel the remaining batch")
	assert(receiver:GetMeshPublicationMetrics().retainedBytes == #second.body + 512)
	assert(auth.options.onResponse({ session = second.session, items = { Proof(first), Proof(second) } }, owner.name))
	assert(#receiver.delivered == 1 and receiver.delivered[1].data.text == string.rep("b", 1000))
	assert(#request.entries == 0 and not next(receiver.meshPublicationState.requests))

	local abandoned = Peer("Receiver-Realm")
	assert(abandoned:HandleMeshPublication(Wire(first), "Relay-Realm"))
	local abandonedAuth = AwaitAuth(abandoned)
	local abandonedRequest
	for value in pairs(abandoned.meshPublicationState.requests) do
		abandonedRequest = value
	end
	abandoned.now = abandoned.now + 6
	abandoned:UpdateMeshPublications(abandoned.now)
	assert(#abandonedRequest.entries == 0 and not next(abandoned.meshPublicationState.requests))
	assert(abandoned:GetMeshPublicationMetrics().retainedBytes == 0 and abandoned:GetCommTransferMetrics().bytes == 0)
	assert(not abandonedAuth.options.isCurrent())
	assert(not abandonedAuth.options.onResponse({ session = first.session, items = { Proof(first) } }, owner.name))
	abandonedAuth.options.onExpire()
	assert(#abandoned.delivered == 0 and abandoned:GetMeshPublicationMetrics().retainedBytes == 0)

	local hashing = Peer("Receiver-Realm")
	assert(hashing:HandleMeshPublication(Wire(first), "Relay-Realm"))
	local job = hashing.meshPublicationState.jobs[1]
	hashing:ResetMeshPublications()
	assert(job.cancelled and job.hash == nil and job.publication == nil)
	assert(hashing:GetMeshPublicationMetrics().retainedBytes == 0 and hashing:GetCommTransferMetrics().bytes == 0)
end)

QT:RegisterTest("mesh authentication tolerates delayed owner proofs without extending publication expiry", function()
	local owner, receiver = Peer("Owner-Realm"), Peer("Receiver-Realm")
	local current = Publish(owner, "QTCHAT", { text = "Still current" }, { expires = owner.now + 90 })
	local expired = Publish(owner, "QTCHAT", { text = "Expired while waiting" }, { expires = owner.now + 35 })
	assert(receiver:HandleMeshPublication(Wire(current), "Relay-Realm"))
	assert(receiver:HandleMeshPublication(Wire(expired), "Relay-Realm"))
	local request = AwaitAuth(receiver)
	owner.now, receiver.now = 41, 41
	owner.serverOffset, receiver.serverOffset = 41, 41
	assert(
		receiver.now > 30 and receiver.now < request.options.expires and request.options.isCurrent(),
		"a congested two-way proof exchange should remain eligible beyond thirty seconds"
	)
	function owner:Respond(_, data)
		self.reply = data
		return true
	end
	request.data.requestId = "delayed-proof"
	assert(owner:HandleMeshAuthenticationRequest(request.data, receiver.name))
	assert(
		#owner.reply.items == 1 and owner.reply.items[1].id == current.id,
		"an owner must stop confirming the original bundle when its lifetime ends"
	)
	owner.reply.items[#owner.reply.items + 1] = Proof(expired)
	assert(request.options.onResponse(owner.reply, owner.name))
	assert(
		#receiver.delivered == 1 and receiver.delivered[1].data.text == "Still current",
		"even an already queued valid proof cannot extend its publication's original expiry"
	)
end)

QT:RegisterTest("mesh publication cancelled public requests retire exposed hops and cannot replay", function()
	local owner = Peer("Developer-Realm")
	owner.Request = QT.Request
	local forwarding
	function owner:ForwardMeshPublication(publication, options)
		forwarding = options
		return self:SendMeshPublicationToPeer(publication, "Relay-Realm", {
			leaseId = "lease",
			destination = "Receiver-Realm",
			zone = 0,
			hops = 8,
		}, options)
	end
	local id = "dev-" .. owner:GetAnnouncementServerTime() .. "-1234-5"
	local completions = 0
	assert(owner:Request("PING", {
		requestId = id,
		issuedAt = owner:GetAnnouncementServerTime(),
		developerRequest = true,
		debugRequest = false,
		signature = string.rep("1", 128),
	}, { { distribution = "MESH", scope = "global" } }, {
		acceptLatePongs = true,
		onComplete = function()
			completions = completions + 1
		end,
	}))
	Finish(owner)
	local _, entry = next(owner.meshPublicationState.entries)
	assert(entry and forwarding and owner.communicationState.requests[id])
	for _ = 1, 50 do
		owner.now = owner.now + 0.1
		owner:UpdateCommTransfers()
		owner:DrainTransport()
		if entry.exposed then
			break
		end
	end
	assert(entry.exposed, "the original request must have crossed native acceptance before cancellation")
	local oldCurrent, oldComplete = forwarding.isCurrent, forwarding.onComplete
	owner:CancelCommRequest(id, "superseded")
	assert(not owner.communicationState.requests[id])
	assert(entry.cancelled and entry.publication == nil and not oldCurrent())
	assert(owner:GetMeshPublicationMetrics().retainedBytes == 0)
	assert(owner:GetCommTransferMetrics().outgoing == 0)
	for _, queued in ipairs(owner.transportState.queue) do
		assert(queued.context ~= "MPUB", "only a small retirement notice may remain after cancellation")
	end
	oldComplete(true, "accepted")
	assert(completions == 1 and owner:GetMeshPublicationMetrics().retained == 0)
end)

QT:RegisterTest("mesh publication producer callbacks cannot revive cancelled or replaced state", function()
	for _, predicate in ipairs({ "publicationCurrent", "isCurrent" }) do
		for _, boundary in ipairs({ "cancel", "session", "replacement" }) do
			local owner, completions = Peer("Owner-Realm"), 0
			local context = {
				operation = "QTCHAT",
				session = owner:GetCommunicationSession(),
				messageId = "1",
				stamp = owner:GetAnnouncementServerTime(),
			}
			local options = {
				expires = owner.now + 30,
				onComplete = function()
					completions = completions + 1
				end,
			}
			local called = false
			options[predicate] = function()
				assert(not called, "retired producer predicate must not run again")
				called = true
				if boundary == "session" then
					owner:EndCommunicationSession()
				else
					owner:CancelMeshPublicationsWhere(function()
						return true
					end)
					if boundary == "replacement" then
						assert(
							owner:QueueMeshPublication(
								context,
								{ text = "Replacement" },
								"global",
								{ expires = owner.now + 30 }
							)
						)
					end
				end
				return true
			end
			assert(owner:QueueMeshPublication(context, { text = "Retired" }, "global", options))
			owner:UpdateMeshPublications(owner.now)
			Finish(owner)
			assert(called and completions == 1)
			if boundary == "replacement" then
				assert(#owner.forwarded == 1)
				assert(owner:DecodeCommRecord("QTCHAT", owner.forwarded[1].body).text == "Replacement")
			else
				assert(#owner.forwarded == 0 and owner:GetMeshPublicationMetrics().retainedBytes == 0)
			end
		end
	end

	for _, boundary in ipairs({ "reset", "session" }) do
		local owner, first, second = Peer("Owner-Realm"), 0, 0
		local audience = { { distribution = "MESH", scope = "global" } }
		assert(owner:Emit("QTCHAT", { text = "Unstarted" }, audience, {
			key = "replacement",
			onComplete = function()
				first = first + 1
				if boundary == "reset" then
					owner:ResetMeshPublications()
				else
					owner:EndCommunicationSession()
				end
			end,
		}))
		local accepted = owner:Emit("QTCHAT", { text = "Must not enter retired state" }, audience, {
			key = "replacement",
			onComplete = function()
				second = second + 1
			end,
		})
		assert(not accepted and first == 1 and second == 1)
		assert(owner:GetMeshPublicationMetrics().retainedBytes == 0 and owner:GetCommTransferMetrics().bytes == 0)
		assert(owner.meshPublicationState == nil and #owner.forwarded == 0)
	end
end)

QT:RegisterTest("mesh publication late interests wait for pending renewals without replaying expired data", function()
	for _, boundary in ipairs({ "complete", "expire", "cancel" }) do
		local owner, completion = Peer("Owner-Realm"), nil
		function owner:ForwardMeshPublication(publication, options)
			self.forwarded[#self.forwarded + 1] = publication
			completion = options.onComplete or completion
			return true, "queued"
		end
		Publish(owner, "QTCHAT", { text = "In-flight public update" })
		local lease = { zone = 0, expiresAt = owner:GetAnnouncementServerTime() + 120 }
		owner:ReplayMeshPublicationsForInterest(lease)
		owner.now = owner.now + 2
		owner:UpdateMeshPublications(owner.now)
		assert(owner.meshPublicationState.replay[lease], "an unfinished fanout must not discard a new interest")
		if boundary == "expire" then
			owner.now = owner.now + 31
		elseif boundary == "cancel" then
			owner:CancelMeshPublicationsWhere(function()
				return true
			end)
		end
		completion(true, "accepted")
		owner.now = owner.now + 2
		owner:UpdateMeshPublications(owner.now)
		assert(#owner.forwarded == (boundary == "complete" and 2 or 1))
	end
end)

QT:RegisterTest("mesh cached public state serves new interests without lending its authentication", function()
	local owner, bridge = Peer("Owner-Realm"), Peer("Bridge-Realm")
	local publication = Publish(owner, "STATE", {
		records = {
			{
				topic = "QTVR",
				data = { version = "9.0.3" },
				sampledAt = owner:GetAnnouncementServerTime(),
				revision = 1,
			},
		},
	})
	assert(bridge:HandleMeshPublication(Wire(publication), owner.name))
	Finish(bridge)
	local forwarded, options = 0, nil
	function bridge:ForwardMeshPublication(copy, descriptor)
		assert(copy.digest == publication.digest and copy.body == publication.body)
		assert(copy.origin == owner.name and copy.expiresAt == publication.expiresAt)
		forwarded, options = forwarded + 1, descriptor
		return true, "queued"
	end
	local lease = {
		id = "new-interest",
		destination = "Newcomer-Realm",
		zone = 0,
		expiresAt = bridge:GetAnnouncementServerTime() + 120,
	}
	bridge:ReplayMeshPublicationsForInterest(lease)
	bridge.now = bridge.now + 2
	bridge:UpdateMeshPublications(bridge.now)
	assert(forwarded == 1 and options.meshInterest == lease and options.meshReplayHops == 7)
	assert(options.isCurrent())
	local receiver = Peer("Receiver-Realm")
	assert(receiver:HandleMeshPublication(Wire(publication), bridge.name))
	local request = AwaitAuth(receiver)
	assert(#receiver.delivered == 0, "a relay's cached verification is not recipient authentication")
	local proof = { session = publication.session, items = { Proof(publication) } }
	assert(not request.options.onResponse(proof, bridge.name))
	assert(request.options.onResponse(proof, owner.name))
	assert(#receiver.delivered == 1)
	bridge.now = bridge.now + 31
	assert(not options.isCurrent(), "cached redistribution cannot renew source expiry")
end)

QT:RegisterTest("mesh cached replay retries failed transfers and ignores retired lease callbacks", function()
	local owner, bridge = Peer("Owner-Realm"), Peer("Bridge-Realm")
	local publication = Publish(owner, "STATE", {
		records = {
			{
				topic = "QTVR",
				data = { version = "9.0.3" },
				sampledAt = owner:GetAnnouncementServerTime(),
				revision = 1,
			},
		},
	}, { owner = owner, expires = owner.now + 120 })
	assert(bridge:HandleMeshPublication(Wire(publication), owner.name))
	Finish(bridge)
	local calls = {}
	function bridge:ForwardMeshPublication(_, descriptor)
		calls[#calls + 1] = descriptor
		return true, "queued"
	end
	local lease = {
		id = "first",
		destination = "Newcomer-Realm",
		zone = 0,
		expiresAt = bridge:GetAnnouncementServerTime() + 120,
	}
	bridge:ReplayMeshPublicationsForInterest(lease)
	bridge.now = bridge.now + 2
	bridge:UpdateMeshPublications(bridge.now)
	assert(#calls == 1)
	bridge.now = bridge.now + 2
	bridge:UpdateMeshPublications(bridge.now)
	assert(#calls == 1, "an admitted replay waits for its real completion")
	calls[1].onComplete(false, "expired")
	bridge.now = bridge.now + 3
	bridge:UpdateMeshPublications(bridge.now)
	assert(#calls == 2, "a failed queued transfer must be offered again")
	local renewal = { id = "second", destination = lease.destination, zone = 0, expiresAt = lease.expiresAt + 1 }
	bridge:ReplayMeshPublicationsForInterest(renewal)
	calls[2].onComplete(true, "accepted")
	bridge.now = bridge.now + 2
	bridge:UpdateMeshPublications(bridge.now)
	assert(
		#calls == 3 and calls[3].meshInterest == renewal,
		"retired lease completion cannot consume a new path's replay"
	)
	calls[3].onComplete(true, "accepted")
	calls[3].onComplete(false, "expired")
	bridge.now = bridge.now + 3
	bridge:UpdateMeshPublications(bridge.now)
	assert(#calls == 3, "successful replay completion is final")
end)

QT:RegisterTest("mesh replay skips confirmed shared-link copies without wasting its useful send slot", function()
	local owner, bridge = Peer("Owner-Realm"), Peer("Bridge-Realm")
	local publications = {}
	for index = 1, 2 do
		local publisher = index == 1 and owner or Peer("Another-Realm")
		publications[index] = Publish(publisher, "STATE", {
			records = {
				{
					topic = "QTVR",
					data = { version = "9.0.3" },
					sampledAt = publisher:GetAnnouncementServerTime(),
					revision = 1,
				},
			},
		})
		assert(bridge:HandleMeshPublication(Wire(publications[index]), publisher.name))
		Finish(bridge)
	end
	function bridge:HasDeliveredMeshPublicationForInterest(publication)
		return publication.origin == owner.name
	end
	local copies = {}
	function bridge:ForwardMeshPublication(publication, descriptor)
		copies[#copies + 1] = publication
		descriptor.onComplete(true, "accepted")
		return true, "queued"
	end
	local lease = {
		id = "shared",
		destination = "Newcomer-Realm",
		zone = 0,
		expiresAt = bridge:GetAnnouncementServerTime() + 120,
	}
	bridge:ReplayMeshPublicationsForInterest(lease)
	bridge.now = bridge.now + 2
	bridge:UpdateMeshPublications(bridge.now)
	assert(#copies == 1 and copies[1].origin == "Another-Realm")
	assert(bridge:GetMeshPublicationMetrics().replayDeliveryReused == 1)
end)

QT:RegisterTest("mesh cached replay excludes unverified events exhausted hops and superseded state", function()
	for _, scenario in ipairs({ "unverified", "event", "hops", "withdrawal", "replacement", "expired" }) do
		local owner, bridge = Peer("Owner-Realm"), Peer("Bridge-Realm")
		local operation = scenario == "event" and "QTCHAT" or "STATE"
		local data = operation == "QTCHAT" and { text = "Do not replay foreign events" }
			or {
				records = {
					{
						topic = "QTPR",
						data = { active = true },
						sampledAt = owner:GetAnnouncementServerTime(),
						revision = 1,
					},
				},
			}
		local original = Publish(owner, operation, data)
		local wire = Wire(original)
		if scenario == "hops" then
			wire.hops = 1
		end
		assert(bridge:HandleMeshPublication(wire, scenario == "unverified" and "OtherRelay-Realm" or owner.name))
		Finish(bridge)
		if scenario == "withdrawal" or scenario == "replacement" then
			owner.now, bridge.now = owner.now + 2, bridge.now + 2
			local newer = Publish(owner, "STATE", {
				records = {
					{
						topic = "QTPR",
						data = { active = scenario ~= "withdrawal" },
						sampledAt = owner:GetAnnouncementServerTime(),
						revision = 2,
					},
				},
			})
			assert(bridge:HandleMeshPublication(Wire(newer), owner.name))
			Finish(bridge)
		end
		local seen = {}
		function bridge:ForwardMeshPublication(publication)
			seen[#seen + 1] = publication
			assert(publication.id ~= original.id, scenario .. " revived superseded or ineligible state")
			return true, "queued"
		end
		bridge:ReplayMeshPublicationsForInterest({
			id = "later",
			destination = "Newcomer-Realm",
			zone = 0,
			expiresAt = bridge:GetAnnouncementServerTime() + 120,
		})
		bridge.now = bridge.now + (scenario == "expired" and 31 or 2)
		bridge:UpdateMeshPublications(bridge.now)
		assert(#seen == ((scenario == "withdrawal" or scenario == "replacement") and 1 or 0), scenario)
	end
end)

QT:RegisterTest("mesh replay withdrawal fences outlive clears and cancel queued cached locations", function()
	local owner, bridge, late = Peer("Owner-Realm"), Peer("Bridge-Realm"), Peer("Late-Realm")
	local old = Publish(owner, "STATE", {
		records = {
			{
				topic = "LOC",
				data = { mask = 3, mapID = 12, x = 0.4, y = 0.6 },
				sampledAt = owner:GetAnnouncementServerTime(),
				revision = 1,
			},
		},
	}, { owner = owner, expires = owner.now + 120 })
	assert(bridge:HandleMeshPublication(Wire(old), owner.name))
	Finish(bridge)
	local queued
	function bridge:ForwardMeshPublication(_, options)
		if options.meshInterest then
			queued = options
		end
		return true, "queued"
	end
	bridge:ReplayMeshPublicationsForInterest({
		id = "before-clear",
		destination = "Viewer-Realm",
		zone = 0,
		expiresAt = bridge:GetAnnouncementServerTime() + 120,
	})
	owner.now, bridge.now, late.now = owner.now + 1, bridge.now + 1, late.now + 1
	bridge:UpdateMeshPublications(bridge.now)
	assert(queued and queued.isCurrent())
	local clear = Publish(owner, "STATE", {
		records = {
			{ topic = "LOC", data = { mask = 0 }, sampledAt = owner:GetAnnouncementServerTime(), revision = 2 },
		},
	}, { owner = owner, expires = owner.now + 5 })
	for _, receiver in ipairs({ bridge, late }) do
		assert(receiver:HandleMeshPublication(Wire(clear), owner.name))
		Finish(receiver)
	end
	assert(not queued.isCurrent(), "withdrawal must invalidate an already queued cached redistribution")
	for _, receiver in ipairs({ bridge, late }) do
		receiver.now = receiver.now + 6
		receiver:UpdateMeshPublications(receiver.now)
		assert(receiver:GetMeshPublicationMetrics().replayFences == 1)
	end
	-- The native API had already accepted these old bytes before withdrawal;
	-- late direct delivery needs no new proof request to the owner's outbox.
	local forwardedBefore, deliveredBefore = #late.forwarded, #late.delivered
	assert(late:HandleMeshPublication(Wire(old), owner.name))
	Finish(late)
	assert(#late.forwarded == forwardedBefore, "retired data must not escape through immediate forwarding either")
	assert(#late.delivered == deliveredBefore, "a newly matching local interest cannot consume retired state")
	local replays = 0
	function late:ForwardMeshPublication(_, options)
		if options.meshInterest then
			replays = replays + 1
		end
		return true, "queued"
	end
	late:ReplayMeshPublicationsForInterest({
		id = "after-clear",
		destination = "Newcomer-Realm",
		zone = 0,
		expiresAt = late:GetAnnouncementServerTime() + 120,
	})
	late.now = late.now + 1
	late:UpdateMeshPublications(late.now)
	assert(
		replays == 0 and (late:GetMeshPublicationMetrics().replayFenceDrops or 0) > 0,
		"an expired clear must not let delayed native owner data repopulate another client's map"
	)
	late.now = late.now + 331
	late:UpdateMeshPublications(late.now)
	assert(late:GetMeshPublicationMetrics().replayFences == 0 and late:GetMeshPublicationMetrics().retainedBytes == 0)
end)

QT:RegisterTest("mesh replay epochs reject ties retired sessions and unverified controls", function()
	local owner, bridge = Peer("Owner-Realm"), Peer("Bridge-Realm")
	local function Data(active)
		return {
			records = {
				{
					topic = "QTPR",
					data = { active = active },
					sampledAt = owner:GetAnnouncementServerTime(),
					revision = owner:NextCommunicationSequence(),
				},
			},
		}
	end
	local old = Publish(owner, "STATE", Data(true), { owner = owner, expires = owner.now + 120 })
	assert(bridge:HandleMeshPublication(Wire(old), owner.name))
	Finish(bridge)
	local oldSession = owner.communicationState.session
	owner.communicationState.session = "new-session"
	local tied = Publish(owner, "STATE", Data(false), { owner = owner, expires = owner.now + 5 })
	local unverified = Peer("Unverified-Realm")
	assert(unverified:HandleMeshPublication(Wire(tied), "Relay-Realm"))
	Finish(unverified)
	assert(
		unverified:GetMeshPublicationMetrics().replayFences == 0,
		"a claimed clear cannot create privacy or epoch authority before origin verification"
	)
	assert(bridge:HandleMeshPublication(Wire(tied), owner.name))
	Finish(bridge)
	local fence = bridge.meshPublicationState.replayFences[owner.name]
	assert(
		fence.session == oldSession and fence.ambiguousStamp == tied.stamp,
		"a same-second session change cannot win ordering, and a tied clear must suspend old replay"
	)
	owner.now, bridge.now = owner.now + 1, bridge.now + 1
	owner.serverOffset, bridge.serverOffset = 1, 1
	local newest = Publish(owner, "STATE", Data(true), { owner = owner, expires = owner.now + 5 })
	assert(bridge:HandleMeshPublication(Wire(newest), owner.name))
	Finish(bridge)
	assert(fence.session == "new-session" and fence.retired[oldSession])
	bridge.now, owner.now = bridge.now + 6, owner.now + 6
	owner.serverOffset, bridge.serverOffset = 7, 7
	bridge:UpdateMeshPublications(bridge.now)
	owner.communicationState.session = oldSession
	local retired = Publish(owner, "STATE", Data(true), { owner = owner, expires = owner.now + 120 })
	assert(bridge:HandleMeshPublication(Wire(retired), owner.name))
	Finish(bridge)
	assert(fence.session == "new-session", "even a later stamp cannot revive a retired epoch")
	local replays = 0
	function bridge:ForwardMeshPublication(_, options)
		if options.meshInterest then
			replays = replays + 1
		end
		return true, "queued"
	end
	bridge:ReplayMeshPublicationsForInterest({
		id = "new-listener",
		destination = "Newcomer-Realm",
		zone = 0,
		expiresAt = bridge:GetAnnouncementServerTime() + 120,
	})
	bridge.now = bridge.now + 1
	bridge:UpdateMeshPublications(bridge.now)
	assert(replays == 0)
	bridge:ResetMeshPublications()
	assert(
		bridge:GetMeshPublicationMetrics().replayFences == 0 and bridge:GetCommTransferMetrics().bytes == 0,
		"reset must release payload and fence reservations without reviving old ordering state"
	)
end)

QT:RegisterTest(
	"mesh replay fence capacity preserves live retirements and fails closed within reserved memory",
	function()
		local owner, bridge = Peer("Owner-Realm"), Peer("Bridge-Realm")
		local first
		for index = 1, 128 do
			owner.name = "Origin" .. index .. "-Realm"
			local publication = Publish(owner, "STATE", {
				records = {
					{
						topic = "QTVR",
						data = { version = "9.0.3" },
						sampledAt = owner:GetAnnouncementServerTime(),
						revision = 1,
					},
				},
			}, { owner = owner, expires = owner.now + 120 })
			assert(bridge:HandleMeshPublication(Wire(publication), owner.name))
			Finish(bridge)
			first = first or bridge.meshPublicationState.replayFences[owner.name]
			owner:ResetMeshPublications()
			assert(bridge:GetMeshPublicationMetrics().retainedBytes <= 131072)
		end
		assert(bridge:GetMeshPublicationMetrics().replayFences == 128)
		for index = 2, 128 do
			bridge:RetireMeshPublicationPeer("Origin" .. index .. "-Realm")
		end
		local queued
		function bridge:ForwardMeshPublication(_, options)
			if options.meshInterest then
				queued = options
			end
			return true, "queued"
		end
		bridge:ReplayMeshPublicationsForInterest({
			id = "before-overflow",
			destination = "Newcomer-Realm",
			zone = 0,
			expiresAt = bridge:GetAnnouncementServerTime() + 120,
		})
		bridge.now = bridge.now + 1
		bridge:UpdateMeshPublications(bridge.now)
		assert(queued and queued.isCurrent())
		owner.name, owner.now = "Untracked-Realm", bridge.now
		local clear = Publish(owner, "STATE", {
			records = {
				{ topic = "LOC", data = { mask = 0 }, sampledAt = owner:GetAnnouncementServerTime(), revision = 1 },
				{
					topic = "QTPR",
					data = { active = false },
					sampledAt = owner:GetAnnouncementServerTime(),
					revision = 2,
				},
				{
					topic = "QTVR",
					data = { version = "9.0.3" },
					sampledAt = owner:GetAnnouncementServerTime(),
					revision = 3,
				},
			},
		})
		assert(bridge:HandleMeshPublication(Wire(clear), owner.name))
		Finish(bridge)
		local receivedClear = bridge.delivered[#bridge.delivered].data.records
		assert(
			#receivedClear == 2
				and receivedClear[1].topic == "LOC"
				and receivedClear[1].data.mask == 0
				and receivedClear[2].topic == "QTPR"
				and receivedClear[2].data.active == false,
			"fence capacity must still deliver verified withdrawals while suppressing positive fields in the same bundle"
		)
		assert(
			receivedClear[1].sampledAt == owner:GetAnnouncementServerTime()
				and receivedClear[1].revision == 1
				and receivedClear[2].sampledAt == owner:GetAnnouncementServerTime()
				and receivedClear[2].revision == 2,
			"withdrawal projection must retain the owner's original field time and ordering"
		)
		local metrics = bridge:GetMeshPublicationMetrics()
		assert(metrics.replayFences == 128 and metrics.replayFenceBytes == 65536)
		assert(
			bridge.meshPublicationState.replayFences["Origin1-Realm"] == first,
			"capacity pressure must not evict a live privacy or epoch retirement fence"
		)
		assert(
			metrics.cachedReplayBlocked == 0 and metrics.replayDeniedBuckets == 1 and metrics.replayDenyBytes == 4096
		)
		assert(queued.isCurrent(), "an overflow origin must not suspend unrelated established subscribers")
		assert(metrics.replayFenceCapacity == 1 and metrics.retainedBytes <= 131072)
		-- A freed record slot must not erase the untracked clear. A colliding
		-- origin is conservatively suppressed by the same bounded timestamp.
		first.untilAt = bridge.now
		bridge:UpdateMeshPublications(bridge.now)
		local late = Publish(owner, "STATE", {
			records = {
				{
					topic = "LOC",
					data = { mask = 3, mapID = 12, x = 0.4, y = 0.6 },
					sampledAt = owner:GetAnnouncementServerTime(),
					revision = 2,
				},
			},
		}, { owner = owner, expires = owner.now + 120 })
		local deliveredBeforeLate = #bridge.delivered
		assert(bridge:HandleMeshPublication(Wire(late), owner.name))
		Finish(bridge)
		assert(
			#bridge.delivered == deliveredBeforeLate,
			"capacity failure cannot permit subsequent positive state into local presentation"
		)
		assert(
			not bridge.meshPublicationState.replayFences[owner.name],
			"an untracked retirement remains denied when an ordinary fence slot becomes available"
		)
		assert(bridge:GetMeshPublicationMetrics().replayFenceDrops >= 2)
		bridge:ResetMeshPublications()
		assert(bridge:GetCommTransferMetrics().bytes == 0 and bridge:GetMeshPublicationMetrics().retainedBytes == 0)
	end,
	{ offline = true }
)

QT:RegisterTest("mesh replay metadata reservation survives synchronous payload retirement and reset", function()
	for _, scenario in ipairs({ "reclaim", "reserve", "reset" }) do
		local owner, bridge = Peer("Earlier-Realm"), Peer("Bridge-Realm")
		local function Data()
			return {
				records = {
					{
						topic = "QTVR",
						data = { version = "9.0.3" },
						sampledAt = owner:GetAnnouncementServerTime(),
						revision = 1,
					},
				},
			}
		end
		local earlier = Publish(owner, "STATE", Data(), { expires = owner.now + 120 })
		assert(bridge:HandleMeshPublication(Wire(earlier), owner.name))
		Finish(bridge)
		owner.name = "Current-Realm"
		local current = Publish(owner, "STATE", Data(), { expires = owner.now + 120 })
		assert(bridge:HandleMeshPublication(Wire(current), owner.name))
		local reserve, cancel = bridge.ReserveCommResponseBytes, bridge.CancelTransportWhere
		local fired = false
		function bridge:ReserveCommResponseBytes(bytes)
			if bytes ~= 512 or fired then
				return reserve(self, bytes)
			end
			if scenario == "reclaim" then
				return nil
			end
			local reservation = reserve(self, bytes)
			fired = true
			if scenario == "reset" then
				self:ResetMeshPublications()
			else
				self:RetireMeshPublicationPeer(owner.name)
			end
			return reservation
		end
		function bridge:CancelTransportWhere(predicate, reason)
			if scenario == "reclaim" and reason == "replayFenceReclaimed" and not fired then
				fired = true
				self:RetireMeshPublicationPeer(owner.name)
			end
			return cancel(self, predicate, reason)
		end
		Finish(bridge)
		assert(fired, scenario)
		local state = bridge.meshPublicationState
		assert(
			not state or not state.replayFences[owner.name],
			"a synchronous cancellation cannot leave newly reserved metadata for its retired payload"
		)
		assert(
			bridge:GetMeshPublicationMetrics().retainedBytes == bridge:GetCommTransferMetrics().bytes,
			"reservations returned after cancellation or reset must still be released"
		)
		bridge:ResetMeshPublications()
		assert(bridge:GetCommTransferMetrics().bytes == 0)
	end
end)
