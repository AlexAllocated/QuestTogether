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
	return a
end

QT:RegisterTest("QT presence authenticates transport and survives disabled location sharing", function()
	local a, b = Peer("Anakin Othername"), Peer("Luke Bucket")
	a.forever, b.forever, a.other = true, true, b
	a.db.profile.shareLocationOnMap, a.db.profile.shareLocationOnMinimap = false, false
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

QT:RegisterTest("QT presence is paced bounded expires and processes explicit departure", function()
	local a, b = Peer(), Peer("Friend-Realm")
	a.other = b
	assert(a:BroadcastQTPlayerPresence())
	a.now = 119
	Equal(a:BroadcastQTPlayerPresence(), false)
	a.now, a.sendFails = 120, true
	Equal(a:BroadcastQTPlayerPresence(), false)
	Equal(#a.sent, 2)
	b.now = 165
	Equal(b:IsKnownQTPlayer(a.name), false)
	b:PruneQTPlayerPresence()
	Equal(next(b.qtPlayerPresenceState.peers), nil)
	a.now, a.sendFails, b.now = 140, false, 166
	assert(a:BroadcastQTPlayerPresence())
	assert(b:IsKnownQTPlayer(a.name))
	assert(a:BroadcastQTPlayerPresence(true))
	Equal(b:IsKnownQTPlayer(a.name), false)
	a.isLoggingOut = true
	a.now = 200
	Equal(a:BroadcastQTPlayerPresence(), false)
	for i = 1, 270 do
		b.now = 200 + i
		assert(b:RecordQTPlayerPresence("Peer" .. i .. "-Realm", true))
	end
	local count = 0
	for _ in pairs(b.qtPlayerPresenceState.peers) do
		count = count + 1
	end
	Equal(count, 256)
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
				Equal(key, "nameplateShowFriends")
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

QT:RegisterTest("QT player icons expire and ignore cleanup defers quarantined handles", function()
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
		s.now = 165
		QT:PruneQTPlayerPresence()
		Equal(icon.shown, false)
	end)
end)

QT:RegisterTest("QT departure after expiry cleans visible logos before periodic pruning", function()
	WithPlate(function(s)
		QT:RefreshNameplateIcon(s.plate)
		local icon = QT.nameplateIconByUnitFrame[s.frame]
		assert(icon.shown)
		s.now = 165.01
		QT:OnCommReceived(QT.commPrefix, "QTPR|1,0", "PARTY", s.name)
		Equal(QT.qtPlayerPresenceState.peers[s.name], nil)
		Equal(QT:IsKnownQTPlayer(s.name), false)
		Equal(icon.shown, false, "expired read state must not skip cleanup of a stored peer")
		local refreshes = s.refreshes
		QT:OnCommReceived(QT.commPrefix, "QTPR|1,0", "PARTY", s.name)
		Equal(s.refreshes, refreshes, "duplicate departure must not schedule another refresh")
		local frame = { IsForbidden = function() return false end, IsProtected = function() return false end }
		function frame:SetScript(_, callback) self.onUpdate = callback end
		Patch({
			hasLoggedIn = true,
			playerLocationUpdateFrame = false,
			CreatePlayerLocationUpdateFrame = function() return frame end,
			BroadcastQTPlayerPresence = function() return false end,
			BroadcastPlayerLocation = function() return false end,
			PrunePlayerLocations = function() end,
			RefreshPlayerLocationPins = function() end,
		}, function()
			assert(QT:InitializePlayerLocations())
			for _ = 1, 3 do s.now = s.now + 1; frame.onUpdate(frame, 1) end
		end)
		Equal(icon.shown, false)
	end)
end)

QT:RegisterTest("expired departure quarantines forbidden logos until safe cleanup", function()
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
