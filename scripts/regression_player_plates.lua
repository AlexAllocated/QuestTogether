-- Live-safe: only addon-owned adapters and private frames are replaced.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function Patch(values, run)
	local old = {}
	for key, value in pairs(values) do
		old[key], QT[key] = QT[key], value
	end
	local ok, err = pcall(run)
	for key in pairs(values) do
		QT[key] = old[key]
	end
	assert(ok, err)
end
local function Peer(name)
	local a = setmetatable({
		isEnabled = true,
		now = 100,
		name = name or "Me-Realm",
		sent = {},
		announcementChannelName = "QuestTogether",
		announcementChannelLocalID = 7,
		nameplateRegisteredEvents = {},
		qtPlayerIconStateByFrame = {},
		recentCommMessageSignatures = {},
	}, { __index = QT })
	function a:AnnounceQuestPartnerSearch() end
	a.db = { profile = QT:DeepCopy(QT.DEFAULTS.profile) }
	a.API = {
		GetTime = function()
			return a.now
		end,
		GetRealmName = function()
			return "Realm"
		end,
		RegionalUniqueNamesEnabled = function()
			return a.forever == true
		end,
		IsOnIgnoredList = function(other)
			return a.ignored == other
		end,
		GetChannelName = function()
			return 7
		end,
		SendAddonMessage = function(prefix, message, route)
			a.sent[#a.sent + 1] = message
			if a.sendFails then
				return false
			end
			if a.other then
				a.other:OnCommReceived(prefix, message, route, a.name, 7, "QuestTogether")
			end
			return 0
		end,
	}
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
	function a:RefreshQTPlayerPlatePresence()
		self.refreshes = (self.refreshes or 0) + 1
	end
	function a:Print(message)
		self.messages = self.messages or {}
		self.messages[#self.messages + 1] = message
	end
	function a:IsRuntimeRestricted()
		return self.restricted == true
	end
	function a:RefreshOptionsWindow()
		self.optionRefreshes = (self.optionRefreshes or 0) + 1
	end
	return a
end

local function PartnerPayload(addon, looking, session, sequence)
	addon.partnerTestSequence = (addon.partnerTestSequence or 0) + 1
	return string.format("1,%s,%d,%d", session or "10-1234", sequence or addon.partnerTestSequence, looking and 1 or 0)
end

QT:RegisterTest("log QT prefixes reflect current local and remote partner status without replacing specific icons", function()
	local a = Peer()
	local logo = a.NAMEPLATE_PLAYER_ICON_TEXTURE
	local glow = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherPartnerIcon"
	local function Prefix(name, expected, event, asset, kind)
		local message = a:BuildConsoleAnnouncementMessage(name, "hello", "MAGE", event or "SCAN_STATUS", asset, kind)
		local tag = a:GetIconChatTagFromAsset(expected, kind or "texture", 14)
		Equal(message:sub(1, #tag), tag)
	end
	Prefix(a.name, logo)
	a.db.profile.lookingForQuestPartners = true
	Prefix(a.name, glow)
	a.db.profile.lookingForQuestPartners = false
	Prefix(a.name, logo)

	local remote = "Friend-Realm"
	Prefix(remote, logo)
	assert(a:HandleQuestPartnerStatusMessage(PartnerPayload(a, true), remote))
	Prefix(remote, glow)
	Prefix(remote, glow, "SCAN_STATUS", logo:gsub("\\", "/"), "texture")
	Prefix(remote, glow, "SCAN_STATUS", a.NAMEPLATE_QUEST_ICON_TEXTURE, "texture")
	Prefix(remote, "Interface\\AddOns\\QuestTogether\\Media\\ChatBubbleIcon", "QT_CHAT")
	Prefix(remote, "UI-QuestIcon-TurnIn-Normal", "QUEST_COMPLETED", "UI-QuestIcon-TurnIn-Normal", "atlas")
	Prefix(remote, "Interface/GossipFrame/AvailableQuestIcon", "QUEST_ACCEPTED", "Interface/GossipFrame/AvailableQuestIcon", "texture")
	a.ignored = remote
	Prefix(remote, logo)
	a.ignored = nil
	assert(a:HandleQuestPartnerStatusMessage(PartnerPayload(a, false), remote))
	Prefix(remote, logo)
	assert(a:HandleQuestPartnerStatusMessage(PartnerPayload(a, true), remote))
	a.now = a.now + 1000
	Prefix(remote, logo)
	-- The LFQP announcement itself retains its existing glow, even without status.
	Prefix(remote, glow, "LOOKING_FOR_QUEST_PARTNERS")
	Equal(a:GetAnnouncementIconChatTag("SCAN_STATUS", 14), a:GetIconChatTagFromAsset(logo, "texture", 14))
end)

QT:RegisterTest("joining a group optionally clears partner status without announcements or roster churn", function()
	local a = Peer()
	local changes = 0
	function a:HandleGroupRosterChanged() changes = changes + 1 end
	Equal(a:GetOption("stopLookingForPartnersOnJoin"), false)
	a:SetOption("lookingForQuestPartners", true)
	a:GROUP_JOINED()
	Equal(a:GetOption("lookingForQuestPartners"), true)
	Equal(a:SetOption("stopLookingForPartnersOnJoin", "true"), false)
	Equal(a:SetOption("stopLookingForPartnersOnJoin", true), true)
	function a:AnnounceQuestPartnerSearch() error("turning LFQP off must be silent") end
	a:GROUP_JOINED()
	Equal(a:GetOption("lookingForQuestPartners"), false)
	assert(a.sent[#a.sent]:match("^QTLF|.+,0$"), "joining must withdraw advertised partner status")
	local sent = #a.sent
	a:GROUP_JOINED()
	Equal(#a.sent, sent)
	-- A player can resume recruiting in their group without roster updates
	-- immediately undoing that choice.
	a.db.profile.lookingForQuestPartners = true
	a:GROUP_ROSTER_UPDATE()
	Equal(a:GetOption("lookingForQuestPartners"), true)
	a.isEnabled = false
	a:GROUP_JOINED()
	Equal(a:GetOption("lookingForQuestPartners"), true)
	a.isEnabled, a.isLoggingOut = true, true
	a:GROUP_JOINED()
	Equal(a:GetOption("lookingForQuestPartners"), true)
	Equal(changes, 6)
end)
local function PartnerWire(message, looking)
	assert(message:match("^QTLF|1,%d+%-%d+,%d+," .. (looking and "1" or "0") .. "$"), message)
end

local function DiscoveryMessages(addon)
	-- Claimed payload identities and compare/share recipients deliberately differ
	-- from the transport sender. They must never receive the sender's logo.
	return {
		ANN = addon:EncodeAnnouncementPayload({
			eventType = "QUEST_ACCEPTED",
			senderName = "Claimed-Realm",
			text = "Quest accepted",
			questId = 42,
		}),
		LVL = addon:EncodeAnnouncementPayload({
			eventType = "PLAYER_LEVEL_UP",
			senderName = "Claimed-Realm",
			text = "Level 60",
			questId = 0,
		}),
		PING = addon:EncodePingRequestPayload({ requestId = "discovery", requesterName = "Claimed-Realm" }),
		PONG = addon:EncodePingResponsePayload({ requestId = "discovery", senderName = "Claimed-Realm" }),
		QCMP = addon:EncodeQuestCompareRequestPayload({
			requestId = "discovery",
			requesterName = "Claimed-Realm",
			targetName = "Third-Realm",
		}),
		QCQE = addon:EncodeQuestCompareEntryPayload({
			requestId = "discovery",
			senderName = "Claimed-Realm",
			questId = 42,
			questTitle = "A quest",
		}),
		QCDN = addon:EncodeQuestCompareDonePayload({ requestId = "discovery", senderName = "Claimed-Realm", count = 0 }),
		QSHR = "1,discovery,Third-Realm,42,request",
		QTPR = "1,1",
		QTVR = "1,5.12.0",
		QTLF = "1,100-1234,1,1",
		LOC = "1,100-1234,1,3,12,0.4,0.6,MAGE,Mage,Human,Alliance,60,0",
	}
end

local function IgnoreDiscoveryActions(addon)
	-- Private display/action boundaries: receive and decode real protocol data
	-- without printing, answering requests, touching quests, or creating UI.
	addon.HandleAnnouncementEvent = function() end
	addon.HandlePingRequest = function() end
	addon.HandlePingResponse = function() end
	addon.HandleQuestCompareRequest = function() end
	addon.HandleQuestCompareEntry = function() end
	addon.HandleQuestCompareDone = function() end
	addon.IsGroupedSender = function()
		return true
	end
end

QT:RegisterTest("every supported communication discovers only its authenticated QT sender", function()
	for command, payload in pairs(DiscoveryMessages(QT)) do
		for _, regional in ipairs({ false, true }) do
			local a = Peer(regional and "Joe Bucket" or "Me-Realm")
			a.forever = regional
			IgnoreDiscoveryActions(a)
			local sender = regional and "Anakin Othername" or "Friend-Realm"
			local message = command .. "|" .. payload
			a:OnCommReceived("UnrelatedPrefix", message, "PARTY", sender)
			a:OnCommReceived(a.commPrefix, message, "GUILD", sender)
			a:OnCommReceived(a.commPrefix, message, "CHANNEL", sender, 8, "OtherChannel")
			a:OnCommReceived(a.commPrefix, message, "PARTY", a.name)
			a:OnCommReceived(a.commPrefix, command .. "|malformed", "PARTY", sender)
			Equal(a:IsKnownQTPlayer(sender), false)
			a.ignored = sender
			a:OnCommReceived(a.commPrefix, message, "PARTY", sender)
			Equal(a:IsKnownQTPlayer(sender), false)
			a.ignored, a.isEnabled = nil, false
			a:OnCommReceived(a.commPrefix, message, "PARTY", sender)
			Equal(a:IsKnownQTPlayer(sender), false)
			a.isEnabled = true
			a:OnCommReceived(a.commPrefix, message, "PARTY", sender)
			assert(a:IsKnownQTPlayer(sender), command .. " should identify its sender")
			Equal(a:IsKnownQTPlayer("Claimed-Realm"), false)
			Equal(a:IsKnownQTPlayer("Third-Realm"), false)
			Equal(a:IsKnownQTPlayer(a.name), false)
			Equal(a.refreshes, 1)
			Equal(#a.sent, 0, "recognition must not add traffic")
			Equal(a:IsPlayerLookingForQuestPartners(sender), command == "QTLF")
		end
	end
end)

QT:RegisterTest("share replies identify peers independently of a current outgoing request", function()
	for _, status in ipairs({ "pending", "sent", "declined", "expired", "unavailable" }) do
		local a = Peer()
		a.IsGroupedSender = function()
			return true
		end
		a:OnCommReceived(a.commPrefix, "QSHR|1,old-request,Me-Realm,42," .. status, "PARTY", "Friend-Realm")
		assert(a:IsKnownQTPlayer("Friend-Realm"), status)
		Equal(next(a:GetPartyQuestShareState().outgoing), nil)
		Equal(#a.sent, 0)
	end
end)

QT:RegisterTest("share traffic identifies a sender before the roster catches up without authorizing a share", function()
	local a = Peer()
	a.IsGroupedSender = function()
		return false
	end
	a.GetQuestShareAvailability = function()
		error("unverified party member cannot request a share")
	end
	a:OnCommReceived(a.commPrefix, "QSHR|1,discovery,Me-Realm,42,request", "PARTY", "Friend-Realm")
	assert(a:IsKnownQTPlayer("Friend-Realm"))
	Equal(rawget(a, "partyQuestShareState"), nil)
	Equal(#a.sent, 0)
end)

QT:RegisterTest("ordered partner updates reject delayed routes and retired sessions after withdrawal", function()
	local a, b = Peer(), Peer("Friend-Realm")
	a.other = b
	a:SetOption("lookingForQuestPartners", true)
	local oldOn = a.sent[1]
	a:SetOption("lookingForQuestPartners", false)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	b.now = 101 -- Beyond content deduplication; sequence ordering must still reject the copy.
	b:OnCommReceived(a.commPrefix, oldOn, "CHANNEL", a.name, 7, "QuestTogether")
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	local offRecord = b.qtPlayerPresenceState.questPartners[a.name]
	Equal(offRecord.receivedAt, 100)
	-- Departure must retain ordering information; legacy presence cannot renew it.
	a:BroadcastQTPlayerPresence(true)
	b.now = 102
	b:OnCommReceived(a.commPrefix, oldOn, "PARTY", a.name)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	assert(b:HandleQuestPartnerStatusMessage(PartnerPayload(b, true, "200-1234", 1), a.name))
	assert(b:IsPlayerLookingForQuestPartners(a.name))
	b.now = 103
	b:OnCommReceived(a.commPrefix, oldOn, "PARTY", a.name)
	assert(b:IsPlayerLookingForQuestPartners(a.name))
	Equal(b.qtPlayerPresenceState.questPartners[a.name].session, "200-1234")
end)

QT:RegisterTest("rapid presence departures and rejoins cannot retain a partner advertisement", function()
	local a, b = Peer(), Peer("Friend-Realm")
	a.other = b
	for _ = 1, 2 do
		a:SetOption("lookingForQuestPartners", true)
		assert(b:IsPlayerLookingForQuestPartners(a.name))
		a:BroadcastQTPlayerPresence(true)
		Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
		Equal(b:IsKnownQTPlayer(a.name), false)
	end
end)

QT:RegisterTest("legacy departure conservatively hides partners until a newer ordered heartbeat", function()
	local a, b = Peer(), Peer("Friend-Realm")
	a.other = b
	a:SetOption("lookingForQuestPartners", true)
	a:BroadcastQTPlayerPresence(true)
	a:SetOption("lookingForQuestPartners", true)
	assert(b:IsPlayerLookingForQuestPartners(a.name))
	b.now = 101
	b:OnCommReceived(a.commPrefix, "QTPR|1,0", "CHANNEL", a.name, 7, "QuestTogether")
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	a:BroadcastQuestPartnerStatus(true)
	assert(b:IsPlayerLookingForQuestPartners(a.name))
	a:SetOption("lookingForQuestPartners", false)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
end)

QT:RegisterTest("partner status stays quiet by default and ends withdrawal retries at expiry", function()
	local a = Peer()
	for now = 100, 220, 20 do
		a.now = now
		Equal(a:BroadcastQuestPartnerStatus(), false)
	end
	Equal(#a.sent, 0)
	a:SetOption("lookingForQuestPartners", true)
	a:SetOption("lookingForQuestPartners", false)
	for now = 240, 280, 20 do
		a.now = now
		assert(a:BroadcastQuestPartnerStatus())
	end
	a.now = 300
	Equal(a:BroadcastQuestPartnerStatus(), false)
	Equal(#a.sent, 5)
end)

QT:RegisterTest("quest partner status is opt in and independent of location and legacy presence", function()
	local a, b = Peer("Anakin Othername"), Peer("Luke Bucket")
	a.forever, b.forever, a.other = true, true, b
	a.db.profile.sharePlayerLocation = false
	Equal(a:GetOption("lookingForQuestPartners"), false)
	a:UpdateQTPlayerPresence()
	Equal(a.sent[1], "QTPR|1,1")
	Equal(#a.sent, 1)
	Equal(a:BroadcastQuestPartnerStatus(), false)
	assert(b:IsKnownQTPlayer(a.name))
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	assert(a:SetOption("lookingForQuestPartners", true))
	PartnerWire(a.sent[2], true)
	assert(b:IsPlayerLookingForQuestPartners(a.name))
	assert(a:IsPlayerLookingForQuestPartners(a.name))
	Equal(b:IsPlayerLookingForQuestPartners("Anakin Someoneelse"), false)
	-- Rapid changes must survive the general comms duplicate window.
	a:SetOption("lookingForQuestPartners", false)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	a:SetOption("lookingForQuestPartners", true)
	assert(b:IsPlayerLookingForQuestPartners(a.name))
	a:BroadcastQTPlayerPresence(true)
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	Equal(b.qtPlayerPresenceState.questPartners[a.name].looking, false)
end)

QT:RegisterTest("quest partner status expires independently and prunes ignored evicted and expired peers", function()
	local a = Peer()
	assert(a:HandleQuestPartnerStatusMessage(PartnerPayload(a, true), "Friend-Realm"))
	a.now = 164
	assert(a:IsPlayerLookingForQuestPartners("Friend-Realm"))
	assert(a:HandleQTPlayerPresenceMessage("1,1", "Friend-Realm"))
	a.now = 165
	assert(a:IsKnownQTPlayer("Friend-Realm"))
	Equal(a:IsPlayerLookingForQuestPartners("Friend-Realm"), false)
	a:PruneQTPlayerPresence(true)
	Equal(a.qtPlayerPresenceState.questPartners["Friend-Realm"], nil)
	a:HandleQuestPartnerStatusMessage(PartnerPayload(a, true), "Friend-Realm")
	a.now = 164 -- A regressed clock must not keep a status alive.
	Equal(a:IsPlayerLookingForQuestPartners("Friend-Realm"), false)
	a:PruneQTPlayerPresence(true)
	Equal(next(a.qtPlayerPresenceState.questPartners), nil)
	for i = 1, 270 do
		a.now = 200 + i / 10
		assert(a:HandleQuestPartnerStatusMessage(PartnerPayload(a, true), "Peer" .. i .. "-Realm"))
	end
	local count = 0
	for name in pairs(a.qtPlayerPresenceState.questPartners) do
		count = count + 1
		assert(a.qtPlayerPresenceState.peers[name])
	end
	Equal(count, 256)
	Equal(a:IsPlayerLookingForQuestPartners("Peer1-Realm"), false)
	a.ignored = "Peer270-Realm"
	Equal(a:IsPlayerLookingForQuestPartners(a.ignored), false)
	a:PruneQTPlayerPresence(true)
	Equal(a.qtPlayerPresenceState.questPartners[a.ignored], nil)
	a.isEnabled = false
	Equal(a:IsPlayerLookingForQuestPartners("Peer269-Realm"), false)
end)

QT:RegisterTest("quest partner messages validate routes identity payload and disabled state", function()
	local a = Peer()
	for _, payload in ipairs({ "", "2,1", "1,2", "1,true", "1,1,Someone-Realm" }) do
		a:OnCommReceived(a.commPrefix, "QTLF|" .. payload, "PARTY", "Friend-Realm")
	end
	a:OnCommReceived(a.commPrefix, "QTLF|" .. PartnerPayload(a, true), "WHISPER", "Friend-Realm")
	a:OnCommReceived(a.commPrefix, "QTLF|" .. PartnerPayload(a, true), "CHANNEL", "Friend-Realm", 8, "Other")
	a:OnCommReceived(a.commPrefix, "QTLF|" .. PartnerPayload(a, true), "PARTY", a.name)
	a.ignored = "Ignored-Realm"
	a:OnCommReceived(a.commPrefix, "QTLF|" .. PartnerPayload(a, true), "PARTY", a.ignored)
	Equal(rawget(a, "qtPlayerPresenceState"), nil)
	for _, route in ipairs({ "PARTY", "RAID", "INSTANCE_CHAT" }) do
		a:OnCommReceived(a.commPrefix, "QTLF|" .. PartnerPayload(a, true), route, "Friend-Realm")
		assert(a:IsPlayerLookingForQuestPartners("Friend-Realm"))
		a:OnCommReceived(a.commPrefix, "QTLF|" .. PartnerPayload(a, false), route, "Friend-Realm")
		Equal(a:IsPlayerLookingForQuestPartners("Friend-Realm"), false)
	end
	a.isEnabled = false
	a:OnCommReceived(a.commPrefix, "QTLF|" .. PartnerPayload(a, true), "PARTY", "Friend-Realm")
	Equal(a.qtPlayerPresenceState.questPartners["Friend-Realm"].looking, false)
end)

QT:RegisterTest("quest partner heartbeat paces failures and retries the latest status", function()
	local a, b = Peer(), Peer("Friend-Realm")
	a.other = b
	a:SetOption("lookingForQuestPartners", true)
	assert(b:IsPlayerLookingForQuestPartners(a.name))
	a.sendFails = true
	a:SetOption("lookingForQuestPartners", false)
	assert(b:IsPlayerLookingForQuestPartners(a.name))
	a.now = 119
	Equal(a:BroadcastQuestPartnerStatus(), false)
	Equal(#a.sent, 2)
	a.now, a.sendFails, b.now = 120, false, 120
	assert(a:BroadcastQuestPartnerStatus())
	Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	Equal(#a.sent, 3)
	a.isLoggingOut, a.now = true, 200
	Equal(a:BroadcastQuestPartnerStatus(true), false)
	a.isLoggingOut, a.isEnabled = false, false
	Equal(a:BroadcastQuestPartnerStatus(true), false)
end)

QT:RegisterTest(
	"quest partner slash command validates arguments saves preference and reports disabled state",
	function()
		local a = Peer()
		assert(a:HandleSlashCommand("lfg"))
		Equal(a:GetOption("lookingForQuestPartners"), true)
		Equal(a.optionRefreshes, 1)
		PartnerWire(a.sent[1], true)
		assert(a:HandleSlashCommand(" LFG   STATUS "))
		Equal(#a.sent, 1)
		Equal(a.optionRefreshes, 1)
		assert(a.messages[2]:find("On", 1, true))
		Equal(a:HandleSlashCommand("lfg nonsense"), false)
		Equal(#a.sent, 1)
		Equal(a:SetOption("lookingForQuestPartners", "true"), false)
		Equal(a:GetOption("lookingForQuestPartners"), true)
		assert(a:HandleSlashCommand("lfg off"))
		Equal(a:GetOption("lookingForQuestPartners"), false)
		a.restricted = true
		assert(a:HandleSlashCommand("lfg toggle"))
		Equal(a.optionRefreshes, 2)
		a.isEnabled = false
		assert(a:HandleSlashCommand("lfg on"))
		assert(a.messages[#a.messages]:find("paused", 1, true))
		Equal(#a.sent, 3)
		Equal(a:IsPlayerLookingForQuestPartners(a.name), false)
	end
)

QT:RegisterTest("player menus advertise only a current explicit quest partner status", function()
	local a = Peer()
	local function Menu()
		local titles = {}
		local menu = {
			CreateTitle = function(_, text)
				titles[#titles + 1] = text
			end,
			CreateButton = function() end,
			CreateDivider = function() end,
		}
		a:PopulateChatLogSpeakerMenu(menu, {}, "Friend-Realm")
		return titles
	end
	Equal(#Menu(), 1)
	a:HandleQuestPartnerStatusMessage(PartnerPayload(a, true), "Friend-Realm")
	Equal(Menu()[2], "Looking for Questing Partners")
	a.now = 165
	Equal(#Menu(), 1)
	a:HandleQuestPartnerStatusMessage(PartnerPayload(a, true), "Friend-Realm")
	a.ignored = "Friend-Realm"
	Equal(#Menu(), 1)
end)

QT:RegisterTest(
	"quest partner status withdraws on departure and runtime resets retain only the saved preference",
	function()
		local a, b = Peer(), Peer("Friend-Realm")
		a.other = b
		function a:BroadcastPlayerLocation() end
		function a:ResetPlayerLocations() end
		function a:ResetPartyQuestCompare() end
		a:SetOption("lookingForQuestPartners", true)
		assert(b:IsPlayerLookingForQuestPartners(a.name))
		a:PLAYER_LEAVING_WORLD()
		assert(a.isLoggingOut)
		Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
		Equal(a:BroadcastQuestPartnerStatus(true), false)
		a.isLoggingOut, a.now, b.now = false, 101, 101
		assert(a:RecordQTPlayerPresence(b.name, true))
		assert(a:IsKnownQTPlayer(b.name))
		a:ResetCommsState()
		Equal(rawget(a, "qtPlayerPresenceState"), nil)
		Equal(a:IsKnownQTPlayer(b.name), false)
		Equal(a:GetOption("lookingForQuestPartners"), true)
		assert(a:BroadcastQuestPartnerStatus())
		assert(b:IsPlayerLookingForQuestPartners(a.name))
		-- Loading another profile advertises its own preference on the next forced update.
		a.db.profile = QT:DeepCopy(QT.DEFAULTS.profile)
		assert(a:BroadcastQuestPartnerStatus(true))
		Equal(b:IsPlayerLookingForQuestPartners(a.name), false)
	end
)

QT:RegisterTest("QT presence authenticates transport and survives disabled location sharing", function()
	local a, b = Peer("Anakin Othername"), Peer("Luke Bucket")
	a.forever, b.forever, a.other = true, true, b
	a.db.profile.sharePlayerLocation = false
	assert(a:BroadcastQTPlayerPresence())
	Equal(a.sent[1], "QTPR|1,1")
	assert(b:IsKnownQTPlayer(a.name))
	Equal(b:IsKnownQTPlayer("Anakin Someoneelse"), false)
	b:OnCommReceived(a.commPrefix, "QTPR|1,1", "WHISPER", "Other Person")
	Equal(b:IsKnownQTPlayer("Other Person"), false)
	b:OnCommReceived(a.commPrefix, "QTPR|1,1", "CHANNEL", "Other Person", 8, "OtherChannel")
	Equal(b:IsKnownQTPlayer("Other Person"), false)
	for _, payload in ipairs({ "", "2,1", "1,2", "1,1,spoof", "1,Friend-Realm" }) do
		Equal(b:HandleQTPlayerPresenceMessage(payload, "Other Person"), false)
	end
	b.ignored = a.name
	b:PruneQTPlayerPresence(true)
	Equal(b:IsKnownQTPlayer(a.name), false)
	Equal(b:HandleQTPlayerPresenceMessage("1,1", a.name), false)
end)

QT:RegisterTest("QT discovery survives silence is bounded and processes explicit departure", function()
	local a, b = Peer(), Peer("Friend-Realm")
	a.other = b
	assert(a:BroadcastQTPlayerPresence())
	a.now = 119
	Equal(a:BroadcastQTPlayerPresence(), false)
	a.now, a.sendFails = 120, true
	Equal(a:BroadcastQTPlayerPresence(), false)
	Equal(#a.sent, 2)
	b.now = 10000
	assert(b:IsKnownQTPlayer(a.name), "a missed heartbeat must not erase QT identification")
	b:PruneQTPlayerPresence()
	assert(b.qtPlayerPresenceState.peers[a.name])
	a.now, a.sendFails, b.now = 10001, false, 10001
	assert(a:BroadcastQTPlayerPresence())
	assert(b:IsKnownQTPlayer(a.name))
	assert(a:BroadcastQTPlayerPresence(true))
	Equal(b:IsKnownQTPlayer(a.name), false)
	a.isLoggingOut = true
	a.now = 200
	Equal(a:BroadcastQTPlayerPresence(), false)
	for i = 1, 526 do
		b.now = 11000 + i
		assert(b:RecordQTPlayerPresence("Peer" .. i .. "-Realm", true))
	end
	local count = 0
	for _ in pairs(b.qtPlayerPresenceState.peers) do
		count = count + 1
	end
	Equal(count, 512)
	Equal(b:IsKnownQTPlayer("Peer1-Realm"), false)
	assert(b:IsKnownQTPlayer("Peer526-Realm"))
	b.isEnabled = false
	Equal(b:IsKnownQTPlayer("Peer270-Realm"), false)
	Equal(b:RecordQTPlayerPresence("Another-Realm", true), false)
end)

local function WithPlate(run)
	local state = {
		now = 100,
		player = true,
		friendly = true,
		name = "Friend-Realm",
		guid = "Player-1-123",
		cvar = "1",
		exists = true,
		invalid = 0,
		creations = 0,
		refreshes = 0,
		questReads = 0,
		tints = 0,
	}
	local function Region(parent)
		local r = { parent = parent, shown = true, writes = 0 }
		function r:IsForbidden()
			return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
		end
		function r:IsProtected()
			return self.protected == true or (self.parent and self.parent:IsProtected()) or false
		end
		function r:IsShown()
			return self.shown
		end
		function r:GetFrameStrata()
			return "LOW"
		end
		function r:GetFrameLevel()
			return 1
		end
		local function Mutate(self)
			if self:IsForbidden() or (self:IsProtected() and (state.restricted or state.restriction)) then
				state.invalid = state.invalid + 1
				error("unsafe player plate mutation")
			end
			self.writes = self.writes + 1
		end
		function r:Hide()
			Mutate(self)
			self.shown = false
		end
		function r:Show()
			Mutate(self)
			self.shown = true
		end
		function r:CreateTexture()
			Mutate(self)
			return Region(self)
		end
		function r:SetPoint(...)
			Mutate(self)
			self.point = { ... }
		end
		function r:SetTexture(value)
			Mutate(self)
			self.texture = value
		end
		for _, method in ipairs({
			"ClearAllPoints",
			"SetSize",
			"SetAllPoints",
			"SetFrameStrata",
			"SetFrameLevel",
			"SetTexCoord",
			"SetBlendMode",
			"SetVertexColor",
		}) do
			r[method] = Mutate
		end
		return r
	end
	local plate = Region()
	local frame = Region(plate)
	plate.UnitFrame, frame.unit = frame, "nameplate1"
	frame.healthBar, frame.name = Region(frame), Region(frame)
	state.plate, state.frame = plate, frame
	QT.isEnabled = true
	QT.db.profile.nameplatePlayerIconEnabled = true
	QT.qtPlayerPresenceState = { peers = { [state.name] = state.now } }
	QT.peerSnapshotState, QT.peerUpdateContext = nil, nil
	QT.qtPlayerIconStateByFrame = {}
	Patch({
		API = {
			GetTime = function()
				return state.now
			end,
			IsWorldMapVisible = function()
				return state.mapVisible == true
			end,
			GetRealmName = function()
				return "Realm"
			end,
			GetCVar = function(key)
				Equal(key, "nameplateShowFriendlyPlayers")
				return state.cvar
			end,
			UnitExists = function()
				return state.exists
			end,
			UnitIsPlayer = function()
				return state.player
			end,
			UnitIsFriend = function(left, right)
				Equal(left, "player")
				Equal(right, "nameplate1")
				return state.friendly
			end,
			UnitGUID = function()
				return state.guid
			end,
			GetNamePlateForUnit = function()
				if state.removed then
					return nil
				end
				return plate
			end,
			IsOnIgnoredList = function(name)
				return name == state.ignored
			end,
		},
		GetUnitFullName = function()
			return state.name
		end,
		GetPlayerFullName = function()
			return "Me-Realm"
		end,
		GetPlayerName = function()
			return "Me"
		end,
		IsRuntimeRestricted = function()
			return state.restricted == true or state.restriction ~= nil
		end,
		IsRuntimeRestrictionTypeActive = function(_, kind)
			return kind == state.restriction
		end,
		IsNameplateAugmentationBlockedInCurrentContext = function()
			return state.blocked == true
		end,
		IsNameplateUnitTapDenied = function()
			return false
		end,
		ScheduleNameplatePresentationRefresh = function()
			state.refreshes = state.refreshes + 1
		end,
		CreateNameplateQuestIconFrame = function(_, owner)
			state.creations = state.creations + 1
			return Region(owner)
		end,
		TryResolveNameplateQuestObjectiveState = function()
			state.questReads = state.questReads + 1
			assert(not state.player, "players must not enter quest detection")
			return true, true, state.guid
		end,
		RefreshNameplateHealthTint = function(_, _, isQuest)
			assert(not state.player, "players must not enter quest tinting")
			if isQuest then
				state.tints = state.tints + 1
			end
		end,
	}, function()
		run(state)
		Equal(state.invalid, 0)
	end)
end

QT:RegisterTest("all QT communications identify players before or after their friendly plate appears", function()
	local actions = {}
	IgnoreDiscoveryActions(actions)
	Patch(actions, function()
		for command, payload in pairs(DiscoveryMessages(QT)) do
			for _, regional in ipairs({ false, true }) do
				for _, alreadyVisible in ipairs({ false, true }) do
					WithPlate(function(s)
						s.name = regional and "Anakin Othername" or "Friend-Realm"
						QT.API.RegionalUniqueNamesEnabled = function()
							return regional
						end
						QT.qtPlayerPresenceState = { peers = {} }
						QT.recentCommMessageSignatures = {}
						QT.playerLocationState = nil
						QT.nameplateRegisteredEvents.NAME_PLATE_UNIT_ADDED = true
						if alreadyVisible then
							QT:OnNameplateAdded("nameplate1")
							Equal(QT.nameplateIconByUnitFrame[s.frame], nil)
						end
						QT:OnCommReceived(QT.commPrefix, command .. "|" .. payload, "PARTY", s.name)
						assert(QT:IsKnownQTPlayer(s.name), command .. " proves the sender is running QT")
						Equal(s.refreshes, 1)
						if alreadyVisible then
							-- The coalesced presentation callback refreshes this existing plate.
							QT:RefreshNameplateIcon(s.plate)
						else
							-- A player discovered earlier stays recognizable without new traffic.
							s.now = 10000
							QT:PruneQTPlayerPresence(true)
							QT:OnNameplateAdded("nameplate1")
						end
						local icon = QT.nameplateIconByUnitFrame[s.frame]
						assert(icon and icon.shown, command)
						Equal(icon.qtIconKind, "player")
						Equal(QT.qtPlayerIconStateByFrame[icon].name, s.name)
						Equal(s.questReads, 0)
						Equal(s.tints, 0)
					end)
				end
			end
		end
	end)
end)

QT:RegisterTest("only fresh authenticated location messages renew QT player identification", function()
	local a = Peer()
	local wire = "LOC|1,100-1234,1,3,12,0.4,0.6,MAGE,Mage,Human,Alliance,60,0"
	a:OnCommReceived(a.commPrefix, wire, "WHISPER", "Friend-Realm")
	a:OnCommReceived(a.commPrefix, wire, "PARTY", a.name)
	a:OnCommReceived(a.commPrefix, wire .. ",spoof", "PARTY", "Friend-Realm")
	Equal(a:IsKnownQTPlayer("Friend-Realm"), false)
	a.ignored = "Friend-Realm"
	a:OnCommReceived(a.commPrefix, wire, "PARTY", "Friend-Realm")
	Equal(a:IsKnownQTPlayer("Friend-Realm"), false)
	a.ignored, a.now = nil, 101
	a:OnCommReceived(a.commPrefix, wire, "PARTY", "Friend-Realm")
	assert(a:IsKnownQTPlayer("Friend-Realm"))
	local refreshes = a.refreshes
	a.now = 121
	a:OnCommReceived(a.commPrefix, wire:gsub(",1,3,", ",2,3,"), "PARTY", "Friend-Realm")
	Equal(a.refreshes, refreshes, "heartbeats should not refresh every known plate")
	a.now = 150
	a:OnCommReceived(a.commPrefix, wire, "PARTY", "Friend-Realm")
	Equal(a.qtPlayerPresenceState.peers["Friend-Realm"], 121, "obsolete location must not renew presence")
	a.now = 186
	assert(a:IsKnownQTPlayer("Friend-Realm"))
	-- Turning location sharing off is not the same as turning the addon off.
	a:OnCommReceived(a.commPrefix, "LOC|1,100-1234,3,0", "PARTY", "Friend-Realm")
	assert(a:IsKnownQTPlayer("Friend-Realm"))
	a:OnCommReceived(a.commPrefix, "QTPR|1,0", "PARTY", "Friend-Realm")
	Equal(a:IsKnownQTPlayer("Friend-Realm"), false)
	a.now = 188
	a:OnCommReceived(a.commPrefix, "LOC|1,100-1234,3,0", "PARTY", "Friend-Realm")
	Equal(a:IsKnownQTPlayer("Friend-Realm"), false, "replayed location must not undo departure")
	a.isEnabled, a.now = false, 190
	a:OnCommReceived(a.commPrefix, "LOC|1,100-1234,4,0", "PARTY", "Friend-Realm")
	Equal(a.qtPlayerPresenceState.peers["Friend-Realm"], nil)
end)

local function LocationSender(name)
	local sender = Peer(name)
	sender.API.GetBestMapForUnit = function() return 12 end
	sender.API.GetPlayerMapPosition = function() return { x = 0.4, y = 0.6 } end
	sender.API.UnitClass = function() return "Mage", "MAGE" end
	sender.API.UnitRace = function() return "Human" end
	sender.API.GetFaction = function() return "Alliance" end
	sender.API.UnitLevel = function() return 60 end
	sender.API.IsWarModeFeatureEnabled = function() return false end
	sender.API.IsInParty = function() return true end
	sender.API.SendAddonMessage = function(prefix, wire, route)
		local packet = { prefix = prefix, wire = wire, route = route }
		if sender.queue then
			sender.queue[#sender.queue + 1] = packet
		else
			sender:Deliver(packet)
		end
		return 0
	end
	function sender:Deliver(packet)
		self.other:OnCommReceived(packet.prefix, packet.wire, packet.route, self.name, 7, "QuestTogether")
	end
	return sender
end

QT:RegisterTest("actual departure withdrawals never restore logos in either channel delivery order", function()
	for _, lifecycle in ipairs({ "Disable", "PLAYER_LEAVING_WORLD" }) do
		for _, order in ipairs({ "native", "reverse", "presence-first" }) do
			WithPlate(function(s)
				QT.recentCommMessageSignatures = {}
				QT.playerLocationState = nil
				QT.API.GetChannelName = function() return 7 end
				local sender = LocationSender(s.name)
				sender.other = QT
				assert(sender:BroadcastQTPlayerPresence())
				assert(sender:BroadcastPlayerLocation())
				assert(sender:SetOption("lookingForQuestPartners", true))
				QT:RefreshNameplateIcon(s.plate)
				local icon = QT.nameplateIconByUnitFrame[s.frame]
				assert(icon.shown and QT:IsPlayerLookingForQuestPartners(s.name))
				sender.queue = {}
				-- Run the real lifecycle and all three real withdrawal senders. Only
				-- unrelated sender-side UI/runtime teardown uses private no-op seams.
				for _, method in ipairs({
					"UnregisterRuntimeEvents", "ResetQuestEventState", "ResetTaskAreaStateStore",
					"ResetRuntimeWorkStateStore", "LeaveAnnouncementChannel", "DisableNameplateAugmentation",
					"RefreshPersonalBubbleAnchorVisualState",
				}) do sender[method] = function() end end
				sender[lifecycle](sender)
				Equal(#sender.queue, 6) -- QTLF Off, QTPR departure, LOC withdrawal on both routes.
				local delivered = {}
				local function Deliver(index)
					s.now = s.now + 1 -- Exercise sequence checks after content deduplication expires.
					sender:Deliver(sender.queue[index])
					delivered[index] = true
				end
				if order == "reverse" then
					for index = #sender.queue, 1, -1 do Deliver(index) end
				else
					if order == "presence-first" then
						for index, packet in ipairs(sender.queue) do
							if packet.wire == "QTPR|1,0" then Deliver(index) end
						end
					end
					for index in ipairs(sender.queue) do if not delivered[index] then Deliver(index) end end
				end
				QT:RefreshNameplateIcon(s.plate)
				Equal(QT:IsKnownQTPlayer(s.name), false)
				Equal(QT:IsPlayerLookingForQuestPartners(s.name), false)
				Equal(icon.shown, false)
				Equal(QT.playerLocationState.peers[s.name].mask, 0)
				-- Replays remain harmless even after location/status ordering records expire.
				s.now = 10000
				QT:PruneQTPlayerPresence(true)
				QT:PrunePlayerLocations(true)
				for _, packet in ipairs(sender.queue) do sender:Deliver(packet) end
				QT:RefreshNameplateIcon(s.plate)
				Equal(QT:IsKnownQTPlayer(s.name), false)
				Equal(icon.shown, false)
				-- An actual new positive publication can identify a returning sender.
				sender.isEnabled, sender.isLoggingOut, sender.queue, sender.now = true, false, nil, s.now
				assert(sender:BroadcastPlayerLocation(true))
				QT:RefreshNameplateIcon(s.plate)
				assert(QT:IsKnownQTPlayer(s.name) and icon.shown)
			end)
		end
	end
end)

QT:RegisterTest("location and partner opt outs preserve known identity without discovering unknown senders", function()
	for _, known in ipairs({ false, true }) do
		for _, command in ipairs({ "LOC", "QTLF" }) do
			local a = Peer()
			local sender = "Friend-Realm"
			if known then assert(a:RecordQTPlayerPresence(sender, true)) end
			a.now = 101
			local wire = command .. "|1,100-1234,1,0"
			a:OnCommReceived(a.commPrefix, wire, "PARTY", sender)
			Equal(a:IsKnownQTPlayer(sender), known)
			if known then Equal(a.qtPlayerPresenceState.peers[sender], 100) end
			-- Withdrawal ordering is retained even when it supplied no identity.
			local state = command == "LOC" and a.playerLocationState.peers[sender]
				or a.qtPlayerPresenceState.questPartners[sender]
			Equal(state.sequence, 1)
			Equal(a:IsPlayerLookingForQuestPartners(sender), false)
			a:OnCommReceived(a.commPrefix, "QTPR|1,1", "PARTY", sender)
			assert(a:IsKnownQTPlayer(sender))
			a.now = 102
			a:OnCommReceived(a.commPrefix, command .. "|1,100-1234,2,0", "CHANNEL", sender, 7, "QuestTogether")
			assert(a:IsKnownQTPlayer(sender))
			Equal(a.qtPlayerPresenceState.peers[sender], 101)
		end
	end
end)

QT:RegisterTest("QT player plate defaults and all four positions are independent of quest icons", function()
	Equal(QT.DEFAULTS.profile.nameplatePlayerIconEnabled, true)
	Equal(QT.DEFAULTS.profile.nameplatePlayerIconStyle, "left")
	WithPlate(function(s)
		QT.db.profile.nameplateQuestIconEnabled = false
		for _, style in ipairs({ "left", "right", "top", "prefix" }) do
			QT.db.profile.nameplatePlayerIconStyle = style
			QT:RefreshNameplateIcon(s.plate)
			local icon = QT.nameplateIconByUnitFrame[s.frame]
			assert(icon.shown)
			Equal(icon.qtIconKind, "player")
			Equal(icon.Icon.texture, QT.NAMEPLATE_PLAYER_ICON_TEXTURE)
			if style == "left" or style == "prefix" then
				Equal(icon.point[4], -4)
			elseif style == "right" then
				Equal(icon.point[4], 4)
			end
			Equal(
				icon.point[1],
				style == "left" and "RIGHT" or style == "right" and "LEFT" or style == "prefix" and "RIGHT" or "TOP"
			)
		end
		Equal(s.creations, 1)
		Equal(s.questReads, 0)
		Equal(s.tints, 0)
		Equal(s.frame.writes, 0)
		Equal(s.plate.writes, 0)
		QT.db.profile.nameplatePlayerIconEnabled = false
		QT:RefreshNameplateIcon(s.plate)
		Equal(QT.nameplateIconByUnitFrame[s.frame].shown, false)
	end)
end)

QT:RegisterTest("QT player plates reject hostile hidden unknown ignored self and unreadable identity", function()
	for _, reason in ipairs({
		"enemy",
		"cvar",
		"unknown",
		"ignored",
		"self",
		"guid",
		"missing",
		"hidden",
		"disabled",
		"blocked",
	}) do
		WithPlate(function(s)
			QT:RefreshNameplateIcon(s.plate)
			local icon = QT.nameplateIconByUnitFrame[s.frame]
			assert(icon.shown)
			if reason == "enemy" then
				s.friendly = false
			elseif reason == "cvar" then
				s.cvar = "0"
			elseif reason == "unknown" then
				s.name = "Stranger-Realm"
			elseif reason == "ignored" then
				s.ignored = s.name
			elseif reason == "self" then
				s.name = "Me-Realm"
			elseif reason == "guid" then
				s.guid = nil
			elseif reason == "missing" then
				s.exists = false
			elseif reason == "hidden" then
				s.plate.shown = false
			elseif reason == "disabled" then
				QT.isEnabled = false
			else
				s.blocked = true
			end
			QT:RefreshNameplateIcon(s.plate)
			Equal(icon.shown, false)
			Equal(s.questReads, 0)
		end)
	end
end)

QT:RegisterTest("QT player icons survive silence and ignore cleanup defers quarantined handles", function()
	WithPlate(function(s)
		QT:RefreshNameplateIcon(s.plate)
		local icon = QT.nameplateIconByUnitFrame[s.frame]
		icon.forbidden = true
		s.ignored = s.name
		QT:PruneQTPlayerPresence(true)
		Equal(QT.qtPlayerIconStateByFrame[icon], nil)
		Equal(QT:GetNameplateStateStore().pendingVisualCleanupByFrame[icon], "icon")
		icon.forbidden = false
		assert(QT:RetryPendingNameplateVisualCleanup())
		Equal(icon.shown, false)
		s.ignored = nil
		assert(QT:RecordQTPlayerPresence(s.name, true))
		QT:RefreshNameplateIcon(s.plate)
		assert(icon.shown)
		s.now = 10000
		QT:PruneQTPlayerPresence()
		assert(icon.shown)
		QT:OnNameplateRemoved("nameplate1")
		Equal(icon.shown, false)
		s.now = 11000
		QT:OnNameplateAdded("nameplate1")
		assert(icon.shown, "remembered player must regain their logo on a new nameplate")
	end)
end)

QT:RegisterTest("evicting a remembered QT player cleans their visible logo", function()
	WithPlate(function(s)
		QT:RefreshNameplateIcon(s.plate)
		local icon = QT.nameplateIconByUnitFrame[s.frame]
		assert(icon.shown)
		for i = 1, 512 do
			s.now = 100 + i
			assert(QT:RecordQTPlayerPresence("Other" .. i .. "-Realm", true))
		end
		Equal(QT:IsKnownQTPlayer(s.name), false)
		Equal(icon.shown, false)
		Equal(QT.qtPlayerIconStateByFrame[icon], nil)
	end)
end)

QT:RegisterTest("QT departure after silence cleans visible logos before periodic pruning", function()
	WithPlate(function(s)
		QT:RefreshNameplateIcon(s.plate)
		local icon = QT.nameplateIconByUnitFrame[s.frame]
		assert(icon.shown)
		s.now = 165.01
		QT:OnCommReceived(QT.commPrefix, "QTPR|1,0", "PARTY", s.name)
		Equal(QT.qtPlayerPresenceState.peers[s.name], nil)
		Equal(QT:IsKnownQTPlayer(s.name), false)
		Equal(icon.shown, false, "departure must clean up a stored peer")
		local refreshes = s.refreshes
		QT:OnCommReceived(QT.commPrefix, "QTPR|1,0", "PARTY", s.name)
		Equal(s.refreshes, refreshes, "duplicate departure must not schedule another refresh")
		local frame = {
			IsForbidden = function()
				return false
			end,
			IsProtected = function()
				return false
			end,
		}
		function frame:SetScript(_, callback)
			self.onUpdate = callback
		end
		Patch({
			hasLoggedIn = true,
			playerLocationUpdateFrame = false,
			CreatePlayerLocationUpdateFrame = function()
				return frame
			end,
			BroadcastQTPlayerPresence = function()
				return false
			end,
			BroadcastPlayerLocation = function()
				return false
			end,
			PrunePlayerLocations = function() end,
			RefreshPlayerLocationPins = function() end,
		}, function()
			assert(QT:InitializePlayerLocations())
			for _ = 1, 3 do
				s.now = s.now + 1
				frame.onUpdate(frame, 1)
			end
		end)
		Equal(icon.shown, false)
	end)
end)

QT:RegisterTest("departure after silence quarantines forbidden logos until safe cleanup", function()
	for _, guard in ipairs({ "forbidden", "protected" }) do
		WithPlate(function(s)
			QT.recentCommMessageSignatures = {}
			QT:RefreshNameplateIcon(s.plate)
			local icon = QT.nameplateIconByUnitFrame[s.frame]
			icon[guard], s.restricted, s.now = true, guard == "protected", 165.01
			QT:OnCommReceived(QT.commPrefix, "QTPR|1,0", "PARTY", s.name)
			Equal(QT.qtPlayerPresenceState.peers[s.name], nil)
			Equal(QT.qtPlayerIconStateByFrame[icon], nil)
			Equal(QT:GetNameplateStateStore().pendingVisualCleanupByFrame[icon], "icon")
			Equal(icon.shown, true, "guarded frame must remain untouched")
			Equal(QT:RetryPendingNameplateVisualCleanup(), false)
			icon[guard], s.restricted = false, false
			assert(QT:RetryPendingNameplateVisualCleanup())
			Equal(icon.shown, false)
		end)
	end
end)

QT:RegisterTest("QT player icon recycling restores quest artwork and removal handles missing native lookup", function()
	WithPlate(function(s)
		QT:RefreshNameplateIcon(s.plate)
		local icon = QT.nameplateIconByUnitFrame[s.frame]
		s.player, s.guid = false, "Creature-0-0-0-0-123-0"
		QT.db.profile.nameplateQuestIconEnabled = true
		QT:RefreshNameplateIcon(s.plate)
		assert(icon.shown)
		Equal(icon.qtIconKind, "quest")
		Equal(icon.Icon.texture, QT.NAMEPLATE_QUEST_ICON_TEXTURE)
		Equal(QT.qtPlayerIconStateByFrame[icon], nil)
		s.player, s.guid = true, "Player-1-123"
		QT:RefreshNameplateIcon(s.plate)
		Equal(icon.qtIconKind, "player")
		s.removed = true
		QT:OnNameplateRemoved("nameplate1")
		Equal(icon.shown, false)
		Equal(s.creations, 1)
	end)
end)

QT:RegisterTest("QT player protected combat layout defers and stale quest callbacks retain player artwork", function()
	WithPlate(function(s)
		QT:RefreshNameplateIcon(s.plate)
		local icon = QT.nameplateIconByUnitFrame[s.frame]
		s.frame.protected, s.restricted = true, true
		QT:RefreshNameplateIcon(s.plate)
		Equal(QT:GetNameplateStateStore().pendingVisualCleanupByFrame[icon], "icon")
		s.frame.protected, s.restricted = false, false
		QT:RefreshNameplateIcon(s.plate)
		Equal(QT:GetNameplateStateStore().pendingVisualCleanupByFrame[icon], nil)
		QT:ApplyResolvedQuestStateToNameplate(s.plate, "nameplate1", s.frame, false, true, s.guid)
		assert(icon.shown)
		Equal(icon.qtIconKind, "player")
		Equal(s.questReads, 0)
		Equal(s.tints, 0)
	end)
end)

QT:RegisterTest("QT player additions defer all blocked work contexts and recover through the real scheduler", function()
	for _, restriction in ipairs({ "mapVisible", "encounter", "challenge", "pvp", "map" }) do
		WithPlate(function(s)
			if restriction == "mapVisible" then
				s.mapVisible = true
			else
				s.restriction = restriction
			end
			assert(QT:IsWorkBlocked("nameplate_refresh"))
			QT:OnNameplateAdded("nameplate1")
			Equal(s.creations, 0)
			assert(next(QT:GetDeferredWorkStateStore().entries))
			QT:FlushDeferredWork("still restricted")
			Equal(s.creations, 0)
			-- Closing the map must not release work into an active encounter.
			s.mapVisible, s.restriction = false, "encounter"
			if restriction == "mapVisible" then
				local wake = QT.mapWorkWakeFrame
				assert(wake and wake.scripts.OnUpdate)
				wake.scripts.OnUpdate(wake, 0.2)
				Equal(wake.scripts.OnUpdate, nil)
			else
				QT:FlushDeferredWork("still restricted")
			end
			Equal(s.creations, 0)
			s.restriction = nil
			QT:ADDON_RESTRICTION_STATE_CHANGED()
			local icon = QT.nameplateIconByUnitFrame[s.frame]
			assert(icon and icon.shown)
			Equal(icon.qtIconKind, "player")
			Equal(s.creations, 1)
			Equal(s.questReads, 0)
			Equal(next(QT:GetDeferredWorkStateStore().entries), nil)
		end)
	end
end)

QT:RegisterTest(
	"QT player blocked refresh hides stale icons and removed tokens cannot revive deferred icons",
	function()
		WithPlate(function(s)
			QT:OnNameplateAdded("nameplate1")
			local icon = QT.nameplateIconByUnitFrame[s.frame]
			assert(icon.shown)
			s.restriction = "encounter"
			QT:RefreshNameplateIcon(s.plate)
			Equal(icon.shown, false)
			Equal(s.creations, 1)
			s.removed = true
			QT:OnNameplateRemoved("nameplate1")
			s.restriction = nil
			QT:ADDON_RESTRICTION_STATE_CHANGED()
			Equal(icon.shown, false)
			Equal(s.creations, 1)
			Equal(next(QT:GetDeferredWorkStateStore().entries), nil)
		end)
	end
)

QT:RegisterTest("QT player additions still present unprotected icons during ordinary combat", function()
	WithPlate(function(s)
		s.restricted, s.restriction = true, "combat"
		Equal(QT:IsWorkBlocked("nameplate_refresh"), false)
		QT:OnNameplateAdded("nameplate1")
		assert(QT.nameplateIconByUnitFrame[s.frame].shown)
		Equal(s.creations, 1)
		Equal(s.frame.writes, 0)
		Equal(s.plate.writes, 0)
	end)
end)

QT:RegisterTest("QT player preview uses its own toggle style and four pixel spacing", function()
	WithPlate(function(s)
		QT:RefreshNameplateIcon(s.plate)
		local icon = QT.nameplateIconByUnitFrame[s.frame]
		local checked, color, refreshes
		function s.frame.name:GetFont()
			return "font", 12, ""
		end
		function s.frame.healthBar:SetVertexColor(r, g, b)
			color = { r, g, b }
		end
		s.frame.questPreviewBaseFillTexture = s.frame.healthBar
		QT.playerPlatesFrame = {}
		QT.playerPlateControls = {
			playerPlates = true,
			previewUnitFrame = s.frame,
			previewIconFrame = icon,
			previewIconTexture = icon.Icon,
			previewIconOwner = s.frame,
			nameplatePlayerIconEnabled = {
				SetChecked = function(_, value)
					checked = value
				end,
			},
		}
		QT.API.GetCVar = function()
			return nil
		end
		QT.db.profile.nameplateQuestIconEnabled = false
		QT.db.profile.nameplateQuestHealthColorEnabled = true
		QT.db.profile.nameplateQuestIconStyle = "top"
		Patch({
			RefreshNameplateAugmentation = function()
				refreshes = (refreshes or 0) + 1
			end,
		}, function()
			for _, style in ipairs({ "left", "right", "top", "prefix" }) do
				assert(QT:SetOption("nameplatePlayerIconStyle", style))
				QT:RefreshQuestPlatesWindow(true)
				assert(checked and icon.shown)
				Equal(icon.Icon.texture, QT.NAMEPLATE_PLAYER_ICON_TEXTURE)
				Equal(icon.point[4], style == "right" and 4 or style == "top" and 0 or -4)
				Equal(color[1], 0.22)
				Equal(color[2], 0.80)
			end
			Equal(QT:SetOption("nameplatePlayerIconStyle", "invalid"), false)
			Equal(QT:SetOption("nameplatePlayerIconEnabled", "false"), false)
			assert(QT:SetOption("nameplatePlayerIconEnabled", false))
			QT:RefreshQuestPlatesWindow(true)
			Equal(icon.shown, false)
			Equal(checked, false)
			Equal(refreshes, 5)
			Equal(QT:GetOption("nameplateQuestIconStyle"), "top")
		end)
	end)
end)

QT:RegisterTest("QT player identity and queued health events recover without quest detection", function()
	WithPlate(function(s)
		local name = s.name
		s.name = nil
		QT:RefreshNameplateIcon(s.plate)
		Equal(s.creations, 0)
		s.name = name
		Patch({
			ScheduleNameplateRefresh = function(_, unit)
				Equal(unit, "nameplate1")
				QT:RefreshNameplateIcon(s.plate)
			end,
			ScheduleDeferredWork = function(_, kind, unit, callback)
				Equal(kind, "nameplate_tint_refresh")
				Equal(unit, "nameplate1")
				callback()
			end,
		}, function()
			QT:HandleNameplateEvent("UNIT_NAME_UPDATE", "nameplate1")
			local icon = QT.nameplateIconByUnitFrame[s.frame]
			assert(icon.shown)
			QT:ScheduleNameplateHealthTintRefresh("nameplate1")
			assert(icon.shown)
			Equal(s.questReads, 0)
			Equal(s.tints, 0)
		end)
	end)
end)

QT:RegisterTest("QT player plates do not read forbidden hosts or mutate foreign frames", function()
	WithPlate(function(s)
		local reads = 0
		QT.API.UnitIsPlayer = function()
			reads = reads + 1
			return true
		end
		s.plate.forbidden = true
		QT:RefreshNameplateIcon(s.plate)
		Equal(reads, 0)
		Equal(s.creations, 0)
		s.plate.forbidden, s.frame.forbidden = false, true
		QT:RefreshNameplateIcon(s.plate)
		Equal(reads, 0)
		s.frame.forbidden = false
		QT:RefreshNameplateIcon(s.plate)
		local icon = QT.nameplateIconByUnitFrame[s.frame]
		assert(icon.shown)
		icon.Icon.forbidden = true
		QT:RefreshNameplateIcon(s.plate)
		Equal(icon.shown, false)
		icon.Icon.forbidden = false
		QT:RefreshNameplateIcon(s.plate)
		assert(icon.shown)
		Equal(s.frame.writes, 0)
		Equal(s.plate.writes, 0)
	end)
end)

QT:RegisterTest("super-tracked partner quests use bounded heartbeat packets and honor both sharing controls", function()
	local a, b = Peer("Alice-Realm"), Peer("Bob-Realm")
	a.other = b
	local reads, id = 0, 42
	a.API.GetActiveTrackedQuestID = function() reads = reads + 1; return id end
	a:BroadcastQuestPartnerStatus()
	Equal(reads, 0)
	a.db.profile.lookingForQuestPartners = true
	a:BroadcastQuestPartnerStatus(true)
	Equal(b:GetPlayerPartnerQuestID(a.name), 42)
	assert(a.sent[#a.sent]:match("^QTLQ|1,%d+%-%d+,%d+,42,$"))
	local count = #a.sent
	a:BroadcastQuestPartnerStatus()
	Equal(#a.sent, count)
	Equal(reads, 1)
	id, a.now = 43, 120
	a:BroadcastQuestPartnerStatus()
	Equal(b:GetPlayerPartnerQuestID(a.name), 43)
	a.db.profile.sharePlayerLocation = false
	a:BroadcastQuestPartnerStatus(true)
	Equal(reads, 2)
	Equal(b:GetPlayerPartnerQuestID(a.name), nil)
	a.db.profile.sharePlayerLocation = true
	a.restricted = true
	a:BroadcastQuestPartnerStatus(true)
	Equal(reads, 2)
	Equal(b:GetPlayerPartnerQuestID(a.name), nil)
	a.restricted = false
	a:BroadcastQuestPartnerStatus(true)
	Equal(b:GetPlayerPartnerQuestID(a.name), 43)
	a.db.profile.lookingForQuestPartners = false
	a:BroadcastQuestPartnerStatus(true)
	Equal(b:GetPlayerPartnerQuestID(a.name), nil)
end)

QT:RegisterTest("partner quest metadata tolerates reordering without resurrecting stale quests or partner status", function()
	local a, name = Peer(), "Alice-Realm"
	assert(a:HandleQuestPartnerQuestMessage("1,10-1234,1,42", name))
	Equal(a:GetPlayerPartnerQuestID(name), nil)
	assert(not a:IsKnownQTPlayer(name))
	assert(a:HandleQuestPartnerStatusMessage("1,10-1234,1,1", name))
	Equal(a:GetPlayerPartnerQuestID(name), 42)
	assert(a:HandleQuestPartnerQuestMessage("1,10-1234,2,43", name))
	Equal(a:GetPlayerPartnerQuestID(name), nil)
	assert(a:HandleQuestPartnerStatusMessage("1,10-1234,2,1", name))
	Equal(a:GetPlayerPartnerQuestID(name), 43)
	assert(not a:HandleQuestPartnerQuestMessage("1,10-1234,1,42", name))
	assert(a:HandleQuestPartnerStatusMessage("1,10-1234,3,0", name))
	assert(a:HandleQuestPartnerQuestMessage("1,10-1234,3,43", name))
	Equal(a:GetPlayerPartnerQuestID(name), nil)
	assert(a:HandleQuestPartnerStatusMessage("1,20-1234,1,1", name))
	Equal(a:GetPlayerPartnerQuestID(name), nil)
	assert(a:HandleQuestPartnerQuestMessage("1,20-1234,1,44", name))
	Equal(a:GetPlayerPartnerQuestID(name), 44)
	assert(not a:HandleQuestPartnerQuestMessage("1,10-1234,99,42", name))
	a.ignored = name
	Equal(a:GetPlayerPartnerQuestID(name), nil)
	assert(not a:HandleQuestPartnerQuestMessage("1,20-1234,2,45", name))
	a.ignored = nil
	a.now = 165
	Equal(a:GetPlayerPartnerQuestID(name), nil)
	a:PruneQTPlayerPresence(true)
	Equal(next(a.qtPlayerPresenceState.partnerQuests), nil)
end)

QT:RegisterTest("partner quest metadata rejects invalid IDs and bounds independent peer storage", function()
	local a = Peer()
	for _, payload in ipairs({ "", "2,10-1234,1,42", "1,10-1234,0,42", "1,10-1234,2147483648,42", "1,10-1234,1,-1", "1,10-1234,1,1.5", "1,10-1234,1,1000000001", "1,10-1234,1,42,extra,field" }) do
		assert(not a:HandleQuestPartnerQuestMessage(payload, "Alice-Realm"), payload)
	end
	assert(not a:HandleQuestPartnerQuestMessage("1,10-1234,1,42", a.name))
	for i = 1, 270 do
		assert(a:HandleQuestPartnerQuestMessage("1,10-1234,1,42", "Peer" .. i .. "-Realm"))
	end
	local count = 0
	for _ in pairs(a.qtPlayerPresenceState.partnerQuests) do count = count + 1 end
	Equal(count, 256)
	a.isEnabled = false
	assert(not a:HandleQuestPartnerQuestMessage("1,10-1234,1,42", "Alice-Realm"))
end)

QT:RegisterTest("missing or cleared super-tracking never substitutes a watched quest and failures remain paced", function()
	local a, b = Peer("Alice-Realm"), Peer("Bob-Realm")
	a.other = b
	a.db.profile.lookingForQuestPartners = true
	a:BroadcastQuestPartnerStatus(true)
	Equal(#a.sent, 1) -- Legacy packet only when no API/active quest exists.
	a.API.GetActiveTrackedQuestID = function() return 42 end
	a:BroadcastQuestPartnerStatus(true)
	Equal(b:GetPlayerPartnerQuestID(a.name), 42)
	a.API.GetActiveTrackedQuestID = function() return nil end
	a:BroadcastQuestPartnerStatus(true)
	Equal(b:GetPlayerPartnerQuestID(a.name), nil)
	a.API.GetActiveTrackedQuestID = function() error("restricted") end
	a:BroadcastQuestPartnerStatus(true)
	Equal(b:GetPlayerPartnerQuestID(a.name), nil)
	a.sendFails = true
	a:BroadcastQuestPartnerStatus(true)
	local count = #a.sent
	a:BroadcastQuestPartnerStatus()
	Equal(#a.sent, count)
end)

QT:RegisterTest("Forever full-name partner quests withdraw on location opt-out and clear retries expire", function()
	local a, b = Peer("Alice Adventure"), Peer("Bob Brave")
	a.forever, b.forever, a.other = true, true, b
	a.db.profile.lookingForQuestPartners = true
	a.API.GetActiveTrackedQuestID = function() return 42 end
	function a:BroadcastPlayerLocation() end
	function a:RefreshPlayerLocationPins() end
	a:BroadcastQuestPartnerStatus(true)
	Equal(b:GetPlayerPartnerQuestID(a.name), 42)
	a.db.profile.sharePlayerLocation = false
	a:OnPlayerLocationOptionsChanged("sharePlayerLocation")
	Equal(b:GetPlayerPartnerQuestID(a.name), nil)
	local count = #a.sent
	a.now = 166
	a:BroadcastQuestPartnerStatus()
	Equal(#a.sent, count + 1) -- Only QTLF, no indefinite quest-clear traffic.
	PartnerWire(a.sent[#a.sent], true)
end)

QT:RegisterTest("partner quest titles preserve UTF-8 and framing within the addon message budget", function()
	local a, b = Peer("Alice-Realm"), Peer("Bob-Realm")
	a.other = b
	a.db.profile.lookingForQuestPartners = true
	a.API.GetActiveTrackedQuestID = function() return 42 end
	local title = "龍, quête | 100%\nnext"
	function a:GetLocalizedQuestTitle() return title end
	a:BroadcastQuestPartnerStatus(true)
	local id, received = b:GetPlayerPartnerQuestID(a.name)
	Equal(id, 42)
	Equal(received, "龍, quête | 100% next")
	assert(#a.sent[#a.sent] <= 255)
	title = string.rep("龍,%|", 150)
	a:BroadcastQuestPartnerStatus(true)
	id, received = b:GetPlayerPartnerQuestID(a.name)
	Equal(id, 42)
	Equal(received, nil)
	assert(#a.sent[#a.sent] <= 255)
end)
