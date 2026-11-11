-- Neutral outbound transport. Producers supply routing, currentness and encoded
-- packets; admission never means delivery. Every native attempt shares a budget.
local QT = _G.QuestTogether
local CLASSES = { "control", "event", "active", "active", "active", "bulk", "bulk", "background" }
local VALID_CLASSES = { control = true, event = true, active = true, bulk = true, background = true }
local MAX_QUEUE, CONTROL_RESERVE, MAX_MESH_QUEUE = 96, 16, 24
local BYTE_RATE, BYTE_BURST, PACKET_RATE, PACKET_BURST = 800, 1600, 4, 4
local MESH_BYTE_RATE, MESH_BYTE_BURST, MESH_PACKET_RATE, MESH_PACKET_BURST = 400, 400, 2, 2
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
	nativeException = true,
	nativeNoResult = true,
	nativeUnknown = true,
	nativeBooleanSuccess = true,
	whisperUnavailable = true,
	whisperCorrelationFull = true,
	whisperFilterBlocked = true,
}
local NATIVE_RESULTS = {}
local NATIVE_ROUTES = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }
local QUEST_OPERATIONS = { QCMP = true, QCRS = true, FXACK = true, FXEND = true, FXNACK = true }
local FAILURE_REPORT_INTERVAL = 60
for code = 0, 12 do
	local key = "nativeResult" .. code
	NATIVE_RESULTS[code], METRICS[key] = key, true
end
-- Fixed operation/route/result buckets distinguish party failures from
-- unrelated traffic without retaining names or message bodies.
for operation in pairs(QUEST_OPERATIONS) do
	for distribution in pairs(NATIVE_ROUTES) do
		for _, outcome in ipairs({ "nativeException", "nativeNoResult", "nativeUnknown", "nativeBooleanSuccess" }) do
			METRICS["questWire." .. operation .. "." .. distribution .. "." .. outcome] = true
		end
		for _, outcome in pairs(NATIVE_RESULTS) do
			METRICS["questWire." .. operation .. "." .. distribution .. "." .. outcome] = true
		end
	end
end

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
		s.tokens, s.byteTokens, s.meshTokens, s.meshByteTokens, s.activeSeconds, s.lastAcceptedAt = 0, 0, 0, 0, 0, nil
	end
	local elapsed = math.max(0, now - s.tokenAt)
	s.tokens = math.min(PACKET_BURST, s.tokens + elapsed * s.packetRate)
	s.byteTokens = math.min(BYTE_BURST, s.byteTokens + elapsed * BYTE_RATE)
	s.meshTokens = math.min(MESH_PACKET_BURST, (s.meshTokens or 0) + elapsed * MESH_PACKET_RATE)
	s.meshByteTokens = math.min(MESH_BYTE_BURST, (s.meshByteTokens or 0) + elapsed * MESH_BYTE_RATE)
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
		and NATIVE_ROUTES[route.distribution] == true
		and a.API
		and type(a.API.SendAddonMessage) == "function"
end
local function ChatRestricted(a)
	-- This native restriction covers addon chat communication, not ordinary
	-- open-world combat. Producers can pause while already-owned packets remain
	-- queued, so revalidate here immediately before any transport budget is used.
	return a.IsRuntimeRestrictionTypeActive and a:IsRuntimeRestrictionTypeActive("chat") == true
end
local function WhisperUnavailable(a, route)
	return route.distribution == "WHISPER"
		and a.IsAddonWhisperTargetUnavailable
		and a:IsAddonWhisperTargetUnavailable(route.target) == true
end
local function WhisperTrackable(a, route)
	if route.distribution ~= "WHISPER" then
		return true
	end
	if not a.CanRecordAddonWhisperAttempt or not a.RecordAddonWhisperAttempt then
		return false, "invalid"
	end
	return a:CanRecordAddonWhisperAttempt(route.target, route.meshTraffic)
end
local function TrackingFailure(reason)
	return (reason == "capacity" or reason == "filter-unavailable") and reason or "invalid"
end
local function RecordTrackingBlock(s, reason)
	if reason == "capacity" then
		Count(s, "whisperCorrelationFull")
	elseif reason == "filter-unavailable" then
		Count(s, "whisperFilterBlocked")
	end
end

local function Take(s, now, cost, mesh)
	Refill(s, now)
	if s.departing or (s.blockedUntil and now < s.blockedUntil) or s.tokens < 1 or s.byteTokens < cost then
		return false
	end
	if mesh and (s.meshTokens < 1 or s.meshByteTokens < cost) then
		return false
	end
	s.tokens, s.byteTokens = s.tokens - 1, s.byteTokens - cost
	if mesh then
		s.meshTokens, s.meshByteTokens = s.meshTokens - 1, s.meshByteTokens - cost
		s.metrics.meshPackets = (s.metrics.meshPackets or 0) + 1
		s.metrics.meshBytes = (s.metrics.meshBytes or 0) + cost
	end
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
local function ReportNativeFailure(a, s, context, route, nativeKey, nativeLabel)
	local distribution = NATIVE_ROUTES[route.distribution] and route.distribution or "OTHER"
	local key, now = distribution .. ":" .. nativeKey, Now(a)
	s.failureReports = s.failureReports or {}
	local previous = s.failureReports[key]
	if previous and now >= previous and now - previous < FAILURE_REPORT_INTERVAL then
		return
	end
	s.failureReports[key] = now
	local operation = type(context) == "string" and a:GetCommOperation(context) and context or "message"
	local detail = "QuestTogether: Addon message send failed (operation="
		.. operation
		.. ", route="
		.. distribution
		.. ", result="
		.. nativeLabel
		.. "). Communication may be incomplete. Run /qt diagnostics for details."
	a:RecordDiagnosticError("communication send", detail)
end
local function NativeSend(a, s, wire, context, route)
	local target, receipt = route.target, nil
	-- A failed destination is suppressed before cancellation callbacks run.
	-- Keep this final guard for direct sends and reentrant cleanup controls.
	if WhisperUnavailable(a, route) then
		Count(s, "whisperUnavailable")
		return false, "unavailable"
	end
	if route.distribution == "WHISPER" then
		local reason
		if a.RecordAddonWhisperAttempt then
			receipt, reason = a:RecordAddonWhisperAttempt(target, route.meshTraffic)
		end
		if not receipt then
			RecordTrackingBlock(s, reason)
			return false, TrackingFailure(reason)
		end
	end
	Count(s, "attempts")
	local ok, result = pcall(a.API.SendAddonMessage, a.commPrefix, wire, route.distribution, target)
	local code = ok and a:SafeToNumber(result) or nil
	-- Install correlation before native entry for synchronous notices. Only a
	-- definite unsent throttle rolls it back; accepted, ambiguous and unknown
	-- outcomes can still generate a later server notice.
	if receipt and a.FinalizeAddonWhisperAttempt then
		a:FinalizeAddonWhisperAttempt(receipt, code == 3)
	end
	if receipt and code == 12 and a.MarkAddonWhisperAttemptUnavailable then
		a:MarkAddonWhisperAttemptUnavailable(receipt)
	end
	local nativeKey, nativeLabel = "nativeUnknown", "unknown"
	if not ok then
		nativeKey, nativeLabel = "nativeException", "exception"
	elseif a:CanAccessValue(result) then
		if result == nil then
			nativeKey, nativeLabel = "nativeNoResult", "no-result"
		elseif result == true then
			nativeKey, nativeLabel = "nativeBooleanSuccess", "true"
		elseif code then
			-- Fixed enum buckets only. New/invalid results cannot grow metric keys,
			-- while the bounded debug log retains their safe numeric value.
			nativeKey, nativeLabel = NATIVE_RESULTS[code] or "nativeUnknown", tostring(code)
		end
	end
	Count(s, nativeKey)
	if QUEST_OPERATIONS[context] and NATIVE_ROUTES[route.distribution] then
		Count(s, "questWire." .. context .. "." .. route.distribution .. "." .. nativeKey)
	end
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
	a:RecordCommsDiagnostic(
		"failedRoutes",
		"route=" .. route.distribution .. " result=" .. nativeLabel .. " " .. (context or "wire message")
	)
	if code == 3 then
		s.blockedUntil, s.packetRate, s.tokens = Now(a) + 1, 1, 0
		s.activeSeconds, s.lastAcceptedAt = 0, nil
		Count(s, "throttled")
		return false, "throttled", code
	end
	-- Code 8 may already have transmitted. Never resend an ambiguous packet.
	if code ~= 8 then
		ReportNativeFailure(a, s, context, route, nativeKey, nativeLabel)
	end
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
			meshTokens = 0,
			meshByteTokens = 0,
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
	if self.RegisterAddonWhisperChatFilter then
		self:RegisterAddonWhisperChatFilter()
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
		s.tokens, s.byteTokens, s.meshTokens, s.meshByteTokens, s.tokenAt = 0, 0, 0, 0, Now(self)
		s.lastFlow, s.sendClassCursor, s.meshLastFlow, s.meshClassCursor = {}, nil, {}, nil
	end
	s.departing = nil
	return s
end
function QT:ResetTransport()
	self:EndTransportSession()
	self.transportState = nil
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
	if ChatRestricted(self) then
		return false, "restricted"
	end
	if WhisperUnavailable(self, route) then
		Count(s, "whisperUnavailable")
		return false, "unavailable"
	end
	local trackable, trackingReason = WhisperTrackable(self, route)
	if not trackable then
		RecordTrackingBlock(s, trackingReason)
		return false, TrackingFailure(trackingReason)
	end
	if s.departing then
		if (s.blockedUntil and now < s.blockedUntil) or s.tokens < 1 or s.byteTokens < cost then
			return false, "paced"
		end
		if route.meshTraffic and (s.meshTokens < 1 or s.meshByteTokens < cost) then
			return false, "paced"
		end
		s.tokens, s.byteTokens = s.tokens - 1, s.byteTokens - cost
		if route.meshTraffic then
			s.meshTokens, s.meshByteTokens = s.meshTokens - 1, s.meshByteTokens - cost
			s.metrics.meshPackets = (s.metrics.meshPackets or 0) + 1
			s.metrics.meshBytes = (s.metrics.meshBytes or 0) + cost
		end
	elseif not Take(s, now, cost, route.meshTraffic) then
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
	-- Receipt capacity and safe error filtering may recover before expiry.
	-- Hold finite background work without spending native budget; private work
	-- remains eligible. An invalid address cannot recover by waiting.
	local trackable, trackingReason = WhisperTrackable(self, {
		distribution = route.distribution,
		target = route.target,
		meshTraffic = route.meshTraffic == true or (options and options.meshTraffic == true),
	})
	if not trackable and TrackingFailure(trackingReason) == "invalid" then
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
	if WhisperUnavailable(self, route) then
		Count(s, "whisperUnavailable")
		return false, "unavailable"
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
	local mesh = options.meshTraffic == true or route.meshTraffic == true
	local meshCount = s.inFlight and s.inFlight.meshTraffic and 1 or 0
	for _, row in ipairs(s.queue) do
		if row.meshTraffic and (options.key == nil or row.key ~= options.key) then
			meshCount = meshCount + 1
		end
	end
	if mesh and meshCount >= MAX_MESH_QUEUE then
		Count(s, "capacity")
		return false, "capacity"
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
		meshTraffic = options.meshTraffic == true or route.meshTraffic == true,
	}
	row.meshTraffic = row.route.meshTraffic
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

local function SharedFlow(row)
	-- The outer scheduler sees one stable mesh flow. Its inner scheduler owns
	-- destination fairness; rotating that destination must not erase the outer
	-- scheduler's last turn and repeatedly jump ahead of replaced party state.
	return row.meshTraffic and "mesh" or row.flow
end
local function SelectClass(a, s, now, cursor, lastFlow, eligible, reserveTurn, flowKey)
	for offset = 1, #CLASSES do
		local slot = ((cursor or 0) + offset - 1) % #CLASSES + 1
		local class, flows, seen = CLASSES[slot], {}, {}
		for _, row in ipairs(s.queue) do
			local flow = flowKey and flowKey(row) or row.flow
			local trackable, trackingReason = true, nil
			if row.priority == class then
				trackable, trackingReason = WhisperTrackable(a, row.route)
				if not trackable and row.correlationBlocked ~= trackingReason then
					RecordTrackingBlock(s, trackingReason)
				end
				row.correlationBlocked = not trackable and trackingReason or nil
			end
			if row.priority == class and trackable and eligible(row) and not seen[flow] then
				seen[flow] = true
				flows[#flows + 1] = row
			end
		end
		local start = 0
		for index, row in ipairs(flows) do
			if (flowKey and flowKey(row) or row.flow) == lastFlow[class] then
				start = index
				break
			end
		end
		for offsetFlow = 1, #flows do
			local row = flows[(start + offsetFlow - 1) % #flows + 1]
			local cost = Cost(a, row.wire)
			if
				(not row.retryAt or now >= row.retryAt)
				and (
					reserveTurn
					or (
						s.byteTokens >= cost
						and (not row.meshTraffic or (s.meshTokens >= 1 and s.meshByteTokens >= cost))
					)
				)
			then
				return row, slot
			end
		end
	end
end
local function Select(a, s, now)
	-- The public sub-budget has its own class rotation. Otherwise unrelated
	-- party sends can repeatedly consume one class's turn while mesh tokens
	-- refill, starving public background identity proofs indefinitely.
	-- Reserve that turn before checking its cost. Cheap directory/control
	-- packets must not continually spend the bytes a larger proof needs.
	-- No row is retained: cancellation/expiry changes the next selection, and
	-- private traffic can still use the shared budget while mesh credit grows.
	s.meshLastFlow = s.meshLastFlow or {}
	local mesh, meshSlot = SelectClass(a, s, now, s.meshClassCursor, s.meshLastFlow, function(row)
		return row.meshTraffic
	end, true)
	local row, slot = SelectClass(a, s, now, s.sendClassCursor, s.lastFlow, function(candidate)
		-- A mesh turn cannot block private traffic while its smaller budget
		-- refills. Once eligible, every outer turn reserves shared byte credit;
		-- continuously affordable small packets cannot starve a larger one.
		return not candidate.meshTraffic
			or (candidate == mesh and s.meshTokens >= 1 and s.meshByteTokens >= Cost(a, candidate.wire))
	end, true, SharedFlow)
	return row, slot, row == mesh and meshSlot or nil
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
		local reason = (now < row.createdAt or now >= row.expires) and "expired"
			or (not Current(row) and "cancelled")
			or (WhisperUnavailable(self, row.route) and "unavailable")
		if reason and Remove(s, row) then
			if reason == "unavailable" then
				Count(s, "whisperUnavailable")
			end
			Complete(s, row, false, reason)
		end
	end
	for _ = 1, 2 do
		if self:GetTransportState() ~= s or s.departing or not self.isEnabled or self.isLoggingOut
			or ChatRestricted(self) then
			break
		end
		now = Now(self)
		Refill(s, now)
		local row, slot, meshSlot = Select(self, s, now)
		if not row then
			break
		end
		if not Current(row) then
			if Remove(s, row) then
				Complete(s, row, false, "cancelled")
			end
			break
		end
		if self:GetTransportState() ~= s or s.departing or not self.isEnabled or self.isLoggingOut
			or ChatRestricted(self) then
			break
		end
		if now < row.createdAt or now >= row.expires then
			if Remove(s, row) then
				Complete(s, row, false, "expired")
			end
			break
		end
		if WhisperUnavailable(self, row.route) then
			if Remove(s, row) then
				Count(s, "whisperUnavailable")
				Complete(s, row, false, "unavailable")
			end
			break
		end
		-- Currentness callbacks can change local chat/filter safety after
		-- selection. Preserve the packet and all native credit if they do.
		local trackable, trackingReason = WhisperTrackable(self, row.route)
		if not trackable then
			if row.correlationBlocked ~= trackingReason then RecordTrackingBlock(s, trackingReason) end
			row.correlationBlocked = trackingReason
			break
		end
		if not Take(s, now, Cost(self, row.wire), row.meshTraffic) then
			break
		end
		if not Remove(s, row) then
			break
		end
		s.sendClassCursor, s.lastFlow[row.priority], s.inFlight = slot, SharedFlow(row), row
		if meshSlot then
			s.meshClassCursor, s.meshLastFlow[row.priority] = meshSlot, row.flow
		end
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

-- Fixed counters and bounded aggregate gauges: no per-peer/ticket diagnostics.
function QT:GetTransportMetrics()
	local s, result = self:GetTransportState(), { queuedPackets = 0, queuedBytes = 0, oldestAge = 0, classes = {} }
	for class in pairs(VALID_CLASSES) do
		result.classes[class] = 0
	end
	if not s then
		return result
	end
	result.packetRate, result.packetTokens, result.byteTokens = s.packetRate, s.tokens, s.byteTokens
	result.byteRate, result.byteBurst, result.packetBurst = BYTE_RATE, BYTE_BURST, PACKET_BURST
	result.meshPacketRate, result.meshByteRate = MESH_PACKET_RATE, MESH_BYTE_RATE
	result.meshPacketBurst, result.meshByteBurst = MESH_PACKET_BURST, MESH_BYTE_BURST
	local now = Now(self)
	result.meshPacketTokens, result.meshByteTokens = s.meshTokens, s.meshByteTokens
	for key, value in pairs(s.metrics) do
		result[key] = value
	end
	for _, row in ipairs(s.queue) do
		result.queuedPackets = result.queuedPackets + 1
		result.queuedBytes = result.queuedBytes + Cost(self, row.wire)
		result.oldestAge = math.max(result.oldestAge, now - row.createdAt)
		result.classes[row.priority] = result.classes[row.priority] + 1
	end
	return result
end
