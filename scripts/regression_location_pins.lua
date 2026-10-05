-- Private frames and adapters only: safe in the live /qt test command.
local QuestTogether = _G.QuestTogether
local activeFixtures
local function Register(name, callback, options)
	QuestTogether:RegisterTest(name, function()
		activeFixtures = {}
		local ok, err = pcall(callback)
		local fixtures = activeFixtures
		activeFixtures = nil
		for _, fixture in ipairs(fixtures) do
			assert((fixture.invalidCalls or 0) == 0, "a swallowed error hid an unsafe location UI call")
		end
		if not ok then
			error(err, 0)
		end
	end, options)
end
local function Equal(a, b)
	assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function Near(a, b)
	assert(type(a) == "number" and math.abs(a - b) < 0.00001)
end

local function Frame(addon, parent, kind)
	local frame = { parent = parent, kind = kind, shown = true, points = {}, scripts = {}, writes = 0, hides = 0 }
	function frame:IsForbidden()
		return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
	end
	function frame:IsProtected()
		return self.protected == true or (self.parent and self.parent:IsProtected()) or false
	end
	function frame:IsShown()
		self:CheckRead()
		return self.shown
	end
	function frame:CheckRead()
		if self:IsForbidden() then
			addon.invalidCalls = (addon.invalidCalls or 0) + 1
			error("unsafe owned read")
		end
	end
	function frame:Check(hide)
		if self:IsForbidden() or self:IsProtected() or (not hide and addon.blocked) then
			addon.invalidCalls = (addon.invalidCalls or 0) + 1
			error("unsafe owned mutation")
		end
		self.writes = self.writes + 1
	end
	function frame:Hide()
		self:Check(true)
		self.shown = false
		self.hides = self.hides + 1
	end
	function frame:Show()
		self:Check()
		self.shown = true
	end
	function frame:SetParent(parent)
		self:Check()
		self.parent = parent
	end
	function frame:SetAllPoints(parent)
		self:Check()
		self.allPoints = parent or self.parent
	end
	function frame:ClearAllPoints()
		self:Check()
		self.points = {}
	end
	function frame:SetPoint(...)
		self:Check()
		self.points[#self.points + 1] = { ... }
	end
	function frame:SetSize(width, height)
		self:Check()
		self.width, self.height = width, height
	end
	function frame:SetWidth(width)
		self:Check()
		self.width = width
	end
	function frame:SetFrameLevel(level)
		self:Check()
		self.level = level
	end
	function frame:GetFrameLevel()
		self:CheckRead()
		return self.level or 1
	end
	function frame:SetScript(event, callback)
		-- The unparented wake frame may install/remove cleanup during combat.
		self:Check(self.parent == nil)
		self.scripts[event] = callback
	end
	function frame:CreateTexture()
		self:Check()
		local region = Frame(addon, self, "Texture")
		addon.regions[#addon.regions + 1] = region
		return region
	end
	function frame:CreateMaskTexture()
		return self:CreateTexture()
	end
	function frame:CreateFontString(_, _, font)
		local region = self:CreateTexture()
		region.font = font
		return region
	end
	function frame:SetText(value)
		self:Check()
		self.text = value
	end
	function frame:GetStringHeight()
		self:CheckRead()
		return 96
	end
	function frame:SetColorTexture(r, g, b, a)
		self:Check()
		self.color = { r, g, b, a }
	end
	function frame:SetTexture(value) self:Check(); self.texture = value end
	function frame:SetAlpha(value) self:Check(); self.alpha = value end
	for _, method in ipairs({
		"EnableMouse",
		"SetClipsChildren",
		"RegisterForClicks",
		"SetBlendMode",
		"AddMaskTexture",
		"SetFrameStrata",
		"SetClampedToScreen",
		"SetJustifyH",
		"SetWordWrap",
		"SetSpacing",
	}) do
		frame[method] = function(self)
			self:Check()
		end
	end
	return frame
end

local function Row(name, x, y, mapID)
	return {
		name = name or "Friend-Realm",
		mapID = mapID or 1,
		x = x or 0.5,
		y = y or 0.5,
		classFile = "MAGE",
		className = "Mage",
		faction = "Alliance",
		race = "Human",
		level = 60,
		warMode = false,
	}
end

local function Fixture()
	local a = setmetatable(
		{ isEnabled = true, frames = {}, regions = {}, menus = {}, rows = {}, reads = {} },
		{ __index = QuestTogether }
	)
	a.mapParent, a.miniParent, a.tooltipParent = Frame(a), Frame(a), Frame(a)
	a.API = {
		RegionalUniqueNamesEnabled = function() return a.forever == true end,
		IsWarModeFeatureEnabled = function() return a.warModeFeature end,
	}
	a.warModeFeature = true
	a.geometry = {
		map = {
			parent = a.mapParent,
			mapID = 1,
			width = 1000,
			height = 600,
			canvasLeft = 0,
			canvasTop = 0,
			canvasWidth = 1000,
			canvasHeight = 600,
		},
		minimap = {
			parent = a.miniParent,
			mapID = 1,
			width = 200,
			height = 200,
			radius = 100,
			continent = 0,
			north = 500,
			west = 500,
			facing = 0,
			shape = "ROUND",
		},
	}
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	function a:GetLocationPinSurface(surface)
		self.geometryReads = (self.geometryReads or 0) + 1
		self.lastGeometrySurface = surface
		local g = self.geometry[surface]
		if self.blocked or not g or not self:CanAccessForeignFrame(g.parent, true) then
			return nil
		end
		return g
	end
	function a:AreLocationPinMapLayersCompatible(source, target)
		return source == target or not self.floorMismatch
	end
	function a:GetPlayerLocationPriorityOrigin()
		if self.worldUnavailable then return nil end
		return { continent = 0, north = 500, west = self.playerWest or 500 }
	end
	function a:GetLocationPinWorldPosition(mapID, x, y)
		if self.worldUnavailable then
			return nil
		end
		return mapID == 3 and 1 or 0, 1000 - y * 1000, 1000 - x * 1000
	end
	function a:GetLocationPinMapPosition(row, target)
		if row.mapID == target then
			return row.x, row.y
		end
		if self.crossMapAvailable and row.mapID == 2 and target == 1 then
			return row.x / 2, row.y / 2
		end
	end
	function a:GetVisiblePlayerLocations(surface)
		self.reads[surface] = (self.reads[surface] or 0) + 1
		return self.rows[surface] or {}
	end
	function a:GetLocationPinTooltipParent()
		return self.tooltipParent
	end
	function a:CreateLocationPinFrame(kind, name, parent, template)
		assert(not name and not template, "location UI must not use named/shared templates")
		if self.blocked then
			self.invalidCalls = (self.invalidCalls or 0) + 1
			error("restricted frame creation")
		end
		local frame = Frame(self, parent, kind)
		self.frames[#self.frames + 1] = frame
		self.regions[#self.regions + 1] = frame
		return frame
	end
	function a:IsIgnoredPlayerName(name)
		return name == self.ignored
	end
	function a:GetClassColorCode(class)
		return class == "MAGE" and "|cff40c7eb" or "|cffffffff"
	end
	function a:ShowChatLogSpeakerMenu(frame, name)
		self.menus[#self.menus + 1] = { owner = frame, name = name }
		return true
	end
	activeFixtures[#activeFixtures + 1] = a
	return a
end

local function Pin(a, surface, index)
	return a.locationPinState.surfaces[surface].pins[index or 1]
end

Register("location map projection follows zoom pan and clips the full dot", function()
	local a = Fixture()
	local g = a.geometry.map
	local x, y = a:ProjectPlayerLocationPin("map", Row(nil, 0.25, 0.5), g)
	Near(x, 250)
	Near(y, 300)
	g.canvasLeft, g.canvasTop, g.canvasWidth, g.canvasHeight = -500, -300, 2000, 1200
	x, y = a:ProjectPlayerLocationPin("map", Row(nil, 0.5, 0.5), g)
	Near(x, 500)
	Near(y, 300)
	Equal(a:ProjectPlayerLocationPin("map", Row(nil, 0.1, 0.5), g), nil)
	Equal(a:ProjectPlayerLocationPin("map", Row(nil, 0.251, 0.5), g), nil)
	Equal(a:ProjectPlayerLocationPin("map", Row(nil, 0.5, 1.2), g), nil)
	Equal(a:ProjectPlayerLocationPin("map", Row(nil, 0.5, 0.5, 2), g), nil)
	a.crossMapAvailable = true
	x, y = a:ProjectPlayerLocationPin("map", Row(nil, 0.8, 0.8, 2), g)
	Near(x, 300)
	Near(y, 180)
	a.floorMismatch = true
	Equal(a:ProjectPlayerLocationPin("map", Row(nil, 0.8, 0.8, 2), g), nil)
end)

Register("location minimap cardinal directions rotation radius and masks are exact", function()
	local a = Fixture()
	local g = a.geometry.minimap
	local x, y = a:ProjectPlayerLocationPin("minimap", Row(nil, 0.55, 0.5), g)
	Near(x, 150)
	Near(y, 100)
	x, y = a:ProjectPlayerLocationPin("minimap", Row(nil, 0.5, 0.45), g)
	Near(x, 100)
	Near(y, 50)
	g.facing = math.pi / 2
	x, y = a:ProjectPlayerLocationPin("minimap", Row(nil, 0.45, 0.5), g)
	Near(x, 100)
	Near(y, 50)
	g.facing, g.radius = 0, 200
	x, y = a:ProjectPlayerLocationPin("minimap", Row(nil, 0.55, 0.5), g)
	Near(x, 125)
	Near(y, 100)
	g.radius = 100
	Equal(a:ProjectPlayerLocationPin("minimap", Row(nil, 0.59, 0.59), g), nil)
	g.shape = "SQUARE"
	x, y = a:ProjectPlayerLocationPin("minimap", Row(nil, 0.59, 0.59), g)
	Near(x, 190)
	Near(y, 190)
	Equal(a:ProjectPlayerLocationPin("minimap", Row(nil, 0.596, 0.5), g), nil)
	Equal(a:ProjectPlayerLocationPin("minimap", Row(nil, 0.5, 0.5, 3), g), nil)
	g.shape = "UNKNOWN"
	Equal(a:ProjectPlayerLocationPin("minimap", Row(), g), nil)
	Equal(a:ProjectPlayerLocationPin("minimap", Row(nil, math.huge, 0.5), g), nil)
end)

Register("location dots reuse a bounded pool and copy no state to native parents", function()
	local a = Fixture()
	for _, surface in ipairs({ "map", "minimap" }) do
		a.rows[surface] = {}
		for index = 1, 200 do
			a.rows[surface][index] = Row("Peer" .. index .. "-Realm")
		end
	end
	assert(a:RefreshPlayerLocationPins())
	Equal(#a.locationPinState.surfaces.map.pins, 128)
	Equal(#a.locationPinState.surfaces.minimap.pins, 128)
	Equal(a.mapParent.writes + a.miniParent.writes, 0)
	Equal(next(a.mapParent.scripts), nil)
	local frames = #a.frames
	assert(a:RefreshPlayerLocationPins())
	Equal(#a.frames, frames)
	a.rows.map, a.rows.minimap = { Row("Replacement-Realm") }, {}
	assert(a:RefreshPlayerLocationPins())
	Equal(Pin(a, "map").name, "Replacement-Realm")
	Equal(Pin(a, "map", 2).name, nil)
	Equal(Pin(a, "map", 2).frame.shown, false)
	Equal(a.locationPinState.surfaces.minimap.frame.shown, false)
	Equal(#a.frames, frames)
	local color = Pin(a, "map").texture.color
	Near(color[1], 64 / 255)
	Near(color[2], 199 / 255)
	Near(color[3], 235 / 255)
	a.rows.map[1].classFile = nil
	a:RefreshPlayerLocationPins()
	Equal(Pin(a, "map").texture.color[1], 1)
end)

Register("location renderer finds visible players after off-map candidates and preserves interaction", function()
	for _, surface in ipairs({ "map", "minimap" }) do
		local a = Fixture()
		a.rows[surface] = {}
		for index = 1, 128 do
			a.rows[surface][index] = Row(string.format("A%03d-Realm", index), 0.5, 0.5, 3)
		end
		a.rows[surface][129] = Row("ZVisible-Realm")
		assert(a:RefreshPlayerLocationPins())
		local pin = Pin(a, surface)
		Equal(#a.locationPinState.surfaces[surface].pins, 1)
		Equal(pin.name, "ZVisible-Realm")
		assert(pin.frame.shown)
		pin.frame.scripts.OnEnter({})
		assert(a.locationPinState.tooltip.shown)
		assert(a.locationPinState.tooltipTitle.text:find("ZVisible-Realm", 1, true))
		pin.frame.scripts.OnClick({}, "RightButton")
		Equal(#a.menus, 1)
		Equal(a.menus[1].name, "ZVisible-Realm")
	end
end)

Register("location renderer bounds candidates independently from its visible pin pool", function()
	for _, surface in ipairs({ "map", "minimap" }) do
		local a = Fixture()
		local projections = 0
		function a:ProjectPlayerLocationPin(...)
			projections = projections + 1
			return QuestTogether.ProjectPlayerLocationPin(self, ...)
		end
		a.rows[surface] = {}
		for index = 1, 328 do
			a.rows[surface][index] = Row(string.format("Peer%03d-Realm", index), 0.5, 0.5, index <= 128 and 3 or 1)
		end
		assert(a:RefreshPlayerLocationPins())
		Equal(projections, 128)
		Equal(#a.locationPinState.surfaces[surface].pins, 128)
		Equal(Pin(a, surface, 128).name, "Peer256-Realm")
		local frames = #a.frames
		projections = 0
		assert(a:RefreshPlayerLocationPins())
		Equal(projections, 128)
		Equal(#a.frames, frames)

		-- Oversized input cannot extend native projection work beyond the model
		-- contract. A visible peer at the last supported index still renders.
		for index = 1, 513 do
			a.rows[surface][index] = Row(string.format("Peer%03d-Realm", index), 0.5, 0.5, index == 513 and 1 or 3)
		end
		projections = 0
		Equal(a:RefreshPlayerLocationPins(), false)
		Equal(projections, 512)
		Equal(a.locationPinState.surfaces[surface].frame.shown, false)
		a.rows[surface][512] = Row("Peer512-Realm")
		projections = 0
		assert(a:RefreshPlayerLocationPins())
		Equal(projections, 512)
		Equal(Pin(a, surface).name, "Peer512-Realm")
		Equal(Pin(a, surface, 2).frame.shown, false)
		Equal(#a.locationPinState.surfaces[surface].pins, 128)
		Equal(#a.frames, frames)
	end
end)

Register("location tooltip and clicks revalidate live permissions identity and map", function()
	local a = Fixture()
	a.rows.map = { Row() }
	a:RefreshPlayerLocationPins()
	local pin = Pin(a, "map")
	pin.frame.scripts.OnEnter({})
	local state = a.locationPinState
	assert(state.tooltip.shown)
	assert(state.tooltipTitle.text:find("Friend-Realm", 1, true))
	for _, text in ipairs({
		"Level 60 Human ",
		"Mage|r",
		"War Mode: Off",
	}) do
		assert((state.tooltipIntro.text .. "\n" .. state.tooltipLabel.text):find(text, 1, true))
	end
	Equal(state.tooltipFaction.texture, "Interface\\TargetingFrame\\UI-PVP-Alliance")
	assert(state.tooltipFaction.shown)
	assert(not state.tooltipLabel.text:find("Class:", 1, true))
	pin.frame.scripts.OnClick({}, "RightButton")
	Equal(a.menus[1].name, "Friend-Realm")
	Equal(a.menus[1].owner, pin.frame)
	Equal(state.tooltip.shown, false)
	a.ignored = "Friend-Realm"
	pin.frame.scripts.OnEnter({})
	pin.frame.scripts.OnClick({}, "LeftButton")
	Equal(#a.menus, 1)
	Equal(state.tooltip.shown, false)
	a.ignored, a.rows.map = nil, { Row("Different-Realm") }
	pin.frame.scripts.OnClick({}, "LeftButton")
	Equal(#a.menus, 1)
	a:RefreshPlayerLocationPins()
	pin.frame.scripts.OnClick({}, "LeftButton")
	Equal(a.menus[2].name, "Different-Realm")
	a.geometry.map.mapID = 2
	pin.frame.scripts.OnClick({}, "LeftButton")
	Equal(#a.menus, 2)
	a.geometry.map.mapID, a.rows.map = 1, {}
	pin.frame.scripts.OnClick({}, "LeftButton")
	Equal(#a.menus, 2)
	a:RefreshPlayerLocationPins()
	Equal(pin.name, nil)
	Equal(state.surfaces.map.frame.shown, false)
end)

Register("location tooltips hide unsupported War Mode and preserve every surface dot", function()
	for _, capability in ipairs({ "regional", "disabled", "unknown", "enabled" }) do
		local a = Fixture()
		a.forever = capability == "regional"
		local name = a.forever and "Torres Sky" or "Friend-Realm"
		if capability == "disabled" then
			a.warModeFeature = false
		elseif capability == "unknown" then
			a.warModeFeature = nil
		end
		for _, surface in ipairs({ "map", "minimap" }) do
			a.rows[surface] = { Row(name) }
			-- Older senders can still attach a War Mode field on Forever.
			a.rows[surface][1].warMode = true
		end
		assert(a:RefreshPlayerLocationPins())
		for _, surface in ipairs({ "map", "minimap" }) do
			local pin = Pin(a, surface)
			Equal(pin.name, name)
			assert(pin.frame.shown)
			pin.frame.scripts.OnEnter({})
			local state = a.locationPinState
			assert(state.tooltip.shown)
			assert(state.tooltipTitle.text:find(name, 1, true))
			Equal(state.tooltipLabel.text:find("War Mode: On", 1, true) ~= nil, capability == "enabled")
			pin.frame.scripts.OnLeave({})
		end
	end
end)

Register("location empty surfaces skip UI allocation and all native geometry reads", function()
	local a = Fixture()
	Equal(a:RefreshPlayerLocationPins(), false)
	Equal(rawget(a, "locationPinState"), nil)
	Equal(#a.frames, 0)
	Equal(a.geometryReads, nil)
	a.rows.map = { Row() }
	assert(a:RefreshPlayerLocationPins())
	Equal(a.geometryReads, 1)
	Equal(a.lastGeometrySurface, "map")
	a.rows.map = {}
	Equal(a:RefreshPlayerLocationPins(), false)
	Equal(a.geometryReads, 1)
	Equal(a.locationPinState.surfaces.map.frame.shown, false)
end)

Register("location empty optional metadata uses class token and unknown character details", function()
	local a = Fixture()
	local row = Row()
	row.className, row.race, row.faction, row.level = "", "", "", nil
	a.rows.map = { row }
	assert(a:RefreshPlayerLocationPins())
	Pin(a, "map").frame.scripts.OnEnter({})
	local text = a.locationPinState.tooltipIntro.text
	for _, expected in ipairs({ "MAGE|r", "Level Unknown Unknown " }) do
		assert(text:find(expected, 1, true))
	end
	Equal(a.locationPinState.tooltipFaction.shown, false)
end)

Register("remote dot and chat tooltips show fresh party size without tracked quest counts", function()
	local a = Fixture()
	local now = 100
	a.API.GetTime = function() return now end
	a.API.GetRealmName = function() return "Realm" end
	function a:GetPlayerFullName() return "Me-Realm" end
	function a:GetChatLogTooltipCursorPosition() return 100, 200 end
	local row = Row("Friend-Realm")
	a.qtPlayerPresenceState = {
		peers = { [row.name] = now },
		peerTooltipStats = { [row.name] = { count = 12, partySize = 4, at = now } },
	}
	a.rows.map, a.playerLocationState = { row }, { peers = { [row.name] = row } }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	local text = a.locationPinState.tooltipLabel.text
	Equal(text:find("Tracked quests:", 1, true), nil)
	assert(a.locationPinState.tooltipIntro.text:find("Party of 4", 1, true))
	local chat = Frame(a, a.tooltipParent)
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm"))
	Equal(a.chatLogPlayerTooltipState.tooltipLabel.text, text)
	now = 280
	a:UpdateChatLogPlayerTooltip()
	text = a.chatLogPlayerTooltipState.tooltipLabel.text
	Equal(text:find("Tracked quests:", 1, true), nil)
	assert(a.chatLogPlayerTooltipState.tooltipIntro.text:find("Party status unknown", 1, true))
	a.partyJoinState = { peers = { [row.name] = { grouped = "0", at = now } } }
	a:UpdateChatLogPlayerTooltip()
	assert(a.chatLogPlayerTooltipState.tooltipIntro.text:find("Solo", 1, true))
	a.partyJoinState.peers[row.name].grouped = "1"
	a:UpdateChatLogPlayerTooltip()
	assert(a.chatLogPlayerTooltipState.tooltipIntro.text:find("In a party", 1, true))
	Equal(a.chatLogPlayerTooltipState.tooltipIntro.text:find("Party of 4", 1, true), nil)
end)

Register("player tooltip reuses faction and class styling without leaking the previous player", function()
	local a = Fixture()
	local row = Row()
	a.rows.map = { row }
	a:RefreshPlayerLocationPins()
	local pin = Pin(a, "map")
	pin.frame.scripts.OnEnter({})
	local state = a.locationPinState
	local regions = #a.regions
	row.faction, row.race, row.className, row.classFile, row.level = "Horde", "Troll", "Warlock", "WARLOCK", 13
	pin.frame.scripts.OnEnter({})
	Equal(#a.regions, regions)
	Equal(state.tooltipFaction.texture, "Interface\\TargetingFrame\\UI-PVP-Horde")
	Equal(state.tooltipFaction.width,36); Equal(state.tooltipFaction.height,36)
	Equal(state.tooltipTitle.width,228)
	assert(state.tooltipFaction.shown)
	assert(state.tooltipIntro.text:find("Level 13 Troll ", 1, true))
	assert(state.tooltipIntro.text:find(a:GetClassColorCode("WARLOCK") .. "Warlock|r", 1, true))
	row.faction = "Unknown"
	pin.frame.scripts.OnEnter({})
	Equal(state.tooltipFaction.shown, false)
	Equal(state.tooltipTitle.width, 272)
end)

Register("own chat tooltip reads live super tracking without a received peer record or sharing consent", function()
	local a = Fixture()
	local id = 42
	a.API.GetRealmName = function() return "Realm" end
	a.API.GetActiveTrackedQuestID = function() return id end
	function a:GetPlayerFullName() return "Me-Realm" end
	function a:GetAddonVersion() return "5.16.7" end
	local count, size = 8, 0
	function a:GetMonitoredQuestCount() return count end
	a.API.GetPartyJoinInfo = function() return size > 0, false, size end
	function a:GetOption(key) return key == "lookingForQuestPartners" end
	function a:ReadLocalPlayerLocation() return Row("Me-Realm") end
	function a:CanPublishPlayerLocation() error("self tooltip must not depend on sharing") end
	function a:GetLocalizedQuestTitle(questID) return "Local quest " .. questID end
	function a:GetChatLogTooltipCursorPosition() return 100, 100 end
	local chat = Frame(a, a.tooltipParent)
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Me-Realm"))
	local state = a.chatLogPlayerTooltipState
	assert(state.tooltipLabel.text:find("Tracked quest: Local quest 42", 1, true))
	assert(state.tooltipIntro.text:find("Level 60 Human", 1, true))
	assert(state.tooltipLabel.text:match("\n\n|cff909090v5%.16%.7|r$"))
	Equal(state.tooltipLabel.text:find("Tracked quests:", 1, true), nil)
	assert(state.tooltipIntro.text:find("Solo", 1, true))
	count, size = 7, 3
	id = 43
	a:UpdateChatLogPlayerTooltip()
	assert(state.tooltipLabel.text:find("Tracked quest: Local quest 43", 1, true))
	Equal(state.tooltipLabel.text:find("Tracked quests:", 1, true), nil)
	assert(state.tooltipIntro.text:find("Party of 3", 1, true))
	id = nil
	a:UpdateChatLogPlayerTooltip()
	Equal(state.tooltipLabel.text:find("Tracked quest:", 1, true), nil)
	id = 43
	a.blocked = true
	a:UpdateChatLogPlayerTooltip()
	Equal(state.tooltip.shown, false)
end)

Register("quest hover shows local status and objectives at the cursor and clears between link kinds", function()
	local a = Fixture()
	a.db = { global = {} }
	local tracker = { [42] = { objectives = { "Wolves slain: 3/8", "|Hbad|hText|h" } } }
	function a:GetPlayerTracker() return tracker end
	function a:GetQuestTitle(id) return "Quest " .. id end
	local status, shareable = "In Progress", "Yes"
	function a:GetQuestStatusLabel() return status end
	function a:GetQuestShareableStatusLabel() return shareable end
	function a:GetChatLogTooltipCursorPosition() return 100, 200 end
	function a:PrintQuestStatus() error("hover must not print") end
	function a:RegisterChatLogHoverCallbacks(enter, leave) self.enter, self.leave = enter, leave; return true end
	a:InitializeChatLogPlayerTooltips()
	local chat = Frame(a, a.tooltipParent)
	a.enter(nil, chat, "questtogetherquest:42", "|Hquesttogetherquest:42|h[Wolf Hunt]|h")
	local state = a.chatLogPlayerTooltipState
	assert(state.tooltip.shown)
	assert(state.tooltipTitle.text:find("Wolf Hunt", 1, true))
	for _, text in ipairs({ "Your quest status: In Progress", "Shareable: Yes", "Quest ID: 42", "Wolves slain: 3/8", "||Hbad||hText||h" }) do
		assert(state.tooltipLabel.text:find(text, 1, true), text)
	end
	Equal(state.tooltipFaction.shown, false)
	Equal(state.tooltipLabel.text:find("QT Version", 1, true), nil)
	Equal(state.tooltip.points[1][4], 112)
	Equal(state.tooltip.points[1][5], 212)
	tracker[42], status, shareable = nil, "Not Started", "Unknown"
	a:UpdateChatLogPlayerTooltip()
	assert(state.tooltipLabel.text:find("Your quest status: Not Started", 1, true))
	Equal(state.tooltipLabel.text:find("Wolves", 1, true), nil)
	a.enter(nil, chat, "questtogetherlog:Friend-Realm")
	Equal(state.tooltipLabel.text:find("Your quest status", 1, true), nil)
	Equal(state.tooltipLabel.text:find("Tracked quests:", 1, true), nil)
	assert(state.tooltipIntro.text:find("Party status unknown", 1, true))
	a.enter(nil, chat, "questtogetherquest:42", "[Wolf Hunt]")
	a.blocked = true
	a:UpdateChatLogPlayerTooltip()
	Equal(state.tooltip.shown, false)
	a.blocked = false
	for _, link in ipairs({ "item:42", "questtogetherquest:0", "questtogetherquest:-1", "questtogetherquest:abc", "questtogetherquest:1.5", "questtogetherquest:1e999" }) do
		Equal(a:ShowChatLogPlayerTooltip(chat, link), false)
	end
	a.enter(nil, chat, "questtogetherquest:42", "[Wolf Hunt]")
	a.leave()
	Equal(state.tooltip.shown, false)
end)

Register("location unavailable geometry clears old surface dots and hover", function()
	local a = Fixture()
	a.rows.map, a.rows.minimap = { Row() }, { Row() }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter({})
	a.geometry.map = nil
	assert(a:RefreshPlayerLocationPins())
	Equal(a.locationPinState.surfaces.map.frame.shown, false)
	Equal(Pin(a, "map").name, nil)
	Equal(a.locationPinState.tooltip.shown, false)
	a.worldUnavailable = true
	Equal(a:RefreshPlayerLocationPins(), false)
	Equal(a.locationPinState.surfaces.minimap.frame.shown, false)
	Equal(Pin(a, "minimap").name, nil)
end)

Register("location restrictions hide safe owned overlays without layout or menu activity", function()
	local a = Fixture()
	a.rows.map = { Row() }
	a:RefreshPlayerLocationPins()
	local pin, state = Pin(a, "map"), a.locationPinState
	pin.frame.scripts.OnEnter({})
	a.blocked = true
	Equal(a:RefreshPlayerLocationPins(), false)
	Equal(state.surfaces.map.frame.shown, false)
	Equal(state.tooltip.shown, false)
	pin.frame.scripts.OnEnter({})
	pin.frame.scripts.OnClick({}, "LeftButton")
	Equal(#a.menus, 0)
	Equal(a.mapParent.writes, 0)
	a.blocked = false
	assert(a:RefreshPlayerLocationPins())
end)

Register("location forbidden cleanup survives disable and cannot hide a reused active overlay", function()
	for _, boundary in ipairs({ "forbidden", "protected" }) do
		local a = Fixture()
		a.rows.map = { Row() }
		a:RefreshPlayerLocationPins()
		local state, surface = a.locationPinState, a.locationPinState.surfaces.map
		local writes = surface.frame.writes
		a.mapParent[boundary], a.isEnabled = true, false
		a:HidePlayerLocationPins()
		Equal(surface.frame.writes, writes)
		Equal(Pin(a, "map").name, nil)
		assert(state.pending[surface.frame] and state.wake.scripts.OnUpdate)
		state.wake.scripts.OnUpdate({}, 0.5)
		Equal(surface.frame.writes, writes)
		a.mapParent[boundary] = false
		state.wake.scripts.OnUpdate({}, 0.5)
		Equal(surface.frame.shown, false)
		Equal(next(state.pending), nil)
		Equal(state.wake.scripts.OnUpdate, nil)
		a.isEnabled = true
		assert(a:RefreshPlayerLocationPins())
		a.mapParent[boundary] = true
		a:HidePlayerLocationPins()
		local staleWake = state.wake.scripts.OnUpdate
		a.mapParent[boundary] = false
		assert(a:RefreshPlayerLocationPins())
		staleWake({}, 0.5)
		assert(surface.frame.shown)
		Equal(state.pending[surface.frame], nil)
	end
end)

Register("location overlay reparents only after its quarantined prior parent recovers", function()
	local a = Fixture()
	a.rows.map = { Row() }
	a:RefreshPlayerLocationPins()
	local state, oldParent = a.locationPinState, a.mapParent
	local oldFrame, count = state.surfaces.map.frame, #a.frames
	oldParent.forbidden = true
	a.geometry.map.parent = Frame(a)
	Equal(a:RefreshPlayerLocationPins(), false)
	Equal(oldFrame.parent, oldParent)
	Equal(#a.frames, count)
	oldParent.forbidden = false
	assert(a:RefreshPlayerLocationPins())
	Equal(state.surfaces.map.frame, oldFrame)
	Equal(oldFrame.parent, a.geometry.map.parent)
	Equal(#a.frames, count)
	Equal(a.geometry.map.parent.writes, 0)
end)

Register("location hidden expired or ignored peer never keeps a stale tooltip", function()
	local a = Fixture()
	a.rows.map = { Row() }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter({})
	local state = a.locationPinState
	state.tooltip.forbidden = true
	local writes = state.tooltip.writes
	a.rows.map = {}
	a:RefreshPlayerLocationPins()
	Equal(state.tooltip.writes, writes)
	Equal(state.hovered, nil)
	assert(state.pending[state.tooltip])
	state.tooltip.forbidden = false
	state.wake.scripts.OnUpdate({}, 0.5)
	Equal(state.tooltip.shown, false)
	Equal(next(state.pending), nil)
end)

Register("location hover refreshes explicit quest partner status without replacing the pin", function()
	local a = Fixture()
	a.now = 100
	a.API = {
		GetTime = function() return a.now end,
		GetRealmName = function() return "Realm" end,
		RegionalUniqueNamesEnabled = function() return false end,
	}
	function a:GetPlayerFullName() return "Me-Realm" end
	a.qtPlayerPresenceState = { peers = { ["Friend-Realm"] = 100 }, questPartners = { ["Friend-Realm"] = { receivedAt = 100, looking = true } } }
	a.rows.map = { Row() }
	a:RefreshPlayerLocationPins()
	local pin = Pin(a, "map")
	pin.frame.scripts.OnEnter({})
	assert(a.locationPinState.tooltipLabel.text:find("Looking for Questing Partners", 1, true))
	a.now = 165
	a.qtPlayerPresenceState.peers["Friend-Realm"] = 165 -- Ordinary presence cannot renew the status.
	a:RefreshPlayerLocationPins()
	Equal(Pin(a, "map"), pin)
	assert(a.locationPinState.tooltip.shown)
	Equal(a.locationPinState.tooltipLabel.text:find("Looking for Questing Partners", 1, true), nil)
	a.qtPlayerPresenceState.questPartners["Friend-Realm"] = { receivedAt = 165, looking = true }
	a:RefreshPlayerLocationPins()
	assert(a.locationPinState.tooltipLabel.text:find("Looking for Questing Partners", 1, true))
	a.qtPlayerPresenceState.questPartners["Friend-Realm"] = nil
	a:RefreshPlayerLocationPins()
	Equal(a.locationPinState.tooltipLabel.text:find("Looking for Questing Partners", 1, true), nil)
end)

Register("quest partner dots gain a gold glow and return to normal on expiry or pin reuse", function()
	local a = Fixture()
	a.now = 100
	a.API.GetTime = function() return a.now end
	a.API.GetRealmName = function() return "Realm" end
	function a:GetPlayerFullName() return "Me-Realm" end
	a.qtPlayerPresenceState = { peers = {}, questPartners = {} }
	for _, surface in ipairs({ "map", "minimap" }) do a.rows[surface] = { Row() } end
	assert(a:RefreshPlayerLocationPins())
	local frames, regions = #a.frames, #a.regions
	a.qtPlayerPresenceState.questPartners["Friend-Realm"] = { receivedAt = 100, looking = true }
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do
		local pin = Pin(a, surface)
		Equal(pin.frame.width, 16)
		Equal(pin.border.color[4], 0)
		local previousSize, previousAlpha = math.huge, 0
		for _, glow in ipairs(pin.glow) do
			assert(glow.shown)
			assert(glow.width < previousSize and glow.color[4] > previousAlpha, "halo fades toward the outer edge")
			assert(glow.width <= 16 and glow.color[4] < 1)
			Equal(glow.color[1], 1)
			previousSize, previousAlpha = glow.width, glow.color[4]
		end
		Near(pin.texture.color[1], 64 / 255)
		Equal(pin.texture.width, 9)
	end
	a.now = 165
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do
		Equal(Pin(a, surface).border.width, 12)
		Equal(Pin(a, surface).border.color[1], 0)
		for _, glow in ipairs(Pin(a, surface).glow) do assert(not glow.shown) end
	end
	a.qtPlayerPresenceState.questPartners["Friend-Realm"].receivedAt = 165
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do a.rows[surface] = { Row("Other-Realm") } end
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do
		Equal(Pin(a, surface).frame.width, 12)
		Equal(Pin(a, surface).border.color[2], 0)
		for _, glow in ipairs(Pin(a, surface).glow) do assert(not glow.shown) end
	end
	Equal(#a.frames, frames)
	Equal(#a.regions, regions)
end)

Register("quest partner dot projection clips the complete larger glow on both maps", function()
	local a = Fixture()
	function a:IsPlayerLookingForQuestPartners() return self.looking == true end
	local nearMapEdge, nearMiniEdge = Row(nil, 0.007, 0.5), Row(nil, 0.593, 0.5)
	assert(a:ProjectPlayerLocationPin("map", nearMapEdge, a.geometry.map))
	assert(a:ProjectPlayerLocationPin("minimap", nearMiniEdge, a.geometry.minimap))
	a.looking = true
	Equal(a:ProjectPlayerLocationPin("map", nearMapEdge, a.geometry.map), nil)
	Equal(a:ProjectPlayerLocationPin("minimap", nearMiniEdge, a.geometry.minimap), nil)
	assert(a:ProjectPlayerLocationPin("map", Row(), a.geometry.map))
	assert(a:ProjectPlayerLocationPin("minimap", Row(), a.geometry.minimap))
end)

Register("quest partner glow changes respect restrictions and forbidden parents", function()
	local a = Fixture()
	function a:IsPlayerLookingForQuestPartners() return self.looking == true end
	a.rows.map = { Row() }
	assert(a:RefreshPlayerLocationPins())
	local pin = Pin(a, "map")
	a.looking, a.blocked = true, true
	a:RefreshPlayerLocationPins()
	Equal(pin.border.width, 12)
	a.blocked, a.mapParent.forbidden = false, true
	a:RefreshPlayerLocationPins()
	Equal(pin.border.width, 12)
	a.mapParent.forbidden = false
	assert(a:RefreshPlayerLocationPins())
	assert(pin.glow[1].shown)
	Equal(pin.frame.width, 16)
end)

Register("location tooltip distinguishes an older last reported position from a fresh update", function()
	local a = Fixture()
	function a:GetPlayerAddonVersion() return "6.0.3" end
	a.now = 500
	a.API.GetTime = function() return a.now end
	a.rows.map = { Row() }
	a.rows.map[1].receivedAt = 450
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter({})
	assert(a.locationPinState.tooltipLabel.text:match("\n\n|cff909090Last update: 50 seconds ago\nv6%.0%.3|r$"))
	a.now = 505
	a:RefreshPlayerLocationPins()
	assert(a.locationPinState.tooltipLabel.text:find("Last update: 55 seconds ago", 1, true))
	a.rows.map[1].receivedAt = 505
	a:RefreshPlayerLocationPins()
	Equal(a.locationPinState.tooltipLabel.text:find("Last update:", 1, true), nil)
	a.rows.map[1].receivedAt = nil
	a:RefreshPlayerLocationPins()
	Equal(a.locationPinState.tooltipLabel.text:find("Last update:", 1, true), nil)
end)

Register("partner dot tooltips show localized super-tracking and clear it on newer status or expiry", function()
	for _, surface in ipairs({ "map", "minimap" }) do
		local a = Fixture()
		a.now = 100
		a.API.GetTime = function() return a.now end
		a.API.GetRealmName = function() return "Realm" end
		function a:GetPlayerFullName() return "Me-Realm" end
		function a:GetLocalizedQuestTitle(id)
			Equal(id, 42)
			return self.title
		end
		a.title = "Une quête |cffff0000test"
		a.qtPlayerPresenceState = {
			peers = {},
			questPartners = { ["Friend-Realm"] = { session = "10-1234", sequence = 1, receivedAt = 100, looking = true } },
			partnerQuests = { ["Friend-Realm"] = { session = "10-1234", sequence = 1, receivedAt = 100, questID = 42 } },
		}
		a.rows[surface] = { Row() }
		a:RefreshPlayerLocationPins()
		Pin(a, surface).frame.scripts.OnEnter({})
		assert(a.locationPinState.tooltipLabel.text:find("Tracked quest: Une quête ||cffff0000test", 1, true))
		a.title = nil
		a.qtPlayerPresenceState.partnerQuests["Friend-Realm"].title = "Sender |Hquest:42|hname|h"
		a:RefreshPlayerLocationPins()
		assert(a.locationPinState.tooltipLabel.text:find("Tracked quest: Sender ||Hquest:42||hname||h", 1, true))
		a.qtPlayerPresenceState.partnerQuests["Friend-Realm"].title = nil
		a:RefreshPlayerLocationPins()
		assert(a.locationPinState.tooltipLabel.text:find("Tracked quest: Quest 42", 1, true))
		a.qtPlayerPresenceState.questPartners["Friend-Realm"].sequence = 2
		a:RefreshPlayerLocationPins()
		Equal(a.locationPinState.tooltipLabel.text:find("Tracked quest:", 1, true), nil)
		a.qtPlayerPresenceState.questPartners["Friend-Realm"].sequence = 1
		a.now = 165
		a:RefreshPlayerLocationPins()
		Equal(a.locationPinState.tooltipLabel.text:find("Tracked quest:", 1, true), nil)
	end
end)

Register("crowded maps prioritize closest players independently of names and map pan", function()
	for _, surface in ipairs({ "map", "minimap" }) do
		local a = Fixture()
		local rows = {}
		for i = 1, 128 do rows[i] = Row(string.format("A%03d-Realm", i), 0.55, 0.5) end
		rows[129] = Row("ZClosest-Realm", 0.501, 0.5)
		a.rows[surface] = rows
		assert(a:RefreshPlayerLocationPins())
		Equal(Pin(a, surface).name, "ZClosest-Realm")
		Equal(#a.locationPinState.surfaces[surface].pins, 128)
		Equal(Pin(a, surface, 128).name, "A127-Realm")
		-- Moving the player, without new peer messages, changes priority.
		a.playerWest = 450
		a.geometry.minimap.west = 450
		assert(a:RefreshPlayerLocationPins())
		Equal(Pin(a, surface).name, "A001-Realm")
		Equal(Pin(a, surface, 128).name, "A128-Realm")
		Equal(rows[129].name, "ZClosest-Realm", "source ordering must not be mutated")
	end
end)

Register("location distance ranks shared world coordinates and uses stable unknown fallback", function()
	local a = Fixture()
	local rows = { Row("ZNear", 0.501, 0.5, 2), Row("AFar", 0.55, 0.5), Row("OtherWorld", 0.5, 0.5, 3) }
	local ranked = a:PrioritizePlayerLocationRows(rows, a:GetPlayerLocationPriorityOrigin())
	Equal(ranked[1].name, "ZNear")
	Equal(ranked[3].name, "OtherWorld")
	ranked = a:PrioritizePlayerLocationRows(rows, nil)
	Equal(ranked[1].name, "AFar")
	Equal(ranked[3].name, "ZNear")
end)

Register("chat speaker hover reuses dot tooltip content and cleans up independent hover state", function()
	local a = Fixture()
	local row = Row("Friend-Realm", 0.5, 0.5)
	local chat = Frame(a)
	function a:GetChatLogTooltipCursorPosition() return 200, 100 end
	a.playerLocationState = { peers = { [row.name] = row } }
	a.rows.map = { row }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	local expected = a.locationPinState.tooltipLabel.text
	-- Reproduce a live client whose real addon has already installed callbacks.
	-- Private fixture initialization must not inherit that instance's state.
	setmetatable(a, { __index = function(_, key)
		if key == "chatLogHoverCallbacksInstalled" then return true end
		return QuestTogether[key]
	end })
	local registrations, enter, leave = 0
	function a:RegisterChatLogHoverCallbacks(onEnter, onLeave)
		registrations = registrations + 1
		enter, leave = onEnter, onLeave
		return true
	end
	a:InitializeChatLogPlayerTooltips()
	a:InitializeChatLogPlayerTooltips()
	Equal(registrations, 1)
	enter(nil, chat, "questtogetherlog:Friend-Realm")
	local state = a.chatLogPlayerTooltipState
	Equal(state.tooltipLabel.text, expected)
	Equal(state.tooltipTitle.font, "GameFontNormalLarge")
	Equal(state.tooltipLabel.font, "GameFontHighlight")
	Equal(state.tooltip.width, 300)
	assert(state.tooltipTitle.text:find("|cff40c7eb", 1, true))
	Equal(state.tooltip.points[1][2], a.tooltipParent)
	Equal(state.tooltip.points[1][4], 212)
	Equal(state.tooltip.points[1][5], 112)
	assert(state.tooltip.shown)
	a:HidePlayerLocationPins()
	assert(state.tooltip.shown)
	leave()
	assert(not state.tooltip.shown)
	Equal(a:ShowChatLogPlayerTooltip(chat, "item:123"), false)
	Equal(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm"), true)
	a.ignored = row.name
	a:UpdateChatLogPlayerTooltip()
	assert(not state.tooltip.shown)
	a.ignored = nil
	a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm")
	a.blocked = true
	a:UpdateChatLogPlayerTooltip()
	assert(not state.tooltip.shown)
	a.blocked = false
	a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm")
	chat:Hide()
	a:UpdateChatLogPlayerTooltip()
	assert(not state.tooltip.shown)
	chat:Show()
	a.isEnabled = false
	Equal(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm"), false)
end)

local function VisualParty(a)
	local info = { key = "Leader:123", size = 3, leader = "Leader-Realm", leaderClass = "MAGE", members = {
		{ name = "Leader-Realm", classFile = "MAGE" }, { name = "Friend-Realm", classFile = "WARRIOR" },
		{ name = "Third-Realm", classFile = "MAGE" },
	} }
	a.visualMembers = { ["Leader-Realm"] = info, ["Friend-Realm"] = info, ["Third-Realm"] = info }
	function a:GetPlayerPartyVisualInfo(name) return self.visualMembers[name] end
	function a:RequestPartyVisualRoster() self.rosterRequests = (self.rosterRequests or 0) + 1 end
	return info
end
Register("party map badges hover outline leader crown and dimming span both surfaces and clear on leave", function()
	local a = Fixture(); VisualParty(a)
	a.rows.map = { Row("Friend-Realm"), Row("Leader-Realm",0.6,0.5), Row("Unrelated-Realm",0.7,0.5) }
	a.rows.minimap = { Row("Third-Realm") }
	function a:IsPlayerLookingForQuestPartners(name) return name == "Leader-Realm" end
	assert(a:RefreshPlayerLocationPins())
	local member,leader,other,mini=Pin(a,"map",1),Pin(a,"map",2),Pin(a,"map",3),Pin(a,"minimap")
	assert(member.partyBadge.shown and leader.partyBadge.shown and not other.partyBadge.shown)
	assert(not leader.partyCrown.shown and not member.partyOutline.shown)
	member.frame.scripts.OnEnter()
	assert(member.partyOutline.shown and leader.partyOutline.shown and mini.partyOutline.shown)
	assert(leader.partyCrown.shown and not member.partyCrown.shown and not other.partyCrown.shown)
	Near(other.frame.alpha,0.45); Near(leader.frame.alpha,1)
	assert(leader.glow[1].shown) -- gold LFQP identity survives the independent white ring
	member.frame.scripts.OnLeave()
	assert(not leader.partyCrown.shown and not mini.partyOutline.shown)
	Near(other.frame.alpha,1); assert(leader.glow[1].shown)
end)
Register("party tooltip lists class colored members crowned leader first and only the leader above five", function()
	local a=Fixture(); local info=VisualParty(a)
	a.rows.map={Row("Friend-Realm")}; a:RefreshPlayerLocationPins(); Pin(a,"map").frame.scripts.OnEnter()
	local s=a.locationPinState
	assert(s.tooltipIntro.text:find("\n\nParty of 3",1,true))
	Equal(s.partyRows[1].frame.points[1][2],s.tooltipIntro)
	Equal(s.tooltipLabel.points[1][2],s.tooltipIntro)
	local rosterHeight=8
	for _,item in ipairs(s.partyRows) do rosterHeight=rosterHeight+item.frame.height end
	Equal(s.tooltipLabel.points[1][5],-rosterHeight-14)
	Equal(#s.partyRows,3); assert(s.partyRows[1].label.text:find("|cff40c7ebLeader-Realm|r",1,true))
	assert(s.partyRows[1].crown.shown and not s.partyRows[2].crown.shown)
	Near(s.partyRows[1].dot.color[2],0.78039215686275)
	Equal(s.partyRows[1].crown.texture,Pin(a,"map").partyCrown.texture)
	local allocated=#a.regions
	info.size=6; a:RefreshPlayerLocationPins()
	assert(s.partyRows[1].frame.shown and not s.partyRows[2].frame.shown and not s.partyRows[3].frame.shown)
	Equal(#a.regions,allocated)
	info.size=3; info.members=nil; a:RefreshPlayerLocationPins()
	assert(s.tooltipIntro.text:find("Loading party members",1,true)); assert(s.partyRows[1].frame.shown)
	a.visualMembers={}; a:RefreshPlayerLocationPins()
	assert(not s.partyRows[1].frame.shown)
end)
Register("party highlights reset for recycled pins and restriction cleanup never mutates protected regions", function()
	local a=Fixture(); VisualParty(a)
	a.rows.map={Row("Friend-Realm"),Row("Leader-Realm",0.6,0.5)}; a:RefreshPlayerLocationPins()
	local pin=Pin(a,"map"); pin.frame.scripts.OnEnter()
	a.rows.map[1]=Row("Unrelated-Realm"); a:RefreshPlayerLocationPins()
	Equal(a.locationPinState.hovered,nil); assert(not pin.partyOutline.shown); Near(pin.frame.alpha,1)
	Pin(a,"map",2).frame.scripts.OnEnter(); a.blocked=true; a:RefreshPlayerLocationPins()
	assert(not a.locationPinState.tooltip.shown)
	a.blocked=false; a:RefreshPlayerLocationPins()
	assert(not Pin(a,"map",2).partyCrown.shown); Near(pin.frame.alpha,1)
end)

Register("party tooltip reserves aligned QT icon slots and updates recognition on reused rows", function()
	local a = Fixture()
	local info = VisualParty(a)
	a.API.GetTime = function() return 100 end
	function a:GetPlayerFullName() return "Third-Realm" end
	function a:NormalizeMemberName(name) return name end
	a.qtPlayerPresenceState = { peers = { ["Leader-Realm"] = 90 } }
	a.rows.map = { Row("Friend-Realm") }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	local rows = a.locationPinState.partyRows
	assert(rows[1].qtIcon.shown and not rows[2].qtIcon.shown and rows[3].qtIcon.shown)
	Equal(rows[1].qtIcon.texture, a.NAMEPLATE_PLAYER_ICON_TEXTURE)
	for _, row in ipairs(rows) do
		Equal(row.dot.points[1][2], rows[1].dot.points[1][2])
		Equal(row.label.points[1][2], rows[1].label.points[1][2])
	end
	local allocated = #a.regions
	a.qtPlayerPresenceState.peers["Leader-Realm"] = nil
	a.qtPlayerPresenceState.peers["Friend-Realm"] = 100
	info.members[3] = { name = "Other-Realm", classFile = "MAGE" }
	a:RefreshPlayerLocationPins()
	assert(not rows[1].qtIcon.shown and rows[2].qtIcon.shown and not rows[3].qtIcon.shown)
	assert(rows[1].crown.shown)
	Equal(#a.regions, allocated)
	local chat = Frame(a)
	function a:GetChatLogTooltipCursorPosition() return 200, 100 end
	a.playerLocationState = { peers = { ["Friend-Realm"] = a.rows.map[1] } }
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm"))
	local chatRows = a.chatLogPlayerTooltipState.partyRows
	assert(not chatRows[1].qtIcon.shown and chatRows[2].qtIcon.shown and not chatRows[3].qtIcon.shown)
end)

Register("nearby stream animation moves only owned minimap pins and respects foreign frame guards", function()
	local a = Fixture()
	a.now = 100
	a.API.GetTime = function() return a.now end
	a.db = { profile = { showPlayerLocations = true, sharePlayerLocation = true } }
	local row = Row(nil, 0.5, 0.5)
	row.receivedAt, row.mask = 100, 3
	a.playerLocationState = { peers = { [row.name] = row } }
	a.rows.map, a.rows.minimap = {row}, {row}
	a.nearbyStreamState = { wanted = { [row.name] = { sample = {
		mapID = 1, x = 0.54, y = 0.5, fromX = 0.5, fromY = 0.5, at = 100, duration = 1,
	} } } }
	a:RefreshPlayerLocationPins()
	local pin, mapPin = Pin(a, "minimap"), Pin(a, "map")
	local frames, mapWrites, miniWrites = #a.frames, mapPin.frame.writes, pin.frame.writes
	a.now = 100.5
	a:RefreshNearbyStreamPins()
	Equal(#a.frames, frames)
	Equal(mapPin.frame.writes, mapWrites)
	assert(pin.frame.writes > miniWrites)
	Near(pin.frame.points[#pin.frame.points][4], 120)
	Near(pin.frame.points[#pin.frame.points][5], -100)
	a.miniParent.forbidden = true
	a:RefreshNearbyStreamPins()
	Equal(a.invalidCalls or 0, 0)
	a.miniParent.forbidden = false
	a.blocked = true
	a:RefreshNearbyStreamPins()
	Equal(a.invalidCalls or 0, 0)
	Equal(a.locationPinState.surfaces.minimap.frame.shown, false)
end)

Register("map and chat tooltip intro use native localized race and class labels", function()
	local a = Fixture()
	a.now = 100
	a.API.GetTime = function() return a.now end
	a.API.GetLocalizedRaceName = function(id) return id == 3 and "Dwarf" or nil end
	a.API.GetLocalizedClassName = function(token) return token == "MAGE" and "Mage" or nil end
	local row = Row()
	row.race, row.className = "Zwerg", "Magier"
	a.nearbyStreamState = { capabilities = { [row.name] = { receivedAt = 100, raceID = 3 } }, wanted = {} }
	a.rows.map = { row }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	assert(a.locationPinState.tooltipIntro.text:find("Dwarf", 1, true))
	assert(a.locationPinState.tooltipIntro.text:find("Mage", 1, true))
	assert(not a.locationPinState.tooltipIntro.text:find("Zwerg", 1, true))
end)

Register("client locale paints quest hover labels and local native title", function()
	assert(QuestTogether.localizationTestLocale == nil)
	local locale = QuestTogether:GetEventLocale()
	local function T(key) return QuestTogether.TranslateForLocale(key, locale) end
	local a = Fixture()
	a.db = { global = {} }
	function a:GetPlayerTracker() return {} end
	function a:GetQuestSnapshot() return nil end
	function a:IsWorkBlocked() return self.blocked == true end
	a.API.GetLocalizedQuestTitle = function() return "Local title " .. locale end
	function a:GetQuestStatusLabel() return "Not Started" end
	function a:GetQuestShareableStatusLabel() return "Unknown" end
	function a:GetChatLogTooltipCursorPosition() return 100, 200 end
	function a:RegisterChatLogHoverCallbacks(enter, leave) self.enter, self.leave = enter, leave; return true end
	a:InitializeChatLogPlayerTooltips()
	local chat = Frame(a, a.tooltipParent)
	a.enter(nil, chat, "questtogetherquest:42", "|Hquesttogetherquest:42|h[Foreign title]|h")
	local state = a.chatLogPlayerTooltipState
	assert(state.tooltip.shown)
	assert(state.tooltipTitle.text:find("Local title " .. locale, 1, true))
	assert(state.tooltipLabel.text:find(T("Your quest status") .. ": " .. T("Not Started"), 1, true))
	assert(state.tooltipLabel.text:find(T("Shareable") .. ": " .. T("Unknown"), 1, true))
	a.leave()
	Equal(state.tooltip.shown, false)
end, { locale = "client" })

Register("hover refresh queries only on entry and incoming details update only the current tooltip", function()
	local a = Fixture()
	a.requests = {}
	function a:RequestPlayerDetails(name) self.requests[#self.requests + 1] = name end
	function a:GetChatLogTooltipCursorPosition() return 200, 100 end
	a.API = { GetTime = function() return 100 end }
	local row = Row("Friend-Realm")
	a.rows.map = { row }
	a.playerLocationState = { peers = { [row.name] = row } }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	Equal(#a.requests, 1)
	for _ = 1, 10 do a:RefreshPlayerLocationPins() end
	Equal(#a.requests, 1)
	local chat = Frame(a)
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm"))
	Equal(#a.requests, 2)
	a.playerDetailsState = { identities = { [row.name] = { receivedAt = 100, level = 42, classFile = "MAGE", race = "Dwarf", faction = "Alliance" } } }
	a:UpdateChatLogPlayerTooltip()
	assert(a.chatLogPlayerTooltipState.tooltipIntro.text:find("42", 1, true))
	Equal(#a.requests, 2)
	a:HideChatLogPlayerTooltip()
	a:UpdateChatLogPlayerTooltip()
	Equal(a.chatLogPlayerTooltipState.tooltip.shown, false)
end)
