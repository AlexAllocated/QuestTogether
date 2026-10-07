-- Party identity is advertised with paced presence. Full small-party rosters are
-- fetched only on hover; native group state and received data stay addon-owned.
local QT = _G.QuestTogether
local TTL, REQUEST_TTL = 180, 60
local function Now(a)
	return a:SafeToNumber(a.API.GetTime and a.API.GetTime()) or 0
end
local function Allowed(a)
	return a.isEnabled and not a.isLoggingOut and not a:IsRuntimeRestricted()
end
local function Name(a, value)
	if not a:CanAccessValue(value) or type(value) ~= "string" or #value > 120 or value:find("[%c|,]") then
		return nil
	end
	local name = a:NormalizeMemberName(value)
	if name and #name <= 120 then
		return name
	end
end
local function Class(value)
	return type(value) == "string" and #value <= 24 and value:match("^[A-Z]*$") and value or nil
end
local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end
local function Bound(t, limit)
	while Count(t) > limit do
		local oldest, at
		for k, v in pairs(t) do
			if not at or v.at < at then
				oldest, at = k, v.at
			end
		end
		t[oldest] = nil
	end
end
local function Fresh(record, now, ttl)
	return record and now >= record.at and now - record.at < (record.lifetime or ttl)
end
local function SendRoster(a, wire, context, target, direct)
	local routes = direct and { { distribution = "WHISPER", target = target } }
		or a:GetTargetedCommRoutes(target, { { distribution = "CHANNEL", channelName = a.announcementChannelName, requiresChannelJoin = true } })
	return a:SendWireMessageToAnnouncementRoutes(wire, context, routes)
end
local function Revision(leader, members)
	local entries = {}
	for _, member in ipairs(members) do
		entries[#entries + 1] = member.name .. "," .. member.classFile
	end
	table.sort(entries)
	local text, hash = leader .. ";" .. table.concat(entries, ";"), 5381
	for i = 1, #text do
		hash = (hash * 33 + text:byte(i)) % 2147483647
	end
	return tostring(hash)
end
-- Reload metadata retains its own sample time and expiry independently from
-- the position that made it cacheable. No restored entry establishes live QT
-- presence or starts a roster/stream subscription.
local RELOAD_TTL = 180
local function CacheTimes(record, now, wall, ttl)
	if not record or not Fresh(record, now, ttl) then return nil end
	local sampled = record.sampledAt or record.at
	local age = now - sampled
	local remaining = math.min(RELOAD_TTL - age, (record.lifetime or ttl) - (now - record.at))
	if age < 0 or remaining <= 0 then return nil end
	return wall - age, wall + remaining
end
local function RestoreTimes(a, record, now, wall, ttl)
	if type(record) ~= "table" then return nil end
	local sampled, expires = a:SafeToNumber(record.sampledAt), a:SafeToNumber(record.expiresAt)
	if not sampled or sampled < 1000000000 or sampled > wall or wall - sampled >= ttl
		or not expires or expires <= wall or expires > wall + ttl then return nil end
	return now - (wall - sampled), math.min(expires - wall, ttl - (wall - sampled))
end
local function FreshCachedLocation(a, name, now)
	local locations = rawget(a, "playerLocationState")
	local location = locations and locations.peers[name]
	return location and location.cached == true and location.mask ~= 0 and location.receivedAt
		and now >= location.receivedAt and now - location.receivedAt < (location.lifetime or 120)
end

function QT:SavePlayerPartyCacheEntry(name, now, wall)
	local s, presence = rawget(self, "partyVisualState"), rawget(self, "qtPlayerPresenceState")
	local info = s and s.peers[name]
	if not Fresh(info, now, TTL) then info = nil end
	local stats = presence and presence.peerTooltipStats and presence.peerTooltipStats[name]
	if not Fresh(stats, now, TTL) or stats.partySize == nil then stats = nil end
	-- A newer size report supersedes an obsolete party identity, just as it does
	-- in the live tooltip getter. Keep QTVR-only solo/group sizes too.
	if stats and (not info or (stats.partySize ~= info.size
		and (stats.sampledAt or stats.at) > (info.sampledAt or info.at))) then
		info = { size = stats.partySize, at = stats.at, sampledAt = stats.sampledAt, lifetime = stats.lifetime }
	end
	local sampled, expires = CacheTimes(info, now, wall, TTL)
	if not sampled then return nil end
	local result = { size = info.size, sampledAt = sampled, expiresAt = expires }
	if info.key then
		result.leader, result.leaderClass, result.revision = info.leader, info.leaderClass, info.revision
		local roster = s and s.rosters[info.key]
		-- The revision hashes leader, member identities and classes. A fresh
		-- matching revision reconfirms this list without another roster exchange.
		-- Persist that confirmation's sample age, never the current hover time.
		if info.size <= 5 and roster then
			local members = {}
			for i, member in ipairs(roster.members) do
				members[i] = { name = member.name, classFile = member.classFile }
			end
			result.roster = { sampledAt = sampled, expiresAt = expires, members = members }
		end
	end
	return result
end

function QT:RestorePlayerPartyCacheEntry(name, cached, now, wall)
	if not self.isEnabled or self:IsIgnoredPlayerName(name) or self:IsSelfSender(name)
		or not FreshCachedLocation(self, name, now) then return false end
	local sampled, lifetime = RestoreTimes(self, cached, now, wall, RELOAD_TTL)
	local size = type(cached) == "table" and self:SafeToNumber(cached.size)
	if not sampled or not size or size < 0 or size > 40 or size ~= math.floor(size) then return false end
	local leader, class, revision, key
	if cached.leader ~= nil or cached.leaderClass ~= nil or cached.revision ~= nil then
		leader, class, revision = Name(self, cached.leader), Class(cached.leaderClass), cached.revision
		if size < 2 or not leader or not class or type(revision) ~= "string"
			or #revision > 10 or not revision:match("^%d+$") then return false end
		key = leader .. ":" .. revision
	end
	local s, presence = self:GetPartyVisualState(), rawget(self, "qtPlayerPresenceState")
	local current, stats = s.peers[name], presence and presence.peerTooltipStats and presence.peerTooltipStats[name]
	if Fresh(current, now, TTL) or (Fresh(stats, now, TTL) and stats.partySize ~= nil) then return false end
	s.peers[name] = { size = size, leader = leader, leaderClass = class, revision = revision,
		key = key, at = now, sampledAt = sampled, lifetime = lifetime, cached = true }
	Bound(s.peers, 512)
	-- A corrupt/expired member list does not invalidate a separately valid size
	-- or leader. Require the same revision hash used by actual roster responses.
	local roster = cached.roster
	local rosterSampled, rosterLifetime = RestoreTimes(self, roster, now, wall, RELOAD_TTL)
	if key and size <= 5 and rosterSampled and type(roster.members) == "table" and #roster.members == size
		and not s.rosters[key] then
		local members, seen, valid = {}, {}, true
		for i = 1, size do
			local member = roster.members[i]
			local memberName = type(member) == "table" and Name(self, member.name)
			local memberClass = type(member) == "table" and Class(member.classFile)
			if not memberName or not memberClass or seen[memberName] then valid = false; break end
			seen[memberName] = true
			members[i] = { name = memberName, classFile = memberClass }
		end
		if valid and seen[leader] and seen[name] and Revision(leader, members) == revision then
			s.rosters[key] = { at = now, sampledAt = rosterSampled, lifetime = rosterLifetime, members = members }
			Bound(s.rosters, 128)
		end
	end
	return true
end

function QT:GetPartyVisualState()
	local s = rawget(self, "partyVisualState")
	if not s then
		s = { peers = {}, rosters = {}, pending = {}, attempts = {}, replies = {}, sequence = 0 }
		self.partyVisualState = s
	end
	return s
end
function QT:ForgetPartyVisualPeer(name)
	local s = rawget(self, "partyVisualState")
	if not s then
		return
	end
	s.peers[name] = nil
	for id, pending in pairs(s.pending) do
		if pending.name == name then
			s.pending[id] = nil
		end
	end
end
function QT:GetLocalPartyVisualInfo()
	if not Allowed(self) then
		return nil
	end
	local s, now = self:GetPartyVisualState(), Now(self)
	local size = self:GetLocalPartySize()
	if s.localAt and now >= s.localAt and now - s.localAt < 1 and s.localSize == size then
		return s.localInfo
	end
	s.localSize = size
	s.localAt, s.localInfo = now, nil
	if size == 0 then
		s.localInfo = { size = 0 }
		return s.localInfo
	end
	if not size or size < 2 then
		return nil
	end
	local getter = self.API.GetPartyVisualLeaderUnit
	if type(getter) ~= "function" then
		return nil
	end
	local ok, unit = pcall(getter)
	if
		not ok
		or not self:CanAccessValue(unit)
		or type(unit) ~= "string"
		or not (unit == "player" or unit:match("^party[1-4]$") or unit:match("^raid%d+$"))
	then
		return nil
	end
	local leader = Name(self, self:GetUnitFullName(unit))
	local roster, members, foundSelf = rawget(self, "partyMembers"), {}, false
	if not leader or not roster or not roster[leader] then
		return nil
	end
	for name, member in pairs(roster) do
		local full = Name(self, name)
		local class = self:SafeToString(member.classFile, "")
		if not full or not Class(class) then
			return nil
		end
		members[#members + 1] = { name = full, classFile = class }
		if self:IsSelfSender(full) then
			foundSelf = true
		end
	end
	if #members ~= size or not foundSelf then
		return nil
	end
	table.sort(members, function(a, b)
		return a.name < b.name
	end)
	local revision = Revision(leader, members)
	s.localInfo = {
		size = size,
		leader = leader,
		leaderClass = self:SafeToString(roster[leader].classFile, ""),
		revision = revision,
		key = leader .. ":" .. revision,
		members = members,
	}
	return s.localInfo
end
function QT:BuildPartyVisualMetadataPayload()
	local info = self:GetLocalPartyVisualInfo()
	if not info then return nil end
	return table.concat({ "1", info.size, info.leader or "", info.leaderClass or "", info.revision or "" }, ","), info
end

function QT:BroadcastPartyVisualMetadata()
	local payload, info = self:BuildPartyVisualMetadataPayload()
	if not info then
		return false
	end
	local state, now = self:GetPartyVisualState(), Now(self)
	-- Solo size is already carried by QTVR. Only publish a withdrawal if we
	-- previously advertised a party during this session.
	local lifetime = rawget(self, "geographicCommsState") and 600 or TTL
	if info.size == 0 and (not state.advertisedGroup
		or (state.lastGroupAdvertisedAt and (now < state.lastGroupAdvertisedAt or now - state.lastGroupAdvertisedAt >= lifetime))) then
		return false
	end
	if info.size > 1 then
		state.advertisedGroup, state.lastGroupAdvertisedAt = true, now
	end
	return self:SendWireMessageToAnnouncementRoutes("QTPG|" .. payload, "party visual metadata")
end
function QT:HandlePartyVisualMetadata(payload, sender, sampleAge, source)
	if not Allowed(self) or not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 200 then
		return false
	end
	local size, leader, class, revision = payload:match("^1,(%d+),([^,]*),([^,]*),(%d*)$")
	size = tonumber(size)
	local name = Name(self, sender)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) or not size or size > 40 or size == 1 then
		return false
	end
	local now = Now(self)
	local sampledAt = now - (sampleAge or 0)
	if not self:CanAcceptPeerUpdate(name, "QTPG", sampledAt, source and source.session, source and source.sequence) then return false end
	local previous = self:GetPartyVisualState().peers[name]
	if previous and sampledAt < (previous.sampledAt or previous.at)
		and (not source or previous.manualSnapshot or (previous.sampledAt or previous.at) - sampledAt >= 1) then return false end
	if size == 0 then
		if leader ~= "" or class ~= "" or revision ~= "" then
			return false
		end
	else
		leader = Name(self, leader)
		if not leader or not Class(class) or #revision > 10 or not tonumber(revision) then
			return false
		end
	end
	if not self:RecordQTPlayerPresence(name, true) then
		return false
	end
	local s = self:GetPartyVisualState()
	s.peers[name] = {
		size = size,
		leader = size > 0 and leader or nil,
		leaderClass = class,
		revision = revision,
		key = size > 0 and leader .. ":" .. revision or nil,
		at = now,
		sampledAt = sampledAt,
		lifetime = sampleAge and self:GetGeographicSnapshotLifetime() - sampleAge or nil,
		manualSnapshot = sampleAge ~= nil and source == nil,
	}
	self:RecordPeerUpdate(name, "QTPG", sampledAt, source and source.session, source and source.sequence)
	Bound(s.peers, 512)
	return true
end
function QT:GetPlayerPartyVisualInfo(sender)
	local name = Name(self, sender)
	if not name or not Allowed(self) or self:IsIgnoredPlayerName(name) then
		return nil
	end
	-- Native membership is authoritative for our own party, including non-QT members.
	if self:IsSelfSender(name) or (rawget(self, "partyMembers") or {})[name] then
		local info = self:GetLocalPartyVisualInfo()
		if info then
			return info
		end
	end
	local s, now = self:GetPartyVisualState(), Now(self)
	local info = s.peers[name]
	local stats = self:GetPlayerTooltipStats(name)
	local function Summary(current)
		-- Join availability already carries explicit solo/grouped state, even on
		-- peers that cannot answer hover queries. It cannot supply a member count.
		local joins = rawget(self, "partyJoinState")
		local join = joins and joins.peers[name]
		if not self:IsKnownQTPlayer(name) or not Fresh(join, now, 125)
			or (join.grouped ~= "0" and join.grouped ~= "1") then return current end
		local grouped = join.grouped == "1"
		if current and ((current.size ~= nil and (current.size > 0) == grouped)
			or (current.sampledAt or current.at or 0) >= (join.sampledAt or join.at)) then return current end
		return { size = not grouped and 0 or nil, grouped = grouped,
			at = join.at, sampledAt = join.sampledAt, lifetime = join.lifetime }
	end
	if not (self:IsKnownQTPlayer(name) or (info and info.cached and FreshCachedLocation(self, name, now)))
		or not Fresh(info, now, TTL) then
		s.peers[name] = nil
		local size = self:GetPlayerPartySize(name)
		return Summary(size and { size = size, at = stats and stats.at, sampledAt = stats and stats.sampledAt } or nil)
	end
	if
		stats
		and stats.partySize ~= nil
		and stats.partySize ~= info.size
		and (stats.sampledAt or stats.at or 0) > (info.sampledAt or info.at)
	then
		s.peers[name] = nil
		return Summary({ size = stats.partySize, at = stats.at, sampledAt = stats.sampledAt })
	end
	local roster = info.key and s.rosters[info.key]
	-- Fresh party metadata above confirms this exact membership revision. Keep
	-- the validated list even when its original fetch is older than two minutes;
	-- changed/expired party metadata cannot expose a list from another revision.
	info.members = roster and roster.members or nil
	return Summary(info)
end
function QT:RequestPartyVisualRoster(sender)
	local name, now = Name(self, sender), Now(self)
	local info = name and self:GetPlayerPartyVisualInfo(name)
	if not info or info.cached or not info.key or info.size > 5 or info.size < 2 or info.members then
		return false
	end
	local s = self:GetPartyVisualState()
	for id, p in pairs(s.pending) do
		if now < p.at or now - p.at >= REQUEST_TTL then
			s.pending[id] = nil
		end
	end
	local attempt = s.attempts[info.key]
	if Fresh(attempt, now, REQUEST_TTL) or Count(s.pending) >= 16 then
		return false
	end
	s.attempts[info.key] = { at = now }
	Bound(s.attempts, 128)
	s.sequence = s.sequence + 1
	local random = self.API.Random and self:SafeToNumber(self.API.Random(1, 99999999)) or 1
	local id = math.floor(now * 1000) .. "-" .. math.floor(random or 1) .. "-" .. s.sequence
	s.pending[id] = {
		at = now,
		name = name,
		key = info.key,
		revision = info.revision,
		size = info.size,
		leader = info.leader,
		members = {},
	}
	local sent = SendRoster(self, "QPGR|1," .. name .. "," .. id .. "," .. info.revision, "party roster request", name)
	if not sent then
		s.pending[id] = nil
	end
	return sent
end
function QT:HandlePartyVisualRosterRequest(payload, sender, direct)
	if not Allowed(self) or not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 240 then
		return false
	end
	local target, id, revision = payload:match("^1,([^,]+),([%d%-]+),(%d+)$")
	local name = Name(self, sender)
	if
		not id
		or #id > 48
		or #revision > 10
		or not Name(self, target)
		or not self:IsSelfSender(target)
		or not name
		or self:IsSelfSender(name)
		or self:IsIgnoredPlayerName(name)
	then
		return false
	end
	local info = self:GetLocalPartyVisualInfo()
	if not info or info.size < 2 or info.size > 5 or info.revision ~= revision then
		return false
	end
	local s, now = self:GetPartyVisualState(), Now(self)
	-- Bound amplification even if many clients hover or a sender varies IDs.
	if Fresh(s.replies[name], now, 20) or (s.lastReply and now - s.lastReply < 5) then
		return false
	end
	s.lastReply, s.replies[name] = now, { at = now }
	Bound(s.replies, 128)
	self:RecordQTPlayerPresence(name, true)
	if direct then self:RememberDirectCommPeer(name, true) end
	for index, member in ipairs(info.members) do
		SendRoster(
			self,
			table.concat({ "QPGM|1", id, revision, index, member.name, member.classFile }, ","),
			"party roster member", name, direct
		)
	end
	return true
end
function QT:HandlePartyVisualRosterMember(payload, sender)
	if not Allowed(self) or not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 240 then
		return false
	end
	local id, revision, index, member, class = payload:match("^1,([%d%-]+),(%d+),(%d+),([^,]+),([^,]*)$")
	local name = Name(self, sender)
	if not id or #id > 48 or #revision > 10 or not name or self:IsIgnoredPlayerName(name) then
		return false
	end
	local s, now = self:GetPartyVisualState(), Now(self)
	local p = s.pending[id]
	local info = self:GetPlayerPartyVisualInfo(name)
	index, member = tonumber(index), Name(self, member)
	if
		not Fresh(p, now, REQUEST_TTL)
		or p.name ~= name
		or p.revision ~= revision
		or not info
		or p.key ~= info.key
		or not index
		or index < 1
		or index > p.size
		or not member
		or not Class(class)
	then
		return false
	end
	local previous = p.members[index]
	if previous then
		return previous.name == member and previous.classFile == class
	end
	for _, existing in pairs(p.members) do
		if existing.name == member then
			return false
		end
	end
	p.members[index] = { name = member, classFile = class }
	if Count(p.members) == p.size then
		local hasLeader, hasSender = false, false
		for _, m in ipairs(p.members) do
			hasLeader = hasLeader or m.name == p.leader
			hasSender = hasSender or m.name == name
		end
		if not hasLeader or not hasSender or Revision(p.leader, p.members) ~= revision then
			s.pending[id] = nil
			return false
		end
		s.rosters[p.key] = { at = now, members = p.members }
		Bound(s.rosters, 128)
		s.pending[id] = nil
	end
	return true
end

-- The transport may hold a chunk while waiting for tokens. Do not deliver an
-- obsolete roster or ask about a party that changed while the request waited.
function QT:IsPartyVisualQueuedWireCurrent(wire)
	local command, payload = wire:match("^([^|]+)|(.*)$")
	if command == "QPGR" then
		local id = payload:match("^1,[^,]+,([%d%-]+),")
		local state = rawget(self, "partyVisualState")
		local pending = state and state.pending[id]
		if not Fresh(pending, Now(self), REQUEST_TTL) then
			return false
		end
		local info = self:GetPlayerPartyVisualInfo(pending.name)
		return info and info.key == pending.key or false
	elseif command == "QPGM" then
		local revision = payload:match("^1,[%d%-]+,(%d+),")
		local info = self:GetLocalPartyVisualInfo()
		return info and info.revision == revision or false
	end
	return true
end
