local QT = _G.QuestTogether
local L = QT.Translate

local function Hex(s)
	return (s:gsub(".", function(c)
		return string.format("%02x", c:byte())
	end))
end
local function Unhex(s, length)
	if type(s) ~= "string" or #s ~= length * 2 or s:find("[^%da-f]") then
		return nil
	end
	return (s:gsub("..", function(pair)
		return string.char(tonumber(pair, 16))
	end))
end
local function SignedText(request, sender, purpose)
	if purpose == "announcements" then
		return table.concat({
			"QTDEVFEED2",
			sender,
			request.requestId,
			tostring(request.issuedAt),
			request.active and "start" or "stop",
			request.subscriptionSession,
			request.targetName or "",
		}, "\n")
	end
	return table.concat({
		"QTDEV2",
		sender,
		request.requestId,
		tostring(request.issuedAt),
		request.debugRequest and "debug" or "snapshot",
		request.targetName or "",
	}, "\n")
end
local function Name(addon, name)
	name = addon:NormalizeMemberName(name)
	if not name or #name > 120 or name:find("[%c|,]") then
		return nil
	end
	return name
end

local function PrepareRequest(addon, request, target, purpose)
	local sign = rawget(addon, "SignDeveloperRequest")
	if type(request) ~= "table" or rawget(addon, "isLocalDeveloper") ~= true or type(sign) ~= "function" then
		return nil
	end
	local now = addon:GetAnnouncementServerTime()
	local sender = Name(addon, addon:GetPlayerFullName())
	if not now or not sender then
		return nil
	end
	if target then
		target = Name(addon, target)
		if not target then
			return nil
		end
	end
	request.requestId =
		string.format("dev-%.0f-%d-%.0f", now, addon.API.Random(1000, 9999), addon:NextCommunicationSequence())
	request.requesterName = "" -- Transport identity is authoritative; do not spend packet bytes repeating it.
	request.issuedAt, request.targetName = now, target
	request.developerRequest = true
	local ok, signature = pcall(sign, addon, SignedText(request, sender, purpose))
	if not ok or type(signature) ~= "string" or #signature ~= 64 then
		return nil
	end
	request.signature = Hex(signature)
	return request
end

local function ValidSubscription(request)
	return type(request) == "table"
		and type(request.active) == "boolean"
		and type(request.subscriptionSession) == "string"
		and #request.subscriptionSession <= 64
		and request.subscriptionSession:match("^[%w%-]+$") ~= nil
end

function QT:PrepareDeveloperPingRequest(request, target, debugRequest)
	if type(request) ~= "table" then
		return nil
	end
	request.debugRequest = debugRequest == true
	return PrepareRequest(self, request, target, "ping")
end

function QT:PrepareDeveloperAnnouncementSubscription(request, target)
	if not ValidSubscription(request) then
		return nil
	end
	return PrepareRequest(self, request, target, "announcements")
end

local function VerificationEnabled(addon)
	return addon.isEnabled and not addon.isLoggingOut and addon:GetOption("shareDeveloperDiagnostics") == true
end

local function ProfileMilliseconds(addon)
	local read = addon.API.ProfileMilliseconds
	return read and addon:SafeToNumber(read()) or nil
end

local function Measure(metrics, name, value)
	value = math.max(0, value)
	metrics[name .. "Last"] = value
	metrics[name .. "Total"] = (metrics[name .. "Total"] or 0) + value
	metrics[name .. "Max"] = math.max(metrics[name .. "Max"] or 0, value)
end

function QT:GetDeveloperCommunicationMetrics()
	local state = rawget(self, "developerRequestState")
	local result = { queued = 0, oldestAge = 0 }
	if not state then
		return result
	end
	for key, value in pairs(state.metrics or {}) do
		result[key] = value
	end
	local now = self:SafeToNumber(self.API.GetTime()) or state.startedAt
	result.queued = #state.jobs
	for _, job in ipairs(state.jobs) do
		result.oldestAge = math.max(result.oldestAge, now - job.startedAt)
	end
	return result
end

function QT:CancelIgnoredDeveloperRequests()
	local state = rawget(self, "developerRequestState")
	for _, job in ipairs(state and state.jobs or {}) do
		if self:IsIgnoredPlayerName(job.sender) then
			job.request.cancelled = true
		end
	end
end

function QT:DrainDeveloperPingVerifications()
	local state = rawget(self, "developerRequestState")
	if not state then
		return
	end
	if not VerificationEnabled(self) then
		self.developerRequestState = nil
		return
	end
	local job = state.jobs[1]
	if not job then
		return
	end
	local now, serverNow = self.API.GetTime(), self:GetAnnouncementServerTime()
	if state.lastAt and now < state.lastAt then
		self.developerRequestState = nil
		return
	end
	state.lastAt = now
	local expired = not serverNow
		or job.request.cancelled
		or now < job.startedAt
		or serverNow - job.request.issuedAt > 300
		or self:IsIgnoredPlayerName(job.sender)
	local done, valid = expired, false
	if not done and now >= state.nextAllowed then
		local started = ProfileMilliseconds(self)
		state.metrics.slices = (state.metrics.slices or 0) + 1
		if not job.verificationStartedAt then
			job.verificationStartedAt = now
			Measure(state.metrics, "queueSeconds", now - job.startedAt)
		end
		local lastProfile = started
		-- Both bounds apply: a missing/paused/reset profiler still cannot turn
		-- this into one synchronous 100ms verification. Yield between frames.
		for _ = 1, 8 do
			state.metrics.steps = (state.metrics.steps or 0) + 1
			local ok, result = coroutine.resume(job.verifier)
			if not ok or coroutine.status(job.verifier) == "dead" then
				done, valid = true, ok and result == true
				break
			end
			local current = started and ProfileMilliseconds(self)
			lastProfile = current or lastProfile
			if current and (current < started or current - started >= 1) then
				break
			end
		end
		if started and lastProfile and lastProfile >= started then
			state.metrics.verificationMilliseconds = (state.metrics.verificationMilliseconds or 0)
				+ lastProfile
				- started
		end
	end
	if done then
		local outcome = valid and "verified" or (expired and "expired" or "failed")
		state.metrics[outcome] = (state.metrics[outcome] or 0) + 1
		if job.verificationStartedAt then
			Measure(state.metrics, "verificationSeconds", now - job.verificationStartedAt)
		end
		table.remove(state.jobs, 1)
		state.pendingSenders[job.sender] = nil
		state.nextAllowed = now + 5
		local failure = state.failures[job.sender]
		if valid then
			state.failures[job.sender] = nil
			job.request.developerVerified = true
			-- State identity fences disable, profile changes, opt-out, and leaving
			-- the world. No diagnostic reads occur before this boundary.
			if rawget(self, "developerRequestState") == state and VerificationEnabled(self) then
				local ok = pcall(job.callback, job.request)
				if not ok then
					self:Debug("Developer request callback failed", "comms")
				end
			end
		elseif not expired then
			local count = math.min(5, (failure and failure.count or 0) + 1)
			if not failure then
				local entries, oldest, oldestAt = 0
				for name, row in pairs(state.failures) do
					entries = entries + 1
					if not oldestAt or row.failedAt < oldestAt then
						oldest, oldestAt = name, row.failedAt
					end
				end
				if entries >= 64 then
					state.failures[oldest] = nil
				end
			end
			state.failures[job.sender] =
				{ count = count, failedAt = now, untilAt = now + math.min(60, 5 * 2 ^ (count - 1)) }
		end
	end
end

local function QueueVerification(self, request, sender, callback, purpose)
	if type(request) ~= "table" or not VerificationEnabled(self) or type(callback) ~= "function" then
		return false
	end
	local now, senderName = self:GetAnnouncementServerTime(), Name(self, sender)
	local issued = self:SafeToNumber(request.issuedAt)
	local target = request.targetName
	if
		not senderName
		or not now
		or not issued
		or issued ~= math.floor(issued)
		or issued > now + 30
		or now - issued > 300
		or type(request.requestId) ~= "string"
		or #request.requestId > 64
		or not request.requestId:match("^dev%-%d+%-%d+%-%d+$")
		or (target and target ~= self:NormalizeMemberName(self:GetPlayerFullName()))
		or (purpose == "ping" and request.debugRequest and not target)
		or (purpose == "announcements" and not ValidSubscription(request))
	then
		return false
	end
	local signature, public = Unhex(request.signature, 64), Unhex(self.developerPublicKeyHex, 32)
	if not signature or not public then
		return false
	end
	local state = rawget(self, "developerRequestState")
	local tick = self.API.GetTime()
	if not state or tick < state.startedAt or (state.lastAt and tick < state.lastAt) then
		state = {
			seen = {},
			jobs = {},
			failures = {},
			pendingSenders = {},
			startedAt = tick,
			lastAt = tick,
			nextAllowed = tick,
			metrics = {},
		}
		self.developerRequestState = state
	end
	state.lastAt = tick
	local count = 0
	for key, at in pairs(state.seen) do
		if now - at > 300 or now < at then
			state.seen[key] = nil
		else
			count = count + 1
		end
	end
	for name, failure in pairs(state.failures) do
		if tick < failure.failedAt or tick >= failure.untilAt + 300 then
			state.failures[name] = nil
		end
	end
	local key = senderName .. "|" .. request.requestId
	local failure = state.failures[senderName]
	if
		state.seen[key]
		or count >= 64
		or #state.jobs >= 4
		or state.pendingSenders[senderName]
		or (failure and tick < failure.untilAt)
		or self:IsIgnoredPlayerName(senderName)
	then
		return false
	end
	local copy = {}
	for _, field in ipairs({ "requestId", "issuedAt", "targetName", "debugRequest", "developerRequest", "signature" }) do
		copy[field] = request[field]
	end
	if purpose == "announcements" then
		copy.active, copy.subscriptionSession = request.active, request.subscriptionSession
	end
	copy.developerPurpose = purpose
	copy.requesterName = senderName
	state.metrics.admitted = (state.metrics.admitted or 0) + 1
	state.seen[key], state.pendingSenders[senderName] = now, true
	state.jobs[#state.jobs + 1] = {
		request = copy,
		sender = senderName,
		callback = callback,
		startedAt = tick,
		verifier = self.Ed25519.NewVerification(public, SignedText(copy, senderName, purpose), signature),
	}
	-- RuntimeCoordinator advances verification in bounded slices.

	return true
end

function QT:QueueDeveloperPingVerification(request, sender, callback)
	return QueueVerification(self, request, sender, callback, "ping")
end

function QT:QueueDeveloperAnnouncementVerification(request, sender, callback)
	return QueueVerification(self, request, sender, callback, "announcements")
end

function QT:BuildDeveloperDiagnosticSnapshot()
	local fields = {}
	-- Only QT-owned, explicitly declared primitive settings. No SavedVariables
	-- dump, chat history, arbitrary globals, other addons, or private key material.
	local keys = {}
	for key, value in pairs(self.DEFAULTS.profile) do
		if type(value) ~= "table" then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local value = self:GetOption(key)
		if
			self:CanAccessValue(value)
			and (type(value) == "boolean" or type(value) == "number" or type(value) == "string")
		then
			fields[#fields + 1] = { "option." .. key, value }
		end
	end
	-- Settings share the report window's 32 KiB budget and explicit truncation
	-- marker instead of being appended outside the diagnostic report's bound.
	return self:BuildDiagnosticReport(nil, fields)
end

function QT:AddDeveloperPingMetadata(response, request)
	if not request or not request.developerVerified or self:GetOption("shareDeveloperDiagnostics") ~= true then
		return false
	end
	response.developer = true
	response.locationShared = self:CanPublishPlayerLocation()
	response.lookingForQuestPartners = self:GetOption("lookingForQuestPartners") == true
	response.sampledAt = self:GetAnnouncementServerTime()
	local location = self:ReadLocalPlayerLocation()
	if location then
		response.mapID, response.coordX, response.coordY =
			tostring(location.mapID), string.format("%.1f", location.x * 100), string.format("%.1f", location.y * 100)
		response.faction = location.faction
		response.warMode = location.warMode == nil and "" or (location.warMode and "1" or "0")
	end
	response.party = self:BuildPartyVisualMetadata()

	return true
end

function QT:AcceptDeveloperPingResponse(response, pending, observation)
	if rawget(self, "isLocalDeveloper") ~= true or not pending.developerRequest or not response.developer then
		return
	end
	local name = Name(self, response.senderName)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return
	end
	-- A correlated report remains useful after departure. Its sampled player
	-- metadata still has to pass the freshness fence below before updating peers.

	local now = self.API.GetTime()
	if observation == nil then
		observation = self:CreatePingResponseObservation(response, pending)
	end
	local age = observation and now - observation.sampledAt
	local data = rawget(self, "developerPlayerData")
	if not data then
		data = {}
		self.developerPlayerData = data
	end
	local count = 0
	for key, row in pairs(data) do
		if now < row.receivedAt or now - row.receivedAt >= 120 then
			data[key] = nil
		else
			count = count + 1
		end
	end
	if age and age >= -30 and age < self:GetGeographicSnapshotLifetime() then
		age = math.max(0, age)
		if not self:CanAcceptPeerUpdate(name, nil, now - age) then
			return
		end
		-- Each field keeps its own ordering. A newer location need not suppress a
		-- useful party refresh, but old party data must never replace a newer one.
		if response.party then
			self:HandlePartyVisualMetadata(
				response.party,
				name,
				self:CreatePeerObservation(
					name,
					"QTPG",
					{ source = "diagnostic", age = age, lifetime = self:GetGeographicSnapshotLifetime() }
				)
			)
		end
		self:RefreshQuestPartnerStatusFromPing(name, response.lookingForQuestPartners, age)
		local previous = data[name]
		local fresh = not previous or now - age >= previous.receivedAt
		local accepted = fresh and self:RefreshPlayerLocationFromPing(name, response, observation)
		if accepted and response.locationShared == false and age < 120 and (count < 512 or previous) then
			local map, x, y, level =
				self:SafeToNumber(response.mapID),
				self:SafeToNumber(response.coordX),
				self:SafeToNumber(response.coordY),
				self:SafeToNumber(response.level)
			if
				map
				and map > 0
				and map == math.floor(map)
				and map <= 1000000
				and x
				and x >= 0
				and x <= 100
				and y
				and y >= 0
				and y <= 100
			then
				data[name] = {
					name = name,
					mapID = map,
					x = x / 100,
					y = y / 100,
					classFile = response.classFile,
					className = response.className,
					race = response.raceName,
					level = level,
					faction = response.faction,
					warMode = self:NormalizeAnnouncementWarModeValue(response.warMode),
					receivedAt = now - math.max(0, age),
					lifetime = 120,
					mask = 3,
					developerOnly = true,
					publicLocationHidden = true,
					lookingForQuestPartners = response.lookingForQuestPartners,
					addonVersion = response.addonVersion,
				}
			end
		end
	end
	self:RefreshPlayerLocationPins()
end

function QT:AppendDeveloperLocationRows(rows)
	if rawget(self, "isLocalDeveloper") ~= true then
		return
	end
	local data = rawget(self, "developerPlayerData")
	local now, indices = self.API.GetTime(), {}
	for index, row in ipairs(rows) do
		indices[row.name] = index
	end
	for name, row in pairs(data or {}) do
		if now < row.receivedAt or now - row.receivedAt >= 120 or self:IsIgnoredPlayerName(name) then
			data[name] = nil
		elseif self:ShouldShowPlayerLocation(name) then
			-- A newer live public sample wins over an older diagnostic snapshot.
			local index = indices[name]
			if not index then
				rows[#rows + 1] = row
			elseif rows[index].receivedAt <= row.receivedAt then
				rows[index] = row
			end
		end
	end
end

function QT:RequestRemoteDiagnostics(input)
	if rawget(self, "isLocalDeveloper") ~= true then
		return false
	end
	local target = self:SafeTrimString(input, "")
	if target:sub(1, 1) == '"' then
		target = target:match('^"([^"]+)"$')
	end
	if not target or target == "" then
		self:Print(L("Ping is unavailable."))
		return false
	end
	local ok, detail = self:SendPingRequest(target, true)
	self:Print(ok and L("Ping sent.") or detail or L("Ping is unavailable."))
	return ok
end

function QT:RetireDeveloperLocationPeer(name)
	local data = rawget(self, "developerPlayerData")
	if data then
		data[name] = nil
	end
end

function QT:ResetDeveloperDiagnostics()
	self.developerPlayerData = nil
	self.developerRequestState = nil
end
