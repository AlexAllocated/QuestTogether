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
local function Bound(t, limit, remove)
	while Count(t) > limit do
		local oldest, at
		for k, v in pairs(t) do
			if not at or v.at < at then
				oldest, at = k, v.at
			end
		end
		if remove then remove(oldest, t[oldest]) end
		t[oldest] = nil
	end
end
-- Membership indexes point at accepted source records. They never turn a
-- teammate's report into a new observation or presence for another player.
local function RemoveMembershipSource(s, name)
	local indexed = s.sources and s.sources[name]
	for member in pairs(indexed and indexed.names or {}) do
		local sources = s.memberships and s.memberships[member]
		if sources then
			sources[name] = nil
			if not next(sources) then s.memberships[member] = nil end
		end
	end
	if s.sources then s.sources[name] = nil end
end
local function IndexMembershipSource(s, name, info)
	RemoveMembershipSource(s, name)
	if not info or not info.key then return end
	s.sources, s.memberships = s.sources or {}, s.memberships or {}
	local names = { [name] = true }
	if info.leader then names[info.leader] = true end
	local roster = s.rosters[info.key]
	for _, member in ipairs(roster and roster.members or {}) do names[member.name] = true end
	s.sources[name] = { record = info, names = names }
	for member in pairs(names) do
		s.memberships[member] = s.memberships[member] or {}
		s.memberships[member][name] = info
	end
end
local function ReindexParty(s, key)
	for name, info in pairs(s.peers) do
		if info.key == key then IndexMembershipSource(s, name, info) end
	end
end
local function BoundPeers(s)
	Bound(s.peers, 512, function(name) RemoveMembershipSource(s, name) end)
end
local function StoreRoster(s, key, roster)
	if s.rosters[key] then roster.invalidatedAt = s.rosters[key].invalidatedAt end
	s.rosters[key] = roster
	ReindexParty(s, key)
	Bound(s.rosters, 128, function(oldKey)
		s.rosters[oldKey] = nil
		ReindexParty(s, oldKey)
	end)
end
local function RetireMembershipProof(s, info, sampledAt)
	local roster = s.rosters[info.key]
	if roster then roster.invalidatedAt = math.max(roster.invalidatedAt or sampledAt, sampledAt) end
	for _, record in pairs(s.peers) do
		if record.key == info.key and (record.sampledAt or record.at) < sampledAt then
			record.membershipInvalidated = true
			record.membershipInvalidatedAt = math.max(record.membershipInvalidatedAt or sampledAt, sampledAt)
		end
	end
end
local function InvalidateMemberships(s, name, current)
	local seen = {}
	for _, info in pairs(s.memberships and s.memberships[name] or {}) do
		if not seen[info.key] and (current.sampledAt or current.at) > (info.sampledAt or info.at)
			and (current.key and current.key ~= info.key or current.size ~= nil and current.size ~= info.size) then
			seen[info.key] = true
			RetireMembershipProof(s, info, current.sampledAt or current.at)
		end
	end
end
local function Fresh(record, now, ttl)
	return record and now >= record.at and now - record.at < (record.lifetime or ttl)
end
-- Other metadata owners call this only after committing a size/solo fact.
-- Retire disproved proofs now, even if no tooltip is open before it expires.
function QT:InvalidatePartyVisualMembership(sender, size, sampledAt)
	local state, name = rawget(self, "partyVisualState"), Name(self, sender)
	size, sampledAt = self:SafeToNumber(size), self:SafeToNumber(sampledAt)
	local now = Now(self)
	if not state or not name or not self.isEnabled or self.isLoggingOut or self:IsIgnoredPlayerName(name)
		or not size or size < 0 or size > 40 or size ~= math.floor(size)
		or not sampledAt or sampledAt > now + 1 or now - sampledAt >= 600 then return end
	InvalidateMemberships(state, name, { size = size, sampledAt = sampledAt })
end
local function PendingFresh(a, id, pending)
	if not pending then
		return false
	end
	local now = Now(a)
	local deadline = a:GetCommunicationRequestDeadline(id) or (pending.at + REQUEST_TTL)
	return now >= pending.at and now < deadline
end
local function CancelPending(a, id, pending, reason)
	a:CancelCommRequest(id, reason)
	a:CancelCommunicationOwner(pending, reason)
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
local PartyRevisionCurrent
local function CacheTimes(record, now, wall, ttl)
	if not record or not Fresh(record, now, ttl) then
		return nil
	end
	local sampled = record.sampledAt or record.at
	local age = now - sampled
	local remaining = math.min(RELOAD_TTL - age, (record.lifetime or ttl) - (now - record.at))
	if age < 0 or remaining <= 0 then
		return nil
	end
	return wall - age, wall + remaining
end
local function RestoreTimes(a, record, now, wall, ttl)
	if type(record) ~= "table" then
		return nil
	end
	local sampled, expires = a:SafeToNumber(record.sampledAt), a:SafeToNumber(record.expiresAt)
	if
		not sampled
		or sampled < 1000000000
		or sampled > wall
		or wall - sampled >= ttl
		or not expires
		or expires <= wall
		or expires > wall + ttl
	then
		return nil
	end
	return now - (wall - sampled), math.min(expires - wall, ttl - (wall - sampled))
end
local function FreshCachedLocation(a, name, now)
	local locations = rawget(a, "playerLocationState")
	local location = locations and locations.peers[name]
	return location
		and location.cached == true
		and location.mask ~= 0
		and location.receivedAt
		and now >= location.receivedAt
		and now - location.receivedAt < (location.lifetime or 120)
end

function QT:SavePlayerPartyCacheEntry(name, now, wall)
	local s, presence = rawget(self, "partyVisualState"), rawget(self, "qtPlayerPresenceState")
	local info = s and s.peers[name]
	if not Fresh(info, now, TTL) then
		info = nil
	end
	local stats = presence and presence.peerTooltipStats and presence.peerTooltipStats[name]
	if not Fresh(stats, now, TTL) or stats.partySize == nil then
		stats = nil
	end
	-- A newer size report supersedes an obsolete party identity, just as it does
	-- in the live tooltip getter. Keep QTVR-only solo/group sizes too.
	if
		stats
		and (not info or (stats.partySize ~= info.size and (stats.sampledAt or stats.at) > (info.sampledAt or info.at)))
	then
		info = { size = stats.partySize, at = stats.at, sampledAt = stats.sampledAt, lifetime = stats.lifetime }
	end
	if info and info.key and not PartyRevisionCurrent(self, s, info, now) then
		info = { size = info.size, at = info.at, sampledAt = info.sampledAt, lifetime = info.lifetime }
	end
	local sampled, expires = CacheTimes(info, now, wall, TTL)
	if not sampled then
		return nil
	end
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
	if
		not self.isEnabled
		or self:IsIgnoredPlayerName(name)
		or self:IsSelfSender(name)
		or not FreshCachedLocation(self, name, now)
	then
		return false
	end
	local sampled, lifetime = RestoreTimes(self, cached, now, wall, RELOAD_TTL)
	local size = type(cached) == "table" and self:SafeToNumber(cached.size)
	if not sampled or not size or size < 0 or size > 40 or size ~= math.floor(size) then
		return false
	end
	local leader, class, revision, key
	if cached.leader ~= nil or cached.leaderClass ~= nil or cached.revision ~= nil then
		leader, class, revision = Name(self, cached.leader), Class(cached.leaderClass), cached.revision
		if
			size < 2
			or not leader
			or not class
			or type(revision) ~= "string"
			or #revision > 10
			or not revision:match("^%d+$")
		then
			return false
		end
		key = leader .. ":" .. revision
	end
	local s, presence = self:GetPartyVisualState(), rawget(self, "qtPlayerPresenceState")
	local current, stats = s.peers[name], presence and presence.peerTooltipStats and presence.peerTooltipStats[name]
	if Fresh(current, now, TTL) or (Fresh(stats, now, TTL) and stats.partySize ~= nil) then
		return false
	end
	s.peers[name] = {
		size = size,
		leader = leader,
		leaderClass = class,
		revision = revision,
		key = key,
		at = now,
		sampledAt = sampled,
		lifetime = lifetime,
		cached = true,
	}
	IndexMembershipSource(s, name, s.peers[name])
	BoundPeers(s)
	-- A corrupt/expired member list does not invalidate a separately valid size
	-- or leader. Require the same revision hash used by actual roster responses.
	local roster = cached.roster
	local rosterSampled, rosterLifetime = RestoreTimes(self, roster, now, wall, RELOAD_TTL)
	if
		key
		and size <= 5
		and rosterSampled
		and type(roster.members) == "table"
		and #roster.members == size
		and not s.rosters[key]
	then
		local members, seen, valid = {}, {}, true
		for i = 1, size do
			local member = roster.members[i]
			local memberName = type(member) == "table" and Name(self, member.name)
			local memberClass = type(member) == "table" and Class(member.classFile)
			if not memberName or not memberClass or seen[memberName] then
				valid = false
				break
			end
			seen[memberName] = true
			members[i] = { name = memberName, classFile = memberClass }
		end
		if valid and seen[leader] and seen[name] and Revision(leader, members) == revision then
			StoreRoster(s, key, { at = now, sampledAt = rosterSampled, lifetime = rosterLifetime, members = members })
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
	if Fresh(s.peers[name], Now(self), TTL) then InvalidateMemberships(s, name, s.peers[name]) end
	s.peers[name] = nil
	RemoveMembershipSource(s, name)
	if s.memberships then s.memberships[name] = nil end
	for id, pending in pairs(s.pending) do
		if pending.name == name then
			s.pending[id] = nil
			self:CancelCommRequest(id, "cancelled")
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
function QT:BuildPartyVisualMetadata()
	local info = self:GetLocalPartyVisualInfo()
	if not info then
		return nil
	end
	return { size = info.size, leader = info.leader, leaderClass = info.leaderClass, revision = info.revision }, info
end

function QT:RecordPartyVisualPublication(record)
	local state = rawget(self, "partyVisualState")
	if not state or type(record) ~= "table" or type(record.size) ~= "number" or record.size <= 1 then
		return
	end
	local current = self:GetLocalPartyVisualInfo()
	if current and current.size == record.size and current.revision == record.revision then
		state.advertisedGroup, state.lastGroupAdvertisedAt = true, Now(self)
	end
end

function QT:BroadcastPartyVisualMetadata()
	local record, info = self:BuildPartyVisualMetadata()
	if not info then
		return false
	end
	local state, now = self:GetPartyVisualState(), Now(self)
	local lifetime = rawget(self, "geographicCommsState") and 600 or TTL
	if
		info.size == 0
		and (
			not state.advertisedGroup
			or (
				state.lastGroupAdvertisedAt
				and (now < state.lastGroupAdvertisedAt or now - state.lastGroupAdvertisedAt >= lifetime)
			)
		)
	then
		return false
	end
	local revision, roster = info.revision, self:GetPartyRosterFingerprint()
	return self:Publish("QTPG", record, nil, {
		owner = state,
		isCurrent = function()
			local current = self:GetLocalPartyVisualInfo()
			return rawget(self, "partyVisualState") == state
				and Allowed(self)
				and roster == self:GetPartyRosterFingerprint()
				and current ~= nil
				and current.size == info.size
				and current.revision == revision
		end,
		onComplete = function(sent)
			if sent and rawget(self, "partyVisualState") == state then
				self:RecordPartyVisualPublication(record)
			end
		end,
	})
end
function QT:HandlePartyVisualMetadata(data, sender, observation)
	if not Allowed(self) or type(data) ~= "table" then
		return false
	end
	local size = self:SafeToNumber(data.size)
	local leader, class, revision = data.leader or "", data.leaderClass or "", data.revision or ""
	local name = Name(self, sender)
	if
		not name
		or self:IsSelfSender(name)
		or self:IsIgnoredPlayerName(name)
		or not size
		or size < 0
		or size > 40
		or size == 1
		or size ~= math.floor(size)
	then
		return false
	end
	local now = Now(self)
	observation = self:ResolvePeerObservation(name, "QTPG", observation)
	if not self:CanAcceptPeerObservation(observation) then
		return false
	end
	local sampledAt = observation.sampledAt
	local source = observation.source ~= "diagnostic" and observation or nil
	local previous = self:GetPartyVisualState().peers[name]
	if
		previous
		and sampledAt < (previous.sampledAt or previous.at)
		and (not source or previous.manualSnapshot or (previous.sampledAt or previous.at) - sampledAt >= 1)
	then
		return false
	end
	if size == 0 then
		if leader ~= "" or class ~= "" or revision ~= "" then
			return false
		end
	else
		leader = Name(self, leader)
		if
			not leader
			or not Class(class)
			or type(revision) ~= "string"
			or #revision > 10
			or not revision:match("^%d+$")
		then
			return false
		end
	end
	if not self:CanRecordPeerPresence(name, observation) then
		return false
	end
	local s = self:GetPartyVisualState()
	local record = {
		size = size,
		leader = size > 0 and leader or nil,
		leaderClass = class,
		revision = revision,
		key = size > 0 and leader .. ":" .. revision or nil,
		at = now,
		sampledAt = sampledAt,
		lifetime = observation.expiresAt - now,
		manualSnapshot = observation.manual == true,
	}
	if previous and previous.key == record.key and previous.membershipInvalidatedAt
		and sampledAt <= previous.membershipInvalidatedAt then
		record.membershipInvalidated, record.membershipInvalidatedAt = true, previous.membershipInvalidatedAt
	end
	if not self:CommitPeerObservation(observation, record, true) then
		return false
	end
	InvalidateMemberships(s, name, record)
	s.peers[name] = record
	IndexMembershipSource(s, name, record)
	BoundPeers(s)
	return true
end
local function Sample(info)
	return info and (info.sampledAt or info.at) or 0
end
local function DirectPartyEvidence(a, s, name, now)
	local info = s.peers[name]
	local known = a:IsKnownQTPlayer(name)
	if not (known or info and info.cached and FreshCachedLocation(a, name, now)) or not Fresh(info, now, TTL) then
		if info then s.peers[name] = nil; RemoveMembershipSource(s, name) end
		info = nil
	end
	local stats = a:GetPlayerTooltipStats(name)
	if stats and stats.partySize ~= nil and (not info or stats.partySize ~= info.size and Sample(stats) > Sample(info)) then
		info = { size = stats.partySize, at = stats.at, sampledAt = stats.sampledAt, lifetime = stats.lifetime }
	elseif not info then
		local size = a:GetPlayerPartySize(name)
		if size ~= nil then info = { size = size, at = stats and stats.at, sampledAt = stats and stats.sampledAt } end
	end
	local joins = rawget(a, "partyJoinState")
	local join = joins and joins.peers[name]
	if known and Fresh(join, now, 125) and (join.grouped == "0" or join.grouped == "1") then
		local grouped = join.grouped == "1"
		if not info or not (info.size ~= nil and (info.size > 0) == grouped) and Sample(join) > Sample(info) then
			info = { size = not grouped and 0 or nil, grouped = grouped,
				at = join.at, sampledAt = join.sampledAt, lifetime = join.lifetime }
		end
	end
	return info
end
PartyRevisionCurrent = function(a, s, info, now)
	local roster = s.rosters[info.key]
	if info.membershipInvalidated or roster and roster.invalidatedAt and Sample(info) <= roster.invalidatedAt then return false end
	local function Conflicts(name)
		if not name or a:IsIgnoredPlayerName(name) then return false end
		local current = DirectPartyEvidence(a, s, name, now)
		if current and Sample(current) > Sample(info)
			and (current.key and current.key ~= info.key or current.size ~= nil and current.size ~= info.size) then
			RetireMembershipProof(s, info, Sample(current))
			return true
		end
		return false
	end
	-- A newer report from the same party, or from a listed member who has
	-- moved/left, invalidates the older shared membership for every consumer.
	if Conflicts(info.leader) then return false end
	for name, record in pairs(s.memberships and s.memberships[info.leader] or {}) do
		if s.peers[name] == record and record.leader == info.leader and record.key ~= info.key
			and not a:IsIgnoredPlayerName(name) then
			local current = DirectPartyEvidence(a, s, name, now)
			if current and current.key and Sample(current) > Sample(info) then
				RetireMembershipProof(s, info, Sample(current))
				return false
			end
		end
	end
	for _, member in ipairs(roster and roster.members or {}) do
		if Conflicts(member.name) then return false end
	end
	return true
end
local function KnownPartyMembers(a, s, info, now)
	local names, members = {}, {}
	local function Add(name, class)
		if not name or names[name] or a:IsIgnoredPlayerName(name) then return end
		names[name] = true
		members[#members + 1] = { name = name, classFile = Class(class) or "" }
	end
	Add(info.leader, info.leaderClass)
	-- Sources indexed under the leader include every direct reporter for this
	-- party, without walking all peer records or querying another resolver.
	for name, record in pairs(s.memberships and s.memberships[info.leader] or {}) do
		if s.peers[name] == record and record.key == info.key and not a:IsIgnoredPlayerName(name) then
			local current = DirectPartyEvidence(a, s, name, now)
			if current and not current.membershipInvalidated and current.key == info.key then Add(name) end
		end
	end
	table.sort(members, function(left, right)
		if (left.name == info.leader) ~= (right.name == info.leader) then return left.name == info.leader end
		return left.name < right.name
	end)
	while #members > info.size do table.remove(members) end
	for _, member in ipairs(members) do
		if member.classFile == "" then
			local row = a:GetFreshPlayerLocation(member.name) or { name = member.name }
			member.classFile = Class(a:GetPlayerDetailsTooltipRow(row).classFile) or ""
		end
	end
	return members
end
function QT:GetPlayerPartyVisualInfo(sender)
	local name = Name(self, sender)
	if not name or not Allowed(self) or self:IsIgnoredPlayerName(name) then return nil end
	-- Native membership is authoritative for our own party, including non-QT members.
	if self:IsSelfSender(name) or (rawget(self, "partyMembers") or {})[name] then
		local localInfo = self:GetLocalPartyVisualInfo()
		if localInfo then return localInfo end
	end
	local s, now = self:GetPartyVisualState(), Now(self)
	local direct = DirectPartyEvidence(self, s, name, now)
	local raw = s.peers[name]
	if raw and (not s.sources or not s.sources[name] or s.sources[name].record ~= raw) then
		IndexMembershipSource(s, name, raw)
	end
	local info, source = direct, name
	-- A roster cannot establish live presence, and removing a subject's index
	-- on departure/ignore prevents old surviving teammate lists reviving it.
	if self:IsKnownQTPlayer(name) or FreshCachedLocation(self, name, now) then
		for reporter, record in pairs(s.memberships and s.memberships[name] or {}) do
			if reporter ~= name and s.peers[reporter] == record and not self:IsIgnoredPlayerName(reporter) then
				local candidate = DirectPartyEvidence(self, s, reporter, now)
				if candidate and not candidate.membershipInvalidated and candidate.key and candidate.key == record.key
					and self:CanAcceptPeerUpdate(name, "QTPG", Sample(candidate))
					and (not direct or Sample(candidate) > Sample(direct))
					and (not info or Sample(candidate) > Sample(info)
						or Sample(candidate) == Sample(info) and reporter < source) then
					info, source = candidate, reporter
				end
			end
		end
	end
	if not info or not info.key then return info end
	if not PartyRevisionCurrent(self, s, info, now) then
		return { size = info.size, at = info.at, sampledAt = info.sampledAt, lifetime = info.lifetime }
	end
	local roster = s.rosters[info.key]
	-- Return a view over shared evidence. No inferred record is installed under
	-- the subject and no sample/expiry or member-list timestamp is renewed.
	return { size = info.size, key = info.key, leader = info.leader, leaderClass = info.leaderClass,
		revision = info.revision, at = info.at, sampledAt = info.sampledAt, lifetime = info.lifetime,
		cached = info.cached, sourceName = source,
		members = roster and roster.members or nil,
		knownMembers = not roster and KnownPartyMembers(self, s, info, now) or nil }
end
function QT:CancelPartyVisualRosterInterest(name)
	local s = rawget(self, "partyVisualState")
	if not s then
		return
	end
	for id, pending in pairs(s.pending) do
		if pending.name == name and pending.hover then
			s.pending[id] = nil
			CancelPending(self, id, pending, "cancelled")
			s.attempts[pending.key] = { at = Now(self), retryAfter = 2 }
		end
	end
end

function QT:RequestPartyVisualRoster(sender, hover)
	local name, now = Name(self, sender), Now(self)
	local info = name and self:GetPlayerPartyVisualInfo(name)
	if not info or info.cached or not info.key or info.size > 5 or info.size < 2 or info.members then
		return false
	end
	local s = self:GetPartyVisualState()
	for id, pending in pairs(s.pending) do
		if not PendingFresh(self, id, pending) then
			s.pending[id] = nil
			CancelPending(self, id, pending, "expired")
		elseif pending.key == info.key then
			return false
		end
	end
	local attempt = s.attempts[info.key]
	if Fresh(attempt, now, attempt and attempt.retryAfter or REQUEST_TTL) or Count(s.pending) >= 16 then
		return false
	end
	s.attempts[info.key] = { at = now }
	Bound(s.attempts, 128)
	s.sequence = s.sequence + 1
	local random = self.API.Random and self:SafeToNumber(self.API.Random(1, 99999999)) or 1
	local id = math.floor(now * 1000) .. "-" .. math.floor(random or 1) .. "-" .. s.sequence
	local pending = {
		at = now,
		name = name,
		key = info.key,
		revision = info.revision,
		size = info.size,
		leader = info.leader,
		hover = hover == true,
	}
	s.pending[id] = pending
	local admitted = self:Request(
		"QPGR",
		{ requestId = id, targetName = name, revision = info.revision },
		{ { distribution = "WHISPER", target = name } },
		{
			owner = pending,
			expires = now + REQUEST_TTL,
			isCurrent = function()
				local current = self:GetPlayerPartyVisualInfo(name)
				return rawget(self, "partyVisualState") == s
					and s.pending[id] == pending
					and PendingFresh(self, id, pending)
					and (not pending.hover or self:HasPlayerDetailsInterest(name))
					and current ~= nil
					and current.key == pending.key
			end,
			onResponse = function(record, peer, context)
				return self:HandlePartyVisualRosterMember(record, peer, context)
			end,
			onComplete = function(sent)
				if not sent and rawget(self, "partyVisualState") == s and s.pending[id] == pending then
					s.pending[id] = nil
					s.attempts[info.key] = { at = Now(self), retryAfter = 2 }
					CancelPending(self, id, pending, "cancelled")
				end
			end,
		}
	)
	if not admitted and s.pending[id] == pending then
		s.pending[id] = nil
		s.attempts[info.key] = { at = now, retryAfter = 2 }
		CancelPending(self, id, pending, "cancelled")
	end
	return admitted
end
function QT:HandlePartyVisualRosterRequest(data, sender)
	if not Allowed(self) or type(data) ~= "table" then
		return false
	end
	local id, revision, name = data.requestId, data.revision, Name(self, sender)
	if
		type(id) ~= "string"
		or #id > 80
		or not id:match("^[%w%-]+$")
		or type(revision) ~= "string"
		or #revision > 10
		or not revision:match("^%d+$")
		or not Name(self, data.targetName)
		or not self:IsSelfSender(data.targetName)
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
	if Fresh(s.replies[name], now, 20) or (s.lastReply and now >= s.lastReply and now - s.lastReply < 5) then
		return false
	end
	local pending, roster = { at = now }, self:GetPartyRosterFingerprint()
	s.lastReply, s.replies[name] = now, pending
	Bound(s.replies, 128)
	self:RecordQTPlayerPresence(name, true)
	return self:Respond(
		"QPGM",
		{ requestId = id, revision = revision, members = info.members },
		{ { distribution = "WHISPER", target = name } },
		{
			owner = pending,
			expires = now + 600,
			isCurrent = function()
				local current = self:GetLocalPartyVisualInfo()
				return rawget(self, "partyVisualState") == s
					and s.replies[name] == pending
					and Allowed(self)
					and not self:IsIgnoredPlayerName(name)
					and roster == self:GetPartyRosterFingerprint()
					and current ~= nil
					and current.revision == revision
			end,
		}
	)
end
function QT:HandlePartyVisualRosterMember(data, sender)
	if not Allowed(self) or type(data) ~= "table" then
		return false
	end
	local id, revision, name = data.requestId, data.revision, Name(self, sender)
	if type(id) ~= "string" or not name or self:IsIgnoredPlayerName(name) or type(data.members) ~= "table" then
		return false
	end
	local s, now = self:GetPartyVisualState(), Now(self)
	local pending, info = s.pending[id], self:GetPlayerPartyVisualInfo(name)
	if
		not PendingFresh(self, id, pending)
		or pending.name ~= name
		or pending.revision ~= revision
		or not info
		or pending.key ~= info.key
		or #data.members ~= pending.size
	then
		return false
	end
	local members, seen = {}, {}
	for index, member in ipairs(data.members) do
		local memberName = type(member) == "table" and Name(self, member.name)
		local class = type(member) == "table" and Class(member.classFile or "")
		if not memberName or not class or seen[memberName] then
			return false
		end
		seen[memberName] = true
		members[index] = { name = memberName, classFile = class }
	end
	if not seen[pending.leader] or not seen[name] or Revision(pending.leader, members) ~= revision then
		return false
	end
	StoreRoster(s, pending.key, { at = now, members = members })
	s.pending[id] = nil
	self:CancelCommRequest(id, "complete")
	return true
end

function QT:ResetPartyVisuals()
	local state = rawget(self, "partyVisualState")
	self.partyVisualState = nil
	if state then
		self:CancelTransportOwner(state)
		for id in pairs(state.pending) do
			self:CancelCommRequest(id, "cancelled")
		end
	end
end
