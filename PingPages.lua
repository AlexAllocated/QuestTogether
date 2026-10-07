-- Paged pongs are negotiated; legacy receivers still get their original packet.
-- The sender queue owns pacing/retries, including clients without geographic comms.
local QT = _G.QuestTogether
local MAX_BYTES, MAX_PAGES, MAX_PARTIALS = 16384, 128, 64
local INTERVAL, LIFETIME = 0.2, 120

function QT:BuildPongPages(id, payload)
	if type(id) ~= "string" or #id == 0 or #id > 128 or type(payload) ~= "string"
		or #payload == 0 or #payload > MAX_BYTES then return nil end
	local prefix = "PONP|1," .. self:EscapePayload(id) .. ","
	-- Reserve room for both page numbers before slicing. Fragments are bytes;
	-- UTF-8 and escaped fields are decoded only after complete reassembly.
	local width = 255 - #prefix - 8
	if width < 32 then return nil end
	local total = math.ceil(#payload / width)
	if total > MAX_PAGES then return nil end
	local pages = {}
	for index = 1, total do
		pages[index] = prefix .. index .. "," .. total .. "," .. payload:sub((index - 1) * width + 1, index * width)
	end
	return pages
end

function QT:SendPagedPong(id, payload, routes, developer)
	-- Negotiated pages are private replies, never a broadcast fallback.
	local route = routes and routes[1]
	if not route or #routes ~= 1 or route.distribution ~= "WHISPER" or not route.target then return false end
	local pages = self:BuildPongPages(id, payload)
	if not pages then return false end
	local queue = rawget(self, "pingPageQueue")
	if not queue then queue = { jobs = {} }; self.pingPageQueue = queue end
	if #queue.jobs >= 8 then return false end
	for _, job in ipairs(queue.jobs) do
		if job.id == id and job.route.target == route.target then return false end
	end
	local now = self.API.GetTime()
	queue.jobs[#queue.jobs + 1] = { id = id, pages = pages, route = route, index = 1,
		createdAt = now, expiresAt = now + LIFETIME, failures = 0,
		developer = developer, sharedLocation = self:CanPublishPlayerLocation() }
	self:DrainPongPages()
	return true
end

function QT:DrainPongPages()
	local queue = rawget(self, "pingPageQueue")
	if not queue or queue.scheduled or not self.isEnabled or self.isLoggingOut then return end
	local job = queue.jobs[1]
	if not job then return end
	local now = self.API.GetTime()
	local current = now >= job.createdAt and now < job.expiresAt
		and not self:IsIgnoredPlayerName(job.route.target)
		and (not job.route.requiresGroup or self:IsGroupedSender(job.route.target))
		and ((job.developer and self:GetOption("shareDeveloperDiagnostics") == true)
			or (not job.developer and (not job.sharedLocation or self:CanPublishPlayerLocation())))
	local done = not current
	if current then
		local sent, reason = self:SendWireMessageToAnnouncementRoutes(job.pages[job.index], "paged pong", { job.route })
		if sent then
			job.index, job.failures = job.index + 1, 0
			done = job.index > #job.pages
		elseif reason ~= "paced" then
			job.failures = job.failures + 1
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

function QT:HandlePongPage(payload, sender)
	if type(payload) ~= "string" or #payload > 250 then return false end
	local rawID, index, total, fragment = payload:match("^1,([^,]+),(%d+),(%d+),(.+)$")
	if not rawID or #rawID > 384 then return false end
	local id = self:UnescapePayload(rawID)
	index, total = tonumber(index), tonumber(total)
	if #id == 0 or #id > 128 or index < 1 or total < 1 or index > total or total > MAX_PAGES then return false end
	local pending = self.pendingPingRequests and self.pendingPingRequests[id]
	local name = self:NormalizeMemberName(sender)
	local now = self.API.GetTime()
	if type(pending) ~= "table" or not name or not pending.expiresAt
		or now < pending.startedAt or now >= pending.expiresAt or pending.responders[name]
		or (pending.targetName and pending.targetName ~= name) then return false end
	pending.pages = pending.pages or {}
	local part = pending.pages[name]
	if not part then
		local count = 0
		for _ in pairs(pending.pages) do count = count + 1 end
		if count >= MAX_PARTIALS then return false end
		part = { total = total, chunks = {}, count = 0, bytes = 0, startedAt = now }
		pending.pages[name] = part
	end
	if part.failed then return false end
	if now < part.startedAt or now - part.startedAt >= LIFETIME or part.total ~= total
		or (part.chunks[index] and part.chunks[index] ~= fragment) then
		part.failed, part.chunks = true, nil
		return false
	end
	if part.chunks[index] then return false end
	part.bytes = part.bytes + #fragment
	if part.bytes > MAX_BYTES then part.failed, part.chunks = true, nil; return false end
	part.chunks[index], part.count = fragment, part.count + 1
	if part.count ~= total then return true end
	local response = self:DecodePingResponsePayload(table.concat(part.chunks))
	if not response or response.requestId ~= id then
		part.failed, part.chunks = true, nil
		return false
	end
	response.senderName = name -- The transport owns identity, not the payload.
	pending.pages[name] = nil
	if not self:HandlePingResponse(response) then return false end
	self:RecordQTPlayerPresence(name, true)
	self:ObserveAddonVersion(response.addonVersion)
	self:RememberPlayerAddonVersion(name, response.addonVersion)
	self:RememberDirectCommPeer(name, true)
	return true
end
