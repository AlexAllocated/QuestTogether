-- Private models only: no live frame/global/native API replacement.
local QT = _G.QuestTogether
local function Equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function Fixture()
	local a = setmetatable({ isEnabled = true, isLocalDeveloper = true, now = 100,
		partyMembers = {}, db = { profile = QT:DeepCopy(QT.DEFAULTS.profile), global = {} } }, { __index = QT })
	a.API = { GetTime = function() return a.now end, GetRealmName = function() return "Realm" end }
	function a:GetPlayerFullName() return "Me-Realm" end
	function a:IsSelfSender(n) return n == "Me-Realm" end
	function a:IsIgnoredPlayerName(n) return n == self.ignored end
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:GetAnnouncementServerTime() return 1800000000 + math.floor(self.now) end
	function a:RefreshQTPlayerPlatePresence() end
	function a:RefreshQTPlayerPartnerIndicators() end
	function a:RefreshPlayerLocationPins() end
	function a:GetPlayerLocationPriorityOrigin() return { continent = 0, north = 0, west = 0 } end
	function a:GetLocationPinWorldPosition(_, x, y) self.projections = (self.projections or 0) + 1; return 0, x, y end
	function a:GetLocationPinSurface() return { width = 200, height = 200, mapID = 12 } end
	function a:ProjectPlayerLocationPin(_, row) return row.x * 200, row.y * 200 end
	return a
end
local function Pong(a, shared, age, looking)
	return { senderName = "Friend-Realm", developer = true, locationShared = shared,
		mapID = "12", coordX = "42", coordY = "63", classFile = "MAGE", className = "Mage",
		raceName = "Human", level = "60", faction = "Alliance", lookingForQuestPartners = looking,
		sampledAt = a:GetAnnouncementServerTime() - (age or 0) }
end
local function Location(sequence, x)
	return "1,1000-1," .. sequence .. ",3,12," .. (x or "0.4") .. ",0.6,MAGE,Mage,Human,Alliance,60,0"
end

QT:RegisterTest("party map filter migration preserves sharing and collapses retired choices", function()
	for _, sharing in ipairs({ true, false }) do
		local party = { sharePlayerLocation = sharing, showPlayerLocations = true, mapPartyOnly = true }
		QT:MigratePlayerMapVisibility(party)
		Equal(party.showPlayerLocations, false); Equal(party.sharePlayerLocation, sharing)
		Equal(party.mapPartyOnly, nil); Equal(party.mapAlwaysShowParty, nil)
		local partners = { sharePlayerLocation = sharing, showPlayerLocations = true, onlyShowQuestPartners = true, mapAlwaysShowParty = true }
		QT:MigratePlayerMapVisibility(partners)
		Equal(partners.showPlayerLocations, true); Equal(partners.onlyShowQuestPartners, true)
		Equal(partners.sharePlayerLocation, sharing); Equal(partners.mapAlwaysShowParty, nil)
		QT:MigratePlayerMapVisibility(partners)
		Equal(partners.showPlayerLocations, true)
	end
end)

QT:RegisterTest("party members never get public or private QT dots or nearby stream slots", function()
	local a = Fixture()
	a:AcceptDeveloperPingResponse(Pong(a, true, 0, true), { developerRequest = true })
	assert(a:HandlePlayerCapabilityMetadata("1,1,0", "Friend-Realm"))
	Equal(#a:GetNearbyStreamCandidates(), 1)
	a.partyMembers["Friend-Realm"] = { classFile = "MAGE" }
	for _, surface in ipairs({ "map", "minimap" }) do Equal(#a:GetVisiblePlayerLocations(surface), 0) end
	Equal(#a:GetNearbyStreamCandidates(), 0)
	a.now = 101
	a:AcceptDeveloperPingResponse(Pong(a, false, 0, true), { developerRequest = true })
	assert(a.developerPlayerData["Friend-Realm"])
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	a.partyMembers = {}
	Equal(#a:GetVisiblePlayerLocations("map"), 1)
	a.db.profile.onlyShowQuestPartners = true
	a.now = 102
	a:AcceptDeveloperPingResponse(Pong(a, false, 0, false), { developerRequest = true })
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	a.db.profile.onlyShowQuestPartners = false
	a.db.profile.sharePlayerLocation = false
	Equal(#a:GetVisiblePlayerLocations("map"), 1) -- Viewing remains independent of sharing.
end)

QT:RegisterTest("diagnostic LFQP refresh uses normal filters and preserves public ordering", function()
	local a = Fixture()
	assert(a:HandleQuestPartnerStatusMessage("1,2000-1,5,1", "Friend-Realm"))
	a.now = 105
	a:AcceptDeveloperPingResponse(Pong(a, true, 0, false), { developerRequest = true })
	Equal(a:IsPlayerLookingForQuestPartners("Friend-Realm"), false)
	Equal(a.qtPlayerPresenceState.questPartners["Friend-Realm"].sequence, 5)
	a.db.profile.onlyShowQuestPartners = true
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	Equal(a:HandleQuestPartnerStatusMessage("1,2000-1,6,1", "Friend-Realm", 20), false)
	a.now = 110
	assert(a:HandleQuestPartnerStatusMessage("1,2000-1,6,1", "Friend-Realm", 0))
	Equal(#a:GetVisiblePlayerLocations("map"), 1)
	a:AcceptDeveloperPingResponse(Pong(a, true, 6, false), { developerRequest = true })
	Equal(a:IsPlayerLookingForQuestPartners("Friend-Realm"), true)
	a.now = 111
	a:AcceptDeveloperPingResponse(Pong(a, true, 0, false), { developerRequest = true })
	Equal(a:IsPlayerLookingForQuestPartners("Friend-Realm"), false)
end)

QT:RegisterTest("diagnostic party imports reject stale snapshots independently from fresh location", function()
	local a = Fixture()
	assert(a:HandlePartyVisualMetadata("1,0,,,", "Friend-Realm"))
	a.now = 101
	local response = Pong(a, true, 20, true)
	response.partyPayload = "1,2,OldLeader-Realm,MAGE,123"
	a:AcceptDeveloperPingResponse(response, { developerRequest = true })
	Equal(a.partyVisualState.peers["Friend-Realm"].size, 0)
	Equal(a.playerLocationState.peers["Friend-Realm"].sampledAt, 81)
	a.now = 102
	response.sampledAt = a:GetAnnouncementServerTime()
	a:AcceptDeveloperPingResponse(response, { developerRequest = true })
	Equal(a.partyVisualState.peers["Friend-Realm"].size, 2)
	Equal(a.partyVisualState.peers["Friend-Realm"].sampledAt, 102)
	Equal(a:HandlePartyVisualMetadata("1,0,,,", "Friend-Realm", 10), false)
end)

QT:RegisterTest("ordered departure clears private dots and fences late replies but permits fresh reentry", function()
	local a = Fixture()
	a:AcceptDeveloperPingResponse(Pong(a, false, 0, true), { developerRequest = true })
	Equal(#a:GetVisiblePlayerLocations("map"), 1)
	a.now = 101
	assert(a:RecordPeerDeparture("Friend-Realm", 101, "9000-1", 20))
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	Equal(a:IsKnownQTPlayer("Friend-Realm"), false)
	Equal(a:RecordQTPlayerPresence("Friend-Realm", true), false)
	a:AcceptDeveloperPingResponse(Pong(a, false, 1, true), { developerRequest = true })
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	Equal(a:CanAcceptPeerUpdate("Friend-Realm", "QTVR", 101, "9000-1", 19), false)
	Equal(a:CanAcceptPeerUpdate("Friend-Realm", "QTVR", 101, "9000-1", 20), false)
	assert(a:WithPeerUpdateContext("Friend-Realm", 101, "9000-1", 21, a.RecordQTPlayerPresence, a, "Friend-Realm", true))
	assert(a:RecordPeerUpdate("Friend-Realm", "QTVR", 101, "9000-1", 21))
	Equal(a:IsKnownQTPlayer("Friend-Realm"), true)
	Equal(a:RecordPeerDeparture("Friend-Realm", 101, "9000-1", 20), false)
	assert(a:RecordPeerDeparture("Friend-Realm", 101, "9000-1", 22))
	Equal(a:CanAcceptPeerUpdate("Friend-Realm", "LOC", 101, "9000-2", 1), true)
	a.now = 102
	assert(a:RecordPeerPresenceFromSnapshot("Friend-Realm", 102))
	Equal(a:IsKnownQTPlayer("Friend-Realm"), true)
end)

QT:RegisterTest("peer update context is cleaned after handler failure", function()
	local a = Fixture()
	local ok = pcall(a.WithPeerUpdateContext, a, "Friend-Realm", 100, "1-1", 1, function() error("expected fixture failure") end)
	Equal(ok, false); Equal(rawget(a, "peerUpdateContext"), nil)
end)

QT:RegisterTest("legacy departure retains stream counters and permits explicit legacy reentry", function()
	local a = Fixture()
	assert(a:HandlePlayerLocationMessage(Location(5), "Friend-Realm"))
	assert(a:HandleQuestPartnerStatusMessage("1,2000-1,7,1", "Friend-Realm"))
	a.now = 101
	assert(a:HandleQTPlayerPresenceMessage("1,0", "Friend-Realm"))
	Equal(a:IsKnownQTPlayer("Friend-Realm"), false)
	Equal(a:IsPlayerLookingForQuestPartners("Friend-Realm"), false)
	Equal(a.playerLocationState.peers["Friend-Realm"].mask, 0)
	Equal(a.playerLocationState.peers["Friend-Realm"].x, nil)
	Equal(a.playerLocationState.peers["Friend-Realm"].sequence, 5)
	Equal(a.qtPlayerPresenceState.questPartners["Friend-Realm"].sequence, 7)
	a.now = 102
	Equal(a:HandlePlayerLocationMessage(Location(5), "Friend-Realm"), false)
	Equal(a:HandleQuestPartnerStatusMessage("1,2000-1,7,1", "Friend-Realm"), false)
	Equal(a:RecordQTPlayerPresence("Friend-Realm", true), false)
	assert(a:HandlePlayerLocationMessage(Location(6), "Friend-Realm"))
	Equal(a:IsKnownQTPlayer("Friend-Realm"), true)
	a.now = 103
	assert(a:HandleQTPlayerPresenceMessage("1,0", "Friend-Realm"))
	assert(a:HandleQuestPartnerStatusMessage("1,2000-1,8,1", "Friend-Realm"))
	Equal(a:IsPlayerLookingForQuestPartners("Friend-Realm"), true)
	assert(a:HandleQTPlayerPresenceMessage("1,0", "Friend-Realm"))
	assert(a:HandleQTPlayerPresenceMessage("1,1", "Friend-Realm"))
	Equal(a:IsKnownQTPlayer("Friend-Realm"), true)
	a.now = 104
	assert(a:RecordPeerDeparture("Friend-Realm", 104, "9000-1", 20))
	Equal(a:HandleQTPlayerPresenceMessage("1,1", "Friend-Realm"), false)
end)

QT:RegisterTest("newer public sequence resolves fractional age rounding without replacing a newer manual sample", function()
	local a = Fixture()
	a.now = 100.8
	assert(a:HandlePlayerLocationMessage(Location(1), "Friend-Realm", 0, { session = "9000-1", sequence = 1 }))
	a.now = 101.2
	assert(a:HandlePlayerLocationMessage(Location(2, "0.5"), "Friend-Realm", 1, { session = "9000-1", sequence = 2 }))
	Equal(a.playerLocationState.peers["Friend-Realm"].x, .5)
	a.now = 102.8
	a:AcceptDeveloperPingResponse(Pong(a, true, 0, false), { developerRequest = true })
	a.now = 103.2
	Equal(a:HandlePlayerLocationMessage(Location(3), "Friend-Realm", 1, { session = "9000-1", sequence = 3 }), false)
	Equal(a.playerLocationState.peers["Friend-Realm"].x, .42)
end)

QT:RegisterTest("dense location admission reuses unchanged peer world projections", function()
	local a = Fixture()
	for i = 1, 512 do assert(a:HandlePlayerLocationMessage(Location(1), "Peer" .. i .. "-Realm")) end
	assert(a:HandlePlayerLocationMessage(Location(1, "0.9"), "Far-Realm"))
	local first = a.projections
	assert(first >= 512 and first <= 514)
	assert(a:HandlePlayerLocationMessage(Location(1, "0.95"), "Farther-Realm"))
	Equal(a.projections - first, 1)
	local row = a.playerLocationState.peers["Peer1-Realm"]
	local origin = a:GetPlayerLocationPriorityOrigin()
	a:GetPlayerLocationPriorityDistance(row, origin)
	local before = a.projections
	row.x = .1
	a:GetPlayerLocationPriorityDistance(row, origin)
	Equal(a.projections, before + 1)
end)
