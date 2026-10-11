local QT = _G.QuestTogether
local L = QT.Translate

function QT:BuildPingResponse(requestId)
	local response = self:GetPlayerPingMetadata()
	response.requestId = requestId
	response.sampledAt = self:GetAnnouncementServerTime()
	response.locationShared = self:CanPublishPlayerLocation()
	return response
end
function QT:SendPingRequest(target, debugRequest)
	if rawget(self, "isLocalDeveloper") ~= true then
		return false, L("Ping is unavailable.")
	end
	if not self.isEnabled then
		return false, L("QuestTogether is disabled.")
	end
	local data =
		self:PrepareDeveloperPingRequest({ requestId = self:BuildChannelRequestId("ping") }, target, debugRequest)
	if not data then
		return false, L("Ping is unavailable.")
	end
	local id, now = data.requestId, self.API.GetTime()
	self.pendingPingRequests = self.pendingPingRequests or {}
	local oldest, at, order, count = nil, nil, nil, 0
	for key, row in pairs(self.pendingPingRequests) do
		count = count + 1
		if not at or row.startedAt < at or (row.startedAt == at and (row.order or 0) < order) then
			oldest, at, order = key, row.startedAt, row.order or 0
		end
	end
	if count >= 8 then
		self.pendingPingRequests[oldest] = nil
		self:CancelCommRequest(oldest, "superseded")
	end
	local pending = {
		responders = {},
		remoteReplies = 0,
		responderCount = 0,
		startedAt = now,
		expiresAt = now + 300,
		targetName = data.targetName,
		developerRequest = true,
		debugRequest = data.debugRequest,
		order = self:NextCommunicationSequence(),
	}
	self.pendingPingRequests[id] = pending
	local function Current()
		return self.pendingPingRequests and self.pendingPingRequests[id] == pending
	end
	local function Expire()
		if not Current() then
			return
		end
		pending.reportExpired = true
		if pending.debugRequest and not pending.reportReceived then
			self:Print(L("Diagnostics unavailable."))
		end
	end
	local routes = data.targetName and { { distribution = "WHISPER", target = data.targetName } }
		or { { distribution = "CHANNEL", channelName = self.announcementChannelName, requiresChannelJoin = true } }
	local ok = self:Request("PING", data, routes, {
		owner = pending,
		isCurrent = Current,
		onExpire = Expire,
		acceptLatePongs = true,
		responseOperations = { PONG = true, DREPORT = data.debugRequest == true, ERROR = true },
	})
	if not ok then
		self.pendingPingRequests[id] = nil
		return false, L("Unable to send ping request over any QuestTogether comm route.")
	end
	if not target then
		self:HandlePingResponse(self:BuildPingResponse(id))
	end
	return true, id
end
function QT:HandlePingRequest(data)
	if not data.developerRequest then
		return false
	end
	if not data.developerVerified then
		return self:QueueDeveloperPingVerification(data, data.requesterName, function(verified)
			self:HandlePingRequest(verified)
		end)
	end
	local sender = self:NormalizeMemberName(data.requesterName)
	if not sender or self:IsIgnoredPlayerName(sender) then
		return false
	end
	local now = self.API.GetTime()
	local state = rawget(self, "pingReplyState")
	if not state then
		state = { jobs = {} }
		self.pingReplyState = state
	end
	local key = sender .. ":" .. data.requestId
	local count = 0
	for id, job in pairs(state.jobs) do
		if now < job.startedAt or now >= job.expiresAt then
			state.jobs[id] = nil
		else
			count = count + 1
		end
	end
	if state.jobs[key] then
		return true
	end
	if count >= 16 then
		return false
	end
	local job = {
		request = data,
		sender = sender,
		startedAt = now,
		expiresAt = now + 600,
		dueAt = now + self.API.Random(1, 20),
		diagnosticGeneration = rawget(self, "diagnosticReplyGeneration") or 0,
	}
	state.jobs[key] = job
	return true
end
local function Current(a, state, key, job)
	return a.isEnabled
		and not a.isLoggingOut
		and rawget(a, "pingReplyState") == state
		and not job.cancelled
		and a:GetOption("shareDeveloperDiagnostics") == true
		and not a:IsIgnoredPlayerName(job.sender)
		and (rawget(a, "diagnosticReplyGeneration") or 0) == job.diagnosticGeneration
end
function QT:ProgressPingReplies(now)
	local state = rawget(self, "pingReplyState")
	for key, job in pairs(state and state.jobs or {}) do
		if now < job.startedAt or now >= job.expiresAt or not Current(self, state, key, job) then
			job.cancelled = true
			state.jobs[key] = nil
			self:CancelTransportOwner(job, "cancelled")
			self:CancelCommTransferOwner(job, "cancelled")
		elseif now >= job.dueAt then
			local options = {
				owner = job,
				startedAt = job.startedAt,
				expires = job.expiresAt,
				isCurrent = function()
					return Current(self, state, key, job)
				end,
			}
			local routes = { { distribution = "WHISPER", target = job.sender } }
			if not job.initialSubmitted then
				local response = self:BuildPingResponse(job.request.requestId)
				if self:AddDeveloperPingMetadata(response, job.request) then
					options.onComplete = function(accepted, result)
						job.initialAccepted = accepted
						job.result = result
						if (accepted and not job.request.debugRequest) or (not accepted and result ~= "capacity") then
							if state.jobs[key] == job then
								state.jobs[key] = nil
							end
						end
					end
					local ok, reason = self:Respond("PONG", response, routes, options)
					job.initialSubmitted = ok
					job.dueAt = now + 1
					if not ok and reason ~= "capacity" then
						job.dueAt = job.expiresAt
						job.result = reason
					end
				else
					state.jobs[key] = nil
				end
			elseif job.initialAccepted and job.request.debugRequest and not job.reportSubmitted then
				-- Build the expensive report only after the small initial response has had
				-- its turn. A report still uses the same fair scheduler as every other topic.
				if not job.report then
					local ok, report = pcall(self.BuildDeveloperDiagnosticSnapshot, self)
					job.report = ok and report or L("Diagnostics unavailable.")
				end
				options.onComplete = function(accepted, result)
					job.reportAccepted = accepted
					job.result = result
					if result ~= "capacity" and state.jobs[key] == job then
						state.jobs[key] = nil
					end
				end
				local ok, reason = self:Respond(
					"DREPORT",
					{ requestId = job.request.requestId, diagnosticText = job.report },
					routes,
					options
				)
				if ok then
					job.reportSubmitted = true
					job.report = nil
				elseif reason ~= "capacity" then
					job.reportSubmitted = true
					job.result = reason
					job.report = nil
					self:Respond(
						"ERROR",
						{ requestId = job.request.requestId, operation = "PING", code = reason },
						routes,
						options
					)
				end
				job.dueAt = now + 1
			end
		end
	end
end
function QT:CreatePingResponseObservation(response, pending)
	local name = self:NormalizeMemberName(response.senderName)
	local now = self:GetAnnouncementServerTime()
	local stamp = self:SafeToNumber(response.sampledAt)
	if not name or not now or not stamp or type(pending) ~= "table" then
		return nil
	end
	if response.developer and (rawget(self, "isLocalDeveloper") ~= true or not pending.developerRequest) then
		return nil
	end
	local age = now - stamp
	if age < -1 or age >= 600 then
		return nil
	end
	local observation = self:CreatePeerObservation(
		name,
		"LOC",
		{ source = response.developer and "diagnostic" or "pong", age = math.max(0, age), lifetime = 600 }
	)
	if observation then
		observation.manual = true
	end
	return observation
end
function QT:HandlePingResponse(data)
	local pending = self.pendingPingRequests and self.pendingPingRequests[data.requestId]
	local name = self:NormalizeMemberName(data.senderName)
	local now = self.API.GetTime()
	if
		not pending
		or not name
		or now < pending.startedAt
		or (pending.targetName and pending.targetName ~= name)
		or pending.responders[name]
		or pending.responderCount >= 4096
	then
		return false
	end
	pending.responders[name] = true
	pending.responderCount = pending.responderCount + 1
	if not self:IsSelfSender(name) then
		pending.remoteReplies = pending.remoteReplies + 1
	end
	if self.PrintPingResponse then
		self:PrintPingResponse(data)
	end
	local observation = self:CreatePingResponseObservation(data, pending)
	if data.developer then
		self:AcceptDeveloperPingResponse(data, pending, observation or false)
	elseif observation and self:RefreshPlayerLocationFromPing(name, data, observation) then
		self:RefreshPlayerLocationPins()
	end
	if observation then
		self:RecordPeerPresenceFromSnapshot(name, observation.sampledAt)
	end
	if data.addonVersion then
		self:ObserveAddonVersion(data.addonVersion)
		self:RememberPlayerAddonVersion(name, data.addonVersion)
	end
	self:RecordCommsDiagnostic("pingReplies", string.format("response %.3fs", now - pending.startedAt))
	return true
end
function QT:HandleDeveloperReport(data, sender)
	local pending = self.pendingPingRequests and self.pendingPingRequests[data.requestId]
	if
		not pending
		or not pending.developerRequest
		or not pending.debugRequest
		or pending.targetName ~= sender
		or rawget(self, "isLocalDeveloper") ~= true
		or pending.reportExpired
		or pending.reportReceived
	then
		return false
	end
	pending.reportReceived = true
	self:GetDebugController():ShowReport(data.diagnosticText, sender)
	-- Retain the bounded ping identity: an initial pong may arrive after its report.
	return true
end
function QT:UpdateCommunicationRequests(now)
	self:DrainDeveloperPingVerifications()
	self:ProgressPingReplies(now)
	self:ProgressQuestCompareResponses(now)
end

function QT:CancelDeveloperDiagnosticReplies()
	self.diagnosticReplyGeneration = (rawget(self, "diagnosticReplyGeneration") or 0) + 1
	local state = rawget(self, "pingReplyState")
	self.pingReplyState = nil
	self.developerRequestState = nil
	for _, job in pairs(state and state.jobs or {}) do
		self:CancelTransportOwner(job, "cancelled")
		self:CancelCommTransferOwner(job, "cancelled")
	end
end
