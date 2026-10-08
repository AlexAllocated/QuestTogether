-- Isolated addon peers use production codecs, request queues and dispatch.
local QT = _G.QuestTogether
local function Eq(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end
local function Noop() end
local function Peer(name, forever)
	local a = setmetatable({
		name = name,
		now = 100,
		isEnabled = true,
		hasLoggedIn = true,
		partyMembers = {},
		partyMemberOrder = {},
		partyRosterFingerprint = "solo",
		count = 0,
		db = { profile = QT:DeepCopy(QT.DEFAULTS.profile), global = {} },
		out = {},
		recentCommMessageSignatures = {},
		runtimeStateStore = {},
		sent = {},
	}, { __index = QT })
	a.API = {}
	for key, value in pairs(QT.API) do
		if type(value) == "function" then
			a.API[key] = Noop
		end
	end
	a.API.GetTime = function()
		return a.now
	end
	a.API.GetServerTime = function()
		return 1800000000 + math.floor(a.now)
	end
	a.API.Random = function(low)
		return low
	end
	a.API.GetRealmName = function()
		return "Realm"
	end
	a.API.RegionalUniqueNamesEnabled = function()
		return forever
	end
	a.API.GetPartyJoinInfo = function()
		return a.count > 0, a.count > 0, a.count, a.count > 0
	end
	a.API.GetPartyVisualLeaderUnit = function()
		return "player"
	end
	a.API.GetPlayerRaceID = function()
		return 3
	end
	a.API.UnitClass = function()
		return "Mage", "MAGE"
	end
	a.API.UnitRace = function()
		return "Dwarf"
	end
	a.API.UnitLevel = function()
		return 13
	end
	a.API.GetFaction = function()
		return "Alliance"
	end
	a.API.GetActiveTrackedQuestID = function()
		return 123
	end
	a.API.SendAddonMessage = function(prefix, wire, route, target)
		assert(#wire <= 255 and route == "WHISPER", "details must stay bounded and direct")
		local row = { prefix = prefix, wire = wire, route = route, target = target }
		a.out[#a.out + 1], a.sent[#a.sent + 1] = row, row
		return a.sendFails and 3 or 0
	end
	a.API.LeaveChannelByName = Noop
	function a:GetPlayerFullName()
		return self.name
	end
	function a:GetUnitFullName()
		return self.name
	end
	function a:GetAddonVersion()
		return "6.1.2"
	end
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	function a:IsRuntimeRestrictionTypeActive()
		return self.chatBlocked == true
	end
	function a:IsIgnoredPlayerName(n)
		return n == self.ignored
	end
	function a:GetLocalizedQuestTitle()
		return "A Local Quest"
	end
	function a:RefreshQTPlayerPlatePresence() end
	function a:RefreshQTPlayerPartnerIndicators() end
	function a:QueuePartyJoinPrompt() end
	function a:Debugf() end
	function a:Debug() end
	function a:Print() end
	a:InitializeGeographicComms()
	return a
end
local function Group(a, count)
	a.count = count
	a.partyMembers = count > 0 and { [a.name] = { classFile = "MAGE" } } or {}
	for i = 2, count do
		a.partyMembers["Member" .. i .. "-Realm"] = { classFile = "WARRIOR" }
	end
	a.partyRosterFingerprint = tostring(count)
	local state = rawget(a, "partyVisualState")
	if state then
		state.localAt = nil
	end
end
local function Deliver(a, b, reverse)
	local out = a.out
	a.out = {}
	for n = 1, #out do
		local row = out[reverse and #out + 1 - n or n]
		Eq(row.target, b.name)
		b:OnCommReceived(row.prefix, row.wire, row.route, a.name)
	end
end
local function Drain(a)
	for _ = 1, 12 do
		a:DrainGeographicQueue()
		a.now = a.now + 0.25
	end
end
local function Exchange(a, b)
	Drain(a)
	Deliver(a, b)
	Drain(b)
	Deliver(b, a, true)
end
local function Pair(forever)
	local a, b =
		Peer(forever and "Jane Doe" or "Jane-Realm", forever), Peer(forever and "John Smith" or "John-Realm", forever)
	a:RecordQTPlayerPresence(b.name, true)
	return a, b
end

QT:RegisterTest(
	"hover details discover unknown party identity by bounded whispers and reuse member roster exchange",
	function()
		for _, forever in ipairs({ false, true }) do
			local a, b = Pair(forever)
			Group(b, 3)
			b.db.profile.lookingForQuestPartners = true
			local globalAt, localAt = b.geographicCommsState.nextGlobal, b.geographicCommsState.nextLocal
			Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
			Eq(a:RequestPlayerDetails(b.name), true)
			for _ = 1, 100 do
				Eq(a:RequestPlayerDetails(b.name), false)
			end
			Exchange(a, b)
			local party = a:GetPlayerPartyVisualInfo(b.name)
			Eq(party.size, 3)
			Eq(party.leader, b.name)
			Eq(party.members, nil)
			Eq(a:GetPlayerAddonVersion(b.name), "6.1.2")
			Eq(a:IsPlayerLookingForQuestPartners(b.name), true)
			Eq(a:GetPlayerPartnerQuestID(b.name), 123)
			Eq(a:RequestPartyVisualRoster(b.name), true)
			Exchange(a, b)
			Eq(#a:GetPlayerPartyVisualInfo(b.name).members, 3)
			Eq(b.geographicCommsState.nextGlobal, globalAt)
			Eq(b.geographicCommsState.nextLocal, localAt)
			Eq(next(b.geographicCommsState.latest), nil)
			Eq(a:RequestPlayerDetails(b.name), false)
			Group(b, 0)
			b.db.profile.lookingForQuestPartners = false
			a.now, b.now = a.now + 31, b.now + 31
			Eq(a:RequestPlayerDetails(b.name), true)
			Exchange(a, b)
			Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0)
			Eq(a:IsPlayerLookingForQuestPartners(b.name), false)
			Eq(a:GetPlayerPartnerQuestID(b.name), nil)
		end
	end
)

QT:RegisterTest("hover metadata respects privacy and cannot be replaced by older public snapshots", function()
	local a, b = Pair()
	Group(b, 3)
	local old = b:BuildPlayerDetailsPackets()
	Group(b, 0)
	b.db.profile.sharePlayerLocation = false
	b.db.profile.lookingForQuestPartners = true
	Eq(a:RequestPlayerDetails(b.name), true)
	Exchange(a, b)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0)
	Eq(a:GetPlayerPartnerQuestID(b.name), nil)
	Eq(rawget(a, "playerLocationState"), nil)
	for _, packet in ipairs(old) do
		a:HandleGeographicSnapshot(packet:sub(6), b.name)
	end
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0)
	for _, row in ipairs(b.sent) do
		assert(not row.wire:find("LOC|", 1, true))
	end
end)

QT:RegisterTest(
	"hover replies reject wrong senders expired fragments wrong routes duplicates and reset lifetimes",
	function()
		local a, b = Pair()
		Group(b, 3)
		Eq(a:RequestPlayerDetails(b.name), true)
		Drain(a)
		Deliver(a, b)
		Drain(b)
		local original = b.out
		assert(#original > 1)
		for _, row in ipairs(original) do
			a:OnCommReceived(row.prefix, row.wire, "WHISPER", "Wrong-Realm")
			a:OnCommReceived(row.prefix, row.wire, "PARTY", b.name)
		end
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
		local first = original[1]
		a:OnCommReceived(first.prefix, first.wire, "WHISPER", b.name)
		a:OnCommReceived(first.prefix, first.wire, "WHISPER", b.name)
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
		a.now = a.now + 16
		Deliver(b, a, true)
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
		a:ResetCommsState()
		a:InitializeGeographicComms()
		b.out = original
		Deliver(b, a)
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
	end
)

QT:RegisterTest(
	"hover request and response limits bound busy clients and leave old peers on normal discovery",
	function()
		local a, b = Pair()
		Eq(a:RequestPlayerDetails(b.name), true)
		a.now = a.now + 16
		Eq(a:RequestPlayerDetails(b.name), false)
		a.now = a.now + 105
		Eq(a:RequestPlayerDetails(b.name), true)
		a:RecordQTPlayerPresence("Other-Realm", true)
		Eq(a:RequestPlayerDetails("Other-Realm"), false)
		Eq(b:HandlePlayerDetailsMessage("QTHQ", "1,1-2-3", a.name), true)
		local queued = #b:GetTransportState().queue
		for i = 1, 100 do
			Eq(b:HandlePlayerDetailsMessage("QTHQ", "1,1-2-" .. i, "Other" .. i .. "-Realm"), false)
		end
		Eq(#b:GetTransportState().queue, queued)
		b.now = b.now + 5
		Eq(b:HandlePlayerDetailsMessage("QTHQ", "1,1-2-4", a.name), false)
	end
)

QT:RegisterTest("hover queued work stops for ignore privacy restrictions disable and changed party", function()
	for _, mode in ipairs({ "ignore", "privacy", "restricted", "chat", "party", "disabled" }) do
		local a, b = Pair()
		Eq(a:RequestPlayerDetails(b.name), true)
		Drain(a)
		Deliver(a, b)
		if mode == "ignore" then
			b.ignored = a.name
		elseif mode == "privacy" then
			b.db.profile.sharePlayerLocation = false
		elseif mode == "restricted" then
			b.blocked = true
		elseif mode == "chat" then
			b.chatBlocked = true
		elseif mode == "party" then
			Group(b, 2)
		else
			b.isEnabled = false
			b:ResetCommsState()
			b:InitializeGeographicComms()
		end
		Drain(b)
		Eq(#b.out, 0)
	end
end)

QT:RegisterTest(
	"hover refresh reuses recent public metadata and does not probe self unknown or ignored names",
	function()
		local a, b = Pair()
		Eq(a:RequestPlayerDetails(a.name), false)
		Eq(a:RequestPlayerDetails("Unknown-Realm"), false)
		a.ignored = b.name
		Eq(a:RequestPlayerDetails(b.name), false)
		a.ignored = nil
		for _, packet in ipairs(b:BuildPlayerDetailsPackets()) do
			a:HandleGeographicSnapshot(packet:sub(6), b.name)
		end
		Eq(a:RequestPlayerDetails(b.name), false)
		Eq(#a:GetTransportState().queue, 0)
	end
)

QT:RegisterTest("hovering restored dots can discover live details without cached live presence", function()
	local a, b = Pair()
	a.qtPlayerPresenceState = nil
	a.playerLocationState = { peers = { [b.name] = { mask = 3, receivedAt = a.now, lifetime = 80 } } }
	Eq(a:IsKnownQTPlayer(b.name), false)
	Eq(a:RequestPlayerDetails(b.name), true)
	Eq(a:IsKnownQTPlayer(b.name), false)
	Exchange(a, b)
	Eq(a:IsKnownQTPlayer(b.name), true)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0)
end)

QT:RegisterTest("fresh party size alone cannot suppress hover repair of missing status metadata", function()
	local a, b = Pair()
	a:HandleAddonVersionMessage("2,6.1.2,,0", b.name)
	Eq(a:RequestPlayerDetails(b.name), true)
	Exchange(a, b)
	Eq(a:RequestPlayerDetails(b.name), false)
	Eq(a:GetQTPlayerPresenceState().questPartners[b.name].looking, false)
end)

QT:RegisterTest("private party advertisements participate in normal solo withdrawals", function()
	local a, b = Pair()
	Group(b, 3)
	Eq(a:RequestPlayerDetails(b.name), true)
	Exchange(a, b)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 3)
	Group(b, 0)
	Eq(b:BroadcastPartyVisualMetadata(), true)
	assert(b.geographicCommsState.latest.QTPG.wire:find("QTPG|1,0,,,", 1, true))
end)

QT:RegisterTest("hover fills private chat tooltip identity without requiring location sharing", function()
	local a, b = Pair()
	b.db.profile.sharePlayerLocation = false
	Eq(a:RequestPlayerDetails(b.name), true)
	Exchange(a, b)
	local base = a:GetChatLogPlayerTooltipRow(b.name)
	local row = a:GetPlayerDetailsTooltipRow(base)
	Eq(base.level, nil)
	Eq(row.level, 13)
	Eq(row.race, "Dwarf")
	Eq(row.classFile, "MAGE")
	Eq(row.faction, "Alliance")
	Eq(row.mapID, nil)
	Eq(row.x, nil)
	Eq(rawget(a, "playerLocationState"), nil)
	local fresh = { name = b.name, level = 14, receivedAt = a.now + 1 }
	Eq(a:GetPlayerDetailsTooltipRow(fresh), fresh)
	a:RecordQTPlayerPresence(b.name, false)
	Eq(a:GetPlayerDetailsTooltipRow(base), base)
end)

QT:RegisterTest("hover rejects injected location envelopes and oversized or inconsistent chunks", function()
	local a, b = Pair()
	Eq(a:RequestPlayerDetails(b.name), true)
	local id = a.playerDetailsState.pending[b.name].id
	local wire = "LOC|1,100-1,1,0"
	local packet = "QTB1|1,1800000100,100-1,1;0," .. #wire .. ":" .. wire
	local body = #packet .. ":" .. packet
	Eq(a:HandlePlayerDetailsMessage("QTHD", "1," .. id .. ",1,1;" .. body, b.name), false)
	Eq(rawget(a, "playerLocationState"), nil)
	a.now = a.now + 121
	Eq(a:RequestPlayerDetails(b.name), true)
	id = a.playerDetailsState.pending[b.name].id
	Eq(a:HandlePlayerDetailsMessage("QTHD", "1," .. id .. ",1,9;x", b.name), false)
	Eq(a:HandlePlayerDetailsMessage("QTHD", "1," .. id .. ",1,2;" .. string.rep("x", 176), b.name), false)
	Eq(a:HandlePlayerDetailsMessage("QTHD", "1," .. id .. ",1,2;x", b.name), true)
	Eq(a:HandlePlayerDetailsMessage("QTHD", "1," .. id .. ",2,3;x", b.name), false)
	Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
end)

QT:RegisterTest("hover metadata preserves long UTF8 names across fragment boundaries", function()
	local a = Peer("Reader-Realm")
	local b = Peer(string.rep("Ж", 48) .. "-Realm")
	Group(b, 5)
	b.db.profile.lookingForQuestPartners = true
	b.GetLocalizedQuestTitle = function()
		return string.rep("界", 70)
	end
	a:RecordQTPlayerPresence(b.name, true)
	Eq(a:RequestPlayerDetails(b.name), true)
	Exchange(a, b)
	Eq(a:GetPlayerPartyVisualInfo(b.name).leader, b.name)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 5)
	Eq(a:GetPlayerPartnerQuestID(b.name), 123)
	for _, row in ipairs(b.sent) do
		assert(#row.wire <= 255)
	end
end)

QT:RegisterTest("hover identity stays inside snapshot envelopes even with long localized labels", function()
	local a, b = Pair()
	b.API.UnitRace = function()
		return string.rep("Ж", 40)
	end
	b.API.UnitClass = function()
		return string.rep("界", 26), "DEATHKNIGHT"
	end
	b.geographicCommsState.session = string.rep("1", 20) .. "-" .. string.rep("2", 19)
	b.geographicCommsState.sequence = 2000000000
	Eq(a:RequestPlayerDetails(b.name), true)
	Exchange(a, b)
	local row = a:GetPlayerDetailsTooltipRow({ name = b.name })
	Eq(row.classFile, "DEATHKNIGHT")
	Eq(row.level, 13)
	for _, sent in ipairs(b.sent) do
		assert(#sent.wire <= 255)
	end
end)
