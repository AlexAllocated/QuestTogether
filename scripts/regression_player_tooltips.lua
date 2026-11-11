-- Live-safe: native hosts, unit reads and artwork are all private fixtures.
local QT = _G.QuestTogether
local function Equal(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end
local function Fixture()
	local a = setmetatable({
		isEnabled = true,
		now = 100,
		known = true,
		friendly = true,
		player = true,
		name = "Friend-Realm",
		guid = "Player-1",
		unit = "mouseover",
		invalid = 0,
		frames = {},
		reads = 0,
		writes = 0,
		measurements = 0,
		db = { profile = QT:DeepCopy(QT.DEFAULTS.profile), global = {} },
		partyMembers = {},
	}, { __index = QT })
	local function Frame(parent, owned)
		local f = { parent = parent, owned = owned, shown = true, width = 180, bottom = 180, scale = 1, points = {} }
		function f:IsForbidden()
			return self.forbidden == true
		end
		function f:IsProtected()
			return self.protected == true
		end
		local function Check(self, write)
			if self.forbidden or (write and not self.owned) then
				a.invalid = a.invalid + 1
				error("unsafe tooltip fixture access")
			end
			if write then a.writes = a.writes + 1 end
		end
		function f:IsShown()
			Check(self)
			return self.shown
		end
		function f:IsVisible()
			Check(self)
			return self.shown and (not self.parent or self.parent:IsVisible())
		end
		function f:SetParent(parent)
			Check(self, true)
			self.parent = parent
		end
		function f:GetParent()
			Check(self)
			return self.parent
		end
		function f:GetWidth()
			Check(self)
			return self.width
		end
		function f:GetBottom()
			Check(self)
			return self.bottom
		end
		function f:GetEffectiveScale()
			Check(self)
			return self.scale
		end
		function f:GetUnit()
			Check(self)
			a.reads = a.reads + 1
			return a.name, a.unit
		end
		function f:GetStringHeight()
			Check(self)
			a.measurements = a.measurements + 1
			return a.textHeight or 28
		end
		function f:GetStringWidth()
			Check(self)
			a.measurements = a.measurements + 1
			return #(self.text or "") * 6
		end
		function f:Show()
			Check(self, true)
			self.shown = true
		end
		function f:Hide()
			Check(self, true)
			self.shown = false
		end
		function f:SetWidth(v)
			Check(self, true)
			self.width = v
		end
		function f:SetScale(v)
			Check(self, true)
			self.scale = v
		end
		function f:SetSize(w, h)
			Check(self, true)
			self.width, self.height = w, h
		end
		function f:SetText(v)
			Check(self, true)
			if self.failText then error("injected owned text failure") end
			self.text = v
		end
		function f:ClearAllPoints()
			Check(self, true)
			self.points = {}
		end
		function f:SetPoint(...)
			Check(self, true)
			self.points[#self.points + 1] = { ... }
		end
		function f:CreateTexture()
			Check(self, true)
			return Frame(self, true)
		end
		function f:CreateFontString()
			Check(self, true)
			return Frame(self, true)
		end
		f.CreateMaskTexture = f.CreateTexture
		for _, method in ipairs({
			"SetFrameStrata",
			"SetClampedToScreen",
			"EnableMouse",
			"SetAllPoints",
			"SetColorTexture",
			"SetTexture",
			"SetJustifyH",
			"SetWordWrap",
			"SetTexCoord",
			"SetVertexColor",
			"SetTextColor",
			"SetBlendMode",
			"SetAlpha",
			"SetSpacing",
			"AddMaskTexture",
			"SetJustifyV",
			"SetScript",
		}) do
			f[method] = function(self)
				Check(self, true)
			end
		end
		return f
	end
	a.frameFactory = Frame
	a.host, a.parent = Frame(nil, false), Frame(nil, false)
	a.bar = Frame(a.host, false)
	a.bar.bottom = 174
	a.API = {
		GetTime = function()
			return a.now
		end,
		UnitExists = function()
			return true
		end,
		UnitIsPlayer = function()
			return a.player
		end,
		UnitIsUnit = function()
			return a.selfUnit == true
		end,
		IsPlayerTooltipFriend = function()
			return a.friend == true or a.bnetFriend == true
		end,
		UnitGUID = function()
			return a.guid
		end,
		UnitIsFriend = function()
			return a.friendly
		end,
		GetRealmName = function()
			return "Realm"
		end,
		RegionalUniqueNamesEnabled = function()
			return false
		end,
	}
	function a:GetPlayerTooltipHost()
		return self.host
	end
	function a:GetPlayerTooltipHealthBar()
		return self.bar
	end
	function a:GetPlayerTooltipParent()
		return self.parent
	end
	function a:CreatePlayerTooltipFrame(parent)
		local f = Frame(parent, true)
		self.frames[#self.frames + 1] = f
		return f
	end
	function a:GetUnitFullName()
		return self.name
	end
	function a:GetPlayerFullName()
		return "Me-Realm"
	end
	function a:IsIgnoredPlayerName(name)
		return name == self.ignored
	end
	function a:IsKnownQTPlayer()
		return self.known
	end
	function a:IsWorkBlocked()
		return self.blocked == true
	end
	return a
end

QT:RegisterTest("whole player tooltip section follows current friendship and group membership", function()
	local a = Fixture()
	function a:GetPlayerNoteTooltipText() return "Private note: A helpful healer" end
	a.qtPlayerPresenceState = { peers = {}, questPartners = { [a.name] = { receivedAt = 100, looking = true } } }
	Equal(a:GetPlayerTooltipIdentifierMode(), "friends")
	for _, mode in ipairs({ "all", "friends", "party", "friends_party", "hidden" }) do
		a.db.profile.playerTooltipIdentifierMode = mode
		for _, friendKind in ipairs({ "neither", "character", "bnet" }) do
			for _, grouped in ipairs({ false, true }) do
				a.friend, a.bnetFriend = friendKind == "character", friendKind == "bnet"
				a.partyMembers = grouped and { [a.name] = {} } or {}
				local expected = mode ~= "hidden"
					and not ((mode == "friends" or mode == "friends_party") and friendKind ~= "neither")
					and not ((mode == "party" or mode == "friends_party") and grouped)
				Equal(a:UpdatePlayerTooltipBadge(), expected)
				if a.playerTooltipBadge then Equal(a.playerTooltipBadge.frame.shown, expected) end
			end
		end
	end
	-- Restricted or unavailable friend information cannot cause a UI exception.
	a.db.profile.playerTooltipIdentifierMode, a.partyMembers = "friends", {}
	a.API.IsPlayerTooltipFriend = function() error("unavailable") end
	assert(a:UpdatePlayerTooltipBadge())
	a.API.IsPlayerTooltipFriend = nil
	assert(a:UpdatePlayerTooltipBadge())
	Equal(a.invalid, 0)
end)

local function PresenterFixture()
	local a = Fixture()
	a.hoverChanges, a.interestUpdates, a.interestClears, a.modelReads = 0, 0, 0, 0
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:GetPlayerTooltipPresentationParent() return self.parent end
	function a:CreatePlayerTooltipPresentationFrame(_, _, parent)
		local frame = self.frameFactory(parent, true)
		self.frames[#self.frames + 1] = frame
		return frame
	end
	function a:CreateOwnedUICleanupFrame() return self.frameFactory(nil, true) end
	function a:CreatePlayerMarkerGlow(frame) return self.frameFactory(frame, true) end
	function a:SetPlayerMarkerGlow(frame, style, size)
		self:CallOwnedUI(frame, "SetSize", size, size)
		frame.glow = style
	end
	function a:ClearPlayerDetailsInterest() self.interestClears = self.interestClears + 1 end
	function a:SetPlayerDetailsInterest(_, name, current)
		self.interestUpdates = self.interestUpdates + 1
		self.interestName, self.interestCurrent = name, current
	end
	function a:BuildPlayerTooltipModel()
		self.modelReads = self.modelReads + 1
		return self:DeepCopy(self.model)
	end
	function a:GetChatLogTooltipCursorPosition() return self.cursorX, self.cursorY end
	a.anchor = { name = a.name, frame = a.frameFactory(a.parent, true), presentationGeneration = 1 }
	a.state = { onHoverChanged = function() a.hoverChanges = a.hoverChanges + 1 end }
	a.model = {
		title = "Party member", introText = "Level 20 Mage", text = "QuestTogether 9.0.9", color = { 0.3, 0.5, 1 },
		members = {
			{ label = "Friend-Realm", color = { 0.3, 0.5, 1 }, icon = "QT", usesQT = true,
				leader = true, partyKey = "party", partySize = 2 },
			{ label = "Other-Realm", color = { 1, 0.7, 0.4 }, icon = "QT", usesQT = true,
				partyKey = "party", partySize = 2 },
		},
	}
	return a
end

QT:RegisterTest("owned player tooltip refresh reuses unchanged layout while refreshing current details interest", function()
	local a = PresenterFixture()
	local function Refresh() a:PresentPlayerTooltip(a.state, a.anchor, { name = a.name }) end
	Refresh()
	local writes, measurements = a.writes, a.measurements
	local firstCurrent, firstPresentation = a.interestCurrent, a.state.tooltipPresentation
	for _ = 1, 20 do Refresh() end
	Equal(a.writes, writes)
	Equal(a.measurements, measurements)
	Equal(a.modelReads, 21)
	Equal(a.interestUpdates, 21)
	Equal(a.hoverChanges, 1)
	assert(firstCurrent ~= a.interestCurrent and a.interestCurrent())
	Equal(a.state.tooltipPresentation, firstPresentation)
	-- New model tables are equivalent; live status, cosmetics, roster grouping,
	-- text color and wrapping width still invalidate the presentation immediately.
	for _, Change in ipairs({
		function() a.model.text = "Updated just now" end,
		function() a.model.members[2].vip = true end,
		function() a.model.members[1].partySize = 3 end,
		function() a.model.members[2].hiddenLocation = true end,
		function() a.model.members[2].color[2] = 0.9 end,
		function() a.model.maxWidth = 320 end,
	}) do
		Change()
		Refresh()
		assert(a.writes > writes and a.measurements > measurements)
		writes, measurements = a.writes, a.measurements
		Refresh()
		Equal(a.writes, writes)
		Equal(a.measurements, measurements)
	end
	Equal(a.hoverChanges, 1)
	Equal(a.invalid, 0)
end)

QT:RegisterTest("owned player tooltip repositions without relayout and notifies only real hover transitions", function()
	local a = PresenterFixture()
	a.anchor.cursorPosition = { x = 20, y = 30 }
	a:RenderPlayerTooltip(a.state, a.anchor, a.model)
	local writes, measurements = a.writes, a.measurements
	a.anchor.cursorPosition.x = 80
	a:RenderPlayerTooltip(a.state, a.anchor, a:DeepCopy(a.model))
	Equal(a.writes - writes, 2) -- clear/set the outer anchor only
	Equal(a.measurements, measurements)
	Equal(a.state.tooltip.points[1][4], 92)
	Equal(a.hoverChanges, 1)
	a.anchor.cursorPosition, a.anchor.chatLink = nil, true
	a.cursorX, a.cursorY = 90, 40
	a:RenderPlayerTooltip(a.state, a.anchor, a.model)
	Equal(a.measurements, measurements)
	Equal(a.state.tooltip.points[1][4], 102)
	local nextAnchor = { name = "Other-Realm", frame = a.frameFactory(a.parent, true) }
	a:RenderPlayerTooltip(a.state, nextAnchor, a.model)
	Equal(a.hoverChanges, 2)
	Equal(a.measurements, measurements)
	a:HidePlayerTooltipPresentation(a.state)
	a:HidePlayerTooltipPresentation(a.state)
	Equal(a.hoverChanges, 3)
	assert(not a.state.tooltipPresentation)
	a:RenderPlayerTooltip(a.state, nextAnchor, a.model)
	Equal(a.hoverChanges, 4)
	assert(a.measurements > measurements)
	measurements = a.measurements
	a.parent = a.frameFactory(nil, false)
	a:RenderPlayerTooltip(a.state, nextAnchor, a.model)
	Equal(a.state.tooltip.parent, a.parent)
	assert(a.measurements > measurements)
	Equal(a.invalid, 0)
end)

QT:RegisterTest("owned player tooltip never reuses a failed hidden or restricted presentation", function()
	local a = PresenterFixture()
	a:RenderPlayerTooltip(a.state, a.anchor, a.model)
	local measurements = a.measurements
	a.model.title, a.state.tooltipTitle.failText = "Changed title", true
	assert(not pcall(a.RenderPlayerTooltip, a, a.state, a.anchor, a.model))
	assert(not a.state.tooltipPresentation)
	a.model.title, a.state.tooltipTitle.failText = "Party member", nil
	a:RenderPlayerTooltip(a.state, a.anchor, a.model)
	assert(a.measurements > measurements)
	for _, restricted in ipairs({ "anchor", "parent", "runtime" }) do
		if restricted == "anchor" then a.anchor.frame.shown = false end
		if restricted == "parent" then a.parent.shown = false end
		if restricted == "runtime" then a.blocked = true end
		a:RenderPlayerTooltip(a.state, a.anchor, a.model)
		assert(not a.state.tooltipPresentation and not a.state.hovered and not a.state.tooltip.shown)
		measurements = a.measurements
		a.anchor.frame.shown, a.parent.shown, a.blocked = true, true, false
		a:RenderPlayerTooltip(a.state, a.anchor, a.model)
		assert(a.measurements > measurements)
	end
	Equal(a.invalid, 0)
end)

QT:RegisterTest("whole player tooltip section stays hidden on your own character through any unit alias", function()
	local a = Fixture()
	function a:GetPlayerNoteTooltipText() return "Private note: Saved note" end
	function a:IsPlayerLookingForQuestPartners() return true end
	a.db.profile.playerTooltipIdentifierMode = "all"
	assert(a:UpdatePlayerTooltipBadge())
	for _, identify in ipairs({ "token", "name", "native" }) do
		a.unit, a.name, a.selfUnit = "mouseover", "Friend-Realm", false
		if identify == "token" then a.unit = "player" end
		if identify == "name" then a.name = "Me-Realm" end
		if identify == "native" then a.selfUnit = true end
		assert(not a:UpdatePlayerTooltipBadge())
		assert(not a.playerTooltipBadge.frame.shown)
	end
	Equal(a.invalid, 0)
end)

QT:RegisterTest("hiding the player tooltip section clears its partner glow and restores all content when shown", function()
	local a = Fixture()
	a.db.profile.playerTooltipIdentifierMode = "hidden"
	assert(not a:UpdatePlayerTooltipBadge())
	Equal(#a.frames, 0)
	function a:GetPlayerNoteTooltipText() return self.note end
	a.note = "Private note: A helpful healer"
	a.qtPlayerPresenceState = { peers = {}, questPartners = { [a.name] = { receivedAt = 100, looking = true } } }
	assert(not a:UpdatePlayerTooltipBadge())
	Equal(#a.frames, 0)
	a.db.profile.playerTooltipIdentifierMode = "all"
	assert(a:UpdatePlayerTooltipBadge())
	local state = a.playerTooltipBadge
	assert(state.label.text:find("Looking for questing partners", 1, true))
	assert(state.label.text:find(a.note, 1, true))
	assert(state.label.text:find("This player is using QuestTogether", 1, true))
	assert(state.icon.qtLookingForPartners)
	a.db.profile.playerTooltipIdentifierMode = "friends"
	a.friend = true
	assert(not a:UpdatePlayerTooltipBadge())
	assert(not state.frame.shown and not state.icon.qtLookingForPartners)
	Equal(a.note, "Private note: A helpful healer")
	a.db.profile.playerTooltipIdentifierMode = "all"
	assert(a:UpdatePlayerTooltipBadge())
	assert(state.label.text:find(a.note, 1, true))
	assert(state.icon.qtLookingForPartners)
	a.note = nil
	a.qtPlayerPresenceState.questPartners[a.name].looking = false
	assert(a:UpdatePlayerTooltipBadge())
	Equal(state.label.text, "This player is using QuestTogether")
	Equal(state.label.points[1][4], 46)
	assert(not state.icon.qtLookingForPartners)
	Equal(a.invalid, 0)
end)

QT:RegisterTest("native player tooltip uses the same fresh cached display evidence without creating presence", function()
	local a = Fixture()
	a.known = false
	local location = { mask = 3, sampledAt = 95, receivedAt = 100, lifetime = 20, cached = true }
	a.playerLocationState = { peers = { [a.name] = location } }
	assert(a:UpdatePlayerTooltipBadge())
	assert(a.playerTooltipBadge.frame.shown)
	assert(a:HasQTPlayerDisplayEvidence(a.name))
	assert(not a:IsKnownQTPlayer(a.name))
	Equal(rawget(a, "qtPlayerPresenceState"), nil)
	a.now = 120
	assert(not a:UpdatePlayerTooltipBadge())
	assert(not a.playerTooltipBadge.frame.shown and not a:HasQTPlayerDisplayEvidence(a.name))
	Equal(location.sampledAt, 95)
	Equal(location.receivedAt, 100)
	Equal(location.lifetime, 20)
	Equal(a.invalid, 0)
end)

QT:RegisterTest("player tooltip badge moves above bottom-edge tooltips and wraps without widening them", function()
	local a = Fixture()
	a.host.width, a.host.bottom, a.bar.bottom, a.textHeight = 140, 35, 29, 48
	assert(a:UpdatePlayerTooltipBadge())
	local s = a.playerTooltipBadge
	Equal(s.frame.width, 140)
	assert(s.frame.height >= a.textHeight)
	Equal(s.frame.points[1][1], "BOTTOMLEFT")
	Equal(s.frame.points[1][3], "TOPLEFT")
	Equal(a.invalid, 0)
end)

QT:RegisterTest("player tooltip adds partner status only while LFG is active and hides it on expiry", function()
	local a = Fixture()
	a.qtPlayerPresenceState = { peers = {}, questPartners = { [a.name] = { receivedAt = 100, looking = true } } }
	assert(a:UpdatePlayerTooltipBadge())
	assert(a.playerTooltipBadge.icon.qtLookingForPartners)
	a.qtPlayerPresenceState.questPartners[a.name].looking = false
	assert(a:UpdatePlayerTooltipBadge())
	assert(not a.playerTooltipBadge.icon.qtLookingForPartners)
	Equal(a.playerTooltipBadge.label.text, "This player is using QuestTogether")
	-- Expiry must start from an active status; leaving looking=false would
	-- pass even if the production lease check disappeared entirely.
	a.qtPlayerPresenceState.questPartners[a.name].looking = true
	a.now = 164.9
	assert(a:UpdatePlayerTooltipBadge())
	assert(a.playerTooltipBadge.icon.qtLookingForPartners)
	a.now = 165
	assert(a:UpdatePlayerTooltipBadge())
	assert(not a.playerTooltipBadge.icon.qtLookingForPartners)
	Equal(a.playerTooltipBadge.label.text, "This player is using QuestTogether")
	Equal(a.invalid, 0)
end)

QT:RegisterTest("player tooltips never invent QT identity for friendly strangers or NPCs", function()
	local a = Fixture()
	a.known = false
	assert(not a:UpdatePlayerTooltipBadge())
	Equal(#a.frames, 0)
	a.known = true
	assert(a:UpdatePlayerTooltipBadge())
	Equal(a.playerTooltipBadge.label.text, "This player is using QuestTogether")
	assert(not a.playerTooltipBadge.icon.qtLookingForPartners)
	a.known = false
	assert(not a:UpdatePlayerTooltipBadge())
	assert(not a.playerTooltipBadge.frame.shown)
	a.known, a.player = true, false
	assert(not a:UpdatePlayerTooltipBadge())
	Equal(a.invalid, 0)
end)

QT:RegisterTest(
	"player tooltip badge clears on reuse hide ignore disable and restricted or unreadable hosts",
	function()
		local a = Fixture()
		assert(a:UpdatePlayerTooltipBadge())
		local f = a.playerTooltipBadge.frame
		for _, key in ipairs({ "blocked", "ignored", "isEnabled", "unit", "guid" }) do
			local old = a[key]
			if key == "blocked" then
				a[key] = true
			elseif key == "ignored" then
				a[key] = a.name
			elseif key == "isEnabled" then
				a[key] = false
			else
				a[key] = nil
			end
			assert(not a:UpdatePlayerTooltipBadge())
			assert(not f.shown)
			a[key] = old
			assert(a:UpdatePlayerTooltipBadge())
		end
		a.host.forbidden = true
		local reads = a.reads
		assert(not a:UpdatePlayerTooltipBadge())
		Equal(a.reads, reads)
		assert(not f.shown)
		a.host.forbidden = false
		assert(a:UpdatePlayerTooltipBadge())
		a.host.shown = false
		assert(not a:UpdatePlayerTooltipBadge())
		assert(not f.shown)
		a.host.shown = true
		assert(a:UpdatePlayerTooltipBadge())
		a.bar.forbidden = true
		assert(not a:UpdatePlayerTooltipBadge())
		assert(not f.shown)
		Equal(a.invalid, 0)
	end
)
