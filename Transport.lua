-- Neutral outbound transport. Producers supply routing, currentness and encoded
-- packets; admission never means delivery. Every native attempt shares a budget.
local QT = _G.QuestTogether
local CLASSES = { "control", "event", "active", "active", "active", "bulk", "bulk", "background" }
local VALID_CLASSES = { control = true, event = true, active = true, bulk = true, background = true }
local MAX_QUEUE, CONTROL_RESERVE = 96, 16
local BYTE_RATE, BYTE_BURST, PACKET_RATE, PACKET_BURST = 800, 1600, 4, 4
local METRICS = {
	attempts = true,
	queued = true,
	accepted = true,
	rejected = true,
	ambiguous = true,
	throttled = true,
	expired = true,
	cancelled = true,
	superseded = true,
	capacity = true,
}

local function Now(a)
	return a:SafeToNumber(a.API and a.API.GetTime and a.API.GetTime()) or 0
end
local function Count(s, key)
	if METRICS[key] then
		s.metrics[key] = (s.metrics[key] or 0) + 1
	end
end
local function Flush(a, s)
	if s.draining or s.flushing then
		return
	end
	s.flushing = true
	while #s.completions > 0 do
		local rows = s.completions
		s.completions = {}
		for _, row in ipairs(rows) do
			if row.onComplete then
				local ok, detail = pcall(row.onComplete, row.sent, row.reason, row.code, row.ticket)
				if not ok then
					a:RecordDiagnosticError("outbound completion", detail)
				end
			end
		end
	end
	s.flushing = nil
end
local function Complete(s, row, sent, reason, code)
	if row.completed then
		return
	end
	row.completed, row.sent, row.reason, row.code = true, sent, reason, code
	row.ticket.status = reason
	Count(s, METRICS[reason] and reason or "cancelled")
	s.completions[#s.completions + 1] = row
end
local function Remove(s, row)
	for index, candidate in ipairs(s.queue) do
		if candidate == row then
			table.remove(s.queue, index)
			return true
		end
	end
	return false
end
local function Current(row)
	if not row.isCurrent then
		return true
	end
	local ok, value = pcall(row.isCurrent)
	return ok and value == true
end
local function Refill(s, now)
	if now < s.tokenAt then
		s.tokens, s.byteTokens, s.activeSeconds, s.lastAcceptedAt = 0, 0, 0, nil
	end
	local elapsed = math.max(0, now - s.tokenAt)
	s.tokens = math.min(PACKET_BURST, s.tokens + elapsed * s.packetRate)
	s.byteTokens = math.min(BYTE_BURST, s.byteTokens + elapsed * BYTE_RATE)
	s.tokenAt = now
end
local function Cost(a, wire)
	return #wire + #(a.commPrefix or "") + 40
end
local function Valid(a, wire, route)
	return type(wire) == "string"
		and #wire > 0
		and #wire <= 255
		and not wire:find("\0", 1, true)
		and type(route) == "table"
		and type(route.distribution) == "string"
		and a.API
		and type(a.API.SendAddonMessage) == "function"
end
local function Take(s, now, cost)
	Refill(s, now)
	if s.departing or (s.blockedUntil and now < s.blockedUntil) or s.tokens < 1 or s.byteTokens < cost then
		return false
	end
	s.tokens, s.byteTokens = s.tokens - 1, s.byteTokens - cost
	return true
end
local function Accepted(s, now)
	-- Recovery needs sustained successful traffic. An idle minute earns no rate
	-- increase, and a suspended clock must not manufacture active sending time.
	if s.lastAcceptedAt and now >= s.lastAcceptedAt and now - s.lastAcceptedAt <= 2 then
		s.activeSeconds = s.activeSeconds + now - s.lastAcceptedAt
	end
	s.lastAcceptedAt = now
	if s.packetRate < PACKET_RATE and s.activeSeconds >= 30 then
		s.activeSeconds = s.activeSeconds - 30
		s.packetRate = math.min(PACKET_RATE, s.packetRate + 0.5)
	elseif s.packetRate == PACKET_RATE then
		s.activeSeconds = 0
	end
end
local function NativeSend(a, s, wire, context, route)
	local target = route.target
	if route.requiresChannelJoin then
		local ok, value = pcall(function()
			if a:EnsureAnnouncementChannelJoined(route.channelName) then
				return a:GetAnnouncementChannelTarget(route.channelName)
			end
		end)
		if not ok or not value then
			a:RecordCommsDiagnostic("failedRoutes", "channel join failed " .. (context or "wire message"))
			return false, "rejected"
		end
		target = value
	end
	Count(s, "attempts")
	local ok, result = pcall(a.API.SendAddonMessage, a.commPrefix, wire, route.distribution, target)
	local code = ok and a:SafeToNumber(result) or nil
	if ok and a:CanAccessValue(result) and (result == 0 or result == true) then
		Accepted(s, Now(a))
		a:RecordCommsTraffic("sent", wire)
		a:RecordCommsDiagnostic(
			"sentRoutes",
			"route=" .. route.distribution .. " bytes=" .. #wire .. " " .. (context or "wire message")
		)
		return true, "accepted", code
	end
	a:RecordCommsTraffic("failed", wire, code)
	a:RecordCommsDiagnostic("failedRoutes", "route=" .. route.distribution .. " " .. (context or "wire message"))
	if code == 3 then
		s.blockedUntil, s.packetRate, s.tokens = Now(a) + 1, 1, 0
		s.activeSeconds, s.lastAcceptedAt = 0, nil
		Count(s, "throttled")
		return false, "throttled", code
	end
	-- Code 8 may already have transmitted. Never resend an ambiguous packet.
	return false, code == 8 and "ambiguous" or "rejected", code
end

function QT:InitializeTransport()
	local state = rawget(self, "transportState")
	if not state then
		state = {
			queue = {},
			completions = {},
			tokens = 0,
			byteTokens = 0,
			tokenAt = Now(self),
			packetRate = PACKET_RATE,
			generation = 0,
			nextTicket = 0,
			lastFlow = {},
			activeSeconds = 0,
			metrics = {},
		}
		self.transportState = state
	end
	return state
end
function QT:GetTransportState()
	return rawget(self, "transportState")
end
function QT:CancelTransportWhere(predicate, reason)
	local s = self:GetTransportState()
	if not s or type(predicate) ~= "function" then
		return
	end
	local selected, snapshot = {}, {}
	for _, row in ipairs(s.queue) do
		snapshot[#snapshot + 1] = row
	end
	for _, row in ipairs(snapshot) do
		local ok, value = pcall(predicate, row)
		if ok and value and Remove(s, row) then
			selected[#selected + 1] = row
		end
	end
	if s.inFlight then
		local ok, value = pcall(predicate, s.inFlight)
		if ok and value then
			s.inFlight.cancelReason = reason or "cancelled"
		end
	end
	for _, row in ipairs(selected) do
		Complete(s, row, false, reason or "cancelled")
	end
	Flush(self, s)
end
function QT:CancelTransportOwner(owner, reason)
	self:CancelTransportWhere(function(row)
		return row.owner == owner
	end, reason)
end
function QT:EndTransportSession()
	local s = self:GetTransportState()
	if not s then
		return
	end
	if not s.departing then
		Refill(s, Now(self))
	end
	s.departing, s.generation = true, s.generation + 1
	-- Preserve only the budget already earned before departure. A best-effort
	-- BYE may consume it, but a suspended session must never refill it.
	s.activeSeconds, s.lastAcceptedAt = 0, nil
	self:CancelTransportWhere(function()
		return true
	end, "cancelled")
end
function QT:ResumeTransportSession()
	local s = self:InitializeTransport()
	if s.departing then
		s.tokens, s.byteTokens, s.tokenAt = 0, 0, Now(self)
		s.lastFlow, s.sendClassCursor = {}, nil
	end
	s.departing = nil
	return s
end
function QT:ResetTransport()
	self:EndTransportSession()
	self.transportState = nil
end

-- Retained for internal callers during migration. There is no nearby exemption;
-- callers holding a reservation must not subsequently call SendTransportNow.
function QT:TakeCommsSendToken(_, _, byteCost)
	local s = self:GetTransportState()
	return s ~= nil and Take(s, Now(self), byteCost or (255 + #(self.commPrefix or "") + 40))
end
function QT:SendTransportNow(wire, context, route, mode)
	local s = self:GetTransportState()
	if
		not s
		or not self.isEnabled
		or (s.departing and mode ~= "departure")
		or (self.isLoggingOut and mode ~= "departure")
	then
		return false, "cancelled"
	end
	if not Valid(self, wire, route) then
		return false, "invalid"
	end
	local now, cost = Now(self), Cost(self, wire)
	if mode == "departure" then
		local frame = self.DecodeCommFrame and self:DecodeCommFrame(wire)
		if not frame or frame.operation ~= "BYE" or frame.total ~= 1 then
			return false, "invalid"
		end
	end
	if s.departing then
		if (s.blockedUntil and now < s.blockedUntil) or s.tokens < 1 or s.byteTokens < cost then
			return false, "paced"
		end
		s.tokens, s.byteTokens = s.tokens - 1, s.byteTokens - cost
	elseif not Take(s, now, cost) then
		return false, "paced"
	end
	local sent, reason, code = NativeSend(self, s, wire, context, route)
	if reason ~= "throttled" then
		Count(s, reason)
	end
	return sent, reason, code
end

function QT:QueueTransportWire(wire, context, route, options)
	local s = self:GetTransportState()
	if not s or not self.isEnabled or self.isLoggingOut or s.departing then
		return false, "cancelled"
	end
	if not Valid(self, wire, route) or (options ~= nil and type(options) ~= "table") then
		return false, "invalid"
	end
	options = options or {}
	local priority, now = options.priority or "control", Now(self)
	if priority == "snapshot" then
		priority = "background"
	end
	local expires = self:SafeToNumber(options.expires or options.expiresAt or (now + (options.snapshot and 15 or 30)))
	if
		not VALID_CLASSES[priority]
		or not expires
		or expires ~= expires
		or expires == math.huge
		or expires <= now
		or (options.onComplete ~= nil and type(options.onComplete) ~= "function")
		or (options.isCurrent ~= nil and type(options.isCurrent) ~= "function")
	then
		return false, "invalid"
	end
	local replaced = {}
	local nonControl = s.inFlight and s.inFlight.priority ~= "control" and 1 or 0
	for _, row in ipairs(s.queue) do
		if row.priority ~= "control" and (options.key == nil or row.key ~= options.key) then
			nonControl = nonControl + 1
		end
	end
	if options.key ~= nil then
		for _, row in ipairs(s.queue) do
			if row.key == options.key then
				replaced[#replaced + 1] = row
			end
		end
	end
	local occupied = #s.queue - #replaced + (s.inFlight and 1 or 0)
	if occupied >= MAX_QUEUE or (priority ~= "control" and nonControl >= MAX_QUEUE - CONTROL_RESERVE) then
		Count(s, "capacity")
		self:RecordCommsDiagnostic("queueDropped", "outbound queue full")
		return false, "capacity"
	end
	s.nextTicket = s.nextTicket + 1
	local row = {}
	-- Owned metadata is retained for cancellation predicates; never decode wire.
	for key, value in pairs(options) do
		row[key] = value
	end
	row.wire, row.context = wire, context
	row.route = {
		distribution = route.distribution,
		target = route.target,
		channelName = route.channelName,
		requiresChannelJoin = route.requiresChannelJoin,
	}
	row.priority, row.createdAt, row.expires = priority, now, expires
	row.completed, row.cancelReason, row.retryAt = nil, nil, nil
	row.flow = options.flow
		or options.flowKey
		or (route.distribution .. ":" .. tostring(route.channelName or route.target or ""))
	row.ticket = { id = s.nextTicket, generation = s.generation, status = "queued" }
	for _, old in ipairs(replaced) do
		Remove(s, old)
		Complete(s, old, false, "superseded")
	end
	if s.inFlight and options.key ~= nil and s.inFlight.key == options.key then
		s.inFlight.cancelReason = "superseded"
	end
	s.queue[#s.queue + 1] = row
	s.metrics.highWater = math.max(s.metrics.highWater or 0, #s.queue)
	Count(s, "queued")
	self:RecordCommsTraffic("queued", wire)
	Flush(self, s)
	return true, "queued", row.ticket
end

local function Select(s, now)
	for offset = 1, #CLASSES do
		local slot = ((s.sendClassCursor or 0) + offset - 1) % #CLASSES + 1
		local class, flows, seen = CLASSES[slot], {}, {}
		for _, row in ipairs(s.queue) do
			if row.priority == class and not seen[row.flow] then
				seen[row.flow] = true -- A delayed head must not let its own tail overtake it.
				flows[#flows + 1] = row
			end
		end
		local start = 0
		for index, row in ipairs(flows) do
			if row.flow == s.lastFlow[class] then
				start = index
				break
			end
		end
		for offsetFlow = 1, #flows do
			local row = flows[(start + offsetFlow - 1) % #flows + 1]
			if not row.retryAt or now >= row.retryAt then
				return row, slot
			end
		end
	end
end
function QT:DrainTransport()
	local s, now = self:GetTransportState(), Now(self)
	if not s or s.draining or not self.isEnabled or self.isLoggingOut or s.departing then
		return
	end
	s.draining = true
	local snapshot = {}
	for _, row in ipairs(s.queue) do
		snapshot[#snapshot + 1] = row
	end
	for _, row in ipairs(snapshot) do
		local reason = (now < row.createdAt or now >= row.expires) and "expired" or (not Current(row) and "cancelled")
		if reason and Remove(s, row) then
			Complete(s, row, false, reason)
		end
	end
	for _ = 1, 2 do
		if self:GetTransportState() ~= s or s.departing or not self.isEnabled or self.isLoggingOut then
			break
		end
		now = Now(self)
		local row, slot = Select(s, now)
		if not row then
			break
		end
		if not Current(row) then
			if Remove(s, row) then
				Complete(s, row, false, "cancelled")
			end
			break
		end
		if self:GetTransportState() ~= s or s.departing or not self.isEnabled or self.isLoggingOut then
			break
		end
		if now < row.createdAt or now >= row.expires then
			if Remove(s, row) then
				Complete(s, row, false, "expired")
			end
			break
		end
		if not Take(s, now, Cost(self, row.wire)) then
			break
		end
		if not Remove(s, row) then
			break
		end
		s.sendClassCursor, s.lastFlow[row.priority], s.inFlight = slot, row.flow, row
		local sent, reason, code = NativeSend(self, s, row.wire, row.context, row.route)
		s.inFlight = nil
		if reason == "throttled" then
			if
				row.cancelReason
				or self:GetTransportState() ~= s
				or s.departing
				or not self.isEnabled
				or self.isLoggingOut
				or not Current(row)
			then
				Complete(s, row, false, row.cancelReason or "cancelled", code)
			else
				row.retryAt = s.blockedUntil
				table.insert(s.queue, 1, row)
			end
			break
		end
		s.metrics.maxQueueWait = math.max(s.metrics.maxQueueWait or 0, now - row.createdAt)
		Complete(s, row, sent, reason, code)
	end
	s.draining = nil
	Flush(self, s)
end

-- Fixed counters and five class gauges only: no lifetime per-peer/ticket map.
function QT:GetTransportMetrics()
	local s, result = self:GetTransportState(), { queuedPackets = 0, queuedBytes = 0, oldestAge = 0, classes = {} }
	for class in pairs(VALID_CLASSES) do
		result.classes[class] = 0
	end
	if not s then
		return result
	end
	for key, value in pairs(s.metrics) do
		result[key] = value
	end
	result.packetRate, result.packetTokens, result.byteTokens = s.packetRate, s.tokens, s.byteTokens
	local now = Now(self)
	for _, row in ipairs(s.queue) do
		result.queuedPackets = result.queuedPackets + 1
		result.queuedBytes = result.queuedBytes + Cost(self, row.wire)
		result.oldestAge = math.max(result.oldestAge, now - row.createdAt)
		result.classes[row.priority] = result.classes[row.priority] + 1
	end
	return result
end
