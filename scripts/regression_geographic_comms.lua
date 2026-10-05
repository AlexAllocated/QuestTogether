local QT = _G.QuestTogether
local function Equal(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end

local function BaseFixture(name)
	local a = setmetatable({
		isEnabled = true,
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
	b.now = 701
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	Equal(b:IsPlayerLookingForQuestPartners("Alice-Realm"), false)
	for _, packet in ipairs(a.sent) do
		assert(#packet.wire <= 255)
		assert(packet.wire:match("^QTB1|"))
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

QT:RegisterTest("send pacing reserves interactive capacity bounds queues and cancels stale routes", function()
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
	Equal(#a.sent, 3)
	assert(a:TakeCommsSendToken(false)) -- last token reserved for interactive sends
	Equal(a:TakeCommsSendToken(false), false)
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

QT:RegisterTest("crowded zones back off without unrelated worldwide peers slowing local updates", function()
	local a = Fixture()
	a:UpdateGeographicSubscriptions()
	for i = 1, 2000 do
		a.geographicCommsState.peers[tostring(i)] = { zone = 45, at = a.now }
	end
	a.geographicCommsState.nextLocal = a.now
	a:UpdateGeographicComms()
	assert(a.geographicCommsState.nextLocal - a.now <= 25)
	for _, peer in pairs(a.geographicCommsState.peers) do
		peer.zone = 12
	end
	a.geographicCommsState.nextLocal = a.now
	a:UpdateGeographicComms()
	assert(a.geographicCommsState.nextLocal - a.now >= 90)
end)

QT:RegisterTest("manual developer ping stays global and does not change background zone routing", function()
	local a = Fixture()
	a.inParty = true
	a:UpdateGeographicSubscriptions()
	local ok = a:SendPingRequest()
	Equal(ok, true)
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
	assert(global and party)
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
