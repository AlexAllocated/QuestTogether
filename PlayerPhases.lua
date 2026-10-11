-- Experimental, open-world layer evidence. GUID routing keys are heuristics,
-- not authoritative phase IDs. Absence of visible units is NEVER a mismatch.
local QT = _G.QuestTogether
local TTL, TRANSIT, MAX_PEERS = 30, 5, 128
local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end
local function Fresh(now, at, ttl)
	return at and now >= at and now - at < ttl
end
local function Enabled(a)
	return a.isEnabled
		and not a.isLoggingOut
		and a:GetOption("experimentalLayerDetection") == true
		and a:CanPublishPlayerLocation()
		and not a:IsRuntimeRestricted()
		and not a:IsRuntimeRestrictionTypeActive("chat")
		and a.API
		and type(a.API.IsInInstance) == "function"
		and a.API.IsInInstance() == false
end
local function State(a)
	local s = rawget(a, "playerPhaseState")
	if not s then
		s = { peers = {}, attempts = {}, replies = {}, nextScan = 0 }
		a.playerPhaseState = s
	end
	return s
end
local function PlayerGUID(g)
	return type(g) == "string" and #g <= 48 and g:match("^Player%-%d+%-%x+$") ~= nil
end
local function Key(g)
	if type(g) ~= "string" or #g > 100 then
		return
	end
	local server, instance, zone = g:match("^Creature%-0%-(%d+)%-(%d+)%-(%d+)%-%d+%-%x+$")
	if server and #server <= 10 and #instance <= 10 and #zone <= 10 then
		return server .. ":" .. instance .. ":" .. zone
	end
end
local function Prune(t, now)
	local count, oldest, at = 0
	for name, row in pairs(t) do
		if not Fresh(now, row.at, 120) then
			t[name] = nil
		else
			count = count + 1
			if not at or row.at < at then
				oldest, at = name, row.at
			end
		end
	end
	if count >= MAX_PEERS and oldest then
		t[oldest] = nil
	end
end

-- Read-only native seam. Never target a unit, change CVars, or retain frames.
function QT:GetPlayerPhaseObservation()
	local map = self:SafeToNumber(self.API.GetPlayerMapID("player"))
	local guid = self.API.UnitGUID("player")
	if not map or not self:CanAccessValue(guid) or not PlayerGUID(guid) then
		return
	end
	local result = { map = map, guid = guid, players = {}, npcs = {} }
	local tokens = { "target", "mouseover", "focus" }
	for _, frame in ipairs(self.API.GetNamePlates()) do
		if #tokens >= 131 then
			break
		end
		local token = self:GetAccessibleFrameMember(frame, "namePlateUnitToken")
		if self:CanAccessValue(token) and type(token) == "string" and token:match("^nameplate%d+$") then
			tokens[#tokens + 1] = token
		end
	end
	for _, token in ipairs(tokens) do
		local unit = self.API.GetLayerObservationUnit(token)
		if unit then
			if PlayerGUID(unit.guid) then
				result.players[unit.guid] = true
			elseif not unit.controlled and Key(unit.guid) then
				result.npcs[unit.guid] = true
			end
		end
	end
	return result
end

-- Geometry supplies candidates, not targeting range or proof of visibility.
function QT:GetPlayerPhaseCandidates()
	local geometry = self:GetLocationPinSurface("minimap")
	if not geometry then
		return {}
	end
	local result, now = {}, Now(self)
	for _, row in ipairs(self:GetVisiblePlayerLocations("minimap")) do
		-- Cached map dots may outlive their actual proximity. Require a recent
		-- position before using geometry to choose a comparison partner.
		if
			Fresh(now, row.sampledAt or row.receivedAt, TTL)
			and not self:IsSelfSender(row.name)
			and not self:IsIgnoredPlayerName(row.name)
		then
			local x, y = self:ProjectPlayerLocationPin("minimap", row, geometry)
			if x and y then
				result[#result + 1] =
					{ name = row.name, distance = (x - geometry.width / 2) ^ 2 + (y - geometry.height / 2) ^ 2 }
			end
		end
	end
	table.sort(result, function(a, b)
		return a.distance < b.distance
	end)
	return result
end

function QT:UpdatePlayerPhaseObservations()
	if not Enabled(self) then
		self:ResetPlayerPhases()
		return
	end
	local s, now = State(self), Now(self)
	if now < s.nextScan and now >= s.nextScan - 1 then
		return
	end
	s.nextScan = now + 1
	local observation = self:GetPlayerPhaseObservation()
	if not observation then
		s.observation, s.candidate = nil, nil
		return
	end
	if s.observation and s.observation.map ~= observation.map then
		self:ResetPlayerPhases()
		s = State(self)
		s.nextScan = now + 1
	end
	local key, count, mixed = nil, 0, false
	for guid in pairs(observation.npcs) do
		local current = Key(guid)
		if current then
			if key and key ~= current then
				mixed = true
			end
			key, count = current, count + 1
		end
	end
	-- Two distinct ordinary NPCs, consistent across scans, in Forever only.
	if not self:UsesRegionalPlayerNames() or mixed or count < 2 then
		key = nil
	end
	if key and s.candidate and s.candidate.key == key and Fresh(now, s.candidate.last, 3) then
		s.candidate.last = now
		if now - s.candidate.at >= 2 then
			observation.key = key
		end
	else
		s.candidate = key and { key = key, at = now, last = now } or nil
	end
	observation.at = now
	if s.observation and s.observation.key ~= observation.key then
		s.peers = {}
		-- A local evidence change is not a failed/unsupported peer. Retire
		-- the nonce and allow a fresh probe after the global pacing interval.
		for _, attempt in pairs(s.attempts) do
			self:CancelCommRequest(attempt.id, "cancelled")
		end
		s.attempts = {}
	end
	s.observation = observation
	s.nearby = {}
	local candidates = self:GetPlayerPhaseCandidates()
	for _, row in ipairs(candidates) do
		s.nearby[row.name] = true
	end
	for _, t in ipairs({ s.peers, s.attempts, s.replies }) do
		Prune(t, now)
	end
	-- Walk past cooling-down/older clients. The global limiter still permits
	-- at most one outgoing probe every two seconds.
	for index = 1, #candidates do
		if self:RequestPlayerPhaseComparison(candidates[index].name) then
			break
		end
	end
end

local function Eligible(a, name)
	local s = rawget(a, "playerPhaseState")
	return s
		and s.observation
		and s.nearby
		and s.nearby[name]
		and Enabled(a)
		and Fresh(Now(a), s.observation.at, 2)
		and not a:IsIgnoredPlayerName(name)
		and not a:IsSelfSender(name)
end
local function Record(s, kind, id)
	local o = s.observation
	local record = { requestId = id, kind = kind, mapID = o.map }
	if kind == "R" then
		record.routingKey, record.guid, record.players = o.key, o.guid, {}
		local players = {}
		for guid in pairs(o.players) do
			if guid ~= o.guid then
				players[#players + 1] = guid
			end
		end
		table.sort(players)
		for index = 1, math.min(8, #players) do
			record.players[index] = { guid = players[index] }
		end
	end
	return record
end
local function Current(a, s, name, row, replying)
	return rawget(a, "playerPhaseState") == s
		and Eligible(a, name)
		and (replying and s.replies[name] or s.attempts[name]) == row
		and Fresh(Now(a), row.at, TRANSIT)
		and row.map == s.observation.map
		and row.key == s.observation.key
		and (replying or row.pending == true)
end
function QT:RequestPlayerPhaseComparison(sender)
	local name = self:NormalizeMemberName(sender)
	if not name or not Eligible(self, name) then
		return false
	end
	local s, now = State(self), Now(self)
	local previous = s.attempts[name]
	if Fresh(now, s.lastRequest, 2) or (previous and Fresh(now, previous.at, previous.success and 30 or 120)) then
		return false
	end
	local id = self:GetCommunicationSession() .. "-phase-" .. self:NextCommunicationSequence()
	local attempt = { at = now, id = id, map = s.observation.map, key = s.observation.key, pending = true }
	s.attempts[name], s.lastRequest = attempt, now
	local ok = self:Request("QTPH", Record(s, "Q", id), { { distribution = "WHISPER", target = name } }, {
		owner = s,
		expires = now + TRANSIT,
		publishesLocation = true,
		isCurrent = function()
			return Current(self, s, name, attempt, false)
		end,
		onResponse = function(data, origin)
			return self:HandlePlayerPhaseMessage(data, origin)
		end,
		onComplete = function(sent)
			if not sent and s.attempts[name] == attempt then
				attempt.pending = false
				self:CancelCommRequest(id, "cancelled")
			end
		end,
		onExpire = function()
			if s.attempts[name] == attempt then
				attempt.pending = false
			end
		end,
	})
	if not ok then
		attempt.pending = false
	end
	return ok
end
local function Validate(data)
	if
		type(data) ~= "table"
		or type(data.requestId) ~= "string"
		or #data.requestId > 80
		or not data.requestId:match("^[%w%-]+$")
		or (data.kind ~= "Q" and data.kind ~= "R")
		or type(data.mapID) ~= "number"
		or data.mapID ~= math.floor(data.mapID)
		or data.mapID < 1
		or data.mapID > 1000000
	then
		return
	end
	local row = { kind = data.kind, id = data.requestId, map = data.mapID }
	if row.kind == "Q" then
		return row
	end
	if
		not PlayerGUID(data.guid)
		or (data.routingKey ~= nil and (type(data.routingKey) ~= "string" or #data.routingKey > 32 or not data.routingKey:match(
			"^%d+:%d+:%d+$"
		)))
		or type(data.players) ~= "table"
		or #data.players > 8
	then
		return
	end
	row.key, row.guid, row.players = data.routingKey, data.guid, {}
	for _, entry in ipairs(data.players) do
		if type(entry) ~= "table" or not PlayerGUID(entry.guid) or row.players[entry.guid] then
			return
		end
		row.players[entry.guid] = true
	end
	return row
end
function QT:HandlePlayerPhaseMessage(data, sender)
	local name = self:NormalizeMemberName(sender)
	if not name or not Eligible(self, name) then
		return false
	end
	local row = Validate(data)
	local s, now = State(self), Now(self)
	if not row or row.map ~= s.observation.map then
		return false
	end
	if row.kind == "Q" then
		local previous = s.replies[name]
		if Fresh(now, s.lastReply, 2) or (previous and Fresh(now, previous.at, 25)) then
			return false
		end
		local reply = { at = now, id = row.id, map = row.map, key = s.observation.key }
		s.replies[name], s.lastReply = reply, now
		return self:Respond("QTPH", Record(s, "R", row.id), { { distribution = "WHISPER", target = name } }, {
			owner = s,
			expires = now + TRANSIT,
			publishesLocation = true,
			isCurrent = function()
				return Current(self, s, name, reply, true)
			end,
		})
	end
	local attempt = s.attempts[name]
	if not attempt or not Current(self, s, name, attempt, false) or attempt.id ~= row.id then
		return false
	end
	attempt.pending, attempt.success = false, true
	self:CancelCommRequest(row.id, "complete")
	row.at, row.localKey = now, s.observation.key
	s.peers[name] = row
	return true
end
function QT:GetPlayerPhaseStatus(name)
	if not Eligible(self, name) then
		return
	end
	local s, now = State(self), Now(self)
	local peer, own = s.peers[name], s.observation
	if not peer or not Fresh(now, peer.at, TTL) or peer.map ~= own.map or peer.localKey ~= own.key then
		return
	end
	-- Positive visibility overrides the NPC heuristic, including quest phasing.
	if own.players[peer.guid] or peer.players[own.guid] then
		return "visible"
	end
	for guid in pairs(peer.players) do
		if own.players[guid] then
			return "shared"
		end
	end
	if own.key and peer.key and own.key ~= peer.key then
		return "different"
	end
	-- Matching routing keys cannot rule out a separate quest phase.
end

function QT:RetirePlayerPhasePeer(name)
	local state = rawget(self, "playerPhaseState")
	if state then
		local attempt = state.attempts[name]
		state.peers[name], state.attempts[name], state.replies[name] = nil, nil, nil
		if attempt then
			self:CancelCommRequest(attempt.id, "cancelled")
		end
	end
end

function QT:ResetPlayerPhases()
	local state = rawget(self, "playerPhaseState")
	self.playerPhaseState = nil
	if state then
		self:CancelTransportOwner(state)
		for _, attempt in pairs(state.attempts) do
			self:CancelCommRequest(attempt.id, "cancelled")
		end
	end
end
