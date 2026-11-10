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
local MAX_DIRECTORY_ROWS, ROWS_PER_TICK = 1500, 32
local CONTACT_SECONDS, CONTACT_EVENT_SECONDS, CONTACT_EVENT_LIMIT = 300, 10, 16
local CONTACT_SOURCES = { friend = true, bnet = true, chat = true, visible = true }
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
local function RetryCandidate(row, now)
	row.delay = math.min(1800, math.max(300, (row.delay or 150) * 2))
	row.retryAt = now + row.delay
	row.failureSerial = (row.failureSerial or 0) + 1
end
local function RetireOldestCandidate(s, now)
	local oldest, at
	for name, candidate in pairs(s.candidates) do
		if not s.neighbors[name] and not s.pending[name] and not s.reservations[name]
			and not (s.admissionIntents and s.admissionIntents[name])
			and candidate.retryAt <= now
			and (not candidate.contactAt or now - candidate.contactAt >= CONTACT_SECONDS)
			and (not at or candidate.heardAt < at) then
			oldest, at = name, candidate.heardAt
		end
	end
	if not oldest then return false end
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
local function SeedStore(a)
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
	if type(global.meshPeerSeeds) ~= "table" then
		global.meshPeerSeeds = {}
	end
	local key = namespace .. ":" .. character
	if type(global.meshPeerSeeds[key]) ~= "table" then
		global.meshPeerSeeds[key] = {}
	end
	return global.meshPeerSeeds[key]
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
	local seeds, stamp = SeedStore(self), Server(self)
	local loaded = 0
	for name, at in pairs(seeds or {}) do
		at = self:SafeToNumber(at)
		if at and at <= stamp and stamp - at < SEED_LIFETIME and loaded < MAX_SEEDS then
			if self:RememberMeshCandidate(name, "saved") then
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
function QT:RememberMeshCandidate(value, source, zone)
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
		row = { name = name, retryAt = now, heardAt = now, discoveredAt = now, rank = random and random[1] or 0 }
		s.candidates[name] = row
		Metric(s, "candidatesAdded")
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
		if validZone then row.zone = validZone end
	end
	row.contactAt, row.contactSource = now, source
	return true
end

function QT:ObserveMeshUnit(unitToken)
	local s = rawget(self, "meshNetworkState")
	if not s or not Current(self, s) or not Allowed(self)
		or not self:CanAccessValue(unitToken) or type(unitToken) ~= "string"
		or not (unitToken == "target" or unitToken == "mouseover" or unitToken:match("^nameplate%d+$")) then
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
local function Confirm(a, s, name, context)
	local row = s.neighbors[name]
	local fresh = row == nil
	if not row and (not Reserved(a, s, name) or Count(s.neighbors) >= MAX_NEIGHBORS) then
		return nil
	end
	a:RememberMeshCandidate(name, "confirmed")
	local now = Now(a)
	row = row or { name = name, connectedAt = now }
	row.at, row.expires, row.session = now, now + NEIGHBOR_SECONDS, context and context.session
	s.neighbors[name] = row
	s.reservations[name] = nil
	s.admissionIntents[name] = nil
	local candidate = s.candidates[name]
	if candidate then
		candidate.delay, candidate.retryAt = nil, now + CHALLENGE_SECONDS
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
	return row
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
		if now >= intent.expiresAt or not candidate or Neighbor(a, s, name)
			or a:IsIgnoredPlayerName(name) or (candidate.failureSerial or 0) ~= intent.failureSerial then
			s.admissionIntents[name] = nil
			Metric(s, now >= intent.expiresAt and "admissionIntentsExpired" or "admissionIntentsCancelled")
		end
	end
end
local function QueueAdmissionIntent(a, s, name, candidate, now)
	PruneAdmissionIntents(a, s, now)
	if s.admissionIntents[name] then return end
	if Count(s.admissionIntents) >= MAX_PENDING then
		Metric(s, "admissionIntentDrops")
		return
	end
	-- Remember an explicit native protocol request, not a trusted edge. Do not
	-- let repeated hellos extend this wait or jump ahead of another caller.
	s.admissionIntents[name] = {
		queuedAt = now, expiresAt = now + ADMISSION_INTENT_SECONDS,
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
	return self:Respond(
		"MACK",
		{
			requestId = record.requestId,
			version = self.version or self.VERSION or "3",
			protocol = 3,
			capabilities = "mesh1",
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
	if not Reserve(a, s, name) then
		-- Local occupancy says nothing about this peer. Wait for a slot instead
		-- of imposing an unreachable-peer cooldown before any packet is sent.
		candidate.lastHandshakeOutcome, candidate.lastHandshakeAt = "local_capacity", now
		candidate.lastHandshakeReason, candidate.lastHandshakeCode = "capacity", nil
		s.nextHandshake = now + 1
		Metric(s, "handshakeCapacity")
		return
	end
	local pending = { submitting = true }
	s.pending[name] = pending
	candidate.triedAt = now
	local function Finish(success, outcome, reason, detail)
		if not Current(a, s) or s.pending[name] ~= pending then
			return
		end
		s.pending[name] = nil
		candidate.lastHandshakeOutcome, candidate.lastHandshakeAt = outcome, Now(a)
		candidate.lastHandshakeReason = a:CanAccessValue(reason) and type(reason) == "string"
			and #reason <= 64 and not reason:find("[%c|]") and reason or nil
		candidate.lastHandshakeCode = a:CanAccessValue(detail) and type(detail) == "number"
			and a:SafeToNumber(detail) or nil
		if not success then
			RetryCandidate(candidate, Now(a))
			local metric = ({ busy = "handshakeBusy", timeout = "handshakeTimeouts",
				admission_failed = "handshakeAdmissionFailures", send_failed = "handshakeSendFailures",
				queue_expired = "handshakeQueueExpiries", confirmation_failed = "handshakeConfirmationFailures",
				cancelled = "handshakeCancelled" })[outcome]
			if metric then Metric(s, metric) end
		end
	end
	local admitted, admissionReason, _, requestId = a:Request(
		"MHEL",
		{ version = a.version or a.VERSION or "3", protocol = 3, capabilities = "mesh1" },
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
					or pending.submitting and "admission_failed" or "send_failed"
				Finish(false, outcome, reason, detail)
			end,
			onResponse = function(record, sender, context)
				if
					not Current(a, s)
					or s.pending[name] ~= pending
					or Name(a, sender) ~= name
					or a:IsIgnoredPlayerName(name)
					or record.protocol ~= 3
					or record.capabilities ~= "mesh1"
				then
					return false
				end
				if record.admitted ~= true then
					Finish(false, "busy", "busy")
					a:CancelCommRequest(record.requestId, "rejected")
					return true
				end
				local confirmed = Confirm(a, s, name, context)
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
	local delay = 4
	if s.metrics.handshakesStarted >= 3 then
		local random = Native(a, "Random", 20, 30)
		delay = a:SafeToNumber(random and random[1]) or 25
		delay = math.min(30, math.max(20, delay))
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
	if budget < 1 then return end
	local job = s.contactDirectory
	if not job then
		if now < s.nextContacts then return end
		s.lastContactScan, s.nextContacts = now, now + CONTACT_SECONDS
		job = {
			friends = ContactCount(a, "GetMeshFriendCount"),
			bnet = ContactCount(a, "GetMeshBattleNetFriendCount"),
			friendVisited = 0, bnetVisited = 0, rows = 0,
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
			if result then a:ObserveMeshContact(result[1], "friend") end
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
				if result then a:ObserveMeshContact(result[1], "bnet") end
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
local function SendInterest(a, s, lease)
	if lease.hops <= 0 then
		return
	end
	-- Fanout is an upper bound, not a target to saturate. A renewed immutable
	-- query rotates its path, while forwarding just one branch leaves room for
	-- public data and authentication under the shared mesh allowance.
	local targets = NeighborTargets(a, s, lease.upstream, lease.destination, lease.upstream and 1 or 2, lease.zone)
	lease.downstreams = lease.downstreams or {}
	for _, target in ipairs(targets) do
		lease.downstreams[target] = true
		a:Emit(
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
				expires = Now(a) + 10,
				isCurrent = function()
					return Current(a, s) and Server(a) < lease.expiresAt and Neighbor(a, s, target) ~= nil
				end,
			}
		)
	end
	Metric(s, "interestForwards")
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
		or not Neighbor(self, s, sender)
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
	if Count(s.interests) >= MAX_INTERESTS then
		Metric(s, "interestCapacity")
		return false
	end
	local owned = 0
	for _, existing in pairs(s.interests) do
		if existing.upstream == sender then
			owned = owned + 1
		end
	end
	if owned >= 8 then
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
	return self:CanAcceptMeshPublicationRoute(sender, metadata, scope, origin)
		and self:IsSelfSender(metadata.destination)
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
	if descriptor.relaySender then
		local metadata = descriptor.relaymeta
		local lease = IncomingLease(self, s, Name(self, descriptor.relaySender), metadata, publication.scope)
		if lease and lease.upstream and metadata.hops > 1 then
			selected[1] = { lease = lease, target = lease.upstream, hops = metadata.hops - 1 }
		end
	else
		local newest = {}
		for _, lease in pairs(s.interests) do
			if lease.zone == zone and Server(self) < lease.expiresAt and Neighbor(self, s, lease.upstream) then
				local previous = newest[lease.destination]
				if not previous or lease.expiresAt > previous.expiresAt then
					newest[lease.destination] = lease
				end
			end
		end
		for _, lease in pairs(newest) do
			local direct = self:IsSelfSender(publication.origin) and Neighbor(self, s, lease.destination)
			selected[#selected + 1] =
				{ lease = lease, target = direct and lease.destination or lease.upstream, hops = MAX_HOPS }
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
		local duplicateKey = tostring(publication.origin)
			.. ":"
			.. tostring(publication.session)
			.. ":"
			.. tostring(publication.id)
			.. ":"
			.. tostring(publication.digest)
			.. ":"
			.. Key(lease.destination, tostring(zone))
		local pendingKey = duplicateKey
		duplicateKey = duplicateKey .. ":" .. lease.id
		local previous = s.forwarded[duplicateKey] or s.pendingPublications[pendingKey]
		if previous and Server(self) < previous.expiresAt then
			if previous.completed then
				Complete(true, "duplicate")
				admitted = true
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
				expiresAt = math.min(publication.expiresAt or Server(self) + 15, lease.expiresAt),
				waiters = {},
			}
			s.forwarded[duplicateKey] = reservation
			s.pendingPublications[pendingKey] = reservation
			local copy = {}
			for key, value in pairs(descriptor) do
				copy[key] = value
			end
			copy.owner, copy.meshTraffic = lease, true
			copy.expires =
				math.min(descriptor.expires or Now(self) + 15, Now(self) + math.max(0, lease.expiresAt - Server(self)))
			copy.key = descriptor.key and (descriptor.key .. ":" .. lease.destination .. ":" .. lease.zone) or nil
			local complete = false
			local tried = {}
			local function Send(nextTarget)
				tried[nextTarget] = true
				local attempt = {}
				for key, value in pairs(copy) do
					attempt[key] = value
				end
				attempt.isCurrent = function()
					return Current(self, s)
						and IsCurrent(descriptor.isCurrent)
						and Server(self) < lease.expiresAt
						and Neighbor(self, s, nextTarget) ~= nil
				end
				local called = false
				attempt.onComplete = function(sent, reason)
					if complete or called then
						return
					end
					called = true
					local retryable = reason ~= "capacity"
						and reason ~= "superseded"
						and reason ~= "cancelled"
						and reason ~= "expired"
					if
						not sent
						and retryable
						and Current(self, s)
						and IsCurrent(descriptor.isCurrent)
						and Server(self) < lease.expiresAt
					then
						for alternate in pairs(lease.alternates or {}) do
							if
								not tried[alternate]
								and alternate ~= descriptor.relaySender
								and Neighbor(self, s, alternate)
							then
								Metric(s, "publicationFailovers")
								Send(alternate)
								return
							end
						end
					end
					complete = true
					if s.pendingPublications[pendingKey] == reservation then
						s.pendingPublications[pendingKey] = nil
					end
					reservation.completed = sent == true
					if not sent and s.forwarded[duplicateKey] == reservation then
						s.forwarded[duplicateKey] = nil
					end
					Complete(sent, reason)
					local waiters = reservation.waiters
					reservation.waiters = {}
					for _, waiter in ipairs(waiters) do
						waiter(sent, reason)
					end
				end
				local accepted, reason = self:SendMeshPublicationToPeer(
					publication,
					nextTarget,
					{ leaseId = lease.id, destination = lease.destination, zone = lease.zone, hops = item.hops },
					attempt
				)
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
	Metric(s, descriptor.relaySender and "publicationRelays" or "publicationFanouts")
	return admitted, admitted and "queued" or failed or "rejected"
end
function QT:RetireMeshPeer(value, reason)
	local s = rawget(self, "meshNetworkState")
	local name = Name(self, value)
	if not s or not name then
		return
	end
	local pending, peer = s.pending[name], s.neighbors[name]
	s.admissionIntents[name] = nil
	s.pending[name], s.neighbors[name], s.reservations[name] = nil, nil, nil
	if pending then
		self:CancelCommunicationOwner(pending, "cancelled")
	end
	if peer then
		self:CancelCommunicationOwner(peer, "cancelled")
	end
	for key, lease in pairs(s.interests) do
		lease.alternates[name] = nil
		if lease.upstream == name then
			local alternate = Alternative(self, s, lease, name)
			if alternate then
				lease.upstream = alternate
				lease.alternates[alternate] = nil
			end
		end
		if lease.destination == name or lease.upstream == name then
			s.interests[key] = nil
			CancelInterest(self, s, lease)
		else
			lease.downstreams[name] = nil
		end
	end
	for _, lease in pairs(s.localHistory) do
		lease.downstreams[name] = nil
	end
	local candidate = s.candidates[name]
	if candidate then
		local now = Now(self)
		local retirement = self:CanAccessValue(reason) and type(reason) == "string"
			and ({ unavailable = true, rotated = true, expired = true, ignored = true })[reason] and reason or "retired"
		candidate.lastRetirementReason, candidate.lastRetiredAt = retirement, now
		if pending and retirement == "unavailable" then
			candidate.lastHandshakeOutcome, candidate.lastHandshakeReason = "unavailable", "unavailable"
			candidate.lastHandshakeAt, candidate.lastHandshakeCode = now, nil
			Metric(s, "handshakeUnavailable")
		end
		RetryCandidate(candidate, now)
	end
	if self:IsIgnoredPlayerName(name) then
		s.candidates[name] = nil
		local seeds = SeedStore(self)
		if seeds then
			seeds[name] = nil
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
local function RotateNeighbor(a, s, now)
	PruneAdmissionIntents(a, s, now)
	local waiting, queuedAt
	for name, intent in pairs(s.admissionIntents) do
		if not s.pending[name] and (not queuedAt or intent.queuedAt < queuedAt
			or intent.queuedAt == queuedAt and name < waiting) then
			waiting, queuedAt = name, intent.queuedAt
		end
	end
	local function AdmitWaiting()
		if not waiting then return false end
		local reserved, reason = Reserve(a, s, waiting, true)
		if reserved then
			-- The caller's native hello permits the same reciprocal retry as an
			-- immediately admitted hello. A failure after it arrived was pruned.
			local candidate = s.candidates[waiting]
			candidate.retryAt = math.min(candidate.retryAt, now)
			s.admissionIntents[waiting] = nil
			Metric(s, "admissionReservations")
		end
		return reserved, reason
	end
	-- Reservation expiry can make space without retiring a healthy neighbor.
	-- Claim it before generic candidates run through the handshake scheduler.
	local admitted, blocked = AdmitWaiting()
	if admitted or blocked == "reciprocal_capacity" then return end
	if now < s.nextRotation or not waiting and Count(s.neighbors) < MAX_NEIGHBORS then
		return
	end
	if not waiting then
		local alternate = false
		for name, candidate in pairs(s.candidates) do
			if not s.neighbors[name] and not s.pending[name] and candidate.retryAt <= now
				and not a:IsIgnoredPlayerName(name) then
				alternate = true
				break
			end
		end
		if not alternate then return end
	end
	local victim, usefulness, age
	for name, peer in pairs(s.neighbors) do
		local current = UsefulPeer(s, name)
		if
			not s.pending[name]
			and (not usefulness or current < usefulness or current == usefulness and peer.connectedAt < age)
		then
			victim, usefulness, age = name, current, peer.connectedAt
		end
	end
	if victim then
		a:RetireMeshPeer(victim, "rotated")
		if not Current(a, s) then return end
		Metric(s, "neighborRotations")
		s.nextRotation = now + 120
		AdmitWaiting()
	end
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
			if reservation and reservation.reciprocal then return 2 end
			if preferContact and candidate.contactAt and now - candidate.contactAt < CONTACT_SECONDS then return 1 end
			return 0
		end
		local function Prefer(candidate, previous)
			if not previous then return true end
			local tier, previousTier = Tier(candidate), Tier(previous)
			if tier ~= previousTier then return tier > previousTier end
			-- A newly heard stranger must not jump ahead of every retried contact.
			-- Discovery time remains fixed when later chat/roster sightings arrive.
			local waiting = candidate.triedAt or candidate.discoveredAt or s.startedAt
			local previousWaiting = previous.triedAt or previous.discoveredAt or s.startedAt
			if waiting ~= previousWaiting then return waiting < previousWaiting end
			return Rank(candidate) < Rank(previous)
		end
		for name, candidate in pairs(s.candidates) do
			local peer = s.neighbors[name]
			local renew = peer and now - peer.at >= CHALLENGE_SECONDS
			if
				not s.pending[name]
				and now >= candidate.retryAt
				and (renew or not peer and Count(s.neighbors) < MAX_NEIGHBORS)
				and not self:IsIgnoredPlayerName(name)
				and Prefer(candidate, selected)
			then
				selected = candidate
			end
		end
		if selected then
			StartHandshake(self, s, selected)
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
	metrics.localInterests = Count(s.localInterests)
	metrics.localRoutes = Count(s.localHistory)
	metrics.queryHistory = Count(s.interestHistory)
	metrics.querySelections = Count(s.interestSelections)
	metrics.publicationRoutes = Count(s.forwarded)
	metrics.pendingPublications = Count(s.pendingPublications)
	metrics.oldestNeighborIdle, metrics.oldestHandshakeAge = 0, 0
	local now = Now(self)
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
