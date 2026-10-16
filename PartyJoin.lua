local L = _G.QuestTogether.Translate
local QT = _G.QuestTogether
local LIFETIME, PEER_LIFETIME = 60, 125
local STATUS = {
	request = true,
	pending = true,
	sent = true,
	declined = true,
	unavailable = true,
	expired = true,
	redirect = true,
	announced = true,
}

local function Now(a)
	return a.API and a.API.GetTime and a:SafeToNumber(a.API.GetTime()) or 0
end
local function Name(a, value)
	if not a:CanAccessValue(value) or type(value) ~= "string" or #value > 120 or value:find("[%c|,]") then
		return nil
	end
	return a:NormalizeMemberName(value)
end
local function ReadInfo(a)
	local fn = a.API and a.API.GetPartyJoinInfo
	if type(fn) ~= "function" then
		return nil
	end
	local ok, grouped, invite, count, relay = pcall(fn)
	if
		not ok
		or not a:CanAccessValue(grouped)
		or not a:CanAccessValue(invite)
		or not a:CanAccessValue(count)
		or type(grouped) ~= "boolean"
		or type(invite) ~= "boolean"
	then
		return nil
	end
	count = a:SafeToNumber(count)
	if not count or count < 0 or count > 40 or count ~= math.floor(count) then
		return nil
	end
	return grouped, invite, count, a:CanAccessValue(relay) and relay == true
end
local function Profile(a)
	local db = rawget(a, "db")
	return db and db.profile
end
local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end
local function Allowed(a)
	return a.isEnabled == true and not a.isLoggingOut and not a:IsRuntimeRestricted()
end

function QT:GetPartyJoinState()
	local state = rawget(self, "partyJoinState")
	if not state then
		state = { peers = {}, incoming = {}, seen = {}, reservations = {}, sequence = 0 }
		self.partyJoinState = state
	end
	return state
end

function QT:ResetPartyJoin()
	local state = rawget(self, "partyJoinState")
	self.partyJoinState = nil
	if state then
		self:CancelTransportOwner(state)
		if state.outgoing then
			self:CancelCommRequest(state.outgoing.id, "cancelled")
		end
	end
	local frame = rawget(self, "partyJoinPrompt")
	if frame then
		frame.request = nil
		-- This unprotected addon-owned prompt must close even while QT is disabled.
		if self.LibChev.CanMutateOwnedRegion(frame) then
			frame:Hide()
		end
	end
end

function QT:ForgetPartyJoinPeer(name)
	local state = rawget(self, "partyJoinState")
	if not state then
		return
	end
	state.peers[name], state.incoming[name], state.reservations[name] = nil, nil, nil
	if state.outgoing and (state.outgoing.target == name or state.outgoing.origin == name) then
		local id = state.outgoing.id
		state.outgoing = nil
		self:CancelCommRequest(id, "cancelled")
	end
	self:QueuePartyJoinPrompt()
end

function QT:PrunePartyJoin()
	local state = rawget(self, "partyJoinState")
	if not state then
		return
	end
	local now, changed = Now(self), false
	for name, peer in pairs(state.peers) do
		if now < peer.at or now - peer.at >= (peer.lifetime or PEER_LIFETIME) or self:IsIgnoredPlayerName(name) then
			state.peers[name] = nil
		end
	end
	for id, seen in pairs(state.seen) do
		if now < seen or now - seen >= 120 then
			state.seen[id] = nil
		end
	end
	for name, expires in pairs(state.reservations) do
		if now >= expires or self:IsGroupedSender(name) or self:IsIgnoredPlayerName(name) then
			state.reservations[name] = nil
		end
	end
	for name, request in pairs(state.incoming) do
		if
			now >= request.expires
			or now < request.created
			or request.profile ~= Profile(self)
			or request.roster ~= self.partyRosterFingerprint
			or ReadInfo(self) ~= true
			or self:IsIgnoredPlayerName(name)
			or self:IsGroupedSender(name)
		then
			state.incoming[name], changed = nil, true
		end
	end
	local outgoing = state.outgoing
	if
		outgoing
		and (
			now >= outgoing.expires
			or now < outgoing.created
			or self:IsIgnoredPlayerName(outgoing.target)
			or (outgoing.origin and self:IsIgnoredPlayerName(outgoing.origin))
			or ReadInfo(self) ~= false
		)
	then
		state.outgoing = nil
		self:CancelCommRequest(outgoing.id, "cancelled")
		if now >= outgoing.expires then
			self:Print(L("Join request expired."))
		end
	end
	if changed then
		self:QueuePartyJoinPrompt()
	end
end

function QT:HandlePartyJoinMetadata(data, sender, observation)
	if
		not self.isEnabled
		or type(data) ~= "table"
		or (data.grouped ~= "0" and data.grouped ~= "1" and data.grouped ~= "2")
		or type(data.invite) ~= "boolean"
	then
		return false
	end
	sender = Name(self, sender)
	if not sender or self:IsSelfSender(sender) or self:IsIgnoredPlayerName(sender) then
		return false
	end
	self:PrunePartyJoin()
	local state, now = self:GetPartyJoinState(), Now(self)
	observation = self:ResolvePeerObservation(sender, "QJST", observation)
	if not self:CanAcceptPeerObservation(observation) then
		return false
	end
	if not state.peers[sender] and Count(state.peers) >= 512 then
		local oldest, at
		for name, peer in pairs(state.peers) do
			if not at or peer.at < at then
				oldest, at = name, peer.at
			end
		end
		state.peers[oldest] = nil
	end
	local record = { grouped = data.grouped, invite = data.invite, at = now }
	if not self:CommitPeerObservation(observation, record, true) then
		return false
	end
	state.peers[sender] = record
	if record.grouped == "0" then
		self:InvalidatePartyVisualMembership(sender, 0, record.sampledAt, record)
	end
	return true
end

function QT:BuildPartyJoinMetadataPayload()
	if not Allowed(self) then
		return nil
	end
	local grouped, invite = ReadInfo(self)
	if grouped == nil then
		return nil
	end
	return { grouped = grouped and "1" or "0", invite = invite }
end
function QT:RecordPartyJoinPublication(record)
	local state = rawget(self, "partyJoinState")
	if not state or type(record) ~= "table" then
		return
	end
	state.lastSent = Now(self)
	state.lastMetadata = record.grouped .. "," .. (record.invite and "1" or "0")
end
function QT:BroadcastPartyJoinMetadata(force)
	local record = self:BuildPartyJoinMetadataPayload()
	if not record then
		return false
	end
	local state, now = self:GetPartyJoinState(), Now(self)
	local metadata = record.grouped .. "," .. (record.invite and "1" or "0")
	if not force and state.lastAttempt and now >= state.lastAttempt and now - state.lastAttempt < 5 then
		return false
	end
	if
		not force
		and state.lastSent
		and metadata == state.lastMetadata
		and now >= state.lastSent
		and now - state.lastSent < 60
	then
		return false
	end
	state.lastAttempt = now
	return self:Publish("QJST", record, nil, {
		owner = state,
		isCurrent = function()
			local current = self:BuildPartyJoinMetadataPayload()
			return rawget(self, "partyJoinState") == state
				and current ~= nil
				and current.grouped == record.grouped
				and current.invite == record.invite
		end,
		onComplete = function(sent)
			if sent and rawget(self, "partyJoinState") == state then
				self:RecordPartyJoinPublication(record)
			end
		end,
	})
end

function QT:UpdatePartyJoin()
	self:PrunePartyJoin()
	self:BroadcastPartyJoinMetadata()
end

function QT:ShouldRequestPartyJoin(name)
	name = Name(self, name)
	local state = rawget(self, "partyJoinState")
	local peer = state and name and state.peers[name]
	local now = Now(self)
	return self.isEnabled == true
		and peer ~= nil
		and peer.grouped == "1"
		and now >= peer.at
		and now - peer.at < (peer.lifetime or PEER_LIFETIME)
		and not self:IsIgnoredPlayerName(name)
end

function QT:GetPartyJoinLeaderName()
	if not Allowed(self) then
		return nil
	end
	local grouped, invite, _, relay = ReadInfo(self)
	if grouped ~= true or invite ~= false or not relay then
		return nil
	end
	local fn = self.API and self.API.GetPartyJoinLeaderUnit
	if type(fn) ~= "function" then
		return nil
	end
	local ok, unit = pcall(fn)
	if not ok or not self:CanAccessValue(unit) or type(unit) ~= "string" or not unit:match("^party[1-4]$") then
		return nil
	end
	local named, leader = pcall(self.GetUnitFullName, self, unit)
	leader = named and Name(self, leader) or nil
	if
		not leader
		or self:IsSelfSender(leader)
		or self:IsIgnoredPlayerName(leader)
		or not self:IsGroupedSender(leader)
	then
		return nil
	end
	return leader
end

function QT:GetPartyJoinRelayTarget()
	local leader = self:GetPartyJoinLeaderName()
	if not leader or not self:ShouldRequestPartyJoin(leader) then
		return nil
	end
	local peer = self:GetPartyJoinState().peers[leader]
	return peer and peer.invite and leader or nil
end

function QT:AnnouncePartyJoinRequest(sender)
	if
		not Allowed(self)
		or self:GetOption("announceToNonQTParty") ~= true
		or self.suppressLocalAnnouncementDisplayDuringTests
		or self:IsRuntimeRestrictionTypeActive("chat")
	then
		return false
	end
	sender = Name(self, sender)
	if not sender or self:IsSelfSender(sender) or self:IsIgnoredPlayerName(sender) or self:IsGroupedSender(sender) then
		return false
	end
	local leader = self:GetPartyJoinLeaderName()
	if not leader or self:IsKnownQTPlayer(leader) then
		return false
	end
	local send = self.API and self.API.SendPartyChatMessage
	if type(send) ~= "function" then
		return false
	end
	if not self:UpdatePartyChatReminder() then
		return false
	end
	-- Authenticated player identity and localized prose only, never requester text.
	local text = "[QT] "
		.. self:SanitizeAnnouncementText(string.format(L("%s is requesting to join the party."), sender))
	local ok, sent = pcall(send, text, "PARTY")
	return ok and self:CanAccessValue(sent) and sent == true
end

function QT:SendPartyJoinMessage(target, id, status, leader)
	target = Name(self, target)
	if not Allowed(self) or not target or not STATUS[status] then
		return false
	end
	if status == "redirect" then
		leader = Name(self, leader)
		if not leader then
			return false
		end
	end
	local record = { requestId = id, targetName = target, status = status, leader = leader }
	local routes = { { distribution = "WHISPER", target = target } }
	if status ~= "request" then
		return self:Respond("QJON", record, routes, { expires = Now(self) + LIFETIME })
	end
	local state, profile = rawget(self, "partyJoinState"), Profile(self)
	local request = state and state.outgoing
	local function Current()
		local now = Now(self)
		return request ~= nil
			and rawget(self, "partyJoinState") == state
			and state.outgoing == request
			and request.id == id
			and request.target == target
			and Profile(self) == profile
			and now >= request.created
			and now < request.expires
			and Allowed(self)
			and ReadInfo(self) == false
			and not self:IsIgnoredPlayerName(target)
			and (not request.origin or not self:IsIgnoredPlayerName(request.origin))
	end
	return self:Request("QJON", record, routes, {
		owner = request,
		expires = request and request.expires or Now(self) + LIFETIME,
		responseCurrent = Current,
		isCurrent = function()
			return Current()
				and not request.pending
				and ((request.redirected and not state.peers[target]) or self:ShouldRequestPartyJoin(target))
		end,
		onResponse = function(data, sender, context)
			return self:HandlePartyJoinMessage(data, sender, context)
		end,
		onComplete = function(sent)
			if not sent and state and state.outgoing == request then
				state.outgoing = nil
				self:CancelCommRequest(id, "cancelled")
			end
		end,
	})
end

function QT:RequestPartyJoin(target)
	target = Name(self, target)
	if not Allowed(self) or not target or self:IsSelfSender(target) or self:IsIgnoredPlayerName(target) then
		return false
	end
	if ReadInfo(self) ~= false then
		self:Print(L("Leave your current party before requesting to join another."))
		return false
	end
	self:PrunePartyJoin()
	local state, now = self:GetPartyJoinState(), Now(self)
	if not self:ShouldRequestPartyJoin(target) then
		self:Print(L("This player cannot currently accept join requests. Try whispering them."))
		return false
	end
	if state.outgoing or (state.lastRequest and now - state.lastRequest < 15) then
		self:Print(L("Please wait before sending another join request."))
		return false
	end
	local request =
		{ target = target, id = self:BuildChannelRequestId("join"), created = now, expires = now + LIFETIME }
	state.outgoing, state.lastRequest = request, now
	if not self:SendPartyJoinMessage(target, request.id, "request") then
		if state.outgoing == request then
			state.outgoing = nil
		end
		self:Print(L("Unable to send join request."))
		return false
	end
	self:Print(L("Join request sent to ") .. target .. ".")
	return true
end

function QT:CanAcceptPartyJoin(sender)
	if
		not Allowed(self)
		or not sender
		or self:IsSelfSender(sender)
		or self:IsIgnoredPlayerName(sender)
		or self:IsGroupedSender(sender)
	then
		return false
	end
	local grouped, invite, count = ReadInfo(self)
	if grouped ~= true or not invite then
		return false
	end
	local state = self:GetPartyJoinState()
	-- Reserve outstanding invite slots until the player joins or the invite ages out.
	return not state.reservations[sender] and math.max(1, count) + Count(state.reservations) < 5
end

function QT:IsPartyJoinAutoApproved(sender)
	if self:GetOption("autoInviteWhileLFG") == true and self:GetOption("lookingForQuestPartners") == true then
		return true
	end
	if self:GetOption("autoInviteFriends") ~= true or type(self.API.IsPartyJoinFriend) ~= "function" then
		return false
	end
	local ok, friend = pcall(self.API.IsPartyJoinFriend, sender)
	return ok and self:CanAccessValue(friend) and friend == true
end

function QT:FinishPartyJoin(request, status)
	local state = rawget(self, "partyJoinState")
	if not request or not state or state.incoming[request.sender] ~= request then
		return false
	end
	state.incoming[request.sender] = nil
	self:SendPartyJoinMessage(request.sender, request.id, status)
	self:QueuePartyJoinPrompt()
	return true
end

function QT:ConfirmPartyJoin(request, friends, lfg, automatic)
	local state = rawget(self, "partyJoinState")
	if not request or not state or state.incoming[request.sender] ~= request then
		return false
	end
	if
		Now(self) >= request.expires
		or Now(self) < request.created
		or request.profile ~= Profile(self)
		or request.roster ~= self.partyRosterFingerprint
		or not self:CanAcceptPartyJoin(request.sender)
	then
		self:FinishPartyJoin(request, "unavailable")
		return false
	end
	if automatic and not self:IsPartyJoinAutoApproved(request.sender) then
		return false
	end
	local ok, sent = pcall(self.API.InviteUnit, request.sender)
	if not ok or sent ~= true then
		if not automatic then
			self:FinishPartyJoin(request, "unavailable")
		end
		return false
	end
	state.reservations[request.sender] = Now(self) + LIFETIME
	if not automatic then
		self:SetOption("autoInviteFriends", friends == true)
		self:SetOption("autoInviteWhileLFG", lfg == true)
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
	end
	self:FinishPartyJoin(request, "sent")
	return true
end

function QT:HandlePartyJoinMessage(data, sender)
	if not self.isEnabled or type(data) ~= "table" then
		return false
	end
	sender = Name(self, sender)
	local id, target, status = data.requestId, Name(self, data.targetName), data.status
	local leader = data.leader and Name(self, data.leader)
	if status == "redirect" and not leader then
		return false
	end
	if
		not sender
		or type(id) ~= "string"
		or #id > 80
		or not id:match("^[%w%-]+$")
		or not STATUS[status]
		or self:IsSelfSender(sender)
		or self:IsIgnoredPlayerName(sender)
		or not target
	then
		return false
	end
	if target ~= Name(self, self:GetPlayerFullName()) then
		return false
	end
	self:RecordQTPlayerPresence(sender, true)
	self:PrunePartyJoin()
	local state, now = self:GetPartyJoinState(), Now(self)
	if status ~= "request" then
		local request = state.outgoing
		if not request or request.target ~= sender or request.id ~= id then
			return false
		end
		if status == "redirect" then
			-- Only the member we contacted can redirect this live request, once.
			-- Send as ourselves: the leader never trusts a relayed requester name.
			if
				not Allowed(self)
				or request.redirected
				or request.pending
				or leader == sender
				or self:IsSelfSender(leader)
				or self:IsIgnoredPlayerName(leader)
			then
				return false
			end
			self:CancelCommRequest(id, "redirect")
			request.redirected, request.origin, request.target = true, sender, leader
			self:Print(L("Join request forwarded to party leader: ") .. leader .. ".")
			if not self:SendPartyJoinMessage(leader, id, "request") then
				if state.outgoing == request then
					state.outgoing = nil
				end
				self:Print(L("Unable to send join request."))
				return false
			end
			return true
		elseif status == "pending" then
			if request.pending then
				return false
			end
			request.pending = true
			self:Print(L("Join request: awaiting confirmation."))
		else
			state.outgoing = nil
			self:CancelCommRequest(id, "complete")
			if status == "announced" then
				self:Print(L("Join request sent to party chat. The leader must invite you manually."))
			elseif status == "sent" then
				self:Print(L("Invitation attempted. Accept WoW's party invitation to join."))
			elseif status == "declined" then
				self:Print(L("Join request declined."))
			elseif status == "expired" then
				self:Print(L("Join request expired."))
			else
				self:Print(L("This player cannot currently invite you."))
			end
		end
		return true
	end
	local key = sender .. ":" .. id
	if state.seen[key] or state.incoming[sender] or Count(state.seen) >= 128 then
		return false
	end
	-- Globally bound prompts/replies/native attempts even if many senders arrive.
	if not state.windowAt or now < state.windowAt or now - state.windowAt >= 60 then
		state.windowAt, state.windowCount = now, 0
	end
	if state.windowCount >= 10 then
		return false
	end
	for previous, at in pairs(state.seen) do
		if previous:sub(1, #sender + 1) == sender .. ":" and now - at < 15 then
			return false
		end
	end
	state.seen[key], state.windowCount = now, state.windowCount + 1
	if not self:CanAcceptPartyJoin(sender) or Count(state.incoming) >= 10 then
		local leader = not self:IsGroupedSender(sender) and self:GetPartyJoinRelayTarget()
		if leader and self:SendPartyJoinMessage(sender, id, "redirect", leader) then
			return true
		end
		if self:AnnouncePartyJoinRequest(sender) then
			self:SendPartyJoinMessage(sender, id, "announced")
			return true
		end
		self:SendPartyJoinMessage(sender, id, "unavailable")
		return false
	end
	local request = {
		sender = sender,
		id = id,
		created = now,
		expires = now + LIFETIME,
		roster = self.partyRosterFingerprint,
		profile = Profile(self),
	}
	state.incoming[sender] = request
	if self:IsPartyJoinAutoApproved(sender) and self:ConfirmPartyJoin(request, false, false, true) then
		return true
	end
	-- A failed immediate auto-invite becomes manual consent, never an automatic retry.
	if state.incoming[sender] ~= request then
		return false
	end
	self:SendPartyJoinMessage(sender, id, "pending")
	self:QueuePartyJoinPrompt()
	return true
end

function QT:GetNextPartyJoinRequest()
	local state, nextRequest = rawget(self, "partyJoinState"), nil
	for _, request in pairs(state and state.incoming or {}) do
		if
			Now(self) < request.expires
			and not self:IsIgnoredPlayerName(request.sender)
			and not self:IsGroupedSender(request.sender)
			and (
				not nextRequest
				or request.created < nextRequest.created
				or (request.created == nextRequest.created and request.sender < nextRequest.sender)
			)
		then
			nextRequest = request
		end
	end
	return nextRequest
end

function QT:QueuePartyJoinPrompt()
	self:HideRetiredPartyRequestPrompt(
		rawget(self, "partyJoinPrompt"),
		self.isEnabled and self:GetNextPartyJoinRequest() or nil
	)
	if not rawget(self, "partyJoinPrompt") and not self:GetNextPartyJoinRequest() then
		return
	end
	self:ScheduleDeferredWork("foreign_frame_mutation", "party_join_prompt", function()
		self:RenderPartyJoinPrompt()
	end, 0, "party join prompt")
end
