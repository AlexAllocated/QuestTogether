-- Production coordinators and transport, with private peers and asynchronous
-- delivery. Cryptographic correctness is covered separately with real keys.
local QT = _G.QuestTogether

local function Equal(actual, expected, detail)
	assert(actual == expected, (detail or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function Peer(net, name, settings, developer)
	local peer = net:AddPeer(name, settings)
	peer.db.profile.devLogAllAnnouncements = false
	peer.db.profile.shareDeveloperDiagnostics = true
	peer.isLocalDeveloper = developer == true
	peer.developerPublicKeyHex = string.rep("0", 64)
	peer.Ed25519 = {
		NewVerification = function()
			return coroutine.create(function()
				while peer.verificationPaused do
					coroutine.yield()
				end
				for _ = 1, peer.verificationSteps or 9 do
					coroutine.yield()
				end
				return true
			end)
		end,
	}
	if developer then
		function peer:SignDeveloperRequest()
			self.signatures = (self.signatures or 0) + 1
			return string.rep("s", 64)
		end
	end
	peer.announcements = {}
	function peer:HandleAnnouncementEvent(event)
		self.announcements[#self.announcements + 1] = event
		return true
	end
	return peer
end

local function HasRoute(peer, target)
	for _, route in ipairs(peer:GetDeveloperAnnouncementRoutes()) do
		if route.distribution == "WHISPER" and route.target == target then
			return true
		end
	end
	return false
end

local function Sent(peer, operation, distribution, target, start)
	local rows = {}
	for index = (start or 0) + 1, #peer.sent do
		local packet = peer.sent[index]
		local frame = peer:DecodeCommFrame(packet.wire)
		if
			frame
			and frame.operation == operation
			and (not distribution or packet.route == distribution)
			and (not target or packet.target == target)
		then
			rows[#rows + 1] = { packet = packet, frame = frame }
		end
	end
	return rows
end

local function Announce(peer, text)
	return peer:SendAnnouncementWireEvent({
		eventType = "QUEST_PROGRESS",
		senderName = peer.name,
		classFile = "MAGE",
		text = text,
		questId = "12345",
		occurredAt = peer.API.GetServerTime(),
	})
end

local function Frames(peer, operation, record)
	return assert(peer:BuildCommFrames(operation, record, {
		session = peer:GetCommunicationSession(),
		messageId = tostring(peer:NextCommunicationSequence()),
		requestId = record.requestId,
		stamp = peer.API.GetServerTime(),
	}))
end

QT:RegisterTest(
	"developer announcement network discovers late peers without devlogall or unsigned responders",
	function()
		local net = QT:CreateTestNetwork({ fps = 10, seed = 317, joinDelay = 0.2 })
		local regular = Peer(net, "Regular-Realm", { mapID = 12 })
		net:StartPeer(regular)
		net:Advance(10)
		Equal(#Sent(regular, "DEVANN"), 0, "ordinary clients must not advertise developer subscriptions")
		assert(not regular:IsDeveloperAnnouncementReceiver())
		regular.isLocalDeveloper = true
		assert(not regular:IsDeveloperAnnouncementReceiver(), "a local flag without a private signer is insufficient")
		regular.isLocalDeveloper = false
		local developer = Peer(net, "Developer-Realm", { mapID = 85 }, true)
		assert(developer:IsDeveloperAnnouncementReceiver())
		developer.isLoggingOut = true
		assert(not developer:IsDeveloperAnnouncementReceiver())
		developer.isLoggingOut = nil
		developer.isEnabled = false
		assert(not developer:IsDeveloperAnnouncementReceiver())
		developer.isEnabled = true
		net:StartPeer(developer)
		net:Advance(20)
		assert(HasRoute(regular, developer.name), "signed global subscription should authorize a different-zone peer")
		Equal(developer:GetOption("devLogAllAnnouncements"), false)
		local signed = developer.signatures
		local oldSent = #developer.sent
		local late = Peer(net, "Late-Realm", { mapID = 23 })
		net:StartPeer(late)
		Equal(#late:GetDeveloperAnnouncementRoutes(), 0)
		net:Advance(20)
		assert(HasRoute(late, developer.name), "late global join must learn the already-running developer feed")
		assert(#Sent(late, "HELLO", "CHANNEL") > 0)
		assert(#Sent(developer, "DEVANN", "CHANNEL", nil, oldSent) > 0, "HELLO must prompt a global reoffer")
		Equal(developer.signatures, signed, "HELLO reoffers must reuse the cached signed subscription")
		Equal(#Sent(regular, "DEVANN"), 0)
		Equal(#Sent(late, "DEVANN"), 0)
		for _, row in ipairs(Sent(developer, "DEVANN")) do
			Equal(row.packet.route, "CHANNEL")
			Equal(row.packet.channel, developer.announcementChannelName)
		end
	end,
	{ offline = true }
)

QT:RegisterTest("developer announcement network shares one identity across regional and private delivery", function()
	local net = QT:CreateTestNetwork({ fps = 10, seed = 71 })
	local developer = Peer(net, "Developer-Realm", { mapID = 12 }, true)
	local sender = Peer(net, "Sender-Realm", { mapID = 12 })
	net:StartPeer(developer)
	net:StartPeer(sender)
	net:Advance(20)
	assert(HasRoute(sender, developer.name))
	local before = #sender.sent
	assert(Announce(sender, "Shared progress"))
	Equal(#developer.announcements, 0, "queue admission cannot be reported as received data")
	net:Advance(10)
	local normal = Sent(sender, "ANN", "CHANNEL", nil, before)
	local mirrored = Sent(sender, "ANN", "WHISPER", developer.name, before)
	assert(#normal > 0 and #mirrored > 0, "both normal publication and the subscribed mirror must be sent")
	Equal(normal[1].frame.session, mirrored[1].frame.session)
	Equal(normal[1].frame.messageId, mirrored[1].frame.messageId, "audience fanout must preserve message identity")
	Equal(#developer.announcements, 1, "regional delivery and private mirror must not duplicate the event")
	Equal(developer.announcements[1].text, "Shared progress")
	local deliveries = {}
	for _, row in ipairs(net.trace) do
		if row.kind == "delivered" and row.peer == developer.name and row.packet.sender == sender.name then
			local frame = developer:DecodeCommFrame(row.packet.wire)
			if frame and frame.operation == "ANN" then
				deliveries[row.packet.route] = true
			end
		end
	end
	assert(
		deliveries.CHANNEL and deliveries.WHISPER,
		"duplicate suppression must run after both real network paths arrive"
	)
end, { offline = true })

QT:RegisterTest("developer announcement control messages only accept the main global channel", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local developer = Peer(net, "Developer-Realm", { group = "party" }, true)
	local receiver = Peer(net, "Receiver-Realm", { group = "party" }, true)
	for _, peer in ipairs({ developer, receiver }) do
		peer:InitializeCommunications()
		peer:InitializeGeographicComms()
		peer.geographicCommsState.subscriptions.QuestTogetherZ12 = true
		net:Join(peer, peer.announcementChannelName, true)
		net:Join(peer, "QuestTogetherZ12", true)
	end
	for _, operation in ipairs({ "HELLO", "DEVANN" }) do
		local record = operation == "HELLO" and { version = "7.0.0" }
			or assert(developer:PrepareDeveloperAnnouncementSubscription({
				active = true,
				subscriptionSession = developer:GetCommunicationSession(),
			}))
		for _, route in ipairs({
			{ distribution = "WHISPER", target = receiver.name },
			{ distribution = "PARTY" },
			{ distribution = "CHANNEL", channelName = "QuestTogetherZ12" },
		}) do
			assert(
				not developer:Emit(operation, record, { route }),
				"outbound " .. operation .. " must reject " .. route.distribution
			)
			for _, wire in ipairs(Frames(developer, operation, record)) do
				net:Inject(
					receiver,
					receiver.commPrefix,
					wire,
					route.distribution,
					developer.name,
					{ channel = route.channelName, group = "party" }
				)
			end
		end
	end
	net:Advance(0.2)
	Equal(receiver:GetDeveloperAnnouncementMetrics().hellosReceived or 0, 0)
	Equal(rawget(receiver, "developerRequestState"), nil, "wrong-route subscriptions must not enter authentication")
	for _, wire in ipairs(Frames(developer, "HELLO", { version = "7.0.0" })) do
		net:Inject(
			receiver,
			receiver.commPrefix,
			wire,
			"CHANNEL",
			developer.name,
			{ channel = receiver.announcementChannelName }
		)
	end
	net:Advance(0.2)
	Equal(receiver:GetDeveloperAnnouncementMetrics().hellosReceived, 1)
end)

QT:RegisterTest(
	"developer announcement privacy applies before initial authorization and strips hidden coordinates",
	function()
		local net = QT:CreateTestNetwork({ fps = 10, seed = 41 })
		local developer = Peer(net, "Developer-Realm", { mapID = 85 }, true)
		local optedOut = Peer(net, "Optedout-Realm", { mapID = 12 })
		local hidden = Peer(net, "Hidden-Realm", { mapID = 12 })
		optedOut.db.profile.shareDeveloperDiagnostics = false
		hidden.db.profile.sharePlayerLocation = false
		for _, peer in ipairs({ developer, optedOut, hidden }) do
			net:StartPeer(peer)
		end
		net:Advance(20)
		Equal(#optedOut:GetDeveloperAnnouncementRoutes(), 0)
		Equal(rawget(optedOut, "developerRequestState"), nil, "initial opt-out must avoid signature work")
		assert(HasRoute(hidden, developer.name))
		assert(hidden:SendAnnouncementWireEvent({
			eventType = "QUEST_PROGRESS",
			senderName = hidden.name,
			text = "Hidden-location progress",
			questId = "12345",
			classFile = "MAGE",
			mapID = "12",
			zoneName = "Private Zone",
			coordX = "42.5",
			coordY = "73.5",
			occurredAt = hidden.API.GetServerTime(),
		}))
		net:Advance(10)
		Equal(#developer.announcements, 1)
		for _, field in ipairs({ "mapID", "zoneName", "coordX", "coordY" }) do
			Equal(developer.announcements[1][field], "", "mirroring must not bypass location privacy for " .. field)
		end
		hidden.ignored[developer.name] = true
		Equal(#hidden:GetDeveloperAnnouncementRoutes(), 0)
		local before = #hidden.sent
		assert(Announce(hidden, "Ignored developer"))
		net:Advance(10)
		Equal(#Sent(hidden, "ANN", "WHISPER", developer.name, before), 0)
		assert(#Sent(hidden, "ANN", "CHANNEL", nil, before) > 0)
	end,
	{ offline = true }
)

QT:RegisterTest("developer announcement copies stay bounded while every normal party event progresses", function()
	local net = QT:CreateTestNetwork({ fps = 10, seed = 191 })
	local developer = Peer(net, "Developer-Realm", { mapID = 85 }, true)
	local sender = Peer(net, "Sender-Realm", { mapID = 12, group = "party" })
	local partner = Peer(net, "Partner-Realm", { mapID = 23, group = "party" })
	for _, peer in ipairs({ developer, sender, partner }) do
		net:StartPeer(peer)
	end
	net:Advance(20)
	assert(HasRoute(sender, developer.name))
	for index = 1, 8 do
		assert(Announce(sender, "Burst " .. index))
	end
	Equal(sender:GetDeveloperAnnouncementMetrics().pendingCopies, 4)
	assert(sender:GetDeveloperAnnouncementMetrics().capacitySkipped >= 4)
	net:Advance(20)
	Equal(#partner.announcements, 8, "mirror capacity must never drop the ordinary party audience")
	Equal(#developer.announcements, 4)
	Equal(sender:GetDeveloperAnnouncementMetrics().pendingCopies, 0)
end, { offline = true })

QT:RegisterTest("developer announcement ingress and partial objects leave capacity for normal party traffic", function()
	local net = QT:CreateTestNetwork({ fps = 10, seed = 281 })
	local developer = Peer(net, "Developer-Realm", { group = "party" }, true)
	net:StartPeer(developer)
	local senders = {}
	for index = 1, 12 do
		senders[index] = Peer(net, "Sender" .. index .. "-Realm")
	end
	local partner = Peer(net, "Partner-Realm", { group = "party" })
	for batch = 0, 2 do
		for index = batch * 4 + 1, batch * 4 + 4 do
			local sender = senders[index]
			local frames = Frames(sender, "ANN", {
				eventType = "QUEST_PROGRESS",
				senderName = sender.name,
				text = string.rep("x", 900),
			})
			assert(#frames > 1)
			net:Inject(developer, developer.commPrefix, frames[1], "WHISPER", sender.name)
		end
		net:Step()
	end
	Equal(developer:GetCommTransferMetrics().incoming, 8, "private feed must cap retained partial objects")
	assert(developer:GetCommTransferMetrics().capacity >= 4)
	local before = developer:GetDeveloperAnnouncementMetrics().ingressDropped or 0
	for index = 1, 24 do
		local sender = senders[index % #senders + 1]
		local frames = Frames(sender, "ANN", { eventType = "QUEST_PROGRESS", senderName = sender.name, text = "Burst" })
		assert(#frames == 1)
		net:Inject(developer, developer.commPrefix, frames[1], "WHISPER", sender.name)
	end
	local normal =
		Frames(partner, "ANN", { eventType = "QUEST_PROGRESS", senderName = partner.name, text = "Party progress" })
	for _, wire in ipairs(normal) do
		net:Inject(developer, developer.commPrefix, wire, "PARTY", partner.name, { group = "party" })
	end
	net:Step()
	assert(developer:GetDeveloperAnnouncementMetrics().ingressDropped >= before + 16)
	Equal(developer:GetCommTransferMetrics().incoming, 8)
	Equal(#developer.announcements, 1)
	Equal(developer.announcements[1].text, "Party progress")
end)

QT:RegisterTest("developer announcement opt-out cancels queued mirrors while normal routes continue", function()
	local net = QT:CreateTestNetwork({ fps = 10, seed = 181 })
	local developer = Peer(net, "Developer-Realm", { mapID = 85 }, true)
	local sender = Peer(net, "Sender-Realm", { mapID = 12 })
	local neighbor = Peer(net, "Neighbor-Realm", { mapID = 12 })
	for _, peer in ipairs({ developer, sender, neighbor }) do
		net:StartPeer(peer)
	end
	net:Advance(20)
	assert(HasRoute(sender, developer.name))
	local before = #sender.sent
	assert(Announce(sender, "Queued before opt-out"))
	sender.db.profile.shareDeveloperDiagnostics = false
	sender:ResetDeveloperAnnouncementSubscriptions()
	Equal(#sender:GetDeveloperAnnouncementRoutes(), 0)
	net:Advance(10)
	Equal(
		#Sent(sender, "ANN", "WHISPER", developer.name, before),
		0,
		"revocation must retire already-queued mirror traffic before native send"
	)
	assert(#Sent(sender, "ANN", "CHANNEL", nil, before) > 0)
	Equal(#neighbor.announcements, 1, "diagnostic opt-out must preserve normal quest publication")
	Equal(#developer.announcements, 0)
	assert(Announce(sender, "Published after opt-out"))
	net:Advance(10)
	Equal(#neighbor.announcements, 2)
	Equal(#developer.announcements, 0)
end, { offline = true })

QT:RegisterTest("developer announcement leases renew and expire without authenticating stale callbacks", function()
	local net = QT:CreateTestNetwork({ fps = 5, seed = 211 })
	local developer = Peer(net, "Developer-Realm", { mapID = 85 }, true)
	local sender = Peer(net, "Sender-Realm", { mapID = 12 })
	net:StartPeer(developer)
	net:StartPeer(sender)
	net:Advance(20)
	assert(HasRoute(sender, developer.name))
	local signed = developer.signatures
	local staleDeparture = Frames(developer, "BYE", { reason = "logout" })
	net:Advance(100)
	assert(developer.signatures > signed, "an active developer feed must renew its signed lease")
	assert(HasRoute(sender, developer.name))
	for _, wire in ipairs(staleDeparture) do
		net:Inject(
			sender,
			sender.commPrefix,
			wire,
			"CHANNEL",
			developer.name,
			{ channel = sender.announcementChannelName }
		)
	end
	net:Advance(1)
	assert(HasRoute(sender, developer.name), "an older departure must not revoke a newer signed lease")
	net.deliveryRule = function(packet)
		local frame = developer:DecodeCommFrame(packet.wire)
		if frame and frame.operation == "DEVANN" then
			return { drop = true }
		end
	end
	net:Advance(245)
	Equal(#sender:GetDeveloperAnnouncementRoutes(), 0, "lost renewal must expire the mirror destination")
	local before = #sender.sent
	assert(Announce(sender, "After lease expiry"))
	net:Advance(10)
	Equal(#Sent(sender, "ANN", "WHISPER", developer.name, before), 0)
	assert(#Sent(sender, "ANN", "CHANNEL", nil, before) > 0)

	for _, boundary in ipairs({ "reset", "disable", "departure" }) do
		local fresh = QT:CreateTestNetwork({ fps = 5, seed = 17 })
		local dev = Peer(fresh, "Developer-Realm", { mapID = 85 }, true)
		local peer = Peer(fresh, "Pending-Realm", { mapID = 12 })
		peer.verificationSteps = 10000
		fresh:StartPeer(dev)
		fresh:StartPeer(peer)
		local state
		for _ = 1, 20 do
			fresh:Advance(1)
			state = rawget(peer, "developerRequestState")
			if state and state.jobs[1] then
				break
			end
		end
		assert(state and state.jobs[1], "subscription must enter the real deferred authentication queue")
		local job = state.jobs[1]
		local staleRequest = peer:DeepCopy(job.request)
		staleRequest.developerVerified = true
		if boundary == "departure" then
			for _, wire in ipairs(Frames(dev, "BYE", { reason = "logout" })) do
				fresh:Inject(
					peer,
					peer.commPrefix,
					wire,
					"CHANNEL",
					dev.name,
					{ channel = peer.announcementChannelName }
				)
			end
			fresh:Advance(0.2)
		else
			if boundary == "disable" then
				peer.isEnabled = false
			end
			peer:ResetDeveloperAnnouncementSubscriptions()
		end
		job.callback(staleRequest)
		Equal(#peer:GetDeveloperAnnouncementRoutes(), 0, boundary .. " must fence captured verification callbacks")
	end
end, { offline = true })

QT:RegisterTest("developer announcement authentication progresses beside a private diagnostic ping", function()
	local net = QT:CreateTestNetwork({ fps = 10, seed = 223 })
	local developer = Peer(net, "Developer-Realm", { mapID = 85 }, true)
	local sender = Peer(net, "Sender-Realm", { mapID = 12 })
	sender.verificationPaused = true
	local pongs, contended, timings = 0, 0, {}
	function developer:PrintPingResponse()
		pongs = pongs + 1
	end
	local verify = sender.QueueDeveloperAnnouncementVerification
	function sender:QueueDeveloperAnnouncementVerification(...)
		local state = rawget(self, "developerRequestState")
		if state and state.pendingSenders[developer.name] then
			contended = contended + 1
		end
		timings[#timings + 1] = "feed@" .. net.now .. ":" .. tostring(state and state.pendingSenders[developer.name])
		return verify(self, ...)
	end
	local pingVerify = sender.QueueDeveloperPingVerification
	function sender:QueueDeveloperPingVerification(...)
		local state = rawget(self, "developerRequestState")
		if state and state.pendingSenders[developer.name] then
			contended = contended + 1
		end
		timings[#timings + 1] = "ping@" .. net.now .. ":" .. tostring(state and state.pendingSenders[developer.name])
		return pingVerify(self, ...)
	end
	net:StartPeer(sender)
	net:StartPeer(developer)
	assert(developer:SendPingRequest(sender.name, false))
	net:Advance(22)
	assert(
		contended > 0,
		"the fixture must overlap a feed offer with real ping authentication: " .. table.concat(timings, ",")
	)
	sender.verificationPaused = false
	local newcomer = Peer(net, "Newcomer-Realm", { mapID = 23 })
	net:StartPeer(newcomer)
	net:Advance(35)
	Equal(pongs, 1, "a feed offer must not block or duplicate the diagnostic pong")
	assert(HasRoute(sender, developer.name), "a coalesced reoffer must recover after the shared verifier was occupied")
	assert(sender:GetDeveloperCommunicationMetrics().verified >= 2)
	assert(Announce(sender, "Progress after authentication"))
	net:Advance(10)
	Equal(#developer.announcements, 1)
	local departure = Frames(developer, "BYE", { reason = "logout" })
	for _, wire in ipairs(departure) do
		net:Inject(
			sender,
			sender.commPrefix,
			wire,
			"CHANNEL",
			developer.name,
			{ channel = sender.announcementChannelName }
		)
	end
	net:Advance(1)
	Equal(#sender:GetDeveloperAnnouncementRoutes(), 0, "current departure must promptly revoke its lease")
end, { offline = true })
