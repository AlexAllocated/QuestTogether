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
		a.sent[#a.sent + 1] = { wire = wire, route = route, target = target, at = a.now }
		if a.fail then
			return 3
		end
		local receiver = a.network and a.network[target]
		if receiver then
			receiver:OnCommReceived(prefix, wire, route, a.name)
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
	assert(a:HandlePlayerCapabilityMetadata("1,1,0", b.name))
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
		if b then
			b:UpdateNearbyStreams()
		end
	end
end
QT:RegisterTest("nearby streams exchange correlated position whispers and preserve baseline metadata", function()
	local a, b = Pair()
	Tick(a, b, 8)
	local stream = a.nearbyStreamState.wanted[b.name]
	assert(stream.sample)
	Equal(a.sent[1].wire:sub(1, 5), "QTSR|")
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
		assert(#packet.wire < 160)
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
		return "1," .. token .. "," .. seq .. "," .. stamp .. "," .. (position or "1,0.51000,0.50000")
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
		local accepted = a:HandleNearbyStreamMessage("QTSR", "1,token-" .. i, peers[i].name)
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
QT:RegisterTest("nearby streams back off on throttling and yield to queued announcements", function()
	local a, b = Pair()
	Tick(a, b, 8)
	a.fail = true
	a.position.x = 0.51
	Tick(a, nil, 1)
	local sent = #a.sent
	Tick(a, nil, 15)
	Equal(#a.sent, sent)
	a.fail = false
	a.geographicCommsState.queue = { { snapshot = false } }
	Tick(a, nil, 30)
	Equal(#a.sent, sent)
	a.geographicCommsState.queue = {}
	Tick(a, b, 5)
	assert(#a.sent > sent)
end)
QT:RegisterTest("nearby stream capability packets are isolated from older geographic metadata", function()
	local a = Fixture()
	a:StageGeographicState("QTPR|1,1")
	a:StageGeographicState("QTPG|1,0")
	a:StageGeographicState("QTCI|1,1,0")
	local packets = a:BuildGeographicSnapshots()
	Equal(#packets, 3)
	assert(packets[1]:find("QTPR|", 1, true))
	assert(packets[2]:find("QTPG|", 1, true))
	assert(packets[3]:find("QTCI|", 1, true))
	Equal(#a:BuildGeographicSnapshots(true), 0)
end)
QT:RegisterTest("nearby streams never probe older clients without advertised support", function()
	local a, b = Pair()
	a.nearbyStreamState.capabilities = {}
	Tick(a, nil, 100)
	Equal(#a.sent, 0)
	assert(not a:HandleNearbyStreamMessage("QTSR", "1,token", b.name))
end)
QT:RegisterTest("nearby stream capability storage and abandoned subscriptions are bounded", function()
	local a, b = Pair()
	for i = 1, 600 do
		a:HandlePlayerCapabilityMetadata("1,1,0", "Peer " .. i)
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
		assert(a:HandleNearbyStreamMessage("QTSR", "1,old", peers[i].name))
	end
	for i = 1, 4 do
		a.playerLocationState.peers[peers[i].name].x = 0.9
	end
	for i = 5, 8 do
		assert(a:HandleNearbyStreamMessage("QTSR", "1,new", peers[i].name))
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
	assert(not a:HandleNearbyStreamMessage("QTSP", "1," .. oldToken .. ",99,0,1,0.50000,0.50000", b.name))
end)
QT:RegisterTest("nearby stream capability follows geographic packet age and rejects whisper advertisements", function()
	local a, b = Pair()
	a.nearbyStreamState.capabilities[b.name] = nil
	a:OnCommReceived(a.commPrefix, "QTCI|1,1,0", "WHISPER", b.name)
	Equal(a.nearbyStreamState.capabilities[b.name], nil)
	b:StageGeographicState("QTCI|1,1,0")
	local wire = b:BuildGeographicSnapshots()[1]
	a.now = b.now + 10
	assert(a:HandleGeographicSnapshot(wire:sub(6), b.name))
	Equal(a.nearbyStreamState.capabilities[b.name].lifetime, 590)
end)
QT:RegisterTest("nearby streams cannot renew by replaying requests every frame", function()
	local a, b = Pair()
	assert(a:HandleNearbyStreamMessage("QTSR", "1,token", b.name))
	for _ = 1, 10 do
		assert(not a:HandleNearbyStreamMessage("QTSR", "1,new-token", b.name))
	end
	Equal(#a.sent, 0)
	Equal(a.nearbyStreamState.subscribers[b.name].token, "token")
	assert(not a:HandleNearbyStreamMessage("QTSX", "1,wrong", b.name))
	assert(a:HandleNearbyStreamMessage("QTSX", "1,token", b.name))
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
	assert(a:HandlePlayerCapabilityMetadata("1,1,3", b.name))
	race, class = a:GetPlayerTooltipIdentity(row)
	Equal(race, "Dwarf")
	Equal(class, "Mage")
	assert(a:HandlePlayerCapabilityMetadata("1,0,3", b.name))
	Equal(a:GetPlayerTooltipIdentity(row), "Dwarf")
	Tick(a, nil, 2)
	Equal(Count(a.nearbyStreamState.wanted), 0)
	assert(a:HandlePlayerCapabilityMetadata("1,1,999", b.name))
	Equal(a:GetPlayerTooltipIdentity(row), "Zwerg")
	assert(a:HandlePlayerCapabilityMetadata("1,1,3", b.name))
	a.now = a.now + 601
	Equal(a:GetPlayerTooltipIdentity(row), "Zwerg")
	for _, payload in ipairs({ "1,1,nan", "1,1,-1", "1,1,1.5", "1,1,100001", "2,1,3", "1,2,3" }) do
		assert(not a:HandlePlayerCapabilityMetadata(payload, b.name))
	end
end)

QT:RegisterTest("nearby stream publishing includes race ID while viewing or sharing is disabled", function()
	local a = Fixture()
	a.API.GetPlayerRaceID = function()
		return 3
	end
	a.db.profile.showPlayerLocations = false
	a:UpdateNearbyStreams()
	Equal(a.geographicCommsState.latest.QTCI.wire, "QTCI|1,0,3,1")
	Equal(#a.sent, 0)
	a.db.profile.showPlayerLocations = true
	a.now = a.now + 20
	a:UpdateNearbyStreams()
	Equal(a.geographicCommsState.latest.QTCI.wire, "QTCI|1,1,3,1")
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
	assert(a:HandlePlayerCapabilityMetadata("1,0,3", b.name))
	Equal(a.nearbyStreamState.wanted[b.name], nil)
	Equal(a.nearbyStreamState.subscribers[b.name], nil)
	assert(not a:HandleNearbyStreamMessage("QTSP", "1," .. token .. ",999,0,1,0.51000,0.50000", b.name))
	Tick(a, nil, 5)
	Equal(Count(a.nearbyStreamState.wanted), 0)
end)

QT:RegisterTest("nearby movement retains its separate budget while comparisons use the fair scheduler", function()
	local a, b = Pair()
	a.questCompareResponseQueue = { jobs = { { entries = {}, expiresAt = a.now + 60 } } }
	Tick(a, b, 4)
	assert(#a.sent > 0)
	a.questCompareResponseQueue.jobs[1].entries = nil
	Tick(a, b, 4)
	assert(#a.sent > 0)
	local before = #a.sent
	a.questCompareResponseQueue.jobs[1] = { entries = {}, expiresAt = a.now - 1 }
	Tick(a, b, 30)
	assert(#a.sent > before)
end)

QT:RegisterTest("nearby streams reuse only the current tick location sample and respect consent", function()
	local a, b = Pair()
	Tick(a, b, 8)
	local state = a.nearbyStreamState
	state.wanted[b.name].nextRequest = a.now + 20
	state.nextSend, state.nextScan = a.now, a.now + 20
	local reads = 0
	function a:ReadLocalPlayerLocation() reads = reads + 1; return self.position end
	local sample = {mapID=1, x=0.51, y=0.5}
	a:UpdateNearbyStreams(sample)
	Equal(reads, 0)
	assert(a.sent[#a.sent].wire:find("1,0.51000,0.50000", 1, true))
	a.now = a.now + 0.3
	a.position.x = 0.52
	a:UpdateNearbyStreams()
	Equal(reads, 1)
	assert(a.sent[#a.sent].wire:find("1,0.52000,0.50000", 1, true))
	local before = #a.sent
	a.db.profile.sharePlayerLocation = false
	a.now = a.now + 0.3
	a:UpdateNearbyStreams(sample)
	Equal(#a.sent, before)
end)
