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
	if not global then return end
	global.playerLocationCache = nil
	local state, now, wall = rawget(self, "playerLocationState"), Now(self), self:GetAnnouncementServerTime()
	local owner = self.activeCharacterKey or self:GetCurrentCharacterKey()
	if not self.isEnabled or not state or not now or not wall or not owner then return end
	local rows = {}
	local presence = rawget(self, "qtPlayerPresenceState")
	for name, peer in pairs(state.peers) do
		local sampled = peer.sampledAt or peer.receivedAt
		local age = now - sampled
		local remaining = math.min(RELOAD_CACHE_LIFETIME - age, (peer.lifetime or LIFETIME) - (now - peer.receivedAt))
		if peer.mask ~= 0 and age >= 0 and remaining > 0 and not self:IsIgnoredPlayerName(name) then
			local payload = self:EncodePlayerLocationPayload(peer, peer.mask, peer)
			if self:DecodePlayerLocationPayload(payload) then
				local row = { name = name, payload = payload, sampledAt = wall - age, expiresAt = wall + remaining }
				row.party = self:SavePlayerPartyCacheEntry(name, now, wall)
				-- Preserve independently fresh LFQP status for the existing map filter.
				-- Neither saving nor restoring it establishes a new live presence.
				local partner = presence and presence.questPartners and presence.questPartners[name]
				if partner and partner.looking == true then
					local partnerAge = now - (partner.sampledAt or partner.receivedAt)
					local partnerRemaining = math.min(RELOAD_CACHE_LIFETIME - partnerAge,
						(partner.lifetime or PARTNER_LIFETIME) - (now - partner.receivedAt))
					if partnerAge >= 0 and partnerRemaining > 0 then
						row.partner = { session = partner.session, sequence = partner.sequence,
							sampledAt = wall - partnerAge, expiresAt = wall + partnerRemaining }
					end
				end
				rows[#rows + 1] = row
			end
		end
		if #rows >= MAX_PEERS then break end
	end
	global.playerLocationCache = { version = 1, owner = owner, savedAt = wall, rows = rows }
end

function QT:RestorePlayerLocationCache()
	local state = self:GetPlayerLocationState()
	if state.cacheRestored then return end
	state.cacheRestored = true
	local global = self.db and self.db.global
	local cache = global and global.playerLocationCache
	-- Consume it once. Disable/re-enable must not resurrect withdrawn positions.
	if global then global.playerLocationCache = nil end
	local now, wall = Now(self), self:GetAnnouncementServerTime()
	local owner = self.activeCharacterKey or self:GetCurrentCharacterKey()
	if not self.isEnabled or not now or not wall or not owner or type(cache) ~= "table"
		or cache.version ~= 1 or cache.owner ~= owner or type(cache.rows) ~= "table"
		or not Number(self, cache.savedAt, wall - RELOAD_CACHE_LIFETIME, wall) then return end
	local count, partnerCount = 0, 0
	for _ in pairs(state.peers) do count = count + 1 end
	local presence = rawget(self, "qtPlayerPresenceState")
	for _ in pairs(presence and presence.questPartners or {}) do partnerCount = partnerCount + 1 end
	for i = 1, math.min(#cache.rows, MAX_PEERS) do
		if count >= MAX_PEERS then break end
		local row = cache.rows[i]
		if type(row) == "table" then
			local sampled = Number(self, row.sampledAt, 1000000000, wall)
			local expires = Number(self, row.expiresAt, wall, wall + RELOAD_CACHE_LIFETIME)
			local name = Text(self, row.name, 150)
			name = name ~= "" and self:NormalizeMemberName(name) or nil
			local data = self:DecodePlayerLocationPayload(row.payload)
			if sampled and expires and expires > wall and wall - sampled < RELOAD_CACHE_LIFETIME
				and name and not self:IsSelfSender(name) and not self:IsIgnoredPlayerName(name)
				and data and data.mask ~= 0 and not state.peers[name] then
				data.name, data.receivedAt, data.sampledAt, data.retired = name, now, now - (wall - sampled), {}
				data.cached = true
				data.lifetime = math.min(expires - wall, RELOAD_CACHE_LIFETIME - (wall - sampled))
				state.peers[name] = data
				count = count + 1
				self:RestorePlayerPartyCacheEntry(name, row.party, now, wall)
				local partner = row.partner
				if type(partner) == "table" and partnerCount < MAX_CACHED_PARTNERS
					and not (presence and presence.questPartners and presence.questPartners[name]) then
					local partnerSampled = Number(self, partner.sampledAt, 1000000000, wall)
					local partnerExpires = Number(self, partner.expiresAt, wall, wall + RELOAD_CACHE_LIFETIME)
					local sequence = Number(self, partner.sequence, 1, 2147483647, true)
					local session = partner.session
					if sequence and type(session) == "string" and #session <= 40
						and session:match("^%d+%-%d+$") and partnerSampled and partnerExpires
						and partnerExpires > wall and wall - partnerSampled < RELOAD_CACHE_LIFETIME then
						presence = presence or self:GetQTPlayerPresenceState()
						presence.questPartners = presence.questPartners or {}
						presence.questPartners[name] = { session = session, sequence = sequence,
							looking = true, receivedAt = now, sampledAt = now - (wall - partnerSampled), retired = {},
							lifetime = math.min(partnerExpires - wall, RELOAD_CACHE_LIFETIME - (wall - partnerSampled)) }
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

function QT:EncodePlayerLocationPayload(state, mask, location)
	local fields = { "1", state.session, tostring(state.sequence), tostring(mask) }
	if mask ~= 0 then
		fields[5], fields[6], fields[7] =
			tostring(location.mapID), string.format("%.5f", location.x), string.format("%.5f", location.y)
		fields[8], fields[9], fields[10] =
			location.classFile, self:EscapePayload(location.className), self:EscapePayload(location.race)
		fields[11], fields[12] = location.faction, location.level and tostring(location.level) or ""
		fields[13] = location.warMode == nil and "" or (location.warMode and "1" or "0")
		-- Optional localized labels never displace position or consent flags.
		if #table.concat(fields, ",") > 251 then
			fields[9] = ""
		end
		if #table.concat(fields, ",") > 251 then
			fields[10] = ""
		end
	end
	return table.concat(fields, ",")
end

function QT:DecodePlayerLocationPayload(payload)
	if not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 251 then
		return nil
	end
	local fields = {}
	for field in (payload .. ","):gmatch("(.-),") do
		fields[#fields + 1] = field
	end
	local mask = Number(self, fields[4], 0, 3, true)
	local sequence = Number(self, fields[3], 1, 2147483647, true)
	if
		fields[1] ~= "1"
		or not mask
		or not sequence
		or not fields[2]
		or #fields[2] > 40
		or not fields[2]:match("^%d+%-%d+$")
	then
		return nil
	end
	if #fields ~= (mask == 0 and 4 or 13) then
		return nil
	end
	local data = { session = fields[2], sequence = sequence, mask = mask }
	if mask == 0 then
		return data
	end
	data.mapID = Number(self, fields[5], 1, 1000000, true)
	data.x, data.y = Number(self, fields[6], 0, 1), Number(self, fields[7], 0, 1)
	if not data.mapID or not data.x or not data.y then
		return nil
	end
	data.classFile = CLASSES[fields[8]] and fields[8] or ""
	data.className, data.race =
		Text(self, self:UnescapePayload(fields[9]), 48), Text(self, self:UnescapePayload(fields[10]), 48)
	data.faction = (fields[11] == "Alliance" or fields[11] == "Horde" or fields[11] == "Neutral") and fields[11] or ""
	data.level = Number(self, fields[12], 1, 1000, true)
	if fields[13] == "1" then
		data.warMode = true
	elseif fields[13] == "0" then
		data.warMode = false
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
	-- One route can accept a permission change while another rejects it. Retry
	-- each revoked surface until its last published point expires. Publications
	-- on a retained surface must not prolong another surface's revocation window.
	local mapEnabled, minimapEnabled = mask % 2 == 1, mask >= 2
	local withdrawing = NeedsWithdrawalRetry(mapEnabled, state.lastMapLocationSentAt, now, rawget(self, "geographicCommsState") and 600 or LIFETIME)
		or NeedsWithdrawalRetry(minimapEnabled, state.lastMinimapLocationSentAt, now, rawget(self, "geographicCommsState") and 600 or LIFETIME)
	local location = mask ~= 0 and self:ReadLocalPlayerLocation() or nil
	if mask ~= 0 and not location then
		-- A transient read outage is not a privacy change. Do not renew stale
		-- coordinates or withdraw an otherwise permitted last-reported point.
		if not withdrawing then return false end
		-- A partial opt-out still needs immediate withdrawal when no fresh
		-- position can be published for the remaining permitted surface.
		mask, mapEnabled, minimapEnabled = 0, false, false
	end
	if mask == 0 and not force and not withdrawing then
		return false
	end
	if not state.session then
		local random = Number(self, self.API.Random and self.API.Random(1000, 999999), 1000, 999999, true) or 1000
		state.session = string.format("%d-%d", math.max(0, math.floor(now * 1000)), random)
	end
	local fingerprint = mask == 0 and "0"
		or self:EncodePlayerLocationPayload({ session = "0-0", sequence = 1 }, mask, location)
	local changed = fingerprint ~= state.lastFingerprint
	local interval = withdrawing and WITHDRAWAL_INTERVAL or (changed and MOVING_INTERVAL or HEARTBEAT_INTERVAL)
	local due = not state.lastSentAt or now - state.lastSentAt >= interval
	if not force and not due then
		return false
	end
	state.sequence = state.sequence % 2147483647 + 1
	local payload = self:EncodePlayerLocationPayload(state, mask, location)
	-- Failed sends are paced too; no per-frame retry or postponed manual action.
	state.lastSentAt = now
	local sent = self:SendWireMessageToAnnouncementRoutes(self:SerializeWireMessage("LOC", payload), "player location")
	if sent then
		state.lastFingerprint = fingerprint
		if mapEnabled then state.lastMapLocationSentAt = now end
		if minimapEnabled then state.lastMinimapLocationSentAt = now end
	end
	return sent, location
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
		if not now or now < peer.receivedAt or now - peer.receivedAt >= (peer.lifetime or LIFETIME) or self:IsIgnoredPlayerName(name) then
			state.peers[name] = nil
		end
	end
end

function QT:HandlePlayerLocationMessage(payload, sender)
	if not self.isEnabled then
		return false
	end
	local name = self:NormalizeMemberName(sender)
	if not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local data, now = self:DecodePlayerLocationPayload(payload), Now(self)
	if not data or not now then
		return false
	end
	self:PrunePlayerLocations()
	local state = self:GetPlayerLocationState()
	local previous = state.peers[name]
	if previous and (previous.session == data.session and previous.sequence >= data.sequence) then
		return false
	end
	local retired = previous and previous.retired or {}
	for _, session in ipairs(retired) do
		if session == data.session then
			return false
		end
	end
	if previous and previous.session ~= data.session then
		retired[#retired + 1] = previous.session
		if #retired > 4 then
			table.remove(retired, 1)
		end
	end
	data.name, data.receivedAt, data.retired = name, now, retired
	state.peers[name] = data
	if not previous then
		local count = 0
		for _ in pairs(state.peers) do count = count + 1 end
		if count > MAX_PEERS then
			local origin = self:GetPlayerLocationPriorityOrigin()
			local worstName, worstDistance, oldestTime
			for peerName, peer in pairs(state.peers) do
				local distance = self:GetPlayerLocationPriorityDistance(peer, origin)
				if not worstName or distance > worstDistance
					or (distance == worstDistance and (peer.receivedAt < oldestTime
						or (peer.receivedAt == oldestTime and peerName > worstName))) then
					worstName, worstDistance, oldestTime = peerName, distance, peer.receivedAt
				end
			end
			state.peers[worstName] = nil
		end
	end

	-- Withdrawals can arrive after QTPR departure on another route. Preserve any
	-- existing identity for privacy opt-outs, but only a position establishes it.
	if data.mask ~= 0 then self:RecordQTPlayerPresence(name, true) end
	return true
end

function QT:GetRecentPlayerLocationMapID(name)
	local state = rawget(self, "playerLocationState")
	local peer = state and state.peers and state.peers[name]
	local now = Now(self)
	if not peer or not now or peer.mask == 0 or now < peer.receivedAt or now - peer.receivedAt >= (peer.lifetime or LIFETIME) then return nil end
	return peer.mapID
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
	local onlyPartners = self:GetOption("onlyShowQuestPartners") == true
	for _, peer in pairs(state and state.peers or {}) do
		if
			now
			and now >= peer.receivedAt
			and now - peer.receivedAt < (peer.lifetime or LIFETIME)
			-- Older peers can still grant permission for just one surface.
			and ((surface == "map" and peer.mask % 2 == 1) or (surface == "minimap" and peer.mask >= 2))
			and (self:GetOption("mapPartyOnly") ~= true or self:IsGroupedSender(peer.name))
			and (not onlyPartners or self:IsPlayerLookingForQuestPartners(peer.name)
				or (self:GetOption("mapAlwaysShowParty") == true and self:IsGroupedSender(peer.name)))
		then
			result[#result + 1] = surface == "minimap" and self:GetNearbyStreamPosition(peer, true) or peer
		end
	end
	table.sort(result, function(a, b)
		return a.name < b.name
	end)
	return result
end

-- One owner for periodic publication. Share this tick's addon-owned location
-- sample with nearby streams; never retain it across frames or privacy changes.
function QT:UpdatePlayerCommunications()
	self:UpdatePartyQuestCompareFreshness()
	self:UpdatePlayerPhaseObservations()
	if self.UpdateQTPlayerPresence then self:UpdateQTPlayerPresence() end
	local sample
	if rawget(self, "geographicCommsState") then
		sample = self:UpdateGeographicComms()
	else
		self:BroadcastPlayerLocation()
	end
	self:UpdateNearbyStreams(sample)
end

function QT:CreatePlayerLocationUpdateFrame()
	return CreateFrame("Frame")
end

function QT:InitializePlayerLocations()
	if not self.isEnabled or not self.hasLoggedIn then
		return false
	end
	local state = self:GetPlayerLocationState()
	self:RestorePlayerLocationCache()
	local frame = rawget(self, "playerLocationUpdateFrame")
	if not frame then
		frame = self:CreatePlayerLocationUpdateFrame()
		self.playerLocationUpdateFrame = frame
	end
	if not self.LibChev.CanMutateOwnedRegion(frame) then
		return false
	end
	local elapsed, animationElapsed = 0, 0
	frame:SetScript("OnUpdate", function(_, delta)
		if rawget(self, "playerLocationState") ~= state or not self.isEnabled then
			return
		end
		local step = Number(self, delta, 0, 1000) or 0
		elapsed, animationElapsed = elapsed + step, animationElapsed + step
		if animationElapsed >= 1 / 30 then
			animationElapsed = 0
			self:RefreshNearbyStreamPins()
		end
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		self:UpdatePartyNavigation()
		self:RefreshPartyWaypointPins()
		self:UpdatePlayerCommunications()
		self:PrunePlayerLocations()
		self:RefreshPlayerLocationPins()
		self:UpdatePlayerTooltipBadge()
		self:UpdateChatLogPlayerTooltip()
	end)
	-- First update uses the same paced path as recovery and movement.
	return true
end

function QT:ResetPlayerLocations()
	self:ResetPartyNavigation()
	self:HideChatLogPlayerTooltip()
	self:HidePlayerTooltipBadge()
	self.playerLocationState = nil
	self.nearbyStreamState = nil
	self.playerPhaseState = nil
	local frame = rawget(self, "playerLocationUpdateFrame")
	if frame and self.LibChev.CanMutateOwnedRegion(frame) then
		frame:SetScript("OnUpdate", nil)
	end
	if self.HidePlayerLocationPins then
		self:HidePlayerLocationPins()
	end
end

function QT:OnPlayerLocationOptionsChanged(key)
	local streams = rawget(self, "nearbyStreamState")
	if streams then
		streams.wanted, streams.nextScan = {}, 0
		if not key or key == "sharePlayerLocation" then streams.subscribers, streams.nextCapability = {}, 0 end
	end
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
-- optional QTCI metadata; legacy clients retain their readable sender labels.
function QT:GetPlayerTooltipIdentity(row)
	local race, class = row.race, row.className
	if self:IsRuntimeRestricted() then return race, class end
	local state = rawget(self, "nearbyStreamState")
	local now = state and Now(self)
	local name = state and self:NormalizeMemberName(row.name)
	local metadata = state and name and state.capabilities[name]
	if metadata and now and now >= metadata.receivedAt and now - metadata.receivedAt < (metadata.lifetime or 600)
		and metadata.raceID and metadata.raceID > 0 and not self:IsIgnoredPlayerName(name) and self.API.GetLocalizedRaceName then
		local localized = self:SafeTrimString(self.API.GetLocalizedRaceName(metadata.raceID), "")
		if localized ~= "" then race = localized end
	end
	if self.API.GetLocalizedClassName then
		local localized = self:SafeTrimString(self.API.GetLocalizedClassName(row.classFile), "")
		if localized ~= "" then class = localized end
	end
	return race, class
end
