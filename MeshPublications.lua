-- Immutable public mesh objects. A relay is a carrier, never an authority for
-- another player's identity. Native origin replies authenticate ordinary data;
-- the existing pinned-key verifiers authenticate developer/VIP proofs.
local QT = _G.QuestTogether
local MAX_BYTES, MAX_ENTRIES, MAX_PENDING, MAX_HASH_JOBS = 131072, 128, 32, 16
local MAX_BODY, MAX_CANONICAL, MAX_LIFETIME = 7000, 8192, 300
local AUTH_BATCH, AUTH_REQUESTS, AUTH_LIFETIME = 8, 8, 30
local PUBLIC_TOPICS = {
	QTPR = true,
	QTVR = true,
	QJST = true,
	QTLF = true,
	QTLQ = true,
	LOC = true,
	QTPG = true,
	QTCI = true,
	QTHI = true,
}
local FIELDS = { "origin", "session", "id", "operation", "scope", "originRequestId", "stamp", "expiresAt", "body" }

local function Now(a)
	return a.API.GetTime()
end
local function Wall(a)
	return a:GetAnnouncementServerTime()
end
local function Count(s, key)
	s.metrics[key] = (s.metrics[key] or 0) + 1
end
local function Copy(value)
	local result = {}
	for key, item in pairs(value or {}) do
		result[key] = item
	end
	return result
end
local function Name(a, name)
	if not a:CanAccessValue(name) or type(name) ~= "string" or #name > 120 or name:find("[%c|,]") then
		return nil
	end
	return a:NormalizeMemberName(name)
end
local function Scope(scope)
	if scope == "global" then
		return scope
	end
	local zone = tonumber(scope)
	if zone and zone >= 1 and zone <= 1000000 and zone == math.floor(zone) then
		return zone
	end
end
local function Identifier(value, limit)
	return type(value) == "string" and #value > 0 and #value <= limit and not value:find("[^%w%-]")
end
local function Hex(value)
	return (value:gsub(".", function(c)
		return string.format("%02x", c:byte())
	end))
end
local function Key(publication)
	return publication.origin
		.. "\001"
		.. publication.session
		.. "\001"
		.. publication.id
		.. "\001"
		.. publication.operation
		.. "\001"
		.. tostring(publication.scope)
end
local function ProofItem(publication)
	return {
		id = publication.id,
		operation = publication.operation,
		scope = tostring(publication.scope),
		digest = publication.digest,
	}
end
local function Current(a, s)
	return rawget(a, "meshPublicationState") == s
		and a.isEnabled
		and not a.isLoggingOut
		and rawget(a, "communicationState") == s.communication
		and not s.communication.departing
end
local function Predicate(callback)
	if not callback then
		return true
	end
	local ok, result = pcall(callback)
	return ok and result == true
end
local function Complete(entry, ok, reason)
	if entry.completed then
		return
	end
	entry.completed = true
	local callback = entry.descriptor and entry.descriptor.onComplete
	if callback then
		pcall(callback, ok, reason)
	end
end
local function State(a)
	local s = rawget(a, "meshPublicationState")
	if not s then
		s = {
			communication = a:InitializeCommunications(),
			entries = {},
			jobs = {},
			requests = {},
			count = 0,
			bytes = 0,
			pending = 0,
			metrics = {},
			nextAuth = 0,
			replay = {},
			nextReplay = 0,
			active = {},
		}
		a.meshPublicationState = s
	end
	return s
end
local function Installed(a, s, entry)
	return Current(a, s) and s.entries[entry.key] == entry and not entry.cancelled
end
local function EntryCurrent(a, s, entry)
	if not Installed(a, s, entry) then
		return false
	end
	local wall, publication, descriptor = Wall(a), entry.publication, entry.descriptor
	if
		not wall
		or wall >= publication.expiresAt
		or Now(a) >= entry.untilAt
		or a:IsIgnoredPlayerName(publication.origin)
		or not Installed(a, s, entry)
	then
		return false
	end
	if entry.owned then
		-- Producer predicates may synchronously cancel this entry, reset its
		-- session, or replace the same immutable key. Recheck ownership after
		-- each callback before reading fields or invoking another predicate.
		if not Predicate(descriptor.publicationCurrent) or not Installed(a, s, entry) then
			return false
		end
		if not (entry.exposed or entry.completed or Predicate(descriptor.isCurrent)) or not Installed(a, s, entry) then
			return false
		end
		if descriptor.publishesLocation and not a:CanPublishPlayerLocation() then
			return false
		end
	end
	return Installed(a, s, entry)
end

local function Remove(a, s, entry, reason)
	if s.entries[entry.key] ~= entry then
		return
	end
	s.entries[entry.key], entry.cancelled = nil, true
	if entry.descriptor and s.active[entry.descriptor.key] == entry then
		s.active[entry.descriptor.key] = nil
	end
	-- A quarantine may also be owned by a batched authentication callback or
	-- a suspended hash coroutine. Drop those references before releasing its
	-- reservation; otherwise the advertised memory bound omits their payloads.
	local request = entry.authRequest
	entry.authRequest = nil
	if request then
		for index = #request.entries, 1, -1 do
			if request.entries[index] == entry then
				table.remove(request.entries, index)
			end
		end
		if #request.entries == 0 then
			s.requests[request] = nil
			if request.id then
				a:CancelCommRequest(request.id, "cancelled")
			end
		end
	end
	for index = #s.jobs, 1, -1 do
		if s.jobs[index] == entry then
			table.remove(s.jobs, index)
		end
	end
	-- Native hop jobs have this exact entry owner, separate from the feature
	-- and lease owners whose other publications must remain intact.
	a:CancelCommTransfers(function(job)
		return job.owner == entry
	end, reason or "cancelled")
	a:CancelTransportWhere(function(row)
		return row.owner == entry
	end, reason or "cancelled")
	a:ReleaseCommResponseBytes(entry.reservation)
	s.count, s.bytes = s.count - 1, s.bytes - entry.cost
	if not entry.verified then
		s.pending = math.max(0, s.pending - 1)
	end
	if entry.owned then
		Complete(entry, false, reason or "cancelled")
	end
	-- Late callbacks retain only this cancelled shell, never released bodies,
	-- decoded records, producer closures or the hash coroutine's input string.
	entry.publication, entry.data, entry.hash, entry.descriptor = nil, nil, nil, nil
	entry.routes, entry.reservation = {}, nil
	Count(s, reason or "cancelled")
end
local function Canonical(publication)
	local cells = { "QTMESH3" }
	for _, field in ipairs(FIELDS) do
		local value = publication[field]
		if value == nil then
			value = ""
		else
			value = tostring(value)
		end
		cells[#cells + 1] = #value .. ":" .. value
	end
	local text = table.concat(cells, "|")
	if #text > MAX_CANONICAL then
		return nil
	end
	return text
end
local function FitsEnvelope(a, publication)
	local wire = Copy(publication)
	wire.scope, wire.digest = tostring(wire.scope), string.rep("0", 128)
	-- Every later route can add this bounded metadata. Admission must account
	-- for the complete encoded object, not only its inner public record.
	wire.leaseId, wire.destination = string.rep("x", 80), string.rep("x", 120)
	wire.zone, wire.hops = 1000000, 8
	local encoded = a:EncodeCommRecord("MPUB", wire)
	return encoded ~= nil and #encoded <= 8192
end
local function PublicRecord(a, operation, data)
	local spec = a:GetCommOperation(operation)
	if not spec or not spec.publicRelay or spec.privateOnly or spec.groupOnly then
		return false
	end
	if operation == "STATE" or operation == "BYE" then
		for _, row in ipairs(data.records or {}) do
			if not PUBLIC_TOPICS[row.topic] then
				return false
			end
		end
	end
	if operation == "PING" then
		return data.developerRequest == true and data.debugRequest ~= true and not data.targetName
	end
	return spec.semantic ~= "response" and spec.semantic ~= "transfer" and spec.semantic ~= "stream"
end
local function Normalize(a, value)
	if type(value) ~= "table" or not a:CanAccessTable(value) then
		return nil
	end
	local p = {}
	for _, field in ipairs(FIELDS) do
		if not a:CanAccessValue(value[field]) then
			return nil
		end
		p[field] = value[field]
	end
	p.origin, p.scope = Name(a, p.origin), Scope(p.scope)
	local wall = Wall(a)
	local spec = a:GetCommOperation(p.operation)
	if
		not p.origin
		or not p.scope
		or not Identifier(p.session, 64)
		or not Identifier(p.id, 64)
		or (p.originRequestId ~= nil and not Identifier(p.originRequestId, 80))
		or not spec
		or not spec.publicRelay
		or spec.privateOnly
		or spec.groupOnly
		or type(p.body) ~= "string"
		or #p.body > MAX_BODY
		or type(p.stamp) ~= "number"
		or p.stamp ~= math.floor(p.stamp)
		or type(p.expiresAt) ~= "number"
		or p.expiresAt ~= math.floor(p.expiresAt)
		or not wall
		or p.stamp > wall + 30
		or p.stamp < wall - 600
		or p.expiresAt <= wall
		or p.expiresAt > wall + MAX_LIFETIME
		or p.expiresAt <= p.stamp
		or p.expiresAt > p.stamp + MAX_LIFETIME
		or type(value.digest) ~= "string"
		or #value.digest ~= 128
		or value.digest:find("[^0-9a-f]")
	then
		return nil
	end
	p.digest = value.digest
	return p
end
-- Only fields covered by existing pinned-key signatures can supply the outer
-- freshness/order of signed exceptions. A relay cannot attach a new epoch or
-- longer expiry to a genuine old proof.
local function SignedIdentity(operation, data)
	local stamp = data.issuedAt
	if type(stamp) ~= "number" or stamp < 1 or stamp ~= math.floor(stamp) then
		return nil
	end
	if operation == "VIP" then
		if not Identifier(data.session, 64) then
			return nil
		end
		return data.session, tostring(stamp), stamp, stamp + 300, nil
	end
	if operation == "DEVANN" or operation == "PING" then
		local id = data.requestId
		local sequence = type(id) == "string" and id:match("^dev%-%d+%-%d+%-(%d+)$")
		if not sequence or not Identifier(id, 64) then
			return nil
		end
		local session = operation == "DEVANN" and data.subscriptionSession or id:gsub("^dev", "dp")
		if not Identifier(session, 64) then
			return nil
		end
		return session, sequence, stamp, stamp + (operation == "DEVANN" and 240 or 300), id
	end
end
local function Retain(a, s, publication, descriptor)
	local wall = Wall(a)
	if not wall or not Current(a, s) then
		return nil
	end
	local cost = #publication.body + 512
	if not descriptor then
		local pending, sameOrigin = 0, 0
		for _, candidate in pairs(s.entries) do
			if not candidate.owned and not candidate.verified then
				pending = pending + 1
				if candidate.publication.origin == publication.origin then
					sameOrigin = sameOrigin + 1
				end
			end
		end
		if pending >= 24 or sameOrigin >= 8 then
			Count(s, "capacity")
			return nil
		end
	end
	if cost > MAX_BYTES or s.pending >= MAX_PENDING then
		Count(s, "capacity")
		return nil
	end
	while s.count >= MAX_ENTRIES or s.bytes + cost > MAX_BYTES do
		local oldest
		for _, candidate in pairs(s.entries) do
			if candidate.verified and not candidate.owned and (not oldest or candidate.at < oldest.at) then
				oldest = candidate
			end
		end
		if not oldest then
			Count(s, "capacity")
			return nil
		end
		Remove(a, s, oldest, "capacity")
		if not Current(a, s) then
			return nil
		end
	end
	local reservation = a:ReserveCommResponseBytes(cost)
	if not reservation then
		Count(s, "capacity")
		return nil
	end
	local entry = {
		key = Key(publication),
		publication = publication,
		descriptor = descriptor,
		owned = descriptor ~= nil,
		at = Now(a),
		untilAt = Now(a) + math.max(0, publication.expiresAt - wall),
		cost = cost,
		reservation = reservation,
		routes = {},
		authAt = Now(a) + 0.15,
	}
	s.entries[entry.key], s.count, s.bytes, s.pending = entry, s.count + 1, s.bytes + cost, s.pending + 1
	s.metrics.retainedBytesHighWater = math.max(s.metrics.retainedBytesHighWater or 0, s.bytes)
	return entry
end
local function QueueHash(a, s, entry)
	local inbound = 0
	for _, job in ipairs(s.jobs) do
		if not job.owned then
			inbound = inbound + 1
		end
	end
	if #s.jobs >= MAX_HASH_JOBS or (not entry.owned and inbound >= 12) then
		Remove(a, s, entry, "capacity")
		return false
	end
	local text = Canonical(entry.publication)
	if not text or not a.Ed25519 or not a.Ed25519.Hash then
		Remove(a, s, entry, "invalid")
		return false
	end
	entry.hash = coroutine.create(function()
		return Hex(a.Ed25519.Hash(text, coroutine.yield))
	end)
	s.jobs[#s.jobs + 1] = entry
	Count(s, "hashQueued")
	return true
end

function QT:GetMeshPublicationMetrics()
	local s = rawget(self, "meshPublicationState")
	local result = Copy(s and s.metrics)
	result.retainedBytes, result.retained, result.pending = s and s.bytes or 0, s and s.count or 0, s and s.pending or 0
	result.hashJobs, result.confirmations, result.oldestQuarantineAge = s and #s.jobs or 0, 0, 0
	for _ in pairs(s and s.requests or {}) do
		result.confirmations = result.confirmations + 1
	end
	for _, entry in pairs(s and s.entries or {}) do
		if not entry.owned and not entry.verified then
			result.oldestQuarantineAge = math.max(result.oldestQuarantineAge, Now(self) - entry.at)
		end
	end
	return result
end

function QT:SendMeshPublicationToPeer(publication, target, relaymeta, descriptor)
	local s, entry = State(self), State(self).entries[Key(publication)]
	if not entry or not entry.verified or not EntryCurrent(self, s, entry) then
		return false, "expired"
	end
	local wire = Copy(publication)
	wire.scope = tostring(wire.scope)
	for _, field in ipairs({ "leaseId", "destination", "zone", "hops" }) do
		wire[field] = relaymeta and relaymeta[field]
	end
	local options = Copy(descriptor)
	local callerCurrent = options.isCurrent
	local callerStarted = options.onStarted
	options.onStarted = function(...)
		if not EntryCurrent(self, s, entry) then
			return
		end
		if not entry.exposed then
			Count(s, "exposed")
		end
		entry.exposed = true
		if callerStarted then
			pcall(callerStarted, ...)
		end
	end
	options.owner, options.meshTraffic = entry, true
	options.requestId, options.retryContext, options.cacheResponse = nil, nil, nil
	options.meshOperation = publication.operation
	-- Logical global/zone audiences fan out into independent native peers.
	-- Schedule each hop with that peer's other traffic, not a single shared
	-- logical-audience flow that gives every destination only one turn.
	options.flow = "WHISPER:" .. target
	options.isCurrent = function()
		return EntryCurrent(self, s, entry) and Predicate(callerCurrent)
	end
	options.expires = math.min(options.expires or entry.untilAt, entry.untilAt)
	return self:Emit("MPUB", wire, { { distribution = "WHISPER", target = target } }, options)
end

function QT:QueueMeshPublication(context, data, scope, descriptor)
	local s = State(self)
	if not Current(self, s) or not PublicRecord(self, context.operation, data) or not Scope(scope) then
		return false, "invalid"
	end
	local body = self:EncodeCommRecord(context.operation, data)
	local wall, now = Wall(self), Now(self)
	if not body or #body > MAX_BODY or not wall then
		return false, "oversize"
	end
	local p = {
		origin = Name(self, self:GetPlayerFullName()),
		session = context.session,
		id = context.messageId,
		operation = context.operation,
		scope = Scope(scope),
		originRequestId = context.requestId,
		stamp = context.stamp,
		expiresAt = math.floor(wall + math.min(MAX_LIFETIME, (descriptor.expires or now + 30) - now)),
		body = body,
	}
	if context.operation == "VIP" or context.operation == "DEVANN" or context.operation == "PING" then
		local session, id, stamp, expires, request = SignedIdentity(context.operation, data)
		if not session or p.scope ~= "global" then
			return false, "invalid"
		end
		p.session, p.id, p.stamp, p.expiresAt, p.originRequestId = session, id, stamp, expires, request
	end
	if not p.origin or not Identifier(p.session, 64) or not Identifier(p.id, 64) or p.expiresAt <= wall then
		return false, "expired"
	end
	if not FitsEnvelope(self, p) then
		return false, "oversize"
	end
	if descriptor.key then
		for _, previous in pairs(s.entries) do
			if previous.owned and previous.descriptor.key == descriptor.key and previous.key ~= Key(p) then
				if previous.exposed then
					-- Bytes already accepted by the native API may still be in transit.
					-- Keep their immutable proof until its original expiry, and let an
					-- already-started hop finish before sending the newest replacement.
					previous.superseded, previous.retryAt = true, nil
				else
					Remove(self, s, previous, "superseded")
					if not Current(self, s) then
						return false, "cancelled"
					end
				end
			end
		end
	end
	if not Current(self, s) then
		return false, "cancelled"
	end
	local key, old = Key(p), s.entries[Key(p)]
	if old then
		if Canonical(old.publication) ~= Canonical(p) then
			return false, "conflict"
		end
		if old.verified then
			return self:ForwardMeshPublication(old.publication, descriptor)
		end
		return false, "pending"
	end
	local entry = Retain(self, s, p, Copy(descriptor))
	if not entry or not QueueHash(self, s, entry) then
		return false, "capacity"
	end
	Count(s, "published")
	return true, "queued"
end

local function Deliver(a, s, entry, route)
	if
		not EntryCurrent(a, s, entry)
		or a:IsIgnoredPlayerName(route.sender)
		or not a:CanAcceptMeshPublicationRoute(
			route.sender,
			route.meta,
			entry.publication.scope,
			entry.publication.origin
		)
	then
		return
	end
	local p = entry.publication
	local hops = 9 - route.meta.hops
	s.metrics.verifiedDeliveryHopsLast = hops
	s.metrics.verifiedDeliveryHopsMax = math.max(s.metrics.verifiedDeliveryHopsMax or 0, hops)
	local context = {
		distribution = "MESH",
		scope = p.scope,
		relaySender = route.sender,
		meshSignedVerified = entry.signedVerified,
		meshSignedKind = entry.signedKind,
	}
	if a:ShouldConsumeMeshPublicationRoute(route.sender, route.meta, p.scope, p.origin) then
		local frame = {
			operation = p.operation,
			session = p.session,
			messageId = p.id,
			requestId = p.originRequestId,
			stamp = p.stamp,
			part = 1,
			total = 1,
		}
		a:DispatchVerifiedMeshRecord(frame, Copy(entry.data), p.origin, context)
	end
	if not EntryCurrent(a, s, entry) then
		return
	end
	a:ForwardMeshPublication(p, {
		relaySender = route.sender,
		relaymeta = route.meta,
		owner = entry,
		expires = entry.untilAt,
		-- Preserve prompt identity changes without promoting routine relayed
		-- snapshots above the background discovery work they represent.
		priority = p.operation == "VIP" and "event" or "background",
		isCurrent = function()
			return EntryCurrent(a, s, entry)
		end,
	})
end
local function ForwardOwned(a, s, entry)
	if entry.superseded or entry.forwarding or not EntryCurrent(a, s, entry) then
		return
	end
	local key = entry.descriptor.key
	local active = key and s.active[key]
	if active and active ~= entry and active.forwarding and EntryCurrent(a, s, active) then
		entry.waiting = true
		return
	end
	entry.waiting, entry.forwarding = nil, true
	if key then
		s.active[key] = entry
	end
	local descriptor = Copy(entry.descriptor)
	-- Producer currentness identifies the newest unsent sample. Once bytes have
	-- left, only durable audience/consent/lifetime gates may invalidate the hop.
	descriptor.isCurrent = function()
		return EntryCurrent(a, s, entry)
	end
	descriptor.onComplete = function(ok, reason)
		entry.forwarding = nil
		if key and s.active[key] == entry then
			s.active[key] = nil
		end
		Complete(entry, ok, reason)
	end
	local accepted, reason = a:ForwardMeshPublication(entry.publication, descriptor)
	if not accepted then
		if Installed(a, s, entry) and not entry.superseded and (reason == "capacity" or reason == "pending") then
			entry.retryAt = Now(a) + 2
		end
		descriptor.onComplete(false, reason)
	end
end
local function Verified(a, s, entry)
	if not EntryCurrent(a, s, entry) then
		return
	end
	if not entry.verified then
		entry.verified, s.pending = true, math.max(0, s.pending - 1)
		Count(s, "verified")
		if not entry.owned then
			local elapsed = math.max(0, Now(a) - entry.at)
			s.metrics.authenticationLatencyLast = elapsed
			s.metrics.authenticationLatencyMax = math.max(s.metrics.authenticationLatencyMax or 0, elapsed)
		end
	end
	if entry.owned then
		ForwardOwned(a, s, entry)
	else
		for _, route in ipairs(entry.routes) do
			Deliver(a, s, entry, route)
		end
		entry.routes = {}
	end
end

function QT:HandleMeshPublication(data, sender, context)
	local s, p = State(self), Normalize(self, data)
	sender = Name(self, sender)
	if
		not Current(self, s)
		or not p
		or not sender
		or self:IsSelfSender(p.origin)
		or self:IsIgnoredPlayerName(sender)
		or self:IsIgnoredPlayerName(p.origin)
	then
		return false
	end
	local meta = { leaseId = data.leaseId, destination = data.destination, zone = data.zone, hops = data.hops }
	if not self:CanAcceptMeshPublicationRoute(sender, meta, p.scope, p.origin) then
		Count(s, "routeRejected")
		return false
	end
	local entry = s.entries[Key(p)]
	if entry and (entry.publication.digest ~= p.digest or Canonical(entry.publication) ~= Canonical(p)) then
		Count(s, "conflicts")
		-- A relay's unverified claim must not reserve another player's immutable
		-- ID against the actual native sender. Once native ownership or a proof
		-- establishes the object, even its owner cannot change that same ID.
		if sender == p.origin and not entry.verified and not entry.nativeOwner then
			Remove(self, s, entry, "unverifiedConflict")
			if not Current(self, s) then
				return false
			end
			entry = nil
		else
			return false
		end
	end
	local route = { sender = sender, meta = meta }
	if entry then
		if entry.verified then
			Deliver(self, s, entry, route)
			return true
		end
		for _, old in ipairs(entry.routes) do
			if old.sender == sender and old.meta.leaseId == meta.leaseId then
				return true
			end
		end
		if #entry.routes >= 8 then
			Count(s, "routeCapacity")
			return false
		end
		entry.routes[#entry.routes + 1] = route
		if sender == p.origin then
			entry.nativeOwner = true
			if entry.hashed and p.operation ~= "VIP" and p.operation ~= "DEVANN" and p.operation ~= "PING" then
				Verified(self, s, entry)
			end
		end
		return true
	end
	entry = Retain(self, s, p)
	if not entry then
		return false
	end
	entry.nativeOwner = sender == p.origin
	entry.routes[1] = route
	return QueueHash(self, s, entry)
end

function QT:HandleMeshAuthenticationRequest(data, sender)
	local s = State(self)
	if not Current(self, s) or data.session ~= s.communication.session or self:IsIgnoredPlayerName(sender) then
		return false
	end
	local entries = {}
	for _, item in ipairs(data.items or {}) do
		if #entries >= AUTH_BATCH then
			break
		end
		local scope, entry = Scope(item.scope)
		if scope and Identifier(item.id, 64) and Identifier(item.operation, 16) then
			entry = s.entries[Key({
				origin = Name(self, self:GetPlayerFullName()),
				session = data.session,
				id = item.id,
				operation = item.operation,
				scope = scope,
			})]
		end
		if
			entry
			and entry.owned
			and entry.verified
			and EntryCurrent(self, s, entry)
			and item.operation ~= "VIP"
			and item.operation ~= "DEVANN"
			and item.operation ~= "PING"
		then
			entries[#entries + 1] = { key = entry.key, digest = entry.publication.digest }
		end
	end
	local expires, attempts = Now(self) + AUTH_LIFETIME, 0
	local SendProof
	SendProof = function()
		if not Current(self, s) or Now(self) >= expires or attempts >= 3 then
			return false
		end
		attempts = attempts + 1
		local active, proofs = {}, {}
		for _, reference in ipairs(entries) do
			local entry = s.entries[reference.key]
			if entry and EntryCurrent(self, s, entry) and entry.publication.digest == reference.digest then
				active[#active + 1] = reference
				proofs[#proofs + 1] = ProofItem(entry.publication)
			end
		end
		return self:Respond(
			"MAPRF",
			{ requestId = data.requestId, session = data.session, items = proofs },
			{ { distribution = "WHISPER", target = sender } },
			{
				owner = s,
				meshTraffic = true,
				expires = expires,
				isCurrent = function()
					if not Current(self, s) then
						return false
					end
					for _, reference in ipairs(active) do
						local entry = s.entries[reference.key]
						if
							not entry
							or not EntryCurrent(self, s, entry)
							or entry.publication.digest ~= reference.digest
						then
							return false
						end
					end
					return true
				end,
				onComplete = function(sent, reason)
					if not sent and reason == "cancelled" then
						SendProof()
					end
				end,
			}
		)
	end
	return SendProof()
end

function QT:VerifyMeshSignedPublication(publication, data, callback)
	local operation = publication.operation
	if operation ~= "VIP" and operation ~= "DEVANN" and operation ~= "PING" then
		return false
	end
	local session, id, stamp, expires, request = SignedIdentity(operation, data)
	if
		publication.scope ~= "global"
		or not session
		or publication.session ~= session
		or publication.id ~= id
		or publication.stamp ~= stamp
		or publication.expiresAt ~= expires
		or publication.originRequestId ~= request
	then
		callback(operation, false)
		return true
	end
	local context = {
		session = session,
		sequence = tonumber(id),
		stamp = stamp,
		requestId = request,
		messageId = id,
		distribution = "MESH",
	}
	if operation == "VIP" then
		return self:HandleVIPIdentity(data, publication.origin, context, function()
			callback(operation, true)
		end) == true
	end
	local developerState = operation == "DEVANN" and self:InitializeDeveloperAnnouncements() or nil
	local generation = developerState and developerState.generation
	local diagnosticGeneration = rawget(self, "diagnosticReplyGeneration") or 0
	local verify = operation == "DEVANN" and self.QueueDeveloperAnnouncementVerification
		or self.QueueDeveloperPingVerification
	return verify(self, data, publication.origin, function(verified)
		if
			developerState
			and (
				rawget(self, "developerAnnouncementState") ~= developerState
				or developerState.generation ~= generation
			)
		then
			callback(operation, false)
			return
		end
		if operation == "PING" and (rawget(self, "diagnosticReplyGeneration") or 0) ~= diagnosticGeneration then
			callback(operation, false)
			return
		end
		callback(operation, verified)
	end) == true
end

local function StartSignedVerification(a, s, entry)
	entry.signedPending, entry.signedRetryAt = true, nil
	entry.signedAttempts = (entry.signedAttempts or 0) + 1
	local handled = a:VerifyMeshSignedPublication(entry.publication, entry.data, function(kind, verified)
		if EntryCurrent(a, s, entry) then
			if not verified then
				Remove(a, s, entry, "signatureRejected")
			else
				entry.signedVerified, entry.signedKind = verified, kind
				Verified(a, s, entry)
			end
		end
	end)
	-- Queue admission is not a cryptographic verdict. Keep a bounded quarantine
	-- while the shared verifier services an existing private request.
	if not handled and EntryCurrent(a, s, entry) then
		entry.signedRetryAt = Now(a) + math.min(5, entry.signedAttempts)
		Count(s, "signatureDeferred")
	end
end

local function RequestAuthentication(a, s, now)
	if now < s.nextAuth then
		return
	end
	local count = 0
	for _ in pairs(s.requests) do
		count = count + 1
	end
	if count >= AUTH_REQUESTS then
		return
	end
	local first
	for _, entry in pairs(s.entries) do
		if
			not entry.owned
			and not entry.verified
			and entry.hashed
			and not entry.signedPending
			and not entry.authRequest
			and (entry.authAttempts or 0) < 3
			and now >= entry.authAt
			and EntryCurrent(a, s, entry)
			and (not first or entry.at < first.at)
		then
			first = entry
		end
	end
	if not first then
		return
	end
	local origin, session = first.publication.origin, first.publication.session
	local entries, items = {}, {}
	for _, entry in pairs(s.entries) do
		if
			#items < AUTH_BATCH
			and not entry.owned
			and not entry.verified
			and entry.hashed
			and not entry.signedPending
			and not entry.authRequest
			and entry.publication.origin == origin
			and entry.publication.session == session
			and entry.publication.operation == first.publication.operation
			and (entry.authAttempts or 0) < 3
			and EntryCurrent(a, s, entry)
		then
			entries[#entries + 1], items[#items + 1] = entry, ProofItem(entry.publication)
			items[#items].digest = nil
		end
	end
	local request = { origin = origin, session = session, entries = entries }
	s.requests[request], s.nextAuth = true, now + 0.25
	for _, entry in ipairs(entries) do
		entry.authRequest = request
		entry.authAttempts = (entry.authAttempts or 0) + 1
	end
	local function Finish(reason)
		if not s.requests[request] then
			return
		end
		s.requests[request] = nil
		local completedEntries = request.entries
		request.entries = {}
		if request.id then
			a:CancelCommRequest(request.id, "complete")
		end
		for _, entry in ipairs(completedEntries) do
			if entry.authRequest == request then
				entry.authRequest = nil
				if not entry.verified then
					if reason == "unconfirmed" then
						Remove(a, s, entry, reason)
					else
						entry.authAt = Now(a) + math.min(30, 5 * 2 ^ (entry.authAttempts or 1))
						Count(s, reason or "unconfirmed")
					end
				end
			end
		end
	end
	local ok, _, _, id = a:Request(
		"MAUTH",
		{ targetName = origin, session = session, items = items },
		{ { distribution = "WHISPER", target = origin } },
		{
			owner = s,
			meshTraffic = true,
			expires = now + AUTH_LIFETIME,
			isCurrent = function()
				return Current(a, s) and s.requests[request] == true
			end,
			onExpire = function()
				Finish("authenticationExpired")
			end,
			onResponse = function(data, sender)
				if not Current(a, s) or not s.requests[request] or sender ~= origin or data.session ~= session then
					return false
				end
				for _, item in ipairs(data.items or {}) do
					for _, entry in ipairs(request.entries) do
						local p = entry.publication
						if
							item.id == p.id
							and item.operation == p.operation
							and Scope(item.scope) == p.scope
							and item.digest == p.digest
						then
							Verified(a, s, entry)
						end
					end
				end
				Finish("unconfirmed")
				return true
			end,
		}
	)
	request.id = id
	if not ok then
		Finish("authenticationRejected")
	end
end

-- Newly reached interests may use retained current public state. Replays are
-- paced by the same runtime and native budgets, never sent in a callback loop.
function QT:ReplayMeshPublicationsForInterest(lease)
	local s = State(self)
	if not Current(self, s) then
		return
	end
	local count = 0
	for _ in pairs(s.replay) do
		count = count + 1
	end
	if count >= 32 then
		return
	end
	s.replay[lease] = { lease = lease, seen = {} }
end
local function ReplayOne(a, s, now)
	if now < s.nextReplay then
		return
	end
	s.nextReplay = now + 1
	for lease, replay in pairs(s.replay) do
		if not lease.expiresAt or lease.expiresAt <= Wall(a) then
			s.replay[lease] = nil
		else
			local chosen, waiting
			for key, entry in pairs(s.entries) do
				local scope = entry.publication.scope == "global" and 0 or entry.publication.scope
				if
					entry.owned
					and not entry.superseded
					and not replay.seen[key]
					and scope == lease.zone
					and EntryCurrent(a, s, entry)
				then
					if not entry.verified or not entry.completed then
						-- A new interest can arrive while the first fanout is in
						-- flight. Keep its replay until that immutable object is
						-- ready; it was not included in the original audience.
						waiting = true
					elseif not chosen or entry.at > chosen.at then
						chosen = entry
					end
				end
			end
			-- Another entry's predicate may have retired the earlier choice or
			-- reset the whole store while this scan was in progress.
			if chosen and not EntryCurrent(a, s, chosen) then
				chosen, waiting = nil, true
			end
			if not Current(a, s) then
				return
			end
			if not chosen then
				if not waiting then
					s.replay[lease] = nil
				end
			else
				local admitted, reason = a:ForwardMeshPublication(chosen.publication, {
					owner = chosen,
					expires = chosen.untilAt,
					key = chosen.descriptor.key,
					priority = chosen.descriptor.priority or "background",
					isCurrent = function()
						return EntryCurrent(a, s, chosen)
					end,
				})
				if admitted or (reason ~= "capacity" and reason ~= "pending") then
					replay.seen[chosen.key] = true
				end
				return
			end
		end
	end
end

function QT:UpdateMeshPublications(now)
	local s = rawget(self, "meshPublicationState")
	if not s or not Current(self, s) then
		return
	end
	now = now or Now(self)
	for _, entry in pairs(s.entries) do
		if not EntryCurrent(self, s, entry) then
			Remove(self, s, entry, "expired")
		elseif entry.owned and entry.waiting then
			ForwardOwned(self, s, entry)
		elseif
			entry.owned
			and not entry.superseded
			and entry.retryAt
			and now >= entry.retryAt
			and (entry.retries or 0) < 3
		then
			entry.retryAt, entry.retries = nil, (entry.retries or 0) + 1
			ForwardOwned(self, s, entry)
		elseif entry.signedPending and not entry.verified and now >= entry.at + 30 then
			Remove(self, s, entry, "authenticationExpired")
		elseif entry.signedRetryAt and now >= entry.signedRetryAt then
			StartSignedVerification(self, s, entry)
		end
	end
	local steps = 0
	local profile = self.API.ProfileMilliseconds
	local started = profile and profile() or nil
	while #s.jobs > 0 and steps < 256 do
		local entry = table.remove(s.jobs, 1)
		if EntryCurrent(self, s, entry) then
			local done, result
			local sliceStart = profile and profile() or nil
			for _ = 1, 16 do
				local ok, value = coroutine.resume(entry.hash)
				steps = steps + 1
				if not ok then
					done = true
					break
				end
				if coroutine.status(entry.hash) == "dead" then
					done, result = true, value
					break
				end
			end
			if sliceStart then
				local ms = math.max(0, profile() - sliceStart)
				s.metrics.hashMilliseconds = (s.metrics.hashMilliseconds or 0) + ms
				s.metrics.hashSliceMaxMilliseconds = math.max(s.metrics.hashSliceMaxMilliseconds or 0, ms)
			end
			if done then
				s.metrics.hashCompleted = (s.metrics.hashCompleted or 0) + 1
				s.metrics.hashQueueLast = now - entry.at
				entry.hash = nil
				if not result or (not entry.owned and result ~= entry.publication.digest) then
					Remove(self, s, entry, "hashRejected")
				else
					entry.publication.digest, entry.hashed = result, true
					entry.data = self:DecodeCommRecord(entry.publication.operation, entry.publication.body)
					if not entry.data or not PublicRecord(self, entry.publication.operation, entry.data) then
						Remove(self, s, entry, "invalid")
					elseif entry.owned then
						Verified(self, s, entry)
					elseif
						entry.publication.operation == "VIP"
						or entry.publication.operation == "DEVANN"
						or entry.publication.operation == "PING"
					then
						StartSignedVerification(self, s, entry)
					elseif entry.nativeOwner then
						Verified(self, s, entry)
					end
				end
			else
				s.jobs[#s.jobs + 1] = entry
			end
		end
		if started and profile() - started >= 1 then
			break
		end
	end
	ReplayOne(self, s, now)
	RequestAuthentication(self, s, now)
end

function QT:CancelMeshPublicationsWhere(predicate)
	local s = rawget(self, "meshPublicationState")
	if not s then
		return
	end
	for _, entry in pairs(s.entries) do
		if not predicate or predicate(entry.descriptor or {}, entry.publication) then
			Remove(self, s, entry, "cancelled")
		end
	end
end
function QT:ResetMeshPublications()
	local s = rawget(self, "meshPublicationState")
	if not s then
		return
	end
	self.meshPublicationState = nil
	self:CancelCommunicationOwner(s, "cancelled")
	for _, entry in pairs(s.entries) do
		Remove(self, s, entry, "cancelled")
	end
end
function QT:RetireMeshPublicationPeer(name)
	name = Name(self, name)
	local s = rawget(self, "meshPublicationState")
	if not s or not name then
		return
	end
	for _, entry in pairs(s.entries) do
		if entry.publication.origin == name then
			Remove(self, s, entry, "retired")
		end
	end
end
