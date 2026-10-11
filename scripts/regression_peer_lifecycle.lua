-- Real serializers, receive handlers and world-lifetime senders on private peers.
-- Native adapters are per fixture; these tests never modify live Blizzard state.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function Peer(name)
	local a = setmetatable({
		name = name or "Me-Realm",
		now = 100,
		isEnabled = true,
		hasLoggedIn = true,
		partyMembers = {},
		partyMemberOrder = {},
		partyRosterFingerprint = "",
		sent = {},
		timers = {},
		joined = { QuestTogether = 6 },
		recentCommMessageSignatures = {},
		announcementChannelName = "QuestTogether",
		announcementChannelLocalID = 6,
		db = { profile = QT:DeepCopy(QT.DEFAULTS.profile), global = {} },
	}, { __index = QT })
	a.API = {}
	for key, value in pairs(QT.API) do
		if type(value) == "function" then
			a.API[key] = function() end
		end
	end
	a.API.GetTime = function()
		return a.now
	end
	a.API.Random = function(low)
		return low
	end
	a.API.GetRealmName = function()
		return "Realm"
	end
	a.API.RegionalUniqueNamesEnabled = function()
		return false
	end
	a.API.GetBestMapForUnit = function()
		return 12
	end
	a.API.GetPlayerMapPosition = function()
		return { x = 0.4, y = 0.6 }
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
	a.API.GetServerTime = function()
		return 1700000000 + math.floor(a.now)
	end
	a.API.GetPartyJoinInfo = function()
		return a.grouped == true, true, a.grouped and 2 or 0, false
	end
	a.API.IsInParty = function()
		return false
	end
	a.API.IsOnIgnoredList = function()
		return false
	end
	a.API.GetChannelName = function(channel)
		return a.joined[channel]
	end
	a.API.GetMapInfo = function(id)
		return { mapType = id == 99 and 2 or 3, parentMapID = 99 }
	end
	a.API.JoinPermanentChannel = function(channel)
		a.joined[channel] = channel == "QuestTogetherZ12" and 7 or 8
	end
	a.API.LeaveChannelByName = function(channel)
		a.joined[channel] = nil
	end
	a.API.Delay = function(_, callback)
		a.timers[#a.timers + 1] = callback
	end
	a.API.SendAddonMessage = function(prefix, wire, route, target)
		a.sent[#a.sent + 1] = { wire = wire, route = route, target = target }
		if a.other then
			a.other.now = a.now
			local channel
			for key, id in pairs(a.joined) do
				if id == target then
					channel = key
				end
			end
			if route ~= "CHANNEL" or a.other.joined[channel] then
				a.other:OnCommReceived(prefix, wire, route, a.name, a.other.joined[channel], channel)
			end
		end
		return 0
	end
	function a:GetPlayerFullName()
		return self.name
	end
	function a:GetPlayerName()
		return self.name
	end
	function a:GetAddonVersion()
		return "6.5.8"
	end
	function a:IsRuntimeRestricted()
		return false
	end
	function a:IsRuntimeRestrictionTypeActive()
		return false
	end
	function a:GetViewedQuestTogetherMapID() end
	function a:GetPlayerLocationPriorityOrigin() end
	function a:RefreshQTPlayerPlatePresence() end
	function a:RefreshQTPlayerPartnerIndicators() end
	function a:QueuePartyJoinPrompt() end
	function a:RegisterAnnouncementChannelChatFilters() end
	function a:HideAnnouncementChannelFromChatWindows() end
	function a:RecordCommsDiagnostic() end
	function a:ObserveAddonVersion() end
	function a:Print() end
	function a:Debug() end
	function a:Debugf() end
	a:InitializeCommunications()
	a:InitializeGeographicComms()
	return a
end
local function Row(topic, data)
	return { topic = topic, data = data }
end
local function Location(_, _, x)
	return Row(
		"LOC",
		{
			mask = 3,
			mapID = 12,
			x = tonumber(x),
			y = 0.6,
			classFile = "MAGE",
			className = "Mage",
			race = "Human",
			faction = "Alliance",
			level = 60,
		}
	)
end
local function Receive(a, session, sequence, sampled, row)
	row.sampledAt, row.revision = sampled and (1700000000 + sampled) or 0, sequence
	local frames = a:BuildCommFrames(
		"STATE",
		{ records = { row } },
		{ session = session, messageId = tostring(sequence), stamp = row.sampledAt }
	)
	if not frames then
		return false
	end
	local accepted = false
	for _, wire in ipairs(frames) do
		accepted = a:ReceiveCommunication(a.commPrefix, wire, "CHANNEL", "Friend-Realm", 6, "QuestTogether")
	end
	return accepted
end
local function Epoch(a)
	return a.peerSnapshotState.peers["Friend-Realm"].epoch
end
local function Tick(a, seconds)
	for _ = 1, seconds * 5 do
		a.now = a.now + 0.2
		a:UpdateGeographicComms()
		a:UpdateCommunicationRuntime()
	end
end
QT:RegisterTest(
	"unseen old geographic session cannot retire current location or a previously unknown metadata field",
	function()
		local a = Peer()
		a.now = 110
		assert(Receive(a, "200000-2", 1, 110, Location(nil, nil, 0.5)))
		a.now = 111
		Equal(Receive(a, "100000-1", 1, 100, Location(nil, nil, 0.1)), false)
		Equal(Receive(a, "100000-1", 2, 100, Row("QTCI", { streams = true, raceID = 1 })), false)
		Equal(Epoch(a).session, "200000-2")
		Equal(#Epoch(a).order, 0)
		a.now = 112
		assert(Receive(a, "200000-2", 2, 112, Location(nil, nil, 0.7)))
		Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.7)
	end
)
QT:RegisterTest("geographic epoch changes commit only after accepted data and preserve fragment ordering", function()
	local a = Peer()
	assert(Receive(a, "100000-1", 4, 100, Row("QTVR", { version = "6.5.8", count = 5, partySize = 2 })))
	a.now = 101
	Equal(Receive(a, "200000-2", 1, 101, Row("LOC", { mask = 3 })), false)
	Equal(Epoch(a).session, "100000-1")
	assert(Receive(a, "100000-1", 3, 100, Row("QTCI", { streams = true, raceID = 1 })))
	assert(a:GetPlayerCapabilities("Friend-Realm"))
	a.now = 102
	assert(Receive(a, "200000-2", 2, 102, Row("QTVR", { version = "6.5.8", count = 6, partySize = 2 })))
	Equal(Epoch(a).session, "200000-2")
	assert(Epoch(a).retired["100000-1"])
	Equal(Receive(a, "100000-1", 5, 102, Row("QTVR", { version = "6.5.8", count = 7, partySize = 2 })), false)
	Equal(a:GetPlayerMonitoredQuestCount("Friend-Realm"), 6)
end)
QT:RegisterTest("unstamped and same-second candidate epochs cannot retire a known geographic epoch", function()
	local a = Peer()
	assert(Receive(a, "200000-2", 1, 100, Location(nil, nil, 0.5)))
	for _, session in ipairs({ "100000-1", "300000-3" }) do
		Equal(Receive(a, session, 1, nil, Row("QTCI", { streams = true, raceID = 1 })), false)
		Equal(Receive(a, session, 2, 100, Row("QTCI", { streams = true, raceID = 1 })), false)
	end
	Equal(Epoch(a).session, "200000-2")
	-- V2 requires a sample clock even for established epochs.
	Equal(Receive(a, "200000-2", 2, nil, Row("QTCI", { streams = true, raceID = 1 })), false)
	a.now = 101
	assert(Receive(a, "300000-3", 3, 101, Location(nil, nil, 0.7)))
	Equal(Epoch(a).session, "300000-3")
	Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.7)
end)
QT:RegisterTest("navigation and geographic snapshots share current peer epoch ownership", function()
	local a = Peer()
	a.partyMembers = { [a.name] = {}, ["Friend-Realm"] = {} }
	function a:GetPartyNavigationRoute()
		return "PARTY"
	end
	local function Navigation(session, sequence, sampled, quest)
		return a:HandlePartyNavigationMessage(
			{ questID = quest, mapID = 12, x = 0.4, y = 0.6, following = "", title = "Current" },
			"Friend-Realm",
			{ distribution = "PARTY", session = session, sequence = sequence, stamp = 1700000000 + sampled }
		)
	end
	a.now = 110
	assert(Navigation("200000-2", 1, 110, 42))
	Equal(Receive(a, "100000-1", 9, 100, Location(nil, nil, 0.1)), false)
	Equal(Receive(a, "100000-1", 10, 100, Row("QTPR", { active = false })), false)
	Equal(a.partyNavigationState.peers["Friend-Realm"].questID, 42)
	assert(Receive(a, "200000-2", 2, 110, Location(nil, nil, 0.5)))
	a.now = 111
	assert(Receive(a, "300000-3", 1, 111, Location(nil, nil, 0.7)))
	Equal(Navigation("200000-2", 3, 110, 43), false)
	assert(Navigation("300000-3", 2, 111, 77))
	Equal(a.partyNavigationState.peers["Friend-Realm"].questID, 77)
	Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.7)
end)
QT:RegisterTest("typed join observations restore availability only through fresh ordered reentry", function()
	local a = Peer()
	local join = Row("QJST", { grouped = "1", invite = true })
	assert(Receive(a, "9000-1", 1, 100, join))
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), true)
	a.now = 101
	assert(Receive(a, "9000-1", 2, 101, Row("QTPR", { active = false })))
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), false)
	Equal(Receive(a, "9000-1", 1, 100, join), false)
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), false)
	a.now = 105
	assert(Receive(a, "9000-1", 3, 105, join))
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), true)
	Equal(a:IsKnownQTPlayer("Friend-Realm"), true)
	assert(Receive(a, "9000-1", 4, 105, Row("QJST", { grouped = "0", invite = true })))
	Equal(Receive(a, "9000-1", 3, 105, join), false)
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), false)
end)
QT:RegisterTest("world reentry immediately republishes fresh join metadata after ordered departure", function()
	local sender, receiver = Peer("Friend-Realm"), Peer("Me-Realm")
	sender.other, sender.grouped = receiver, true
	sender:UpdateGeographicSubscriptions()
	receiver:UpdateGeographicSubscriptions()
	sender:BroadcastQTPlayerPresence()
	sender:BroadcastPlayerLocation(true)
	assert(sender:BroadcastPartyJoinMetadata())
	Tick(sender, 5)
	Equal(receiver:ShouldRequestPartyJoin(sender.name), true)
	local old = receiver.peerSnapshotState.peers[sender.name].fields.QJST.sequence
	-- Fencing cancels queued work but leaves one best-effort departure budget.
	sender:EndCommsWorldSession()
	sender:FlushGeographicDeparture()
	Equal(receiver:ShouldRequestPartyJoin(sender.name), false)
	sender.now = 110
	sender:ResumeCommsWorldSession()
	assert(sender.geographicCommsState.latest.QJST)
	Tick(sender, 5)
	Equal(receiver:ShouldRequestPartyJoin(sender.name), true)
	assert(receiver.peerSnapshotState.peers[sender.name].fields.QJST.sequence > old)
	sender:EndCommsWorldSession()
	sender:ResumeCommsWorldSession()
	assert(sender.geographicCommsState.latest.QJST, "same-tick reentry cannot lose staged join metadata")
end)
