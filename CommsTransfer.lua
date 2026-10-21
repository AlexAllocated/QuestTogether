-- Bounded, addon-owned object delivery. The runtime ticks this service; no
-- packet owns a timer. Domains retain correlation, consent and state admission.
local QT = _G.QuestTogether
local MAX_OUT, MAX_IN, RESERVED = 16, 64, 16
local MAX_BYTES, MAX_OBJECT, MAX_PARTS = 524288, 131072, 1024
local MAX_UNSOLICITED_PER_SENDER, MAX_TOMBSTONES = 4, 128
local PROBE_INTERVAL, MAX_PROBES, MAX_REPAIR = 30, 2, 2
local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end
local function Key(sender, frame)
	return sender .. ":" .. frame.session .. ":" .. frame.messageId
end
local function State(a)
	local state = rawget(a, "commTransferState")
	if not state then
		state = {
			outgoing = {},
			incoming = {},
			completed = {},
			completedOrder = {},
			bytes = 0,
			nextJob = 0,
			cursor = 0,
			metrics = {},
		}
		a.commTransferState = state
	end
	return state
end
local function Count(state, name)
	state.metrics[name] = (state.metrics[name] or 0) + 1
end
local function Timing(state, prefix, elapsed)
	elapsed = math.max(0, elapsed)
	state.metrics[prefix .. "Count"] = (state.metrics[prefix .. "Count"] or 0) + 1
	state.metrics[prefix .. "Last"] = elapsed
	state.metrics[prefix .. "Max"] = math.max(state.metrics[prefix .. "Max"] or 0, elapsed)
end
local function CopyFrame(frame)
	return {
		operation = frame.operation,
		session = frame.session,
		messageId = frame.messageId,
		requestId = frame.requestId,
		total = frame.total,
		stamp = frame.stamp,
		part = 1,
	}
end
local function SameFrame(a, b)
	return a.operation == b.operation
		and a.session == b.session
		and a.messageId == b.messageId
		and a.requestId == b.requestId
		and a.total == b.total
		and a.stamp == b.stamp
end
local function Complete(a, job, success, reason)
	if job.completed then
		return
	end
	job.completed = true
	if job.onComplete then
		local ok, detail = pcall(job.onComplete, success, reason, nil, job)
		if not ok then
			a:RecordDiagnosticError("transfer completion", detail)
		end
	end
end
local function Current(a, state, job)
	local now = Now(a)
	if
		rawget(a, "commTransferState") ~= state
		or not a.isEnabled
		or a.isLoggingOut
		or job.retired
		or now < job.createdAt
		or now >= job.expires
	then
		return false
	end
	if job.isCurrent then
		local ok, current = pcall(job.isCurrent)
		return ok
			and current == true
			and rawget(a, "commTransferState") == state
			and not job.retired
			and a.isEnabled
			and not a.isLoggingOut
	end
	return true
end
local function RetireOut(a, state, job, reason, deferCompletion)
	if job.retired then
		return
	end
	job.retired = true
	for index, value in ipairs(state.outgoing) do
		if value == job then
			table.remove(state.outgoing, index)
			break
		end
	end
	state.bytes = state.bytes - job.bytes
	a:CancelTransportOwner(job, reason or "cancelled")
	if not deferCompletion then
		Complete(a, job, false, reason or "cancelled")
	end
end
local function RetireIn(state, key)
	local item = state.incoming[key]
	if item then
		item.retired = true
		state.incoming[key], state.bytes = nil, state.bytes - item.bytes
	end
end
local function Tombstone(state, key, item, accepted)
	local previous = state.completed[key]
	if previous then
		return
	end
	local row = {
		frame = item.frame,
		expires = item.expires,
		accepted = accepted,
		reliable = item.reliable,
		request = item.request,
	}
	state.completed[key] = row
	state.completedOrder[#state.completedOrder + 1] = { key = key, row = row }
	if #state.completedOrder > MAX_TOMBSTONES then
		local old = table.remove(state.completedOrder, 1)
		if state.completed[old.key] == old.row then
			state.completed[old.key] = nil
		end
	end
end
local function Expected(a, frame, sender)
	local spec = a:GetCommOperation(frame.operation)
	if not spec or spec.semantic == "record" or spec.semantic == "transfer" then
		return false
	end
	if spec.semantic == "response" then
		if not frame.requestId or not a.IsCommResponseExpected then
			return false
		end
		local ok, allowed, expires = pcall(a.IsCommResponseExpected, a, frame, sender)
		if not ok or allowed ~= true then
			return false
		end
		return true, expires
	end
	return true
end
local function SendControl(a, state, operation, frame, sender, parts, status, owner)
	if rawget(a, "commTransferState") ~= state or not a.isEnabled or a.isLoggingOut or not a.Emit then
		return false
	end
	local record = { session = frame.session, messageId = frame.messageId, parts = parts, status = status }
	local expires = owner and owner.expires or (Now(a) + 30)
	return a:Emit(operation, record, { { distribution = "WHISPER", target = sender } }, {
		priority = "control",
		-- A throttled response in the same priority class must not hold its
		-- status/repair traffic behind that response's destination queue head.
		flow = "transfer-control:" .. sender,
		owner = owner or state,
		expires = expires,
		key = operation .. ":" .. sender .. ":" .. frame.session .. ":" .. frame.messageId .. ":" .. (status or ""),
		isCurrent = function()
			return rawget(a, "commTransferState") == state
				and a.isEnabled
				and not a.isLoggingOut
				and Now(a) < expires
				and (
					not owner
					or (
						not owner.retired
						and (not owner.frames or Current(a, state, owner))
						and (not owner.sender or Expected(a, owner.frame, owner.sender))
					)
				)
		end,
	})
end
local function MissingChunks(item)
	local ranges, first = {}, nil
	for index = 1, item.frame.total + 1 do
		if index <= item.frame.total and not item.parts[index] then
			first = first or index
		elseif first then
			ranges[#ranges + 1] = first == index - 1 and tostring(first) or (first .. "-" .. (index - 1))
			first = nil
		end
	end
	local chunks, current = {}, ""
	for _, range in ipairs(ranges) do
		local nextValue = current == "" and range or current .. "," .. range
		if #nextValue > 48 then
			chunks[#chunks + 1], current = current, range
		else
			current = nextValue
		end
	end
	if current ~= "" then
		chunks[#chunks + 1] = current
	end
	return chunks
end
local function RequestMissing(a, state, item)
	if not item.reliable or not item.endSeen or item.repairs >= MAX_REPAIR then
		return false
	end
	local chunks = MissingChunks(item)
	if #chunks == 0 then
		return false
	end
	item.repairs = item.repairs + 1
	for index, chunk in ipairs(chunks) do
		SendControl(
			a,
			state,
			"FXMISS",
			item.frame,
			item.sender,
			chunk,
			item.repairs .. ":" .. index .. ":" .. #chunks,
			item
		)
	end
	item.lastActivity = Now(a)
	return true
end
local function FinishIncoming(a, state, key, item)
	local valid = Expected(a, item.frame, item.sender)
	if not valid then
		RetireIn(state, key)
		return false
	end
	local payload = table.concat(item.parts)
	local record = a:DecodeCommRecord(item.frame.operation, payload)
	if not record or (item.frame.requestId and record.requestId and record.requestId ~= item.frame.requestId) then
		RetireIn(state, key)
		Tombstone(state, key, item, false)
		Count(state, "invalid")
		return false
	end
	-- Remove before domain callbacks, which may cancel/reset the whole service.
	item.request = a:GetCommOperation(item.frame.operation).semantic == "request"
		and not a:IsCommResponseRecord(item.frame.operation, record)
	RetireIn(state, key)
	local ok, result = pcall(a.DispatchCommRecord, a, item.frame, record, item.sender, item.routeContext)
	local accepted = ok and result == true
	if rawget(a, "commTransferState") ~= state then
		return accepted
	end
	-- A structurally valid request rejected by a busy domain can be retried
	-- under its original identity. Malformed/conflicting payloads stay fenced.
	if (accepted or not item.request) and not a:GetCommOperation(item.frame.operation).authenticatedEvent then
		Tombstone(state, key, item, accepted)
	end
	if accepted then
		Count(state, "received")
		if item.frame.total > 1 then
			Timing(state, "assembly", Now(a) - item.createdAt)
		end
		if item.reliable then
			SendControl(a, state, "FXACK", item.frame, item.sender)
		end
	elseif not ok then
		a:RecordDiagnosticError("transfer dispatch", result)
	end
	return accepted
end

function QT:QueueCommTransfer(frames, context, route, options)
	options = options or {}
	if
		not self.isEnabled
		or self.isLoggingOut
		or type(frames) ~= "table"
		or #frames < 1
		or #frames > MAX_PARTS
		or type(route) ~= "table"
	then
		return false, "invalid"
	end
	local first, bytes = nil, 0
	local copied = {}
	for index, wire in ipairs(frames) do
		local frame, body = self:DecodeCommFrame(wire)
		if not frame or frame.part ~= index or frame.total ~= #frames or (first and not SameFrame(first, frame)) then
			return false, "invalid"
		end
		first, bytes, copied[index] = first or CopyFrame(frame), bytes + #body, wire
	end
	local spec = self:GetCommOperation(first.operation)
	if not spec or spec.semantic == "transfer" or bytes > math.min(MAX_OBJECT, spec.maxBytes) then
		return false, "invalid"
	end
	local state, now = State(self), Now(self)
	local startedAt = options.startedAt or (type(context) == "table" and context.startedAt) or now
	local expires = math.min(options.expires or now + (spec.lifetime or 30), startedAt + 600)
	if expires <= now then
		return false, "expired"
	end
	local reliable = options.reliable == true
		or (options.reliable ~= false and spec.semantic == "response" and #frames > 1)
	if reliable and (route.distribution ~= "WHISPER" or not route.target or not first.requestId) then
		return false, "invalid"
	end
	local replaced
	for _, job in ipairs(state.outgoing) do
		if
			options.key
			and job.key == options.key
			and job.route.distribution == route.distribution
			and job.route.target == route.target
			and job.route.channelName == route.channelName
		then
			replaced = job
			break
		end
	end
	if
		#state.outgoing - (replaced and 1 or 0) >= MAX_OUT
		or state.bytes - (replaced and replaced.bytes or 0) + bytes > MAX_BYTES
	then
		Count(state, "capacity")
		return false, "capacity"
	end
	if replaced then
		RetireOut(self, state, replaced, "superseded", true)
	end
	state.nextJob = state.nextJob + 1
	local job = {
		id = state.nextJob,
		frames = copied,
		frame = first,
		operation = first.operation,
		requestId = first.requestId,
		bytes = bytes,
		context = type(context) == "table" and context.operation or context,
		route = {
			distribution = route.distribution,
			target = route.target,
			channelName = route.channelName,
			requiresChannelJoin = route.requiresChannelJoin,
		},
		owner = options.owner,
		key = options.key,
		createdAt = now,
		expires = expires,
		isCurrent = options.isCurrent,
		onComplete = options.onComplete,
		priority = options.priority or spec.priority,
		flow = options.flow,
		publishesLocation = options.publishesLocation,
		nextPart = 1,
		reliable = reliable,
		repairRound = 0,
		probes = 0,
	}
	state.outgoing[#state.outgoing + 1], state.bytes = job, state.bytes + bytes
	Count(state, "queued")
	-- Publish the replacement before invoking external completion code. A hook
	-- may reset the runtime or enqueue a still newer value under the same key.
	if replaced then
		Complete(self, replaced, false, "superseded")
	end
	return true, "queued", job
end

function QT:ReceiveCommFragment(frame, body, sender, routeContext)
	if
		not self.isEnabled
		or self.isLoggingOut
		or type(frame) ~= "table"
		or type(body) ~= "string"
		or #body > 255
		or type(sender) ~= "string"
		or #sender > 120
		or type(frame.session) ~= "string"
		or #frame.session > 64
		or type(frame.messageId) ~= "string"
		or #frame.messageId > 64
		or type(frame.total) ~= "number"
		or frame.total < 1
		or frame.total > MAX_PARTS
		or frame.total % 1 ~= 0
		or type(frame.part) ~= "number"
		or frame.part < 1
		or frame.part > frame.total
		or frame.part % 1 ~= 0
	then
		return false
	end
	local spec = self:GetCommOperation(frame.operation)
	if not spec or spec.semantic == "record" then
		return false
	end
	if spec.semantic == "transfer" then
		if frame.total ~= 1 then
			return false
		end
		local record = self:DecodeCommRecord(frame.operation, body)
		if not record then
			return false
		end
		return self:DispatchCommRecord(frame, record, sender, routeContext) == true
	end
	local state, now = State(self), Now(self)
	local key = Key(sender, frame)
	local done = state.completed[key]
	if done and now < done.expires then
		if done.accepted and done.request and SameFrame(done.frame, frame) and self.ReplayCommResponses then
			self:ReplayCommResponses(sender, frame.requestId)
		end
		return false
	end
	local valid, requestExpiry = Expected(self, frame, sender)
	if not valid then
		return false
	end
	local item = state.incoming[key]
	if item and (not SameFrame(item.frame, frame) or (item.parts[frame.part] and item.parts[frame.part] ~= body)) then
		RetireIn(state, key)
		Tombstone(state, key, item, false)
		Count(state, "invalid")
		return false
	end
	if item and item.parts[frame.part] then
		return false
	end
	if not item then
		local count, own, background = 0, 0, 0
		for _, candidate in pairs(state.incoming) do
			count = count + 1
			if candidate.routeContext and candidate.routeContext.backgroundAnnouncement then
				background = background + 1
			end
			if candidate.sender == sender then
				own = own + 1
			end
		end
		local reserved = routeContext and (routeContext.targeted == true or routeContext.group == true)
		if
			count >= (reserved and MAX_IN or MAX_IN - RESERVED)
			or (spec.semantic ~= "response" and own >= MAX_UNSOLICITED_PER_SENDER)
			or (routeContext and routeContext.backgroundAnnouncement and background >= 8)
		then
			Count(state, "capacity")
			return false
		end
		local lifetime = spec.semantic == "response" and 600 or math.min(30, spec.lifetime or 30)
		item = {
			sender = sender,
			frame = CopyFrame(frame),
			parts = {},
			bytes = 0,
			count = 0,
			createdAt = now,
			expires = math.min(now + lifetime, requestExpiry or now + lifetime),
			lastActivity = now,
			reliable = spec.semantic == "response" and frame.total > 1,
			repairs = 0,
			probes = 0,
			routeContext = routeContext,
		}
		if item.expires <= now then
			return false
		end
		state.incoming[key] = item
	end
	local limit = math.min(
		MAX_OBJECT,
		spec.maxBytes,
		spec.semantic == "state" and 8192 or spec.semantic == "event" and 4096 or MAX_OBJECT
	)
	if item.bytes + #body > limit or state.bytes + #body > MAX_BYTES then
		RetireIn(state, key)
		Tombstone(state, key, item, false)
		Count(state, "capacity")
		return false
	end
	item.parts[frame.part], item.bytes, item.count = body, item.bytes + #body, item.count + 1
	item.lastActivity, state.bytes = now, state.bytes + #body
	if item.count == frame.total then
		return FinishIncoming(self, state, key, item)
	end
	return true
end

local function FindOut(state, record, sender)
	for _, job in ipairs(state.outgoing) do
		if
			job.reliable
			and job.route.target == sender
			and job.frame.session == record.session
			and job.frame.messageId == record.messageId
		then
			return job
		end
	end
end
local function ParseRanges(parts, total)
	if type(parts) ~= "string" or #parts > 128 or parts == "" then
		return nil
	end
	local result = {}
	for token in (parts .. ","):gmatch("(.-),") do
		local first, last = token:match("^(%d+)%-(%d+)$")
		if not first then
			first = token:match("^(%d+)$")
			last = first
		end
		first, last = tonumber(first), tonumber(last)
		if not first or not last or first < 1 or last < first or last > total then
			return nil
		end
		for index = first, last do
			result[index] = true
		end
	end
	return result
end

function QT:HandleCommTransferControl(operation, record, sender)
	local state = rawget(self, "commTransferState")
	if
		not state
		or not self.isEnabled
		or self.isLoggingOut
		or type(record) ~= "table"
		or type(sender) ~= "string"
		or type(record.session) ~= "string"
		or type(record.messageId) ~= "string"
	then
		return false
	end
	local now, key = Now(self), Key(sender, record)
	local incoming, done, job = state.incoming[key], state.completed[key], FindOut(state, record, sender)
	if operation == "FXACK" then
		if not job or not job.initialComplete or not Current(self, state, job) then
			return false
		end
		RetireOut(self, state, job, "acknowledged")
		Count(state, "acknowledged")
		return true
	elseif operation == "FXEND" then
		if done and done.accepted and done.reliable and now < done.expires then
			SendControl(self, state, "FXACK", done.frame, sender)
			return true
		end
		if not incoming or not incoming.reliable or not Expected(self, incoming.frame, sender) then
			return false
		end
		local round = tonumber(record.status or "0")
		if
			not round
			or round < 0
			or round > MAX_REPAIR
			or round ~= math.floor(round)
			or (incoming.lastEndRound and round <= incoming.lastEndRound)
		then
			return false
		end
		incoming.endSeen, incoming.lastEndRound = true, round
		self:RecordCommunicationResponseProgress(incoming.frame, sender)
		return RequestMissing(self, state, incoming)
	elseif operation == "FXSTAT" then
		if record.status == "request" then
			if not job or not Current(self, state, job) then
				return false
			end
			SendControl(
				self,
				state,
				"FXSTAT",
				job.frame,
				sender,
				nil,
				job.initialComplete and "complete" or "sending",
				job
			)
			return true
		end
		if not incoming or not incoming.reliable or not Expected(self, incoming.frame, sender) then
			return false
		end
		if not incoming.statusProbePending then return false end
		if record.status == "complete" then
			incoming.statusProbePending = nil
			incoming.endSeen = true
			self:RecordCommunicationResponseProgress(incoming.frame, sender)
			return RequestMissing(self, state, incoming)
		end
		if record.status == "sending" then
			incoming.statusProbePending = nil
			self:RecordCommunicationResponseProgress(incoming.frame, sender)
			return true
		end
		return false
	elseif operation == "FXMISS" then
		if not job or not job.initialComplete or not Current(self, state, job) then
			return false
		end
		local round, index, total = (record.status or ""):match("^(%d+):(%d+):(%d+)$")
		round, index, total = tonumber(round), tonumber(index), tonumber(total)
		if
			not round
			or round < 1
			or round > MAX_REPAIR
			or round <= job.repairRound
			or job.repairParts
			or not index
			or not total
			or index < 1
			or index > total
			or total > 128
		then
			return false
		end
		local parts = ParseRanges(record.parts, job.frame.total)
		if not parts then
			return false
		end
		local repair = job.repairRequest
		if repair and round < repair.round then
			return false
		end
		if repair and round > repair.round then
			repair = nil
		end
		if repair and repair.total ~= total then
			return false
		end
		if not repair then
			repair = { round = round, total = total, chunks = {}, parts = {}, count = 0 }
			job.repairRequest = repair
		end
		if repair.chunks[index] then
			return repair.chunks[index] == record.parts
		end
		repair.chunks[index], repair.count = record.parts, repair.count + 1
		for part in pairs(parts) do
			repair.parts[part] = true
		end
		if repair.count == total then
			job.repairParts, job.repairIndex, job.repairRound, job.repairRequest = {}, 1, round, nil
			for part = 1, job.frame.total do
				if repair.parts[part] then
					job.repairParts[#job.repairParts + 1] = part
				end
			end
		end
		return true
	end
	return false
end

function QT:UpdateCommTransfers()
	local state, now = rawget(self, "commTransferState"), Now(self)
	if not state then
		return
	end
	local jobs = {}
	for _, job in ipairs(state.outgoing) do
		jobs[#jobs + 1] = job
	end
	for offset = 1, #jobs do
		local job = jobs[((state.cursor or 0) + offset - 1) % #jobs + 1]
		if not Current(self, state, job) then
			RetireOut(self, state, job, now >= job.expires and "expired" or "cancelled")
		elseif not job.inFlight then
			local repair = job.repairParts
			local part = repair and repair[job.repairIndex] or (not job.initialComplete and job.nextPart)
			if part then
				job.inFlight = true
				local accepted, reason = self:QueueTransportWire(job.frames[part], job.context, job.route, {
					priority = job.priority,
					flow = job.flow,
					owner = job,
					expires = job.expires,
					publishesLocation = job.publishesLocation,
					isCurrent = function()
						return Current(self, state, job)
					end,
					onComplete = function(sent, result)
						if job.retired or rawget(self, "commTransferState") ~= state then
							return
						end
						job.inFlight = nil
						if not sent and result ~= "ambiguous" then
							RetireOut(self, state, job, result)
							return
						end
						-- The server may have submitted this fragment. Do not replay it,
						-- but still send the remaining fragments so that a delivered
						-- ambiguous packet does not guarantee an incomplete object.
						if result == "ambiguous" then job.ambiguous = true end
						job.lastProgressAt = Now(self)
						if not job.firstProgressAt then
							job.firstProgressAt = job.lastProgressAt
							Timing(state, "outboundFirstProgress", job.firstProgressAt - job.createdAt)
						end
						if repair then
							job.repairIndex = job.repairIndex + 1
							if job.repairIndex > #repair then
								job.repairParts = nil
								SendControl(
									self,
									state,
									"FXEND",
									job.frame,
									job.route.target,
									nil,
									tostring(job.repairRound),
									job
								)
							end
						else
							job.nextPart = job.nextPart + 1
							if job.nextPart > #job.frames then
								job.initialComplete, job.completedAt = true, Now(self)
								Timing(state, "outboundCompletion", job.completedAt - job.createdAt)
								Complete(self, job, not job.ambiguous, job.ambiguous and "ambiguous" or "accepted")
								if job.reliable then
									SendControl(self, state, "FXEND", job.frame, job.route.target, nil, "0", job)
								else
									RetireOut(self, state, job, "accepted")
								end
							end
						end
					end,
				})
				if not accepted then
					job.inFlight = nil
					if reason ~= "capacity" then
						RetireOut(self, state, job, reason)
					end
				end
			elseif
				job.initialComplete
				and job.reliable
				and now - (job.lastProbe or job.completedAt) >= PROBE_INTERVAL
				and job.probes < MAX_PROBES
			then
				job.probes, job.lastProbe = job.probes + 1, now
				SendControl(self, state, "FXEND", job.frame, job.route.target, nil, tostring(job.repairRound), job)
			end
		end
	end
	state.cursor = #jobs > 0 and ((state.cursor or 0) + 1) % #jobs or 0
	for key, item in pairs(state.incoming) do
		if
			not self.isEnabled
			or self.isLoggingOut
			or now < item.createdAt
			or now >= item.expires
			or not Expected(self, item.frame, item.sender)
		then
			RetireIn(state, key)
		elseif item.reliable and now - item.lastActivity >= PROBE_INTERVAL and item.probes < MAX_PROBES then
			item.probes, item.lastActivity = item.probes + 1, now
			item.statusProbePending = SendControl(self, state, "FXSTAT", item.frame, item.sender, nil, "request", item) == true
		end
	end
	for index = #state.completedOrder, 1, -1 do
		local entry = state.completedOrder[index]
		if now >= entry.row.expires then
			state.completed[entry.key] = nil
			table.remove(state.completedOrder, index)
		end
	end
end

function QT:CancelCommTransfers(predicate, reason)
	local state = rawget(self, "commTransferState")
	if not state then
		return
	end
	local selected = {}
	for _, job in ipairs(state.outgoing) do
		if not predicate or predicate(job) then
			selected[#selected + 1] = job
		end
	end
	for _, job in ipairs(selected) do
		RetireOut(self, state, job, reason or "cancelled")
	end
end
function QT:CancelCommTransferOwner(owner, reason)
	self:CancelCommTransfers(function(job)
		return job.owner == owner
	end, reason)
end
function QT:CancelIncomingCommResponses(requestId, reason)
	local state = rawget(self, "commTransferState")
	if not state then return end
	for key, item in pairs(state.incoming) do
		if item.frame.requestId == requestId and self:GetCommOperation(item.frame.operation).semantic == "response" then
			RetireIn(state, key)
			self:CancelTransportOwner(item, reason or "cancelled")
		end
	end
end
-- Duplicate request envelopes may have lost their original response. Reuse the
-- already bounded immutable object; never rebuild or repeat a domain action.
function QT:ReplayCommResponse(sender, requestId)
	local state = rawget(self, "commTransferState")
	if not state then
		return false
	end
	local found = false
	for _, job in ipairs(state.outgoing) do
		if job.reliable and job.route.target == sender and job.requestId == requestId and Current(self, state, job) then
			found = true
			if job.initialComplete and not job.repairParts and (job.replays or 0) < 2 then
				job.replays = (job.replays or 0) + 1
				job.repairParts, job.repairIndex = {}, 1
				for index = 1, #job.frames do
					job.repairParts[index] = index
				end
			end
		end
	end
	return found
end
function QT:ReserveCommResponseBytes(bytes)
	local state = State(self)
	if bytes < 0 or state.bytes + bytes > MAX_BYTES then
		return nil
	end
	state.bytes = state.bytes + bytes
	return { state = state, bytes = bytes }
end
function QT:ReleaseCommResponseBytes(reservation)
	if reservation and not reservation.released then
		reservation.released = true
		reservation.state.bytes = reservation.state.bytes - reservation.bytes
	end
end
function QT:ResetCommTransfers(reason)
	local state = rawget(self, "commTransferState")
	if not state then
		return
	end
	self.commTransferState = nil
	local jobs = state.outgoing
	state.outgoing = {}
	for _, job in ipairs(jobs) do
		RetireOut(self, state, job, reason or "cancelled")
	end
	for _, item in pairs(state.incoming) do
		item.retired = true
		self:CancelTransportOwner(item, reason or "cancelled")
	end
	self:CancelTransportOwner(state, reason or "cancelled")
end
function QT:GetCommTransferMetrics()
	local state = rawget(self, "commTransferState")
	local result = {
		outgoing = 0,
		incoming = 0,
		bytes = 0,
		completed = 0,
		oldestIncomingAge = 0,
		oldestIncomingIdle = 0,
		oldestOutgoingAge = 0,
		oldestOutgoingIdle = 0,
	}
	if state then
		for key, value in pairs(state.metrics) do
			result[key] = value
		end
		result.outgoing, result.bytes, result.completed = #state.outgoing, state.bytes, #state.completedOrder
		local now = Now(self)
		for _, item in pairs(state.incoming) do
			result.incoming = result.incoming + 1
			result.oldestIncomingAge = math.max(result.oldestIncomingAge, now - item.createdAt)
			result.oldestIncomingIdle = math.max(result.oldestIncomingIdle, now - item.lastActivity)
		end
		for _, job in ipairs(state.outgoing) do
			result.oldestOutgoingAge = math.max(result.oldestOutgoingAge, now - job.createdAt)
			result.oldestOutgoingIdle = math.max(result.oldestOutgoingIdle, now - (job.lastProgressAt or job.createdAt))
		end
	end
	return result
end
