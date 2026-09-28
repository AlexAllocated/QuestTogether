local QT = _G.QuestTogether
local HEARTBEAT, LIFETIME, MAX_PEERS = 20, 65, 256

local function Now(addon)
	local getTime = addon.API and addon.API.GetTime
	return type(getTime) == "function" and addon:SafeToNumber(getTime()) or nil
end

function QT:GetQTPlayerPresenceState()
	local state = rawget(self, "qtPlayerPresenceState")
	if not state then
		state = { peers = {} }
		self.qtPlayerPresenceState = state
	end
	return state
end

function QT:IsKnownQTPlayer(name)
	local state, now = rawget(self, "qtPlayerPresenceState"), Now(self)
	name = self:NormalizeMemberName(name)
	local seen = state and name and state.peers[name]
	return self.isEnabled == true
		and now ~= nil
		and seen ~= nil
		and now >= seen
		and now - seen < LIFETIME
		and not self:IsIgnoredPlayerName(name)
end

function QT:RecordQTPlayerPresence(name, active)
	if not self.isEnabled then
		return false
	end
	name = self:NormalizeMemberName(name)
	local now = Now(self)
	if not now or not name or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local state = self:GetQTPlayerPresenceState()
	local wasKnown = self:IsKnownQTPlayer(name)
	local hadRecord = state.peers[name] ~= nil
	if active then
		if not state.peers[name] then
			local count, oldest, oldestAt = 0, nil, math.huge
			for peer, seen in pairs(state.peers) do
				count = count + 1
				if seen < oldestAt then
					oldest, oldestAt = peer, seen
				end
			end
			if count >= MAX_PEERS then
				state.peers[oldest] = nil
			end
		end
		state.peers[name] = now
	else
		state.peers[name] = nil
	end
	-- A stored peer can already be expired while its last logo is still shown.
	-- Removing that record must clean up before the periodic prune loses it.
	if (wasKnown ~= active or (not active and hadRecord)) and self.RefreshQTPlayerPlatePresence then
		self:RefreshQTPlayerPlatePresence()
	end
	return true
end

function QT:HandleQTPlayerPresenceMessage(payload, sender)
	if payload ~= "1,1" and payload ~= "1,0" then
		return false
	end
	return self:RecordQTPlayerPresence(sender, payload == "1,1")
end

function QT:BroadcastQTPlayerPresence(inactive)
	if not self.isEnabled then
		return false
	end
	local now = Now(self)
	if not now then
		return false
	end
	local state = self:GetQTPlayerPresenceState()
	if not inactive and (self.isLoggingOut or (state.lastSentAt and now - state.lastSentAt < HEARTBEAT)) then
		return false
	end
	state.lastSentAt = now
	-- This presence packet contains no position and is independent of map consent.
	return self:SendWireMessageToAnnouncementRoutes(
		self:SerializeWireMessage("QTPR", inactive and "1,0" or "1,1"),
		"player presence"
	)
end

function QT:PruneQTPlayerPresence(force)
	local state, now = rawget(self, "qtPlayerPresenceState"), Now(self)
	if not state then
		return
	end
	if not force and now and state.lastPruneAt and now - state.lastPruneAt < 1 then
		return
	end
	state.lastPruneAt = now
	local changed = false
	for name, seen in pairs(state.peers) do
		if not now or now < seen or now - seen >= LIFETIME or self:IsIgnoredPlayerName(name) then
			state.peers[name], changed = nil, true
		end
	end
	if changed and self.RefreshQTPlayerPlatePresence then
		self:RefreshQTPlayerPlatePresence()
	end
end

function QT:UpdateQTPlayerPresence()
	self:BroadcastQTPlayerPresence()
	self:PruneQTPlayerPresence()
end

function QT:IsFriendlyQTPlayerUnit(unitToken)
	if
		not self:IsNameplateUnitToken(unitToken)
		or not self:DoesNameplateUnitExist(unitToken)
		or not self:IsNameplateUnitPlayer(unitToken)
	then
		return false
	end
	local ok, friendly = pcall(self.API.UnitIsFriend, "player", unitToken)
	if not ok or not self:CanAccessValue(friendly) or friendly ~= true then
		return false
	end
	local name = self:NormalizeMemberName(self:GetUnitFullName(unitToken))
	return name ~= nil and not self:IsSelfSender(name) and self:IsKnownQTPlayer(name), name
end
