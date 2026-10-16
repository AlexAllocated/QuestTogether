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
	a.API.GetServerTime = function()
		return 1700000000 + math.floor(a.now)
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
	function a:AdvanceRuntime(now)
		self.now = now or self.now
		if self.runtimeAdvancedAt ~= self.now then
			self.runtimeAdvancedAt = self.now
			-- A changed fixture clock represents a new client frame. Keep the
			-- production ingress budget and advance its real runtime owner.
			self:UpdateCommunicationRuntime()
		end
	end
	a.API.SendAddonMessage = function(prefix, message, route, target)
		local frame, body = a:DecodeCommFrame(message)
		a.sent[#a.sent + 1] = {
			prefix = prefix,
			message = message,
			route = route,
			target = target,
			frame = frame,
			data = frame and frame.total == 1 and a:DecodeCommRecord(frame.operation, body),
		}
		if a.sendFails or (a.failedRoutes and a.failedRoutes[route]) then
			return false
		end
		local other = a.peersByRoute and a.peersByRoute[route] or a.other
		if other then
			other:AdvanceRuntime(a.now)
			if route == "PARTY" then
				-- This domain fixture isolates per-route publication outcomes;
				-- group membership and native-dot filtering have separate tests.
				local data = frame and other:DecodeCommRecord(frame.operation, body)
				if data then
					other:ApplyCommunicationState(
						{ { topic = frame.operation, data = data } },
						a.name,
						{ session = frame.session, sequence = tonumber(frame.messageId), stamp = frame.stamp }
					)
				end
			else
				other:ReceiveCommunication(prefix, message, route, a.name, 7, "QuestTogether")
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
	function a:IsGroupedSender()
		return self.inParty == true
	end
	-- The publication seam completes synchronously here so domain cadence tests
	-- can use exact sample times. Real packet budgets/fragment delivery are
	-- exercised by network_v2 and presence_v2 rather than bypassed in production.
	function a:Publish(operation, record, routes, options)
		self:AdvanceRuntime()
		options = options or {}
		local data = self:CopyCommRecord(operation, record)
		if not data then
			return false
		end
		local sequence = self:NextCommunicationSequence()
		local context = {
			session = self:GetCommunicationSession(),
			messageId = tostring(sequence),
			sequence = sequence,
			stamp = self:GetAnnouncementServerTime(),
		}
		local frames = assert(self:BuildCommFrames(operation, data, context))
		local accepted = true
		for _, route in ipairs(routes or self:GetAnnouncementWireRoutes()) do
			for _, wire in ipairs(frames) do
				accepted = self.API.SendAddonMessage(self.commPrefix, wire, route.distribution, route.target) == 0
					and accepted
			end
		end
		if options.onComplete then
			options.onComplete(accepted, accepted and "accepted" or "rejected")
		end
		return true
	end
	a.Emit = a.Publish
	a:InitializeCommunications()
	return a
end

-- Surface masks are an explicit typed record permission. The public profile
-- uses the combined mask; this fixture exercises independent revocation fences.
local function SurfacePermissionFixture(name)
	local a = Fixture(name)
	a.surfaceShareMask = 3
	function a:GetPlayerLocationShareMask()
		return self.surfaceShareMask
	end
	function a:SetSurfaceShareMask(mask)
		self.surfaceShareMask = mask
		return self:BroadcastPlayerLocation(true)
	end
	return a
end

local function LatestLocation(a)
	for i = #a.sent, 1, -1 do
		if a.sent[i].frame.operation == "LOC" then
			return a.sent[i].data
		end
	end
end
local function Location(x)
	return {
		mask = 3,
		mapID = 12,
		x = x or 0.4,
		y = 0.6,
		classFile = "MAGE",
		className = "Mage",
		race = "Human",
		faction = "Alliance",
		level = 60,
		warMode = false,
	}
end
local function ObserveLocation(a, name, data, sequence)
	return a:ApplyCommunicationState(
		{ { topic = "LOC", data = data } },
		name,
		{ session = "1700000100000-1234", sequence = sequence or 1, stamp = a:GetAnnouncementServerTime() }
	)
end

QT:RegisterTest("location settings migrate every stored profile before applying defaults", function()
	local a, profiles, expected = Fixture(), {}, {}
	local values = { "missing", false, true }
	local function LegacyValue(value)
		if value ~= "missing" then
			return value
		end
	end
	for i, shareMap in ipairs(values) do
		for j, shareMinimap in ipairs(values) do
			for k, showMap in ipairs(values) do
				for l, showMinimap in ipairs(values) do
					local key = string.format("profile-%d-%d-%d-%d", i, j, k, l)
					profiles[key] = {
						shareLocationOnMap = LegacyValue(shareMap),
						shareLocationOnMinimap = LegacyValue(shareMinimap),
						showLocationsOnMap = LegacyValue(showMap),
						showLocationsOnMinimap = LegacyValue(showMinimap),
					}
					expected[key] = {
						share = shareMap ~= false and shareMinimap ~= false,
						show = not (showMap == false and showMinimap == false),
					}
				end
			end
		end
	end
	-- Old runtime getters accepted only true. Invalid stored values must never
	-- become new permission merely because they were not the boolean false.
	for i, invalid in ipairs({ 0, 1, "true", "false", {} }) do
		local key = "malformed-" .. tostring(i)
		profiles[key] = {
			shareLocationOnMap = invalid,
			shareLocationOnMinimap = true,
			showLocationsOnMap = false,
			showLocationsOnMinimap = invalid,
		}
		expected[key] = { share = false, show = false }
	end
	local db = { profiles = profiles, profileKeys = { [a.name] = "profile-2-3-2-2" } }
	a:InitializeDatabase(db)
	Equal(a:GetPlayerLocationShareMask(), 0)
	for key, profile in pairs(profiles) do
		Equal(profile.sharePlayerLocation, expected[key].share)
		Equal(profile.showPlayerLocations, expected[key].show)
		Equal(profile.onlyShowQuestPartners, false)
		Equal(profile.shareLocationOnMap, nil)
		Equal(profile.shareLocationOnMinimap, nil)
		Equal(profile.showLocationsOnMap, nil)
		Equal(profile.showLocationsOnMinimap, nil)
	end
	-- A second initialization must preserve the migrated privacy choice.
	a:InitializeDatabase(db)
	Equal(a:GetPlayerLocationShareMask(), 0)
end)

QT:RegisterTest("location migration preserves explicit new settings and imported profile privacy", function()
	local a = Fixture()
	local explicit = {
		sharePlayerLocation = true,
		showPlayerLocations = false,
		onlyShowQuestPartners = true,
		shareLocationOnMap = false,
		shareLocationOnMinimap = false,
		showLocationsOnMap = true,
		showLocationsOnMinimap = true,
	}
	local explicitOff = {
		sharePlayerLocation = false,
		showPlayerLocations = true,
		onlyShowQuestPartners = false,
		shareLocationOnMap = true,
		shareLocationOnMinimap = true,
		showLocationsOnMap = false,
		showLocationsOnMinimap = false,
	}
	a:InitializeDatabase({
		profiles = { explicit = explicit, explicitOff = explicitOff },
		profileKeys = { [a.name] = "explicit" },
	})
	Equal(a.db.profile, explicit)
	Equal(explicit.sharePlayerLocation, true)
	Equal(explicit.showPlayerLocations, false)
	Equal(explicit.onlyShowQuestPartners, true)
	Equal(explicit.shareLocationOnMap, nil)
	Equal(explicit.showLocationsOnMinimap, nil)
	Equal(explicitOff.sharePlayerLocation, false)
	Equal(explicitOff.showPlayerLocations, true)
	Equal(explicitOff.onlyShowQuestPartners, false)
	Equal(explicitOff.shareLocationOnMinimap, nil)
	local source = { shareLocationOnMap = false, showLocationsOnMap = false, showLocationsOnMinimap = false }
	local key, imported = a:EnsureProfile("Imported", source)
	Equal(key, "Imported")
	Equal(imported.sharePlayerLocation, false)
	Equal(imported.showPlayerLocations, false)
	Equal(imported.onlyShowQuestPartners, false)
	Equal(imported.shareLocationOnMap, nil)
	Equal(source.shareLocationOnMap, false) -- Migration owns its copy, not a caller's source.
	function a:ApplyActiveProfileState() end
	assert(a:CreateProfile("Copied", "Imported"))
	assert(a:SetActiveProfile("Copied"))
	Equal(a:GetPlayerLocationShareMask(), 0)
	assert(a:CopyProfileIntoActiveProfile("explicit"))
	Equal(a.db.profile.sharePlayerLocation, true)
	Equal(a.db.profile.showPlayerLocations, false)
	Equal(a.db.profile.onlyShowQuestPartners, true)
	assert(a:ResetActiveProfile())
	Equal(a:GetPlayerLocationShareMask(), 3)
	Equal(a.db.profile.showPlayerLocations, true)
	Equal(a.db.profile.onlyShowQuestPartners, false)
end)

QT:RegisterTest("location partner filter follows authenticated active status without deleting positions", function()
	local a, b = Fixture(), Fixture("Friend-Realm")
	a.other = b
	assert(a:BroadcastPlayerLocation())
	Equal(b:GetOption("onlyShowQuestPartners"), false)
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	local sends, reads, renders = #b.sent, b.reads, b.renders
	assert(b:SetOption("onlyShowQuestPartners", true))
	assert(b.renders > renders)
	Equal(#b.sent, sends)
	Equal(b.reads, reads)
	for _, surface in ipairs({ "map", "minimap" }) do
		Equal(#b:GetVisiblePlayerLocations(surface), 0)
	end
	assert(b.playerLocationState.peers[a.name])
	-- LOC/QTPR presence alone does not assert an active quest-partner status.
	assert(a:BroadcastQTPlayerPresence())
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	assert(a:SetOption("lookingForQuestPartners", true))
	for _, surface in ipairs({ "map", "minimap" }) do
		Equal(#b:GetVisiblePlayerLocations(surface), 1)
	end
	assert(a:SetOption("lookingForQuestPartners", false))
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	assert(b:SetOption("onlyShowQuestPartners", false))
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	assert(b:SetOption("onlyShowQuestPartners", true))
	assert(a:SetOption("lookingForQuestPartners", true))
	a.now, b.now = 164, 164
	assert(a:BroadcastPlayerLocation(true))
	Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
	b.now = 700 -- Typed public status uses the common ten-minute lifetime.
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	assert(b.playerLocationState.peers[a.name])
	a.now = 700
	assert(a:BroadcastQuestPartnerStatus(true))
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	b.ignored[a.name] = true
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("partner filtering and combined viewing retain explicit per-surface record permissions", function()
	local a, b = SurfacePermissionFixture(), Fixture("Friend-Realm")
	a.other = b
	assert(b:SetOption("onlyShowQuestPartners", true))
	assert(a:SetOption("lookingForQuestPartners", true))
	assert(a:SetSurfaceShareMask(1))
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
	assert(a:SetSurfaceShareMask(2))
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
	assert(b:SetOption("showPlayerLocations", false))
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
	assert(b:SetOption("showPlayerLocations", true))
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
	assert(a:SetOption("lookingForQuestPartners", false))
	Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
	assert(b:SetOption("onlyShowQuestPartners", false))
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
	Equal(#b:GetVisiblePlayerLocations("invalid"), 0)
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
		b.API.IsWarModeActive = function()
			return true
		end
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
			if capability == "regional" then
				Equal(peers[1].name, "Torres Sky")
			end
		end
	end
end)

QT:RegisterTest(
	"combined location sharing and viewing independently control both surfaces and withdraw old positions",
	function()
		local a, b = Fixture(), Fixture("Friend-Realm")
		a.other = b
		assert(a:BroadcastPlayerLocation())
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
		assert(b:SetOption("showPlayerLocations", false))
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
		Equal(#b.sent, 0)
		assert(b:SetOption("showPlayerLocations", true))
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
		assert(a:SetOption("sharePlayerLocation", false))
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
		Equal(LatestLocation(a).mask, 0)
		assert(not a:SetOption("sharePlayerLocation", "true"))
		Equal(a:GetPlayerLocationShareMask(), 0)
		assert(a:SetOption("sharePlayerLocation", true))
		Equal(#b:GetVisiblePlayerLocations("minimap"), 1)
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
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
	assert(a:BroadcastPlayerLocation())
	Equal(#a.sent, 4)
	a.now = 141
	assert(not a:BroadcastPlayerLocation())
	Equal(#a.sent, 4)
end)

QT:RegisterTest("failed location sends never deliver a point to the receiver", function()
	local a, b = Fixture(), Fixture("Friend-Realm")
	a.other, a.sendFails = b, true
	Equal(a:BroadcastPlayerLocation(), true)
	Equal(a:GetPlayerLocationState().lastSentAt, nil)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	a.now, b.now, a.sendFails = 110, 110, false
	assert(a:BroadcastPlayerLocation())
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
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
		a.db.profile.sharePlayerLocation = false
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
		a.db.profile.sharePlayerLocation = false
		a.sendFails = failed
		a:BroadcastPlayerLocation(true)
		for now = 105, 695, 5 do
			a.now, b.now = now, now
			a:BroadcastPlayerLocation()
		end
		Equal(#a.sent, 121) -- one point, one opt-out,119 bounded retries
		local attempts = #a.sent
		for now = 700, 755, 5 do
			a.now, b.now = now, now
			Equal(a:BroadcastPlayerLocation(), false)
		end
		Equal(#a.sent, attempts)
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		-- Resuming sharing publishes only a fresh position, and a new opt-out
		-- has its own expiry window rather than inheriting the exhausted one.
		a.sendFails, a.db.profile.sharePlayerLocation, a.position.x = false, true, 0.7
		assert(a:BroadcastPlayerLocation(true))
		Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.7)
		a.db.profile.sharePlayerLocation = false
		assert(a:BroadcastPlayerLocation(true))
		a.now = 760
		assert(a:BroadcastPlayerLocation())
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
	end
end)

QT:RegisterTest("single-surface location opt-out retries every route before the stationary heartbeat", function()
	for _, surface in ipairs({ "map", "minimap" }) do
		for _, failures in ipairs({ { PARTY = true }, { CHANNEL = true }, { PARTY = true, CHANNEL = true } }) do
			local a, party, channel = SurfacePermissionFixture(), Fixture("Party-Realm"), Fixture("Channel-Realm")
			a.inParty, a.peersByRoute = true, { PARTY = party, CHANNEL = channel }
			assert(a:BroadcastPlayerLocation())
			a.failedRoutes = failures
			Equal(a:SetSurfaceShareMask(surface == "map" and 2 or 1), true)
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

-- Full location-capacity and publication-retry matrices run offline.
QT:RegisterTest("location permission retry expiry belongs to each surface and resets for fresh sharing", function()
	local a, b = SurfacePermissionFixture(), Fixture("Friend-Realm")
	a.other = b
	assert(a:BroadcastPlayerLocation())
	assert(a:SetSurfaceShareMask(1))
	for now = 105, 695, 5 do
		a.now, b.now = now, now
		assert(a:BroadcastPlayerLocation())
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
	end
	-- Updating the retained map surface must not extend the minimap revocation.
	local attempts = #a.sent
	for now = 700, 710, 5 do
		a.now, b.now = now, now
		Equal(a:BroadcastPlayerLocation(), false)
	end
	Equal(#a.sent, attempts)
	a.now, b.now = 715, 715
	assert(a:BroadcastPlayerLocation(), "the remaining surface resumes its ordinary heartbeat")
	assert(a:SetSurfaceShareMask(0))
	local reads = a.reads
	for now = 720, 1310, 5 do
		a.now, b.now = now, now
		assert(a:BroadcastPlayerLocation(), "the newly revoked map has its own expiry")
	end
	Equal(a.reads, reads)
	a.now = 1315
	Equal(a:BroadcastPlayerLocation(), false)
	a.now, b.now, a.position.x = 1320, 1320, 0.7
	assert(a:SetSurfaceShareMask(2))
	Equal(b:GetVisiblePlayerLocations("minimap")[1].x, 0.7)
	assert(a:SetSurfaceShareMask(0))
	a.now = 1325
	assert(a:BroadcastPlayerLocation(), "fresh sharing starts a new bounded revocation lifetime")
	a:ResetPlayerLocations()
	a.now = 1330
	Equal(a:BroadcastPlayerLocation(), false, "reset must not retain old publication history")
end, { offline = true })

QT:RegisterTest("location restrictions and unreadable positions retain the last point without renewing it", function()
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
	for now = 125, 715, 5 do
		a.now, b.now = now, now
		Equal(a:BroadcastPlayerLocation(), false)
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
	end
	Equal(#a.sent, 2)
	b.now = 720
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("location runtime ticks tolerate lost heartbeats and publish only fresh recovery data", function()
	local a, b = Fixture(), Fixture("Friend-Realm")
	a.other = b
	-- Presence has its own protocol tests; these owned runtime callbacks
	-- exercise location sampling, real transport, pruning and recovery.
	function a:UpdateQTPlayerPresence() end
	function b:UpdateQTPlayerPresence() end
	b.db.profile.sharePlayerLocation = false
	assert(a:InitializePlayerLocations())
	assert(b:InitializePlayerLocations())
	assert(a:InitializeRuntimeCoordinator())
	assert(b:InitializeRuntimeCoordinator())
	local function Tick(now)
		a.now, b.now = now, now
		a.runtimeCoordinatorFrame.scripts.OnUpdate(a.runtimeCoordinatorFrame, 0.2)
		b.runtimeCoordinatorFrame.scripts.OnUpdate(b.runtimeCoordinatorFrame, 0.2)
	end
	Tick(100)
	a.sendFails = true
	for now = 105, 175, 5 do
		Tick(now)
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
		Equal(b:GetVisiblePlayerLocations("map")[1].receivedAt, 100)
	end
	Equal(#a.sent, 8, "failed attempts do not advance accepted fingerprints and retry every ten seconds")
	a.sendFails, a.position = false, { x = 0.7, y = 0.8 }
	Tick(180)
	Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.7)
	Equal(b:GetVisiblePlayerLocations("map")[1].receivedAt, 180)
	a.restricted = true
	local reads, sends = a.reads, #a.sent
	for now = 185, 775, 5 do
		Tick(now)
		Equal(#b:GetVisiblePlayerLocations("map"), 1)
	end
	Equal(a.reads, reads)
	Equal(#a.sent, sends)
	Tick(780)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("location privacy changes withdraw immediately while fresh position is unavailable", function()
	for _, action in ipairs({ "legacy-map", "legacy-minimap", "both", "disable" }) do
		local legacy = action == "legacy-map" or action == "legacy-minimap"
		local a, b = legacy and SurfacePermissionFixture() or Fixture(), Fixture("Friend-Realm")
		a.other = b
		assert(a:BroadcastPlayerLocation())
		a.restricted, a.now, b.now = true, 101, 101
		if action == "disable" then
			assert(a:BroadcastPlayerLocation(true, true))
		elseif legacy then
			assert(a:SetSurfaceShareMask(action == "legacy-map" and 2 or 1))
		else
			assert(a:SetOption("sharePlayerLocation", false))
		end
		Equal(#b:GetVisiblePlayerLocations("map"), 0)
		Equal(#b:GetVisiblePlayerLocations("minimap"), 0)
		Equal(LatestLocation(a).mask, 0)
		Equal(a.reads, 1)
	end
end)

QT:RegisterTest("partial location privacy withdrawal retries failed routes during a position outage", function()
	local a, party, channel = SurfacePermissionFixture(), Fixture("Party-Realm"), Fixture("Channel-Realm")
	a.inParty, a.peersByRoute = true, { PARTY = party, CHANNEL = channel }
	assert(a:BroadcastPlayerLocation())
	a.restricted, a.now, a.failedRoutes = true, 101, { PARTY = true }
	assert(a:SetSurfaceShareMask(2))
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
	b.now = 700
	Equal(#b:GetVisiblePlayerLocations("map"), 1)
	b.now = 701
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
end)

QT:RegisterTest("location transport ignores unsupported routes and uses authoritative Forever identity", function()
	local a, b = Fixture("Anakin Othername"), Fixture("Luke Bucket")
	a.forever, b.forever = true, true
	assert(a:BroadcastPlayerLocation())
	local wire = a.sent[1].message
	b:OnCommReceived(a.commPrefix, wire, "SAY", a.name)
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

-- Full location-capacity and publication-retry matrices run offline.
QT:RegisterTest("location records and malformed wire input are bounded", function()
	local a = Fixture()
	for _, record in ipairs({
		{},
		{ mask = 7 },
		{ mask = 3, mapID = 12, x = math.huge, y = 0.6 },
		{ mask = 3, mapID = 12, x = -0.1, y = 0.6 },
		{ mask = 3, mapID = 12, x = 0.4 },
	}) do
		Equal(a:ValidatePlayerLocationRecord(record), nil)
	end
	for _, wire in ipairs({ "", "LOC|1,100-1234,1,0", string.rep("x", 256) }) do
		Equal(a:ReceiveCommunication(a.commPrefix, wire, "CHANNEL", "Bad-Realm", 7, "QuestTogether"), false)
	end
	for i = 1, 540 do
		a.now = 100 + i / 100
		assert(ObserveLocation(a, "Peer" .. i .. "-Realm", Location()))
	end
	Equal(#a:GetVisiblePlayerLocations("map"), 512)
end, { offline = true })

-- Full location-capacity and publication-retry matrices run offline.
QT:RegisterTest("location channel retains fresh positions from two hundred fifty active peers", function()
	local a = Fixture()
	local function Send(sequence)
		local frames = assert(a:BuildCommFrames("LOC", Location(), {
			session = "1700000100000-1234",
			messageId = tostring(sequence),
			sequence = sequence,
			stamp = a:GetAnnouncementServerTime(),
		}))
		for i = 1, 250 do
			if (i - 1) % 32 == 0 then
				-- Deliver the population over successive frames, with room for
				-- other client traffic under the real per-frame ingress cap.
				a:AdvanceRuntime(a.now + 1 / 60)
			end
			for _, wire in ipairs(frames) do
				assert(
					a:ReceiveCommunication(a.commPrefix, wire, "CHANNEL", "Peer" .. i .. "-Realm", 7, "QuestTogether")
				)
			end
		end
	end
	Send(1)
	Equal(#a:GetVisiblePlayerLocations("map"), 250)
	assert(a.playerLocationState.peers["Peer1-Realm"])
	a.now = 120
	Send(2)
	Equal(#a:GetVisiblePlayerLocations("minimap"), 250)
	Equal(a.playerLocationState.peers["Peer1-Realm"].sequence, 2)
end, { offline = true })

QT:RegisterTest("location runtime replacement cancels old update callbacks and clears owned pins", function()
	local a = Fixture()
	function a:UpdateQTPlayerPresence() end
	function a:UpdateGeographicComms() end
	function a:UpdateNearbyStreams() end
	function a:UpdatePlayerDetails() end
	assert(a:InitializePlayerLocations())
	assert(a:InitializeRuntimeCoordinator())
	local frame, state = a.runtimeCoordinatorFrame, a.playerLocationState
	local callback = frame.scripts.OnUpdate
	callback(frame, 0.2)
	Equal(#a.sent, 1)
	Equal(a.sent[1].frame.operation, "LOC")
	a:ResetRuntimeCoordinator()
	a:ResetPlayerLocations()
	Equal(rawget(a, "playerLocationState"), nil)
	Equal(frame.scripts.OnUpdate, nil)
	assert(a.hidden)
	assert(a:InitializePlayerLocations())
	assert(a:InitializeRuntimeCoordinator())
	assert(a.playerLocationState ~= state)
	a.now = 110
	callback(frame, 1)
	Equal(#a.sent, 1)
	frame.scripts.OnUpdate(frame, 0.2)
	Equal(#a.sent, 2)
end)

QT:RegisterTest("disabling combined location sharing also removes coordinates from quest and ping messages", function()
	local unexpectedCalls = 0
	local a = Fixture()
	a.db.profile.sharePlayerLocation = false
	function a:GetPlayerAnnouncementLocationInfo()
		unexpectedCalls = unexpectedCalls + 1
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
	local sent = a.sent[1].data
	Equal(sent.coordX, "")
	Equal(sent.coordY, "")
	Equal(sent.zoneName, "")
	assert(sent.mapID == nil or sent.mapID == "")
	Equal(unexpectedCalls, 0)
end)

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
		local data = a.sent[1].data
		Equal(data.mask, 3)
		Equal(data.classFile, "")
		assert(not data.className:find("|", 1, true))
		Equal(data.race, "")
		Equal(data.faction, "")
		Equal(data.level, nil)
		Equal(data.warMode, nil)
	end
)

-- Full location-capacity and publication-retry matrices run offline.
QT:RegisterTest("full location cache retains nearby peers over fresh distant arrivals", function()
	local a = Fixture()
	a.GetPlayerLocationPriorityOrigin = function()
		return {}
	end
	a.GetPlayerLocationPriorityDistance = function(_, row)
		return row.mask == 0 and math.huge or row.x
	end
	local function Payload(x, sequence)
		return Location(tonumber(x))
	end
	for i = 1, 512 do
		assert(ObserveLocation(a, "Near" .. i .. "-Realm", Payload("0.1")))
	end
	a.now = 101
	assert(ObserveLocation(a, "Far-Realm", Payload("0.9")))
	assert(not a.playerLocationState.peers["Far-Realm"])
	Equal(#a:GetVisiblePlayerLocations("map"), 512)
	assert(ObserveLocation(a, "Closest-Realm", Payload("0.01")))
	assert(a.playerLocationState.peers["Closest-Realm"])
	Equal(#a:GetVisiblePlayerLocations("map"), 512)
	-- Existing peers still accept a move, then become eligible for eviction.
	assert(ObserveLocation(a, "Closest-Realm", Payload("0.95"), 2))
	assert(ObserveLocation(a, "NewNear-Realm", Payload("0.02")))
	assert(not a.playerLocationState.peers["Closest-Realm"])
	assert(a.playerLocationState.peers["NewNear-Realm"])
end, { offline = true })

QT:RegisterTest("split map viewing preferences migrate once without changing sharing", function()
	for _, pair in ipairs({ { false, false }, { false, true }, { true, false }, { true, true } }) do
		local profile = { showWorldMapPlayers = pair[1], showMinimapPlayers = pair[2], sharePlayerLocation = false }
		QT:MigratePlayerLocationOptions(profile)
		Equal(profile.showPlayerLocations, pair[1] or pair[2])
		Equal(profile.sharePlayerLocation, false)
		Equal(profile.showWorldMapPlayers, nil)
		Equal(profile.showMinimapPlayers, nil)
		profile.showPlayerLocations = false
		QT:MigratePlayerLocationOptions(profile)
		Equal(profile.showPlayerLocations, false)
	end
	local profile = { showPlayerLocations = false, showWorldMapPlayers = true, sharePlayerLocation = true }
	QT:MigratePlayerLocationOptions(profile)
	Equal(profile.showPlayerLocations, true)
	Equal(profile.sharePlayerLocation, true)
end)

QT:RegisterTest("display preferences do not withdraw streams shared with other players", function()
	local a = Fixture()
	local subscribers = { ["Friend-Realm"] = { at = 100 } }
	a.nearbyStreamState = { subscribers = subscribers, wanted = {}, nextCapability = 130 }
	a:OnPlayerLocationOptionsChanged("showPlayerLocations")
	Equal(a.nearbyStreamState.subscribers, subscribers)
	Equal(a.nearbyStreamState.nextCapability, 130)
end)

QT:RegisterTest("v2 pong imports require explicit sharing and preserve public field permissions", function()
	local a, name = Fixture(), "Friend-Realm"
	local initial = Location()
	initial.mask = 1
	assert(ObserveLocation(a, name, initial))
	a.now = 101
	local function Import(response)
		local observation = a:CreatePeerObservation(name, "LOC", { source = "pong", age = 0, lifetime = 600 })
		observation.manual = true
		return a:RefreshPlayerLocationFromPing(name, response, observation)
	end
	local response = { mapID = "12", coordX = "70", coordY = "80" }
	Equal(Import(response), false)
	Equal(a.playerLocationState.peers[name].x, 0.4)
	response.locationShared = true
	assert(Import(response))
	local row = a.playerLocationState.peers[name]
	Equal(row.x, 0.7)
	Equal(row.mask, 1)
	Equal(row.classFile, "MAGE")
	Equal(row.faction, "Alliance")
	a.now = 102
	response.locationShared = false
	assert(Import(response))
	Equal(a.playerLocationState.peers[name].mask, 0)
	Equal(a.playerLocationState.peers[name].x, nil)
	response.locationShared = true
	Equal(Import(response), false)
	Equal(a.playerLocationState.peers[name].mask, 0)
	a.now = 103
	response.coordY = nil
	Equal(Import(response), false)
	Equal(a.playerLocationState.peers[name].mask, 0)
end)
