local QT = _G.QuestTogether
local function Equal(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
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
	function a:PrepareDeveloperPingRequest(request) return request end
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
	function a:CreatePlayerLocationUpdateFrame()
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
				a.other:OnCommReceived(prefix, wire, route, a.name, a.other.joined[channel], channel)
			end
		end
		return 0
	end
	a:InitializeGeographicComms()
	return a
end
local function Stage(a, looking)
	a.db.profile.lookingForQuestPartners = looking == true
	a:BroadcastPlayerLocation(true)
	a:BroadcastQTPlayerPresence()
	a:BroadcastQuestPartnerStatus(true)
	a:SendWireMessageToAnnouncementRoutes("QTVR|2,6.0.0,13,1")
	a:SendWireMessageToAnnouncementRoutes("QJST|1,1000-1234," .. math.floor(a.now) .. ",0,1")
end
local function Tick(a, seconds)
	for _ = 1, math.floor(seconds * 5) do
		a.now = a.now + 0.2
		a:UpdateGeographicComms()
	end
end

QT:RegisterTest("stationary geographic dots use heartbeats while movement and new routes publish promptly", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a.other = b
	a.API.Random = function(low) return low end
	a:UpdateGeographicSubscriptions(); b:UpdateGeographicSubscriptions()
	Stage(a, true)
	local s = a.geographicCommsState
	s.nextLocal, s.nextLocalMetadata, s.nextGlobal = a.now, a.now, a.now + 1000
	Tick(a, 12)
	assert(#a.sent <= 3, "stationary player must not broadcast identical one-second positions")
	assert(b.playerLocationState.peers[a.name])
	local before = #a.sent
	a.position.x = 0.41
	Tick(a, 1.4)
	assert(#a.sent > before and b.playerLocationState.peers[a.name].x == 0.41)
	before = #a.sent
	Tick(a, 12)
	assert(#a.sent > before, "metadata heartbeats must renew stationary dots")
	a.mapID = 45
	Tick(a, 4)
	local found = false
	for _, packet in ipairs(a.sent) do if packet.target == a.joined.QuestTogetherZ45 then found = true end end
	assert(found, "a new subscription must not inherit another route's stationary suppression")
end)

QT:RegisterTest("unavailable channels back off independently without stalling healthy group announcements", function()
	local a = Fixture()
	a.inParty = true
	a.API.SendAddonMessage = function(_, wire, route)
		a.sent[#a.sent + 1] = { wire = wire, route = route }
		if route == "CHANNEL" then return false end
		return 0
	end
	a:QueueGeographicWire("ANN|unavailable", "event", { distribution = "CHANNEL", channelName = "QuestTogether" }, false)
	a:QueueGeographicWire("ANN|healthy", "event", { distribution = "PARTY" }, false)
	a:DrainGeographicQueue()
	a.now = a.now + 0.2
	a:DrainGeographicQueue()
	Equal(#a.sent, 2)
	Equal(a.sent[2].route, "PARTY")
	Equal(#a.geographicCommsState.queue, 1)
	assert(not a.geographicCommsState.blockedUntil)
end)

QT:RegisterTest("repeated privacy clears retain normal global heartbeat rather than urgent broadcast storms", function()
	local a = Fixture()
	Stage(a, true)
	a.db.profile.sharePlayerLocation = false
	a:BroadcastPlayerLocation(true)
	local s = a.geographicCommsState
	s.nextGlobal, s.nextLocal, s.nextLocalMetadata = a.now + 180, a.now + 20, a.now + 20
	a.now = a.now + 5
	a:BroadcastPlayerLocation()
	Equal(s.nextGlobal, 280)
	Equal(s.nextLocalMetadata, 120)
end)

QT:RegisterTest("partner and tracked quest withdrawals cover the geographic publication lifetime", function()
	local a = Fixture()
	a.db.profile.lookingForQuestPartners = true
	a.API.GetActiveTrackedQuestID = function() return 123 end
	function a:GetLocalizedQuestTitle() return "Local quest" end
	a:BroadcastQuestPartnerStatus(true)
	a.db.profile.lookingForQuestPartners = false
	a.now = a.now + 240
	assert(a:BroadcastQuestPartnerStatus())
	local s = a.geographicCommsState
	assert(s.latest.QTLF.wire:match(",0$"))
	assert(s.latest.QTLQ.wire:match(",0,$"))
	Equal(s.latest.QTLF.at, a.now)
	Equal(s.latest.QTLQ.at, a.now)
	a.now = a.now + 361
	Equal(a:BroadcastQuestPartnerStatus(), false)
end)

QT:RegisterTest("reload reconciles orphaned QT zone channels without touching unrelated subscriptions", function()
	local a = Fixture()
	a.joined.QuestTogetherZ45 = 8
	a.joined.QuestTogetherZ99 = 9
	a.API.GetChatChannelList = function()
		return { 1, "General", false, 6, "QuestTogether", false, 7, "QuestTogetherZ12", false,
			8, "QuestTogetherZ45", false, 9, "QuestTogetherZ99", false, 10, "QuestTogetherZFriends", false }
	end
	a.restricted = true
	a:UpdateGeographicSubscriptions()
	Equal(#a.left, 0)
	a.restricted = false
	a:UpdateGeographicSubscriptions()
	Equal(#a.left, 2)
	assert(a.joined.QuestTogether and a.joined.QuestTogetherZ12)
	for _, name in ipairs(a.left) do assert(name == "QuestTogetherZ45" or name == "QuestTogetherZ99") end
	a.now = a.now + 2
	a:UpdateGeographicSubscriptions()
	Equal(#a.left, 2)
end)

QT:RegisterTest("new full snapshots replace all old fragments without displacing newer event traffic", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	Stage(a, true)
	local s = a.geographicCommsState
	local route = { distribution = "CHANNEL", channelName = "QuestTogetherZ12", requiresChannelJoin = true }
	a:QueueGeographicWire("QTB1|obsolete", "snapshot", route, true, "QuestTogetherZ12:state:9")
	a:QueueGeographicWire("ANN|preserve", "event", route, false)
	s.nextGlobal, s.nextLocalMetadata = a.now + 1000, a.now
	a:UpdateGeographicComms()
	for _, packet in ipairs(a.sent) do assert(packet.wire ~= "QTB1|obsolete") end
	for _, packet in ipairs(s.queue) do assert(packet.wire ~= "QTB1|obsolete") end
	Equal(a.sent[1].wire, "ANN|preserve")
end)

QT:RegisterTest("large party comparison requests are paced and cancelled requests never leave the queue", function()
	local a = Fixture()
	a.inParty = true
	a.pendingQuestCompareRequests = {}
	local ids = {}
	for i = 1, 39 do
		local name = "Peer" .. i .. "-Realm"
		a.partyMembers[name] = {}
		local sent, id = a:RequestQuestCompare(name, { routes = { { distribution = "PARTY" } } })
		assert(sent)
		ids[i] = id
	end
	Equal(#a.sent, 0)
	a.pendingQuestCompareRequests[ids[1]] = nil
	for _ = 1, 110 do a.now = a.now + 0.2; a:DrainGeographicQueue() end
	Equal(#a.sent, 38)
	for _, packet in ipairs(a.sent) do
		Equal(packet.route, "PARTY")
		assert(not packet.wire:find(ids[1] .. ",", 1, true))
	end
	Equal(#a.geographicCommsState.queue, 0)
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
	a.other, b.mapID = b, 45
	b:UpdateGeographicSubscriptions()
	Stage(a, true)
	Equal(#a.sent, 0) -- storage is not delivery
	Tick(a, 15)
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	Equal(b:GetPlayerAddonVersion("Alice-Realm"), "6.0.0")
	Equal(b:IsPlayerLookingForQuestPartners("Alice-Realm"), true)
	Equal(b.qtPlayerPresenceState.peerTooltipStats["Alice-Realm"].count, 13)
	-- Far-zone data outlives old 65/120-second expiry without inventing updates.
	b.now = 300
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	Equal(b:IsPlayerLookingForQuestPartners("Alice-Realm"), true)
	b.now = b.playerLocationState.peers[a.name].sampledAt + 600
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	Equal(b:IsPlayerLookingForQuestPartners("Alice-Realm"), false)
	for _, packet in ipairs(a.sent) do
		assert(#packet.wire <= 255)
		assert(packet.wire:match("^QTB1|") or packet.wire == "QTDQ|1,12")
	end
end)

QT:RegisterTest(
	"snapshot parser rejects control nesting truncation stale epochs ignored and retired sessions",
	function()
		local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
		Stage(a, true)
		local packets = a:BuildGeographicSnapshots()
		for _, packet in ipairs(packets) do
			Equal(b:HandleGeographicSnapshot(packet:sub(6), a.name), true)
			Equal(b:HandleGeographicSnapshot(packet:sub(6) .. "garbage", a.name), false)
		end
		Equal(b:HandleGeographicSnapshot("1,1700000100,123-456,1;0,8:ANN|text", a.name), false)
		Equal(b:HandleGeographicSnapshot("1,1700000100,123-456,1;0,9:QTB1|test", a.name), false)
		b.now = 1000
		Equal(b:HandleGeographicSnapshot(packets[1]:sub(6), a.name), false)
		b.now = 100
		b.ignored[a.name] = true
		Equal(b:HandleGeographicSnapshot(packets[1]:sub(6), a.name), false)
	end
)

QT:RegisterTest("snapshot fragments may reorder but old publications cannot undo departure", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	local packets = a:BuildGeographicSnapshots()
	for i = #packets, 1, -1 do
		assert(b:HandleGeographicSnapshot(packets[i]:sub(6), a.name))
	end
	Equal(b:IsKnownQTPlayer(a.name), true)
	a.other = b
	a:BroadcastQTPlayerPresence(true)
	a:BroadcastPlayerLocation(true, true)
	a:FlushGeographicDeparture()
	Equal(b:IsKnownQTPlayer(a.name), false)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	b.now = b.now + 10
	for _, packet in ipairs(packets) do
		b:HandleGeographicSnapshot(packet:sub(6), a.name)
	end
	Equal(b:IsKnownQTPlayer(a.name), false)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("send pacing bounds queues and cancels stale routes while all traffic shares scheduling", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	local routes = a:GetGeographicAnnouncementRoutes()
	for i = 1, 100 do
		a:QueueGeographicWire("ANN|event" .. i, "event", routes[1], false)
	end
	Equal(#a.geographicCommsState.queue, 96)
	for _ = 1, 10 do
		a:DrainGeographicQueue()
	end
	Equal(#a.sent, 4)
	Equal(a:TakeCommsSendToken(false), false) -- Player actions share the fair queue rather than bypassing it.
	a.mapID = 45
	Tick(a, 4)
	Equal(#a.geographicCommsState.queue, 0)
	a:QueueGeographicWire("ANN|expired", "event", a:GetGeographicAnnouncementRoutes()[1], false)
	a.now = a.now + 31
	a:DrainGeographicQueue()
	Equal(#a.geographicCommsState.queue, 0)
end)

QT:RegisterTest("privacy opt out removes packed snapshots and queued location bearing events", function()
	local a = Fixture()
	Stage(a, true)
	a:UpdateGeographicSubscriptions()
	a:QueueGeographicWire("ANN|old position", "event", a:GetGeographicAnnouncementRoutes()[1], false)
	a:QueueGeographicWire(a:BuildGeographicSnapshots()[1], "snapshot", a:GetGeographicAnnouncementRoutes()[1], true)
	a.db.profile.sharePlayerLocation = false
	a:BroadcastPlayerLocation(true)
	Equal(#a.geographicCommsState.queue, 0)
	assert(
		a:SendAnnouncementWireEvent({ eventType = "QUEST_PROGRESS", senderName = a.name, text = "Private progress" })
	)
	a:BroadcastPlayerLocation(true) -- repeated clears must not cancel newly redacted events
	Equal(#a.geographicCommsState.queue, 1)
	local packets = a:BuildGeographicSnapshots()
	assert(table.concat(packets):find("LOC|1,", 1, true))
	assert(not table.concat(packets):find("0.40000", 1, true))
end)

QT:RegisterTest("global snapshots are slower than zone updates and do not renew unreadable locations", function()
	local a = Fixture()
	for _ = 1, 30 do
		Stage(a, true)
		Tick(a, 20)
	end
	local global, regional = 0, 0
	for _, packet in ipairs(a.sent) do
		if packet.target == 6 then
			global = global + 1
		elseif packet.target == 7 then
			regional = regional + 1
		end
	end
	assert(global > 0 and global < regional / 2, global .. "/" .. regional)
	-- Map read failure cannot perpetuate the last known point in fresh snapshots.
	a.restricted = true
	a.now = a.now + 40
	local packets = a:BuildGeographicSnapshots()
	assert(not table.concat(packets):find("LOC|", 1, true))
end)

QT:RegisterTest("native throttle pauses all outgoing work and queue does not survive reset", function()
	local a = Fixture()
	Stage(a, false)
	a.sendFails = true
	Tick(a, 15)
	assert(a.geographicCommsState.blockedUntil)
	Equal(#a.sent, 0)
	a.sendFails = false
	Tick(a, 20)
	assert(#a.sent > 0)
	a:ScheduleGeographicPingReply(
		"test",
		{ { distribution = "CHANNEL", requiresChannelJoin = true, channelName = "QuestTogether" } }
	)
	local before = #a.sent
	a:ResetGeographicComms()
	for _, callback in ipairs(a.timers) do
		callback()
	end
	Equal(#a.sent, before)
end)

QT:RegisterTest("duplicate signature memory is bounded during a many sender burst", function()
	local a = Fixture()
	for i = 1, 10000 do
		a:ShouldSuppressDuplicateCommMessage("Player" .. i .. "-Realm", "ANN|" .. i)
	end
	local count = 0
	for _ in pairs(a.recentCommMessageSignatures) do
		count = count + 1
	end
	Equal(count, 4096)
	Equal(a:ShouldSuppressDuplicateCommMessage("Player10000-Realm", "ANN|10000"), true)
end)

QT:RegisterTest("zone events reach current zone and group but never the viewed remote zone", function()
	local a = Fixture()
	a.inParty, a.viewedMap = true, 45
	Tick(a, 8)
	a.sent = {}
	assert(a:SendWireMessageToAnnouncementRoutes("ANN|event", "event"))
	Tick(a, 3)
	local group, zone = false, false
	for _, packet in ipairs(a.sent) do
		if packet.wire == "ANN|event" then
			if packet.route == "PARTY" then
				group = true
			else
				Equal(packet.target, 7)
				zone = true
			end
		end
	end
	assert(group and zone)
	a.partyRosterFingerprint = "old party"
	assert(a:SendWireMessageToAnnouncementRoutes("ANN|old group", "event", { { distribution = "PARTY" } }))
	a.partyRosterFingerprint = "replacement party"
	Tick(a, 2)
	for _, packet in ipairs(a.sent) do
		assert(packet.wire ~= "ANN|old group")
	end
end)

QT:RegisterTest("long snapshot fields fit packets and missing clock never masquerades as measured delay", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	a:SendWireMessageToAnnouncementRoutes("QTLQ|1,1000-1234,1,123," .. string.rep("é", 110))
	a.API.GetServerTime = function()
		return nil
	end
	for _, packet in ipairs(a:BuildGeographicSnapshots()) do
		assert(#packet <= 255)
		assert(b:HandleGeographicSnapshot(packet:sub(6), a.name))
	end
	Equal(b:GetVisiblePlayerLocations("map")[1].mapID, 12)
	Equal(b.qtPlayerPresenceState.partnerQuests[a.name].questID, 123)
	Equal(b.qtPlayerPresenceState.partnerQuests[a.name].title, nil)
end)

QT:RegisterTest("snapshot retired sessions and delayed coordinates cannot restore obsolete state", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	local old = a:BuildGeographicSnapshots()
	for _, packet in ipairs(old) do
		b:HandleGeographicSnapshot(packet:sub(6), a.name)
	end
	a.geographicCommsState.session = "200000-5678"
	a.now = 120
	Stage(a, false)
	for _, packet in ipairs(a:BuildGeographicSnapshots()) do
		b.now = 300 -- delivery is delayed, so the tooltip must show sample age.
		assert(b:HandleGeographicSnapshot(packet:sub(6), a.name))
	end
	Equal(b.playerLocationState.peers[a.name].sampledAt, 120)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	for _, packet in ipairs(old) do
		Equal(b:HandleGeographicSnapshot(packet:sub(6), a.name), false)
	end
end)

QT:RegisterTest("delayed geographic envelopes cannot undo a pong and subsequent broadcasts refresh normally", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, true)
	local delayed = a:BuildGeographicSnapshots()
	b.now = 120
	b:AcceptDeveloperPingResponse({senderName=a.name, developer=true, locationShared=true,
		mapID="12",coordX="80",coordY="60",sampledAt=b:GetAnnouncementServerTime()}, {developerRequest=true})
	for _, packet in ipairs(delayed) do
		assert(b:HandleGeographicSnapshot(packet:sub(6), a.name))
	end
	Equal(b.playerLocationState.peers[a.name].x, 0.8)
	Equal(b.playerLocationState.peers[a.name].sampledAt, 120)
	Equal(b.playerLocationState.peers[a.name].lifetime, 600)
	a.now, b.now, a.position.x = 310, 310, 0.9
	Stage(a, true)
	for _, packet in ipairs(a:BuildGeographicSnapshots()) do
		assert(b:HandleGeographicSnapshot(packet:sub(6), a.name))
	end
	Equal(b.playerLocationState.peers[a.name].x, 0.9)
	Equal(b.playerLocationState.peers[a.name].sampledAt, 310)
	Equal(b.playerLocationState.peers[a.name].lifetime, 600)
	b.now = 909
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	b.now = 910
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("crowded zones back off without unrelated worldwide peers slowing local updates", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	for i = 1, 2000 do
		a.geographicCommsState.peers[tostring(i)] = { zone = 45, at = a.now }
	end
	a.geographicCommsState.nextLocal = a.now
	a:UpdateGeographicComms()
	Equal(a.geographicCommsState.nextLocal - a.now, 1)
	for _, peer in pairs(a.geographicCommsState.peers) do
		peer.zone = 12
	end
	a.geographicCommsState.nextLocal = a.now
	a:UpdateGeographicComms()
	assert(a.geographicCommsState.nextLocal - a.now >= 90)
end)

QT:RegisterTest("regional location cadence matches sparse and crowded population anchors", function()
	for _, edge in ipairs({ 0, 5 }) do
		for _, row in ipairs({ {0,1}, {9,1}, {10,5}, {19,5}, {20,5}, {99,14}, {100,15},
			{499,44}, {500,45}, {1000,70}, {1400,90}, {2000,90} }) do
			local a = Fixture()
			a.API.Random = function(low, high) return edge == 0 and low or high end
			a:UpdateGeographicSubscriptions()
			local state = a.geographicCommsState
			for i = 1, row[1] do state.peers[tostring(i)] = { zone = 12, at = a.now } end
			state.peers.stale = { zone = 12, at = a.now - 600 }
			state.peers.future = { zone = 12, at = a.now + 1 }
			state.peers.remote = { zone = 45, at = a.now }
			state.nextLocal, state.nextGlobal = a.now, a.now + 1000
			a:UpdateGeographicComms()
			Equal(state.nextLocal - a.now, row[2] + (row[1] < 10 and 0 or edge))
		end
	end
end)

QT:RegisterTest("one-second zone updates resample movement without repeating full metadata or growing queues", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a.other = b
	b:UpdateGeographicSubscriptions()
	a:UpdateGeographicSubscriptions()
	Stage(a, true)
	local s = a.geographicCommsState
	s.nextLocal, s.nextGlobal = a.now, a.now + 1000
	s.nextLocalMetadata = a.now
	a:UpdateGeographicComms()
	Tick(a, 6) -- Include the one-time zone discovery query before measuring movement.
	assert(b.playerLocationState.peers[a.name])
	local before = #a.sent
	for step = 1, 10 do
		a.position.x = 0.4 + step * 0.001
		Tick(a, 1.2)
		assert(#s.queue <= 2, "fast updates coalesce rather than accumulating")
	end
	assert(math.abs(b.playerLocationState.peers[a.name].x - a.position.x) < 0.00001, "receiver must get newly sampled coordinates")
	assert(#a.sent > before + 5, "low-density updates must actually leave the queue")
	for i = before + 1, #a.sent do
		local packet = a.sent[i]
		Equal(packet.target, a.joined.QuestTogetherZ12)
		assert(packet.wire:find("LOC|", 1, true))
		assert(not packet.wire:find("QTVR|", 1, true) and not packet.wire:find("QTLF|", 1, true))
		assert(#packet.wire <= 255)
	end
	-- Turning off sharing replaces queued coordinates with a withdrawal, even
	-- while the server is throttling sends. It must not restore a preview/sample.
	a.sendFails = true
	a.db.profile.sharePlayerLocation = false
	a:BroadcastPlayerLocation(true)
	for _, pending in ipairs(s.queue) do assert(not pending.publishesLocation) end
	Equal(#a:BuildGeographicSnapshots(true), 0, "privacy withdrawals use full snapshots, not a perpetual one-second broadcast")
	a.sendFails = false
	Tick(a, 4)
	Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
end)

QT:RegisterTest("metadata heartbeat is independent of movement jitter and survives one-second party traffic", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a.other, a.inParty, b.inParty = b, true, true
	a:UpdateGeographicSubscriptions()
	b:UpdateGeographicSubscriptions()
	Stage(a, true)
	local s = a.geographicCommsState
	s.nextGlobal, s.nextLocal, s.nextLocalMetadata = a.now + 1000, a.now, a.now
	for step = 1, 40 do
		a.position.x = 0.4 + step * 0.001
		if step % 10 == 0 then Stage(a, true) end
		Tick(a, 1.2)
		assert(#s.queue <= 12, "party copies and metadata cannot create an unbounded movement backlog")
	end
	local peer = assert(b.playerLocationState.peers[a.name])
	assert(math.abs(peer.x - a.position.x) < 0.004, "party traffic cannot starve fresh movement")
	Equal(b:GetPlayerAddonVersion(a.name), "6.0.0")
	Equal(b:IsPlayerLookingForQuestPartners(a.name), true)
	-- Full state is due even when a separately jittered location timer is later.
	s.queue, s.nextLocal, s.nextLocalMetadata = {}, a.now + 40, a.now
	a:UpdateGeographicComms()
	Equal(s.nextLocal, a.now + 40)
	assert(s.nextLocalMetadata > a.now)
	local foundMetadata = false
	for _, pending in ipairs(s.queue) do
		if pending.wire:find("QTVR|", 1, true) then foundMetadata = true end
	end
	assert(foundMetadata, "metadata must not wait for the next position timer")
end)

QT:RegisterTest("manual developer ping stays global and does not change background zone routing", function()
	local a = Fixture()
	a.inParty = true
	a:UpdateGeographicSubscriptions()
	local ok = a:SendPingRequest()
	Equal(ok, true)
	a:DrainGeographicQueue()
	local global, party = false, false
	for _, packet in ipairs(a.sent) do
		if packet.wire:match("^PING|") then
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
	local first = a.geographicCommsState.queue[1].wire
	a.geographicCommsState.queue = {}
	assert(a:SendAnnouncementWireEvent(event))
	local second = a.geographicCommsState.queue[1].wire
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
	-- IDs are retained even when optional metadata/text must shrink.
	event.text, event.eventId = string.rep("é", 300), "100000-1234-3"
	local payload = a:EncodeAnnouncementPayload(event)
	assert(#payload + 4 <= 255)
	Equal(a:DecodeAnnouncementPayload(payload).eventId, event.eventId)
end)

QT:RegisterTest("party metadata is isolated from older snapshot commands and keeps geographic freshness", function()
	local a,b=Fixture("Alice-Realm"),Fixture("Bob-Realm")
	Stage(a, false)
	assert(a:StageGeographicState("QTPG|1,3,Alice-Realm,MAGE,123"))
	local packets=a:BuildGeographicSnapshots(); local partyPackets=0
	for _,wire in ipairs(packets) do
		if wire:find("QTPG|",1,true) then
			partyPackets=partyPackets+1
			for _,command in ipairs({"LOC|","QTVR|","QJST|","QTLF|","QTPR|"}) do assert(not wire:find(command,1,true)) end
		end
		assert(b:HandleGeographicSnapshot(wire:sub(6),a.name))
	end
	Equal(partyPackets,1); Equal(b:GetPlayerPartyVisualInfo(a.name).leader,a.name)
	b.now=400; assert(b:GetPlayerPartyVisualInfo(a.name))
	b.now=701; Equal(b:GetPlayerPartyVisualInfo(a.name),nil)
	-- A current withdrawal cannot be undone by an older split packet.
	b.now,a.now=110,110; a:StageGeographicState("QTPG|1,0,,,")
	for _,wire in ipairs(a:BuildGeographicSnapshots()) do b:HandleGeographicSnapshot(wire:sub(6),a.name) end
	for _,wire in ipairs(packets) do b:HandleGeographicSnapshot(wire:sub(6),a.name) end
	Equal(b:GetPlayerPartyVisualInfo(a.name).size,0)
end)
QT:RegisterTest("five member hover responses drain through shared pacing rather than dropping the fifth member", function()
	local a,b=Fixture("Viewer-Realm"),Fixture("Leader-Realm")
	a.other,b.other=b,a
	b.API.GetPartyJoinInfo=function() return true,false,5 end
	b.API.GetPartyVisualLeaderUnit=function() return "player" end
	function b:GetUnitFullName() return self.name end
	b.partyMembers={[b.name]={classFile="MAGE"}}
	for i=2,5 do b.partyMembers["Member"..i.."-Realm"]={classFile="WARRIOR"} end
	assert(b:BroadcastPartyVisualMetadata())
	for _,wire in ipairs(b:BuildGeographicSnapshots()) do a:OnCommReceived(a.commPrefix,wire,"CHANNEL",b.name,6,"QuestTogether") end
	assert(a:RequestPartyVisualRoster(b.name))
	Equal(#a.sent,0)
	for i=1,30 do
		a.now,b.now=100+i/2,100+i/2
		a:DrainGeographicQueue(); b:DrainGeographicQueue()
	end
	Equal(#a:GetPlayerPartyVisualInfo(b.name).members,5)
	Equal(#a.sent,1); Equal(#b.sent,5)
	for _,packet in ipairs(b.sent) do Equal(packet.route,"CHANNEL"); assert(#packet.wire<=255) end
end)

QT:RegisterTest("snapshot bursts retain bounded ordered peers and prune expired entries", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	Stage(a, false)
	local packets = a:BuildGeographicSnapshots()
	for i = 1, 2050 do
		assert(b:HandleGeographicSnapshot(packets[1]:sub(6), "Peer" .. i .. "-Realm"))
	end
	local count = 0
	for _ in pairs(b.geographicCommsState.peers) do count = count + 1 end
	Equal(count, 2048)
	Equal(b.geographicCommsState.peerCount, count)
	local retained
	for name in pairs(b.geographicCommsState.peers) do retained = name; break end
	local commands = b.geographicCommsState.peers[retained].commands
	assert(b:HandleGeographicSnapshot(packets[1]:sub(6), retained))
	Equal(b.geographicCommsState.peers[retained].commands, commands)
	a.now, b.now = 701, 701
	Stage(a, false)
	assert(b:HandleGeographicSnapshot(a:BuildGeographicSnapshots()[1]:sub(6), a.name))
	Equal(b.geographicCommsState.peerCount, 1)
	assert(b.geographicCommsState.peers[a.name])
end)

-- Three-client topology: broadcasts reach everyone, whispers reach only their
-- native target. Scheduled callbacks retain real deadlines, not inline mocks.
local function DirectNetwork(forever)
	local a, b, bystander = Fixture(forever and "Alice Person" or "Alice-Realm"),
		Fixture(forever and "Bob Person" or "Bob-OtherRealm"), Fixture("Bystander-Realm")
	local peers = { a, b, bystander }
	for _, peer in ipairs(peers) do
		local owner = peer
		owner.forever, owner.received, owner.clockTimers = forever, {}, {}
		owner.API.Delay = function(delay, callback)
			owner.clockTimers[#owner.clockTimers + 1] = { at = owner.now + delay, callback = callback }
		end
		owner.API.SendAddonMessage = function(prefix, wire, route, target)
			owner.sent[#owner.sent + 1] = { wire = wire, route = route, target = target }
			for _, receiver in ipairs(peers) do
				if route ~= "WHISPER" or receiver.name == target then
					receiver.received[#receiver.received + 1] = { wire = wire, sender = owner.name, route = route }
					receiver:OnCommReceived(prefix, wire, route, owner.name, 6, "QuestTogether")
				end
			end
			return 0
		end
	end
	local function advance(seconds)
		for _ = 1, seconds * 4 do
			for _, peer in ipairs(peers) do peer.now = peer.now + 0.25 end
			for _, peer in ipairs(peers) do
				local due = {}
				for i = #peer.clockTimers, 1, -1 do
					if peer.clockTimers[i].at <= peer.now then due[#due + 1] = table.remove(peer.clockTimers, i).callback end
				end
				for _, callback in ipairs(due) do callback() end
				peer:DrainGeographicQueue()
			end
		end
	end
	return a, b, bystander, advance
end
local function AdvertiseDirect(sender, receiver)
	assert(sender:StageGeographicState("QTCI|1,0,3,1"))
	for _, wire in ipairs(sender:BuildGeographicSnapshots()) do
		assert(receiver:HandleGeographicSnapshot(wire:sub(6), sender.name))
	end
	assert(receiver:SupportsDirectComms(sender.name))
end

QT:RegisterTest("targeted comparisons whisper every quest only to the requester in Retail and Forever", function()
	for _, forever in ipairs({ false, true }) do
		local a, b, observer, advance = DirectNetwork(forever)
		AdvertiseDirect(b, a) -- Only the initiator knows capability initially.
		function b:BuildQuestCompareEntries()
			return { { questId = "42", questTitle = "A quest", isPushable = true }, { questId = "43", questTitle = "Another quest" } }
		end
		local entries, complete = {}, false
		local ok, id = a:RequestQuestCompare(b.name, {
			onEntry = function(entry) entries[entry.questId] = entry end,
			onDone = function() complete = true end,
			onTimeout = function() error("direct comparison timed out") end,
		})
		assert(ok)
		advance(5)
		assert(complete and entries["42"] and entries["43"])
		Equal(a.pendingQuestCompareRequests[id], nil)
		Equal(#observer.received, 0)
		Equal(#a.sent, 1); Equal(#b.sent, 3)
		for _, row in ipairs(a.sent) do Equal(row.route, "WHISPER"); Equal(row.target, b.name) end
		for _, row in ipairs(b.sent) do Equal(row.route, "WHISPER"); Equal(row.target, a.name) end
	end
end)

QT:RegisterTest("older comparison peers keep one supported broadcast route", function()
	local a, b, observer, advance = DirectNetwork(false)
	function b:BuildQuestCompareEntries() return {} end
	local complete = false
	assert(a:RequestQuestCompare(b.name, { onEntry = function() end, onDone = function() complete = true end, onTimeout = function() end }))
	advance(3)
	assert(complete)
	Equal(#a.sent, 1); Equal(#b.sent, 1)
	Equal(a.sent[1].route, "CHANNEL"); Equal(b.sent[1].route, "CHANNEL")
	Equal(#observer.received, 2)
end)

QT:RegisterTest("direct capabilities expire from sample time and do not depend on location consent", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a.now = 100; b.now = 690
	AdvertiseDirect(a, b)
	Equal(b:GetTargetedCommRoutes(a.name)[1].distribution, "WHISPER")
	b.now = 701
	Equal(b:GetTargetedCommRoutes(a.name)[1].distribution, "CHANNEL")
	a.now, b.now = 702, 702
	a:StageGeographicState("QTCI|1,0,3")
	for _, wire in ipairs(a:BuildGeographicSnapshots()) do b:HandleGeographicSnapshot(wire:sub(6), a.name) end
	Equal(b:SupportsDirectComms(a.name), false)
	for i = 1, 520 do b:RememberDirectCommPeer("Peer" .. i .. "-Realm", true) end
	local count = 0
	for _ in pairs(b.directCommPeers) do count = count + 1 end
	Equal(count, 512)
	b:ResetCommsState()
	Equal(b.directCommPeers, nil)
end)

QT:RegisterTest("queued direct controls preserve cancellation ignore and group departure guards", function()
	local a, b, _, advance = DirectNetwork(false)
	AdvertiseDirect(b, a)
	local receiver = { onEntry = function() end, onDone = function() end, onTimeout = function() end }
	local ok, id = a:RequestQuestCompare(b.name, receiver)
	assert(ok); a.pendingQuestCompareRequests[id] = nil
	advance(1); Equal(#a.sent, 0)
	assert(a:RequestQuestCompare(b.name, receiver))
	a.ignored[b.name] = true
	advance(1); Equal(#a.sent, 0)
	a.ignored[b.name] = nil
	a.partyMembers[b.name] = {}; a.inParty = true
	receiver.routes = { { distribution = "PARTY" } }
	assert(a:RequestQuestCompare(b.name, receiver))
	a.partyMembers = {}
	advance(1); Equal(#a.sent, 0)
end)

QT:RegisterTest("manual global ping requests advertise direct replies without waiting for discovery", function()
	local a, b, observer, advance = DirectNetwork(false)
	function a:PrintPingResponse() end
	function b:PrintPingResponse() end
	function observer:PrintPingResponse() end
	assert(a:SendPingRequest())
	advance(25)
	local reports = 0
	for _, row in ipairs(a.received) do if row.wire:match("^PONG|") then reports = reports + 1 end end
	Equal(reports, 2)
	for _, peer in ipairs({b, observer}) do
		Equal(#peer.sent, 1); Equal(peer.sent[1].route, "WHISPER"); Equal(peer.sent[1].target, a.name)
		for _, row in ipairs(peer.received) do assert(not row.wire:match("^PONG|")) end
	end
end)

QT:RegisterTest("direct transport rejects broadcast commands and unsolicited comparison effects", function()
	local a = Fixture("Alice-Realm")
	function a:HandleAnnouncementEvent() error("whisper announcement accepted") end
	function a:HandleGeographicSnapshot() error("whisper snapshot accepted") end
	function a:HandlePlayerLocationMessage() error("whisper location accepted") end
	for _, wire in ipairs({ "ANN|1", "LVL|1", "LOC|1", "QTB1|1", "QTPR|1,1", "QTVR|1,6.1.2", "PING|1,id,Peer-Realm" }) do
		a:OnCommReceived(a.commPrefix, wire, "WHISPER", "Peer-Realm")
	end
	a:OnCommReceived(a.commPrefix, "QCDN|" .. a:EncodeQuestCompareDonePayload({ requestId = "unsolicited", senderName = "Impostor-Realm", count = 0 }), "WHISPER", "Peer-Realm")
	Equal(#a.sent, 0)
	Equal(a:SupportsDirectComms("Peer-Realm"), false)
end)

QT:RegisterTest("party roster hover whispers all member details without broadcasting to observers", function()
	local a, b, observer, advance = DirectNetwork(false)
	AdvertiseDirect(b, a)
	b.API.GetPartyJoinInfo = function() return true, false, 3 end
	b.API.GetPartyVisualLeaderUnit = function() return "player" end
	function b:GetUnitFullName() return self.name end
	b.partyMembers = { [b.name] = {classFile="MAGE"}, ["Second-Realm"] = {classFile="WARRIOR"}, ["Third-Realm"] = {classFile="DRUID"} }
	assert(b:BroadcastPartyVisualMetadata())
	for _, wire in ipairs(b:BuildGeographicSnapshots()) do a:HandleGeographicSnapshot(wire:sub(6), b.name) end
	assert(a:RequestPartyVisualRoster(b.name))
	advance(5)
	Equal(#a:GetPlayerPartyVisualInfo(b.name).members, 3)
	Equal(#observer.received, 0)
	Equal(#a.sent, 1); Equal(#b.sent, 3)
	for _, row in ipairs(b.sent) do Equal(row.route, "WHISPER"); Equal(row.target, a.name) end
end)

QT:RegisterTest("direct comparisons recover native throttling without broadcast retries", function()
	local a, b, observer, advance = DirectNetwork(false)
	AdvertiseDirect(b, a)
	function b:BuildQuestCompareEntries() return { { questId = "42", questTitle = "A quest" } } end
	for _, peer in ipairs({a,b}) do
		local original, first = peer.API.SendAddonMessage, true
		peer.API.SendAddonMessage = function(...)
			if first then first = false; return 3 end
			return original(...)
		end
	end
	local complete = false
	assert(a:RequestQuestCompare(b.name, { onEntry = function() end, onDone = function() complete = true end, onTimeout = function() error("throttled comparison did not recover") end }))
	advance(12)
	assert(complete)
	Equal(#observer.received, 0)
	for _, peer in ipairs({a,b}) do for _, row in ipairs(peer.sent) do Equal(row.route, "WHISPER") end end
end)

QT:RegisterTest("direct group comparison replies stop after the requester leaves", function()
	local a, b, observer, advance = DirectNetwork(false)
	AdvertiseDirect(b, a)
	b.partyMembers[a.name] = {}
	function b:BuildQuestCompareEntries() return { { questId = "42", questTitle = "One" }, { questId = "43", questTitle = "Two" } } end
	assert(a:RequestQuestCompare(b.name, { onEntry = function() end, onDone = function() error("departed requester must not receive completion") end, onTimeout = function() end }))
	advance(0.25)
	Equal(#b.sent, 1)
	b.partyMembers = {}
	advance(3)
	Equal(#b.sent, 1)
	Equal(#observer.received, 0)
end)

QT:RegisterTest("a valid direct comparison reply teaches the next request to avoid global broadcast", function()
	local a, b, observer, advance = DirectNetwork(false)
	AdvertiseDirect(a, b) -- The initial requester has not discovered the responder yet.
	function b:BuildQuestCompareEntries() return {} end
	local receiver = { onEntry = function() end, onDone = function() end, onTimeout = function() end }
	assert(a:RequestQuestCompare(b.name, receiver)); advance(2)
	Equal(a.sent[1].route, "CHANNEL"); Equal(b.sent[1].route, "WHISPER")
	assert(a:SupportsDirectComms(b.name))
	local before = #observer.received
	assert(a:RequestQuestCompare(b.name, receiver)); advance(2)
	Equal(a.sent[2].route, "WHISPER")
	Equal(#observer.received, before)
end)

QT:RegisterTest("geographic presence stages current version stats and party visuals in one heartbeat", function()
	local a = Fixture("Alice-Realm")
	local size, count, version, visuals = 3, 7, "6.1.2", 0
	function a:GetAddonVersion() return version end
	function a:GetMonitoredQuestCount() return count end
	function a:GetLocalPartySize() return size end
	function a:BroadcastPartyVisualMetadata() visuals = visuals + 1 end
	a:UpdateQTPlayerPresence()
	Equal(a.geographicCommsState.latest.QTVR.wire, "QTVR|2,6.1.2,7,3")
	Equal(a.geographicCommsState.latest.QTPR, nil)
	Equal(visuals, 1); Equal(#a.sent, 0)
	for _ = 1, 10 do a:UpdateQTPlayerPresence() end
	Equal(visuals, 1)
	a.now, size, count = 120, 0, 0
	a:UpdateQTPlayerPresence()
	Equal(a.geographicCommsState.latest.QTVR.wire, "QTVR|2,6.1.2,0,0")
	Equal(a.geographicCommsState.latest.QTVR.at, 120)
	Equal(visuals, 2)
	a.now, version = 140, "unavailable"
	a:UpdateQTPlayerPresence()
	Equal(visuals, 3)
	Equal(a.geographicCommsState.latest.QTPR.wire, "QTPR|1,1")
end)

QT:RegisterTest("snapshot consolidation removes only redundant positive presence", function()
	local a, b = Fixture("Alice-Realm"), Fixture("Bob-Realm")
	a:StageGeographicState("QTPR|1,1")
	a:StageGeographicState("QTVR|2,6.1.2,7,3")
	local packets = a:BuildGeographicSnapshots()
	for _, wire in ipairs(packets) do
		assert(not wire:find("QTPR|",1,true))
		assert(b:HandleGeographicSnapshot(wire:sub(6), a.name))
	end
	assert(b:IsKnownQTPlayer(a.name))
	Equal(b:GetPlayerPartySize(a.name), 3)
	a:StageGeographicState("QTPR|1,0")
	assert(table.concat(a:BuildGeographicSnapshots()):find("QTPR|1,0",1,true))
	a.now = 281
	a:StageGeographicState("QTPR|1,1")
	assert(table.concat(a:BuildGeographicSnapshots()):find("QTPR|1,1",1,true))
	a:StageGeographicState("QTVR|2,invalid,7,3")
	assert(table.concat(a:BuildGeographicSnapshots()):find("QTPR|1,1",1,true))
end)

QT:RegisterTest("communication ticks sample public location only when publication is due", function()
	local a = Fixture("Alice-Realm")
	a:UpdateGeographicSubscriptions()
	function a:UpdateQTPlayerPresence() end
	local original, reads, shared = a.ReadLocalPlayerLocation, 0, nil
	function a:ReadLocalPlayerLocation() reads = reads + 1; return original(self) end
	function a:UpdateNearbyStreams(sample) shared = sample end
	local s = a.geographicCommsState
	s.nextLocal, s.nextLocalMetadata, s.nextGlobal = 120, 120, 200
	a:UpdatePlayerCommunications()
	Equal(reads, 0); Equal(shared, nil)
	a.now = 120
	a:UpdatePlayerCommunications()
	Equal(reads, 1); assert(shared and shared.x == a.position.x)
	a.now = 120.2
	a:UpdatePlayerCommunications()
	Equal(reads, 1); Equal(shared, nil)
end)

QT:RegisterTest("cold zone discovery advances one shared snapshot without a global solicitation", function()
	local a, b = Fixture("New-Realm"), Fixture("Resident-Realm")
	a.other, b.other = b, a
	a.API.Random = function(low) return low end
	b.API.Random = function(low) return low end
	a:UpdateGeographicSubscriptions(); b:UpdateGeographicSubscriptions()
	Stage(a); Stage(b)
	local s = b.geographicCommsState
	s.discoveryRequestAt, s.nextLocal, s.nextLocalMetadata, s.nextGlobal = nil, 999, 170, 999
	a.geographicCommsState.nextGlobal = 999
	for _ = 1, 60 do
		a.now = a.now + 0.2
		a:UpdateGeographicComms()
		b.now = a.now
		b:UpdateGeographicComms()
	end
	assert(a.playerLocationState.peers[b.name], "newcomer receives resident location before its heartbeat")
	Equal(s.nextGlobal, 999)
	local requests = 0
	for _, row in ipairs(a.sent) do
		if row.wire:match("^QTDQ|") then requests = requests + 1 end
		Equal(row.target, a.joined.QuestTogetherZ12)
	end
	Equal(requests, 1)
	for _, row in ipairs(b.sent) do Equal(row.target, b.joined.QuestTogetherZ12) end
end)

QT:RegisterTest("zone discovery rejects foreign routes and coalesces arrivals with a response cooldown", function()
	local a = Fixture()
	a.API.Random = function(low) return low end
	a:UpdateGeographicSubscriptions()
	local s = a.geographicCommsState
	s.nextLocalMetadata, s.nextGlobal = 190, 999
	for _, route in ipairs({ {"CHANNEL",6,"QuestTogether"}, {"WHISPER",7,""}, {"PARTY",7,""}, {"CHANNEL",8,"QuestTogetherZ45"} }) do
		a:OnCommReceived(a.commPrefix, "QTDQ|1,12", route[1], "Foreign-Realm", route[2], route[3])
		Equal(s.nextLocalMetadata, 190)
	end
	assert(not a:HandleGeographicDiscovery("1,45", "Other-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	a.ignored["Ignored-Realm"] = true
	assert(not a:HandleGeographicDiscovery("1,12", "Ignored-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	a.now = 105
	a:UpdateGeographicDiscovery()
	assert(#s.queue > 0)
	a:OnCommReceived(a.commPrefix, "QTDQ|1,12", "CHANNEL", "New-Realm", 7, "QuestTogetherZ12")
	assert(a:IsKnownQTPlayer("New-Realm"))
	Equal(s.nextLocalMetadata, 107); Equal(s.nextGlobal, 999)
	Equal(s.discoveryRequestAt, nil); Equal(#s.queue, 0)
	for i = 1, 100 do
		a.now = 105 + i / 10
		assert(a:HandleGeographicDiscovery("1,12", "New" .. i .. "-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	end
	Equal(s.nextLocalMetadata, 107)
	Equal(s.lastDiscoveryResponseAt, 105)
	a.now = 165; s.nextLocalMetadata = 200
	assert(a:HandleGeographicDiscovery("1,12", "Later-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	Equal(s.nextLocalMetadata, 167)
	a.restricted = true
	a.now = 230; s.nextLocalMetadata = 290
	assert(not a:HandleGeographicDiscovery("1,12", "Restricted-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	Equal(s.nextLocalMetadata, 290)
	a.restricted = false
	a.db.profile.sharePlayerLocation = false
	assert(a:HandleGeographicDiscovery("1,12", "NoShare-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	Equal(s.nextLocalMetadata, 290)
end)

QT:RegisterTest("crowded zone discovery samples responders once per minute and never delays a due heartbeat", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	local s = a.geographicCommsState
	for i = 1, 1000 do s.peers[tostring(i)] = { zone = 12, at = a.now } end
	s.nextLocalMetadata = 190
	a.API.Random = function(_, high) return high end
	assert(a:HandleGeographicDiscovery("1,12", "New-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	Equal(s.nextLocalMetadata, 190)
	a.API.Random = function(low) return low end
	-- Repeated requests cannot retry the lottery until the cooldown expires.
	assert(a:HandleGeographicDiscovery("1,12", "Again-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	Equal(s.nextLocalMetadata, 190)
	a.now = 160
	assert(a:HandleGeographicDiscovery("1,12", "Later-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	Equal(s.nextLocalMetadata, 162)
	a.now = 220; s.nextLocalMetadata = 220
	assert(a:HandleGeographicDiscovery("1,12", "Last-Realm", "CHANNEL",7,"QuestTogetherZ12"))
	Equal(s.nextLocalMetadata, 220)
end)

QT:RegisterTest("discovery waits for its channel and cancels queued queries after changing zones", function()
	local a = Fixture()
	a.joinFails = true
	a:UpdateGeographicSubscriptions()
	a.now = 110
	a:UpdateGeographicDiscovery(); Equal(#a.geographicCommsState.queue, 0)
	a.joinFails = false
	a:UpdateGeographicSubscriptions()
	a.db.profile.showPlayerLocations = false
	a:UpdateGeographicDiscovery(); Equal(#a.geographicCommsState.queue, 0)
	a.db.profile.showPlayerLocations = true
	a:UpdateGeographicDiscovery(); Equal(#a.geographicCommsState.queue, 1)
	local s = a.geographicCommsState
	a.mapID, a.viewedMap = 45, 12
	a.now = 120; a:UpdateGeographicSubscriptions()
	-- Even if the previous channel is retained for the world-map view, do not query it.
	s.subscriptions.QuestTogetherZ12 = true
	a:DrainGeographicQueue(); Equal(#a.sent, 0); Equal(#s.queue, 0)
	a.now = 130; a:UpdateGeographicDiscovery(); Equal(#s.queue, 0)
	a.now = 170; a:UpdateGeographicDiscovery(); Equal(#s.queue, 1)
	Equal(s.queue[1].route.channelName, "QuestTogetherZ45")
end)

local function CachedLocationFixture(name, now, wall, database)
	local a = Fixture(name or "Viewer-Realm")
	a.now, a.wall = now or 100, wall or 1700000100
	a.API.GetServerTime = function() return a.wall end
	a.db.global = database or {}
	a.activeCharacterKey = a.name
	return a
end
local function AddCachePosition(a, name, mask)
	local wire = a:EncodePlayerLocationPayload({session="1-1",sequence=1}, mask or 3, {
		mapID=12,x=0.4,y=0.6,classFile="MAGE",className="Mage",race="Human",faction="Alliance",level=60,
	})
	assert(a:HandlePlayerLocationMessage(wire, name or "Peer-Realm"))
	return wire
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
	Equal(#rows, 1); Equal(rows[1].x, 0.4); Equal(rows[1].level, 60)
	Equal(rows[1].sampledAt, -30); Equal(rows[1].lifetime, 145)
	Equal(#b.sent, 0)
	b.now, b.wall = 15, 1700000125
	b:SavePlayerLocationCache()
	local c = CachedLocationFixture(nil, 2, 1700000130, QT:DeepCopy(b.db.global))
	c:RestorePlayerLocationCache()
	Equal(c.playerLocationState.peers["Peer-Realm"].lifetime, 130)
	c.now = 132
	Equal(#c:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("reload cache expires overnight and rejects clock rollback different characters and malformed data", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	a:SavePlayerLocationCache()
	local saved = QT:DeepCopy(a.db.global)
	for _, setup in ipairs({ {nil,1700086500}, {nil,1700000099}, {"Alt-Realm",1700000101} }) do
		local b = CachedLocationFixture(setup[1], 5, setup[2], QT:DeepCopy(saved))
		b:RestorePlayerLocationCache(); Equal(#b:GetVisiblePlayerLocations("map"), 0)
		Equal(b.db.global.playerLocationCache, nil)
	end
	local b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
	b.db.global.playerLocationCache.savedAt = 1700000110
	b:RestorePlayerLocationCache(); Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(saved))
	local rows = b.db.global.playerLocationCache.rows
	rows[1].payload = "invalid"
	rows[2] = {name="Fake-Realm", payload="LOC|bad",sampledAt=math.huge,expiresAt=math.huge}
	rows[3] = false
	b:RestorePlayerLocationCache(); Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

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
	b:RestorePlayerLocationCache(); Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b = CachedLocationFixture(nil, 5, 1700000101, QT:DeepCopy(a.db.global))
	b.db.profile.showPlayerLocations = false
	b:RestorePlayerLocationCache(); Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b.db.profile.showPlayerLocations = true
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	wire = wire:gsub("1,1%-1,1,", "1,1-1,2,"):gsub("0.40000", "0.50000")
	assert(b:HandlePlayerLocationMessage(wire, "Peer-Realm"))
	Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.5)
	assert(b:HandlePlayerLocationMessage("1,1-1,3,0", "Peer-Realm"))
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b:SavePlayerLocationCache(); Equal(#b.db.global.playerLocationCache.rows, 0)
	b:ResetPlayerLocations(); b:RestorePlayerLocationCache()
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

QT:RegisterTest("location opt out preserves queued comparisons and non-location controls through pacing", function()
	local a = Fixture()
	Stage(a)
	a:UpdateGeographicSubscriptions()
	local s = a.geographicCommsState
	s.tokens, s.blockedUntil = 0, a.now + 2
	local sent, id = a:RequestQuestCompare("Other-Realm", {
		routes = { {distribution="CHANNEL",channelName="QuestTogether",requiresChannelJoin=true} },
		onEntry=function() end,onDone=function() end,onTimeout=function() end,
	})
	assert(sent and id)
	local route = {distribution="CHANNEL",channelName="QuestTogether",requiresChannelJoin=true}
	local redacted = "ANN|" .. a:EncodeAnnouncementPayload({eventType="QUEST_PROGRESS",senderName=a.name,text="Progress"})
	local location = "ANN|" .. a:EncodeAnnouncementPayload({eventType="QUEST_PROGRESS",senderName=a.name,text="Progress",mapID=12,coordX=40,coordY=60})
	local pong = "PONG|" .. a:EncodePingResponsePayload({requestId="test",senderName=a.name,zoneName="Elwynn"})
	for _, wire in ipairs({redacted,location,pong,"QPGR|request","QPGM|member"}) do
		assert(a:QueueGeographicWire(wire,"test",route,false))
	end
	assert(not a:TakeCommsSendToken(false)); Equal(#a.sent,0)
	a.db.profile.sharePlayerLocation = false
	a:BroadcastPlayerLocation(true)
	Equal(#s.queue,4)
	local retained = {}
	for _, row in ipairs(s.queue) do retained[row.wire]=true; assert(not row.publishesLocation) end
	assert(retained[redacted] and retained["QPGR|request"] and retained["QPGM|member"])
	assert(not retained[location] and not retained[pong])
	assert(a.pendingQuestCompareRequests[id])
	-- Invalid stand-in roster requests are pruned normally; the real comparison
	-- still transmits after the existing pacing delay, without resubmission.
	a.now = a.now + 3
	a:DrainGeographicQueue()
	Equal(#a.sent,1); Equal(a.sent[1].wire,redacted)
	a.now = a.now + 1; a:DrainGeographicQueue()
	Equal(#a.sent,2); assert(a.sent[2].wire:match("^QCMP|"))
end)

QT:RegisterTest("reload restores LFQP filtered dots without renewing status or establishing live presence", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	assert(a:HandleQuestPartnerStatusMessage("1,1-1,1,1","Peer-Realm"))
	a.db.profile.onlyShowQuestPartners = true
	Equal(#a:GetVisiblePlayerLocations("map"),1)
	a.now,a.wall = 110,1700000110
	a:SavePlayerLocationCache()
	local b = CachedLocationFixture(nil,5,1700000115,QT:DeepCopy(a.db.global))
	b.db.profile.onlyShowQuestPartners = true
	b:RestorePlayerLocationCache()
	Equal(#b:GetVisiblePlayerLocations("map"),1)
	Equal(#b:GetVisiblePlayerLocations("minimap"),1)
	assert(not b:IsKnownQTPlayer("Peer-Realm"),"cache is not a new live discovery")
	local status = b.qtPlayerPresenceState.questPartners["Peer-Realm"]
	Equal(status.sampledAt,-10); Equal(status.lifetime,50)
	b.now,b.wall = 15,1700000125; b:SavePlayerLocationCache()
	local c = CachedLocationFixture(nil,2,1700000130,QT:DeepCopy(b.db.global))
	c.db.profile.onlyShowQuestPartners = true; c:RestorePlayerLocationCache()
	Equal(c.qtPlayerPresenceState.questPartners["Peer-Realm"].lifetime,35)
	c.now = 37
	Equal(#c:GetVisiblePlayerLocations("map"),0)
	c.db.profile.onlyShowQuestPartners = false
	Equal(#c:GetVisiblePlayerLocations("map"),1,"position may outlive independently expiring partner status")
end)

QT:RegisterTest("cached partner status rejects malformed state and yields to live off updates", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	assert(a:HandleQuestPartnerStatusMessage("1,1-1,1,1","Peer-Realm"))
	a:SavePlayerLocationCache()
	local saved = QT:DeepCopy(a.db.global)
	local b = CachedLocationFixture(nil,5,1700000101,QT:DeepCopy(saved))
	assert(b:HandleQuestPartnerStatusMessage("1,1-1,2,0","Peer-Realm"))
	b:RestorePlayerLocationCache()
	assert(not b:IsPlayerLookingForQuestPartners("Peer-Realm"))
	Equal(b.qtPlayerPresenceState.questPartners["Peer-Realm"].sequence,2)
	b = CachedLocationFixture(nil,5,1700000101,QT:DeepCopy(saved))
	b:RestorePlayerLocationCache()
	assert(b:HandleQuestPartnerStatusMessage("1,1-1,2,0","Peer-Realm"))
	assert(not b:IsPlayerLookingForQuestPartners("Peer-Realm"))
	for _, mutate in ipairs({
		function(p) p.session="1|1-1" end,
		function(p) p.session={} end,
		function(p) p.sequence=0 end,
		function(p) p.sequence=1.5 end,
		function(p) p.sequence=math.huge end,
		function(p) p.sampledAt=1700000102 end,
		function(p) p.expiresAt=1700000100 end,
		function(p) p.expiresAt=math.huge end,
	}) do
		local db = QT:DeepCopy(saved); mutate(db.playerLocationCache.rows[1].partner)
		b = CachedLocationFixture(nil,5,1700000101,db); b:RestorePlayerLocationCache()
		Equal(#b:GetVisiblePlayerLocations("map"),1)
		assert(not b:IsPlayerLookingForQuestPartners("Peer-Realm"))
	end
end)

QT:RegisterTest("reload partner metadata obeys peer bounds and original sample age", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	assert(a:HandleQuestPartnerStatusMessage("1,1-1,1,1","Peer-Realm"))
	local status = a.qtPlayerPresenceState.questPartners["Peer-Realm"]
	status.sampledAt,status.lifetime = -70,600 -- Only ten cache seconds remain despite the long live lifetime.
	a:SavePlayerLocationCache()
	local saved = QT:DeepCopy(a.db.global)
	local prototype = saved.playerLocationCache.rows[1]
	for i=1,512 do
		local row=QT:DeepCopy(prototype); row.name="Peer"..i.."-Realm"
		saved.playerLocationCache.rows[i]=row
	end
	local b = CachedLocationFixture(nil,5,1700000101,saved)
	b.db.profile.onlyShowQuestPartners=true
	b:RestorePlayerLocationCache()
	Equal(#b:GetVisiblePlayerLocations("map"),256)
	b.now=14
	Equal(#b:GetVisiblePlayerLocations("map"),0)
	b.db.profile.onlyShowQuestPartners=false
	Equal(#b:GetVisiblePlayerLocations("map"),512)
end)

-- Build party identity with the real revision algorithm before putting its
-- independently received member list into the viewer's cache.
local function AddCachedParty(a, name, count, withMembers)
	local owner = Fixture(name)
	owner.API.GetPartyJoinInfo = function() return count > 0,true,count end
	owner.API.GetPartyVisualLeaderUnit = function() return "player" end
	owner.GetUnitFullName = function() return name end
	owner.partyMembers = { [name] = {classFile="MAGE"} }
	for i=2,count do owner.partyMembers["Member"..i.."-Realm"]={classFile="WARRIOR"} end
	local payload, info = owner:BuildPartyVisualMetadataPayload()
	assert(payload)
	assert(a:HandlePartyVisualMetadata(payload,name))
	if withMembers and info.key then
		a:GetPartyVisualState().rosters[info.key] = {at=a.now,members=QT:DeepCopy(info.members)}
	end
	return info
end

QT:RegisterTest("reload restores cached party identity and small roster without live presence or network queries", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	local original = AddCachedParty(a,"Peer-Realm",3,true)
	local party = a:GetPartyVisualState().peers["Peer-Realm"]
	party.sampledAt,party.lifetime = 80,580
	a:GetPartyVisualState().rosters[original.key].at = 90
	a.now,a.wall = 110,1700000110; a:SavePlayerLocationCache()
	local b = CachedLocationFixture(nil,5,1700000115,QT:DeepCopy(a.db.global))
	b:RestorePlayerLocationCache()
	local info = b:GetPlayerPartyVisualInfo("Peer-Realm")
	assert(info and info.cached)
	Equal(info.size,3); Equal(info.leader,"Peer-Realm"); Equal(info.leaderClass,"MAGE")
	Equal(info.key,original.key); Equal(#info.members,3)
	Equal(info.sampledAt,-30); Equal(info.lifetime,145)
	assert(not b:IsKnownQTPlayer("Peer-Realm"))
	assert(not b:RequestPartyVisualRoster("Peer-Realm")); Equal(#b.sent,0)
	b.now,b.wall = 15,1700000125; b:SavePlayerLocationCache()
	local c = CachedLocationFixture(nil,2,1700000130,QT:DeepCopy(b.db.global))
	c:RestorePlayerLocationCache()
	info = c:GetPlayerPartyVisualInfo("Peer-Realm")
	Equal(info.lifetime,130); Equal(#info.members,3)
	Equal(c.partyVisualState.rosters[original.key].lifetime,130)
	c.now=82 -- The matching revision still confirms the older fetched member list.
	info=c:GetPlayerPartyVisualInfo("Peer-Realm")
	assert(info and info.size==3); Equal(#info.members,3)
	assert(not c:RequestPartyVisualRoster("Peer-Realm")); Equal(#c.sent,0)
	c.now=112 -- Original location expires: cached metadata cannot outlive its anchor.
	Equal(c:GetPlayerPartyVisualInfo("Peer-Realm"),nil)
end)

QT:RegisterTest("reload party cache preserves QTVR-only solo sizes and yields to live replacements", function()
	local a = CachedLocationFixture()
	AddCachePosition(a)
	assert(a:HandleAddonVersionMessage("2,6.1.2,,0","Peer-Realm"))
	a:SavePlayerLocationCache()
	local saved=QT:DeepCopy(a.db.global)
	local b=CachedLocationFixture(nil,5,1700000101,QT:DeepCopy(saved)); b:RestorePlayerLocationCache()
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm").size,0)
	assert(not b:IsKnownQTPlayer("Peer-Realm"))
	AddCachedParty(b,"Peer-Realm",2,false)
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm").size,2)
	assert(not b:GetPlayerPartyVisualInfo("Peer-Realm").cached)
	-- Already received live size must survive restoration, even if no live LOC
	-- has arrived yet and the older cached location is otherwise still useful.
	b=CachedLocationFixture(nil,5,1700000101,QT:DeepCopy(saved))
	assert(b:HandleAddonVersionMessage("2,6.1.2,,4","Peer-Realm"))
	b:RestorePlayerLocationCache()
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm").size,4)
	-- A newer live size report also supersedes a cached group identity.
	a=CachedLocationFixture(); AddCachePosition(a); AddCachedParty(a,"Peer-Realm",3,true)
	a:SavePlayerLocationCache()
	b=CachedLocationFixture(nil,5,1700000101,QT:DeepCopy(a.db.global)); b:RestorePlayerLocationCache()
	b.now=6; assert(b:HandleAddonVersionMessage("2,6.1.2,,0","Peer-Realm"))
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm").size,0)
end)

QT:RegisterTest("party reload cache validates metadata hashes roster expiry and ignore rules independently", function()
	local a=CachedLocationFixture(); AddCachePosition(a); AddCachedParty(a,"Peer-Realm",3,true)
	a:SavePlayerLocationCache(); local saved=QT:DeepCopy(a.db.global)
	for _, mutate in ipairs({
		function(p) p.size=41 end,
		function(p) p.size=1.5 end,
		function(p) p.leader="Broken|Name" end,
		function(p) p.leaderClass={} end,
		function(p) p.revision="bad" end,
		function(p) p.sampledAt=1700000102 end,
		function(p) p.expiresAt=math.huge end,
	}) do
		local db=QT:DeepCopy(saved); mutate(db.playerLocationCache.rows[1].party)
		local b=CachedLocationFixture(nil,5,1700000101,db); b:RestorePlayerLocationCache()
		Equal(#b:GetVisiblePlayerLocations("map"),1)
		Equal(b:GetPlayerPartyVisualInfo("Peer-Realm"),nil)
	end
	for _, mutate in ipairs({
		function(r) r.members[2].name=r.members[1].name end,
		function(r) r.members[2].classFile="HUNTER" end, -- Valid label, wrong revision.
		function(r) r.members[2].classFile={} end,
		function(r) r.sampledAt=1700000102 end,
		function(r) r.expiresAt=1700000100 end,
	}) do
		local db=QT:DeepCopy(saved); mutate(db.playerLocationCache.rows[1].party.roster)
		local b=CachedLocationFixture(nil,5,1700000101,db); b:RestorePlayerLocationCache()
		local info=b:GetPlayerPartyVisualInfo("Peer-Realm")
		Equal(info.size,3); Equal(info.members,nil)
	end
	local b=CachedLocationFixture(nil,5,1700000101,QT:DeepCopy(saved))
	b.ignored["Peer-Realm"]=true; b:RestorePlayerLocationCache()
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm"),nil)
	Equal(rawget(b,"partyVisualState"),nil)
end)

QT:RegisterTest("large cached groups keep leader only and explicit departures retire cached party identity", function()
	local a=CachedLocationFixture(); AddCachePosition(a); AddCachedParty(a,"Peer-Realm",6,true)
	a:SavePlayerLocationCache()
	Equal(a.db.global.playerLocationCache.rows[1].party.roster,nil)
	local b=CachedLocationFixture(nil,5,1700000101,QT:DeepCopy(a.db.global)); b:RestorePlayerLocationCache()
	local info=b:GetPlayerPartyVisualInfo("Peer-Realm")
	Equal(info.size,6); Equal(info.leader,"Peer-Realm"); Equal(info.members,nil)
	b:RecordQTPlayerPresence("Peer-Realm",false)
	Equal(b:GetPlayerPartyVisualInfo("Peer-Realm"),nil)
end)

QT:RegisterTest("roster reload expiry follows original revision confirmation including transit not hover or save time", function()
	local a=CachedLocationFixture(nil,500,1700000500)
	AddCachePosition(a)
	local original=AddCachedParty(a,"Peer-Realm",3,true)
	local info=a:GetPartyVisualState().peers["Peer-Realm"]
	-- This party revision was sampled fifty seconds before it arrived. Its
	-- matching full roster was fetched much earlier and needs no new transfer.
	info.sampledAt,info.lifetime=450,550
	a:GetPartyVisualState().rosters[original.key].at=100
	a.playerLocationState.peers["Peer-Realm"].lifetime=600
	for i=1,10 do a.now=500+i; Equal(#a:GetPlayerPartyVisualInfo("Peer-Realm").members,3) end
	a.wall=1700000510; a:SavePlayerLocationCache()
	local cached=a.db.global.playerLocationCache.rows[1].party
	Equal(cached.sampledAt,1700000450); Equal(cached.expiresAt,1700000630)
	Equal(cached.roster.sampledAt,1700000450); Equal(cached.roster.expiresAt,1700000630)
	local b=CachedLocationFixture(nil,10,1700000520,QT:DeepCopy(a.db.global))
	b:RestorePlayerLocationCache()
	Equal(#b:GetPlayerPartyVisualInfo("Peer-Realm").members,3)
	for i=1,20 do b.now=10+i; Equal(#b:GetPlayerPartyVisualInfo("Peer-Realm").members,3) end
	b.wall=1700000540; b:SavePlayerLocationCache()
	cached=b.db.global.playerLocationCache.rows[1].party
	Equal(cached.expiresAt,1700000630); Equal(cached.roster.expiresAt,1700000630)
	local c=CachedLocationFixture(nil,2,1700000600,QT:DeepCopy(b.db.global))
	c:RestorePlayerLocationCache()
	Equal(c:GetPlayerPartyVisualInfo("Peer-Realm").lifetime,30)
	Equal(#c:GetPlayerPartyVisualInfo("Peer-Realm").members,3)
	c.now=32
	Equal(c:GetPlayerPartyVisualInfo("Peer-Realm"),nil)
	Equal(#c:GetVisiblePlayerLocations("map"),1,"fresher position may remain after party confirmation expires")
end)

-- These networks use the real sender queue, native admission, decoders and
-- completion handlers; only the clock and external wire are private adapters.
local function FairTransportNetwork(count, questCount)
	local peers, byName = {}, {}
	local clock = QT:CreateTestClock(100)
	for index=1,count do
		local a = Fixture("Transport"..index.."-Realm")
		a.API.GetTime = function() return clock:GetTime() end
		a.API.Delay = function(delay, callback) clock:After(delay, callback) end
		function a:BuildQuestCompareEntries()
			local entries={}
			for id=1,questCount do entries[id]={questId=tostring(id),questTitle="Quest "..id,isPushable=true} end
			return entries
		end
		peers[index],byName[a.name]=a,a
	end
	local function Advance(seconds)
		for _=1,math.floor(seconds*10) do
			for _,a in ipairs(peers) do a.now=clock:GetTime()+0.1 end
			clock:Advance(0.1)
			for _,a in ipairs(peers) do a:DrainGeographicQueue() end
		end
	end
	return peers,byName,Advance
end

QT:RegisterTest("five full quest logs converge through loss duplicate reorder and native throttle",function()
	local peers,byName,advance=FairTransportNetwork(5,40)
	local dropped,throttled,held=false,false,nil
	for _,a in ipairs(peers) do
		for _,b in ipairs(peers) do if a~=b then a:RememberDirectCommPeer(b.name,true) end end
		a.API.SendAddonMessage=function(prefix,wire,route,target)
			local b=byName[target]
			assert(b and route=="WHISPER")
			local command,payload=a:DeserializeWireMessage(wire)
			local entry=command=="QCQE" and a:DecodeQuestCompareEntryPayload(payload)
			if a==peers[2] and entry and not throttled then throttled=true;return 3 end
			if a==peers[1] and b==peers[2] and entry and entry.questId=="1" and not dropped then dropped=true;return 0 end
			if a==peers[1] and b==peers[3] and entry and entry.questId=="2" and not held then held=wire;return 0 end
			b:OnCommReceived(prefix,wire,route,a.name)
			b:OnCommReceived(prefix,wire,route,a.name) -- duplicated delivery is harmless
			if a==peers[1] and b==peers[3] and command=="QCDN" and held then
				b:OnCommReceived(prefix,held,route,a.name)
			end
			return 0
		end
	end
	local completed,timedOut=0,0
	for _,a in ipairs(peers) do
		for _,b in ipairs(peers) do if a~=b then
			local entries={}
			assert(a:RequestQuestCompare(b.name,{
				onEntry=function(entry) entries[entry.questId]=true end,
				onDone=function()
					local n=0;for _ in pairs(entries) do n=n+1 end
					Equal(n,40);completed=completed+1
				end,
				onTimeout=function() timedOut=timedOut+1 end,
			}))
		end end
	end
	advance(145)
	assert(dropped and throttled and held)
	Equal(completed,20);Equal(timedOut,0)
	for _,a in ipairs(peers) do
		Equal(next(a.pendingQuestCompareRequests),nil)
		Equal(#a.questCompareResponseQueue.jobs,0)
		Equal(a.questCompareResponseQueue.packets,0)
	end
end)

QT:RegisterTest("fair transport sends announcements and actions promptly during large diagnostic replies",function()
	local peers,_,advance=FairTransportNetwork(1,0)
	local a=peers[1]
	local eventAt,actionAt,pages=nil,nil,0
	a.API.SendAddonMessage=function(_,wire)
		if wire:match("^ANN|") then eventAt=a.API.GetTime() end
		if wire:match("^PING|") then actionAt=a.API.GetTime() end
		if wire:match("^PONP|") then pages=pages+1 end
		return 0
	end
	local id="dev-1791300000-1234-1"
	local payload=a:EncodePingResponsePayload({requestId=id,senderName=a.name,developer=true,diagnosticText=string.rep("diagnostic state\n",800)},true)
	assert(#payload<16384 and #payload>14000)
	assert(a:SendPagedPong(id,payload,{{distribution="WHISPER",target="Reader-Realm"}},true))
	advance(1)
	local started=a.API.GetTime()
	assert(a:SendAnnouncementWireEvent{eventType="QUEST_PROGRESS",senderName=a.name,text="1/5 Wolf Pelts"})
	assert(a:SendWireMessageToAnnouncementRoutes("PING|1,interactive,"..a.name,"player action",{{distribution="WHISPER",target="Reader-Realm"}}))
	advance(5)
	assert(eventAt and eventAt-started<2)
	assert(actionAt and actionAt-started<2)
	advance(65)
	Equal(pages,#a:BuildPongPages(id,payload))
	Equal(#a.pingPageQueue.jobs,0)
end)

QT:RegisterTest("world departure fences all response owners and reentry publishes only fresh state",function()
	local peers,_,advance=FairTransportNetwork(1,5)
	local a=peers[1]
	assert(a:HandleQuestCompareRequest{requestId="old",targetName=a.name,requesterName="Reader-Realm",replyDistribution="WHISPER"})
	local payload=a:EncodePingResponsePayload{requestId="old-pong",senderName=a.name}
	assert(a:SendPagedPong("old-pong",payload,{{distribution="WHISPER",target="Reader-Realm"}},true))
	a:PLAYER_LEAVING_WORLD()
	local before=#a.sent
	advance(10)
	Equal(#a.sent,before)
	Equal(rawget(a,"questCompareResponseQueue"),nil)
	Equal(rawget(a,"pingPageQueue"),nil)
	a.isLoggingOut=false
	a:ResumeCommsWorldSession()
	advance(1)
	for index=before+1,#a.sent do assert(not a.sent[index].wire:match("^QC") and not a.sent[index].wire:match("^PONP")) end
	assert(a.geographicCommsState.latest.LOC)
	Equal(a.geographicCommsState.departing,nil)
end)

QT:RegisterTest("diagnostic opt out permanently cancels queued developer pages without cancelling ordinary replies",function()
	local peers,_,advance=FairTransportNetwork(1,0)
	local a=peers[1]
	local function Payload(id) return a:EncodePingResponsePayload({requestId=id,senderName=a.name,diagnosticText=string.rep("x",400),developer=true},true) end
	assert(a:SendPagedPong("private",Payload("private"),{{distribution="WHISPER",target="Reader-Realm"}},true))
	assert(a:SendPagedPong("public",Payload("public"),{{distribution="WHISPER",target="Reader-Realm"}},false))
	a:CancelDeveloperDiagnosticReplies()
	advance(5)
	assert(#a.sent>0)
	for _,packet in ipairs(a.sent) do assert(packet.wire:match("^PONP|1,public,")) end
end)

QT:RegisterTest("same comparison correlation replays an immutable log after loss and quest changes",function()
	local peers,byName,advance=FairTransportNetwork(2,3)
	local receiver,sender=peers[1],peers[2]
	receiver:RememberDirectCommPeer(sender.name,true)
	local dropped=false
	for _,a in ipairs(peers) do
		a.API.SendAddonMessage=function(prefix,wire,route,target)
			local b=assert(byName[target])
			if a==sender and wire:match("^QCQE|") then
				local row=a:DecodeQuestCompareEntryPayload(wire:sub(6))
				if row.questId=="2" and not dropped then dropped=true;return 0 end
			end
			b:OnCommReceived(prefix,wire,route,a.name)
			return 0
		end
	end
	local result,done={},false
	assert(receiver:RequestQuestCompare(sender.name,{
		onEntry=function(row) result[row.questId]=row.questTitle end,
		onDone=function() done=true end,
		onTimeout=function() error("immutable recovery timed out") end,
	}))
	advance(5)
	assert(dropped and not done)
	function sender:BuildQuestCompareEntries()
		return {{questId="3",questTitle="Changed third quest"},{questId="4",questTitle="New quest"}}
	end
	advance(40)
	assert(done)
	Equal(result["1"],"Quest 1");Equal(result["2"],"Quest 2");Equal(result["3"],"Quest 3")
	Equal(result["4"],nil)
end)

QT:RegisterTest("delayed ping callbacks cannot cross a leave and return within the same geographic object",function()
	local peers,_,advance=FairTransportNetwork(1,0)
	local a=peers[1]
	local replies=0
	function a:SendPingResponse() replies=replies+1;return true end
	assert(a:ScheduleGeographicPingReply("old",{{distribution="WHISPER",target="Reader-Realm"}},true))
	a:EndCommsWorldSession()
	a:ResumeCommsWorldSession()
	advance(25)
	Equal(replies,0)
	assert(a:ScheduleGeographicPingReply("new",{{distribution="WHISPER",target="Reader-Realm"}},true))
	advance(25)
	Equal(replies,1)
end)

QT:RegisterTest("queued party navigation coalesces edits and rechecks focus and waypoint consent",function()
	local peers,_,advance=FairTransportNetwork(1,0)
	local a=peers[1]
	a.inParty=true
	a.partyMembers={[a.name]={},["Friend-Realm"]={}}
	a.db.profile.sharePartyFocus,a.db.profile.sharePartyWaypoint=true,true
	local state=a:GetPartyNavigationState()
	local function Queue(questID,mapID)
		state.sequence=state.sequence+1
		local wire=a:EncodePartyNavigation({questID=questID,mapID=mapID,x=0.2,y=0.3},false)
		assert(a:SendWireMessageToAnnouncementRoutes(wire,"party navigation",{{distribution="PARTY",requiresGroup=true}}))
		return wire
	end
	Queue(1,12)
	local latest=Queue(2,12)
	Equal(#a.geographicCommsState.queue,1)
	advance(1)
	Equal(#a.sent,1);Equal(a.sent[1].wire,latest)
	Queue(3,12)
	a.db.profile.sharePartyFocus=false
	advance(1)
	Equal(#a.sent,1)
	Queue(-1,12)
	a.db.profile.sharePartyWaypoint=false
	advance(1)
	Equal(#a.sent,1)
	local withdrawn=Queue(-1,-1)
	advance(1)
	Equal(#a.sent,2);Equal(a.sent[2].wire,withdrawn)
end)

QT:RegisterTest("deferred response at queue head can reclaim unsent tail packet reservations",function()
	local peers,_,advance=FairTransportNetwork(1,40)
	local a=peers[1]
	a.restricted=true
	assert(a:HandleQuestCompareRequest{requestId="first",targetName=a.name,requesterName="First-Realm",replyDistribution="WHISPER"})
	a.restricted=false
	for index=2,4 do
		assert(a:HandleQuestCompareRequest{requestId=tostring(index),targetName=a.name,requesterName="Other"..index.."-Realm",replyDistribution="WHISPER"})
	end
	local done={}
	a.API.SendAddonMessage=function(_,wire,_,target)
		if wire:match("^QCDN|") then done[target]=true end
		return 0
	end
	advance(110)
	assert(done["First-Realm"] and done["Other2-Realm"] and done["Other3-Realm"] and done["Other4-Realm"])
	Equal(#a.questCompareResponseQueue.jobs,0)
	Equal(a.questCompareResponseQueue.packets,0)
end)

QT:RegisterTest("five maximum quest logs recover every comparison after a lost entry with bounded large deadlines",function()
	local peers,byName,advance=FairTransportNetwork(5,100)
	local lost={}
	for _,a in ipairs(peers) do
		for _,b in ipairs(peers) do if a~=b then a:RememberDirectCommPeer(b.name,true) end end
		a.API.SendAddonMessage=function(prefix,wire,route,target)
			local b=assert(byName[target])
			local key=a.name..":"..b.name
			if wire:match("^QCQE|") and not lost[key] then lost[key]=true;return 0 end
			b:OnCommReceived(prefix,wire,route,a.name)
			return 0
		end
	end
	local completed,timedOut=0,0
	for _,a in ipairs(peers) do
		for _,b in ipairs(peers) do if a~=b then
			local count=0
			assert(a:RequestQuestCompare(b.name,{
				onEntry=function() count=count+1 end,
				onDone=function() Equal(count,100);completed=completed+1 end,
				onTimeout=function() timedOut=timedOut+1 end,
			}))
		end end
	end
	advance(15)
	for _,a in ipairs(peers) do
		for _,pending in pairs(a.pendingQuestCompareRequests) do Equal(pending.largeResponse,true) end
	end
	advance(530)
	Equal(completed,20);Equal(timedOut,0)
	for _,a in ipairs(peers) do
		Equal(next(a.pendingQuestCompareRequests),nil)
		Equal(#a.questCompareResponseQueue.jobs,0)
		Equal(a.questCompareResponseQueue.packets,0)
		Equal(#a.geographicCommsState.queue,0)
	end
end)

QT:RegisterTest("diagnostic opt out and back in cancels randomized private replies but preserves ordinary replies",function()
	local peers,_,advance=FairTransportNetwork(1,0)
	local a=peers[1]
	local replies={}
	function a:SendPingResponse(id) replies[id]=true;return true end
	local routes={{distribution="WHISPER",target="Reader-Realm"}}
	assert(a:ScheduleGeographicPingReply("private",routes,true,{developerVerified=true}))
	assert(a:ScheduleGeographicPingReply("public",routes,true))
	a.db.profile.shareDeveloperDiagnostics=false
	a:CancelDeveloperDiagnosticReplies()
	a.db.profile.shareDeveloperDiagnostics=true
	advance(25)
	Equal(replies.private,nil);Equal(replies.public,true)
	assert(a:ScheduleGeographicPingReply("fresh",routes,true,{developerVerified=true}))
	advance(25)
	Equal(replies.fresh,true)
end)

QT:RegisterTest("disable and world departure deliver navigation withdrawal after fencing the actual queue",function()
	for _,event in ipairs({"Disable","PLAYER_LEAVING_WORLD"}) do
		local a,b=Fixture("Leader-Realm"),Fixture("Follower-Realm")
		a.other=b
		for _,peer in ipairs({a,b}) do
			peer.inParty=true
			peer.partyMembers={[a.name]={},[b.name]={}}
			peer.db.profile.sharePartyFocus,peer.db.profile.sharePartyWaypoint=true,true
		end
		-- Only unrelated UI teardown is stubbed; the queue, departure methods,
		-- native transport adapter and remote navigation decoder all execute.
		for _,method in ipairs({"UnregisterRuntimeEvents","RefreshMinimapPartnerGlow","ResetQuestEventState",
			"ResetTaskAreaStateStore","ResetRuntimeWorkStateStore","DisableNameplateAugmentation",
			"RefreshPersonalBubbleAnchorVisualState"}) do a[method]=function() end end
		local state=a:GetPartyNavigationState()
		state.sequence=1
		local wire=a:EncodePartyNavigation({questID=7,mapID=12,x=0.2,y=0.3},false)
		assert(a:SendWireMessageToAnnouncementRoutes(wire,"navigation",{{distribution="PARTY",requiresGroup=true}}))
		a:DrainGeographicQueue()
		Equal(b:GetPartyNavigationPeer(a.name).questID,7)
		local follow=b:GetPartyNavigationState()
		follow.following=a.name
		state.sequence=2
		wire=a:EncodePartyNavigation({questID=8,mapID=12,x=0.4,y=0.5},false)
		assert(a:SendWireMessageToAnnouncementRoutes(wire,"navigation",{{distribution="PARTY",requiresGroup=true}}))
		a[event](a)
		local peer=b:GetPartyNavigationPeer(a.name)
		Equal(peer.questID,-1);Equal(peer.mapID,-1)
		Equal(follow.following,a.name)
		local navigationPackets=0
		for _,packet in ipairs(a.sent) do
			if packet.wire:match("^QTNAV|") then navigationPackets=navigationPackets+1 end
			assert(packet.wire~=wire) -- The unsent newer position was fenced.
		end
		Equal(navigationPackets,2) -- Original navigation and the direct clear.
	end
end)
