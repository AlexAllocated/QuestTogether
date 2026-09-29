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

function QT:HandleAddonVersionMessage(payload, sender)
	if not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 50 then
		return false
	end
	local version = payload:match("^1,(.+)$")
	if not self:ParseAddonVersion(version) or not self:RecordQTPlayerPresence(sender, true) then
		return false
	end
	self:ObserveAddonVersion(version)
	return true
end

function QT:BroadcastAddonVersion()
	if not self.isEnabled or self.isLoggingOut then
		return false
	end
	local now = self.API and self.API.GetTime and self:SafeToNumber(self.API.GetTime())
	if not now then
		return false
	end
	local state = self:GetAddonUpdateState()
	if state.lastAttempt and now >= state.lastAttempt and now - state.lastAttempt < state.interval then
		return false
	end
	state.lastAttempt, state.interval = now, RETRY_INTERVAL
	local version = self:GetAddonVersion()
	if not self:ParseAddonVersion(version) then
		return false
	end
	-- Advertise only our installed version, never relay another peer's claim.
	-- Keep legacy presence unchanged and reuse the existing paced update frame.
	local sent =
		self:SendWireMessageToAnnouncementRoutes(self:SerializeWireMessage("QTVR", "1," .. version), "addon version")
	if sent then
		state.interval = BROADCAST_INTERVAL
	end
	return sent
end
