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

function QT:VerifyDeveloperPingRequest(request, sender)
	if self:GetOption("shareDeveloperDiagnostics") ~= true then return false end
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
	if not state then state = { seen = {} }; self.developerRequestState = state end
	-- Bound crypto work before verification, and bound all attacker-controlled state.
	local tick = self.API.GetTime()
	if state.lastCheck and tick >= state.lastCheck and tick - state.lastCheck < 0.5 then return false end
	state.lastCheck = tick
	local count = 0
	for key, at in pairs(state.seen) do if now-at > 300 or now < at then state.seen[key]=nil else count=count+1 end end
	local key = senderName .. "|" .. request.requestId
	if state.seen[key] or count >= 64 then return false end
	if state.lastAccepted and tick >= state.lastAccepted and tick-state.lastAccepted < 5 then return false end
	local ok, valid = pcall(self.Ed25519.Verify, public, SignedText(request,senderName),signature)
	if not ok or not valid then return false end
	state.seen[key], state.lastAccepted = now, tick
	return true
end

function QT:BuildDeveloperDiagnosticSnapshot()
	local lines = { self:BuildDiagnosticReport() }
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
			lines[#lines+1] = "option." .. key .. "=" .. tostring(value)
		end
	end
	return table.concat(lines,"\n")
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
	if not name then return end
	if response.partyPayload and response.partyPayload ~= "" then self:HandlePartyVisualMetadata(response.partyPayload,name) end
	local now = self.API.GetTime()
	local serverNow, sampled = self:GetAnnouncementServerTime(), self:SafeToNumber(response.sampledAt)
	local age = serverNow and sampled and serverNow-sampled
	local data = rawget(self,"developerPlayerData")
	if not data then data={}; self.developerPlayerData=data end
	local count=0
	for key,row in pairs(data) do if now < row.receivedAt or now-row.receivedAt>=120 then data[key]=nil else count=count+1 end end
	if age and age >= -30 and age < 120 and (count < 512 or data[name]) then
		local map,x,y,level = self:SafeToNumber(response.mapID),self:SafeToNumber(response.coordX),self:SafeToNumber(response.coordY),self:SafeToNumber(response.level)
		if map and map>0 and map==math.floor(map) and map<=1000000 and x and x>=0 and x<=100 and y and y>=0 and y<=100 then
			data[name]={ name=name,mapID=map,x=x/100,y=y/100,classFile=response.classFile,className=response.className,
				race=response.raceName,level=level,faction=response.faction,warMode=self:NormalizeAnnouncementWarModeValue(response.warMode),
				receivedAt=now-math.max(0,age),lifetime=120,mask=3,developerOnly=true,publicLocationHidden=response.locationShared==false,
				lookingForQuestPartners=response.lookingForQuestPartners,addonVersion=response.addonVersion }
		end
	end
	if pending.debugRequest and pending.targetName==name and response.diagnosticText and response.diagnosticText~="" then
		self:GetDebugController():ShowReport(response.diagnosticText, name)
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
		elseif not self:IsSelfSender(name) then
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
