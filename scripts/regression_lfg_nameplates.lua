-- Live-safe fixtures: only QT-owned adapters and private regions are replaced.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

local function Fixture()
	local s = { name = "Friend Othername", invalid = 0, mutations = 0, textures = 0, creations = 0 }
	s.clock = QT:CreateTestClock(100)
	local function Region(parent, owned)
		local r = { parent = parent, shown = true, points = {} }
		function r:IsForbidden()
			return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
		end
		function r:IsProtected()
			return self.protected == true or (self.parent and self.parent:IsProtected()) or false
		end
		local function Read(self)
			if self:IsForbidden() or s.blocked then
				s.invalid = s.invalid + 1
				error("unsafe LFG frame read")
			end
		end
		local function Write(self, hide)
			if not owned or self:IsForbidden() or (s.blocked and (not hide or self:IsProtected())) then
				s.invalid = s.invalid + 1
				error("unsafe LFG region mutation")
			end
			s.mutations = s.mutations + 1
		end
		function r:IsShown()
			Read(self)
			return self.shown
		end
		function r:GetFrameStrata()
			Read(self)
			return "LOW"
		end
		function r:GetFrameLevel()
			Read(self)
			return 1
		end
		function r:Show()
			Write(self)
			self.shown = true
		end
		function r:Hide()
			Write(self, true)
			self.shown = false
		end
		function r:CreateTexture(_, layer)
			Write(self)
			s.textures = s.textures + 1
			local texture = Region(self, true)
			texture.layer = layer
			return texture
		end
		function r:CreateAnimationGroup()
			if s.animationUnsupported then error("animation unavailable") end
			Write(self)
			local group = { animations = {}, plays = 0, stops = 0 }
			function group:SetLooping(value) self.looping = value end
			function group:CreateAnimation(kind)
				Equal(kind, "Alpha")
				local animation = {}
				for _, field in ipairs({ "Order", "FromAlpha", "ToAlpha", "Duration", "Smoothing" }) do
					local key = field
					animation["Set" .. key] = function(_, value) animation[key] = value end
				end
				self.animations[#self.animations + 1] = animation
				return animation
			end
			function group:IsPlaying() Read(r); return self.playing == true end
			function group:Play() Write(r); self.playing = true; self.plays = self.plays + 1 end
			function group:Stop() Write(r, true); self.playing = false; self.stops = self.stops + 1 end
			return group
		end
		function r:SetTexture(value)
			Write(self)
			self.texture = value
		end
		function r:SetColorTexture(...)
			Write(self)
			self.color = { ... }
		end
		function r:SetVertexColor(...)
			Write(self)
			self.color = { ... }
		end
		function r:SetBlendMode(value)
			Write(self)
			self.blendMode = value
		end
		function r:SetPoint(...)
			Write(self)
			self.points[#self.points + 1] = { ... }
		end
		function r:ClearAllPoints()
			Write(self)
			self.points = {}
		end
		function r:SetWidth(value)
			Write(self)
			self.width = value
		end
		function r:SetHeight(value)
			Write(self)
			self.height = value
		end
		function r:SetSize(width, height)
			Write(self)
			self.width, self.height = width, height
		end
		for _, method in ipairs({ "SetFrameStrata", "SetFrameLevel", "SetTexCoord", "SetAllPoints" }) do
			r[method] = Write
		end
		return r
	end
	s.plate = Region()
	s.unitFrame = Region(s.plate)
	s.unitFrame.unit, s.unitFrame.healthBar, s.unitFrame.name = "nameplate1", Region(s.unitFrame), Region(s.unitFrame)
	s.plate.UnitFrame = s.unitFrame
	QT.isEnabled = true
	QT.db.profile.nameplatePlayerIconEnabled = true
	QT.qtPlayerPresenceState = { peers = { [s.name] = 100 } }
	QT.peerSnapshotState = nil
	QT.recentCommMessageSignatures = {}
	QT.nameplateRegisteredEvents.NAME_PLATE_UNIT_ADDED = true
	QT.API = {
		GetCVar = function()
			return "1"
		end,
		GetTime = function()
			return s.clock:GetTime()
		end,
		Delay = function(delay, callback)
			s.clock:After(delay, callback)
		end,
		RegionalUniqueNamesEnabled = function()
			return true
		end,
		UnitFullName = function(unit)
			return unit == "player" and "Me Self" or s.name
		end,
		UnitExists = function()
			return not s.removed
		end,
		UnitIsPlayer = function()
			return not s.npc
		end,
		UnitIsFriend = function()
			return true
		end,
		UnitGUID = function()
			return s.npc and "Creature-0-0-0-0-123-0" or "Player-1-123"
		end,
		GetNamePlateForUnit = function()
			return not s.removed and s.plate or nil
		end,
		GetNamePlates = function()
			return { s.plate }
		end,
		IsInInstance = function()
			return false
		end,
		IsWorldMapVisible = function()
			return false
		end,
		IsOnIgnoredList = function(name)
			return name == s.ignored
		end,
	}
	QT.IsRuntimeRestricted = function()
		return s.blocked == true
	end
	QT.IsRuntimeRestrictionTypeActive = function(_, kind)
		return s.blocked and kind == "encounter" or false
	end
	QT.CreateNameplateQuestIconFrame = function(_, parent)
		s.creations = s.creations + 1
		return Region(parent, true)
	end
	function s:Show()
		QT:OnNameplateAdded("nameplate1")
		self.icon = QT.nameplateIconByUnitFrame[self.unitFrame]
		assert(self.icon and self.icon.shown)
		return self.icon
	end
	function s:Status(looking)
		self.sequence = (self.sequence or 0) + 1
		QT:OnCommReceived(
			QT.commPrefix,
			"QTLF|1,100-1234," .. self.sequence .. "," .. (looking and "1" or "0"),
			"PARTY",
			self.name
		)
	end
	return s
end

local function Glow(icon, shown)
	assert(icon.qtPartnerGlow and #icon.qtPartnerGlow == 8, "eight reusable contour-glow regions expected")
	for index, edge in ipairs(icon.qtPartnerGlow) do
		local pulse = icon.qtPartnerGlowPulses[index]
		assert(pulse and pulse.playing == shown)
		Equal(pulse.looping, "REPEAT")
		Equal(#pulse.animations, 2)
		assert(pulse.animations[1].FromAlpha > 0, "pulse must not blink off")
		Equal(pulse.animations[1].ToAlpha, pulse.animations[2].FromAlpha)
		Equal(pulse.animations[2].ToAlpha, pulse.animations[1].FromAlpha)
		Equal(edge.parent, icon)
		Equal(edge.shown, shown)
		Equal(edge.layer, "BACKGROUND")
		Equal(edge.texture, QT.NAMEPLATE_PLAYER_ICON_TEXTURE)
		Equal(edge.blendMode, "ADD")
		assert(edge.color[4] > 0 and edge.color[4] < 1)
		assert(edge.color[1] > 0.9 and edge.color[2] > 0.6 and edge.color[3] < 0.3)
		assert(#edge.points == 2, "glow follows the logo size")
		for _, point in ipairs(edge.points) do
			Equal(point[2], icon)
			assert(math.abs(point[4]) <= 4 and math.abs(point[5]) <= 4, "halo stays within its four-pixel reach")
		end
	end
end

QT:RegisterTest("partner messages add and remove the gold player-logo glow without replacing its artwork", function()
	local s = Fixture()
	local icon = s:Show()
	Equal(icon.qtPartnerGlow, nil)
	local texture, anchor = icon.Icon.texture, icon.points[1][2]
	s:Status(true)
	s.clock:Advance(0)
	Glow(icon, true)
	Equal(icon.Icon.texture, texture)
	Equal(icon.points[1][2], anchor)
	Equal(QT.qtPlayerIconStateByFrame[icon].lookingForPartners, true)
	Equal(s.textures, 9)
	local mutations = s.mutations
	s:Status(true)
	s.clock:Advance(0)
	Equal(s.mutations, mutations, "unchanged status must not relayout the plate")
	s:Status(false)
	s.clock:Advance(0)
	Glow(icon, false)
	assert(icon.shown)
	Equal(QT.qtPlayerIconStateByFrame[icon].lookingForPartners, false)
	s:Status(true)
	s.clock:Advance(0)
	Glow(icon, true)
	Equal(s.textures, 9)
	Equal(s.invalid, 0)
end)

QT:RegisterTest("partner logo expiry removes only the glow while session recognition keeps the logo", function()
	local s = Fixture()
	local icon = s:Show()
	s:Status(true)
	s.clock:Advance(0)
	Glow(icon, true)
	s.clock:Advance(64)
	QT:PruneQTPlayerPresence()
	Glow(icon, true)
	s.clock:Advance(1)
	QT:PruneQTPlayerPresence()
	s.clock:Advance(0)
	Glow(icon, false)
	assert(icon.shown and QT:IsKnownQTPlayer(s.name))
	Equal(s.invalid, 0)
end)

QT:RegisterTest("evicted partner status removes a remembered player's glow without losing their logo", function()
	local s = Fixture()
	local icon = s:Show()
	s:Status(true)
	s.clock:Advance(1)
	Glow(icon, true)
	local state = QT:GetQTPlayerPresenceState()
	-- Model a full bounded status cache with this visible player the oldest.
	for index = 1, 255 do
		local name = "Other" .. index .. " Othername"
		state.peers[name] = s.clock:GetTime()
		state.questPartners[name] = {
			session = "100-1234",
			sequence = 1,
			looking = false,
			receivedAt = s.clock:GetTime(),
			retired = {},
		}
	end
	QT:OnCommReceived(QT.commPrefix, "QTLF|1,100-1234,1,0", "PARTY", "Newest Othername")
	s.clock:Advance(0)
	Equal(state.questPartners[s.name], nil)
	assert(QT:IsKnownQTPlayer(s.name) and icon.shown)
	Glow(icon, false)
	Equal(s.textures, 9)
	Equal(s.invalid, 0)
end)

QT:RegisterTest("delayed old partner status cannot relight the glow after an ordered withdrawal", function()
	local s = Fixture()
	local icon = s:Show()
	s:Status(true)
	s.clock:Advance(0)
	s:Status(false)
	s.clock:Advance(1)
	Glow(icon, false)
	local mutations = s.mutations
	QT:OnCommReceived(QT.commPrefix, "QTLF|1,100-1234,1,1", "PARTY", s.name)
	s.clock:Advance(0)
	Glow(icon, false)
	Equal(s.mutations, mutations)
	Equal(s.invalid, 0)
end)

QT:RegisterTest("partner glows follow every logo style and clear when the owned frame becomes a quest icon", function()
	local s = Fixture()
	s:Status(true)
	local icon = s:Show()
	for _, style in ipairs({ "left", "right", "prefix", "top" }) do
		QT.db.profile.nameplatePlayerIconStyle = style
		QT:RefreshNameplateIcon(s.plate)
		Glow(icon, true)
		Equal(icon.Icon.texture, QT.NAMEPLATE_PLAYER_ICON_TEXTURE)
	end
	s.npc = true
	QT.db.profile.nameplateQuestIconEnabled = true
	QT.TryResolveNameplateQuestObjectiveState = function()
		return true, true, "Creature-0-0-0-0-123-0"
	end
	QT.RefreshNameplateHealthTint = function() end
	QT:RefreshNameplateIcon(s.plate)
	Equal(icon.qtIconKind, "quest")
	Glow(icon, false)
	Equal(s.creations, 1)
	Equal(s.invalid, 0)
end)

QT:RegisterTest("partner glow state does not carry to another player on a reused frame", function()
	local s = Fixture()
	s:Status(true)
	local icon = s:Show()
	Glow(icon, true)
	s.name = "Another Othername"
	QT.qtPlayerPresenceState.peers[s.name] = s.clock:GetTime()
	QT:RefreshNameplateIcon(s.plate)
	assert(icon.shown)
	Glow(icon, false)
	Equal(QT.qtPlayerIconStateByFrame[icon].name, s.name)
	Equal(s.invalid, 0)
end)

QT:RegisterTest("partner glow updates defer restrictions and never mutate forbidden regions", function()
	local s = Fixture()
	local icon = s:Show()
	s.blocked, icon.protected = true, true
	s:Status(true)
	s.clock:Advance(0)
	Equal(icon.qtPartnerGlow, nil)
	Equal(s.invalid, 0)
	s.blocked, icon.protected = false, false
	QT:FlushDeferredWork("partner restriction ended")
	s.clock:Advance(0)
	Glow(icon, true)
	icon.qtPartnerGlow[1].forbidden = true
	s:Status(false)
	s.clock:Advance(0)
	Equal(icon.shown, false, "an inaccessible glow must not remain visible with an obsolete status")
	assert(QT.qtPlayerIconStateByFrame[icon].partnerIndicatorPending)
	Equal(s.invalid, 0)
	icon.qtPartnerGlow[1].forbidden = false
	QT:PruneQTPlayerPresence(true)
	s.clock:Advance(0)
	Glow(icon, false)
	assert(icon.shown)
	Equal(QT.qtPlayerIconStateByFrame[icon].partnerIndicatorPending, nil)
end)

QT:RegisterTest("deferred partner status displays only the latest value when restrictions end", function()
	local s = Fixture()
	local icon = s:Show()
	s:Status(true)
	s.clock:Advance(0)
	Glow(icon, true)
	s.blocked, icon.protected = true, true
	s:Status(false)
	s.clock:Advance(0)
	s:Status(true)
	s.clock:Advance(0)
	s.blocked, icon.protected = false, false
	QT:FlushDeferredWork("latest partner status after restriction")
	s.clock:Advance(0)
	Glow(icon, true)
	Equal(QT.qtPlayerIconStateByFrame[icon].lookingForPartners, true)
	Equal(s.textures, 9)
	Equal(s.invalid, 0)
end)

QT:RegisterTest("queued and quarantined partner changes cannot revive retired player logos", function()
	for _, pending in ipairs({ "queued", "quarantined" }) do
		for _, action in ipairs({ "removed", "disabled", "ignored", "departed" }) do
			local s = Fixture()
			local icon = s:Show()
			s:Status(true)
			if pending == "quarantined" then
				s.clock:Advance(0)
				Glow(icon, true)
				icon.qtPartnerGlow[1].forbidden = true
				s:Status(false)
				s.clock:Advance(0)
				assert(QT.qtPlayerIconStateByFrame[icon].partnerIndicatorPending)
			end
			if action == "removed" then
				s.removed = true
				QT:OnNameplateRemoved("nameplate1")
			elseif action == "disabled" then
				QT.isEnabled = false
				QT:DisableNameplateAugmentation()
			elseif action == "departed" then
				QT:OnCommReceived(QT.commPrefix, "QTPR|1,0", "PARTY", s.name)
			else
				s.ignored = s.name
				QT:PruneQTPlayerPresence(true)
			end
			if icon.qtPartnerGlow then
				icon.qtPartnerGlow[1].forbidden = false
			end
			s.clock:Advance(1)
			QT:PruneQTPlayerPresence(true)
			s.clock:Advance(0)
			Equal(icon.shown, false)
			Equal((QT.qtPlayerIconStateByFrame or {})[icon], nil)
			Equal(s.invalid, 0)
		end
	end
end)

QT:RegisterTest("partner indicator refresh accepts empty stores and old records without status fields", function()
	local s = Fixture()
	QT.qtPlayerIconStateByFrame = nil
	Equal(QT:RefreshQTPlayerPartnerIndicators(), false)
	local icon = s:Show()
	QT.qtPlayerIconStateByFrame[icon].lookingForPartners = nil
	local timers = #s.clock.timers
	Equal(QT:RefreshQTPlayerPartnerIndicators(), false)
	Equal(#s.clock.timers, timers)
	s:Status(true)
	s.clock:Advance(0)
	Glow(icon, true)
	Equal(s.invalid, 0)
end)

QT:RegisterTest("partner logo pulses stop on hide and restart without allocating new glow layers", function()
	local s = Fixture()
	s:Status(true)
	s.clock:Advance(0)
	local icon = s:Show()
	Glow(icon, true)
	local pulse, textures = icon.qtPartnerGlowPulses[1], s.textures
	local plays = pulse.plays
	s:Show()
	Equal(pulse.plays, plays)
	QT:HideQTPlayerIcon(icon)
	Glow(icon, false)
	s:Show()
	Glow(icon, true)
	Equal(pulse.plays, plays + 1)
	Equal(s.textures, textures)
	Equal(s.invalid, 0)
end)

QT:RegisterTest("unsupported native animation keeps the partner logo bright and static", function()
	local s = Fixture()
	s.animationUnsupported = true
	s:Status(true)
	s.clock:Advance(0)
	local icon = s:Show()
	assert(icon.shown and icon.qtLookingForPartners)
	Equal(next(icon.qtPartnerGlowPulses), nil)
	for _, layer in ipairs(icon.qtPartnerGlow) do
		assert(layer.shown and layer.color[4] >= 0.8)
	end
	s:Status(false)
	s.clock:Advance(0)
	for _, layer in ipairs(icon.qtPartnerGlow) do assert(not layer.shown) end
	Equal(s.invalid, 0)
end)
