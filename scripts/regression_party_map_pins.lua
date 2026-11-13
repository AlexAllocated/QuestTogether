-- Private native adapters and QT-owned frames only. No live map/global writes.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local MEDIA = "Interface\\AddOns\\QuestTogether\\Media\\"
local function Row(unit, name, class, subgroup)
	return { unit = unit, name = name, classFile = class, inSubgroup = subgroup ~= false, nativeParty = true }
end
local function Fixture()
	local a = setmetatable({ isEnabled = true, options = { showPlayerLocations = true }, mapShown = true,
		rows = { Row("party1", "VIP-Realm", "MAGE"), Row("party2", "Ordinary-Realm", "ROGUE") },
		vip = { ["VIP-Realm"] = true }, developer = {}, visibility = {}, errors = {}, counts = {}, ignored = {},
	}, { __index = QT })
	a.parent = a:CreateTestUIRegion(a)
	a.parent:SetSize(1000, 800)
	a.context = { pin = {}, parent = a.parent, mapID = 12, canvasScale = 2, frameLevel = 10,
		showParty = true, showRaid = true, surface = { parent = a.parent } }
	a.liveMapID, a.nativeContextVisible = 12, true
	a.API = { GetTime = function() return 100 end }
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:IsWorkBlocked() return self.blocked == true end
	function a:GetOption(key) return self.options[key] end
	function a:IsQuestTogetherMapDataShown(surface) return surface == "map" and self.mapShown end
	function a:GetPartyMapRoster() self.rosterReads = (self.rosterReads or 0) + 1; return self.rows end
	function a:GetPartyMapNativeContext() return self.context end
	function a:IsPartyMapNativeContextCurrent(context)
		return self.nativeContextVisible and self.context and context.pin == self.context.pin
			and context.mapID == self.liveMapID
	end
	function a:IsVerifiedDeveloper(name) return self.developer[name] == true end
	function a:IsVerifiedVIP(name) return self.vip[name] == true end
	function a:GetClassColorCode(class) return class == "MAGE" and "|cff33aaff" or "|cffffee44" end
	function a:IsIgnoredPlayerName(name) return self.ignored[name] == true end
	function a:IsPartyMapRowCurrent(row)
		for _, current in ipairs(self.rows or {}) do
			if current.unit == row.unit then return current.name == row.name and not self.blocked end
		end
		return false
	end
	function a:RecordDiagnosticError(kind, message) self.errors[#self.errors + 1] = { kind, message } end
	function a:CreateOwnedUICleanupFrame() return self:CreateTestUIRegion({}) end
	function a:CreateLocationPinFrame(kind, _, parent)
		Equal(kind, "UnitPositionFrame")
		local frame = self:CreateTestUIRegion(self, parent, kind)
		local function Count(method)
			frame:Check(); a.counts[method] = (a.counts[method] or 0) + 1
			if a.failMethod == method then error("private native renderer failure") end
		end
		function frame:SetUiMapID(mapID) Count("SetUiMapID"); self.mapID = mapID end
		function frame:ClearUnits() Count("ClearUnits"); self.units = {}; self.finalized = false end
		function frame:AddUnit(unit, texture, width, height, r, g, b, alpha)
			Count("AddUnit")
			self.units[unit] = { texture = texture, width = width, height = height, color = { r, g, b, alpha } }
		end
		function frame:FinalizeUnits() Count("FinalizeUnits"); self.finalized = true end
		return frame
	end
	function a:SetPartyMapNativeVisibility(context, party, raid)
		local suppressing = party == false and raid == false
		if suppressing then
			local frame = self.partyMapPinState and self.partyMapPinState.frame
			assert(frame and frame.finalized and frame:IsShown(), "native markers were hidden before replacements were ready")
		end
		self.visibility[#self.visibility + 1] = { context = context, party = party, raid = raid,
			replacementShown = self.partyMapPinState and self.partyMapPinState.frame
				and self.partyMapPinState.frame:IsShown() }
		if self.failRestore and not suppressing or self.failSuppress and suppressing then return false end
		self.nativeParty, self.nativeRaid = party, raid
		return true
	end
	function a:HidePlayerTooltipPresentation(tip) tip.hovered = nil; self.lastTip = nil end
	function a:PresentPlayerTooltip(tip, anchor, row) tip.hovered = anchor; self.lastTip = row end
	function a:GetPartyMapMouseOverUnits() return self.mouseUnits end
	function a:GetPlayerTooltipPresentationParent() return self.parent end
	function a:GetChatLogTooltipCursorPosition() return 300, 400 end
	for _, method in ipairs({ "Publish", "Emit", "Request", "Respond" }) do
		a[method] = function() error("native party presentation cannot send addon traffic") end
	end
	return a
end

QT:RegisterTest("native party world map markers keep authenticated cosmetics and include non-QT members without coordinates", function()
	local a = Fixture()
	a.rows[#a.rows + 1] = Row("party3", "Developer-Realm", "MAGE")
	a.developer["Developer-Realm"], a.vip["Developer-Realm"] = true, true
	assert(a:RefreshPartyMapPins())
	local frame = a.partyMapPinState.frame
	Equal(frame.units.party1.texture, MEDIA .. "VIPStar")
	Equal(frame.units.party3.texture, MEDIA .. "DeveloperGear")
	Equal(frame.units.party2.texture, "WhiteCircle-RaidBlips")
	Equal(frame.units.party1.width, 9)
	Equal(frame.units.party2.width, 6)
	Equal(frame.units.party1.color[1], 0x33 / 255)
	Equal(a.counts.FinalizeUnits, 1)
	Equal(a.nativeParty, false); Equal(a.nativeRaid, false)
	Equal(rawget(a, "playerLocationState"), nil)
	Equal(rawget(a, "locationPinState"), nil)
end)

QT:RegisterTest("native party renderer rebuilds only changed styles identities map or scale", function()
	local a = Fixture()
	assert(a:RefreshPartyMapPins())
	for _ = 1, 20 do assert(a:RefreshPartyMapPins()) end
	Equal(a.counts.ClearUnits, 1); Equal(a.counts.AddUnit, 2)
	a.rows[1].level = 61
	assert(a:RefreshPartyMapPins())
	Equal(a.counts.ClearUnits, 1)
	-- A recycled unit may still be the same native token, but cannot inherit a star.
	a.rows[1] = Row("party1", "Replacement-Realm", "MAGE")
	assert(a:RefreshPartyMapPins())
	Equal(a.counts.ClearUnits, 2)
	Equal(a.partyMapPinState.frame.units.party1.texture, "WhiteCircle-RaidBlips")
	a.vip["Replacement-Realm"] = true
	assert(a:RefreshPartyMapPins())
	Equal(a.counts.ClearUnits, 3)
	a.context.mapID = 13
	assert(a:RefreshPartyMapPins())
	Equal(a.counts.ClearUnits, 4)
	a.context.canvasScale = 1
	assert(a:RefreshPartyMapPins())
	Equal(a.counts.ClearUnits, 5)
	Equal(a.partyMapPinState.frame.units.party1.width, 18)
end)

QT:RegisterTest("native party map takeover honors party and raid visibility independently", function()
	local a = Fixture()
	a.rows[2].inSubgroup = false
	a.context.showRaid = false
	assert(a:RefreshPartyMapPins())
	Equal(a.partyMapPinState.frame.units.party2, nil)
	a:HidePartyMapPins()
	Equal(a.nativeParty, true); Equal(a.nativeRaid, false)
	a.context.showParty, a.context.showRaid = false, true
	assert(a:RefreshPartyMapPins())
	Equal(a.partyMapPinState.frame.units.party1, nil)
	assert(a.partyMapPinState.frame.units.party2)
	a:HidePartyMapPins()
	Equal(a.nativeParty, false); Equal(a.nativeRaid, true)
end)

QT:RegisterTest("native party markers restore on disable hidden maps missing data and restrictions", function()
	for _, change in ipairs({
		function(a) a.isEnabled = false end,
		function(a) a.isLoggingOut = true end,
		function(a) a.mapShown = false end,
		function(a) a.options.showPlayerLocations = false end,
		function(a) a.rows = nil end,
		function(a) a.rows = {} end,
		function(a) a.context = nil end,
		function(a) a.blocked = true end,
	}) do
		local a = Fixture(); assert(a:RefreshPartyMapPins()); change(a)
		assert(not a:RefreshPartyMapPins())
		Equal(a.nativeParty, true); Equal(a.nativeRaid, true)
		assert(not a.partyMapPinState.frame:IsShown())
		Equal(a.partyMapPinState.context, nil)
		Equal(#a.errors, 0)
	end
end)

QT:RegisterTest("native party renderer failures restore native markers and report only once", function()
	for _, method in ipairs({ "AddUnit", "FinalizeUnits", "suppression" }) do
		local a = Fixture()
		if method == "suppression" then a.failSuppress = true else a.failMethod = method end
		assert(not a:RefreshPartyMapPins())
		assert(a.partyMapPinState.failed)
		assert(not a.partyMapPinState.frame:IsShown())
		Equal(#a.errors, 1)
		local writes = a.counts.AddUnit
		for _ = 1, 5 do assert(not a:RefreshPartyMapPins()) end
		Equal(a.counts.AddUnit, writes)
		Equal(#a.errors, 1)
		if method == "suppression" then Equal(a.nativeParty, true); Equal(a.nativeRaid, true) end
	end
end)

QT:RegisterTest("native party map hover validates current unit identity before using reused markers", function()
	local a = Fixture()
	assert(a:RefreshPartyMapPins())
	a.mouseUnits = { "party1" }
	a:UpdatePartyMapHover()
	Equal(a.lastTip.name, "VIP-Realm")
	local old = a.partyMapPinState.anchor
	a.rows[1] = Row("party1", "Replacement-Realm", "ROGUE")
	a:UpdatePartyMapHover()
	Equal(a.lastTip, nil)
	assert(not old.isCurrent())
	assert(a:RefreshPartyMapPins())
	a:UpdatePartyMapHover()
	Equal(a.lastTip.name, "Replacement-Realm")
	assert(not old.isCurrent())
	a.ignored["Replacement-Realm"] = true
	a:UpdatePartyMapHover()
	Equal(a.lastTip, nil)
end)

QT:RegisterTest("native party map retires stale artwork while retaining failed restoration for retry", function()
	local a = Fixture()
	assert(a:RefreshPartyMapPins())
	local state, context = a.partyMapPinState, a.context
	a.mouseUnits = { "party1" }; a:UpdatePartyMapHover()
	local anchor = state.anchor
	a.failRestore, a.mapShown = true, false
	a.rows[1] = Row("party1", "Replacement-Realm", "ROGUE")
	a:RefreshPartyMapPins()
	Equal(state.context, context)
	assert(a.visibility[#a.visibility].replacementShown, "native restoration must be attempted before retiring owned artwork")
	assert(not state.frame:IsShown(), "failed restoration cannot leave a stale VIP texture on a recycled party token")
	assert(state.retiring)
	assert(not anchor.isCurrent())
	Equal(state.rows, nil)
	Equal(a.lastTip, nil)
	a.failRestore = false
	a:FlushOwnedUICleanup()
	Equal(state.context, nil)
	assert(not state.frame:IsShown())
	Equal(a.nativeParty, true); Equal(a.nativeRaid, true)
end)

QT:RegisterTest("native party map frame retirement clears changed maps before paced roster refresh", function()
	for _, change in ipairs({
		function(a) a.liveMapID = 13 end,
		function(a) a.mapShown = false end,
		function(a) a.nativeContextVisible = false end,
	}) do
		local a = Fixture()
		assert(a:RefreshPartyMapPins())
		a.mouseUnits = { "party1" }; a:UpdatePartyMapHover()
		local state, anchor, reads = a.partyMapPinState, a.partyMapPinState.anchor, a.rosterReads
		change(a)
		a:RetireUnavailablePartyMapPins()
		assert(not state.frame:IsShown())
		Equal(state.context, nil)
		Equal(a.lastTip, nil)
		Equal(a.rosterReads, reads)
		Equal(a.counts.ClearUnits, 1)
		Equal(a.nativeParty, true); Equal(a.nativeRaid, true)
		assert(not anchor.isCurrent())
	end
end)

QT:RegisterTest("native party map retirement restores the latest immutable native visibility policy", function()
	local a = Fixture()
	assert(a:RefreshPartyMapPins())
	local original = a.context
	local current = {}
	for key, value in pairs(original) do current[key] = value end
	current.showParty, current.showRaid = false, false
	a.context = current
	assert(not a:RefreshPartyMapPins())
	local restoration = a.visibility[#a.visibility]
	Equal(restoration.context, current)
	Equal(restoration.party, false); Equal(restoration.raid, false)
	Equal(original.showParty, true); Equal(original.showRaid, true)
	assert(not a.partyMapPinState.frame:IsShown())
	Equal(a.partyMapPinState.context, nil)
end)

QT:RegisterTest("native party map hidden sessions cannot revive a stale VIP tooltip", function()
	local a = Fixture()
	assert(a:RefreshPartyMapPins())
	a.mouseUnits = { "party1" }
	a:UpdatePartyMapHover()
	local old = a.partyMapPinState.anchor
	assert(old and old.isCurrent())
	a.mapShown = false
	a:UpdatePartyMapHover()
	assert(not old.isCurrent())
	Equal(a.lastTip, nil)
	a.vip["VIP-Realm"] = nil
	for _ = 1, 3 do a:UpdatePartyMapHover() end
	Equal(a.lastTip, nil)
	a.mapShown = true
	assert(a:RefreshPartyMapPins())
	assert(not old.isCurrent(), "a retired presentation lifetime must not become current when the map reopens")
	Equal(a.partyMapPinState.frame.units.party1.texture, "WhiteCircle-RaidBlips")
	a:UpdatePartyMapHover()
	assert(a.partyMapPinState.anchor ~= old)
end)

QT:RegisterTest("native party map hover failures retire hover work and record one diagnostic", function()
	local a = Fixture()
	assert(a:RefreshPartyMapPins())
	a.mouseUnits = { "party1" }
	function a:PresentPlayerTooltip()
		self.hoverAttempts = (self.hoverAttempts or 0) + 1
		error("private tooltip failure")
	end
	for _ = 1, 5 do a:UpdatePartyMapHover() end
	Equal(a.hoverAttempts, 1)
	Equal(#a.errors, 1)
	Equal(a.errors[1][1], "party_map_hover")
	assert(a.partyMapPinState.hoverFailed)
	assert(a.partyMapPinState.frame:IsShown())
end)

QT:RegisterTest("native party non-QT tooltip renders an empty body without requesting addon details", function()
	local a = Fixture()
	a.PresentPlayerTooltip, a.HidePlayerTooltipPresentation = nil, nil
	a.wireCalls, a.interestCalls, a.clearInterestCalls = 0, 0, 0
	function a:GetPlayerDetailsTooltipRow() error("native party identity must use the current unit roster") end
	function a:GetPlayerPartyVisualInfo() return { size = 2, grouped = true } end
	function a:GetPlayerTooltipIdentity(row) return row.raceName, row.classFile end
	function a:GetPlayerPhaseStatus() return nil end
	function a:SupportsWarMode() return false end
	function a:IsPlayerLookingForQuestPartners() return false end
	function a:GetPlayerAddonVersion() return nil end
	function a:GetPlayerNoteTooltipText() return nil end
	function a:HasQTPlayerDisplayEvidence() return false end
	function a:IsPlayerLocationHiddenForDeveloper() return false end
	function a:SetPlayerDetailsInterest() self.interestCalls = self.interestCalls + 1 end
	function a:ClearPlayerDetailsInterest() self.clearInterestCalls = self.clearInterestCalls + 1 end
	for _, method in ipairs({ "Publish", "Emit", "Request", "Respond" }) do
		a[method] = function(self) self.wireCalls = self.wireCalls + 1 end
	end
	function a:CreatePlayerTooltipPresentationFrame(kind, _, parent)
		local frame = self:CreateTestUIRegion(self, parent, kind)
		local create = frame.CreateFontString
		function frame:CreateFontString(...)
			local label = create(self, ...)
			local measure = label.GetStringHeight
			function label:GetStringHeight()
				-- Native empty FontStrings can measure zero, unlike the default fake.
				if self:GetText() == "" then return 0 end
				return measure(self)
			end
			return label
		end
		return frame
	end
	local row = a.rows[2]
	row.level, row.raceName = 42, "Human"
	local model = a:BuildPlayerTooltipModel(row)
	Equal(model.text, "")
	assert(model.title:find(row.name, 1, true))
	assert(model.introText:find("42", 1, true))
	assert(a:RefreshPartyMapPins())
	a.mouseUnits = { row.unit }
	a:UpdatePartyMapHover()
	local tip = a.partyMapPinState.tip
	assert(tip.tooltip and tip.tooltip:IsShown(), "zero body height must not suppress the native party tooltip")
	Equal(tip.tooltipLabel:GetText(), "")
	assert(tip.tooltipTitle:GetText():find(row.name, 1, true))
	a:UpdatePartyMapHover()
	Equal(a.wireCalls, 0)
	Equal(a.interestCalls, 0)
	Equal(a.clearInterestCalls, 4)
	Equal(#a.errors, 0)
end)

_G.QuestTogether:RecordTestModule("scripts/regression_party_map_pins.lua")
