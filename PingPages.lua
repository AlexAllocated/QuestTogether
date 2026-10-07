-- Paged pongs are negotiated; legacy receivers still get their original packet.
-- The sender queue owns pacing/retries, including clients without geographic comms.
local QT = _G.QuestTogether
local MAX_PARTIALS = 64
local INTERVAL, LIFETIME = 0.2, 120
-- Large reports are explicitly negotiated for one targeted diagnostic request.
-- A 32 KiB report can triple when escaped, with room left for player metadata.
local function Limits(version)
	if version == 2 then return 102400, 1024, 540 end
	return 16384, 128, LIFETIME
end

function QT:BuildPongPages(id, payload, version)
	version = version or 1
	if version ~= 1 and version ~= 2 then return nil end
	local maxBytes, maxPages = Limits(version)
	if type(id) ~= "string" or #id == 0 or #id > 128 or type(payload) ~= "string"
		or #payload == 0 or #payload > maxBytes then return nil end
	local prefix = "PONP|" .. version .. "," .. self:EscapePayload(id) .. ","
	-- Reserve room for both page numbers before slicing. Fragments are bytes;
	-- UTF-8 and escaped fields are decoded only after complete reassembly.
	local width = 255 - #prefix - (version == 2 and 10 or 8)
	if width < 32 then return nil end
	local total = math.ceil(#payload / width)
	if total > maxPages then return nil end
	local pages = {}
	for index = 1, total do
		pages[index] = prefix .. index .. "," .. total .. "," .. payload:sub((index - 1) * width + 1, index * width)
	end
	return pages
end

function QT:SendPagedPong(id, payload, routes, developer, version)
	-- Negotiated pages are private replies, never a broadcast fallback.
	local route = routes and routes[1]
	if not route or #routes ~= 1 or route.distribution ~= "WHISPER" or not route.target then return false end
	version = version or 1
	if version == 2 and not developer then return false end
	local pages = self:BuildPongPages(id, payload, version)
	if not pages then return false end
	local queue = rawget(self, "pingPageQueue")
	if not queue then queue = { jobs = {} }; self.pingPageQueue = queue end
	if #queue.jobs >= 8 then return false end
	for _, job in ipairs(queue.jobs) do
		if job.id == id and job.route.target == route.target then return false end
	end
	local now = self.API.GetTime()
	local _, _, lifetime = Limits(version)
	queue.jobs[#queue.jobs + 1] = { id = id, pages = pages, route = route, index = 1,
		createdAt = now, expiresAt = now + lifetime, failures = 0,
		developer = developer, sharedLocation = self:CanPublishPlayerLocation() }
	self:DrainPongPages()
	return true
end

function QT:DrainPongPages()
	local queue = rawget(self, "pingPageQueue")
	if not queue or queue.scheduled or not self.isEnabled or self.isLoggingOut then return end
	local job = queue.jobs[1]
	if not job or job.inFlight then return end
	local now = self.API.GetTime()
	local function Current()
		local tick = self.API.GetTime()
		return rawget(self, "pingPageQueue") == queue and queue.jobs[1] == job and not self.isLoggingOut
			and tick >= job.createdAt and tick < job.expiresAt
			and not self:IsIgnoredPlayerName(job.route.target)
			and (not job.route.requiresGroup or self:IsGroupedSender(job.route.target))
			and ((job.developer and self:GetOption("shareDeveloperDiagnostics") == true)
				or (not job.developer and (not job.sharedLocation or self:CanPublishPlayerLocation())))
	end
	local current = Current()
	local done = not current
	if current then
		local sent, reason
		if job.delivery then
			sent, reason = job.delivery.sent, job.delivery.reason
			job.delivery = nil
		else
			local completion
			if rawget(self, "geographicCommsState") then
				completion = { owner=job, expires=job.expiresAt, isCurrent=Current, onComplete=function(ok, failure)
					if rawget(self, "pingPageQueue") ~= queue or queue.jobs[1] ~= job then return end
					job.inFlight, job.delivery = nil, { sent=ok, reason=failure }
					self:DrainPongPages()
				end }
			end
			sent, reason = self:SendWireMessageToAnnouncementRoutes(job.pages[job.index], "paged pong", { job.route }, false, completion)
			if reason == "queued" then job.inFlight=true; return end
		end
		if sent then
			job.index, job.failures = job.index + 1, 0
			done = job.index > #job.pages
		elseif reason ~= "paced" then
			job.failures = reason == "cancelled" and 5 or job.failures + 1
			done = job.failures >= 5
		end
	end
	if done then table.remove(queue.jobs, 1) end
	queue.scheduled = true
	self.API.Delay(INTERVAL, function()
		if rawget(self, "pingPageQueue") ~= queue then return end
		queue.scheduled = false
		self:DrainPongPages()
	end)
end

function QT:CancelDeveloperDiagnosticReplies()
	self.diagnosticReplyGeneration = (rawget(self, "diagnosticReplyGeneration") or 0) + 1
	local queue = rawget(self, "pingPageQueue")
	local cancelled = {}
	for index = #(queue and queue.jobs or {}), 1, -1 do
		local job = queue.jobs[index]
		if job.developer then cancelled[job]=true; table.remove(queue.jobs,index) end
	end
	local geo = rawget(self, "geographicCommsState")
	for index = #(geo and geo.queue or {}), 1, -1 do
		if cancelled[geo.queue[index].owner] then table.remove(geo.queue,index) end
	end
	-- A cancelled in-flight job has no timer; restart remaining ordinary replies.
	if queue and not queue.scheduled and #queue.jobs > 0 then self:DrainPongPages() end
end

local function RetirePartial(pending, name)
	pending.pages[name] = nil
	pending.failedPages = pending.failedPages or {}
	-- Tombstones never consume active-assembly slots; their fixed ring is
	-- bounded independently and dies with this ping request.
	pending.failedPageOrder = pending.failedPageOrder or {}
	if not pending.failedPages[name] then
		pending.failedPageOrder[#pending.failedPageOrder+1] = name
		pending.failedPages[name] = true
		if #pending.failedPageOrder > MAX_PARTIALS then
			pending.failedPages[table.remove(pending.failedPageOrder,1)] = nil
		end
	end
end

function QT:HandlePongPage(payload, sender)
	if type(payload) ~= "string" or #payload > 250 then return false end
	local version, rawID, index, total, fragment = payload:match("^([12]),([^,]+),(%d+),(%d+),(.+)$")
	if not rawID or #rawID > 384 then return false end
	version = tonumber(version)
	local maxBytes, maxPages, lifetime = Limits(version)
	local id = self:UnescapePayload(rawID)
	index, total = tonumber(index), tonumber(total)
	if #id == 0 or #id > 128 or index < 1 or total < 1 or index > total or total > maxPages then return false end
	local pending = self.pendingPingRequests and self.pendingPingRequests[id]
	local name = self:NormalizeMemberName(sender)
	local now = self.API.GetTime()
	if type(pending) ~= "table" or not name or not pending.expiresAt
		or now < pending.startedAt or now >= pending.expiresAt or pending.responders[name]
		or (pending.targetName and pending.targetName ~= name) then return false end
	if version == 2 and not (pending.supportsLargePong and pending.developerRequest
		and pending.debugRequest and pending.targetName == name) then return false end
	pending.pages = pending.pages or {}
	for peer, active in pairs(pending.pages) do
		if active.failed or now < active.startedAt or now-active.startedAt >= (active.lifetime or LIFETIME) then
			RetirePartial(pending, peer)
		end
	end
	if pending.failedPages and pending.failedPages[name] then return false end
	local part = pending.pages[name]
	if not part then
		local count = 0
		for _ in pairs(pending.pages) do count = count + 1 end
		if count >= MAX_PARTIALS then return false end
		part = { total = total, chunks = {}, count = 0, bytes = 0, startedAt = now,
			version = version, lifetime = lifetime }
		pending.pages[name] = part
	end
	if part.failed then return false end
	if now < part.startedAt or now - part.startedAt >= part.lifetime or part.total ~= total or part.version ~= version
		or (part.chunks[index] and part.chunks[index] ~= fragment) then
		RetirePartial(pending, name)
		return false
	end
	if part.chunks[index] then return false end
	part.bytes = part.bytes + #fragment
	if part.bytes > maxBytes then RetirePartial(pending, name); return false end
	part.chunks[index], part.count = fragment, part.count + 1
	if version == 2 and not pending.largePongStarted then
		-- Only a valid, explicitly negotiated targeted stream earns a longer
		-- deadline. A silent peer or legacy reply retains the five-minute limit.
		pending.largePongStarted = true
		pending.expiresAt = pending.startedAt + 600
	end
	if part.count ~= total then return true end
	local response = self:DecodePingResponsePayload(table.concat(part.chunks))
	if not response or response.requestId ~= id then
		RetirePartial(pending, name)
		return false
	end
	response.senderName = name -- The transport owns identity, not the payload.
	pending.pages[name] = nil
	if not self:HandlePingResponse(response) then return false end
	self:ObserveAddonVersion(response.addonVersion)
	self:RememberPlayerAddonVersion(name, response.addonVersion)
	self:RememberDirectCommPeer(name, true)
	return true
end
