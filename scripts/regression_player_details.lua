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
	a:InitializeCommunications()
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
		b:ReceiveCommunication(row.prefix, row.wire, row.route, a.name)
	end
end
local function Drain(a)
	for _ = 1, 12 do
		a:UpdateCommunicationRuntime()
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

QT:RegisterTest("switching an active hover reuses a teammate's received roster before the new player's metadata reply", function()
	local a, b = Pair()
	Group(b, 3)
	local owner, member = {}, "Member2-Realm"
	a:RecordQTPlayerPresence(member, true)
	assert(a:SetPlayerDetailsInterest(owner, b.name, function() return true end))
	Exchange(a, b)
	a:UpdatePlayerDetailsInterests()
	Exchange(a, b)
	local source = assert(a:GetPlayerPartyVisualInfo(b.name))
	Eq(#source.members, 3)
	Eq(a:GetPartyVisualState().peers[member], nil)
	local sent = #a.sent
	assert(a:SetPlayerDetailsInterest(owner, member, function() return true end))
	local party = assert(a:GetPlayerPartyVisualInfo(member))
	Eq(party.key, source.key)
	Eq(party.members, source.members)
	Eq(party.sampledAt, source.sampledAt)
	for _ = 1, 20 do a:UpdatePlayerDetailsInterests() end
	assert(a.playerDetailsState.pending[member], "missing personal metadata remains independently requestable")
	Eq(next(a:GetPartyVisualState().pending), nil)
	Eq(a:ArePeerFieldsFresh(member, { "QTPG" }, 600), false)
	Drain(a)
	assert(#a.sent > sent)
	for index = sent + 1, #a.sent do
		local frame = assert(a:DecodeCommFrame(a.sent[index].wire))
		Eq(frame.operation, "QTHQ")
		Eq(a.sent[index].target, member)
	end
	Eq(a:GetPlayerPartyVisualInfo(member).members, source.members)
	Eq(a:GetPartyVisualState().peers[member], nil)
	a:ClearPlayerDetailsInterest(owner)
end)

QT:RegisterTest("hover metadata respects privacy and cannot be replaced by older public snapshots", function()
	local a, b = Pair()
	Group(b, 3)
	local old = b:BuildPlayerDetailsRecords()
	local oldContext = {
		session = b:GetCommunicationSession(),
		sequence = b:NextCommunicationSequence(),
		stamp = b:GetAnnouncementServerTime(),
	}
	Group(b, 0)
	b.db.profile.sharePlayerLocation = false
	b.db.profile.lookingForQuestPartners = true
	Eq(a:RequestPlayerDetails(b.name), true)
	Exchange(a, b)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0)
	Eq(a:GetPlayerPartnerQuestID(b.name), nil)
	Eq(rawget(a, "playerLocationState"), nil)
	a:ApplyCommunicationState(old, b.name, oldContext)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0)
	for _, row in ipairs(b.sent) do
		local frame = a:DecodeCommFrame(row.wire)
		assert(frame and frame.operation ~= "LOC")
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
			a:ReceiveCommunication(row.prefix, row.wire, "WHISPER", "Wrong-Realm")
			a:ReceiveCommunication(row.prefix, row.wire, "PARTY", b.name)
		end
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
		local first = original[1]
		a:ReceiveCommunication(first.prefix, first.wire, "WHISPER", b.name)
		a:ReceiveCommunication(first.prefix, first.wire, "WHISPER", b.name)
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
		a.now = a.now + 601
		Deliver(b, a, true)
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
		a:ResetCommsState()
		a:InitializeCommunications()
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
		Drain(a)
		a.now = a.now + 16
		Eq(a:RequestPlayerDetails(b.name), false)
		a.now = a.now + 105
		Eq(a:RequestPlayerDetails(b.name), true)
		a:RecordQTPlayerPresence("Other-Realm", true)
		Eq(a:RequestPlayerDetails("Other-Realm"), false)
		Eq(b:HandlePlayerDetailsMessage("QTHQ", {}, a.name, { requestId = "1-2-3" }), true)
		local queued = #b:GetTransportState().queue
		for i = 1, 100 do
			Eq(b:HandlePlayerDetailsMessage("QTHQ", {}, "Other" .. i .. "-Realm", { requestId = "1-2-" .. i }), false)
		end
		Eq(#b:GetTransportState().queue, queued)
		b.now = b.now + 5
		Eq(b:HandlePlayerDetailsMessage("QTHQ", {}, a.name, { requestId = "1-2-4" }), false)
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
		a:ApplyCommunicationState(b:BuildPlayerDetailsRecords(), b.name, {
			session = b:GetCommunicationSession(),
			sequence = b:NextCommunicationSequence(),
			stamp = b:GetAnnouncementServerTime(),
		})
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
	ObserveState(a, "HandleAddonVersionMessage", "QTVR", { version = "6.1.2", partySize = 0 }, b.name)
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
	Eq(b.geographicCommsState.latest.QTPG.data.size, 0)
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

QT:RegisterTest("hover rejects injected location and duplicate or oversized metadata records", function()
	local a, b = Pair()
	Eq(a:RequestPlayerDetails(b.name), true)
	local id = a.playerDetailsState.pending[b.name].id
	local context = {
		requestId = id,
		session = b:GetCommunicationSession(),
		sequence = b:NextCommunicationSequence(),
		stamp = b:GetAnnouncementServerTime(),
	}
	Eq(
		a:HandlePlayerDetailsMessage("QTHD", { records = { { topic = "LOC", data = { mask = 0 } } } }, b.name, context),
		false
	)
	Eq(rawget(a, "playerLocationState"), nil)
	local record =
		{ topic = "QTHI", data = b:BuildPlayerDetailsIdentityPayload(), sampledAt = b:GetAnnouncementServerTime() }
	Eq(a:HandlePlayerDetailsMessage("QTHD", { records = { record, record } }, b.name, context), false)
	local tooMany = {}
	for i = 1, 8 do
		tooMany[i] = record
	end
	Eq(a:HandlePlayerDetailsMessage("QTHD", { records = tooMany }, b.name, context), false)
	Eq(a:HandlePlayerDetailsMessage("QTHD", { records = {} }, b.name, context), false)
	Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
	local invalid = b:BuildPlayerDetailsIdentityPayload()
	invalid.race = string.rep("x", 97)
	Eq(b:EncodeCommRecord("QTHI", invalid), nil)
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
	b.communicationState.session = string.rep("1", 20) .. "-" .. string.rep("2", 19)
	b.communicationState.sequence = 2000000000
	Eq(a:RequestPlayerDetails(b.name), true)
	Exchange(a, b)
	local row = a:GetPlayerDetailsTooltipRow({ name = b.name })
	Eq(row.classFile, "DEATHKNIGHT")
	Eq(row.level, 13)
	for _, sent in ipairs(b.sent) do
		assert(#sent.wire <= 255)
	end
end)

QT:RegisterTest("partial hover replies retain source age and recover beyond the initial request deadline", function()
	local a, b = Pair()
	Group(b, 3)
	assert(a:RequestPlayerDetails(b.name))
	local pending = a.playerDetailsState.pending[b.name]
	Drain(a)
	local request = a.sent[1]
	Deliver(a, b)
	Drain(b)
	local first = b.out[1]
	assert(first and #b.out > 1)
	assert(a:ReceiveCommunication(first.prefix, first.wire, "WHISPER", b.name))
	Eq(a:GetCommunicationRequestDeadline(pending.id), pending.at + 600)
	local owner = b.playerDetailsState.replies[a.name]
	local sourceAt = owner.at
	assert(not owner.pending)
	a.now, b.now = 130, 130
	-- The original request solicits repair from the immutable retained response;
	-- it must not rebuild its source samples or fail a15-second queue guard.
	b.out = {}
	b:ReceiveCommunication(request.prefix, request.wire, "WHISPER", a.name)
	Drain(b)
	assert(#b.out > 0)
	Deliver(b, a, true)
	local info = assert(a:GetPlayerPartyVisualInfo(b.name))
	Eq(info.size, 3)
	assert(info.sampledAt <= sourceAt + 1 and info.sampledAt < a.now - 20)
	Eq(a.playerDetailsState.pending[b.name], nil)
	b.db.profile.sharePlayerLocation = false
	b.out = {}
	b:ReceiveCommunication(request.prefix, request.wire, "WHISPER", a.name)
	Drain(b)
	Eq(#b.out, 0, "retained replies still obey changed consent")
end)

QT:RegisterTest(
	"active hover obtains complete distant player metadata and party then renews without duplicate requests",
	function()
		local a, b = Pair()
		Group(b, 5)
		b.db.profile.sharePlayerLocation = false
		local map, chat, visible = {}, {}, true
		local function Current()
			return visible
		end
		assert(a:SetPlayerDetailsInterest(map, b.name, Current))
		local pending = assert(a.playerDetailsState.pending[b.name])
		assert(a:SetPlayerDetailsInterest(chat, b.name, Current))
		for _ = 1, 20 do
			a:UpdatePlayerDetailsInterests()
		end
		Eq(a.playerDetailsState.pending[b.name], pending)
		Exchange(a, b)
		Eq(a:GetPlayerPartyVisualInfo(b.name).size, 5)
		Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil)
		a:UpdatePlayerDetailsInterests()
		local id = assert(next(a:GetPartyVisualState().pending))
		for _ = 1, 20 do
			a:UpdatePlayerDetailsInterests()
		end
		Eq(next(a:GetPartyVisualState().pending), id)
		Exchange(a, b)
		local party = a:GetPlayerPartyVisualInfo(b.name)
		Eq(#party.members, 5)
		Eq(a:GetPlayerDetailsTooltipRow({ name = b.name }).level, 13)
		Eq(a:GetFreshPlayerLocation(b.name), nil, "hover must not request or invent hidden coordinates")
		local requests = #a.sent
		a:UpdatePlayerDetailsInterests()
		Eq(#a.sent, requests)
		Group(b, 0)
		a.now, b.now = a.now + 31, b.now + 31
		a:UpdatePlayerDetailsInterests()
		assert(a.playerDetailsState.pending[b.name], "a sustained hover renews stale metadata")
		a:ClearPlayerDetailsInterest(map)
		assert(a.playerDetailsState.pending[b.name], "another visible surface still owns the shared request")
		Exchange(a, b)
		Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0)
		visible = false
		a:UpdatePlayerDetailsInterests()
		Eq(next(a.playerDetailsState.interests), nil)
	end
)

QT:RegisterTest("active hover retries rejected metadata and roster admissions with bounded shared cooldowns", function()
	local a, b = Pair()
	Group(b, 3)
	local calls, blocked = {}, { QTHQ = true, QPGR = true }
	function a:Request(operation, record, routes, options)
		calls[operation] = (calls[operation] or 0) + 1
		if blocked[operation] then
			blocked[operation] = nil
			if options.onComplete then
				options.onComplete(false, "rejected")
			end
			return false, "capacity"
		end
		return QT.Request(self, operation, record, routes, options)
	end
	assert(a:SetPlayerDetailsInterest({}, b.name, function()
		return true
	end))
	Eq(calls.QTHQ, 1)
	for _ = 1, 10 do
		a:UpdatePlayerDetailsInterests()
	end
	Eq(calls.QTHQ, 1)
	a.now = a.now + 2
	a:UpdatePlayerDetailsInterests()
	Eq(calls.QTHQ, 2)
	Exchange(a, b)
	a:UpdatePlayerDetailsInterests()
	Eq(calls.QPGR, 1)
	for _ = 1, 10 do
		a:UpdatePlayerDetailsInterests()
	end
	Eq(calls.QPGR, 1)
	a.now = a.now + 2
	a:UpdatePlayerDetailsInterests()
	Eq(calls.QPGR, 2)
	Exchange(a, b)
	Eq(#a:GetPlayerPartyVisualInfo(b.name).members, 3)
end)

QT:RegisterTest(
	"active hover recovers a throttled entry and cancels obsolete interests before late callbacks",
	function()
		local a, b = Pair()
		local other = Peer("Other-Realm")
		a:RecordQTPlayerPresence(other.name, true)
		local owner, name = {}, b.name
		local function Current()
			return name ~= nil
		end
		assert(a:SetPlayerDetailsInterest(owner, name, Current))
		local old = assert(a.playerDetailsState.pending[name])
		local oldRequest = a.communicationState.requests[old.id]
		name = other.name
		assert(a:SetPlayerDetailsInterest(owner, name, Current))
		Eq(a.communicationState.requests[old.id], nil)
		Eq(a.playerDetailsState.pending[b.name], nil)
		Eq(a.playerDetailsState.pending[name], nil, "second entry observes shared request pacing")
		a.now = a.now + 2
		a:UpdatePlayerDetailsInterests()
		assert(a.playerDetailsState.pending[name], "remaining hovered must retry after shared entry throttle")
		assert(not oldRequest.isCurrent())
		Eq(oldRequest.onResponse({ records = b:BuildPlayerDetailsRecords() }, b.name, { requestId = old.id }), false)
		Eq(a:GetPlayerPartyVisualInfo(b.name), nil)
		name = nil
		a:UpdatePlayerDetailsInterests()
		Eq(next(a.playerDetailsState.interests), nil)
		Eq(next(a.playerDetailsState.pending), nil)
		Eq(next(a.communicationState.requests), nil)
		Drain(a)
		Eq(#a.out, 0, "left and replaced hovers must not drain stale requests")
	end
)

QT:RegisterTest("hover interest stops on ignore restrictions disable reset and callback failure", function()
	for _, mode in ipairs({ "ignored", "blocked", "chatBlocked", "disabled", "reset", "callback" }) do
		local a, b = Pair()
		local valid = true
		assert(a:SetPlayerDetailsInterest({}, b.name, function()
			if not valid then
				error("retired UI owner")
			end
			return true
		end))
		local pending = assert(a.playerDetailsState.pending[b.name])
		local request = a.communicationState.requests[pending.id]
		if mode == "disabled" then
			a.isEnabled = false
		elseif mode == "reset" then
			a:ResetPlayerDetails()
		elseif mode == "callback" then
			valid = false
		elseif mode == "ignored" then
			a.ignored = b.name
		else
			a[mode] = true
		end
		a:UpdatePlayerDetailsInterests()
		Eq(a.communicationState.requests[pending.id], nil, mode)
		assert(not request.isCurrent())
		Drain(a)
		Eq(#a.out, 0, mode)
	end
end)

QT:RegisterTest(
	"hover roster assembly honors extended coordinator deadlines without replacement or partial exposure",
	function()
		local a, b = Pair()
		Group(b, 5)
		for index = 2, 5 do
			b.partyMembers["Member" .. index .. "-Realm"] = nil
			b.partyMembers[string.rep("名", 18) .. index .. "-Realm"] = { classFile = "WARRIOR" }
		end
		assert(a:SetPlayerDetailsInterest({}, b.name, function()
			return true
		end))
		Exchange(a, b)
		a:UpdatePlayerDetailsInterests()
		local id, pending = next(a:GetPartyVisualState().pending)
		assert(id and pending)
		Drain(a)
		Deliver(a, b)
		Drain(b)
		local rest, first = {}, nil
		for _, packet in ipairs(b.out) do
			local frame = b:DecodeCommFrame(packet.wire)
			if frame.operation == "QPGM" and not first then
				first = packet
			else
				rest[#rest + 1] = packet
			end
		end
		assert(first and #rest > 0, "actual roster transfer must contain multiple native datagrams")
		assert(a:ReceiveCommunication(first.prefix, first.wire, first.route, b.name))
		Eq(a:GetCommunicationRequestDeadline(id), pending.at + 600)
		a.now, b.now = a.now + 65, b.now + 65
		Eq(a:RequestPartyVisualRoster(b.name, true), false, "partial transfer retains its existing identity")
		Eq(a:GetPartyVisualState().pending[id], pending)
		Eq(a:GetPlayerPartyVisualInfo(b.name).members, nil)
		b.out = rest
		Deliver(b, a, true)
		Eq(#a:GetPlayerPartyVisualInfo(b.name).members, 5)
		Eq(a:GetPartyVisualState().pending[id], nil)
	end
)

QT:RegisterTest(
	"active hover retries unanswered metadata without the inactive peer backoff and bounds owners",
	function()
		local a, b = Pair()
		local owner = {}
		assert(a:SetPlayerDetailsInterest(owner, b.name, function()
			return true
		end))
		local old = assert(a.playerDetailsState.pending[b.name])
		Drain(a)
		a.out = {}
		a.now = old.sentAt + 29
		a:UpdateCommunicationRuntime()
		a:UpdatePlayerDetailsInterests()
		Eq(a.communicationState.requests[old.id], nil)
		Eq(a.playerDetailsState.pending[b.name], old)
		a.now = old.sentAt + 30
		a:UpdatePlayerDetailsInterests()
		local renewed = assert(a.playerDetailsState.pending[b.name])
		assert(renewed ~= old and renewed.id ~= old.id, "active interest must recover without waiting two minutes")
		for _ = 1, 7 do
			assert(a:SetPlayerDetailsInterest({}, b.name, function()
				return true
			end))
		end
		Eq(
			a:SetPlayerDetailsInterest({}, b.name, function()
				return true
			end),
			false
		)
		local count = 0
		for _ in pairs(a.playerDetailsState.interests) do
			count = count + 1
		end
		Eq(count, 8)
		Eq(a.playerDetailsState.pending[b.name], renewed, "more owners must not duplicate the request")
	end
)

local function PartialHoverResponse(blockAfterFirst)
	local a, b = Pair()
	Group(b, 3)
	assert(a:ApplyCommunicationState(b:BuildPlayerDetailsRecords(), b.name, {
		session = b:GetCommunicationSession(), sequence = b:NextCommunicationSequence(), stamp = b:GetAnnouncementServerTime(),
	}))
	a.now, b.now = 131, 131
	local owner, completions, callbacks = {}, {}, {}
	function a:Request(operation, record, routes, options)
		if operation == "QTHQ" then
			local id, complete = options.requestId, options.onComplete
			callbacks[id] = complete
			options.onComplete = function(...)
				completions[id] = (completions[id] or 0) + 1
				return complete(...)
			end
		end
		return QT.Request(self, operation, record, routes, options)
	end
	if blockAfterFirst then
		local send, sent = b.API.SendAddonMessage, 0
		b.API.SendAddonMessage = function(prefix, wire, route, target)
			local frame = assert(b:DecodeCommFrame(wire))
			if frame.operation == "QTHD" then
				if sent > 0 and not b.releaseDetails then return 3 end
				sent = sent + 1
			end
			return send(prefix, wire, route, target)
		end
	end
	assert(a:SetPlayerDetailsInterest(owner, b.name, function() return true end))
	local pending = assert(a.playerDetailsState.pending[b.name])
	local request = assert(a.communicationState.requests[pending.id])
	Drain(a)
	Deliver(a, b)
	Drain(b)
	local first, frames = nil, b.out
	b.out = {}
	for _, packet in ipairs(frames) do
		local frame = assert(b:DecodeCommFrame(packet.wire))
		if frame.operation == "QTHD" and not first then first = packet end
	end
	assert(first and a:ReceiveCommunication(first.prefix, first.wire, first.route, b.name))
	Eq(a:GetCommunicationRequestDeadline(pending.id), pending.at + 600)
	return a, b, owner, pending, request, first, frames, completions, callbacks
end

QT:RegisterTest("active hover replaces an abandoned partial metadata reply and retires its buffers and callbacks", function()
	local a, b, _, pending, request, _, frames, completions, callbacks = PartialHoverResponse()
	Eq(#b.commTransferState.outgoing, 1)
	Group(b, 0)
	b:UpdateCommunicationRuntime()
	Eq(#b.commTransferState.outgoing, 0, "changed party retires the real retained response")
	local progress = assert(a:GetCommunicationRequestProgress(pending.id))
	local originalAt = progress.lastProgressAt
	progress.lastProgressAt = 999999
	Eq(a:GetCommunicationRequestProgress(pending.id).lastProgressAt, originalAt, "query returns owned copies")
	a.now, b.now = originalAt + 89, originalAt + 89
	a:UpdateCommunicationRuntime()
	a:UpdatePlayerDetailsInterests()
	Eq(a.playerDetailsState.pending[b.name], pending, "ordinary repair and status probes retain the request")
	a.now, b.now = originalAt + 90, originalAt + 90
	a:UpdateCommunicationRuntime()
	a:UpdatePlayerDetailsInterests()
	local renewed = assert(a.playerDetailsState.pending[b.name])
	assert(renewed ~= pending and renewed.id ~= pending.id)
	Eq(a:GetCommunicationRequestProgress(pending.id), nil)
	Eq(a:GetCommTransferMetrics().incoming, 0)
	Eq(a:GetCommTransferMetrics().bytes, 0, "cancelled response payload is freed immediately")
	local attempt = a.playerDetailsState.attempts[b.name]
	callbacks[pending.id](false)
	Eq(a.playerDetailsState.attempts[b.name], attempt, "retired send callback cannot change replacement retry state")
	assert(not request.onResponse({ records = b:BuildPlayerDetailsRecords() }, b.name, { requestId = pending.id }))
	for _, packet in ipairs(frames) do a:ReceiveCommunication(packet.prefix, packet.wire, packet.route, b.name) end
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 3, "retired fragments cannot install a response")
	Exchange(a, b)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0)
	Eq(a.playerDetailsState.pending[b.name], nil)
	Eq(completions[pending.id], 1)
	Eq(completions[renewed.id], 1, "each actual request completes its native submission once")
end)

QT:RegisterTest("cancelled hover metadata reenters after short pacing and the responder serves a new request identity", function()
	local a, b, owner, pending, request, _, frames = PartialHoverResponse()
	assert(a:GetCommTransferMetrics().incoming > 0)
	a:ClearPlayerDetailsInterest(owner)
	Eq(a:GetCommTransferMetrics().incoming, 0)
	Eq(a:GetCommTransferMetrics().bytes, 0)
	local at = a.now
	assert(a:SetPlayerDetailsInterest(owner, b.name, function() return true end))
	Eq(a.playerDetailsState.pending[b.name], nil)
	a.now, b.now = at + 1.9, at + 1.9
	a:UpdatePlayerDetailsInterests()
	Eq(a.playerDetailsState.pending[b.name], nil)
	Group(b, 0)
	a.now, b.now = at + 2, at + 2
	a:UpdatePlayerDetailsInterests()
	local renewed = assert(a.playerDetailsState.pending[b.name])
	assert(renewed.id ~= pending.id)
	assert(not request.onResponse({ records = b:BuildPlayerDetailsRecords() }, b.name, { requestId = pending.id }))
	for _, packet in ipairs(frames) do a:ReceiveCommunication(packet.prefix, packet.wire, packet.route, b.name) end
	Exchange(a, b)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 0, "completed old reply must not impose another thirty second cooldown")
	Eq(a.playerDetailsState.pending[b.name], nil)
	local previous = b.playerDetailsState.replies[a.name]
	assert(previous and not previous.pending)
	-- Even a new identity cannot exceed the shared five-second reply cadence.
	Eq(b:HandlePlayerDetailsMessage("QTHQ", {}, "Other-Realm", { requestId = "other-hover" }), false)
	b.now = previous.at + 5
	Eq(b:HandlePlayerDetailsMessage("QTHQ", {}, a.name, { requestId = renewed.id }), false)
	Eq(b:HandlePlayerDetailsMessage("QTHQ", {}, a.name, { requestId = "fresh-hover" }), true)
	b.now = previous.at + 10
	Eq(b:HandlePlayerDetailsMessage("QTHQ", {}, a.name, { requestId = "pending-duplicate" }), false,
		"pending response still excludes competing replacement work")
end)

QT:RegisterTest("active hover preserves a queued live metadata transfer and only accepted correlated progress renews it", function()
	local a, b, _, pending, _, first = PartialHoverResponse(true)
	local progress = assert(a:GetCommunicationRequestProgress(pending.id))
	local firstAt, deadline = progress.lastProgressAt, progress.expires
	local frame = assert(b:DecodeCommFrame(first.wire))
	a.now, b.now = firstAt + 65, firstAt + 65
	assert(not a:ReceiveCommunication(first.prefix, first.wire, first.route, b.name))
	Eq(a:GetCommunicationRequestProgress(pending.id).lastProgressAt, firstAt, "duplicate data is not progress")
	a:UpdateCommunicationRuntime()
	a:UpdatePlayerDetailsInterests()
	Deliver(a, b)
	Drain(b)
	local status
	for _, packet in ipairs(b.out) do
		local control, body = b:DecodeCommFrame(packet.wire)
		if control.operation == "FXSTAT" and b:DecodeCommRecord(control.operation, body).status == "sending" then
			status = packet
		end
	end
	assert(status, "a genuinely queued response reports that it is still sending")
	assert(not a:ReceiveCommunication(status.prefix, status.wire, status.route, "Wrong-Realm"))
	Eq(a:GetCommunicationRequestProgress(pending.id).lastProgressAt, firstAt)
	Deliver(b, a)
	local statusAt = a:GetCommunicationRequestProgress(pending.id).lastProgressAt
	Eq(statusAt, a.now)
	local forged = assert(b:BuildCommFrames("FXSTAT", {
		session = frame.session, messageId = "wrong-object", status = "sending",
	}, { session = b:GetCommunicationSession(), messageId = tostring(b:NextCommunicationSequence()), stamp = b:GetAnnouncementServerTime() }))
	local unsolicited = assert(b:BuildCommFrames("FXSTAT", {
		session = frame.session, messageId = frame.messageId, status = "sending",
	}, { session = b:GetCommunicationSession(), messageId = tostring(b:NextCommunicationSequence()), stamp = b:GetAnnouncementServerTime() }))
	local fractionalEnd = assert(b:BuildCommFrames("FXEND", {
		session = frame.session, messageId = frame.messageId, status = "0.1",
	}, { session = b:GetCommunicationSession(), messageId = tostring(b:NextCommunicationSequence()), stamp = b:GetAnnouncementServerTime() }))
	a.now, b.now = firstAt + 100, firstAt + 100
	assert(not a:ReceiveCommunication(b.commPrefix, forged[1], "WHISPER", b.name))
	assert(not a:ReceiveCommunication(b.commPrefix, fractionalEnd[1], "WHISPER", b.name),
		"fractional completion rounds cannot manufacture unbounded liveness")
	assert(not a:ReceiveCommunication(b.commPrefix, unsolicited[1], "WHISPER", b.name),
		"one status reply consumes its probe; a new packet identity cannot replay the same liveness")
	a:ReceiveCommunication(status.prefix, status.wire, status.route, b.name)
	Eq(a:GetCommunicationRequestProgress(pending.id).lastProgressAt, statusAt, "duplicate or mismatched status cannot renew progress")
	a:UpdatePlayerDetailsInterests()
	Eq(a.playerDetailsState.pending[b.name], pending, "status liveness preserves a healthy queued response")
	Eq(a:GetCommunicationRequestDeadline(pending.id), deadline, "liveness never extends the absolute deadline")
	b.releaseDetails = true
	Drain(b)
	Deliver(b, a)
	Eq(a.playerDetailsState.pending[b.name], nil)
	Eq(a:GetPlayerPartyVisualInfo(b.name).size, 3)
	Eq(a:GetCommTransferMetrics().incoming, 0)
end)

QT:RegisterTest("explicit metadata cancellation frees incoming payload and queued probes after correlation retirement", function()
	local a, b, _, pending = PartialHoverResponse()
	a.now = a.now + 31
	a:UpdateCommTransfers()
	local incoming = assert(next(a.commTransferState.incoming))
	local item = a.commTransferState.incoming[incoming]
	local queued = false
	for _, row in ipairs(a:GetTransportState().queue) do if row.owner == item then queued = true end end
	assert(queued, "an incoming assembly owns its queued probe")
	a.communicationState.requests[pending.id] = nil
	a:CancelCommRequest(pending.id, "cancelled")
	Eq(a:GetCommTransferMetrics().incoming, 0)
	Eq(a:GetCommTransferMetrics().bytes, 0)
	assert(item.retired)
	for _, row in ipairs(a:GetTransportState().queue) do assert(row.owner ~= item) end
	a:CancelCommRequest(pending.id, "cancelled")
	Eq(a:GetCommTransferMetrics().bytes, 0, "repeated cancellation cannot release bytes twice")
end)
