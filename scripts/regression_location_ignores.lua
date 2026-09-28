-- Live-safe ignore regressions: private frames and QuestTogether-owned seams only.
local QT = _G.QuestTogether

local function Equal(actual, expected, message)
	assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function Patch(replacements, run)
	local originals = {}
	for key, value in pairs(replacements) do
		originals[key], QT[key] = QT[key], value
	end
	local ok, err = pcall(run)
	for key in pairs(replacements) do
		QT[key] = originals[key]
	end
	assert(ok, err)
end

local function RemoteEvent(sender)
	return {
		eventType = "QUEST_COMPLETED",
		senderName = sender or "Ignored-Realm",
		senderGUID = "Player-1-REMOTE",
		classFile = "MAGE",
		text = "Quest complete",
		questId = "12345",
		emoteToken = "CHEER",
	}
end

local function NewReceiver()
	local addon = setmetatable({
		isEnabled = true,
		prints = 0,
		bubbles = 0,
		emotes = 0,
		db = { profile = QT:DeepCopy(QT.DEFAULTS.profile) },
		recentCommMessageSignatures = {},
	}, { __index = QT })
	addon.db.profile.showChatLogs = true
	addon.db.profile.showChatBubbles = true
	addon.db.profile.devLogAllAnnouncements = true
	addon.API = {
		IsOnIgnoredList = function(name)
			return name == "Ignored-Realm"
		end,
		RegionalUniqueNamesEnabled = function()
			return false
		end,
		GetRealmName = function()
			return "Realm"
		end,
		GetTime = function()
			return 100
		end,
		GetChannelName = function()
			return 7
		end,
	}
	function addon:GetPlayerFullName()
		return "Self-Realm"
	end
	function addon:GetPlayerName()
		return "Self"
	end
	function addon:IsGroupedSender()
		return true
	end
	function addon:ShouldDisplayAnnouncementType()
		return true
	end
	function addon:RecordCommsDiagnostic() end
	function addon:Debug() end
	function addon:Debugf() end
	function addon:FindVisiblePlayerNameplateForSender()
		return {}
	end
	function addon:FindNearbyPlayerUnitTokenForSender()
		return nil
	end
	function addon:IsAnnouncementSenderNearbyByLocation()
		return false
	end
	function addon:PrintConsoleAnnouncement()
		self.prints = self.prints + 1
	end
	function addon:ShowAnnouncementBubbleOnNameplate()
		self.bubbles = self.bubbles + 1
	end
	function addon:PlayRemoteCelebrationEmote()
		self.emotes = self.emotes + 1
	end
	return addon
end

QT:RegisterTest("ignored transport sender cannot bypass suppression with an allowed payload name", function()
	local addon = NewReceiver()
	local wire = "ANN|" .. addon:EncodeAnnouncementPayload(RemoteEvent("Allowed-Realm"))
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Ignored-Realm")
	addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", "Ignored-Realm", 7, addon.announcementChannelName)
	Equal(addon.prints, 0)
	Equal(addon.bubbles, 0)
	Equal(addon.emotes, 0)
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Allowed-Realm")
	Equal(addon.prints, 1, "an allowed sender remains visible")
	Equal(addon.bubbles, 1)
	Equal(addon.emotes, 1)
end)

QT:RegisterTest("ignored remote announcements stay suppressed through direct handling and developer logging", function()
	local addon = NewReceiver()
	Equal(addon:HandleAnnouncementEvent(RemoteEvent(), false), false)
	Equal(addon:ShouldShowAnnouncementsForRemoteSender("Ignored-Realm", true), false)
	Equal(addon.prints, 0)
	Equal(addon.bubbles, 0)
	Equal(addon.emotes, 0)
	Equal(addon:HandleAnnouncementEvent(RemoteEvent("Allowed-Realm"), false), true)
	Equal(addon.prints, 1)
	Equal(addon.bubbles, 1)
	Equal(addon.emotes, 1)
end)

QT:RegisterTest("regional ignore suppression preserves full surname identity", function()
	local addon = NewReceiver()
	addon.API.RegionalUniqueNamesEnabled = function()
		return true
	end
	addon.API.IsOnIgnoredList = function(name)
		assert(name ~= "Anakin", "ignore lookup must not collapse different surnames")
		return name == "Anakin Ofthesea"
	end
	Equal(addon:HandleAnnouncementEvent(RemoteEvent("Anakin-Ofthesea"), false), false)
	local wire = "ANN|" .. addon:EncodeAnnouncementPayload(RemoteEvent("Allowed Else"))
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Anakin Ofthesea")
	Equal(addon.prints, 0)
	Equal(addon.bubbles, 0)
	Equal(addon.emotes, 0)
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Anakin Else")
	Equal(addon.prints, 1)
	Equal(addon.bubbles, 1)
	Equal(addon.emotes, 1)
end)

local function WithBubbles(run)
	local state = { restricted = false, ignored = {}, hosts = {}, guids = {}, nextUnit = 0 }
	local function Region(parent)
		local frame = { parent = parent, shown = true, writes = 0 }
		function frame:IsForbidden()
			return self.forbidden == true
		end
		function frame:IsProtected()
			return self.protected == true
		end
		function frame:IsShown()
			return self.shown
		end
		function frame:GetParent()
			return self.parent
		end
		function frame:GetFrameStrata()
			return "LOW"
		end
		function frame:GetFrameLevel()
			return 1
		end
		local function Mutate(self)
			assert(not self.forbidden, "forbidden visual mutated")
			assert(not state.restricted, "remote visual mutated during restrictions")
			self.writes = self.writes + 1
		end
		function frame:Show()
			Mutate(self)
			self.shown = true
		end
		function frame:Hide()
			Mutate(self)
			self.shown = false
		end
		for _, method in ipairs({
			"SetFrameStrata",
			"SetFrameLevel",
			"SetAlpha",
			"ClearAllPoints",
			"SetPoint",
			"SetSize",
			"SetClampRectInsets",
			"SetWidth",
			"SetText",
			"SetFont",
		}) do
			frame[method] = Mutate
		end
		return frame
	end
	function state:Add(sender)
		self.nextUnit = self.nextUnit + 1
		local token = "nameplate" .. self.nextUnit
		self.guids[token] = "Player-fixture-" .. token
		local host, unitFrame = Region(), Region()
		host.UnitFrame, unitFrame.unit = unitFrame, token
		local bubble = Region(host)
		bubble.String = Region(bubble)
		function bubble.String:GetFont()
			return "font", 14, ""
		end
		function bubble.String:GetUnboundedStringWidth()
			return 100
		end
		function bubble.String:GetStringHeight()
			return 14
		end
		bubble.animationGroup = { playing = false, stops = 0, plays = 0 }
		function bubble.animationGroup:IsPlaying()
			return self.playing
		end
		function bubble.animationGroup:Play()
			assert(not state.restricted and not bubble.forbidden, "blocked animation played")
			self.playing, self.plays = true, self.plays + 1
		end
		function bubble.animationGroup:Stop()
			assert(not state.restricted and not bubble.forbidden, "blocked animation stopped")
			self.playing, self.stops = false, self.stops + 1
			QT:CompleteAnnouncementBubblePlayback(bubble)
		end
		self.hosts[token] = host
		QT.nameplateBubbleByUnitFrame[unitFrame] = bubble
		Equal(QT:ShowAnnouncementBubbleOnNameplate(host, "Initial progress", "QUEST_PROGRESS", nil, nil, sender), true)
		return bubble, host
	end
	QT.isEnabled = true
	QT.db.profile.showChatBubbles = true
	Patch({
		API = {
			UnitGUID = function(token)
				return state.guids[token]
			end,
			GetRealmName = function()
				return "Realm"
			end,
			RegionalUniqueNamesEnabled = function()
				return false
			end,
		},
		IsRuntimeRestricted = function()
			return state.restricted
		end,
		IsIgnoredPlayerName = function(_, name)
			return state.ignored[name] == true
		end,
		GetAnnouncementBubbleHostFrameForUnit = function(_, token)
			return state.hosts[token]
		end,
	}, function()
		run(state)
	end)
end

QT:RegisterTest("ignored named bubble requests reject before reading a foreign host", function()
	local reads = 0
	local host = setmetatable({}, {
		__index = function()
			reads = reads + 1
			error("ignored sender must not read its foreign host")
		end,
	})
	WithBubbles(function(state)
		state.ignored["Ignored-Realm"] = true
		Equal(
			QT:ShowAnnouncementBubbleOnNameplate(host, "Unwanted", "QUEST_PROGRESS", nil, nil, "Ignored-Realm"),
			false
		)
		Equal(reads, 0)
	end)
end)

QT:RegisterTest("ignore cleanup discards only ignored remote playback without looking up hosts", function()
	WithBubbles(function(state)
		local ignored = state:Add("Ignored-Realm")
		local allowed = state:Add("Allowed-Realm")
		local personal = { animationGroup = {
			IsPlaying = function()
				return true
			end,
		} }
		QT.nameplateBubbleStateByFrame[personal] =
			{ unitToken = "player", text = "Personal", senderName = "Ignored-Realm" }
		state.ignored["Ignored-Realm"] = true
		Patch({
			GetAnnouncementBubbleHostFrameForUnit = function()
				error("cleanup must use owned identity only")
			end,
		}, function()
			Equal(QT:ClearIgnoredAnnouncementBubbles(), 1)
		end)
		Equal(ignored.shown, false)
		Equal(ignored.animationGroup.stops, 1)
		Equal(QT.nameplateBubbleStateByFrame[ignored], nil)
		Equal(allowed.shown, true)
		Equal(allowed.animationGroup.stops, 0)
		Equal(QT.nameplateBubbleStateByFrame[personal].text, "Personal")
		Equal(QT:ClearIgnoredAnnouncementBubbles(), 0, "duplicate updates are idempotent")
	end)
end)

QT:RegisterTest("ignore-list runtime event clears existing ignored bubbles", function()
	local registered = false
	for _, event in ipairs(QT.runtimeEvents) do
		if event == "IGNORELIST_UPDATE" then
			registered = true
		end
	end
	Equal(registered, true, "ignore changes must be observed while enabled")
	WithBubbles(function(state)
		local ignored = state:Add("Ignored-Realm")
		local allowed = state:Add("Allowed-Realm")
		state.ignored["Ignored-Realm"] = true
		Patch({
			PrunePlayerLocations = function() end,
			RefreshPlayerLocationPins = function() end,
			CancelIgnoredPlayerQuestCompare = function() end,
		}, function()
			QT:IGNORELIST_UPDATE()
		end)
		Equal(ignored.shown, false)
		Equal(QT.nameplateBubbleStateByFrame[ignored], nil)
		Equal(allowed.shown, true)
	end)
end)

QT:RegisterTest("ignored bubble cleanup defers blocked mutations and never replays after unignore", function()
	for _, blockedBy in ipairs({ "restriction", "forbidden" }) do
		WithBubbles(function(state)
			local bubble = state:Add("Ignored-Realm")
			local writes = bubble.writes
			state.ignored["Ignored-Realm"] = true
			state.restricted = blockedBy == "restriction"
			bubble.forbidden = blockedBy == "forbidden"
			bubble.protected = true
			Equal(QT:ClearIgnoredAnnouncementBubbles(), 1)
			Equal(bubble.writes, writes)
			Equal(bubble.animationGroup.stops, 0)
			Equal(QT.nameplateBubbleStateByFrame[bubble], nil, "replayable data is discarded while blocked")
			Equal(QT:GetNameplateStateStore().pendingVisualCleanupByFrame[bubble], "bubble")
			Equal(QT.pendingNameplateVisualCleanup, true)
			state.ignored["Ignored-Realm"] = false
			state.restricted, bubble.forbidden = false, false
			Patch({
				TryInstallPersonalBubbleEditModeHooks = function() end,
				ScheduleNameplatePresentationRefresh = function() end,
			}, function()
				QT:HandleNameplateEvent("PLAYER_REGEN_ENABLED")
			end)
			QT:RefreshActiveAnnouncementBubbles()
			Equal(bubble.shown, false)
			Equal(bubble.animationGroup.plays, 1, "unignore never restarts discarded playback")
			Equal(QT.pendingNameplateVisualCleanup, false)
		end)
	end
end)

QT:RegisterTest("new allowed playback cancels deferred ignore cleanup on the reused bubble", function()
	WithBubbles(function(state)
		local bubble, host = state:Add("Ignored-Realm")
		state.ignored["Ignored-Realm"], state.restricted = true, true
		Equal(QT:ClearIgnoredAnnouncementBubbles(), 1)
		state.restricted = false
		state.guids[host.UnitFrame.unit] = "Player-fixture-recycled"
		Equal(
			QT:ShowAnnouncementBubbleOnNameplate(
				host,
				"New allowed progress",
				"QUEST_PROGRESS",
				nil,
				nil,
				"Allowed-Realm"
			),
			true
		)
		Equal(QT.pendingNameplateVisualCleanup, false)
		Equal(QT:RetryPendingNameplateVisualCleanup(), true)
		Equal(bubble.shown, true)
		Equal(QT.nameplateBubbleStateByFrame[bubble].senderName, "Allowed-Realm")
		Equal(QT.nameplateBubbleStateByFrame[bubble].unitGUID, "Player-fixture-recycled")
		Equal(QT.nameplateBubbleStateByFrame[bubble].text, "New allowed progress")
	end)
end)
