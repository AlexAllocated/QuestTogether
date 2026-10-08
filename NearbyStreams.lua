-- Optional, short-lived minimap position streams. All state is addon-owned.
-- Whispers are not unlimited bandwidth: at most five packets/second TOTAL,
-- shared by four nearest peers (including lease requests). Nothing is queued.
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
		s = { capabilities = {}, wanted = {}, subscribers = {}, nextSend = 0, nextScan = 0 }
		a.nearbyStreamState = s
	end
	return s
end
local function Fresh(now, at, lifetime)
	return at and now >= at and now - at < lifetime
end
local function BasePeer(a, name, now)
	local locations = rawget(a, "playerLocationState")
	local row = locations and locations.peers[name]
	if
		row
		and row.mask >= 2
		and Fresh(now, row.receivedAt, row.lifetime or 120)
		and a:ShouldShowPlayerLocation(name)
	then
		return row
	end
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
		x = sample.fromX + (sample.x - sample.fromX) * fraction,
		y = sample.fromY + (sample.y - sample.fromY) * fraction,
	}
end

function QT:HandlePlayerCapabilityMetadata(payload, sender, sampleAge, source)
	if not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 32 then
		return false
	end
	local streams, raceID, direct = payload:match("^1,([01]),(%d+),([01])$")
	if not streams then
		streams, raceID = payload:match("^1,([01]),(%d+)$")
	end
	raceID = tonumber(raceID)
	if not streams or not raceID or raceID > 100000 then
		return false
	end
	local name = self:NormalizeMemberName(sender)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local s, now = State(self), Now(self)
	local observation = self:ResolvePeerObservation(name, "QTCI", sampleAge, source, nil, nil, 600)
	if not self:CanAcceptPeerObservation(observation) then
		return false
	end
	local cap = s.capabilities[name] or {}
	cap.receivedAt, cap.lifetime, cap.raceID, cap.streams = now, nil, raceID, streams == "1"
	cap.direct = direct == "1"
	if not self:CommitPeerObservation(observation, cap, false) then
		return false
	end
	s.capabilities[name] = cap
	if observation.source == "snapshot" then
		self:RememberDirectCommPeer(name, cap.direct, cap.lifetime)
	end
	if not cap.streams then
		s.wanted[name], s.subscribers[name] = nil, nil
	end
	local count, oldest, oldestAt = 0
	for key, cap in pairs(s.capabilities) do
		if not Fresh(now, cap.receivedAt, cap.lifetime or 600) then
			s.capabilities[key] = nil
		else
			count = count + 1
			if not oldest or cap.receivedAt < oldestAt then
				oldest, oldestAt = key, cap.receivedAt
			end
		end
	end
	if count > 512 then
		s.capabilities[oldest] = nil
	end
	return true
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
	return copy
end

local function Send(a, s, name, wire, now)
	if now < s.nextSend then
		return nil
	end
	local sent, reason =
		a:SendTransportNow(wire, "nearby position whisper", { distribution = "WHISPER", target = name }, "nearby")
	if reason == "paced" then
		return nil
	end
	s.nextSend = now + (sent and 0.2 or 5)
	return sent
end

function QT:HandleNearbyStreamMessage(command, payload, sender)
	if command ~= "QTSR" and command ~= "QTSP" and command ~= "QTSX" then
		return false
	end
	if not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 160 or not Enabled(self) then
		return false
	end
	local name = self:NormalizeMemberName(sender)
	local s, now = rawget(self, "nearbyStreamState"), Now(self)
	if not s or not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local token = payload:match("^1,([%w%-]+)$")
	if command == "QTSX" then
		local peer = s.subscribers[name]
		if token and peer and peer.token == token then
			s.subscribers[name] = nil
			return true
		end
		return false
	elseif command == "QTSR" then
		if not token or #token > 60 or not Capability(s, name, now) or not BasePeer(self, name, now) then
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
				s.subscribers[key] = nil
			end
		end
		local peer = s.subscribers[name]
		if peer and Fresh(now, peer.renewedAt, 2) then
			return false
		end
		if not peer or peer.token ~= token then
			peer = { token = token, sequence = 0, lastSent = 0 }
		end
		peer.renewedAt = now
		s.subscribers[name] = peer
		return true
	end
	local seq, stamp, mapID, x, y
	token, seq, stamp, mapID, x, y = payload:match("^1,([%w%-]+),(%d+),(%d+),(%d+),(%d+%.%d+),(%d+%.%d+)$")
	seq, stamp, mapID, x, y = tonumber(seq), tonumber(stamp), tonumber(mapID), tonumber(x), tonumber(y)
	local peer = s.wanted[name]
	if
		not token
		or not peer
		or peer.token ~= token
		or not Fresh(now, peer.requestedAt, LEASE)
		or not seq
		or seq < 1
		or seq > 2147483647
		or seq <= (peer.sequence or 0)
		or not mapID
		or mapID < 1
		or mapID > 1000000
		or not x
		or x > 1
		or not y
		or y > 1
		or not BasePeer(self, name, now)
	then
		return false
	end
	local serverNow = self:GetAnnouncementServerTime()
	if
		not stamp
		or stamp > 99999999999
		or (serverNow and stamp ~= 0 and (serverNow - stamp > 3 or serverNow - stamp < -5))
	then
		return false
	end
	local position = { mapID = mapID, x = x, y = y, name = name }
	local geometry = self:GetLocationPinSurface("minimap")
	if not geometry or not self:ProjectPlayerLocationPin("minimap", position, geometry) then
		s.wanted[name] = nil
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
	peer.sample = { mapID = mapID, x = x, y = y, fromX = fromX, fromY = fromY, at = now, duration = duration }
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
		-- Capability and locale-independent race identity share one tiny optional
		-- metadata packet, rather than adding another heartbeat for each feature.
		local raceID = self.API.GetPlayerRaceID and self.API.GetPlayerRaceID() or 0
		raceID = self:SafeToNumber(raceID) or 0
		self:StageGeographicState("QTCI|1," .. (Enabled(self) and "1" or "0") .. "," .. raceID .. ",1")
		s.nextCapability = now + 20
	end
	if not Enabled(self) then
		s.wanted, s.subscribers = {}, {}
		return
	end
	-- Geometry/ranking at 2 Hz, not once per packet or animation frame.
	if now >= s.nextScan then
		local selected = {}
		for i, row in ipairs(self:GetNearbyStreamCandidates()) do
			if i > MAX_PEERS then
				break
			end
			selected[row.name] = true
			local cap = s.capabilities[row.name]
			if not s.wanted[row.name] and now >= (cap.retryAt or 0) then
				local geo = rawget(self, "geographicCommsState")
				if geo then
					geo.nearbySerial = (geo.nearbySerial or 0) + 1
					s.wanted[row.name] =
						{ token = geo.session .. "-" .. geo.nearbySerial, nextRequest = 0, startedAt = now }
				end
			end
		end
		for name, peer in pairs(s.wanted) do
			if not selected[name] or not Fresh(now, peer.sample and peer.sample.at or peer.startedAt, LEASE) then
				if s.capabilities[name] then
					s.capabilities[name].retryAt = now + 20
				end
				s.wanted[name] = nil
				-- Best effort cancellation; expiry covers throttle, packet loss and logout.
				Send(self, s, name, "QTSX|1," .. peer.token, now)
			end
		end
		for name, peer in pairs(s.subscribers) do
			if not selected[name] or not Fresh(now, peer.renewedAt, LEASE) then
				s.subscribers[name] = nil
			end
		end
		s.nextScan = now + 0.5
	end
	-- Fair oldest-first lease renewals. The same five-packet budget includes controls.
	local requestName, request
	for name, peer in pairs(s.wanted) do
		if
			BasePeer(self, name, now)
			and now >= peer.nextRequest
			and (
				not request
				or peer.nextRequest < request.nextRequest
				or (peer.nextRequest == request.nextRequest and name < requestName)
			)
		then
			requestName, request = name, peer
		end
	end
	if request and now >= s.nextSend then
		-- Install before dispatch: private transports may deliver synchronously.
		local old = request.requestedAt
		request.requestedAt = now
		local sent = Send(self, s, requestName, "QTSR|1," .. request.token, now)
		if sent then
			request.nextRequest = now + 5
		else
			request.requestedAt = old
			if sent == false then
				s.wanted[requestName] = nil
				if s.capabilities[requestName] then
					s.capabilities[requestName].retryAt = now + 20
				end
			end
		end
		return
	end
	if now < s.nextSend or not next(s.subscribers) then
		return
	end
	local location = currentSample or self:ReadLocalPlayerLocation()
	if not location then
		s.subscribers = {}
		return
	end
	local encoded = string.format("%d,%.5f,%.5f", location.mapID, location.x, location.y)
	local target, peer
	for name, candidate in pairs(s.subscribers) do
		if
			BasePeer(self, name, now)
			and (candidate.position ~= encoded or now - candidate.lastSent >= 2)
			and (
				not peer
				or candidate.lastSent < peer.lastSent
				or (candidate.lastSent == peer.lastSent and name < target)
			)
		then
			target, peer = name, candidate
		end
	end
	if peer then
		peer.sequence = peer.sequence + 1
		local wire = "QTSP|1,"
			.. peer.token
			.. ","
			.. peer.sequence
			.. ","
			.. (self:GetAnnouncementServerTime() or 0)
			.. ","
			.. encoded
		local sent = Send(self, s, target, wire, now)
		if sent then
			peer.lastSent, peer.position = now, encoded
		elseif sent == false then
			s.subscribers[target] = nil
		end
	end
end

function QT:RetireNearbyStreamPeer(name)
	local state = rawget(self, "nearbyStreamState")
	if state then
		state.capabilities[name], state.wanted[name], state.subscribers[name] = nil, nil, nil
	end
end

function QT:ResetNearbyStreams()
	self.nearbyStreamState = nil
end
