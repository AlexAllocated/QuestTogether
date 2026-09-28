-- Private adapters and frames only; safe in the live /qt test runner.
local QT = _G.QuestTogether
local MODERN, LEGACY = "nameplateShowFriendlyPlayers", "nameplateShowFriends"
local function Equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

local function Fixture()
	local state = { cvars = {}, reads = {}, mutations = 0, invalid = 0, creations = 0 }
	state.clock = QT:CreateTestClock(100)
	local function Frame(parent, owned)
		local frame = { parent = parent, shown = true }
		function frame:IsForbidden()
			return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
		end
		function frame:IsProtected()
			return false
		end
		local function Read(self)
			if self:IsForbidden() or state.blocked then
				state.invalid = state.invalid + 1
				error("unsafe friendly-plate read")
			end
		end
		function frame:IsShown()
			Read(self)
			return self.shown
		end
		function frame:GetEffectiveScale()
			Read(self)
			return self.scale or 1
		end
		function frame:GetNumChildren()
			Read(self)
			return #(self.children or {})
		end
		function frame:GetChildren()
			Read(self)
			self.childReads = (self.childReads or 0) + 1
			return unpack(self.children or {})
		end
		function frame:GetFrameStrata()
			return "LOW"
		end
		function frame:GetFrameLevel()
			return 1
		end
		local function Mutate(self)
			if not owned or self:IsForbidden() or state.blocked then
				state.invalid = state.invalid + 1
				error("unsafe friendly-plate mutation")
			end
			state.mutations = state.mutations + 1
		end
		function frame:Show()
			Mutate(self)
			self.shown = true
		end
		function frame:Hide()
			Mutate(self)
			self.shown = false
		end
		function frame:CreateTexture()
			Mutate(self)
			return Frame(self, true)
		end
		function frame:SetPoint(...)
			Mutate(self)
			self.point = { ... }
			assert(not self.point[2]:IsForbidden(), "forbidden anchor")
		end
		for _, method in ipairs({
			"SetFrameStrata",
			"SetFrameLevel",
			"SetTexture",
			"SetTexCoord",
			"SetSize",
			"SetAllPoints",
			"ClearAllPoints",
		}) do
			frame[method] = Mutate
		end
		return frame
	end
	local plate = Frame()
	local unitFrame = Frame(plate)
	unitFrame.unit, unitFrame.healthBar, unitFrame.name = "nameplate1", Frame(unitFrame), Frame(unitFrame)
	plate.UnitFrame = unitFrame
	state.plate, state.unitFrame = plate, unitFrame
	function state:AddBuffs(count, scale)
		unitFrame.AurasFrame = unitFrame.AurasFrame or Frame(unitFrame)
		local auras = unitFrame.AurasFrame
		auras.BuffListFrame = auras.BuffListFrame or Frame(auras)
		local buffs = auras.BuffListFrame
		buffs.children = {}
		for index = 1, count do
			buffs.children[index] = Frame(buffs)
			buffs.children[index].scale = scale
		end
		return buffs
	end
	QT.isEnabled = true
	QT.db.profile.nameplatePlayerIconEnabled = true
	QT.qtPlayerPresenceState = { peers = { ["Friend Othername"] = 100 } }
	QT.API = {
		GetCVar = function(key)
			state.reads[#state.reads + 1] = key
			if state.throw then
				error("CVar unavailable")
			end
			return state.cvars[key], state.readable
		end,
		GetTime = function()
			return state.clock:GetTime()
		end,
		Delay = function(delay, callback)
			state.clock:After(delay, callback)
		end,
		RegionalUniqueNamesEnabled = function()
			return true
		end,
		UnitFullName = function(unit)
			if unit == "player" then
				return "Me", "Self"
			end
			return "Friend", "Othername"
		end,
		UnitExists = function()
			return true
		end,
		UnitIsPlayer = function()
			return not state.npc
		end,
		UnitIsFriend = function()
			return true
		end,
		UnitGUID = function()
			return "Player-1-123"
		end,
		GetNamePlateForUnit = function()
			return not state.removed and plate or nil
		end,
		GetNamePlates = function()
			return { plate }
		end,
		IsInInstance = function()
			return false
		end,
		IsWorldMapVisible = function()
			return false
		end,
	}
	QT.IsRuntimeRestricted = function()
		return state.blocked == true
	end
	QT.IsRuntimeRestrictionTypeActive = function(_, kind)
		return state.blocked and kind == "encounter" or false
	end
	QT.CreateNameplateQuestIconFrame = function(_, parent)
		state.creations = state.creations + 1
		return Frame(parent, true)
	end
	return state
end

QT:RegisterTest("friendly player visibility prefers the modern CVar and falls back only when absent", function()
	for _, case in ipairs({
		{ modern = "1", legacy = "0", expected = true, reads = 1 },
		{ modern = "0", legacy = "1", expected = false, reads = 1 },
		{ legacy = "1", expected = true, reads = 2 },
		{ legacy = "0", expected = false, reads = 2 },
		{ reads = 2 },
	}) do
		local state = Fixture()
		state.cvars[MODERN], state.cvars[LEGACY] = case.modern, case.legacy
		Equal(QT:GetFriendlyPlayerNameplateVisibility(), case.expected)
		Equal(#state.reads, case.reads)
		Equal(state.reads[1], MODERN)
		if case.reads == 2 then
			Equal(state.reads[2], LEGACY)
		end
	end
end)

QT:RegisterTest(
	"friendly player visibility rejects invalid or unreadable modern values without legacy fallback",
	function()
		for _, value in ipairs({ "", "true", "2", 1, true, {} }) do
			local state = Fixture()
			state.cvars[MODERN], state.cvars[LEGACY] = value, "1"
			Equal(QT:GetFriendlyPlayerNameplateVisibility(), nil)
			Equal(#state.reads, 1)
		end
		for _, boundary in ipairs({ "unreadable", "error", "adapter_failure", "missing_api" }) do
			local state = Fixture()
			state.cvars[LEGACY] = "1"
			if boundary == "unreadable" then
				local inaccessible = {}
				state.cvars[MODERN] = inaccessible
				local canAccess = QT.CanAccessValue
				QT.CanAccessValue = function(self, value)
					return value ~= inaccessible and canAccess(self, value)
				end
			elseif boundary == "error" then
				state.throw = true
			elseif boundary == "adapter_failure" then
				state.readable = false
			else
				QT.API.GetCVar = nil
			end
			Equal(QT:GetFriendlyPlayerNameplateVisibility(), nil)
			Equal(#state.reads, boundary == "missing_api" and 0 or 1)
		end
	end
)

QT:RegisterTest("modern friendly visibility renders the logo and CVar events update the actual plate", function()
	local state = Fixture()
	state.cvars[MODERN] = "1"
	QT:HandleNameplateEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
	local icon = QT.nameplateIconByUnitFrame[state.unitFrame]
	assert(icon and icon.shown)
	Equal(icon.qtIconKind, "player")
	Equal(state.creations, 1)
	state.cvars[MODERN], state.cvars[LEGACY] = "0", "1"
	QT:HandleNameplateEvent("CVAR_UPDATE", MODERN)
	state.clock:Advance(0.05)
	Equal(icon.shown, false)
	state.cvars[MODERN] = "1"
	QT:HandleNameplateEvent("CVAR_UPDATE", MODERN)
	state.clock:Advance(0.05)
	assert(icon.shown)
	Equal(state.creations, 1)
	Equal(state.invalid, 0)
end)

QT:RegisterTest("modern visibility does not bypass forbidden frames or restricted presentation", function()
	for _, boundary in ipairs({ "forbidden", "restricted" }) do
		local state = Fixture()
		state.cvars[MODERN] = "1"
		if boundary == "forbidden" then
			state.plate.forbidden = true
		else
			state.blocked = true
		end
		QT:RefreshNameplateIcon(state.plate)
		Equal(state.creations, 0)
		Equal(#state.reads, 0)
		Equal(state.invalid, 0)
	end
end)

local function ShowLogo(state)
	state.cvars[MODERN] = "1"
	QT:RefreshNameplateIcon(state.plate)
	local icon = QT.nameplateIconByUnitFrame[state.unitFrame]
	assert(icon and icon.shown)
	return icon
end

QT:RegisterTest("player logo moves outside visible buffs after layout and returns when they disappear", function()
	local state = Fixture()
	local buffs = state:AddBuffs(0)
	local icon = ShowLogo(state)
	Equal(icon.point[2], state.unitFrame.healthBar)
	Equal(icon.point[4], -4)
	local reads, mutations, timers = buffs.childReads, state.mutations, #state.clock.timers
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
	Equal(#state.clock.timers, timers + 1)
	Equal(state.mutations, mutations)
	Equal(buffs.childReads, reads)
	-- Simulate Blizzard's later event handler updating the pool and layout.
	state:AddBuffs(1)
	state.clock:Advance(0)
	Equal(icon.point[1], "RIGHT")
	Equal(icon.point[2], buffs)
	Equal(icon.point[3], "LEFT")
	Equal(icon.point[4], -4)
	local released = buffs.children[1]
	released.forbidden = true
	state:AddBuffs(2, 1.5)
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
	state.clock:Advance(0)
	Equal(icon.point[2], buffs) -- Never anchor to a pooled child.
	Equal(icon.point[4], -5)
	state:AddBuffs(0)
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
	state.clock:Advance(0)
	Equal(icon.point[2], state.unitFrame.healthBar)
	Equal(icon.point[4], -4)
	Equal(state.creations, 1)
	Equal(state.invalid, 0)
end)

QT:RegisterTest("hidden buff containers and hidden pooled children do not displace player logos", function()
	for _, hidden in ipairs({ "auras", "list", "child" }) do
		local state = Fixture()
		local buffs = state:AddBuffs(1)
		local hiddenFrame = hidden == "auras" and state.unitFrame.AurasFrame
			or hidden == "list" and buffs
			or buffs.children[1]
		hiddenFrame.shown = false
		local icon = ShowLogo(state)
		Equal(icon.point[2], state.unitFrame.healthBar)
		if hidden ~= "child" then
			Equal(buffs.childReads, nil)
		end
		hiddenFrame.shown = true
		QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
		state.clock:Advance(0)
		Equal(icon.point[2], buffs)
		Equal(state.invalid, 0)
	end
end)

QT:RegisterTest("buff layout rejects forbidden frames and unreadable values without unsafe reads", function()
	for _, boundary in ipairs({ "auras", "list", "child", "shown", "count", "handle", "method", "error", "excess" }) do
		local state = Fixture()
		local buffs = state:AddBuffs(1)
		local inaccessible = {}
		local canAccess = QT.CanAccessValue
		QT.CanAccessValue = function(self, value)
			return value ~= inaccessible and canAccess(self, value)
		end
		if boundary == "auras" then
			state.unitFrame.AurasFrame.forbidden = true
		elseif boundary == "list" then
			buffs.forbidden = true
		elseif boundary == "child" then
			buffs.children[1].forbidden = true
		elseif boundary == "shown" then
			buffs.children[1].shown = inaccessible
		elseif boundary == "count" then
			buffs.GetNumChildren = function()
				return inaccessible
			end
		elseif boundary == "handle" then
			buffs.children[1] = inaccessible
		elseif boundary == "method" then
			buffs.GetChildren = inaccessible
		elseif boundary == "error" then
			buffs.GetChildren = function()
				error("layout unavailable")
			end
		else
			buffs.GetNumChildren = function()
				return 1000
			end
		end
		local icon = ShowLogo(state)
		Equal(icon.point[2], state.unitFrame.healthBar)
		if boundary == "count" or boundary == "method" or boundary == "excess" then
			Equal(buffs.childReads, nil)
		end
		Equal(state.invalid, 0)
	end
end)

QT:RegisterTest("unreadable aura scale keeps a safe fixed margin without doing secret arithmetic", function()
	local state = Fixture()
	local buffs = state:AddBuffs(1)
	local inaccessible = {}
	local canAccess = QT.CanAccessValue
	QT.CanAccessValue = function(self, value)
		return value ~= inaccessible and canAccess(self, value)
	end
	buffs.children[1].scale = inaccessible
	local icon = ShowLogo(state)
	Equal(icon.point[2], buffs)
	Equal(icon.point[4], -4)
	Equal(state.invalid, 0)
end)

QT:RegisterTest("aura layout updates wait through restrictions and cancel when a plate is removed", function()
	local state = Fixture()
	local buffs = state:AddBuffs(0)
	local icon = ShowLogo(state)
	state:AddBuffs(1)
	state.blocked = true
	local mutations = state.mutations
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
	state.clock:Advance(0)
	Equal(state.mutations, mutations)
	Equal(buffs.childReads, nil)
	state.blocked = false
	QT:FlushDeferredWork("aura restrictions ended")
	state.clock:Advance(0)
	Equal(icon.point[2], buffs)
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
	state.removed = true
	QT:HandleNameplateEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	mutations = state.mutations
	state.clock:Advance(0)
	Equal(state.mutations, mutations)
	Equal(icon.shown, false)
	Equal(state.invalid, 0)
end)

QT:RegisterTest("aura events never schedule quest scans for NPC or unrelated unit tokens", function()
	local state = Fixture()
	ShowLogo(state)
	state.npc = true -- A recycled token can precede the normal removal event.
	local timers = #state.clock.timers
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate2")
	QT:HandleNameplateEvent("UNIT_AURA", "target")
	QT:HandleNameplateEvent("UNIT_AURA", {})
	Equal(#state.clock.timers, timers)
	state.npc = false
	QT.db.profile.nameplatePlayerIconStyle = "right"
	QT:HandleNameplateEvent("UNIT_AURA", "nameplate1")
	Equal(#state.clock.timers, timers)
	Equal(state.invalid, 0)
end)
