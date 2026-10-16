-- Optional, short-lived minimap position streams. All state is addon-owned.
-- Latest-only samples and leases share the coordinator and native byte budget.
-- At most four normal, consenting nearby peers can own a short lease.
local QT = _G.QuestTogether
local MAX_PEERS, LEASE, FRESH = 4, 12, 3
local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end
local function Enabled(a)
	return a.isEnabled
		and not a.isLoggingOut
		and not a:IsRuntimeRestricted()
		and a:CanPublishPlayerLocation()
		and a:GetOption("showPlayerLocations") == true
end
local function State(a)
	local s = rawget(a, "nearbyStreamState")
	if not s then
		s = { capabilities = {}, wanted = {}, subscribers = {}, nextSubmit = 0, nextScan = 0, serial = 0 }
		a.nearbyStreamState = s
	end
	return s
end
local function Fresh(now, at, lifetime)
	return at and now >= at and now - at < lifetime
end
local function BasePeer(a, name)
	local row = a:GetFreshPlayerLocation(name, "minimap")
	return row and a:ShouldShowPlayerLocation(name) and row or nil
end
local function Capability(s, name, now)
	local cap = s.capabilities[name]
	return cap and cap.streams and Fresh(now, cap.receivedAt, cap.lifetime or 600)
end

local function Position(entry, now, smooth)
	local sample = entry and entry.sample
	if not sample or not Fresh(now, sample.at, FRESH) then
		return nil
	end
	local fraction = smooth and math.min(1, (now - sample.at) / sample.duration) or 1
	return {
		mapID = sample.mapID,
		sampledAt = sample.at,
		x = sample.fromX + (sample.x - sample.fromX) * fraction,
		y = sample.fromY + (sample.y - sample.fromY) * fraction,
	}
end

function QT:BuildPlayerCapabilityRecord()
	local raceID = self.API.GetPlayerRaceID and self:SafeToNumber(self.API.GetPlayerRaceID()) or 0
	raceID = raceID and raceID >= 0 and raceID <= 100000 and raceID == math.floor(raceID) and raceID or 0
	return { streams = Enabled(self) == true, raceID = raceID }
end

function QT:GetPlayerCapabilities(name)
	local s, now = rawget(self, "nearbyStreamState"), Now(self)
	local cap = s and s.capabilities[name]
	if cap and not self:IsIgnoredPlayerName(name) and Fresh(now, cap.receivedAt, cap.lifetime or 600) then
		return { streams = cap.streams, raceID = cap.raceID, sampledAt = cap.sampledAt, receivedAt = cap.receivedAt }
	end
end

function QT:HandlePlayerCapabilityMetadata(payload, sender, observation)
	if type(payload) ~= "table" or type(payload.streams) ~= "boolean" then
		return false
	end
	local raceID = self:SafeToNumber(payload.raceID)
	if not raceID or raceID < 0 or raceID > 100000 or raceID ~= math.floor(raceID) then
		return false
	end
	local name = self:NormalizeMemberName(sender)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local s, now = State(self), Now(self)
	observation = self:ResolvePeerObservation(name, "QTCI", observation)
	local previous = s.capabilities[name]
	local cap = {
		raceID = raceID,
		streams = payload.streams,
		lastRequestAt = previous and previous.lastRequestAt,
		retryAt = previous and previous.retryAt,
	}
	if not self:CommitPeerObservation(observation, cap, false) then
		return false
	end
	s.capabilities[name] = cap
	if not cap.streams then
		local wanted, subscriber = s.wanted[name], s.subscribers[name]
		s.wanted[name], s.subscribers[name] = nil, nil
		if wanted then
			self:CancelCommunicationOwner(wanted, "cancelled")
		end
		if subscriber then
			self:CancelCommunicationOwner(subscriber, "cancelled")
		end
	end
	local count, oldest, oldestAt = 0
	for key, value in pairs(s.capabilities) do
		if not Fresh(now, value.receivedAt, value.lifetime or 600) then
			s.capabilities[key] = nil
		else
			count = count + 1
			if not oldestAt or value.receivedAt < oldestAt then
				oldest, oldestAt = key, value.receivedAt
			end
		end
	end
	if count > 512 then
		self:RetireNearbyStreamPeer(oldest)
	end
	return true, cap
end

-- This wrapper also provides the private-fixture geometry seam. A peer must be
-- independently known through normal location sharing, never request payloads.
function QT:GetNearbyStreamCandidates()
	if not Enabled(self) then
		return {}
	end
	local s, now = State(self), Now(self)
	local geometry = self:GetLocationPinSurface("minimap")
	if not geometry then
		return {}
	end
	local result = {}
	for name in pairs(s.capabilities) do
		local base = BasePeer(self, name, now)
		if base and Capability(s, name, now) then
			local position = Position(s.wanted[name], now, false)
			if position then
				position.name = name
			end
			local row = position or base
			local x, y = self:ProjectPlayerLocationPin("minimap", row, geometry)
			if x and y then
				result[#result + 1] =
					{ name = name, distance = (x - geometry.width / 2) ^ 2 + (y - geometry.height / 2) ^ 2 }
			end
		end
	end
	table.sort(result, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.name < b.name
	end)
	return result
end

function QT:GetNearbyStreamPosition(row, smooth)
	local s = rawget(self, "nearbyStreamState")
	if not s or not s.wanted[row.name] then
		return row
	end
	local now = Now(self)
	if not Enabled(self) or not BasePeer(self, row.name, now) then
		return row
	end
	local position = Position(s.wanted[row.name], now, smooth)
	if not position then
		return row
	end
	-- Preserve identity/consent/tooltip metadata; never mutate the LOC sequence
	-- or refresh its lifetime with a packet from this independent protocol.
	local copy = {}
	for key, value in pairs(row) do
		copy[key] = value
	end
	copy.mapID, copy.x, copy.y = position.mapID, position.x, position.y
	copy.sampledAt = position.sampledAt
	return copy
end

local function Submit(a, s, name, operation, record, owner, current, complete)
	local now = Now(a)
	return a:Emit(operation, record, { { distribution = "WHISPER", target = name } }, {
		owner = owner,
		key = "nearby:" .. operation .. ":" .. name,
		flow = "nearby:" .. name,
		priority = operation == "QTSP" and "active" or "control",
		expires = now + 2,
		publishesLocation = operation == "QTSP",
		isCurrent = function()
			return rawget(a, "nearbyStreamState") == s and Enabled(a) and not a:IsIgnoredPlayerName(name) and current()
		end,
		onComplete = complete,
	})
end

function QT:HandleNearbyStreamMessage(command, payload, sender, context)
	if command ~= "QTSR" and command ~= "QTSP" and command ~= "QTSX" then
		return false
	end
	if type(payload) ~= "table" or not Enabled(self) then
		return false
	end
	local name = self:NormalizeMemberName(sender)
	local s, now = rawget(self, "nearbyStreamState"), Now(self)
	if not s or not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local token = self:SafeToString(payload.token, "")
	if #token < 1 or #token > 80 or not token:match("^[%w%-]+$") then
		return false
	end
	if command == "QTSX" then
		local peer = s.subscribers[name]
		if token and peer and peer.token == token then
			s.subscribers[name] = nil
			self:CancelCommunicationOwner(peer, "cancelled")
			return true
		end
		return false
	elseif command == "QTSR" then
		if not Capability(s, name, now) or not BasePeer(self, name, now) then
			return false
		end
		-- Only our nearest four peers may request a stream; no sender can choose
		-- an arbitrary whisper recipient or force an immediate reply.
		local cap = s.capabilities[name]
		if Fresh(now, cap.lastRequestAt, 2) then
			return false
		end
		cap.lastRequestAt = now
		local allowed, selected = false, {}
		for i, row in ipairs(self:GetNearbyStreamCandidates()) do
			if i > MAX_PEERS then
				break
			end
			selected[row.name] = true
			if row.name == name then
				allowed = true
			end
		end
		if not allowed then
			return false
		end
		for key in pairs(s.subscribers) do
			if not selected[key] then
				local stale = s.subscribers[key]
				s.subscribers[key] = nil
				self:CancelCommunicationOwner(stale, "cancelled")
			end
		end
		local peer = s.subscribers[name]
		if peer and Fresh(now, peer.renewedAt, 2) then
			return false
		end
		if not peer or peer.token ~= token then
			if peer then
				self:CancelCommunicationOwner(peer, "cancelled")
			end
			peer = { token = token, sequence = 0, lastSent = 0 }
		end
		peer.renewedAt = now
		s.subscribers[name] = peer
		return true
	end
	local seq, stamp, mapID, x, y =
		self:SafeToNumber(payload.sequence),
		self:SafeToNumber(payload.stamp),
		self:SafeToNumber(payload.mapID),
		self:SafeToNumber(payload.x),
		self:SafeToNumber(payload.y)
	local peer = s.wanted[name]
	if
		not token
		or not peer
		or peer.token ~= token
		or not (Fresh(now, peer.requestedAt, LEASE) or peer.pendingRequest and Fresh(now, peer.pendingRequest.at, LEASE))
		or not seq
		or seq < 1
		or seq > 2147483647
		or seq ~= math.floor(seq)
		or seq <= (peer.sequence or 0)
		or not mapID
		or mapID < 1
		or mapID > 1000000
		or mapID ~= math.floor(mapID)
		or not x
		or x < 0
		or x > 1
		or not y
		or y < 0
		or y > 1
		or not BasePeer(self, name, now)
	then
		return false
	end
	local serverNow = self:GetAnnouncementServerTime()
	if
		not stamp
		or stamp < 0
		or stamp > 99999999999
		or stamp ~= math.floor(stamp)
		or (serverNow and stamp ~= 0 and (serverNow - stamp > 3 or serverNow - stamp < -5))
	then
		return false
	end
	local position = { mapID = mapID, x = x, y = y, name = name }
	local geometry = self:GetLocationPinSurface("minimap")
	if not geometry or not self:ProjectPlayerLocationPin("minimap", position, geometry) then
		s.wanted[name] = nil
		self:CancelCommunicationOwner(peer, "cancelled")
		if s.capabilities[name] then
			s.capabilities[name].retryAt = now + 20
		end
		return false
	end
	local previous = Position(peer, now, true)
	local duration = peer.sample and math.max(0.2, math.min(1, now - peer.sample.at)) or 0.2
	-- Snap across maps and teleports rather than animating a trip that did not happen.
	local fromX, fromY = x, y
	if previous and previous.mapID == mapID then
		local beforeX, beforeY = self:ProjectPlayerLocationPin("minimap", previous, geometry)
		local afterX, afterY = self:ProjectPlayerLocationPin("minimap", position, geometry)
		if beforeX and (beforeX - afterX) ^ 2 + (beforeY - afterY) ^ 2 < (geometry.width / 2) ^ 2 then
			fromX, fromY = previous.x, previous.y
		end
	end
	peer.sequence = seq
	local age = serverNow and stamp ~= 0 and math.max(0, serverNow - stamp) or 0
	peer.sample = { mapID = mapID, x = x, y = y, fromX = fromX, fromY = fromY, at = now - age, duration = duration }
	return true
end

function QT:UpdateNearbyStreams(currentSample)
	local s, now = State(self), Now(self)
	if
		self.isEnabled
		and not self.isLoggingOut
		and not self:IsRuntimeRestricted()
		and now >= (s.nextCapability or 0)
	then
		self:Publish("QTCI", self:BuildPlayerCapabilityRecord())
		s.nextCapability = now + 20
	end
	if not Enabled(self) then
		local wanted, subscribers = s.wanted, s.subscribers
		s.wanted, s.subscribers = {}, {}
		for _, peer in pairs(wanted) do
			self:CancelCommunicationOwner(peer, "cancelled")
		end
		for _, peer in pairs(subscribers) do
			self:CancelCommunicationOwner(peer, "cancelled")
		end
		return
	end
	if now >= s.nextScan then
		local selected = {}
		for i, row in ipairs(self:GetNearbyStreamCandidates()) do
			if i > MAX_PEERS then
				break
			end
			selected[row.name] = true
			local cap = s.capabilities[row.name]
			if not s.wanted[row.name] and now >= (cap.retryAt or 0) then
				s.serial = self:NextCommunicationSequence()
				s.wanted[row.name] =
					{ token = self:GetCommunicationSession() .. "-" .. s.serial, nextRequest = 0, startedAt = now }
			end
		end
		for name, peer in pairs(s.wanted) do
			if not selected[name] or not Fresh(now, peer.sample and peer.sample.at or peer.startedAt, LEASE) then
				if s.capabilities[name] then
					s.capabilities[name].retryAt = now + 20
				end
				s.wanted[name] = nil
				self:CancelCommunicationOwner(peer, "cancelled")
				-- The lease itself expires if this best-effort cancellation cannot send.
				Submit(self, s, name, "QTSX", { token = peer.token }, s, function()
					return s.wanted[name] == nil
				end)
			end
		end
		for name, peer in pairs(s.subscribers) do
			if not selected[name] or not Fresh(now, peer.renewedAt, LEASE) then
				s.subscribers[name] = nil
				self:CancelCommunicationOwner(peer, "cancelled")
			end
		end
		s.nextScan = now + 0.5
	end
	if now < s.nextSubmit then
		return
	end
	local requestName, request
	for name, peer in pairs(s.wanted) do
		if
			not peer.pendingRequest
			and BasePeer(self, name)
			and now >= peer.nextRequest
			and (
				not request
				or peer.nextRequest < request.nextRequest
				or peer.nextRequest == request.nextRequest and name < requestName
			)
		then
			requestName, request = name, peer
		end
	end
	if request then
		-- Correlation exists before dispatch because private transports may return a
		-- stream sample synchronously. Publication timestamps wait for acceptance.
		local pending = { at = now }
		request.pendingRequest = pending
		local admitted = Submit(self, s, requestName, "QTSR", { token = request.token }, request, function()
			return s.wanted[requestName] == request
				and request.pendingRequest == pending
				and BasePeer(self, requestName) ~= nil
		end, function(sent, reason)
			if s.wanted[requestName] ~= request or request.pendingRequest ~= pending then
				return
			end
			request.pendingRequest = nil
			if sent then
				request.requestedAt, request.nextRequest = Now(self), Now(self) + 5
			elseif reason == "rejected" or reason == "ambiguous" then
				s.wanted[requestName] = nil
				if s.capabilities[requestName] then
					s.capabilities[requestName].retryAt = Now(self) + 20
				end
			else
				request.nextRequest = Now(self) + 2
			end
		end)
		if not admitted and request.pendingRequest == pending then
			request.pendingRequest, request.nextRequest = nil, now + 2
		end
		s.nextSubmit = now + 0.2
		return
	end
	if not next(s.subscribers) then
		return
	end
	local location = currentSample or self:ReadLocalPlayerLocation()
	if not location then
		local previous = s.subscribers
		s.subscribers = {}
		for _, peer in pairs(previous) do
			self:CancelCommunicationOwner(peer, "cancelled")
		end
		return
	end
	local position = string.format("%d,%.5f,%.5f", location.mapID, location.x, location.y)
	local target, peer
	for name, candidate in pairs(s.subscribers) do
		if
			BasePeer(self, name)
			and (candidate.position ~= position or now - candidate.lastSent >= 2)
			and (not candidate.pendingSample or candidate.pendingSample.position ~= position)
			and (
				not peer
				or (candidate.lastSubmitted or 0) < (peer.lastSubmitted or 0)
				or (candidate.lastSubmitted or 0) == (peer.lastSubmitted or 0) and name < target
			)
		then
			target, peer = name, candidate
		end
	end
	if not peer then
		return
	end
	-- Allocation orders attempts; sequence/lastSent describe accepted publication.
	peer.issuedSequence = (peer.issuedSequence or peer.sequence) + 1
	local pending = { position = position, sequence = peer.issuedSequence }
	peer.pendingSample, peer.lastSubmitted = pending, now
	local admitted = Submit(
		self,
		s,
		target,
		"QTSP",
		{
			token = peer.token,
			sequence = pending.sequence,
			stamp = self:GetAnnouncementServerTime() or 0,
			mapID = location.mapID,
			x = location.x,
			y = location.y,
		},
		peer,
		function()
			return s.subscribers[target] == peer
				and peer.pendingSample == pending
				and Fresh(Now(self), peer.renewedAt, LEASE)
				and BasePeer(self, target) ~= nil
		end,
		function(sent)
			if s.subscribers[target] ~= peer or peer.pendingSample ~= pending then
				return
			end
			peer.pendingSample = nil
			if sent then
				peer.sequence, peer.lastSent, peer.position = pending.sequence, Now(self), position
			end
		end
	)
	if not admitted and peer.pendingSample == pending then
		peer.pendingSample = nil
	end
	s.nextSubmit = now + 0.2
end

function QT:RetireNearbyStreamPeer(name)
	local s = rawget(self, "nearbyStreamState")
	if not s then
		return
	end
	local wanted, subscriber = s.wanted[name], s.subscribers[name]
	s.capabilities[name], s.wanted[name], s.subscribers[name] = nil, nil, nil
	if wanted then
		self:CancelCommunicationOwner(wanted, "cancelled")
	end
	if subscriber then
		self:CancelCommunicationOwner(subscriber, "cancelled")
	end
end
function QT:ResetNearbyStreams()
	local s = rawget(self, "nearbyStreamState")
	self.nearbyStreamState = nil
	if s then
		self:CancelCommunicationOwner(s, "cancelled")
		for _, peer in pairs(s.wanted) do
			self:CancelCommunicationOwner(peer, "cancelled")
		end
		for _, peer in pairs(s.subscribers) do
			self:CancelCommunicationOwner(peer, "cancelled")
		end
	end
end

function QT:OnNearbyLocationOptionsChanged(key)
	local s = rawget(self, "nearbyStreamState")
	if not s then
		return
	end
	local wanted = s.wanted
	s.wanted, s.nextScan = {}, 0
	for _, peer in pairs(wanted) do
		self:CancelCommunicationOwner(peer, "cancelled")
	end
	if not key or key == "sharePlayerLocation" then
		local subscribers = s.subscribers
		s.subscribers, s.nextCapability = {}, 0
		for _, peer in pairs(subscribers) do
			self:CancelCommunicationOwner(peer, "cancelled")
		end
	end
end
