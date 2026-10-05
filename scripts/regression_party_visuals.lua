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
	function a:SendWireMessageToAnnouncementRoutes(wire)
		assert(#wire <= 255, "oversized wire")
		self.wire[#self.wire + 1] = wire
		return not self.sendFails
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
local function Deliver(a, wire, sender)
	local command, payload = wire:match("^([^|]+)|(.*)$")
	local handlers = {
		QTPG = "HandlePartyVisualMetadata",
		QPGR = "HandlePartyVisualRosterRequest",
		QPGM = "HandlePartyVisualRosterMember",
	}
	return a[handlers[command]](a, payload, sender)
end
local function Start(a, b, count)
	Group(b, count)
	Eq(b:BroadcastPartyVisualMetadata(), true)
	Eq(Deliver(a, b.wire[1], b.name), true)
	Eq(a:RequestPartyVisualRoster(b.name), true)
	Eq(Deliver(b, a.wire[1], a.name), true)
end
QT:RegisterTest("party visuals exchange a complete reordered roster and reuse it without hover spam", function()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b, 5)
	Eq(#b.wire, 6)
	for i = #b.wire, 2, -1 do
		Eq(Deliver(a, b.wire[i], b.name), true)
	end
	local info = a:GetPlayerPartyVisualInfo(b.name)
	Eq(info.size, 5)
	Eq(info.leader, b.name)
	Eq(#info.members, 5)
	Eq(a:RequestPartyVisualRoster(b.name), false)
	Eq(#a.wire, 1)
	Eq(Deliver(a, b.wire[2], b.name), false) -- completed request cannot mutate its roster
end)
QT:RegisterTest("party visuals isolate partial replies and reject spoofed or changed party responses", function()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b)
	Eq(Deliver(a, b.wire[2], "Impostor-Realm"), false)
	Eq(Deliver(a, b.wire[2], b.name), true)
	Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil)
	Eq(Deliver(a, b.wire[2], b.name), true)
	Group(b, 2)
	b:BroadcastPartyVisualMetadata()
	Deliver(a, b.wire[#b.wire], b.name)
	Eq(Deliver(a, b.wire[3], b.name), false)
	Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil)
end)
QT:RegisterTest("party visuals reject corrupt membership and expire delayed replies and metadata", function()
	local a, b = Peer(), Peer("Leader-Realm")
	Start(a, b)
	local corrupt = b.wire[3]:gsub("Member2", "Stranger")
	Deliver(a, b.wire[2], b.name)
	Deliver(a, corrupt, b.name)
	Eq(Deliver(a, b.wire[4], b.name), false)
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
QT:RegisterTest("party visual decoder rejects invalid headers and caps peer state", function()
	local a = Peer()
	for _, payload in ipairs({
		"1,1,A-Realm,MAGE,1",
		"1,41,A-Realm,MAGE,1",
		"1,0,A-Realm,,",
		"1,3,A-Realm,bad,1",
		"1,3,A|bad,MAGE,1",
		"1,3,A-Realm,MAGE,12345678901",
	}) do
		Eq(a:HandlePartyVisualMetadata(payload, "Other-Realm"), false)
	end
	for i = 1, 600 do
		a:HandlePartyVisualMetadata("1,3,Leader-Realm,MAGE,123", "Peer" .. i .. "-Realm")
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
	Eq(a:IsPartyVisualQueuedWireCurrent(a.wire[1]), true)
	Eq(b:IsPartyVisualQueuedWireCurrent(b.wire[2]), true)
	Group(b, 4)
	Eq(b:IsPartyVisualQueuedWireCurrent(b.wire[2]), false)
	a:ForgetPartyVisualPeer(b.name)
	Eq(a:IsPartyVisualQueuedWireCurrent(a.wire[1]), false)
	Eq(Deliver(a, b.wire[2], b.name), false)
	Eq(a:IsPartyVisualQueuedWireCurrent("ANN|unrelated"), true)
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
	Eq(a:IsPartyVisualQueuedWireCurrent(a.wire[1]), false)
end)
QT:RegisterTest("party roster chunks fit long multilingual full names without truncation", function()
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
