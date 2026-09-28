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
		questCompareResponseQueue = false,
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
		IsWarModeFeatureEnabled = function()
			return true
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
	Equal(addon:GetPlayerPingMetadata().realmName, "")
	Equal(addon:GetPlayerPingMetadata().senderName, "Anakin Ofthesea")
	addon.API.UnitFullName = function()
		return "Anakin Ofthesea", nil
	end
	Equal(addon:GetPlayerFullName(), "Anakin Ofthesea")
end)

QuestTogether:RegisterTest("Forever unavailable surname profile fallback never invents a realm", function()
	local addon = NewRegionalNameFixture()
	addon.API.UnitFullName = function() return nil, nil end
	addon.GetPlayerFullName = function() return nil end
	addon.API.GetRealmName = function() error("regional profile fallback must not read a realm") end
	Equal(addon:GetCurrentCharacterKey(), "Anakin")
	Equal(addon:GetPersonalBubbleAnchorKey(), "Anakin")
	addon.API.UnitFullName = function() return "Anakin", "Ofthesea" end
	Equal(addon:GetCurrentCharacterKey(), "Anakin-Ofthesea")
	Equal(addon:GetPersonalBubbleAnchorKey(), "Anakin-Ofthesea")
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

local function UseNativeLocationModel(addon)
	addon.GetPlayerAnnouncementLocationInfo = QuestTogether.GetPlayerAnnouncementLocationInfo
	addon.CanPublishPlayerLocation = function() return true end
	addon.API.GetBestMapForUnit = function() return 37 end
	addon.API.GetMapInfo = function() return { mapID = 37, name = "Elwynn Forest" } end
	addon.API.GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end
end

QuestTogether:RegisterTest("Forever metadata never reads or displays realms and War Mode", function()
	local addon = NewRegionalNameFixture()
	UseNativeLocationModel(addon)
	addon.API.GetRealmName = function() error("Forever has no realm identity") end
	addon.API.IsWarModeFeatureEnabled = function() error("regional clients have no War Mode") end
	addon.API.IsWarModeActive = function() error("unsupported mode must not be polled") end
	Equal(addon:SupportsWarMode(), false)
	local location = addon:GetPlayerAnnouncementLocationInfo()
	Equal(location.warMode, nil)
	Equal(location.mapID, 37)
	local metadata = addon:GetPlayerPingMetadata()
	Equal(metadata.realmName, "")
	Equal(metadata.warMode, "")
	Equal(metadata.senderName, "Anakin Ofthesea")
	metadata.requestId = "regional-ping"
	local decoded = addon:DecodePingResponsePayload(addon:EncodePingResponsePayload(metadata))
	Equal(decoded.realmName, "")
	Equal(decoded.warMode, "")
	Equal(decoded.senderName, metadata.senderName)
	local event = addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
	Equal(event.warMode, "")
	Equal(addon:DecodeAnnouncementPayload(addon:EncodeAnnouncementPayload(event)).warMode, "")
	-- Older clients still send a dummy realm and WM Off; ignore these labels
	-- without discarding their real name, map or coordinates.
	decoded.realmName, decoded.warMode = "LegacyRealm", "0"
	local message = addon:BuildPingResponseMessage(decoded)
	assert(not message:find("LegacyRealm", 1, true))
	assert(not message:find("WM Off", 1, true))
	assert(message:find("Elwynn Forest", 1, true))
	assert(not addon:BuildAnnouncementLocationSuffix(decoded):find("WM Off", 1, true))
end)

QuestTogether:RegisterTest("announcement metadata preserves unknown War Mode instead of inventing Off", function()
	for _, capability in ipairs({ "enabled", "disabled", "unreadable", "missing" }) do
		for _, state in ipairs({ "on", "off", "unknown" }) do
			local addon = NewCommsFixture()
			UseNativeLocationModel(addon)
			local polls = 0
			addon.API.IsWarModeFeatureEnabled = function()
				if capability == "enabled" then return true end
				if capability == "disabled" then return false end
				return nil
			end
			if capability == "missing" then addon.API.IsWarModeFeatureEnabled = nil end
			addon.API.IsWarModeActive = function()
				polls = polls + 1
				if state == "on" then return true end
				if state == "off" then return false end
			end
			local expected = ""
			if capability == "enabled" and state ~= "unknown" then expected = state == "on" and "1" or "0" end
			local metadata = addon:GetPlayerPingMetadata()
			Equal(metadata.warMode, expected)
			Equal(addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123).warMode, expected)
			Equal(polls, capability == "enabled" and 2 or 0)
			local suffix = addon:BuildAnnouncementLocationSuffix(metadata)
			Equal(suffix:find("WM ", 1, true) ~= nil, expected ~= "")
		end
	end
end)

QuestTogether:RegisterTest("unavailable War Mode capability cannot certify nearby announcement state", function()
	local addon = NewCommsFixture()
	UseNativeLocationModel(addon)
	local remote = { mapID = 37, zoneName = "Elwynn Forest", coordX = 50, coordY = 50, warMode = "0" }
	local inaccessible = setmetatable({}, { __tostring = function() error("inaccessible mode formatted") end })
	function addon:CanAccessValue(value) return value ~= inaccessible end
	addon.API.IsWarModeActive = function() return false end
	addon.API.IsWarModeFeatureEnabled = function() return inaccessible end
	Equal(addon:SupportsWarMode(), nil)
	Equal(addon:NormalizeAnnouncementWarModeValue(inaccessible), nil)
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.API.IsWarModeFeatureEnabled = function() error("capability unavailable") end
	Equal(addon:SupportsWarMode(), nil)
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.API.IsWarModeFeatureEnabled = function() return false end
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	addon.API.IsWarModeFeatureEnabled = function() return true end
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	remote.warMode = "1"
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
end)

QuestTogether:RegisterTest("Forever nearby announcements use map distance without Retail War Mode", function()
	local sender, receiver = NewRegionalNameFixture(), NewRegionalNameFixture()
	UseNativeLocationModel(sender)
	UseNativeLocationModel(receiver)
	receiver.API.UnitFullName = function() return "Anakin", "Othername" end
	receiver.IsAnnouncementSenderNearbyByLocation = QuestTogether.IsAnnouncementSenderNearbyByLocation
	receiver.ShouldShowAnnouncementsForRemoteSender = QuestTogether.ShouldShowAnnouncementsForRemoteSender
	receiver.GetOption = function(_, key)
		if key == "showProgressFor" then return "party_nearby" end
		return key == "showChatLogs"
	end
	local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
	for _, legacyMode in ipairs({ "", "0", "1" }) do
		event.warMode = legacyMode
		assert(sender:SendAnnouncementWireEvent(event))
		receiver:OnCommReceived(receiver.commPrefix, sender.wire[#sender.wire][2], "CHANNEL", "Anakin Ofthesea", 7,
			receiver.announcementChannelName)
		receiver.now = receiver.now + 1
	end
	Equal(#receiver.printed, 3)
	event.mapID = "999"
	assert(sender:SendAnnouncementWireEvent(event))
	receiver:OnCommReceived(receiver.commPrefix, sender.wire[#sender.wire][2], "CHANNEL", "Anakin Ofthesea", 7,
		receiver.announcementChannelName)
	Equal(#receiver.printed, 3)
	event.mapID, event.coordX, event.coordY = "37", "90", "90"
	assert(sender:SendAnnouncementWireEvent(event))
	receiver:OnCommReceived(receiver.commPrefix, sender.wire[#sender.wire][2], "CHANNEL", "Anakin Ofthesea", 7,
		receiver.announcementChannelName)
	Equal(#receiver.printed, 3)
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

local function NewRemoteCelebrationFixture()
	local addon = NewLevelUpFixture()
	addon.db.profile.showChatBubbles = false
	addon.db.profile.showChatLogs = false
	addon.db.profile.showProgressFor = "party_nearby"
	addon.API.UnitFullName = function(unit) return unit == "player" and "MyPlayer" or "Friend", "Realm" end
	addon.API.UnitName = function(unit) return unit == "player" and "MyPlayer" or "Friend" end
	addon.API.UnitExists = function(unit) return unit == "player" or unit == "target" end
	addon.API.UnitIsPlayer = function() return true end
	addon.API.UnitGUID = function(unit) return unit == "player" and "Player-self" or "Player-friend" end
	addon.API.IsMounted = function() return false end
	addon.API.GetFaction = function() return "Neutral" end
	addon.FindVisiblePlayerNameplateForSender = nil
	addon.FindNearbyPlayerUnitTokenForSender = nil
	addon.ForEachVisibleNamePlate = function() end
	return addon
end

local function ReceiveCelebration(addon, eventType, token, sender)
	local event = Event("Quest Completed: Wolves")
	event.eventType = eventType
	event.senderGUID = "Player-friend"
	event.emoteToken = token
	local command = eventType == "PLAYER_LEVEL_UP" and "LVL" or "ANN"
	local wire = command .. "|" .. addon:EncodeAnnouncementPayload(event)
	Equal(#wire <= 255, true)
	addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", sender or "Friend-Realm", 7, addon.announcementChannelName)
end

QuestTogether:RegisterTest("received celebrations reject unsupported and malformed emote tokens", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, token in ipairs({ "rude", "not-an-emote", "cheer rude", "cheer\nrude", "|Hplayer:Friend|hcheer|h", "\0cheer", "123", "true", "" }) do
			local addon = NewRemoteCelebrationFixture()
			ReceiveCelebration(addon, eventType, token)
			Equal(addon:GetCommsDiagnostics().acceptedAnnouncements, 1)
			Equal(#addon.emotes, 0)
		end
	end
end)

QuestTogether:RegisterTest("received celebrations canonicalize every approved local emote", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, token in ipairs(QuestTogether.completionEmotes) do
			local addon = NewRemoteCelebrationFixture()
			ReceiveCelebration(addon, eventType, " \t" .. string.upper(token) .. " \n")
			Equal(#addon.emotes, 1)
			Equal(addon.emotes[1].token, token)
			Equal(addon.emotes[1].target, "target")
		end
	end
end)

QuestTogether:RegisterTest("received special celebrations retain mounted and faction handling", function()
	local cases = {
		{ token = " MOUNTSPECIAL ", mounted = true, expected = "mountspecial" },
		{ token = "mountspecial", expected = "applaud" },
		{ token = " FORTHEHORDE ", faction = "Alliance", expected = "forthealliance" },
		{ token = " FORTHEALLIANCE ", faction = "Horde", expected = "forthehorde" },
		{ token = "forthealliance", expected = "applaud" },
	}
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, case in ipairs(cases) do
			local addon = NewRemoteCelebrationFixture()
			addon.API.IsMounted = function() return case.mounted == true end
			addon.API.GetFaction = function() return case.faction or "Neutral" end
			ReceiveCelebration(addon, eventType, case.token)
			Equal(#addon.emotes, 1)
			Equal(addon.emotes[1].token, case.expected)
			Equal(addon.emotes[1].target, "target")
		end
	end
end)

QuestTogether:RegisterTest("received celebration validation retains identity scope and option checks", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, blockedBy in ipairs({ "option", "scope", "ignored", "self", "identity" }) do
			local addon = NewRemoteCelebrationFixture()
			if blockedBy == "option" then
				local option = eventType == "PLAYER_LEVEL_UP" and "emoteOnNearbyPlayerLevelUp" or "emoteOnNearbyPlayerQuestCompletion"
				addon.db.profile[option] = false
			elseif blockedBy == "scope" then
				addon.db.profile.showProgressFor = "party_only"
			elseif blockedBy == "ignored" then
				addon.IsIgnoredPlayerName = function() return true end
			end
			local sender = blockedBy == "self" and "MyPlayer-Realm" or (blockedBy == "identity" and "Other-Realm" or "Friend-Realm")
			ReceiveCelebration(addon, eventType, "CHEER", sender)
			Equal(#addon.emotes, 0)
		end
	end
end)

QuestTogether:RegisterTest("remote celebration validation never stringifies inaccessible or non-string tokens", function()
	local addon = NewRemoteCelebrationFixture()
	local inaccessible = setmetatable({}, { __tostring = function() error("inaccessible token stringified") end })
	local accessible = setmetatable({}, { __tostring = function() error("non-string token stringified") end })
	addon.CanAccessValue = function(_, value) return value ~= inaccessible end
	for _, token in ipairs({ inaccessible, accessible, 123, true, false }) do
		Equal(addon:GetSafeRemoteCompletionEmote(token), nil)
	end
	Equal(addon:GetSafeRemoteCompletionEmote(nil), nil)
end)

QuestTogether:RegisterTest("remote celebration fallback cannot expand its approved token set", function()
	local addon = NewRemoteCelebrationFixture()
	addon.completionEmotes = { "rude" }
	local attempts = 0
	addon.API.Random = function() attempts = attempts + 1; return 1 end
	ReceiveCelebration(addon, "QUEST_COMPLETED", "mountspecial")
	Equal(#addon.emotes, 0)
	Equal(attempts > 0 and attempts <= 20, true)
end)

QuestTogether:RegisterTest("remote special celebrations use approved fallback when local state is inaccessible", function()
	local addon = NewRemoteCelebrationFixture()
	local inaccessible = {}
	addon.CanAccessValue = function(_, value) return value ~= inaccessible end
	addon.API.IsMounted = function() return inaccessible end
	addon.API.GetFaction = function() return inaccessible end
	for _, token in ipairs({ "mountspecial", "forthealliance", "forthehorde" }) do
		Equal(addon:GetSafeRemoteCompletionEmote(token), "applaud")
	end
end)

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
	-- Forever traps division by zero, so constructing NaN here aborts the fixture
	-- before the handler runs. NaN coverage belongs to the offline contracts.
	for _, level in ipairs({ 0, -1, 1.5, false, {}, "invalid", math.huge }) do
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

QuestTogether:RegisterTest("localized announcement metadata and default icon fit a real send", function()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function() return "Алесандра", "Гордунни" end
	addon.API.UnitGUID = function() return "Player-1602-12345678" end
	function addon:GetPlayerClassFile() return "DEATHKNIGHT" end
	function addon:GetPlayerAnnouncementLocationInfo()
		return { mapID = 2248, zoneName = "Остров Дорн", coordX = 50.1, coordY = 40.2, warMode = false }
	end
	local event = addon:BuildLocalAnnouncementEvent("QUEST_ACCEPTED", "Quest accepted: A normal quest", 12345)
	Equal(event.iconAsset, "Interface/GossipFrame/AvailableQuestIcon")
	Equal(addon:SendAnnouncementWireEvent(event), true)
	local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	local decoded = addon:DecodeAnnouncementPayload(payload)
	Equal(command, "ANN")
	Equal(#addon.wire[1][2] <= 255, true)
	Equal(decoded.senderName, "Алесандра-Гордунни")
	Equal(decoded.text, event.text)
	Equal(decoded.zoneName, "Остров Дорн")
	-- Optional decoration must yield to identity and useful text for larger
	-- localized metadata, rather than producing an undecodable empty message.
	event.zoneName = string.rep("Долина", 30)
	event.iconAsset = string.rep("Icon", 40)
	Equal(addon:SendAnnouncementWireEvent(event), true)
	_, payload = addon:DeserializeWireMessage(addon.wire[2][2])
	decoded = addon:DecodeAnnouncementPayload(payload)
	Equal(#addon.wire[2][2] <= 255, true)
	Equal(decoded.senderName, event.senderName)
	Equal(decoded.text, event.text)
	Equal(decoded.zoneName, "")
	Equal(decoded.mapID, "2248")
	Equal(decoded.coordX, "50.1")
	Equal(decoded.coordY, "40.2")
end)

QuestTogether:RegisterTest("localized ping metadata sends without shortening player identity", function()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function() return "Алесандра", "Гордунни" end
	addon.API.UnitRace = function() return "Ночная эльфийка" end
	addon.API.UnitClass = function() return "Рыцарь смерти", "DEATHKNIGHT" end
	addon.API.UnitLevel = function() return 80 end
	function addon:GetPlayerAnnouncementLocationInfo()
		return { zoneName = "Остров Дорн", mapID = 2248, coordX = 50.1, coordY = 40.2, warMode = false }
	end
	local requestId = "ping-Character-12345678-1234"
	Equal(addon:SendPingResponse(requestId), true)
	local _, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	local response = addon:DecodePingResponsePayload(payload)
	Equal(#addon.wire[1][2] <= 255, true)
	Equal(response.senderName, "Алесандра-Гордунни")
	Equal(response.requestId, requestId)
	Equal(response.raceName, "Ночная эльфийка")
	-- Long optional labels can be omitted, but mandatory identity survives.
	function addon:GetPlayerAnnouncementLocationInfo() return { zoneName = string.rep("Долина", 40) } end
	Equal(addon:SendPingResponse(requestId), true)
	_, payload = addon:DeserializeWireMessage(addon.wire[2][2])
	response = addon:DecodePingResponsePayload(payload)
	Equal(#addon.wire[2][2] <= 255, true)
	Equal(response.senderName, "Алесандра-Гордунни")
	Equal(response.requestId, requestId)
	Equal(response.zoneName, "")
end)

QuestTogether:RegisterTest("wire escaping preserves UTF8 and legacy percent encoded payloads", function()
	local addon = NewCommsFixture()
	local original = "Дорн, 100% | test\0\n"
	local escaped = addon:EscapePayload(original)
	Equal(addon:UnescapePayload(escaped), original)
	Equal(escaped:find(",", 1, true), nil)
	Equal(escaped:find("|", 1, true), nil)
	Equal(escaped:find("\0", 1, true), nil)
	Equal(addon:UnescapePayload("%D0%94%D0%BE%D1%80%D0%BD%2C%20test"), "Дорн, test")
end)

local function InstallResponseClock(addon)
	addon.delayed = {}
	addon.API.Delay = function(seconds, callback)
		addon.delayed[#addon.delayed + 1] = { seconds = seconds, callback = callback }
	end
end

local function RunResponseTimer(addon)
	local timer = table.remove(addon.delayed, 1)
	if not timer then return false end
	addon.now = addon.now + timer.seconds
	timer.callback()
	return true
end

local function SetComparisonEntries(addon, count)
	function addon:BuildQuestCompareEntries()
		local entries = {}
		for index = 1, count do
			entries[index] = { questId = tostring(index), questTitle = "Quest " .. index, isComplete = false }
		end
		return entries
	end
end

QuestTogether:RegisterTest("quest comparison paces and retries delivery before completing the real receiver", function()
	local sender, receiver = NewCommsFixture(), NewCommsFixture()
	InstallResponseClock(sender)
	InstallResponseClock(receiver)
	sender.API.UnitFullName = function() return "Friend", "Realm" end
	sender.API.UnitName = function() return "Friend" end
	sender.partyMembers["MyPlayer-Realm"] = {}
	SetComparisonEntries(sender, 12)
	Equal(receiver:RequestQuestCompare("Friend-Realm"), true)
	local requestId = next(receiver.pendingQuestCompareRequests)
	Equal(receiver.delayed[1].seconds >= 120, true)
	local attempts, rejected, lastAttemptAt = 0, false, nil
	sender.API.SendAddonMessage = function(prefix, message, route)
		Equal(route, "PARTY")
		if lastAttemptAt then Equal(sender.now - lastAttemptAt >= 0.099, true) end
		lastAttemptAt = sender.now
		attempts = attempts + 1
		if attempts == 2 then rejected = true; return 3 end
		receiver.now = sender.now
		receiver:OnCommReceived(prefix, message, route, "Friend-Realm")
		return 0
	end
	sender:OnCommReceived(sender.commPrefix, receiver.wire[1][2], "PARTY", "MyPlayer-Realm")
	Equal(attempts, 1)
	Equal(receiver.pendingQuestCompareRequests[requestId].count, 1)
	for _ = 1, 20 do if not RunResponseTimer(sender) then break end end
	Equal(rejected, true)
	Equal(attempts, 14)
	Equal(receiver.pendingQuestCompareRequests[requestId], nil)
	Equal(#receiver.printed, 13)
	Equal(receiver.printed[13], "done:12")
	Equal(#sender.questCompareResponseQueue.jobs, 0)
	Equal(sender.questCompareResponseQueue.packets, 0)
end)

QuestTogether:RegisterTest("quest comparison retry exhaustion never advertises a partial result as complete", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 3)
	local attempts, donePackets = 0, 0
	addon.API.SendAddonMessage = function(_, message)
		attempts = attempts + 1
		if message:find("^QCDN|") then donePackets = donePackets + 1 end
		return attempts == 1 and 0 or 3
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "retry", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }), true)
	for _ = 1, 10 do if not RunResponseTimer(addon) then break end end
	Equal(attempts, 6)
	Equal(donePackets, 0)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
	Equal(addon:GetCommsDiagnostics().failedComparisons, 1)
end)

QuestTogether:RegisterTest("quest comparison queues expire and old callbacks cannot send after reset", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 3)
	local request = { requestId = "old", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }
	Equal(addon:HandleQuestCompareRequest(request), true)
	local expiredCount = #addon.wire
	addon.now = addon.now + 151
	RunResponseTimer(addon)
	Equal(#addon.wire, expiredCount)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	request.requestId = "reset"
	Equal(addon:HandleQuestCompareRequest(request), true)
	local oldTimer = table.remove(addon.delayed, 1)
	addon:ResetCommsState()
	request.requestId = "replacement"
	Equal(addon:HandleQuestCompareRequest(request), true)
	local replacementQueue, before = addon.questCompareResponseQueue, #addon.wire
	oldTimer.callback()
	Equal(addon.questCompareResponseQueue, replacementQueue)
	Equal(#addon.wire, before)
	addon.isEnabled = false
	RunResponseTimer(addon)
	Equal(#addon.wire, before)
end)

QuestTogether:RegisterTest("quest comparison response memory has job and packet bounds", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 1)
	for index = 1, 4 do
		Equal(addon:HandleQuestCompareRequest({ requestId = tostring(index), targetName = "MyPlayer-Realm" }), true)
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "overflow", targetName = "MyPlayer-Realm" }), false)
	Equal(#addon.questCompareResponseQueue.jobs, 4)
	addon:ResetCommsState()
	SetComparisonEntries(addon, 40)
	for index = 1, 3 do
		Equal(addon:HandleQuestCompareRequest({ requestId = tostring(index), targetName = "MyPlayer-Realm" }), true)
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "overflow", targetName = "MyPlayer-Realm" }), false)
	Equal(addon.questCompareResponseQueue.packets <= 128, true)
	addon:ResetCommsState()
	SetComparisonEntries(addon, 101)
	Equal(addon:HandleQuestCompareRequest({ requestId = "large", targetName = "MyPlayer-Realm" }), false)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
end)

QuestTogether:RegisterTest("oversized mandatory wire identity is rejected rather than truncated", function()
	local addon = NewCommsFixture()
	local identity = string.rep("Длинное", 50) .. "-Realm"
	local event = Event("1/5 objectives")
	event.senderName = identity
	Equal(addon:SendAnnouncementWireEvent(event), false)
	local payload = addon:EncodePingResponsePayload({ requestId = "test", senderName = identity })
	Equal(addon:DecodePingResponsePayload(payload).senderName, identity)
	Equal(addon:SendWireMessageToAnnouncementRoutes("PONG|" .. payload), false)
	Equal(#addon.wire, 0)
end)

QuestTogether:RegisterTest("empty quest comparisons share the response packet cooldown", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 0)
	Equal(addon:HandleQuestCompareRequest({ requestId = "first", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 1)
	Equal(addon:HandleQuestCompareRequest({ requestId = "second", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 1)
	RunResponseTimer(addon)
	Equal(#addon.wire, 2)
	local _, payload = addon:DeserializeWireMessage(addon.wire[2][2])
	Equal(addon:DecodeQuestCompareDonePayload(payload).count, 0)
end)

QuestTogether:RegisterTest("paced successful comparisons finish within legacy ten second window", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 25)
	local startedAt, lastAttemptAt = addon.now, nil
	local completedAt, sentCount = nil, 0
	addon.API.SendAddonMessage = function(_, message, route)
		Equal(route, "PARTY")
		if lastAttemptAt then Equal(addon.now - lastAttemptAt >= 0.099, true) end
		lastAttemptAt = addon.now
		sentCount = sentCount + 1
		if message:find("^QCDN|") then
			local _, payload = addon:DeserializeWireMessage(message)
			Equal(addon:DecodeQuestCompareDonePayload(payload).count, 25)
			completedAt = addon.now
		end
		return 0
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "legacy", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }), true)
	Equal(sentCount, 1)
	for _ = 1, 30 do if not RunResponseTimer(addon) then break end end
	Equal(sentCount, 26)
	Equal(completedAt ~= nil and completedAt - startedAt < 10, true)
end)

QuestTogether:RegisterTest("failed comparison sends back off longer than successful packet pacing", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 2)
	local attempts = 0
	addon.API.SendAddonMessage = function()
		attempts = attempts + 1
		return attempts == 2 and 3 or 0
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "backoff", targetName = "MyPlayer-Realm" }), true)
	local normalDelay = addon.delayed[1].seconds
	RunResponseTimer(addon)
	Equal(addon.delayed[1].seconds >= 1, true)
	Equal(addon.delayed[1].seconds > normalDelay, true)
	RunResponseTimer(addon)
	Equal(addon.delayed[1].seconds, normalDelay)
end)

QuestTogether:RegisterTest("queued group comparisons stop when requester leaves the roster", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 3)
	addon.partyMembers["Friend-Realm"] = {}
	Equal(addon:HandleQuestCompareRequest({ requestId = "group", requesterName = "Friend-Realm", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }), true)
	Equal(#addon.wire, 1)
	addon.partyMembers = { ["NewFriend-Realm"] = {} }
	RunResponseTimer(addon)
	Equal(#addon.wire, 1)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
end)

QuestTogether:RegisterTest("queued channel comparisons resolve changed channel identifiers per packet", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 2)
	Equal(addon:HandleQuestCompareRequest({ requestId = "channel", targetName = "MyPlayer-Realm", replyDistribution = "CHANNEL" }), true)
	Equal(addon.wire[1][4], 7)
	addon.channelID = 9
	RunResponseTimer(addon)
	Equal(addon.wire[2][4], 9)
end)

QuestTogether:RegisterTest("queued group comparisons follow a still grouped requester into raid transport", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 2)
	addon.partyMembers["Friend-Realm"] = {}
	addon.API.IsInParty = function() return true end
	Equal(addon:HandleQuestCompareRequest({ requestId = "raid", requesterName = "Friend-Realm", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }), true)
	Equal(addon.wire[1][3], "PARTY")
	addon.API.IsInRaid = function() return true end
	RunResponseTimer(addon)
	Equal(addon.wire[2][3], "RAID")
end)

QuestTogether:RegisterTest("comparison snapshots wait for both quest count and every row before sending", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local phase = 0
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return phase > 0 and 2 or nil end
	addon.API.GetQuestLogInfo = function(index)
		if index == 2 and phase < 2 then return nil end
		return { questID = index, title = "Quest " .. index, isComplete = false }
	end
	addon.GetQuestShareableStatusLabel = function() return "No" end
	Equal(addon:HandleQuestCompareRequest({ requestId = "loading", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 0)
	Equal(addon.questCompareResponseQueue.packets, 1)
	phase = 1
	RunResponseTimer(addon)
	Equal(#addon.wire, 0)
	phase = 2
	RunResponseTimer(addon)
	Equal(#addon.wire, 1)
	for _ = 1, 5 do if not RunResponseTimer(addon) then break end end
	Equal(#addon.wire, 3)
	local command, payload = addon:DeserializeWireMessage(addon.wire[3][2])
	Equal(command, "QCDN")
	Equal(addon:DecodeQuestCompareDonePayload(payload).count, 2)
	Equal(addon.questCompareResponseQueue.packets, 0)
end)

QuestTogether:RegisterTest("unavailable comparison count exhausts bounded snapshot retries without completion", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local reads = 0
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() reads = reads + 1; return nil end
	Equal(addon:HandleQuestCompareRequest({ requestId = "unavailable", targetName = "MyPlayer-Realm" }), true)
	for _ = 1, 10 do if not RunResponseTimer(addon) then break end end
	Equal(reads, 5)
	Equal(#addon.wire, 0)
	Equal(#addon.delayed, 0)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
	Equal(addon:GetCommsDiagnostics().failedComparisons, 1)
end)

QuestTogether:RegisterTest("missing comparison rows cannot become a certified partial quest log", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local missingReads = 0
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return 2 end
	addon.API.GetQuestLogInfo = function(index)
		if index == 2 then missingReads = missingReads + 1; return nil end
		return { questID = 123, title = "Readable quest" }
	end
	addon.GetQuestShareableStatusLabel = function() return "No" end
	Equal(addon:HandleQuestCompareRequest({ requestId = "partial", targetName = "MyPlayer-Realm" }), true)
	for _ = 1, 10 do if not RunResponseTimer(addon) then break end end
	Equal(missingReads, 5)
	Equal(#addon.wire, 0)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
end)

QuestTogether:RegisterTest("a readable empty quest log still completes a comparison", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return 0 end
	Equal(addon:HandleQuestCompareRequest({ requestId = "empty", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 1)
	local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	Equal(command, "QCDN")
	Equal(addon:DecodeQuestCompareDonePayload(payload).count, 0)
end)

QuestTogether:RegisterTest("comparison snapshots defer restricted reads and reject changing counts", function()
	local addon = NewCommsFixture()
	local blocked, reads = true, 0
	addon.IsWorkBlocked = function() return blocked end
	addon.API.GetNumQuestLogEntries = function() reads = reads + 1; return reads == 1 and 0 or 1 end
	Equal(addon:BuildQuestCompareEntries(), nil)
	Equal(reads, 0)
	blocked = false
	Equal(addon:BuildQuestCompareEntries(), nil)
	Equal(reads, 2)
end)

QuestTogether:RegisterTest("self comparison reports an unavailable snapshot without claiming completion", function()
	local addon = NewCommsFixture()
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return nil end
	Equal(addon:RequestQuestCompare("MyPlayer-Realm"), false)
	Equal(#addon.printed, 1)
	Equal(addon.printed[1], "Quest comparison unavailable while the quest log is updating.")
end)

QuestTogether:RegisterTest("comparison snapshots wait for missing blank and inaccessible visible quest titles", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local phase = 0
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return 1 end
	addon.API.GetQuestLogInfo = function()
		local titles = { [1] = "   ", [2] = "inaccessible title", [3] = "Loaded quest" }
		return { questID = 123, title = titles[phase] }
	end
	addon.CanAccessValue = function(_, value) return value ~= "inaccessible title" end
	addon.GetQuestShareableStatusLabel = function() return "No" end
	Equal(addon:HandleQuestCompareRequest({ requestId = "title", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 0)
	for index = 1, 2 do
		phase = index
		RunResponseTimer(addon)
		Equal(#addon.wire, 0)
	end
	phase = 3
	RunResponseTimer(addon)
	Equal(#addon.wire, 1)
	local _, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	Equal(addon:DecodeQuestCompareEntryPayload(payload).questTitle, "Loaded quest")
	RunResponseTimer(addon)
	Equal(#addon.wire, 2)
end)

QuestTogether:RegisterTest("comparison snapshots can omit explicitly known header and hidden rows", function()
	local addon = NewCommsFixture()
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return 2 end
	addon.API.GetQuestLogInfo = function(index)
		if index == 1 then return { isHeader = true } end
		return { questID = 123, isHidden = true }
	end
	local entries = addon:BuildQuestCompareEntries()
	Equal(type(entries), "table")
	Equal(#entries, 0)
end)

local function NewSnapshotComparisonFixture()
	local addon = NewCommsFixture()
	local clock = addon:CreateTestClock(100)
	addon.restrictions = {}
	addon.questReads = 0
	addon.API.GetTime = function() return clock:GetTime() end
	addon.API.Delay = function(seconds, callback) clock:After(seconds, callback) end
	addon.API.InCombatLockdown = function() return addon.restrictions.combat == true end
	addon.API.IsWorldMapVisible = function() return addon.restrictions.map == true end
	addon.IsRuntimeRestrictionTypeActive = function(_, restrictionType)
		return addon.restrictions[restrictionType] == true
	end
	addon.API.GetNumQuestLogEntries = function()
		Equal(addon:IsWorkBlocked("quest_snapshot_refresh"), false)
		addon.questReads = addon.questReads + 1
		if addon.snapshotUnavailable then return nil end
		return 1
	end
	addon.API.GetQuestLogInfo = function()
		Equal(addon:IsWorkBlocked("quest_snapshot_refresh"), false)
		return { questID = 123, title = "Readable quest", isComplete = false }
	end
	addon.GetTrackedQuestStatusState = function() return { isOnQuest = true } end
	addon.API.IsPushableQuest = function() return nil end
	addon.partyMembers["Friend-Realm"] = {}
	return addon, clock
end

local function ReceiveSnapshotComparisonRequest(addon, requestId)
	local payload = addon:EncodeQuestCompareRequestPayload({
		requestId = requestId,
		requesterName = "Friend-Realm",
		targetName = "MyPlayer-Realm",
	})
	addon:OnCommReceived(addon.commPrefix, addon:SerializeWireMessage("QCMP", payload), "PARTY", "Friend-Realm")
end

QuestTogether:RegisterTest("queued comparisons recover after long combat map and encounter restrictions", function()
	for _, restriction in ipairs({ "combat", "map", "encounter" }) do
		local addon, clock = NewSnapshotComparisonFixture()
		addon.restrictions[restriction] = true
		ReceiveSnapshotComparisonRequest(addon, restriction)
		for _ = 1, 12 do clock:Advance(1) end
		Equal(#addon.questCompareResponseQueue.jobs, 1)
		Equal(addon.questCompareResponseQueue.jobs[1].snapshotAttempts, 0)
		Equal(addon.questCompareResponseQueue.packets, 1)
		Equal(addon.questReads, 0)
		Equal(#addon.wire, 0)
		addon.restrictions[restriction] = nil
		clock:Advance(1)
		Equal(#addon.wire, 1)
		local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
		Equal(command, "QCQE")
		Equal(addon:DecodeQuestCompareEntryPayload(payload).questId, "123")
		clock:Drain()
		Equal(#addon.wire, 2)
		command, payload = addon:DeserializeWireMessage(addon.wire[2][2])
		Equal(command, "QCDN")
		Equal(addon:DecodeQuestCompareDonePayload(payload).count, 1)
		Equal(#addon.questCompareResponseQueue.jobs, 0)
		Equal(addon.questCompareResponseQueue.packets, 0)
	end
end)

QuestTogether:RegisterTest("restriction deferrals preserve the bounded unavailable snapshot retry budget", function()
	local addon, clock = NewSnapshotComparisonFixture()
	addon.snapshotUnavailable = true
	ReceiveSnapshotComparisonRequest(addon, "unavailable-around-combat")
	clock:Advance(1)
	clock:Advance(1)
	Equal(addon.questReads, 3)
	addon.restrictions.combat = true
	for _ = 1, 12 do clock:Advance(1) end
	Equal(addon.questReads, 3)
	Equal(addon.questCompareResponseQueue.jobs[1].snapshotAttempts, 3)
	addon.restrictions.combat = nil
	clock:Advance(1)
	Equal(#addon.questCompareResponseQueue.jobs, 1)
	clock:Advance(1)
	Equal(addon.questReads, 5)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
	Equal(#addon.wire, 0)
	Equal(#clock.timers, 0)
end)

QuestTogether:RegisterTest("restricted comparison jobs still expire without reading or sending", function()
	local addon, clock = NewSnapshotComparisonFixture()
	addon.restrictions.map = true
	ReceiveSnapshotComparisonRequest(addon, "expired-map")
	for _ = 1, 149 do clock:Advance(1) end
	Equal(#addon.questCompareResponseQueue.jobs, 1)
	clock:Advance(1)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
	Equal(addon:GetCommsDiagnostics().failedComparisons, 1)
	addon.restrictions.map = nil
	clock:Advance(10)
	Equal(addon.questReads, 0)
	Equal(#addon.wire, 0)
	Equal(#clock.timers, 0)
end)

QuestTogether:RegisterTest("restricted comparison callbacks cannot revive canceled or disabled work", function()
	local addon, clock = NewSnapshotComparisonFixture()
	addon.restrictions.combat = true
	ReceiveSnapshotComparisonRequest(addon, "old-combat")
	local oldCallback = clock.timers[1].callback
	addon:ResetCommsState()
	ReceiveSnapshotComparisonRequest(addon, "replacement-combat")
	local replacementQueue = addon.questCompareResponseQueue
	oldCallback()
	Equal(addon.questCompareResponseQueue, replacementQueue)
	Equal(#replacementQueue.jobs, 1)
	Equal(replacementQueue.scheduled, true)
	addon.isEnabled = false
	addon.restrictions.combat = nil
	clock:Advance(10)
	Equal(addon.questReads, 0)
	Equal(#addon.wire, 0)
	addon:ResetCommsState()
	addon.isEnabled = true
	clock:Advance(10)
	Equal(addon.questCompareResponseQueue, nil)
	Equal(#addon.wire, 0)
end)

QuestTogether:RegisterTest("comparison source wire and display preserve all three shareability states", function()
	for _, expected in ipairs({ "Yes", "No", "Unknown" }) do
		local addon = NewSnapshotComparisonFixture()
		addon.API.IsPushableQuest = function()
			if expected == "Yes" then return true end
			if expected == "No" then return false end
		end
		addon.GetQuestStatusLabel = function() return "Not Started" end
		addon.BuildChatLogQuestLabel = function(_, _, title) return title end
		Equal(addon:GetQuestShareableStatusLabel(123), expected)
		local entry = addon:BuildQuestCompareEntries()[1]
		Equal(addon:GetQuestCompareShareableToYouLabel(entry.isPushable), expected)
		Equal(addon:SendQuestCompareEntry("shareability", entry), true)
		local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
		Equal(command, "QCQE")
		local received = addon:DecodeQuestCompareEntryPayload(payload)
		Equal(received.questId, "123")
		Equal(received.classFile, "MAGE")
		Equal(addon:GetQuestCompareShareableToYouLabel(received.isPushable), expected)
		Equal(addon:BuildQuestCompareMessage("Friend-Realm", received),
			"Readable quest | Them: In Progress | You: Not Started | Shareable to You: " .. expected)
	end
end)

QuestTogether:RegisterTest("legacy comparison layouts retain known booleans and unknown shareability", function()
	local addon = NewCommsFixture()
	for _, hasClass in ipairs({ false, true }) do
		for _, token in ipairs({ "1", "0", "", "invalid" }) do
			local payload = "1,legacy,Friend-Realm," .. (hasClass and "MAGE," or "") .. "123,Old quest,0," .. token
			local entry = addon:DecodeQuestCompareEntryPayload(payload)
			Equal(entry.questId, "123")
			Equal(entry.classFile, hasClass and "MAGE" or "")
			Equal(entry.isComplete, false)
			Equal(addon:GetQuestCompareShareableToYouLabel(entry.isPushable),
				token == "1" and "Yes" or (token == "0" and "No" or "Unknown"))
		end
	end
end)

local function NewLocationReceiver()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function() return "Receiver", "Realm" end
	addon.API.UnitName = function() return "Receiver" end
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.db.profile.showProgressFor = "party_nearby"
	addon.db.profile.showChatLogs = true
	addon.db.profile.showChatBubbles = false
	addon.FindVisiblePlayerNameplateForSender = function() return nil end
	addon.FindNearbyPlayerUnitTokenForSender = function() return nil end
	return addon
end

QuestTogether:RegisterTest("announcement map identity survives local construction and wire round trip", function()
	local addon = NewCommsFixture()
	addon.GetPlayerAnnouncementLocationInfo = function()
		return { mapID = 37, zoneName = "Elwynn Forest", coordX = 50, coordY = 50, warMode = false }
	end
	local event = addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123, { emoteToken = "CHEER" })
	Equal(event.mapID, "37")
	Equal(addon:SendAnnouncementWireEvent(event), true)
	local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	local received = addon:DecodeAnnouncementPayload(payload)
	Equal(command, "ANN")
	Equal(received.mapID, "37")
	Equal(received.emoteToken, "CHEER", "appending map identity must not move old fields")
	Equal(#addon.wire[1][2] <= 255, true)
end)

QuestTogether:RegisterTest("received nearby announcements use map identity across localized labels", function()
	local cases = {
		{ remoteID = 37, localID = 37, remoteName = "Elwynn Forest", localName = "Wald von Elwynn", visible = true },
		{ remoteID = 37, localID = 99999, remoteName = "Same label", localName = "Same label", visible = false },
		{ remoteID = 37, localID = 37, remoteName = "", localName = "", visible = true },
		{ remoteID = 37, localID = 37, remoteName = "Same label", localName = "Same label", far = true, visible = false },
		{ remoteID = 37, localID = 37, remoteName = "Same label", localName = "Same label", differentWarMode = true, visible = false },
		{ localID = 37, remoteName = "Legacy label", localName = "Legacy label", visible = true },
		{ remoteID = 37, remoteName = "Legacy label", localName = "Legacy label", visible = true },
		{ remoteName = "Different label", localName = "Legacy label", visible = false },
	}
	for _, case in ipairs(cases) do
		local sender, receiver = NewCommsFixture(), NewLocationReceiver()
		sender.GetPlayerAnnouncementLocationInfo = function()
			return { mapID = case.remoteID, zoneName = case.remoteName, coordX = 50, coordY = 50, warMode = false }
		end
		receiver.GetPlayerAnnouncementLocationInfo = function()
			return { mapID = case.localID, zoneName = case.localName, coordX = case.far and 90 or 50,
				coordY = 50, warMode = case.differentWarMode == true }
		end
		local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
		Equal(sender:SendAnnouncementWireEvent(event), true)
		receiver:OnCommReceived(receiver.commPrefix, sender.wire[1][2], "CHANNEL", "MyPlayer-Realm", 7, receiver.announcementChannelName)
		Equal(#receiver.printed, case.visible and 1 or 0)
	end
end)

QuestTogether:RegisterTest("announcement map extension preserves legacy layouts and rejects invalid IDs", function()
	local addon = NewCommsFixture()
	local function Payload(version, suffix)
		return tostring(version) .. ",QUEST_PROGRESS,Player-1-ID,MAGE,Friend-Realm,Wolves: 1/8,123,,,Zone,50,50,0,CHEER" .. suffix
	end
	for _, version in ipairs({ 1, 2, 3 }) do
		local legacy = addon:DecodeAnnouncementPayload(Payload(version, ""))
		Equal(legacy.mapID, "")
		Equal(legacy.zoneName, "Zone")
		Equal(legacy.emoteToken, "CHEER")
		Equal(addon:DecodeAnnouncementPayload(Payload(version, ",37")).mapID, "37")
	end
	for _, invalid in ipairs({ "0", "-1", "1.5", "nan", "inf", "garbage", "" }) do
		Equal(addon:DecodeAnnouncementPayload(Payload(3, "," .. invalid)).mapID, "")
	end
	local secret = setmetatable({}, { __tostring = function() error("secret map ID stringified") end })
	addon.CanAccessValue = function(_, value) return value ~= secret end
	local event = Event()
	event.mapID = secret
	Equal(addon:SanitizeAnnouncementEventData(event).mapID, "")
end)

QuestTogether:RegisterTest("announcement packet fitting retains numeric location when display labels are too large", function()
	local sender, receiver = NewCommsFixture(), NewLocationReceiver()
	sender.GetPlayerAnnouncementLocationInfo = function()
		return { mapID = 2248, zoneName = string.rep("Долина", 40), coordX = 50, coordY = 50, warMode = false }
	end
	receiver.GetPlayerAnnouncementLocationInfo = function()
		return { mapID = 2248, zoneName = "Isle of Dorn", coordX = 50, coordY = 50, warMode = false }
	end
	local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
	Equal(sender:SendAnnouncementWireEvent(event), true)
	local wire = sender.wire[1][2]
	Equal(#wire <= 255, true)
	local _, payload = sender:DeserializeWireMessage(wire)
	local received = sender:DecodeAnnouncementPayload(payload)
	Equal(received.zoneName, "")
	Equal(received.mapID, "2248")
	Equal(received.coordX, "50.0")
	Equal(received.coordY, "50.0")
	Equal(received.warMode, "0")
	receiver:OnCommReceived(receiver.commPrefix, wire, "CHANNEL", "MyPlayer-Realm", 7, receiver.announcementChannelName)
	Equal(#receiver.printed, 1)
end)

local function NewBubblePreviewFixture()
	local addon = NewCommsFixture()
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.db.profile.showChatBubbles = true
	addon.db.profile.showChatLogs = false
	addon.partyMembers["Target-Realm"] = {}
	addon.API.UnitFullName = function(unit)
		return unit == "player" and "MyPlayer" or "Target", "Realm"
	end
	addon.API.UnitGUID = function(unit) return unit == "player" and "Player-self" or "Player-target" end
	addon.API.UnitExists = function(unit) return unit == "target" or unit == "nameplate1" or unit == "player" end
	addon.API.UnitIsPlayer = function() return true end
	addon.IsWorkBlocked = function() return false end
	local plate = { UnitFrame = { unit = "nameplate1" }, GetUnit = function() return "nameplate1" end }
	addon.ForEachVisibleNamePlate = function(_, callback) callback(plate) end
	addon.bubbles = {}
	addon.ShowAnnouncementBubbleOnNameplate = function(_, frame, text)
		Equal(frame, plate)
		addon.bubbles[#addon.bubbles + 1] = text
		return true
	end
	return addon
end

QuestTogether:RegisterTest("bubbletest previews target locally without broadcasting another identity", function()
	local addon = NewBubblePreviewFixture()
	local ok, name = addon:SendBubbleAnnouncementTest("Local target preview")
	Equal(ok, true)
	Equal(name, "Target-Realm")
	Equal(#addon.wire, 0)
	Equal(#addon.bubbles, 1)
	Equal(addon.bubbles[1], "Local target preview")
	addon.API.UnitExists = function(unit) return unit == "nameplate1" or unit == "player" end
	ok, name = addon:SendBubbleAnnouncementTest("Explicit player preview", "Target-Realm")
	Equal(ok, true)
	Equal(name, "Target-Realm")
	Equal(#addon.wire, 0)
	Equal(#addon.bubbles, 2)
end)

QuestTogether:RegisterTest("local bubble previews do not depend on transport and report suppression", function()
	local addon = NewBubblePreviewFixture()
	addon.SendAnnouncementWireEvent = function() error("a local preview must not use the network") end
	Equal(addon:SendBubbleAnnouncementTest("Local preview"), true)
	addon.db.profile.announceProgress = false
	local ok, message = addon:SendBubbleAnnouncementTest("Suppressed preview")
	Equal(ok, false)
	Equal(message, "The local preview was suppressed by your announcement settings.")
	Equal(#addon.bubbles, 1)
end)

local function NewBubbleSlashFixture(regional, hasTarget)
	local addon = NewBubblePreviewFixture()
	addon.messages = {}
	addon.Print = function(_, message) addon.messages[#addon.messages + 1] = message end
	addon.GetDebugController = function() return { HandleCommand = function() return false end } end
	addon.API.RegionalUniqueNamesEnabled = function() return regional end
	addon.API.ShouldDisplaySurname = function() return false end
	addon.API.UnitExists = function(unit)
		return unit == "player" or unit == "nameplate1" or unit == "nameplate2" or (hasTarget and unit == "target")
	end
	addon.API.UnitFullName = function(unit)
		if not regional then return unit == "player" and "MyPlayer" or "Target", "Realm" end
		if unit == "player" then return "MyPlayer", "Selfname" end
		return "Anakin", unit == "nameplate2" and "Elsewhere" or "Othername"
	end
	addon.API.UnitName = function(unit) return unit == "player" and "MyPlayer" or (regional and "Anakin" or "Target") end
	addon.API.UnitGUID = function(unit)
		return unit == "player" and "Player-self" or (unit == "nameplate2" and "Player-other" or "Player-target")
	end
	if regional then
		-- The other character with the same first name appears first, so a
		-- weakened first-name lookup would render on the wrong private frame.
		local firstPlate = addon.ForEachVisibleNamePlate
		local otherPlate = { UnitFrame = { unit = "nameplate2" }, GetUnit = function() return "nameplate2" end }
		addon.ForEachVisibleNamePlate = function(self, callback)
			callback(otherPlate)
			firstPlate(self, callback)
		end
	end
	return addon
end

QuestTogether:RegisterTest("bubbletest slash accepts full regional quoted and legacy identities", function()
	for _, command in ipairs({
		"bubbletest Anakin Othername hello there",
		"bubbletest Anakin   Othername hello there",
		'bubbletest "Anakin Othername" hello there',
		"bubbletest Anakin-Othername hello there",
	}) do
		local addon = NewBubbleSlashFixture(true, false)
		addon:HandleSlashCommand(command)
		Equal(#addon.bubbles, 1)
		Equal(addon.bubbles[1], "hello there")
		Equal(#addon.wire, 0)
		Equal(addon.messages[#addon.messages], "Ran local bubble preview for Anakin Othername")
	end
	local addon = NewBubbleSlashFixture(true, false)
	Equal(addon:SendBubbleAnnouncementTest("Direct preview", "Anakin Othername"), true)
	Equal(#addon.bubbles, 1)
	Equal(addon.bubbles[1], "Direct preview")
end)

QuestTogether:RegisterTest("bubbletest slash retains retail single-token and quoted player names", function()
	for _, command in ipairs({
		"bubbletest Target hello there",
		"bubbletest Target-Realm hello there",
		'bubbletest "Target-Realm" hello there',
	}) do
		local addon = NewBubbleSlashFixture(false, false)
		addon:HandleSlashCommand(command)
		Equal(#addon.bubbles, 1)
		Equal(addon.bubbles[1], "hello there")
		Equal(#addon.wire, 0)
	end
end)

QuestTogether:RegisterTest("bubbletest slash keeps complete target text including quotes and player-like words", function()
	for _, regional in ipairs({ false, true }) do
		local addon = NewBubbleSlashFixture(regional, true)
		local text = '"Anakin Othername" hello there'
		addon:HandleSlashCommand("bubbletest " .. text)
		Equal(#addon.bubbles, 1)
		Equal(addon.bubbles[1], text)
		Equal(#addon.wire, 0)
	end
end)

QuestTogether:RegisterTest("bubbletest slash rejects malformed names empty text and ambiguous first names", function()
	for _, regional in ipairs({ false, true }) do
		for _, arguments in ipairs({ '"" hello', '"   " hello', '"Anakin Othername hello', '"Anakin Othername"hello', '"Anakin Othername"', '"Anakin Othername"   ', "Target-Realm" }) do
			local addon = NewBubbleSlashFixture(regional, false)
			addon:HandleSlashCommand("bubbletest " .. arguments)
			Equal(#addon.bubbles, 0)
			Equal(#addon.wire, 0)
			Equal(addon.messages[#addon.messages], 'Usage without a target: /qt bubbletest "<player>" <text>')
		end
	end
	for _, arguments in ipairs({ '"Anakin" hello there', "Anakin hello there" }) do
		local addon = NewBubbleSlashFixture(true, false)
		addon:HandleSlashCommand("bubbletest " .. arguments)
		Equal(#addon.bubbles, 0)
		Equal(#addon.wire, 0)
		Equal(addon.messages[#addon.messages], "No visible nearby player matched that name.")
	end
end)

QuestTogether:RegisterTest("rapid party comparison refreshes supersede obsolete peer responses and complete the newest session", function()
	local peer, requester = NewCommsFixture(), NewCommsFixture()
	local clock = QuestTogether:CreateTestClock(100)
	for _, addon in ipairs({ peer, requester }) do
		addon.API.GetTime = function() return clock:GetTime() end
		addon.API.IsInParty = function() return true end
		addon.API.Delay = function(delay, callback) clock:After(delay, callback) end
		addon.runtime.deferredWorkState = { entries = {}, generations = {} }
		addon.IsWorkBlocked = function() return false end
		addon.QueuePartyQuestCompareRender = function() end
		addon.partyQuestCompareSession = false
	end
	peer.API.UnitFullName = function() return "Friend", "Realm" end
	peer.API.UnitName = function() return "Friend" end
	peer.GetPlayerClassFile = function() return "" end -- Classless peers still reply.
	peer.partyMembers["MyPlayer-Realm"] = {}
	requester.partyMembers["Friend-Realm"] = {}
	requester.partyMemberOrder = { "Friend-Realm" }
	SetComparisonEntries(peer, 35)
	SetComparisonEntries(requester, 0)
	local timers = {}
	peer.API.Delay = function(delay, callback)
		timers[#timers + 1] = callback
		clock:After(delay, callback)
	end
	local ids = {}
	for index = 1, 4 do
		Equal(requester:RefreshPartyQuestCompare(), true)
		ids[index] = requester.partyQuestCompareSession.byName["Friend-Realm"].requestId
		peer:OnCommReceived(peer.commPrefix, requester.wire[#requester.wire][2], "PARTY", "MyPlayer-Realm")
	end
	local queue = peer.questCompareResponseQueue
	Equal(#queue.jobs, 1)
	Equal(queue.jobs[1].requestId, ids[4])
	Equal(queue.packets, 36)
	Equal(#peer.wire, 1) -- The first response packet was already sent before Refresh.
	Equal(#timers, 1) -- Supersession retains the existing cooldown callback.
	for index = 1, 3 do Equal(requester.pendingQuestCompareRequests[ids[index]], nil) end
	requester:OnCommReceived(requester.commPrefix, peer.wire[1][2], "PARTY", "Friend-Realm")
	local member = requester.partyQuestCompareSession.byName["Friend-Realm"]
	Equal(next(member.entries), nil) -- Delayed old packets cannot enter the new session.
	Equal(member.state, "loading")
	local delivered = 1
	for _ = 1, 40 do
		clock:Advance(0.1) -- The first tick is the callback created for the old response.
		while delivered < #peer.wire do
			delivered = delivered + 1
			local packet = peer.wire[delivered]
			local command, payload = peer:DeserializeWireMessage(packet[2])
			local data = command == "QCQE" and peer:DecodeQuestCompareEntryPayload(payload)
				or peer:DecodeQuestCompareDonePayload(payload)
			Equal(data.requestId, ids[4])
			Equal(packet[3], "PARTY")
			requester:OnCommReceived(requester.commPrefix, packet[2], packet[3], "Friend-Realm")
		end
	end
	Equal(member.state, "ready")
	Equal(member.supportsShareRequests, true)
	Equal(requester.pendingQuestCompareRequests[ids[4]], nil)
	local count = 0
	for _ in pairs(member.entries) do count = count + 1 end
	Equal(count, 35)
	Equal(#peer.wire, 37) -- One unavoidable old entry, then all 35 new entries and done.
	Equal(#queue.jobs, 0)
	Equal(queue.packets, 0)
	clock:Advance(181)
	Equal(member.state, "ready")
	Equal(#peer.wire, 37)
end)

QuestTogether:RegisterTest("comparison supersession uses transport identity and preserves unrelated queue jobs and bounds", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 1)
	local function Receive(id, transportSender, claimedSender, route)
		addon.partyMembers[transportSender] = {}
		local wire = addon:SerializeWireMessage("QCMP", addon:EncodeQuestCompareRequestPayload({
			requestId = id, requesterName = claimedSender or transportSender, targetName = "MyPlayer-Realm",
		}))
		addon:OnCommReceived(addon.commPrefix, wire, route or "PARTY", transportSender)
	end
	Receive("a-old", "Alpha-Realm")
	Receive("b", "Beta-Realm", "Alpha-Realm") -- Payload cannot cancel Alpha's authenticated job.
	Receive("c", "Gamma-Realm")
	Receive("d", "Delta-Realm")
	local queue = addon.questCompareResponseQueue
	Equal(#queue.jobs, 4)
	Equal(queue.jobs[1].requestId, "a-old")
	Equal(queue.jobs[2].requesterName, "Beta-Realm")
	local beta, gamma, delta = queue.jobs[2], queue.jobs[3], queue.jobs[4]
	Receive("a-new", "Alpha-Realm", "Beta-Realm", "RAID")
	Equal(#queue.jobs, 4)
	Equal(queue.jobs[1], beta)
	Equal(queue.jobs[2], gamma)
	Equal(queue.jobs[3], delta)
	Equal(queue.jobs[4].requestId, "a-new")
	Equal(queue.jobs[4].routes[1].distribution, "RAID")
	Equal(queue.packets, 8)
	local latest = queue.jobs[4]
	Receive("a-new", "Alpha-Realm", "Beta-Realm", "PARTY") -- Duplicate route delivery keeps the same job.
	Equal(queue.jobs[4], latest)
	Receive("overflow", "Epsilon-Realm")
	Equal(#queue.jobs, 4)
	Equal(queue.packets, 8)
	for _ = 1, 12 do if not RunResponseTimer(addon) then break end end
	Equal(#queue.jobs, 0)
	Equal(queue.packets, 0)

	addon:ResetCommsState()
	SetComparisonEntries(addon, 60)
	Receive("large-a", "Alpha-Realm")
	Receive("large-b", "Beta-Realm")
	queue = addon.questCompareResponseQueue
	local old, other = queue.jobs[1], queue.jobs[2]
	Equal(queue.packets, 121) -- One Alpha entry has already left the queue.
	SetComparisonEntries(addon, 100)
	Receive("too-large-replacement", "Alpha-Realm")
	Equal(queue.jobs[1], old) -- Failed admission must not discard the valid old job.
	Equal(queue.jobs[2], other)
	Equal(queue.packets, 121)
	SetComparisonEntries(addon, 1)
	Receive("small-replacement", "Alpha-Realm")
	Equal(queue.jobs[1], other)
	Equal(queue.jobs[2].requestId, "small-replacement")
	Equal(queue.packets, 63)
	for _ = 1, 70 do if not RunResponseTimer(addon) then break end end
	Equal(#queue.jobs, 0)
	Equal(queue.packets, 0)
end)

QuestTogether:RegisterTest("restricted comparison refreshes replace pending snapshots without extra timers or stale replies", function()
	local addon, clock = NewSnapshotComparisonFixture()
	addon.restrictions.combat = true
	ReceiveSnapshotComparisonRequest(addon, "restricted-old")
	local oldTimer = clock.timers[1].callback
	clock:Advance(1)
	ReceiveSnapshotComparisonRequest(addon, "restricted-new")
	local queue = addon.questCompareResponseQueue
	Equal(#queue.jobs, 1)
	Equal(queue.jobs[1].requestId, "restricted-new")
	Equal(queue.jobs[1].snapshotAttempts, 0)
	Equal(queue.packets, 1)
	Equal(#clock.timers, 1)
	Equal(addon.questReads, 0)
	addon.restrictions.combat = nil
	clock:Advance(1)
	clock:Advance(0.1)
	Equal(#addon.wire, 2)
	for _, packet in ipairs(addon.wire) do
		local command, payload = addon:DeserializeWireMessage(packet[2])
		local data = command == "QCQE" and addon:DecodeQuestCompareEntryPayload(payload)
			or addon:DecodeQuestCompareDonePayload(payload)
		Equal(data.requestId, "restricted-new")
	end
	Equal(#queue.jobs, 0)
	Equal(queue.packets, 0)
	addon:ResetCommsState()
	oldTimer()
	Equal(addon.questCompareResponseQueue, nil)
	Equal(#addon.wire, 2)
end)
