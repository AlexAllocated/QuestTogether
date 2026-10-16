-- On-demand public metadata. Correlation, fragmentation and delivery are owned
-- by the communications coordinator; this domain owns interest and cooldowns.
local QT = _G.QuestTogether
local TTL, COOLDOWN, LIMIT, HOVER_STALL = 15, 30, 128, 90
local TOPICS = { QTVR = true, QTPG = true, QJST = true, QTLF = true, QTLQ = true, QTCI = true, QTHI = true }
local FIELDS = { "QTVR", "QTPG", "QJST", "QTLF", "QTLQ", "QTCI", "QTHI" }
local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end
local function Fresh(now, at, age)
	return at and now >= at and now - at < age
end
local function PendingFresh(a, pending)
	local now = Now(a)
	local progress = pending.hover and a:GetCommunicationRequestProgress(pending.id)
	-- Leave two ordinary status-probe intervals plus a delivery allowance. A
	-- responding/advancing transfer keeps its original identity and 600s cap;
	-- an abandoned partial hover snapshot must not block fresh metadata that long.
	if progress and progress.lastProgressAt and now - progress.lastProgressAt >= HOVER_STALL then return false end
	local deadline = a:GetCommunicationRequestDeadline(pending.id) or (pending.at + TTL)
	return now >= pending.at and now < deadline
end
local function Enabled(a)
	return a.isEnabled
		and not a.isLoggingOut
		and not a:IsRuntimeRestricted()
		and not a:IsRuntimeRestrictionTypeActive("chat")
end
local function State(a)
	local s = rawget(a, "playerDetailsState")
	if not s then
		s = { attempts = {}, pending = {}, replies = {}, identities = {}, interests = {} }
		a.playerDetailsState = s
	end
	return s
end
local function Name(a, name)
	name = a:SafeTrimString(name, "")
	if name == "" or #name > 120 or name:find("[%c|,]") then
		return nil
	end
	name = a:NormalizeMemberName(name)
	if name and not a:IsSelfSender(name) and not a:IsIgnoredPlayerName(name) then
		return name
	end
end
local function Bound(t)
	local count, oldest, at = 0
	for key, value in pairs(t) do
		count = count + 1
		if not at or value.at < at then
			oldest, at = key, value.at
		end
	end
	if count > LIMIT then
		t[oldest] = nil
	end
end
local function CancelPending(a, pending, reason)
	if not pending then
		return
	end
	a:CancelCommRequest(pending.id, reason)
	a:CancelCommunicationOwner(pending, reason)
end
local function Route(name)
	return { { distribution = "WHISPER", target = name } }
end

local function InterestCurrent(a, interest)
	if not Enabled(a) or not Name(a, interest.name) then
		return false
	end
	local ok, current = pcall(interest.isCurrent)
	return ok and current == true
end

function QT:HasPlayerDetailsInterest(name)
	local s = rawget(self, "playerDetailsState")
	for _, interest in pairs(s and s.interests or {}) do
		if interest.name == name and InterestCurrent(self, interest) then
			return true
		end
	end
	return false
end

function QT:ClearPlayerDetailsInterest(owner)
	local s = rawget(self, "playerDetailsState")
	local interest = s and s.interests and s.interests[owner]
	if not interest then
		return
	end
	s.interests[owner] = nil
	if self:HasPlayerDetailsInterest(interest.name) then
		return
	end
	local pending = s.pending[interest.name]
	if pending and pending.hover then
		s.pending[interest.name] = nil
		s.attempts[interest.name] = { at = Now(self), retryAfter = 2 }
		Bound(s.attempts)
		CancelPending(self, pending, "cancelled")
	end
	self:CancelPartyVisualRosterInterest(interest.name)
end

local function RefreshInterest(a, name)
	a:RequestPlayerDetails(name, true)
	a:RequestPartyVisualRoster(name, true)
end

-- Presentation owns only the interest. The shared runtime owns retries and
-- renewal; neither rebuilding a tooltip model nor an incoming response sends.
function QT:SetPlayerDetailsInterest(owner, sender, isCurrent)
	local name = Name(self, sender)
	if type(owner) ~= "table" or type(isCurrent) ~= "function" or not name or not Enabled(self) then
		if type(owner) == "table" then
			self:ClearPlayerDetailsInterest(owner)
		end
		return false
	end
	local s = State(self)
	s.interests = s.interests or {}
	local previous = s.interests[owner]
	if previous and previous.name == name then
		previous.isCurrent = isCurrent
		return true
	end
	self:ClearPlayerDetailsInterest(owner)
	local count = 0
	for _ in pairs(s.interests) do
		count = count + 1
	end
	if count >= 8 then
		return false
	end
	local interest = { name = name, isCurrent = isCurrent }
	if not InterestCurrent(self, interest) then
		return false
	end
	s.interests[owner] = interest
	RefreshInterest(self, name)
	return true
end

function QT:UpdatePlayerDetailsInterests()
	local s = rawget(self, "playerDetailsState")
	local visited = {}
	for owner, interest in pairs(s and s.interests or {}) do
		if not InterestCurrent(self, interest) then
			self:ClearPlayerDetailsInterest(owner)
		elseif not visited[interest.name] then
			visited[interest.name] = true
			RefreshInterest(self, interest.name)
		end
	end
end

function QT:RequestPlayerDetails(sender, hover)
	if not Enabled(self) then
		return false
	end
	local name = Name(self, sender)
	if not name or not (self:IsKnownQTPlayer(name) or self:GetFreshPlayerLocation(name)) then
		return false
	end
	if self:ArePeerFieldsFresh(name, FIELDS, COOLDOWN) then
		return false
	end
	local s, now = State(self), Now(self)
	local attempt = s.attempts[name]
	local cooldown = attempt and (attempt.retryAfter or (attempt.success or hover) and COOLDOWN or 120)
	if attempt and Fresh(now, attempt.at, cooldown) or Fresh(now, s.lastRequest, 2) then
		return false
	end
	local count = 0
	for peer, pending in pairs(s.pending) do
		if not PendingFresh(self, pending) then
			s.pending[peer] = nil
			CancelPending(self, pending, "expired")
		else
			count = count + 1
		end
	end
	if s.pending[name] or count >= 8 then
		return false
	end
	local id = self:GetCommunicationSession() .. "-details-" .. self:NextCommunicationSequence()
	local pending = { id = id, at = now, hover = hover == true }
	s.pending[name], s.lastRequest = pending, now
	local admitted = self:Request("QTHQ", {}, Route(name), {
		owner = pending,
		requestId = id,
		responseOperations = { QTHD = true },
		expires = now + TTL,
		key = "details:request:" .. name,
		priority = "control",
		isCurrent = function()
			return rawget(self, "playerDetailsState") == s
				and s.pending[name] == pending
				and Enabled(self)
				and PendingFresh(self, pending)
				and not self:IsIgnoredPlayerName(name)
				and (not pending.hover or self:HasPlayerDetailsInterest(name))
		end,
		onComplete = function(sent)
			if rawget(self, "playerDetailsState") ~= s or s.pending[name] ~= pending then
				return
			end
			s.attempts[name] = { at = Now(self), retryAfter = not sent and 2 or nil }
			Bound(s.attempts)
			if sent then
				pending.sentAt = Now(self)
			else
				s.pending[name] = nil
				CancelPending(self, pending, "cancelled")
			end
		end,
		onResponse = function(record, responder, context)
			return self:HandlePlayerDetailsMessage("QTHD", record, responder, context)
		end,
	})
	if not admitted and s.pending[name] == pending then
		s.pending[name] = nil
		s.attempts[name] = { at = now, retryAfter = 2 }
		Bound(s.attempts)
	end
	return admitted == true
end

function QT:BuildPlayerDetailsRecords()
	if not Enabled(self) then
		return {}
	end
	return self:BuildLocalCommunicationState(TOPICS)
end

function QT:HandlePlayerDetailsMessage(command, payload, sender, context)
	if not Enabled(self) or type(payload) ~= "table" or type(context) ~= "table" then
		return false
	end
	local name = Name(self, sender)
	local id = context.requestId or payload.requestId
	if not name or type(id) ~= "string" or #id < 1 or #id > 80 then
		return false
	end
	local s, now = State(self), Now(self)
	if command == "QTHQ" then
		local previous = s.replies[name]
		-- A new hover may replace a completed reply that its previous owner left
		-- before receiving it. Keep the shared cadence and pending/duplicate fences,
		-- rather than making the new request wait for the old owner's cooldown.
		if Fresh(now, s.lastReply, 5)
			or previous and (previous.id == id or previous.pending and Fresh(now, previous.at, TTL)) then
			return false
		end
		local records, completed = self:BuildPlayerDetailsRecords()
		if #records == 0 then
			return false
		end
		local reply = {
			id = id,
			at = now,
			pending = true,
			roster = self.partyRosterFingerprint,
			looking = self:GetOption("lookingForQuestPartners") == true,
			sharing = self:CanPublishPlayerLocation(),
			showing = self:GetOption("showPlayerLocations") == true,
		}
		s.replies[name], s.lastReply = reply, now
		Bound(s.replies)
		local admitted = self:Respond("QTHD", { records = records }, Route(name), {
			owner = reply,
			requestId = id,
			key = "details:reply:" .. name,
			priority = "control",
			expires = now + 600,
			isCurrent = function()
				return rawget(self, "playerDetailsState") == s
					and s.replies[name] == reply
					and Enabled(self)
					and reply.roster == self.partyRosterFingerprint
					and reply.looking == (self:GetOption("lookingForQuestPartners") == true)
					and reply.sharing == self:CanPublishPlayerLocation()
					and reply.showing == (self:GetOption("showPlayerLocations") == true)
					and Fresh(Now(self), reply.at, 600)
					and not self:IsIgnoredPlayerName(name)
			end,
			onComplete = function(sent)
				if rawget(self, "playerDetailsState") ~= s or s.replies[name] ~= reply then
					return
				end
				if sent then
					reply.pending, reply.acceptedAt = nil, Now(self)
					if completed then
						completed(true)
					end
				else
					s.replies[name] = nil
				end
			end,
		})
		if not admitted and s.replies[name] == reply then
			s.replies[name] = nil
		end
		return admitted == true
	elseif command == "QTHD" then
		local pending, records = s.pending[name], payload.records
		if
			not pending
			or id ~= pending.id
			or not PendingFresh(self, pending)
			or type(records) ~= "table"
			or #records < 1
			or #records > #FIELDS
		then
			return false
		end
		local seen = {}
		-- A metadata request never invents coordinates or location permission.
		-- Validate the entire response before letting any topic reach its domain.
		for _, record in ipairs(records) do
			if type(record) ~= "table" or not TOPICS[record.topic] or seen[record.topic] then
				return false
			end
			seen[record.topic] = true
		end
		local accepted = self:ApplyCommunicationState(records, name, context)
		if not accepted then
			return false
		end
		s.pending[name] = nil
		CancelPending(self, pending, "complete")
		s.attempts[name] = { at = now, success = true }
		Bound(s.attempts)
		return true
	end
	return false
end

-- Identity is public character metadata, independent of location consent.
function QT:BuildPlayerDetailsIdentityPayload()
	local className, classFile = self.API.UnitClass("player")
	local race, level = self.API.UnitRace("player"), self:SafeToNumber(self.API.UnitLevel("player"))
	local faction = self:SafeToString(self.API.GetFaction(), "")
	classFile = self:SafeTrimString(classFile, "")
	if
		not classFile:match("^[A-Z]+$")
		or #classFile > 24
		or not level
		or level < 1
		or level > 1000
		or level ~= math.floor(level)
		or faction ~= "Alliance" and faction ~= "Horde" and faction ~= "Neutral"
	then
		return nil
	end
	local function Label(value)
		value = self:SafeTrimString(value, ""):gsub("[%c|]", "")
		return #value <= 80 and value or ""
	end
	return { classFile = classFile, level = level, faction = faction, race = Label(race), className = Label(className) }
end
function QT:HandlePlayerDetailsIdentity(payload, sender, observation)
	if not Enabled(self) or type(payload) ~= "table" then
		return false
	end
	local name = Name(self, sender)
	local classFile, level, faction =
		self:SafeToString(payload.classFile, ""),
		self:SafeToNumber(payload.level),
		self:SafeToString(payload.faction, "")
	if
		not name
		or not classFile:match("^[A-Z]+$")
		or #classFile > 24
		or not level
		or level < 1
		or level > 1000
		or level ~= math.floor(level)
		or faction ~= "Alliance" and faction ~= "Horde" and faction ~= "Neutral"
	then
		return false
	end
	local race, className = self:SafeToString(payload.race, ""), self:SafeToString(payload.className, "")
	if #race > 80 or #className > 80 or race:find("[%c|]") or className:find("[%c|]") then
		return false
	end
	local s, now = State(self), Now(self)
	observation = self:ResolvePeerObservation(name, "QTHI", observation)
	local record =
		{ classFile = classFile, level = level, faction = faction, race = race, className = className, at = now }
	if not self:CommitPeerObservation(observation, record, false) then
		return false
	end
	s.identities[name] = record
	Bound(s.identities)
	return true, record
end

function QT:GetPlayerDetailsTooltipRow(row)
	local s = rawget(self, "playerDetailsState")
	local info = s and s.identities[row.name]
	if not info then
		return row
	end
	local now = Now(self)
	if
		self:IsIgnoredPlayerName(row.name)
		or not Fresh(now, info.receivedAt, info.lifetime or 180)
		or (row.receivedAt and (row.sampledAt or row.receivedAt) > (info.sampledAt or info.receivedAt))
	then
		return row
	end
	local copy = {}
	for key, value in pairs(row) do
		copy[key] = value
	end
	for _, key in ipairs({ "classFile", "className", "level", "race", "faction" }) do
		if info[key] ~= "" then
			copy[key] = info[key]
		end
	end
	return copy
end

function QT:RetirePlayerDetailsPeer(name)
	local s = rawget(self, "playerDetailsState")
	if not s then
		return
	end
	local pending, reply = s.pending[name], s.replies[name]
	for owner, interest in pairs(s.interests or {}) do
		if interest.name == name then
			self:ClearPlayerDetailsInterest(owner)
		end
	end
	s.pending[name], s.attempts[name], s.replies[name], s.identities[name] = nil, nil, nil, nil
	if pending then
		CancelPending(self, pending, "cancelled")
	end
	if reply then
		self:CancelCommunicationOwner(reply, "cancelled")
	end
end
function QT:ResetPlayerDetails()
	local s = rawget(self, "playerDetailsState")
	self.playerDetailsState = nil
	if s then
		for _, pending in pairs(s.pending) do
			CancelPending(self, pending, "cancelled")
		end
		for _, reply in pairs(s.replies) do
			self:CancelCommunicationOwner(reply, "cancelled")
		end
	end
end
