-- Directory bootstrap and bounded public-interest routing. Directory entries
-- and introductions are addresses, never accepted player observations.
local QT = _G.QuestTogether
local MAX_NEIGHBORS, MAX_CANDIDATES, MAX_PENDING = 8, 512, 3
local RESERVATION_SECONDS, RECIPROCAL_SECONDS = 30, 120
-- Three callers can wait through three 120s rotation turns plus a paced
-- reciprocal exchange. Repeated hellos never extend this queue lifetime.
local ADMISSION_INTENT_SECONDS = 480
local MAX_SEEDS, SEED_LIFETIME = 64, 86400
local LEASE_SECONDS, RENEW_SECONDS, MAX_INTERESTS = 120, 40, 32
local NEIGHBOR_SECONDS, CHALLENGE_SECONDS = 180, 120
local FANOUT, MAX_HOPS, DIRECTORY_INTERVAL = 3, 8, 300
local MAX_PENDING_INTERESTS = 24
local MAX_DIRECTORY_ROWS, ROWS_PER_TICK = 1500, 32
local CONTACT_SECONDS, CONTACT_EVENT_SECONDS, CONTACT_EVENT_LIMIT = 300, 10, 16
local CONTACT_SOURCES = { friend = true, bnet = true, chat = true, visible = true }
local RetirePeerRoutes, PersistFailure, RestoreFailure, ForgetFailure, MakeReplacementRoom
local MAX_FAILURES, FAILURE_LIFETIME, MAX_STALE_PROBES = 512, 86400, 3
local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end
local function Server(a)
	return a:GetAnnouncementServerTime() or 0
end
local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end
local function Metric(s, key)
	s.metrics[key] = (s.metrics[key] or 0) + 1
end
local function Name(a, value)
	if
		not a:CanAccessValue(value)
		or type(value) ~= "string"
		or #value > 120
		or value == ""
		or value:find("[%c|,:]")
	then
		return nil
	end
	local normalized = a:NormalizeMemberName(value)
	return type(normalized) == "string" and #normalized <= 120 and normalized ~= "" and normalized or nil
end
local function Own(a)
	return Name(a, a:GetPlayerFullName())
end
local function Allowed(a)
	return a.isEnabled
		and not a.isLoggingOut
		and not a:IsRuntimeRestricted()
		and not a:IsRuntimeRestrictionTypeActive("chat")
end
local function Current(a, s)
	return rawget(a, "meshNetworkState") == s
		and a.isEnabled
		and not a.isLoggingOut
		and rawget(a, "communicationState") == s.communication
		and not s.communication.departing
		and (not a.db or a.db.profile == s.profile)
end
local function ValidZone(a, zone)
	zone = a:SafeToNumber(zone)
	return zone and zone >= 0 and zone <= 1000000 and zone == math.floor(zone) and zone or nil
end
local function Zone(scope)
	return scope == "global" and 0 or tonumber(scope)
end
local function Key(destination, id)
	return destination .. ":" .. id
end
local function Route(name)
	return { { distribution = "WHISPER", target = name, meshTraffic = true } }
end
local function Invoke(callback, ...)
	if callback then
		pcall(callback, ...)
	end
end
local function IsCurrent(predicate)
	if not predicate then
		return true
	end
	local ok, result = pcall(predicate)
	return ok and result == true
end
local function Native(a, method, ...)
	local callback = a.API[method]
	if type(callback) ~= "function" then
		return nil
	end
	local ok, one, two, three, four, five, six, seven, eight = pcall(callback, ...)
	if not ok then
		return nil
	end
	return { one, two, three, four, five, six, seven, eight }
end
local function RetryCandidate(a, row, now, remoteFailure)
	row.delay = math.min(1800, math.max(300, (row.delay or 150) * 2))
	row.retryAt = now + row.delay
	row.failureSerial = (row.failureSerial or 0) + 1
	if remoteFailure then
		local fresh = (row.evidenceAt or 0) > (row.failureEvidenceAt or 0)
			or (row.evidenceSerial or 0) > (row.failureEvidenceSerial or 0)
		row.probeFailures = math.min(MAX_STALE_PROBES, (fresh and 0 or row.probeFailures or 0) + 1)
		row.failureEvidenceAt, row.failureAt = row.evidenceAt or 0, Server(a)
		row.failureEvidenceSerial = row.evidenceSerial or 0
		PersistFailure(a, row)
	end
end
local function ProbeEligible(a, row)
	if row.failureAt and Server(a) - row.failureAt >= FAILURE_LIFETIME then
		row.probeFailures, row.failureEvidenceAt, row.failureAt = nil, nil, nil
		ForgetFailure(a, row.name)
	end
	return (row.probeFailures or 0) < MAX_STALE_PROBES
		or (row.evidenceAt or 0) > (row.failureEvidenceAt or 0)
		or (row.evidenceSerial or 0) > (row.failureEvidenceSerial or 0)
end
local function RetireOldestCandidate(s, now)
	local oldest, at
	for name, candidate in pairs(s.candidates) do
		if
			not s.neighbors[name]
			and not s.pending[name]
			and not s.reservations[name]
			and not (s.admissionIntents and s.admissionIntents[name])
			and candidate.retryAt <= now
			and (not candidate.contactAt or now - candidate.contactAt >= CONTACT_SECONDS)
			and (not at or candidate.heardAt < at)
		then
			oldest, at = name, candidate.heardAt
		end
	end
	if not oldest then
		return false
	end
	s.candidates[oldest] = nil
	return true
end
local function Retry(row, now)
	row.delay = math.min(900, math.max(5, (row.delay or 2.5) * 2))
	row.retryAt = now + row.delay
end
local function Neighbor(a, s, name)
	local row = s.neighbors[name]
	return row and Now(a) < row.expires and not a:IsIgnoredPlayerName(name) and row or nil
end
function QT:IsConfirmedMeshNeighbor(value)
	local s = rawget(self, "meshNetworkState")
	local name = Name(self, value)
	return s ~= nil and Current(self, s) and name ~= nil and Neighbor(self, s, name) ~= nil
end
local function Reserved(a, s, name)
	local reservation = s.reservations[name]
	return reservation and Now(a) < reservation.expires and not a:IsIgnoredPlayerName(name) and reservation or nil
end
local function Reserve(a, s, name, reciprocal)
	if Neighbor(a, s, name) then
		return true
	end
	local existing = Reserved(a, s, name)
	if reciprocal and not (existing and existing.reciprocal) then
		local waiting = 0
		for peer in pairs(s.reservations) do
			local reservation = Reserved(a, s, peer)
			if reservation and reservation.reciprocal then
				waiting = waiting + 1
			end
		end
		if waiting >= MAX_PENDING then
			return false, "reciprocal_capacity"
		end
	end
	if existing then
		if reciprocal and not existing.reciprocal then
			existing.reciprocal, existing.expires = true, Now(a) + RECIPROCAL_SECONDS
		end
		return true
	end
	local occupied = {}
	for peer in pairs(s.neighbors) do
		if Neighbor(a, s, peer) then
			occupied[peer] = true
		end
	end
	for peer in pairs(s.reservations) do
		if Reserved(a, s, peer) then
			occupied[peer] = true
		end
	end
	if Count(occupied) >= MAX_NEIGHBORS then
		return false, "capacity"
	end
	s.reservations[name] = {
		expires = Now(a) + (reciprocal and RECIPROCAL_SECONDS or RESERVATION_SECONDS),
		reciprocal = reciprocal == true,
	}
	return true
end
local function ScopedStore(a, field)
	local global = a.db and a.db.global
	if type(global) ~= "table" then
		return nil
	end
	local namespace = Native(a, "GetPlayerNotesNamespace")
	namespace = namespace and namespace[1]
	local character = Own(a)
	if type(namespace) ~= "string" or namespace == "" or not character then
		return nil
	end
	if type(global[field]) ~= "table" then
		global[field] = {}
	end
	local key = namespace .. ":" .. character
	if type(global[field][key]) ~= "table" then
		global[field][key] = {}
	end
	return global[field][key]
end
local function SeedStore(a)
	return ScopedStore(a, "meshPeerSeeds")
end
local function FailureStore(a)
	return ScopedStore(a, "meshPeerFailures")
end
local function Finite(a, value)
	local n = a:SafeToNumber(value)
	return n and n == n and n ~= math.huge and n ~= -math.huge and n or nil
end
local function PruneFailures(a, rows)
	local now, kept = Server(a), {}
	for key, row in pairs(rows or {}) do
		local at = type(row) == "table" and Finite(a, row.at)
		local delay = type(row) == "table" and Finite(a, row.delay)
		local untilAt = type(row) == "table" and Finite(a, row.untilAt)
		local failures = type(row) == "table" and Finite(a, row.failures)
		local evidence = type(row) == "table" and Finite(a, row.evidenceAt)
		if
			not Name(a, key)
			or key ~= key:lower()
			or a:IsIgnoredPlayerName(key)
			or not at
			or at <= 0
			or at > now
			or now - at >= FAILURE_LIFETIME
			or not delay
			or delay < 300
			or delay > 1800
			or not untilAt
			or untilAt < at
			or untilAt > at + 1800
			or not failures
			or failures < 1
			or failures > MAX_STALE_PROBES
			or failures % 1 ~= 0
			or not evidence
			or evidence < 0
			or evidence > at
		then
			rows[key] = nil
		else
			-- Rebuild rather than retaining unexpected nested or oversized values
			-- from a damaged saved-variable record.
			rows[key] = { at = at, delay = delay, untilAt = untilAt, failures = failures, evidenceAt = evidence }
			kept[#kept + 1] = { key = key, at = at }
		end
	end
	table.sort(kept, function(one, two)
		return one.at > two.at or one.at == two.at and one.key < two.key
	end)
	for index = MAX_FAILURES + 1, #kept do
		rows[kept[index].key] = nil
	end
end
PersistFailure = function(a, row)
	local rows, stamp = FailureStore(a), Server(a)
	if not rows or stamp <= 0 then
		return
	end
	rows[row.name:lower()] = {
		at = stamp,
		untilAt = stamp + row.delay,
		delay = row.delay,
		failures = row.probeFailures,
		evidenceAt = math.min(stamp, row.failureEvidenceAt or 0),
	}
	PruneFailures(a, rows)
end
RestoreFailure = function(a, row, preserveDirectEvidence)
	local rows = FailureStore(a)
	local old = rows and rows[row.name:lower()]
	if old then
		row.delay = old.delay
		row.retryAt = Now(a) + math.max(0, old.untilAt - Server(a))
		row.probeFailures, row.failureEvidenceAt, row.failureAt = old.failures, old.evidenceAt, old.at
		-- A repeated address after a reset is not a newly observed live player.
		if not preserveDirectEvidence or not row.evidenceSerial then
			row.evidenceAt = math.min(row.evidenceAt or old.evidenceAt, old.evidenceAt)
		end
	end
end
ForgetFailure = function(a, name)
	local rows = FailureStore(a)
	if rows then
		rows[name:lower()] = nil
	end
end
local function RememberSeed(a, name)
	local seeds, stamp = SeedStore(a), Server(a)
	if not seeds or stamp <= 0 then
		return
	end
	seeds[name] = stamp
	local n, oldest, oldestAt = 0
	for candidate, at in pairs(seeds) do
		local valid = Name(a, candidate)
		at = a:SafeToNumber(at)
		if not valid or not at or at > stamp or stamp - at >= SEED_LIFETIME then
			seeds[candidate] = nil
		else
			n = n + 1
			if not oldestAt or at < oldestAt then
				oldest, oldestAt = candidate, at
			end
		end
	end
	if n > MAX_SEEDS then
		seeds[oldest] = nil
	end
end
function QT:InitializeMeshNetwork()
	local s = rawget(self, "meshNetworkState")
	if s and Current(self, s) then
		return s
	end
	if s then
		self:ResetMeshNetwork()
	end
	local now = Now(self)
	s = {
		communication = self:InitializeCommunications(),
		profile = self.db and self.db.profile,
		startedAt = now,
		nextTick = now,
		nextHandshake = now + 1,
		nextDirectory = now + 2,
		nextGuild = now + 2,
		nextContacts = now + 2,
		contactCursors = { friend = 1, bnet = 1 },
		nextRotation = now + 120,
		directoryCursors = {},
		directoryCycle = 0,
		candidates = {},
		neighbors = {},
		reservations = {},
		admissionIntents = {},
		pending = {},
		pendingInterests = {},
		localInterests = {},
		localHistory = {},
		interests = {},
		joins = {},
		forwarded = {},
		pendingPublications = {},
		interestHistory = {},
		interestSelections = {},
		destinations = {},
		metrics = {},
		serial = 0,
		serviceSerial = 0,
	}
	self.meshNetworkState = s
	s.failureRows = FailureStore(self)
	PruneFailures(self, s.failureRows)
	local seeds, stamp = SeedStore(self), Server(self)
	local loaded = 0
	for name, at in pairs(seeds or {}) do
		at = self:SafeToNumber(at)
		if at and at <= stamp and stamp - at < SEED_LIFETIME and loaded < MAX_SEEDS then
			if self:RememberMeshCandidate(name, "saved", nil, at) then
				loaded = loaded + 1
			else
				seeds[name] = nil
			end
		else
			seeds[name] = nil
		end
	end
	return s
end
function QT:RememberMeshCandidate(value, source, zone, observedAt)
	local s = rawget(self, "meshNetworkState")
	local name = Name(self, value)
	if not s or not Current(self, s) or not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local now, row = Now(self), s.candidates[name]
	if not row then
		if Count(s.candidates) >= MAX_CANDIDATES then
			if not RetireOldestCandidate(s, now) then
				Metric(s, "candidateCapacity")
				return false
			end
		end
		local random = Native(self, "Random", 1, 1000000)
		row = {
			name = name,
			retryAt = now,
			heardAt = now,
			discoveredAt = now,
			rank = random and random[1] or 0,
			evidenceAt = observedAt or Server(self),
		}
		RestoreFailure(self, row)
		s.candidates[name] = row
		Metric(s, "candidatesAdded")
	end
	-- Cached rosters, introductions and saved seeds are addresses. Only a
	-- direct native observation can reopen an exhausted probe allowance.
	if source == "hello" or source == "confirmed" then
		row.evidenceAt = Server(self)
		row.evidenceSerial = (row.evidenceSerial or 0) + 1
	end
	row.heardAt, row.source = now, source
	if zone then
		row.zone = zone
	end
	return true
end
-- Native sightings provide addresses only. In particular, neither an ordinary
-- chat message nor a friend-list entry proves that this character uses QT.
function QT:ObserveMeshContact(value, source, zone)
	local s = rawget(self, "meshNetworkState")
	if not CONTACT_SOURCES[source] or not s or not Current(self, s) or not Allowed(self) then
		return false
	end
	local name = Name(self, value)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local now, row = Now(self), s.candidates[name]
	if not row then
		-- Bound event-driven work even on a busy city chat/nameplate stream.
		-- Roster reads already share the runtime's paced row budget.
		if source == "chat" or source == "visible" then
			if not s.contactEventAt or now - s.contactEventAt >= CONTACT_EVENT_SECONDS then
				s.contactEventAt, s.contactEventCount = now, 0
			end
			if s.contactEventCount >= CONTACT_EVENT_LIMIT then
				Metric(s, "contactRateDrops")
				return false
			end
			s.contactEventCount = s.contactEventCount + 1
		end
		if Count(s.candidates) >= MAX_CANDIDATES then
			if not RetireOldestCandidate(s, now) then
				Metric(s, "contactCapacityDrops")
				return false
			end
		end
		if not self:RememberMeshCandidate(name, source, ValidZone(self, zone)) then
			return false
		end
		row = s.candidates[name]
		Metric(s, "contactsAdded_" .. source)
	else
		row.heardAt = now
		-- Do not reset triedAt, retryAt, delay, or promote to a neighbor.
		-- A repeated sighting is not evidence of a successful QT handshake.
		local validZone = ValidZone(self, zone)
		if validZone then
			row.zone = validZone
		end
	end
	if source == "chat" or source == "visible" then
		row.evidenceAt = Server(self)
		row.evidenceSerial = (row.evidenceSerial or 0) + 1
	end
	row.contactAt, row.contactSource = now, source
	return true
end

function QT:ObserveMeshUnit(unitToken)
	local s = rawget(self, "meshNetworkState")
	if
		not s
		or not Current(self, s)
		or not Allowed(self)
		or not self:CanAccessValue(unitToken)
		or type(unitToken) ~= "string"
		or not (unitToken == "target" or unitToken == "mouseover" or unitToken:match("^nameplate%d+$"))
	then
		return false
	end
	local result = Native(self, "GetMeshUnitPlayerName", unitToken)
	local geo = rawget(self, "geographicCommsState")
	return result and self:ObserveMeshContact(result[1], "visible", geo and geo.currentZone) or false
end

function QT:ScheduleMeshContactScan()
	local s = rawget(self, "meshNetworkState")
	if s and Current(self, s) and Allowed(self) then
		s.nextContacts = math.min(s.nextContacts, math.max(Now(self), (s.lastContactScan or -30) + 30))
	end
end
local function Confirm(a, s, name, context, sharedDelivery)
	local row = s.neighbors[name]
	local fresh = row == nil
	if not row and (not Reserved(a, s, name) or Count(s.neighbors) >= MAX_NEIGHBORS) then
		return nil
	end
	if row and row.session and context and context.session ~= row.session then
		RetirePeerRoutes(a, s, name)
		if not Current(a, s) then
			return nil
		end
		Metric(s, "neighborSessionChanges")
	end
	a:RememberMeshCandidate(name, "confirmed")
	local now = Now(a)
	row = row or { name = name, connectedAt = now }
	row.at, row.expires, row.session = now, now + NEIGHBOR_SECONDS, context and context.session
	row.sharedDelivery = sharedDelivery == true
	s.neighbors[name] = row
	s.reservations[name] = nil
	s.admissionIntents[name] = nil
	local candidate = s.candidates[name]
	if candidate then
		candidate.delay, candidate.retryAt = nil, now + CHALLENGE_SECONDS
		candidate.probeFailures, candidate.failureEvidenceAt, candidate.failureAt = nil, nil, nil
		ForgetFailure(a, name)
	end
	RememberSeed(a, name)
	if fresh then
		for _, lease in pairs(s.localInterests) do
			if Count(lease.downstreams) == 0 then
				lease.renewAt = math.min(lease.renewAt or now, now)
			end
		end
	end
	Metric(s, "handshakesConfirmed")
	local waiting = s.pendingInterests[name]
	s.pendingInterests[name] = nil
	for _, item in ipairs(waiting or {}) do
		if not Current(a, s) then
			break
		end
		-- Reserved senders are not graph peers. Their early control messages
		-- become eligible only after our independent challenge confirms the
		-- same native session, and the normal handler rechecks every field.
		if item.session == row.session then
			a:HandleMeshInterest(item.record, name, { distribution = "WHISPER", session = row.session })
		else
			Metric(s, "pendingInterestDrops")
		end
	end
	return row
end

local function DiscoveryPressure(a)
	local transport = a:GetTransportMetrics()
	local publications = rawget(a, "meshPublicationState")
	return (transport.queuedPackets or 0) >= 8
		or (transport.oldestAge or 0) >= 4
		or (transport.packetRate or 4) < 4
		or publications and (publications.pending or 0) >= 8
end
local function Introductions(a, s, target)
	local names = {}
	for name in pairs(s.neighbors) do
		if name ~= target and Neighbor(a, s, name) then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	local peers = {}
	for _, name in ipairs(names) do
		if #peers < 8 then
			peers[#peers + 1] = { name = name }
		end
	end
	return peers
end
local function PruneAdmissionIntents(a, s, now)
	for name, intent in pairs(s.admissionIntents) do
		local candidate = s.candidates[name]
		if
			now >= intent.expiresAt
			or not candidate
			or Neighbor(a, s, name)
			or a:IsIgnoredPlayerName(name)
			or (candidate.failureSerial or 0) ~= intent.failureSerial
		then
			s.admissionIntents[name] = nil
			Metric(s, now >= intent.expiresAt and "admissionIntentsExpired" or "admissionIntentsCancelled")
		end
	end
end
local function QueueAdmissionIntent(a, s, name, candidate, now)
	PruneAdmissionIntents(a, s, now)
	if s.admissionIntents[name] then
		return
	end
	if Count(s.admissionIntents) >= MAX_PENDING then
		Metric(s, "admissionIntentDrops")
		return
	end
	-- Remember an explicit native protocol request, not a trusted edge. Do not
	-- let repeated hellos extend this wait or jump ahead of another caller.
	s.admissionIntents[name] = {
		queuedAt = now,
		expiresAt = now + ADMISSION_INTENT_SECONDS,
		failureSerial = candidate.failureSerial or 0,
	}
	Metric(s, "admissionIntentsQueued")
end
function QT:HandleMeshHello(record, sender, context)
	local s = self:InitializeMeshNetwork()
	sender = Name(self, sender)
	if
		not Allowed(self)
		or not Current(self, s)
		or not sender
		or self:IsSelfSender(sender)
		or self:IsIgnoredPlayerName(sender)
		or not context
		or context.distribution ~= "WHISPER"
		or record.protocol ~= 3
		or record.capabilities ~= "mesh1"
	then
		return false
	end
	local now = Now(self)
	self:RememberMeshCandidate(sender, "hello")
	local previous = s.candidates[sender]
	if previous and previous.replyAt and now - previous.replyAt < 10 then
		return false
	end
	if not previous then
		return false
	end
	previous.replyAt = now
	local prospective = s.pending[sender]
	if
		prospective
		and prospective.exploring
		and now < prospective.expires
		and not Neighbor(self, s, sender)
		and not Reserved(self, s, sender)
	then
		MakeReplacementRoom(self, s, sender)
		if not Current(self, s) then
			return false
		end
	end
	local admitted = Reserve(self, s, sender, true)
	if not admitted then
		Metric(s, "handshakeBusyReplies")
		QueueAdmissionIntent(self, s, sender, previous, now)
	else
		s.admissionIntents[sender] = nil
	end
	-- A hello is only an address hint. A correlated reply to our independent
	-- challenge is required before that sender owns any graph edge.
	if admitted or not previous.triedAt then
		previous.retryAt = math.min(previous.retryAt, now)
	end
	if admitted then
		-- Finish an admitted reciprocal exchange promptly. This only makes it
		-- eligible for the shared scheduler; it does not bypass send budgets.
		s.nextHandshake = math.min(s.nextHandshake, math.max(now, (s.lastHandshakeAt or now - 1) + 1))
	end
	return self:Respond(
		"MACK",
		{
			requestId = record.requestId,
			version = self.version or self.VERSION or "3",
			protocol = 3,
			capabilities = "mesh1",
			sharedDelivery = true,
			admitted = admitted,
			peers = admitted and Introductions(self, s, sender) or {},
		},
		Route(sender),
		{
			owner = previous,
			requestId = record.requestId,
			meshTraffic = true,
			priority = "background",
			expires = now + 15,
			isCurrent = function()
				return Current(self, s)
					and not self:IsIgnoredPlayerName(sender)
					and (not admitted or Neighbor(self, s, sender) ~= nil or Reserved(self, s, sender) ~= nil)
			end,
		}
	)
end
local function StartHandshake(a, s, candidate)
	local name, now = candidate.name, Now(a)
	if a.CanRecordAddonWhisperAttempt then
		local ready, reason = a:CanRecordAddonWhisperAttempt(name, true)
		if not ready and reason == "filter-unavailable" then
			s.nextHandshake = now + 1
			Metric(s, "handshakeLocalDeferrals")
			return
		end
	end
	local reservation = Reserved(a, s, name)
	if not (reservation and reservation.reciprocal) then
		-- Another spelling may have completed a silent timeout since this
		-- candidate was learned. Read the shared address history before probing.
		RestoreFailure(a, candidate, true)
		if now < candidate.retryAt or not ProbeEligible(a, candidate) then
			s.nextHandshake = now + 0.2
			return
		end
		-- Directory/chat spellings can arrive after a failed address was retired.
		-- Share its remaining backoff before attempting a native probe. This is
		-- one bounded candidate scan per probe opportunity, not per queued packet
		-- or per candidate during selection, and creates no second identity store.
		local key, blocked, reachable = name:lower(), nil, false
		for otherName, other in pairs(s.candidates) do
			if otherName ~= name and otherName:lower() == key then
				if Neighbor(a, s, otherName) then
					reachable = true
				end
				if other.delay and other.retryAt > now and (not blocked or other.retryAt > blocked.retryAt) then
					blocked = other
				end
			end
		end
		if blocked and not reachable then
			candidate.retryAt = blocked.retryAt
			candidate.delay = math.max(candidate.delay or 0, blocked.delay)
			s.nextHandshake = now + 0.2
			return
		end
	end
	local exploring = not Neighbor(a, s, name) and not reservation and Count(s.neighbors) >= MAX_NEIGHBORS
	if exploring then
		for _, pending in pairs(s.pending) do
			if pending.exploring then
				s.nextHandshake = now + 1
				return
			end
		end
	end
	if not exploring and not Reserve(a, s, name) then
		-- Local occupancy says nothing about this peer. Wait for a slot instead
		-- of imposing an unreachable-peer cooldown before any packet is sent.
		candidate.lastHandshakeOutcome, candidate.lastHandshakeAt = "local_capacity", now
		candidate.lastHandshakeReason, candidate.lastHandshakeCode = "capacity", nil
		s.nextHandshake = now + 1
		Metric(s, "handshakeCapacity")
		return
	end
	local pending = { submitting = true, exploring = exploring, expires = now + 20 }
	if exploring then
		s.nextRotation = now + 120
	end
	s.pending[name] = pending
	candidate.triedAt = now
	local function Finish(success, outcome, reason, detail)
		if not Current(a, s) or s.pending[name] ~= pending then
			return
		end
		s.pending[name] = nil
		candidate.lastHandshakeOutcome, candidate.lastHandshakeAt = outcome, Now(a)
		candidate.lastHandshakeReason = a:CanAccessValue(reason)
				and type(reason) == "string"
				and #reason <= 64
				and not reason:find("[%c|]")
				and reason
			or nil
		candidate.lastHandshakeCode = a:CanAccessValue(detail) and type(detail) == "number" and a:SafeToNumber(detail)
			or nil
		if not success then
			RetryCandidate(a, candidate, Now(a), outcome == "timeout")
			local metric = ({
				busy = "handshakeBusy",
				timeout = "handshakeTimeouts",
				admission_failed = "handshakeAdmissionFailures",
				send_failed = "handshakeSendFailures",
				queue_expired = "handshakeQueueExpiries",
				confirmation_failed = "handshakeConfirmationFailures",
				cancelled = "handshakeCancelled",
			})[outcome]
			if metric then
				Metric(s, metric)
			end
		end
	end
	local admitted, admissionReason, _, requestId = a:Request(
		"MHEL",
		{ version = a.version or a.VERSION or "3", protocol = 3, capabilities = "mesh1", sharedDelivery = true },
		Route(name),
		{
			owner = pending,
			meshTraffic = true,
			priority = "background",
			expires = now + 20,
			isCurrent = function()
				return Current(a, s) and s.pending[name] == pending and not a:IsIgnoredPlayerName(name)
			end,
			onComplete = function(sent, reason, _, _, outcomes)
				if sent or reason == "ambiguous" or outcomes and (outcomes.accepted or outcomes.ambiguous) then
					pending.sentAt = Now(a)
				end
			end,
			onExpire = function(reason, detail)
				local outcome = reason == "expired" and (pending.sentAt and "timeout" or "queue_expired")
					or reason == "cancelled" and "cancelled"
					or pending.submitting and "admission_failed"
					or "send_failed"
				Finish(false, outcome, reason, detail)
			end,
			onResponse = function(record, sender, context)
				if
					not Current(a, s)
					or s.pending[name] ~= pending
					or Now(a) >= pending.expires
					or Name(a, sender) ~= name
					or a:IsIgnoredPlayerName(name)
					or record.protocol ~= 3
					or record.capabilities ~= "mesh1"
				then
					return false
				end
				if a.RememberPlayerHandshakeVersion then
					a:RememberPlayerHandshakeVersion(sender, record.version, context)
				end
				if record.admitted ~= true then
					Finish(false, "busy", "busy")
					a:CancelCommRequest(record.requestId, "rejected")
					return true
				end
				if pending.exploring and not Neighbor(a, s, name) and not Reserved(a, s, name) then
					if not MakeReplacementRoom(a, s, name) or s.pending[name] ~= pending or not Reserve(a, s, name) then
						Finish(false, "confirmation_failed", "capacity")
						return false
					end
				end
				if s.admissionIntents[name] then
					Metric(s, "admissionReservations")
				end
				local confirmed = Confirm(a, s, name, context, record.sharedDelivery)
				if not confirmed then
					Finish(false, "confirmation_failed", "confirmation_failed")
					return false
				end
				for index, peer in ipairs(record.peers or {}) do
					if index > 8 then
						break
					end
					a:RememberMeshCandidate(peer.name, "introduction")
				end
				Finish(true, "confirmed", "accepted")
				a:CancelCommRequest(record.requestId, "completed")
				return true
			end,
		}
	)
	pending.submitting = false
	pending.requestId = requestId
	if not admitted then
		Finish(false, "admission_failed", admissionReason)
	end
	Metric(s, "handshakesStarted")
	s.lastHandshakeAt = now
	local random = Native(a, "Random", 20, 30)
	local delay = math.min(30, math.max(20, a:SafeToNumber(random and random[1]) or 25))
	s.regularHandshakeAt = now + delay
	if s.metrics.handshakesStarted < 3 then
		delay = 4
	elseif Count(s.neighbors) < MAX_NEIGHBORS and not DiscoveryPressure(a) then
		local bootstrap = Native(a, "Random", 4, 6)
		delay = math.min(6, math.max(4, a:SafeToNumber(bootstrap and bootstrap[1]) or 5))
		Metric(s, "bootstrapProbes")
	end
	s.nextHandshake = now + delay
end

function QT:EnsureMeshDirectoryJoined(channelName)
	local s = self:InitializeMeshNetwork()
	if not Current(self, s) or not Allowed(self) or type(channelName) ~= "string" or #channelName > 120 then
		return false
	end
	if self:GetAnnouncementChannelLocalID(channelName) then
		return self:EnsureAnnouncementChannelJoined(channelName)
	end
	local now = Now(self)
	local join = s.joins[channelName]
	if not join then
		if Count(s.joins) >= 8 then
			return false
		end
		join = {}
		s.joins[channelName] = join
	end
	if now < (join.retryAt or 0) then
		return false
	end
	Retry(join, now)
	Metric(s, "directoryJoinAttempts")
	-- Free the former global directory's slot before attempting its replacement.
	-- A full channel list must not delay discovery until a failed join backs off.
	if channelName == self.announcementChannelName and channelName == "QuestTogether" then
		local previous = Native(self, "GetChannelName", "QuestTogether3")
		local previousID = previous and self:SafeToNumber(previous[1])
		if previousID and previousID > 0 then
			Native(self, "LeaveChannelByName", "QuestTogether3")
			previous = Native(self, "GetChannelName", "QuestTogether3")
			previousID = previous and self:SafeToNumber(previous[1])
			if not previous or (previousID and previousID > 0) then return false end
		end
	end
	return self:EnsureAnnouncementChannelJoined(channelName)
end
function QT:RecordMeshDirectoryRefusal(channelName)
	local s = rawget(self, "meshNetworkState")
	if not s or type(channelName) ~= "string" then
		return
	end
	local join = s.joins[channelName]
	if join then
		Retry(join, Now(self))
		Metric(s, "directoryRefusals")
	end
end
local function DisplayRows(a)
	local total = Native(a, "GetNumDisplayChannels")
	total = total and a:SafeToNumber(total[1]) or 0
	local rows = {}
	for index = 1, math.min(60, total) do
		local info = Native(a, "GetChannelDisplayInfo", index)
		local name = info and a:SafeToString(info[1], "")
		if name and name ~= "" and info[2] ~= true and info[6] ~= false then
			rows[#rows + 1] = { index = index, name = name }
		end
	end
	return rows
end
local function ClearDirectoryRestore(a)
	a.meshDirectoryRestore = nil
	Native(a, "CancelChannelSelectionRestore")
end
function QT:RestoreMeshDirectorySelection()
	local pending = rawget(self, "meshDirectoryRestore")
	if not pending then
		return true
	end
	local selected = Native(self, "GetSelectedDisplayChannel")
	local info = selected and Native(self, "GetChannelDisplayInfo", selected[1])
	local ui = Native(self, "IsChannelWindowShown")
	if not info or info[1] ~= pending.selectedName or (ui and ui[1]) then
		ClearDirectoryRestore(self)
		return true
	end
	for _, row in ipairs(DisplayRows(self)) do
		if row.name == pending.previousName then
			local restored = Native(self, "SetSelectedDisplayChannel", row.index)
			if restored and restored[1] then
				ClearDirectoryRestore(self)
				return true
			end
			if not pending.scheduled then
				local scheduled = Native(self, "RequestChannelSelectionRestore", function(allowed)
					if rawget(self, "meshDirectoryRestore") ~= pending then
						return
					end
					pending.scheduled = nil
					if allowed then
						self:RestoreMeshDirectorySelection()
					else
						ClearDirectoryRestore(self)
					end
				end)
				pending.scheduled = scheduled and scheduled[1] == true
			end
			return false
		end
	end
	-- The prior channel was left while we were waiting; no replacement index
	-- is ours to select.
	ClearDirectoryRestore(self)
	return true
end
local function DirectoryRestore(a, s)
	local job = s.directory
	if not job then
		return
	end
	local selected = Native(a, "GetSelectedDisplayChannel")
	local info = selected and Native(a, "GetChannelDisplayInfo", selected[1])
	local ours = job.selectedName or job.lastSelectedName
	-- Indices can move when another channel joins or leaves. Restore the
	-- original channel's identity only if selection is still owned by us.
	if info and info[1] == ours and job.previousName and job.previousName ~= ours then
		-- Keep only the UI ownership names outside the resettable network graph.
		-- An event-only cleanup can restore them after combat even if QT is
		-- disabled meanwhile; it never retains or restarts network work.
		a.meshDirectoryRestore = { previousName = job.previousName, selectedName = ours }
		a:RestoreMeshDirectorySelection()
	end
	s.directory = nil
end
local function DirectoryWanted(a)
	local wanted = { [a.announcementChannelName] = true }
	local geo = rawget(a, "geographicCommsState")
	for channel in pairs(geo and geo.subscriptions or {}) do
		wanted[channel] = true
	end
	return wanted
end
local function DirectoryStep(a, s, now)
	if not a:RestoreMeshDirectorySelection() then
		return
	end
	local ui = Native(a, "IsChannelWindowShown")
	if not Allowed(a) or not ui or ui[1] then
		DirectoryRestore(a, s)
		return
	end
	local job = s.directory
	if not job then
		if now < s.nextDirectory then
			return
		end
		s.nextDirectory = now + DIRECTORY_INTERVAL
		local channels, wanted = {}, DirectoryWanted(a)
		for _, row in ipairs(DisplayRows(a)) do
			if wanted[row.name] and #channels < 8 then
				channels[#channels + 1] = row.name
			end
		end
		if #channels == 0 then
			s.nextDirectory = now + 30
			Metric(s, "directoryUnavailable")
			return
		end
		-- Rotate which directory receives the first selection, and divide the
		-- cycle's row budget so a crowded global list cannot starve a zone.
		local rotated, first = {}, s.directoryCycle % #channels
		for index = 1, #channels do
			rotated[index] = channels[(first + index - 1) % #channels + 1]
		end
		s.directoryCycle = s.directoryCycle + 1
		local selected = Native(a, "GetSelectedDisplayChannel")
		local previous = selected and Native(a, "GetChannelDisplayInfo", selected[1])
		job = { channels = rotated, index = 0, rows = 0, previousName = previous and previous[1] }
		s.directory = job
		Metric(s, "directoryScans")
	end
	if job.selected then
		local selected = Native(a, "GetSelectedDisplayChannel")
		local info = selected and Native(a, "GetChannelDisplayInfo", selected[1])
		if not info or info[1] ~= job.selectedName then
			s.directory = nil
			s.nextDirectory = math.min(s.nextDirectory, now + 30)
			return
		end
		job.selected = selected[1]
		if not DirectoryWanted(a)[job.selectedName] then
			DirectoryRestore(a, s)
			return
		end
	end
	if not job.selected or job.finished then
		if job.rows >= MAX_DIRECTORY_ROWS then
			DirectoryRestore(a, s)
			return
		end
		job.index = job.index + 1
		job.lastSelectedName = job.selectedName
		job.selectedName, job.selected = job.channels[job.index], nil
		if not job.selectedName then
			DirectoryRestore(a, s)
			return
		end
		local alternate
		for _, row in ipairs(DisplayRows(a)) do
			if row.name == job.selectedName then
				job.selected = row.index
			elseif not alternate then
				alternate = row.index
			end
		end
		if not job.selected or not DirectoryWanted(a)[job.selectedName] then
			DirectoryRestore(a, s)
			return
		end
		-- A header/disabled row is not a valid refresh toggle. With only one
		-- selectable channel, read the available roster without inventing an ID.
		if alternate then
			Native(a, "SetSelectedDisplayChannel", alternate)
		end
		Native(a, "SetSelectedDisplayChannel", job.selected)
		job.readyAt, job.finalAt, job.row, job.finished = now + 3, now + 8, nil, false
		job.channelReads, job.visited = 0, 0
		job.quota = math.floor((MAX_DIRECTORY_ROWS - job.rows) / (#job.channels - job.index + 1))
		return
	end
	if now < job.readyAt then
		return
	end
	local info = Native(a, "GetChannelDisplayInfo", job.selected)
	if not info or info[1] ~= job.selectedName then
		DirectoryRestore(a, s)
		return
	end
	local count = a:SafeToNumber(info[5]) or 0
	if count < 1 then
		if now < job.finalAt then
			job.readyAt = job.finalAt
			return
		end
		job.finished = true
		Metric(s, "directoryEmpty")
		return
	end
	if not job.row then
		job.row = ((s.directoryCursors[job.selectedName] or 1) - 1) % count + 1
	elseif job.row > count then
		job.row = 1
	end
	local read = 0
	for _ = 1, ROWS_PER_TICK do
		if job.visited >= count or job.channelReads >= job.quota or job.rows >= MAX_DIRECTORY_ROWS then
			job.finished = true
			break
		end
		local peer = Native(a, "GetChannelRosterInfo", job.selected, job.row)
		read, job.rows, job.channelReads = read + 1, job.rows + 1, job.channelReads + 1
		if not peer or not peer[1] then
			-- Counts can arrive before the asynchronously requested names.
			-- Keep this row pending until the bounded roster wait ends.
			if now < job.finalAt then
				job.readyAt = now + 0.2
				break
			end
			Metric(s, "directoryUnreadable")
		else
			local zone = tonumber(job.selectedName:match("Z(%d+)$"))
			a:RememberMeshCandidate(peer[1], "directory", zone)
		end
		job.visited = job.visited + 1
		job.row = job.row % count + 1
		s.directoryCursors[job.selectedName] = job.row
	end
	s.metrics.directoryRows = (s.metrics.directoryRows or 0) + read
end
local function GuildStep(a, s, now, budget)
	if budget < 1 then
		return 0
	end
	local job = s.guildDirectory
	if not job then
		if now < s.nextGuild then
			return 0
		end
		s.nextGuild = now + DIRECTORY_INTERVAL
		local total = Native(a, "GetNumGuildMembers")
		total = total and a:SafeToNumber(total[1])
		if not total or total < 1 then
			return 0
		end
		job = { index = 1, total = math.min(total, MAX_DIRECTORY_ROWS) }
		s.guildDirectory = job
	end
	local read = 0
	for _ = 1, budget do
		if job.index > job.total then
			s.guildDirectory = nil
			return read
		end
		local member = Native(a, "GetGuildRosterInfo", job.index)
		if member and member[2] == true then
			a:RememberMeshCandidate(member[1], "guild")
		end
		job.index = job.index + 1
		read = read + 1
		Metric(s, "guildRows")
	end
	return read
end

local function ContactCount(a, method, ...)
	local result = Native(a, method, ...)
	local count = result and a:SafeToNumber(result[1])
	return count and math.max(0, math.min(MAX_DIRECTORY_ROWS, math.floor(count))) or 0
end

local function ContactStep(a, s, now, budget)
	if budget < 1 then
		return
	end
	local job = s.contactDirectory
	if not job then
		if now < s.nextContacts then
			return
		end
		s.lastContactScan, s.nextContacts = now, now + CONTACT_SECONDS
		job = {
			friends = ContactCount(a, "GetMeshFriendCount"),
			bnet = ContactCount(a, "GetMeshBattleNetFriendCount"),
			friendVisited = 0,
			bnetVisited = 0,
			rows = 0,
		}
		s.contactDirectory = job
		Metric(s, "contactScans")
	end
	for _ = 1, budget do
		if job.rows >= MAX_DIRECTORY_ROWS then
			s.contactDirectory = nil
			return
		end
		if job.friendVisited < job.friends then
			local index = (s.contactCursors.friend - 1) % job.friends + 1
			local result = Native(a, "GetMeshFriendName", index)
			if result then
				a:ObserveMeshContact(result[1], "friend")
			end
			s.contactCursors.friend, job.friendVisited = index + 1, job.friendVisited + 1
		elseif job.bnetVisited < job.bnet then
			local index = (s.contactCursors.bnet - 1) % job.bnet + 1
			if not job.accounts then
				-- Each account-count lookup also consumes one row of work. An
				-- offline/empty friend list cannot create an unbounded inner loop.
				job.accounts = math.min(5, ContactCount(a, "GetMeshBattleNetGameAccountCount", index))
				job.accountIndex = 1
			elseif job.accountIndex <= job.accounts then
				local result = Native(a, "GetMeshBattleNetFriendName", index, job.accountIndex)
				if result then
					a:ObserveMeshContact(result[1], "bnet")
				end
				job.accountIndex = job.accountIndex + 1
			end
			if job.accountIndex > job.accounts then
				s.contactCursors.bnet, job.bnetVisited = index + 1, job.bnetVisited + 1
				job.accounts = nil
			end
		else
			s.contactDirectory = nil
			return
		end
		job.rows = job.rows + 1
		Metric(s, "contactRows")
	end
end
local function NeighborTargets(a, s, exclude, destination, limit, zone)
	-- Each audience rotates independently. Sharing wall-clock timestamps
	-- across global and zone queries can repeatedly assign the same branches
	-- to each scope when both renew during one runtime tick.
	local key, now = Key(destination, tostring(zone)), Now(a)
	local history = s.interestSelections[key]
	if not history or now >= history.expires then
		if not history and Count(s.interestSelections) >= 64 then
			local oldest, at
			for candidate, entry in pairs(s.interestSelections) do
				if not at or entry.at < at then
					oldest, at = candidate, entry.at
				end
			end
			if oldest then
				s.interestSelections[oldest] = nil
			end
		end
		history = { peers = {}, serial = 0 }
		s.interestSelections[key] = history
	end
	history.at, history.expires = now, now + LEASE_SECONDS
	for name in pairs(history.peers) do
		if not Neighbor(a, s, name) then
			history.peers[name] = nil
		end
	end
	local targets = {}
	for name, peer in pairs(s.neighbors) do
		if name ~= exclude and name ~= destination and Neighbor(a, s, name) then
			targets[#targets + 1] = peer
		end
	end
	table.sort(targets, function(left, right)
		if (history.peers[left.name] or 0) ~= (history.peers[right.name] or 0) then
			return (history.peers[left.name] or 0) < (history.peers[right.name] or 0)
		end
		return left.name < right.name
	end)
	local result = {}
	for index = 1, math.min(limit or FANOUT, #targets) do
		local peer = targets[index]
		history.serial = history.serial + 1
		history.peers[peer.name] = history.serial
		result[#result + 1] = peer.name
	end
	return result
end
local function LocalInterestCovers(a, s, zone, exclude)
	if not s.localInterests[zone] then
		return false
	end
	-- A renewal is queued while the preceding immutable generation remains
	-- usable. Keep that coverage until its actual expiry, avoiding a new query
	-- flood every forty seconds while the replacement waits its send turn.
	for _, lease in pairs(s.localHistory) do
		if lease.zone == zone and Server(a) < lease.expiresAt then
			for target in pairs(lease.coveredDownstreams or {}) do
				if target ~= exclude and Neighbor(a, s, target) then
					return true
				end
			end
		end
	end
	return false
end
local function InterestCurrent(a, s, lease)
	return Current(a, s)
		and Server(a) < lease.expiresAt
		and (
			s.localHistory[Key(lease.destination, lease.id)] == lease
			or s.interests[Key(lease.destination, lease.id)] == lease
		)
end
local function SendInterestTarget(a, s, lease, target, job)
	if
		not InterestCurrent(a, s, lease)
		or not Neighbor(a, s, target)
		or job.pending
		or job.attempts >= 3
		or Now(a) < (job.retryAt or 0)
	then
		return
	end
	job.attempts, job.pending = job.attempts + 1, true
	local session = Neighbor(a, s, target).session
	local function Live()
		local peer = Neighbor(a, s, target)
		return InterestCurrent(a, s, lease) and peer ~= nil and peer.session == session
	end
	local called = false
	local function Complete(sent, reason)
		if called then
			return
		end
		called, job.pending = true, false
		if not Live() then
			return
		end
		if sent then
			job.done, lease.downstreams[target] = true, true
			lease.coveredDownstreams = lease.coveredDownstreams or {}
			lease.coveredDownstreams[target] = true
		elseif reason ~= "cancelled" and job.attempts < 3 then
			if lease.coveredDownstreams then
				lease.coveredDownstreams[target] = nil
			end
			job.retryAt = Now(a) + 2 ^ job.attempts
			Metric(s, "interestRetries")
		else
			job.done = true
			if lease.coveredDownstreams then
				lease.coveredDownstreams[target] = nil
			end
		end
	end
	local accepted, reason = a:Emit(
		"MINT",
		{
			leaseId = lease.id,
			destination = lease.destination,
			zone = lease.zone,
			expiresAt = lease.expiresAt,
			hops = lease.hops,
		},
		Route(target),
		{
			owner = lease,
			meshTraffic = true,
			priority = "background",
			key = "interest:" .. lease.id,
			expires = Now(a) + math.min(30, math.max(0, lease.expiresAt - Server(a))),
			isCurrent = Live,
			onStarted = function()
				if Live() then
					lease.downstreams[target] = true
				end
			end,
			onComplete = Complete,
		}
	)
	if not accepted then
		Complete(false, reason)
	end
end
local function SendInterest(a, s, lease)
	if lease.hops <= 0 then
		return
	end
	local upstream = lease.upstream and Neighbor(a, s, lease.upstream)
	if upstream and upstream.sharedDelivery and LocalInterestCovers(a, s, lease.zone, lease.upstream) then
		lease.aggregated = true
		Metric(s, "interestsAggregated")
		return
	end
	lease.aggregated = nil
	-- A locally owned query supplies shared same-scope demand. Uncovered
	-- scopes still rotate two origin branches and one branch per relay.
	local targets = NeighborTargets(a, s, lease.upstream, lease.destination, lease.upstream and 1 or 2, lease.zone)
	lease.downstreams, lease.interestSends = lease.downstreams or {}, lease.interestSends or {}
	for _, target in ipairs(targets) do
		local job = { attempts = 0 }
		lease.interestSends[target] = job
		SendInterestTarget(a, s, lease, target, job)
	end
	Metric(s, "interestForwards")
end
local function RetryInterests(a, s, lease)
	if lease.aggregated then
		if not LocalInterestCovers(a, s, lease.zone, lease.upstream) then
			SendInterest(a, s, lease)
		end
		return
	end
	for target, job in pairs(lease.interestSends or {}) do
		if not job.done then
			SendInterestTarget(a, s, lease, target, job)
		end
	end
end
local function CancelInterest(a, s, lease)
	a:CancelCommunicationOwner(lease, "cancelled")
	for target in pairs(lease.downstreams or {}) do
		-- Natural expiry is already shared by every carrier; only early
		-- withdrawal needs a control packet.
		if Server(a) < lease.expiresAt and Neighbor(a, s, target) then
			a:Emit("MCAN", { leaseId = lease.id, destination = lease.destination }, Route(target), {
				owner = s,
				meshTraffic = true,
				priority = "background",
				expires = Now(a) + 5,
				isCurrent = function()
					return Current(a, s) and Neighbor(a, s, target) ~= nil
				end,
			})
		end
	end
	lease.expiresAt = 0
end
local function RememberInterest(s, key, now)
	if Count(s.interestHistory) >= 2048 then
		local oldest, at
		for id, expiry in pairs(s.interestHistory) do
			if not at or expiry < at then
				oldest, at = id, expiry
			end
		end
		if oldest then
			s.interestHistory[oldest] = nil
		end
	end
	s.interestHistory[key] = now + 600
end
function QT:HandleMeshInterest(record, sender, context)
	local s = self:InitializeMeshNetwork()
	sender = Name(self, sender)
	local destination, zone, now = Name(self, record.destination), ValidZone(self, record.zone), Server(self)
	local expires = self:SafeToNumber(record.expiresAt)
	local hops = self:SafeToNumber(record.hops)
	if
		not Current(self, s)
		or not Allowed(self)
		or not context
		or context.distribution ~= "WHISPER"
		or not sender
		or not (Neighbor(self, s, sender) or Reserved(self, s, sender))
		or not destination
		or self:IsSelfSender(destination)
		or self:IsIgnoredPlayerName(destination)
		or not zone
		or type(record.leaseId) ~= "string"
		or #record.leaseId > 80
		or record.leaseId == ""
		or record.leaseId:find("[^%w%-]")
		or not expires
		or expires <= now
		or expires > now + LEASE_SECONDS + 2
		or not hops
		or hops < 1
		or hops > MAX_HOPS
		or hops ~= math.floor(hops)
	then
		return false
	end
	local confirmed = Neighbor(self, s, sender)
	if confirmed and confirmed.session and context.session and context.session ~= confirmed.session then
		return false
	end
	if not Neighbor(self, s, sender) then
		-- A reciprocal challenge can still be queued when the other endpoint
		-- sends its first interests. Hold only bounded, validated control data;
		-- no route or publication is admitted before native confirmation.
		if
			type(context.session) ~= "string"
			or #context.session == 0
			or #context.session > 64
			or context.session:find("[^%w%-]")
		then
			return false
		end
		local waiting = s.pendingInterests[sender] or {}
		for _, item in ipairs(waiting) do
			if item.record.leaseId == record.leaseId and item.record.destination == destination then
				return item.session == context.session
					and item.record.zone == zone
					and item.record.expiresAt == expires
					and item.record.hops == hops
			end
		end
		local total = 0
		for _, items in pairs(s.pendingInterests) do
			total = total + #items
		end
		if #waiting >= 3 or total >= MAX_PENDING_INTERESTS then
			Metric(s, "pendingInterestDrops")
			return false
		end
		waiting[#waiting + 1] = {
			session = context.session,
			record = {
				leaseId = record.leaseId,
				destination = destination,
				zone = zone,
				expiresAt = expires,
				hops = hops,
			},
		}
		s.pendingInterests[sender] = waiting
		Metric(s, "pendingInterestsQueued")
		return true
	end
	local key = Key(destination, record.leaseId)
	local lease = s.interests[key]
	if lease then
		-- Query identity, scope and expiry are immutable. Equal/shorter paths
		-- can be failovers, but never flood the same query a second time.
		if lease.zone ~= zone or expires ~= lease.expiresAt or hops < lease.receivedHops then
			return false
		end
		if sender ~= lease.upstream and Count(lease.alternates) < 2 then
			lease.alternates[sender] = true
		end
		Metric(s, "interestDuplicates")
		return true
	end
	if s.interestHistory[key] then
		Metric(s, "interestReplays")
		return false
	end
	-- Native delivery can precede this frame's periodic expiry pass. Retire
	-- elapsed generations before counting capacity for their renewal.
	for expiredKey, existing in pairs(s.interests) do
		if now >= existing.expiresAt then
			s.interests[expiredKey] = nil
			CancelInterest(self, s, existing)
		end
	end
	if Count(s.interests) >= MAX_INTERESTS then
		Metric(s, "interestCapacity")
		return false
	end
	local audiences, generations = {}, 0
	for _, existing in pairs(s.interests) do
		if existing.upstream == sender then
			audiences[Key(existing.destination, tostring(existing.zone))] = true
		end
		if existing.destination == destination and existing.zone == zone then
			generations = generations + 1
		end
	end
	-- Immutable renewal generations keep their old reverse paths alive, but
	-- are one audience for upstream fairness, not three competing listeners.
	local audience = Key(destination, tostring(zone))
	if generations >= 3 or not audiences[audience] and Count(audiences) >= 8 then
		Metric(s, "interestCapacity")
		return false
	end
	lease = {
		id = record.leaseId,
		destination = destination,
		zone = zone,
		upstream = sender,
		downstreams = {},
		alternates = {},
		receivedHops = hops,
		expiresAt = expires,
		hops = hops - 1,
	}
	s.interests[key] = lease
	RememberInterest(s, key, now)
	self:RecordMeshPeerActivity(sender)
	SendInterest(self, s, lease)
	if self.ReplayMeshPublicationsForInterest then
		self:ReplayMeshPublicationsForInterest(lease)
	end
	Metric(s, "interestsAccepted")
	return true
end
local function Alternative(a, s, lease, exclude)
	for name in pairs(lease.alternates or {}) do
		if name ~= exclude and Neighbor(a, s, name) then
			return name
		end
	end
end
RetirePeerRoutes = function(a, s, name)
	for key, lease in pairs(s.interests) do
		lease.alternates[name] = nil
		if lease.upstream == name then
			local alternate = Alternative(a, s, lease, name)
			if alternate then
				lease.upstream = alternate
				lease.alternates[alternate] = nil
			end
		end
		if lease.destination == name or lease.upstream == name then
			s.interests[key] = nil
			CancelInterest(a, s, lease)
		else
			lease.downstreams[name] = nil
			if lease.coveredDownstreams then
				lease.coveredDownstreams[name] = nil
			end
			if lease.interestSends then
				lease.interestSends[name] = nil
			end
		end
	end
	for _, lease in pairs(s.localHistory) do
		lease.downstreams[name] = nil
		if lease.coveredDownstreams then
			lease.coveredDownstreams[name] = nil
		end
		if lease.interestSends then
			lease.interestSends[name] = nil
		end
		if Count(lease.downstreams) == 0 then
			lease.renewAt = math.min(lease.renewAt or Now(a), Now(a))
		end
	end
end
function QT:HandleMeshInterestCancel(record, sender, context)
	local s = rawget(self, "meshNetworkState")
	local destination = Name(self, record.destination)
	if
		not s
		or not Current(self, s)
		or not destination
		or type(record.leaseId) ~= "string"
		or not context
		or context.distribution ~= "WHISPER"
	then
		return false
	end
	local key = Key(destination, record.leaseId)
	local lease = s.interests[key]
	sender = Name(self, sender)
	if not lease then
		return false
	end
	if lease.upstream ~= sender then
		if lease.alternates[sender] then
			lease.alternates[sender] = nil
			return true
		end
		return false
	end
	local alternate = Alternative(self, s, lease, sender)
	if alternate then
		lease.upstream = alternate
		lease.alternates[alternate] = nil
		return true
	end
	s.interests[key] = nil
	CancelInterest(self, s, lease)
	return true
end
local function UpdateInterests(a, s, now)
	local own = Own(a)
	if not own then
		return
	end
	local geo = rawget(a, "geographicCommsState")
	local wanted = { [0] = true }
	if geo then
		if ValidZone(a, geo.currentZone) then
			wanted[geo.currentZone] = true
		end
		if a:GetOption("showPlayerLocations") == true and ValidZone(a, geo.viewZone) then
			wanted[geo.viewZone] = true
		end
	end
	for zone, lease in pairs(s.localInterests) do
		if not wanted[zone] then
			s.localInterests[zone] = nil
		end
	end
	for key, lease in pairs(s.localHistory) do
		if not wanted[lease.zone] or Server(a) >= lease.expiresAt then
			s.localHistory[key] = nil
			CancelInterest(a, s, lease)
		end
	end
	for zone in pairs(wanted) do
		local lease = s.localInterests[zone]
		if not lease or now >= lease.renewAt then
			s.serial = s.serial + 1
			lease = {
				id = s.communication.session .. "-m" .. s.serial,
				destination = own,
				zone = zone,
				renewAt = now + RENEW_SECONDS,
				downstreams = {},
				hops = MAX_HOPS,
				expiresAt = Server(a) + LEASE_SECONDS,
			}
			s.localInterests[zone] = lease
			s.localHistory[Key(lease.destination, lease.id)] = lease
			if lease.destination then
				SendInterest(a, s, lease)
			end
		end
	end
	for key, lease in pairs(s.interests) do
		if not Neighbor(a, s, lease.upstream) then
			local alternate = Alternative(a, s, lease, lease.upstream)
			if alternate then
				lease.upstream = alternate
				lease.alternates[alternate] = nil
			end
		end
		if Server(a) >= lease.expiresAt or not Neighbor(a, s, lease.upstream) then
			s.interests[key] = nil
			CancelInterest(a, s, lease)
		end
	end
	for _, lease in pairs(s.localHistory) do
		RetryInterests(a, s, lease)
	end
	for _, lease in pairs(s.interests) do
		RetryInterests(a, s, lease)
	end
	for key, expires in pairs(s.interestHistory) do
		if Server(a) >= expires then
			s.interestHistory[key] = nil
		end
	end
end
local function IncomingLease(a, s, sender, metadata, scope, origin)
	if type(metadata) ~= "table" or not sender or not Neighbor(a, s, sender) then
		return nil
	end
	if
		metadata.sharedDelivery ~= nil
		and (
			type(metadata.sharedDelivery) ~= "boolean"
			or metadata.sharedDelivery and not Neighbor(a, s, sender).sharedDelivery
		)
	then
		return nil
	end
	local destination, zone = Name(a, metadata.destination), ValidZone(a, metadata.zone)
	local hops = a:SafeToNumber(metadata.hops)
	if
		not destination
		or not zone
		or zone ~= Zone(scope)
		or type(metadata.leaseId) ~= "string"
		or #metadata.leaseId > 80
		or not hops
		or hops < 1
		or hops > MAX_HOPS
		or hops ~= math.floor(hops)
	then
		return nil
	end
	local lease = a:IsSelfSender(destination) and s.localHistory[Key(destination, metadata.leaseId)]
		or s.interests[Key(destination, metadata.leaseId)]
	local directOwner = a:IsSelfSender(destination) and Name(a, origin) == sender
	if
		not lease
		or lease.id ~= metadata.leaseId
		or lease.destination ~= destination
		or lease.zone ~= zone
		or Server(a) >= lease.expiresAt
		or (not lease.downstreams[sender] and not directOwner)
	then
		return nil
	end
	return lease
end
function QT:CanAcceptMeshPublicationRoute(sender, metadata, scope, origin)
	local s = rawget(self, "meshNetworkState")
	return s ~= nil and Current(self, s) and IncomingLease(self, s, Name(self, sender), metadata, scope, origin) ~= nil
end
function QT:ShouldConsumeMeshPublicationRoute(sender, metadata, scope, origin)
	if not self:CanAcceptMeshPublicationRoute(sender, metadata, scope, origin) then
		return false
	end
	local s = self.meshNetworkState
	local localLease = s.localInterests[Zone(scope)]
	return self:IsSelfSender(metadata.destination) or localLease ~= nil and Server(self) < localLease.expiresAt
end
local function PublicationTarget(a, s, publication, lease)
	local direct = a:IsSelfSender(publication.origin) and Neighbor(a, s, lease.destination)
	return direct and lease.destination or lease.upstream
end
local function PublicationDeliveryKey(a, s, publication, lease, target)
	local peer = Neighbor(a, s, target)
	if not peer then
		return nil
	end
	return table.concat({
		publication.origin,
		publication.session,
		publication.id,
		publication.digest,
		tostring(lease.zone),
		target,
		tostring(peer.session or ""),
		peer.sharedDelivery and "shared" or lease.destination,
	}, ":")
end
function QT:HasDeliveredMeshPublicationForInterest(publication, lease)
	local s = rawget(self, "meshNetworkState")
	if
		not s
		or not Current(self, s)
		or type(publication) ~= "table"
		or type(publication.digest) ~= "string"
		or not lease
		or s.interests[Key(lease.destination, lease.id)] ~= lease
		or lease.zone ~= Zone(publication.scope)
		or Server(self) >= lease.expiresAt
	then
		return false
	end
	local target = PublicationTarget(self, s, publication, lease)
	if not target or target == publication.origin then
		return false
	end
	local key = PublicationDeliveryKey(self, s, publication, lease, target)
	local previous = key and s.forwarded[key]
	return previous ~= nil and previous.completed == true and Server(self) < previous.expiresAt
end
function QT:ForwardMeshPublication(publication, descriptor)
	descriptor = descriptor or {}
	local s = rawget(self, "meshNetworkState")
	local zone = Zone(publication.scope)
	if not s or not Current(self, s) or not zone or not IsCurrent(descriptor.isCurrent) then
		Invoke(descriptor.onComplete, false, "cancelled")
		return false, "cancelled"
	end
	local selected = {}
	local function LeaseCurrent(lease)
		return s.interests[Key(lease.destination, lease.id)] == lease
			and lease.zone == zone
			and Server(self) < lease.expiresAt
	end
	if descriptor.meshInterest then
		local lease = descriptor.meshInterest
		local hops = descriptor.meshReplayHops
		if hops == nil and self:IsSelfSender(publication.origin) then
			hops = MAX_HOPS
		end
		if
			type(hops) ~= "number"
			or hops < 1
			or hops > MAX_HOPS
			or hops ~= math.floor(hops)
			or not LeaseCurrent(lease)
			or not Neighbor(self, s, lease.upstream)
		then
			Invoke(descriptor.onComplete, false, "cancelled")
			return false, "cancelled"
		end
		local target = PublicationTarget(self, s, publication, lease)
		if target ~= publication.origin then
			selected[1] = { lease = lease, target = target, hops = hops }
		end
	else
		local hops = MAX_HOPS
		if descriptor.relaySender then
			local metadata = descriptor.relaymeta
			local incoming = IncomingLease(
				self,
				s,
				Name(self, descriptor.relaySender),
				metadata,
				publication.scope,
				publication.origin
			)
			if not incoming or metadata.hops <= 1 then
				Invoke(descriptor.onComplete, false, "no-interest")
				return false, "no-interest"
			end
			hops = metadata.hops - 1
		end
		local newest = {}
		for _, lease in pairs(s.interests) do
			if
				lease.zone == zone
				and Server(self) < lease.expiresAt
				and Neighbor(self, s, lease.upstream)
				and lease.destination ~= publication.origin
			then
				local previous = newest[lease.destination]
				if not previous or lease.expiresAt > previous.expiresAt then
					newest[lease.destination] = lease
				end
			end
		end
		for _, lease in pairs(newest) do
			local target = PublicationTarget(self, s, publication, lease)
			if target ~= descriptor.relaySender and target ~= publication.origin then
				selected[#selected + 1] = { lease = lease, target = target, hops = hops }
			end
		end
	end
	if #selected == 0 then
		Invoke(descriptor.onComplete, false, "no-interest")
		return false, "no-interest"
	end
	table.sort(selected, function(left, right)
		local lkey, rkey = Key(left.lease.destination, tostring(zone)), Key(right.lease.destination, tostring(zone))
		local lserved, rserved = s.destinations[lkey] or 0, s.destinations[rkey] or 0
		if lserved ~= rserved then
			return lserved < rserved
		end
		return lkey < rkey
	end)
	-- One authenticated object satisfies every matching reverse subscription
	-- on an upgraded next hop. Legacy next hops retain destination envelopes.
	local grouped, byLink = {}, {}
	for _, item in ipairs(selected) do
		local peer = Neighbor(self, s, item.target)
		local link = peer and peer.sharedDelivery and item.target
		if link and byLink[link] then
			local group = byLink[link]
			group.leases[#group.leases + 1] = item.lease
			Metric(s, "publicationSharedCopiesSaved")
		else
			item.leases = { item.lease }
			grouped[#grouped + 1] = item
			if link then
				byLink[link] = item
			end
		end
	end
	selected = grouped
	local remaining, any, failed, finished = #selected, false, nil, false
	local function Complete(sent, reason)
		remaining = remaining - 1
		any = any or sent
		if not sent then
			failed = reason
		end
		if remaining == 0 and not finished then
			finished = true
			Invoke(descriptor.onComplete, any, any and "accepted" or failed or "rejected")
		end
	end
	local admitted = false
	for _, item in ipairs(selected) do
		local lease, target = item.lease, item.target
		local serviceKey = Key(lease.destination, tostring(zone))
		if not s.destinations[serviceKey] and Count(s.destinations) >= 64 then
			local oldest, at
			for key, served in pairs(s.destinations) do
				if not at or served < at then
					oldest, at = key, served
				end
			end
			if oldest then
				s.destinations[oldest] = nil
			end
		end
		local function Served()
			s.serviceSerial = s.serviceSerial + 1
			s.destinations[serviceKey] = s.serviceSerial
		end
		local duplicateKey = PublicationDeliveryKey(self, s, publication, lease, target)
		local pendingKey = duplicateKey
		if not duplicateKey then
			Complete(false, "cancelled")
		else
			local previous = s.forwarded[duplicateKey] or s.pendingPublications[pendingKey]
			if previous and Server(self) < previous.expiresAt then
				if previous.completed then
					Complete(true, "duplicate")
					admitted = true
				elseif previous.destination ~= lease.destination then
					Complete(false, "pending")
				elseif #previous.waiters < 8 then
					previous.waiters[#previous.waiters + 1] = Complete
					admitted = true
				else
					Complete(false, "capacity")
				end
				Metric(s, "publicationDuplicates")
			else
				if Count(s.forwarded) >= 512 then
					local oldest, at
					for key, entry in pairs(s.forwarded) do
						if not at or entry.at < at then
							oldest, at = key, entry.at
						end
					end
					if oldest then
						s.forwarded[oldest] = nil
					end
				end
				local reservation = {
					at = Now(self),
					destination = lease.destination,
					expiresAt = Neighbor(self, s, target).sharedDelivery and publication.expiresAt
						or math.min(publication.expiresAt or Server(self) + 15, lease.expiresAt),
					waiters = {},
					pendingKeys = {},
				}
				s.forwarded[duplicateKey] = reservation
				s.pendingPublications[pendingKey] = reservation
				local copy = {}
				for key, value in pairs(descriptor) do
					copy[key] = value
				end
				copy.owner, copy.meshTraffic = lease, true
				copy.expires = math.min(
					descriptor.expires or Now(self) + 15,
					Now(self) + math.max(0, lease.expiresAt - Server(self))
				)
				copy.key = descriptor.key and (descriptor.key .. ":" .. lease.destination .. ":" .. lease.zone) or nil
				local complete = false
				local tried, attempts = {}, 0
				local function FinishDelivery(sent, reason, deliveryKey, peer)
					if complete then
						return
					end
					complete = true
					for key in pairs(reservation.pendingKeys) do
						if s.pendingPublications[key] == reservation then
							s.pendingPublications[key] = nil
						end
					end
					if s.pendingPublications[pendingKey] == reservation then
						s.pendingPublications[pendingKey] = nil
					end
					reservation.completed = sent == true
					if (not sent or deliveryKey ~= duplicateKey) and s.forwarded[duplicateKey] == reservation then
						s.forwarded[duplicateKey] = nil
					end
					if sent then
						reservation.expiresAt = peer.sharedDelivery and publication.expiresAt
							or math.min(publication.expiresAt or Server(self) + 15, lease.expiresAt)
						s.forwarded[deliveryKey] = reservation
					end
					Complete(sent, reason)
					local waiters = reservation.waiters
					reservation.waiters = {}
					for _, waiter in ipairs(waiters) do
						local matched = sent and lease.destination == reservation.destination
						waiter(matched, matched and reason or reason == "acknowledged" and "pending" or reason)
					end
				end
				local function Send(nextTarget)
					attempts = attempts + 1
					tried[nextTarget] = true
					local routeLease = lease
					local deliveryKey = PublicationDeliveryKey(self, s, publication, lease, nextTarget)
					local peer = Neighbor(self, s, nextTarget)
					if not deliveryKey or not peer then
						FinishDelivery(false, "cancelled")
						return
					end
					local peerSession = peer.session
					local attempt = {}
					for key, value in pairs(copy) do
						attempt[key] = value
					end
					attempt.owner = routeLease
					attempt.key = descriptor.key
							and (descriptor.key .. ":" .. routeLease.destination .. ":" .. routeLease.zone)
						or nil
					attempt.expires = math.min(
						descriptor.expires or Now(self) + 15,
						Now(self) + math.max(0, routeLease.expiresAt - Server(self))
					)
					attempt.isCurrent = function()
						return Current(self, s)
							and IsCurrent(descriptor.isCurrent)
							and LeaseCurrent(routeLease)
							and Neighbor(self, s, nextTarget) ~= nil
							and Neighbor(self, s, nextTarget).session == peerSession
					end
					local called = false
					attempt.onComplete = function(sent, reason)
						if complete or called then
							return
						end
						called = true
						if sent and not attempt.isCurrent() then
							sent, reason = false, "cancelled"
						end
						local retryable = reason ~= "capacity"
							and reason ~= "superseded"
							and reason ~= "cancelled"
							and reason ~= "expired"
							and reason ~= "pending"
						if not sent and attempts < 3 and Current(self, s) and IsCurrent(descriptor.isCurrent) then
							-- A queued representative can disappear while another
							-- subscriber still needs this same common link.
							if not LeaseCurrent(routeLease) then
								for _, candidate in ipairs(item.leases) do
									if
										candidate ~= routeLease
										and LeaseCurrent(candidate)
										and Neighbor(self, s, target)
									then
										lease = candidate
										Send(target)
										return
									end
								end
							elseif retryable then
								for _, candidate in ipairs(item.leases) do
									if LeaseCurrent(candidate) then
										for alternate in pairs(candidate.alternates or {}) do
											if
												not tried[alternate]
												and alternate ~= descriptor.relaySender
												and alternate ~= publication.origin
												and Neighbor(self, s, alternate)
											then
												lease = candidate
												Metric(s, "publicationFailovers")
												Send(alternate)
												return
											end
										end
									end
								end
							end
						end
						FinishDelivery(sent, reason, deliveryKey, peer)
					end
					local prior = s.forwarded[deliveryKey] or s.pendingPublications[deliveryKey]
					if prior and prior ~= reservation and Server(self) < prior.expiresAt then
						attempt.onComplete(prior.completed == true, prior.completed and "duplicate" or "pending")
						return
					end
					s.pendingPublications[deliveryKey], reservation.pendingKeys[deliveryKey] = reservation, true
					local accepted, reason = self:SendMeshPublicationToPeer(publication, nextTarget, {
						leaseId = lease.id,
						destination = lease.destination,
						zone = lease.zone,
						hops = item.hops,
						sharedDelivery = peer.sharedDelivery and true or nil,
					}, attempt)
					admitted = admitted or accepted
					if accepted then
						Served()
					end
					if not accepted then
						attempt.onComplete(false, reason)
					end
				end
				Send(target)
			end
		end
	end
	Metric(s, descriptor.relaySender and "publicationRelays" or "publicationFanouts")
	return admitted, admitted and "queued" or failed or "rejected"
end
function QT:RetireMeshPeer(value, reason)
	local s = rawget(self, "meshNetworkState")
	local name = Name(self, value)
	if not s or not name then
		return
	end
	local retirement = self:CanAccessValue(reason)
			and type(reason) == "string"
			and ({ unavailable = true, rotated = true, expired = true, ignored = true })[reason]
			and reason
		or "retired"
	local names = { name }
	if retirement == "unavailable" then
		-- Native failure correlation compares complete addresses without case.
		-- Directory/chat spellings can differ from the confirmed peer's spelling;
		-- retire those aliases too, retaining the realm or Forever surname.
		-- Every admitted routing peer has a bounded candidate entry.
		local key = name:lower()
		for candidate in pairs(s.candidates) do
			if candidate ~= name and candidate:lower() == key then
				names[#names + 1] = candidate
			end
		end
	end
	for _, retiredName in ipairs(names) do
		if rawget(self, "meshNetworkState") ~= s then
			return
		end
		local pending, peer = s.pending[retiredName], s.neighbors[retiredName]
		s.admissionIntents[retiredName] = nil
		s.pendingInterests[retiredName] = nil
		s.pending[retiredName], s.neighbors[retiredName], s.reservations[retiredName] = nil, nil, nil
		if pending then
			self:CancelCommunicationOwner(pending, "cancelled")
		end
		if peer then
			self:CancelCommunicationOwner(peer, "cancelled")
		end
		RetirePeerRoutes(self, s, retiredName)
		local candidate = s.candidates[retiredName]
		if candidate then
			local now = Now(self)
			candidate.lastRetirementReason, candidate.lastRetiredAt = retirement, now
			if pending and retirement == "unavailable" then
				candidate.lastHandshakeOutcome, candidate.lastHandshakeReason = "unavailable", "unavailable"
				candidate.lastHandshakeAt, candidate.lastHandshakeCode = now, nil
				Metric(s, "handshakeUnavailable")
			end
			RetryCandidate(self, candidate, now, retirement == "unavailable")
		end
		if self:IsIgnoredPlayerName(retiredName) then
			s.candidates[retiredName] = nil
			ForgetFailure(self, retiredName)
			local seeds = SeedStore(self)
			if seeds then
				seeds[retiredName] = nil
			end
		end
	end
end
function QT:RecordMeshPeerActivity(value)
	local s = rawget(self, "meshNetworkState")
	local name = Name(self, value)
	local peer = s and name and s.neighbors[name]
	if peer and not self:IsIgnoredPlayerName(name) then
		peer.expires = Now(self) + NEIGHBOR_SECONDS
	end
end
local function UsefulPeer(s, name)
	local useful = 0
	for _, lease in pairs(s.interests) do
		if lease.upstream == name then
			useful = useful + 1
		end
	end
	return useful
end
MakeReplacementRoom = function(a, s, replacement)
	if not Current(a, s) or a:IsIgnoredPlayerName(replacement) then
		return false
	end
	if Neighbor(a, s, replacement) or Reserved(a, s, replacement) or Count(s.neighbors) < MAX_NEIGHBORS then
		return true
	end
	local victim, usefulness, age
	for name, peer in pairs(s.neighbors) do
		local current, connectedAt = UsefulPeer(s, name), peer.connectedAt or peer.at or Now(a)
		if
			not s.pending[name]
			and (not usefulness or current < usefulness or current == usefulness and connectedAt < age)
		then
			victim, usefulness, age = name, current, connectedAt
		end
	end

	if not victim then
		return false
	end
	a:RetireMeshPeer(victim, "rotated")
	if not Current(a, s) then
		return false
	end
	Metric(s, "neighborRotations")
	s.nextRotation = Now(a) + 120
	return true
end
local function RotateNeighbor(a, s, now)
	PruneAdmissionIntents(a, s, now)
	local waiting, queuedAt
	for name, intent in pairs(s.admissionIntents) do
		if
			not s.pending[name]
			and (not queuedAt or intent.queuedAt < queuedAt or intent.queuedAt == queuedAt and name < waiting)
		then
			waiting, queuedAt = name, intent.queuedAt
		end
	end
	local function AdmitWaiting()
		if not waiting then
			return false
		end
		local reserved, reason = Reserve(a, s, waiting, true)
		if reserved then
			-- The caller's native hello permits the same reciprocal retry as an
			-- immediately admitted hello. A failure after it arrived was pruned.
			local candidate = s.candidates[waiting]
			candidate.retryAt = math.min(candidate.retryAt, now)
			s.nextHandshake = math.min(s.nextHandshake, math.max(now, (s.lastHandshakeAt or now - 1) + 1))
			s.admissionIntents[waiting] = nil
			Metric(s, "admissionReservations")
		end
		return reserved, reason
	end
	-- Reservation expiry can make space without retiring a healthy neighbor.
	-- Claim it before generic candidates run through the handshake scheduler.
	local admitted, blocked = AdmitWaiting()
	if admitted or blocked == "reciprocal_capacity" then
		return
	end
	if now < s.nextRotation or not waiting and Count(s.neighbors) < MAX_NEIGHBORS then
		return
	end
	if not waiting then
		return
	end

	-- A queued hello can be several minutes old. Challenge that caller first;
	-- only its fresh reply (or crossed native hello) can replace a live edge.
	local candidate = s.candidates[waiting]
	candidate.retryAt = math.min(candidate.retryAt, now)
	s.nextHandshake = math.min(s.nextHandshake, now)
end
function QT:UpdateMeshNetwork(now)
	self:RestoreMeshDirectorySelection()
	if not self.isEnabled or self.isLoggingOut then
		return
	end
	local s = self:InitializeMeshNetwork()
	now = now or Now(self)
	if now < s.startedAt then
		self:ResetMeshNetwork()
		return
	end
	if now < s.nextTick then
		return
	end
	s.nextTick = now + 0.2
	if not Allowed(self) then
		DirectoryRestore(self, s)
		return
	end
	for _, name in ipairs(self.partyMemberOrder or {}) do
		self:RememberMeshCandidate(name, "party")
	end
	self:EnsureMeshDirectoryJoined(self.announcementChannelName)
	local wanted = DirectoryWanted(self)
	for channel in pairs(s.directoryCursors) do
		if not wanted[channel] then
			s.directoryCursors[channel] = nil
		end
	end
	for channel in pairs(s.joins) do
		if not wanted[channel] then
			s.joins[channel] = nil
		end
	end
	for name, peer in pairs(s.neighbors) do
		local ignored = self:IsIgnoredPlayerName(name)
		if now >= peer.expires or ignored then
			self:RetireMeshPeer(name, ignored and "ignored" or "expired")
		end
	end
	for name, reservation in pairs(s.reservations) do
		if now >= reservation.expires or self:IsIgnoredPlayerName(name) then
			s.reservations[name] = nil
		end
	end
	for name, items in pairs(s.pendingInterests) do
		if not Reserved(self, s, name) then
			s.pendingInterests[name] = nil
			for _ = 1, #items do
				Metric(s, "pendingInterestDrops")
			end
		else
			for index = #items, 1, -1 do
				if Server(self) >= items[index].record.expiresAt then
					table.remove(items, index)
					Metric(s, "pendingInterestDrops")
				end
			end
			if #items == 0 then
				s.pendingInterests[name] = nil
			end
		end
	end
	for key, entry in pairs(s.forwarded) do
		if Server(self) >= entry.expiresAt then
			s.forwarded[key] = nil
		end
	end
	for key, selection in pairs(s.interestSelections) do
		if now >= selection.expires then
			s.interestSelections[key] = nil
		end
	end
	for key, entry in pairs(s.pendingPublications) do
		if Server(self) >= entry.expiresAt then
			s.pendingPublications[key] = nil
		end
	end
	local directoryRows = s.metrics.directoryRows or 0
	DirectoryStep(self, s, now)
	local remainingRows = ROWS_PER_TICK - ((s.metrics.directoryRows or 0) - directoryRows)
	remainingRows = remainingRows - GuildStep(self, s, now, remainingRows)
	ContactStep(self, s, now, remainingRows)
	UpdateInterests(self, s, now)
	RotateNeighbor(self, s, now)
	if now >= s.nextHandshake and Count(s.pending) < MAX_PENDING then
		local selected
		local geo = rawget(self, "geographicCommsState")
		local preferContact = (s.metrics.handshakesStarted or 0) % 3 == 0
		local function Rank(candidate)
			local zone = candidate.zone
			local relevant = zone and geo and (zone == geo.currentZone or zone == geo.viewZone)
			-- Alternate relevant geographic candidates with random candidates;
			-- sorted names alone can strand a crowded directory in cliques.
			local preferZone = (s.metrics.handshakesStarted or 0) % 2 == 0
			return (preferZone and relevant and -2000000 or 0) + (candidate.rank or 0)
		end
		local function Tier(candidate)
			local reservation = Reserved(self, s, candidate.name)
			if reservation and reservation.reciprocal then
				return 3
			end
			if s.admissionIntents[candidate.name] then
				return 2
			end
			if preferContact and candidate.contactAt and now - candidate.contactAt < CONTACT_SECONDS then
				return 1
			end
			return 0
		end
		local function Prefer(candidate, previous)
			if not previous then
				return true
			end
			local tier, previousTier = Tier(candidate), Tier(previous)
			if tier ~= previousTier then
				return tier > previousTier
			end
			if tier == 2 then
				local one, two = s.admissionIntents[candidate.name], s.admissionIntents[previous.name]
				return one.queuedAt < two.queuedAt or one.queuedAt == two.queuedAt and candidate.name < previous.name
			end
			-- A newly heard stranger must not jump ahead of every retried contact.
			-- Discovery time remains fixed when later chat/roster sightings arrive.
			local waiting = candidate.triedAt or candidate.discoveredAt or s.startedAt
			local previousWaiting = previous.triedAt or previous.discoveredAt or s.startedAt
			if waiting ~= previousWaiting then
				return waiting < previousWaiting
			end
			return Rank(candidate) < Rank(previous)
		end
		for name, candidate in pairs(s.candidates) do
			local peer = s.neighbors[name]
			local renew = peer and now - peer.at >= CHALLENGE_SECONDS
			if
				not s.pending[name]
				and now >= candidate.retryAt
				and (renew or not peer and (Count(s.neighbors) < MAX_NEIGHBORS or now >= s.nextRotation))
				and (renew or ProbeEligible(self, candidate))
				and not self:IsIgnoredPlayerName(name)
				and Prefer(candidate, selected)
			then
				selected = candidate
			end
		end
		if selected then
			if
				(s.metrics.handshakesStarted or 0) >= 3
				and now < (s.regularHandshakeAt or 0)
				and DiscoveryPressure(self)
			then
				-- Optional bootstrap acceleration yields to queued payloads,
				-- authentication and native throttling. Normal maintenance still
				-- runs at its existing paced deadline.
				s.nextHandshake = math.min(s.regularHandshakeAt, now + 2)
				Metric(s, "bootstrapPressureDeferrals")
			else
				StartHandshake(self, s, selected)
			end
		end
	end
end
function QT:GetMeshDepartureRoutes()
	local s = rawget(self, "meshNetworkState")
	local routes = {}
	for name in pairs(s and s.neighbors or {}) do
		if Neighbor(self, s, name) and #routes < MAX_NEIGHBORS then
			routes[#routes + 1] = { distribution = "WHISPER", target = name, meshTraffic = true }
		end
	end
	return routes
end
function QT:GetMeshNetworkMetrics()
	local s = rawget(self, "meshNetworkState")
	local metrics = { neighbors = 0, candidates = 0, handshakes = 0, interests = 0 }
	if not s then
		return metrics
	end
	for key, value in pairs(s.metrics) do
		metrics[key] = value
	end
	metrics.neighbors, metrics.candidates, metrics.handshakes, metrics.interests =
		Count(s.neighbors), Count(s.candidates), Count(s.pending), Count(s.interests)
	metrics.admissionIntents, metrics.reservations = Count(s.admissionIntents), Count(s.reservations)
	metrics.failureHistory, metrics.candidatesCoolingDown, metrics.candidatesExhausted = Count(s.failureRows), 0, 0
	local now, stamp = Now(self), Server(self)
	for _, candidate in pairs(s.candidates) do
		if candidate.delay and candidate.retryAt > now then
			metrics.candidatesCoolingDown = metrics.candidatesCoolingDown + 1
		end
		if
			(candidate.probeFailures or 0) >= MAX_STALE_PROBES
			and stamp - (candidate.failureAt or stamp) < FAILURE_LIFETIME
			and (candidate.evidenceAt or 0) <= (candidate.failureEvidenceAt or 0)
			and (candidate.evidenceSerial or 0) <= (candidate.failureEvidenceSerial or 0)
		then
			metrics.candidatesExhausted = metrics.candidatesExhausted + 1
		end
	end
	metrics.pendingInterests = 0
	for _, items in pairs(s.pendingInterests) do
		metrics.pendingInterests = metrics.pendingInterests + #items
	end
	metrics.localInterests = Count(s.localInterests)
	local audiences = {}
	for _, lease in pairs(s.interests) do
		audiences[Key(lease.destination, tostring(lease.zone))] = true
	end
	metrics.interestAudiences = Count(audiences)
	metrics.localRoutes = Count(s.localHistory)
	metrics.queryHistory = Count(s.interestHistory)
	metrics.querySelections = Count(s.interestSelections)
	metrics.publicationRoutes = Count(s.forwarded)
	metrics.pendingPublications = Count(s.pendingPublications)
	metrics.oldestNeighborIdle, metrics.oldestHandshakeAge = 0, 0
	metrics.oldestAdmissionIntentAge = 0
	for _, intent in pairs(s.admissionIntents) do
		metrics.oldestAdmissionIntentAge = math.max(metrics.oldestAdmissionIntentAge, now - intent.queuedAt)
	end
	for _, peer in pairs(s.neighbors) do
		metrics.oldestNeighborIdle = math.max(metrics.oldestNeighborIdle, now - (peer.expires - NEIGHBOR_SECONDS))
	end
	for name in pairs(s.pending) do
		local candidate = s.candidates[name]
		metrics.oldestHandshakeAge =
			math.max(metrics.oldestHandshakeAge, now - (candidate and candidate.triedAt or now))
	end
	return metrics
end
function QT:ResetMeshNetwork()
	local s = rawget(self, "meshNetworkState")
	if not s then
		return
	end
	DirectoryRestore(self, s)
	self.meshNetworkState = nil
	self:CancelCommunicationOwner(s, "cancelled")
	for _, collection in ipairs({ s.pending, s.neighbors, s.localHistory, s.interests }) do
		for _, owner in pairs(collection) do
			self:CancelCommunicationOwner(owner, "cancelled")
		end
	end
end
