-- Geographic interests, directory subscriptions and publication cadence. Public
-- data uses the whisper mesh; directory channels never carry addon payloads.
local QT = _G.QuestTogether
local ORDER = { "QTPR", "QTVR", "QJST", "QTLF", "QTLQ", "LOC", "QTPG", "QTCI", "QTHI" }
local TOPICS = {}
for _, topic in ipairs(ORDER) do
	TOPICS[topic] = true
end
local SNAPSHOT_LIFETIME = 600
local function Now(a)
	return a:SafeToNumber(a.API.GetTime and a.API.GetTime()) or 0
end
local function Mesh(scope)
	return { distribution = "MESH", scope = scope }
end
local function Random(a, low, high)
	local n = a:SafeToNumber(a.API.Random and a.API.Random(low, high)) or low
	return math.max(low, math.min(high, n))
end
local function Active(a)
	return a.isEnabled
		and not a.isLoggingOut
		and not a:IsRuntimeRestricted()
		and not a:IsRuntimeRestrictionTypeActive("chat")
end
local function Copy(record)
	local copy = {}
	for key, value in pairs(record) do
		copy[key] = value
	end
	return copy
end
local function Equal(a, b)
	if not a or not b then
		return a == b
	end
	for key, value in pairs(a) do
		if b[key] ~= value then
			return false
		end
	end
	for key, value in pairs(b) do
		if a[key] ~= value then
			return false
		end
	end
	return true
end
local function FinishReceipt(receipt, sent, reason, code, ticket)
	if not receipt or receipt.done then
		return
	end
	receipt.done = true
	if receipt.options.onComplete then
		pcall(receipt.options.onComplete, sent, reason, code, ticket)
	end
end

function QT:GetGeographicSnapshotLifetime()
	return SNAPSHOT_LIFETIME
end
function QT:InitializeGeographicComms()
	if rawget(self, "geographicCommsState") then
		return
	end
	local now = Now(self)
	self.geographicCommsState = {
		subscriptions = {},
		latest = {},
		routes = {},
		peers = {},
		peerCount = 0,
		startedAt = now,
		nextGlobal = now + Random(self, 2, 12),
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
		desired["QuestTogether3Z" .. current] = true
	end
	if s.viewZone and s.viewZone ~= current then
		desired["QuestTogether3Z" .. s.viewZone] = true
	end
	-- Permanent channels can outlive a reload. Leave protocol-2 subscriptions
	-- and stale protocol-3 zone directories, never unrelated player channels.
	if not s.reconciledChannels and self.API.GetChatChannelList then
		local listed, channels = pcall(self.API.GetChatChannelList)
		if listed and self:CanAccessTable(channels) and #channels <= 90 and #channels % 3 == 0 then
			s.reconciledChannels = true
			for index = 2, #channels, 3 do
				local name = self:SafeToString(channels[index], "")
				local lower = name:lower()
				local legacy = lower == "questtogether" or lower:match("^questtogetherz[1-9]%d*$") ~= nil
				local zone = tonumber(lower:match("^questtogether3z([1-9]%d*)$"))
				if
					(
						legacy
						or zone
							and zone <= 1000000
							and not desired["QuestTogether3Z" .. zone]
							and not s.subscriptions["QuestTogether3Z" .. zone]
					)
					and self.API.LeaveChannelByName
				then
					local left, result = pcall(self.API.LeaveChannelByName, name)
					if not left or result == false then
						s.reconciledChannels = false
					end
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
			s.routes[name] = nil
			self:CancelCommunicationOwner("geography:" .. name, "cancelled")
			if self.announcementChannelBindings then
				self.announcementChannelBindings[name] = nil
			end
		end
	end
	for name in pairs(desired) do
		s.subscriptions[name] = true
		local joined = self:GetAnnouncementChannelLocalID(name) ~= nil
		if self:EnsureMeshDirectoryJoined(name) and not joined then
			self:ScheduleAnnouncementChannelOrder()
		end
	end
	s.currentZone = current
	local channel = current and ("QuestTogether3Z" .. current) or nil
	if channel ~= s.currentChannel then
		s.currentChannel = channel
		if channel then
			s.routes[channel] = nil
		end
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
	routes[#routes + 1] = Mesh(s.currentZone or "global")
	return routes
end

-- Producer-owned primitive records are copied when staged. Their sample time is
-- retained through later publication; receipt cannot make old metadata fresh.
function QT:StageCommunicationState(topic, record, options)
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s or not TOPICS[topic] or type(record) ~= "table" then
		return false
	end
	options = options or {}
	local old = s.latest[topic]
	local sampledAt = options.sampledAt or self:GetAnnouncementServerTime() or 0
	local revision = old and old.sampledAt == sampledAt and Equal(old.data, record) and old.revision
		or self:NextCommunicationSequence()
	local receipt = old and Equal(old.data, record) and not old.receipt.done and old.receipt or nil
	if not receipt then
		if old then
			FinishReceipt(old.receipt, false, "superseded")
		end
		receipt = {}
	end
	receipt.options = options
	s.latest[topic] = {
		data = Copy(record),
		at = now,
		sampledAt = sampledAt,
		revision = revision,
		options = options,
		receipt = receipt,
	}
	local withdrawal = topic == "LOC" and record.mask == 0
	local changed = topic == "QTPR" and record.active == false
		or topic == "QTLF" and old and old.data.looking ~= record.looking
		or topic == "QTPG" and (not old or not Equal(old.data, record))
		or withdrawal and (not old or old.data.mask ~= 0)
	if changed then
		s.nextGlobal = math.min(s.nextGlobal, math.max(now + 1, (s.lastGlobal or 0) + 10))
		for key, route in pairs(s.routes) do
			route.nextLocation, route.nextMetadata =
				math.min(route.nextLocation, now + 1), math.min(route.nextMetadata, now + 1)
			self:CancelCommunicationOwner("geography:" .. key, "cancelled")
		end
		if withdrawal then
			self:CancelCommunicationWhere(function(row)
				return row.publishesLocation == true
			end)
		end
	end
	return true
end

function QT:BuildCommunicationStateRecords(locationOnly, topics, includeVersion)
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	local records, entries = {}, {}
	if not s then
		return records, entries
	end
	for _, topic in ipairs(ORDER) do
		local entry = s.latest[topic]
		local maxAge = topic == "LOC" and 35 or (topic == "QTVR" and 180 or 90)
		if
			entry
			and (not topics or topics[topic])
			and (not locationOnly or topic == "LOC" or topic == "QTVR" and includeVersion ~= false)
			and now >= entry.at
			and now - entry.at <= maxAge
			and (not entry.options.isCurrent or entry.options.isCurrent())
		then
			-- Every public location carries its owner's version, including when a
			-- recipient missed the slower full baseline. Preserve its source time
			-- and existing counts: protocol-3 receivers treat omitted counts as
			-- unknown. The original revision/time prevent renewing old party data.
			local data = Copy(entry.data)
			records[#records + 1] =
				{ topic = topic, data = data, sampledAt = entry.sampledAt, revision = entry.revision }
			if not locationOnly or topic ~= "QTVR" then
				entries[#entries + 1] = { topic = topic, receipt = entry.receipt }
			end
		end
	end
	return records, entries
end

-- The coordinator invokes this only after normal LOC admission. This index is
-- routing density, not another location source or a second freshness authority.
function QT:RecordGeographicPeerLocation(name, record, observation)
	local s = rawget(self, "geographicCommsState")
	if not s then
		return
	end
	s.density = nil
	if not record or record.mask == 0 then
		if s.peers[name] then
			s.peerCount = math.max(0, (s.peerCount or 1) - 1)
		end
		s.peers[name] = nil
		return
	end
	local now = Now(self)
	if not s.peers[name] then
		s.peerCount = (s.peerCount or 0) + 1
	end
	s.peers[name] = {
		zone = self:GetGeographicZoneID(record.mapID),
		expires = observation and observation.expiresAt or now + SNAPSHOT_LIFETIME,
		at = now,
	}
	if not s.prunedAt or now < s.prunedAt or now - s.prunedAt >= 1 then
		s.prunedAt, s.peerCount = now, 0
		for peer, value in pairs(s.peers) do
			if now >= value.expires or now < value.at then
				s.peers[peer] = nil
			else
				s.peerCount = s.peerCount + 1
			end
		end
	end
	if s.peerCount > 2048 then
		local oldest, oldestAt
		for peer, value in pairs(s.peers) do
			if not oldestAt or value.at < oldestAt then
				oldest, oldestAt = peer, value.at
			end
		end
		s.peers[oldest], s.peerCount = nil, s.peerCount - 1
	end
end
function QT:GetGeographicZonePopulation(zone)
	local s, now, count = rawget(self, "geographicCommsState"), Now(self), 0
	if not s then
		return count
	end
	local cached = s.density
	if cached and cached.zone == zone and now >= cached.at and now < cached.untilAt then
		return cached.count
	end
	local untilAt = now + 1
	for _, peer in pairs(s.peers) do
		if peer.zone == zone and now >= peer.at and now < peer.expires then
			count = count + 1
			untilAt = math.min(untilAt, peer.expires)
		end
	end
	s.density = { zone = zone, at = now, untilAt = untilAt, count = count }
	return count
end
local function Intervals(a, count)
	local interval
	if count < 20 then
		interval = 5
	elseif count < 100 then
		interval = 5 + math.floor((count - 20) / 8)
	elseif count < 500 then
		interval = 15 + math.floor((count - 100) * 30 / 400)
	else
		interval = math.min(90, 20 + math.floor(count / 20))
	end
	return interval + (count < 10 and 0 or Random(a, 0, 5)), math.min(90, 20 + math.floor(count / 20)) + Random(a, 0, 5)
end

function QT:UpdateGeographicComms()
	local s, now = rawget(self, "geographicCommsState"), Now(self)
	if not s or not Active(self) or s.departing then
		return
	end
	self:UpdateGeographicSubscriptions()
	local routes = { { route = Mesh("global"), global = true } }
	if s.currentZone then
		routes[#routes + 1] = { route = Mesh(s.currentZone) }
	end
	local group = self:GetGroupAnnouncementDistribution()
	if group then
		routes[#routes + 1] = { route = { distribution = group }, roster = self.partyRosterFingerprint }
	end
	local locationInterval, metadataInterval = Intervals(self, self:GetGeographicZonePopulation(s.currentZone))
	local sampled, sampledLocation = false, nil
	for _, item in ipairs(routes) do
		local public = item.route.distribution == "MESH"
		local key = public and (item.global and "global" or "QuestTogether3Z" .. item.route.scope)
			or item.route.distribution
		local cadence = public and locationInterval or 1
		local route = s.routes[key]
		if not route then
			local initial = item.global and s.nextGlobal or now + Random(self, 1, 10)
			route = { nextLocation = initial, nextMetadata = initial }
			s.routes[key] = route
		end
		if item.global then
			route.nextMetadata = math.min(route.nextMetadata, s.nextGlobal)
		end
		if route.roster ~= item.roster then
			route.roster, route.nextMetadata = item.roster, now
		end
		-- A slow full baseline must not freeze current movement behind it. Keep
		-- one full publication and one replaceable location publication per route.
		local full = now >= route.nextMetadata and not route.pending
		local pendingSlot = not full and "locationPending" or "pending"
		if
			(not route[pendingSlot] or not full)
			and now >= (route.retryAt or 0)
			and (not public or not route.submittedAt or now >= route.submittedAt + 5)
			and (full or not item.global and now >= route.nextLocation)
		then
			if not sampled then
				local staged
				staged, sampledLocation = self:BroadcastPlayerLocation(self:CanPublishPlayerLocation())
				sampled = true
			end
			local records, entries = self:BuildCommunicationStateRecords(not full, nil, public)
			local location = s.latest.LOC and Copy(s.latest.LOC.data)
			-- Envelope sequencing owns order. Position equality ignores producer-local
			-- counters, so stationary dots do not generate one-second traffic.
			if location then
				location.session, location.sequence = nil, nil
			end
			local previousLocation = route.locationPending and route.locationSubmitted or route.location
			if not full and Equal(location, previousLocation) then
				route.nextLocation = now + cadence
			elseif #records == 0 then
				route.retryAt = now + 1
			else
				local pending, roster = {}, item.roster
				local publishesLocation = false
				for _, record in ipairs(records) do
					if record.topic == "LOC" and record.data.mask ~= 0 then
						publishesLocation = true
					end
				end
				route[pendingSlot] = pending
				local submittedAt = now
				route.submittedAt, route.nextLocation = now, now + cadence
				if not full then route.locationSubmitted = location end
				local admitted = self:Emit("STATE", { records = records }, { item.route }, {
					owner = "geography:" .. key,
					key = "geography:" .. key .. (not full and ":location" or ":full"),
					priority = full and "background" or "active",
					-- The slow global baseline renews after 150--210 seconds.
					-- Retain its source proof through that interval so newly joined
					-- interests can still receive it; timestamps remain unchanged.
					expires = now + (public and (full and (item.global and 300 or 120) or 30) or (full and 15 or 2)),
					publishesLocation = publishesLocation,
					isCurrent = function()
						return rawget(self, "geographicCommsState") == s
							and not s.departing
							and Active(self)
							and route[pendingSlot] == pending
							and (not publishesLocation or self:CanPublishPlayerLocation())
							and (not public or item.global or s.currentZone == item.route.scope)
							and (not roster or roster == self.partyRosterFingerprint)
							and (public or self:GetGroupAnnouncementDistribution() == item.route.distribution)
					end,
					onComplete = function(sent, reason, code, ticket)
						if route[pendingSlot] ~= pending then
							return
						end
						route[pendingSlot] = nil
						if not sent then
							route.retryAt = Now(self) + 1
							return
						end
						local acceptedAt = Now(self)
						route.acceptedAt, route.retryAt = acceptedAt, nil
						if not route.locationSampledAt or submittedAt >= route.locationSampledAt then
							route.location, route.locationSampledAt = location, submittedAt
							route.nextLocation = acceptedAt + cadence
						end
						if full then
							route.nextMetadata = acceptedAt
								+ (item.global and Random(self, 150, 210) or metadataInterval)
						end
						if item.global then
							s.lastGlobal, s.nextGlobal = acceptedAt, route.nextMetadata
						end
						for _, selected in ipairs(entries) do
							local latest = s.latest[selected.topic]
							if latest and latest.receipt == selected.receipt then
								local current = not latest.options.isCurrent or latest.options.isCurrent()
								FinishReceipt(
									selected.receipt,
									current == true,
									current and reason or "cancelled",
									code,
									ticket
								)
							end
						end
					end,
				})
				if not admitted and route[pendingSlot] == pending then
					route[pendingSlot], route.retryAt = nil, now + 1
				end
			end
		end
	end
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
		for key in pairs(s.routes) do
			self:CancelCommunicationOwner("geography:" .. key, "cancelled")
		end
		for _, entry in pairs(s.latest) do
			FinishReceipt(entry.receipt, false, "cancelled")
		end
	end
	self.geographicCommsState = nil
end

function QT:ResumeGeographicComms()
	local s = rawget(self, "geographicCommsState")
	if not s then
		return
	end
	for key in pairs(s.routes) do
		self:CancelCommunicationOwner("geography:" .. key, "cancelled")
	end
	for _, entry in pairs(s.latest) do
		FinishReceipt(entry.receipt, false, "cancelled")
	end
	s.departing, s.latest, s.routes, s.checkedAt = nil, {}, {}, nil
	local now = Now(self)
	s.nextGlobal = now
end

-- Requested metadata is sampled directly from domain builders. It never reads
-- peer caches, stages a broadcast, or grants the requester's location consent.
function QT:BuildLocalCommunicationState(topics)
	if not Active(self) then
		return {}
	end
	local records, callbacks, stamp = {}, {}, self:GetAnnouncementServerTime() or 0
	local function Add(topic, record, completed)
		if record and (not topics or topics[topic]) then
			local owned = self:CopyCommRecord(topic, record)
			if owned then
				records[#records + 1] =
					{ topic = topic, data = owned, sampledAt = stamp, revision = self:NextCommunicationSequence() }
				if completed then
					callbacks[#callbacks + 1] = function()
						completed(self, owned)
					end
				end
			end
		end
	end
	local presence = self:GetQTPlayerPresenceState()
	local looking = self:GetOption("lookingForQuestPartners") == true
	Add("QTPR", { active = true })
	local version = self:GetAddonVersion()
	if self:ParseAddonVersion(version) then
		Add("QTVR", { version = version, count = self:GetMonitoredQuestCount(), partySize = self:GetLocalPartySize() })
	end
	Add("QTPG", self:BuildPartyVisualMetadata(), self.RecordPartyVisualPublication)
	Add("QJST", self:BuildPartyJoinMetadataPayload(), self.RecordPartyJoinPublication)
	Add("QTLF", self:BuildQuestPartnerStatusPayload(presence, looking), self.RecordQuestPartnerPublication)
	Add("QTLQ", self:BuildQuestPartnerQuestPayload(presence, looking), self.RecordQuestPartnerQuestPublication)
	Add("QTCI", self:BuildPlayerCapabilityRecord())
	Add("QTHI", self:BuildPlayerDetailsIdentityPayload())
	local completed = false
	return records,
		function(sent)
			if not sent or completed then
				return
			end
			completed = true
			for _, callback in ipairs(callbacks) do
				callback()
			end
		end
end
