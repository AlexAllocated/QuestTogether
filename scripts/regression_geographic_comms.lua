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

local QT = _G.QuestTogether
local function Equal(a, b)
	if a ~= b then
		error(tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function BaseFixture(name)
	local a = setmetatable({
		isEnabled = true,
		isLocalDeveloper = true,
		hasLoggedIn = true,
		now = 100,
		sent = {},
		ignored = {},
		name = name or "Me-Realm",
		partyMembers = {},
		partyMemberOrder = {},
		recentCommMessageSignatures = {},
		renders = 0,
		reads = 0,
		position = { x = 0.4, y = 0.6 },
		mapID = 12,
		announcementChannelName = "QuestTogether",
		announcementChannelLocalID = 7,
	}, { __index = QT })
	function a:AnnounceQuestPartnerSearch() end
	a.db = { profile = QT:DeepCopy(QT.DEFAULTS.profile) }
	a.API = {}
	for key, value in pairs(QT.API) do
		if type(value) == "function" then
			a.API[key] = function() end
		end
	end
	function a:PrepareDeveloperPingRequest(request)
		return request
	end
	a.API.GetTime = function()
		return a.now
	end
	a.API.Random = function()
		return 1234
	end
	a.API.RegionalUniqueNamesEnabled = function()
		return a.forever == true
	end
	a.API.GetRealmName = function()
		return "Realm"
	end
	a.API.GetBestMapForUnit = function()
		a.reads = a.reads + 1
		return a.mapID
	end
	a.API.GetPlayerMapPosition = function()
		return a.position
	end
	a.API.UnitClass = function()
		return "Mage", "MAGE"
	end
	a.API.UnitRace = function()
		return "Human"
	end
	a.API.GetFaction = function()
		return "Alliance"
	end
	a.API.UnitLevel = function()
		return 60
	end
	a.API.IsWarModeActive = function()
		a.warModeReads = (a.warModeReads or 0) + 1
		return false
	end
	a.API.IsWarModeFeatureEnabled = function()
		return a.warModeFeature
	end
	a.warModeFeature = true
	a.API.IsOnIgnoredList = function(target)
		return a.ignored[target] == true
	end
	a.API.GetChannelName = function()
		return 7
	end
	a.API.IsInParty = function()
		return a.inParty == true
	end
	a.API.SendAddonMessage = function(prefix, message, route, target)
		a.sent[#a.sent + 1] = { prefix = prefix, message = message, route = route, target = target }
		if a.sendFails or (a.failedRoutes and a.failedRoutes[route]) then
			return false
		end
		local other = a.peersByRoute and a.peersByRoute[route] or a.other
		if other then
			other:OnCommReceived(prefix, message, route, a.name, 7, "QuestTogether")
		end
		return 0
	end
	function a:GetPlayerFullName()
		return self.name
	end
	function a:GetPlayerName()
		return self.name
	end
	function a:GetPlayerClassFile()
		return "MAGE"
	end
	function a:IsRuntimeRestricted()
		return self.restricted == true
	end
	function a:EnsureAnnouncementChannelJoined()
		return true
	end
	function a:RecordCommsDiagnostic() end
	function a:Debug() end
	function a:Debugf() end
	function a:RefreshPlayerLocationPins()
		self.renders = self.renders + 1
	end
	function a:RefreshQTPlayerPartnerIndicators() end
	function a:HidePlayerLocationPins()
		self.hidden = true
	end
	function a:CreateRuntimeCoordinatorFrame()
		return {
			scripts = {},
			IsForbidden = function()
				return false
			end,
			IsProtected = function()
				return false
			end,
			SetScript = function(frame, event, callback)
				frame.scripts[event] = callback
			end,
		}
	end
	a.GetPlayerLocationPriorityOrigin = function()
		return nil
	end
	return a
end

local function Fixture(name)
	local a = BaseFixture(name)
	a.joined, a.left, a.timers = { QuestTogether = 6 }, {}, {}
	a.EnsureAnnouncementChannelJoined = QT.EnsureAnnouncementChannelJoined
	a.API.GetChannelName = function(channel)
		return a.joined[channel]
	end
	a.API.GetServerTime = function()
		return 1700000000 + math.floor(a.now)
	end
	a.API.GetMapInfo = function(id)
		if id == 99 then
			return { mapType = 2, parentMapID = 1 }
		end
		if id == 13 then
			return { mapType = 4, parentMapID = 12 }
		end
		return { mapType = 3, parentMapID = 99 }
	end
	a.API.JoinPermanentChannel = function(channel)
		if not a.joinFails then
			a.joined[channel] = channel == "QuestTogetherZ12" and 7 or 8
		end
	end
	a.API.LeaveChannelByName = function(channel)
		a.left[#a.left + 1] = channel
		a.joined[channel] = nil
	end
	a.API.Delay = function(delay, callback)
		a.timers[#a.timers + 1] = callback
	end
	function a:GetViewedQuestTogetherMapID()
		return self.viewedMap
	end
	function a:IsRuntimeRestrictionTypeActive()
		return self.restricted == true
	end
	function a:RegisterAnnouncementChannelChatFilters() end
	function a:HideAnnouncementChannelFromChatWindows() end
	function a:RefreshQTPlayerPlatePresence() end
	function a:Print() end
	function a:GetAddonVersion()
		return "6.0.0"
	end
	function a:ObserveAddonVersion() end
	a.API.SendAddonMessage = function(prefix, wire, route, target)
		if a.sendFails then
			return 3
		end
		a.sent[#a.sent + 1] = { wire = wire, route = route, target = target }
		if a.other then
			a.other.now = a.now
			local channel
			for n, id in pairs(a.joined) do
				if id == target then
					channel = n
				end
			end
			if route ~= "CHANNEL" or a.other.joined[channel] then
				a.other:ReceiveCommunication(prefix, wire, route, a.name, a.other.joined[channel], channel)
			end
		end
		return 0
	end
	function a:IsGroupedSender()
		return self.inParty == true
	end
	a:InitializeCommunications()
	a:InitializeGeographicComms()
	-- Exercise the same producer/transport ordering as the runtime coordinator.
	function a:UpdateGeographicComms()
		local sampled = QT.UpdateGeographicComms(self)
		self:UpdateCommunicationRuntime()
		return sampled
	end
	return a
end
local function Stage(a, looking)
	a.db.profile.lookingForQuestPartners = looking == true
	a:BroadcastPlayerLocation(true)
	a:BroadcastQTPlayerPresence()
	a:BroadcastQuestPartnerStatus(true)
	a:Publish("QTVR", { version = "6.0.0", count = 13, partySize = 1 })
	a:Publish("QJST", { grouped = "0", invite = true })
end
local function MakeStateDue(a, full)
	local state = a.geographicCommsState
	local key = state.currentChannel or "QuestTogetherZ" .. a.mapID
	state.routes[key] = { nextLocation = a.now, nextMetadata = full and a.now or a.now + 1000 }
	return state.routes[key]
end
local function StateFrames(a, records)
	return assert(a:BuildCommFrames("STATE", { records = records or a:BuildCommunicationStateRecords() }, {
		session = a:GetCommunicationSession(),
		messageId = tostring(a:NextCommunicationSequence()),
		stamp = a:GetAnnouncementServerTime() or 0,
	}))
end
local function DeliverState(a, b, frames)
	local accepted = false
	for _, wire in ipairs(frames or StateFrames(a)) do
		accepted =
			b:ReceiveCommunication(b.commPrefix, wire, "CHANNEL", a.name, b.joined.QuestTogether, "QuestTogether")
	end
	return accepted
end
local function Tick(a, seconds)
	for _ = 1, math.floor(seconds * 5) do
		a.now = a.now + 0.2
		a:UpdateGeographicComms()
	end
end

local function SentRecords(a, operation)
	local groups, out = {}, {}
	for _, row in ipairs(a.sent) do
		local frame, body = a:DecodeCommFrame(row.wire)
		if frame and frame.operation == operation then
			local key = frame.session .. ":" .. frame.messageId .. ":" .. tostring(row.target) .. ":" .. row.route
			local group = groups[key] or { parts = {}, count = 0, frame = frame }
			groups[key] = group
			if not group.parts[frame.part] then
				group.count = group.count + 1
			end
			group.parts[frame.part] = body
			if group.count == frame.total then
				local data = assert(a:DecodeCommRecord(operation, table.concat(group.parts)))
				out[#out + 1] = { data = data, route = row.route, target = row.target, frame = frame }
				groups[key] = nil
			end
		end
	end
	return out
end
local function Topic(records, topic)
	for _, row in ipairs(records) do
		if row.topic == topic then
			return row
		end
	end
end
local function Observe(a, topic, data, name, sequence, lifetime)
	name = name or "Peer-Realm"
	local handlers = {
		LOC = "HandlePlayerLocationMessage",
		QTLF = "HandleQuestPartnerStatusMessage",
		QTVR = "HandleAddonVersionMessage",
		QTPG = "HandlePartyVisualMetadata",
	}
	local observation = a:CreatePeerObservation(name, topic, {
		source = "snapshot",
		age = 0,
		lifetime = lifetime or 600,
		session = "1-1",
		sequence = sequence or 1,
		stamp = a:GetAnnouncementServerTime(),
	})
	return a[handlers[topic]](a, data, name, observation)
end
local function Event(a, text)
	return { eventType = "QUEST_PROGRESS", senderName = a.name, text = text or "progress", questID = 123 }
end

-- Real typed ingress and runtime progression with private frame-rounded native
-- delivery. Tests can lose deliveries without changing native acceptance.
local function CommunicationNetwork(count, questCount, regional)
	local network = QT:CreateTestNetwork({ fps = 20, seed = 817 })
	local peers = {}
	for index = 1, count do
		local a = network:AddPeer(
			regional and ("Player " .. index) or ("Transport" .. index .. "-Realm"),
			{ regional = regional }
		)
		a.packets = {}
		local send = a.API.SendAddonMessage
		a.API.SendAddonMessage = function(...)
			local args = { ... }
			local result = send(...)
			if result == 0 or result == true then
				a.packets[#a.packets + 1] = args[2]
			end
			return result
		end
		function a:BuildQuestCompareEntries()
			local entries = {}
			for id = 1, (questCount or 0) do
				entries[id] = { questId = tostring(id), questTitle = "Quest " .. id, isPushable = true }
			end
			return entries
		end
		function a:QueuePartyQuestCompareRender() end
		a:InitializeCommunications()
		local driver = network:CreateFrame(a)
		driver:SetScript("OnUpdate", function()
			a:UpdateCommunicationRuntime()
		end)
		peers[index] = a
	end
	network.deliveryRule = function(packet)
		local sender = network.byName[packet.sender]
		if sender and sender.drop and sender.drop(packet.wire) then
			return { drop = true }
		end
	end
	return peers, function(seconds)
		network:Advance(seconds)
	end, network
end

QT:RegisterTest("stationary geographic dots use heartbeats while movement and new routes publish promptly", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a.other = b
	a.API.Random = function(low)
		return low
	end
	a:UpdateGeographicSubscriptions()
	b:UpdateGeographicSubscriptions()
	Stage(a, true)
	a.geographicCommsState.nextGlobal = 999
	MakeStateDue(a, true)
	Tick(a, 12)
	assert(#SentRecords(a, "STATE") <= 3, "stationary samples cannot generate one-second publications")
	assert(b.playerLocationState.peers[a.name])
	local before = #SentRecords(a, "STATE")
	a.position.x = 0.41
	Tick(a, 2)
	assert(#SentRecords(a, "STATE") > before)
	Equal(b.playerLocationState.peers[a.name].x, 0.41)
	before = #SentRecords(a, "STATE")
	Tick(a, 12)
	assert(#SentRecords(a, "STATE") > before)
	a.mapID = 45
	Tick(a, 6)
	local found = false
	for _, packet in ipairs(a.sent) do
		if packet.target == a.joined.QuestTogetherZ45 then
			found = true
		end
	end
	assert(found, "new subscriptions must not inherit stationary suppression")
end)

QT:RegisterTest("unavailable channels back off independently without stalling healthy group announcements", function()
	local a = Fixture()
	a.inParty = true
	a.API.SendAddonMessage = function(_, wire, route)
		a.sent[#a.sent + 1] = { wire = wire, route = route }
		return route == "CHANNEL" and false or 0
	end
	assert(
		a:Emit(
			"ANN",
			Event(a),
			{ { distribution = "CHANNEL", channelName = "QuestTogether" }, { distribution = "PARTY" } }
		)
	)
	a.now = 101
	a:UpdateCommunicationRuntime()
	Equal(#a.sent, 2)
	Equal(#a:GetTransportState().queue, 0)
	local party = false
	for _, row in ipairs(a.sent) do
		party = party or row.route == "PARTY"
	end
	assert(party)
	assert(not a:GetTransportState().blockedUntil)
end)

QT:RegisterTest("repeated privacy clears retain normal global heartbeat rather than urgent broadcast storms", function()
	local a = Fixture()
	Stage(a, true)
	a.db.profile.sharePlayerLocation = false
	a:BroadcastPlayerLocation(true)
	local s = a.geographicCommsState
	local route = MakeStateDue(a, true)
	s.nextGlobal, route.nextLocation, route.nextMetadata = 280, 120, 120
	a.now = 105
	a:BroadcastPlayerLocation()
	Equal(s.nextGlobal, 280)
	Equal(route.nextMetadata, 120)
end)

QT:RegisterTest("partner and tracked quest withdrawals cover the geographic publication lifetime", function()
	local a = Fixture()
	a.db.profile.lookingForQuestPartners = true
	a.API.GetActiveTrackedQuestID = function()
		return 123
	end
	function a:GetLocalizedQuestTitle()
		return "Local quest"
	end
	a:BroadcastQuestPartnerStatus(true)
	local s = a.geographicCommsState
	a:RecordQuestPartnerPublication(s.latest.QTLF.data)
	a:RecordQuestPartnerQuestPublication(s.latest.QTLQ.data)
	a.db.profile.lookingForQuestPartners = false
	a.now = 340
	assert(a:BroadcastQuestPartnerStatus())
	Equal(s.latest.QTLF.data.looking, false)
	Equal(s.latest.QTLQ.data.questID, 0)
	Equal(s.latest.QTLF.at, a.now)
	Equal(s.latest.QTLQ.at, a.now)
	a.now = 701
	Equal(a:BroadcastQuestPartnerStatus(), false)
end)

QT:RegisterTest("reload reconciles orphaned QT zone channels without touching unrelated subscriptions", function()
	local a = Fixture()
	a.joined.QuestTogetherZ45 = 8
	a.joined.QuestTogetherZ99 = 9
	a.API.GetChatChannelList = function()
		return {
			1,
			"General",
			false,
			6,
			"QuestTogether",
			false,
			7,
			"QuestTogetherZ12",
			false,
			8,
			"QuestTogetherZ45",
			false,
			9,
			"QuestTogetherZ99",
			false,
			10,
			"QuestTogetherZFriends",
			false,
		}
	end
	a.restricted = true
	a:UpdateGeographicSubscriptions()
	Equal(#a.left, 0)
	a.restricted = false
	a:UpdateGeographicSubscriptions()
	Equal(#a.left, 2)
	assert(a.joined.QuestTogether and a.joined.QuestTogetherZ12)
	for _, name in ipairs(a.left) do
		assert(name == "QuestTogetherZ45" or name == "QuestTogetherZ99")
	end
	a.now = a.now + 2
	a:UpdateGeographicSubscriptions()
	Equal(#a.left, 2)
end)

QT:RegisterTest("new full snapshots replace all old fragments without displacing newer event traffic", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	Stage(a, true)
	a.geographicCommsState.nextGlobal = 999
	local first = MakeStateDue(a, true)
	a:UpdateGeographicComms()
	assert(first.pending)
	assert(a:Emit("ANN", Event(a, "new event"), a:GetGeographicAnnouncementRoutes()))
	a.db.profile.lookingForQuestPartners = false
	a:BroadcastQuestPartnerStatus(true)
	Tick(a, 5)
	Equal(#SentRecords(a, "ANN"), 1)
	local rows = SentRecords(a, "STATE")
	assert(#rows > 0)
	for _, row in ipairs(rows) do
		local status = Topic(row.data.records, "QTLF")
		if status then
			Equal(status.data.looking, false)
		end
	end
end)

QT:RegisterTest("large private comparison batches are paced and cancelled requests never reach native send", function()
	local peers, advance = CommunicationNetwork(2, 1)
	local a, b = peers[1], peers[2]
	local ids = {}
	for i = 1, 30 do
		local ok, id = a:RequestQuestCompare(
			b.name,
			{ onEntry = function() end, onDone = function() end, onTimeout = function() end }
		)
		assert(ok)
		ids[i] = id
	end
	Equal(#a.sent, 0)
	a:CancelCommRequest(ids[1])
	a.pendingQuestCompareRequests[ids[1]] = nil
	advance(3)
	assert(#a.sent > 0 and #a.sent <= 12)
	for _, packet in ipairs(a.sent) do
		local f = assert(a:DecodeCommFrame(packet.wire))
		assert(f.requestId ~= ids[1])
		Equal(packet.route, "WHISPER")
	end
	a:EndCommunicationSession()
	Equal(#a:GetTransportState().queue, 0)
end)

QT:RegisterTest(
	"geographic subscriptions normalize floors and bound map browsing without joining continents",
	function()
		local a = Fixture()
		a.mapID, a.viewedMap = 13, 45
		a:UpdateGeographicSubscriptions()
		Equal(a.geographicCommsState.currentChannel, "QuestTogetherZ12")
		Equal(a.joined.QuestTogetherZ45, nil)
		Tick(a, 6)
		assert(a.joined.QuestTogetherZ45)
		a.viewedMap = 46
		Tick(a, 2)
		assert(a.joined.QuestTogetherZ45)
		Tick(a, 6)
		Equal(a.joined.QuestTogetherZ45, nil)
		assert(a.joined.QuestTogetherZ46)
		a.viewedMap = 99
		Tick(a, 8)
		Equal(a.joined.QuestTogetherZ46, nil)
		Equal(a:GetGeographicZoneID(99), nil)
		a.API.GetMapInfo = function(id)
			return { mapType = 4, parentMapID = id }
		end
		Equal(a:GetGeographicZoneID(13), nil)
		a:ResetGeographicComms()
		Equal(a.joined.QuestTogetherZ12, nil)
		Equal(a.joined.QuestTogether, 6)
	end
)

QT:RegisterTest("geographic subscriptions defer restricted joins and survive exhausted channel slots", function()
	local a = Fixture()
	a.restricted = true
	a:UpdateGeographicSubscriptions()
	Equal(a.joined.QuestTogetherZ12, nil)
	a.restricted, a.joinFails = false, true
	a:UpdateGeographicSubscriptions()
	Equal(a:GetGeographicAnnouncementRoutes()[1].channelName, "QuestTogether")
	a.joinFails = false
	Tick(a, 3)
	Equal(a:GetGeographicAnnouncementRoutes()[1].channelName, "QuestTogetherZ12")
end)

QT:RegisterTest("compact snapshots preserve worldwide dots partner status version and quest counts", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a.other = b
	b.mapID = 45
	b:UpdateGeographicSubscriptions()
	Stage(a, true)
	Equal(#a.sent, 0)
	Tick(a, 15)
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	Equal(b:GetPlayerAddonVersion(a.name), "6.0.0")
	Equal(b:IsPlayerLookingForQuestPartners(a.name), true)
	Equal(b.qtPlayerPresenceState.peerTooltipStats[a.name].count, 13)
	b.now = 300
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), true)
	b.now = b.playerLocationState.peers[a.name].sampledAt + 600
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	for _, packet in ipairs(a.sent) do
		assert(#packet.wire <= 255)
		assert(a:DecodeCommFrame(packet.wire))
	end
end)

QT:RegisterTest(
	"snapshot parser rejects control nesting truncation stale epochs ignored and retired sessions",
	function()
		local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
		Stage(a, true)
		local frames = StateFrames(a)
		assert(DeliverState(a, b, frames))
		for _, wire in ipairs(frames) do
			Equal(b:ReceiveCommunication(b.commPrefix, wire .. "garbage", "CHANNEL", a.name, 6, "QuestTogether"), false)
		end
		Equal(
			a:CopyCommRecord(
				"STATE",
				{ records = { { topic = "ANN", data = Event(a), sampledAt = a:GetAnnouncementServerTime() } } }
			),
			nil
		)
		b.now = 1000
		Equal(DeliverState(a, b, StateFrames(a)), false)
		b.now = 100
		b.ignored[a.name] = true
		Equal(DeliverState(a, b, frames), false)
	end
)

QT:RegisterTest("snapshot fragments may reorder but old publications cannot undo departure", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	local packets = StateFrames(a)
	local reverse = {}
	for i = #packets, 1, -1 do
		reverse[#reverse + 1] = packets[i]
	end
	assert(DeliverState(a, b, reverse))
	Equal(b:IsKnownQTPlayer(a.name), true)
	assert(b:RecordPeerDeparture(a.name, b.now, a:GetCommunicationSession(), a:NextCommunicationSequence()))
	Equal(b:IsKnownQTPlayer(a.name), false)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b.now = b.now + 10
	DeliverState(a, b, packets)
	Equal(b:IsKnownQTPlayer(a.name), false)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("send pacing bounds queues and cancels stale routes while all traffic shares scheduling", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	local routes = a:GetGeographicAnnouncementRoutes()
	for i = 1, 100 do
		a:Emit("ANN", Event(a, "event" .. i), routes)
	end
	assert(#a:GetTransportState().queue <= 96)
	for _ = 1, 10 do
		a:UpdateCommunicationRuntime()
	end
	Equal(#a.sent, 0, "startup has no free token burst")
	a.now = 101
	a:UpdateCommunicationRuntime()
	assert(#a.sent <= 4)
	a.mapID = 45
	Tick(a, 6)
	Equal(#a:GetTransportState().queue, 0)
	a:Emit("ANN", Event(a, "expired"), a:GetGeographicAnnouncementRoutes(), { expires = a.now + 1 })
	a.now = a.now + 2
	a:UpdateCommunicationRuntime()
	Equal(#a:GetTransportState().queue, 0)
end)

QT:RegisterTest("privacy opt out removes packed snapshots and queued location bearing events", function()
	local a = Fixture()
	Stage(a, true)
	a:UpdateGeographicSubscriptions()
	MakeStateDue(a, true)
	a:UpdateGeographicComms()
	assert(#a:GetTransportState().queue > 0)
	a.db.profile.sharePlayerLocation = false
	a:BroadcastPlayerLocation(true)
	for _, row in ipairs(a:GetTransportState().queue) do
		assert(not row.publishesLocation)
	end
	assert(a:SendAnnouncementWireEvent(Event(a, "Private progress")))
	a:BroadcastPlayerLocation(true)
	local count = #a:GetTransportState().queue
	assert(count > 0)
	local location = assert(Topic(a:BuildCommunicationStateRecords(), "LOC"))
	Equal(location.data.mask, 0)
	Equal(location.data.x, nil)
	Tick(a, 3)
	assert(#SentRecords(a, "ANN") > 0)
end)

-- Full crowd-capacity and multi-minute publication/recovery simulations run offline.
QT:RegisterTest("global snapshots are slower than zone updates and do not renew unreadable locations", function()
	local a = Fixture()
	for _ = 1, 30 do
		Stage(a, true)
		Tick(a, 20)
	end
	local global, regional = 0, 0
	for _, row in ipairs(SentRecords(a, "STATE")) do
		if row.target == 6 then
			global = global + 1
		elseif row.target == 7 then
			regional = regional + 1
		end
	end
	assert(global > 0 and global < regional / 2, global .. "/" .. regional)
	a.restricted = true
	a.now = a.now + 40
	Equal(Topic(a:BuildCommunicationStateRecords(), "LOC"), nil)
end, { offline = true })

QT:RegisterTest("native throttle pauses all outgoing work and queue does not survive reset", function()
	local a = Fixture()
	Stage(a, false)
	a.sendFails = true
	Tick(a, 15)
	assert(a:GetTransportState().blockedUntil)
	Equal(#a.sent, 0)
	a.sendFails = false
	Tick(a, 20)
	assert(#a.sent > 0)
	MakeStateDue(a, true)
	a:UpdateGeographicComms()
	local before = #a.sent
	a:ResetGeographicComms()
	a.now = a.now + 5
	a:UpdateCommunicationRuntime()
	Equal(#a.sent, before)
	Equal(#a:GetTransportState().queue, 0)
end)

-- Full crowd-capacity and multi-minute publication/recovery simulations run offline.
QT:RegisterTest("duplicate signature memory is bounded during a many sender burst", function()
	local a = Fixture()
	local frames = assert(
		a:BuildCommFrames(
			"QTPR",
			{ active = true },
			{ session = "1-1", messageId = "1", stamp = a:GetAnnouncementServerTime() }
		)
	)
	for i = 1, 10000 do
		-- Cache capacity spans many frames; the per-frame flood cap has its own test.
		if i % 32 == 1 then
			a:UpdateCommunicationRuntime()
		end
		a:ReceiveCommunication(a.commPrefix, frames[1], "CHANNEL", "Player" .. i .. "-Realm", 6, "QuestTogether")
	end
	local count = 0
	for _ in pairs(a.communicationState.seen) do
		count = count + 1
	end
	Equal(count, 4096)
	local before = a.qtPlayerPresenceState.peers["Player10000-Realm"]
	Equal(a:ReceiveCommunication(a.commPrefix, frames[1], "CHANNEL", "Player10000-Realm", 6, "QuestTogether"), false)
	Equal(a.qtPlayerPresenceState.peers["Player10000-Realm"], before)
end, { offline = true })

QT:RegisterTest("zone events reach current zone and group but never the viewed remote zone", function()
	local a = Fixture()
	a.inParty, a.viewedMap = true, 45
	Tick(a, 8)
	a.sent = {}
	assert(a:SendAnnouncementWireEvent(Event(a, "event")))
	Tick(a, 3)
	local group, zone = false, false
	for _, row in ipairs(SentRecords(a, "ANN")) do
		if row.route == "PARTY" then
			group = true
		else
			Equal(row.target, 7)
			zone = true
		end
	end
	assert(group and zone)
	a.partyRosterFingerprint = "old party"
	assert(a:Emit("ANN", Event(a, "old group"), { { distribution = "PARTY" } }))
	a.partyRosterFingerprint = "replacement party"
	Tick(a, 2)
	for _, row in ipairs(SentRecords(a, "ANN")) do
		assert(row.data.text ~= "old group")
	end
end)

QT:RegisterTest("long snapshot fields fit packets and missing clock never masquerades as measured delay", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	assert(a:Publish("QTLQ", {
		session = a:GetCommunicationSession(),
		sequence = a:NextCommunicationSequence(),
		questID = 123,
		title = string.rep("é", 110),
	}))
	local frames = StateFrames(a)
	assert(#frames > 1)
	for _, wire in ipairs(frames) do
		assert(#wire <= 255)
	end
	assert(DeliverState(a, b, frames))
	Equal(b.qtPlayerPresenceState.partnerQuests[a.name].questID, 123)
	Equal(b.qtPlayerPresenceState.partnerQuests[a.name].title, string.rep("é", 110))
	local c = Fixture("NoClock-Realm")
	c.API.GetServerTime = function()
		return nil
	end
	DeliverState(a, c, frames)
	Equal(#c:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("snapshot retired sessions and delayed coordinates cannot restore obsolete state", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	local old = StateFrames(a)
	assert(DeliverState(a, b, old))
	a.communicationState.session = "1700000120000-5678"
	a.now = 120
	Stage(a, false)
	b.now = 300
	assert(DeliverState(a, b))
	Equal(b.playerLocationState.peers[a.name].sampledAt, 120)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	DeliverState(a, b, old)
	Equal(b.playerLocationState.peers[a.name].sampledAt, 120)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
end)

QT:RegisterTest("delayed geographic envelopes cannot undo a pong and subsequent broadcasts refresh normally", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	local delayed = StateFrames(a)
	b.now = 120
	b:AcceptDeveloperPingResponse({
		senderName = a.name,
		developer = true,
		locationShared = true,
		mapID = "12",
		coordX = "80",
		coordY = "60",
		sampledAt = b:GetAnnouncementServerTime(),
	}, { developerRequest = true, startedAt = 100 })
	DeliverState(a, b, delayed)
	Equal(b.playerLocationState.peers[a.name].x, 0.8)
	Equal(b.playerLocationState.peers[a.name].sampledAt, 120)
	a.now, b.now, a.position.x = 310, 310, 0.9
	Stage(a, true)
	assert(DeliverState(a, b))
	Equal(b.playerLocationState.peers[a.name].x, 0.9)
	Equal(b.playerLocationState.peers[a.name].sampledAt, 310)
	b.now = 909
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	b.now = 910
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("crowded zones back off without unrelated worldwide peers slowing local updates", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	Stage(a, true)
	function a:Emit(_, _, _, options)
		options.onComplete(true, "accepted")
		return true
	end
	local s = a.geographicCommsState
	s.nextGlobal = 999
	for i = 1, 2000 do
		s.peers[tostring(i)] = { zone = 45, at = a.now, expires = a.now + 600 }
	end
	local route = MakeStateDue(a, true)
	a:UpdateGeographicComms()
	Equal(route.nextLocation - a.now, 1)
	for _, peer in pairs(s.peers) do
		peer.zone = 12
	end
	s.density = nil
	route.nextLocation, route.nextMetadata = a.now, a.now
	a:UpdateGeographicComms()
	assert(route.nextLocation - a.now >= 90)
end)

QT:RegisterTest(
	"one-second zone updates resample movement without repeating full metadata or growing queues",
	function()
		local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
		a.other = b
		a.API.Random = function(low)
			return low
		end
		a:UpdateGeographicSubscriptions()
		b:UpdateGeographicSubscriptions()
		Stage(a, true)
		a.geographicCommsState.nextGlobal = 999
		MakeStateDue(a, true)
		Tick(a, 6)
		assert(b.playerLocationState.peers[a.name])
		local before = #SentRecords(a, "STATE")
		for step = 1, 10 do
			a.position.x = 0.4 + step * 0.001
			Tick(a, 1.2)
			assert(#a:GetTransportState().queue <= 4)
		end
		assert(math.abs(b.playerLocationState.peers[a.name].x - a.position.x) < 0.00001)
		local rows = SentRecords(a, "STATE")
		assert(#rows > before + 5)
		for i = before + 1, #rows do
			Equal(rows[i].target, 7)
			assert(Topic(rows[i].data.records, "LOC"))
			Equal(Topic(rows[i].data.records, "QTVR"), nil)
		end
		a.sendFails = true
		a.db.profile.sharePlayerLocation = false
		a:BroadcastPlayerLocation(true)
		for _, pending in ipairs(a:GetTransportState().queue) do
			assert(not pending.publishesLocation)
		end
		a.sendFails = false
		Tick(a, 5)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
	end
)

QT:RegisterTest("metadata heartbeat is independent of movement jitter and survives one-second party traffic", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a.other = b
	a.inParty, b.inParty = true, true
	a.API.Random = function(low)
		return low
	end
	a:UpdateGeographicSubscriptions()
	b:UpdateGeographicSubscriptions()
	Stage(a, true)
	a.geographicCommsState.nextGlobal = 999
	MakeStateDue(a, true)
	for step = 1, 40 do
		a.position.x = 0.4 + step * 0.001
		if step % 10 == 0 then
			Stage(a, true)
		end
		Tick(a, 1.2)
		assert(#a:GetTransportState().queue <= 12)
	end
	local peer = assert(b.playerLocationState.peers[a.name])
	assert(math.abs(peer.x - a.position.x) < 0.006)
	Equal(b:GetPlayerAddonVersion(a.name), "6.0.0")
	Equal(b:IsPlayerLookingForQuestPartners(a.name), true)
	local route = a.geographicCommsState.routes.QuestTogetherZ12
	route.nextLocation, route.nextMetadata = a.now + 40, a.now
	local before = #SentRecords(a, "STATE")
	Tick(a, 3)
	local found = false
	for i = before + 1, #SentRecords(a, "STATE") do
		found = found or Topic(SentRecords(a, "STATE")[i].data.records, "QTVR") ~= nil
	end
	assert(found, "metadata cannot wait for separately jittered location cadence")
end)

QT:RegisterTest("manual developer ping stays global and does not change background zone routing", function()
	local a = Fixture()
	a.inParty = true
	a:UpdateGeographicSubscriptions()
	local ok = a:SendPingRequest()
	Equal(ok, true)
	Tick(a, 2)
	local global, party = false, false
	for _, packet in ipairs(a.sent) do
		local frame = a:DecodeCommFrame(packet.wire)
		if frame and frame.operation == "PING" then
			if packet.route == "PARTY" then
				party = true
			else
				Equal(packet.target, 6)
				global = true
			end
		end
	end
	assert(global and not party)
	Equal(a:GetGeographicAnnouncementRoutes()[2].channelName, "QuestTogetherZ12")
end)

QT:RegisterTest("delayed group and zone event copies deduplicate without merging separate identical actions", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a:UpdateGeographicSubscriptions()
	b:UpdateGeographicSubscriptions()
	local event =
		{ eventType = "QUEST_PROGRESS", senderName = a.name, questId = 12, text = "Progress", occurredAt = 1700000100 }
	assert(a:SendAnnouncementWireEvent(event))
	local first = a:GetTransportState().queue[1].wire
	a:GetTransportState().queue = {}
	assert(a:SendAnnouncementWireEvent(event))
	local second = a:GetTransportState().queue[1].wire
	assert(first ~= second)
	local count = 0
	function b:HandleAnnouncementEvent()
		count = count + 1
	end
	b:OnCommReceived(b.commPrefix, first, "PARTY", a.name)
	b.now = b.now + 20
	b:OnCommReceived(b.commPrefix, first, "CHANNEL", a.name, 7, "QuestTogetherZ12")
	Equal(count, 1)
	b:OnCommReceived(b.commPrefix, second, "CHANNEL", a.name, 7, "QuestTogetherZ12")
	Equal(count, 2)
end)

QT:RegisterTest("party metadata is isolated from older snapshot commands and keeps geographic freshness", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	assert(a:Publish("QTPG", { size = 3, leader = "Alice-Realm", leaderClass = "MAGE", revision = "123" }))
	local old = StateFrames(a)
	assert(DeliverState(a, b, old))
	Equal(b:GetPlayerPartyVisualInfo(a.name).size, 3)
	a.now, b.now = 110, 130
	assert(a:Publish("QTPG", { size = 0 }))
	assert(DeliverState(a, b))
	Equal(b:GetPlayerPartyVisualInfo(a.name).size, 0)
	DeliverState(a, b, old)
	Equal(b:GetPlayerPartyVisualInfo(a.name).size, 0)
end)

QT:RegisterTest("five member hover responses privately complete through the shared transfer budget", function()
	local peers, advance, network = CommunicationNetwork(6, 0)
	local viewer, leader = peers[1], peers[2]
	for i = 2, 6 do
		network:SetGroup(peers[i], "otherparty")
	end
	leader.API.GetPartyVisualLeaderUnit = function()
		return "player"
	end
	function leader:GetUnitFullName()
		return self.name
	end
	leader:BroadcastPartyVisualMetadata()
	local metadata = assert(leader:BuildPartyVisualMetadata())
	assert(ObserveState(viewer, "HandlePartyVisualMetadata", "QTPG", metadata, leader.name))
	assert(viewer:RequestPartyVisualRoster(leader.name))
	Equal(#viewer.sent, 0)
	advance(12)
	Equal(#viewer:GetPlayerPartyVisualInfo(leader.name).members, 5)
	for _, packet in ipairs(leader.sent) do
		Equal(packet.route, "WHISPER")
		Equal(packet.target, viewer.name)
	end
	for i = 3, 6 do
		Equal(#peers[i].received, 0)
	end
end)

-- Full crowd-capacity and multi-minute publication/recovery simulations run offline.
QT:RegisterTest("snapshot bursts retain bounded ordered peers and prune expired entries", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	local frames = StateFrames(a)
	for i = 1, 2200 do
		b:UpdateCommunicationRuntime() -- Each complete snapshot arrives on a later frame.
		a.name = "Peer" .. i .. "-Realm"
		assert(DeliverState(a, b, frames))
	end
	local count = 0
	for _ in pairs(b.geographicCommsState.peers) do
		count = count + 1
	end
	Equal(count, 2048)
	b.now = 701
	Equal(b:GetGeographicZonePopulation(12), 0)
	a.name = "Fresh-Realm"
	a.now = 701
	Stage(a, true)
	assert(DeliverState(a, b))
	Equal(b:GetGeographicZonePopulation(12), 1)
end, { offline = true })

QT:RegisterTest("targeted comparisons whisper complete snapshots privately in Retail and Forever", function()
	for _, regional in ipairs({ false, true }) do
		local peers, advance = CommunicationNetwork(3, 2, regional)
		local a, b, observer = peers[1], peers[2], peers[3]
		local entries, done = {}, 0
		assert(a:RequestQuestCompare(b.name, {
			onEntry = function(row)
				entries[tonumber(row.questId)] = row
			end,
			onDone = function()
				done = done + 1
			end,
			onTimeout = function()
				error("unexpected timeout")
			end,
		}))
		advance(8)
		Equal(done, 1)
		assert(entries[1] and entries[2])
		Equal(#observer.received, 0)
		for _, sender in ipairs({ a, b }) do
			for _, packet in ipairs(sender.sent) do
				Equal(packet.route, "WHISPER")
				Equal(packet.target, sender == a and b.name or a.name)
			end
		end
	end
end)

QT:RegisterTest("queued private comparison is cancelled when its target becomes ignored", function()
	local peers, advance = CommunicationNetwork(2, 2)
	local a, b = peers[1], peers[2]
	local timedOut, entries, completed = 0, 0, 0
	a.transportState.blockedUntil = a.now + 2
	assert(a:RequestQuestCompare(b.name, {
		onEntry = function()
			entries = entries + 1
		end,
		onDone = function()
			completed = completed + 1
		end,
		onTimeout = function()
			timedOut = timedOut + 1
		end,
	}))
	a.ignored[b.name] = true
	advance(4)
	Equal(#a.sent, 0)
	Equal(#b.sent, 0)
	Equal(timedOut, 1)
	Equal(entries, 0)
	Equal(completed, 0)
end)

QT:RegisterTest("snapshot consolidation removes only redundant positive presence", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	assert(a:Publish("QTPR", { active = true }))
	assert(a:Publish("QTVR", { version = "6.1.2", count = 7, partySize = 3 }))
	assert(DeliverState(a, b))
	assert(b:IsKnownQTPlayer(a.name))
	Equal(b:GetPlayerPartySize(a.name), 3)
	assert(a:Publish("QTPR", { active = false }))
	Equal(Topic(a:BuildCommunicationStateRecords(), "QTPR").data.active, false)
	a.now = 281
	assert(a:Publish("QTPR", { active = true }))
	Equal(Topic(a:BuildCommunicationStateRecords(), "QTVR"), nil)
	Equal(Topic(a:BuildCommunicationStateRecords(), "QTPR").data.active, true)
end)

QT:RegisterTest("cold zone discovery advances one shared snapshot without a global solicitation", function()
	local a, b = Fixture("New-Realm"), Fixture("Resident-Realm")
	a.other, b.other = b, a
	a.API.Random = function(low)
		return low
	end
	b.API.Random = a.API.Random
	a:UpdateGeographicSubscriptions()
	b:UpdateGeographicSubscriptions()
	Stage(a)
	Stage(b)
	a.geographicCommsState.nextGlobal, b.geographicCommsState.nextGlobal = 999, 999
	local route = MakeStateDue(b, true)
	route.nextLocation, route.nextMetadata = 999, 170
	for _ = 1, 60 do
		a.now = a.now + 0.2
		a:UpdateGeographicComms()
		b.now = a.now
		b:UpdateGeographicComms()
	end
	assert(a.playerLocationState.peers[b.name])
	Equal(b.geographicCommsState.nextGlobal, 999)
	Equal(#SentRecords(a, "QTDQ"), 1)
	for _, row in ipairs(a.sent) do
		Equal(row.target, 7)
	end
	for _, row in ipairs(b.sent) do
		Equal(row.target, 7)
	end
end)

QT:RegisterTest("zone discovery rejects foreign routes and coalesces arrivals with a response cooldown", function()
	local a = Fixture()
	a.API.Random = function(low)
		return low
	end
	a:UpdateGeographicSubscriptions()
	local s = a.geographicCommsState
	local route = MakeStateDue(a, true)
	route.nextMetadata, s.nextGlobal = 190, 999
	local function Query(name, distribution, channel, zone)
		return a:HandleGeographicDiscovery(
			{ zone = zone or 12 },
			name,
			{ distribution = distribution or "CHANNEL", channelName = channel or "QuestTogetherZ12", localID = 7 }
		)
	end
	for _, context in ipairs({
		{ "CHANNEL", "QuestTogether" },
		{ "WHISPER", "QuestTogetherZ12" },
		{ "PARTY", "QuestTogetherZ12" },
		{ "CHANNEL", "QuestTogetherZ45" },
	}) do
		Equal(Query("Foreign-Realm", context[1], context[2]), false)
		Equal(route.nextMetadata, 190)
	end
	Equal(Query("WrongZone-Realm", nil, nil, 45), false)
	a.ignored["Ignored-Realm"] = true
	Equal(Query("Ignored-Realm"), false)
	a.now = 105
	a:UpdateGeographicDiscovery()
	assert(#a:GetTransportState().queue > 0)
	assert(Query("New-Realm"))
	Equal(route.nextMetadata, 107)
	Equal(s.nextGlobal, 999)
	Equal(#a:GetTransportState().queue, 0)
	for i = 1, 100 do
		a.now = 105 + i / 10
		assert(Query("New" .. i .. "-Realm"))
	end
	Equal(route.nextMetadata, 107)
	Equal(s.discovery[12].responseAt, 105)
	a.now = 165
	route.nextMetadata = 200
	assert(Query("Later-Realm"))
	Equal(route.nextMetadata, 167)
	a.restricted = true
	a.now = 230
	route.nextMetadata = 290
	Equal(Query("Restricted-Realm"), false)
	a.restricted = false
	a.db.profile.sharePlayerLocation = false
	assert(Query("NoShare-Realm"))
	Equal(route.nextMetadata, 290)
end)

QT:RegisterTest("crowded zone discovery samples responders once per minute and never delays a due heartbeat", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	local s = a.geographicCommsState
	for i = 1, 1000 do
		s.peers[tostring(i)] = { zone = 12, at = a.now, expires = a.now + 600 }
	end
	local route = MakeStateDue(a, true)
	route.nextMetadata = 190
	local function Query(name)
		return a:HandleGeographicDiscovery(
			{ zone = 12 },
			name,
			{ distribution = "CHANNEL", channelName = "QuestTogetherZ12" }
		)
	end
	a.API.Random = function(_, high)
		return high
	end
	assert(Query("New-Realm"))
	Equal(route.nextMetadata, 190)
	a.API.Random = function(low)
		return low
	end
	assert(Query("Again-Realm"))
	Equal(route.nextMetadata, 190)
	a.now = 160
	assert(Query("Later-Realm"))
	Equal(route.nextMetadata, 162)
	a.now = 220
	route.nextMetadata = 220
	assert(Query("Last-Realm"))
	Equal(route.nextMetadata, 220)
end)

QT:RegisterTest("discovery waits for its channel and cancels queued queries after changing zones", function()
	local a = Fixture()
	a.API.Random = function(low)
		return low
	end
	a.joinFails = true
	a:UpdateGeographicSubscriptions()
	a.now = 110
	a:UpdateGeographicDiscovery()
	Equal(#a:GetTransportState().queue, 0)
	a.joinFails = false
	a:UpdateGeographicSubscriptions()
	a.db.profile.showPlayerLocations = false
	a:UpdateGeographicDiscovery()
	Equal(#a:GetTransportState().queue, 0)
	a.now = 115
	a.db.profile.showPlayerLocations = true
	a:UpdateGeographicDiscovery()
	Equal(#a:GetTransportState().queue, 1)
	a.mapID = 45
	a.now = 120
	a:UpdateGeographicSubscriptions()
	a.now = 125
	a:UpdateGeographicSubscriptions()
	a:UpdateCommunicationRuntime()
	Equal(#SentRecords(a, "QTDQ"), 0)
	a:UpdateGeographicDiscovery()
	a.now = 126
	a:UpdateCommunicationRuntime()
	local requests = SentRecords(a, "QTDQ")
	Equal(#requests, 1)
	Equal(requests[1].data.zone, 45)
end)

local function CachedLocationFixture(name, now, wall, database)
	local a = Fixture(name or "Viewer-Realm")
	a.now, a.wall = now or 100, wall or 1700000100
	a.API.GetServerTime = function()
		return a.wall
	end
	a.db.global = database or {}
	a.activeCharacterKey = a.name
	return a
end
local function AddCachePosition(a, name, mask)
	local data = {
		mask = mask or 3,
		mapID = 12,
		x = 0.4,
		y = 0.6,
		classFile = "MAGE",
		className = "Mage",
		race = "Human",
		faction = "Alliance",
		level = 60,
	}
	assert(Observe(a, "LOC", data, name or "Peer-Realm", 1, 120))
	return data
end

QT:RegisterTest("reload cache restores validated positions immediately without renewing sample age", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	local peer = a.playerLocationState.peers["Peer-Realm"]
	peer.sampledAt, peer.lifetime = 80, 580 -- A snapshot already twenty seconds old in transit.
	a.now, a.wall = 110, 1700000110
	a:PLAYER_LOGOUT()
	local saved = a.db.global
	Equal(#saved.playerLocationCache.rows, 1)
	local b = CachedLocationFixture(nil, 5, 1700000115, QT:DeepCopy(saved))
	b:InitializePlayerLocations()
	Equal(b.db.global.playerLocationCache, nil)
	local rows = b:GetVisiblePlayerLocations("map")
	Equal(#rows, 1)
	Equal(rows[1].x, 0.4)
	Equal(rows[1].level, 60)
	Equal(rows[1].sampledAt, -30)
	Equal(rows[1].lifetime, 145)
	Equal(#b.sent, 0)
	b.now, b.wall = 15, 1700000125
	b:SavePlayerLocationCache()
	local c = CachedLocationFixture(nil, 2, 1700000130, QT:DeepCopy(b.db.global))
	c:RestorePlayerLocationCache()
	Equal(c.playerLocationState.peers["Peer-Realm"].lifetime, 130)
	c.now = 132
	Equal(#c:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest(
	"reload cache expires overnight and rejects clock rollback different characters and malformed data",
	function()
		local a = CachedLocationFixture()
		AddCachePosition(a)
		a:SavePlayerLocationCache()
		local saved = QT:DeepCopy(a.db.global)
		for _, setup in ipairs({ { nil, 1700086500 }, { nil, 1700000099 }, { "Alt-Realm", 1700000101 } }) do
			local b = CachedLocationFixture(setup[1], 5, setup[2], QT:DeepCopy(saved))
			b:RestorePlayerLocationCache()
			Equal(#b:GetVisiblePlayerLocations("map"), 0)
			Equal(b.db.global.playerLocationCache, nil)
		end
		local b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
		b.db.global.playerLocationCache.savedAt = 1700000110
		b:RestorePlayerLocationCache()
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
		local rows = b.db.global.playerLocationCache.rows
		rows[1].data = "invalid"
		rows[2] = { name = "Fake-Realm", data = "invalid", sampledAt = math.huge, expiresAt = math.huge }
		rows[3] = false
		b:RestorePlayerLocationCache()
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
	end
)

QT:RegisterTest("cached positions respect ignore display consent withdrawal and live replacement", function()
	local a = CachedLocationFixture()
	local wire = AddCachePosition(a)
	AddCachePosition(a, "Withdrawn-Realm", 0)
	AddCachePosition(a, "Ignored-Realm")
	a.ignored["Ignored-Realm"] = true
	a:SavePlayerLocationCache()
	Equal(#a.db.global.playerLocationCache.rows, 1)
	local b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(a.db.global))
	b.ignored["Peer-Realm"] = true
	b:RestorePlayerLocationCache()
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(a.db.global))
	b.db.profile.showPlayerLocations = false
	b:RestorePlayerLocationCache()
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b.db.profile.showPlayerLocations = true
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	wire.x = 0.5
	assert(Observe(b, "LOC", wire, "Peer-Realm", 2))
	Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.5)
	assert(Observe(b, "LOC", { mask = 0 }, "Peer-Realm", 3))
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b:SavePlayerLocationCache()
	Equal(#b.db.global.playerLocationCache.rows, 0)
	b:ResetPlayerLocations()
	b:RestorePlayerLocationCache()
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("reload cache bounds records and preserves earlier live expiry", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	a.now, a.wall = 210, 1700000210
	a:SavePlayerLocationCache()
	local saved = QT:DeepCopy(a.db.global)
	local prototype = saved.playerLocationCache.rows[1]
	for i = 1, 600 do
		local row = QT:DeepCopy(prototype)
		row.name = "Peer" .. i .. "-Realm"
		saved.playerLocationCache.rows[i] = row
	end
	local b = CachedLocationFixture(nil, 3, 1700000211, saved)
	AddCachePosition(b, "Live-Realm")
	b:RestorePlayerLocationCache()
	Equal(#b:GetVisiblePlayerLocations("map"), 512)
	assert(b.playerLocationState.peers["Live-Realm"], "restoration must preserve already received live data")
	b.now = 12
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
end)

QT:RegisterTest("location opt out preserves private comparisons while cancelling queued coordinates", function()
	local peers, advance = CommunicationNetwork(2, 2)
	local a, b = peers[1], peers[2]
	local done = false
	a.transportState.blockedUntil = a.now + 2
	assert(a:RequestQuestCompare(b.name, {
		onEntry = function() end,
		onDone = function()
			done = true
		end,
		onTimeout = function()
			error("timeout")
		end,
	}))
	assert(
		a:Publish(
			"LOC",
			{ mask = 3, mapID = 12, x = 0.4, y = 0.6 },
			{ { distribution = "WHISPER", target = b.name } },
			{ publishesLocation = true }
		)
	)
	a.db.profile.sharePlayerLocation = false
	a:BroadcastPlayerLocation(true)
	advance(8)
	assert(done)
	for _, packet in ipairs(a.sent) do
		local frame = assert(a:DecodeCommFrame(packet.wire))
		assert(frame.operation ~= "LOC")
	end
end)

QT:RegisterTest("reload restores LFQP filtered dots without renewing status or establishing live presence", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	assert(Observe(a, "QTLF", { session = "1-1", sequence = 1, looking = true }, "Peer-Realm", 1, 65))
	a.db.profile.onlyShowQuestPartners = true
	Equal(#a:GetVisiblePlayerLocations("map"), 1)
	a.now, a.wall = 110, 1700000110
	a:SavePlayerLocationCache()
	local b = CachedLocationFixture(nil, 5, 1700000115, QT:DeepCopy(a.db.global))
	b.db.profile.onlyShowQuestPartners = true
	b:RestorePlayerLocationCache()
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
	assert(not b:IsKnownQTPlayer("Peer-Realm"), "cache is not a new live discovery")
	local status = b.qtPlayerPresenceState.questPartners["Peer-Realm"]
	Equal(status.sampledAt, -10)
	Equal(status.lifetime, 50)
	b.now, b.wall = 15, 1700000125
	b:SavePlayerLocationCache()
	local c = CachedLocationFixture(nil, 2, 1700000130, QT:DeepCopy(b.db.global))
	c.db.profile.onlyShowQuestPartners = true
	c:RestorePlayerLocationCache()
	Equal(c.qtPlayerPresenceState.questPartners["Peer-Realm"].lifetime, 35)
	c.now = 37
	Equal(#c:GetVisiblePlayerLocations("map"), 0)
	c.db.profile.onlyShowQuestPartners = false
	Equal(#c:GetVisiblePlayerLocations("map"), 1, "position may outlive independently expiring partner status")
end)

QT:RegisterTest("cached partner status rejects malformed state and yields to live off updates", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	assert(Observe(a, "QTLF", { session = "1-1", sequence = 1, looking = true }, "Peer-Realm", 1, 65))
	a:SavePlayerLocationCache()
	local saved = QT:DeepCopy(a.db.global)
	local b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
	assert(Observe(b, "QTLF", { session = "1-1", sequence = 2, looking = false }, "Peer-Realm", 2, 65))
	b:RestorePlayerLocationCache()
	assert(not b:IsPlayerLookingForQuestPartners("Peer-Realm"))
	Equal(b.qtPlayerPresenceState.questPartners["Peer-Realm"].sequence, 2)
	b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
	b:RestorePlayerLocationCache()
	assert(Observe(b, "QTLF", { session = "1-1", sequence = 2, looking = false }, "Peer-Realm", 2, 65))
	assert(not b:IsPlayerLookingForQuestPartners("Peer-Realm"))
	for _, mutate in ipairs({
		function(p)
			p.session = "1|1-1"
		end,
		function(p)
			p.session = {}
		end,
		function(p)
			p.sequence = 0
		end,
		function(p)
			p.sequence = 1.5
		end,
		function(p)
			p.sequence = math.huge
		end,
		function(p)
			p.sampledAt = 1700000102
		end,
		function(p)
			p.expiresAt = 1700000100
		end,
		function(p)
			p.expiresAt = math.huge
		end,
	}) do
		local db = QT:DeepCopy(saved)
		mutate(db.playerLocationCache.rows[1].partner)
		b = CachedLocationFixture(nil, 5, 1700000101, db)
		b:RestorePlayerLocationCache()
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		assert(not b:IsPlayerLookingForQuestPartners("Peer-Realm"))
	end
end)

QT:RegisterTest("reload partner metadata obeys peer bounds and original sample age", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	assert(Observe(a, "QTLF", { session = "1-1", sequence = 1, looking = true }, "Peer-Realm", 1, 65))
	local status = a.qtPlayerPresenceState.questPartners["Peer-Realm"]
	status.sampledAt, status.lifetime = -70, 600 -- Only ten cache seconds remain despite the long live lifetime.
	a:SavePlayerLocationCache()
	local saved = QT:DeepCopy(a.db.global)
	local prototype = saved.playerLocationCache.rows[1]
	for i = 1, 512 do
		local row = QT:DeepCopy(prototype)
		row.name = "Peer" .. i .. "-Realm"
		saved.playerLocationCache.rows[i] = row
	end
	local b = CachedLocationFixture(nil, 5, 1700000101, saved)
	b.db.profile.onlyShowQuestPartners = true
	b:RestorePlayerLocationCache()
	Equal(#b:GetVisiblePlayerLocations("map"), 256)
	b.now = 14
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b.db.profile.onlyShowQuestPartners = false
	Equal(#b:GetVisiblePlayerLocations("map"), 512)
end)

-- Build party identity with the real revision algorithm before putting its
-- independently received member list into the viewer's cache.
local function AddCachedParty(a, name, count, withMembers)
	local owner = Fixture(name)
	owner.API.GetPartyJoinInfo = function()
		return count > 0, true, count
	end
	owner.API.GetPartyVisualLeaderUnit = function()
		return "player"
	end
	owner.GetUnitFullName = function()
		return name
	end
	owner.partyMembers = { [name] = { classFile = "MAGE" } }
	for i = 2, count do
		owner.partyMembers["Member" .. i .. "-Realm"] = { classFile = "WARRIOR" }
	end
	local payload, info = owner:BuildPartyVisualMetadata()
	assert(payload)
	assert(Observe(a, "QTPG", payload, name, 1))
	if withMembers and info.key then
		a:GetPartyVisualState().rosters[info.key] = { at = a.now, members = QT:DeepCopy(info.members) }
	end
	return info
end

QT:RegisterTest(
	"reload restores cached party identity and small roster without live presence or network queries",
	function()
		local a = CachedLocationFixture()
		AddCachePosition(a)
		local original = AddCachedParty(a, "Peer-Realm", 3, true)
		local party = a:GetPartyVisualState().peers["Peer-Realm"]
		party.sampledAt, party.lifetime = 80, 580
		a:GetPartyVisualState().rosters[original.key].at = 90
		a.now, a.wall = 110, 1700000110
		a:SavePlayerLocationCache()
		local b = CachedLocationFixture(nil, 5, 1700000115, QT:DeepCopy(a.db.global))
		b:RestorePlayerLocationCache()
		local info = b:GetPlayerPartyVisualInfo("Peer-Realm")
		assert(info and info.cached)
		Equal(info.size, 3)
		Equal(info.leader, "Peer-Realm")
		Equal(info.leaderClass, "MAGE")
		Equal(info.key, original.key)
		Equal(#info.members, 3)
		Equal(info.sampledAt, -30)
		Equal(info.lifetime, 145)
		assert(not b:IsKnownQTPlayer("Peer-Realm"))
		assert(not b:RequestPartyVisualRoster("Peer-Realm"))
		Equal(#b.sent, 0)
		b.now, b.wall = 15, 1700000125
		b:SavePlayerLocationCache()
		local c = CachedLocationFixture(nil, 2, 1700000130, QT:DeepCopy(b.db.global))
		c:RestorePlayerLocationCache()
		info = c:GetPlayerPartyVisualInfo("Peer-Realm")
		Equal(info.lifetime, 130)
		Equal(#info.members, 3)
		Equal(c.partyVisualState.rosters[original.key].lifetime, 130)
		c.now = 82 -- The matching revision still confirms the older fetched member list.
		info = c:GetPlayerPartyVisualInfo("Peer-Realm")
		assert(info and info.size == 3)
		Equal(#info.members, 3)
		assert(not c:RequestPartyVisualRoster("Peer-Realm"))
		Equal(#c.sent, 0)
		c.now = 112 -- Original location expires: cached metadata cannot outlive its anchor.
		Equal(c:GetPlayerPartyVisualInfo("Peer-Realm"), nil)
	end
)

QT:RegisterTest("reload party cache preserves QTVR-only solo sizes and yields to live replacements", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	assert(Observe(a, "QTVR", { version = "6.1.2", partySize = 0 }, "Peer-Realm", 1))
	a:SavePlayerLocationCache()
	local saved = QT:DeepCopy(a.db.global)
	local b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
	b:RestorePlayerLocationCache()
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm").size, 0)
	assert(not b:IsKnownQTPlayer("Peer-Realm"))
	AddCachedParty(b, "Peer-Realm", 2, false)
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm").size, 2)
	assert(not b:GetPlayerPartyVisualInfo("Peer-Realm").cached)
	-- Already received live size must survive restoration, even if no live LOC
	-- has arrived yet and the older cached location is otherwise still useful.
	b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
	assert(Observe(b, "QTVR", { version = "6.1.2", partySize = 4 }, "Peer-Realm", 1))
	b:RestorePlayerLocationCache()
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm").size, 4)
	-- A newer live size report also supersedes a cached group identity.
	a = CachedLocationFixture()
	AddCachePosition(a)
	AddCachedParty(a, "Peer-Realm", 3, true)
	a:SavePlayerLocationCache()
	b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(a.db.global))
	b:RestorePlayerLocationCache()
	b.now = 6
	assert(Observe(b, "QTVR", { version = "6.1.2", partySize = 0 }, "Peer-Realm", 1))
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm").size, 0)
end)

QT:RegisterTest("party reload cache validates metadata hashes roster expiry and ignore rules independently", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	AddCachedParty(a, "Peer-Realm", 3, true)
	a:SavePlayerLocationCache()
	local saved = QT:DeepCopy(a.db.global)
	for _, mutate in ipairs({
		function(p)
			p.size = 41
		end,
		function(p)
			p.size = 1.5
		end,
		function(p)
			p.leader = "Broken|Name"
		end,
		function(p)
			p.leaderClass = {}
		end,
		function(p)
			p.revision = "bad"
		end,
		function(p)
			p.sampledAt = 1700000102
		end,
		function(p)
			p.expiresAt = math.huge
		end,
	}) do
		local db = QT:DeepCopy(saved)
		mutate(db.playerLocationCache.rows[1].party)
		local b = CachedLocationFixture(nil, 5, 1700000101, db)
		b:RestorePlayerLocationCache()
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		Equal(b:GetPlayerPartyVisualInfo("Peer-Realm"), nil)
	end
	for _, mutate in ipairs({
		function(r)
			r.members[2].name = r.members[1].name
		end,
		function(r)
			r.members[2].classFile = "HUNTER"
		end, -- Valid label, wrong revision.
		function(r)
			r.members[2].classFile = {}
		end,
		function(r)
			r.sampledAt = 1700000102
		end,
		function(r)
			r.expiresAt = 1700000100
		end,
	}) do
		local db = QT:DeepCopy(saved)
		mutate(db.playerLocationCache.rows[1].party.roster)
		local b = CachedLocationFixture(nil, 5, 1700000101, db)
		b:RestorePlayerLocationCache()
		local info = b:GetPlayerPartyVisualInfo("Peer-Realm")
		Equal(info.size, 3)
		Equal(info.members, nil)
	end
	local b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
	b.ignored["Peer-Realm"] = true
	b:RestorePlayerLocationCache()
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm"), nil)
	Equal(rawget(b, "partyVisualState"), nil)
end)

QT:RegisterTest("large cached groups keep leader only and explicit departures retire cached party identity", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	AddCachedParty(a, "Peer-Realm", 6, true)
	a:SavePlayerLocationCache()
	Equal(a.db.global.playerLocationCache.rows[1].party.roster, nil)
	local b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(a.db.global))
	b:RestorePlayerLocationCache()
	local info = b:GetPlayerPartyVisualInfo("Peer-Realm")
	Equal(info.size, 6)
	Equal(info.leader, "Peer-Realm")
	Equal(info.members, nil)
	b:RecordQTPlayerPresence("Peer-Realm", false)
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm"), nil)
end)

QT:RegisterTest(
	"roster reload expiry follows original revision confirmation including transit not hover or save time",
	function()
		local a = CachedLocationFixture(nil, 500, 1700000500)
		AddCachePosition(a)
		local original = AddCachedParty(a, "Peer-Realm", 3, true)
		local info = a:GetPartyVisualState().peers["Peer-Realm"]
		-- This party revision was sampled fifty seconds before it arrived. Its
		-- matching full roster was fetched much earlier and needs no new transfer.
		info.sampledAt, info.lifetime = 450, 550
		a:GetPartyVisualState().rosters[original.key].at = 100
		a.playerLocationState.peers["Peer-Realm"].lifetime = 600
		for i = 1, 10 do
			a.now = 500 + i
			Equal(#a:GetPlayerPartyVisualInfo("Peer-Realm").members, 3)
		end
		a.wall = 1700000510
		a:SavePlayerLocationCache()
		local cached = a.db.global.playerLocationCache.rows[1].party
		Equal(cached.sampledAt, 1700000450)
		Equal(cached.expiresAt, 1700000630)
		Equal(cached.roster.sampledAt, 1700000450)
		Equal(cached.roster.expiresAt, 1700000630)
		local b = CachedLocationFixture(nil, 10, 1700000520, QT:DeepCopy(a.db.global))
		b:RestorePlayerLocationCache()
		Equal(#b:GetPlayerPartyVisualInfo("Peer-Realm").members, 3)
		for i = 1, 20 do
			b.now = 10 + i
			Equal(#b:GetPlayerPartyVisualInfo("Peer-Realm").members, 3)
		end
		b.wall = 1700000540
		b:SavePlayerLocationCache()
		cached = b.db.global.playerLocationCache.rows[1].party
		Equal(cached.expiresAt, 1700000630)
		Equal(cached.roster.expiresAt, 1700000630)
		local c = CachedLocationFixture(nil, 2, 1700000600, QT:DeepCopy(b.db.global))
		c:RestorePlayerLocationCache()
		Equal(c:GetPlayerPartyVisualInfo("Peer-Realm").lifetime, 30)
		Equal(#c:GetPlayerPartyVisualInfo("Peer-Realm").members, 3)
		c.now = 32
		Equal(c:GetPlayerPartyVisualInfo("Peer-Realm"), nil)
		Equal(#c:GetVisiblePlayerLocations("map"), 1, "fresher position may remain after party confirmation expires")
	end
)

local function RevisionNetwork(count, quests)
	local peers, advance, network = CommunicationNetwork(count, quests)
	for _, a in ipairs(peers) do
		network:SetGroup(a, "party")
	end
	return peers, advance, network
end
local function RefreshRevision(a, b, baseline, force)
	local result = { entries = {}, completed = false }
	local ok, id = a:RequestQuestCompare(b.name, {
		knownRevision = not force and baseline and baseline.revision,
		previousEntries = baseline and baseline.entries,
		onEntry = function(entry)
			result.entries[tonumber(entry.questId)] = entry
		end,
		onDone = function(_, _, _, revision)
			result.completed, result.revision = true, revision
		end,
		onTimeout = function()
			result.timedOut = true
		end,
	})
	assert(ok)
	result.id = id
	return result
end
local function EntryPackets(a, first)
	local objects, count = {}, 0
	for index = (first or 0) + 1, #a.packets do
		local frame, body = a:DecodeCommFrame(a.packets[index])
		if frame and frame.operation == "QCRS" then
			local key = frame.session .. ":" .. frame.messageId
			local object = objects[key] or { parts = {}, count = 0 }
			objects[key] = object
			if not object.parts[frame.part] then
				object.parts[frame.part] = body
				object.count = object.count + 1
			end
			if object.count == frame.total and not object.complete then
				local record = assert(a:DecodeCommRecord("QCRS", table.concat(object.parts)))
				count = count + #record.entries
				object.complete = true
			end
		end
	end
	return count
end

local function ObjectiveRevisionNetwork()
	local peers, advance = RevisionNetwork(2, 1)
	local a, b = peers[1], peers[2]
	b.quest = { questId = "1", questTitle = "Collect supplies", isComplete = false, isPushable = true }
	b.progress = 1
	function b:BuildQuestCompareEntries()
		return self.quest and { self:DeepCopy(self.quest) } or {}
	end
	function b:ReadQuestCompareObjectives()
		return {
			{
				questId = 1,
				objectiveIndex = 1,
				text = "Supplies collected",
				kind = "item",
				finished = false,
				current = self.progress,
				required = 10,
			},
		}
	end
	-- Rendering is outside this protocol fixture. Real member refresh, objective
	-- callbacks, wire codecs, bounded queues and delivery all remain connected.
	function a:QueuePartyQuestCompareRender() end
	local member = { name = b.name, entries = {}, state = "loading" }
	a.partyQuestCompareSession = {
		mode = "party",
		members = { member },
		byName = { [b.name] = member },
		expandedQuestIds = {},
	}
	assert(a:RefreshPartyQuestCompareMember(b.name, false))
	advance(5)
	assert(member.state == "ready" and member.revision)
	return a, b, member, advance
end

local function ExpandRevisionObjective(addon, member)
	addon.partyQuestCompareSession.expandedQuestIds[1] = true
	addon:LoadPartyQuestObjectives(member)
end

local function CollapseRevisionObjective(addon)
	local session = addon.partyQuestCompareSession
	session.expandedQuestIds[1] = nil
	addon:CancelPartyQuestObjectiveRequests(session, 1)
end

-- Full crowd-capacity and multi-minute publication/recovery simulations run offline.
QT:RegisterTest(
	"party comparison auto refresh reacquires an ignored then unignored snapshot before reusing revisions",
	function()
		local a, b, _, advance = ObjectiveRevisionNetwork()
		a.runtimeStateStore = {}
		a.API.IsWorldMapVisible = function()
			return false
		end
		a.partyMemberOrder = { a.name, b.name }
		a.db.profile.compareAutoRefresh = true
		-- Only presentation is private. Exercise the real visible-window freshness
		-- clock, whole-session refresh, ignore event, transport and reply callbacks.
		a.partyQuestCompareWindow = a:CreateTestUIRegion(a)
		a.partyQuestCompareWindow.headerStatuses = {}
		assert(a:RefreshPartyQuestCompare())
		advance(5)
		local function Member()
			return a.partyQuestCompareSession.byName[b.name]
		end
		local function AutoRefresh()
			advance(31)
			local previous = a.partyQuestCompareSession
			a:UpdatePartyQuestCompareFreshness()
			assert(a.partyQuestCompareSession ~= previous, "the visible-window auto refresh must replace its session")
			advance(5)
		end
		local revision = Member().revision
		assert(revision and Member().entries[1])
		local before = #b.packets
		AutoRefresh()
		Equal(Member().state, "ready")
		Equal(EntryPackets(b, before), 0) -- A valid unchanged baseline still saves traffic.
		a.ignored[b.name] = true
		a:IGNORELIST_UPDATE()
		Equal(Member().state, "unavailable")
		Equal(next(Member().entries), nil)
		before = #b.packets
		AutoRefresh()
		Equal(Member().state, "unavailable")
		Equal(#b.packets, before) -- No request is sent while the member stays ignored.
		a.ignored[b.name] = nil
		a:IGNORELIST_UPDATE()
		before = #b.packets
		AutoRefresh()
		Equal(Member().state, "ready")
		Equal(Member().entries[1].questTitle, "Collect supplies")
		Equal(Member().revision, revision)
		Equal(EntryPackets(b, before), 1) -- Unignore must reacquire the discarded list.
		before = #b.packets
		AutoRefresh()
		Equal(Member().state, "ready")
		Equal(EntryPackets(b, before), 0) -- The newly certified baseline can be reused.
		before = #b.packets
		assert(a:RefreshPartyQuestCompare())
		advance(5)
		Equal(Member().state, "ready")
		Equal(EntryPackets(b, before), 1) -- Manual refresh remains explicitly full.
	end,
	{ offline = true }
)

-- Full crowd-capacity and multi-minute publication/recovery simulations run offline.
QT:RegisterTest(
	"objective summary changes retire comparison revisions before changed then restored refreshes",
	function()
		for _, field in ipairs({ "isComplete", "questTitle", "isPushable", "unknownShareability" }) do
			local a, b, member, advance = ObjectiveRevisionNetwork()
			local original, revision, certifiedEntries = b:DeepCopy(b.quest), member.revision, member.entries
			if field == "unknownShareability" then
				b.quest.isPushable = nil
			elseif field == "questTitle" then
				b.quest.questTitle = "Updated supplies"
			elseif field == "isComplete" then
				b.quest.isComplete = true
			else
				b.quest.isPushable = false
			end
			ExpandRevisionObjective(a, member)
			advance(5)
			Equal(member.objectiveDetails[1].state, "ready")
			Equal(member.revision, nil)
			assert(member.entries ~= certifiedEntries, "detail updates cannot mutate a certified snapshot in place")
			Equal(certifiedEntries[1].questTitle, original.questTitle)
			Equal(certifiedEntries[1].isComplete, original.isComplete)
			Equal(certifiedEntries[1].isPushable, original.isPushable)
			CollapseRevisionObjective(a)
			-- The responder legitimately reuses its original revision after the quest
			-- returns to that state; our altered baseline must request the full log.
			b.quest = original
			local before = #b.packets
			assert(a:RefreshPartyQuestCompareMember(b.name, true))
			advance(10)
			Equal(member.state, "ready")
			Equal(EntryPackets(b, before), 1)
			Equal(member.revision, revision)
			Equal(member.entries[1].questTitle, original.questTitle)
			Equal(member.entries[1].isComplete, false)
			Equal(member.entries[1].isPushable, true)
		end
	end,
	{ offline = true }
)

QT:RegisterTest("objective removal then reacquisition recovers through a full conditional comparison", function()
	local a, b, member, advance = ObjectiveRevisionNetwork()
	local original, revision = b.quest, member.revision
	b.quest = nil
	ExpandRevisionObjective(a, member)
	advance(5)
	Equal(member.objectiveDetails[1].state, "ready")
	Equal(member.entries[1], nil)
	Equal(member.revision, nil)
	CollapseRevisionObjective(a)
	b.quest = original
	local before = #b.packets
	assert(a:RefreshPartyQuestCompareMember(b.name, true))
	advance(10)
	Equal(member.state, "ready")
	Equal(EntryPackets(b, before), 1)
	Equal(member.revision, revision)
	Equal(member.entries[1].questTitle, original.questTitle)
end)

QT:RegisterTest(
	"repeated objective progress preserves unchanged comparison certificates and explicit full refresh",
	function()
		local a, b, member, advance = ObjectiveRevisionNetwork()
		local revision = member.revision
		for progress = 2, 3 do
			b.progress = progress
			ExpandRevisionObjective(a, member)
			advance(5)
			Equal(member.objectiveDetails[1].objectives[1].current, progress)
			Equal(member.revision, revision)
			CollapseRevisionObjective(a)
		end
		local before = #b.packets
		assert(a:RefreshPartyQuestCompareMember(b.name, true))
		advance(5)
		Equal(member.state, "ready")
		Equal(member.revision, revision)
		Equal(EntryPackets(b, before), 0)
		before = #b.packets
		assert(a:RefreshPartyQuestCompareMember(b.name, false))
		advance(5)
		Equal(member.state, "ready")
		Equal(EntryPackets(b, before), 1)
	end
)

-- Full crowd-capacity and multi-minute publication/recovery simulations run offline.
QT:RegisterTest("incomplete full comparison replies preserve the certified baseline through timeout", function()
	local a, b, member, advance = ObjectiveRevisionNetwork()
	local revision, entries = member.revision, member.entries
	b.quest.isComplete = true
	function b:BuildQuestCompareEntries()
		local rows = { self:DeepCopy(self.quest) }
		for id = 2, 10 do
			rows[id] = { questId = tostring(id), questTitle = string.rep("Another quest ", 8) }
		end
		return rows
	end
	b.drop = function(wire)
		local frame = b:DecodeCommFrame(wire)
		return frame and frame.operation == "QCRS" and frame.part == 2
	end
	assert(a:RefreshPartyQuestCompareMember(b.name, false))
	advance(10)
	Equal(member.state, "loading")
	Equal(member.entries, entries)
	Equal(member.revision, revision)
	advance(601)
	Equal(member.state, "timeout")
	Equal(member.entries, entries)
	Equal(member.revision, revision)
end, { offline = true })

QT:RegisterTest(
	"revisioned comparisons validate unchanged baselines and force changed or explicit refreshes",
	function()
		local peers, advance = RevisionNetwork(2, 3)
		local a, b = peers[1], peers[2]
		local first = RefreshRevision(a, b)
		advance(5)
		assert(first.completed and first.revision)
		Equal(EntryPackets(b), 3)
		local before = #b.packets
		local unchanged = RefreshRevision(a, b, first)
		advance(3)
		assert(unchanged.completed)
		Equal(unchanged.revision, first.revision)
		Equal(EntryPackets(b, before), 0)
		assert(#b.packets - before <= 3)
		Equal(unchanged.entries[2].questTitle, "Quest 2")
		before = #b.packets
		local forced = RefreshRevision(a, b, first, true)
		advance(5)
		assert(forced.completed)
		Equal(EntryPackets(b, before), 3)
		function b:BuildQuestCompareEntries()
			return { { questId = "2", questTitle = "Updated quest", isPushable = false, isComplete = true } }
		end
		before = #b.packets
		local changed = RefreshRevision(a, b, unchanged)
		advance(4)
		assert(changed.completed and changed.revision ~= first.revision)
		Equal(EntryPackets(b, before), 1)
		Equal(changed.entries[1], nil)
		assert(changed.entries[2].isComplete and changed.entries[2].isPushable == false)
		function b:BuildQuestCompareEntries()
			return {}
		end
		local empty = RefreshRevision(a, b, changed)
		advance(3)
		assert(empty.completed and empty.revision ~= changed.revision)
		Equal(next(empty.entries), nil)
		local sameEmpty = RefreshRevision(a, b, empty)
		advance(3)
		assert(sameEmpty.completed)
		Equal(sameEmpty.revision, empty.revision)
	end
)

QT:RegisterTest("comparison revisions are invalidated by responder world sessions and reloads", function()
	local peers, advance = RevisionNetwork(2, 2)
	local a, b = peers[1], peers[2]
	local first = RefreshRevision(a, b)
	advance(5)
	assert(first.completed)
	b:EndCommsWorldSession()
	b:ResumeCommsWorldSession()
	local before = #b.packets
	local afterZone = RefreshRevision(a, b, first)
	advance(8)
	assert(afterZone.completed and afterZone.revision ~= first.revision)
	Equal(EntryPackets(b, before), 2)
	b.questCompareLocalRevision, b.questCompareResponseCache = nil, nil
	local afterReload = RefreshRevision(a, b, afterZone)
	advance(5)
	assert(afterReload.completed and afterReload.revision ~= afterZone.revision)
end)

QT:RegisterTest(
	"lost unchanged certificates recover without entries and the next refresh observes changed content",
	function()
		local peers, advance = RevisionNetwork(2, 3)
		local a, b = peers[1], peers[2]
		local first = RefreshRevision(a, b)
		advance(5)
		assert(first.completed and first.revision)
		local dropped, before = false, #b.packets
		b.drop = function(wire)
			local frame = b:DecodeCommFrame(wire)
			if not dropped and frame and frame.operation == "QCRS" then
				dropped = true
				return true
			end
		end
		local lost = RefreshRevision(a, b, first)
		advance(3)
		assert(dropped and not lost.completed)
		-- Retry preserves the original request identity and replays its immutable reply.
		advance(12)
		assert(lost.completed and not lost.timedOut)
		Equal(lost.revision, first.revision)
		Equal(EntryPackets(b, before), 0)
		Equal(lost.entries[1].questTitle, "Quest 1")
		Equal(lost.entries[4], nil)
		function b:BuildQuestCompareEntries()
			return { { questId = "4", questTitle = "New quest", isPushable = true } }
		end
		local changed = RefreshRevision(a, b, lost)
		advance(4)
		assert(changed.completed and changed.revision ~= lost.revision)
		Equal(changed.entries[1], nil)
		Equal(changed.entries[4].questTitle, "New quest")
	end
)

QT:RegisterTest("unchanged certificates cannot complete a missing wrong or partial comparison baseline", function()
	local peers, advance = RevisionNetwork(2, 2)
	local a, b = peers[1], peers[2]
	local first = RefreshRevision(a, b)
	advance(5)
	assert(first.completed)
	local result = RefreshRevision(a, b, first)
	local function Certificate(revision, count, sender)
		return a:HandleQuestCompareResponse({
			requestId = result.id,
			senderName = sender or b.name,
			count = count,
			snapshotId = "1-2-3",
			revision = revision,
			unchanged = true,
			entries = {},
		}, sender or b.name)
	end
	Equal(Certificate(first.revision, 2, "Unrelated-Realm"), false)
	Equal(Certificate("8-8-8", 2), false)
	Equal(Certificate(first.revision, 1), false)
	assert(not result.completed)
	a.pendingQuestCompareRequests[result.id] = nil
	result = RefreshRevision(a, b)
	Equal(Certificate(first.revision, 2), false)
	assert(not result.completed)
end)

-- Full crowd-capacity and multi-minute publication/recovery simulations run offline.
QT:RegisterTest(
	"five unchanged party logs refresh with twenty certificates instead of eight hundred quest packets",
	function()
		local peers, advance = RevisionNetwork(5, 40)
		local baseline = {}
		for _, a in ipairs(peers) do
			baseline[a] = {}
			for _, b in ipairs(peers) do
				if a ~= b then
					baseline[a][b] = RefreshRevision(a, b)
				end
			end
		end
		advance(145)
		local firstEntries = 0
		for _, a in ipairs(peers) do
			firstEntries = firstEntries + EntryPackets(a)
			for _, result in pairs(baseline[a]) do
				assert(result.completed and result.revision and not result.timedOut)
			end
			a.packets = {}
		end
		Equal(firstEntries, 800)
		local results = {}
		for _, a in ipairs(peers) do
			for _, b in ipairs(peers) do
				if a ~= b then
					results[#results + 1] = RefreshRevision(a, b, baseline[a][b])
				end
			end
		end
		advance(8)
		for _, result in ipairs(results) do
			assert(result.completed and not result.timedOut)
		end
		local packets = 0
		for _, a in ipairs(peers) do
			packets = packets + #a.packets
			Equal(EntryPackets(a), 0)
		end
		assert(packets <= 100, "unchanged snapshots should remain much smaller than full logs")
	end,
	{ offline = true }
)

QT:RegisterTest("lost comparison responses replay the original immutable quest log", function()
	local peers, advance = RevisionNetwork(2, 8)
	local a, b = peers[1], peers[2]
	local reads = 0
	local build = b.BuildQuestCompareEntries
	function b:BuildQuestCompareEntries()
		reads = reads + 1
		return build(self)
	end
	b.drop = function(wire)
		local f = b:DecodeCommFrame(wire)
		return f and f.operation == "QCRS"
	end
	local result = RefreshRevision(a, b)
	advance(4)
	assert(not result.completed)
	Equal(reads, 1)
	function b:BuildQuestCompareEntries()
		reads = reads + 1
		return { { questId = "99", questTitle = "New acceptance" } }
	end
	b.drop = nil
	advance(20)
	assert(result.completed and not result.timedOut)
	Equal(reads, 1)
	Equal(result.entries[99], nil)
	Equal(result.entries[8].questTitle, "Quest 8")
	local fresh = RefreshRevision(a, b)
	advance(5)
	assert(fresh.completed)
	Equal(fresh.entries[8], nil)
	Equal(fresh.entries[99].questTitle, "New acceptance")
end)

QT:RegisterTest("comparison loss reordering and duplicate fragments publish entries atomically once", function()
	local peers, advance, network = RevisionNetwork(2, 25)
	local a, b = peers[1], peers[2]
	local dropped, entries, done = false, 0, 0
	network.deliveryRule = function(packet)
		local f = b:DecodeCommFrame(packet.wire)
		if packet.sender == b.name and f and f.operation == "QCRS" then
			if f.part == 2 and not dropped then
				dropped = true
				return { drop = true }
			end
			return { copies = 2, delay = f.part % 2 == 0 and 0.02 or 0.2 }
		end
	end
	assert(a:RequestQuestCompare(b.name, {
		onEntry = function()
			entries = entries + 1
		end,
		onDone = function()
			done = done + 1
		end,
		onTimeout = function()
			error("unexpected timeout")
		end,
	}))
	advance(1)
	Equal(entries, 0)
	Equal(done, 0)
	advance(40)
	assert(dropped)
	Equal(entries, 25)
	Equal(done, 1)
	advance(35)
	Equal(entries, 25)
	Equal(done, 1)
end)

QT:RegisterTest("requester world transitions settle real PQL member and objective loading state", function()
	for _, kind in ipairs({ "log", "objectives" }) do
		local peers, advance = RevisionNetwork(2, 1)
		local a, b = peers[1], peers[2]
		local member =
			{ name = b.name, state = "ready", entries = { [1] = { questId = "1" } }, supportsObjectives = true }
		a.partyQuestCompareSession = {
			mode = "party",
			members = { member },
			byName = { [member.name] = member },
			expandedQuestIds = { [1] = true },
		}
		if kind == "log" then
			a:RefreshPartyQuestCompareMember(member.name)
		else
			a:LoadPartyQuestObjectives(member)
		end
		local detail = member.objectiveDetails and member.objectiveDetails[1]
		Equal(kind == "log" and member.state or detail.state, "loading")
		a:EndCommsWorldSession()
		a:ResumeCommsWorldSession()
		advance(3)
		Equal(next(a.pendingQuestCompareRequests), nil)
		if kind == "log" then
			Equal(member.state, "timeout")
		else
			Equal(detail.state, "unknown")
			Equal(member.objectiveRequestQuestId, nil)
		end
	end
end)

QT:RegisterTest("departure cancels old work then spends only existing budget on a bounded goodbye", function()
	local peers, advance, network = CommunicationNetwork(2, 1)
	local a, b = peers[1], peers[2]
	network:Join(a, a.announcementChannelName, true)
	network:Join(b, b.announcementChannelName, true)
	advance(2)
	assert(a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = b.name } }))
	advance(0.1)
	local before = #a.sent
	assert(a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = b.name } }))
	a:EndCommunicationSession()
	local tokens, bytes = a.transportState.tokens, a.transportState.byteTokens
	assert(a:FlushCommunicationDeparture())
	Equal(#a.sent, before + 1)
	local frame = assert(a:DecodeCommFrame(a.sent[#a.sent].wire))
	Equal(frame.operation, "BYE")
	assert(a.transportState.tokens < tokens and a.transportState.byteTokens < bytes)
	local other =
		assert(a:BuildCommFrames("QTPR", { active = true }, { session = "test", messageId = "1", stamp = 0 }))[1]
	Equal(a:SendTransportNow(other, "QTPR", { distribution = "WHISPER", target = b.name }, "departure"), false)
	advance(120)
	Equal(a.transportState.tokens, tokens - 1)
	a.transportState.tokens, a.transportState.byteTokens = 0, 0
	Equal(a:FlushCommunicationDeparture(), false)
	Equal(#a.sent, before + 1)
	a:ResumeCommunicationSession()
	Equal(a.transportState.tokens, 0)
	Equal(a.transportState.byteTokens, 0)
	assert(a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = b.name } }))
	advance(3)
	assert(#a.sent > before + 1)
end)
