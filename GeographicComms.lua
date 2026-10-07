-- Addon-owned subscriptions, bounded outbound scheduling, and compact presence.
-- No server phase identifiers: regional names depend only on the zone map ID.
local QT = _G.QuestTogether
local STATE_COMMANDS = { LOC = true, QTPR = true, QTVR = true, QTLF = true, QTLQ = true, QJST = true, QTPG = true, QTCI = true, QTHI = true }
local ORDER = { "QTPR", "QTVR", "QJST", "QTLF", "QTLQ", "LOC", "QTPG", "QTCI", "QTHI" }
local HANDLERS = {
	LOC = "HandlePlayerLocationMessage",
	QTPR = "HandleQTPlayerPresenceMessage",
	QTVR = "HandleAddonVersionMessage",
	QTLF = "HandleQuestPartnerStatusMessage",
	QTLQ = "HandleQuestPartnerQuestMessage",
	QJST = "HandlePartyJoinMetadata",
	QTPG = "HandlePartyVisualMetadata",
	QTCI = "HandlePlayerCapabilityMetadata",
	QTHI = "HandlePlayerDetailsIdentity",
}
local SNAPSHOT_LIFETIME = 600
local function Now(a)
	return a:SafeToNumber(a.API.GetTime and a.API.GetTime()) or 0
end
local function Channel(name)
	return { distribution = "CHANNEL", requiresChannelJoin = true, channelName = name }
end
local function Random(a, low, high)
	local n = a:SafeToNumber(a.API.Random and a.API.Random(low, high)) or low
	return math.max(low, math.min(high, n))
end

function QT:InitializeGeographicComms()
	if rawget(self, "geographicCommsState") then
		return
	end
	self.geographicCommsState = {
		subscriptions = {},
		latest = {},
		locationFingerprints = {},
		queue = {},
		peers = {},
		peerCount = 0,
		startedAt = Now(self),
		tokens = 4,
		tokenAt = Now(self),
		sequence = 0,
		session = string.format("%d-%d", math.floor(Now(self) * 1000), Random(self, 1000, 999999)),
		nextGlobal = Now(self) + Random(self, 2, 12),
		nextLocal = Now(self) + Random(self, 1, 10),
	}
	self.geographicCommsState.nextLocalMetadata = self.geographicCommsState.nextLocal
end

function QT:GetGeographicZoneID(mapID)
	local visited = {}
	for _ = 1, 12 do
		mapID = self:SafeToNumber(mapID)
		if not mapID or mapID < 1 or mapID > 1000000 or mapID ~= math.floor(mapID) or visited[mapID] then
			return nil
		end
		visited[mapID] = true
		local ok, info = pcall(self.API.GetMapInfo, mapID)
		if not ok or not self:CanAccessTable(info) then
			return nil
		end
		local kind = self:SafeToNumber(info.mapType)
		if kind == 3 then
			return mapID
		end -- Enum.UIMapType.Zone, including cities.
		if not kind or kind < 3 then
			return nil
		end -- Never subscribe to a whole continent.
		mapID = info.parentMapID
	end
end

function QT:IsGeographicChannelName(value)
	if not self:CanAccessValue(value) or type(value) ~= "string" then
		return false
	end
	local base = value:match("^%d+%.%s+(.+)$") or value
	local state = rawget(self, "geographicCommsState")
	if state then
		base = string.lower(base)
		for name in pairs(state.subscriptions) do
			if string.lower(name) == base then
				return true
			end
		end
	end
	return false
end

function QT:IsGeographicChannelEvent(channel, id, name)
	if channel ~= "CHANNEL" then
		return false
	end
	if self:CanAccessValue(name) and type(name) == "string" and name ~= "" then
		return self:IsGeographicChannelName(name)
	end
	id = self:SafeToNumber(id)
	if not id or id <= 0 then
		return false
	end
	local state = rawget(self, "geographicCommsState")
	for channelName in pairs(state and state.subscriptions or {}) do
		if self:GetAnnouncementChannelLocalID(channelName) == id then
			return true
		end
	end
	return false
end

function QT:UpdateGeographicSubscriptions()
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if
		not s
		or not self.isEnabled
		or self.isLoggingOut
		or self:IsRuntimeRestricted()
		or self:IsRuntimeRestrictionTypeActive("chat")
	then
		return
	end
	if s.checkedAt and now >= s.checkedAt and now - s.checkedAt < 2 then
		return
	end
	s.checkedAt = now
	local ok, mapID = pcall(self.API.GetBestMapForUnit, "player")
	local current = ok and self:GetGeographicZoneID(mapID) or nil
	local viewed = self.GetViewedQuestTogetherMapID and self:GetViewedQuestTogetherMapID()
	viewed = viewed and self:GetGeographicZoneID(viewed) or nil
	if viewed ~= s.viewCandidate then
		s.viewCandidate, s.viewSince = viewed, now
	end
	if now - (s.viewSince or now) >= 4 then
		s.viewZone = viewed
	end
	-- Keep the last viewed zone briefly on close; at most two regional channels.
	local desired = {}
	if current then
		desired["QuestTogetherZ" .. current] = true
	end
	if s.viewZone and s.viewZone ~= current then
		desired["QuestTogetherZ" .. s.viewZone] = true
	end
	-- Permanent channels can outlive the addon state on reload. Reconcile only
	-- our exact numeric zone names; never leave unrelated player channels.
	if not s.reconciledChannels and self.API.GetChatChannelList then
		local listed, channels = pcall(self.API.GetChatChannelList)
		if listed and self:CanAccessTable(channels) and #channels <= 90 and #channels % 3 == 0 then
			s.reconciledChannels = true
			for index = 2, #channels, 3 do
				local name = self:SafeToString(channels[index], "")
				local zone = tonumber(name:lower():match("^questtogetherz([1-9]%d*)$"))
				if zone and zone <= 1000000 and not desired["QuestTogetherZ" .. zone] and not s.subscriptions["QuestTogetherZ" .. zone] and self.API.LeaveChannelByName then
					local left, result = pcall(self.API.LeaveChannelByName, name)
					if not left or result == false then s.reconciledChannels = false end
				end
			end
		end
	end
	for name in pairs(s.subscriptions) do
		if not desired[name] then
			if self.API.LeaveChannelByName then
				pcall(self.API.LeaveChannelByName, name)
			end
			s.subscriptions[name] = nil
			s.locationFingerprints[name] = nil
			if self.announcementChannelBindings then self.announcementChannelBindings[name] = nil end
		end
	end
	for name in pairs(desired) do
		s.subscriptions[name] = true
		if not self:GetAnnouncementChannelLocalID(name) and self:EnsureAnnouncementChannelJoined(name) then
			self:ScheduleAnnouncementChannelOrder()
		end
	end
	s.currentZone = current
	local channel = current and ("QuestTogetherZ" .. current) or nil
	if channel ~= s.currentChannel then
		s.currentChannel, s.nextLocal = channel, now + Random(self, 1, 10)
		s.nextLocalMetadata = s.nextLocal
		s.discoveryRequestAt = channel and (now + Random(self, 2, 5)) or nil
	end
end

-- A startup/zone-entry nudge, not another heartbeat. All arrivals benefit from
-- one shared regional response; never solicit the global or viewed-zone audience.
function QT:UpdateGeographicDiscovery()
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s or not self.isEnabled or self.isLoggingOut or self:IsRuntimeRestricted()
		or self:IsRuntimeRestrictionTypeActive("chat") or not s.discoveryRequestAt
		or self:GetOption("showPlayerLocations") ~= true
		or now < s.discoveryRequestAt or not s.currentChannel
		or not self:GetAnnouncementChannelLocalID(s.currentChannel) then return end
	if s.lastDiscoveryRequestAt and now - s.lastDiscoveryRequestAt < 60 then return end
	if self:QueueGeographicWire("QTDQ|1," .. s.currentZone, "zone discovery", Channel(s.currentChannel), true, "zone-discovery") then
		s.discoveryRequestAt, s.lastDiscoveryRequestAt = nil, now
	end
end

function QT:HandleGeographicDiscovery(payload, sender, channel, id, name)
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s or not self.isEnabled or self.isLoggingOut or self:IsRuntimeRestricted()
		or self:IsRuntimeRestrictionTypeActive("chat") or self:SafeToString(channel, "") ~= "CHANNEL" then return false end
	local zone = self:CanAccessValue(payload) and type(payload) == "string" and tonumber(payload:match("^1,([1-9]%d*)$"))
	if not zone or zone ~= s.currentZone or not s.currentChannel then return false end
	-- Check the actual channel, not merely the zone claimed in the payload.
	local actual = self:SafeToString(name, ""):gsub("^%d+%.%s+", ""):lower()
	if actual ~= "" then
		if actual ~= s.currentChannel:lower() then return false end
	else
		local expected = self:GetAnnouncementChannelLocalID(s.currentChannel)
		if not expected or self:SafeToNumber(id) ~= expected then return false end
	end
	local peer = self:NormalizeMemberName(sender)
	if not peer or self:IsSelfSender(peer) or self:IsIgnoredPlayerName(peer) then return false end
	self:RecordQTPlayerPresence(peer, true)
	-- A neighbor already asked for the same shared snapshots. Coalesce our own
	-- pending query as well as repeated requests from different newcomers.
	s.discoveryRequestAt = nil
	for i = #s.queue, 1, -1 do
		if s.queue[i].key == "zone-discovery" then table.remove(s.queue, i) end
	end
	if s.lastDiscoveryResponseAt and now - s.lastDiscoveryResponseAt < 60 then return true end
	s.lastDiscoveryResponseAt = now
	if not self:CanPublishPlayerLocation() then return true end
	local count = 0
	for _, record in pairs(s.peers) do
		if record.zone == zone and now >= record.at and now - record.at < SNAPSHOT_LIFETIME then count = count + 1 end
	end
	-- Around 32 responders per request in a known crowded zone, not thousands.
	-- This is a probabilistic traffic budget; normal heartbeats fill the remainder.
	if count > 32 and Random(self, 1, count) > 32 then return true end
	s.nextLocalMetadata = math.min(s.nextLocalMetadata or s.nextLocal, now + Random(self, 2, 20))
	return true
end

function QT:GetGeographicAnnouncementRoutes()
	local s = rawget(self, "geographicCommsState")
	if not s then
		return nil
	end
	local routes, group = {}, self:GetGroupAnnouncementDistribution()
	if group then
		routes[#routes + 1] = { distribution = group }
	end
	-- Current zone only, never the remote zone the map happens to display.
	local name = s.currentChannel
	if not name or not self:GetAnnouncementChannelLocalID(name) then
		name = self.announcementChannelName
	end
	routes[#routes + 1] = Channel(name)
	return routes
end

-- Staging acknowledges bounded addon-owned storage, not native delivery.
-- Every state has just one slot; a withdrawal replaces the old publication.
function QT:StageGeographicState(wire)
	local s = rawget(self, "geographicCommsState")
	local command, payload = self:DeserializeWireMessage(wire)
	if not s or not STATE_COMMANDS[command] then
		return nil
	end
	local now, old = Now(self), s.latest[command]
	-- Retain extended tooltip metadata when alternating legacy QTVR forms.
	if command == "QTVR" and payload:sub(1, 2) == "1," and old and old.wire:sub(6, 7) == "2," then
		return true
	end
	s.latest[command] = { wire = wire, at = now }
	local changedStatus = (old ~= nil or now - s.startedAt > 12)
		and command == "QTLF"
		and (not old or old.wire:match(",([01])$") ~= wire:match(",([01])$"))
	local changedParty = command == "QTPG" and (not old or old.wire ~= wire)
	local withdrawal = command == "LOC" and payload:match("^1,[^,]+,%d+,0$")
	local changedLocationConsent = withdrawal and (not old or not old.wire:match("^LOC|1,[^,]+,%d+,0$"))
	if changedLocationConsent or changedStatus or changedParty or (command == "QTPR" and payload == "1,0") then
		s.nextGlobal = math.min(s.nextGlobal, math.max(now + 1, (s.lastGlobal or 0) + 10))
		s.nextLocal = math.min(s.nextLocal, now + 1)
		s.nextLocalMetadata = math.min(s.nextLocalMetadata or 0, now + 1)
		-- Discard already packed positions/status; never let them follow a clear.
		for i = #s.queue, 1, -1 do
			if s.queue[i].snapshot or (withdrawal and s.queue[i].publishesLocation) then
				table.remove(s.queue, i)
			end
		end
	end
	return true
end

-- Length-prefixed inner messages retain the existing strict decoders. The
-- envelope permits only presence data, never recursively nested/control messages.
function QT:BuildGeographicSnapshots(locationOnly, entries)
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s then
		return {}
	end
	local stamp = self:GetAnnouncementServerTime() or 0
	s.sequence = s.sequence + 1
	local header = "QTB1|1," .. stamp .. "," .. s.session .. "," .. s.sequence .. ";"
	local packets, packet = {}, header
	local latest = entries or s.latest
	local version = latest.QTVR
	local versionText = version and (version.wire:match("^QTVR|1,(.+)$") or version.wire:match("^QTVR|2,([^,]+),%d*,%d*$"))
	local hasVersionPresence = version and now >= version.at and now - version.at <= 180
		and self:ParseAddonVersion(versionText)
	for _, command in ipairs(ORDER) do
		local entry = latest[command]
		local maxAge = command == "LOC" and 35 or (command == "QTVR" and 180 or 90)
		local isLocationUpdate = command == "LOC" and entry and not entry.wire:match("^LOC|1,[^,]+,%d+,0$")
		local redundantPresence = command == "QTPR" and entry and entry.wire == "QTPR|1,1" and hasVersionPresence
		if entry and not redundantPresence and (not locationOnly or isLocationUpdate) and now >= entry.at and now - entry.at <= maxAge then
			local wire = entry.wire
			-- Optional localized labels never displace position/status. Receivers
			-- resolve quest titles locally when the title cannot fit the envelope.
			if #wire > 160 and command == "QTLQ" then
				wire = wire:match("^(QTLQ|1,[^,]+,%d+,%d+,)") or wire
			end
			if #wire > 160 and command == "LOC" then
				local fields = {}
				for field in (wire .. ","):gmatch("(.-),") do
					fields[#fields + 1] = field
				end
				fields[9], fields[10] = "", ""
				wire = table.concat(fields, ",")
			end
			local part = math.floor(now - entry.at) .. "," .. #wire .. ":" .. wire
			if #header + #part <= 255 then
				-- Older receivers reject unknown inner commands. Isolate new metadata
				-- so their established location/presence packets remain readable.
				if #packet + #part > 255 or ((command == "QTPG" or command == "QTCI") and packet ~= header) then
					packets[#packets + 1], packet = packet, header
				end
				packet = packet .. part
			end
		end
	end
	if packet ~= header then
		packets[#packets + 1] = packet
	end
	return packets
end

function QT:HandleGeographicSnapshot(payload, sender)
	if not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 250 then
		return false
	end
	local stamp, session, sequence, rest = payload:match("^1,(%d+),(%d+%-%d+),(%d+);(.*)$")
	sequence = self:SafeToNumber(sequence)
	if not session or #session > 40 or not sequence or sequence < 1 or sequence > 2147483647 then
		return false
	end
	stamp = self:SafeToNumber(stamp)
	if not stamp or (stamp ~= 0 and (stamp < 1000000000 or stamp >= 100000000000)) then
		return false
	end
	local serverNow = self:GetAnnouncementServerTime()
	local transit = stamp ~= 0 and serverNow and serverNow - stamp or 0
	if transit < -5 or transit >= SNAPSHOT_LIFETIME then
		return false
	end
	transit = math.max(0, transit)
	local entries, seen = {}, {}
	while rest ~= "" do
		local age, length, start = rest:match("^(%d+),(%d+):()")
		age, length = tonumber(age), tonumber(length)
		if not age or age > 180 or not length or length < 6 or length > #rest - (start or 1) + 1 then
			return false
		end
		local wire = rest:sub(start, start + length - 1)
		local command, data = self:DeserializeWireMessage(wire)
		if not STATE_COMMANDS[command] or seen[command] then
			return false
		end
		seen[command] = true
		entries[#entries + 1] = { command = command, data = data, age = age + transit }
		rest = rest:sub(start + length)
	end
	if #entries == 0 then
		return false
	end
	local now = Now(self)
	local s = rawget(self, "geographicCommsState")
	if not s then
		return false
	end
	local name = self:NormalizeMemberName(sender)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	sender = name
	local peer = s.peers[sender]
	if peer and now >= peer.at and now - peer.at < SNAPSHOT_LIFETIME then
		for _, retired in ipairs(peer.retired) do
			if retired == session then
				return false
			end
		end
		if peer.session ~= session then
			peer.retired[#peer.retired + 1] = peer.session
			if #peer.retired > 4 then
				table.remove(peer.retired, 1)
			end
			peer.session, peer.commands = session, {}
		end
	else
		if not peer then s.peerCount = (s.peerCount or 0) + 1 end
		peer = { session = session, commands = {}, retired = {}, at = now }
		s.peers[sender] = peer
	end
	for _, entry in ipairs(entries) do
		local newer = sequence > (peer.commands[entry.command] or 0)
		if newer then
			peer.commands[entry.command] = sequence
		end
		if newer and entry.age < SNAPSHOT_LIFETIME and self[HANDLERS[entry.command]](self, entry.data, sender) then
			local name = self:NormalizeMemberName(sender)
			local locations, presence, joins =
				rawget(self, "playerLocationState"),
				rawget(self, "qtPlayerPresenceState"),
				rawget(self, "partyJoinState")
			local records = {
				LOC = locations and locations.peers,
				QTLF = presence and presence.questPartners,
				QTLQ = presence and presence.partnerQuests,
				QTVR = presence and presence.peerTooltipStats,
				QJST = joins and joins.peers,
				QTPG = rawget(self, "partyVisualState") and self.partyVisualState.peers,
				QTCI = rawget(self, "nearbyStreamState") and self.nearbyStreamState.capabilities,
				QTHI = rawget(self, "playerDetailsState") and self.playerDetailsState.identities,
			}
			local record = records[entry.command] and records[entry.command][name]
			if entry.command == "LOC" then
				local position = record or self:DecodePlayerLocationPayload(entry.data)
				if position then
					if position.mask == 0 then
						peer.zone, peer.mapID = nil, nil
					elseif position.mapID ~= peer.mapID then
						peer.zone, peer.mapID = self:GetGeographicZoneID(position.mapID), position.mapID
					end
				end
			end
			if entry.command == "QTCI" and record then
				self:RememberDirectCommPeer(name, record.direct, SNAPSHOT_LIFETIME - entry.age)
			end
			if record then
				record.lifetime = SNAPSHOT_LIFETIME - entry.age
				record.sampledAt = now - entry.age
			end
		end
	end
	local s = rawget(self, "geographicCommsState")
	if s then
		local peer = s.peers[sender]
		if peer then
			peer.at = now
		end
		-- Expiry is coarse (minutes), so scanning every peer for every packet
		-- adds quadratic work during a busy-zone burst without improving freshness.
		if not s.prunedAt or now < s.prunedAt or now - s.prunedAt >= 1 then
			s.prunedAt, s.peerCount = now, 0
			for name, record in pairs(s.peers) do
				local at = record.at
				if now < at or now - at >= SNAPSHOT_LIFETIME then
					s.peers[name] = nil
				else
					s.peerCount = s.peerCount + 1
				end
			end
		end
		if s.peerCount > 2048 then
			local oldest, at
			for name, record in pairs(s.peers) do
				if not at or record.at < at then
					oldest, at = name, record.at
				end
			end
			s.peers[oldest] = nil
			s.peerCount = s.peerCount - 1
		end
	end
	return true
end

function QT:TakeCommsSendToken(background)
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s then
		return true
	end
	if now < s.tokenAt then
		s.tokens = 0
	end
	s.tokens = math.min(4, s.tokens + math.max(0, now - s.tokenAt) * 2)
	s.tokenAt = now
	if s.blockedUntil and now < s.blockedUntil then
		return false
	end
	if s.tokens < (background and 2 or 1) then
		return false
	end
	s.tokens = s.tokens - 1
	return true
end

-- Privacy cleanup follows packet content, not the preference at enqueue time.
-- Interactive comparison/roster controls never carry a position and must survive
-- an unrelated location opt-out. Fail closed for malformed location-bearing wire.
local function PublishesLocation(addon, wire)
	local command, payload = addon:DeserializeWireMessage(wire)
	local data
	if command == "ANN" or command == "LVL" then
		data = addon:DecodeAnnouncementPayload(payload)
	elseif command == "PONG" then
		data = addon:DecodePingResponsePayload(payload)
	elseif command == "LOC" then
		data = addon:DecodePlayerLocationPayload(payload)
		return not data or data.mask ~= 0
	elseif command == "QTB1" then
		return true -- Packed snapshots are replaced atomically on consent changes.
	else
		return false
	end
	if not data then return true end
	for _, key in ipairs({ "mapID", "zoneName", "coordX", "coordY" }) do
		if data[key] ~= nil and data[key] ~= "" then return true end
	end
	return false
end

function QT:QueueGeographicWire(wire, context, route, snapshot, key)
	local s = rawget(self, "geographicCommsState")
	if not s or not self.isEnabled then
		return false
	end
	if key then
		for i = #s.queue, 1, -1 do
			if s.queue[i].key == key then
				table.remove(s.queue, i)
			end
		end
	end
	if #s.queue >= 96 then
		self:RecordCommsDiagnostic("queueDropped", "outbound queue full")
		return false
	end
	s.queue[#s.queue + 1] = {
		wire = wire,
		context = context,
		route = route,
		snapshot = snapshot,
		key = key,
		groupFingerprint = self.partyRosterFingerprint,
		publishesLocation = PublishesLocation(self, wire),
		expires = Now(self) + (snapshot and 15 or 30),
	}
	self:RecordCommsTraffic("queued", wire)
	return true
end

function QT:DrainGeographicQueue()
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s or not self.isEnabled or self.isLoggingOut then
		return
	end
	for i = #s.queue, 1, -1 do
		local row = s.queue[i]
		local route = row.route
		local staleDiscovery = row.key == "zone-discovery" and route.channelName ~= s.currentChannel
		local staleRoute = (route.distribution ~= "CHANNEL" and route.distribution ~= "WHISPER")
			and (
				route.distribution ~= self:GetGroupAnnouncementDistribution()
				or row.groupFingerprint ~= self.partyRosterFingerprint
			)
		if
			route.channelName ~= self.announcementChannelName
			and route.distribution == "CHANNEL"
			and not s.subscriptions[route.channelName]
		then
			staleRoute = true
		end
		if route.distribution == "WHISPER" then
			staleRoute = self:IsIgnoredPlayerName(route.target) or (route.requiresGroup and
				(not self:IsGroupedSender(route.target) or row.groupFingerprint ~= self.partyRosterFingerprint))
		end
		if now >= row.expires or now < row.expires - 30 or staleRoute or staleDiscovery
			or not self:IsPartyVisualQueuedWireCurrent(row.wire) or not self:IsQueuedCommRequestCurrent(row.wire)
			or not self:IsPlayerDetailsQueuedWireCurrent(row.wire, route.target)
			or not self:IsPlayerPhaseQueuedWireCurrent(row.wire, route.target) then
			table.remove(s.queue, i)
			self:RecordCommsDiagnostic("queueDropped", "expired or departed route")
		end
	end
	-- Events precede heartbeats; one actual attempt per tick, with a shared
	-- token reserve for immediate request/response traffic.
	local index
	for i, row in ipairs(s.queue) do
		if not row.retryAt or now >= row.retryAt then
			if not index or (s.queue[index].snapshot and not row.snapshot) then index = i end
			if not row.snapshot then break end
		end
	end
	local row = index and s.queue[index]
	if not row or not self:TakeCommsSendToken(true) then
		return
	end
	-- The direct path does not recursively stage or queue.
	local sent = self:SendWireMessageToAnnouncementRoutes(row.wire, row.context, { row.route }, true)
	if sent then
		table.remove(s.queue, index)
	else
		-- Native throttles already pause the whole transport. A missing channel
		-- or rejected target must not prevent unrelated routes from draining.
		row.retryAt = now + 2
	end
end

function QT:UpdateGeographicComms()
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s or not self.isEnabled or self.isLoggingOut then
		return
	end
	self:UpdateGeographicSubscriptions()
	self:UpdateGeographicDiscovery()
	local global, locationDue = now >= s.nextGlobal, now >= s.nextLocal
	local fullLocal = now >= (s.nextLocalMetadata or s.nextLocal)
	local regional = locationDue or fullLocal
	local sampledLocation
	if global or regional then
		-- Sample now instead of republishing the producer's older 10/20-second
		-- location. Staging is local; the same bounded queue owns actual sends.
		local staged
		staged, sampledLocation = self:BroadcastPlayerLocation(self:CanPublishPlayerLocation())
		local fullPackets = (global or fullLocal) and self:BuildGeographicSnapshots() or nil
		local localPackets = regional and (fullLocal and fullPackets or self:BuildGeographicSnapshots(true)) or nil
		local routes = {}
		if global then
			routes[#routes + 1] = Channel(self.announcementChannelName)
		end
		if regional then
			if s.currentChannel and self:GetAnnouncementChannelLocalID(s.currentChannel) then
				routes[#routes + 1] = Channel(s.currentChannel)
			end
			local group = self:GetGroupAnnouncementDistribution()
			if group then
				routes[#routes + 1] = { distribution = group }
			end
		end
		for _, route in ipairs(routes) do
			local isGlobal = route.channelName == self.announcementChannelName
			local packets = isGlobal and fullPackets or localPackets
			local locationOnly = not isGlobal and not fullLocal
			local routeKey = route.channelName or route.distribution
			local location = s.latest.LOC
			local fingerprint = location and location.wire:match("^LOC|1,[^,]+,%d+,(.+)$")
			if route.distribution ~= "CHANNEL" and fingerprint then
				fingerprint = fingerprint .. ":" .. (self.partyRosterFingerprint or "")
			end
			-- Full metadata must not be displaced by the next one-second location
			-- sample. A full snapshot supersedes any older queued location-only one.
			if not locationOnly then
				for i = #s.queue, 1, -1 do
					local key = s.queue[i].key
					if key == routeKey .. ":location:1" or (key and key:sub(1, #routeKey + 7) == routeKey .. ":state:") then
						table.remove(s.queue, i)
					end
				end
			end
			-- Full heartbeats still renew stationary dots and discover newcomers.
			-- Fast updates only need to publish changed coordinates/identity.
			local changed = not locationOnly or fingerprint ~= s.locationFingerprints[routeKey]
			local queued = false
			for i, packet in ipairs(changed and packets or {}) do
				queued = self:QueueGeographicWire(
					packet,
					"presence snapshot",
					route,
					true,
					routeKey .. (locationOnly and ":location:" or ":state:") .. i
					) or queued
			end
			if queued and fingerprint then s.locationFingerprints[routeKey] = fingerprint end
		end
		if global then
			s.lastGlobal, s.nextGlobal = now, now + Random(self, 150, 210)
		end
		if regional then
			local count = 0
			for _, peer in pairs(s.peers) do
				if peer.zone == s.currentZone and now >= peer.at and now - peer.at < SNAPSHOT_LIFETIME then
					count = count + 1
				end
			end
			-- Sparse zones get smooth positions; retain the previous density
			-- backoff at 500+ known peers. Interpolate between the smaller anchors.
			local interval
			if count < 10 then interval = 1
			elseif count < 20 then interval = 5
			elseif count < 100 then interval = 5 + math.floor((count - 20) / 8)
			elseif count < 500 then interval = 15 + math.floor((count - 100) * 30 / 400)
			else interval = math.min(90, 20 + math.floor(count / 20)) end
			if locationDue then
				s.nextLocal = now + interval + (count < 10 and 0 or Random(self, 0, 5))
			end
			-- Compact LOC-only envelopes carry fast movement updates. Version,
			-- party and partner metadata retain their existing heartbeat cadence.
			if fullLocal then
				s.nextLocalMetadata = now + math.min(90, 20 + math.floor(count / 20)) + Random(self, 0, 5)
			end
		end
	end
	self:DrainGeographicQueue()
	return sampledLocation
end

function QT:ResetGeographicComms()
	local s = rawget(self, "geographicCommsState")
	if s then
		for name in pairs(s.subscriptions) do
			if self.API.LeaveChannelByName then
				pcall(self.API.LeaveChannelByName, name)
			end
		end
	end
	self.geographicCommsState = nil
end

function QT:FlushGeographicDeparture()
	local s = rawget(self, "geographicCommsState")
	if not s then
		return
	end
	s.queue = {}
	local location = s.latest.LOC
	-- Never serialize an old nonzero position during departure.
	local clear = location and location.wire:match("^LOC|1,[^,]+,%d+,0$") and location.wire
	s.sequence = s.sequence + 1
	local wire = "QTB1|1," .. (self:GetAnnouncementServerTime() or 0) .. "," .. s.session .. "," .. s.sequence .. ";"
	if clear then
		wire = wire .. "0," .. #clear .. ":" .. clear
	end
	local partner = s.latest.QTLF and s.latest.QTLF.wire
	if partner and partner:sub(-2) == ",0" then
		wire = wire .. "0," .. #partner .. ":" .. partner
	end
	wire = wire .. "0,8:QTPR|1,0"
	local routes = self:GetGeographicAnnouncementRoutes() or {}
	local hasGlobal = false
	for _, route in ipairs(routes) do
		if route.channelName == self.announcementChannelName then
			hasGlobal = true
		end
	end
	if not hasGlobal then
		routes[#routes + 1] = Channel(self.announcementChannelName)
	end
	-- Best effort now: disable/logout must never leave deferred publications.
	self:SendWireMessageToAnnouncementRoutes(wire, "presence departure", routes, true)
	s.latest = {}
end

function QT:ScheduleGeographicPingReply(id, routes, supportsPages, developerRequest)
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s or not self.API.Delay then
		return false
	end
	s.pingReplies = s.pingReplies or {}
	local count = 0
	for key, at in pairs(s.pingReplies) do
		if now < at or now - at > 300 then
			s.pingReplies[key] = nil
		else
			count = count + 1
		end
	end
	if s.pingReplies[id] or count >= 16 then
		return false
	end
	s.pingReplies[id] = now
	self.API.Delay(Random(self, 1, 20), function()
		if rawget(self, "geographicCommsState") ~= s or not self.isEnabled or self.isLoggingOut then
			return
		end
		self:SendPingResponse(id, routes, supportsPages, developerRequest)
	end)
	return true
end
