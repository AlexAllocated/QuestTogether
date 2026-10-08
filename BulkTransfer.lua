-- Shared delivery pump for bounded response queues. Features retain their wire
-- formats, snapshot assembly, admission limits and authorization predicates.
local QT = _G.QuestTogether
function QT:PumpBulkTransfer(queue, spec)
	if rawget(self, spec.field) ~= queue or queue.scheduled or not self.isEnabled or self.isLoggingOut then
		return
	end
	local job = queue.jobs[1]
	if not job or job.inFlight then
		return
	end
	local function Current()
		local now = self.API.GetTime()
		return rawget(self, spec.field) == queue
			and queue.jobs[1] == job
			and self.isEnabled
			and not self.isLoggingOut
			and (not job.createdAt or now >= job.createdAt)
			and now < job.expiresAt
			and (not spec.isCurrent or spec.isCurrent(job))
	end
	local delay, finished, attempted = spec.interval or 0.2, not Current(), false
	local failure = finished and "cancelled" or nil
	if not finished then
		local ready, terminal
		if spec.prepare then
			ready, terminal = spec.prepare(job)
		else
			ready = true
		end
		if terminal then
			finished, failure = true, terminal
		elseif ready then
			attempted = true
			local sent, reason
			if job.delivery then
				sent, reason = job.delivery.sent, job.delivery.reason
				job.delivery = nil
			else
				local completion = {
					owner = job,
					expires = job.expiresAt,
					isCurrent = Current,
					priority = "bulk",
					onComplete = function(ok, detail)
						if rawget(self, spec.field) ~= queue or queue.jobs[1] ~= job then
							return
						end
						job.inFlight, job.delivery = nil, { sent = ok, reason = detail }
						self:PumpBulkTransfer(queue, spec)
					end,
				}
				sent, reason = spec.send(job, completion)
				if sent and reason == "queued" then
					job.inFlight = true
					return
				end
			end
			if sent then
				job.attempts = 0
				finished = spec.accept(job) == true
			else
				if reason == "cancelled" or reason == "superseded" then
					job.attempts = 5
				elseif reason ~= "paced" then
					job.attempts = (job.attempts or 0) + 1
				end
				finished = (job.attempts or 0) >= (spec.maxAttempts or 5)
				failure = reason
				delay = spec.retryInterval or delay
			end
		else
			delay = spec.retryInterval or delay
		end
	end
	if finished then
		table.remove(queue.jobs, 1)
		self:CancelTransportOwner(job)
		if spec.release then
			spec.release(job, failure)
		end
	end
	-- Retain the cooldown after a just-finished job as well as between packets.
	if #queue.jobs > 0 or attempted then
		queue.scheduled = true
		self.API.Delay(delay, function()
			if rawget(self, spec.field) ~= queue then
				return
			end
			queue.scheduled = false
			self:PumpBulkTransfer(queue, spec)
		end)
	end
end

function QT:CancelBulkTransfers(field, predicate)
	local queue = rawget(self, field)
	if not queue then
		return
	end
	local removed = {}
	for index = #queue.jobs, 1, -1 do
		local job = queue.jobs[index]
		if predicate(job) then
			table.remove(queue.jobs, index)
			removed[#removed + 1] = job
		end
	end
	for _, job in ipairs(removed) do
		self:CancelTransportOwner(job)
	end
	return queue
end
