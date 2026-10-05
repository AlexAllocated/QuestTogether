-- Party identity is advertised with paced presence. Full small-party rosters are
-- fetched only on hover; native group state and received data stay addon-owned.
local QT = _G.QuestTogether
local TTL, CACHE_TTL, REQUEST_TTL = 180, 120, 60
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
local function SendRoster(a, wire, context)
	-- Roster queries are targeted global control messages, not duplicate party
	-- and zone broadcasts. The shared geographic queue paces the reply chunks.
	return a:SendWireMessageToAnnouncementRoutes(wire, context, {
		{ distribution = "CHANNEL", channelName = a.announcementChannelName, requiresChannelJoin = true },
	})
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
function QT:BroadcastPartyVisualMetadata()
	local info = self:GetLocalPartyVisualInfo()
	if not info then
		return false
	end
	local state = self:GetPartyVisualState()
	-- Solo size is already carried by QTVR. Only publish a withdrawal if we
	-- previously advertised a party during this session.
	if info.size == 0 and not state.advertisedGroup then
		return false
	end
	if info.size > 1 then
		state.advertisedGroup = true
	end
	local payload =
		table.concat({ "1", info.size, info.leader or "", info.leaderClass or "", info.revision or "" }, ",")
	return self:SendWireMessageToAnnouncementRoutes("QTPG|" .. payload, "party visual metadata")
end
function QT:HandlePartyVisualMetadata(payload, sender)
	if not Allowed(self) or not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 200 then
		return false
	end
	local size, leader, class, revision = payload:match("^1,(%d+),([^,]*),([^,]*),(%d*)$")
	size = tonumber(size)
	local name = Name(self, sender)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) or not size or size > 40 or size == 1 then
		return false
	end
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
		at = Now(self),
	}
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
	if not self:IsKnownQTPlayer(name) or not Fresh(info, now, TTL) then
		s.peers[name] = nil
		local size = self:GetPlayerPartySize(name)
		return size and { size = size } or nil
	end
	local stats = self:GetPlayerTooltipStats(name)
	if
		stats
		and stats.partySize ~= nil
		and stats.partySize ~= info.size
		and (stats.sampledAt or stats.at or 0) > (info.sampledAt or info.at)
	then
		s.peers[name] = nil
		return { size = stats.partySize }
	end
	local roster = info.key and s.rosters[info.key]
	info.members = Fresh(roster, now, CACHE_TTL) and roster.members or nil
	return info
end
function QT:RequestPartyVisualRoster(sender)
	local name, now = Name(self, sender), Now(self)
	local info = name and self:GetPlayerPartyVisualInfo(name)
	if not info or not info.key or info.size > 5 or info.size < 2 or info.members then
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
	local sent = SendRoster(self, "QPGR|1," .. name .. "," .. id .. "," .. info.revision, "party roster request")
	if not sent then
		s.pending[id] = nil
	end
	return sent
end
function QT:HandlePartyVisualRosterRequest(payload, sender)
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
	for index, member in ipairs(info.members) do
		SendRoster(
			self,
			table.concat({ "QPGM|1", id, revision, index, member.name, member.classFile }, ","),
			"party roster member"
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
