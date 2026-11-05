-- Private native observations and QT-owned regions only; safe for /qt test.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local function Fixture()
	local a = setmetatable({
		isEnabled = true, now = 100, ignored = {}, nativeRegions = {},
		partyMemberOrder = { "You Realm", "Mage Realm", "Rogue Realm", "Druid Realm", "Warrior Realm" },
		partyMembers = {}, partyNavigationState = { peers = {}, seen = {} },
		options = { questTrackerMode = "hidden", sharePartyFocus = false, lightMode = true },
	}, { __index = QT })
	local classes = { "PRIEST", "MAGE", "ROGUE", "DRUID", "WARRIOR" }
	local colors = { MAGE = "|cff33aaff", ROGUE = "|cffffdd33", DRUID = "|cffff6633", WARRIOR = "|cffaa7755" }
	for index, name in ipairs(a.partyMemberOrder) do
		a.partyMembers[name] = { classFile = classes[index] }
		if index > 1 then a.partyNavigationState.peers[name] = { questID = index < 4 and 41 or 42, at = a.now } end
	end
	a.API = {
		GetTime = function() return a.now end,
		IsInRaid = function() return a.raid == true end,
		IsInParty = function() return a.solo ~= true end,
		IsInInstanceGroup = function() return false end,
	}
	function a:GetPlayerFullName() return "You Realm" end
	function a:NormalizeMemberName(name) return name end
	function a:IsIgnoredPlayerName(name) return self.ignored[name] == true end
	function a:GetOption(key) return self.options[key] end
	function a:GetClassColorCode(classFile) return colors[classFile] or "|cffffffff" end
	function a:IsRuntimeRestricted() return self.restricted == true end
	function a:IsWorkBlocked() return self.restricted == true end
	-- A private sentinel models the native accessibility boundary without
	-- replacing global secret-value APIs used by the running addon.
	a.secretCoordinate = {}
	function a:CanAccessValue(value)
		return value ~= self.secretCoordinate and QT.CanAccessValue(self, value)
	end
	function a:GetOwnedUIParent() return self.root end
	function a:CreateOwnedWindowFrame(kind, _, parent, template)
		local frame = self:ApplyTestUITemplate(self:CreateTestUIRegion(self, parent, kind), template)
		local enableMouse = frame.EnableMouse
		function frame:EnableMouse(value)
			self.mouseEnabled = value
			return enableMouse(self, value)
		end
		return frame
	end
	a.root = a:CreateTestUIRegion(a)
	a.root:SetSize(1200, 900)
	a.root:SetScale(0.8)
	local function Native(parent, kind)
		local region = a:CreateTestUIRegion(a, parent, kind)
		a.nativeRegions[#a.nativeRegions + 1] = region
		return region
	end
	a.module = Native(a.root)
	a.module.blocks = {}
	function a.module:GetExistingBlock(id) return self.blocks[id] end
	function a:GetPartyQuestFocusTrackerModules() return { self.module } end
	function a:Block(id, top)
		local block = Native(self.module)
		block.id, block.parentModule, block.used = id, self.module, true
		function block:GetFrameStrata() return "MEDIUM" end
		local label = Native(block, "FontString")
		block.HeaderText = label
		label.left, label.top = 900, top
		label:SetSize(200, 16)
		self.module.blocks[id] = block
		return block
	end
	a.first, a.second = a:Block(41, 700), a:Block(42, 600)
	function a:FreezeNativeWrites()
		self.nativeWrites = {}
		for _, region in ipairs(self.nativeRegions) do self.nativeWrites[region] = region.writes end
	end
	function a:AssertNativeReadOnly()
		for region, writes in pairs(self.nativeWrites) do Equal(region.writes, writes) end
		Equal(self.invalidCalls or 0, 0)
	end
	a:FreezeNativeWrites()
	return a
end
local function Visible(a)
	local result = {}
	for index = 1, 4 do
		local pin = a.partyFocusIndicatorState and a.partyFocusIndicatorState.pins[index]
		if pin and pin.frame:IsShown() then result[#result + 1] = pin end
	end
	return result
end

QT:RegisterTest("native tracker party focus indicators use shared focus independently of following and POT visibility", function()
	local a = Fixture()
	a.partyNavigationState.peers["Warrior Realm"].questID = 0
	local rows = a:GetPartyQuestFocusRows()
	Equal(#rows, 3)
	Equal(rows[1].name, "Mage Realm")
	Equal(rows[1].questID, 41)
	Equal(rows[1].classFile, "MAGE")
	Equal(rows[2].name, "Rogue Realm")
	Equal(rows[2].questID, 41)
	Equal(rows[3].questID, 42)
	Equal(a.partyNavigationState.following, nil)
	Equal(rawget(a, "partyQuestCompareSession"), nil)
	a.partyNavigationState.following = "Druid Realm"
	Equal(#a:GetPartyQuestFocusRows(), 3)
	-- Freshness, consent and membership must come from the navigation query,
	-- even before its periodic pruning has removed the stored records.
	a.partyNavigationState.peers["Mage Realm"].at = a.now - 90
	a.partyNavigationState.peers["Rogue Realm"].questID = -1
	a.ignored["Druid Realm"] = true
	Equal(#a:GetPartyQuestFocusRows(), 0)
	a.partyNavigationState.peers["Mage Realm"].at = a.now
	a.partyMembers["Mage Realm"] = nil
	Equal(#a:GetPartyQuestFocusRows(), 0)
	a.partyMembers["Mage Realm"] = { classFile = "MAGE" }
	Equal(#a:GetPartyQuestFocusRows(), 1)
	a.raid = true
	Equal(#a:GetPartyQuestFocusRows(), 0)
end)

QT:RegisterTest("native tracker focus dots preserve class colors and follow native geometry without modifying it", function()
	local a = Fixture()
	for _, peer in pairs(a.partyNavigationState.peers) do peer.questID = 41 end
	a:UpdatePartyQuestFocusIndicators()
	local pins = Visible(a)
	Equal(#pins, 4)
	local ys = {}
	for _, pin in ipairs(pins) do
		Equal(pin.frame:GetParent(), a.root)
		Equal(pin.frame.mouseEnabled, false)
		Equal(pin.questID, 41)
		local color = pin.dot.textureColor or pin.dot.vertexColor
		local r, g, b = a:GetWindowClassColor(a:GetGroupedSenderClassFile(pin.name), 1)
		Equal(color[1], r)
		Equal(color[2], g)
		Equal(color[3], b)
		local point = pin.frame.points[1]
		assert(point and not ys[point[5]], "members focusing the same quest need distinct marker positions")
		ys[point[5]] = true
	end
	local pin = pins[1]
	local previousX, previousScale = pin.frame.points[1][4], pin.frame:GetScale()
	a.first.HeaderText.left = 650
	a.first.HeaderText.scale = 0.75
	a:RefreshPartyQuestFocusIndicatorGeometry()
	assert(pin.frame.points[1][4] ~= previousX, "marker must follow a moved native header")
	assert(pin.frame:GetScale() ~= previousScale, "marker scale must follow the header")
	Equal(#Visible(a), 4)
	a:AssertNativeReadOnly()
end)

QT:RegisterTest("native tracker focus dots reject recycled collapsed sliding and forbidden quest blocks", function()
	local a = Fixture()
	a:UpdatePartyQuestFocusIndicators()
	Equal(#Visible(a), 4)
	local first = a.first
	for _, condition in ipairs({ "recycled", "wrongModule", "unused", "sliding", "unreadableSlide", "secretCoordinate", "hiddenHeader", "collapsed", "forbidden" }) do
		setmetatable(first, nil)
		first.id, first.parentModule, first.used, first.slideInfo = 41, a.module, true, nil
		first.shown, first.forbidden, first.HeaderText.shown = true, false, true
		first.HeaderText.left = 900
		if condition == "recycled" then first.id = 999
		elseif condition == "wrongModule" then first.parentModule = a.second
		elseif condition == "unused" then first.used = false
		elseif condition == "sliding" then first.slideInfo = {}
		elseif condition == "unreadableSlide" then
			setmetatable(first, { __index = function(_, key)
				if key == "slideInfo" then error("native field is unreadable") end
			end })
		elseif condition == "secretCoordinate" then first.HeaderText.left = a.secretCoordinate
		elseif condition == "hiddenHeader" then first.HeaderText.shown = false
		elseif condition == "collapsed" then first.shown = false
		elseif condition == "forbidden" then first.forbidden = true end
		a:RefreshPartyQuestFocusIndicatorGeometry()
		local pins = Visible(a)
		Equal(#pins, 2)
		for _, pin in ipairs(pins) do Equal(pin.questID, 42) end
	end
	setmetatable(first, nil)
	first.forbidden = false
	a.module.blocks[41] = nil
	a:RefreshPartyQuestFocusIndicatorGeometry()
	Equal(#Visible(a), 2)
	a.module.blocks[41] = a:Block(41, 680)
	a:FreezeNativeWrites()
	a:RefreshPartyQuestFocusIndicatorGeometry()
	Equal(#Visible(a), 4)
	a:AssertNativeReadOnly()
end)

QT:RegisterTest("native tracker focus indicators retire immediately for restricted or ended lifetimes", function()
	for _, condition in ipairs({ "restricted", "disabled", "worldExit", "expired", "partyChange", "reset" }) do
		local a = Fixture()
		-- The first roster members' quest is not tracked, so the initially
		-- allocated visible pins may occupy only the later pool positions.
		a.module.blocks[41] = nil
		a:UpdatePartyQuestFocusIndicators()
		Equal(#Visible(a), 2)
		if condition == "restricted" then a.restricted = true
		elseif condition == "disabled" then a.isEnabled = false
		elseif condition == "worldExit" then a.isLoggingOut = true
		elseif condition == "expired" then a.now = a.now + 90
		elseif condition == "partyChange" then a.partyMembers = { ["You Realm"] = { classFile = "PRIEST" } }
		else a:ResetPartyQuestFocusIndicators() end
		a:RefreshPartyQuestFocusIndicatorGeometry()
		Equal(#Visible(a), 0)
		-- An old geometry call must not restore a retired presentation.
		a:RefreshPartyQuestFocusIndicatorGeometry()
		Equal(#Visible(a), 0)
		a:AssertNativeReadOnly()
	end
end)
