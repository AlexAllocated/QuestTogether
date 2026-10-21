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

local function FinishVerification(peer)
	local steps = 0
	while peer.developerRequestState and #peer.developerRequestState.jobs > 0 do
		steps = steps + 1
		assert(steps < 10000, "identity authentication did not finish")
		peer:DrainDeveloperPingVerifications()
		peer.now = peer.now + 0.01
	end
end

QT:RegisterTest(
	"developer identity is local-key or signed-session evidence and retires at lifecycle boundaries",
	function()
		for _, boundary in ipairs({ "expiry", "departure", "session", "ignore", "disable", "logout", "reset" }) do
			local net = QT:CreateTestNetwork({ fps = 10 })
			local dev = Peer(net, "Developer-Realm", nil, true)
			local peer = Peer(net, "Peer-Realm")
			peer.db.profile.shareDeveloperDiagnostics = false
			assert(dev:IsVerifiedDeveloper(dev.name))
			peer.isLocalDeveloper = true
			assert(not peer:IsVerifiedDeveloper(peer.name), "a flag without the private signer cannot identify self")
			peer.isLocalDeveloper = false
			assert(not peer:IsVerifiedDeveloper(dev.name))
			local record = assert(dev:PrepareDeveloperAnnouncementSubscription({
				active = true,
				subscriptionSession = dev:GetCommunicationSession(),
			}))
			local context = { session = record.subscriptionSession, sequence = dev:NextCommunicationSequence() }
			assert(peer:HandleDeveloperAnnouncementSubscription(record, dev.name, context))
			assert(not peer:IsVerifiedDeveloper(dev.name), "pending verification is not identity evidence")
			FinishVerification(peer)
			assert(peer:IsVerifiedDeveloper(dev.name), boundary)
			assert(#peer:GetDeveloperAnnouncementRoutes() == 0)
			local lease = peer.developerAnnouncementState.subscribers[dev.name]
			if boundary == "expiry" then
				peer.now = lease.expires
			elseif boundary == "departure" then
				assert(peer:RecordPeerDeparture(dev.name, peer.now, context.session, context.sequence + 1))
			elseif boundary == "session" then
				assert(peer:RecordPeerEpoch(dev.name, "next-session", record.issuedAt + 1))
			elseif boundary == "ignore" then
				peer.ignored[dev.name] = true
			elseif boundary == "disable" then
				peer.isEnabled = false
			elseif boundary == "logout" then
				peer.isLoggingOut = true
			else
				peer:ResetDeveloperAnnouncements()
			end
			assert(not peer:IsVerifiedDeveloper(dev.name), boundary .. " must retire the badge immediately")
			if boundary == "session" then
				assert(
					not peer:RecordPeerEpoch(dev.name, context.session, record.issuedAt + 2),
					"retired session cannot return"
				)
			end
		end
	end
)

QT:RegisterTest("developer identity requires an authentic signature bound to sender request and session", function()
	local seed = ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"):gsub("..", function(x)
		return string.char(tonumber(x, 16))
	end)
	for _, altered in ipairs({ "none", "signature", "sender", "request", "session" }) do
		local net = QT:CreateTestNetwork({ fps = 10 })
		local dev = Peer(net, "Developer-Realm", nil, true)
		local peer = Peer(net, "Peer-Realm")
		peer.db.profile.shareDeveloperDiagnostics = false
		peer.Ed25519 = QT.Ed25519
		peer.developerPublicKeyHex = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
		function dev:SignDeveloperRequest(text)
			return QT.Ed25519.Sign(seed, text)
		end
		local record = assert(dev:PrepareDeveloperAnnouncementSubscription({
			active = true,
			subscriptionSession = dev:GetCommunicationSession(),
		}))
		local sender = dev.name
		if altered == "signature" then
			record.signature = string.rep("0", 128)
		elseif altered == "sender" then
			sender = "Forged-Realm"
		elseif altered == "request" then
			record.requestId = record.requestId .. "1"
		elseif altered == "session" then
			record.subscriptionSession = "forged-session"
		end
		assert(peer:HandleDeveloperAnnouncementSubscription(record, sender, {
			session = record.subscriptionSession,
			sequence = dev:NextCommunicationSequence(),
		}))
		FinishVerification(peer)
		Equal(peer:IsVerifiedDeveloper(sender), altered == "none", altered)
		Equal(#peer:GetDeveloperAnnouncementRoutes(), 0)
	end
end, { offline = true })

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
		late.db.profile.sharePlayerLocation = false
		net:StartPeer(late)
		Equal(#late:GetDeveloperAnnouncementRoutes(), 0)
		net:Advance(20)
		assert(HasRoute(late, developer.name), "late global join must learn the already-running developer feed")
		assert(developer:IsPlayerLocationHiddenForDeveloper(late.name), "late hidden peers must appear without a manual ping")
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
	"developer feed renews private locations without pings and preserves public and diagnostic consent",
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
		net:Advance(30)
		Equal(#optedOut:GetDeveloperAnnouncementRoutes(), 0)
		assert(
			optedOut:IsVerifiedDeveloper(developer.name),
			"signed public identity is independent of diagnostics consent"
		)
		assert(developer:IsPlayerLocationHiddenForDeveloper(hidden.name), "verified subscription must deliver a private location without ping")
		Equal(developer.developerPlayerData[hidden.name].x, hidden.position.x)
		for _, observer in ipairs({ developer, optedOut }) do
			local public = observer:GetPlayerLocationState().peers[hidden.name]
			assert(not public or public.mask == 0, "private coordinates must never become public location state")
			assert(not public or public.x == nil)
		end
		Equal(rawget(optedOut, "developerPlayerData"), nil)
		Equal(#Sent(optedOut, "DLOC"), 0)
		Equal(#Sent(developer, "PING"), 0)
		Equal(#Sent(hidden, "PONG"), 0)
		assert(#Sent(hidden, "DLOC", "WHISPER", developer.name) > 0)
		Equal(#Sent(hidden, "DLOC", "CHANNEL"), 0)
		local beforeOptedOut = #optedOut.sent
		assert(Announce(optedOut, "Opted-out progress"))
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
		Equal(#Sent(optedOut, "ANN", "WHISPER", developer.name, beforeOptedOut), 0)
		assert(#Sent(optedOut, "ANN", "CHANNEL", nil, beforeOptedOut) > 0)
		Equal(#developer.announcements, 1)
		for _, field in ipairs({ "mapID", "zoneName", "coordX", "coordY" }) do
			Equal(developer.announcements[1][field], "", "mirroring must not bypass location privacy for " .. field)
		end
		local original = developer.developerPlayerData[hidden.name]
		hidden.position.x = 0.72
		net:Advance(55)
		Equal(developer.developerPlayerData[hidden.name].x, 0.72)
		assert(developer.developerPlayerData[hidden.name].receivedAt > original.receivedAt)
		-- Stationary updates must renew well before their two-minute lifetime,
		-- including across signed developer subscription renewal.
		net:Advance(130)
		assert(developer:IsPlayerLocationHiddenForDeveloper(hidden.name))
		assert(developer.developerPlayerData[hidden.name].receivedAt > original.receivedAt + 120)
		hidden.db.profile.sharePlayerLocation = true
		net:Advance(15)
		Equal(developer.developerPlayerData[hidden.name], nil)
		assert(developer:GetFreshPlayerLocation(hidden.name, "map"))
		hidden.db.profile.sharePlayerLocation = false
		net:Advance(15)
		assert(developer:IsPlayerLocationHiddenForDeveloper(hidden.name))
		hidden.ignored[developer.name] = true
		Equal(#hidden:GetDeveloperAnnouncementRoutes(), 0)
		local before = #hidden.sent
		assert(Announce(hidden, "Ignored developer"))
		net:Advance(10)
		Equal(#Sent(hidden, "ANN", "WHISPER", developer.name, before), 0)
		Equal(#Sent(hidden, "DLOC", "WHISPER", developer.name, before), 0)
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
	sender.db.profile.sharePlayerLocation = false
	for _, peer in ipairs({ developer, sender, neighbor }) do
		net:StartPeer(peer)
	end
	net:Advance(20)
	assert(HasRoute(sender, developer.name))
	local before = #sender.sent
	local lease = sender.developerAnnouncementState.subscribers[developer.name]
	lease.nextLocationAt = sender.now
	sender:UpdateDeveloperLocationPublications(sender.now)
	assert(lease.locationPending, "exercise consent withdrawal with a queued private location")
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
	Equal(#Sent(sender, "DLOC", "WHISPER", developer.name, before), 0)
	Equal(#neighbor.announcements, 1, "diagnostic opt-out must preserve normal quest publication")
	Equal(#developer.announcements, 0)
	net:Advance(125)
	assert(not developer:IsPlayerLocationHiddenForDeveloper(sender.name), "opt-out must let old private data expire")
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
	assert(not sender:IsVerifiedDeveloper(developer.name), "unrelated traffic cannot renew signed identity")
	local before = #sender.sent
	assert(Announce(sender, "After lease expiry"))
	net:Advance(10)
	Equal(#Sent(sender, "ANN", "WHISPER", developer.name, before), 0)
	assert(#Sent(sender, "ANN", "CHANNEL", nil, before) > 0)

	for _, boundary in ipairs({ "reset", "disable", "departure", "consent" }) do
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
			elseif boundary == "consent" then
				peer.db.profile.shareDeveloperDiagnostics = false
			end
			peer:ResetDeveloperAnnouncementSubscriptions()
		end
		job.callback(staleRequest)
		Equal(#peer:GetDeveloperAnnouncementRoutes(), 0, boundary .. " must fence captured verification callbacks")
		assert(not peer:IsVerifiedDeveloper(dev.name), boundary .. " must not restore stale identity")
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

QT:RegisterTest("private location feed orders snapshots across privacy changes departures and developer renewal", function()
	local net = QT:CreateTestNetwork({ fps = 5 })
	local dev = Peer(net, "Developer-Realm", nil, true)
	local peer = Peer(net, "Hidden-Realm")
	local state = dev:InitializeDeveloperAnnouncements()
	local offer = assert(dev:PrepareDeveloperAnnouncementSubscription({ active = true, subscriptionSession = state.communication.session }))
	state.locationSubscriptions[offer.requestId] = { startedAt = dev.now, expires = dev.now + 240 }
	local location = { mask = 3, mapID = 12, x = 0.4, y = 0.6, classFile = "MAGE" }
	local record = { subscriptionSession = offer.subscriptionSession, subscriptionId = offer.requestId,
		locationShared = false, location = location }
	local context = { distribution = "WHISPER", session = peer:GetCommunicationSession(), sequence = 1,
		stamp = peer.API.GetServerTime() }
	local function Accept()
		return dev:HandleDeveloperLocationSnapshot(record, peer.name, context)
	end
	assert(Accept())
	local first = dev.developerPlayerData[peer.name]
	Equal(first.x, 0.4)
	Equal(dev:GetPlayerLocationState().peers[peer.name].mask, 0)
	assert(dev:IsKnownQTPlayer(peer.name), "private snapshots should refresh genuine addon identity")
	net:Advance(2)
	location.x, context.sequence, context.stamp = 0.7, 3, peer.API.GetServerTime()
	assert(Accept())
	local current = dev.developerPlayerData[peer.name]
	context.sequence = 2
	assert(not Accept())
	Equal(dev.developerPlayerData[peer.name], current)
	context.sequence, context.stamp = 4, peer.API.GetServerTime() - 2
	assert(not Accept(), "new envelope identity cannot make an older sample fresh")
	context.stamp, record.locationShared = peer.API.GetServerTime(), true
	assert(Accept())
	Equal(dev.developerPlayerData[peer.name], nil)
	Equal(dev:GetFreshPlayerLocation(peer.name, "map").x, 0.7)
	Equal(dev:GetFreshPlayerLocation(peer.name, "map").lifetime, dev:GetGeographicSnapshotLifetime(),
		"the optional developer feed must not shorten ordinary public location lifetime")
	local public = dev:GetFreshPlayerLocation(peer.name, "map")
	record.location, context.sequence = { mask = 0 }, 5
	Accept()
	Equal(dev:GetFreshPlayerLocation(peer.name, "map"), public,
		"temporarily unavailable diagnostic coordinates must not withdraw or refresh a valid public dot")
	record.location = location
	record.locationShared, context.sequence = false, 3
	assert(not Accept(), "old hidden data cannot resurrect a red dot after public sharing resumes")
	context.sequence = 5
	assert(Accept())
	record.location, context.sequence = { mask = 0 }, 6
	assert(Accept())
	Equal(dev.developerPlayerData[peer.name], nil)
	Equal(dev:GetFreshPlayerLocation(peer.name, "map"), nil)
	record.location, context.sequence = location, 7
	assert(Accept())
	assert(dev:RecordPeerDeparture(peer.name, dev.now, context.session, 8))
	assert(not Accept())
	Equal(dev.developerPlayerData[peer.name], nil)
	net:Advance(2)
	local oldSession = context.session
	context.session, context.sequence, context.stamp = "new-session", 1, peer.API.GetServerTime()
	assert(Accept())
	context.session, context.sequence = oldSession, 99
	assert(not Accept(), "a retired sender session must not return with a higher sequence")
	context.session, context.sequence = "new-session", 2
	-- A renewal does not invalidate a still-live preceding signed offer.
	local renewal = assert(dev:PrepareDeveloperAnnouncementSubscription({ active = true, subscriptionSession = state.communication.session }))
	state.locationSubscriptions[renewal.requestId] = { startedAt = dev.now, expires = dev.now + 240 }
	assert(Accept())
	record.subscriptionId = "unissued-subscription"
	context.sequence = 3
	assert(not Accept())
	record.subscriptionId = offer.requestId
	context.stamp = peer.API.GetServerTime() - 120
	assert(not Accept(), "queue delays must not renew an expired source sample")
	context.stamp = peer.API.GetServerTime()
	location.x = 2
	assert(not Accept())
	location.x = 0.7
	net:Advance(121)
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	context.stamp = peer.API.GetServerTime()
	assert(Accept())
	dev:ResetDeveloperAnnouncements()
	assert(not Accept(), "late callbacks from a retired developer lifetime cannot install a dot")
end)
