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

-- Pure addon-owned peers, clocks and transports. No live native API substitution.
local QT = _G.QuestTogether
local function Eq(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end
local function Peer(name)
	local a = setmetatable({
		name = name or "Me-Realm",
		now = 100,
		isEnabled = true,
		partyMembers = {},
		wire = {},
		known = {},
		count = 0,
		qtPlayerPresenceState = { peers = {} },
	}, { __index = QT })
	a.API = {
		GetTime = function()
			return a.now
		end,
		GetRealmName = function()
			return "Realm"
		end,
		Random = function()
			return 12345
		end,
		RegionalUniqueNamesEnabled = function()
			return a.forever
		end,
		GetPartyJoinInfo = function()
			return a.count > 0, false, a.count
		end,
		GetPartyVisualLeaderUnit = function()
			return a.leader and "party1"
		end,
	}
	function a:IsRuntimeRestricted()
		return self.blocked
	end
	function a:GetPlayerFullName()
		return self.name
	end
	function a:GetUnitFullName()
		return self.leader
	end
	function a:IsIgnoredPlayerName(n)
		return n == self.ignored
	end
	function a:IsKnownQTPlayer(n)
		return self.known[n] == true
	end
	function a:RecordQTPlayerPresence(n)
		self.known[n] = true
		return true
	end
	function a:GetPlayerPartySize()
		return nil
	end
	function a:SubmitRecord(operation, record, _, options)
		if self.sendFails then
			return false
		end
		local message = { operation = operation, record = QT:DeepCopy(record), options = options or {} }
		self.wire[#self.wire + 1] = message
		if not self.holdAcceptance and message.options.onComplete then
			message.options.onComplete(true, "accepted")
		end
		return true
	end
	function a:Publish(...)
		return self:SubmitRecord(...)
	end
	function a:Request(operation, record, routes, options)
		self.requests = self.requests or {}
		self.requests[record.requestId] = options
		return self:SubmitRecord(operation, record, routes, options)
	end
	function a:Respond(...)
		return self:SubmitRecord(...)
	end
	function a:CancelCommRequest(id)
		if self.requests then
			self.requests[id] = nil
		end
	end
	return a
end
local function Group(a, count)
	a.count, a.leader, a.partyMembers = count or 3, a.name, {}
	a.partyMembers[a.name] = { classFile = "MAGE" }
	for i = 2, a.count do
		a.partyMembers["Member" .. i .. "-Realm"] = { classFile = "WARRIOR" }
	end
	local s = rawget(a, "partyVisualState")
	if s then
		s.localAt = nil
	end
end
QT:RegisterTest(
	"party summary uses current join metadata without inventing counts or reviving stale rosters",
	function()
		local a, name = Peer(), "Friend-Realm"
		a.known[name] = true
		a.partyJoinState = { peers = { [name] = { grouped = "0", at = 100 } } }
		Eq(a:GetPlayerPartyVisualInfo(name).size, 0)
		a.partyJoinState.peers[name].grouped = "1"
		Eq(a:GetPlayerPartyVisualInfo(name).grouped, true)
		Eq(a:GetPlayerPartyVisualInfo(name).size, nil)
		Eq(a:RequestPartyVisualRoster(name), false)
		Eq(
			ObserveState(
				a,
				"HandlePartyVisualMetadata",
				"QTPG",
				{ size = 3, leader = "Friend-Realm", leaderClass = "MAGE", revision = "123" },
				name
			),
			true
		)
		Eq(a:GetPlayerPartyVisualInfo(name).size, 3)
		a.now = 101
		a.partyJoinState.peers[name] = { grouped = "0", at = 101 }
		Eq(a:GetPlayerPartyVisualInfo(name).size, 0)
		Eq(a:GetPlayerPartyVisualInfo(name).leader, nil)
		-- Delivery order is not sample order: an older solo snapshot cannot win.
		a.partyJoinState.peers[name].sampledAt = 99
		Eq(a:GetPlayerPartyVisualInfo(name).size, 3)
		a:GetPartyVisualState().peers[name] = nil
		a.partyJoinState.peers[name] = { grouped = "1", at = 100 }
		a.now = 225
		Eq(a:GetPlayerPartyVisualInfo(name), nil)
		a.partyJoinState.peers[name].lifetime = 600
		Eq(a:GetPlayerPartyVisualInfo(name).grouped, true)
		a.partyJoinState.peers[name].grouped = "2"
		Eq(a:GetPlayerPartyVisualInfo(name), nil)
		a.partyJoinState.peers[name].grouped = "0"
		a.ignored = name
		Eq(a:GetPlayerPartyVisualInfo(name), nil)
		a.ignored, a.known[name] = nil, nil
		Eq(a:GetPlayerPartyVisualInfo(name), nil)
	end
)
local function Deliver(a, message, sender)
	local handlers = {
		QTPG = "HandlePartyVisualMetadata",
		QPGR = "HandlePartyVisualRosterRequest",
		QPGM = "HandlePartyVisualRosterMember",
	}
	if message.operation == "QTPG" then
		return ObserveState(a, handlers[message.operation], "QTPG", QT:DeepCopy(message.record), sender)
	end
	return a[handlers[message.operation]](a, QT:DeepCopy(message.record), sender)
end
local function Start(a, b, count)
	Group(b, count)
	Eq(b:BroadcastPartyVisualMetadata(), true)
	Eq(Deliver(a, b.wire[1], b.name), true)
	Eq(a:RequestPartyVisualRoster(b.name), true)
	Eq(Deliver(b, a.wire[1], a.name), true)
end
QT:RegisterTest("party visuals reject partial spoofed and changed atomic roster responses", function()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b)
	Eq(Deliver(a, b.wire[2], "Impostor-Realm"), false)
	local partial = QT:DeepCopy(b.wire[2])
	table.remove(partial.record.members)
	Eq(Deliver(a, partial, b.name), false)
	Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil)
	Group(b, 2)
	b:BroadcastPartyVisualMetadata()
	Deliver(a, b.wire[#b.wire], b.name)
	Eq(Deliver(a, b.wire[2], b.name), false)
	Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil)
end)
QT:RegisterTest("party visuals reject corrupt membership and expire delayed replies and metadata", function()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b)
	local corrupt = QT:DeepCopy(b.wire[2])
	corrupt.record.members[2].name = "Stranger-Realm"
	Eq(Deliver(a, corrupt, b.name), false)
	Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil)
	a.now = a.now + 61
	Eq(a:RequestPartyVisualRoster(b.name), true)
	Eq(Deliver(a, b.wire[2], b.name), false)
	a.now = a.now + 180
	Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
end)
QT:RegisterTest("party visuals support Forever names and never request a raid roster", function()
	local a, b = Peer("Alice Example"), Peer("Bob Example")
	a.forever, b.forever = true, true
	Group(b, 2)
	b.partyMembers["Member2-Realm"] = nil
	b.partyMembers["Carl Example"] = { classFile = "PALADIN" }
	b:BroadcastPartyVisualMetadata()
	Deliver(a, b.wire[1], b.name)
	Eq(a:RequestPartyVisualRoster(b.name), true)
	Deliver(b, a.wire[1], a.name)
	for i = 2, #b.wire do
		Deliver(a, b.wire[i], b.name)
	end
	Eq(a:GetPlayerPartyVisualInfo(b.name).members[1].name, "Bob Example")
	Group(b, 6)
	b:BroadcastPartyVisualMetadata()
	Deliver(a, b.wire[#b.wire], b.name)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 6)
	Eq(a:RequestPartyVisualRoster(b.name), false)
end)
QT:RegisterTest(
	"party visuals handle native group changes and solo withdrawals without inheriting remote claims",
	function()
		local a = Peer()
		Group(a)
		local first = a:GetPlayerPartyVisualInfo(a.name)
		assert(first.key)
		Eq(a:GetPlayerPartyVisualInfo("Member2-Realm"), first)
		a.partyMembers["Member2-Realm"] = nil
		a.now = a.now + 1
		Eq(a:GetLocalPartyVisualInfo(), nil) -- partial native roster is not authoritative
		Group(a)
		a.leader = "Member2-Realm"
		a.now = a.now + 1
		assert(a:GetLocalPartyVisualInfo().key ~= first.key)
		a.count = 0
		a.partyMembers = {}
		a.now = a.now + 1
		Eq(a:GetLocalPartyVisualInfo().size, 0)
		local b = Peer("Viewer-Realm")
		a.partyVisualState.advertisedGroup = true
		a:BroadcastPartyVisualMetadata()
		Deliver(b, a.wire[1], a.name)
		Eq(b:GetPlayerPartyVisualInfo(a.name).size, 0)
	end
)
QT:RegisterTest(
	"party visual queries are bounded and ignored disabled and restricted peers cannot exchange rosters",
	function()
		local a, b = Peer(), Peer("Leader-Realm")
		Start(a, b)
		Eq(a:RequestPartyVisualRoster(b.name), false)
		Eq(Deliver(b, a.wire[1], a.name), false)
		a.ignored = b.name
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
		Eq(Deliver(a, b.wire[2], b.name), false)
		a.ignored = nil
		a.blocked = true
		Eq(a:RequestPartyVisualRoster(b.name), false)
		Eq(Deliver(a, b.wire[2], b.name), false)
		a.blocked = false
		a.isEnabled = false
		Eq(Deliver(a, b.wire[1], b.name), false)
		b.now = b.now + 21
		b.ignored = a.name
		Eq(Deliver(b, a.wire[1], a.name), false)
	end
)
QT:RegisterTest("party visual record admission rejects invalid fields and caps peer state", function()
	local a = Peer()
	for _, record in ipairs({
		{ size = 1, leader = "A-Realm", leaderClass = "MAGE", revision = "1" },
		{ size = 41, leader = "A-Realm", leaderClass = "MAGE", revision = "1" },
		{ size = 0, leader = "A-Realm" },
		{ size = 3, leader = "A-Realm", leaderClass = "bad", revision = "1" },
		{ size = 3, leader = "A|bad", leaderClass = "MAGE", revision = "1" },
		{ size = 3, leader = "A-Realm", leaderClass = "MAGE", revision = "12345678901" },
	}) do
		Eq(ObserveState(a, "HandlePartyVisualMetadata", "QTPG", record, "Other-Realm"), false)
	end
	for i = 1, 600 do
		ObserveState(
			a,
			"HandlePartyVisualMetadata",
			"QTPG",
			{ size = 3, leader = "Leader-Realm", leaderClass = "MAGE", revision = "123" },
			"Peer" .. i .. "-Realm"
		)
	end
	local count = 0
	for _ in pairs(a.partyVisualState.peers) do
		count = count + 1
	end
	Eq(count, 512)
end)

QT:RegisterTest("party visuals drop queued old rosters and clear pending work when a peer departs", function()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b)
	Eq(a.wire[1].options.isCurrent(), true)
	Eq(b.wire[2].options.isCurrent(), true)
	Group(b, 4)
	Eq(b.wire[2].options.isCurrent(), false)
	a:ForgetPartyVisualPeer(b.name)
	Eq(a.wire[1].options.isCurrent(), false)
	Eq(Deliver(a, b.wire[2], b.name), false)
end)
QT:RegisterTest("a newer solo report clears old group identity after a remote reload", function()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b)
	function a:GetPlayerTooltipStats()
		return { partySize = 0, at = 101 }
	end
	local info = a:GetPlayerPartyVisualInfo(b.name)
	Eq(info.size, 0)
	Eq(info.key, nil)
	Eq(a.wire[1].options.isCurrent(), false)
end)
QT:RegisterTest("party roster records retain long multilingual full names without truncation", function()
	local a, b = Peer("Viewer-Realm"), Peer(string.rep("领", 15) .. "-" .. string.rep("域", 15))
	Group(b, 5)
	for i = 2, 5 do
		b.partyMembers["Member" .. i .. "-Realm"] = nil
		b.partyMembers[string.rep("玩", 20) .. i .. "-" .. string.rep("域", 10)] = { classFile = "DEATHKNIGHT" }
	end
	assert(b:BroadcastPartyVisualMetadata())
	assert(Deliver(a, b.wire[1], b.name))
	assert(a:RequestPartyVisualRoster(b.name))
	assert(Deliver(b, a.wire[1], a.name))
	for i = 2, #b.wire do
		assert(Deliver(a, b.wire[i], b.name))
	end
	Eq(#a:GetPlayerPartyVisualInfo(b.name).members, 5)
end)

QT:RegisterTest("solo party visual withdrawals stop after the last grouped publication can expire", function()
	for _, geographic in ipairs({ false, true }) do
		local a = Peer()
		if geographic then
			a.geographicCommsState = {}
		end
		Group(a, 3)
		assert(a:BroadcastPartyVisualMetadata())
		local deadline = a.now + (geographic and 600 or 180)
		a.now = a.now + 1
		Group(a, 0)
		assert(a:BroadcastPartyVisualMetadata())
		a.now = deadline - 1
		assert(a:BroadcastPartyVisualMetadata())
		local count = #a.wire
		a.now = deadline
		Eq(a:BroadcastPartyVisualMetadata(), false)
		Eq(#a.wire, count)
		a.now = a.now + 1
		Group(a, 3)
		assert(a:BroadcastPartyVisualMetadata())
		a.now = a.now + 1
		Group(a, 0)
		assert(a:BroadcastPartyVisualMetadata())
	end
end)

QT:RegisterTest("matching fresh party revisions reuse rosters beyond the old two minute fetch expiry", function()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b, 3)
	for i = 2, #b.wire do
		assert(Deliver(a, b.wire[i], b.name))
	end
	local key = a:GetPlayerPartyVisualInfo(b.name).key
	local roster = a:GetPartyVisualState().rosters[key]
	Eq(roster.at, 100)
	a.now = 250
	Eq(#a:GetPlayerPartyVisualInfo(b.name).members, 3)
	Eq(a:RequestPartyVisualRoster(b.name), false)
	Eq(#a.wire, 1)
	-- A later heartbeat confirms the same hash; no re-download is needed even
	-- though the first roster fetch is now five minutes old.
	a.now, b.now = 400, 400
	assert(b:BroadcastPartyVisualMetadata())
	assert(Deliver(a, b.wire[#b.wire], b.name))
	Eq(#a:GetPlayerPartyVisualInfo(b.name).members, 3)
	Eq(a:RequestPartyVisualRoster(b.name), false)
	Eq(roster.at, 100, "hover must not manufacture a fresh fetch timestamp")
	-- A same-size membership/class change still invalidates the list via hash.
	b.partyMembers["Member2-Realm"].classFile = "MAGE"
	b:GetPartyVisualState().localAt = nil
	a.now, b.now = 410, 410
	assert(b:BroadcastPartyVisualMetadata())
	assert(Deliver(a, b.wire[#b.wire], b.name))
	Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil)
	Eq(a:RequestPartyVisualRoster(b.name), true)
	a.now = 590
	Eq(a:GetPlayerPartyVisualInfo(b.name), nil, "an old list cannot keep expired party metadata alive")
end)

QT:RegisterTest("party visuals retain native acceptance semantics for advertised group withdrawals", function()
	local a = Peer()
	Group(a, 3)
	a.holdAcceptance = true
	assert(a:BroadcastPartyVisualMetadata())
	Eq(a.partyVisualState.advertisedGroup, nil)
	local group = a.wire[1]
	group.options.onComplete(true, "accepted")
	Eq(a.partyVisualState.advertisedGroup, true)
	Eq(a.partyVisualState.lastGroupAdvertisedAt, a.now)
	a.now = a.now + 1
	Group(a, 0)
	assert(a:BroadcastPartyVisualMetadata())
	Eq(group.options.isCurrent(), false)
	Eq(a.wire[2].options.isCurrent(), true)
end)

QT:RegisterTest(
	"party roster correlation retires accepted responses and departed requests without partial exposure",
	function()
		local a, b = Peer(), Peer("Leader-Realm")
		Start(a, b)
		local id = a.wire[1].record.requestId
		assert(a.requests[id])
		assert(Deliver(a, b.wire[2], b.name))
		Eq(a.requests[id], nil)
		Eq(#a:GetPlayerPartyVisualInfo(b.name).members, 3)
		Eq(Deliver(a, b.wire[2], b.name), false) -- a retired request cannot accept a replay
		a, b = Peer(), Peer("Leader-Realm")
		Start(a, b)
		id = a.wire[1].record.requestId
		a:ForgetPartyVisualPeer(b.name)
		Eq(a.requests[id], nil)
		Eq(Deliver(a, b.wire[2], b.name), false)
	end
)

QT:RegisterTest("party roster uses shared request framing repair and correlation with long member names", function()
	local net = QT:CreateTestNetwork({ fps = 20, latency = 0.05 })
	local a = net:AddPeer("Viewer-Realm")
	local b = net:AddPeer(string.rep("领", 15) .. "-Realm", { group = "party" })
	for i = 2, 5 do
		net:AddPeer(string.rep("玩", 20) .. i .. "-Realm", { group = "party" })
	end
	b.API.GetPartyVisualLeaderUnit = function()
		return "player"
	end
	function b:GetUnitFullName()
		return self.name
	end
	for _, peer in ipairs({ a, b }) do
		peer.OnCommReceived = peer.ReceiveCommunication
		peer:InitializeCommunications()
		local frame = net:CreateFrame(peer)
		frame:SetScript("OnUpdate", function()
			peer:UpdateCommunicationRuntime()
		end)
	end
	local summary = b:BuildPartyVisualMetadata()
	assert(summary)
	assert(b:Publish("QTPG", summary, { { distribution = "WHISPER", target = a.name } }))
	net:Advance(3)
	assert(a:RequestPartyVisualRoster(b.name))
	local lost
	net.deliveryRule = function(packet, receiver)
		local frame = a:DecodeCommFrame(packet.wire)
		if receiver == a and frame and frame.operation == "QPGM" then
			if frame.part == 2 and not lost then
				lost = true
				return { drop = true }
			end
			return { copies = 2, delay = frame.part == 1 and 0.2 or 0.05 }
		end
	end
	net:Advance(40)
	assert(lost, "full member names must exercise actual multipart repair")
	local info = a:GetPlayerPartyVisualInfo(b.name)
	assert(info and info.members)
	Eq(#info.members, 5)
	Eq(a:RequestPartyVisualRoster(b.name), false)
	Eq(next(a:GetPartyVisualState().pending), nil)
	Eq(next(a.communicationState.requests), nil)
end)

local function SharedRoster()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b, 3)
	assert(Deliver(a, b.wire[2], b.name))
	return a, b, "Member2-Realm", a:GetPlayerPartyVisualInfo(b.name).key
end

QT:RegisterTest("shared party roster resolves every known member without copied observations or new requests", function()
	local a, b, member, key = SharedRoster()
	local state = a:GetPartyVisualState()
	Eq(a:GetPlayerPartyVisualInfo(member), nil, "roster membership must not establish QT presence")
	a.known[member] = true
	local source, result = state.peers[b.name], a:GetPlayerPartyVisualInfo(member)
	Eq(result.key, key)
	Eq(result.members, state.rosters[key].members)
	Eq(result.sampledAt, source.sampledAt)
	Eq(result.at, source.at)
	Eq(result.lifetime, source.lifetime)
	Eq(state.peers[member], nil)
	Eq(a:RequestPartyVisualRoster(member), false)
	Eq(#a.wire, 1)
	a.now = 200
	Eq(a:GetPlayerPartyVisualInfo(member).sampledAt, 100)
	Eq(state.rosters[key].at, 100)
	a.now = 280
	Eq(a:GetPlayerPartyVisualInfo(member), nil)
end)

QT:RegisterTest("shared party partial metadata gives sender and leader one incomplete requestable view", function()
	local a, b = Peer(), Peer("Sender-Realm")
	Group(b, 3)
	b.leader, b.partyMembers["Leader-Realm"] = "Leader-Realm", { classFile = "WARRIOR" }
	b.partyMembers["Member2-Realm"] = nil
	assert(b:BroadcastPartyVisualMetadata())
	assert(Deliver(a, b.wire[1], b.name))
	a.known[b.leader] = true
	local sender, leader = a:GetPlayerPartyVisualInfo(b.name), a:GetPlayerPartyVisualInfo(b.leader)
	Eq(sender.key, leader.key)
	Eq(sender.members, nil)
	Eq(leader.members, nil)
	Eq(#sender.knownMembers, 2)
	Eq(#leader.knownMembers, 2)
	for index, row in ipairs(sender.knownMembers) do Eq(leader.knownMembers[index].name, row.name) end
	Eq(a:GetPartyVisualState().peers[b.leader], nil)
	assert(a:RequestPartyVisualRoster(b.leader))
end)

QT:RegisterTest("shared party newer solo or membership evidence invalidates old lists for all their members", function()
	for _, mode in ipairs({ "solo", "size", "join", "party" }) do
		local a, b, member, key = SharedRoster()
		a.known[member], a.now = true, 101
		if mode == "solo" or mode == "party" then
			local record = mode == "solo" and { size = 0 }
				or { size = 2, leader = "Other-Realm", leaderClass = "MAGE", revision = "7" }
			assert(ObserveState(a, "HandlePartyVisualMetadata", "QTPG", record, member))
		elseif mode == "size" then
			a.qtPlayerPresenceState.peerTooltipStats = { [member] = { partySize = 0, at = 101 } }
		else
			a.partyJoinState = { peers = { [member] = { grouped = "0", at = 101 } } }
		end
		local result = a:GetPlayerPartyVisualInfo(member)
		Eq(result.size, mode == "party" and 2 or 0)
		local old = a:GetPlayerPartyVisualInfo(b.name)
		Eq(old.key, nil)
		Eq(old.members, nil)
		assert(a:GetPartyVisualState().rosters[key], "retain validated immutable content for exact future revision reuse")
	end
end)

QT:RegisterTest("shared party new same leader revision excludes stale direct members until reconfirmed", function()
	local a, b, _, key = SharedRoster()
	local member = "Member3-Realm"
	assert(ObserveState(a, "HandlePartyVisualMetadata", "QTPG", b.wire[1].record, member))
	Eq(a:GetPlayerPartyVisualInfo(member).key, key)
	a.now, b.now = 101, 101
	Group(b, 2)
	assert(b:BroadcastPartyVisualMetadata())
	assert(Deliver(a, b.wire[#b.wire], b.name))
	local result = a:GetPlayerPartyVisualInfo(member)
	Eq(result.key, nil)
	Eq(result.members, nil)
	assert(a:GetPlayerPartyVisualInfo(b.name).key ~= key)
end)

QT:RegisterTest("shared party references cannot revive ignored departed evicted or reset subjects and sources", function()
	for _, mode in ipairs({ "subject", "source", "ignore", "reset" }) do
		local a, b, member = SharedRoster()
		a.known[member] = true
		assert(a:GetPlayerPartyVisualInfo(member).members)
		if mode == "ignore" then
			a.ignored = member
		elseif mode == "reset" then
			a:ResetPartyVisuals()
		else
			local retired = mode == "subject" and member or b.name
			a:ForgetPartyVisualPeer(retired)
			a.known[retired] = nil
		end
		Eq(a:GetPlayerPartyVisualInfo(member), nil)
		if mode == "subject" then
			a.known[member] = true -- independent later presence does not restore removed membership proof
			Eq(a:GetPlayerPartyVisualInfo(member), nil)
		end
	end
	local a, b, member = SharedRoster()
	a.known[member], a.now = true, 101
	assert(a:RecordPeerDeparture(member, 101))
	a:ForgetPartyVisualPeer(member)
	a.now = 102
	local observation = a:CreatePeerObservation(b.name, "QTPG", { source = "snapshot", lifetime = 180, age = 2 })
	assert(a:HandlePartyVisualMetadata(b.wire[1].record, b.name, observation))
	Eq(a:GetPlayerPartyVisualInfo(member), nil, "reindexing an old source must not bypass the subject departure fence")
end)

QT:RegisterTest("shared party restored rosters serve cached members without manufacturing live presence or lifetime", function()
	local a, b, member, key = SharedRoster()
	local saved = a:SavePlayerPartyCacheEntry(b.name, 110, 1000000100)
	for _, order in ipairs({ { b.name, member }, { member, b.name } }) do
		local restored = Peer()
		restored.now = 10
		restored.playerLocationState = { peers = {} }
		for _, name in ipairs(order) do
			restored.playerLocationState.peers[name] = { cached = true, mask = 3, receivedAt = 10, lifetime = 150 }
			if name == b.name then assert(restored:RestorePlayerPartyCacheEntry(name, saved, 10, 1000000120)) end
		end
		local result = restored:GetPlayerPartyVisualInfo(member)
		Eq(result.key, key)
		Eq(result.cached, true)
		Eq(result.sampledAt, -20)
		Eq(result.lifetime, 150)
		Eq(restored:GetPartyVisualState().peers[member], nil)
		Eq(restored.known[member], nil)
		Eq(restored:RequestPartyVisualRoster(member), false)
		restored.now = 160
		Eq(restored:GetPlayerPartyVisualInfo(member), nil)
	end
end)

QT:RegisterTest("shared party partial leader contradictions and invalidated reload exports stay summary only", function()
	local a, b = Peer(), Peer("Sender-Realm")
	Group(b, 2)
	b.leader = "Member2-Realm"
	assert(b:BroadcastPartyVisualMetadata())
	assert(Deliver(a, b.wire[1], b.name))
	a.now = 101
	assert(ObserveState(a, "HandlePartyVisualMetadata", "QTPG", { size = 0 }, b.leader))
	local info = a:GetPlayerPartyVisualInfo(b.name)
	Eq(info.key, nil)
	Eq(info.knownMembers, nil)
	Eq(a:GetPlayerPartyVisualInfo(b.leader).size, 0)
	local saved = a:SavePlayerPartyCacheEntry(b.name, 101, 1000000101)
	Eq(saved.leader, nil)
	Eq(saved.roster, nil)
	local viewer, publisher, member = SharedRoster()
	viewer.now = 101
	assert(ObserveState(viewer, "HandlePartyVisualMetadata", "QTPG", { size = 0 }, member))
	saved = viewer:SavePlayerPartyCacheEntry(publisher.name, 101, 1000000101)
	Eq(saved.leader, nil)
	Eq(saved.roster, nil, "missing cacheable location for the solo member cannot preserve an invalidated list")
end)

QT:RegisterTest("shared party indexes and partial lists stay bounded across source and roster eviction", function()
	local a = Peer()
	for index = 1, 514 do
		a.now = 100 + index / 1000
		assert(ObserveState(a, "HandlePartyVisualMetadata", "QTPG",
			{ size = 3, leader = "SharedLeader-Realm", leaderClass = "MAGE", revision = "123" }, "Source" .. index .. "-Realm"))
	end
	local s, sourceCount, referenceCount = a:GetPartyVisualState(), 0, 0
	for source, indexed in pairs(a:GetPartyVisualState().sources) do
		sourceCount = sourceCount + 1
		assert(s.peers[source] == indexed.record)
	end
	for _, sources in pairs(s.memberships) do
		for source, record in pairs(sources) do
			referenceCount = referenceCount + 1
			assert(s.peers[source] == record)
		end
	end
	Eq(sourceCount, 512)
	Eq(referenceCount, 1024)
	Eq(s.sources["Source1-Realm"], nil)
	local info = a:GetPlayerPartyVisualInfo("Source514-Realm")
	assert(#info.knownMembers <= info.size)
	-- Canonical roster eviction removes full-member references while keeping
	-- independently advertised sender/leader relationships.
	local viewer, firstKey, firstLeader = Peer()
	for index = 1, 129 do
		viewer.now, viewer.wire = 100 + index, {}
		local publisher = Peer("Party" .. index .. "-Realm")
		publisher.now = viewer.now
		Start(viewer, publisher, 3)
		assert(Deliver(viewer, publisher.wire[2], publisher.name))
		if index == 1 then firstKey, firstLeader = viewer:GetPlayerPartyVisualInfo(publisher.name).key, publisher.name end
	end
	local state, rosterCount = viewer:GetPartyVisualState(), 0
	for _ in pairs(state.rosters) do rosterCount = rosterCount + 1 end
	Eq(rosterCount, 128)
	Eq(state.rosters[firstKey], nil)
	Eq(state.memberships["Member2-Realm"][firstLeader], nil)
	assert(state.memberships[firstLeader][firstLeader])
end)

QT:RegisterTest("shared party superseded proofs cannot revive when contradictory peers expire or depart", function()
	for _, mode in ipairs({ "metadata", "join", "forget", "unseen" }) do
		local a, b, member, key = SharedRoster()
		a.known[member] = true
		a:GetPartyVisualState().peers[b.name].lifetime = 600
		a.now = 101
		if mode == "join" then
			a.partyJoinState = { peers = { [member] = { grouped = "0", at = 101 } } }
		else
			assert(ObserveState(a, "HandlePartyVisualMetadata", "QTPG", { size = 0 }, member))
		end
		if mode ~= "unseen" then Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil) end
		if mode == "forget" or mode == "unseen" then
			a:ForgetPartyVisualPeer(member)
			a.known[member] = nil
		else
			a.now = 300
		end
		local info = a:GetPlayerPartyVisualInfo(b.name)
		Eq(info.key, nil)
		Eq(info.members, nil)
		assert(a:GetPartyVisualState().rosters[key])
		-- A genuinely new exact revision can reconfirm the immutable list;
		-- merely hovering, expiring, or deleting contrary evidence cannot.
		a.now, b.now = 301, 301
		assert(b:BroadcastPartyVisualMetadata())
		assert(Deliver(a, b.wire[#b.wire], b.name))
		Eq(#a:GetPlayerPartyVisualInfo(b.name).members, 3)
	end
end)

QT:RegisterTest("shared party accepted size and join counterfacts retire proofs before any hover observes them", function()
	for _, mode in ipairs({ "size", "join" }) do
		local a, b, member = SharedRoster()
		a.known[member] = true
		a:GetPartyVisualState().peers[b.name].lifetime = 600
		a.now = 101
		if mode == "size" then
			assert(ObserveState(a, "HandleAddonVersionMessage", "QTVR", { version = "0.0.0", partySize = 0 }, member))
		else
			assert(ObserveState(a, "HandlePartyJoinMetadata", "QJST", { grouped = "0", invite = false }, member))
		end
		a.now = 300 -- no query between receipt and expiry of the conflicting fact
		local info = a:GetPlayerPartyVisualInfo(b.name)
		Eq(info.key, nil)
		Eq(info.members, nil)
	end
end)

QT:RegisterTest("shared party newer canonical rosters retire overlapping older membership without direct member reports", function()
	for _, retire in ipairs({ "none", "departure", "expiry" }) do
		local a, old, member, oldKey = SharedRoster()
		a.known[member], a.now = true, 101
		local current = Peer("NewLeader-Realm")
		current.now = 101
		Group(current, 3)
		current.partyMembers["Member3-Realm"] = nil
		current.partyMembers["NewMember-Realm"] = { classFile = "MAGE" }
		assert(current:BroadcastPartyVisualMetadata())
		assert(Deliver(a, current.wire[1], current.name))
		assert(a:RequestPartyVisualRoster(current.name))
		assert(Deliver(current, a.wire[#a.wire], a.name))
		assert(Deliver(a, current.wire[#current.wire], current.name))
		Eq(a:GetPartyVisualState().peers[member], nil)
		if retire == "none" then Eq(a:GetPlayerPartyVisualInfo(member).sourceName, current.name) end
		-- The counterfact must retire the old proof at receipt, even when the
		-- first query of that old party occurs after the new source disappears.
		if retire == "departure" then
			a:ForgetPartyVisualPeer(current.name)
			a.known[current.name] = nil
		elseif retire == "expiry" then
			a:GetPartyVisualState().peers[old.name].lifetime = 600
			a.now = 281
		end
		local previous = a:GetPlayerPartyVisualInfo(old.name)
		Eq(previous.key, nil)
		Eq(previous.members, nil)
		assert(a:GetPartyVisualState().rosters[oldKey])
	end
end)

QT:RegisterTest("delayed older canonical roster cannot override a newer shared membership", function()
	local a, old = Peer(), Peer("OldLeader-Realm")
	Start(a, old, 3) -- keep the older complete response in flight
	a.now = 101
	local current = Peer("NewLeader-Realm")
	current.now = 101
	Group(current, 3)
	current.partyMembers["Member3-Realm"] = nil
	current.partyMembers["NewMember-Realm"] = { classFile = "MAGE" }
	assert(current:BroadcastPartyVisualMetadata())
	assert(Deliver(a, current.wire[1], current.name))
	assert(a:RequestPartyVisualRoster(current.name))
	assert(Deliver(current, a.wire[#a.wire], a.name))
	assert(Deliver(a, current.wire[#current.wire], current.name))
	a.now = 102
	assert(Deliver(a, old.wire[2], old.name))
	a.known["Member2-Realm"] = true
	Eq(a:GetPlayerPartyVisualInfo("Member2-Realm").sourceName, current.name)
	Eq(a:GetPlayerPartyVisualInfo(old.name).members, nil)
	assert(a:GetPlayerPartyVisualInfo(current.name).members)
	Eq(Deliver(a, old.wire[2], old.name), false)
end)

QT:RegisterTest("party join conflicts use source order across same-second delivery and reload", function()
	for _, order in ipairs({ { "QTPG", "QJST" }, { "QJST", "QTPG" } }) do
		local a, name, stamp = Peer(), "Friend-Realm", 1800000100
		function a:GetAnnouncementServerTime() return stamp end
		local records = {
			QTPG = { topic = "QTPG", sampledAt = stamp, revision = 11,
				data = { size = 3, leader = name, leaderClass = "MAGE", revision = "12" } },
			QJST = { topic = "QJST", sampledAt = stamp, revision = 10, data = { grouped = "0", invite = false } },
		}
		for index, topic in ipairs(order) do
			a.now = 100 + index / 10
			assert(a:ApplyCommunicationState({ records[topic] }, name,
				{ session = "1800000000-1", sequence = index + 20, stamp = stamp }))
		end
		local current = a:GetPlayerPartyVisualInfo(name)
		Eq(current.size, 3)
		assert(current.key)
		local saved = a:SavePlayerPartyCacheEntry(name, a.now, stamp)
		Eq(saved.sourceSampledAt, stamp)
		Eq(saved.observationSequence, 11)
		local restored = Peer()
		restored.now = 10
		restored.playerLocationState = { peers = { [name] = { cached = true, mask = 3, receivedAt = 10, lifetime = 180 } } }
		assert(restored:RestorePlayerPartyCacheEntry(name, saved, 10, stamp))
		local restoredInfo = restored:GetPlayerPartyVisualInfo(name)
		Eq(restoredInfo.sourceSampledAt, stamp)
		Eq(restoredInfo.observationName, name)
		Eq(restoredInfo.observationSession, "1800000000-1")
		Eq(restoredInfo.observationSequence, 11)
		function restored:GetAnnouncementServerTime() return stamp end
		restored.now = 10.9
		assert(restored:ApplyCommunicationState({ records.QJST }, name,
			{ session = "1800000000-1", sequence = 30, stamp = stamp }))
		Eq(restored:GetPlayerPartyVisualInfo(name).key, current.key)
		restored.now = 11
		records.QJST.revision = 12
		assert(restored:ApplyCommunicationState({ records.QJST }, name,
			{ session = "1800000000-1", sequence = 31, stamp = stamp }))
		Eq(restored:GetPlayerPartyVisualInfo(name).size, 0)
		Eq(restored:GetPartyVisualState().peers[name].membershipInvalidatedBy.observationSequence, 12)
	end
end)

QT:RegisterTest("party reload uses the live solo or unknown-size grouped evidence and its original lease", function()
	for _, grouped in ipairs({ "0", "1" }) do
		local a, name = Peer(), "Friend-Realm"
		local first = grouped == "0" and { size = 3, leader = name, leaderClass = "MAGE", revision = "1" }
			or { size = 0 }
		assert(ObserveState(a, "HandlePartyVisualMetadata", "QTPG", first, name))
		a.now = 101
		assert(ObserveState(a, "HandlePartyJoinMetadata", "QJST", { grouped = grouped, invite = false }, name))
		local live = a:GetPlayerPartyVisualInfo(name)
		local saved = a:SavePlayerPartyCacheEntry(name, 110, 1000000110)
		Eq(saved.size, live.size)
		Eq(saved.grouped, live.grouped)
		Eq(saved.leader, nil)
		Eq(saved.sampledAt, 1000000101)
		Eq(saved.expiresAt, 1000000226)
		local restored = Peer()
		restored.now = 20
		restored.playerLocationState = { peers = { [name] = { cached = true, mask = 3, receivedAt = 20, lifetime = 300 } } }
		assert(restored:RestorePlayerPartyCacheEntry(name, saved, 20, 1000000111))
		local after = restored:GetPlayerPartyVisualInfo(name)
		Eq(after.size, live.size)
		Eq(after.grouped, live.grouped)
		Eq(after.sampledAt, 10)
		Eq(after.lifetime, 115)
		Eq(restored.known[name], nil)
		Eq(restored:RequestPartyVisualRoster(name), false)
		local again = restored:SavePlayerPartyCacheEntry(name, 30, 1000000121)
		Eq(again.sampledAt, saved.sampledAt)
		Eq(again.expiresAt, saved.expiresAt)
		restored.now = 135
		Eq(restored:GetPlayerPartyVisualInfo(name), nil)
	end
end)
