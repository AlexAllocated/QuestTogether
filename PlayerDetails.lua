-- On-demand tooltip metadata. Requests and bounded replies share the ordinary
-- send budget; hovering never broadcasts or starts another heartbeat.
local QT = _G.QuestTogether
local TTL, COOLDOWN, LIMIT = 15, 30, 128
local ALLOWED = { QTVR = true, QTPG = true, QJST = true, QTLF = true, QTLQ = true, QTCI = true, QTHI = true }
local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end
local function Fresh(now, at, age)
	return at and now >= at and now - at < age
end
local function Enabled(a)
	return a.isEnabled
		and not a.isLoggingOut
		and rawget(a, "geographicCommsState") ~= nil
		and not a:IsRuntimeRestricted()
		and not a:IsRuntimeRestrictionTypeActive("chat")
end
local function State(a)
	local s = rawget(a, "playerDetailsState")
	if not s then
		s = { attempts = {}, pending = {}, replies = {}, identities = {}, sequence = 0 }
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
local function Send(a, name, wire)
	return a:QueueGeographicWire(wire, "hover player details", { distribution = "WHISPER", target = name }, false)
end

function QT:RequestPlayerDetails(sender)
	if not Enabled(self) then
		return false
	end
	local name = Name(self, sender)
	if not name then
		return false
	end
	local locations = rawget(self, "playerLocationState")
	local cached = locations and locations.peers[name]
	if
		not self:IsKnownQTPlayer(name)
		and not (cached and cached.mask ~= 0 and Fresh(Now(self), cached.receivedAt, cached.lifetime or 120))
	then
		return false
	end
	local s, now = State(self), Now(self)
	local attempt = s.attempts[name]
	local stats = self:GetPlayerTooltipStats(name)
	local visuals = rawget(self, "partyVisualState")
	local party = visuals and visuals.peers[name]
	local presence, streams, joins =
		rawget(self, "qtPlayerPresenceState"), rawget(self, "nearbyStreamState"), rawget(self, "partyJoinState")
	local function Current(record)
		return record
			and Fresh(now, record.sampledAt or record.receivedAt or record.at, COOLDOWN)
			and Fresh(now, record.receivedAt or record.at, record.lifetime or COOLDOWN)
	end
	if
		Current(stats)
		and (stats.partySize == 0 or Current(party))
		and Current(presence and presence.questPartners and presence.questPartners[name])
		and Current(presence and presence.partnerQuests and presence.partnerQuests[name])
		and Current(streams and streams.capabilities[name])
		and Current(joins and joins.peers[name])
		and Current(s.identities[name])
	then
		return false
	end

	-- Unknown/old peers receive one harmless probe, then a longer failure cooldown.
	if attempt and Fresh(now, attempt.at, attempt.success and COOLDOWN or 120) then
		return false
	end
	if Fresh(now, s.lastRequest, 2) then
		return false
	end
	local count = 0
	for peer, pending in pairs(s.pending) do
		if not Fresh(now, pending.at, TTL) then
			s.pending[peer] = nil
		else
			count = count + 1
		end
	end
	if count >= 8 then
		return false
	end
	s.sequence = s.sequence % 1000000 + 1
	local id = self.geographicCommsState.session .. "-" .. s.sequence
	s.pending[name] = { id = id, at = now, parts = {} }
	s.attempts[name], s.lastRequest = { at = now }, now
	Bound(s.attempts)
	if not Send(self, name, "QTHQ|1," .. id) then
		s.pending[name] = nil
		return false
	end
	return true
end

function QT:BuildPlayerDetailsPackets()
	if not Enabled(self) then
		return {}
	end
	local entries, now = {}, Now(self)
	local function Add(command, payload)
		if payload then
			entries[command] = { wire = command .. "|" .. payload, at = now }
		end
	end
	Add("QTHI", self:BuildPlayerDetailsIdentityPayload())
	local version = self:GetAddonVersion()
	if self:ParseAddonVersion(version) then
		local size = self:GetLocalPartySize()
		local count = self:GetMonitoredQuestCount()
		Add(
			"QTVR",
			"2," .. version .. "," .. (count and tostring(count) or "") .. "," .. (size and tostring(size) or "")
		)
	end
	local partyPayload, party = self:BuildPartyVisualMetadataPayload()
	Add("QTPG", partyPayload)
	if party and party.size > 1 then
		local visuals = self:GetPartyVisualState()
		visuals.advertisedGroup, visuals.lastGroupAdvertisedAt = true, now
	end
	Add("QJST", self:BuildPartyJoinMetadataPayload())
	local presence = self:GetQTPlayerPresenceState()
	local looking = self:GetOption("lookingForQuestPartners") == true
	Add("QTLF", self:BuildQuestPartnerStatusPayload(presence, looking))
	local questPayload, questID = self:BuildQuestPartnerQuestPayload(presence, looking)
	Add("QTLQ", questPayload)
	-- Direct publication also needs future withdrawals on normal routes.
	if looking then
		presence.lastPartnerOnAt = now
	end
	if questID then
		presence.lastPartnerQuestOnAt = now
	end
	local raceID = self.API.GetPlayerRaceID and self:SafeToNumber(self.API.GetPlayerRaceID()) or 0
	raceID = raceID and raceID >= 0 and raceID <= 100000 and raceID == math.floor(raceID) and raceID or 0
	local streams = self:CanPublishPlayerLocation() and self:GetOption("showPlayerLocations") == true
	Add("QTCI", "1," .. (streams and "1" or "0") .. "," .. raceID .. ",1")
	-- Existing session/sequence ordering prevents delayed public heartbeats from
	-- replacing a newer direct reply. No LOC is included, even with sharing on.
	return self:BuildGeographicSnapshots(false, entries)
end

-- Validate the complete response before dispatching any metadata. Fragments
-- are byte slices (possibly inside UTF-8); only assembled strings are decoded.
local function DecodePackets(text)
	local packets = {}
	while text ~= "" do
		local length, start = text:match("^(%d+):()")
		length = tonumber(length)
		if not length or length < 6 or length > 255 or length > #text - start + 1 then
			return nil
		end
		local packet = text:sub(start, start + length - 1)
		local rest = packet:match("^QTB1|1,%d+,%d+%-%d+,%d+;(.*)$")
		if not rest or rest == "" then
			return nil
		end
		while rest ~= "" do
			local age, size, offset = rest:match("^(%d+),(%d+):()")
			age, size = tonumber(age), tonumber(size)
			if not age or age ~= 0 or not size or size < 6 or size > #rest - offset + 1 then
				return nil
			end
			local wire = rest:sub(offset, offset + size - 1)
			if not ALLOWED[wire:match("^([^|]+)|")] then
				return nil
			end
			rest = rest:sub(offset + size)
		end
		packets[#packets + 1] = packet
		if #packets > 8 then
			return nil
		end
		text = text:sub(start + length)
	end
	return #packets > 0 and packets or nil
end

function QT:HandlePlayerDetailsMessage(command, payload, sender)
	if not Enabled(self) or not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 250 then
		return false
	end
	local name = Name(self, sender)
	if not name then
		return false
	end
	local s, now = State(self), Now(self)
	if command == "QTHQ" then
		local id = payload:match("^1,(%d+%-%d+%-%d+)$")
		if
			not id
			or #id > 60
			or Fresh(now, s.lastReply, 5)
			or (s.replies[name] and Fresh(now, s.replies[name].at, COOLDOWN))
		then
			return false
		end
		s.lastReply = now
		s.replies[name] =
			{ id = id, at = now, sharing = self:CanPublishPlayerLocation(), roster = self.partyRosterFingerprint }
		Bound(s.replies)
		local packets, text = self:BuildPlayerDetailsPackets(), ""
		for _, packet in ipairs(packets) do
			text = text .. #packet .. ":" .. packet
		end
		local count = math.ceil(#text / 175)
		if count < 1 or count > 8 then
			return false
		end
		self:RecordQTPlayerPresence(name, true)
		for index = 1, count do
			if
				not Send(
					self,
					name,
					"QTHD|1,"
						.. id
						.. ","
						.. index
						.. ","
						.. count
						.. ";"
						.. text:sub((index - 1) * 175 + 1, index * 175)
				)
			then
				return false
			end
		end
		return true
	elseif command == "QTHD" then
		local id, index, count, part = payload:match("^1,([%d%-]+),(%d+),(%d+);(.+)$")
		index, count = tonumber(index), tonumber(count)
		local pending = s.pending[name]
		if
			not id
			or #id > 60
			or not index
			or not count
			or count < 1
			or count > 8
			or index < 1
			or index > count
			or #part > 175
			or not pending
			or pending.id ~= id
			or not Fresh(now, pending.at, TTL)
			or (pending.count and pending.count ~= count)
			or pending.parts[index]
		then
			return false
		end
		pending.count, pending.parts[index] = count, part
		for i = 1, count do
			if not pending.parts[i] then
				return true
			end
		end
		s.pending[name] = nil
		local packets = DecodePackets(table.concat(pending.parts))
		if not packets then
			return false
		end
		for _, packet in ipairs(packets) do
			if not self:HandleGeographicSnapshot(packet:sub(6), name) then
				return false
			end
		end
		s.attempts[name] = { at = now, success = true }
		Bound(s.attempts)
		self:RememberDirectCommPeer(name, true)
		-- Owned tooltips already repaint at their normal cadence, including the
		-- follow-up roster request. Never reopen a tooltip after hover ended.
		return true
	end
	return false
end

function QT:IsPlayerDetailsQueuedWireCurrent(wire, target)
	local command, id = wire:match("^(QTH[QD])|1,([%d%-]+)")
	if not command then
		return true
	end
	if not Enabled(self) then
		return false
	end
	local s, now = rawget(self, "playerDetailsState"), Now(self)
	local record = s and (command == "QTHQ" and s.pending[target] or command == "QTHD" and s.replies[target])
	return record
			and record.id == id
			and Fresh(now, record.at, TTL)
			and (command ~= "QTHD" or (record.roster == self.partyRosterFingerprint and (not record.sharing or self:CanPublishPlayerLocation())))
		or false
end

-- Identity is public character information, independent from location consent.
-- Keep it separate from LOC so a query cannot invent or renew a map position.
function QT:BuildPlayerDetailsIdentityPayload()
	local className, classFile = self.API.UnitClass("player")
	local race = self.API.UnitRace("player")
	local level = self:SafeToNumber(self.API.UnitLevel("player"))
	local faction = self:SafeToString(self.API.GetFaction(), "")
	classFile = self:SafeTrimString(classFile, "")
	if
		not classFile:match("^[A-Z]+$")
		or #classFile > 24
		or not level
		or level < 1
		or level > 1000
		or level ~= math.floor(level)
		or (faction ~= "Alliance" and faction ~= "Horde" and faction ~= "Neutral")
	then
		return nil
	end
	local function Label(value)
		value = self:SafeTrimString(value, ""):gsub("[%c|]", "")
		return #value <= 80 and self:EscapePayload(value) or ""
	end
	local payload = table.concat({ "1", classFile, level, faction, Label(race), Label(className) }, ",")
	if #payload > 160 then
		payload = table.concat({ "1", classFile, level, faction, Label(race), "" }, ",")
	end
	if #payload > 160 then
		payload = table.concat({ "1", classFile, level, faction, "", "" }, ",")
	end
	return payload
end

function QT:HandlePlayerDetailsIdentity(payload, sender)
	if not Enabled(self) or type(payload) ~= "string" or #payload > 240 then
		return false
	end
	local classFile, level, faction, race, className = payload:match("^1,([A-Z]+),(%d+),([^,]+),([^,]*),([^,]*)$")
	level = tonumber(level)
	local name = Name(self, sender)
	if
		not name
		or not classFile
		or #classFile > 24
		or not level
		or level < 1
		or level > 1000
		or (faction ~= "Alliance" and faction ~= "Horde" and faction ~= "Neutral")
	then
		return false
	end
	race, className = self:UnescapePayload(race), self:UnescapePayload(className)
	if #race > 80 or #className > 80 or race:find("[%c|]") or className:find("[%c|]") then
		return false
	end
	local s, now = State(self), Now(self)
	s.identities[name] = {
		classFile = classFile,
		level = level,
		faction = faction,
		race = race,
		className = className,
		receivedAt = now,
		at = now,
	}
	Bound(s.identities)
	return true
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
