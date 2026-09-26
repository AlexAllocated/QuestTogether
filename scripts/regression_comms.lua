-- Live-safe fixtures: these tests only replace fields on private addon objects.
local QuestTogether = _G.QuestTogether

local function Equal(actual, expected)
	if actual ~= expected then
		error("expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function NewCommsFixture()
	local addon = setmetatable({
		isEnabled = true,
		partyMembers = {},
		pendingPingRequests = {},
		pendingQuestCompareRequests = {},
		recentCommMessageSignatures = {},
		delayed = {},
		printed = {},
		wire = {},
		runtime = {},
		now = 100,
		channelID = 7,
	}, { __index = QuestTogether })
	addon.API = {
		GetTime = function()
			return addon.now
		end,
		Random = function()
			return 1234
		end,
		GetRealmName = function()
			return "Realm"
		end,
		UnitFullName = function()
			return "MyPlayer", "Realm"
		end,
		UnitName = function()
			return "MyPlayer"
		end,
		UnitClass = function()
			return "Mage", "MAGE"
		end,
		GetChannelName = function()
			return addon.channelID
		end,
		IsInParty = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInInstanceGroup = function()
			return false
		end,
		Delay = function(_, callback)
			addon.delayed[#addon.delayed + 1] = callback
		end,
		SendAddonMessage = function(prefix, message, distribution, target)
			addon.wire[#addon.wire + 1] = { prefix, message, distribution, target }
			return 0
		end,
	}
	function addon:GetRuntimeWorkStateStore()
		return self.runtime
	end
	function addon:Debugf() end
	function addon:Debug() end
	function addon:IsIgnoredPlayerName()
		return false
	end
	function addon:GetPlayerClassFile()
		return "MAGE"
	end
	function addon:GetPlayerAnnouncementLocationInfo()
		return {}
	end
	function addon:GetAddonVersion()
		return "test"
	end
	function addon:PrintQuestCompareStart() end
	function addon:PrintQuestCompareMessage(_, entry)
		self.printed[#self.printed + 1] = entry.questId
	end
	function addon:PrintQuestCompareDone(_, count)
		self.printed[#self.printed + 1] = "done:" .. count
	end
	function addon:PrintPingResponse(response)
		self.printed[#self.printed + 1] = response.senderName
	end
	function addon:PrintConsoleAnnouncement(message)
		self.printed[#self.printed + 1] = message
	end
	return addon
end

local function Event(text)
	return {
		eventType = "QUEST_PROGRESS",
		senderName = "Friend-Realm",
		senderGUID = "Player-1-ABC",
		classFile = "MAGE",
		text = text or "1/5 Things",
		questId = "12345",
	}
end

local function NewRegionalNameFixture()
	local addon = NewCommsFixture()
	addon.showSurname = false
	addon.suppressLocalAnnouncementDisplayDuringTests = false
	addon.API.RegionalUniqueNamesEnabled = function()
		return true
	end
	addon.API.ShouldDisplaySurname = function()
		return addon.showSurname
	end
	addon.API.UnitFullName = function(unit)
		return "Anakin", unit == "player" and "Ofthesea" or "Othername"
	end
	addon.API.UnitName = function()
		return "Anakin"
	end
	addon.API.UnitGUID = function()
		return "Player-fixture-self"
	end
	addon.API.UnitExists = function(unit)
		return unit == "player" or unit == "party1"
	end
	addon.API.IsInRaid = function()
		return false
	end
	function addon:GetOption(key)
		return key == "showChatLogs"
	end
	function addon:ShouldDisplayAnnouncementType()
		return true
	end
	function addon:GetAnnouncementIconInfo()
		return "", ""
	end
	function addon:FindVisiblePlayerNameplateForSender()
		return nil
	end
	function addon:FindNearbyPlayerUnitTokenForSender()
		return nil
	end
	function addon:IsAnnouncementSenderNearbyByLocation()
		return true
	end
	function addon:ShouldShowAnnouncementsForRemoteSender()
		return true
	end
	function addon:PrintConsoleAnnouncement(text, sender)
		self.printed[#self.printed + 1] = { text = text, sender = sender, label = self:GetShortDisplayName(sender) }
	end
	return addon
end

QuestTogether:RegisterTest("Forever local announcements reject their own channel and party echoes", function()
	local addon = NewRegionalNameFixture()
	Equal(addon:PublishAnnouncementEvent("QUEST_PROGRESS", "1/5 objectives", 123), true)
	Equal(#addon.printed, 1)
	Equal(addon.printed[1].label, "Anakin")
	local packet = addon.wire[1][2]
	addon:OnCommReceived(addon.commPrefix, packet, "CHANNEL", "Anakin Ofthesea", 7, addon.announcementChannelName)
	addon:OnCommReceived(addon.commPrefix, packet, "PARTY", "Anakin-Ofthesea")
	Equal(#addon.printed, 1)
	Equal(addon:GetCommsDiagnostics().acceptedAnnouncements, 1)
	-- A different character sharing the first name must still be accepted,
	-- even if the payload claims our GUID. Only transport identity is trusted.
	addon:OnCommReceived(addon.commPrefix, packet, "CHANNEL", "Anakin Othername", 7, addon.announcementChannelName)
	Equal(#addon.printed, 2)
	Equal(addon.printed[2].sender, "Anakin Othername")
	Equal(addon.printed[2].label, "Anakin Othername")
end)

QuestTogether:RegisterTest(
	"Forever surname setting changes labels without changing identity or profile keys",
	function()
		local addon = NewRegionalNameFixture()
		for _, show in ipairs({ false, true, false }) do
			addon.showSurname = show
			Equal(addon:GetPlayerFullName(), "Anakin Ofthesea")
			Equal(addon:GetCurrentCharacterKey(), "Anakin-Ofthesea")
			Equal(addon:GetPersonalBubbleAnchorKey(), "Anakin-Ofthesea")
			Equal(addon:GetShortDisplayName("Anakin Ofthesea"), show and "Anakin Ofthesea" or "Anakin")
			Equal(addon:GetShortDisplayName("Anakin-Ofthesea"), show and "Anakin Ofthesea" or "Anakin")
			Equal(addon:GetShortDisplayName("Anakin Othername"), "Anakin Othername")
			Equal(addon:IsSelfSender("Anakin Ofthesea"), true)
			Equal(addon:IsSelfSender("Anakin-Ofthesea"), true)
			Equal(addon:IsSelfSender("Anakin Othername"), false)
			Equal(addon:IsSelfSender("Anakin"), false)
			Equal(addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "progress", 123).senderName, "Anakin Ofthesea")
		end
	end
)

QuestTogether:RegisterTest("Forever roster unit announcements and ping metadata preserve full names", function()
	local addon = NewRegionalNameFixture()
	addon:RefreshPartyRoster()
	Equal(addon.partyMembers["Anakin Ofthesea"].displayName, "Anakin")
	Equal(addon.partyMembers["Anakin Othername"].displayName, "Anakin Othername")
	Equal(addon:IsGroupedSender("Anakin-Othername"), true)
	Equal(addon:BuildAnnouncementEventForUnit("party1", "QUEST_PROGRESS", "progress").senderName, "Anakin Othername")
	Equal(addon:GetPlayerPingMetadata().realmName, "Realm")
	Equal(addon:GetPlayerPingMetadata().senderName, "Anakin Ofthesea")
	addon.API.UnitFullName = function()
		return "Anakin Ofthesea", nil
	end
	Equal(addon:GetPlayerFullName(), "Anakin Ofthesea")
end)

QuestTogether:RegisterTest("Forever hidden surnames never become social interaction targets", function()
	local addon = NewRegionalNameFixture()
	local queried = {}
	addon.API.IsOnIgnoredList = function(name)
		queried[#queried + 1] = name
		return false
	end
	Equal(QuestTogether.IsIgnoredPlayerName(addon, "Anakin Ofthesea"), false)
	Equal(#queried, 1)
	Equal(queried[1], "Anakin Ofthesea")
	addon.API.InviteUnit = function(name)
		queried[#queried + 1] = name
	end
	addon:InviteChatLogSpeaker("Anakin Ofthesea")
	Equal(queried[2], "Anakin Ofthesea")
end)

QuestTogether:RegisterTest("Forever nameplate matching preserves surnames and rejects conflicting GUIDs", function()
	local addon = NewRegionalNameFixture()
	function addon:IsNameplateUnitPlayer()
		return true
	end
	addon.API.UnitGUID = function()
		return nil
	end
	Equal(addon:DoesUnitTokenMatchSender("party1", nil, "Anakin Othername"), true)
	Equal(addon:DoesUnitTokenMatchSender("party1", nil, "Anakin-Othername"), true)
	Equal(addon:DoesUnitTokenMatchSender("party1", nil, "Anakin Ofthesea"), false)
	Equal(addon:DoesUnitTokenMatchSender("party1", nil, "Anakin"), false)
	addon.API.UnitGUID = function()
		return "Player-fixture-other"
	end
	Equal(addon:DoesUnitTokenMatchSender("party1", "Player-fixture-self", "Anakin Othername"), false)
	Equal(addon:DoesUnitTokenMatchSender("party1", "Player-fixture-other", "Anakin Othername"), true)
end)

QuestTogether:RegisterTest("Forever display settings fail closed and inaccessible names stay unread", function()
	local addon = NewRegionalNameFixture()
	local inaccessible = setmetatable({}, {
		__tostring = function()
			error("foreign name traversed")
		end,
	})
	function addon:CanAccessValue(value)
		return value ~= inaccessible
	end
	Equal(addon:GetShortDisplayName(inaccessible), "Unknown")
	addon.API.ShouldDisplaySurname = function()
		return inaccessible
	end
	Equal(addon:GetShortDisplayName("Anakin Ofthesea"), "Anakin")
	addon.API.ShouldDisplaySurname = function()
		error("unknown setting")
	end
	Equal(addon:GetShortDisplayName("Anakin Ofthesea"), "Anakin")
	Equal(addon:GetShortDisplayName("Anakin Othername"), "Anakin Othername")
	addon.API.UnitFullName = function()
		return "Anakin", inaccessible
	end
	Equal(addon:GetPlayerFullName(), nil)
end)

QuestTogether:RegisterTest("retail names keep realm identity and native short display", function()
	local addon = NewCommsFixture()
	addon.API.RegionalUniqueNamesEnabled = function()
		return false
	end
	addon.API.Ambiguate = function(name, context)
		Equal(context, "short")
		return name:match("^[^-]+")
	end
	addon.API.ShouldDisplaySurname = function()
		error("not a regional name")
	end
	Equal(addon:GetPlayerFullName(), "MyPlayer-Realm")
	Equal(addon:GetShortDisplayName("MyPlayer-Realm"), "MyPlayer")
	Equal(addon:NormalizeMemberName("Other-Other Realm"), "Other-OtherRealm")
	Equal(addon:IsSelfSender("MyPlayer-Realm"), true)
	Equal(addon:IsSelfSender("MyPlayer-OtherRealm"), false)
end)

QuestTogether:RegisterTest("comms reports rejected or throwing send results as failure", function()
	local addon = NewCommsFixture()
	for _, result in ipairs({ 1, 2, 3, 7, 8, 11, false }) do
		addon.API.SendAddonMessage = function()
			return result
		end
		Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), false)
	end
	addon.API.SendAddonMessage = function()
		return nil
	end
	Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), false)
	addon.API.SendAddonMessage = function()
		error("transport failed")
	end
	Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), false)
	for _, result in ipairs({ 0, true }) do
		addon.API.SendAddonMessage = function()
			return result
		end
		Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), true)
	end
	Equal(addon:GetCommsDiagnostics().failedRoutes, 9)
	Equal(addon:GetCommsDiagnostics().sentRoutes, 2)
end)

QuestTogether:RegisterTest("comms resolves channel target after rejoining", function()
	local addon = NewCommsFixture()
	addon.channelID = 0
	addon.announcementChannelLocalID = 2
	function addon:EnsureAnnouncementChannelJoined()
		self.channelID = 9
		self.announcementChannelLocalID = 9
		return true
	end
	Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), true)
	Equal(addon.wire[1][4], 9)
end)

QuestTogether:RegisterTest("announcement packets fit escaped byte budget without cutting UTF8", function()
	local addon = NewCommsFixture()
	local text = string.rep("写真", 30)
	local payload = addon:EncodeAnnouncementPayload(Event(text))
	local decoded = addon:DecodeAnnouncementPayload(payload)
	Equal(#("ANN|" .. payload) <= 255, true)
	Equal(decoded ~= nil, true)
	Equal(#decoded.text % 3, 0)
	Equal(string.sub(text, 1, #decoded.text), decoded.text)
	Equal(addon:SendAnnouncementWireEvent(Event(text)), true)
	Equal(#addon.wire[1][2] <= 255, true)
end)

QuestTogether:RegisterTest("announcement local text limit preserves complete UTF8", function()
	local addon = NewCommsFixture()
	local text = addon:SanitizeAnnouncementText(string.rep("写", 100))
	Equal(#text, 219)
	Equal(string.sub(text, -3), "写")
end)

QuestTogether:RegisterTest("quest comparison titles fit escaped packet budget", function()
	local addon = NewCommsFixture()
	local payload = addon:EncodeQuestCompareEntryPayload({
		requestId = "qcmp-123",
		senderName = "Friend-Realm",
		classFile = "MAGE",
		questId = "12345",
		questTitle = string.rep("写真", 80),
	})
	Equal(#("QCQE|" .. payload) <= 255, true)
	local decoded = addon:DecodeQuestCompareEntryPayload(payload)
	Equal(decoded.questId, "12345")
	Equal(#decoded.questTitle % 3, 0)
end)

QuestTogether:RegisterTest("oversized transport messages fail before sending", function()
	local addon = NewCommsFixture()
	Equal(addon:SendWireMessageToAnnouncementRoutes(string.rep("x", 256)), false)
	Equal(#addon.wire, 0)
	Equal(addon:GetCommsDiagnostics().invalidMessages, 1)
end)

QuestTogether:RegisterTest("chat channel filter ignores mentions and similarly named channels", function()
	local addon = NewCommsFixture()
	Equal(
		addon:AnnouncementChannelChatFilter(
			nil,
			"CHAT_MSG_CHANNEL",
			addon.announcementChannelName,
			"Friend",
			"",
			"General"
		),
		false
	)
	Equal(
		addon:AnnouncementChannelChatFilter(
			nil,
			"CHAT_MSG_CHANNEL",
			"hi",
			"Friend",
			"",
			"7. " .. addon.announcementChannelName
		),
		true
	)
	Equal(
		addon:AnnouncementChannelChatFilter(
			nil,
			"CHAT_MSG_CHANNEL",
			"hi",
			"Friend",
			"",
			addon.announcementChannelName .. "Other"
		),
		false
	)
end)

QuestTogether:RegisterTest("explicit channel name overrides a stale local channel ID", function()
	local addon = NewCommsFixture()
	addon.announcementChannelLocalID = 7
	Equal(addon:IsAnnouncementChannelEvent("CHANNEL", 7, "General"), false)
	Equal(addon:IsAnnouncementChannelEvent("CHANNEL", 7, ""), true)
end)

QuestTogether:RegisterTest("party normalization rejects inaccessible names and realms", function()
	local addon = NewCommsFixture()
	function addon:CanAccessValue(value)
		return value ~= "hidden"
	end
	Equal(addon:NormalizeMemberName("hidden"), nil)
	Equal(addon:NormalizeMemberName("  Friend-Other Realm  "), "Friend-OtherRealm")
	Equal(addon:NormalizeMemberName(""), nil)
	Equal(addon:NormalizeMemberName(nil), nil)
	addon.API.UnitFullName = function()
		return "Friend", "hidden"
	end
	Equal(addon:GetPlayerFullName(), nil)
end)

QuestTogether:RegisterTest("ping metadata keeps class and realm secondary return values", function()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function()
		return "Friend", "Other Realm"
	end
	local response = addon:GetPlayerPingMetadata()
	Equal(response.classFile, "MAGE")
	Equal(response.realmName, "Other Realm")
end)

QuestTogether:RegisterTest("quest comparison deduplicates entries for the entire request", function()
	local addon = NewCommsFixture()
	addon.pendingQuestCompareRequests.test = { targetName = "Friend-Realm", count = 0 }
	local entry = { requestId = "test", senderName = "Friend-Realm", questId = "12345" }
	Equal(addon:HandleQuestCompareEntry(entry), true)
	addon.now = 105
	Equal(addon:HandleQuestCompareEntry(entry), false)
	Equal(addon.pendingQuestCompareRequests.test.count, 1)
	Equal(#addon.printed, 1)
end)

QuestTogether:RegisterTest("quest comparison waits for entries after early completion marker", function()
	local addon = NewCommsFixture()
	addon.pendingQuestCompareRequests.test = { targetName = "Friend-Realm", count = 0 }
	Equal(addon:HandleQuestCompareDone({ requestId = "test", senderName = "Friend-Realm", count = 2 }), true)
	Equal(#addon.printed, 0)
	Equal(addon:HandleQuestCompareEntry({ requestId = "test", senderName = "Friend-Realm", questId = "100" }), true)
	Equal(addon.pendingQuestCompareRequests.test ~= nil, true)
	Equal(addon:HandleQuestCompareEntry({ requestId = "test", senderName = "Friend-Realm", questId = "200" }), true)
	Equal(addon.pendingQuestCompareRequests.test, nil)
	Equal(addon.printed[3], "done:2")
end)

QuestTogether:RegisterTest("ping responses deduplicate each sender for entire request", function()
	local addon = NewCommsFixture()
	addon.pendingPingRequests.test = { responders = {} }
	local response = { requestId = "test", senderName = "Friend-Realm" }
	Equal(addon:HandlePingResponse(response), true)
	addon.now = 105
	Equal(addon:HandlePingResponse(response), false)
	Equal(addon:HandlePingResponse({ requestId = "test", senderName = "Friend-OtherRealm" }), true)
	Equal(#addon.printed, 2)
end)

QuestTogether:RegisterTest("stale quest compare timeout cannot clear a replacement request", function()
	local addon = NewCommsFixture()
	Equal(addon:RequestQuestCompare("Friend-Realm"), true)
	local requestId = next(addon.pendingQuestCompareRequests)
	local replacement = { targetName = "Friend-Realm", count = 1 }
	addon.pendingQuestCompareRequests[requestId] = replacement
	addon.delayed[1]()
	Equal(addon.pendingQuestCompareRequests[requestId], replacement)
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest("incomplete quest comparison reports timeout instead of completion", function()
	local addon = NewCommsFixture()
	Equal(addon:RequestQuestCompare("Friend-Realm"), true)
	local requestId = next(addon.pendingQuestCompareRequests)
	addon:HandleQuestCompareDone({ requestId = requestId, senderName = "Friend-Realm", count = 2 })
	addon:HandleQuestCompareEntry({ requestId = requestId, senderName = "Friend-Realm", questId = "100" })
	addon.delayed[1]()
	Equal(addon.pendingQuestCompareRequests[requestId], nil)
	Equal(addon.printed[2], "Quest comparison timed out (1 quests received).")
end)

QuestTogether:RegisterTest("leaving comm channel clears outstanding response and replay state", function()
	local addon = NewCommsFixture()
	addon.pendingPingRequests.test = true
	addon.pendingQuestCompareRequests.test = {}
	addon.recentCommMessageSignatures.test = 100
	addon:LeaveAnnouncementChannel()
	Equal(next(addon.pendingPingRequests), nil)
	Equal(next(addon.pendingQuestCompareRequests), nil)
	Equal(next(addon.recentCommMessageSignatures), nil)
end)

QuestTogether:RegisterTest("incoming sender identity remains transport authoritative", function()
	local addon = NewCommsFixture()
	local seen
	function addon:HandleAnnouncementEvent(event)
		seen = event.senderName
	end
	local event = Event()
	event.senderName = "MyPlayer-Realm"
	addon:OnCommReceived(addon.commPrefix, "ANN|" .. addon:EncodeAnnouncementPayload(event), "PARTY", "Friend-Realm")
	Equal(seen, "Friend-Realm")
end)

QuestTogether:RegisterTest("disabled comm receiver does not dispatch announcements", function()
	local addon = NewCommsFixture()
	addon.isEnabled = false
	local count = 0
	function addon:HandleAnnouncementEvent()
		count = count + 1
	end
	addon:OnCommReceived(addon.commPrefix, "ANN|" .. addon:EncodeAnnouncementPayload(Event()), "PARTY", "Friend-Realm")
	Equal(count, 0)
end)

QuestTogether:RegisterTest("quest compare done rejects invalid or fractional counts", function()
	local addon = NewCommsFixture()
	for _, count in ipairs({ "bad", "-1", "1.5" }) do
		Equal(addon:DecodeQuestCompareDonePayload("1,test,Friend-Realm,MAGE," .. count), nil)
	end
end)

local function NewLevelUpFixture()
	local addon = NewCommsFixture()
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.suppressLocalAnnouncementDisplayDuringTests = false
	addon.emotes = {}
	addon.API.Random = function() return 1 end
	addon.API.DoEmote = function(token, target)
		addon.emotes[#addon.emotes + 1] = { token = token, target = target }
	end
	function addon:FindVisiblePlayerNameplateForSender() return nil end
	function addon:FindNearbyPlayerUnitTokenForSender() return "target" end
	function addon:IsAnnouncementSenderNearbyByLocation() return false end
	function addon:ShowAnnouncementBubbleOnUnitNameplate() error("level-up should only play an emote") end
	function addon:ShowAnnouncementBubbleOnNameplate() error("level-up should only play an emote") end
	return addon
end

local function LevelUpEvent()
	local event = Event("Level 20")
	event.eventType = "PLAYER_LEVEL_UP"
	event.questId = ""
	event.emoteToken = "cheer"
	return event
end

QuestTogether:RegisterTest("level-up sends one shared emote token on party and nearby routes", function()
	local addon = NewLevelUpFixture()
	addon.db.profile.emoteOnQuestCompletion = false
	addon.API.IsInParty = function() return true end
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), true)
	Equal(#addon.wire, 2)
	Equal(addon.wire[1][3], "PARTY")
	Equal(addon.wire[2][3], "CHANNEL")
	Equal(addon.wire[1][2], addon.wire[2][2])
	local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	Equal(command, "LVL")
	local event = addon:DecodeAnnouncementPayload(payload)
	Equal(event.eventType, "PLAYER_LEVEL_UP")
	Equal(event.text, "Level 20")
	Equal(event.questId, "")
	Equal(#addon.emotes, 1)
	Equal(addon.emotes[1].token, event.emoteToken)
	Equal(addon.emotes[1].target, "MyPlayer")
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest("local level-up toggle and test suppression still publish to peers", function()
	for _, suppressTests in ipairs({ false, true }) do
		local addon = NewLevelUpFixture()
		addon.db.profile.emoteOnLevelUp = suppressTests
		addon.suppressLocalAnnouncementDisplayDuringTests = suppressTests
		Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), true)
		Equal(#addon.wire, 1)
		Equal(#addon.emotes, 0)
	end
end)

QuestTogether:RegisterTest("disabled addon and invalid level-up payloads cannot celebrate or publish", function()
	local addon = NewLevelUpFixture()
	for _, level in ipairs({ 0, -1, 1.5, false, {}, "invalid", math.huge, 0 / 0 }) do
		Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", level), false)
	end
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", nil), false)
	addon.CanAccessValue = function() return false end
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), false)
	addon.CanAccessValue = nil
	addon.isEnabled = false
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), false)
	Equal(#addon.emotes, 0)
	Equal(#addon.wire, 0)
end)

QuestTogether:RegisterTest("remote level-up obeys its own toggle independently of quest and chat options", function()
	for _, enabled in ipairs({ false, true }) do
		local addon = NewLevelUpFixture()
		addon.db.profile.emoteOnNearbyPlayerLevelUp = enabled
		addon.db.profile.emoteOnNearbyPlayerQuestCompletion = not enabled
		addon.db.profile.emoteOnLevelUp = false
		addon.db.profile.showChatLogs = false
		addon.db.profile.showChatBubbles = false
		Equal(addon:HandleAnnouncementEvent(LevelUpEvent(), false), true)
		Equal(#addon.emotes, enabled and 1 or 0)
		if enabled then
			Equal(addon.emotes[1].token, "cheer")
			Equal(addon.emotes[1].target, "target")
		end
	end
end)

QuestTogether:RegisterTest("level-up reactions require proximity and obey party-only scope", function()
	local addon = NewLevelUpFixture()
	addon.db.profile.showProgressFor = "party_only"
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 0)
	addon.partyMembers["Friend-Realm"] = { fullName = "Friend-Realm", classFile = "MAGE" }
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1)
	addon.FindNearbyPlayerUnitTokenForSender = function() return nil end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1)
	addon.db.profile.showProgressFor = "party_nearby"
	addon.partyMembers = {}
	addon.db.profile.devLogAllAnnouncements = true
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1)
	addon.IsAnnouncementSenderNearbyByLocation = function() return true end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 2)
	Equal(addon.emotes[2].target, "Friend-Realm")
	addon.FindVisiblePlayerNameplateForSender = function()
		return { GetUnit = function() return "nameplate1" end }
	end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 3)
	Equal(addon.emotes[3].target, "nameplate1")
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest("level-up wire uses transport identity and suppresses duplicates self and ignored senders", function()
	local addon = NewLevelUpFixture()
	addon.FindNearbyPlayerUnitTokenForSender = function(_, _, senderName)
		Equal(senderName, "Friend-Realm")
		return "target"
	end
	local event = LevelUpEvent()
	event.senderName = "Spoofed-Realm"
	local wire = "LVL|" .. addon:EncodeAnnouncementPayload(event)
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Friend-Realm")
	addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, addon.announcementChannelName)
	Equal(#addon.emotes, 1)
	Equal(#addon.printed, 0)
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "MyPlayer-Realm")
	addon.IsIgnoredPlayerName = function() return true end
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Ignored-Realm")
	Equal(#addon.emotes, 1)
end)

QuestTogether:RegisterTest("level-up wire rejects other event types", function()
	local addon = NewLevelUpFixture()
	local event = LevelUpEvent()
	event.eventType = "QUEST_COMPLETED"
	addon:OnCommReceived(addon.commPrefix, "LVL|" .. addon:EncodeAnnouncementPayload(event), "PARTY", "Friend-Realm")
	Equal(#addon.emotes, 0)
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest("level-up options migrate existing profiles and preserve disabled values", function()
	local addon = NewLevelUpFixture()
	addon.db.profile.emoteOnLevelUp = nil
	addon.db.profile.emoteOnNearbyPlayerLevelUp = nil
	addon:NormalizeAnnouncementDisplayOptions()
	Equal(addon:GetOption("emoteOnLevelUp"), true)
	Equal(addon:GetOption("emoteOnNearbyPlayerLevelUp"), true)
	addon:SetOption("emoteOnLevelUp", false)
	addon:SetOption("emoteOnNearbyPlayerLevelUp", false)
	addon:NormalizeAnnouncementDisplayOptions()
	Equal(addon:GetOption("emoteOnLevelUp"), false)
	Equal(addon:GetOption("emoteOnNearbyPlayerLevelUp"), false)
end)

QuestTogether:RegisterTest("level-up event registration follows addon enable and disable", function()
	local addon = NewLevelUpFixture()
	local registered = {}
	addon.registeredRuntimeEvents = {}
	addon.eventFrame = {
		RegisterEvent = function(_, name) registered[name] = true end,
		UnregisterEvent = function(_, name) registered[name] = nil end,
	}
	addon:RegisterRuntimeEvents()
	Equal(registered.PLAYER_LEVEL_UP, true)
	addon:UnregisterRuntimeEvents()
	Equal(registered.PLAYER_LEVEL_UP, nil)
end)
