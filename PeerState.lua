-- Common ordering for public metadata, requested snapshots and departures.
-- This contains only addon-owned primitive timestamps, never private locations.
local QT = _G.QuestTogether
local TTL, LIMIT = 600, 1024
local function Now(a)
	return a:SafeToNumber(a.API.GetTime())
end
local function State(a)
	local state = rawget(a, "peerSnapshotState")
	if not state then
		state = { peers = {}, count = 0 }
		a.peerSnapshotState = state
	end
	return state
end
local function Record(a, name, create)
	local state, now = State(a), Now(a)
	local row = state.peers[name]
	if row and (not now or now < row.at or now - row.at >= TTL) then
		state.peers[name], state.count, row = nil, state.count - 1, nil
	end
	if not row and create and now then
		if state.count >= LIMIT then
			local oldest, at
			for key, peer in pairs(state.peers) do
				if not at or peer.at < at then
					oldest, at = key, peer.at
				end
			end
			if oldest then
				state.peers[oldest] = nil
				state.count = state.count - 1
			end
		end
		row = { at = now, fields = {} }
		state.peers[name] = row
		state.count = state.count + 1
	end
	return row, now
end

-- Stamped protocols share epoch ownership. A parsed packet is not evidence of
-- a new session until one of its fields has passed freshness/content validation.
function QT:CanAcceptPeerEpoch(name, session, stamp)
	local row = Record(self, name, false)
	local epoch = row and row.epoch
	if not epoch or epoch.session == session then
		return true
	end
	if epoch.retired[session] then
		return false
	end
	-- A legacy unstamped packet or a same-second tie cannot establish which
	-- unknown epoch is newer. A subsequent stamped publication resolves it.
	if epoch.stamp and epoch.stamp > 0 and (not stamp or stamp <= epoch.stamp) then
		return false
	end
	return true
end

function QT:RecordPeerEpoch(name, session, stamp)
	if not self:CanAcceptPeerEpoch(name, session, stamp) then
		return false
	end
	local row, now = Record(self, name, true)
	if not row then
		return false
	end
	local epoch = row.epoch
	if not epoch then
		epoch = { session = session, retired = {}, order = {} }
		row.epoch = epoch
	end
	if epoch.session ~= session then
		epoch.retired[epoch.session] = true
		epoch.order[#epoch.order + 1] = epoch.session
		if #epoch.order > 8 then
			epoch.retired[table.remove(epoch.order, 1)] = nil
		end
		epoch.session, epoch.stamp = session, nil
	end
	if stamp and stamp > 0 then
		epoch.stamp = math.max(epoch.stamp or 0, stamp)
	end
	row.at = now
	return true
end

function QT:CanAcceptPeerUpdate(name, field, sampledAt, session, sequence)
	local row, now = Record(self, name, false)
	if
		not now
		or not sampledAt
		or sampledAt > now + 1
		or now - sampledAt >= TTL
		or self:IsIgnoredPlayerName(name)
		or self:IsSelfSender(name)
	then
		return false
	end
	if not row then
		return true
	end
	local departed = row.departed
	if departed then
		if session and departed.session == session then
			if not sequence or sequence <= departed.sequence then
				return false
			end
		elseif sampledAt <= departed.sampledAt and (not session or sampledAt < departed.sampledAt) then
			return false
		end
	end
	local previous = field and row.fields[field]
	if previous then
		-- Envelope ages are whole seconds while receipt clocks are fractional.
		-- For two ordered public samples, a newer sequence resolves that rounding
		-- ambiguity. A manual refresh has no sequence and keeps strict ordering.
		local orderedNewer = session
			and previous.session == session
			and sequence
			and previous.sequence
			and sequence > previous.sequence
			and not previous.manual
		if sampledAt < previous.sampledAt and not (orderedNewer and previous.sampledAt - sampledAt < 1) then
			return false
		end
		if
			session
			and previous.session == session
			and sequence
			and previous.sequence
			and sequence <= previous.sequence
		then
			return false
		end
	end
	return true
end

function QT:RecordPeerUpdate(name, field, sampledAt, session, sequence, establishesPresence)
	if not self:CanAcceptPeerUpdate(name, field, sampledAt, session, sequence) then
		return false
	end
	local row, now = Record(self, name, true)
	local previous = row.fields[field]
	row.fields[field] = {
		sampledAt = sampledAt,
		session = session or (previous and previous.session),
		sequence = sequence or (previous and previous.sequence),
		manual = session == nil,
	}
	row.at, row.latestSampledAt = now, math.max(row.latestSampledAt or sampledAt, sampledAt)
	if session and sequence then
		if establishesPresence ~= false then
			row.activeAfterDeparture = true
		end
		-- Inner LOC/QTLF stream counters are not comparable to QTB1 envelopes.
		if session:match("^%d+%-%d+$") then
			if row.session ~= session then
				row.session, row.sequence = session, sequence
			else
				row.sequence = math.max(row.sequence or 0, sequence)
			end
		end
	end
	return true
end

-- Explicit, addon-owned observation metadata travels with the decoded field.
-- Producers retain distinct freshness policies; transport never edits payload stores.
function QT:CreatePeerObservation(name, field, options)
	options = options or {}
	local now = Now(self)
	local age = self:SafeToNumber(options.age) or 0
	local lifetime = self:SafeToNumber(options.lifetime) or TTL
	if not now or age < 0 or age >= lifetime then
		return nil
	end
	return {
		name = name,
		field = field,
		source = options.source or "legacy",
		receivedAt = now,
		sampledAt = now - age,
		expiresAt = now - age + lifetime,
		session = options.session,
		sequence = options.sequence,
		stamp = options.stamp,
		manual = options.source == "diagnostic",
	}
end

function QT:ResolvePeerObservation(name, field, value, source, legacySession, legacySequence, lifetime)
	if type(value) == "table" then
		if value.name ~= name or value.field ~= field then
			return nil
		end
		return value
	end
	return self:CreatePeerObservation(name, field, {
		source = source and "snapshot" or (value ~= nil and "diagnostic" or "legacy"),
		age = value or 0,
		lifetime = value ~= nil and TTL or lifetime,
		session = source and source.session or legacySession,
		sequence = source and source.sequence or legacySequence,
	})
end

function QT:CanAcceptPeerObservation(observation)
	local now = Now(self)
	if
		type(observation) ~= "table"
		or not now
		or type(observation.receivedAt) ~= "number"
		or type(observation.sampledAt) ~= "number"
		or type(observation.expiresAt) ~= "number"
		or observation.receivedAt > now
		or observation.sampledAt > observation.receivedAt
		or observation.expiresAt <= now
	then
		return false
	end
	return observation
			and observation.name
			and observation.field
			and (observation.stamp == nil or self:CanAcceptPeerEpoch(
				observation.name,
				observation.session,
				observation.stamp
			))
			and self:CanAcceptPeerUpdate(
				observation.name,
				observation.field,
				observation.sampledAt,
				observation.session,
				observation.sequence
			)
		or false
end

function QT:CommitPeerObservation(observation, record, establishesPresence)
	if not self:CanAcceptPeerObservation(observation) then
		return false
	end
	local name = observation.name
	if establishesPresence and not self:RecordQTPlayerPresence(name, true, observation) then
		return false
	end
	if
		not self:RecordPeerUpdate(
			name,
			observation.field,
			observation.sampledAt,
			observation.session,
			observation.sequence,
			establishesPresence == true
		)
	then
		return false
	end
	if observation.stamp ~= nil then
		self:RecordPeerEpoch(name, observation.session, observation.stamp)
	end
	if record then
		record.sampledAt, record.receivedAt = observation.sampledAt, observation.receivedAt
		record.lifetime, record.expiresAt = observation.expiresAt - observation.receivedAt, observation.expiresAt
		record.observationSource, record.manualSnapshot = observation.source, observation.manual
	end
	return true
end

function QT:CanRecordPeerPresence(name, observation)
	local row = Record(self, name, false)
	if not row or not row.departed or row.activeAfterDeparture then
		return true
	end
	return observation
			and observation.name == name
			and self:CanAcceptPeerUpdate(name, nil, observation.sampledAt, observation.session, observation.sequence)
		or false
end

function QT:RecordPeerPresenceFromSnapshot(name, sampledAt, session, sequence)
	local now = Now(self)
	if not now or not sampledAt then
		return false
	end
	local observation = { name = name, sampledAt = sampledAt, session = session, sequence = sequence }
	if not self:CanAcceptPeerUpdate(name, nil, sampledAt, session, sequence) then
		return false
	end
	local accepted = self:RecordQTPlayerPresence(name, true, observation)
	if accepted then
		local row = Record(self, name, true)
		row.activeAfterDeparture = true
	end
	return accepted
end

function QT:RecordLegacyPeerPresence(name, active)
	local now = Now(self)
	if not now then
		return false
	end
	local row = Record(self, name, false)
	if not active then
		if row and row.activeAfterDeparture and row.departed and not row.departed.session then
			row.departed = nil
		end
		return self:RecordPeerDeparture(name, now)
	end
	-- Legacy has no timestamp/counter. Explicit On is its reentry witness;
	-- it cannot override a sequenced modern departure with a delayed packet.
	if row and row.departed and row.departed.session then
		return self:RecordQTPlayerPresence(name, true)
	end
	if row then
		row.departed = nil
	end
	return self:RecordPeerPresenceFromSnapshot(name, now, "QTPR:legacy", 1)
end

function QT:RecordPeerDeparture(name, sampledAt, session, sequence)
	if not self:CanAcceptPeerUpdate(name, "QTPR", sampledAt, session, sequence) then
		return false
	end
	local row, now = Record(self, name, true)
	local orderedNewer = session and row.session == session and sequence and sequence >= (row.sequence or 0)
	if
		(
			row.latestSampledAt
			and sampledAt < row.latestSampledAt
			and not (orderedNewer and row.latestSampledAt - sampledAt < 1)
		) or (session and row.session == session and sequence and sequence < (row.sequence or 0))
	then
		return false
	end
	row.at = now
	row.activeAfterDeparture = false
	row.departed = { sampledAt = sampledAt, session = session, sequence = sequence or 0 }
	local presence = rawget(self, "qtPlayerPresenceState")
	if presence then
		local status = presence.questPartners and presence.questPartners[name]
		if status then
			-- Retain the real inner stream counter to reject delayed old On copies.
			status.looking, status.receivedAt, status.sampledAt, status.lifetime = false, now, sampledAt, TTL
		end
		if presence.partnerQuests then
			presence.partnerQuests[name] = nil
		end
	end
	self:RecordQTPlayerPresence(name, false)
	return true
end

function QT:MigratePlayerMapVisibility(profile)
	if type(profile) ~= "table" then
		return
	end
	if profile.mapPartyOnly == true then
		profile.showPlayerLocations = false
	end
	profile.mapPartyOnly, profile.mapAlwaysShowParty = nil, nil
end

function QT:GetPlayerMapVisibilityChoice()
	if self:GetOption("showPlayerLocations") ~= true or self:GetOption("mapPartyOnly") == true then
		return 3
	end
	return self:GetOption("onlyShowQuestPartners") == true and 2 or 1
end

-- Blizzard owns our party's map indicators. Every QT location consumer uses
-- this same rule, including temporary developer dots and nearby streams.
function QT:ShouldShowPlayerLocation(name)
	if
		not self.isEnabled
		or self.isLoggingOut
		or self:GetOption("showPlayerLocations") ~= true
		or self:GetOption("mapPartyOnly") == true
		or self:IsSelfSender(name)
		or self:IsGroupedSender(name)
		or self:IsIgnoredPlayerName(name)
	then
		return false
	end
	return self:GetOption("onlyShowQuestPartners") ~= true or self:IsPlayerLookingForQuestPartners(name)
end

function QT:ResetPeerSnapshots()
	self.peerSnapshotState = nil
end
