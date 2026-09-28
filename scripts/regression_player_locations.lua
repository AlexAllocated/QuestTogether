local QT = _G.QuestTogether
local function Equal(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end

local function Fixture(name)
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
	return a
end

QT:RegisterTest("locations default to sharing and viewing both surfaces and preserve all tooltip metadata", function()
	local a, b = Fixture(), Fixture("Friend-Realm")
	a.other = b
	Equal(a:GetPlayerLocationShareMask(), 3)
	assert(a:BroadcastPlayerLocation())
	Equal(#a.sent, 1)
	local peers = b:GetVisiblePlayerLocations("map")
	Equal(#peers, 1)
	local p = peers[1]
	Equal(p.name, "Me-Realm")
	Equal(p.mapID, 12)
	Equal(p.x, 0.4)
	Equal(p.y, 0.6)
	Equal(p.race, "Human")
	Equal(p.classFile, "MAGE")
	Equal(p.className, "Mage")
	Equal(p.faction, "Alliance")
	Equal(p.level, 60)
	Equal(p.warMode, false)
	Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
end)

QT:RegisterTest("locations omit unsupported War Mode without dropping cross-phase positions", function()
	for _, capability in ipairs({ "regional", "disabled", "unknown", "enabled" }) do
		local regional = capability == "regional"
		local a = Fixture(regional and "Torres Sky" or "Me-Realm")
		local b = Fixture(regional and "Mira Dawn" or "Friend-Realm")
		a.other = b
		a.forever, b.forever = regional, regional
		if capability == "disabled" then
			a.warModeFeature = false
		elseif capability == "unknown" then
			a.warModeFeature = nil
		end
		-- The receiving player can have a different mode. This metadata does
		-- not authorize filtering either map surface's shared positions.
		b.API.IsWarModeActive = function() return true end
		assert(a:BroadcastPlayerLocation())
		Equal(a.warModeReads or 0, capability == "enabled" and 1 or 0)
		for _, surface in ipairs({ "map", "minimap" }) do
			local peers = b:GetVisiblePlayerLocations(surface)
			Equal(#peers, 1)
			Equal(peers[1].x, 0.4)
			Equal(peers[1].y, 0.6)
			if capability == "enabled" then
				Equal(peers[1].warMode, false)
			else
				Equal(peers[1].warMode, nil)
			end
			if capability == "regional" then Equal(peers[1].name, "Torres Sky") end
		end
	end
end)

QT:RegisterTest(
	"locations independently honor sender and viewer options and withdraw previously visible positions",
	function()
		local a, b = Fixture(), Fixture("Friend-Realm")
		a.other = b
		assert(a:SetOption("shareLocationOnMinimap", false))
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
		assert(b:SetOption("showLocationsOnMap", false))
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		assert(b:SetOption("showLocationsOnMap", true))
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		assert(a:SetOption("shareLocationOnMap", false))
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		assert(a.sent[#a.sent].message:match(",0$"))
		assert(not a:SetOption("shareLocationOnMap", "true"))
		Equal(a:GetPlayerLocationShareMask(), 0)
		assert(a:SetOption("shareLocationOnMinimap", true))
		Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
	end
)

QT:RegisterTest("location sends pace position reads movement heartbeat and failed sends", function()
	local a = Fixture()
	assert(a:BroadcastPlayerLocation())
	local reads = a.reads
	for i = 1, 20 do
		a.now = 100 + i * 0.2
		a:BroadcastPlayerLocation()
	end
	Equal(a.reads, reads)
	Equal(#a.sent, 1)
	a.now = 105
	assert(not a:BroadcastPlayerLocation())
	a.position.x = 0.41
	a.now = 106
	assert(not a:BroadcastPlayerLocation())
	Equal(a.reads, reads + 1)
	a.now = 110
	assert(a:BroadcastPlayerLocation())
	Equal(#a.sent, 2)
	for _, now in ipairs({ 115, 120, 125 }) do
		a.now = now
		assert(not a:BroadcastPlayerLocation())
	end
	a.now = 130
	assert(a:BroadcastPlayerLocation())
	a.sendFails, a.position.x, a.now = true, 0.42, 140
	assert(not a:BroadcastPlayerLocation())
	Equal(#a.sent, 4)
	a.now = 141
	assert(not a:BroadcastPlayerLocation())
	Equal(#a.sent, 4)
end)

QT:RegisterTest("failed location sends never deliver a point to the receiver", function()
	local a, b = Fixture(), Fixture("Friend-Realm")
	a.other, a.sendFails = b, true
	Equal(a:BroadcastPlayerLocation(), false)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	a.now, b.now, a.sendFails = 110, 110, false
	assert(a:BroadcastPlayerLocation())
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
end)

QT:RegisterTest("location movement samples at five seconds but sends no faster than ten", function()
	local a = Fixture()
	assert(a:BroadcastPlayerLocation())
	for now = 105, 160, 5 do
		a.now, a.position.x = now, (now - 100) / 100
		Equal(a:BroadcastPlayerLocation(), now % 10 == 0)
	end
	Equal(a.reads, 13)
	Equal(#a.sent, 7, "moving traffic must be at most one position per ten seconds")
end)

QT:RegisterTest("location opt-out retries partial and total withdrawal failures after route recovery", function()
	for _, failures in ipairs({ { PARTY = true }, { CHANNEL = true }, { PARTY = true, CHANNEL = true } }) do
		local a, party, channel = Fixture(), Fixture("Party-Realm"), Fixture("Channel-Realm")
		a.inParty = true
		a.peersByRoute = { PARTY = party, CHANNEL = channel }
		assert(a:BroadcastPlayerLocation())
		Equal(#party:GetVisiblePlayerLocations("map"), 1)
		Equal(#channel:GetVisiblePlayerLocations("map"), 1)
		a.failedRoutes = failures
		a.db.profile.shareLocationOnMap, a.db.profile.shareLocationOnMinimap = false, false
		a:BroadcastPlayerLocation(true)
		Equal(#party:GetVisiblePlayerLocations("map"), failures.PARTY and 1 or 0)
		Equal(#channel:GetVisiblePlayerLocations("map"), failures.CHANNEL and 1 or 0)
		local attempts = #a.sent
		a.failedRoutes = nil
		for i = 1, 24 do
			a.now = 100 + i * 0.2
			a:BroadcastPlayerLocation()
		end
		Equal(#a.sent, attempts)
		a.now, party.now, channel.now = 105, 105, 105
		assert(a:BroadcastPlayerLocation())
		Equal(#party:GetVisiblePlayerLocations("map"), 0)
		Equal(#channel:GetVisiblePlayerLocations("minimap"), 0)
	end
end)

QT:RegisterTest("location withdrawal retries stop at old-position expiry even when every send fails", function()
	for _, failed in ipairs({ false, true }) do
		local a, b = Fixture(), Fixture("Friend-Realm")
		a.other = b
		assert(a:BroadcastPlayerLocation())
		a.db.profile.shareLocationOnMap, a.db.profile.shareLocationOnMinimap = false, false
		a.sendFails = failed
		a:BroadcastPlayerLocation(true)
		for now = 105, 215, 5 do
			a.now, b.now = now, now
			a:BroadcastPlayerLocation()
		end
		Equal(#a.sent, 25) -- one point, one opt-out, twenty-three bounded retries
		local attempts = #a.sent
		for now = 220, 275, 5 do
			a.now, b.now = now, now
			Equal(a:BroadcastPlayerLocation(), false)
		end
		Equal(#a.sent, attempts)
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		-- Resuming sharing publishes only a fresh position, and a new opt-out
		-- has its own expiry window rather than inheriting the exhausted one.
		a.sendFails, a.db.profile.shareLocationOnMap, a.position.x = false, true, 0.7
		assert(a:BroadcastPlayerLocation(true))
		Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.7)
		a.db.profile.shareLocationOnMap = false
		assert(a:BroadcastPlayerLocation(true))
		a.now = 280
		assert(a:BroadcastPlayerLocation())
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
	end
end)

QT:RegisterTest("single-surface location opt-out retries every route before the stationary heartbeat", function()
	for _, surface in ipairs({ "map", "minimap" }) do
		for _, failures in ipairs({ { PARTY = true }, { CHANNEL = true }, { PARTY = true, CHANNEL = true } }) do
			local a, party, channel = Fixture(), Fixture("Party-Realm"), Fixture("Channel-Realm")
			a.inParty, a.peersByRoute = true, { PARTY = party, CHANNEL = channel }
			assert(a:BroadcastPlayerLocation())
			a.failedRoutes = failures
			assert(a:SetOption(surface == "map" and "shareLocationOnMap" or "shareLocationOnMinimap", false))
			Equal(#party:GetVisiblePlayerLocations(surface), failures.PARTY and 1 or 0)
			Equal(#channel:GetVisiblePlayerLocations(surface), failures.CHANNEL and 1 or 0)
			local attempts = #a.sent
			a.failedRoutes = nil
			for i = 1, 24 do
				a.now = 100 + i * 0.2
				Equal(a:BroadcastPlayerLocation(), false)
			end
			Equal(#a.sent, attempts)
			a.now, party.now, channel.now = 105, 105, 105
			assert(a:BroadcastPlayerLocation(), "revoking either surface requires the five-second retry")
			local retained = surface == "map" and "minimap" or "map"
			for _, receiver in ipairs({ party, channel }) do
				Equal(#receiver:GetVisiblePlayerLocations(surface), 0)
				Equal(#receiver:GetVisiblePlayerLocations(retained), 1)
			end
		end
	end
end)

QT:RegisterTest("location permission retry expiry belongs to each surface and resets for fresh sharing", function()
	local a, b = Fixture(), Fixture("Friend-Realm")
	a.other = b
	assert(a:BroadcastPlayerLocation())
	assert(a:SetOption("shareLocationOnMinimap", false))
	for now = 105, 215, 5 do
		a.now, b.now = now, now
		assert(a:BroadcastPlayerLocation())
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
	end
	-- Updating the retained map surface must not extend the minimap revocation.
	local attempts = #a.sent
	for now = 220, 230, 5 do
		a.now, b.now = now, now
		Equal(a:BroadcastPlayerLocation(), false)
	end
	Equal(#a.sent, attempts)
	a.now, b.now = 235, 235
	assert(a:BroadcastPlayerLocation(), "the remaining surface resumes its ordinary heartbeat")
	assert(a:SetOption("shareLocationOnMap", false))
	local reads = a.reads
	for now = 240, 350, 5 do
		a.now, b.now = now, now
		assert(a:BroadcastPlayerLocation(), "the newly revoked map has its own expiry")
	end
	Equal(a.reads, reads)
	a.now = 355
	Equal(a:BroadcastPlayerLocation(), false)
	a.now, b.now, a.position.x = 360, 360, 0.7
	assert(a:SetOption("shareLocationOnMinimap", true))
	Equal(b:GetVisiblePlayerLocations("minimap")[1].x, 0.7)
	assert(a:SetOption("shareLocationOnMinimap", false))
	a.now = 365
	assert(a:BroadcastPlayerLocation(), "fresh sharing starts a new bounded revocation lifetime")
	a:ResetPlayerLocations()
	a.now = 370
	Equal(a:BroadcastPlayerLocation(), false, "reset must not retain old publication history")
end)

QT:RegisterTest(
	"location restrictions and unreadable positions retain the last point without renewing it",
	function()
		local a, b = Fixture(), Fixture("Friend-Realm")
		a.other = b
		assert(a:BroadcastPlayerLocation())
		local reads = a.reads
		a.restricted, a.now, b.now = true, 105, 105
		Equal(a:BroadcastPlayerLocation(), false)
		Equal(a.reads, reads)
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		a.restricted, a.position, a.now, b.now = false, { x = math.huge, y = 0 }, 110, 110
		Equal(a:BroadcastPlayerLocation(), false)
		Equal(b:GetVisiblePlayerLocations("map")[1].receivedAt, 100)
		Equal(#a.sent, 1, "unreadable data must not send a withdrawal or a cached location")
		a.position = { x = 0, y = 0 }
		a.now, b.now = 120, 120
		assert(a:BroadcastPlayerLocation())
		Equal(b:GetVisiblePlayerLocations("map")[1].x, 0)
		Equal(b:GetVisiblePlayerLocations("map")[1].receivedAt, 120)
		a.position = nil
		for now = 125, 235, 5 do
			a.now, b.now = now, now
			Equal(a:BroadcastPlayerLocation(), false)
			Equal(#b:GetVisiblePlayerLocations("map"), 1)
		end
		Equal(#a.sent, 2)
		b.now = 240
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
	end
)

QT:RegisterTest("location runtime ticks tolerate lost heartbeats and publish only fresh recovery data", function()
	local a, b = Fixture(), Fixture("Friend-Realm")
	a.other = b
	-- Presence has its own protocol tests; these owned runtime callbacks
	-- exercise location sampling, real transport, pruning and recovery.
	function a:UpdateQTPlayerPresence() end
	function b:UpdateQTPlayerPresence() end
	b.db.profile.shareLocationOnMap, b.db.profile.shareLocationOnMinimap = false, false
	assert(a:InitializePlayerLocations())
	assert(b:InitializePlayerLocations())
	local function Tick(now)
		a.now, b.now = now, now
		a.playerLocationUpdateFrame.scripts.OnUpdate(a.playerLocationUpdateFrame, 0.2)
		b.playerLocationUpdateFrame.scripts.OnUpdate(b.playerLocationUpdateFrame, 0.2)
	end
	Tick(100)
	a.sendFails = true
	for now = 105, 175, 5 do
		Tick(now)
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		Equal(b:GetVisiblePlayerLocations("map")[1].receivedAt, 100)
	end
	Equal(#a.sent, 4, "stationary traffic stays at one attempt per twenty seconds")
	a.sendFails, a.position = false, { x = 0.7, y = 0.8 }
	Tick(180)
	Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.7)
	Equal(b:GetVisiblePlayerLocations("map")[1].receivedAt, 180)
	a.restricted = true
	local reads, sends = a.reads, #a.sent
	for now = 185, 295, 5 do
		Tick(now)
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
	end
	Equal(a.reads, reads)
	Equal(#a.sent, sends)
	Tick(300)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("location privacy changes withdraw immediately while fresh position is unavailable", function()
	for _, key in ipairs({ "shareLocationOnMap", "shareLocationOnMinimap", "both", "disable" }) do
		local a, b = Fixture(), Fixture("Friend-Realm")
		a.other = b
		assert(a:BroadcastPlayerLocation())
		a.restricted, a.now, b.now = true, 101, 101
		if key == "disable" then
			assert(a:BroadcastPlayerLocation(true, true))
		elseif key == "both" then
			a.db.profile.shareLocationOnMap, a.db.profile.shareLocationOnMinimap = false, false
			assert(a:BroadcastPlayerLocation(true))
		else
			assert(a:SetOption(key, false))
		end
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
		assert(a.sent[#a.sent].message:match(",0$"))
		Equal(a.reads, 1)
	end
end)

QT:RegisterTest("location partial privacy withdrawal retries failed routes during a position outage", function()
	local a, party, channel = Fixture(), Fixture("Party-Realm"), Fixture("Channel-Realm")
	a.inParty, a.peersByRoute = true, { PARTY = party, CHANNEL = channel }
	assert(a:BroadcastPlayerLocation())
	a.restricted, a.now, a.failedRoutes = true, 101, { PARTY = true }
	assert(a:SetOption("shareLocationOnMap", false))
	Equal(#party:GetVisiblePlayerLocations("map"), 1)
	Equal(#channel:GetVisiblePlayerLocations("map"), 0)
	local attempts = #a.sent
	a.now, a.failedRoutes = 105, nil
	Equal(a:BroadcastPlayerLocation(), false)
	Equal(#a.sent, attempts)
	a.now = 106
	assert(a:BroadcastPlayerLocation())
	Equal(#party:GetVisiblePlayerLocations("map"), 0)
	Equal(#party:GetVisiblePlayerLocations("minimap"), 0)
	Equal(a.reads, 1)
	a.restricted, a.now, a.position = false, 120, { x = 0.7, y = 0.8 }
	assert(a:BroadcastPlayerLocation())
	Equal(#party:GetVisiblePlayerLocations("map"), 0)
	Equal(party:GetVisiblePlayerLocations("minimap")[1].x, 0.7)
end)

QT:RegisterTest("location ordering session replacement and expiry prevent stale or revoked dots returning", function()
	local a, b = Fixture(), Fixture("Friend-Realm")
	assert(a:BroadcastPlayerLocation())
	local old = a.sent[1].message
	b:OnCommReceived(a.commPrefix, old, "CHANNEL", a.name, 7, "QuestTogether")
	a.now = 101
	assert(a:BroadcastPlayerLocation(true, true))
	b:OnCommReceived(a.commPrefix, a.sent[2].message, "CHANNEL", a.name, 7, "QuestTogether")
	b.now = 102
	b:OnCommReceived(a.commPrefix, old, "CHANNEL", a.name, 7, "QuestTogether")
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	a:ResetPlayerLocations()
	assert(a:BroadcastPlayerLocation(true))
	b:OnCommReceived(a.commPrefix, a.sent[3].message, "CHANNEL", a.name, 7, "QuestTogether")
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	b.now = 103
	b:OnCommReceived(a.commPrefix, a.sent[2].message, "CHANNEL", a.name, 7, "QuestTogether")
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	b.now = 221
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	b.now = 222
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("location transport ignores unsupported routes and uses authoritative Forever identity", function()
	local a, b = Fixture("Anakin Othername"), Fixture("Luke Bucket")
	a.forever, b.forever = true, true
	assert(a:BroadcastPlayerLocation())
	local wire = a.sent[1].message
	b:OnCommReceived(a.commPrefix, wire, "WHISPER", a.name)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b:OnCommReceived(a.commPrefix, wire, "CHANNEL", a.name, 8, "OtherChannel")
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b:OnCommReceived(a.commPrefix, wire, "CHANNEL", a.name, 7, "QuestTogether")
	Equal(b:GetVisiblePlayerLocations("map")[1].name, "Anakin Othername")
	b.ignored[a.name] = true
	b:PrunePlayerLocations(true)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	b.now = 200
	b:OnCommReceived(a.commPrefix, wire, "CHANNEL", a.name, 7, "QuestTogether")
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("location records and malformed wire input are bounded", function()
	local a = Fixture()
	local valid = "1,100-1234,1,3,12,0.4,0.6,MAGE,Mage,Human,Alliance,60,0"
	for _, payload in ipairs({
		"",
		"2,100-1234,1,0",
		"1,100-1234,1,7",
		valid .. ",extra",
		"1,100-1234,1,3,12,nan,0.6,MAGE,Mage,Human,Alliance,60,0",
		"1,100-1234,1,3,12,-0.1,0.6,MAGE,Mage,Human,Alliance,60,0",
		string.rep("x", 256),
	}) do
		Equal(a:DecodePlayerLocationPayload(payload), nil)
	end
	for i = 1, 540 do
		a.now = 100 + i / 100
		assert(a:HandlePlayerLocationMessage(valid, "Peer" .. i .. "-Realm"))
	end
	Equal(#a:GetVisiblePlayerLocations("map"), 512)
end)

QT:RegisterTest("location channel retains fresh positions from two hundred fifty active peers", function()
	local a = Fixture()
	local payload = "LOC|1,100-1234,1,3,12,0.4,0.6,MAGE,Mage,Human,Alliance,60,0"
	for i = 1, 250 do
		a.now = 100 + i / 100
		a:OnCommReceived(a.commPrefix, payload, "CHANNEL", "Peer" .. i .. "-Realm", 7, "QuestTogether")
	end
	Equal(#a:GetVisiblePlayerLocations("map"), 250)
	assert(a.playerLocationState.peers["Peer1-Realm"], "healthy first peers must survive an active shared channel")
	for i = 1, 250 do
		a.now = 120 + i / 100
		a:OnCommReceived(a.commPrefix, payload:gsub(",1,3,", ",2,3,"), "CHANNEL", "Peer" .. i .. "-Realm", 7, "QuestTogether")
	end
	Equal(#a:GetVisiblePlayerLocations("minimap"), 250)
	Equal(a.playerLocationState.peers["Peer1-Realm"].sequence, 2)
end)

QT:RegisterTest("location runtime replacement cancels old update callbacks and clears owned pins", function()
	local a = Fixture()
	assert(a:InitializePlayerLocations())
	local frame, state = a.playerLocationUpdateFrame, a.playerLocationState
	local callback = frame.scripts.OnUpdate
	callback(frame, 0.2)
	Equal(#a.sent, 2)
	Equal(a.sent[1].message, "QTPR|1,1")
	assert(a.sent[2].message:find("LOC|", 1, true) == 1)
	a:ResetPlayerLocations()
	Equal(rawget(a, "playerLocationState"), nil)
	Equal(frame.scripts.OnUpdate, nil)
	assert(a.hidden)
	assert(a:InitializePlayerLocations())
	assert(a.playerLocationState ~= state)
	a.now = 110
	callback(frame, 1)
	Equal(#a.sent, 2)
	frame.scripts.OnUpdate(frame, 0.2)
	Equal(#a.sent, 3)
end)

QT:RegisterTest(
	"disabling both location-sharing options also removes coordinates from quest and ping messages",
	function()
		local a = Fixture()
		a.db.profile.shareLocationOnMap, a.db.profile.shareLocationOnMinimap = false, false
		function a:GetPlayerAnnouncementLocationInfo()
			error("private coordinates must not be read for publication")
		end
		function a:GetAddonVersion()
			return "5.10.0"
		end
		function a:GetAnnouncementIconInfo()
			return "", ""
		end
		local ping = a:GetPlayerPingMetadata()
		Equal(ping.coordX, "")
		Equal(ping.coordY, "")
		Equal(ping.mapID, "")
		local event = a:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Progress", 123)
		assert(event)
		Equal(event.coordX, "")
		Equal(event.coordY, "")
		-- Even a caller supplying already-built metadata cannot bypass the send gate.
		event.coordX, event.coordY, event.mapID, event.zoneName = "40", "60", "12", "Example Zone"
		assert(a:SendAnnouncementWireEvent(event))
		local _, payload = a:DeserializeWireMessage(a.sent[1].message)
		local sent = a:DecodeAnnouncementPayload(payload)
		Equal(sent.coordX, "")
		Equal(sent.coordY, "")
		Equal(sent.zoneName, "")
		assert(sent.mapID == nil or sent.mapID == "")
	end
)

QT:RegisterTest(
	"location metadata sanitizes markup unavailable values and oversized labels without losing consent",
	function()
		local a = Fixture()
		a.API.UnitClass = function()
			return "|cffffffffMage|r", "INVENTED"
		end
		a.API.UnitRace = function()
			return string.rep("z", 100)
		end
		a.API.GetFaction = function()
			error("metadata unavailable")
		end
		a.API.UnitLevel = function()
			return math.huge
		end
		a.API.IsWarModeActive = function()
			return "unknown"
		end
		assert(a:BroadcastPlayerLocation())
		assert(#a.sent[1].message <= 255)
		local _, payload = a:DeserializeWireMessage(a.sent[1].message)
		local data = a:DecodePlayerLocationPayload(payload)
		Equal(data.mask, 3)
		Equal(data.classFile, "")
		assert(not data.className:find("|", 1, true))
		Equal(data.race, "")
		Equal(data.faction, "")
		Equal(data.level, nil)
		Equal(data.warMode, nil)
	end
)
