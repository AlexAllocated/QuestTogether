local QT = _G.QuestTogether
local L = QT.Translate

local function Hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function Unhex(s, length)
	if type(s) ~= "string" or #s ~= length * 2 or s:find("[^%da-f]") then return nil end
	return (s:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
end
local function SignedText(request, sender)
	return table.concat({ "QTDEV1", sender, request.requestId, tostring(request.issuedAt),
		request.debugRequest and "debug" or "snapshot", request.targetName or "" }, "\n")
end
local function Name(addon, name)
	name = addon:NormalizeMemberName(name)
	if not name or #name > 120 or name:find("[%c|,]") then return nil end
	return name
end

function QT:PrepareDeveloperPingRequest(request, target, debugRequest)
	local sign = rawget(self, "SignDeveloperRequest")
	if rawget(self, "isLocalDeveloper") ~= true or type(sign) ~= "function" then return nil end
	local now = self:GetAnnouncementServerTime()
	local sender = Name(self, self:GetPlayerFullName())
	if not now or not sender then return nil end
	if target then target = Name(self, target); if not target then return nil end end
	request.requestId = string.format("dev-%d-%d-%d", now, self.API.Random(1000,9999), self.channelRequestSequence or 0)
	request.requesterName = "" -- Transport identity is authoritative; do not spend packet bytes repeating it.
	request.issuedAt, request.targetName, request.debugRequest = now, target, debugRequest == true
	request.developerRequest = true
	local ok, signature = pcall(sign, self, SignedText(request, sender))
	if not ok or type(signature) ~= "string" or #signature ~= 64 then return nil end
	request.signature = Hex(signature)
	return request
end

local function VerificationEnabled(addon)
	return addon.isEnabled and not addon.isLoggingOut and addon:GetOption("shareDeveloperDiagnostics") == true
end

local function ProfileMilliseconds(addon)
	local read = addon.API.ProfileMilliseconds
	return read and addon:SafeToNumber(read()) or nil
end

function QT:DrainDeveloperPingVerifications()
	local state = rawget(self, "developerRequestState")
	if not state or state.scheduled then return end
	if not VerificationEnabled(self) then self.developerRequestState = nil; return end
	local job = state.jobs[1]
	if not job then return end
	local now, serverNow = self.API.GetTime(), self:GetAnnouncementServerTime()
	if state.lastAt and now < state.lastAt then self.developerRequestState = nil; return end
	state.lastAt = now
	local expired = not serverNow or now < job.startedAt or serverNow - job.request.issuedAt > 300
		or self:IsIgnoredPlayerName(job.sender)
	local done, valid = expired, false
	if not done and now >= state.nextAllowed then
		local started = ProfileMilliseconds(self)
		-- Both bounds apply: a missing/paused/reset profiler still cannot turn
		-- this into one synchronous 100ms verification. Yield between frames.
		for _ = 1, 8 do
			local ok, result = coroutine.resume(job.verifier)
			if not ok or coroutine.status(job.verifier) == "dead" then
				done, valid = true, ok and result == true
				break
			end
			local current = started and ProfileMilliseconds(self)
			if current and (current < started or current - started >= 1) then break end
		end
	end
	if done then
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
				if not ok then self:Debug("Developer ping callback failed", "comms") end
			end
		elseif not expired then
			local count = math.min(5, (failure and failure.count or 0) + 1)
			if not failure then
				local entries, oldest, oldestAt = 0
				for name, row in pairs(state.failures) do
					entries = entries + 1
					if not oldestAt or row.failedAt < oldestAt then oldest, oldestAt = name, row.failedAt end
				end
				if entries >= 64 then state.failures[oldest] = nil end
			end
			state.failures[job.sender] = { count = count, failedAt = now,
				untilAt = now + math.min(60, 5 * 2 ^ (count - 1)) }
		end
	end
	if rawget(self, "developerRequestState") ~= state or #state.jobs == 0 then return end
	state.scheduled = true
	self.API.Delay(math.max(0.01, state.nextAllowed - now), function()
		if rawget(self, "developerRequestState") ~= state then return end
		state.scheduled = false
		self:DrainDeveloperPingVerifications()
	end)
end

function QT:QueueDeveloperPingVerification(request, sender, callback)
	if not VerificationEnabled(self) or type(callback) ~= "function" then return false end
	local now, senderName = self:GetAnnouncementServerTime(), Name(self, sender)
	local issued = self:SafeToNumber(request.issuedAt)
	local target = request.targetName
	if not senderName or not now or not issued or issued ~= math.floor(issued)
		or issued > now + 30 or now - issued > 300 or not request.supportsPagedPong
		or type(request.requestId) ~= "string" or #request.requestId > 64
		or not request.requestId:match("^dev%-%d+%-%d+%-%d+$")
		or (target and target ~= self:NormalizeMemberName(self:GetPlayerFullName()))
		or (request.debugRequest and not target) then return false end
	local signature, public = Unhex(request.signature,64), Unhex(self.developerPublicKeyHex,32)
	if not signature or not public then return false end
	local state = rawget(self, "developerRequestState")
	local tick = self.API.GetTime()
	if not state or tick < state.startedAt or (state.lastAt and tick < state.lastAt) then
		state = { seen = {}, jobs = {}, failures = {}, pendingSenders = {}, startedAt = tick, lastAt = tick, nextAllowed = tick }
		self.developerRequestState = state
	end
	state.lastAt = tick
	local count = 0
	for key, at in pairs(state.seen) do if now-at > 300 or now < at then state.seen[key]=nil else count=count+1 end end
	for name, failure in pairs(state.failures) do
		if tick < failure.failedAt or tick >= failure.untilAt + 300 then state.failures[name] = nil end
	end
	local key = senderName .. "|" .. request.requestId
	local failure = state.failures[senderName]
	if state.seen[key] or count >= 64 or #state.jobs >= 4 or state.pendingSenders[senderName]
		or (failure and tick < failure.untilAt) or self:IsIgnoredPlayerName(senderName) then return false end
	local copy = {}
	for _, field in ipairs({ "requestId", "issuedAt", "targetName", "debugRequest", "developerRequest",
		"signature", "supportsPagedPong", "supportsDirectComms", "supportsLargePong" }) do copy[field] = request[field] end
	copy.requesterName = senderName
	state.seen[key], state.pendingSenders[senderName] = now, true
	state.jobs[#state.jobs + 1] = { request = copy, sender = senderName, callback = callback, startedAt = tick,
		verifier = self.Ed25519.NewVerification(public, SignedText(copy, senderName), signature) }
	-- Schedule even the first slice. Incoming-message handling stays cheap.
	if not state.scheduled then
		state.scheduled = true
		self.API.Delay(math.max(0.01, state.nextAllowed - tick), function()
			if rawget(self, "developerRequestState") ~= state then return end
			state.scheduled = false
			self:DrainDeveloperPingVerifications()
		end)
	end
	return true
end

function QT:BuildDeveloperDiagnosticSnapshot()
	local fields = {}
	-- Only QT-owned, explicitly declared primitive settings. No SavedVariables
	-- dump, chat history, arbitrary globals, other addons, or private key material.
	local keys = {}
	for key, value in pairs(self.DEFAULTS.profile) do
		if type(value) ~= "table" then keys[#keys+1] = key end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local value = self:GetOption(key)
		if self:CanAccessValue(value) and (type(value)=="boolean" or type(value)=="number" or type(value)=="string") then
			fields[#fields+1] = { "option." .. key, value }
		end
	end
	-- Settings share the report window's 32 KiB budget and explicit truncation
	-- marker instead of being appended outside the diagnostic report's bound.
	return self:BuildDiagnosticReport(nil, fields)
end

function QT:AddDeveloperPingMetadata(response, request)
	if not request or not request.developerVerified or self:GetOption("shareDeveloperDiagnostics") ~= true then return false end
	response.developer = true
	response.locationShared = self:CanPublishPlayerLocation()
	response.lookingForQuestPartners = self:GetOption("lookingForQuestPartners") == true
	response.sampledAt = self:GetAnnouncementServerTime()
	local location = self:ReadLocalPlayerLocation()
	if location then
		response.mapID, response.coordX, response.coordY = tostring(location.mapID), string.format("%.1f",location.x*100), string.format("%.1f",location.y*100)
		response.faction = location.faction
		response.warMode = location.warMode == nil and "" or (location.warMode and "1" or "0")
	end
	response.partyPayload = self:BuildPartyVisualMetadataPayload()
	if request.debugRequest then
		local ok, report = pcall(self.BuildDeveloperDiagnosticSnapshot,self)
		response.diagnosticText = ok and report or L("Diagnostics unavailable.")
	end
	return true
end

function QT:AcceptDeveloperPingResponse(response, pending)
	if rawget(self,"isLocalDeveloper") ~= true or not pending.developerRequest or not response.developer then return end
	local name = Name(self,response.senderName)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then return end
	-- A correlated report remains useful after departure. Its sampled player
	-- metadata still has to pass the freshness fence below before updating peers.
	if pending.debugRequest and pending.targetName==name and response.diagnosticText and response.diagnosticText~="" then
		self:GetDebugController():ShowReport(response.diagnosticText, name)
	end
	local now = self.API.GetTime()
	local serverNow, sampled = self:GetAnnouncementServerTime(), self:SafeToNumber(response.sampledAt)
	local age = serverNow and sampled and serverNow-sampled
	local data = rawget(self,"developerPlayerData")
	if not data then data={}; self.developerPlayerData=data end
	local count=0
	for key,row in pairs(data) do if now < row.receivedAt or now-row.receivedAt>=120 then data[key]=nil else count=count+1 end end
	if age and age >= -30 and age < self:GetGeographicSnapshotLifetime() then
		age = math.max(0, age)
		if not self:CanAcceptPeerUpdate(name, nil, now - age) then return end
		-- Each field keeps its own ordering. A newer location need not suppress a
		-- useful party refresh, but old party data must never replace a newer one.
		if response.partyPayload and response.partyPayload ~= "" then
			self:WithPeerUpdateContext(name, now - age, nil, nil, self.HandlePartyVisualMetadata, self, response.partyPayload, name, age)
		end
		self:RefreshQuestPartnerStatusFromPing(name, response.lookingForQuestPartners, age)
		local previous = data[name]
		local fresh = not previous or now - age >= previous.receivedAt
		local accepted = fresh and self:RefreshPlayerLocationFromPing(name, response, age)
		if accepted and response.locationShared == false and age < 120 and (count < 512 or previous) then
			local map,x,y,level = self:SafeToNumber(response.mapID),self:SafeToNumber(response.coordX),self:SafeToNumber(response.coordY),self:SafeToNumber(response.level)
			if map and map>0 and map==math.floor(map) and map<=1000000 and x and x>=0 and x<=100 and y and y>=0 and y<=100 then
				data[name]={ name=name,mapID=map,x=x/100,y=y/100,classFile=response.classFile,className=response.className,
					race=response.raceName,level=level,faction=response.faction,warMode=self:NormalizeAnnouncementWarModeValue(response.warMode),
					receivedAt=now-math.max(0,age),lifetime=120,mask=3,developerOnly=true,publicLocationHidden=true,
					lookingForQuestPartners=response.lookingForQuestPartners,addonVersion=response.addonVersion }
			end
		end
	end
	self:RefreshPlayerLocationPins()
end

function QT:AppendDeveloperLocationRows(rows)
	if rawget(self,"isLocalDeveloper") ~= true then return end
	local data = rawget(self,"developerPlayerData")
	local now, indices=self.API.GetTime(),{}
	for index,row in ipairs(rows) do indices[row.name]=index end
	for name,row in pairs(data or {}) do
		if now < row.receivedAt or now-row.receivedAt>=120 or self:IsIgnoredPlayerName(name) then data[name]=nil
		elseif self:ShouldShowPlayerLocation(name) then
			-- A newer live public sample wins over an older diagnostic snapshot.
			local index=indices[name]
			if not index then rows[#rows+1]=row
			elseif rows[index].receivedAt <= row.receivedAt then rows[index]=row end
		end
	end
end

function QT:RequestRemoteDiagnostics(input)
	if rawget(self,"isLocalDeveloper") ~= true then return false end
	local target=self:SafeTrimString(input,"")
	if target:sub(1,1)=='"' then target=target:match('^"([^"]+)"$') end
	if not target or target=="" then self:Print(L("Ping is unavailable.")); return false end
	local ok,detail=self:SendPingRequest(target,true)
	self:Print(ok and L("Ping sent.") or detail or L("Ping is unavailable."))
	return ok
end
