-- Common ordering for public metadata, requested snapshots and departures.
-- This contains only addon-owned primitive timestamps, never private locations.
local QT = _G.QuestTogether
local TTL, LIMIT = 600, 1024
local function Now(a)
	return a:SafeToNumber(a.API.GetTime())
end
local FRESHNESS_FIELDS = {
	"at", "sampledAt", "receivedAt", "expiresAt", "lifetime", "cached", "manualSnapshot",
	"observationSource", "observationName", "observationSession", "observationSequence", "sourceSampledAt",
}

-- Views over accepted records must keep the sample's provenance. In particular,
-- comparing fractional receipt times cannot order two whole-second wire samples.
function QT:CopyPeerRecordFreshness(source, target)
	for _, field in ipairs(FRESHNESS_FIELDS) do
		target[field] = source[field]
	end
	return target
end

function QT:ComparePeerRecordSamples(left, right)
	if not left then return right and -1 or 0 end
	if not right then return 1 end
	local leftStamp, rightStamp = left.sourceSampledAt, right.sourceSampledAt
	if leftStamp and rightStamp then
		if leftStamp ~= rightStamp then return leftStamp > rightStamp and 1 or -1 end
		-- Sequence numbers are comparable only within one sender's session. An
		-- unsequenced diagnostic sample or another sender cannot break this tie.
		if left.observationName and left.observationName == right.observationName
			and left.observationSession and left.observationSession == right.observationSession
			and left.observationSequence and right.observationSequence then
			local difference = left.observationSequence - right.observationSequence
			return difference > 0 and 1 or difference < 0 and -1 or 0
		end
		return 0
	end
	local difference = (left.sampledAt or left.at or 0) - (right.sampledAt or right.at or 0)
	return difference > 0 and 1 or difference < 0 and -1 or 0
end
function QT:ComparePeerObservationToRecord(observation, record)
	return self:ComparePeerRecordSamples({
		sampledAt = observation.sampledAt, sourceSampledAt = observation.sourceSampledAt,
		observationName = observation.name, observationSession = observation.session,
		observationSequence = observation.sequence,
	}, record)
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

-- Read-only identity evidence query. A signed observation belongs only to the
-- current peer session and cannot survive a departure later than that proof.
function QT:IsPeerSessionObservationCurrent(name, session, sampledAt)
	local row = Record(self, name, false)
	return row ~= nil
		and row.epoch ~= nil
		and row.epoch.session == session
		and (not row.departed or sampledAt > row.departed.sampledAt)
end

function QT:CanAcceptPeerUpdate(name, field, sampledAt, session, sequence, sourceSampledAt)
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
		if sourceSampledAt and previous.sourceSampledAt then
			if sourceSampledAt < previous.sourceSampledAt then return false end
			if sourceSampledAt == previous.sourceSampledAt
				and not (session and session == previous.session and sequence and previous.sequence and not previous.manual) then
				-- Unsequenced diagnostic samples cannot be ordered within a source
				-- second. Keep the accepted fact until a strictly newer sample arrives.
				return false
			end
		end
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

function QT:RecordPeerUpdate(name, field, sampledAt, session, sequence, establishesPresence, sourceSampledAt)
	if not self:CanAcceptPeerUpdate(name, field, sampledAt, session, sequence, sourceSampledAt) then
		return false
	end
	local row, now = Record(self, name, true)
	local previous = row.fields[field]
	row.fields[field] = {
		sampledAt = sampledAt,
		session = session or (previous and previous.session),
		sequence = sequence or (previous and previous.sequence),
		manual = session == nil,
		sourceSampledAt = sourceSampledAt,
	}
	row.at, row.latestSampledAt = now, math.max(row.latestSampledAt or sampledAt, sampledAt)
	if session and sequence then
		if establishesPresence ~= false then
			row.activeAfterDeparture = true
		end
		-- Shared wire observations carry the same session and sequence across topics.
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
	if
		type(options) ~= "table"
		or not self:CanAccessTable(options)
		or not self:CanAccessValue(options.source)
		or type(options.source) ~= "string"
		or options.source == ""
	then
		return nil
	end
	local now = Now(self)
	local age = self:SafeToNumber(options.age) or 0
	local lifetime = self:SafeToNumber(options.lifetime) or TTL
	if not now or age < 0 or age >= lifetime then
		return nil
	end
	return {
		name = name,
		field = field,
		source = options.source,
		receivedAt = now,
		sampledAt = now - age,
		expiresAt = now - age + lifetime,
		session = options.session,
		sequence = options.sequence,
		stamp = options.stamp,
		sourceSampledAt = self:SafeToNumber(options.sourceSampledAt),
		manual = options.source == "diagnostic",
	}
end

function QT:ResolvePeerObservation(name, field, observation)
	if
		type(observation) ~= "table"
		or not self:CanAccessTable(observation)
		or not self:CanAccessValue(observation.name)
		or not self:CanAccessValue(observation.field)
		or observation.name ~= name
		or observation.field ~= field
		or not self:CanAccessValue(observation.source)
		or type(observation.source) ~= "string"
		or observation.source == ""
	then
		return nil
	end
	return observation
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
				observation.sequence,
				observation.sourceSampledAt
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
			establishesPresence == true,
			observation.sourceSampledAt
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
		record.observationName, record.observationSession = observation.name, observation.session
		record.observationSequence, record.sourceSampledAt = observation.sequence, observation.sourceSampledAt
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

-- Read admitted sample times through their owner instead of traversing feature caches.
function QT:ArePeerFieldsFresh(name, fields, maxAge)
	name = self:NormalizeMemberName(name)
	local row, now
	if name then
		row, now = Record(self, name, false)
	end
	if not row or not now then
		return false
	end
	for _, field in ipairs(fields) do
		local sample = row.fields[field]
		if
			not sample
			or now < sample.sampledAt
			or now - sample.sampledAt >= maxAge
			or not self:CanAcceptPeerUpdate(name, nil, sample.sampledAt, sample.session, sample.sequence)
		then
			return false
		end
	end
	return true
end
