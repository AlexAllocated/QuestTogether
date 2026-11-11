-- Developer auth and public/private observation contracts use independent peers.
local QT = _G.QuestTogether
local function Eq(a, b, label)
	assert(a == b, (label or "") .. tostring(a) .. " ~= " .. tostring(b))
end
local function Setup(realCrypto)
	local net = QT:CreateTestNetwork({ fps = 30, latency = 0.05 })
	local dev = net:AddPeer("Dev-Realm", { mapID = 12 })
	local peer = net:AddPeer("Friend-Realm", { mapID = 13 })
	dev.isLocalDeveloper = true
	local seed = ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"):gsub("..", function(x)
		return string.char(tonumber(x, 16))
	end)
	dev.Ed25519, peer.Ed25519 = QT.Ed25519, QT.Ed25519
	dev.developerPublicKeyHex = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
	peer.developerPublicKeyHex = dev.developerPublicKeyHex
	function dev:SignDeveloperRequest(text)
		self.lastSignedText = text
		return realCrypto and QT.Ed25519.Sign(seed, text) or string.rep("x", 64)
	end
	if not realCrypto then
		peer.Ed25519 = {
			Hash = QT.Ed25519.Hash,
			NewVerification = function()
				return coroutine.create(function()
					coroutine.yield()
					return true
				end)
			end,
		}
	end
	dev.pongs = {}
	function dev:PrintPingResponse(row)
		self.pongs[#self.pongs + 1] = row
	end
	function peer:BuildDeveloperDiagnosticSnapshot()
		self.reportReads = (self.reportReads or 0) + 1
		return string.rep("任務 100% | data\n", 500)
	end
	function dev:GetDebugController()
		return {
			ShowReport = function(_, text, name)
				self.report = text
				self.reportName = name
			end,
		}
	end
	for _, p in ipairs({ dev, peer }) do
		p:InitializeCommunications()
		p:InitializeRuntimeCoordinator()
		-- Only the communication progression is under test; regular publishers have
		-- independent tests and are disabled here to expose diagnostic-only leakage.
		function p:UpdatePlayerCommunications() end
		function p:UpdateDeveloperAnnouncements() end
		function p:UpdateMeshNetwork() end
	end
	return net, dev, peer
end
local function MeshSetup(relayConsent)
	local net, dev, bridge = Setup(true)
	local remote = net:AddPeer("Relayed-Realm", { mapID = 14 })
	net:SetFPS(20)
	bridge.db.profile.shareDeveloperDiagnostics = relayConsent
	remote.developerPublicKeyHex = dev.developerPublicKeyHex
	-- The real directory, challenges and scoped leases build a three-peer
	-- chain. Direct origin whispers remain reachable for private PONG replies;
	-- only their mesh-neighbor handshake is denied to require a relay.
	net.deliveryRule = function(packet, receiver)
		local frame = dev:DecodeCommFrame(packet.wire)
		if
			frame
			and (frame.operation == "MHEL" or frame.operation == "MACK")
			and (
				(packet.sender == dev.name and receiver == remote)
				or (packet.sender == remote.name and receiver == dev)
			)
		then
			return { drop = true }
		end
	end
	for _, peer in ipairs({ dev, bridge, remote }) do
		peer.UpdateMeshNetwork = nil
		-- Keep the existing private fixture's regular feature publishers quiet.
		-- Every PING codec, verifier, dispatcher, reply producer and native send
		-- still runs unchanged under the real runtime coordinator.
		function peer:UpdatePlayerCommunications() end
		function peer:UpdateDeveloperAnnouncements() end
		net:StartPeer(peer)
	end
	net:Advance(75)
	assert(dev:IsConfirmedMeshNeighbor(bridge.name) and bridge:IsConfirmedMeshNeighbor(dev.name))
	assert(remote:IsConfirmedMeshNeighbor(bridge.name) and bridge:IsConfirmedMeshNeighbor(remote.name))
	assert(not dev:IsConfirmedMeshNeighbor(remote.name), "the remote recipient must require a relay")
	local interested, bridgeInterested = false, false
	for _, lease in pairs(dev.meshNetworkState.interests) do
		if lease.expiresAt > dev:GetAnnouncementServerTime() and lease.zone == 0 then
			interested = interested or lease.destination == bridge.name
		end
	end
	for _, lease in pairs(bridge.meshNetworkState.interests) do
		bridgeInterested = bridgeInterested
			or lease.expiresAt > bridge:GetAnnouncementServerTime()
				and lease.destination == remote.name
				and lease.zone == 0
	end
	assert(interested and bridgeInterested, "shared global demand needs a live reverse path across both links")
	return net, dev, bridge, remote
end

local function MeshPingPublication(peer, requestId)
	for _, entry in pairs(peer.meshPublicationState and peer.meshPublicationState.entries or {}) do
		if entry.publication.operation == "PING" and entry.publication.originRequestId == requestId then
			return entry
		end
	end
end

QT:RegisterTest("ping protocol 3 signed mesh broadcasts return private direct and relayed PONGs", function()
	local net, dev, bridge, remote = MeshSetup(true)
	local sent, id = dev:SendPingRequest()
	assert(sent)
	net:Advance(120)
	local first, second = MeshPingPublication(bridge, id), MeshPingPublication(remote, id)
	assert(
		first and first.verified and first.signedVerified and first.nativeOwner,
		"direct mesh reception must authenticate the real developer signature"
	)
	assert(
		second and second.verified and second.signedVerified and not second.nativeOwner,
		"the remote recipient must authenticate the developer through the intermediate peer"
	)
	local replies = {}
	for _, pong in ipairs(dev.pongs) do
		assert(not replies[pong.senderName], "a mesh retransmission must not duplicate a PONG")
		replies[pong.senderName] = pong
	end
	assert(
		replies[bridge.name] and replies[bridge.name].developer,
		"the direct mesh recipient must return its authorized PONG"
	)
	assert(
		replies[remote.name] and replies[remote.name].developer,
		"the relayed mesh recipient must return its authorized PONG"
	)
	Eq(#dev.pongs, 3, "self plus both remote replies")
	for _, peer in ipairs({ bridge, remote }) do
		for _, packet in ipairs(peer.sent) do
			local frame = peer:DecodeCommFrame(packet.wire)
			if frame and frame.operation == "PONG" then
				Eq(packet.route, "WHISPER")
				Eq(packet.target, dev.name)
			end
		end
	end
end, { offline = true })

QT:RegisterTest(
	"ping protocol 3 diagnostic opt-out relays public authorization without sending its own data",
	function()
		local net, dev, bridge, remote = MeshSetup(false)
		local sent, id = dev:SendPingRequest()
		assert(sent)
		net:Advance(120)
		local entry = MeshPingPublication(remote, id)
		assert(
			entry and entry.verified and entry.signedVerified and not entry.nativeOwner,
			"an opted-out bridge must still carry the public signed ping to consenting recipients"
		)
		local replies = {}
		for _, pong in ipairs(dev.pongs) do
			replies[pong.senderName] = pong
		end
		assert(
			replies[remote.name] and replies[remote.name].developer,
			"the consenting remote recipient must respond through the real reply producer"
		)
		Eq(replies[bridge.name], nil, "an opted-out peer must never send diagnostic data")
		Eq(#dev.pongs, 2, "self plus consenting remote reply")
		Eq(bridge.reportReads, nil)
		for _, packet in ipairs(bridge.sent) do
			local frame = bridge:DecodeCommFrame(packet.wire)
			assert(
				not frame or (frame.operation ~= "PONG" and frame.operation ~= "DREPORT"),
				"public forwarding must not authorize a private diagnostic response"
			)
		end
	end,
	{ offline = true }
)

QT:RegisterTest(
	"ping protocol 3 consent changes during mesh verification preserve relay but retire private replies",
	function()
		local net, dev, bridge, remote = MeshSetup(true)
		local sent, id = dev:SendPingRequest()
		assert(sent)
		local admitted = false
		for _ = 1, 2400 do
			net:Step()
			for _, job in ipairs(bridge.developerRequestState and bridge.developerRequestState.jobs or {}) do
				if job.request.requestId == id then
					admitted = true
				end
			end
			if admitted then
				break
			end
		end
		assert(admitted, "the real broadcast signature verifier must be paused before its verdict")
		bridge:SetOption("shareDeveloperDiagnostics", false)
		bridge:SetOption("shareDeveloperDiagnostics", true)
		net:Advance(120)
		local entry = MeshPingPublication(remote, id)
		assert(
			entry and entry.verified and entry.signedVerified and not entry.nativeOwner,
			"consent withdrawal must not interrupt forwarding the public authorization"
		)
		local replies = {}
		for _, pong in ipairs(dev.pongs) do
			replies[pong.senderName] = pong
		end
		assert(
			replies[remote.name] and replies[remote.name].developer,
			"the downstream consenting recipient must still receive and answer the signed ping"
		)
		Eq(replies[bridge.name], nil, "re-enabling consent must not revive a previously admitted private reply")
		Eq(#dev.pongs, 2, "self plus downstream reply")
		Eq(bridge.reportReads, nil)
	end,
	{ offline = true }
)

-- Full signed, repeated, and multi-minute diagnostic exchanges run offline.
QT:RegisterTest("ping protocol 3 real signature returns complete private snapshot only to its developer", function()
	local net, dev, peer = Setup(true)
	peer.db.profile.sharePlayerLocation = false
	assert(dev:SendPingRequest(peer.name))
	net:Advance(90)
	Eq(#dev.pongs, 1)
	local pong = dev.pongs[1]
	Eq(pong.senderName, peer.name)
	Eq(pong.locationShared, false)
	Eq(pong.coordX, "40.0")
	Eq(pong.coordY, "60.0")
	assert(dev.developerPlayerData[peer.name].publicLocationHidden)
	assert(dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	Eq(dev.playerLocationState.peers[peer.name].mask, 0)
	for _, packet in ipairs(peer.sent) do
		Eq(packet.route, "WHISPER")
		Eq(packet.target, dev.name)
	end
	dev.activeCharacterKey = dev.name
	dev:SavePlayerLocationCache()
	Eq(#dev.db.global.playerLocationCache.rows, 0)
end, { offline = true })
-- Full signed, repeated, and multi-minute diagnostic exchanges run offline.
QT:RegisterTest(
	"ping protocol 3 authorized shared coordinates refresh normal stores and clear prior private positions",
	function()
		local net, dev, peer = Setup()
		peer.db.profile.sharePlayerLocation = false
		assert(dev:SendPingRequest(peer.name))
		net:Advance(40)
		assert(dev.developerPlayerData[peer.name])
		peer.db.profile.sharePlayerLocation = true
		peer.position.x = 0.7
		assert(dev:SendPingRequest(peer.name))
		net:Advance(40)
		Eq(dev.playerLocationState.peers[peer.name].x, 0.7)
		Eq(dev.developerPlayerData[peer.name], nil)
		assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
		Eq(dev.playerLocationState.peers[peer.name].manualSnapshot, true)
	end,
	{ offline = true }
)

QT:RegisterTest("hidden location presentation only uses fresh accepted private developer observations", function()
	local net, dev, peer = Setup()
	peer.db.profile.sharePlayerLocation = false
	assert(dev:SendPingRequest(peer.name))
	net:Advance(30)
	assert(dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	local row = assert(dev.developerPlayerData[peer.name])
	dev.isLocalDeveloper = false
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	dev.isLocalDeveloper = true
	dev.ignored[peer.name] = true
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	dev.ignored[peer.name] = nil
	dev.isEnabled = false
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	dev.isEnabled = true
	dev.isLoggingOut = true
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	dev.isLoggingOut = nil
	row.publicLocationHidden = false
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	row.publicLocationHidden = true
	local now = dev.now
	dev.now = row.receivedAt - 1
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	dev.now = row.receivedAt + 120
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
	dev.now = now
	assert(dev:RecordPeerDeparture(peer.name, now, peer:GetCommunicationSession(), 100000))
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name), "a retained private row cannot outlive departure")
	dev:RetireDeveloperLocationPeer(peer.name)
	assert(not dev:IsPlayerLocationHiddenForDeveloper(peer.name))
end, { offline = true })
-- Full signed, repeated, and multi-minute diagnostic exchanges run offline.
QT:RegisterTest("ping protocol 3 auth binds sender target purpose timestamp and protocol generation", function()
	local _, dev, peer = Setup(true)
	local request = assert(dev:PrepareDeveloperPingRequest({}, peer.name, true))
	assert(dev.lastSignedText:find("QTDEV2", 1, true))
	for _, alter in ipairs({ "sender", "target", "purpose", "timestamp", "signature" }) do
		local copy = peer:DeepCopy(request)
		local sender = dev.name
		if alter == "sender" then
			sender = "Forged-Realm"
		elseif alter == "target" then
			copy.targetName = "Another-Realm"
		elseif alter == "purpose" then
			copy.debugRequest = false
		elseif alter == "timestamp" then
			copy.issuedAt = copy.issuedAt - 301
		else
			copy.signature = string.rep("0", 128)
		end
		peer.developerRequestState = nil
		local called = false
		peer:QueueDeveloperPingVerification(copy, sender, function()
			called = true
		end)
		for _ = 1, 2000 do
			peer:DrainDeveloperPingVerifications()
		end
		Eq(called, false)
	end
end, { offline = true })
-- Full signed, repeated, and multi-minute diagnostic exchanges run offline.
QT:RegisterTest(
	"ping protocol 3 permission changes cancel authentication delayed replies and retained report traffic",
	function()
		for _, phase in ipairs({ "authentication", "jitter", "report" }) do
			local net, dev, peer = Setup()
			assert(dev:SendPingRequest(peer.name, true))
			if phase == "authentication" then
				net:Advance(1)
			elseif phase == "jitter" then
				net:Advance(3)
			else
				net:Advance(30)
			end
			peer:SetOption("shareDeveloperDiagnostics", false)
			local sent = #peer.sent
			net:Advance(90)
			Eq(#peer.sent, sent)
			if phase ~= "report" then
				Eq(peer.reportReads, nil)
			end
			Eq(dev.report, nil)
		end
	end,
	{ offline = true }
)
-- Full signed, repeated, and multi-minute diagnostic exchanges run offline.
QT:RegisterTest(
	"ping protocol 3 initial response precedes report and neither duplicates nor reorder open it twice",
	function()
		local net, dev, peer = Setup()
		net.deliveryRule = function(packet)
			local frame = peer:DecodeCommFrame(packet.wire)
			return { copies = 2, delay = frame and frame.part % 3 * 0.1 or 0.1 }
		end
		local opened = 0
		function dev:GetDebugController()
			return {
				ShowReport = function(_, text, name)
					opened = opened + 1
					self.report = text
					self.reportName = name
				end,
			}
		end
		assert(dev:SendPingRequest(peer.name, true))
		for _ = 1, 1800 do
			net:Step()
			if #dev.pongs > 0 then
				break
			end
		end
		Eq(#dev.pongs, 1, "initial")
		Eq(dev.report, nil, "report must follow initial")
		net:Advance(150)
		Eq(opened, 1)
		Eq(dev.reportName, peer.name)
		Eq(dev.report, string.rep("任務 100% | data\n", 500))
		Eq(#dev.pongs, 1)
	end,
	{ offline = true }
)
-- Full signed, repeated, and multi-minute diagnostic exchanges run offline.
QT:RegisterTest("ping protocol 3 no response time cutoff retains only bounded owned correlations", function()
	local net, dev, peer = Setup()
	peer.db.profile.shareDeveloperDiagnostics = false
	local ids = {}
	for i = 1, 12 do
		local ok, id = dev:SendPingRequest(peer.name)
		assert(ok)
		ids[i] = id
	end
	local count = 0
	for _ in pairs(dev.pendingPingRequests) do
		count = count + 1
	end
	Eq(count, 8)
	net:Advance(700)
	Eq(#dev.pongs, 0)
	for _, id in ipairs({ ids[1], ids[12] }) do
		assert(
			peer:Respond(
				"PONG",
				{ requestId = id, sampledAt = peer.API.GetServerTime(), addonVersion = "7.0.0" },
				{ { distribution = "WHISPER", target = dev.name } }
			)
		)
	end
	net:Advance(10)
	Eq(#dev.pongs, 1, "after late replies")
	Eq(dev.pongs[1].requestId, ids[12])
	dev:EndCommunicationSession()
	dev:ResumeCommunicationSession()
	assert(
		peer:Respond(
			"PONG",
			{ requestId = ids[12], sampledAt = peer.API.GetServerTime() },
			{ { distribution = "WHISPER", target = dev.name } }
		)
	)
	net:Advance(5)
	Eq(#dev.pongs, 1, "after world transition")
end, { offline = true })
QT:RegisterTest("ping protocol 3 retired protocol messages never import data or send fallback replies", function()
	local net, dev, peer = Setup()
	for _, prefix in ipairs({ "QuestTogether", "QuestTogether2" }) do
		for _, wire in ipairs({
			"PONG|2,r,Friend-Realm,Realm,Human,MAGE,Mage,60,Elwynn,42,63,0,12,6.5.11",
			"PING|1,r,Dev-Realm",
			"PONP|2,r,1,1,data",
		}) do
			Eq(dev:OnCommReceived(prefix, wire, "WHISPER", peer.name), false)
		end
	end
	net:Advance(10)
	Eq(#dev.pongs, 0)
	Eq(#dev.sent, 0)
end)

-- Full signed, repeated, and multi-minute diagnostic exchanges run offline.
QT:RegisterTest(
	"ping protocol 3 completed replies release producer capacity while retaining immutable recovery",
	function()
		local net, dev, peer = Setup()
		peer.API.Random = function(low)
			return low
		end
		for index = 1, 20 do
			assert(dev:SendPingRequest(peer.name))
			net:Advance(8)
			Eq(#dev.pongs, index)
			Eq(next(peer.pingReplyState.jobs), nil, "completed producer slot")
		end
		local drop = true
		net.deliveryRule = function(packet)
			local frame = peer:DecodeCommFrame(packet.wire)
			if packet.sender == peer.name and frame and frame.operation == "PONG" and drop then
				return { drop = true }
			end
		end
		local builds = 0
		local original = peer.BuildPingResponse
		function peer:BuildPingResponse(id)
			builds = builds + 1
			return original(self, id)
		end
		assert(dev:SendPingRequest(peer.name))
		net:Advance(3)
		Eq(next(peer.pingReplyState.jobs), nil)
		Eq(#dev.pongs, 20)
		Eq(builds, 1)
		drop = false
		net:Advance(20)
		Eq(#dev.pongs, 21)
		Eq(builds, 1, "retry must reuse retained immutable snapshot")
	end,
	{ offline = true }
)

-- Full signed, repeated, and multi-minute diagnostic exchanges run offline.
QT:RegisterTest(
	"ping protocol 3 a completed diagnostic report frees its producer without weakening permission cancellation",
	function()
		local net, dev, peer = Setup()
		peer.API.Random = function(low)
			return low
		end
		assert(dev:SendPingRequest(peer.name, true))
		net:Advance(150)
		assert(dev.report)
		Eq(next(peer.pingReplyState.jobs), nil)
		peer:SetOption("shareDeveloperDiagnostics", false)
		local sent = #peer.sent
		net:Advance(40)
		Eq(#peer.sent, sent)
	end,
	{ offline = true }
)

_G.QuestTogether:RecordTestModule("scripts/regression_ping_v2.lua")
