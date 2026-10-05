local L = _G.QuestTogether.Translate
local QT = _G.QuestTogether
local HEARTBEAT, LIFETIME, MAX_PEERS = 20, 65, 256
local MAX_KNOWN_PLAYERS = 512
local PARTNER_ANNOUNCEMENT_COOLDOWN = 30

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
	return self.isEnabled == true and now ~= nil and seen ~= nil and now >= seen and not self:IsIgnoredPlayerName(name)
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
	if not active then self:ForgetPartyVisualPeer(name) end
	if active then
		if not state.peers[name] then
			local count, oldest, oldestAt = 0, nil, math.huge
			for peer, seen in pairs(state.peers) do
				count = count + 1
				if seen < oldestAt then
					oldest, oldestAt = peer, seen
				end
			end
			if count >= MAX_KNOWN_PLAYERS then
				state.peers[oldest] = nil
				self:ForgetPartyVisualPeer(oldest)
				if state.peerVersions then state.peerVersions[oldest] = nil end
				if state.peerTooltipStats then state.peerTooltipStats[oldest] = nil end
			end
		end
		state.peers[name] = now
	else
		state.peers[name] = nil
		if state.peerVersions then state.peerVersions[name] = nil end
		if state.peerTooltipStats then state.peerTooltipStats[name] = nil end
		if self.ForgetPartyJoinPeer then self:ForgetPartyJoinPeer(name) end
	end
	-- Recognition lasts for this UI session, independently of short-lived map
	-- positions and partner status. Departures and evictions still clear logos.
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
	if inactive and (state.lastPartnerOnAt or self:GetOption("lookingForQuestPartners") == true) then
		self:BroadcastQuestPartnerStatus(true, true)
	end
	if not inactive then
		local includeVersion = state.nextPresenceIncludesVersion
		state.nextPresenceIncludesVersion = not includeVersion
		-- Legacy QTPR receivers require an exact payload. Alternate with QTVR,
		-- which also establishes presence, instead of extending that payload or
		-- adding traffic. Invalid local version metadata still permits discovery.
		if includeVersion and self:ParseAddonVersion(self:GetAddonVersion()) then
			return self:BroadcastAddonVersion(true)
		end
	end
	-- This presence packet contains no position and is independent of map consent.
	return self:SendWireMessageToAnnouncementRoutes(
		self:SerializeWireMessage("QTPR", inactive and "1,0" or "1,1"),
		"player presence"
	)
end

-- Keep the original QTPR packet intact for older clients. Only explicit QTLF
-- updates renew this status; announcements and other presence cannot do so.
function QT:IsPlayerLookingForQuestPartners(name)
	name = self:NormalizeMemberName(name)
	if not name or not self.isEnabled then
		return false
	end
	if self:IsSelfSender(name) then
		return self:GetOption("lookingForQuestPartners") == true
	end
	local state, now = rawget(self, "qtPlayerPresenceState"), Now(self)
	local record = state and state.questPartners and state.questPartners[name]
	-- Legacy QTPR has no ordering information. A delayed old departure must not
	-- overwrite a newer ordered status after the sender rejoins.
	return not self:IsIgnoredPlayerName(name)
		and record ~= nil
		and record.looking == true
		and now ~= nil
		and now >= record.receivedAt
		and now - record.receivedAt < (record.lifetime or LIFETIME)
end

function QT:HandleQuestPartnerStatusMessage(payload, sender)
	if not self.isEnabled or not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 80 then
		return false
	end
	local session, sequence, looking = payload:match("^1,(%d+%-%d+),(%d+),([01])$")
	sequence = self:SafeToNumber(sequence)
	if not session or #session > 40 or not sequence or sequence < 1 or sequence > 2147483647 then
		return false
	end
	local name, now = self:NormalizeMemberName(sender), Now(self)
	if not name or not now or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	self:PruneQTPlayerPresence()
	local state = self:GetQTPlayerPresenceState()
	state.questPartners = state.questPartners or {}
	local previous = state.questPartners[name]
	if previous and previous.session == session and previous.sequence >= sequence then
		return false
	end
	local retired = previous and previous.retired or {}
	for _, oldSession in ipairs(retired) do
		if oldSession == session then
			return false
		end
	end
	if previous and previous.session ~= session then
		retired[#retired + 1] = previous.session
		if #retired > 4 then
			table.remove(retired, 1)
		end
	end
	if not previous then
		local count, oldest, oldestAt = 0, nil, math.huge
		for peer, record in pairs(state.questPartners) do
			count = count + 1
			if record.receivedAt < oldestAt then
				oldest, oldestAt = peer, record.receivedAt
			end
		end
		if count >= MAX_PEERS then
			state.questPartners[oldest] = nil
		end
	end
	-- Off can be a delayed departure withdrawal. It clears partner status while
	-- preserving an existing identity, but must not restore a departed logo.
	if looking == "1" and not self:RecordQTPlayerPresence(name, true) then
		return false
	end
	-- Keep Off records until expiry too: a delayed copy of On must not revive it.
	state.questPartners[name] = {
		session = session,
		sequence = sequence,
		looking = looking == "1",
		receivedAt = now,
		retired = retired,
	}
	if self.RefreshQTPlayerPartnerIndicators then self:RefreshQTPlayerPartnerIndicators() end
	return true
end

-- Only an explicit off-to-on setting change announces a search. Heartbeats,
-- login, profile loading, and withdrawals remain metadata-only updates.
function QT:AnnounceQuestPartnerSearch()
	if not self.isEnabled or self.isLoggingOut or self:IsRuntimeRestricted()
		or self:GetOption("lookingForQuestPartners") ~= true
		or not self:ShouldDisplayAnnouncementType("LOOKING_FOR_QUEST_PARTNERS") then return false end
	local now = Now(self)
	if not now then return false end
	local last = rawget(self, "lastQuestPartnerAnnouncementAt")
	if last and now >= last and now - last < PARTNER_ANNOUNCEMENT_COOLDOWN then return false end
	local event = self:BuildLocalAnnouncementEvent("LOOKING_FOR_QUEST_PARTNERS", L("Looking for questing partners") .. " :)")
	if not event then return false end
	-- Pace attempts too; failed routes must not let rapid toggles flood comms.
	-- Keep this separate from presence state so disabling/re-enabling the addon
	-- or changing profiles does not reset the session cooldown.
	self.lastQuestPartnerAnnouncementAt = now
	local sent = self:SendAnnouncementWireEvent(event)
	if not self.suppressLocalAnnouncementDisplayDuringTests then self:HandleAnnouncementEvent(event, true) end
	return sent
end

function QT:StopLookingForPartnersOnGroupJoin()
	if not self.isEnabled or self.isLoggingOut
		or self:GetOption("stopLookingForPartnersOnJoin") ~= true
		or self:GetOption("lookingForQuestPartners") ~= true then return false end
	return self:SetOption("lookingForQuestPartners", false)
end

function QT:BroadcastQuestPartnerStatus(force, inactive)
	if not self.isEnabled or (self.isLoggingOut and not inactive) then
		return false
	end
	local now = Now(self)
	if not now then
		return false
	end
	local state = self:GetQTPlayerPresenceState()
	local looking = not inactive and self:GetOption("lookingForQuestPartners") == true
	-- Most users leave this opt-in setting off. Send nothing periodically unless
	-- an earlier On can still be visible, in which case repeat its withdrawal.
	local withdrawing = state.lastPartnerOnAt
		and now >= state.lastPartnerOnAt
		and now - state.lastPartnerOnAt < LIFETIME
	if not looking and not force and not withdrawing then
		return false
	end
	if
		not force
		and state.lastPartnerSentAt
		and now >= state.lastPartnerSentAt
		and now - state.lastPartnerSentAt < HEARTBEAT
	then
		return false
	end
	if not state.partnerSession then
		local random = self:SafeToNumber(self.API.Random and self.API.Random(1000, 999999)) or 1000
		state.partnerSession = string.format(
			"%d-%d",
			math.max(0, math.floor(now * 1000)),
			math.max(1000, math.min(999999, math.floor(random)))
		)
		state.partnerSequence = 0
	end
	state.partnerSequence = state.partnerSequence % 2147483647 + 1
	local payload = string.format("1,%s,%d,%d", state.partnerSession, state.partnerSequence, looking and 1 or 0)
	state.lastPartnerSentAt = now -- Pace failed sends too.
	local sent =
		self:SendWireMessageToAnnouncementRoutes(self:SerializeWireMessage("QTLF", payload), "quest partner status")
	self:BroadcastQuestPartnerQuest(state, looking)
	if sent and looking then
		state.lastPartnerOnAt = now
	end
	return sent
end

function QT:HandleQuestPartnerCommand(input)
	local action = string.lower(self:SafeTrimString(input, ""))
	local looking = self:GetOption("lookingForQuestPartners") == true
	if action == "" or action == "toggle" then
		looking = not looking
	elseif action == "on" then
		looking = true
	elseif action == "off" then
		looking = false
	elseif action ~= "status" then
		self:Print(L("Usage: /qt lfg [on|off|toggle|status]"))
		return false
	end
	if action ~= "status" then
		if not self:SetOption("lookingForQuestPartners", looking) then
			return false
		end
		if not self:IsRuntimeRestricted() and self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
	end
	self:Print(
		L("Looking for questing partners: ")
			.. (looking and L("On") or L("Off"))
			.. (looking and not self.isEnabled and L(" (paused while QuestTogether is disabled).") or ".")
	)
	return true
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
	self:PruneQuestPartnerQuests(now)
	local changed = false
	for name, seen in pairs(state.peers) do
		if not now or now < seen or self:IsIgnoredPlayerName(name) then
			state.peers[name], changed = nil, true
			self:ForgetPartyVisualPeer(name)
			if state.peerVersions then state.peerVersions[name] = nil end
			if state.peerTooltipStats then state.peerTooltipStats[name] = nil end
		end
	end
	for name, record in pairs(state.questPartners or {}) do
		if
			not now
			or now < record.receivedAt
			or now - record.receivedAt >= (record.lifetime or LIFETIME)
			or self:IsIgnoredPlayerName(name)
		then
			state.questPartners[name] = nil
		end
	end
	if changed and self.RefreshQTPlayerPlatePresence then
		self:RefreshQTPlayerPlatePresence()
	end
	if self.RefreshQTPlayerPartnerIndicators then self:RefreshQTPlayerPartnerIndicators() end
end

function QT:UpdateQTPlayerPresence()
	if self.UpdatePartyJoin then self:UpdatePartyJoin() end
	self:BroadcastQTPlayerPresence()
	self:BroadcastQuestPartnerStatus()
	self:BroadcastAddonVersion()
	self:PruneQTPlayerPresence()
end

function QT:ShouldShowQTPlayerLogoForName(name)
	name = self:NormalizeMemberName(name)
	return self.isEnabled == true
		and name ~= nil
		and not self:IsSelfSender(name)
		and not self:IsIgnoredPlayerName(name)
		and self:IsKnownQTPlayer(name)
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
	return self:ShouldShowQTPlayerLogoForName(name), name
end
