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

function QT:RememberPlayerAddonVersion(sender, version)
	local name = self:NormalizeMemberName(sender)
	if not name or not self:ParseAddonVersion(version) or not self:IsKnownQTPlayer(name) then return false end
	local state = self:GetQTPlayerPresenceState()
	state.peerVersions = state.peerVersions or {}
	state.peerVersions[name] = version
	return true
end

function QT:GetPlayerAddonVersion(sender)
	local name = self:NormalizeMemberName(sender)
	if not name then return nil end
	if self:IsSelfSender(name) then return self:GetAddonVersion() end
	if not self:IsKnownQTPlayer(name) then return nil end
	local state = rawget(self, "qtPlayerPresenceState")
	return state and state.peerVersions and state.peerVersions[name] or nil
end

function QT:GetLocalPartySize()
	if self:IsRuntimeRestricted() then return nil end
	local getter = self.API and self.API.GetPartyJoinInfo
	if type(getter) ~= "function" then return nil end
	local ok, grouped, _, size = pcall(getter)
	if not ok or not self:CanAccessValue(grouped) or type(grouped) ~= "boolean" then return nil end
	size = self:SafeToNumber(size)
	if not size or size < 0 or size > 40 or size ~= math.floor(size) then return nil end
	if not grouped then return size == 0 and 0 or nil end
	return size > 0 and size or nil
end

function QT:GetPlayerTooltipStats(sender)
	local name = self:NormalizeMemberName(sender)
	if not name then return nil end
	if self:IsSelfSender(name) then
		return { count = self:GetMonitoredQuestCount(), partySize = self:GetLocalPartySize() }
	end
	if not self:IsKnownQTPlayer(name) then return nil end
	local state = rawget(self, "qtPlayerPresenceState")
	local record = state and state.peerTooltipStats and state.peerTooltipStats[name]
	local now = self.API.GetTime and self:SafeToNumber(self.API.GetTime())
	if record and now and now >= record.at and now - record.at < (record.lifetime or 180) then return record end
end

function QT:GetPlayerMonitoredQuestCount(sender)
	local stats = self:GetPlayerTooltipStats(sender)
	return stats and stats.count
end

function QT:GetPlayerPartySize(sender)
	local stats = self:GetPlayerTooltipStats(sender)
	return stats and stats.partySize
end

function QT:HandleAddonVersionMessage(payload, sender)
	if not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 64 then
		return false
	end
	local version = payload:match("^1,(.+)$")
	local extended, count, partySize
	if not version then
		local rawCount, rawSize
		version, rawCount, rawSize = payload:match("^2,([^,]+),(%d*),(%d*)$")
		if not version then return false end
		extended = true
		if rawCount ~= "" then
			count = self:SafeToNumber(rawCount)
			if not count or count < 0 or count > 20000 or count ~= math.floor(count) then return false end
		end
		if rawSize ~= "" then
			partySize = self:SafeToNumber(rawSize)
			if not partySize or partySize > 40 or partySize < 0 or partySize ~= math.floor(partySize) then return false end
		end
	end
	local now = self.API.GetTime and self:SafeToNumber(self.API.GetTime())
	if not now or not self:ParseAddonVersion(version) or not self:RecordQTPlayerPresence(sender, true) then
		return false
	end
	self:RememberPlayerAddonVersion(sender, version)
	if extended then
		local state = self:GetQTPlayerPresenceState()
		state.peerTooltipStats = state.peerTooltipStats or {}
		state.peerTooltipStats[self:NormalizeMemberName(sender)] = { count = count, partySize = partySize, at = now }
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
	local interval = forPresenceHeartbeat and math.min(state.interval or RETRY_INTERVAL, RETRY_INTERVAL) or state.interval
	if state.lastAttempt and now >= state.lastAttempt and now - state.lastAttempt < interval then
		return false
	end
	state.lastAttempt, state.interval = now, RETRY_INTERVAL
	local geographic = rawget(self, "geographicCommsState")
	if forPresenceHeartbeat and not geographic then self:BroadcastPartyVisualMetadata() end
	local version = self:GetAddonVersion()
	if not self:ParseAddonVersion(version) then
		return false
	end
	-- Advertise only our installed version, never relay another peer's claim.
	-- Keep legacy presence unchanged and reuse the existing paced update frame.
	local payload = "1," .. version
	-- Alternate extended and legacy version heartbeats. Old clients require an
	-- exact version string; they must continue receiving readable advertisements.
	if forPresenceHeartbeat and (geographic or not state.lastVersionIncludedStats) then
		local count = self:GetMonitoredQuestCount()
		local partySize = self:GetLocalPartySize()
		payload = "2," .. version .. "," .. (count and tostring(count) or "") .. "," .. (partySize and tostring(partySize) or "")
		state.lastVersionIncludedStats = true
	else
		state.lastVersionIncludedStats = false
	end
	local sent = self:SendWireMessageToAnnouncementRoutes(self:SerializeWireMessage("QTVR", payload), "addon version")
	if sent then
		state.interval = BROADCAST_INTERVAL
	end
	return sent
end
