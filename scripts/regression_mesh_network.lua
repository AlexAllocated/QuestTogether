-- Mesh contracts run real coordinators on independent peers. Directory rows
-- remain untrusted addresses; accepted native sends and delivery are separate.
local QT = _G.QuestTogether
local function Count(values)
	local n = 0
	for _ in pairs(values or {}) do
		n = n + 1
	end
	return n
end
local function Peer(net, name, settings)
	local peer = net:AddPeer(name, settings)
	peer.announcementChannelName = "QuestTogether"
	peer.API.GetPlayerNotesNamespace = function()
		return "test:US:realm"
	end
	return peer
end
local function NoChannels(net)
	for _, packet in ipairs(net.trace) do
		if packet.kind == "attempts" then
			assert(packet.packet.route ~= "CHANNEL", "directory membership became channel traffic")
		end
	end
end

QT:RegisterTest("mesh shared links reuse completed bundles across subscribers and renewals but not sessions", function()
	local net = QT:CreateTestNetwork({ now = 10000 })
	local peer = Peer(net, "Owner-Realm")
	net:StartPeer(peer)
	local state, wall = peer:InitializeMeshNetwork(), peer:GetAnnouncementServerTime()
	state.neighbors["Hub-Realm"] =
		{ name = "Hub-Realm", session = "hub-one", sharedDelivery = true, expires = peer.now + 1000 }
	state.neighbors["Old-Realm"] = { name = "Old-Realm", session = "old-one", expires = peer.now + 1000 }
	local leases = {}
	local function AddLease(destination, target, id, expires)
		local lease = {
			id = id,
			destination = destination,
			zone = 12,
			upstream = target,
			expiresAt = expires,
			downstreams = {},
			alternates = {},
		}
		state.interests[destination .. ":" .. id] = lease
		return lease
	end
	for index = 1, 4 do
		leases[index] = AddLease(
			"Viewer" .. index .. "-Realm",
			index <= 2 and "Hub-Realm" or "Old-Realm",
			"lease" .. index,
			wall + 120
		)
	end
	local sends = {}
	function peer:SendMeshPublicationToPeer(_, target, metadata, options)
		sends[#sends + 1] = { target = target, metadata = metadata, options = options }
		options.onComplete(true, "acknowledged")
		return true, "queued"
	end
	local publication =
		{ origin = peer.name, session = "source", id = "1", digest = "digest", scope = 12, expiresAt = wall + 300 }
	assert(
		not peer:HasDeliveredMeshPublicationForInterest({ scope = 12 }, leases[1]),
		"unhashed state is not delivered"
	)
	assert(peer:ForwardMeshPublication(publication))
	assert(#sends == 3, "two subscribers on a shared link need one bundle; legacy destinations remain separate")
	for _, sent in ipairs(sends) do
		assert((sent.metadata.sharedDelivery == true) == (sent.target == "Hub-Realm"))
	end
	assert(peer:HasDeliveredMeshPublicationForInterest(publication, leases[2]))
	local renewed = AddLease(leases[1].destination, "Hub-Realm", "renewed", wall + 240)
	assert(peer:HasDeliveredMeshPublicationForInterest(publication, renewed))
	assert(peer:ForwardMeshPublication(publication, { meshInterest = renewed }))
	assert(#sends == 3, "renewing a lease must not resend a completed shared-link bundle")
	state.neighbors["Hub-Realm"].session = "hub-two"
	assert(not peer:HasDeliveredMeshPublicationForInterest(publication, renewed))
	assert(peer:ForwardMeshPublication(publication, { meshInterest = renewed }))
	assert(#sends == 4, "a restarted peer must receive the bundle in its new native session")
	local oldRenewal = AddLease(leases[3].destination, "Old-Realm", "legacy-renewed", wall + 240)
	assert(peer:HasDeliveredMeshPublicationForInterest(publication, oldRenewal))
	net.now, peer.now = net.now + 121, peer.now + 121
	assert(
		not peer:HasDeliveredMeshPublicationForInterest(publication, oldRenewal),
		"a legacy hop receipt cannot suppress recovery after its original reverse lease expires"
	)
	assert(peer:ForwardMeshPublication(publication, { meshInterest = oldRenewal }))
	assert(#sends == 5)
end, { offline = true })

QT:RegisterTest("mesh authenticated shared routing matches scopes and consumes hops without echoing origins", function()
	local net = QT:CreateTestNetwork({ now = 10000 })
	local peer = Peer(net, "Bridge-Realm")
	net:StartPeer(peer)
	local state, wall = peer:InitializeMeshNetwork(), peer:GetAnnouncementServerTime()
	for _, name in ipairs({ "Origin-Realm", "Shared-Realm", "Legacy-Realm" }) do
		state.neighbors[name] =
			{ name = name, session = "native", sharedDelivery = name ~= "Legacy-Realm", expires = peer.now + 1000 }
	end
	local route = {
		id = "incoming",
		destination = "Viewer1-Realm",
		zone = 12,
		upstream = "Shared-Realm",
		expiresAt = wall + 120,
		downstreams = { ["Origin-Realm"] = true },
		alternates = {},
	}
	state.interests[route.destination .. ":" .. route.id] = route
	state.localInterests[12] = { expiresAt = wall + 120 }
	for index, target in ipairs({ "Shared-Realm", "Legacy-Realm", "Origin-Realm" }) do
		local lease = {
			id = "more" .. index,
			destination = "Other" .. index .. "-Realm",
			zone = 12,
			upstream = target,
			expiresAt = wall + 120,
			downstreams = {},
			alternates = {},
		}
		state.interests[lease.destination .. ":" .. lease.id] = lease
	end
	local meta = { leaseId = route.id, destination = route.destination, zone = 12, hops = 4, sharedDelivery = true }
	assert(
		peer:ShouldConsumeMeshPublicationRoute("Origin-Realm", meta, 12, "Origin-Realm"),
		"a valid authenticated public route can also satisfy the relay's own live same-scope interest"
	)
	assert(not peer:CanAcceptMeshPublicationRoute("Legacy-Realm", meta, 12, "Origin-Realm"))
	assert(not peer:CanAcceptMeshPublicationRoute("Origin-Realm", meta, 99, "Origin-Realm"))
	local sends = {}
	function peer:SendMeshPublicationToPeer(_, target, metadata, options)
		sends[#sends + 1] = target
		assert(target ~= "Origin-Realm" and metadata.hops == 3)
		options.onComplete(true, "acknowledged")
		return true
	end
	local publication = {
		origin = "Origin-Realm",
		session = "source",
		id = "1",
		digest = "digest",
		scope = 12,
		expiresAt = wall + 120,
	}
	assert(peer:ForwardMeshPublication(publication, { relaySender = "Origin-Realm", relaymeta = meta }))
	assert(#sends == 2, "matching shared subscribers use one link; a separate legacy route still receives its copy")
	meta.hops = 1
	assert(not peer:ForwardMeshPublication(publication, { relaySender = "Origin-Realm", relaymeta = meta }))
	assert(#sends == 2, "new subscriptions cannot restart an exhausted publication hop budget")
end, { offline = true })

QT:RegisterTest(
	"mesh interests aggregate live local demand and retry expired sends with bounded runtime work",
	function()
		local net = QT:CreateTestNetwork({ now = 10000 })
		local peer = Peer(net, "Bridge-Realm")
		net:StartPeer(peer)
		local state, wall = peer:InitializeMeshNetwork(), peer:GetAnnouncementServerTime()
		state.nextDirectory, state.nextGuild, state.nextHandshake = math.huge, math.huge, math.huge
		peer.geographicCommsState = { currentZone = 12, viewZone = 12 }
		for _, name in ipairs({ "Upstream-Realm", "Downstream-Realm" }) do
			state.neighbors[name] =
				{ name = name, session = "native", sharedDelivery = true, expires = peer.now + 1000 }
		end
		local own = {
			id = "local",
			destination = peer.name,
			zone = 12,
			expiresAt = wall + 120,
			renewAt = peer.now + 120,
			hops = 8,
			downstreams = { ["Downstream-Realm"] = true },
			coveredDownstreams = { ["Downstream-Realm"] = true },
		}
		state.localInterests[12], state.localHistory[peer.name .. ":local"] = own, own
		local renewal = {
			id = "pending-local",
			destination = peer.name,
			zone = 12,
			expiresAt = wall + 120,
			renewAt = peer.now + 120,
			hops = 8,
			downstreams = {},
		}
		state.localInterests[12], state.localHistory[peer.name .. ":pending-local"] = renewal, renewal
		local sends, attempts, first = 0, 0
		function peer:Emit(operation, data, _, options)
			if operation ~= "MINT" then
				return true
			end
			if data.destination == "Viewer-Realm" then
				sends, attempts = sends + 1, attempts + 1
				assert(options.expires == peer.now + 30, "interest queues need room for measured congestion")
				if attempts == 1 then
					first = options
					options.onComplete(false, "expired")
				else
					options.onStarted()
					options.onComplete(true, "accepted")
				end
			elseif options.onStarted then
				options.onStarted()
				options.onComplete(true, "accepted")
			end
			return true
		end
		local request =
			{ leaseId = "shared-demand", destination = "Viewer-Realm", zone = 12, expiresAt = wall + 120, hops = 8 }
		assert(
			not peer:HandleMeshInterest(request, "Upstream-Realm", { distribution = "WHISPER", session = "retired" })
		)
		assert(peer:HandleMeshInterest(request, "Upstream-Realm", { distribution = "WHISPER", session = "native" }))
		local incoming = state.interests["Viewer-Realm:shared-demand"]
		assert(
			incoming.aggregated and sends == 0,
			"an unsent renewal must preserve coverage from its preceding live query"
		)
		peer.geographicCommsState = { currentZone = 99, viewZone = 99 }
		peer:UpdateMeshNetwork(peer.now)
		assert(not incoming.aggregated and sends == 1, "remaining foreign demand resumes when local scope is removed")
		net.now, peer.now = net.now + 2, peer.now + 2
		peer:UpdateMeshNetwork(peer.now)
		assert(
			sends == 2 and incoming.downstreams["Downstream-Realm"],
			"failed interest delivery retries from the runtime"
		)
		state.interests["Viewer-Realm:shared-demand"] = nil
		assert(not first.isCurrent(), "retired query callbacks cannot recreate a route")
	end,
	{ offline = true }
)

QT:RegisterTest("mesh shared cycles deliver authenticated public data once within native budgets", function()
	local net = QT:CreateTestNetwork({ now = 10000, fps = 20, latency = 0.02, seed = 92 })
	local peers, deliveries = {}, {}
	for index = 1, 4 do
		local peer = Peer(net, "Cycle" .. index .. "-Realm", { mapID = 12 })
		peers[index], deliveries[index] = peer, 0
		net:StartPeer(peer)
		peer:InitializeMeshNetwork()
		peer.UpdateMeshNetwork = function() end
		peer.UpdatePlayerCommunications = function() end
		peer:UpdateGeographicSubscriptions()
		function peer:HandleQTMeshChat(data, origin)
			if data.text == "Shared cycle" then
				assert(origin == peers[1].name)
				deliveries[index] = deliveries[index] + 1
			end
			return true
		end
	end
	for index, peer in ipairs(peers) do
		local s, wall = peer.meshNetworkState, peer:GetAnnouncementServerTime()
		local localLease = {
			id = "cycle" .. index,
			destination = peer.name,
			zone = 12,
			expiresAt = wall + 120,
			downstreams = {},
			hops = 8,
		}
		s.localInterests[12], s.localHistory[peer.name .. ":" .. localLease.id] = localLease, localLease
		for _, neighborIndex in ipairs({ (index + 2) % 4 + 1, index % 4 + 1 }) do
			local neighbor = peers[neighborIndex]
			s.neighbors[neighbor.name] = {
				name = neighbor.name,
				session = neighbor:GetCommunicationSession(),
				sharedDelivery = true,
				expires = peer.now + 180,
			}
			localLease.downstreams[neighbor.name] = true
			local lease = {
				id = "cycle" .. neighborIndex,
				destination = neighbor.name,
				zone = 12,
				expiresAt = wall + 120,
				upstream = neighbor.name,
				downstreams = {},
				alternates = {},
			}
			s.interests[neighbor.name .. ":" .. lease.id] = lease
		end
	end
	assert(
		peers[1]:Emit(
			"QTCHAT",
			{ text = "Shared cycle" },
			{ { distribution = "MESH", scope = 12 } },
			{ owner = peers[1], expires = peers[1].now + 90 }
		)
	)
	net:Advance(60)
	for index, peer in ipairs(peers) do
		assert(
			deliveries[index] == (index == 1 and 0 or 1),
			"cycles must not duplicate accepted public events: index=" .. index .. " received=" .. deliveries[index]
		)
		local metrics = peer:GetTransportMetrics()
		assert((metrics.meshPackets or 0) <= 122 and (metrics.meshBytes or 0) <= 24400)
		assert(peer:GetMeshNetworkMetrics().pendingPublications == 0)
	end
	assert(
		(peers[3]:GetMeshPublicationMetrics().authenticationLatencyLast or -1) >= 0,
		"the non-neighbor recipient must independently authenticate the original owner"
	)
	NoChannels(net)
end, { offline = true })

QT:RegisterTest(
	"mesh correlated capability changes retire old routes and stale callbacks cannot restore them",
	function()
		local net = QT:CreateTestNetwork({ now = 10000 })
		local peer = Peer(net, "Local-Realm")
		net:StartPeer(peer)
		local s, wall = peer:InitializeMeshNetwork(), peer:GetAnnouncementServerTime()
		peer.API.GetNumDisplayChannels = function()
			return 0
		end
		s.nextDirectory, s.nextGuild = math.huge, math.huge
		s.neighbors["Remote-Realm"] = {
			name = "Remote-Realm",
			session = "old-session",
			sharedDelivery = true,
			at = peer.now - 121,
			expires = peer.now + 180,
		}
		local lease = {
			id = "old-query",
			destination = "Remote-Realm",
			zone = 12,
			expiresAt = wall + 120,
			upstream = "Remote-Realm",
			downstreams = {},
			alternates = {},
		}
		s.interests["Remote-Realm:old-query"] = lease
		local queued
		function peer:SendMeshPublicationToPeer(_, _, _, options)
			queued = options
			return true
		end
		assert(peer:ForwardMeshPublication({
			origin = peer.name,
			session = "source",
			id = "1",
			digest = "digest",
			scope = 12,
			expiresAt = wall + 120,
		}))
		assert(queued and queued.isCurrent())
		peer:RememberMeshCandidate("Remote-Realm", "friend")
		local candidate = s.candidates["Remote-Realm"]
		candidate.retryAt, candidate.triedAt, s.nextHandshake = peer.now, nil, peer.now
		local challenge
		function peer:Request(_, _, _, options)
			challenge = options
			return true, "queued", {}, "challenge"
		end
		peer:UpdateMeshNetwork(peer.now)
		assert(challenge)
		local response = { protocol = 3, capabilities = "mesh1", admitted = true, peers = {}, requestId = "challenge" }
		assert(challenge.onResponse(response, "Remote-Realm", { distribution = "WHISPER", session = "new-session" }))
		assert(
			s.neighbors["Remote-Realm"].sharedDelivery == false,
			"a new correlated session without the extension must not inherit the previous capability"
		)
		assert(not s.interests["Remote-Realm:old-query"] and not queued.isCurrent())
		queued.onComplete(true, "acknowledged")
		assert(s.pendingPublications and not next(s.pendingPublications))
		response.sharedDelivery = true
		assert(
			not challenge.onResponse(response, "Remote-Realm", { distribution = "WHISPER", session = "old-session" })
		)
		assert(s.neighbors["Remote-Realm"].session == "new-session" and not s.neighbors["Remote-Realm"].sharedDelivery)
	end,
	{ offline = true }
)

QT:RegisterTest("mesh shared groups preserve other subscribers when the representative fails or retires", function()
	for _, scenario in ipairs({ "alternate", "retired" }) do
		local net = QT:CreateTestNetwork({ now = 10000 })
		local peer = Peer(net, "Owner-Realm")
		net:StartPeer(peer)
		local s, wall = peer:InitializeMeshNetwork(), peer:GetAnnouncementServerTime()
		for _, name in ipairs({ "Hub-Realm", "Alternate-Realm" }) do
			s.neighbors[name] = { name = name, session = "native", sharedDelivery = true, expires = peer.now + 180 }
		end
		local first = {
			id = "a",
			destination = "A-Realm",
			zone = 12,
			upstream = "Hub-Realm",
			expiresAt = wall + 120,
			downstreams = {},
			alternates = {},
		}
		local second = {
			id = "b",
			destination = "B-Realm",
			zone = 12,
			upstream = "Hub-Realm",
			expiresAt = wall + 120,
			downstreams = {},
			alternates = { ["Alternate-Realm"] = true },
		}
		s.interests["A-Realm:a"], s.interests["B-Realm:b"] = first, second
		local sends, queued, completions = {}, nil, 0
		function peer:SendMeshPublicationToPeer(_, target, meta, options)
			sends[#sends + 1] = { target = target, destination = meta.destination }
			if #sends == 1 then
				queued = options
				if scenario == "alternate" then
					options.onComplete(false, "unacknowledged")
				end
			else
				options.onComplete(true, "acknowledged")
			end
			return true
		end
		local publication = {
			origin = peer.name,
			session = "source",
			id = "one",
			digest = "digest",
			scope = 12,
			expiresAt = wall + 120,
		}
		assert(peer:ForwardMeshPublication(publication, {
			onComplete = function(ok)
				assert(ok)
				completions = completions + 1
			end,
		}))
		if scenario == "retired" then
			s.interests["A-Realm:a"] = nil
			assert(not queued.isCurrent())
			queued.onComplete(false, "cancelled")
		end
		assert(#sends == 2 and sends[2].destination == "B-Realm" and completions == 1)
		assert(sends[2].target == (scenario == "alternate" and "Alternate-Realm" or "Hub-Realm"))
		if scenario == "alternate" then
			assert(
				not peer:HasDeliveredMeshPublicationForInterest(publication, first),
				"an alternate used for B must not claim delivery on A's failed common hop"
			)
			second.upstream = "Alternate-Realm"
		end
		assert(peer:HasDeliveredMeshPublicationForInterest(publication, second))
		queued.onComplete(true, "late")
		assert(completions == 1 and not next(s.pendingPublications))
	end
end, { offline = true })

QT:RegisterTest("mesh failed provisional interests cannot suppress unrelated subscriber demand", function()
	local net = QT:CreateTestNetwork({ now = 10000 })
	local peer = Peer(net, "Bridge-Realm")
	net:StartPeer(peer)
	local s = peer:InitializeMeshNetwork()
	s.nextDirectory, s.nextGuild, s.nextContacts, s.nextHandshake = math.huge, math.huge, math.huge, math.huge
	peer.geographicCommsState = { currentZone = 12, viewZone = 12 }
	for _, name in ipairs({ "Upstream-Realm", "Downstream-Realm" }) do
		s.neighbors[name] = { name = name, session = "native", sharedDelivery = true, expires = peer.now + 1000 }
	end
	function peer:Emit(operation, _, _, options)
		if operation == "MINT" then
			options.onStarted()
			options.onComplete(false, "expired")
		end
		return true
	end
	for _, elapsed in ipairs({ 0, 2, 4 }) do
		net.now, peer.now = net.now + elapsed, peer.now + elapsed
		peer:UpdateMeshNetwork(peer.now)
	end
	local localLease = s.localInterests[12]
	for _, job in pairs(localLease.interestSends) do
		assert(job.attempts == 3 and job.done)
	end
	assert(next(localLease.downstreams), "provisional route claims remain available to a possible late valid response")
	assert(not next(localLease.coveredDownstreams or {}))
	local request = {
		leaseId = "foreign",
		destination = "Viewer-Realm",
		zone = 12,
		expiresAt = peer:GetAnnouncementServerTime() + 120,
		hops = 8,
	}
	assert(peer:HandleMeshInterest(request, "Upstream-Realm", { distribution = "WHISPER", session = "native" }))
	assert(
		not s.interests["Viewer-Realm:foreign"].aggregated,
		"three failed sends provide no completed local coverage for another subscriber"
	)
end, { offline = true })

QT:RegisterTest("mesh bootstrap fills spare capacity faster and yields acceleration under pressure", function()
	local counts = {}
	for _, pressured in ipairs({ false, true }) do
		local net = QT:CreateTestNetwork({ fps = 10, now = 10000 })
		local peer = Peer(net, "Bootstrap-Realm")
		peer.UpdatePlayerCommunications = function() end
		peer.API.GetNumDisplayChannels = function()
			return 0
		end
		peer.API.Random = function(low)
			return low
		end
		net:StartPeer(peer)
		peer:InitializeMeshNetwork()
		local metrics = peer.GetTransportMetrics
		if pressured then
			function peer:GetTransportMetrics()
				return { queuedPackets = 8, oldestAge = 5, packetRate = 4 }
			end
		end
		function peer:Request(operation, _, routes, options)
			assert(operation == "MHEL")
			assert(
				options.onResponse(
					{ protocol = 3, capabilities = "mesh1", admitted = true, peers = {}, requestId = "bootstrap" },
					routes[1].target,
					{ distribution = "WHISPER", session = "remote-session" }
				)
			)
			return true, "queued", nil, "bootstrap"
		end
		for index = 1, 20 do
			peer:RememberMeshCandidate("Candidate" .. index .. "-Realm", "directory")
		end
		for _ = 1, 32 do
			net:Advance(1)
			assert(peer:GetMeshNetworkMetrics().handshakes <= 3)
		end
		local measured = metrics(peer)
		assert((measured.meshPackets or 0) <= 32 * 2 + 2 and (measured.meshBytes or 0) <= 32 * 400 + 400)
		counts[pressured and "busy" or "idle"] = peer:GetMeshNetworkMetrics().handshakesStarted or 0
	end
	assert(
		counts.idle >= 6 and counts.busy <= 4,
		"underfilled discovery must accelerate only with spare capacity, not change the shared budget: idle="
			.. counts.idle
			.. " busy="
			.. counts.busy
	)
end, { offline = true })

QT:RegisterTest("mesh early interests wait for correlated native session confirmation", function()
	for _, sameSession in ipairs({ true, false }) do
		local net = QT:CreateTestNetwork({ now = 10000 })
		local peer = Peer(net, "Receiver-Realm")
		peer.UpdatePlayerCommunications = function() end
		peer.API.GetNumDisplayChannels = function()
			return 0
		end
		net:StartPeer(peer)
		local state = peer:InitializeMeshNetwork()
		state.metrics.handshakesStarted, state.nextHandshake = 3, peer.now + 30
		peer.Respond = function()
			return true
		end
		local challenge
		function peer:Request(_, _, _, options)
			challenge = options
			return true, "queued", nil, "reciprocal"
		end
		assert(
			peer:HandleMeshHello(
				{ protocol = 3, capabilities = "mesh1", requestId = "hello" },
				"Sender-Realm",
				{ distribution = "WHISPER", session = "old-session" }
			)
		)
		assert(state.nextHandshake <= peer.now + 1, "a reserved reciprocal caller must not wait for a generic probe")
		local record = {
			leaseId = "early-interest",
			destination = "Sender-Realm",
			zone = 12,
			expiresAt = peer:GetAnnouncementServerTime() + 120,
			hops = 8,
		}
		assert(peer:HandleMeshInterest(record, "Sender-Realm", { distribution = "WHISPER", session = "old-session" }))
		for index = 2, 4 do
			local extra = {
				leaseId = "early" .. index,
				destination = "Sender-Realm",
				zone = 10 + index,
				expiresAt = record.expiresAt,
				hops = 8,
			}
			assert(
				peer:HandleMeshInterest(extra, "Sender-Realm", { distribution = "WHISPER", session = "old-session" })
					== (index <= 3),
				"unconfirmed control storage must stay bounded"
			)
		end
		assert(Count(state.interests) == 0 and not peer:IsConfirmedMeshNeighbor("Sender-Realm"))
		peer:UpdateMeshNetwork(peer.now)
		assert(
			challenge
				and challenge.onResponse(
					{ protocol = 3, capabilities = "mesh1", admitted = true, requestId = "reciprocal", peers = {} },
					"Sender-Realm",
					{
						distribution = "WHISPER",
						session = sameSession and "old-session" or "new-session",
					}
				)
		)
		assert(peer:IsConfirmedMeshNeighbor("Sender-Realm") and not state.pendingInterests["Sender-Realm"])
		assert(
			Count(state.interests) == (sameSession and 3 or 0),
			"early routing control must not cross a remote reload before the challenge completes"
		)
	end
end, { offline = true })

QT:RegisterTest("mesh interest renewals share audience fairness without evicting live reverse paths", function()
	local net = QT:CreateTestNetwork({ now = 10000 })
	local peer = Peer(net, "Relay-Realm")
	local state = peer:InitializeMeshNetwork()
	state.neighbors["Upstream-Realm"] = { name = "Upstream-Realm", expires = peer.now + 1000 }
	peer.Emit = function()
		return true
	end
	local old
	for audience = 1, 8 do
		for generation = 1, 3 do
			local record = {
				leaseId = "query" .. audience .. "x" .. generation,
				destination = "Viewer" .. audience .. "-Realm",
				zone = 12,
				expiresAt = peer:GetAnnouncementServerTime() + 120,
				hops = 8,
			}
			assert(peer:HandleMeshInterest(record, "Upstream-Realm", { distribution = "WHISPER" }))
			if not old then
				old = state.interests[record.destination .. ":" .. record.leaseId]
			end
		end
	end
	assert(Count(state.interests) == 24 and state.interests[old.destination .. ":" .. old.id] == old)
	for _, record in ipairs({
		{ leaseId = "fourth", destination = "Viewer1-Realm" },
		{ leaseId = "ninth", destination = "Viewer9-Realm" },
	}) do
		record.zone, record.hops, record.expiresAt = 12, 8, peer:GetAnnouncementServerTime() + 120
		assert(not peer:HandleMeshInterest(record, "Upstream-Realm", { distribution = "WHISPER" }))
	end
	state.neighbors["Other-Realm"] = { name = "Other-Realm", expires = peer.now + 1000 }
	for audience = 9, 17 do
		local record = {
			leaseId = "other" .. audience,
			destination = "Viewer" .. audience .. "-Realm",
			zone = 12,
			hops = 8,
			expiresAt = peer:GetAnnouncementServerTime() + 120,
		}
		assert(peer:HandleMeshInterest(record, "Other-Realm", { distribution = "WHISPER" }) == (audience <= 16))
	end
	assert(Count(state.interests) == 32, "renewal accounting must preserve the aggregate lease bound")
end, { offline = true })

QT:RegisterTest("mesh cached replay targets only its live subscribed reverse path and remaining hops", function()
	local peer = Peer(QT:CreateTestNetwork({ now = 10000 }), "Relay-Realm")
	local state = peer:InitializeMeshNetwork()
	local selected
	for index, name in ipairs({ "Upstream-Realm", "Other-Realm" }) do
		state.neighbors[name] = { name = name, expires = peer.now + 1000 }
		local lease = {
			id = "lease" .. index,
			destination = "Viewer" .. index .. "-Realm",
			zone = 12,
			upstream = name,
			expiresAt = peer:GetAnnouncementServerTime() + 120,
			downstreams = {},
			alternates = {},
		}
		state.interests[lease.destination .. ":" .. lease.id] = lease
		if index == 1 then
			selected = lease
		end
	end
	local sends = {}
	function peer:SendMeshPublicationToPeer(_, target, metadata, options)
		sends[#sends + 1] = { target = target, metadata = metadata, options = options }
		return true, "queued"
	end
	local publication = {
		origin = "Owner-Realm",
		session = "owner-session",
		id = "42",
		scope = 12,
		digest = "digest",
		expiresAt = peer:GetAnnouncementServerTime() + 120,
	}
	assert(peer:ForwardMeshPublication(publication, { meshInterest = selected, meshReplayHops = 3 }))
	assert(#sends == 1 and sends[1].target == "Upstream-Realm" and sends[1].metadata.hops == 3)
	assert(sends[1].options.isCurrent())
	state.interests[selected.destination .. ":" .. selected.id] = nil
	assert(not sends[1].options.isCurrent(), "retired lease objects must cancel queued cached delivery")
	assert(not peer:ForwardMeshPublication(publication, { meshInterest = selected, meshReplayHops = 3 }))
	state.interests[selected.destination .. ":" .. selected.id] = selected
	assert(not peer:ForwardMeshPublication(publication, { meshInterest = selected, meshReplayHops = 0 }))
	assert(not peer:ForwardMeshPublication(publication, { meshInterest = selected }))
	assert(#sends == 1, "a foreign cached publication cannot restart its hop budget")
end, { offline = true })

QT:RegisterTest("mesh observed contacts connect disjoint directories only after native verification", function()
	for _, source in ipairs({ "friend", "bnet", "chat", "visible" }) do
		local net = QT:CreateTestNetwork({ fps = 20, latency = 0.03 })
		local alice = Peer(net, "Alice-Realm", { backingRealm = "IslandA", mapID = 12 })
		local bob = Peer(net, "Bob-Realm", { backingRealm = "IslandB", mapID = 12 })
		if source == "friend" then
			alice.API.GetMeshFriendCount = function()
				return 1
			end
			alice.API.GetMeshFriendName = function(index)
				assert(index == 1)
				return bob.name
			end
		elseif source == "bnet" then
			alice.API.GetMeshBattleNetFriendCount = function()
				return 1
			end
			alice.API.GetMeshBattleNetGameAccountCount = function(index)
				assert(index == 1)
				return 3
			end
			alice.API.GetMeshBattleNetFriendName = function(friendIndex, accountIndex)
				assert(friendIndex == 1)
				-- The account adapter returns nil for offline/incompatible accounts.
				return accountIndex == 3 and bob.name or nil
			end
		end
		net:StartPeer(alice)
		net:StartPeer(bob)
		local state = alice:InitializeMeshNetwork()
		if source == "chat" then
			alice:CHAT_MSG_SAY("CHAT_MSG_SAY", "SomeoneElse-Realm", bob.name)
		elseif source == "visible" then
			alice.API.GetMeshUnitPlayerName = function(unit)
				assert(unit == "nameplate1")
				return bob.name
			end
			alice:NAME_PLATE_UNIT_ADDED("NAME_PLATE_UNIT_ADDED", "nameplate1")
		end
		assert(
			Count(state.neighbors) == 0 and #alice.attempts == 0,
			"an observation must not authenticate a player or send outside the paced coordinator"
		)
		assert(not alice:GetPlayerLocationState().peers[bob.name], "an address hint is not a location")
		net:Advance(40)
		assert(
			alice:IsConfirmedMeshNeighbor(bob.name) and bob:IsConfirmedMeshNeighbor(alice.name),
			"a " .. source .. " contact should bridge disjoint directories through reciprocal challenges"
		)
		assert(not state.candidates["SomeoneElse-Realm"], "chat contents must not become discovery addresses")
		local delivered = 0
		function bob:HandleQTMeshChat(data, sender, context)
			assert(sender == alice.name and context.meshVerified and data.text == "Contact bridge")
			delivered = delivered + 1
			return true
		end
		assert(
			alice:Emit(
				"QTCHAT",
				{ text = "Contact bridge" },
				{ { distribution = "MESH", scope = 12 } },
				{ owner = alice, expires = alice.now + 60 }
			)
		)
		net:Advance(30)
		assert(delivered == 1, "a discovered connection must carry authenticated public records")
		NoChannels(net)
	end
end, { offline = true })

QT:RegisterTest(
	"mesh established neighborhoods discover retried contacts despite continuous new chat candidates",
	function()
		local net = QT:CreateTestNetwork({ fps = 5, now = 10000 })
		local peers = {
			Peer(net, "Owner-Realm", { backingRealm = "IslandA" }),
			Peer(net, "Friend-Realm", { backingRealm = "IslandB" }),
		}
		local probes, deadlines = { 0, 0 }, {}
		for index, peer in ipairs(peers) do
			-- Isolate discovery from unrelated quest/location producers. Existing
			-- neighbor records model active connections; no complete directory or
			-- preverified friend edge is handed to either coordinator.
			peer.UpdatePlayerCommunications = function() end
			peer.API.GetNumDisplayChannels = function()
				return 0
			end
			peer.API.GetChannelRosterInfo = function() end
			net:StartPeer(peer)
			local state = peer:InitializeMeshNetwork()
			for slot = 1, 8 do
				local name = "Existing" .. index .. "x" .. slot .. "-Realm"
				state.neighbors[name] = {
					name = name,
					expires = peer.now + 10000,
					at = peer.now + 10000,
					connectedAt = peer.now,
				}
			end
			local other = peers[3 - index].name
			assert(peer:ObserveMeshContact(other, "friend"))
			local candidate = state.candidates[other]
			deadlines[index] = peer.now + 60
			candidate.triedAt, candidate.retryAt, candidate.delay = peer.now - 400, deadlines[index], 300
			state.metrics.handshakesStarted = 3
			local request = peer.Request
			function peer:Request(operation, data, routes, options)
				if operation == "MHEL" and routes[1].target == other then
					assert(self.now >= deadlines[index], "a fresh observation must not bypass active backoff")
					probes[index] = probes[index] + 1
				end
				return request(self, operation, data, routes, options)
			end
		end
		local delivered, submitted, receiver = 0, false, peers[2]
		function receiver:HandleQTMeshChat(data, sender, context)
			assert(sender == peers[1].name and context.meshVerified and data.text == "Busy neighborhood bridge")
			delivered = delivered + 1
			return true
		end
		for second = 1, 360 do
			for index, peer in ipairs(peers) do
				assert(peer:ObserveMeshContact(peers[3 - index].name, "friend"))
				peer:ObserveMeshContact("Chat" .. index .. "x" .. second .. "-Realm", "chat")
			end
			net:Advance(1)
			for _, peer in ipairs(peers) do
				local metrics = peer:GetMeshNetworkMetrics()
				assert(metrics.neighbors <= 8 and metrics.candidates <= 512 and metrics.handshakes <= 3)
				local transport = peer:GetTransportMetrics()
				assert(
					(transport.meshPackets or 0) <= second * 2 + 2 and (transport.meshBytes or 0) <= second * 400 + 400
				)
			end
			if
				not submitted
				and peers[1]:IsConfirmedMeshNeighbor(peers[2].name)
				and peers[2]:IsConfirmedMeshNeighbor(peers[1].name)
				and Count(peers[1].meshNetworkState.interests) > 0
			then
				assert(
					peers[1]:Emit(
						"QTCHAT",
						{ text = "Busy neighborhood bridge" },
						{ { distribution = "MESH", scope = "global" } },
						{ owner = peers[1], expires = peers[1].now + 60 }
					)
				)
				submitted = true
			end
			if delivered > 0 then
				break
			end
		end
		assert(probes[1] > 0 and probes[2] > 0, "never-tried strangers must not starve an eligible observed contact")
		assert(delivered == 1, "discovery must lead to authenticated public delivery, not just candidate admission")
		NoChannels(net)
	end,
	{ offline = true }
)

QT:RegisterTest("mesh passive contact bursts preserve failed probes and bounded candidate memory", function()
	local net = QT:CreateTestNetwork()
	local peer = Peer(net, "Owner-Realm")
	net:StartPeer(peer)
	local state = peer:InitializeMeshNetwork()
	assert(peer:ObserveMeshContact("Busy-Realm", "chat"))
	local failed = state.candidates["Busy-Realm"]
	failed.retryAt, failed.delay, failed.triedAt = peer.now + 300, 300, peer.now
	for index = 1, 1000 do
		peer:ObserveMeshContact("Busy-Realm", "visible", 12)
		peer:ObserveMeshContact("Crowd" .. index .. "-Realm", "chat")
	end
	assert(Count(state.candidates) <= 16, "a chat/visibility burst must have bounded admission")
	assert(
		failed.retryAt == peer.now + 300 and failed.delay == 300 and failed.triedAt == peer.now,
		"seeing an unavailable player again must not defeat handshake backoff"
	)
	assert(
		Count(state.neighbors) == 0 and #peer.attempts == 0,
		"passive events must neither bypass authentication nor send directly"
	)
	peer.now = peer.now + 11
	assert(peer:ObserveMeshContact("Later-Realm", "chat"), "the event budget must recover under runtime time")
	for index = 1, 512 do
		peer:RememberMeshCandidate("Stored" .. index .. "-Realm", "directory")
	end
	assert(Count(state.candidates) == 512)
	for _, candidate in pairs(state.candidates) do
		candidate.triedAt, candidate.retryAt, candidate.delay = peer.now, peer.now + 300, 300
	end
	local retained = {}
	local position = 0
	for name, candidate in pairs(state.candidates) do
		position = position + 1
		if position % 2 == 0 then
			-- A failed reservation can back off before a handshake was sent.
			candidate.triedAt = nil
		end
		retained[name] = candidate
	end
	peer.now = peer.now + 11
	for index = 1, 1000 do
		peer:ObserveMeshContact("Overflow" .. index .. "-Realm", "chat")
	end
	for index = 1, 32 do
		assert(not peer:RememberMeshCandidate("DirectoryPressure" .. index .. "-Realm", "directory"))
		assert(not peer:RememberMeshCandidate("GuildPressure" .. index .. "-Realm", "guild"))
	end
	assert(Count(state.candidates) == 512)
	for name, candidate in pairs(retained) do
		assert(
			state.candidates[name] == candidate and candidate.retryAt == peer.now - 11 + 300,
			"discovery pressure must not evict backed-off candidates and reset their failure history"
		)
	end
	peer.now = peer.now + 301
	for _, candidate in pairs(state.candidates) do
		candidate.source, candidate.contactAt, candidate.triedAt = "friend", peer.now - 301, peer.now - 301
	end
	assert(
		peer:ObserveMeshContact("NewFriend-Realm", "friend"),
		"an expired passive-only pool must make room for a newly observed friend"
	)
	assert(
		state.candidates["NewFriend-Realm"] and Count(state.candidates) == 512,
		"replacing an expired contact must retain the shared candidate ceiling"
	)
end, { offline = true })

QT:RegisterTest("mesh contact events accept native addresses only within the current enabled lifetime", function()
	local net = QT:CreateTestNetwork()
	local peer = Peer(net, "Owner-Realm")
	net:StartPeer(peer)
	local state = peer:InitializeMeshNetwork()
	peer.ignored["Ignored-Realm"] = true
	for _, name in ipairs({ "Ignored-Realm", peer.name, "Bad:Identity", "Bad|Identity", "" }) do
		assert(not peer:ObserveMeshContact(name, "chat"))
	end
	local opaque = {}
	local canAccess = peer.CanAccessValue
	function peer:CanAccessValue(value)
		return value ~= opaque and canAccess(self, value)
	end
	peer:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "Body-Realm", opaque)
	assert(Count(state.candidates) == 0, "inaccessible sender data must not enter the graph")
	local samples = 0
	peer.API.GetMeshUnitPlayerName = function()
		samples = samples + 1
		return "Visible-Realm"
	end
	peer.isEnabled = false
	peer:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "Body-Realm", "Disabled-Realm")
	peer:UPDATE_MOUSEOVER_UNIT("UPDATE_MOUSEOVER_UNIT")
	assert(samples == 0 and Count(state.candidates) == 0)
	peer.isEnabled, peer.restricted = true, true
	assert(not peer:ObserveMeshContact("Restricted-Realm", "friend"))
	peer.restricted, peer.isLoggingOut = false, true
	assert(not peer:ObserveMeshContact("Leaving-Realm", "bnet"))
	peer.isLoggingOut = false
	peer.db.profile = {}
	assert(not peer:ObserveMeshContact("OldProfile-Realm", "chat"))
	assert(Count(state.candidates) == 0, "a stale profile lifetime must stay retired")
	peer:ResetMeshNetwork()
	peer:PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED")
	peer:CHAT_MSG_CHANNEL("CHAT_MSG_CHANNEL", "Body-Realm", "AfterReset-Realm")
	assert(peer.meshNetworkState == nil and samples == 0, "late events must not recreate a retired mesh")
end, { offline = true })

QT:RegisterTest("mesh contact roster scans share the row budget and coalesce friend-list events", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local peer = Peer(net, "Owner-Realm")
	local rowsAt, starts, contactRows, maximumAccount = {}, {}, 0, 0
	local function Read(contact)
		rowsAt[peer.now] = (rowsAt[peer.now] or 0) + 1
		if contact then
			contactRows = contactRows + 1
		end
		assert(rowsAt[peer.now] <= 32, "directory, guild and contact reads must share one paced row budget")
	end
	local channelRead = peer.API.GetChannelRosterInfo
	peer.API.GetChannelRosterInfo = function(...)
		Read(false)
		return channelRead(...)
	end
	local directory = {}
	for index = 1, 100 do
		directory[index] = "Directory" .. index .. "-Realm"
	end
	net:SetChannelDirectory(peer, "QuestTogether", directory)
	peer.API.GetNumGuildMembers = function()
		return 100
	end
	peer.API.GetGuildRosterInfo = function()
		Read(false)
	end
	peer.API.GetMeshFriendCount = function()
		starts[#starts + 1] = peer.now
		return 1300
	end
	peer.API.GetMeshFriendName = function()
		Read(true)
	end
	peer.API.GetMeshBattleNetFriendCount = function()
		return 1000
	end
	peer.API.GetMeshBattleNetGameAccountCount = function()
		Read(true)
		return 1000
	end
	peer.API.GetMeshBattleNetFriendName = function(_, index)
		Read(true)
		maximumAccount = math.max(maximumAccount, index)
	end
	net:StartPeer(peer)
	net:Advance(30)
	assert(#starts == 1 and contactRows == 1500, "one contact cycle must stop at its bounded row limit")
	assert(maximumAccount == 5, "a friend with many game accounts must not monopolize roster processing")
	for _ = 1, 1000 do
		peer:FRIENDLIST_UPDATE("FRIENDLIST_UPDATE")
		peer:BN_FRIEND_INFO_CHANGED("BN_FRIEND_INFO_CHANGED", 1)
	end
	net:Advance(5)
	assert(
		#starts == 2 and starts[2] - starts[1] >= 30,
		"friend-list event bursts must schedule one throttled refresh, not restart a scan for every event"
	)
	peer:ResetMeshNetwork()
	peer:FRIENDLIST_UPDATE("FRIENDLIST_UPDATE")
	assert(peer.meshNetworkState == nil, "a roster event after reset must not restart the old lifetime")
end, { offline = true })

QT:RegisterTest("mesh bootstrap uses asynchronous directory rows and correlated native whispers", function()
	local net = QT:CreateTestNetwork({ fps = 20, directoryDelay = 1, latency = 0.03 })
	local alice, bob = Peer(net, "Alice-Realm"), Peer(net, "Bob-Realm")
	net:StartPeer(alice)
	net:StartPeer(bob)
	net:Advance(35)
	assert(
		alice.meshNetworkState.neighbors[bob.name] and bob.meshNetworkState.neighbors[alice.name],
		"directory candidates must complete reciprocal challenges"
	)
	assert(alice:GetMeshNetworkMetrics().directoryRows >= 2)
	assert(
		alice.selectedDisplayChannel == 1 and bob.selectedDisplayChannel == 1,
		"background roster refresh must restore the player's channel selection"
	)
	assert(Count(alice.meshNetworkState.interests) > 0, "confirmed peers must propagate scoped interest")
	assert(
		alice.db.global.meshPeerSeeds["test:US:realm:Alice-Realm"][bob.name],
		"confirmed addresses persist per character"
	)
	NoChannels(net)
end, { offline = true })

QT:RegisterTest("mesh saved seeds are bounded addresses isolated by character and client namespace", function()
	local net = QT:CreateTestNetwork()
	local peer = Peer(net, "Owner-Realm")
	local wall = peer:GetAnnouncementServerTime()
	local seeds, other = {}, { ["OtherCharacter-Realm"] = wall }
	for index = 1, 100 do
		seeds["Seed" .. index .. "-Realm"] = wall
	end
	seeds["Expired-Realm"], seeds["Future-Realm"], seeds["Bad:Identity"] = wall - 86401, wall + 1, wall
	peer.db.global.meshPeerSeeds = {
		["test:US:realm:Owner-Realm"] = seeds,
		["test:US:realm:Other-Realm"] = other,
		["test:EU:realm:Owner-Realm"] = { ["OtherRegion-Realm"] = wall },
	}
	local state = peer:InitializeMeshNetwork()
	assert(Count(seeds) == 64 and Count(state.candidates) == 64)
	assert(Count(state.neighbors) == 0, "a saved address must still pass the native challenge")
	assert(
		not state.candidates["Expired-Realm"]
			and not state.candidates["OtherCharacter-Realm"]
			and not state.candidates["OtherRegion-Realm"]
	)
	assert(
		peer.db.global.meshPeerSeeds["test:US:realm:Other-Realm"] == other,
		"local cleanup must preserve another character's independently scoped seeds"
	)
end, { offline = true })

QT:RegisterTest("mesh directory refresh never mistakes a shifted display row for a QT directory", function()
	local net = QT:CreateTestNetwork({ fps = 20, directoryDelay = 1 })
	local peer = Peer(net, "Owner-Realm")
	net:SetChannelDirectory(peer, "AAA", { "Unrelated-Realm" })
	net:StartPeer(peer)
	net:Advance(2.4)
	assert(peer.meshNetworkState.directory and peer.meshNetworkState.directory.selectedName == "QuestTogether")
	-- A simultaneous unrelated channel join shifts the directory's display
	-- index before the asynchronous names arrive.
	net:Join(peer, "AAA", true)
	net:Advance(10)
	assert(
		not peer.meshNetworkState.candidates["Unrelated-Realm"],
		"a changed display index cannot authorize unrelated roster reads"
	)
	assert(not peer.meshNetworkState.directory, "the displaced scan must yield until a fresh selection")
end, { offline = true })

QT:RegisterTest("mesh directory waits for names after count and avoids selecting channel headers", function()
	local net = QT:CreateTestNetwork({ fps = 20, directoryDelay = 5 })
	local peer = Peer(net, "Owner-Realm")
	net:SetChannelDirectory(peer, "QuestTogether", { "Ready-Realm" })
	local info, selectChannel = peer.API.GetChannelDisplayInfo, peer.API.SetSelectedDisplayChannel
	local selected = {}
	peer.API.GetChannelDisplayInfo = function(index)
		local name, header, collapsed, id, count, active = info(index)
		if name == "QuestTogether" then
			count = 1
		else
			header = true
		end
		return name, header, collapsed, id, count, active
	end
	peer.API.SetSelectedDisplayChannel = function(index)
		local _, header = peer.API.GetChannelDisplayInfo(index)
		assert(not header, "a native header is not a selectable roster refresh target")
		selected[#selected + 1] = index
		return selectChannel(index)
	end
	net:StartPeer(peer)
	net:Advance(6)
	assert(
		not peer.meshNetworkState.candidates["Ready-Realm"],
		"a count must not manufacture a peer before names arrive"
	)
	net:Advance(3)
	assert(
		peer.meshNetworkState.candidates["Ready-Realm"],
		"the scan must retain the row while asynchronous names are pending"
	)
	assert(#selected > 0)
end, { offline = true })

QT:RegisterTest("mesh capacity pressure rotates admitted destinations instead of favoring table order", function()
	local net = QT:CreateTestNetwork()
	local peer = Peer(net, "Owner-Realm")
	net:StartPeer(peer)
	local s, wall = peer:InitializeMeshNetwork(), peer:GetAnnouncementServerTime()
	for _, name in ipairs({ "Alice-Realm", "Bob-Realm" }) do
		s.neighbors[name] = { name = name, expires = peer.now + 180 }
		s.interests[name .. ":lease"] = {
			id = "lease",
			destination = name,
			zone = 12,
			upstream = name,
			expiresAt = wall + 120,
			downstreams = {},
			alternates = {},
		}
	end
	local admitted, first = nil, nil
	function peer:SendMeshPublicationToPeer(_, target, _, options)
		if admitted then
			options.onComplete(false, "capacity")
			return false, "capacity"
		end
		admitted = target
		options.onComplete(true, "acknowledged")
		return true
	end
	for index = 1, 2 do
		admitted = nil
		assert(peer:ForwardMeshPublication({
			origin = peer.name,
			session = "s",
			id = tostring(index),
			digest = "d",
			scope = 12,
			expiresAt = wall + 30,
		}, {}))
		if first then
			assert(admitted ~= first, "the previously capacity-blocked destination must get the next opening")
		else
			first = admitted
		end
	end
end, { offline = true })

QT:RegisterTest("mesh scoped public data crosses an intermediate peer only after direct owner confirmation", function()
	local net = QT:CreateTestNetwork({ fps = 20, latency = 0.02, seed = 29 })
	local alice, bridge, carol =
		Peer(net, "Alice-Realm", { mapID = 12 }),
		Peer(net, "Bridge-Realm", { mapID = 99 }),
		Peer(net, "Carol-Realm", { mapID = 12 })
	local confirmations, delivered = 0, {}
	net.deliveryRule = function(packet, receiver)
		local frame = alice:DecodeCommFrame(packet.wire)
		if
			frame
			and (frame.operation == "MHEL" or frame.operation == "MACK")
			and (
				(packet.sender == alice.name and receiver == carol)
				or (packet.sender == carol.name and receiver == alice)
			)
		then
			return { drop = true }
		end
		if frame and frame.operation == "MAUTH" and packet.sender == carol.name and receiver == alice then
			confirmations = confirmations + 1
		end
	end
	for _, peer in ipairs({ alice, bridge, carol }) do
		function peer:HandleQTMeshChat(data, sender, context)
			if data.text == "Scoped public announcement" then
				delivered[self.name] = (delivered[self.name] or 0) + 1
				assert(sender == alice.name and context.meshVerified, "relays must preserve verified origin")
			end
			return true
		end
		net:StartPeer(peer)
	end
	net:Advance(45)
	assert(alice.meshNetworkState.neighbors[bridge.name] and carol.meshNetworkState.neighbors[bridge.name])
	assert(not alice.meshNetworkState.neighbors[carol.name], "test topology must require an intermediate carrier")
	local accepted = alice:Emit(
		"QTCHAT",
		{ text = "Scoped public announcement" },
		{ { distribution = "MESH", scope = 12 } },
		{ owner = alice, expires = alice.now + 60 }
	)
	assert(accepted)
	net:Advance(55)
	assert(delivered[carol.name] == 1, "a subscribed peer must receive the public record exactly once")
	assert(not delivered[bridge.name], "a bridge must not install data for an unviewed scope")
	assert(confirmations > 0, "a relayed record needs recipient-specific confirmation from its native owner")
	NoChannels(net)
end, { offline = true })

QT:RegisterTest(
	"mesh candidate hints cannot install neighbors and delayed challenges cannot revive a lifetime",
	function()
		local net = QT:CreateTestNetwork({ fps = 20 })
		local alice, bob = Peer(net, "Alice-Realm"), Peer(net, "Bob-Realm")
		net:StartPeer(alice)
		net:StartPeer(bob)
		local s = alice:InitializeMeshNetwork()
		assert(
			alice:HandleMeshHello(
				{ requestId = "hint", version = "9", protocol = 3, capabilities = "mesh1" },
				bob.name,
				{ distribution = "WHISPER", session = "remote" }
			)
		)
		assert(s.candidates[bob.name] and not s.neighbors[bob.name], "unsolicited hello must remain an address hint")
		assert(
			not alice:HandleMeshHello(
				{ requestId = "legacy", protocol = 2, capabilities = "mesh1" },
				"Legacy-Realm",
				{ distribution = "WHISPER" }
			)
		)
		assert(not s.candidates["Legacy-Realm"])
		local callbacks
		function alice:Request(_, _, _, options)
			callbacks = options
			return true, "queued", {}, "pending"
		end
		alice:RememberMeshCandidate(bob.name, "directory")
		alice:UpdateMeshNetwork(alice.now + 2)
		assert(callbacks, "candidate should start one bounded challenge")
		alice.ignored[bob.name] = true
		assert(
			not callbacks.onResponse(
				{ requestId = "pending", protocol = 3, capabilities = "mesh1", admitted = true, peers = {} },
				bob.name,
				{ distribution = "WHISPER", session = "remote" }
			),
			"an already-running native callback cannot confirm a newly ignored peer"
		)
		assert(not s.neighbors[bob.name])
		alice.ignored[bob.name] = nil
		alice:ResetMeshNetwork()
		local replacement = alice:InitializeMeshNetwork()
		assert(
			not callbacks.onResponse(
				{ requestId = "pending", protocol = 3, capabilities = "mesh1", admitted = true, peers = {} },
				bob.name,
				{ distribution = "WHISPER", session = "remote" }
			)
		)
		assert(Count(replacement.neighbors) == 0, "old callbacks must not mutate the replacement graph")
		alice.ignored[bob.name] = true
		assert(not alice:RememberMeshCandidate(bob.name, "introduction"))
		alice:EndCommunicationSession()
		local joins = 0
		function alice:EnsureAnnouncementChannelJoined()
			joins = joins + 1
			return true
		end
		assert(not alice:EnsureMeshDirectoryJoined("QuestTogether"))
		assert(joins == 0, "a delayed directory callback cannot join after the communication lifetime ended")
	end,
	{ offline = true }
)

QT:RegisterTest("mesh accelerated discovery preserves failed-peer backoff and reservation bounds", function()
	local net = QT:CreateTestNetwork()
	local peer = Peer(net, "Owner-Realm")
	peer:InitializeCommunications()
	peer:InitializeMeshNetwork()
	peer.API.Random = function(minimum)
		return minimum
	end
	for index = 1, 12 do
		peer:RememberMeshCandidate("Candidate" .. index .. "-Realm", "directory")
	end
	local probes = {}
	function peer:Request(operation, _, _, options)
		assert(operation == "MHEL")
		probes[#probes + 1] = self.now
		options.onExpire()
		return false, "offline"
	end
	local began = peer.now
	for second = 1, 90 do
		peer.now = began + second
		peer:UpdateMeshNetwork(peer.now)
	end
	assert(#probes >= 9 and #probes <= 12, "spare capacity can probe new addresses without retrying failed ones")
	assert(probes[2] - probes[1] == 4 and probes[3] - probes[2] == 4)
	for index = 4, #probes do
		local gap = probes[index] - probes[index - 1]
		assert(gap >= 4, "failed submissions must not bypass the paced bootstrap interval")
	end
	for _, candidate in pairs(peer.meshNetworkState.candidates) do
		if candidate.triedAt then
			assert(candidate.retryAt >= candidate.triedAt + 300)
		end
	end
	assert(peer:GetMeshNetworkMetrics().handshakes == 0)
end, { offline = true })

QT:RegisterTest("mesh directory cycles rotate oversized roster rows and share the budget across directories", function()
	local net = QT:CreateTestNetwork({ fps = 5, directoryDelay = 0.5 })
	local peer = Peer(net, "Owner-Realm")
	local global, zone = {}, {}
	for index = 1, 2000 do
		global[index], zone[index] = "Global" .. index .. "-Realm", "Zone" .. index .. "-Realm"
	end
	net:SetChannelDirectory(peer, "QuestTogether", global)
	net:SetChannelDirectory(peer, "QuestTogether3Z12", zone)
	local getRow = peer.API.GetChannelRosterInfo
	local cycles, seen, frameReads, at = {}, {}, 0, nil
	peer.API.GetChannelRosterInfo = function(display, index)
		if at ~= net.now then
			at, frameReads = net.now, 0
		end
		frameReads = frameReads + 1
		assert(frameReads <= 32, "rotating samples retain the per-tick native read limit")
		local name = peer.API.GetChannelDisplayInfo(display)
		local number = peer:GetMeshNetworkMetrics().directoryScans
		local cycle = cycles[number] or { total = 0, first = name }
		cycles[number] = cycle
		cycle.total, cycle[name] = cycle.total + 1, (cycle[name] or 0) + 1
		seen[name] = seen[name] or {}
		seen[name][index] = true
		return getRow(display, index)
	end
	net:StartPeer(peer)
	net:Advance(640)
	assert(cycles[1] and cycles[2] and cycles[3])
	for index = 1, 3 do
		local cycle = cycles[index]
		assert(cycle.total == 1500, "crowded directories must share and fill the bounded refresh budget")
		assert(
			(cycle.QuestTogether or 0) > 0 and (cycle.QuestTogether3Z12 or 0) > 0,
			"a crowded first directory must not starve a later directory"
		)
	end
	assert(cycles[1].first ~= cycles[2].first, "the first directory must rotate each refresh")
	assert(
		seen.QuestTogether[1501] and seen.QuestTogether3Z12[1501],
		"later refreshes must discover rows beyond the first cycle's truncation"
	)
	assert(Count(peer.meshNetworkState.directoryCursors) <= 8)
	assert(peer:GetMeshNetworkMetrics().candidates <= 512)
	NoChannels(net)
end, { offline = true })

QT:RegisterTest("mesh directory sampling is bounded and yields to the visible channel window", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local alice = Peer(net, "Alice-Realm")
	local names = {}
	for i = 1, 1800 do
		names[i] = "Candidate" .. i .. "-Realm"
	end
	net:SetChannelDirectory(alice, "QuestTogether", names)
	alice.API.GetNumGuildMembers = function()
		return 50
	end
	alice.API.GetGuildRosterInfo = function(index)
		return "Guild" .. index .. "-Realm", index % 2 == 0
	end
	alice.channelWindowShown = true
	net:StartPeer(alice)
	net:Advance(10)
	assert((alice:GetMeshNetworkMetrics().directoryRows or 0) == 0 and alice.selectedDisplayChannel == 1)
	alice.channelWindowShown = false
	local previous = (alice:GetMeshNetworkMetrics().guildRows or 0)
	for _ = 1, 200 do
		net:Advance(0.1)
		local metrics = alice:GetMeshNetworkMetrics()
		local current = (metrics.directoryRows or 0) + (metrics.guildRows or 0)
		assert(current - previous <= 32, "one tick must not scan an unbounded directory")
		previous = current
	end
	local metrics = alice:GetMeshNetworkMetrics()
	assert(metrics.directoryRows > 512 and metrics.directoryRows <= 1500, "one directory cycle has a hard row budget")
	assert(metrics.guildRows == 50, "online guild rows can bootstrap without an unbounded roster refresh")
	assert(metrics.candidates <= 512 and metrics.handshakes <= 3)
	assert(alice.selectedDisplayChannel == 1)
	NoChannels(net)
end, { offline = true })

QT:RegisterTest("mesh reverse paths reject unsolicited scopes and retire publication work on map changes", function()
	local net = QT:CreateTestNetwork({ fps = 20, latency = 0.02 })
	local alice, bob = Peer(net, "Alice-Realm"), Peer(net, "Bob-Realm")
	net:StartPeer(alice)
	net:StartPeer(bob)
	net:Advance(35)
	local s = alice.meshNetworkState
	local lease = s.localInterests[12]
	assert(lease and lease.downstreams[bob.name], "current-map interest must be routed")
	local metadata = { leaseId = lease.id, destination = alice.name, zone = 12, hops = 8 }
	assert(alice:CanAcceptMeshPublicationRoute(bob.name, metadata, 12))
	assert(alice:ShouldConsumeMeshPublicationRoute(bob.name, metadata, 12))
	assert(not alice:CanAcceptMeshPublicationRoute("Stranger-Realm", metadata, 12))
	assert(not alice:CanAcceptMeshPublicationRoute(bob.name, metadata, 99))
	metadata.hops = 9
	assert(not alice:CanAcceptMeshPublicationRoute(bob.name, metadata, 12))
	metadata.hops = 8
	alice.mapID = 99
	alice.geographicCommsState.currentZone = 99
	alice.geographicCommsState.viewZone = nil
	alice:UpdateMeshNetwork(alice.now + 1)
	assert(
		not alice:CanAcceptMeshPublicationRoute(bob.name, metadata, 12),
		"retired map interest must reject delayed publications"
	)
	assert(lease.expiresAt == 0, "queued reverse-path work must lose its currentness fence")
end, { offline = true })

QT:RegisterTest("mesh unanswered candidates back off and public fanout completes once per immutable route", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local alice = Peer(net, "Alice-Realm")
	net:StartPeer(alice)
	local s = alice:InitializeMeshNetwork()
	alice:RememberMeshCandidate("Absent-Realm", "introduction")
	local callbacks
	function alice:Request(_, _, _, options)
		callbacks = options
		return true, "queued", {}, "pending"
	end
	alice:UpdateMeshNetwork(alice.now + 2)
	assert(callbacks)
	callbacks.onExpire()
	assert(s.candidates["Absent-Realm"].retryAt >= alice.now + 300, "unanswered candidates require five-minute backoff")
	local server = alice:GetAnnouncementServerTime()
	s.neighbors["Viewer-Realm"] = { name = "Viewer-Realm", expires = alice.now + 120 }
	s.interests["Viewer-Realm:lease"] = {
		id = "lease",
		destination = "Viewer-Realm",
		zone = 12,
		upstream = "Viewer-Realm",
		expiresAt = server + 120,
		downstreams = {},
	}
	local sends, completions, pending = 0, 0, nil
	function alice:SendMeshPublicationToPeer(_, target, metadata, options)
		assert(target == "Viewer-Realm" and metadata.hops == 8)
		sends = sends + 1
		pending = options.onComplete
		return true
	end
	local publication = {
		origin = alice.name,
		session = "session",
		id = "record",
		digest = "digest",
		scope = 12,
		expiresAt = server + 30,
	}
	local options = {
		onComplete = function(ok)
			assert(ok)
			completions = completions + 1
		end,
	}
	assert(alice:ForwardMeshPublication(publication, options))
	assert(alice:ForwardMeshPublication(publication, options))
	assert(sends == 1 and completions == 0, "pending duplicates must wait for remote completion")
	s.interests["Viewer-Realm:renewed"] = {
		id = "renewed",
		destination = "Viewer-Realm",
		zone = 12,
		upstream = "Viewer-Realm",
		expiresAt = server + 160,
		downstreams = {},
	}
	assert(alice:ForwardMeshPublication(publication, options))
	assert(
		sends == 1 and completions == 0,
		"renewed query must share the existing pending immutable destination transfer"
	)
	pending(true, "acknowledged")
	pending(false, "duplicate-callback")
	assert(sends == 1 and completions == 3, "each submission completes once while duplicate pending content sends once")
	assert(alice:GetMeshNetworkMetrics().pendingPublications == 0, "ACK must retire cross-query pending reservations")
	assert(alice:ForwardMeshPublication(publication, options))
	assert(
		sends == 1 and completions == 4,
		"a completed native destination receipt may satisfy overlapping renewal generations"
	)
	pending(true, "acknowledged")
	assert(alice:ForwardMeshPublication(publication, options))
	assert(sends == 1 and completions == 5, "completed duplicates remain suppressed during the original valid lease")
end, { offline = true })

QT:RegisterTest(
	"mesh immutable interests retain alternate paths without repeated flooding or lifetime extension",
	function()
		local net = QT:CreateTestNetwork()
		local peer = Peer(net, "Bridge-Realm")
		net:StartPeer(peer)
		local s, now = peer:InitializeMeshNetwork(), peer:GetAnnouncementServerTime()
		for _, name in ipairs({ "Left-Realm", "Right-Realm", "Downstream-Realm" }) do
			s.neighbors[name] = { name = name, expires = peer.now + 180 }
		end
		local sends = 0
		function peer:Emit(operation)
			if operation == "MINT" then
				sends = sends + 1
			end
			return true
		end
		local record =
			{ leaseId = "immutable", destination = "Viewer-Realm", zone = 12, expiresAt = now + 120, hops = 7 }
		assert(peer:HandleMeshInterest(record, "Left-Realm", { distribution = "WHISPER" }))
		local flooded = sends
		assert(peer:HandleMeshInterest(record, "Right-Realm", { distribution = "WHISPER" }))
		assert(sends == flooded, "a duplicate query can register a failover without flooding again")
		local lease = s.interests["Viewer-Realm:immutable"]
		assert(lease.alternates["Right-Realm"])
		record.expiresAt = record.expiresAt + 1
		assert(not peer:HandleMeshInterest(record, "Left-Realm", { distribution = "WHISPER" }))
		assert(lease.expiresAt == now + 120, "a replay cannot extend an immutable query's lifetime")
		local completed, destinations = 0, {}
		function peer:SendMeshPublicationToPeer(_, target, _, options)
			destinations[#destinations + 1] = target
			options.onComplete(target == "Right-Realm", target == "Right-Realm" and "acknowledged" or "unacknowledged")
			return true
		end
		assert(
			peer:ForwardMeshPublication(
				{ origin = peer.name, session = "s", id = "p", digest = "d", scope = 12, expiresAt = now + 30 },
				{
					onComplete = function(ok)
						assert(ok)
						completed = completed + 1
					end,
				}
			)
		)
		assert(
			destinations[1] == "Left-Realm" and destinations[2] == "Right-Realm" and completed == 1,
			"an unacknowledged publication must try its bounded alternate and complete once"
		)
		peer:RetireMeshPeer("Left-Realm")
		assert(lease.upstream == "Right-Realm" and s.interests["Viewer-Realm:immutable"] == lease)
	end,
	{ offline = true }
)

QT:RegisterTest("mesh missing remote completion retries an alternate native path", function()
	local net = QT:CreateTestNetwork({ fps = 15, latency = 0.02, seed = 63 })
	local viewer, left, right, owner =
		Peer(net, "Viewer-Realm", { mapID = 12 }),
		Peer(net, "Left-Realm", { mapID = 99 }),
		Peer(net, "Right-Realm", { mapID = 99 }),
		Peer(net, "Owner-Realm", { mapID = 12 })
	local blocked, deliveries, confirmations = nil, 0, 0
	local function Edge(a, b)
		return (a == viewer.name or a == owner.name) ~= (b == viewer.name or b == owner.name)
	end
	net.deliveryRule = function(packet, receiver)
		local frame = viewer:DecodeCommFrame(packet.wire)
		if not frame then
			return
		end
		if (frame.operation == "MHEL" or frame.operation == "MACK") and not Edge(packet.sender, receiver.name) then
			return { drop = true }
		end
		if blocked and packet.sender == owner.name and receiver.name == blocked and frame.operation == "MPUB" then
			return { drop = true }
		end
		if packet.sender == viewer.name and receiver == owner and frame.operation == "MAUTH" then
			confirmations = confirmations + 1
		end
	end
	function viewer:HandleQTMeshChat(data, sender)
		if data.text == "Alternate path" then
			assert(sender == owner.name)
			deliveries = deliveries + 1
		end
		return true
	end
	for _, peer in ipairs({ viewer, left, right, owner }) do
		net:StartPeer(peer)
	end
	net:Advance(70)
	local latest
	for _, lease in pairs(owner.meshNetworkState.interests) do
		if
			lease.destination == viewer.name
			and lease.zone == 12
			and (not latest or lease.expiresAt > latest.expiresAt)
		then
			latest = lease
		end
	end
	assert(latest and Count(latest.alternates) > 0, "the diamond must discover a bounded alternate reverse path")
	blocked = latest.upstream
	assert(
		owner:Emit(
			"QTCHAT",
			{ text = "Alternate path" },
			{ { distribution = "MESH", scope = 12 } },
			{ owner = owner, expires = owner.now + 90 }
		)
	)
	net:Advance(85)
	assert(
		(owner:GetMeshNetworkMetrics().publicationFailovers or 0) > 0,
		"accepted native sends without completion must fail over"
	)
	assert(
		deliveries == 1 and confirmations > 0,
		"alternate delivery must still authenticate the native owner exactly once: deliveries="
			.. deliveries
			.. " confirmations="
			.. confirmations
	)
	NoChannels(net)
end, { offline = true })

QT:RegisterTest("mesh publication routes bind the query scope as well as its destination", function()
	local net = QT:CreateTestNetwork()
	local peer = Peer(net, "Owner-Realm")
	net:StartPeer(peer)
	peer:UpdateMeshNetwork(peer.now)
	local state, sender = peer.meshNetworkState, "Relay-Realm"
	local lease = assert(state.localInterests[0])
	state.neighbors[sender] = { name = sender, expires = peer.now + 180 }
	lease.downstreams[sender] = true
	local metadata = { leaseId = lease.id, destination = peer.name, zone = 0, hops = 8 }
	assert(peer:CanAcceptMeshPublicationRoute(sender, metadata, "global", "Origin-Realm"))
	metadata.zone = 98765
	assert(
		not peer:CanAcceptMeshPublicationRoute(sender, metadata, 98765, "Origin-Realm"),
		"a global query must not authorize an unrelated zone publication"
	)
	assert(
		not peer:ShouldConsumeMeshPublicationRoute(sender, metadata, 98765, sender),
		"a native owner shortcut must preserve the query scope"
	)
end, { offline = true })

QT:RegisterTest("mesh full neighbors decline admission without creating unusable edges", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local full, newcomer = Peer(net, "Full-Realm"), Peer(net, "New-Realm")
	net:StartPeer(full)
	net:StartPeer(newcomer)
	local state = full:InitializeMeshNetwork()
	for index = 1, 8 do
		local name = "Existing" .. index .. "-Realm"
		state.neighbors[name] = { name = name, expires = full.now + 180, at = full.now, connectedAt = full.now }
	end
	newcomer:RememberMeshCandidate(full.name, "directory")
	net:Advance(35)
	assert(not newcomer:IsConfirmedMeshNeighbor(full.name) and not full:IsConfirmedMeshNeighbor(newcomer.name))
	assert((newcomer:GetMeshNetworkMetrics().handshakeBusy or 0) > 0)
	assert(
		(newcomer:GetMeshNetworkMetrics().handshakeTimeouts or 0) == 0,
		"an explicit busy reply is not a response timeout"
	)
	assert(newcomer.meshNetworkState.candidates[full.name].lastHandshakeOutcome == "busy")
	assert(
		newcomer.meshNetworkState.candidates[full.name].retryAt > newcomer.now,
		"an explicit capacity refusal must enter bounded backoff"
	)
	assert(
		not newcomer.meshNetworkState.candidates["Existing1-Realm"],
		"a declined admission must not add introductions"
	)
end, { offline = true })

QT:RegisterTest("mesh local reservation pressure waits without backing off an unprobed peer", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local owner, contact = Peer(net, "Owner-Realm"), Peer(net, "Contact-Realm")
	for _, peer in ipairs({ owner, contact }) do
		peer.UpdatePlayerCommunications = function() end
		peer.API.GetNumDisplayChannels = function()
			return 0
		end
		peer.API.GetChannelRosterInfo = function() end
		net:StartPeer(peer)
	end
	local state = owner:InitializeMeshNetwork()
	for slot = 1, 7 do
		local name = "Existing" .. slot .. "-Realm"
		state.neighbors[name] =
			{ name = name, expires = owner.now + 10000, at = owner.now + 10000, connectedAt = owner.now }
	end
	state.reservations["OtherProbe-Realm"] = { expires = owner.now + 10 }
	assert(owner:ObserveMeshContact(contact.name, "friend"))
	local candidate, due = state.candidates[contact.name], owner.now
	local probes, request = 0, owner.Request
	function owner:Request(operation, data, routes, options)
		if operation == "MHEL" and routes[1].target == contact.name then
			probes = probes + 1
		end
		return request(self, operation, data, routes, options)
	end
	net:Advance(5)
	assert(
		probes == 0 and candidate.triedAt == nil and candidate.retryAt == due and candidate.delay == nil,
		"local reservations must not create an attempted handshake or failed-peer cooldown"
	)
	assert(candidate.lastHandshakeOutcome == "local_capacity" and candidate.lastHandshakeAt <= owner.now)
	assert((owner:GetMeshNetworkMetrics().handshakeTimeouts or 0) == 0)
	net:Advance(35)
	assert(
		probes > 0 and owner:IsConfirmedMeshNeighbor(contact.name),
		"the eligible peer must be probed when the local slot becomes available"
	)
	assert(candidate.lastHandshakeOutcome == "confirmed")
end, { offline = true })

QT:RegisterTest("mesh saturated recipients give waiting native callers the next safe admission opportunity", function()
	local net = QT:CreateTestNetwork({ fps = 5, now = 10000 })
	local requester = Peer(net, "Requester-Realm", { backingRealm = "IslandA" })
	local full = Peer(net, "Full-Realm", { backingRealm = "IslandB" })
	for index, peer in ipairs({ requester, full }) do
		peer.UpdatePlayerCommunications = function() end
		peer.API.GetNumDisplayChannels = function()
			return 0
		end
		peer.API.GetChannelRosterInfo = function() end
		peer.API.Random = function(low)
			return low
		end
		net:StartPeer(peer)
		local state = peer:InitializeMeshNetwork()
		state.metrics.handshakesStarted = 3
		for slot = 1, peer == full and 8 or 4 do
			local name = "Existing" .. index .. "x" .. slot .. "-Realm"
			state.neighbors[name] =
				{ name = name, expires = peer.now + 10000, at = peer.now + 10000, connectedAt = peer.now }
		end
	end
	local state = full.meshNetworkState
	-- Offset rotation from the requester's exponential busy retry schedule.
	-- The recipient also has older unknown candidates competing for each slot.
	state.nextRotation = full.now + 127.4
	for index = 1, 200 do
		local name = "Waiting" .. index .. "-Realm"
		full:RememberMeshCandidate(name, "directory")
		state.candidates[name].discoveredAt = full.now - 10
	end
	state.interests.protected = {
		id = "protected",
		destination = "Watcher-Realm",
		zone = 0,
		expiresAt = full:GetAnnouncementServerTime() + 1000,
		upstream = "Existing2x1-Realm",
		downstreams = {},
		alternates = {},
	}
	assert(requester:ObserveMeshContact(full.name, "friend"))
	net:Advance(35)
	local busy = requester.meshNetworkState.candidates[full.name]
	assert(busy.lastHandshakeOutcome == "busy" and busy.retryAt > requester.now)
	assert(state.admissionIntents[requester.name] and not full:IsConfirmedMeshNeighbor(requester.name))
	local originalRetry = busy.retryAt
	local lastRotationAt, rotations = nil, 0
	for _ = 1, 205 do
		net:Advance(1)
		local metrics = full:GetMeshNetworkMetrics()
		if (metrics.neighborRotations or 0) > rotations then
			assert(not lastRotationAt or net.now - lastRotationAt >= 120)
			lastRotationAt, rotations = net.now, metrics.neighborRotations
		end
		local occupied = {}
		for name in pairs(state.neighbors) do
			occupied[name] = true
		end
		for name, reservation in pairs(state.reservations) do
			if reservation.expires > full.now then
				occupied[name] = true
			end
		end
		assert(Count(occupied) <= 8 and metrics.handshakes <= 3 and metrics.admissionIntents <= 3)
		if requester:IsConfirmedMeshNeighbor(full.name) and full:IsConfirmedMeshNeighbor(requester.name) then
			break
		end
	end
	assert(
		requester:IsConfirmedMeshNeighbor(full.name) and full:IsConfirmedMeshNeighbor(requester.name),
		"a full recipient must initiate the normal reciprocal exchange instead of waiting for coincident free slots"
	)
	assert(
		requester.now < originalRetry,
		"a new native hello may recover the caller without waiting for its old busy deadline"
	)
	assert(not state.admissionIntents[requester.name] and (state.metrics.admissionReservations or 0) == 1)
	assert(state.neighbors["Existing2x1-Realm"], "rotation must preserve the more useful existing path")
	assert((state.metrics.neighborRotations or 0) == 1)
	local delivered = 0
	function requester:HandleQTMeshChat(data, sender, context)
		assert(sender == full.name and context.meshVerified and data.text == "Newly admitted public owner")
		delivered = delivered + 1
		return true
	end
	-- Let the new neighbors exchange their ordinary scoped interests before
	-- asking the actual publication path to deliver owner-authenticated data.
	net:Advance(30)
	assert(
		full:Emit(
			"QTCHAT",
			{ text = "Newly admitted public owner" },
			{ { distribution = "MESH", scope = "global" } },
			{ owner = full, expires = full.now + 60 }
		)
	)
	net:Advance(30)
	assert(delivered == 1, "admission must lead to authenticated public delivery rather than only a neighbor edge")
	NoChannels(net)
end, { offline = true })

QT:RegisterTest("mesh queued admission intents remain bounded ordered and owned by their original lifetime", function()
	local function Fixture()
		local net = QT:CreateTestNetwork({ fps = 5, now = 10000 })
		local peer = Peer(net, "Owner-Realm")
		peer.UpdatePlayerCommunications = function() end
		peer.API.GetNumDisplayChannels = function()
			return 0
		end
		peer.API.GetChannelRosterInfo = function() end
		peer.Respond = function()
			return true
		end
		net:StartPeer(peer)
		local state = peer:InitializeMeshNetwork()
		state.nextHandshake, state.nextRotation = math.huge, math.huge
		for slot = 1, 8 do
			local name = "Existing" .. slot .. "-Realm"
			state.neighbors[name] =
				{ name = name, expires = peer.now + 10000, at = peer.now + 10000, connectedAt = peer.now }
		end
		return peer, state
	end
	local serial = 0
	local function Hello(peer, name)
		serial = serial + 1
		assert(
			peer:HandleMeshHello(
				{ requestId = "admission" .. serial, protocol = 3, capabilities = "mesh1" },
				name,
				{ distribution = "WHISPER", session = "native" }
			)
		)
	end
	local peer, state = Fixture()
	for _, name in ipairs({ "Zeta-Realm", "Alpha-Realm", "Gamma-Realm", "Overflow-Realm" }) do
		Hello(peer, name)
		peer.now = peer.now + 1
	end
	assert(Count(state.admissionIntents) == 3 and not state.admissionIntents["Overflow-Realm"])
	local oldest = state.admissionIntents["Zeta-Realm"]
	local queuedAt, expiry = oldest.queuedAt, oldest.expiresAt
	peer.now = peer.now + 20
	Hello(peer, "Zeta-Realm")
	assert(
		oldest.queuedAt == queuedAt and oldest.expiresAt == expiry and expiry - queuedAt == 480,
		"duplicate hellos must not extend the queue lifetime or replace its order"
	)
	peer:RetireMeshPeer("Existing8-Realm")
	peer:UpdateMeshNetwork(peer.now)
	assert(
		state.reservations["Zeta-Realm"]
			and not state.admissionIntents["Zeta-Realm"]
			and not state.neighbors["Zeta-Realm"],
		"the oldest caller gets a reservation, not a trusted edge"
	)
	state.reservations["Zeta-Realm"].expires = peer.now
	peer.now = peer.now + 1
	peer:UpdateMeshNetwork(peer.now)
	assert(
		state.reservations["Alpha-Realm"] and not state.admissionIntents["Alpha-Realm"],
		"expired reservations must make room for queued callers without another rotation"
	)
	assert((state.metrics.neighborRotations or 0) == 0)

	local capped, capState = Fixture()
	for slot = 6, 8 do
		capState.neighbors["Existing" .. slot .. "-Realm"] = nil
		capState.reservations["Reserved" .. slot .. "-Realm"] = { reciprocal = true, expires = capped.now + 60 }
	end
	Hello(capped, "Caller-Realm")
	capState.nextRotation = capped.now
	capped:UpdateMeshNetwork(capped.now)
	assert(
		Count(capState.neighbors) == 5
			and Count(capState.reservations) == 3
			and (capState.metrics.neighborRotations or 0) == 0,
		"reciprocal capacity must not evict a healthy path"
	)
	capState.reservations["Reserved6-Realm"].expires = capped.now
	capped.now = capped.now + 1
	capped:UpdateMeshNetwork(capped.now)
	assert(capState.reservations["Caller-Realm"] and Count(capState.reservations) == 3)

	for _, boundary in ipairs({ "expiry", "ignore", "retirement", "profile", "reset", "later_failure" }) do
		local owner, current = Fixture()
		local callback
		if boundary == "later_failure" then
			current.neighbors["Existing8-Realm"] = nil
			owner:RememberMeshCandidate("Caller-Realm", "directory")
			owner.Request = function(_, _, _, _, options)
				callback = options.onExpire
				return true, "queued", {}, "pending"
			end
			current.nextHandshake = owner.now
			owner:UpdateMeshNetwork(owner.now)
			assert(callback and current.pending["Caller-Realm"])
			-- A delayed native callback can outlive its original slot. Refill
			-- that slot before the incoming hello to exercise the queued fence.
			current.reservations["Caller-Realm"] = nil
			current.neighbors["Existing8-Realm"] = {
				name = "Existing8-Realm",
				expires = owner.now + 10000,
				at = owner.now + 10000,
				connectedAt = owner.now,
			}
		end
		Hello(owner, "Caller-Realm")
		assert(current.admissionIntents["Caller-Realm"])
		if boundary == "expiry" then
			owner.now = owner.now + 481
		elseif boundary == "ignore" then
			owner.ignored["Caller-Realm"] = true
		elseif boundary == "retirement" then
			owner:RetireMeshPeer("Caller-Realm", "unavailable")
		elseif boundary == "profile" then
			owner.db.profile = {}
		elseif boundary == "reset" then
			owner:ResetMeshNetwork()
		elseif boundary == "later_failure" then
			callback("rejected", 7)
		end
		owner.now = owner.now + 1
		owner:UpdateMeshNetwork(owner.now)
		local replacement = owner.meshNetworkState
		assert(
			not replacement.admissionIntents["Caller-Realm"] and not replacement.neighbors["Caller-Realm"],
			boundary .. " must not let an old admission intent establish a connection"
		)
		if boundary == "later_failure" then
			assert(
				current.candidates["Caller-Realm"].retryAt > owner.now and not current.reservations["Caller-Realm"],
				"a failure after the intent arrived must retain its normal backoff"
			)
		end
	end
end, { offline = true })

QT:RegisterTest(
	"mesh handshake diagnostics distinguish admission native rejection retirement queue expiry and timeout",
	function()
		for _, outcome in ipairs({ "admission_failed", "send_failed", "unavailable", "queue_expired", "timeout" }) do
			local net = QT:CreateTestNetwork({ fps = 5 })
			local peer = Peer(net, "Owner-Realm")
			peer.UpdatePlayerCommunications = function() end
			peer.API.GetNumDisplayChannels = function()
				return 0
			end
			peer.API.GetChannelRosterInfo = function() end
			if outcome == "admission_failed" then
				peer.Request = function()
					return false, "capacity"
				end
			elseif outcome == "send_failed" then
				net.sendRule = function()
					return 7
				end
			elseif outcome == "queue_expired" then
				net.sendRule = function()
					return 3
				end
			end
			net:StartPeer(peer)
			peer:InitializeMeshNetwork()
			assert(peer:ObserveMeshContact("Unavailable-Realm", "chat"))
			if outcome == "unavailable" then
				net:Advance(2)
				assert(peer.meshNetworkState.pending["Unavailable-Realm"])
				peer:RetireMeshPeer("Unavailable-Realm", "unavailable")
				net:Advance(23)
			else
				net:Advance(25)
			end
			local candidate = peer.meshNetworkState.candidates["Unavailable-Realm"]
			assert(
				candidate.lastHandshakeOutcome == outcome,
				"handshake failure must retain its actual stage: expected "
					.. outcome
					.. ", got "
					.. tostring(candidate.lastHandshakeOutcome)
			)
			assert(candidate.lastHandshakeAt >= candidate.triedAt and candidate.retryAt > peer.now)
			assert(
				(peer:GetMeshNetworkMetrics().handshakeTimeouts or 0) == (outcome == "timeout" and 1 or 0),
				"only an attempted request with no response counts as a timeout"
			)
			if outcome == "send_failed" then
				assert(candidate.lastHandshakeCode == 7)
			end
			if outcome == "unavailable" then
				assert(
					candidate.lastRetirementReason == "unavailable"
						and candidate.lastRetiredAt == candidate.lastHandshakeAt
				)
			end
		end
	end,
	{ offline = true }
)

QT:RegisterTest("mesh reserved reciprocal probes beat candidate backoff without exceeding neighbor slots", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local owner, peers = Peer(net, "Owner-Realm"), {}
	net:StartPeer(owner)
	local state = owner:InitializeMeshNetwork()
	state.metrics.handshakesStarted, state.nextHandshake = 3, owner.now + 30
	owner.API.Random = function(minimum, maximum)
		return maximum or minimum
	end
	owner.API.GetChannelRosterInfo = function() end
	for index = 1, 5 do
		local name = "Existing" .. index .. "-Realm"
		state.neighbors[name] = { name = name, expires = owner.now + 180, at = owner.now, connectedAt = owner.now }
	end
	for index = 1, 3 do
		local peer = Peer(net, "Reciprocal" .. index .. "-Realm")
		peers[index] = peer
		peer.API.GetChannelRosterInfo = function() end
		net:StartPeer(peer)
		peer:InitializeMeshNetwork()
		peer:RememberMeshCandidate(owner.name, "party")
		owner:RememberMeshCandidate(peer.name, "directory")
		local candidate = state.candidates[peer.name]
		candidate.triedAt, candidate.retryAt = owner.now - 1, owner.now + 300
	end
	local started = net.now
	net:Advance(20)
	for _, peer in ipairs(peers) do
		assert(
			owner:IsConfirmedMeshNeighbor(peer.name) or state.reservations[peer.name],
			"a reciprocal caller must retain its slot until its independent challenge completes"
		)
	end
	for _ = 1, 95 do
		net:Advance(1)
		local occupied = {}
		for name in pairs(state.neighbors) do
			occupied[name] = true
		end
		for name, reservation in pairs(state.reservations) do
			if reservation.expires > owner.now then
				occupied[name] = true
			end
		end
		assert(Count(occupied) <= 8, "inbound and outbound reservations for one peer share one slot")
		local complete = true
		for _, peer in ipairs(peers) do
			if not owner:IsConfirmedMeshNeighbor(peer.name) or not peer:IsConfirmedMeshNeighbor(owner.name) then
				complete = false
			end
		end
		if complete then
			assert(net.now - started < 120)
			return
		end
	end
	error("paced reciprocal probes failed to complete before their admission reservations expired")
end, { offline = true })

QT:RegisterTest("mesh directory cleanup survives combat resets and yields to later user selection", function()
	for _, boundary in ipairs({ "reset", "disable", "selection", "reorder", "logout" }) do
		local net = QT:CreateTestNetwork({ fps = 20, directoryDelay = 1 })
		local peer = Peer(net, "Owner-Realm")
		local select, cleanup = peer.API.SetSelectedDisplayChannel, nil
		peer.API.SetSelectedDisplayChannel = function(index)
			if peer.restricted then
				return false
			end
			select(index)
			return peer.selectedDisplayChannel == index
		end
		peer.API.RequestChannelSelectionRestore = function(callback)
			cleanup = callback
			return true
		end
		net:StartPeer(peer)
		local original = peer.API.GetChannelDisplayInfo(peer.selectedDisplayChannel)
		net:Advance(2.4)
		assert(peer.meshNetworkState.directory)
		peer.restricted = true
		net:Advance(0.3)
		assert(cleanup and peer.meshDirectoryRestore)
		peer:ResetMeshNetwork()
		if boundary == "disable" then
			peer.isEnabled = false
		end
		if boundary == "reorder" or boundary == "selection" then
			local prior = peer.API.GetChannelDisplayInfo(peer.selectedDisplayChannel)
			net:Join(peer, "AAA", true)
			for index = 1, peer.API.GetNumDisplayChannels() do
				local name = peer.API.GetChannelDisplayInfo(index)
				if name == (boundary == "selection" and "AAA" or prior) then
					select(index)
					break
				end
			end
		end
		local chosen = peer.API.GetChannelDisplayInfo(peer.selectedDisplayChannel)
		peer.restricted = false
		cleanup(boundary ~= "logout")
		local restored = peer.API.GetChannelDisplayInfo(peer.selectedDisplayChannel)
		assert(restored == ((boundary == "selection" or boundary == "logout") and chosen or original), boundary)
		assert(not peer.meshDirectoryRestore, "cleanup must release its ownership after " .. boundary)
	end
end, { offline = true })

QT:RegisterTest("mesh renewed scopes fairly rotate eligible branches with bounded selection history", function()
	for _, size in ipairs({ 3, 4 }) do
		local net = QT:CreateTestNetwork()
		local peer = Peer(net, "Viewer-Realm")
		local state = peer:InitializeMeshNetwork()
		state.nextDirectory, state.nextGuild = math.huge, math.huge
		peer.geographicCommsState = { currentZone = 12, viewZone = 12 }
		for index = 1, size do
			local name = "Branch" .. index .. "-Realm"
			state.neighbors[name] = { name = name, at = peer.now, connectedAt = peer.now, expires = peer.now + 10000 }
		end
		local seen = { [0] = {}, [12] = {} }
		function peer:Emit(operation, record, routes)
			if operation == "MINT" and seen[record.zone] then
				assert(#routes <= 2, "rotation must not broaden the fanout")
				for _, route in ipairs(routes) do
					seen[record.zone][route.target] = true
				end
			end
			return true
		end
		local start = net.now
		for cycle = 0, 7 do
			net.now = start + cycle * 41
			peer.now = net.now
			peer:UpdateMeshNetwork(peer.now)
		end
		for zone, names in pairs(seen) do
			for name in pairs(state.neighbors) do
				assert(names[name], "scope " .. zone .. " must not repeatedly miss branch " .. name)
			end
		end
		-- A terminal query does not send anything onward, so it must not take
		-- the turn that the next usable query needs for its branch rotation.
		seen[999] = {}
		for cycle = 1, 8 do
			for _, hops in ipairs({ 1, 8 }) do
				local data = {
					leaseId = "terminal" .. cycle .. "-" .. hops,
					destination = "Terminal-Realm",
					zone = 999,
					expiresAt = peer:GetAnnouncementServerTime() + 120,
					hops = hops,
				}
				assert(peer:HandleMeshInterest(data, "Branch1-Realm", { distribution = "WHISPER" }))
				assert(peer:HandleMeshInterestCancel(data, "Branch1-Realm", { distribution = "WHISPER" }))
			end
		end
		for name in pairs(state.neighbors) do
			if name ~= "Branch1-Realm" then
				assert(seen[999][name], "terminal queries must not consume another branch's turn")
			end
		end
		-- Retired remote queries must not leave unbounded destination/scope
		-- selection state, even when a neighbor rapidly cycles its requests.
		for index = 1, 100 do
			local data = {
				leaseId = "rotating" .. index,
				destination = "Remote" .. index .. "-Realm",
				zone = 20 + index,
				expiresAt = peer:GetAnnouncementServerTime() + 120,
				hops = 8,
			}
			assert(peer:HandleMeshInterest(data, "Branch1-Realm", { distribution = "WHISPER" }))
			assert(peer:HandleMeshInterestCancel(data, "Branch1-Realm", { distribution = "WHISPER" }))
			assert(Count(state.interestSelections) <= 64)
			for _, history in pairs(state.interestSelections) do
				assert(Count(history.peers) <= size)
			end
		end
		net.now = net.now + 121
		peer.now = net.now
		peer:UpdateMeshNetwork(peer.now)
		assert(Count(state.interestSelections) == 2, "only current local scopes may survive history expiry")
	end
end, { offline = true })

QT:RegisterTest(
	"mesh failed whispers retire routes without erasing observations and recover on direct contact",
	function()
		local net = QT:CreateTestNetwork({ fps = 20, latency = 0.03 })
		local alice, bob = Peer(net, "Alice-Realm"), Peer(net, "Bob-Realm")
		for _, peer in ipairs({ alice, bob }) do
			peer.API.GetPlayerNotFoundMessageFormat = function()
				return "No player named '%s' is currently playing."
			end
			peer.API.SetOrdinaryWhisperObserver = function(callback)
				peer.ordinaryWhisperObserver = callback
				return true
			end
			peer.API.AddMessageEventFilter = function(_, callback)
				peer.systemFilter = callback
				return true
			end
			peer.API.RemoveMessageEventFilter = function(_, callback)
				if peer.systemFilter == callback then
					peer.systemFilter = nil
				end
				return true
			end
			net:StartPeer(peer)
		end
		for _ = 1, 90 do
			net:Advance(1)
			if
				alice:IsConfirmedMeshNeighbor(bob.name)
				and bob:IsConfirmedMeshNeighbor(alice.name)
				and alice:GetFreshPlayerLocation(bob.name)
			then
				break
			end
		end
		assert(alice:IsConfirmedMeshNeighbor(bob.name) and alice:GetFreshPlayerLocation(bob.name))
		local blockIncoming = true
		net.deliveryRule = function(packet, receiver)
			if blockIncoming and packet.sender == bob.name and receiver == alice then
				return { drop = true }
			end
		end
		local before = #alice.attempts
		assert(alice:Request("QTHQ", {}, { { distribution = "WHISPER", target = bob.name } }))
		for _ = 1, 100 do
			net:Advance(0.05)
			if #alice.attempts > before and alice.addonWhisperState.targets[bob.name:lower()] then
				break
			end
		end
		assert(alice.addonWhisperState.targets[bob.name:lower()], "the notice must correlate a real native send")
		local location = alice:GetPlayerLocationState().peers[bob.name]
		local completed = 0
		assert(
			alice:Emit(
				"ANN",
				{ senderName = alice.name, eventType = "QUEST_PROGRESS", text = string.rep("x", 900) },
				{ { distribution = "WHISPER", target = bob.name } },
				{
					onComplete = function(sent, reason)
						assert(not sent and reason == "unavailable")
						completed = completed + 1
					end,
				}
			)
		)
		local notice = "No player named 'Bob-Realm' is currently playing."
		assert(alice.systemFilter({}, "CHAT_MSG_SYSTEM", notice))
		alice:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM", notice)
		assert(alice.systemFilter({}, "CHAT_MSG_SYSTEM", notice), "all chat frames share the same decision")
		assert(alice:IsAddonWhisperTargetUnavailable(bob.name) and not alice:IsConfirmedMeshNeighbor(bob.name))
		assert(alice.meshNetworkState.candidates[bob.name].retryAt >= alice.now + 300)
		assert(
			alice:GetPlayerLocationState().peers[bob.name] == location,
			"routing failure must not erase accepted domain data"
		)
		assert(completed == 1 and alice:GetCommTransferMetrics().outgoing == 0)
		local attempts = #alice.attempts
		assert(not alice:Request("QTHQ", {}, { { distribution = "WHISPER", target = bob.name } }))
		net:Advance(2)
		assert(#alice.attempts == attempts, "the failed recipient must not trigger a retry or cancellation send loop")
		blockIncoming = false
		assert(
			bob:Request(
				"MHEL",
				{ version = "test", protocol = 3, capabilities = "mesh1" },
				{ { distribution = "WHISPER", target = alice.name } },
				{ meshTraffic = true }
			)
		)
		for _ = 1, 100 do
			net:Advance(0.05)
			if not alice:IsAddonWhisperTargetUnavailable(bob.name) then
				break
			end
		end
		assert(
			not alice:IsAddonWhisperTargetUnavailable(bob.name),
			"eligible native contact must unblock its handshake reply"
		)
		for _ = 1, 60 do
			net:Advance(1)
			if alice:IsConfirmedMeshNeighbor(bob.name) then
				break
			end
		end
		assert(alice:IsConfirmedMeshNeighbor(bob.name), "a recovered address must still complete native confirmation")
		assert(completed == 1)
	end,
	{ offline = true }
)

QT:RegisterTest("mesh whisper failures retire casing aliases without conflating surnames or realms", function()
	for _, regional in ipairs({ false, true }) do
		local net = QT:CreateTestNetwork({ now = 10000 })
		local peer = Peer(net, regional and "Local Tester" or "Local-Realm", { regional = regional })
		peer.API.GetPlayerNotFoundMessageFormat = function()
			return "No player named '%s' is currently playing."
		end
		peer.API.SetOrdinaryWhisperObserver = function()
			return true
		end
		peer.API.AddMessageEventFilter = function(_, callback)
			peer.systemFilter = callback
			return true
		end
		net:StartPeer(peer)
		local state = peer:InitializeMeshNetwork()
		local canonical = regional and "Meaty Secrets" or "Meaty-Realm"
		local alias = canonical:lower()
		local unrelated = regional and "Meaty Stranger" or "Meaty-Elsewhere"
		for _, name in ipairs({ canonical, alias, unrelated }) do
			assert(peer:RememberMeshCandidate(name, "directory"))
		end
		for _, name in ipairs({ canonical, unrelated }) do
			state.neighbors[name] = { name = name, expires = peer.now + 1000, at = peer.now, connectedAt = peer.now }
		end
		local lease = {
			id = "live-route",
			destination = regional and "Remote Viewer" or "Viewer-Realm",
			zone = 12,
			upstream = canonical,
			expiresAt = peer:GetAnnouncementServerTime() + 100,
			downstreams = {},
			alternates = {},
		}
		state.interests["live-route"] = lease
		-- The native API accepts differently cased full addresses. Its failure
		-- ledger already matches those spellings; routing cleanup must agree.
		net.now, peer.now = net.now + 1, peer.now + 1
		assert(peer:SendTransportNow("private-wire", "MHEL", { distribution = "WHISPER", target = alias }))
		local notice = "No player named '" .. canonical .. "' is currently playing."
		assert(peer.systemFilter({}, "CHAT_MSG_SYSTEM", notice))
		peer:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM", notice)
		assert(not peer:IsConfirmedMeshNeighbor(canonical), "a casing alias must retire the existing native peer")
		assert(not state.interests["live-route"], "a failed native peer must not retain a differently cased route")
		for _, name in ipairs({ canonical, alias }) do
			local candidate = state.candidates[name]
			assert(
				candidate.lastRetirementReason == "unavailable" and candidate.retryAt >= peer.now + 300,
				"all known spellings of the same full address must share the failed-peer backoff"
			)
		end
		assert(peer:IsAddonWhisperTargetUnavailable(canonical))
		assert(
			peer:IsConfirmedMeshNeighbor(unrelated) and state.candidates[unrelated].delay == nil,
			"a shared first name must not retire a different surname or realm"
		)
	end
end, { offline = true })

QT:RegisterTest(
	"mesh newly discovered casing aliases inherit failed address backoff but native recovery remains eligible",
	function()
		for _, regional in ipairs({ false, true }) do
			local net = QT:CreateTestNetwork({ now = 10000, fps = 5 })
			local peer = Peer(net, regional and "Local Tester" or "Local-Realm", { regional = regional })
			peer.API.GetPlayerNotFoundMessageFormat = function()
				return "No player named '%s' is currently playing."
			end
			peer.API.SetOrdinaryWhisperObserver = function()
				return true
			end
			peer.API.AddMessageEventFilter = function(_, callback)
				peer.systemFilter = callback
				return true
			end
			peer.API.GetNumDisplayChannels = function()
				return 0
			end
			peer.API.GetChannelRosterInfo = function() end
			peer.UpdatePlayerCommunications = function() end
			net:StartPeer(peer)
			local state = peer:InitializeMeshNetwork()
			local canonical = regional and "Meaty Secrets" or "Meaty-Realm"
			local alias = canonical:lower()
			local unrelated = regional and "Meaty Stranger" or "Meaty-Elsewhere"
			assert(peer:RememberMeshCandidate(canonical, "directory"))
			net.now, peer.now = net.now + 1, peer.now + 1
			assert(peer:SendTransportNow("first", "MHEL", { distribution = "WHISPER", target = canonical }))
			assert(
				peer.systemFilter({}, "CHAT_MSG_SYSTEM", "No player named '" .. canonical .. "' is currently playing.")
			)
			peer:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM", "No player named '" .. canonical .. "' is currently playing.")
			local retryAt = state.candidates[canonical].retryAt
			-- The short native send hold has ended, but failed discovery has a
			-- longer backoff. A later directory spelling must not reopen that probe.
			net.now, peer.now = net.now + 61, peer.now + 61
			assert(peer:RememberMeshCandidate(alias, "directory"))
			local before = #peer.attempts
			peer:UpdateMeshNetwork(peer.now)
			peer:DrainTransport()
			assert(
				#peer.attempts == before and not state.pending[alias],
				"new spellings cannot bypass failed-peer backoff"
			)
			assert(state.candidates[alias].retryAt == retryAt and state.candidates[alias].delay == 300)
			assert(peer:RememberMeshCandidate(unrelated, "directory"))
			net.now, peer.now = net.now + 1, peer.now + 1
			peer:UpdateMeshNetwork(peer.now)
			assert(state.pending[unrelated], "a different surname or realm must remain eligible")
			-- A direct native hello can arrange a reciprocal challenge before the
			-- old timeout. It is still only an address hint, not a confirmed edge.
			assert(
				peer:HandleMeshHello(
					{ requestId = "recovery", version = "test", protocol = 3, capabilities = "mesh1" },
					alias,
					{ distribution = "WHISPER" }
				)
			)
			net.now, peer.now = net.now + 1, peer.now + 1
			peer:UpdateMeshNetwork(peer.now)
			assert(
				state.pending[alias] and not peer:IsConfirmedMeshNeighbor(alias),
				"native recovery must permit a fresh challenge without granting unauthenticated membership"
			)
		end
	end,
	{ offline = true }
)

local function QuietDiscoveryPeer(net, name, global)
	local peer = Peer(net, name)
	peer.UpdatePlayerCommunications = function() end
	peer.API.GetNumDisplayChannels = function()
		return 0
	end
	peer.API.GetChannelRosterInfo = function() end
	peer.API.GetNumGuildMembers = function()
		return 0
	end
	peer.API.Random = function(low)
		return low
	end
	if global then
		peer.db.global = global
	end
	net:StartPeer(peer)
	peer:InitializeMeshNetwork()
	return peer
end
local function MeshProbeCount(peer)
	local count = 0
	for _, packet in ipairs(peer.attempts) do
		local frame = peer:DecodeCommFrame(packet.wire)
		if frame and frame.operation == "MHEL" then
			count = count + 1
		end
	end
	return count
end

QT:RegisterTest(
	"mesh negative reachability survives world transitions reload and casing without becoming bootstrap seeds",
	function()
		local net = QT:CreateTestNetwork({ fps = 5, now = 10000 })
		local peer = QuietDiscoveryPeer(net, "Owner-Realm")
		net.sendRule = function()
			return 12
		end
		assert(peer:RememberMeshCandidate("Absent-Realm", "directory"))
		net:Advance(5)
		local first = peer.meshNetworkState.candidates["Absent-Realm"]
		assert(MeshProbeCount(peer) == 1 and first.probeFailures == 1)
		local deadline, global = first.retryAt, peer.db.global
		peer:EndCommunicationSession()
		peer:ResumeCommunicationSession()
		peer:InitializeMeshNetwork()
		assert(not peer.meshNetworkState.candidates["Absent-Realm"], "failure history cannot create candidates")
		assert(peer:RememberMeshCandidate("absent-realm", "introduction"))
		local alias = peer.meshNetworkState.candidates["absent-realm"]
		assert(alias.probeFailures == 1 and math.abs(alias.retryAt - deadline) < 1)
		net:Advance(60)
		assert(MeshProbeCount(peer) == 1, "a world transition must preserve the failed address cooldown")
		local reload = QT:CreateTestNetwork({ fps = 5, now = net.now })
		local restored = QuietDiscoveryPeer(reload, "Owner-Realm", global)
		reload.sendRule = function()
			return 12
		end
		assert(Count(restored.meshNetworkState.candidates) == 0)
		assert(restored:RememberMeshCandidate("Absent-Realm", "party"))
		reload:Advance(60)
		assert(MeshProbeCount(restored) == 0, "a reload must not reopen the same failed address")
		local other = QuietDiscoveryPeer(reload, "Other-Realm", global)
		assert(other:RememberMeshCandidate("Absent-Realm", "directory"))
		assert(
			not other.meshNetworkState.candidates["Absent-Realm"].delay,
			"another character owns independent evidence"
		)
		local scoped = global.meshPeerFailures["test:US:realm:Owner-Realm"]
		assert(scoped["absent-realm"] and Count(scoped) == 1)
		restored.ignored["Absent-Realm"] = true
		restored:RetireMeshPeer("Absent-Realm", "ignored")
		assert(not scoped["absent-realm"], "ignore removes retained discovery evidence")
	end,
	{ offline = true }
)

QT:RegisterTest(
	"mesh stale hints exhaust a bounded probe allowance until direct evidence or sparse recovery",
	function()
		local net = QT:CreateTestNetwork({ fps = 1, now = 10000 })
		local peer = QuietDiscoveryPeer(net, "Owner-Realm")
		net.sendRule = function()
			return 12
		end
		assert(peer:RememberMeshCandidate("Absent-Realm", "directory"))
		net:Advance(1000)
		assert(MeshProbeCount(peer) == 3 and peer.meshNetworkState.candidates["Absent-Realm"].probeFailures == 3)
		peer:ResetMeshNetwork()
		peer:InitializeMeshNetwork()
		for _, source in ipairs({ "introduction", "party", "directory", "guild" }) do
			assert(peer:RememberMeshCandidate("Absent-Realm", source))
		end
		assert(peer:ObserveMeshContact("Absent-Realm", "friend"))
		assert(peer:ObserveMeshContact("Absent-Realm", "bnet"))
		net:Advance(2000)
		assert(MeshProbeCount(peer) == 3, "repeated stale hints and graph reset cannot manufacture new reachability")
		assert(peer:ObserveMeshContact("Absent-Realm", "chat"))
		net:Advance(5)
		assert(MeshProbeCount(peer) == 4, "a fresh native message permits recovery after existing backoff")
		local row = peer.meshNetworkState.candidates["Absent-Realm"]
		assert(row.probeFailures == 1)
		local due = row.retryAt
		assert(peer:ObserveMeshContact("Absent-Realm", "visible"))
		assert(row.retryAt == due, "fresh evidence must not erase the active failed-address backoff")
		-- A silent address remains recoverable, but only after the bounded daily epoch.
		row.probeFailures = 3
		row.failureEvidenceAt = row.evidenceAt
		row.failureEvidenceSerial = row.evidenceSerial
		net.now, peer.now = net.now + 86401, peer.now + 86401
		net:Advance(5)
		assert(MeshProbeCount(peer) == 5 and row.probeFailures == 1)
		-- A real native round trip retires negative evidence rather than persisting distrust.
		net.sendRule = nil
		local returning = QuietDiscoveryPeer(net, "Absent-Realm")
		assert(returning:RememberMeshCandidate(peer.name, "directory"))
		net:Advance(40)
		assert(peer:IsConfirmedMeshNeighbor("Absent-Realm"))
		assert(not peer.db.global.meshPeerFailures["test:US:realm:Owner-Realm"]["absent-realm"])
	end,
	{ offline = true }
)

QT:RegisterTest("mesh saved negative evidence validates bounds clock identity and primitive privacy", function()
	local net = QT:CreateTestNetwork({ now = 10000 })
	local peer = Peer(net, "Owner-Realm")
	local stamp, rows = peer:GetAnnouncementServerTime(), {}
	for index = 1, 520 do
		rows["peer" .. index .. "-realm"] = {
			at = stamp - index,
			untilAt = stamp - index + 300,
			delay = 300,
			failures = 1,
			evidenceAt = stamp - index,
			unwanted = { location = "private" },
		}
	end
	rows["future-realm"] = { at = stamp + 1, untilAt = stamp + 301, delay = 300, failures = 1, evidenceAt = stamp }
	rows["old-realm"] = { at = stamp - 86400, untilAt = stamp - 86100, delay = 300, failures = 1, evidenceAt = 0 }
	rows["nan-realm"] = { at = math.huge, untilAt = stamp, delay = 300, failures = 1, evidenceAt = 0 }
	rows["bad|name"] = {}
	rows[false] = true
	peer.db.global.meshPeerFailures =
		{ ["test:US:realm:Owner-Realm"] = rows, ["test:EU:realm:Owner-Realm"] = { untouched = true } }
	peer:InitializeMeshNetwork()
	assert(Count(rows) == 512 and Count(peer.meshNetworkState.candidates) == 0)
	assert(not rows["future-realm"] and not rows["old-realm"] and not rows["nan-realm"] and not rows["peer520-realm"])
	for key, row in pairs(rows) do
		assert(key == key:lower() and Count(row) == 5 and not row.unwanted)
	end
	assert(peer.db.global.meshPeerFailures["test:EU:realm:Owner-Realm"].untouched)
	peer:RememberMeshCandidate("Peer1-Realm", "saved")
	assert(peer.meshNetworkState.candidates["Peer1-Realm"].probeFailures == 1)
	peer.db.profile = {}
	peer:InitializeMeshNetwork()
	assert(Count(peer.meshNetworkState.candidates) == 0, "profile switching cannot bootstrap failed names")
end, { offline = true })

QT:RegisterTest("mesh unsent local failures never persist remote reachability evidence", function()
	for _, failure in ipairs({ "filter", "admission", "queue" }) do
		local net = QT:CreateTestNetwork({ fps = 5, now = 10000 })
		local peer = QuietDiscoveryPeer(net, "Owner-Realm")
		local state = peer.meshNetworkState
		if failure == "filter" then
			peer.CanRecordAddonWhisperAttempt = function()
				return false, "filter-unavailable"
			end
		elseif failure == "admission" then
			peer.Request = function()
				return false, "capacity"
			end
		else
			net.sendRule = function()
				return 3
			end
		end
		assert(peer:RememberMeshCandidate("Absent-Realm", "directory"))
		net:Advance(25)
		assert(Count(peer.db.global.meshPeerFailures["test:US:realm:Owner-Realm"]) == 0)
		if failure == "filter" then
			assert(
				not state.candidates["Absent-Realm"].triedAt
					and Count(state.reservations) == 0
					and Count(state.pending) == 0
			)
			peer.CanRecordAddonWhisperAttempt = QT.CanRecordAddonWhisperAttempt
			net:Advance(3)
			assert(MeshProbeCount(peer) > 0, "local suppression recovery must resume discovery")
		end
	end
end, { offline = true })

QT:RegisterTest("mesh prospective replacements keep healthy edges until fresh native reachability", function()
	for _, boundary in ipairs({ "offline", "stale_waiter", "expiry", "reset", "ignore", "reachable" }) do
		local net = QT:CreateTestNetwork({ fps = 5, now = 10000 })
		local peer = QuietDiscoveryPeer(net, "Owner-Realm")
		local state = peer.meshNetworkState
		for index = 1, 8 do
			local name = "Healthy" .. index .. "-Realm"
			state.neighbors[name] =
				{ name = name, at = peer.now + 10000, connectedAt = peer.now, expires = peer.now + 10000 }
		end
		state.nextRotation = peer.now
		assert(peer:RememberMeshCandidate("Candidate-Realm", "introduction"))
		local reply
		if boundary == "reachable" then
			QuietDiscoveryPeer(net, "Candidate-Realm")
		elseif boundary == "offline" or boundary == "stale_waiter" then
			net.sendRule = function(packet)
				return packet.target == "Candidate-Realm" and 12 or 0
			end
			if boundary == "stale_waiter" then
				state.admissionIntents["Candidate-Realm"] =
					{ queuedAt = peer.now - 100, expiresAt = peer.now + 100, failureSerial = 0 }
			end
		else
			peer.Request = function(_, _, _, _, options)
				reply = options.onResponse
				return true, "queued", {}, "probe"
			end
		end
		net:Advance(3)
		if reply then
			if boundary == "expiry" then
				net.now, peer.now = net.now + 21, peer.now + 21
			elseif boundary == "reset" then
				peer:ResetMeshNetwork()
			else
				peer.ignored["Candidate-Realm"] = true
			end
			assert(
				not reply(
					{ requestId = "probe", protocol = 3, capabilities = "mesh1", admitted = true },
					"Candidate-Realm",
					{ distribution = "WHISPER", session = "native" }
				)
			)
		end
		if boundary == "reachable" then
			net:Advance(35)
			assert(peer:IsConfirmedMeshNeighbor("Candidate-Realm") and Count(state.neighbors) == 8)
			assert(state.metrics.neighborRotations == 1)
		elseif boundary ~= "reset" then
			assert(
				Count(state.neighbors) == 8 and (state.metrics.neighborRotations or 0) == 0,
				boundary .. " discarded a healthy edge"
			)
		end
	end
end, { offline = true })

QT:RegisterTest("mesh discovery admission keeps reciprocal priority FIFO and same-second native recovery", function()
	local net = QT:CreateTestNetwork({ now = 10000, fps = 5 })
	local peer = QuietDiscoveryPeer(net, "Owner-Realm")
	local s = peer.meshNetworkState
	for index = 1, 7 do
		local name = "Healthy" .. index .. "-Realm"
		s.neighbors[name] = { name = name, at = peer.now + 10000, connectedAt = peer.now, expires = peer.now + 10000 }
	end
	for _, name in ipairs({ "Reciprocal-Realm", "First-Realm", "Later-Realm" }) do
		assert(peer:RememberMeshCandidate(name, "directory"))
	end
	s.reservations["Reciprocal-Realm"] = { reciprocal = true, expires = peer.now + 120 }
	for _, name in ipairs({ "First-Realm", "Later-Realm" }) do
		s.admissionIntents[name] = {
			queuedAt = peer.now + (name == "First-Realm" and -10 or -5),
			expiresAt = peer.now + 480,
			failureSerial = 0,
		}
	end
	-- A newer caller can have an older address hint; arrival order still wins.
	s.candidates["Later-Realm"].discoveredAt = peer.now - 500
	local targets = {}
	peer.Request = function(_, _, _, routes)
		targets[#targets + 1] = routes[1].target
		return true, "queued", {}, "probe" .. #targets
	end
	s.nextRotation, s.nextHandshake = peer.now, peer.now
	peer:UpdateMeshNetwork(peer.now)
	assert(targets[1] == "Reciprocal-Realm", "a queued caller cannot starve an occupied reciprocal slot")
	assert(not s.pending["First-Realm"] and Count(s.neighbors) == 7)
	-- Clear the private pending fixture, then exercise FIFO with a genuinely free slot.
	s.pending, s.reservations = {}, {}
	peer.now, net.now = peer.now + 1, net.now + 1
	s.nextHandshake = peer.now
	peer:UpdateMeshNetwork(peer.now)
	assert(targets[2] == "First-Realm")
	local fresh = QuietDiscoveryPeer(QT:CreateTestNetwork({ now = 10000, fps = 5 }), "Other-Realm")
	fresh:RememberMeshCandidate("Returning-Realm", "directory")
	local row = fresh.meshNetworkState.candidates["Returning-Realm"]
	row.probeFailures, row.failureAt, row.failureEvidenceAt = 3, fresh:GetAnnouncementServerTime(), row.evidenceAt
	row.retryAt, row.evidenceSerial, row.failureEvidenceSerial = fresh.now + 1800, 0, 0
	fresh.Respond = function()
		return true
	end
	local requested = false
	fresh.Request = function()
		requested = true
		return true, "queued", {}, "recovery"
	end
	assert(
		fresh:HandleMeshHello(
			{ requestId = "same-second", protocol = 3, capabilities = "mesh1" },
			"Returning-Realm",
			{ distribution = "WHISPER" }
		)
	)
	fresh.meshNetworkState.nextHandshake = fresh.now
	fresh:UpdateMeshNetwork(fresh.now)
	assert(requested, "native recovery in the same server second must escape exhausted stale evidence")
end, { offline = true })

QT:RegisterTest("mesh silent timeouts share exhausted history with preexisting casing aliases", function()
	local net = QT:CreateTestNetwork({ now = 10000, fps = 1 })
	local peer = QuietDiscoveryPeer(net, "Owner-Realm")
	assert(peer:RememberMeshCandidate("Absent-Realm", "directory"))
	-- Learn a second spelling before any failure, then let only the canonical
	-- spelling consume its three accepted-but-unanswered challenge attempts.
	assert(peer:RememberMeshCandidate("absent-realm", "introduction"))
	local state, alias = peer.meshNetworkState, peer.meshNetworkState.candidates["absent-realm"]
	alias.retryAt = peer.now + 100000
	net:Advance(1100)
	local canonical = state.candidates["Absent-Realm"]
	assert(canonical.probeFailures == 3 and canonical.lastHandshakeOutcome == "timeout")
	local probes, due = MeshProbeCount(peer), canonical.retryAt
	alias.retryAt = peer.now
	state.nextHandshake = peer.now
	net:Advance(1)
	assert(alias.probeFailures == 3 and math.abs(alias.retryAt - due) < 1)
	net:Advance(2200)
	assert(
		MeshProbeCount(peer) == probes and not state.pending["absent-realm"],
		"a stale casing alias cannot reopen an exhausted remote address"
	)
	local metrics = peer:GetMeshNetworkMetrics()
	assert(metrics.failureHistory == 1 and metrics.candidatesExhausted == 2 and metrics.candidatesCoolingDown == 0)
end, { offline = true })

_G.QuestTogether:RecordTestModule("scripts/regression_mesh_network.lua")
