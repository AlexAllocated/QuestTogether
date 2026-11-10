local L = _G.QuestTogether.Translate
-- Peer-reported release discovery. Saved state is account-wide; notification
-- suppression and broadcast pacing last only for this UI session.
local QT = _G.QuestTogether
local BROADCAST_INTERVAL, RETRY_INTERVAL = 300, 20

local function Component(text)
	if not text or #text > 6 or (#text > 1 and text:sub(1, 1) == "0") then
		return nil
	end
	return tonumber(text)
end

function QT:ParseAddonVersion(version)
	if not self:CanAccessValue(version) or type(version) ~= "string" or #version > 48 then
		return nil
	end
	local major, minor, patch, suffix = version:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
	major, minor, patch = Component(major), Component(minor), Component(patch)
	if not major or not minor or not patch then
		return nil
	end
	local stage, sequence = 2, 0
	if suffix ~= "" then
		local channel, number = suffix:match("^%-(%a+)%.(%d+)$")
		sequence = Component(number)
		if (channel ~= "alpha" and channel ~= "beta") or not sequence or sequence < 1 then
			return nil
		end
		stage = channel == "alpha" and 0 or 1
	end
	return { major, minor, patch, stage, sequence }
end

function QT:CompareAddonVersions(left, right)
	local first, second = self:ParseAddonVersion(left), self:ParseAddonVersion(right)
	if not first or not second then
		return nil
	end
	for index = 1, #first do
		if first[index] ~= second[index] then
			return first[index] > second[index] and 1 or -1
		end
	end
	return 0
end

function QT:GetAddonUpdateState()
	local state = rawget(self, "addonUpdateState")
	if not state then
		state = {}
		self.addonUpdateState = state
	end
	return state
end

function QT:GetAvailableAddonUpdate()
	local global = self.db and self.db.global
	if type(global) ~= "table" then
		return nil
	end
	local known = self:ParseAddonVersion(global.availableAddonVersion)
	if not known or known[4] ~= 2 then
		global.availableAddonVersion, global.addonUpdateAvailable = "", false
		return nil
	end
	local comparison = self:CompareAddonVersions(global.availableAddonVersion, self:GetAddonVersion())
	if comparison == nil then
		return nil
	end
	global.addonUpdateAvailable = comparison == 1
	if comparison == 1 then
		return global.availableAddonVersion
	else
		-- Installing this release (or a newer one) resolves the saved notice.
		-- Unknown local metadata cannot prove the update was installed.
		global.availableAddonVersion = ""
	end
	return nil
end

function QT:NotifyAddonUpdate()
	local version = self:GetAvailableAddonUpdate()
	if not version or not self.hasLoggedIn or self.isLoggingOut then
		return false
	end
	local state = self:GetAddonUpdateState()
	if state.noticeShown then
		return false
	end
	state.noticeShown = true
	self:Print(
		L("A newer QuestTogether version is available: ")
			.. version
			.. L(" (installed: ")
			.. self:GetAddonVersion()
			.. L("). Please update with your addon manager.")
	)
	return true
end

function QT:ObserveAddonVersion(version)
	local parsed = self:ParseAddonVersion(version)
	if not self.isEnabled or not parsed or parsed[4] ~= 2 then
		return false
	end
	local global = self.db and self.db.global
	if type(global) ~= "table" or self:CompareAddonVersions(version, self:GetAddonVersion()) ~= 1 then
		return false
	end
	local previous = self:GetAvailableAddonUpdate()
	if not previous or self:CompareAddonVersions(version, previous) == 1 then
		global.availableAddonVersion = version
	end
	global.addonUpdateAvailable = true
	self:NotifyAddonUpdate()
	return true
end

local VERSION_LIFETIME, VERSION_LIMIT, VERSION_CACHE_LIFETIME = 600, 512, 180
local function VersionNow(a)
	return a.API.GetTime and a:SafeToNumber(a.API.GetTime())
end
local function VersionRecord(a, name)
	local state, now = rawget(a, "qtPlayerPresenceState"), VersionNow(a)
	local record = state and state.peerVersions and state.peerVersions[name]
	if not a.isEnabled or a.isLoggingOut or not name or a:IsIgnoredPlayerName(name)
		or type(record) ~= "table" or not now or now < record.receivedAt or now >= record.expiresAt then
		return nil
	end
	if record.observationSession and not a:CanAcceptPeerEpoch(name, record.observationSession, record.sourceSampledAt) then
		return nil
	end
	if not a:CanAcceptPeerUpdate(name, nil, record.sampledAt, record.observationSession,
		record.observationSequence, record.sourceSampledAt) then return nil end
	if record.cached and not a:GetFreshPlayerLocation(name) then return nil end
	return record
end
local function StoreVersion(a, name, record)
	local state = a:GetQTPlayerPresenceState()
	state.peerVersions = state.peerVersions or {}
	if not state.peerVersions[name] then
		local count, oldest, at = 0
		for peer, value in pairs(state.peerVersions) do
			count = count + 1
			if not at or value.receivedAt < at then oldest, at = peer, value.receivedAt end
		end
		if count >= VERSION_LIMIT then state.peerVersions[oldest] = nil end
	end
	state.peerVersions[name] = record
end
local function VersionObservation(name, observation)
	if type(observation) ~= "table" or observation.name ~= name then return nil end
	-- Version evidence has its own ordering. A compact identity update cannot
	-- refresh quest/party counts or prevent an older full snapshot filling them.
	local result = {}
	for key, value in pairs(observation) do result[key] = value end
	result.field = "QTVER"
	return result
end
function QT:RememberPlayerAddonVersion(sender, version, observation, establishesPresence)
	local name = self:NormalizeMemberName(sender)
	if not name or not self:ParseAddonVersion(version) then return false end
	if not observation then
		if not self:IsKnownQTPlayer(name) then return false end
		observation = self:CreatePeerObservation(name, "QTVER", { source = "version", lifetime = VERSION_LIFETIME })
	else
		observation = VersionObservation(name, observation)
	end
	local record = { version = version }
	if not self:CommitPeerObservation(observation, record, establishesPresence == true) then return false end
	StoreVersion(self, name, record)
	return true
end

-- Only a still-correlated native MACK may supply handshake identity evidence.
-- This stores the version in its domain without inventing presence or stats.
function QT:RememberPlayerHandshakeVersion(sender, version, context)
	local name = self:NormalizeMemberName(sender)
	local state = rawget(self, "communicationState")
	local request = type(context) == "table" and state and state.requests[context.requestId]
	local stamp = type(context) == "table" and self:SafeToNumber(context.stamp)
	local sequence = type(context) == "table" and self:SafeToNumber(context.sequence)
	local serverNow = self:GetAnnouncementServerTime()
	if not name or type(context) ~= "table" or context.distribution ~= "WHISPER" or context.meshVerified
		or not request or request.operation ~= "MHEL" or request.target ~= name
		or not self:IsCommResponseExpected({ operation = "MACK", requestId = context.requestId }, name)
		or type(context.session) ~= "string" or #context.session > 40 or not context.session:match("^[%w%-]+$")
		or not sequence or sequence < 1 or sequence > 1e12 or sequence ~= math.floor(sequence)
		or not stamp or stamp <= 0 or not serverNow or serverNow - stamp < -1 or serverNow - stamp >= VERSION_LIFETIME then
		return false
	end
	local observation = self:CreatePeerObservation(name, "QTVER", {
		source = "handshake", session = context.session, sequence = sequence, stamp = stamp,
		sourceSampledAt = stamp, age = math.max(0, serverNow - stamp), lifetime = VERSION_LIFETIME,
	})
	return self:RememberPlayerAddonVersion(name, version, observation, false)
end

function QT:GetPlayerAddonVersion(sender)
	local name = self:NormalizeMemberName(sender)
	if not name then return nil end
	if self:IsSelfSender(name) then return self:GetAddonVersion() end
	local record = VersionRecord(self, name)
	if record and (self:IsKnownQTPlayer(name) or self:GetFreshPlayerLocation(name)) then return record.version end
end

function QT:SavePlayerAddonVersionCacheEntry(name, now, wall, locationExpires)
	name = self:NormalizeMemberName(name)
	local record = VersionRecord(self, name)
	if not record or not self:ParseAddonVersion(record.version) then return nil end
	local age = now - record.sampledAt
	local remaining = math.min(record.expiresAt - now, VERSION_LIFETIME - age, locationExpires - wall)
	if age < 0 or remaining <= 0 then return nil end
	return { version = record.version, sampledAt = wall - age, expiresAt = wall + remaining,
		sourceSampledAt = record.sourceSampledAt,
		session = record.observationSession, sequence = record.observationSequence }
end

function QT:RestorePlayerAddonVersionCacheEntry(name, cached, now, wall)
	name = self:NormalizeMemberName(name)
	local location = name and self:GetFreshPlayerLocation(name)
	if not self.isEnabled or not location or not location.cached or self:IsIgnoredPlayerName(name)
		or self:IsSelfSender(name) or type(cached) ~= "table" or not self:ParseAddonVersion(cached.version)
		or VersionRecord(self, name) then return false end
	local sampled, expires = self:SafeToNumber(cached.sampledAt), self:SafeToNumber(cached.expiresAt)
	local sequence, session = self:SafeToNumber(cached.sequence), cached.session
	local sourceStamp = cached.sourceSampledAt == nil and sampled or self:SafeToNumber(cached.sourceSampledAt)
	if not sampled or sampled > wall or wall - sampled >= VERSION_LIFETIME
		or not expires or expires <= wall or expires > wall + VERSION_CACHE_LIFETIME
		or (session ~= nil and (type(session) ~= "string" or #session > 40 or not session:match("^[%w%-]+$")))
		or (cached.sequence ~= nil and (not sequence or sequence < 1 or sequence > 1e12 or sequence ~= math.floor(sequence)))
		or not sourceStamp or sourceStamp > wall + 1 or sourceStamp <= 0
		or (session and not self:CanAcceptPeerEpoch(name, session, sourceStamp)) then return false end
	local remaining = math.min(expires - wall, VERSION_LIFETIME - (wall - sampled),
		(location.receivedAt + location.lifetime) - now)
	if remaining <= 0 or not self:CanAcceptPeerUpdate(name, nil, now - (wall - sampled), session, sequence, sourceStamp) then
		return false
	end
	StoreVersion(self, name, { version = cached.version, cached = true, sampledAt = now - (wall - sampled),
		receivedAt = now, expiresAt = now + remaining, lifetime = remaining, sourceSampledAt = sourceStamp,
		observationName = name, observationSession = session, observationSequence = sequence,
		observationSource = "cache" })
	return true
end

function QT:GetLocalPartySize()
	if self:IsRuntimeRestricted() then
		return nil
	end
	local getter = self.API and self.API.GetPartyJoinInfo
	if type(getter) ~= "function" then
		return nil
	end
	local ok, grouped, _, size = pcall(getter)
	if not ok or not self:CanAccessValue(grouped) or type(grouped) ~= "boolean" then
		return nil
	end
	size = self:SafeToNumber(size)
	if not size or size < 0 or size > 40 or size ~= math.floor(size) then
		return nil
	end
	if not grouped then
		return size == 0 and 0 or nil
	end
	return size > 0 and size or nil
end

function QT:GetPlayerTooltipStats(sender)
	local name = self:NormalizeMemberName(sender)
	if not name then
		return nil
	end
	if self:IsSelfSender(name) then
		return { count = self:GetMonitoredQuestCount(), partySize = self:GetLocalPartySize() }
	end
	if not self:IsKnownQTPlayer(name) then
		return nil
	end
	local state = rawget(self, "qtPlayerPresenceState")
	local record = state and state.peerTooltipStats and state.peerTooltipStats[name]
	local now = self.API.GetTime and self:SafeToNumber(self.API.GetTime())
	if record and now and now >= record.at and now - record.at < (record.lifetime or 180) then
		return record
	end
end

function QT:GetPlayerMonitoredQuestCount(sender)
	local stats = self:GetPlayerTooltipStats(sender)
	return stats and stats.count
end

function QT:GetPlayerPartySize(sender)
	local stats = self:GetPlayerTooltipStats(sender)
	return stats and stats.partySize
end

function QT:HandleAddonVersionMessage(payload, sender, observation)
	if type(payload) ~= "table" or not self:CanAccessTable(payload) then
		return false
	end
	local version, count, partySize = payload.version, payload.count, payload.partySize
	local extended = count ~= nil or partySize ~= nil
	if count ~= nil and (type(count) ~= "number" or count < 0 or count > 20000 or count ~= math.floor(count)) then
		return false
	end
	if
		partySize ~= nil
		and (type(partySize) ~= "number" or partySize < 0 or partySize > 40 or partySize ~= math.floor(partySize))
	then
		return false
	end
	local now = self.API.GetTime and self:SafeToNumber(self.API.GetTime())
	local name = self:NormalizeMemberName(sender)
	observation = self:ResolvePeerObservation(name, "QTVR", observation)
	local record = { count = count, partySize = partySize, at = now }
	if not now or not self:ParseAddonVersion(version) or not observation then return false end
	if extended then
		if not self:CommitPeerObservation(observation, record, true) then return false end
		self:RememberPlayerAddonVersion(sender, version, observation)
	else
		if not self:RememberPlayerAddonVersion(sender, version, observation, true) then return false end
	end
	if extended then
		local state = self:GetQTPlayerPresenceState()
		state.peerTooltipStats = state.peerTooltipStats or {}
		state.peerTooltipStats[self:NormalizeMemberName(sender)] = record
		self:InvalidatePartyVisualMembership(name, record.partySize, record.sampledAt, record)
	end
	self:ObserveAddonVersion(version)
	return true
end

function QT:BroadcastAddonVersion(forPresenceHeartbeat)
	if not self.isEnabled or self.isLoggingOut then
		return false
	end
	local now = self.API and self.API.GetTime and self:SafeToNumber(self.API.GetTime())
	if not now then
		return false
	end
	local state = self:GetAddonUpdateState()
	local interval = forPresenceHeartbeat and math.min(state.interval or RETRY_INTERVAL, RETRY_INTERVAL)
		or state.interval
	if state.lastAttempt and now >= state.lastAttempt and now - state.lastAttempt < interval then
		return false
	end
	state.lastAttempt, state.interval = now, RETRY_INTERVAL
	local geographic = rawget(self, "geographicCommsState")
	if forPresenceHeartbeat and not geographic then
		self:BroadcastPartyVisualMetadata()
	end
	local version = self:GetAddonVersion()
	if not self:ParseAddonVersion(version) then
		return false
	end
	local payload = { version = version, count = self:GetMonitoredQuestCount(), partySize = self:GetLocalPartySize() }
	local sent = self:Publish("QTVR", payload, nil, {
		owner = state,
		onComplete = function(accepted)
			if accepted and self:GetAddonUpdateState() == state then
				state.interval = BROADCAST_INTERVAL
			end
		end,
	})
	return sent
end
