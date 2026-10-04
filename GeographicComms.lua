-- Addon-owned subscriptions, bounded outbound scheduling, and compact presence.
-- No server phase identifiers: regional names depend only on the zone map ID.
local QT = _G.QuestTogether
local STATE_COMMANDS = { LOC = true, QTPR = true, QTVR = true, QTLF = true, QTLQ = true, QJST = true }
local ORDER = { "QTPR", "QTVR", "QJST", "QTLF", "QTLQ", "LOC" }
local HANDLERS = {
	LOC = "HandlePlayerLocationMessage",
	QTPR = "HandleQTPlayerPresenceMessage",
	QTVR = "HandleAddonVersionMessage",
	QTLF = "HandleQuestPartnerStatusMessage",
	QTLQ = "HandleQuestPartnerQuestMessage",
	QJST = "HandlePartyJoinMetadata",
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
		queue = {},
		peers = {},
		startedAt = Now(self),
		tokens = 4,
		tokenAt = Now(self),
		sequence = 0,
		session = string.format("%d-%d", math.floor(Now(self) * 1000), Random(self, 1000, 999999)),
		nextGlobal = Now(self) + Random(self, 2, 12),
		nextLocal = Now(self) + Random(self, 1, 10),
	}
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
	for name in pairs(s.subscriptions) do
		if not desired[name] then
			if self.API.LeaveChannelByName then
				pcall(self.API.LeaveChannelByName, name)
			end
			s.subscriptions[name] = nil
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
	end
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
	local withdrawal = command == "LOC" and payload:match("^1,[^,]+,%d+,0$")
	if withdrawal or changedStatus or (command == "QTPR" and payload == "1,0") then
		s.nextGlobal = math.min(s.nextGlobal, math.max(now + 1, (s.lastGlobal or 0) + 10))
		s.nextLocal = math.min(s.nextLocal, now + 1)
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
function QT:BuildGeographicSnapshots()
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s then
		return {}
	end
	local stamp = self:GetAnnouncementServerTime() or 0
	s.sequence = s.sequence + 1
	local header = "QTB1|1," .. stamp .. "," .. s.session .. "," .. s.sequence .. ";"
	local packets, packet = {}, header
	for _, command in ipairs(ORDER) do
		local entry = s.latest[command]
		local maxAge = command == "LOC" and 35 or (command == "QTVR" and 180 or 90)
		if entry and now >= entry.at and now - entry.at <= maxAge then
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
				if #packet + #part > 255 then
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
		local count = 0
		for name, record in pairs(s.peers) do
			local at = record.at
			if now < at or now - at >= SNAPSHOT_LIFETIME then
				s.peers[name] = nil
			else
				count = count + 1
			end
		end
		if count > 2048 then
			local oldest, at
			for name, record in pairs(s.peers) do
				if not at or record.at < at then
					oldest, at = name, record.at
				end
			end
			s.peers[oldest] = nil
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
		publishesLocation = self:CanPublishPlayerLocation(),
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
		local staleRoute = route.distribution ~= "CHANNEL"
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
		if now >= row.expires or now < row.expires - 30 or staleRoute then
			table.remove(s.queue, i)
			self:RecordCommsDiagnostic("queueDropped", "expired or departed route")
		end
	end
	-- Events precede heartbeats; one actual attempt per tick, with a shared
	-- token reserve for immediate request/response traffic.
	local index = 1
	for i, row in ipairs(s.queue) do
		if not row.snapshot then
			index = i
			break
		end
	end
	local row = s.queue[index]
	if not row or not self:TakeCommsSendToken(true) then
		return
	end
	-- The direct path does not recursively stage or queue.
	local sent = self:SendWireMessageToAnnouncementRoutes(row.wire, row.context, { row.route }, true)
	if sent then
		table.remove(s.queue, index)
	else
		s.blockedUntil = now + 2
	end
end

function QT:UpdateGeographicComms()
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s or not self.isEnabled or self.isLoggingOut then
		return
	end
	self:UpdateGeographicSubscriptions()
	local global, regional = now >= s.nextGlobal, now >= s.nextLocal
	if global or regional then
		local packets = self:BuildGeographicSnapshots()
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
			for i, packet in ipairs(packets) do
				self:QueueGeographicWire(
					packet,
					"presence snapshot",
					route,
					true,
					(route.channelName or route.distribution) .. ":" .. i
				)
			end
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
			-- Bounded density backoff: a crowded launch zone updates less often.
			s.nextLocal = now + math.min(90, 20 + math.floor(count / 20)) + Random(self, 0, 5)
		end
	end
	self:DrainGeographicQueue()
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

function QT:ScheduleGeographicPingReply(id, routes)
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
		self:SendPingResponse(id, routes)
	end)
	return true
end
