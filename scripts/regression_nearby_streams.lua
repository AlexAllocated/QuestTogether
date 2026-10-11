-- Explicit typed observation supplied at the private receive boundary.
-- Short per-field lifetimes exercise expiry boundaries; public v2 snapshots use 600 seconds.
local function ObserveState(addon, method, field, record, sender)
	local lifetimes = { QTLF = 65, QTLQ = 65, QTVR = 180, QTPG = 180, QJST = 125, QTHI = 180 }
	local observation = addon:CreatePeerObservation(sender, field, {
		source = "snapshot",
		lifetime = lifetimes[field] or 600,
		session = type(record) == "table" and record.session or nil,
		sequence = type(record) == "table" and record.sequence or nil,
	})
	return addon[method](addon, record, sender, observation)
end

-- Private addon models and transport only; safe in a live /qt test run.
local QT = _G.QuestTogether
local function Equal(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end
local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end
local function Fixture(name)
	local a = setmetatable({
		isEnabled = true,
		now = 100,
		name = name or "Alice Test",
		sent = {},
		ignored = {},
		position = { mapID = 1, x = 0.5, y = 0.5 },
		playerLocationState = { peers = {} },
		db = { profile = { sharePlayerLocation = true, showPlayerLocations = true } },
	}, { __index = QT })
	a.API = {
		GetTime = function()
			return a.now
		end,
		Random = function()
			return 1234
		end,
	}
	a.API.SendAddonMessage = function(prefix, wire, route, target)
		local frame, body = a:DecodeCommFrame(wire)
		a.sent[#a.sent + 1] = {
			wire = wire,
			route = route,
			target = target,
			at = a.now,
			operation = frame and frame.operation,
			record = frame and frame.total == 1 and a:DecodeCommRecord(frame.operation, body),
		}
		if a.fail then
			return 3
		end
		local receiver = a.network and a.network[target]
		if receiver then
			receiver:ReceiveCommunication(prefix, wire, route, a.name)
		end
		return 0
	end
	function a:NormalizeMemberName(n)
		return n
	end
	function a:IsSelfSender(n)
		return n == self.name
	end
	function a:IsIgnoredPlayerName(n)
		return self.ignored[n] == true
	end
	function a:IsRuntimeRestricted()
		return self.restricted == true
	end
	function a:GetAnnouncementServerTime()
		return 1800000000 + math.floor(self.now)
	end
	function a:RecordCommsTraffic() end
	function a:RecordCommsDiagnostic() end
	function a:Debug() end
	function a:Debugf() end
	function a:ReadLocalPlayerLocation()
		return self.position
	end
	function a:GetLocationPinSurface()
		if not self.hidden then
			return { width = 200, height = 200, mapID = 1 }
		end
	end
	function a:ProjectPlayerLocationPin(_, row)
		if row.mapID ~= 1 or math.abs(row.x - self.position.x) > 0.1 or math.abs(row.y - self.position.y) > 0.1 then
			return nil
		end
		return 100 + (row.x - self.position.x) * 1000, 100 + (row.y - self.position.y) * 1000
	end
	function a:GetPartyRosterFingerprint()
		return "solo"
	end
	function a:GetGroupAnnouncementDistribution()
		return nil
	end
	function a:IsGroupedSender()
		return false
	end
	function a:IsRuntimeRestrictionTypeActive()
		return false
	end
	function a:IsAnnouncementChannelEvent()
		return false
	end
	a:InitializeCommunications()
	a:InitializeGeographicComms()
	return a
end
local function Discover(a, b)
	a.playerLocationState.peers[b.name] = {
		name = b.name,
		mapID = 1,
		x = b.position.x,
		y = b.position.y,
		mask = 3,
		receivedAt = a.now,
		classFile = "MAGE",
		sequence = 7,
	}
	assert(ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", { streams = true, raceID = 0 }, b.name))
end
local function Pair()
	local a, b = Fixture(), Fixture("Bob Smith")
	local network = { [a.name] = a, [b.name] = b }
	a.network, b.network = network, network
	Discover(a, b)
	Discover(b, a)
	return a, b
end
local function Tick(a, b, steps)
	for _ = 1, steps do
		a.now = a.now + 0.21
		if b then
			b.now = a.now
		end
		a:UpdateNearbyStreams()
		a:UpdateCommunicationRuntime()
		if b then
			b:UpdateNearbyStreams()
			b:UpdateCommunicationRuntime()
		end
	end
end
QT:RegisterTest("nearby streams exchange correlated position whispers and preserve baseline metadata", function()
	local a, b = Pair()
	Tick(a, b, 8)
	local stream = a.nearbyStreamState.wanted[b.name]
	assert(stream.sample)
	Equal(a.sent[1].operation, "QTSR")
	b.position.x = 0.52
	Tick(a, b, 3)
	local baseline = a.playerLocationState.peers[b.name]
	local row = a:GetNearbyStreamPosition(baseline, false)
	Equal(row.x, 0.52)
	Equal(row.classFile, "MAGE")
	Equal(baseline.x, 0.5)
	Equal(baseline.sequence, 7)
	for _, packet in ipairs(a.sent) do
		Equal(packet.route, "WHISPER")
		Equal(packet.target, b.name)
		assert(#packet.wire <= 255)
	end
end)
QT:RegisterTest("nearby stream movement is interpolated and never extrapolated", function()
	local a, b = Pair()
	Tick(a, b, 8)
	b.position.x = 0.52
	Tick(a, b, 1)
	local sample = a.nearbyStreamState.wanted[b.name].sample
	local base = a.playerLocationState.peers[b.name]
	a.now = sample.at + sample.duration / 2
	local middle = a:GetNearbyStreamPosition(base, true)
	assert(middle.x > 0.5 and middle.x < 0.52)
	a.now = sample.at + 2
	Equal(a:GetNearbyStreamPosition(base, true).x, 0.52)
	a.now = sample.at + 3
	Equal(a:GetNearbyStreamPosition(base, true).x, 0.5)
end)
QT:RegisterTest("nearby streams restrict unknown senders routes payloads and expired correlations", function()
	local a, b = Pair()
	Tick(a, b, 3)
	local peer = a.nearbyStreamState.wanted[b.name]
	local function Packet(token, seq, stamp, position)
		local mapID, x, y = (position or "1,0.51000,0.50000"):match("([^,]+),([^,]+),([^,]+)")
		return {
			token = token,
			sequence = seq,
			stamp = stamp,
			mapID = tonumber(mapID),
			x = tonumber(x),
			y = tonumber(y),
		}
	end
	local stamp = a:GetAnnouncementServerTime()
	assert(not a:HandleNearbyStreamMessage("QTSP", Packet("wrong", 99, stamp), b.name))
	assert(not a:HandleNearbyStreamMessage("QTSP", Packet(peer.token, 99, stamp), "Stranger"))
	for _, coords in ipairs({ "0,0.50000,0.50000", "1,2.00000,0.50000", "1,nan,0.50000", "1,0.50000,inf" }) do
		assert(not a:HandleNearbyStreamMessage("QTSP", Packet(peer.token, 99, stamp, coords), b.name))
	end
	assert(not a:HandleNearbyStreamMessage("QTSP", Packet(peer.token, 99, stamp - 10), b.name))
	assert(a:HandleNearbyStreamMessage("QTSP", Packet(peer.token, 99, stamp), b.name))
	assert(not a:HandleNearbyStreamMessage("QTSP", Packet(peer.token, 99, stamp), b.name))
	a:OnCommReceived(a.commPrefix, "ANN|anything", "WHISPER", b.name)
	a.now = a.now + 13
	assert(not a:HandleNearbyStreamMessage("QTSP", Packet(peer.token, 100, stamp), b.name))
end)
QT:RegisterTest("nearby streams stop on privacy ignore restriction range and visibility changes", function()
	for _, change in ipairs({
		function(a)
			a.db.profile.sharePlayerLocation = false
		end,
		function(a)
			a.db.profile.showPlayerLocations = false
		end,
		function(a)
			a.restricted = true
		end,
		function(a)
			a.isLoggingOut = true
		end,
		function(a)
			a.isEnabled = false
		end,
		function(a)
			a.hidden = true
		end,
		function(a, b)
			a.ignored[b.name] = true
		end,
		function(a, b)
			a.playerLocationState.peers[b.name].mask = 0
		end,
		function(a)
			a.position.x = 0.9
		end,
	}) do
		local a, b = Pair()
		Tick(a, b, 8)
		change(a, b)
		Tick(a, nil, 4)
		Equal(Count(a.nearbyStreamState.wanted), 0)
		Equal(Count(a.nearbyStreamState.subscribers), 0)
		local sent = #a.sent
		Tick(a, nil, 10)
		Equal(#a.sent, sent)
	end
end)
QT:RegisterTest("nearby stream budget is bounded and prioritizes four closest peers", function()
	local a = Fixture()
	local peers = {}
	for i = 1, 20 do
		local b = Fixture(string.format("Peer %02d", i))
		b.position.x = 0.5 + i / 1000
		Discover(a, b)
		peers[i] = b
	end
	Tick(a, nil, 6)
	Equal(Count(a.nearbyStreamState.wanted), 4)
	assert(a.nearbyStreamState.wanted[peers[1].name])
	assert(not a.nearbyStreamState.wanted[peers[5].name])
	for i = 1, 20 do
		local accepted = a:HandleNearbyStreamMessage("QTSR", { token = "token-" .. i }, peers[i].name)
		Equal(accepted, i <= 4)
	end
	for _ = 1, 100 do
		a.position.y = a.position.y + 0.0001
		Tick(a, nil, 1)
	end
	for i = 2, #a.sent do
		assert(a.sent[i].at - a.sent[i - 1].at >= 0.199)
	end
	assert(Count(a.nearbyStreamState.subscribers) <= 4)
end)
QT:RegisterTest("nearby streams use common throttle backoff and yield to control traffic", function()
	local a, b = Pair()
	Tick(a, b, 8)
	a.fail = true
	a.position.x = 0.51
	Tick(a, nil, 1)
	local before = #a.sent
	Tick(a, nil, 15)
	assert(#a.sent - before < 10, "native throttle must not retry every frame")
	a.fail = false
	a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = b.name } }, { priority = "control" })
	Tick(a, b, 30)
	local found = false
	for index = before + 1, #a.sent do
		if a.sent[index].operation == "QTPR" then
			found = true
		end
	end
	assert(found, "control work shares and drains the same queue")
	assert(a.nearbyStreamState.wanted[b.name].sample)
end)
QT:RegisterTest("nearby capabilities share one typed state envelope without legacy companions", function()
	local a = Fixture()
	a:Publish("QTPR", { active = true })
	a:Publish("QTPG", { size = 0 })
	a:Publish("QTCI", { streams = true, raceID = 0 })
	local records = a:BuildCommunicationStateRecords()
	Equal(#records, 3)
	Equal(records[1].topic, "QTPR")
	Equal(records[2].topic, "QTPG")
	Equal(records[3].topic, "QTCI")
	Equal(#a:BuildCommunicationStateRecords(true), 0)
end)
QT:RegisterTest("nearby streams never probe older clients without advertised support", function()
	local a, b = Pair()
	a.nearbyStreamState.capabilities = {}
	Tick(a, nil, 100)
	Equal(#a.sent, 0)
	assert(not a:HandleNearbyStreamMessage("QTSR", { token = "token" }, b.name))
end)
QT:RegisterTest("nearby stream capability storage and abandoned subscriptions are bounded", function()
	local a, b = Pair()
	for i = 1, 600 do
		ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", { streams = true, raceID = 0 }, "Peer " .. i)
	end
	assert(Count(a.nearbyStreamState.capabilities) <= 512)
	Discover(a, b)
	Tick(a, nil, 65)
	Equal(Count(a.nearbyStreamState.wanted), 0)
	local count = #a.sent
	Tick(a, nil, 50)
	Equal(#a.sent, count)
end)
QT:RegisterTest("nearby streams replace crowded subscribers without exceeding the limit", function()
	local a = Fixture()
	local peers = {}
	for i = 1, 8 do
		local b = Fixture("Peer " .. i)
		b.position.x = 0.5 + i / 1000
		Discover(a, b)
		peers[i] = b
	end
	for i = 1, 4 do
		assert(a:HandleNearbyStreamMessage("QTSR", { token = "old" }, peers[i].name))
	end
	for i = 1, 4 do
		a.playerLocationState.peers[peers[i].name].x = 0.9
	end
	for i = 5, 8 do
		assert(a:HandleNearbyStreamMessage("QTSR", { token = "new" }, peers[i].name))
		assert(Count(a.nearbyStreamState.subscribers) <= 4)
	end
	assert(not a.nearbyStreamState.subscribers[peers[1].name])
end)
QT:RegisterTest("nearby stream reset never reuses correlations from the geographic session", function()
	local a, b = Pair()
	Tick(a, b, 3)
	local oldToken = a.nearbyStreamState.wanted[b.name].token
	a.nearbyStreamState = nil
	Discover(a, b)
	Tick(a, nil, 1)
	assert(a.nearbyStreamState.wanted[b.name].token ~= oldToken)
	assert(
		not a:HandleNearbyStreamMessage(
			"QTSP",
			{ token = oldToken, sequence = 99, stamp = 0, mapID = 1, x = 0.5, y = 0.5 },
			b.name
		)
	)
end)
QT:RegisterTest("nearby capability freshness follows the original sample timestamp", function()
	local a, b = Pair()
	a.nearbyStreamState.capabilities[b.name] = nil
	local context = {
		session = b:GetCommunicationSession(),
		sequence = b:NextCommunicationSequence(),
		stamp = b:GetAnnouncementServerTime(),
	}
	local records =
		{ { topic = "QTCI", data = { streams = true, raceID = 0 }, sampledAt = b:GetAnnouncementServerTime() } }
	a.now = b.now + 10
	assert(a:ApplyCommunicationState(records, b.name, context))
	Equal(a.nearbyStreamState.capabilities[b.name].lifetime, 590)
	a.now = a.now + 590
	Equal(a:GetPlayerCapabilities(b.name), nil)
end)
QT:RegisterTest("nearby streams cannot renew by replaying requests every frame", function()
	local a, b = Pair()
	assert(a:HandleNearbyStreamMessage("QTSR", { token = "token" }, b.name))
	for _ = 1, 10 do
		assert(not a:HandleNearbyStreamMessage("QTSR", { token = "new-token" }, b.name))
	end
	Equal(#a.sent, 0)
	Equal(a.nearbyStreamState.subscribers[b.name].token, "token")
	assert(not a:HandleNearbyStreamMessage("QTSX", { token = "wrong" }, b.name))
	assert(a:HandleNearbyStreamMessage("QTSX", { token = "token" }, b.name))
	Equal(a.nearbyStreamState.subscribers[b.name], nil)
end)

QT:RegisterTest("player identity localizes race and class without guessing legacy or custom races", function()
	local a, b = Pair()
	a.API.GetLocalizedRaceName = function(id)
		return id == 3 and "Dwarf" or nil
	end
	a.API.GetLocalizedClassName = function(token)
		return token == "MAGE" and "Mage" or nil
	end
	local row = { name = b.name, race = "Zwerg", className = "Magier", classFile = "MAGE" }
	local race, class = a:GetPlayerTooltipIdentity(row)
	Equal(race, "Zwerg")
	Equal(class, "Mage")
	assert(ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", { streams = true, raceID = 3 }, b.name))
	race, class = a:GetPlayerTooltipIdentity(row)
	Equal(race, "Dwarf")
	Equal(class, "Mage")
	assert(ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", { streams = false, raceID = 3 }, b.name))
	Equal(a:GetPlayerTooltipIdentity(row), "Dwarf")
	Tick(a, nil, 2)
	Equal(Count(a.nearbyStreamState.wanted), 0)
	assert(ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", { streams = true, raceID = 999 }, b.name))
	Equal(a:GetPlayerTooltipIdentity(row), "Zwerg")
	assert(ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", { streams = true, raceID = 3 }, b.name))
	a.now = a.now + 601
	Equal(a:GetPlayerTooltipIdentity(row), "Zwerg")
	for _, payload in ipairs({
		{ streams = true, raceID = "nan" },
		{ streams = true, raceID = -1 },
		{ streams = true, raceID = 1.5 },
		{ streams = true, raceID = 100001 },
		{ raceID = 3 },
		{ streams = 2, raceID = 3 },
	}) do
		assert(not ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", payload, b.name))
	end
end)

QT:RegisterTest("nearby stream publishing includes race ID while viewing or sharing is disabled", function()
	local a = Fixture()
	a.API.GetPlayerRaceID = function()
		return 3
	end
	a.db.profile.showPlayerLocations = false
	a:UpdateNearbyStreams()
	Equal(a.geographicCommsState.latest.QTCI.data.streams, false)
	Equal(a.geographicCommsState.latest.QTCI.data.raceID, 3)
	Equal(#a.sent, 0)
	a.db.profile.showPlayerLocations = true
	a.now = a.now + 20
	a:UpdateNearbyStreams()
	Equal(a.geographicCommsState.latest.QTCI.data.streams, true)
	Equal(a.geographicCommsState.latest.QTCI.data.raceID, 3)
end)

QT:RegisterTest("unreachable whisper recipients do not permanently stall other nearby peers", function()
	local a, b = Pair()
	local c = Fixture("Aaron Missing")
	Discover(a, c)
	local send = a.API.SendAddonMessage
	a.API.SendAddonMessage = function(prefix, wire, route, target)
		if target == c.name then
			return 7
		end
		return send(prefix, wire, route, target)
	end
	Tick(a, b, 50)
	assert(a.nearbyStreamState.wanted[b.name].sample)
	assert(not a.nearbyStreamState.wanted[c.name])
end)

QT:RegisterTest("stream commands require whisper transport and full native player identities", function()
	for _, forever in ipairs({ false, true }) do
		local a, b = Pair()
		a.name, b.name = forever and "Alice Test" or "Alice-Realm", forever and "Bob Smith" or "Bob-OtherRealm"
		a.NormalizeMemberName, b.NormalizeMemberName = nil, nil
		for _, client in ipairs({ a, b }) do
			client.API.RegionalUniqueNamesEnabled = function()
				return forever
			end
			client.API.GetRealmName = function()
				return "Realm"
			end
			client.IsAnnouncementChannelEvent = function()
				return true
			end
			client.ShouldSuppressDuplicateCommMessage = function()
				return false
			end
			client.IsGeographicChannelEvent = function()
				return false
			end
		end
		local network = { [a.name] = a, [b.name] = b }
		a.network, b.network = network, network
		a.playerLocationState.peers, b.playerLocationState.peers = {}, {}
		a.nearbyStreamState, b.nearbyStreamState = nil, nil
		Discover(a, b)
		Discover(b, a)
		a:OnCommReceived(a.commPrefix, "QTSR|1,channel-token", "CHANNEL", b.name)
		Equal(Count(a.nearbyStreamState.subscribers), 0)
		Tick(a, b, 8)
		assert(a.nearbyStreamState.wanted[b.name].sample)
		for _, packet in ipairs(a.sent) do
			Equal(packet.target, b.name)
		end
	end
end)

QT:RegisterTest("nearby capability withdrawals and data from departed subscriptions cannot revive a stream", function()
	local a, b = Pair()
	Tick(a, b, 8)
	local token = a.nearbyStreamState.wanted[b.name].token
	assert(ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", { streams = false, raceID = 3 }, b.name))
	Equal(a.nearbyStreamState.wanted[b.name], nil)
	Equal(a.nearbyStreamState.subscribers[b.name], nil)
	assert(
		not a:HandleNearbyStreamMessage(
			"QTSP",
			{ token = token, sequence = 999, stamp = 0, mapID = 1, x = 0.51, y = 0.5 },
			b.name
		)
	)
	Tick(a, nil, 5)
	Equal(Count(a.nearbyStreamState.wanted), 0)
end)

QT:RegisterTest("nearby movement remains responsive while actual bulk traffic shares the transport", function()
	local a, b = Pair()
	Tick(a, b, 8)
	local owner = {}
	local wire = assert(
		a:BuildCommFrames(
			"QCRS",
			{ requestId = "pressure", snapshotId = "load", entries = {}, count = 0 },
			{ session = "100-1234", messageId = "900", requestId = "pressure", stamp = a:GetAnnouncementServerTime() }
		)
	)[1]
	for index = 1, 60 do
		assert(
			a:QueueTransportWire(
				wire,
				"QCRS",
				{ distribution = "WHISPER", target = b.name },
				{ priority = "bulk", flow = "bulk:" .. (index % 3), owner = owner, expires = a.now + 60 }
			)
		)
	end
	Equal(#a:GetTransportState().queue >= 60, true)
	local start = #a.sent
	for step = 1, 40 do
		a.position.x = 0.5 + step * 0.0001
		Tick(a, b, 1)
	end
	local bulk, movement = 0, 0
	for index = start + 1, #a.sent do
		local packet = a.sent[index]
		if packet.operation == "QCRS" then
			bulk = bulk + 1
		elseif packet.operation == "QTSP" then
			movement = movement + 1
		end
	end
	assert(bulk >= 6, "bulk traffic must receive service during nearby movement")
	assert(movement >= 4, "nearby movement must receive service during bulk pressure")
	assert(#a:GetTransportState().queue > 0, "pressure must still be present")
	a:CancelTransportOwner(owner, "cancelled")
	local accepted = movement
	start = #a.sent
	a.position.x = 0.51
	Tick(a, b, 8)
	for index = start + 1, #a.sent do
		assert(a.sent[index].operation ~= "QCRS", "cancelled bulk packets must stop")
		if a.sent[index].operation == "QTSP" then
			movement = movement + 1
		end
	end
	assert(movement > accepted)
end)

QT:RegisterTest("nearby streams reuse only the current tick location sample and respect consent", function()
	local a, b = Pair()
	Tick(a, b, 8)
	local state = a.nearbyStreamState
	state.wanted[b.name].nextRequest = a.now + 20
	state.nextSubmit, state.nextScan = a.now, a.now + 20
	local reads = 0
	function a:ReadLocalPlayerLocation()
		reads = reads + 1
		return self.position
	end
	local sample = { mapID = 1, x = 0.51, y = 0.5 }
	a:UpdateNearbyStreams(sample)
	a:UpdateCommunicationRuntime()
	Equal(reads, 0)
	Equal(a.sent[#a.sent].record.x, 0.51)
	a.now = a.now + 0.3
	a.position.x = 0.52
	a:UpdateNearbyStreams()
	a:UpdateCommunicationRuntime()
	Equal(reads, 1)
	Equal(a.sent[#a.sent].record.x, 0.52)
	local before = #a.sent
	a.db.profile.sharePlayerLocation = false
	a.now = a.now + 0.3
	a:UpdateNearbyStreams(sample)
	Equal(#a.sent, before)
end)
