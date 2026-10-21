-- Owns communication lifetimes, audiences and transactions. Feature modules
-- submit records; they never reverse-engineer serialized packets for policy.
local QT = _G.QuestTogether
local GROUP = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local INGRESS_PACKETS, INGRESS_BYTES, PUBLIC_PACKETS, PUBLIC_BYTES = 96, 24576, 64, 16384
local STATE_HANDLERS = {
	QTPR = "HandleQTPlayerPresenceMessage",
	QTVR = "HandleAddonVersionMessage",
	QTLF = "HandleQuestPartnerStatusMessage",
	QTLQ = "HandleQuestPartnerQuestMessage",
	QTPG = "HandlePartyVisualMetadata",
	QJST = "HandlePartyJoinMetadata",
	LOC = "HandlePlayerLocationMessage",
	QTCI = "HandlePlayerCapabilityMetadata",
	QTHI = "HandlePlayerDetailsIdentity",
}
local policies = {}
local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end
local function Copy(t)
	local out = {}
	if type(t) ~= "table" then
		return out
	end
	for k, v in pairs(t or {}) do
		out[k] = v
	end
	return out
end
local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end
local function Name(a, name)
	if not a:CanAccessValue(name) or type(name) ~= "string" or #name > 120 or name:find("[%c|,]") then
		return nil
	end
	return a:NormalizeMemberName(name)
end
local function Current(a, s)
	return rawget(a, "communicationState") == s and a.isEnabled and not a.isLoggingOut and not s.departing
end
function QT:InitializeCommunications()
	local s = rawget(self, "communicationState")
	if not s then
		local now = Now(self)
		local random = self:SafeToNumber(self.API.Random and self.API.Random(1000, 999999)) or 1000
		s = {
			-- Forever's integer formatter is signed 32-bit; epoch milliseconds
			-- must stay a Lua number and use fixed-point decimal formatting.
			session = string.format("%.0f-%d", math.floor((self:GetAnnouncementServerTime() or now) * 1000), random),
			sequence = 0,
			requests = {},
			inboundTargets = {},
			seen = {},
			seenRing = {},
			seenCursor = 0,
			receivedRequests = {},
			requestRing = {},
			requestCursor = 0,
			generation = 0,
			startedAt = now,
		}
		self.communicationState = s
	end
	self:InitializeTransport()
	return s
end
function QT:GetCommunicationSession()
	return self:InitializeCommunications().session
end
function QT:NextCommunicationSequence()
	local s = self:InitializeCommunications()
	s.sequence = s.sequence + 1
	return s.sequence
end
function QT:RegisterCommunicationPolicy(operation, policy)
	policies[operation] = policy
end
function QT:GetCommunicationMetrics()
	local s = rawget(self, "communicationState")
	if not s then
		return { admitted = 0, rejected = 0, received = 0, duplicates = 0, expiredRequests = 0 }
	end
	s.metrics = s.metrics or { admitted = 0, rejected = 0, received = 0, duplicates = 0, expiredRequests = 0 }
	return s.metrics
end
local function Timing(a, prefix, elapsed)
	local metrics = a:GetCommunicationMetrics()
	elapsed = math.max(0, elapsed)
	metrics[prefix .. "Count"] = (metrics[prefix .. "Count"] or 0) + 1
	metrics[prefix .. "Last"] = elapsed
	metrics[prefix .. "Max"] = math.max(metrics[prefix .. "Max"] or 0, elapsed)
end
local function FirstResponse(a, request)
	request.lastProgressAt = Now(a)
	if not request.firstResponseAt then
		request.firstResponseAt = request.lastProgressAt
		Timing(a, "firstResponse", request.firstResponseAt - request.startedAt)
	end
	request.responseProgress = true
end
local function RouteKey(route)
	return route.distribution .. ":" .. tostring(route.channelName or route.target or "")
end
function QT:GetCommunicationRoutes(operation, routes)
	if routes then
		return routes
	end
	local spec = self:GetCommOperation(operation)
	if spec.privateOnly then
		return {}
	end
	if spec.groupOnly then
		local distribution = self:GetGroupAnnouncementDistribution()
		return distribution and { { distribution = distribution, requiresGroup = true } } or {}
	end
	if spec.semantic == "event" and (operation == "ANN" or operation == "LVL") then
		local routes = self:GetGeographicAnnouncementRoutes() or self:GetAnnouncementWireRoutes()
		for _, route in ipairs(self:GetDeveloperAnnouncementRoutes()) do
			routes[#routes + 1] = route
		end
		return routes
	end
	return self:GetAnnouncementWireRoutes()
end
function QT:IsCommunicationRouteCurrent(route, fingerprint)
	if route.developerAnnouncement and not self:IsDeveloperAnnouncementRouteCurrent(route) then
		return false
	end
	if route.distribution == "WHISPER" then
		return Name(self, route.target) ~= nil
			and not self:IsIgnoredPlayerName(route.target)
			and (
				not route.requiresGroup
				or (self:IsGroupedSender(route.target) and fingerprint == self:GetPartyRosterFingerprint())
			)
	elseif GROUP[route.distribution] then
		return route.distribution == self:GetGroupAnnouncementDistribution()
			and fingerprint == self:GetPartyRosterFingerprint()
	elseif route.distribution == "CHANNEL" then
		local geo = rawget(self, "geographicCommsState")
		return route.channelName == self.announcementChannelName
			or (geo and geo.subscriptions[route.channelName] ~= nil)
			or false
	end
	return false
end
local function SubmitsLocation(operation, record)
	if operation == "LOC" then
		return record.mask ~= 0
	end
	if operation == "STATE" then
		for _, row in ipairs(record.records or {}) do
			if row.topic == "LOC" and row.data.mask ~= 0 then
				return true
			end
		end
	end
	return (operation == "ANN" or operation == "LVL") and record.mapID ~= nil and record.mapID ~= ""
end
-- Canonicalize before counting callbacks or admitting any route. Duplicate
-- spellings must have one delivery lifetime and one completion contribution.
function QT:NormalizeCommunicationRoutes(operation, routes)
	local source = self:GetCommunicationRoutes(operation, routes)
	if type(source) ~= "table" or not self:CanAccessTable(source) or #source > 64 then
		return nil
	end
	local result, seen = {}, {}
	for _, original in ipairs(source) do
		if type(original) ~= "table" or not self:CanAccessTable(original) then
			return nil
		end
		local distribution = original.distribution
		if not self:CanAccessValue(distribution) or type(distribution) ~= "string" then
			return nil
		end
		local route = { distribution = distribution, requiresGroup = original.requiresGroup == true }
		if
			original.developerAnnouncement
			and (operation == "ANN" or operation == "LVL" or operation == "DLOC")
			and distribution == "WHISPER"
		then
			route.developerAnnouncement = original.developerAnnouncement
		end
		if distribution == "WHISPER" then
			route.target = Name(self, original.target)
			if not route.target then
				return nil
			end
		elseif distribution == "CHANNEL" then
			local channel = original.channelName or self.announcementChannelName
			if
				not self:CanAccessValue(channel)
				or type(channel) ~= "string"
				or channel == ""
				or #channel > 120
				or channel:find("[%c|]")
			then
				return nil
			end
			route.channelName = channel
			route.requiresChannelJoin = true
		elseif not GROUP[distribution] then
			return nil
		end
		local key = RouteKey(route)
		if
			self:GetCommOperation(operation).privateOnly
			and (distribution ~= "WHISPER" or not self:IsDeveloperAnnouncementRouteCurrent(route))
		then
			return nil
		end
		if
			self:GetCommOperation(operation).globalOnly
			and (distribution ~= "CHANNEL" or route.channelName ~= self.announcementChannelName)
		then
			return nil
		end
		if seen[key] then
			seen[key].requiresGroup = seen[key].requiresGroup or route.requiresGroup
		else
			seen[key] = route
			result[#result + 1] = route
		end
	end
	return result
end
local function Invoke(a, label, callback, ...)
	if not callback then
		return true
	end
	local ok, result = pcall(callback, ...)
	if not ok then
		a:RecordDiagnosticError(label, result)
	end
	return ok, result
end
local function Predicate(a, callback)
	if not callback then
		return true
	end
	local ok, value = Invoke(a, "communication currentness", callback)
	return ok and value == true
end
function QT:CacheCommResponse(context, wire, route, options)
	local s = rawget(self, "communicationState")
	if not s or not Current(self, s) or route.distribution ~= "WHISPER" or not context.requestId then
		return
	end
	s.replies = s.replies or {}
	s.replyBytes = s.replyBytes or 0
	local now = Now(self)
	local count = 0
	for key, row in pairs(s.replies) do
		if now >= row.expires or not Predicate(self, row.isCurrent) then
			self:ReleaseCommResponseBytes(row.reservation)
			s.replies[key] = nil
			s.replyBytes = s.replyBytes - #row.wire
		else
			count = count + 1
		end
	end
	if not Current(self, s) then
		return
	end
	local key = route.target .. ":" .. context.requestId .. ":" .. context.operation
	local old = s.replies[key]
	if count - (old and 1 or 0) >= 128 or s.replyBytes - (old and #old.wire or 0) + #wire > 65536 then
		return
	end
	local expires = math.min(options.expires, (options.startedAt or now) + 600)
	-- Cached single-packet outcomes share the transfer service's aggregate
	-- payload budget; their smaller independent cap also bounds bookkeeping.
	if old then
		self:ReleaseCommResponseBytes(old.reservation)
		s.replies[key] = nil
		s.replyBytes = s.replyBytes - #old.wire
	end
	local reservation = self:ReserveCommResponseBytes(#wire)
	if not reservation then
		return
	end
	s.replies[key] = {
		wire = wire,
		operation = context.operation,
		requestId = context.requestId,
		route = Copy(route),
		expires = expires,
		owner = options.owner,
		isCurrent = options.isCurrent,
		replays = 0,
		reservation = reservation,
	}
	s.replyBytes = s.replyBytes + #wire
end
function QT:ReplayCommResponses(sender, id)
	local s = rawget(self, "communicationState")
	if not s or not Current(self, s) then
		return false
	end
	local found = self:ReplayCommResponse(sender, id)
	for _, row in pairs(s.replies or {}) do
		if
			row.requestId == id
			and row.route.target == sender
			and row.replays < 2
			and Now(self) < row.expires
			and Predicate(self, row.isCurrent)
			and Current(self, s)
		then
			local ok = self:QueueTransportWire(row.wire, row.operation, row.route, {
				priority = "control",
				owner = row.owner,
				expires = row.expires,
				isCurrent = row.isCurrent,
				key = "reply:" .. sender .. ":" .. id .. ":" .. row.operation,
			})
			if ok then
				row.replays = row.replays + 1
				found = true
			end
		end
	end
	return found
end
function QT:SubmitCommunication(operation, record, routes, options)
	local spec = self:GetCommOperation(operation)
	options = Copy(options)
	local s = self:InitializeCommunications()
	if
		not spec
		or spec.semantic == "record"
		or (options.direct and operation ~= "BYE")
		or (not options.direct and not Current(self, s))
	then
		return false, "cancelled"
	end
	local data, reason = self:CopyCommRecord(operation, record)
	if not data then
		return false, reason
	end
	if options.requestId and data.requestId and options.requestId ~= data.requestId then
		return false, "correlation"
	end
	local audience = self:NormalizeCommunicationRoutes(operation, routes)
	if not audience or #audience == 0 then
		return false, "route"
	end
	if spec.privateOnly then
		for _, route in ipairs(audience) do
			local lease = route.developerAnnouncement
			if data.subscriptionSession ~= lease.session or data.subscriptionId ~= lease.requestId then
				return false, "correlation"
			end
		end
	end
	local sequence = options.retryContext and options.retryContext.sequence or self:NextCommunicationSequence()
	local context = options.retryContext
		or {
			operation = operation,
			session = s.session,
			messageId = tostring(sequence),
			sequence = sequence,
			requestId = options.requestId or data.requestId,
			stamp = options.sampledAt or self:GetAnnouncementServerTime() or 0,
		}
	local frames, why = self:BuildCommFrames(operation, data, context)
	if not frames then
		return false, why
	end
	if spec.semantic == "transfer" and #frames ~= 1 then
		return false, "oversize"
	end
	local fingerprint = self:GetPartyRosterFingerprint()
	local remaining, finished, overall, lastFailure = #audience, false, true, nil
	local admitted, last = false, "route"
	local function Complete(ok, status, code, ticket)
		remaining = remaining - 1
		overall = overall and ok
		if not ok then
			lastFailure = status
		end
		if remaining == 0 and not finished then
			finished = true
			Invoke(
				self,
				"communication completion",
				options.onComplete,
				overall,
				overall and "accepted" or lastFailure,
				code,
				ticket
			)
		end
	end
	for _, route in ipairs(audience) do
		local key = RouteKey(route)
		local descriptor = Copy(options)
		descriptor.operation = operation
		descriptor.requestId = context.requestId
		descriptor.owner = options.owner or s
		descriptor.expires = options.expires or Now(self) + spec.lifetime
		descriptor.priority = options.priority or spec.priority
		descriptor.flow = options.flow or key
		descriptor.key = options.key and (key .. ":" .. options.key) or nil
		descriptor.publishesLocation = options.publishesLocation == true or SubmitsLocation(operation, data)
		local policy = policies[operation]
		descriptor.isCurrent = function()
			if not Current(self, s) or not self:IsCommunicationRouteCurrent(route, fingerprint) then
				return false
			end
			if descriptor.publishesLocation and not self:CanPublishPlayerLocation() then
				return false
			end
			if not Predicate(self, options.isCurrent) or not Current(self, s) then
				return false
			end
			return not policy or not policy.canSend or policy.canSend(self, data, route, options)
		end
		local completed = false
		descriptor.onComplete = function(ok, status, code, ticket)
			if completed then
				return
			end
			completed = true
			if ok and options.cacheResponse and #frames == 1 then
				self:CacheCommResponse(context, frames[1], route, descriptor)
			end
			Complete(ok, status, code, ticket)
		end
		if route.developerAnnouncement then
			self:ConfigureDeveloperAnnouncementDelivery(route, descriptor)
		end
		local ok, status, ticket
		if options.direct then
			if #frames ~= 1 then
				ok, status = false, "oversize"
			else
				ok, status = self:SendTransportNow(frames[1], operation, route, "departure")
			end
			descriptor.onComplete(ok, status, nil, nil)
		elseif not Current(self, s) then
			ok, status = false, "cancelled"
			descriptor.onComplete(false, status)
		elseif #frames == 1 then
			ok, status, ticket = self:QueueTransportWire(frames[1], operation, route, descriptor)
			if not ok then
				descriptor.onComplete(false, status, nil, ticket)
			end
		else
			context.startedAt = options.startedAt or Now(self)
			ok, status, ticket = self:QueueCommTransfer(frames, context, route, descriptor)
			if not ok then
				descriptor.onComplete(false, status, nil, ticket)
			end
		end
		admitted, last = admitted or ok, status or last
	end
	if rawget(self, "communicationState") == s then
		local metrics = self:GetCommunicationMetrics()
		metrics[admitted and "admitted" or "rejected"] = metrics[admitted and "admitted" or "rejected"] + 1
	end
	return admitted, admitted and "queued" or last, context
end
function QT:Publish(operation, record, routes, options)
	local spec = self:GetCommOperation(operation)
	if not spec or spec.semantic ~= "state" then
		return false, "invalid"
	end
	if not routes and not spec.privateOnly and operation ~= "STATE" and operation ~= "BYE" then
		if not self.isEnabled or self.isLoggingOut then
			return false, "cancelled"
		end
		local data, reason = self:CopyCommRecord(operation, record)
		if not data then
			return false, reason
		end
		return self:StageCommunicationState(operation, data, options)
	end
	return self:SubmitCommunication(operation, record, routes, options)
end
function QT:Emit(operation, record, routes, options)
	return self:SubmitCommunication(operation, record, routes, options)
end
function QT:Request(operation, record, routes, options)
	options = Copy(options)
	local spec = self:GetCommOperation(operation)
	if not spec or spec.semantic ~= "request" or type(record) ~= "table" then
		return false, "invalid"
	end
	local s = self:InitializeCommunications()
	if not Current(self, s) or Count(s.requests) >= 128 then
		return false, "capacity"
	end
	if options.requestId and record.requestId and options.requestId ~= record.requestId then
		return false, "correlation"
	end
	local audience = self:NormalizeCommunicationRoutes(operation, routes)
	if not audience or #audience == 0 then
		return false, "route"
	end
	local id = options.requestId or record.requestId or (s.session .. "-" .. self:NextCommunicationSequence())
	if type(id) ~= "string" or id == "" or #id > 80 or id:find("[^%w%-]") then
		return false, "correlation"
	end
	if s.requests[id] then
		return false, "duplicate"
	end
	local data = Copy(record)
	data.requestId = id
	options.requestId = id
	local target = Name(self, data.targetName)
		or (#audience == 1 and audience[1].distribution == "WHISPER" and audience[1].target)
		or nil
	local groupOnly = spec.groupOnly or data.partyOnly == true
	for _, route in ipairs(audience) do
		if route.requiresGroup or GROUP[route.distribution] then
			groupOnly = true
		end
	end
	if operation == "QCMP" and groupOnly then
		data.partyOnly = true
	end
	local owned, invalid = self:CopyCommRecord(operation, data)
	if not owned then
		return false, invalid
	end
	data = owned
	local responses = Copy(options.responseOperations or spec.responses)
	responses.ERROR = true

	local request = {
		id = id,
		operation = operation,
		target = target,
		startedAt = Now(self),
		expires = options.expires or (Now(self) + spec.lifetime),
		owner = options.owner or s,
		isCurrent = options.responseCurrent or options.isCurrent,
		onResponse = options.onResponse,
		onExpire = options.onExpire,
		responses = responses,
		groupOnly = groupOnly,
		roster = groupOnly and self:GetPartyRosterFingerprint() or nil,
		generation = s.generation,
		acceptLatePongs = options.acceptLatePongs == true,
	}
	s.requests[id] = request
	if target then
		s.inboundTargets[target] = (s.inboundTargets[target] or 0) + 1
	end
	local callerCurrent = options.isCurrent
	options.isCurrent = function()
		return Current(self, s)
			and s.requests[id] == request
			and Predicate(self, callerCurrent)
			and (not request.groupOnly or request.roster == self:GetPartyRosterFingerprint())
	end
	local completion = options.onComplete
	options.onComplete = function(sent, reason, code, ticket)
		if s.requests[id] == request and sent then
			request.acceptedAt = Now(self)
			Timing(self, "requestQueueWait", request.acceptedAt - request.startedAt)
		end
		Invoke(self, "request completion", completion, sent, reason, code, ticket)
	end
	request.retryOptions = Copy(options)
	request.retryOptions.onComplete = nil
	request.record, request.routes, request.retries = data, audience, 0
	local ok, reason, ticket = self:SubmitCommunication(operation, data, audience, options)
	request.retryOptions.retryContext = ticket
	if not ok and s.requests[id] == request then
		self:CancelCommRequest(id, reason)
	end
	return ok, reason, ticket, id
end
function QT:Respond(operation, record, routes, options)
	options = Copy(options)
	if
		type(record) ~= "table" or (options.requestId and record.requestId and options.requestId ~= record.requestId)
	then
		return false, "correlation"
	end
	options.requestId = options.requestId or record.requestId
	if not options.requestId then
		return false, "uncorrelated"
	end
	local data = Copy(record)
	data.requestId = options.requestId
	options.cacheResponse = true
	return self:SubmitCommunication(operation, data, routes, options)
end
function QT:CancelCommRequest(id, reason)
	self:CancelIncomingCommResponses(id, reason or "cancelled")
	local s = rawget(self, "communicationState")
	if not s then
		return
	end
	local request = s.requests[id]
	s.requests[id] = nil
	if request then
		if request.target and s.inboundTargets then
			local count = (s.inboundTargets[request.target] or 1) - 1
			s.inboundTargets[request.target] = count > 0 and count or nil
		end
		if reason == "complete" or reason == "completed" then
			Timing(self, "requestCompletion", Now(self) - request.startedAt)
		end
		self:CancelTransportWhere(function(row)
			return row.requestId == id or row.owner == request
		end, reason or "cancelled")
		self:CancelCommTransfers(function(job)
			return job.requestId == id
		end, reason or "cancelled")
	end
end
function QT:CancelCommunicationWhere(predicate, reason)
	self:CancelCommTransfers(predicate, reason)
	self:CancelTransportWhere(predicate, reason)
	local s = rawget(self, "communicationState")
	for key, row in pairs(s and s.replies or {}) do
		if not predicate or predicate(row) then
			self:ReleaseCommResponseBytes(row.reservation)
			s.replies[key] = nil
			s.replyBytes = s.replyBytes - #row.wire
		end
	end
end
function QT:CancelCommunicationOwner(owner, reason)
	self:CancelCommunicationWhere(function(row)
		return row.owner == owner
	end, reason)
end
function QT:IsCommResponseExpected(frame, sender)
	local s = rawget(self, "communicationState")
	local request = s and frame.requestId and s.requests[frame.requestId]
	local latePong = request and request.acceptLatePongs and frame.operation == "PONG"
	if
		not request
		or not Current(self, s)
		or Now(self) < request.startedAt
		or (not latePong and Now(self) >= request.expires)
		or not request.responses[frame.operation]
		or (request.target and request.target ~= sender)
		or (request.groupOnly and (not self:IsGroupedSender(sender) or request.roster ~= self:GetPartyRosterFingerprint()))
		or not Predicate(self, request.isCurrent)
		or s.requests[frame.requestId] ~= request
		or not Current(self, s)
	then
		return false
	end
	if latePong then
		return true, Now(self) + 600
	end
	if frame.total and frame.total > 1 and not request.extended then
		request.extended = true
		request.expires = request.startedAt + 600
		local pending = self.pendingPingRequests and self.pendingPingRequests[frame.requestId]
		if pending then
			pending.expiresAt = request.expires
		end
	end
	return true, request.expires
end
function QT:GetCommunicationRequestDeadline(id)
	local state = rawget(self, "communicationState")
	local request = state and state.requests[id]
	return request and Current(self, state) and request.expires or nil
end
-- Domains may replace a stalled snapshot without reading transfer buffers or
-- treating native acceptance, duplicate fragments, or our own probes as progress.
function QT:GetCommunicationRequestProgress(id)
	local state = rawget(self, "communicationState")
	local request = state and state.requests[id]
	if not request or not Current(self, state) then return nil end
	return { startedAt = request.startedAt, firstResponseAt = request.firstResponseAt,
		lastProgressAt = request.lastProgressAt, expires = request.expires }
end
function QT:RecordCommunicationResponseProgress(frame, sender)
	local state = rawget(self, "communicationState")
	local request = state and frame.requestId and state.requests[frame.requestId]
	if not request or not self:IsCommResponseExpected(frame, sender) then return false end
	FirstResponse(self, request)
	return true
end
local function Seen(s, key, now, remember)
	local old = s.seen[key]
	if old and now >= old and now - old < 600 then
		return true
	end
	if remember == false then
		return false
	end
	s.seenCursor = s.seenCursor % 4096 + 1
	local retired = s.seenRing[s.seenCursor]
	if retired then
		s.seen[retired] = nil
	end
	s.seenRing[s.seenCursor] = key
	s.seen[key] = now
	return false
end
function QT:ApplyCommunicationState(records, sender, context)
	local accepted = false
	for _, row in ipairs(records or {}) do
		local handler = STATE_HANDLERS[row.topic]
		if handler and self[handler] then
			local serverNow = self:GetAnnouncementServerTime()
			local stamp = row.sampledAt or context.stamp
			local age = serverNow and stamp and stamp > 0 and serverNow - stamp or nil
			if age and age >= -1 and age < 600 and self:CanAcceptPeerEpoch(sender, context.session, context.stamp) then
				local observation = self:CreatePeerObservation(sender, row.topic, {
					source = "snapshot",
					age = math.max(0, age),
					sourceSampledAt = stamp,
					lifetime = 600,
					session = context.session,
					sequence = row.revision or context.sequence,
					stamp = context.stamp,
				})
				if observation and self:CanAcceptPeerObservation(observation) then
					local ok, value = self[handler](self, row.data, sender, observation)
					if ok then
						accepted = true
						self:RecordPeerEpoch(sender, context.session, context.stamp)
						if row.topic == "LOC" then
							self:RecordGeographicPeerLocation(sender, value or row.data, observation)
						end
					end
				end
			end
		end
	end
	return accepted
end
local function ExpireRequest(a, request, reason, detail)
	if request.expiryNotified then
		return
	end
	request.expiryNotified = true
	if reason == "expired" then
		local metrics = a:GetCommunicationMetrics()
		metrics.expiredRequests = metrics.expiredRequests + 1
	end
	Invoke(a, "request expiry", request.onExpire, reason, detail)
end
local function DispatchOperation(self, frame, data, sender, context)
	local spec = self:GetCommOperation(frame.operation)
	local operation = frame.operation
	if spec.semantic == "transfer" then
		return self:HandleCommTransferControl(operation, data, sender)
	end
	if operation == "STATE" then
		return self:ApplyCommunicationState(data.records, sender, context)
	end
	if operation == "BYE" then
		local now = self:GetAnnouncementServerTime()
		if
			not now
			or frame.stamp <= 0
			or now - frame.stamp >= 600
			or now - frame.stamp < -1
			or not self:CanAcceptPeerEpoch(sender, frame.session, frame.stamp)
		then
			return false
		end
		local accepted = self:RecordPeerDeparture(
			sender,
			Now(self) - math.max(0, now - frame.stamp),
			frame.session,
			context.sequence
		)
		if accepted then
			self:RemoveDeveloperAnnouncementSubscriber(sender, context)
		end
		return accepted
	end
	if STATE_HANDLERS[operation] then
		return self:ApplyCommunicationState(
			{ { topic = operation, data = data, sampledAt = frame.stamp } },
			sender,
			context
		)
	end
	if operation == "QTDQ" then
		return self:HandleGeographicDiscovery(data, sender, context)
	end
	if operation == "HELLO" then
		return self:HandleDeveloperAnnouncementHello(data, sender, context)
	end
	if operation == "VIP" then
		return self:HandleVIPIdentity(data, sender, context)
	end
	if operation == "DEVANN" then
		return self:HandleDeveloperAnnouncementSubscription(data, sender, context)
	end
	if operation == "DLOC" then
		return self:HandleDeveloperLocationSnapshot(data, sender, context)
	end
	if operation == "QTN2" then
		return self:HandlePartyNavigationMessage(data, sender, context)
	end
	if operation == "QTHQ" or operation == "QTHD" then
		return self:HandlePlayerDetailsMessage(operation, data, sender, context)
	end
	if operation == "QTSR" or operation == "QTSP" or operation == "QTSX" then
		return self:HandleNearbyStreamMessage(operation, data, sender, context)
	end
	if operation == "ANN" or operation == "LVL" then
		local event = self:SanitizeAnnouncementEventData(data)
		if not event or (operation == "LVL" and event.eventType ~= "PLAYER_LEVEL_UP") then
			return false
		end
		self:RecordAnnouncementLatency(event)
		self:RecordQTPlayerPresence(sender, true)
		self:ObservePartyQuestProgress(event, sender, context)
		self:HandleAnnouncementEvent(event, false)
		return true
	end
	if operation == "PING" then
		return self:HandlePingRequest(data, context.distribution, context.localID, context.channelName)
	end
	if operation == "PONG" then
		return self:HandlePingResponse(data)
	end
	if operation == "DREPORT" then
		return self:HandleDeveloperReport(data, sender)
	end
	if operation == "QCMP" then
		return self:HandleQuestCompareRequest(data)
	end
	if operation == "QCRS" then
		return self:HandleQuestCompareResponse(data, sender)
	end
	if operation == "QPGR" then
		return self:HandlePartyVisualRosterRequest(data, sender, true)
	end
	if operation == "QPGM" then
		return self:HandlePartyVisualRosterMember(data, sender)
	end
	if operation == "QTPH" then
		return self:HandlePlayerPhaseMessage(data, sender)
	end
	if operation == "QJON" then
		return self:HandlePartyJoinMessage(data, sender, true)
	end
	if operation == "QSHR" then
		return self:HandlePartyQuestShareMessage(data, sender, context.distribution)
	end
	return false
end
function QT:DispatchCommRecord(frame, data, sender, context)
	local s = self:InitializeCommunications()
	local spec = self:GetCommOperation(frame.operation)
	if not Current(self, s) or not spec or type(data) ~= "table" then
		return false
	end
	if data.requestId ~= frame.requestId and (data.requestId or frame.requestId) then
		return false
	end
	if data.senderName and data.senderName ~= "" and Name(self, data.senderName) ~= sender then
		return false
	end
	context = Copy(context)
	context.requestId = frame.requestId
	context.session = frame.session
	context.sequence = tonumber(frame.messageId)
	context.stamp = frame.stamp
	context.messageId = frame.messageId
	if
		spec.privateOnly
		and (context.distribution ~= "WHISPER" or not self:IsDeveloperLocationSubscriptionCurrent(
			data.subscriptionSession, data.subscriptionId
		))
	then
		return false
	end
	if not context.sequence or context.sequence < 1 or context.sequence > 1e12 or context.sequence % 1 ~= 0 then
		return false
	end
	if (spec.groupOnly or data.partyOnly == true) and not self:IsGroupedSender(sender) then
		return false
	end
	local response = self:IsCommResponseRecord(frame.operation, data)
	if response and (context.distribution == "CHANNEL" or not self:IsCommResponseExpected(frame, sender)) then
		return false
	end
	local request = frame.requestId and s.requests[frame.requestId]
	if frame.operation == "ERROR" and (not request or data.operation ~= request.operation) then
		return false
	end
	local key = sender .. ":" .. frame.session .. ":" .. frame.messageId
	local isRequest = spec.semantic == "request" and not response
	-- Authenticated subscriptions own replay admission. A cached signed offer
	-- must be usable again after consent/session reset or verifier congestion.
	if not spec.authenticatedEvent and Seen(s, key, Now(self), not isRequest) then
		self:GetCommunicationMetrics().duplicates = self:GetCommunicationMetrics().duplicates + 1
		if spec.semantic == "request" and not response then
			self:ReplayCommResponses(sender, frame.requestId)
		end
		return true
	end
	data.senderName, data.requesterName = sender, sender
	if frame.operation == "ERROR" then
		self:CancelCommRequest(frame.requestId, "remote-error")
		ExpireRequest(self, request, data.code, data.detail)
		return true
	end
	local ok, result
	if response and request and request.onResponse then
		ok, result = Invoke(self, "request response", request.onResponse, data, sender, context)
	else
		ok, result = pcall(DispatchOperation, self, frame, data, sender, context)
	end
	if not ok then
		self:RecordDiagnosticError("communication dispatch", result)
		return false
	end
	if result == true and isRequest and Current(self, s) then
		Seen(s, key, Now(self))
	end
	if response and request and result == true and rawget(self, "communicationState") == s then
		FirstResponse(self, request)
		Timing(self, "responseCompletion", Now(self) - request.startedAt)
	end
	return result == true
end
-- Bound decode/dispatch work independently of retained object limits. The
-- runtime grants one frame's allowance; idle time never accumulates a burst.
local function AdmitIncoming(a, wire, distribution, sender)
	local s = a:InitializeCommunications()
	if not Current(a, s) then
		return false
	end
	-- Extra developer copies get a smaller allowance before consuming the
	-- shared ingress budget, preserving room for normal zone and party work.
	if
		distribution == "WHISPER"
		and (wire:sub(1, 6) == "2|ANN|" or wire:sub(1, 6) == "2|LVL|" or wire:sub(1, 7) == "2|DLOC|")
		and not a:AdmitDeveloperAnnouncementPacket()
	then
		return false
	end
	local reserved = (GROUP[distribution] or distribution == "WHISPER")
		and ((s.inboundTargets[sender] or 0) > 0 or a:IsGroupedSender(sender))
	local packets, bytes = s.ingressPackets or 0, s.ingressBytes or 0
	local publicPackets, publicBytes = s.ingressPublicPackets or 0, s.ingressPublicBytes or 0
	if
		packets >= INGRESS_PACKETS
		or bytes + #wire > INGRESS_BYTES
		or (not reserved and (publicPackets >= PUBLIC_PACKETS or publicBytes + #wire > PUBLIC_BYTES))
	then
		local metrics = a:GetCommunicationMetrics()
		metrics.ingressDropped = (metrics.ingressDropped or 0) + 1
		return false
	end
	s.ingressPackets, s.ingressBytes = packets + 1, bytes + #wire
	if not reserved then
		s.ingressPublicPackets, s.ingressPublicBytes = publicPackets + 1, publicBytes + #wire
	end
	return true
end
local function Receive(self, prefix, wire, distribution, sender, localID, channelName)
	if
		not self:CanAccessValue(prefix)
		or not self:CanAccessValue(distribution)
		or not self:CanAccessValue(wire)
		or prefix ~= self.commPrefix
		or type(wire) ~= "string"
		or #wire > 255
		or type(distribution) ~= "string"
		or not self.isEnabled
		or self.isLoggingOut
	then
		return false
	end
	sender = Name(self, sender)
	if not sender or not AdmitIncoming(self, wire, distribution, sender) then
		return false
	end
	if self:IsSelfSender(sender) or self:IsIgnoredPlayerName(sender) then
		return false
	end
	local frame, body = self:DecodeCommFrame(wire)
	if not frame then
		return false
	end
	local spec = self:GetCommOperation(frame.operation)
	local context = { distribution = distribution, localID = localID, channelName = channelName }
	if spec.privateOnly and (distribution ~= "WHISPER" or not self:IsDeveloperLocationSubscriptionCurrent()) then
		return false
	end
	if GROUP[distribution] then
		if not self:IsGroupedSender(sender) then
			return false
		end
		context.group = true
	elseif distribution == "CHANNEL" then
		if
			not self:IsAnnouncementChannelEvent(distribution, localID, channelName)
			and not self:IsGeographicChannelEvent(distribution, localID, channelName)
		then
			return false
		end
		if
			spec.semantic == "response"
			or spec.semantic == "transfer"
			or spec.groupOnly
			or spec.semantic == "stream"
		then
			return false
		end
	elseif distribution ~= "WHISPER" then
		return false
	end
	if spec.groupOnly and not self:IsGroupedSender(sender) then
		return false
	end
	if spec.regionalOnly and not self:IsGeographicChannelEvent(distribution, localID, channelName) then
		return false
	end
	if spec.globalOnly and not self:IsGlobalAnnouncementChannelEvent(distribution, localID, channelName) then
		return false
	end
	context.backgroundAnnouncement = distribution == "WHISPER"
		and (frame.operation == "ANN" or frame.operation == "LVL" or frame.operation == "DLOC")
	if spec.semantic == "response" then
		if not self:IsCommResponseExpected(frame, sender) then
			return false
		end
		local pending = self.communicationState.requests[frame.requestId]
		context.targeted = pending and pending.target == sender or false
	end
	self:GetCommunicationMetrics().received = self:GetCommunicationMetrics().received + 1
	local accepted = self:ReceiveCommFragment(frame, body, sender, context)
	if accepted and spec.semantic == "response" then
		local state = rawget(self, "communicationState")
		local request = state and state.requests[frame.requestId]
		if request then
			FirstResponse(self, request)
		end
	end
	return accepted
end
function QT:ReceiveCommunication(...)
	local ok, result = pcall(Receive, self, ...)
	if not ok then
		self:RecordDiagnosticError("communication receive", result)
		return false
	end
	return result
end
function QT:UpdateCommunicationRuntime()
	local s = rawget(self, "communicationState")
	if not s or not Current(self, s) then
		return
	end
	s.ingressPackets, s.ingressBytes, s.ingressPublicPackets, s.ingressPublicBytes = 0, 0, 0, 0
	local now = Now(self)
	if now < s.startedAt then
		self:EndCommunicationSession()
		return
	end
	self:UpdateDeveloperAnnouncements(now)
	self:UpdateVIPIdentity()
	self:FlushPendingQuestScanAnnouncement()
	local requests = {}
	for id, request in pairs(s.requests) do
		requests[#requests + 1] = { id, request }
	end
	for _, row in ipairs(requests) do
		local id, request = row[1], row[2]
		if not Current(self, s) then
			return
		end
		if s.requests[id] == request then
			local cancelled = not Predicate(self, request.isCurrent)
				or (request.groupOnly and request.roster ~= self:GetPartyRosterFingerprint())
			if not Current(self, s) then
				return
			end
			if s.requests[id] == request then
				if cancelled or (now >= request.expires and not request.acceptLatePongs) then
					self:CancelCommRequest(id, "expired")
					ExpireRequest(self, request, cancelled and "cancelled" or "expired")
				elseif now >= request.expires then
					ExpireRequest(self, request, "expired")
				elseif
					request.acceptedAt
					and not request.responseProgress
					and request.retries < 2
					and now >= request.acceptedAt + ({ 5, 15 })[request.retries + 1]
				then
					request.retries = request.retries + 1
					self:SubmitCommunication(request.operation, request.record, request.routes, request.retryOptions)
				end
			end
		end
	end
	if not Current(self, s) then
		return
	end
	for key, row in pairs(s.replies or {}) do
		if now >= row.expires or not Predicate(self, row.isCurrent) then
			self:ReleaseCommResponseBytes(row.reservation)
			s.replies[key] = nil
			s.replyBytes = s.replyBytes - #row.wire
		end
	end
	if not Current(self, s) then
		return
	end
	self:UpdateCommTransfers()
	if not Current(self, s) then
		return
	end
	if self.UpdateCommunicationRequests then
		self:UpdateCommunicationRequests(now)
	end
	if Current(self, s) then
		self:DrainTransport()
	end
end
function QT:EndCommunicationSession(preserveVerifiedPeers)
	self:ResetVIPIdentity(preserveVerifiedPeers)
	self:ResetDeveloperAnnouncements()
	local s = rawget(self, "communicationState")
	local requests = s and s.requests or {}
	if s then
		s.departing = true
		s.generation = s.generation + 1
		s.requests, s.inboundTargets = {}, {}
		for _, row in pairs(s.replies or {}) do
			self:ReleaseCommResponseBytes(row.reservation)
		end
		s.replies, s.replyBytes = {}, 0
	end
	self.commsWorldGeneration = (rawget(self, "commsWorldGeneration") or 0) + 1
	if self.ResetCommTransfers then
		self:ResetCommTransfers("cancelled")
	end
	self:EndTransportSession()
	self.pingReplyState = nil
	self.developerRequestState = nil
	self.questCompareResponseCache = nil
	for _, request in pairs(requests) do
		ExpireRequest(self, request, "cancelled")
	end
end
function QT:ResumeCommunicationSession()
	local s = self:InitializeCommunications()
	s.departing = nil
	s.startedAt = Now(self)
	self:ResumeTransportSession()
	self:InitializeDeveloperAnnouncements()
	if self.ResumeGeographicComms then
		self:ResumeGeographicComms()
	end
	self:BroadcastQTPlayerPresence()
	self:BroadcastQuestPartnerStatus(true)
	self:BroadcastPartyJoinMetadata(true)
end
function QT:FlushCommunicationDeparture()
	local routes = self:GetGeographicAnnouncementRoutes() or {}
	local present = false
	for _, route in ipairs(routes) do
		if route.channelName == self.announcementChannelName then
			present = true
		end
	end
	if not present then
		routes[#routes + 1] =
			{ distribution = "CHANNEL", channelName = self.announcementChannelName, requiresChannelJoin = true }
	end
	return self:Emit("BYE", { reason = "departure" }, routes, { direct = true, priority = "control" })
end
function QT:EndCommsWorldSession(preserveVerifiedPeers)
	self:ResetQuestFocusWindow()
	self:CancelPartyQuestObjectiveRequests(rawget(self, "partyQuestCompareSession"))
	self:ResetPartyQuestProgress()
	self:ResetLocalizedQuestTitles()
	return self:EndCommunicationSession(preserveVerifiedPeers)
end
function QT:ResumeCommsWorldSession()
	local result = self:ResumeCommunicationSession()
	local session = rawget(self, "partyQuestCompareSession")
	for _, member in ipairs(session and session.members or {}) do self:LoadPartyQuestObjectives(member) end
	return result
end
function QT:FlushGeographicDeparture()
	return self:FlushCommunicationDeparture()
end
