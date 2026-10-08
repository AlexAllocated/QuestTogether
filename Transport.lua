-- Neutral outbound transport. Domain producers own routing, consent and wire
-- codecs; this module owns bounded admission, native acceptance and cancellation.
local QT = _G.QuestTogether
local CLASSES = { "event", "control", "bulk", "bulk", "bulk", "snapshot" }
local function Now(a)
	return a:SafeToNumber(a.API and a.API.GetTime and a.API.GetTime()) or 0
end
local function Complete(a, row, sent, reason)
	if row.completed then
		return
	end
	row.completed = true
	if row.onComplete then
		local ok, detail = pcall(row.onComplete, sent, reason)
		if not ok then
			a:RecordDiagnosticError("outbound completion", detail)
		end
	end
end
function QT:InitializeTransport()
	local state = rawget(self, "transportState")
	if not state then
		state = { queue = {}, tokens = 4, tokenAt = Now(self), generation = 0 }
		self.transportState = state
	end
	return state
end
function QT:GetTransportState()
	return rawget(self, "transportState")
end

function QT:CancelTransportWhere(predicate, reason)
	local state, cancelled = self:GetTransportState(), {}
	if not state then
		return
	end
	for index = #state.queue, 1, -1 do
		local row = state.queue[index]
		if predicate(row) then
			table.remove(state.queue, index)
			cancelled[#cancelled + 1] = row
		end
	end
	-- Callbacks may enqueue replacement work; never invoke them during traversal.
	for _, row in ipairs(cancelled) do
		Complete(self, row, false, reason or "cancelled")
	end
end
function QT:CancelTransportOwner(owner, reason)
	self:CancelTransportWhere(function(row)
		return row.owner == owner
	end, reason)
end
function QT:EndTransportSession()
	local state = self:GetTransportState()
	if state then
		state.departing, state.generation = true, state.generation + 1
		self:CancelTransportWhere(function()
			return true
		end, "cancelled")
	end
end
function QT:ResumeTransportSession()
	local state = self:InitializeTransport()
	state.departing = nil
	return state
end
function QT:ResetTransport()
	self:EndTransportSession()
	self.transportState = nil
end

function QT:TakeCommsSendToken(background, lane)
	local s, now = self:GetTransportState(), Now(self)
	if not s then
		return true
	end
	if now < s.tokenAt then
		s.tokens = 0
	end
	s.tokens = math.min(4, s.tokens + math.max(0, now - s.tokenAt) * 2)
	s.tokenAt = now
	if s.departing or (s.blockedUntil and now < s.blockedUntil) then
		return false
	end
	if lane == "nearby" then
		if now < (s.nextNearbySend or 0) then
			return false
		end
		for _, row in ipairs(s.queue) do
			if row.priority == "event" or row.priority == "control" then
				return false
			end
		end
		s.nextNearbySend = now + 0.2
		return true
	end
	if s.tokens < (background and 2 or 1) then
		return false
	end
	s.tokens = s.tokens - 1
	return true
end

-- "scheduled" already holds a normal token; "nearby" drops obsolete samples
-- instead of queuing them; "departure" is the sole final-world-send exception.
function QT:SendTransportNow(wire, context, route, mode)
	if not self.isEnabled or (self.isLoggingOut and mode ~= "departure") then
		return false, "cancelled"
	end
	if
		type(wire) ~= "string"
		or #wire == 0
		or #wire > 255
		or wire:find("\0", 1, true)
		or type(route) ~= "table"
		or not self.API.SendAddonMessage
	then
		return false, "invalid"
	end
	local state = self:GetTransportState()
	if mode ~= "departure" then
		if state and state.departing then
			return false, "cancelled"
		end
		if mode ~= "scheduled" and not self:TakeCommsSendToken(false, mode) then
			return false, "paced"
		end
	end
	if route.requiresChannelJoin and not self:EnsureAnnouncementChannelJoined(route.channelName) then
		self:RecordCommsDiagnostic("failedRoutes", "channel join failed " .. (context or "wire message"))
		return false, "failed"
	end
	local target = route.requiresChannelJoin and self:GetAnnouncementChannelTarget(route.channelName) or route.target
	local ok, result = pcall(self.API.SendAddonMessage, self.commPrefix, wire, route.distribution, target)
	if ok and self:CanAccessValue(result) and (result == 0 or result == true) then
		self:RecordCommsTraffic("sent", wire)
		self:RecordCommsDiagnostic(
			"sentRoutes",
			"route=" .. route.distribution .. " bytes=" .. #wire .. " " .. (context or "wire message")
		)
		return true, "accepted"
	end
	local code = self:SafeToNumber(result)
	if state and (code == 3 or code == 8) then
		state.blockedUntil = Now(self) + 2
	end
	self:RecordCommsTraffic("failed", wire, code)
	self:RecordCommsDiagnostic("failedRoutes", "route=" .. route.distribution .. " " .. (context or "wire message"))
	return false, "failed"
end

function QT:QueueTransportWire(wire, context, route, options)
	local state = self:GetTransportState()
	if not state or not self.isEnabled or self.isLoggingOut or state.departing then
		return false, "cancelled"
	end
	if type(wire) ~= "string" or #wire == 0 or #wire > 255 or wire:find("\0", 1, true) then
		return false, "invalid"
	end
	options = options or {}
	if options.key then
		self:CancelTransportWhere(function(row)
			return row.key == options.key
		end, "superseded")
	end
	if #state.queue >= 96 then
		self:RecordCommsDiagnostic("queueDropped", "outbound queue full")
		return false, "capacity"
	end
	local row = {}
	for key, value in pairs(options) do
		row[key] = value
	end
	row.wire, row.context, row.route = wire, context, route
	row.priority, row.createdAt = row.priority or "control", Now(self)
	row.expires = row.expires or (row.createdAt + (row.snapshot and 15 or 30))
	state.queue[#state.queue + 1] = row
	self:RecordCommsTraffic("queued", wire)
	return true, "queued"
end

function QT:DrainTransport()
	local state, now = self:GetTransportState(), Now(self)
	if not state or not self.isEnabled or self.isLoggingOut or state.departing then
		return
	end
	self:CancelTransportWhere(function(row)
		local current = true
		if row.isCurrent then
			local ok, value = pcall(row.isCurrent)
			current = ok and value == true
		end
		return now < row.createdAt or now >= row.expires or not current
	end, "cancelled")
	local index, slot
	for offset = 1, #CLASSES do
		local cursor = ((state.sendClassCursor or 0) + offset - 1) % #CLASSES + 1
		for i, row in ipairs(state.queue) do
			if row.priority == CLASSES[cursor] and (not row.retryAt or now >= row.retryAt) then
				index, slot = i, cursor
				break
			end
		end
		if index then
			break
		end
	end
	local row = index and state.queue[index]
	if not row or not self:TakeCommsSendToken(false) then
		return
	end
	state.sendClassCursor = slot
	local sent, reason = self:SendTransportNow(row.wire, row.context, row.route, "scheduled")
	if sent or row.onComplete then
		table.remove(state.queue, index)
		Complete(self, row, sent, reason)
	else
		row.retryAt = now + 2
	end
end
