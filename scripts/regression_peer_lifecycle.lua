-- Real serializers, receive handlers and world-lifetime senders on private peers.
-- Native adapters are per fixture; these tests never modify live Blizzard state.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function Peer(name)
	local a = setmetatable(
		{
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
		},
		{ __index = QT }
	)
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
	a:InitializeGeographicComms()
	return a
end
local function Snapshot(a, session, sequence, sampled, wire)
	return "1," .. (1700000000 + sampled) .. "," .. session .. "," .. sequence .. ";0," .. #wire .. ":" .. wire
end
local function Receive(a, session, sequence, sampled, wire)
	return a:HandleGeographicSnapshot(Snapshot(a, session, sequence, sampled, wire), "Friend-Realm")
end
local function Location(session, sequence, x)
	return "LOC|1," .. session .. "," .. sequence .. ",3,12," .. x .. ",0.6,MAGE,Mage,Human,Alliance,60,0"
end
local function Tick(a, seconds)
	for _ = 1, seconds * 5 do
		a.now = a.now + 0.2
		a:UpdateGeographicComms()
		a:DrainTransport()
	end
end

QT:RegisterTest(
	"unseen old geographic session cannot retire current location or a previously unknown metadata field",
	function()
		local a = Peer()
		a.now = 110
		assert(Receive(a, "200000-2", 1, 110, Location("200000-2", 1, "0.5")))
		a.now = 111
		Equal(Receive(a, "100000-1", 1, 100, Location("100000-1", 1, "0.1")), false)
		Equal(Receive(a, "100000-1", 2, 100, "QTCI|1,1,1,1"), false)
		Equal(a.geographicCommsState.peers["Friend-Realm"].session, "200000-2")
		Equal(#a.geographicCommsState.peers["Friend-Realm"].retired, 0)
		a.now = 112
		assert(Receive(a, "200000-2", 2, 112, Location("200000-2", 2, "0.7")))
		Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.7)
	end
)

QT:RegisterTest("geographic epoch changes commit only after accepted data and preserve fragment ordering", function()
	local a = Peer()
	assert(Receive(a, "100000-1", 4, 100, "QTVR|2,6.5.8,5,2"))
	a.now = 101
	assert(Receive(a, "200000-2", 1, 101, "LOC|invalid"))
	Equal(a.geographicCommsState.peers["Friend-Realm"].session, "100000-1")
	assert(Receive(a, "100000-1", 3, 100, "QTCI|1,1,1,1"))
	assert(a.nearbyStreamState.capabilities["Friend-Realm"])
	a.now = 102
	assert(Receive(a, "200000-2", 1, 102, "QTVR|2,6.5.8,6,2"))
	Equal(a.geographicCommsState.peers["Friend-Realm"].session, "200000-2")
	Equal(a.geographicCommsState.peers["Friend-Realm"].retired[1], "100000-1")
	Equal(Receive(a, "100000-1", 5, 102, "QTVR|2,6.5.8,7,2"), false)
	Equal(a:GetPlayerMonitoredQuestCount("Friend-Realm"), 6)
end)

QT:RegisterTest("unstamped and same-second candidate epochs cannot retire a known geographic epoch", function()
	local a = Peer()
	assert(Receive(a, "200000-2", 1, 100, Location("200000-2", 1, "0.5")))
	local function UnknownStamp(session, sequence, wire)
		return a:HandleGeographicSnapshot(
			"1,0," .. session .. "," .. sequence .. ";0," .. #wire .. ":" .. wire,
			"Friend-Realm"
		)
	end
	Equal(UnknownStamp("100000-1", 1, "QTCI|1,1,1,1"), false)
	Equal(Receive(a, "100000-1", 1, 100, "QTCI|1,1,1,1"), false)
	Equal(Receive(a, "300000-3", 1, 100, "QTCI|1,1,1,1"), false)
	Equal(a.geographicCommsState.peers["Friend-Realm"].session, "200000-2")
	-- Missing clocks are still allowed for an already established epoch, and
	-- a same-second restart becomes admissible once its publication is newer.
	assert(UnknownStamp("200000-2", 2, "QTCI|1,1,1,1"))
	a.now = 101
	assert(Receive(a, "300000-3", 2, 101, Location("300000-3", 2, "0.7")))
	Equal(a.geographicCommsState.peers["Friend-Realm"].session, "300000-3")
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
			"1,"
				.. (1700000000 + sampled)
				.. ","
				.. session
				.. ","
				.. sequence
				.. ",0,"
				.. quest
				.. ",12,4000,6000,,Current",
			"Friend-Realm",
			"PARTY",
			true
		)
	end
	a.now = 110
	assert(Navigation("200000-2", 1, 110, 42))
	Equal(Receive(a, "100000-1", 9, 100, Location("100000-1", 9, "0.1")), false)
	Equal(Receive(a, "100000-1", 10, 100, "QTPR|1,0"), false)
	Equal(a.partyNavigationState.peers["Friend-Realm"].questID, 42)
	assert(Receive(a, "200000-2", 2, 110, Location("200000-2", 2, "0.5")))
	a.now = 111
	assert(Receive(a, "300000-3", 1, 111, Location("300000-3", 1, "0.7")))
	Equal(Navigation("200000-2", 3, 110, 43), false)
	assert(Navigation("300000-3", 2, 111, 77))
	Equal(a.partyNavigationState.peers["Friend-Realm"].questID, 77)
	Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.7)
end)

QT:RegisterTest("older senders restore the same join session only through fresh ordered reentry", function()
	local a = Peer()
	assert(Receive(a, "9000-1", 1, 100, "QJST|1,1000-1,1,1,1"))
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), true)
	a.now = 101
	assert(Receive(a, "9000-1", 2, 101, "QTPR|1,0"))
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), false)
	Equal(a:HandlePartyJoinMetadata("1,1000-1,2,1,1", "Friend-Realm"), false)
	assert(Receive(a, "9000-1", 1, 100, "QJST|1,1000-1,2,1,1"))
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), false)
	a.now = 105
	assert(Receive(a, "9000-1", 3, 105, "QJST|1,1000-1,2,1,1"))
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), true)
	Equal(a:IsKnownQTPlayer("Friend-Realm"), true)
	assert(Receive(a, "9000-1", 4, 105, "QJST|1,2000-2,1,0,1"))
	assert(Receive(a, "9000-1", 5, 105, "QJST|1,1000-1,3,1,1"))
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), false)
	Equal(a.partyJoinState.peers["Friend-Realm"].session, "2000-2")
end)

QT:RegisterTest("world reentry immediately republishes a distinct join session for legacy receivers", function()
	local sender, receiver = Peer("Friend-Realm"), Peer("Me-Realm")
	sender.other, sender.grouped = receiver, true
	sender:UpdateGeographicSubscriptions()
	receiver:UpdateGeographicSubscriptions()
	sender:BroadcastQTPlayerPresence()
	sender:BroadcastPlayerLocation(true)
	assert(sender:BroadcastPartyJoinMetadata())
	Tick(sender, 5)
	Equal(receiver:ShouldRequestPartyJoin(sender.name), true)
	local old = sender.partyJoinState.session
	sender:EndCommsWorldSession()
	sender:BroadcastQTPlayerPresence(true)
	sender:BroadcastPlayerLocation(true, true)
	sender:FlushGeographicDeparture()
	Equal(receiver:ShouldRequestPartyJoin(sender.name), false)
	sender.now = 110
	sender:ResumeCommsWorldSession()
	local current = sender.partyJoinState.session
	assert(current ~= old)
	assert(sender.geographicCommsState.latest.QJST.wire:find(current, 1, true))
	Tick(sender, 5)
	Equal(receiver:ShouldRequestPartyJoin(sender.name), true)
	Equal(receiver.partyJoinState.peers[sender.name].session, current)
	-- No modern context: older QJST receivers accept a new inner epoch while
	-- keeping the previous one retired, so mixed installations recover too.
	local legacy = Peer("Legacy-Realm")
	assert(legacy:HandlePartyJoinMetadata("1," .. old .. ",1,1,1", sender.name))
	legacy:RecordQTPlayerPresence(sender.name, false)
	assert(legacy:HandlePartyJoinMetadata("1," .. current .. ",1,1,1", sender.name))
	Equal(legacy:ShouldRequestPartyJoin(sender.name), true)
	Equal(legacy:HandlePartyJoinMetadata("1," .. old .. ",2,1,1", sender.name), false)
	-- Reentering twice without advancing the clock must still use a new epoch.
	sender:EndCommsWorldSession()
	sender:ResumeCommsWorldSession()
	assert(sender.partyJoinState.session ~= current)
end)
