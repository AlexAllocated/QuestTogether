local QT = _G.QuestTogether

local UPDATE_INTERVAL, SAMPLE_INTERVAL, MOVING_INTERVAL = 0.2, 5, 10
local HEARTBEAT_INTERVAL, WITHDRAWAL_INTERVAL, LIFETIME = 20, 5, 120
local MAX_PEERS = 512
local RELOAD_CACHE_LIFETIME = 180
local PARTNER_LIFETIME, MAX_CACHED_PARTNERS = 65, 256
local CLASSES = {
	WARRIOR = true,
	PALADIN = true,
	HUNTER = true,
	ROGUE = true,
	PRIEST = true,
	DEATHKNIGHT = true,
	SHAMAN = true,
	MAGE = true,
	WARLOCK = true,
	MONK = true,
	DRUID = true,
	DEMONHUNTER = true,
	EVOKER = true,
}

local function Number(addon, value, minimum, maximum, integer)
	value = addon:SafeToNumber(value)
	if value and value >= minimum and value <= maximum and (not integer or value == math.floor(value)) then
		return value
	end
end

local function Text(addon, value, maximum)
	if not addon:CanAccessValue(value) or type(value) ~= "string" then
		return ""
	end
	value = addon:SafeTrimString(value, ""):gsub("|", ""):gsub("[%c]", "")
	return #value <= maximum and value or ""
end

local function Now(addon)
	local getter = addon.API and addon.API.GetTime
	return type(getter) == "function" and addon:SafeToNumber(getter()) or nil
end

local function NeedsWithdrawalRetry(enabled, publishedAt, now, lifetime)
	return not enabled and publishedAt and now >= publishedAt and now < publishedAt + lifetime
end

function QT:GetPlayerLocationShareMask()
	return self:GetOption("sharePlayerLocation") == true and 3 or 0
end

function QT:CanPublishPlayerLocation()
	return self:GetPlayerLocationShareMask() ~= 0
end

function QT:GetPlayerLocationState()
	local state = rawget(self, "playerLocationState")
	if not state then
		state = { peers = {}, sequence = 0 }
		self.playerLocationState = state
	end
	return state
end

-- Persist only primitive, validated public positions. Wall time crosses client
-- restarts; GetTime timestamps do not. Never renew a sample by saving it again.
function QT:SavePlayerLocationCache()
	local global = self.db and self.db.global
	if not global then
		return
	end
	global.playerLocationCache = nil
	local state, now, wall = rawget(self, "playerLocationState"), Now(self), self:GetAnnouncementServerTime()
	local owner = self.activeCharacterKey or self:GetCurrentCharacterKey()
	if not self.isEnabled or not state or not now or not wall or not owner then
		return
	end
	local rows = {}
	local presence = rawget(self, "qtPlayerPresenceState")
	for name, peer in pairs(state.peers) do
		local sampled = peer.sampledAt or peer.receivedAt
		local age = now - sampled
		local remaining = math.min(RELOAD_CACHE_LIFETIME - age, (peer.lifetime or LIFETIME) - (now - peer.receivedAt))
		if peer.mask ~= 0 and age >= 0 and remaining > 0 and not self:IsIgnoredPlayerName(name) then
			local data = self:ValidatePlayerLocationRecord(peer)
			if data then
				local row = { name = name, data = data, sampledAt = wall - age, expiresAt = wall + remaining }
				row.party = self:SavePlayerPartyCacheEntry(name, now, wall)
				-- Preserve independently fresh LFQP status for the existing map filter.
				-- Neither saving nor restoring it establishes a new live presence.
				local partner = presence and presence.questPartners and presence.questPartners[name]
				if partner and partner.looking == true then
					local partnerAge = now - (partner.sampledAt or partner.receivedAt)
					local partnerRemaining = math.min(
						RELOAD_CACHE_LIFETIME - partnerAge,
						(partner.lifetime or PARTNER_LIFETIME) - (now - partner.receivedAt)
					)
					if partnerAge >= 0 and partnerRemaining > 0 then
						row.partner = {
							session = partner.session,
							sequence = partner.sequence,
							sampledAt = wall - partnerAge,
							expiresAt = wall + partnerRemaining,
						}
					end
				end
				rows[#rows + 1] = row
			end
		end
		if #rows >= MAX_PEERS then
			break
		end
	end
	global.playerLocationCache = { version = 2, owner = owner, savedAt = wall, rows = rows }
end

function QT:RestorePlayerLocationCache()
	local state = self:GetPlayerLocationState()
	if state.cacheRestored then
		return
	end
	state.cacheRestored = true
	local global = self.db and self.db.global
	local cache = global and global.playerLocationCache
	-- Consume it once. Disable/re-enable must not resurrect withdrawn positions.
	if global then
		global.playerLocationCache = nil
	end
	local now, wall = Now(self), self:GetAnnouncementServerTime()
	local owner = self.activeCharacterKey or self:GetCurrentCharacterKey()
	if
		not self.isEnabled
		or not now
		or not wall
		or not owner
		or type(cache) ~= "table"
		or cache.version ~= 2
		or cache.owner ~= owner
		or type(cache.rows) ~= "table"
		or not Number(self, cache.savedAt, wall - RELOAD_CACHE_LIFETIME, wall)
	then
		return
	end
	local count, partnerCount = 0, 0
	for _ in pairs(state.peers) do
		count = count + 1
	end
	local presence = rawget(self, "qtPlayerPresenceState")
	for _ in pairs(presence and presence.questPartners or {}) do
		partnerCount = partnerCount + 1
	end
	for i = 1, math.min(#cache.rows, MAX_PEERS) do
		if count >= MAX_PEERS then
			break
		end
		local row = cache.rows[i]
		if type(row) == "table" then
			local sampled = Number(self, row.sampledAt, 1000000000, wall)
			local expires = Number(self, row.expiresAt, wall, wall + RELOAD_CACHE_LIFETIME)
			local name = Text(self, row.name, 150)
			name = name ~= "" and self:NormalizeMemberName(name) or nil
			local data = self:ValidatePlayerLocationRecord(row.data)
			if
				sampled
				and expires
				and expires > wall
				and wall - sampled < RELOAD_CACHE_LIFETIME
				and name
				and not self:IsSelfSender(name)
				and not self:IsIgnoredPlayerName(name)
				and data
				and data.mask ~= 0
				and not state.peers[name]
			then
				data.name, data.receivedAt, data.sampledAt, data.retired = name, now, now - (wall - sampled), {}
				data.cached = true
				data.lifetime = math.min(expires - wall, RELOAD_CACHE_LIFETIME - (wall - sampled))
				state.peers[name] = data
				count = count + 1
				self:RestorePlayerPartyCacheEntry(name, row.party, now, wall)
				local partner = row.partner
				if
					type(partner) == "table"
					and partnerCount < MAX_CACHED_PARTNERS
					and not (presence and presence.questPartners and presence.questPartners[name])
				then
					local partnerSampled = Number(self, partner.sampledAt, 1000000000, wall)
					local partnerExpires = Number(self, partner.expiresAt, wall, wall + RELOAD_CACHE_LIFETIME)
					local sequence = Number(self, partner.sequence, 1, 2147483647, true)
					local session = partner.session
					if
						sequence
						and type(session) == "string"
						and #session <= 40
						and session:match("^%d+%-%d+$")
						and partnerSampled
						and partnerExpires
						and partnerExpires > wall
						and wall - partnerSampled < RELOAD_CACHE_LIFETIME
					then
						presence = presence or self:GetQTPlayerPresenceState()
						presence.questPartners = presence.questPartners or {}
						presence.questPartners[name] = {
							session = session,
							sequence = sequence,
							looking = true,
							receivedAt = now,
							sampledAt = now - (wall - partnerSampled),
							retired = {},
							lifetime = math.min(partnerExpires - wall, RELOAD_CACHE_LIFETIME - (wall - partnerSampled)),
						}
						partnerCount = partnerCount + 1
					end
				end
			end
		end
	end
end

function QT:ReadLocalPlayerLocation()
	if not self.isEnabled or self.isLoggingOut or self:IsRuntimeRestricted() then
		return nil
	end
	local mapID = Number(self, self.API.GetBestMapForUnit("player"), 1, 1000000, true)
	if not mapID then
		return nil
	end
	local position = self.API.GetPlayerMapPosition(mapID, "player")
	if not self:CanAccessTable(position) then
		return nil
	end
	local x, y = Number(self, position.x, 0, 1), Number(self, position.y, 0, 1)
	if not x or not y then
		return nil
	end
	local className, classFile = self.API.UnitClass("player")
	classFile = Text(self, classFile, 20)
	local factionOK, faction = pcall(self.API.GetFaction)
	if not factionOK or not self:CanAccessValue(faction) then
		faction = nil
	end
	local warMode
	if self:SupportsWarMode() == true and self.API.IsWarModeActive then
		warMode = self.API.IsWarModeActive()
	end
	if not self:CanAccessValue(warMode) or type(warMode) ~= "boolean" then
		warMode = nil
	end
	return {
		mapID = mapID,
		x = x,
		y = y,
		classFile = CLASSES[classFile] and classFile or "",
		className = Text(self, className, 48),
		race = Text(self, self.API.UnitRace("player"), 48),
		faction = (faction == "Alliance" or faction == "Horde" or faction == "Neutral") and faction or "",
		level = Number(self, self.API.UnitLevel("player"), 1, 1000, true),
		warMode = warMode,
	}
end

function QT:ValidatePlayerLocationRecord(record)
	if type(record) ~= "table" or not self:CanAccessTable(record) then
		return nil
	end
	local mask = Number(self, record.mask, 0, 3, true)
	if not mask then
		return nil
	end
	local data = { mask = mask }
	if record.session ~= nil then
		if type(record.session) ~= "string" or #record.session > 64 or not record.session:match("^[%w%-]+$") then
			return nil
		end
		data.session = record.session
	end
	if record.sequence ~= nil then
		data.sequence = Number(self, record.sequence, 1, 2147483647, true)
		if not data.sequence then
			return nil
		end
	end
	if mask == 0 then
		return data
	end
	data.mapID, data.x, data.y =
		Number(self, record.mapID, 1, 1000000, true), Number(self, record.x, 0, 1), Number(self, record.y, 0, 1)
	if not data.mapID or not data.x or not data.y then
		return nil
	end
	data.classFile = CLASSES[record.classFile] and record.classFile or ""
	data.className, data.race = Text(self, record.className, 80), Text(self, record.race, 80)
	local faction = self:SafeToString(record.faction, "")
	data.faction = (faction == "Alliance" or faction == "Horde" or faction == "Neutral") and faction or ""
	data.level = Number(self, record.level, 1, 1000, true)
	if self:CanAccessValue(record.warMode) and type(record.warMode) == "boolean" then
		data.warMode = record.warMode
	end
	return data
end

function QT:BroadcastPlayerLocation(force, withdraw)
	if not self.isEnabled then
		return false
	end
	local state, now = self:GetPlayerLocationState(), Now(self)
	if not now then
		return false
	end
	if not force and state.lastSampleAt and now - state.lastSampleAt < SAMPLE_INTERVAL then
		return false
	end
	state.lastSampleAt = now
	local mask = withdraw and 0 or self:GetPlayerLocationShareMask()
	local mapEnabled, minimapEnabled = mask % 2 == 1, mask >= 2
	local lifetime = self:GetGeographicSnapshotLifetime()
	local withdrawing = NeedsWithdrawalRetry(mapEnabled, state.lastMapLocationSentAt, now, lifetime)
		or NeedsWithdrawalRetry(minimapEnabled, state.lastMinimapLocationSentAt, now, lifetime)
	local location = mask ~= 0 and self:ReadLocalPlayerLocation() or nil
	if mask ~= 0 and not location then
		if not withdrawing then
			return false
		end
		mask, mapEnabled, minimapEnabled = 0, false, false
	end
	if mask == 0 and not force and not withdrawing then
		return false
	end
	local record = { mask = mask }
	if mask ~= 0 then
		for field, value in pairs(location) do
			record[field] = value
		end
	end
	-- Fingerprinting is local change detection, never a second wire format.
	local fingerprint = self:EncodeCommRecord("LOC", record)
	if not fingerprint then
		return false
	end
	local changed = fingerprint ~= state.lastFingerprint
	local interval = withdrawing and WITHDRAWAL_INTERVAL or changed and MOVING_INTERVAL or HEARTBEAT_INTERVAL
	if not force and state.lastAttemptAt and now - state.lastAttemptAt < interval then
		return false
	end
	state.lastAttemptAt = now
	local admitted = self:Publish("LOC", record, nil, {
		owner = state,
		publishesLocation = mask ~= 0,
		isCurrent = function()
			return rawget(self, "playerLocationState") == state
				and self.isEnabled
				and (mask == 0 or self:GetPlayerLocationShareMask() == mask)
		end,
		onComplete = function(sent)
			if not sent or rawget(self, "playerLocationState") ~= state then
				return
			end
			local acceptedAt = Now(self)
			state.lastSentAt, state.lastFingerprint = acceptedAt, fingerprint
			if mapEnabled then
				state.lastMapLocationSentAt = acceptedAt
			end
			if minimapEnabled then
				state.lastMinimapLocationSentAt = acceptedAt
			end
		end,
	})
	return admitted, location
end

function QT:PrunePlayerLocations(force)
	local state, now = rawget(self, "playerLocationState"), Now(self)
	if not state then
		return
	end
	if not force and now and state.lastPruneAt and now - state.lastPruneAt < 1 then
		return
	end
	state.lastPruneAt = now
	for name, peer in pairs(state.peers) do
		if
			not now
			or now < peer.receivedAt
			or now - peer.receivedAt >= (peer.lifetime or LIFETIME)
			or self:IsIgnoredPlayerName(name)
		then
			state.peers[name] = nil
		end
	end
end

function QT:HandlePlayerLocationMessage(payload, sender, observation)
	if not self.isEnabled then
		return false
	end
	local name = self:NormalizeMemberName(sender)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local data, now = self:ValidatePlayerLocationRecord(payload), Now(self)
	if not data or not now then
		return false
	end
	self:PrunePlayerLocations()
	local previous = self:GetPlayerLocationState().peers[name]
	observation = self:ResolvePeerObservation(name, "LOC", observation)
	if not self:CanAcceptPeerObservation(observation) then
		return false
	end
	local sampledAt = observation.sampledAt
	if
		previous
		and sampledAt < (previous.sampledAt or previous.receivedAt)
		and (previous.manualSnapshot or (previous.sampledAt or previous.receivedAt) - sampledAt >= 1)
	then
		return false
	end
	-- One admitted envelope owns ordering; LOC no longer maintains a parallel
	-- inner session/retired-epoch protocol that can disagree with other metadata.
	data.session, data.sequence = observation.session, observation.sequence
	data.retired = {}
	return self:StorePlayerLocationRecord(name, data, now, sampledAt, observation.expiresAt - now, observation)
end

-- Both public broadcasts and manual refreshes use the same bounded cache.
function QT:StorePlayerLocationRecord(name, data, now, sampledAt, lifetime, observation)
	local state = self:GetPlayerLocationState()
	local previous = state.peers[name]
	data.name, data.receivedAt, data.sampledAt, data.lifetime = name, now, sampledAt, lifetime
	observation = self:ResolvePeerObservation(name, "LOC", observation)
	if not self:CommitPeerObservation(observation, data, data.mask ~= 0) then
		return false
	end
	state.peers[name] = data
	local private = rawget(self, "developerPlayerData")
	if data.mask ~= 0 and private and private[name] and sampledAt >= private[name].receivedAt then
		private[name] = nil
	end
	if not previous then
		local count = 0
		for _ in pairs(state.peers) do
			count = count + 1
		end
		if count > MAX_PEERS then
			local origin = self:GetPlayerLocationPriorityOrigin()
			local worstName, worstDistance, oldestTime
			for peerName, peer in pairs(state.peers) do
				local distance = self:GetPlayerLocationPriorityDistance(peer, origin)
				if
					not worstName
					or distance > worstDistance
					or (
						distance == worstDistance
						and (peer.receivedAt < oldestTime or (peer.receivedAt == oldestTime and peerName > worstName))
					)
				then
					worstName, worstDistance, oldestTime = peerName, distance, peer.receivedAt
				end
			end
			state.peers[worstName] = nil
		end
	end

	-- Withdrawals can arrive after QTPR departure on another route. Preserve any
	-- existing identity for privacy opt-outs, but only a position establishes it.
	return true, data
end

-- A pong observation has a sample time, but no LOC stream sequence. Retain the
-- last real sequence; 0-0 is a local bootstrap session until the first LOC.
-- Hidden replies store only a withdrawal here, never their coordinates.
function QT:RefreshPlayerLocationFromPing(name, response, observation)
	local now = Now(self)
	if
		not self.isEnabled
		or not now
		or self:IsSelfSender(name)
		or self:IsIgnoredPlayerName(name)
		or type(response.locationShared) ~= "boolean"
		or not observation
		or observation.name ~= name
		or observation.field ~= "LOC"
		or not self:CanAcceptPeerObservation(observation)
	then
		return false
	end
	self:PrunePlayerLocations()
	local state = self:GetPlayerLocationState()
	local previous = state.peers[name]
	local sampledAt = observation.sampledAt
	-- Coordinates alone never grant public consent. Diagnostic replies can
	-- contain a private position while their explicit sharing setting is false.
	local shared = response.locationShared
	if
		previous
		and (
			sampledAt < (previous.sampledAt or previous.receivedAt)
			or (sampledAt == (previous.sampledAt or previous.receivedAt) and previous.mask == 0 and shared)
		)
	then
		return false
	end
	local data = {
		session = previous and previous.session or "0-0",
		sequence = previous and previous.sequence or 1,
		mask = shared and 3 or 0,
		manualSnapshot = true,
	}
	if shared then
		data.mapID = Number(self, response.mapID, 1, 1000000, true)
		local x, y = Number(self, response.coordX, 0, 100), Number(self, response.coordY, 0, 100)
		if not data.mapID or not x or not y then
			return false
		end
		data.x, data.y = x / 100, y / 100
		data.classFile = CLASSES[response.classFile] and response.classFile or ""
		data.className, data.race = Text(self, response.className, 48), Text(self, response.raceName, 48)
		data.faction = (response.faction == "Alliance" or response.faction == "Horde" or response.faction == "Neutral")
				and response.faction
			or ""
		data.level = Number(self, response.level, 1, 1000, true)
		data.warMode = self:NormalizeAnnouncementWarModeValue(response.warMode)
		if not response.developer and previous then
			-- A public pong does not grant additional surface consent or erase
			-- identity fields that are absent from its response.
			if previous.mask == 1 or previous.mask == 2 then
				data.mask = previous.mask
			end
			for _, field in ipairs({ "classFile", "className", "race", "faction", "level", "warMode" }) do
				if data[field] == nil or data[field] == "" then
					data[field] = previous[field]
				end
			end
		end
	end
	data.retired = previous and previous.retired or {}
	return self:StorePlayerLocationRecord(name, data, now, sampledAt, observation.expiresAt - now, observation)
end

function QT:GetFreshPlayerLocation(name, surface)
	name = self:NormalizeMemberName(name)
	local state, now = rawget(self, "playerLocationState"), Now(self)
	local peer = name and state and state.peers[name]
	if
		not peer
		or not now
		or self:IsIgnoredPlayerName(name)
		or peer.mask == 0
		or now < peer.receivedAt
		or now - peer.receivedAt >= (peer.lifetime or LIFETIME)
	then
		return nil
	end
	if surface == "map" and peer.mask % 2 ~= 1 or surface == "minimap" and peer.mask < 2 then
		return nil
	end
	return peer
end
function QT:GetRecentPlayerLocationMapID(name)
	local peer = self:GetFreshPlayerLocation(name)
	return peer and peer.mapID or nil
end

function QT:GetVisiblePlayerLocations(surface)
	if
		(surface ~= "map" and surface ~= "minimap")
		or not self.isEnabled
		or self.isLoggingOut
		or self:IsRuntimeRestricted()
		or self:GetOption("showPlayerLocations") ~= true
	then
		return {}
	end
	self:PrunePlayerLocations()
	local state, result, now = rawget(self, "playerLocationState"), {}, Now(self)
	for _, peer in pairs(state and state.peers or {}) do
		if
			now
			and now >= peer.receivedAt
			and now - peer.receivedAt < (peer.lifetime or LIFETIME)
			-- Surface permissions are evaluated independently from viewer filters.
			and ((surface == "map" and peer.mask % 2 == 1) or (surface == "minimap" and peer.mask >= 2))
			and self:ShouldShowPlayerLocation(peer.name)
		then
			result[#result + 1] = surface == "minimap" and self:GetNearbyStreamPosition(peer, true) or peer
		end
	end
	self:AppendDeveloperLocationRows(result)
	table.sort(result, function(a, b)
		return a.name < b.name
	end)
	return result
end

function QT:InitializePlayerLocations()
	if not self.isEnabled or not self.hasLoggedIn then
		return false
	end
	self:GetPlayerLocationState()
	self:RestorePlayerLocationCache()
	return true
end

function QT:ResetPlayerLocations()
	self.playerLocationState, self.locationPriorityCache = nil, nil
	self:HidePlayerLocationPins()
end

function QT:OnPlayerLocationOptionsChanged(key)
	self:OnNearbyLocationOptionsChanged(key)
	if not self.isEnabled then
		return
	end
	if not key or key == "sharePlayerLocation" then
		self:BroadcastPlayerLocation(true)
		self:BroadcastQuestPartnerStatus(true)
	end
	self:RefreshPlayerLocationPins()
end

-- Race/class labels belong to the viewer's client locale. Race IDs arrive in
-- QTCI metadata; unknown custom races retain their readable sender labels.
function QT:GetPlayerTooltipIdentity(row)
	local race, class = row.race, row.className
	if self:IsRuntimeRestricted() then
		return race, class
	end
	local name = self:NormalizeMemberName(row.name)
	local metadata = name and self:GetPlayerCapabilities(name)
	if metadata and metadata.raceID and metadata.raceID > 0 and self.API.GetLocalizedRaceName then
		local localized = self:SafeTrimString(self.API.GetLocalizedRaceName(metadata.raceID), "")
		if localized ~= "" then
			race = localized
		end
	end
	if self.API.GetLocalizedClassName then
		local localized = self:SafeTrimString(self.API.GetLocalizedClassName(row.classFile), "")
		if localized ~= "" then
			class = localized
		end
	end
	return race, class
end

function QT:RetirePlayerLocationPeer(name)
	local state, now = rawget(self, "playerLocationState"), Now(self)
	local previous = state and state.peers[name]
	if previous and previous.mask ~= 0 then
		state.peers[name] = {
			name = name,
			session = previous.session,
			sequence = previous.sequence,
			retired = previous.retired,
			mask = 0,
			receivedAt = now,
			sampledAt = now,
			lifetime = self:GetGeographicSnapshotLifetime(),
		}
	end
end
