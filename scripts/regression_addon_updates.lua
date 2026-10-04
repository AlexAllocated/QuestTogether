-- Private peers, SavedVariables tables and transport adapters only. Live-safe.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

local function Peer(version, global, name)
	local a = setmetatable({
		version = version or "5.12.0",
		name = name or "Me-Realm",
		now = 100,
		hasLoggedIn = true,
		isEnabled = true,
		messages = {},
		sent = {},
		partyMembers = {},
		pendingPingRequests = {},
		recentCommMessageSignatures = {},
		announcementChannelName = "QuestTogether",
		announcementChannelLocalID = 7,
		db = { global = global or QT:DeepCopy(QT.DEFAULTS.global), profile = QT:DeepCopy(QT.DEFAULTS.profile) },
	}, { __index = QT })
	a.API = {
		GetTime = function()
			return a.now
		end,
		GetRealmName = function()
			return "Realm"
		end,
		RegionalUniqueNamesEnabled = function()
			return a.regional == true
		end,
		IsOnIgnoredList = function(other)
			return other == a.ignored
		end,
		GetChannelName = function()
			return 7
		end,
		SendAddonMessage = function(prefix, wire, route)
			a.sent[#a.sent + 1] = wire
			if a.sendFails then
				return false
			end
			if a.other then
				a.other:OnCommReceived(prefix, wire, route, a.name, 7, "QuestTogether")
			end
			return 0
		end,
	}
	function a:GetAddonVersion()
		return self.version
	end
	function a:GetPlayerFullName()
		return self.name
	end
	function a:GetPlayerName()
		return self.name
	end
	function a:EnsureAnnouncementChannelJoined()
		return true
	end
	function a:RecordCommsDiagnostic() end
	function a:Debug() end
	function a:Debugf() end
	function a:RefreshQTPlayerPlatePresence() end
	function a:Print(message)
		self.messages[#self.messages + 1] = message
	end
	function a:ReconcileQuestLogChatDestination() end
	function a:InitializeMinimapLauncher() end
	function a:InitializeReleaseNotes() end
	function a:Enable()
		self.isEnabled = true
	end
	function a:PrintPingResponse() end
	return a
end

QT:RegisterTest("player tooltip versions come from identified peers and clear with recognition", function()
	local a = Peer()
	Equal(a:GetPlayerAddonVersion(a.name), a.version)
	Equal(a:GetPlayerAddonVersion("Friend-Realm"), nil)
	assert(a:HandleAddonVersionMessage("1,5.11.0", "Friend-Realm"))
	Equal(a:GetPlayerAddonVersion("Friend-Realm"), "5.11.0")
	assert(a:HandleAddonVersionMessage("1,5.17.0-beta.1", "Friend-Realm"))
	Equal(a:GetPlayerAddonVersion("Friend-Realm"), "5.17.0-beta.1")
	Equal(a:GetAvailableAddonUpdate(), nil) -- Display beta versions without promoting beta update notices.
	Equal(a:RememberPlayerAddonVersion("Friend-Realm", "|Hbad|h"), false)
	Equal(a:GetPlayerAddonVersion("Friend-Realm"), "5.17.0-beta.1")
	a:RecordQTPlayerPresence("Friend-Realm", false)
	Equal(a:GetPlayerAddonVersion("Friend-Realm"), nil)
	Equal(a.qtPlayerPresenceState.peerVersions["Friend-Realm"], nil)
	assert(a:HandleAddonVersionMessage("1,5.11.1", "Friend-Realm"))
	a.ignored = "Friend-Realm"
	Equal(a:GetPlayerAddonVersion("Friend-Realm"), nil)
	a:PruneQTPlayerPresence(true)
	Equal(a.qtPlayerPresenceState.peerVersions["Friend-Realm"], nil)
end)

local function Receive(a, version, sender, route)
	a:OnCommReceived(a.commPrefix, "QTVR|1," .. version, route or "PARTY", sender or "Friend-Realm")
end

QT:RegisterTest("addon versions compare numeric components and supported prereleases in release order", function()
	for _, case in ipairs({
		{ "5.10.0", "5.9.99", 1 },
		{ "5.12.10", "5.12.9", 1 },
		{ "6.0.0", "5.99.99", 1 },
		{ "5.12.0", "5.12.0", 0 },
		{ "5.12.0-alpha.2", "5.12.0-alpha.10", -1 },
		{ "5.12.0-alpha.99", "5.12.0-beta.1", -1 },
		{ "5.12.0-beta.1", "5.12.0", -1 },
		{ "5.13.0-alpha.1", "5.12.99", 1 },
	}) do
		Equal(QT:CompareAddonVersions(case[1], case[2]), case[3])
		Equal(QT:CompareAddonVersions(case[2], case[1]), -case[3])
	end
end)

QT:RegisterTest("addon versions reject malformed excessive and inaccessible input", function()
	for _, value in ipairs({
		"",
		"5.12",
		"v5.12.0",
		" 5.12.0",
		"5.12.0 ",
		"05.12.0",
		"5.012.0",
		"5.12.-1",
		"5.12.0.1",
		"5.12.0garbage",
		"5.12.0+build",
		"5.12.0-rc.1",
		"5.12.0-beta.0",
		"5.12.0-beta.01",
		"5.12.0-BETA.1",
		"9999999.0.0",
		"5.12.0-alpha.9999999",
		"5.12.0|cffFFFFFF",
		"5.12.0\n",
		string.rep("1", 100),
		{},
		true,
		math.huge,
	}) do
		Equal(QT:ParseAddonVersion(value), nil)
		Equal(QT:CompareAddonVersions(value, "5.12.0"), nil)
	end
	local a = Peer()
	function a:CanAccessValue(value)
		return value ~= "6.0.0"
	end
	Equal(a:ParseAddonVersion("6.0.0"), nil)
end)

QT:RegisterTest("newer stable peers notify once and save the highest observed release", function()
	local a = Peer()
	Receive(a, "5.12.1")
	Equal(a.db.global.addonUpdateAvailable, true)
	Equal(a.db.global.availableAddonVersion, "5.12.1")
	Equal(#a.messages, 1)
	assert(a.messages[1]:find("5.12.1", 1, true))
	assert(a.messages[1]:find("installed: 5.12.0", 1, true))
	assert(a.messages[1]:find("addon manager", 1, true))
	Receive(a, "5.12.1", "Second-Realm")
	Receive(a, "5.13.0")
	Receive(a, "5.12.2", "Third-Realm")
	Equal(a:GetAvailableAddonUpdate(), "5.13.0")
	Equal(#a.messages, 1)
	Equal(#a.sent, 0) -- No request/reply amplification.
end)

QT:RegisterTest("equal older and alpha beta versions never create update notices", function()
	local a = Peer()
	for _, version in ipairs({ "5.12.0", "5.11.99", "5.13.0-alpha.1", "6.0.0-beta.1" }) do
		Receive(a, version)
	end
	Equal(#a.messages, 0)
	Equal(a:GetAvailableAddonUpdate(), nil)
	Equal(a.db.global.addonUpdateAvailable, false)
	assert(a:IsKnownQTPlayer("Friend-Realm"))
	local beta = Peer("5.13.0-beta.10")
	Receive(beta, "5.13.0")
	Equal(beta:GetAvailableAddonUpdate(), "5.13.0")
	Equal(#beta.messages, 1)
end)

QT:RegisterTest("saved update notices repeat on login reload and another character without peer contact", function()
	local a = Peer()
	Receive(a, "5.13.0")
	local saved = QT:DeepCopy(a.db.global)
	for _, name in ipairs({ "Me-Realm", "Alt-Realm" }) do
		local reloaded = Peer("5.12.0", saved, name)
		reloaded.isEnabled, reloaded.db.profile.enabled = false, false
		reloaded:OnLogin()
		Equal(#reloaded.messages, 1)
		Equal(reloaded.db.global.addonUpdateAvailable, true)
		reloaded:OnLogin()
		reloaded.db.profile = { enabled = true }
		reloaded:OnLogin()
		Equal(#reloaded.messages, 1)
	end
end)

QT:RegisterTest("installing the observed release or newer clears persisted update state", function()
	for _, version in ipairs({ "5.13.0", "5.13.1", "6.0.0" }) do
		local a = Peer(version, { availableAddonVersion = "5.13.0", addonUpdateAvailable = true })
		a:OnLogin()
		Equal(a.db.global.addonUpdateAvailable, false)
		Equal(a.db.global.availableAddonVersion, "")
		Equal(#a.messages, 0)
		Receive(a, "5.12.99")
		Equal(#a.messages, 0)
	end
	local partial = Peer("5.12.1", { availableAddonVersion = "5.13.0", addonUpdateAvailable = true })
	partial:OnLogin()
	Equal(partial:GetAvailableAddonUpdate(), "5.13.0")
	Equal(#partial.messages, 1)
end)

QT:RegisterTest(
	"saved notices reconcile stale flags and corrupt data without repeating old welcome messages",
	function()
		for _, value in ipairs({ "garbage", "6.0.0-beta.1", true, {} }) do
			local a = Peer("5.12.0", { availableAddonVersion = value, addonUpdateAvailable = true })
			a:OnLogin()
			Equal(a.db.global.addonUpdateAvailable, false)
			Equal(a.db.global.availableAddonVersion, "")
			Equal(#a.messages, 0)
		end
		local a = Peer("5.12.0", { availableAddonVersion = "5.13.0", addonUpdateAvailable = false })
		a:OnLogin()
		Equal(a.db.global.addonUpdateAvailable, true)
		Equal(#a.messages, 1)
	end
)

QT:RegisterTest("unknown local versions preserve observed releases until an installed version is readable", function()
	local a = Peer("development", { availableAddonVersion = "5.13.0", addonUpdateAvailable = true })
	a:OnLogin()
	Equal(a.db.global.availableAddonVersion, "5.13.0")
	Equal(a.db.global.addonUpdateAvailable, true)
	Equal(#a.messages, 0)
	Receive(a, "6.0.0")
	Equal(a.db.global.availableAddonVersion, "5.13.0")
	a.version = "5.12.0"
	assert(a:NotifyAddonUpdate())
	Equal(#a.messages, 1)
end)

QT:RegisterTest("version discovery honors transport sender channel ignore and enabled boundaries", function()
	for _, boundary in ipairs({ "prefix", "whisper", "channel", "self", "ignored", "disabled", "sender" }) do
		local a = Peer()
		local prefix, route, sender, localID = a.commPrefix, "PARTY", "Friend-Realm", 7
		if boundary == "prefix" then
			prefix = "OtherAddon"
		elseif boundary == "whisper" then
			route = "WHISPER"
		elseif boundary == "channel" then
			route, localID = "CHANNEL", 8
		elseif boundary == "self" then
			sender = a.name
		elseif boundary == "ignored" then
			a.ignored = sender
		elseif boundary == "disabled" then
			a.isEnabled = false
		else
			sender = ""
		end
		a:OnCommReceived(prefix, "QTVR|1,6.0.0", route, sender, localID, "OtherChannel")
		Equal(a:GetAvailableAddonUpdate(), nil)
		Equal(#a.messages, 0)
	end
	for _, payload in ipairs({
		"",
		"2,6.0.0",
		"1,6.0.0,spoof",
		"1,6.0.0|junk",
		"1,6.0.0\n",
		"1," .. string.rep("1", 100),
	}) do
		local a = Peer()
		a:OnCommReceived(a.commPrefix, "QTVR|" .. payload, "PARTY", "Friend-Realm")
		Equal(a:GetAvailableAddonUpdate(), nil)
		Equal(a:IsKnownQTPlayer("Friend-Realm"), false)
	end
end)

QT:RegisterTest("version broadcasts work through real routing on Retail and Forever names", function()
	for _, regional in ipairs({ false, true }) do
		local sender = Peer("5.13.0", nil, regional and "Torres Sky" or "Torres-Realm")
		local receiver = Peer("5.12.0", nil, regional and "Mira Dawn" or "Mira-Realm")
		sender.regional, receiver.regional, sender.other = regional, regional, receiver
		sender.db.profile.sharePlayerLocation = false
		assert(sender:BroadcastAddonVersion())
		Equal(sender.sent[1], "QTVR|1,5.13.0")
		Equal(receiver:GetAvailableAddonUpdate(), "5.13.0")
		Equal(#receiver.messages, 1)
		assert(receiver:IsKnownQTPlayer(sender.name))
		Equal(#receiver.sent, 0)
	end
end)

QT:RegisterTest("version announcements are paced across success failure and comms resets", function()
	local a = Peer()
	assert(a:BroadcastAddonVersion())
	for _, now in ipairs({ 100, 101, 120, 399 }) do
		a.now = now
		Equal(a:BroadcastAddonVersion(), false)
	end
	Equal(#a.sent, 1)
	a:ResetCommsState()
	Equal(a:BroadcastAddonVersion(), false)
	a.now = 400
	assert(a:BroadcastAddonVersion())
	Equal(#a.sent, 2)
	a.now, a.sendFails = 700, true
	Equal(a:BroadcastAddonVersion(), false)
	a.now = 719
	Equal(a:BroadcastAddonVersion(), false)
	Equal(#a.sent, 3)
	a.now, a.sendFails = 720, false
	assert(a:BroadcastAddonVersion())
	Equal(#a.sent, 4)
	a.isEnabled, a.now = false, 2000
	Equal(a:BroadcastAddonVersion(), false)
	a.isEnabled, a.isLoggingOut = true, true
	Equal(a:BroadcastAddonVersion(), false)
	Equal(#a.sent, 4)
end)

QT:RegisterTest("receiving a newer release never makes us advertise its version", function()
	local a = Peer()
	Receive(a, "6.0.0")
	assert(a:BroadcastAddonVersion())
	Equal(a.sent[1], "QTVR|1,5.12.0")
	a:ResetCommsState()
	Equal(a:GetAvailableAddonUpdate(), "6.0.0")
	Equal(a:NotifyAddonUpdate(), false)
	Equal(#a.messages, 1)
end)

QT:RegisterTest("validated legacy ping responses discover versions without requiring an active ping", function()
	local a = Peer()
	local payload =
		a:EncodePingResponsePayload({ requestId = "older-peer", senderName = "Claimed-Realm", addonVersion = "5.13.0" })
	a:OnCommReceived(a.commPrefix, "PONG|" .. payload, "PARTY", "Friend-Realm")
	Equal(a:GetAvailableAddonUpdate(), "5.13.0")
	Equal(#a.messages, 1)
	assert(a:IsKnownQTPlayer("Friend-Realm"))
	Equal(a:IsKnownQTPlayer("Claimed-Realm"), false)
	local old = Peer()
	payload = old:EncodePingResponsePayload({ requestId = "old", senderName = "Friend-Realm" })
	old:OnCommReceived(old.commPrefix, "PONG|" .. payload, "PARTY", "Friend-Realm")
	Equal(old:GetAvailableAddonUpdate(), nil)
	Equal(#old.messages, 0)
end)

QT:RegisterTest("presence alternates compatible version packets without adding heartbeat messages", function()
	local a = Peer()
	a:UpdateQTPlayerPresence()
	Equal(a.sent[1], "QTPR|1,1")
	Equal(a.sent[2], "QTVR|1,5.12.0")
	Equal(#a.sent, 2)
	a.now = 120
	a:UpdateQTPlayerPresence()
	Equal(a.sent[3], "QTVR|1,5.12.0")
	Equal(#a.sent, 3)
	a.now = 140
	a:UpdateQTPlayerPresence()
	Equal(a.sent[4], "QTPR|1,1")
	Equal(#a.sent, 4)
	a.now = 160
	a:UpdateQTPlayerPresence()
	Equal(a.sent[5], "QTVR|1,5.12.0")
	Equal(#a.sent, 5)
	a:BroadcastQTPlayerPresence(true)
	Equal(a.sent[6], "QTPR|1,0")
	Equal(#a.sent, 6)
end)

QT:RegisterTest("a reloaded observer learns versions from heartbeats without ping or location sharing", function()
	for _, regional in ipairs({ false, true }) do
		local sender = Peer("5.13.0", nil, regional and "Torres Sky" or "Torres-Realm")
		local receiver = Peer("5.13.0", nil, regional and "Mira Dawn" or "Mira-Realm")
		sender.regional, receiver.regional, sender.other = regional, regional, receiver
		sender.db.profile.sharePlayerLocation = false
		sender:UpdateQTPlayerPresence()
		Equal(receiver:GetPlayerAddonVersion(sender.name), "5.13.0")
		-- Reload after the last version packet, then see a legacy heartbeat
		-- before the next version slot. Neither observer sends any requests.
		sender.now = 120
		sender:UpdateQTPlayerPresence()
		receiver.qtPlayerPresenceState = nil
		receiver.recentCommMessageSignatures = {}
		Equal(receiver:GetPlayerAddonVersion(sender.name), nil)
		sender.now, receiver.now = 140, 140
		sender:UpdateQTPlayerPresence()
		assert(receiver:IsKnownQTPlayer(sender.name))
		Equal(receiver:GetPlayerAddonVersion(sender.name), nil)
		sender.now, receiver.now = 160, 160
		sender:UpdateQTPlayerPresence()
		Equal(receiver:GetPlayerAddonVersion(sender.name), "5.13.0")
		Equal(#sender.sent, 5)
		Equal(#receiver.sent, 0)
		Equal(#receiver.messages, 0)
		sender:BroadcastQTPlayerPresence(true)
		Equal(receiver:GetPlayerAddonVersion(sender.name), nil)
	end
end)

QT:RegisterTest("version heartbeat failures remain paced and invalid versions retain legacy discovery", function()
	local a = Peer()
	a:UpdateQTPlayerPresence()
	a.now, a.sendFails = 120, true
	a:UpdateQTPlayerPresence()
	Equal(#a.sent, 3)
	a.now = 121
	a:UpdateQTPlayerPresence()
	Equal(#a.sent, 3)
	a.now, a.sendFails = 140, false
	a:UpdateQTPlayerPresence()
	Equal(#a.sent, 5) -- Legacy heartbeat plus the due failed-version retry.
	a.version, a.now = "unknown", 160
	a:UpdateQTPlayerPresence()
	Equal(a.sent[6], "QTPR|1,1")
	Equal(#a.sent, 6)
end)
