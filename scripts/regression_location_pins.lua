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
	function frame:IsVisible()
		return self:IsShown() and (not self.parent or self.parent:IsVisible())
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
	function frame:CreateTexture(_, layer)
		self:Check()
		local region = Frame(addon, self, "Texture")
		region.layer = layer
		addon.regions[#addon.regions + 1] = region
		return region
	end
	function frame:CreateLine(_, layer)
		self:Check()
		local region = Frame(addon, self, "Line")
		region.layer = layer
		addon.regions[#addon.regions + 1] = region
		return region
	end
	function frame:SetStartPoint(...)
		self:Check()
		self.startPoint = { ... }
	end
	function frame:SetEndPoint(...)
		self:Check()
		self.endPoint = { ... }
	end
	function frame:SetThickness(value)
		self:Check()
		self.thickness = value
	end
	function frame:EnableMouseWheel(value)
		self:Check()
		self.mouseWheel = value
	end
	function frame:EnableMouse(value)
		self:Check()
		self.mouseEnabled = value
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
	function frame:GetStringWidth()
		self:CheckRead()
		local text = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		local widest = 0
		for line in (text .. "\n"):gmatch("([^\n]*)\n") do
			widest = math.max(widest, #line * 7)
		end
		return widest
	end
	function frame:GetStringHeight()
		self:CheckRead()
		if addon.measureText then
			local text = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			local columns = self.width and self.width > 0 and math.max(1, math.floor(self.width / 7)) or math.huge
			local lines = 0
			for line in (text .. "\n"):gmatch("([^\n]*)\n") do
				lines = lines + math.max(1, math.ceil(#line / columns))
			end
			return math.max(1, lines) * 12
		end
		return 96
	end
	function frame:SetColorTexture(r, g, b, a)
		self:Check()
		self.color = { r, g, b, a }
	end
	function frame:SetVertexColor(...)
		self:Check()
		self.vertexColor = { ... }
	end
	function frame:SetTextColor(...)
		self:Check()
		self.textColor = { ... }
	end
	function frame:SetJustifyV(value)
		self:Check()
		self.justifyV = value
	end
	function frame:SetTexture(value)
		self:Check()
		self.texture = value
	end
	function frame:SetTexCoord(...)
		self:Check()
		self.texCoord = { ... }
	end
	function frame:SetAlpha(value)
		self:Check()
		self.alpha = value
	end
	for _, method in ipairs({
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
		receivedAt = 100,
		mask = 3,
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
		GetTime = function()
			return 100
		end,
		RegionalUniqueNamesEnabled = function()
			return a.forever == true
		end,
		IsWarModeFeatureEnabled = function()
			return a.warModeFeature
		end,
		IsWorldMapVisible = function()
			if a.mapParent:IsForbidden() then return true end
			return a.mapVisibleDuringTransition or (a.geometry.map ~= nil and a.mapParent:IsVisible())
		end,
		OpenPlayerLocationMap = function(mapID)
			a.openedMapID = mapID
			a.mapOpenCalls = (a.mapOpenCalls or 0) + 1
			a.geometry.map.mapID = mapID
			return true
		end,
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
		if self.worldUnavailable then
			return nil
		end
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
	function a:IsVerifiedDeveloper(name)
		return self.verifiedDeveloperName ~= nil and name == self.verifiedDeveloperName
	end
	function a:IsPlayerLocationHiddenForDeveloper()
		return false
	end
	function a:GetPlayerLocationClusterNavigationAction()
		return "expand"
	end
	function a:TryNavigatePlayerLocationCluster()
		return false
	end
	function a:GetPlayerLocationMapNavigationTarget(_, mapID)
		return mapID
	end
	function a:GetClassColorCode(class)
		return class == "MAGE" and "|cff40c7eb" or "|cffffffff"
	end
	function a:ShowChatLogSpeakerMenu(frame, name, firstAction)
		self.menus[#self.menus + 1] = { owner = frame, name = name, firstAction = firstAction }
		return true
	end
	function a:ShowLocationTargetButton(owner, name, isCurrent, onEnter, onLeave, onClick)
		self.targetHover = { owner = owner, name = name, isCurrent = isCurrent, onClick = onClick }
		return true
	end
	function a:HideLocationTargetButton()
		self.targetHover = nil
	end
	activeFixtures[#activeFixtures + 1] = a
	function a:CreateOwnedUICleanupFrame()
		return Frame(self)
	end

	return a
end

local function Pin(a, surface, index)
	return a.locationPinState.surfaces[surface].pins[index or 1]
end

local function FocusShade(a)
	local state = assert(a.mapOverlayFocusState, "missing map focus owner")
	local shade = assert(state.shade, "missing owned map shade")
	assert(shade:IsVisible(), "map focus shade must be visible")
	return shade
end

local function NoFocusShade(a)
	local state = rawget(a, "mapOverlayFocusState")
	assert(not state or not state.shade or not state.shade:IsVisible(), "map focus shade must be hidden")
end

local function FocusedAboveShade(a, focused, other)
	local shade = FocusShade(a)
	for _, pin in ipairs(focused or {}) do
		assert(pin.frame.level > shade.level, "focused marker must be above map shade")
		assert(pin.frame.parent.level > shade.level, "focused marker host must also be above map shade")
		Near(pin.frame.alpha, pin.baseAlpha or 1)
	end
	for _, pin in ipairs(other or {}) do
		assert(pin.frame.parent.level > shade.level, "marker host must be above map shade")
		assert(pin.frame.level > shade.level, "unrelated markers fade independently above map shade")
		local alpha = a.mapOverlayFocusState.active.kind == "hover" and 0.45 or 0.78
		Near(pin.frame.alpha, (pin.baseAlpha or 1) * alpha)
	end
	return shade
end

Register("location dot clicks keep minimap targeting separate from world map narrowing and secondary menus", function()
	local a = Fixture()
	a.now = 100
	a.API.GetTime = function() return a.now end
	a.rows.map, a.rows.minimap = { Row(), Row("Other-Realm", 0.8) }, { Row() }
	local function PlayerPin(name)
		for _, pin in ipairs(a.locationPinState.surfaces.map.pins) do
			if pin.name == name and pin.frame:IsVisible() then return pin end
		end
		error("missing visible player pin: " .. name)
	end
	a:RefreshPlayerLocationPins()
	local mini, map = Pin(a, "minimap"), Pin(a, "map")
	mini.frame.scripts.OnEnter()
	local hover = a.targetHover
	Equal(hover.name, "Friend-Realm")
	assert(hover.isCurrent())
	hover.onClick("LeftButton")
	Equal(#a.menus, 0)
	hover.onClick("RightButton")
	Equal(#a.menus, 1)
	Equal(a.playerMapSelection, nil)
	local observed
	function a:PopulateLocationTargetMenu(root, name, isCurrent)
		observed = { root = root, name = name, valid = isCurrent }
	end
	local root = {}
	a.menus[1].firstAction(root)
	Equal(observed.root, root)
	Equal(observed.name, hover.name)
	assert(observed.valid())
	a.rows.minimap = { Row("Replacement-Realm") }
	Equal(hover.isCurrent(), false)
	Equal(observed.valid(), false)
	function a:GetLocationPinMapPosition(row) return row.x, row.y end
	function a:GetPlayerLocationMapNavigationTarget(members, mapID)
		Equal(#members, 1)
		Equal(mapID, self.geometry.map.mapID)
		if self.navigationUnavailable then return nil end
		return 2
	end
	map.frame.scripts.OnClick(nil, "LeftButton")
	Equal(#a.menus, 1)
	Equal(a.openedMapID, 2)
	Equal(a.mapOpenCalls, 1)
	Equal(a.playerMapSelection.name, "Friend-Realm")
	Equal(a.playerMapSelection.expires, 160)
	assert(PlayerPin("Friend-Realm").selected)
	Near(PlayerPin("Friend-Realm").glow[1].color[2], 1)
	a.now = 105
	map.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.mapOpenCalls, 1)
	Equal(#a.menus, 2)
	Equal(a.menus[2].firstAction, nil)
	Equal(a.menus[2].owner, PlayerPin("Friend-Realm").frame)
	Equal(a.playerMapSelection.expires, 165)
	local selected = a.playerMapSelection
	a.now = 110
	PlayerPin("Other-Realm").frame.scripts.OnClick(nil, "RightButton")
	Equal(a.menus[3].name, "Other-Realm")
	Equal(a.playerMapSelection, selected)
	Equal(selected.expires, 165)
	a.now = 115
	PlayerPin("Friend-Realm").frame.scripts.OnClick(nil, "RightButton")
	Equal(a.menus[4].name, "Friend-Realm")
	Equal(a.playerMapSelection, selected)
	Equal(selected.expires, 165)
	a.now = 120
	PlayerPin("Other-Realm").frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.playerMapSelection.name, "Other-Realm")
	Equal(a.playerMapSelection.expires, 180)
	assert(PlayerPin("Other-Realm").selected and not PlayerPin("Friend-Realm").selected)
	assert(not PlayerPin("Friend-Realm").glow[1].shown)
	Equal(a.menus[5].name, "Other-Realm")
	Equal(a.menus[5].owner, PlayerPin("Other-Realm").frame)
	a.now = 130
	a.navigationUnavailable = true
	PlayerPin("Friend-Realm").frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.mapOpenCalls, 1)
	Equal(#a.menus, 5)
	Equal(a.playerMapSelection.name, "Friend-Realm")
	Equal(a.playerMapSelection.expires, 190)
	assert(PlayerPin("Friend-Realm").selected and not PlayerPin("Other-Realm").selected)
	a.now = 140
	PlayerPin("Other-Realm").frame.scripts.OnClick(nil, "RightButton")
	Equal(a.menus[6].name, "Other-Realm")
	Equal(a.playerMapSelection.name, "Friend-Realm")
	Equal(a.playerMapSelection.expires, 190)
	a.now = 189.999
	a:RefreshPlayerLocationPins()
	assert(PlayerPin("Friend-Realm").selected)
	a.now = 190
	a:RefreshPlayerLocationPins()
	Equal(a.playerMapSelection, nil)
	assert(not PlayerPin("Friend-Realm").selected)
	a:HidePlayerLocationPins()
	Equal(a.targetHover, nil)
end)

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

-- Full map-candidate and pooled-renderer capacity stress runs offline.
Register("location dots reuse a bounded pool and copy no state to native parents", function()
	local a = Fixture()
	for _, surface in ipairs({ "map", "minimap" }) do
		a.rows[surface] = {}
		for index = 1, 200 do
			a.rows[surface][index] = Row("Peer" .. index .. "-Realm")
			if surface == "map" then
				-- Sparse points exercise the full pin pool; crowded points now
				-- correctly share a cluster marker on the world map.
				a.rows[surface][index].x = 0.02 + (index - 1) % 25 * 0.04
				a.rows[surface][index].y = 0.04 + math.floor((index - 1) / 25) * 0.07
			end
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
end, { offline = true })

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

-- Full map-candidate and pooled-renderer capacity stress runs offline.
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
		Equal(projections, surface == "map" and 328 or 128)
		Equal(#a.locationPinState.surfaces[surface].pins, surface == "map" and 1 or 128)
		if surface == "map" then
			Equal(#Pin(a, surface).cluster.members, 200)
		else Equal(Pin(a, surface, 128).name, "Peer256-Realm") end
		local frames = #a.frames
		projections = 0
		assert(a:RefreshPlayerLocationPins())
		Equal(projections, surface == "map" and 328 or 128)
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
		if surface == "minimap" then Equal(Pin(a, surface, 2).frame.shown, false) end
		Equal(#a.locationPinState.surfaces[surface].pins, surface == "map" and 1 or 128)
		Equal(#a.frames, frames)
	end
end, { offline = true })

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
	pin.frame.scripts.OnClick({}, "RightButton")
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
	for _, target in ipairs({ 1, 2 }) do
		for _, change in ipairs({ "identity", "position", "ignored", "map", "canvas", "hidden", "disabled", "restricted", "dataOff" }) do
			local b = Fixture()
			local row = Row()
			b.rows.map = { row }
			function b:GetPlayerLocationMapNavigationTarget()
				if change == "identity" then self.rows.map = { Row("Replacement-Realm") }
				elseif change == "position" then row.x = 0.6
				elseif change == "ignored" then self.ignored = row.name
				elseif change == "map" then self.geometry.map.mapID = 3
				elseif change == "canvas" then self.geometry.map.canvasWidth = 2000
				elseif change == "hidden" then self.mapParent:Hide()
				elseif change == "disabled" then self.isEnabled = false
				elseif change == "restricted" then self.blocked = true
				else function self:IsQuestTogetherMapDataShown() return false end end
				return target
			end
			b:RefreshPlayerLocationPins()
			Pin(b, "map").frame.scripts.OnClick(nil, "LeftButton")
			Equal(b.openedMapID, nil)
			Equal(#b.menus, 0)
			Equal(b.playerMapSelection, nil)
		end
	end
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

Register("remote dot and chat tooltips show fresh party size without tracked quest counts", function()
	local a = Fixture()
	local now = 100
	a.API.GetTime = function()
		return now
	end
	a.API.GetRealmName = function()
		return "Realm"
	end
	function a:GetPlayerFullName()
		return "Me-Realm"
	end
	function a:GetChatLogTooltipCursorPosition()
		return 100, 200
	end
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
	function state.tooltipTitle:GetStringHeight()
		self:CheckRead()
		return self.testHeight or 18
	end
	row.faction, row.race, row.className, row.classFile, row.level = "Horde", "Troll", "Warlock", "WARLOCK", 13
	pin.frame.scripts.OnEnter({})
	Equal(#a.regions, regions)
	Equal(state.tooltipFaction.texture, "Interface\\TargetingFrame\\UI-PVP-Horde")
	Equal(state.tooltipFaction.width, 36)
	Equal(state.tooltipFaction.height, 36)
	Equal(state.tooltipTitle.width, state.tooltip.width - 28 - 44)
	assert(state.tooltipFaction.shown)
	Equal(state.tooltipDivider.points[1][5], -6)
	Equal(state.tooltipIntro.points[1][5], -16)
	Equal(state.tooltipDivider.width, state.tooltip.width - 28)
	state.tooltipTitle.testHeight = 48
	pin.frame.scripts.OnEnter({})
	Equal(state.tooltipDivider.points[1][5], -6)
	assert(state.tooltipIntro.text:find("Level 13 Troll ", 1, true))
	assert(state.tooltipIntro.text:find(a:GetClassColorCode("WARLOCK") .. "Warlock|r", 1, true))
	row.faction = "Unknown"
	pin.frame.scripts.OnEnter({})
	Equal(state.tooltipFaction.shown, false)
	Equal(state.tooltipTitle.width, state.tooltip.width - 28)
	Equal(state.tooltipDivider.width, state.tooltip.width - 28)
end)

Register("own chat tooltip reads live super tracking without a received peer record or sharing consent", function()
	local a = Fixture()
	local consentChecks = 0
	local id = 42
	a.API.GetRealmName = function()
		return "Realm"
	end
	a.API.GetActiveTrackedQuestID = function()
		return id
	end
	function a:GetPlayerFullName()
		return "Me-Realm"
	end
	function a:GetAddonVersion()
		return "5.16.7"
	end
	local count, size = 8, 0
	function a:GetMonitoredQuestCount()
		return count
	end
	a.API.GetPartyJoinInfo = function()
		return size > 0, false, size
	end
	function a:GetOption(key)
		return key == "lookingForQuestPartners"
	end
	function a:ReadLocalPlayerLocation()
		return Row("Me-Realm")
	end
	function a:CanPublishPlayerLocation()
		consentChecks = consentChecks + 1
		return false
	end
	function a:GetLocalizedQuestTitle(questID)
		return "Local quest " .. questID
	end
	function a:GetChatLogTooltipCursorPosition()
		return 100, 100
	end
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
	Equal(consentChecks, 0)
end)

Register("quest hover shows local status and objectives at the cursor and clears between link kinds", function()
	local a = Fixture()
	local printCalls = 0
	a.db = { global = {} }
	local tracker = { [42] = { objectives = { "Wolves slain: 3/8", "|Hbad|hText|h" } } }
	function a:GetPlayerTracker()
		return tracker
	end
	function a:GetQuestTitle(id)
		return "Quest " .. id
	end
	local status, shareable = "In Progress", "Yes"
	function a:GetQuestStatusLabel()
		return status
	end
	function a:GetQuestShareableStatusLabel()
		return shareable
	end
	function a:GetChatLogTooltipCursorPosition()
		return 100, 200
	end
	function a:PrintQuestStatus()
		printCalls = printCalls + 1
	end
	function a:RegisterChatLogHoverCallbacks(enter, leave)
		self.enter, self.leave = enter, leave
		return true
	end
	a:InitializeChatLogPlayerTooltips()
	local chat = Frame(a, a.tooltipParent)
	a.enter(nil, chat, "questtogetherquest:42", "|Hquesttogetherquest:42|h[Wolf Hunt]|h")
	local state = a.chatLogPlayerTooltipState
	assert(state.tooltip.shown)
	assert(state.tooltipTitle.text:find("Wolf Hunt", 1, true))
	for _, text in ipairs({
		"Your quest status: In Progress",
		"Shareable: Yes",
		"Quest ID: 42",
		"Wolves slain: 3/8",
		"||Hbad||hText||h",
	}) do
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
	for _, link in ipairs({
		"item:42",
		"questtogetherquest:0",
		"questtogetherquest:-1",
		"questtogetherquest:abc",
		"questtogetherquest:1.5",
		"questtogetherquest:1e999",
	}) do
		Equal(a:ShowChatLogPlayerTooltip(chat, link), false)
	end
	a.enter(nil, chat, "questtogetherquest:42", "[Wolf Hunt]")
	a.leave()
	Equal(state.tooltip.shown, false)
	Equal(printCalls, 0)
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
	NoFocusShade(a)
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
		assert(a:GetOwnedUICleanupState().pending[surface.frame] and a:GetOwnedUICleanupState().driver.scripts.OnUpdate)
		a:GetOwnedUICleanupState().driver.scripts.OnUpdate({}, 0.5)
		Equal(surface.frame.writes, writes)
		a.mapParent[boundary] = false
		a:GetOwnedUICleanupState().driver.scripts.OnUpdate({}, 0.5)
		Equal(surface.frame.shown, false)
		Equal(next(a:GetOwnedUICleanupState().pending), nil)
		Equal(a:GetOwnedUICleanupState().driver.scripts.OnUpdate, nil)
		a.isEnabled = true
		assert(a:RefreshPlayerLocationPins())
		a.mapParent[boundary] = true
		a:HidePlayerLocationPins()
		local staleWake = a:GetOwnedUICleanupState().driver.scripts.OnUpdate
		a.mapParent[boundary] = false
		assert(a:RefreshPlayerLocationPins())
		staleWake({}, 0.5)
		assert(surface.frame.shown)
		Equal(a:GetOwnedUICleanupState().pending[surface.frame], nil)
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

Register("removed location row retires its quarantined tooltip after access returns", function()
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
	assert(a:GetOwnedUICleanupState().pending[state.tooltip])
	state.tooltip.forbidden = false
	a:GetOwnedUICleanupState().driver.scripts.OnUpdate({}, 0.5)
	Equal(state.tooltip.shown, false)
	Equal(next(a:GetOwnedUICleanupState().pending), nil)
end)

Register("location hover refreshes explicit quest partner status without replacing the pin", function()
	local a = Fixture()
	a.now = 100
	a.API = {
		GetTime = function()
			return a.now
		end,
		GetRealmName = function()
			return "Realm"
		end,
		RegionalUniqueNamesEnabled = function()
			return false
		end,
	}
	function a:GetPlayerFullName()
		return "Me-Realm"
	end
	a.qtPlayerPresenceState = {
		peers = { ["Friend-Realm"] = 100 },
		questPartners = { ["Friend-Realm"] = { receivedAt = 100, looking = true } },
	}
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
	a.API.GetTime = function()
		return a.now
	end
	a.API.GetRealmName = function()
		return "Realm"
	end
	function a:GetPlayerFullName()
		return "Me-Realm"
	end
	a.qtPlayerPresenceState = { peers = {}, questPartners = {} }
	for _, surface in ipairs({ "map", "minimap" }) do
		a.rows[surface] = { Row() }
	end
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
			assert(glow.color[4] < 1)
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
		for _, glow in ipairs(Pin(a, surface).glow) do
			assert(not glow.shown)
		end
	end
	a.qtPlayerPresenceState.questPartners["Friend-Realm"].receivedAt = 165
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do
		a.rows[surface] = { Row("Other-Realm") }
	end
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do
		Equal(Pin(a, surface).frame.width, 12)
		Equal(Pin(a, surface).border.color[2], 0)
		for _, glow in ipairs(Pin(a, surface).glow) do
			assert(not glow.shown)
		end
	end
	Equal(#a.frames, frames)
	Equal(#a.regions, regions)
end)

Register("developer diagnostic dots use red halos and reset color when reused for partners", function()
	local a = Fixture()
	for _, surface in ipairs({ "map", "minimap" }) do
		local row = Row()
		row.developerOnly, row.publicLocationHidden = true, true
		a.rows[surface] = { row }
	end
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do
		local pin = Pin(a, surface)
		Equal(pin.frame.width, 16)
		for _, glow in ipairs(pin.glow) do
			assert(glow.shown)
			Near(glow.color[1], 1)
			Near(glow.color[2], 0.12)
			Near(glow.color[3], 0.12)
		end
		a.rows[surface][1].publicLocationHidden = false
		a.rows[surface][1].lookingForQuestPartners = true
	end
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do
		local pin = Pin(a, surface)
		for _, glow in ipairs(pin.glow) do
			assert(glow.shown)
			Near(glow.color[2], 0.8)
			Near(glow.color[3], 0.15)
		end
		a.rows[surface] = { Row("Other-Realm") }
	end
	assert(a:RefreshPlayerLocationPins())
	for _, surface in ipairs({ "map", "minimap" }) do
		for _, glow in ipairs(Pin(a, surface).glow) do
			assert(not glow.shown)
		end
	end
end)

Register("quest partner dot projection clips the complete larger glow on both maps", function()
	local a = Fixture()
	function a:IsPlayerLookingForQuestPartners()
		return self.looking == true
	end
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
	function a:IsPlayerLookingForQuestPartners()
		return self.looking == true
	end
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
	function a:GetPlayerAddonVersion()
		return "6.0.3"
	end
	a.now = 500
	a.API.GetTime = function()
		return a.now
	end
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
		a.API.GetTime = function()
			return a.now
		end
		a.API.GetRealmName = function()
			return "Realm"
		end
		function a:GetPlayerFullName()
			return "Me-Realm"
		end
		function a:GetLocalizedQuestTitle(id)
			Equal(id, 42)
			return self.title
		end
		a.title = "Une quête |cffff0000test"
		a.qtPlayerPresenceState = {
			peers = {},
			questPartners = {
				["Friend-Realm"] = { session = "10-1234", sequence = 1, receivedAt = 100, looking = true },
			},
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

-- Full map-candidate and pooled-renderer capacity stress runs offline.
Register("crowded maps prioritize closest players independently of names and map pan", function()
	for _, surface in ipairs({ "map", "minimap" }) do
		local a = Fixture()
		local rows = {}
		for i = 1, 128 do
			rows[i] = Row(string.format("A%03d-Realm", i), 0.55, 0.5)
		end
		rows[129] = Row("ZClosest-Realm", 0.501, 0.5)
		a.rows[surface] = rows
		assert(a:RefreshPlayerLocationPins())
		Equal(Pin(a, surface).name, "ZClosest-Realm")
		Equal(#a.locationPinState.surfaces[surface].pins, surface == "map" and 2 or 128)
		if surface == "map" then Equal(#Pin(a, surface, 2).cluster.members, 128)
		else Equal(Pin(a, surface, 128).name, "A127-Realm") end
		-- Moving the player, without new peer messages, changes priority.
		a.playerWest = 450
		a.geometry.minimap.west = 450
		assert(a:RefreshPlayerLocationPins())
		if surface == "map" then
			Equal(Pin(a, surface).cluster.members[1].name, "A001-Realm")
			Equal(Pin(a, surface).cluster.members[128].name, "A128-Realm")
		else
			Equal(Pin(a, surface).name, "A001-Realm")
			Equal(Pin(a, surface, 128).name, "A128-Realm")
		end
		Equal(rows[129].name, "ZClosest-Realm", "source ordering must not be mutated")
	end
end, { offline = true })

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
	function a:GetChatLogTooltipCursorPosition()
		return 200, 100
	end
	a.playerLocationState = { peers = { [row.name] = row } }
	a.rows.map = { row }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	local expected = a.locationPinState.tooltipLabel.text
	-- Reproduce a live client whose real addon has already installed callbacks.
	-- Private fixture initialization must not inherit that instance's state.
	setmetatable(a, {
		__index = function(_, key)
			if key == "chatLogHoverCallbacksInstalled" then
				return true
			end
			return QuestTogether[key]
		end,
	})
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
	assert(state.tooltip.width >= 188 and state.tooltip.width <= 300)
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
	local info = {
		key = "Leader:123",
		size = 3,
		leader = "Leader-Realm",
		leaderClass = "MAGE",
		knownMembers = {
			{ name = "Leader-Realm", classFile = "MAGE" },
			{ name = "Friend-Realm", classFile = "WARRIOR" },
		},
		members = {
			{ name = "Leader-Realm", classFile = "MAGE" },
			{ name = "Friend-Realm", classFile = "WARRIOR" },
			{ name = "Third-Realm", classFile = "MAGE" },
		},
	}
	a.visualMembers = { ["Leader-Realm"] = info, ["Friend-Realm"] = info, ["Third-Realm"] = info }
	function a:GetPlayerPartyVisualInfo(name)
		return self.visualMembers[name]
	end
	function a:RequestPartyVisualRoster()
		self.rosterRequests = (self.rosterRequests or 0) + 1
	end
	return info
end
Register("solo and party world map hovers shade unrelated markers while minimap hover stays local", function()
	local a = Fixture()
	VisualParty(a)
	local getOption = a.GetOption
	function a:GetOption(key)
		if key == "clusterPlayerLocations" then return false end
		return getOption(self, key)
	end
	a.geometry.map.pinFrameLevel = 2300
	a.rows.map = { Row("Friend-Realm"), Row("Leader-Realm", 0.6, 0.5), Row("Unrelated-Realm", 0.601, 0.5) }
	a.rows.minimap = { Row("Third-Realm"), Row("Unrelated-Realm") }
	function a:IsPlayerLookingForQuestPartners(name)
		return name == "Leader-Realm"
	end
	assert(a:RefreshPlayerLocationPins())
	local member, leader, other, mini = Pin(a, "map", 1), Pin(a, "map", 2), Pin(a, "map", 3), Pin(a, "minimap")
	assert(member.partyBadge.shown and leader.partyBadge.shown and not other.partyBadge.shown)
	assert(not leader.partyCrown.shown and not member.partyOutline.shown)
	NoFocusShade(a)
	member.frame.scripts.OnEnter()
	assert(member.partyOutline.shown and leader.partyOutline.shown and mini.partyOutline.shown)
	assert(leader.partyCrown.shown and not member.partyCrown.shown and not other.partyCrown.shown)
	local shade = FocusedAboveShade(a, { member, leader }, { other })
	assert(shade.level > 2300)
	assert(leader.glow[1].shown)
	member.frame.scripts.OnLeave()
	assert(not leader.partyCrown.shown and not mini.partyOutline.shown)
	NoFocusShade(a)
	assert(leader.glow[1].shown)
	-- Clustering off leaves overlapping players individually focusable, even
	-- before the hovered player has any party metadata.
	other.frame.scripts.OnEnter()
	a:RefreshPlayerLocationPins()
	local otherMini = Pin(a, "minimap", 2)
	FocusedAboveShade(a, { other }, { member, leader })
	Near(otherMini.frame.alpha, 1)
	Near(mini.frame.alpha, 0.45)
	assert(not other.partyOutline.shown and not other.partyCrown.shown)
	member.frame.scripts.OnEnter()
	other.frame.scripts.OnLeave()
	FocusedAboveShade(a, { member, leader }, { other })
	otherMini.frame.scripts.OnEnter()
	member.frame.scripts.OnLeave()
	NoFocusShade(a)
	Near(otherMini.frame.alpha, 1)
	Near(mini.frame.alpha, 0.45)
	for _, pin in ipairs({ member, leader, other }) do Near(pin.frame.alpha, 1) end
	otherMini.frame.scripts.OnLeave()
	NoFocusShade(a)
	for _, pin in ipairs({ member, leader, other, mini, otherMini }) do Near(pin.frame.alpha, 1) end
	Equal(a.mapParent.writes, 0)
end)

Register("party tooltip lists class colored members crowned leader first and only the leader above five", function()
	local a = Fixture()
	local info = VisualParty(a)
	a.rows.map = { Row("Friend-Realm") }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	local s = a.locationPinState
	assert(s.tooltipIntro.text:find("\n\nParty of 3", 1, true))
	Equal(s.partyRows[1].frame.points[1][2], s.tooltipIntro)
	Equal(s.tooltipLabel.points[1][2], s.tooltipIntro)
	local rosterHeight = 8
	for _, item in ipairs(s.partyRows) do
		rosterHeight = rosterHeight + item.frame.height
	end
	Equal(s.tooltipLabel.points[1][5], -rosterHeight - 14)
	Equal(#s.partyRows, 3)
	assert(s.partyRows[1].label.text:find("|cff40c7ebLeader-Realm|r", 1, true))
	assert(s.partyRows[1].crown.shown and not s.partyRows[2].crown.shown)
	Near(s.partyRows[1].dot.color[2], 0.78039215686275)
	Equal(s.partyRows[1].crown.texture, Pin(a, "map").partyCrown.texture)
	local allocated = #a.regions
	info.size = 6
	a:RefreshPlayerLocationPins()
	assert(s.partyRows[1].frame.shown and not s.partyRows[2].frame.shown and not s.partyRows[3].frame.shown)
	Equal(#a.regions, allocated)
	info.size = 3
	info.members = nil
	a:RefreshPlayerLocationPins()
	assert(s.tooltipIntro.text:find("Loading party members", 1, true))
	assert(s.partyRows[1].frame.shown)
	assert(s.partyRows[2].frame.shown and s.partyRows[2].label.text:find("Friend-Realm", 1, true))
	assert(not s.partyRows[2].crown.shown and not s.partyRows[3].frame.shown)
	Equal(info.members, nil) -- partial display must not become an authoritative roster
	a.visualMembers = {}
	a:RefreshPlayerLocationPins()
	assert(not s.partyRows[1].frame.shown and not s.partyRows[2].frame.shown)
end)
Register("player hover shade retires for recycled pins map changes and guarded lifecycle cleanup", function()
	for _, change in ipairs({ "recycled", "map", "geometry", "hidden", "restricted", "forbidden", "protected", "disabled" }) do
		local a = Fixture()
		VisualParty(a)
		a.rows.map = { Row("Friend-Realm"), Row("Leader-Realm", 0.6, 0.5) }
		a:RefreshPlayerLocationPins()
		local pin = Pin(a, "map")
		pin.frame.scripts.OnEnter()
		local shade = FocusShade(a)
		if change == "recycled" then a.rows.map[1] = Row("Unrelated-Realm")
		elseif change == "map" then
			a.geometry.map.mapID = 2
			function a:GetLocationPinMapPosition(row) return row.x, row.y end
		elseif change == "geometry" then a.geometry.map.canvasLeft = -1
		elseif change == "hidden" then a.mapParent:Hide()
		elseif change == "restricted" then a.blocked = true
		elseif change == "forbidden" then a.mapParent.forbidden = true
		elseif change == "protected" then a.mapParent.protected = true
		else a.isEnabled = false end
		a:RefreshPlayerLocationPins()
		Equal(a.locationPinState.hovered, nil)
		Equal(a.mapOverlayFocusState.active, nil)
		if change ~= "forbidden" and change ~= "protected" then NoFocusShade(a) end
		a.blocked, a.isEnabled, a.mapParent.forbidden, a.mapParent.protected = false, true, false, false
		a.mapParent:Show()
		a.geometry.map.mapID, a.geometry.map.canvasLeft = 1, 0
		a:RefreshPlayerLocationPins()
		NoFocusShade(a)
		assert(not Pin(a, "map", 2).partyCrown.shown)
		Near(pin.frame.alpha, 1)
		Pin(a, "map", 2).frame.scripts.OnEnter()
		Equal(FocusShade(a), shade)
		Pin(a, "map", 2).frame.scripts.OnLeave()
		NoFocusShade(a)
	end
end)

Register("party tooltip reserves aligned QT icon slots and updates recognition on reused rows", function()
	local a = Fixture()
	local info = VisualParty(a)
	local now = 100
	a.API.GetTime = function()
		return now
	end
	function a:GetPlayerFullName()
		return "Third-Realm"
	end
	function a:NormalizeMemberName(name)
		return name
	end
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
	local glow = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherPartnerIcon"
	a.qtPlayerPresenceState.questPartners = { ["Leader-Realm"] = { looking = true, receivedAt = 99, lifetime = 10 } }
	a:RefreshPlayerLocationPins()
	Equal(rows[1].qtIcon.texture, glow)
	Equal(rows[3].qtIcon.texture, a.NAMEPLATE_PLAYER_ICON_TEXTURE)
	now = 111
	a:RefreshPlayerLocationPins()
	Equal(rows[1].qtIcon.texture, a.NAMEPLATE_PLAYER_ICON_TEXTURE)
	a.qtPlayerPresenceState.peers["Leader-Realm"] = nil
	a.qtPlayerPresenceState.peers["Friend-Realm"] = 100
	a.qtPlayerPresenceState.questPartners["Friend-Realm"] = { looking = true, receivedAt = 111 }
	info.members[3] = { name = "Other-Realm", classFile = "MAGE" }
	a:RefreshPlayerLocationPins()
	assert(not rows[1].qtIcon.shown and rows[2].qtIcon.shown and not rows[3].qtIcon.shown)
	Equal(rows[2].qtIcon.texture, glow)
	assert(rows[1].crown.shown)
	Equal(#a.regions, allocated)
	local chat = Frame(a)
	function a:GetChatLogTooltipCursorPosition()
		return 200, 100
	end
	a.playerLocationState = { peers = { ["Friend-Realm"] = a.rows.map[1] } }
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm"))
	local chatRows = a.chatLogPlayerTooltipState.partyRows
	assert(not chatRows[1].qtIcon.shown and chatRows[2].qtIcon.shown and not chatRows[3].qtIcon.shown)
	Equal(chatRows[2].qtIcon.texture, glow)
	a.qtPlayerPresenceState.questPartners["Friend-Realm"].looking = false
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm"))
	Equal(chatRows[2].qtIcon.texture, a.NAMEPLATE_PLAYER_ICON_TEXTURE)
end)

Register("restored map evidence immediately identifies both roster members and active hovers follow new evidence and expiry", function()
	local a = Fixture()
	VisualParty(a)
	a.now, a.requests = 100, {}
	a.API.GetTime = function() return a.now end
	a.API.GetRealmName = function() return "Realm" end
	a.activeCharacterKey = "Viewer-Realm"
	function a:GetPlayerFullName() return "Viewer-Realm" end
	function a:GetAnnouncementServerTime() return 1700000100 end
	function a:IsGroupedSender() return false end
	function a:GetChatLogTooltipCursorPosition() return 200, 100 end
	function a:RequestPlayerDetails(name) self.requests[#self.requests + 1] = name end
	function a:RequestPlayerPhaseComparison() end
	function a:RefreshQTPlayerPlatePresence() end
	function a:RefreshQTPlayerPartnerIndicators() end
	a.GetVisiblePlayerLocations = QuestTogether.GetVisiblePlayerLocations
	a.db = { profile = a:DeepCopy(a.DEFAULTS.profile), global = { playerLocationCache = {
		version = 2, owner = a.activeCharacterKey, savedAt = 1700000100, rows = {
			{ name = "Friend-Realm", data = Row("Friend-Realm"), sampledAt = 1700000095, expiresAt = 1700000160 },
			{ name = "Leader-Realm", data = Row("Leader-Realm", 0.55), sampledAt = 1700000095, expiresAt = 1700000130 },
		},
	} } }
	a:RestorePlayerLocationCache()
	local original = a:GetFreshPlayerLocation("Friend-Realm")
	assert(original and original.cached and not a:IsKnownQTPlayer("Friend-Realm") and not a:IsKnownQTPlayer("Leader-Realm"))
	a:RefreshPlayerLocationPins()
	Equal(Pin(a, "map").name, "Friend-Realm")
	Equal(Pin(a, "map", 2).name, "Leader-Realm")
	local function Icons(state, leader)
		assert(state.partyRows[2].qtIcon.shown, "the visible restored Friend dot already proves QT use")
		Equal(state.partyRows[1].qtIcon.shown, leader)
		assert(not state.partyRows[3].qtIcon.shown, "third-hand membership alone cannot establish QT use")
	end
	Pin(a, "map").frame.scripts.OnEnter()
	Icons(a.locationPinState, true)
	Pin(a, "map").frame.scripts.OnLeave()
	Pin(a, "map", 2).frame.scripts.OnEnter()
	Icons(a.locationPinState, true)
	Pin(a, "map", 2).frame.scripts.OnLeave()
	Pin(a, "map").frame.scripts.OnEnter()
	assert(a:ShowChatLogPlayerTooltip(Frame(a), "questtogetherlog:Leader-Realm"))
	Icons(a.chatLogPlayerTooltipState, true)
	local requests = #a.requests
	assert(not a:IsKnownQTPlayer("Friend-Realm") and not a:IsKnownQTPlayer("Leader-Realm"))
	Equal(rawget(a, "qtPlayerPresenceState"), nil)
	a.now = 130
	a:RefreshPlayerLocationPins()
	a:UpdateChatLogPlayerTooltip()
	Icons(a.locationPinState, false)
	Icons(a.chatLogPlayerTooltipState, false)
	local observation = a:CreatePeerObservation("Leader-Realm", "LOC", { source = "snapshot", lifetime = 120 })
	assert(a:HandlePlayerLocationMessage(Row("Leader-Realm", 0.55), "Leader-Realm", observation))
	a:RefreshPlayerLocationPins()
	a:UpdateChatLogPlayerTooltip()
	Icons(a.locationPinState, true)
	Icons(a.chatLogPlayerTooltipState, true)
	assert(a:IsKnownQTPlayer("Leader-Realm"))
	Equal(#a.requests, requests, "refreshing evidence must not create new hover interests or requests")
	Equal(original.sampledAt, 95)
	Equal(original.receivedAt, 100)
	Equal(original.lifetime, 60)
end)

Register("display evidence rejects withdrawn expired ignored and departed cached peers without renewing recognition", function()
	local a = Fixture()
	a.now = 100
	a.API.GetTime = function() return a.now end
	a.API.GetRealmName = function() return "Realm" end
	function a:GetPlayerFullName() return "Viewer-Realm" end
	function a:RefreshQTPlayerPlatePresence() end
	function a:RefreshQTPlayerPartnerIndicators() end
	local name, row = "Friend-Realm", Row("Friend-Realm")
	row.cached, row.lifetime = true, 20
	a.playerLocationState = { peers = { [name] = row } }
	assert(a:BuildPlayerTooltipMember(row).usesQT)
	assert(a:HasQTPlayerDisplayEvidence(name))
	assert(not a:IsKnownQTPlayer(name))
	for _, change in ipairs({ "withdrawn", "expired", "future", "ignored", "disabled", "loggingOut" }) do
		row.mask, a.now, a.ignored, a.isEnabled, a.isLoggingOut = 3, 100, nil, true, false
		if change == "withdrawn" then row.mask = 0
		elseif change == "expired" then a.now = 120
		elseif change == "future" then a.now = 99
		elseif change == "ignored" then a.ignored = name
		elseif change == "disabled" then a.isEnabled = false
		else a.isLoggingOut = true end
		local member = a:BuildPlayerTooltipMember(row)
		assert(not member or not member.usesQT, change)
		assert(not a:HasQTPlayerDisplayEvidence(name), change)
	end
	row.mask, a.now, a.ignored, a.isEnabled, a.isLoggingOut = 3, 101, nil, true, false
	assert(a:RecordPeerDeparture(name, 101))
	-- Even an old cached copy still referenced by a view cannot cross a newer departure.
	a.playerLocationState.peers[name] = row
	assert(not a:BuildPlayerTooltipMember(row).usesQT)
	assert(not a:HasQTPlayerDisplayEvidence(name))
	assert(not a:IsKnownQTPlayer(name))
	a.IsPlayerLocationHiddenForDeveloper = QuestTogether.IsPlayerLocationHiddenForDeveloper
	a.now, a.isLocalDeveloper = 102, true
	a.developerPlayerData = { [name] = { developerOnly = true, publicLocationHidden = true, receivedAt = 102 } }
	assert(a:BuildPlayerTooltipMember(row).usesQT, "authorized fresh private map evidence also identifies its sender")
	assert(not a:IsKnownQTPlayer(name))
	a.isLocalDeveloper = false
	assert(not a:BuildPlayerTooltipMember(row).usesQT, "private evidence must not escape the authorized viewer")
	a.isLocalDeveloper, a.now = true, 222
	assert(not a:BuildPlayerTooltipMember(row).usesQT, "expired private evidence cannot retain the logo")
end)

Register("nearby stream animation moves only owned minimap pins and respects foreign frame guards", function()
	local a = Fixture()
	a.now = 100
	a.API.GetTime = function()
		return a.now
	end
	a.db = { profile = { showPlayerLocations = true, sharePlayerLocation = true } }
	local row = Row(nil, 0.5, 0.5)
	row.receivedAt, row.mask = 100, 3
	a.playerLocationState = { peers = { [row.name] = row } }
	a.rows.map, a.rows.minimap = { row }, { row }
	a.nearbyStreamState = {
		wanted = {
			[row.name] = {
				sample = {
					mapID = 1,
					x = 0.54,
					y = 0.5,
					fromX = 0.5,
					fromY = 0.5,
					at = 100,
					duration = 1,
				},
			},
		},
	}
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

Register("client locale paints quest hover labels and local native title", function()
	assert(QuestTogether.localizationTestLocale == nil)
	local locale = QuestTogether:GetEventLocale()
	local function T(key)
		return QuestTogether.TranslateForLocale(key, locale)
	end
	local a = Fixture()
	a.db = { global = {} }
	function a:GetPlayerTracker()
		return {}
	end
	function a:GetQuestSnapshot()
		return nil
	end
	function a:IsWorkBlocked()
		return self.blocked == true
	end
	a.API.GetLocalizedQuestTitle = function()
		return "Local title " .. locale
	end
	function a:GetQuestStatusLabel()
		return "Not Started"
	end
	function a:GetQuestShareableStatusLabel()
		return "Unknown"
	end
	function a:GetChatLogTooltipCursorPosition()
		return 100, 200
	end
	function a:RegisterChatLogHoverCallbacks(enter, leave)
		self.enter, self.leave = enter, leave
		return true
	end
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

Register(
	"hover interest deduplicates presentation refresh and incoming details update only the current tooltip",
	function()
		local a = Fixture()
		a.requests = {}
		function a:RequestPlayerDetails(name)
			self.requests[#self.requests + 1] = name
		end
		function a:GetChatLogTooltipCursorPosition()
			return 200, 100
		end
		a.API = {
			GetTime = function()
				return 100
			end,
		}
		local row = Row("Friend-Realm")
		a.rows.map = { row }
		a.playerLocationState = { peers = { [row.name] = row } }
		a:RefreshPlayerLocationPins()
		Pin(a, "map").frame.scripts.OnEnter()
		Equal(#a.requests, 1)
		for _ = 1, 10 do
			a:RefreshPlayerLocationPins()
		end
		Equal(#a.requests, 1)
		local chat = Frame(a)
		assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:Friend-Realm"))
		Equal(#a.requests, 2)
		a.playerDetailsState.identities = {
			[row.name] = { receivedAt = 100, level = 42, classFile = "MAGE", race = "Dwarf", faction = "Alliance" },
		}
		a:UpdateChatLogPlayerTooltip()
		assert(a.chatLogPlayerTooltipState.tooltipIntro.text:find("42", 1, true))
		Equal(#a.requests, 2)
		a:HideChatLogPlayerTooltip()
		a:UpdateChatLogPlayerTooltip()
		Equal(a.chatLogPlayerTooltipState.tooltip.shown, false)
	end
)

Register("player tooltip width fits content expands for party names and shrinks on reuse", function()
	local a = Fixture()
	a.API.GetRealmName = function()
		return "Realm"
	end
	a.API.GetTime = function()
		return 100
	end
	a.warModeFeature = false
	local party = { size = 0 }
	function a:GetPlayerPartyVisualInfo()
		return party
	end
	local row = Row("Ari-Realm")
	a.rows.map = { row }
	a:RefreshPlayerLocationPins()
	local pin = Pin(a, "map")
	pin.frame.scripts.OnEnter()
	local state = a.locationPinState
	local compact = state.tooltip.width
	assert(compact < 300)
	Equal(state.tooltipDivider.width, compact - 28)
	Equal(state.tooltipIntro.width, compact - 28)
	Equal(state.tooltipTitle.width + 44, compact - 28)
	row.name = string.rep("Long", 10) .. "-Realm"
	a:RefreshPlayerLocationPins()
	pin.frame.scripts.OnEnter()
	Equal(state.tooltip.width, 300)
	Equal(state.tooltipDivider.width, 272)
	row.name = "Ari-Realm"
	party = { key = "group", size = 2, leader = string.rep("LongLeaderName", 8),
		knownMembers = { { name = string.rep("LongLeaderName", 8), classFile = "MAGE" } } }
	a:RefreshPlayerLocationPins()
	pin.frame.scripts.OnEnter()
	Equal(state.tooltip.width, 300)
	Equal(state.partyRows[1].frame.width, 272)
	Equal(state.partyRows[1].label.width, 234)
	local allocated = #a.regions
	party = { size = 0 }
	pin.frame.scripts.OnEnter()
	Equal(state.tooltip.width, compact)
	Equal(state.tooltipDivider.width, compact - 28)
	Equal(state.partyRows[1].active, false)
	assert(not state.partyRows[1].frame.shown)
	Equal(#a.regions, allocated)
end)

local function WaypointFixture(addon)
	local a = addon or Fixture()
	a.waypoints = {
		{ name = "First-Realm", mapID = 1, x = 0.5, y = 0.5, classFile = "MAGE" },
		{ name = "Second-Realm", mapID = 1, x = 0.5, y = 0.5, classFile = "WARRIOR" },
	}
	function a:GetPartyWaypointRows()
		return self.waypoints
	end
	function a:GetPartyNavigationPeer(name)
		for _, row in ipairs(self.waypoints) do
			if row.name == name then
				return row
			end
		end
	end
	function a:GetGroupedSenderClassFile(name)
		local p = self:GetPartyNavigationPeer(name)
		return p and p.classFile
	end
	a.API.GetMapInfo = function()
		return { name = "Stormwind" }
	end
	function a:CreatePartyQuestFilterMenu(_, generator)
		self.waypointMenu = {}
		local root = {}
		function root:CreateTitle(text)
			a.waypointMenu[#a.waypointMenu + 1] = text
		end
		function root:CreateButton(text, callback)
			a.waypointMenu[#a.waypointMenu + 1] = { text = text, callback = callback }
		end
		generator(nil, root)
	end
	function a:NavigateToPartyWaypoint(name)
		self.navigated = name
	end
	return a
end
Register("party waypoint pins expose overlapping owners and shade only focused map waypoints without player dots", function()
	local a = WaypointFixture()
	a.geometry.map.pinFrameLevel = 2300
	a.waypoints[3] = { name = "Distant-Realm", mapID = 1, x = 0.8, y = 0.5, classFile = "MAGE" }
	a:RefreshPartyWaypointPins()
	local s = a.partyWaypointPinState
	Equal(#s.surfaces.map.pins, 3)
	Equal(#s.surfaces.minimap.pins, 2)
	local pin, overlapping, distant = s.surfaces.map.pins[1], s.surfaces.map.pins[2], s.surfaces.map.pins[3]
	Equal(#pin.names, 2)
	pin.frame.scripts.OnEnter()
	assert(s.tooltip.shown and s.label.text:find("First-Realm", 1, true) and s.label.text:find("Second-Realm", 1, true))
	local shade = FocusedAboveShade(a, { pin, overlapping }, { distant })
	assert(shade.level > 2300)
	Equal(shade.mouseEnabled, false)
	Equal(shade.mouseWheel, false)
	assert(not rawget(a, "locationPinState"), "waypoint focus needs no player dots")
	pin.frame.scripts.OnClick()
	Equal(#a.waypointMenu, 4)
	a.waypointMenu[4].callback()
	Equal(a.navigated, "Second-Realm")
	local count = #a.frames
	a:RefreshPartyWaypointPins()
	Equal(#a.frames, count)
	FocusedAboveShade(a, { pin, overlapping }, { distant })
	distant.frame.scripts.OnEnter()
	pin.frame.scripts.OnLeave()
	FocusedAboveShade(a, { distant }, { pin, overlapping })
	distant.frame.scripts.OnLeave()
	NoFocusShade(a)
	local mini = s.surfaces.minimap.pins[1]
	mini.frame.scripts.OnEnter()
	NoFocusShade(a)
	assert(s.tooltip:IsVisible())
	mini.frame.scripts.OnLeave()
	pin.frame.scripts.OnEnter()
	a.waypoints[2], a.waypoints[3] = nil, nil
	a.waypoints[1].x = 0.52
	a:RefreshPartyWaypointPins()
	NoFocusShade(a)
	Equal(s.hovered, nil)
	Equal(#pin.names, 1)
	Equal(s.surfaces.map.pins[2].frame.shown, false)
	Equal(a.mapParent.writes, 0)
	Equal(a.miniParent.writes, 0)
	pin.frame.scripts.OnEnter()
	FocusedAboveShade(a, { pin })
	Equal(a.mapOverlayFocusState.shade, shade)
	a.waypoints = {}
	a:RefreshPartyWaypointPins()
	Equal(s.surfaces.map.frame.shown, false)
	Equal(s.tooltip.shown, false)
	NoFocusShade(a)
end)
Register("party waypoint focus retires on restrictions unavailable geometry recycled peers and forbidden parents", function()
	for _, change in ipairs({ "restricted", "hidden", "disabled", "forbidden", "geometry", "viewport", "map", "parent", "recycled" }) do
		local a = WaypointFixture()
		a:RefreshPartyWaypointPins()
		local s = a.partyWaypointPinState
		local pin = s.surfaces.map.pins[1]
		pin.frame.scripts.OnEnter()
		local shade = FocusShade(a)
		assert(s.tooltip.shown)
		if change == "restricted" then a.blocked = true
		elseif change == "hidden" then a.mapParent:Hide()
		elseif change == "disabled" then a.isEnabled = false
		elseif change == "forbidden" then a.mapParent.forbidden = true
		elseif change == "geometry" then a.geometry.map = nil
		elseif change == "viewport" then a.geometry.map.canvasLeft = -1
		elseif change == "map" then
			a.geometry.map.mapID = 2
			function a:GetLocationPinMapPosition(row) return row.x, row.y end
		elseif change == "parent" then a.geometry.map.parent = Frame(a)
		else a.waypoints[1].name = "Replacement-Realm" end
		a:RefreshPartyWaypointPins()
		Equal(s.hovered, nil)
		Equal(s.tooltip.shown, false)
		if change ~= "forbidden" then NoFocusShade(a) end
		a.blocked, a.isEnabled, a.mapParent.forbidden = false, true, false
		a.mapParent:Show()
		if not a.geometry.map then
			a:HidePartyWaypointPins()
		else
			a:RefreshPartyWaypointPins()
			NoFocusShade(a)
		end
		a:HidePartyWaypointPins()
		Equal(s.surfaces.minimap.frame.shown, false)
		Equal(shade.shown, false)
	end
end)

Register("experimental phase decoration clears when a pooled pin changes occupant", function()
	local a = Fixture()
	function a:GetPlayerPhaseStatus(name)
		return name == "Other-Realm" and "different" or nil
	end
	a.rows.map = { Row("Other-Realm") }
	assert(a:RefreshPlayerLocationPins())
	local pin = Pin(a, "map")
	Equal(pin.phaseIcon.shown, true)
	Equal(pin.phaseIcon.texture, "Interface\\TargetingFrame\\UI-PhasingIcon")
	Equal(pin.phaseIcon.texCoord[1], 0.15625)
	a.rows.map = { Row("Same-Realm") }
	assert(a:RefreshPlayerLocationPins())
	Equal(Pin(a, "map"), pin)
	Equal(pin.phaseIcon.shown, false)
end)

Register("hover interests follow visible owners across Alt Z recycled pins chat switches and leaves", function()
	local a = Fixture()
	a.requests = {}
	function a:RequestPlayerDetails(name)
		self.requests[#self.requests + 1] = name
	end
	function a:GetChatLogTooltipCursorPosition()
		return 200, 100
	end
	local first, second = Row("Friend-Realm"), Row("Other-Realm")
	a.rows.map = { first }
	a.playerLocationState = { peers = { [first.name] = first, [second.name] = second } }
	a:RefreshPlayerLocationPins()
	local pin = Pin(a, "map")
	pin.frame.scripts.OnEnter()
	local state = a.locationPinState
	local original = assert(a.playerDetailsState.interests[state])
	assert(original.isCurrent())
	local chatParent = Frame(a)
	local chat = Frame(a, chatParent)
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:" .. first.name))
	local chatState = a.chatLogPlayerTooltipState
	pin.frame.scripts.OnLeave()
	Equal(a.playerDetailsState.interests[state], nil)
	assert(a.playerDetailsState.interests[chatState])
	chatParent:Hide()
	assert(chat:IsShown() and not chat:IsVisible())
	local calls = #a.requests
	a:UpdatePlayerDetailsInterests()
	Equal(next(a.playerDetailsState.interests), nil)
	Equal(#a.requests, calls, "hidden parents must retire interests before runtime retries")
	a:UpdateChatLogPlayerTooltip()
	Equal(chatState.hovered, nil)
	chatParent:Show()
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:" .. second.name))
	local selected = assert(a.playerDetailsState.interests[chatState])
	Equal(selected.name, second.name)
	a.playerDetailsState.identities[first.name] = {
		receivedAt = 100,
		level = 99,
		classFile = "MAGE",
		race = "Dwarf",
		faction = "Alliance",
	}
	a:UpdateChatLogPlayerTooltip()
	assert(not chatState.tooltipIntro.text:find("99", 1, true), "old response cannot redraw the selected player")
	pin.frame.scripts.OnEnter()
	local mapInterest = assert(a.playerDetailsState.interests[state])
	a.rows.map = { second }
	a:RefreshPlayerLocationPins()
	Equal(a.playerDetailsState.interests[state], nil)
	assert(not mapInterest.isCurrent())
	pin.frame.scripts.OnEnter()
	Equal(a.playerDetailsState.interests[state].name, second.name)
	a.tooltipParent:Hide()
	a:UpdatePlayerDetailsInterests()
	Equal(next(a.playerDetailsState.interests), nil)
	a:RefreshPlayerLocationPins()
	Equal(state.hovered, nil)
	a:UpdateChatLogPlayerTooltip()
	Equal(chatState.hovered, nil)
end)

local function ClusterFixture(count)
	local a = Fixture()
	a.requests, a.phaseRequests = {}, {}
	a.clusterOptions = { showPlayerLocations = true, clusterPlayerLocations = true }
	function a:GetOption(key)
		if self.clusterOptions[key] ~= nil then return self.clusterOptions[key] end
		return QuestTogether.GetOption(self, key)
	end
	function a:RequestPlayerDetails(name)
		self.requests[#self.requests + 1] = name
	end
	function a:RequestPlayerPhaseComparison(name)
		self.phaseRequests[#self.phaseRequests + 1] = name
	end
	a.rows.map = {}
	a.playerLocationState = { peers = {} }
	for index = 1, count or 2 do
		local row = Row(string.format("Peer%03d-Realm", index))
		a.rows.map[index], a.playerLocationState.peers[row.name] = row, row
	end
	return a
end

local function VisibleMapPins(a)
	local result = {}
	for _, pin in ipairs(a.locationPinState.surfaces.map.pins) do
		if pin.frame:IsVisible() then result[#result + 1] = pin end
	end
	return result
end

local function ExpandedPlayerPin(a, name)
	for _, pin in ipairs(VisibleMapPins(a)) do
		if pin.expansion and (not name or pin.name == name) then return pin end
	end
end

local function AssertNoVisibleConnectors(a)
	for _, pin in ipairs(a.locationPinState.surfaces.map.pins) do
		assert(not pin.connector or not pin.connector:IsVisible(), "a collapsed expansion left a visible connector")
	end
end

local function SharedPartyHoverFixture(size)
	local a = ClusterFixture(3)
	a.now, a.known, a.rosterWire = 100, {}, {}
	a.API.GetTime = function() return a.now end
	a.API.GetRealmName = function() return "Realm" end
	a.API.Random = function() return 12345 end
	a.clusterOptions.clusterPlayerLocations = false
	a.rows.map[2].x, a.rows.map[3].x = 0.55, 0.7
	a.rows.minimap = { a.rows.map[1], a.rows.map[2] }
	for _, row in ipairs(a.rows.map) do a.known[row.name] = true end
	function a:IsSelfSender() return false end
	function a:IsKnownQTPlayer(name) return self.known[name] == true end
	function a:RecordQTPlayerPresence(name) self.known[name] = true; return true end
	function a:GetPlayerTooltipStats() return nil end
	function a:GetPlayerPartySize() return nil end
	function a:GetChatLogTooltipCursorPosition() return 200, 100 end
	function a:GetCommunicationRequestDeadline() return nil end
	function a:CancelCommRequest() end
	function a:CancelCommunicationOwner() end
	function a:Request(operation, record, _, options)
		Equal(operation, "QPGR")
		self.rosterWire[#self.rosterWire + 1] = { record = self:DeepCopy(record), options = options }
		return true
	end
	function a:AcceptPartyMetadata(name, record)
		local observation = self:CreatePeerObservation(name, "QTPG", { source = "snapshot", lifetime = 180 })
		assert(self:HandlePartyVisualMetadata(record, name, observation))
	end
	-- Build the advertised revision through the actual local party owner, then
	-- receive it through the actual observation/roster boundary on the viewer.
	local sender, leader = a.rows.map[1].name, a.rows.map[2].name
	local publisher = setmetatable({ isEnabled = true, partyMembers = {} }, { __index = QuestTogether })
	publisher.API = {
		GetTime = function() return a.now end,
		GetRealmName = function() return "Realm" end,
		GetPartyVisualLeaderUnit = function() return "party1" end,
	}
	function publisher:IsRuntimeRestricted() return false end
	function publisher:IsSelfSender(name) return name == sender end
	function publisher:GetUnitFullName() return leader end
	function publisher:GetLocalPartySize() return size end
	publisher.partyMembers[sender], publisher.partyMembers[leader] = { classFile = "MAGE" }, { classFile = "MAGE" }
	if size == 3 then publisher.partyMembers["Remote-Realm"] = { classFile = "WARRIOR" } end
	local record, info = publisher:BuildPartyVisualMetadata()
	assert(record and info)
	a:AcceptPartyMetadata(sender, record)
	function a:CompletePartyRoster()
		local request = assert(self.rosterWire[#self.rosterWire]).record
		assert(self:HandlePartyVisualRosterMember({ requestId = request.requestId, revision = record.revision,
			members = self:DeepCopy(info.members) }, sender))
	end
	return a, sender, leader, record
end

local function AssertTooltipParty(state, names, loading)
	local shown = {}
	for _, item in ipairs(state.partyRows or {}) do
		if item.active and item.frame:IsVisible() then
			shown[#shown + 1] = item
		end
	end
	Equal(#shown, #names)
	for index, name in ipairs(names) do assert(shown[index].label.text:find(name, 1, true)) end
	assert(not shown[1] or shown[1].crown.shown)
	for index = 2, #shown do assert(not shown[index].crown.shown) end
	Equal(state.tooltipIntro.text:find("Loading party members", 1, true) ~= nil, loading)
end

Register("accepted party roster from one member is reused by another hover chat cluster and map highlights", function()
	local a, sender, leader = SharedPartyHoverFixture(3)
	a:RefreshPlayerLocationPins()
	local first, second, other = Pin(a, "map"), Pin(a, "map", 2), Pin(a, "map", 3)
	first.frame.scripts.OnEnter()
	Equal(#a.rosterWire, 1)
	a:CompletePartyRoster()
	assert(a:GetPartyVisualState().peers[leader] == nil, "the other member sent no party advertisement")
	local source = a:GetPlayerPartyVisualInfo(sender)
	Equal(a:GetPlayerPartyVisualInfo(leader).key, source.key)
	Equal(#a:GetPlayerPartyVisualInfo(leader).members, 3)
	first.frame.scripts.OnLeave()
	second.frame.scripts.OnEnter()
	AssertTooltipParty(a.locationPinState, { leader, sender, "Remote-Realm" }, false)
	assert(first.partyOutline.shown and second.partyOutline.shown and second.partyCrown.shown)
	assert(Pin(a, "minimap").partyOutline.shown and Pin(a, "minimap", 2).partyOutline.shown)
	assert(not other.partyOutline.shown)
	FocusedAboveShade(a, { first, second }, { other })
	Equal(#a.rosterWire, 1, "accepted shared roster must prevent a second roster fetch")
	assert(a:ShowChatLogPlayerTooltip(Frame(a), "questtogetherlog:" .. leader))
	AssertTooltipParty(a.chatLogPlayerTooltipState, { leader, sender, "Remote-Realm" }, false)
	a:HideChatLogPlayerTooltip()
	second.frame.scripts.OnLeave()
	a.clusterOptions.clusterPlayerLocations, a.rows.map[2].x = true, 0.501
	a:RefreshPlayerLocationPins()
	local requests = #a.requests
	Pin(a, "map").frame.scripts.OnEnter()
	local summary = a.locationPinState.clusterTooltip
	Equal(summary.partyRows[1].partyKey, source.key)
	Equal(summary.partyRows[2].partyKey, source.key)
	Equal(summary.partyGroups[1].count.text, "3")
	Equal(#a.rosterWire, 1)
	Equal(#a.requests, requests, "cluster summary only reads the shared party result")
	Equal(a:GetPartyVisualState().peers[sender].sampledAt, 100)
end)

Register("partial party membership is consistent across member and leader hovers without becoming a complete roster", function()
	for _, size in ipairs({ 2, 3 }) do
		local a, sender, leader = SharedPartyHoverFixture(size)
		a:RefreshPlayerLocationPins()
		local first, second = Pin(a, "map"), Pin(a, "map", 2)
		first.frame.scripts.OnEnter()
		AssertTooltipParty(a.locationPinState, { leader, sender }, size == 3)
		Equal(a:GetPlayerPartyVisualInfo(sender).members, nil)
		Equal(#a.rosterWire, 1)
		first.frame.scripts.OnLeave()
		second.frame.scripts.OnEnter()
		AssertTooltipParty(a.locationPinState, { leader, sender }, size == 3)
		Equal(a:GetPlayerPartyVisualInfo(leader).members, nil)
		assert(first.partyOutline.shown and second.partyOutline.shown and second.partyCrown.shown)
		second.frame.scripts.OnLeave()
		a.clusterOptions.clusterPlayerLocations, a.rows.map[2].x = true, 0.501
		a:RefreshPlayerLocationPins()
		local requests, rosters = #a.requests, #a.rosterWire
		Pin(a, "map").frame.scripts.OnEnter()
		local summary = a.locationPinState.clusterTooltip
		Equal(summary.partyRows[1].partyKey, summary.partyRows[2].partyKey)
		assert(summary.partyRows[1].partyKey)
		Equal(summary.partyGroups[1].count.text, tostring(size))
		Equal(#a.requests, requests)
		Equal(#a.rosterWire, rosters)
		Equal(a:GetPartyVisualState().peers[leader], nil)
	end
end)

Register("newer solo evidence removes inferred party membership from active hover cluster and highlights", function()
	local a, sender, leader = SharedPartyHoverFixture(3)
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	a:CompletePartyRoster()
	Pin(a, "map").frame.scripts.OnLeave()
	local selected = Pin(a, "map", 2)
	selected.frame.scripts.OnEnter()
	AssertTooltipParty(a.locationPinState, { leader, sender, "Remote-Realm" }, false)
	a.now = 101
	a:AcceptPartyMetadata(leader, { size = 0 })
	a:RefreshPlayerLocationPins()
	assert(a.locationPinState.tooltipIntro.text:find("Solo", 1, true))
	for _, row in ipairs(a.locationPinState.partyRows) do assert(not row.active) end
	for _, surface in pairs(a.locationPinState.surfaces) do
		for _, pin in ipairs(surface.pins) do
			assert(not pin.partyOutline.shown and not pin.partyCrown.shown)
			Near(pin.frame.alpha, (pin.name == leader and 1 or 0.45))
		end
	end
	FocusedAboveShade(a, { selected }, { Pin(a, "map"), Pin(a, "map", 3) })
	selected.frame.scripts.OnLeave()
	NoFocusShade(a)
	a.clusterOptions.clusterPlayerLocations, a.rows.map[2].x = true, 0.501
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	local summary = a.locationPinState.clusterTooltip
	for _, item in ipairs(summary.partyRows) do
		if item.label.text:find("Peer002", 1, true) then Equal(item.partyKey, nil) end
	end
	Equal(a:GetPlayerPartyVisualInfo(leader).key, nil)
	Equal(#a.rosterWire, 1)
end)

Register("cluster summary hover requests no details and expansion preserves normal player dots and hover", function()
	local a = ClusterFixture()
	VisualParty(a)
	local friend, leader = Row("Friend-Realm"), Row("Leader-Realm", 0.501)
	friend.classFile = "WARRIOR"
	a.rows.map = { friend, leader, Row("Unrelated-Realm", 0.7) }
	a.rows.minimap = { Row("Friend-Realm"), Row("Leader-Realm", 0.501) }
	function a:IsPlayerLookingForQuestPartners(name) return name == leader.name end
	function a:GetPlayerPhaseStatus(name) return name == friend.name and "different" or "same" end
	assert(a:RefreshPlayerLocationPins())
	local cluster, state = Pin(a, "map"), a.locationPinState
	Equal(#VisibleMapPins(a), 2)
	Equal(#state.surfaces.minimap.pins, 2)
	Equal(cluster.name, nil)
	Equal(cluster.count.text, "2")
	cluster.frame.scripts.OnEnter()
	Equal(state.clusterTooltip.hovered, cluster)
	FocusedAboveShade(a, { cluster }, { Pin(a, "map", 2) })
	Equal(a.playerLocationClusterExpansion, nil)
	assert(state.clusterTooltip.tooltipTitle.text:find("2 players", 1, true))
	assert(state.clusterTooltip.partyRows[1].label.text:find("Friend", 1, true))
	assert(state.clusterTooltip.tooltipLabel.text:find("Click to expand players.", 1, true))
	Equal(#a.requests, 0)
	Equal(#a.phaseRequests, 0)
	Equal(a.rosterRequests, nil)
	assert(not rawget(a, "playerDetailsState") or next(a.playerDetailsState.interests) == nil)
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(#a.menus, 0)
	Equal(#VisibleMapPins(a), 4)
	assert(state.clusterTooltip.tooltipLabel.text:find("Click to collapse", 1, true))
	local member = assert(ExpandedPlayerPin(a, friend.name))
	local expandedLeader = assert(ExpandedPlayerPin(a, leader.name))
	assert(member.phaseIcon.shown and member.partyBadge.shown)
	assert(expandedLeader.glow[1].shown and expandedLeader.partyBadge.shown)
	Equal(member.texture.color[1], 1)
	assert(not member.count.shown)
	local line, host = member.connector, state.surfaces.map.frame
	Equal(line.kind, "Line")
	Equal(line.parent, state.surfaces.map.clusterShade)
	Equal(line.layer, "OVERLAY")
	Equal(line.thickness, 1)
	Equal(line.startPoint[1], "TOPLEFT")
	Equal(line.startPoint[2], host)
	Near(line.startPoint[3], 500)
	Near(line.startPoint[4], -300)
	Equal(line.endPoint[2], host)
	Near(line.endPoint[3], member.frame.points[1][4])
	Near(line.endPoint[4], member.frame.points[1][5])
	assert(line.endPoint[3] ~= line.startPoint[3] or line.endPoint[4] ~= line.startPoint[4])
	Near(friend.x, 0.5)
	Near(friend.y, 0.5)
	Near(leader.x, 0.501)
	member.frame.scripts.OnEnter()
	Equal(state.clusterTooltip.hovered, nil)
	Equal(state.hovered, member)
	Equal(a.requests[1], friend.name)
	Equal(a.phaseRequests[1], friend.name)
	Equal(a.playerDetailsState.interests[state].name, friend.name)
	assert(a.playerDetailsState.interests[state].isCurrent())
	assert(state.tooltipTitle.text:find("Friend", 1, true))
	assert(state.tooltipIntro.text:find("Level 60 Human", 1, true))
	assert(member.partyOutline.shown and expandedLeader.partyCrown.shown)
	member.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.menus[1].name, friend.name)
	Equal(a.menus[1].firstAction, nil)
	-- Selection removes this member from the cluster and may recycle the old
	-- expansion button. The open menu must follow the current selected dot.
	local selected = Pin(a, "map")
	Equal(selected.name, friend.name)
	assert(selected.selected and selected.frame:IsVisible())
	Near(selected.glow[1].color[2], 1)
	Equal(a.playerMapSelection.name, friend.name)
	Equal(a.menus[1].owner, selected.frame)
	assert(selected ~= member)
	AssertNoVisibleConnectors(a)
	selected.frame.scripts.OnClick(nil, "RightButton")
	Equal(a.menus[2].name, friend.name)
	Equal(a.menus[2].owner, selected.frame)
	local mini = Pin(a, "minimap")
	assert(not mini.cluster and not mini.expansion and not mini.connector)
	mini.frame.scripts.OnEnter()
	Equal(a.targetHover.name, friend.name)
	assert(a.targetHover.isCurrent())
end)

Register("cluster summary uses capped roster rows with validated indicators and no metadata requests", function()
	local a = ClusterFixture(8)
	local original = a.rows.map
	original[1].developer, original[1].developerOnly, original[1].publicLocationHidden = true, true, true
	original[4].classFile = "WARRIOR"
	a.verifiedDeveloperName, a.hiddenForName, a.lookingForName = original[2].name, original[2].name, original[3].name
	a.partyReads, a.rosterRequests = 0, 0
	function a:IsKnownQTPlayer() return false end
	function a:IsPlayerLookingForQuestPartners(name) return name == self.lookingForName end
	function a:IsPlayerLocationHiddenForDeveloper(name) return name == self.hiddenForName end
	function a:GetPlayerPartyVisualInfo()
		self.partyReads = self.partyReads + 1
		return nil
	end
	function a:RequestPartyVisualRoster() self.rosterRequests = self.rosterRequests + 1 end
	a:RefreshPlayerLocationPins()
	local partyReads = a.partyReads
	Pin(a, "map").frame.scripts.OnEnter()
	local summary = a.locationPinState.clusterTooltip
	assert(summary.tooltipTitle.text:find("8 players", 1, true))
	assert(summary.tooltipLabel.text:find("…and 2 more", 1, true))
	Equal(#summary.partyRows, 6)
	Equal(summary.tooltipIntro.shown, false)
	assert(a.partyReads > partyReads)
	Equal(a.rosterRequests, 0)
	Equal(#a.requests, 0)
	Equal(#a.phaseRequests, 0)
	assert(not rawget(a, "playerDetailsState") or next(a.playerDetailsState.interests) == nil)
	for index, item in ipairs(summary.partyRows) do
		assert(item.active and item.frame:IsVisible() and item.qtIcon.shown)
		assert(not item.crown.shown)
		assert(not item.label.text:find(" — Leader", 1, true))
		assert(not item.label.text:find("Party of", 1, true))
		assert(item.label.text:find("Peer00" .. index, 1, true))
		Equal(item.frame.points[1][2], summary.tooltipTitle)
		Equal(item.frame.points[1][3], "BOTTOMLEFT")
		if index > 1 then
			local previous = summary.partyRows[index - 1]
			assert(item.frame.points[1][5] <= previous.frame.points[1][5] - previous.frame.height)
		end
	end
	local ordinary, developer, looking = summary.partyRows[1], summary.partyRows[2], summary.partyRows[3]
	assert(ordinary.dot.shown and not ordinary.developerIcon.shown and not ordinary.hiddenGlow[1].shown)
	Near(ordinary.dot.color[1], 64 / 255)
	Near(ordinary.dot.color[2], 199 / 255)
	assert(not ordinary.label.text:find("QuestTogether developer", 1, true))
	assert(not ordinary.label.text:find("Location sharing is off", 1, true))
	Equal(ordinary.qtIcon.texture, a.NAMEPLATE_PLAYER_ICON_TEXTURE)
	assert(developer.developerIcon.shown and not developer.dot.shown and developer.hiddenGlow[1].shown)
	Equal(developer.hiddenGlow[1].color[1], 1)
	Near(developer.hiddenGlow[1].color[2], 0.12)
	Near(developer.hiddenGlow[1].color[3], 0.12)
	assert(developer.developerIcon.texture:find("DeveloperGear", 1, true))
	Near(developer.developerIcon.vertexColor[1], 64 / 255)
	Near(developer.developerIcon.vertexColor[2], 199 / 255)
	assert(not developer.label.text:find("QuestTogether developer", 1, true))
	assert(not developer.label.text:find("Location sharing is off", 1, true))
	assert(looking.qtIcon.texture:find("QuestTogetherPartnerIcon", 1, true))
	local last = summary.partyRows[6]
	Equal(summary.tooltipLabel.points[1][2], summary.tooltipTitle)
	assert(summary.tooltipLabel.points[1][5] <= last.frame.points[1][5] - last.frame.height - 14)
	local allocated = #a.regions
	a.verifiedDeveloperName, a.hiddenForName, a.lookingForName = nil, nil, nil
	original[3].developer, original[3].developerOnly, original[3].publicLocationHidden = true, true, true
	a.rows.map = { original[3], original[4] }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	Equal(a.locationPinState.clusterTooltip, summary)
	Equal(#a.regions, allocated)
	for index, item in ipairs(summary.partyRows) do
		if index <= 2 then
			assert(item.active and item.dot.shown and not item.developerIcon.shown and not item.hiddenGlow[1].shown)
			assert(not item.crown.shown)
			Equal(item.qtIcon.texture, a.NAMEPLATE_PLAYER_ICON_TEXTURE)
			assert(not item.label.text:find("QuestTogether developer", 1, true))
			assert(not item.label.text:find("Location sharing is off", 1, true))
		else
			assert(not item.active and not item.frame:IsVisible())
		end
	end
	Equal(summary.partyRows[2].dot.color[1], 1)
	assert(not summary.tooltipLabel.text:find("more", 1, true))
	Equal(a.rosterRequests, 0)
	Equal(#a.requests, 0)
end)

local function ClusterPartySummaryFixture(count)
	local a = ClusterFixture(count or 6)
	a.measureText, a.now, a.rosterRequests = true, 100, 0
	a.API.GetTime = function() return a.now end
	function a:IsSelfSender() return false end
	function a:IsKnownQTPlayer() return true end
	function a:GetPlayerTooltipStats() return nil end
	function a:GetPlayerPartySize() return nil end
	function a:RequestPartyVisualRoster() self.rosterRequests = self.rosterRequests + 1 end
	function a:SetSummaryParty(indices, key, size)
		local peers = self:GetPartyVisualState().peers
		for _, index in ipairs(indices) do
			local name = self.rows.map[index].name
			peers[name] = { key = key, size = size or #indices, leader = self.rows.map[indices[1]].name,
				leaderClass = "MAGE", at = self.now, lifetime = 180 }
		end
	end
	return a
end

local function AssertNoClusterMetadataRequests(a)
	Equal(a.rosterRequests, 0)
	Equal(#a.requests, 0)
	Equal(#a.phaseRequests, 0)
	assert(not rawget(a, "playerDetailsState") or next(a.playerDetailsState.interests) == nil)
end

Register("cluster summary renders validated party membership and totals without requesting metadata", function()
	local a = ClusterPartySummaryFixture()
	a:SetSummaryParty({ 1, 4 }, "PartyA", 5)
	a:SetSummaryParty({ 2, 5 }, "PartyB", 40)
	a:SetSummaryParty({ 3 }, "UntrustedSoloKey", 0)
	a.rows.map[6].partyKey = "PartyA" -- raw location fields cannot establish party identity
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	local state = a.locationPinState.clusterTooltip
	for index, originalIndex in ipairs({ 1, 4, 2, 5, 3, 6 }) do
		local item = state.partyRows[index]
		assert(item.active and item.label.text:find("Peer00" .. originalIndex, 1, true))
		Equal(item.partyKey, index <= 2 and "PartyA" or index <= 4 and "PartyB" or nil)
		Equal(item.partySize, index <= 2 and 5 or index <= 4 and 40 or nil)
	end
	Equal(#state.partyGroups, 2)
	for index, group in ipairs(state.partyGroups) do
		assert(group.active and group.frame:IsVisible())
		Equal(group.frame.mouseEnabled, false)
		Equal(group.count.text, index == 1 and "5" or "40")
	end
	AssertNoClusterMetadataRequests(a)
end)

Register("cluster party outlines retire on metadata expiry reuse their frames and reject stale cluster hover", function()
	local a = ClusterPartySummaryFixture()
	a:SetSummaryParty({ 1, 4 }, "PartyA", 40)
	a:SetSummaryParty({ 2, 5 }, "PartyB", 5)
	a:RefreshPlayerLocationPins()
	local cluster = Pin(a, "map")
	cluster.frame.scripts.OnEnter()
	local state = a.locationPinState.clusterTooltip
	local firstFrame, secondFrame = state.partyGroups[1].frame, state.partyGroups[2].frame
	local frames, regions = #a.frames, #a.regions
	a.now = 280
	a:RefreshPlayerLocationPins()
	assert(state.tooltip:IsVisible())
	for _, group in ipairs(state.partyGroups) do
		assert(not group.active and not group.frame:IsVisible())
		Equal(group.key, nil)
		Equal(group.first, nil)
		Equal(group.last, nil)
		Equal(group.partySize, nil)
		Equal(group.count.text, "")
	end
	for index, item in ipairs(state.partyRows) do
		Equal(item.partyKey, nil)
		Equal(item.partySize, nil)
		Equal(item.frame.points[1][4], 0)
		assert(item.label.text:find("Peer00" .. index, 1, true))
	end
	a:SetSummaryParty({ 2, 6 }, "NewParty", 3)
	a:RefreshPlayerLocationPins()
	Equal(state.partyGroups[1].frame, firstFrame)
	Equal(state.partyGroups[1].key, "NewParty")
	Equal(state.partyGroups[1].partySize, 3)
	Equal(state.partyGroups[1].count.text, "3")
	assert(state.partyGroups[1].active)
	Equal(state.partyGroups[2].frame, secondFrame)
	assert(not state.partyGroups[2].active and not secondFrame:IsVisible())
	Equal(#a.frames, frames)
	Equal(#a.regions, regions)
	a.rows.map = { a.rows.map[2], a.rows.map[6] }
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnEnter()
	for index = 3, #state.partyRows do
		assert(not state.partyRows[index].active)
		Equal(state.partyRows[index].partySize, nil)
	end
	local staleEnter = cluster.frame.scripts.OnEnter
	a.rows.map = { Row("ReplacementA-Realm"), Row("ReplacementB-Realm") }
	staleEnter()
	assert(not state.tooltip:IsVisible())
	assert(not firstFrame:IsVisible() and not secondFrame:IsVisible())
	AssertNoClusterMetadataRequests(a)
end)

Register("grouped cluster summaries cap rows after grouping while expanded summaries stay within the visible fanout page", function()
	local a = ClusterPartySummaryFixture(20)
	a:SetSummaryParty({ 1, 13 }, "CrossPageParty", 5)
	a:RefreshPlayerLocationPins()
	local cluster = Pin(a, "map")
	cluster.frame.scripts.OnEnter()
	local state = a.locationPinState.clusterTooltip
	Equal(#state.partyRows, 6)
	assert(state.partyRows[1].label.text:find("Peer001", 1, true))
	assert(state.partyRows[2].label.text:find("Peer013", 1, true))
	Equal(state.partyGroups[1].first, 1)
	Equal(state.partyGroups[1].last, 2)
	Equal(state.partyGroups[1].count.text, "5")
	assert(state.tooltipLabel.text:find("…and 14 more", 1, true))
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(cluster.cluster.expansionInfo.page, 1)
	Equal(state.partyGroups[1].last, 1)
	Equal(state.partyGroups[1].count.text, "5")
	for _, item in ipairs(state.partyRows) do
		assert(not item.label.text:find("Peer013", 1, true))
	end
	cluster.frame.scripts.OnMouseWheel(nil, -1)
	Equal(cluster.cluster.expansionInfo.page, 2)
	assert(state.partyRows[1].label.text:find("Peer013", 1, true))
	Equal(state.partyGroups[1].first, 1)
	Equal(state.partyGroups[1].last, 1)
	Equal(state.partyGroups[1].count.text, "5")
	for _, item in ipairs(state.partyRows) do
		assert(not item.label.text:find("Peer001", 1, true))
	end
	AssertNoClusterMetadataRequests(a)
end)

Register("reusing a grouped tooltip for an individual retires the prior party presentation", function()
	local a = ClusterPartySummaryFixture(2)
	a:SetSummaryParty({ 1, 2 }, "Party", 40)
	a:RefreshPlayerLocationPins()
	local cluster = Pin(a, "map")
	cluster.frame.scripts.OnEnter()
	local state = a.locationPinState.clusterTooltip
	local group = state.partyGroups[1]
	assert(group.active and group.frame:IsVisible())
	a:RenderPlayerTooltip(state, cluster, a:BuildPlayerTooltipModel(a.rows.map[1]))
	assert(state.tooltipIntro.shown)
	assert(not group.active and not group.frame:IsVisible())
	Equal(group.partySize, nil)
	Equal(group.count.text, "")
	for _, item in ipairs(state.partyRows) do
		if item.active then
			Equal(item.partyKey, nil)
			Equal(item.partySize, nil)
		end
	end
	AssertNoClusterMetadataRequests(a)
end)

Register("crowded private and public map rows expand the same admitted cluster and retain selected player", function()
	local a = ClusterFixture(520)
	for index, row in ipairs(a.rows.map) do
		row.x = index < 256 and 0.55 or 0.5
		row.developerOnly = index > 500 or nil
	end
	local found = Row("Found-Realm", 0.5)
	function a:GetFindPlayerMapLocation() return found end
	a.playerMapSelection = { name = found.name, mapID = 1, expires = 120 }
	a:RefreshPlayerLocationPins()
	assert(Pin(a, "map").selected)
	local cluster = Pin(a, "map", 2)
	assert(cluster.cluster)
	local key = cluster.cluster.key
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.playerLocationClusterExpansion.key, key)
	local member, selected = assert(ExpandedPlayerPin(a)), nil
	for _, pin in ipairs(VisibleMapPins(a)) do
		if pin.name == found.name then selected = pin end
	end
	assert(selected and selected.selected and selected.glow[1].shown)
	assert(not selected.expansion)
	FocusedAboveShade(a, { member }, { selected })
	assert(member.frame.level > a.locationPinState.surfaces.map.clusterShade.level)
	Near(selected.frame.points[1][4], 500)
	Near(selected.frame.points[1][5], -300)
	member.frame.scripts.OnEnter()
	assert(a.playerDetailsState.interests[a.locationPinState].isCurrent())
	member.frame.scripts.OnClick(nil, "RightButton")
	Equal(a.menus[1].name, member.name)
end, { offline = true })

Register("large map clusters page actual dots and collapse retires hover interests and connector lines", function()
	local a = ClusterFixture(45)
	a:RefreshPlayerLocationPins()
	local cluster, state = Pin(a, "map"), a.locationPinState
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	assert(cluster.frame.mouseWheel)
	local first = assert(ExpandedPlayerPin(a, "Peer001-Realm"))
	first.frame.scripts.OnEnter()
	local stale = assert(a.playerDetailsState.interests[state])
	assert(stale.isCurrent())
	local seen = {}
	local pages = cluster.cluster.expansionInfo.pages
	assert(pages > 1)
	for page = 1, pages do
		Equal(cluster.cluster.expansionInfo.page, page)
		local onPage = 0
		for _, pin in ipairs(VisibleMapPins(a)) do
			if pin.expansion then
				assert(not seen[pin.name], "player repeated across expansion pages")
				seen[pin.name] = true
				onPage = onPage + 1
				assert(pin.connector:IsVisible())
			end
		end
		assert(onPage > 0 and onPage <= 12)
		if page < pages then cluster.frame.scripts.OnMouseWheel(nil, -1) end
	end
	for index = 1, 45 do assert(seen[string.format("Peer%03d-Realm", index)]) end
	assert(not stale.isCurrent())
	Equal(a.playerDetailsState.interests[state], nil)
	cluster.frame.scripts.OnEnter()
	assert(state.clusterTooltip.tooltipLabel.text:find("Scroll to browse players", 1, true))
	cluster.frame.scripts.OnMouseWheel(nil, -1)
	Equal(cluster.cluster.expansionInfo.page, pages)
	cluster.frame.scripts.OnMouseWheel(nil, 1)
	Equal(cluster.cluster.expansionInfo.page, pages - 1)
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(#VisibleMapPins(a), 1)
	assert(not cluster.frame.mouseWheel)
	AssertNoVisibleConnectors(a)
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(cluster.cluster.expansionInfo.page, 1)
	assert(not stale.isCurrent(), "reopening cannot renew an earlier hover callback")
end)

Register("expanded hover currentness rejects changed membership geometry and replaced expansion before redraw", function()
	for _, change in ipairs({ "membership", "geometry", "replaced" }) do
		local a = ClusterFixture(3)
		a:RefreshPlayerLocationPins()
		local cluster = Pin(a, "map")
		cluster.frame.scripts.OnClick(nil, "LeftButton")
		local member = assert(ExpandedPlayerPin(a, "Peer001-Realm"))
		member.frame.scripts.OnEnter()
		local state = a.locationPinState
		local stale = assert(a.playerDetailsState.interests[state])
		assert(stale.isCurrent())
		if change == "membership" then
			table.remove(a.rows.map, 3)
		elseif change == "geometry" then
			a.geometry.map.canvasLeft = -1
		else
			a:ClearPlayerLocationClusterExpansion()
			assert(a:TogglePlayerLocationClusterExpansion(cluster.cluster, a.geometry.map))
		end
		assert(not stale.isCurrent(), change .. " retained an old hover")
		a:UpdatePlayerDetailsInterests()
		Equal(a.playerDetailsState.interests[state], nil)
		Equal(#a.requests, 1)
		member.frame.scripts.OnClick(nil, "RightButton")
		Equal(#a.menus, 0)
		a:RefreshPlayerLocationPins()
		assert(not stale.isCurrent())
		if change ~= "replaced" then AssertNoVisibleConnectors(a) end
	end
end)

Register("hidden map and restrictions stop expanded actions before refresh and clear expansion safely", function()
	for _, change in ipairs({ "hidden", "restricted", "disabled" }) do
		local a = ClusterFixture()
		a:RefreshPlayerLocationPins()
		local cluster = Pin(a, "map")
		cluster.frame.scripts.OnClick(nil, "LeftButton")
		local member = assert(ExpandedPlayerPin(a))
		member.frame.scripts.OnEnter()
		local interest = assert(a.playerDetailsState.interests[a.locationPinState])
		if change == "hidden" then a.mapParent:Hide()
		elseif change == "restricted" then a.blocked = true
		else a.isEnabled = false end
		assert(not interest.isCurrent())
		member.frame.scripts.OnClick(nil, "RightButton")
		cluster.frame.scripts.OnClick(nil, "LeftButton")
		Equal(#a.menus, 0)
		a:UpdatePlayerDetailsInterests()
		Equal(#a.requests, 1)
		Equal(a.playerDetailsState.interests[a.locationPinState], nil)
		a:RefreshPlayerLocationPins()
		Equal(a.playerLocationClusterExpansion, nil)
		AssertNoVisibleConnectors(a)
		a.blocked, a.isEnabled = false, true
		a.mapParent:Show()
		a:RefreshPlayerLocationPins()
		Equal(#VisibleMapPins(a), 1)
		AssertNoVisibleConnectors(a)
	end
end)

Register("privacy withdrawal immediately invalidates expanded player without retaining accepted coordinates", function()
	local a = ClusterFixture()
	local withdrawn, remaining = a.rows.map[1], a.rows.map[2]
	a.playerLocationState = { peers = { [withdrawn.name] = withdrawn, [remaining.name] = remaining } }
	a.GetVisiblePlayerLocations = QuestTogether.GetVisiblePlayerLocations
	function a:ShouldShowPlayerLocation(name) return not self:IsIgnoredPlayerName(name) end
	function a:AppendDeveloperLocationRows() end
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnClick(nil, "LeftButton")
	local member = assert(ExpandedPlayerPin(a, withdrawn.name))
	member.frame.scripts.OnEnter()
	local interest = assert(a.playerDetailsState.interests[a.locationPinState])
	-- The accepted cache now contains the withdrawal, which carries no position.
	a.playerLocationState.peers[withdrawn.name] = { name = withdrawn.name, mask = 0, receivedAt = 100 }
	assert(not interest.isCurrent())
	Equal(a.playerLocationClusterExpansion, nil)
	member.frame.scripts.OnClick(nil, "RightButton")
	Equal(#a.menus, 0)
	a:RefreshPlayerLocationPins()
	Equal(#VisibleMapPins(a), 1)
	Equal(Pin(a, "map").name, remaining.name)
	Equal(a.playerDetailsState.interests[a.locationPinState], nil)
	AssertNoVisibleConnectors(a)
	Equal(a.playerLocationState.peers[withdrawn.name].x, nil)
	Near(withdrawn.x, 0.5)
	Near(remaining.x, 0.5)
end)

Register("disabling clustering restores actual world map dots and leaves minimap targeting unchanged", function()
	local a = ClusterFixture()
	a.rows.map[2].x = 0.501
	a.rows.minimap = { a.rows.map[1], a.rows.map[2] }
	a:RefreshPlayerLocationPins()
	local mini = Pin(a, "minimap")
	local miniPoint = mini.frame.points[1]
	Pin(a, "map").frame.scripts.OnClick(nil, "LeftButton")
	local member = assert(ExpandedPlayerPin(a))
	member.frame.scripts.OnEnter()
	local interest = assert(a.playerDetailsState.interests[a.locationPinState])
	a.clusterOptions.clusterPlayerLocations = false
	assert(not interest.isCurrent())
	a:RefreshPlayerLocationPins()
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(#VisibleMapPins(a), 2)
	for index, pin in ipairs(VisibleMapPins(a)) do
		assert(pin.name and not pin.cluster and not pin.expansion and not pin.count.shown)
		Near(pin.frame.points[1][4], index == 1 and 500 or 501)
	end
	AssertNoVisibleConnectors(a)
	Equal(Pin(a, "minimap"), mini)
	Near(mini.frame.points[1][4], miniPoint[4])
	Near(mini.frame.points[1][5], miniPoint[5])
	mini.frame.scripts.OnEnter()
	Equal(a.targetHover.name, "Peer001-Realm")
	assert(a.targetHover.isCurrent())
	mini.frame.scripts.OnClick(nil, "LeftButton")
	Equal(#a.menus, 0)
	mini.frame.scripts.OnClick(nil, "RightButton")
	Equal(a.menus[1].name, "Peer001-Realm")
	assert(a.menus[1].firstAction)
	a.clusterOptions.clusterPlayerLocations = true
	a:RefreshPlayerLocationPins()
	Equal(#VisibleMapPins(a), 1)
	Equal(Pin(a, "map").count.text, "2")
	Equal(a.playerLocationClusterExpansion, nil)
end)

Register("developer and VIP artwork requires verified identity and restores normal dots after revocation or reuse", function()
	local a = ClusterFixture(1)
	local row = a.rows.map[1]
	row.developer, row.verifiedDeveloper = true, true
	a.rows.minimap = { row }
	function a:IsPlayerLookingForQuestPartners() return true end
	a:RefreshPlayerLocationPins()
	local map, mini = Pin(a, "map"), Pin(a, "minimap")
	for _, pin in ipairs({ map, mini }) do
		assert(not pin.developerGear.shown and pin.texture.shown and pin.border.shown)
		assert(pin.glow[1].shown)
	end
	map.frame.scripts.OnEnter()
	assert(not a.locationPinState.tooltipIntro.text:find("QuestTogether developer", 1, true))
	function a:IsVerifiedVIP(name) return name == self.verifiedVIPName end
	a.verifiedVIPName = row.name
	a:RefreshPlayerLocationPins()
	for _, pin in ipairs({ map, mini }) do
		assert(pin.developerGear.shown and not pin.texture.shown and not pin.border.shown)
		assert(pin.developerGear.texture:find("VIPStar", 1, true))
		assert(pin.glow[1].shown)
	end
	assert(a.locationPinState.tooltipIntro.text:find("QuestTogether VIP", 1, true))
	a.verifiedDeveloperName = row.name
	a:RefreshPlayerLocationPins()
	assert(map.developerGear.texture:find("DeveloperGear", 1, true), "developer takes precedence over VIP")
	a.verifiedVIPName = nil
	for _, pin in ipairs({ map, mini }) do
		assert(pin.developerGear.shown and not pin.texture.shown and not pin.border.shown)
		Equal(pin.frame.width, 18)
		assert(pin.developerGear.texture:find("DeveloperGear", 1, true))
		Near(pin.developerGear.vertexColor[1], 64 / 255)
		Near(pin.developerGear.vertexColor[2], 199 / 255)
		Near(pin.developerGear.vertexColor[3], 235 / 255)
		assert(pin.glow[1].shown)
		Near(pin.glow[1].color[2], 0.8)
	end
	assert(a.locationPinState.tooltipIntro.text:find("QuestTogether developer", 1, true))
	map.frame.scripts.OnClick(nil, "RightButton")
	Equal(a.menus[1].name, row.name)
	mini.frame.scripts.OnEnter()
	Equal(a.targetHover.name, row.name)
	assert(a.targetHover.isCurrent())
	a.verifiedDeveloperName = nil
	a:RefreshPlayerLocationPins()
	for _, pin in ipairs({ map, mini }) do
		assert(not pin.developerGear.shown and pin.texture.shown and pin.border.shown)
		assert(pin.glow[1].shown)
	end
	assert(not a.locationPinState.tooltipIntro.text:find("QuestTogether developer", 1, true))
	a.verifiedDeveloperName = row.name
	a:RefreshPlayerLocationPins()
	local replacement = Row("Replacement-Realm")
	replacement.developer = true
	a.rows.map, a.rows.minimap = { replacement }, { replacement }
	a:RefreshPlayerLocationPins()
	for _, pin in ipairs({ map, mini }) do
		Equal(pin.name, replacement.name)
		assert(not pin.developerGear.shown and pin.texture.shown and pin.border.shown)
	end
end)

Register("map and chat hidden location labels follow the viewer query and ignore raw private row flags", function()
	local a = ClusterFixture(1)
	local row = a.rows.map[1]
	row.developerOnly, row.publicLocationHidden, row.locationShared = true, true, false
	a.playerLocationState = { peers = { [row.name] = row } }
	function a:GetChatLogTooltipCursorPosition() return 200, 100 end
	local showHidden = false
	function a:IsPlayerLocationHiddenForDeveloper(name)
		return showHidden and name == row.name
	end
	a:RefreshPlayerLocationPins()
	local pin, chat = Pin(a, "map"), Frame(a, a.tooltipParent)
	pin.frame.scripts.OnEnter()
	assert(a:ShowChatLogPlayerTooltip(chat, "questtogetherlog:" .. row.name))
	local function HasLabel(state)
		assert(not (state.tooltipLabel.text or ""):find("Location sharing is off", 1, true))
		return (state.tooltipIntro.text or ""):find("Location sharing is off", 1, true) ~= nil
	end
	assert(not HasLabel(a.locationPinState) and not HasLabel(a.chatLogPlayerTooltipState))
	assert(pin.glow[1].shown)
	Near(pin.glow[1].color[2], 0.12)
	Near(pin.glow[1].color[3], 0.12)
	showHidden = true
	a:RefreshPlayerLocationPins()
	a:UpdateChatLogPlayerTooltip()
	assert(HasLabel(a.locationPinState) and HasLabel(a.chatLogPlayerTooltipState))
	assert(pin.glow[1].shown and not pin.developerGear.shown)
	showHidden = false
	a:RefreshPlayerLocationPins()
	a:UpdateChatLogPlayerTooltip()
	assert(not HasLabel(a.locationPinState) and not HasLabel(a.chatLogPlayerTooltipState))
	assert(pin.glow[1].shown)
	Near(pin.glow[1].color[2], 0.12)
	-- A developer-only visible dot can be selected without entering the public
	-- location store. Removing it from the authorized view retires selection.
	a.playerLocationState.peers[row.name] = nil
	pin.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.playerMapSelection.name, row.name)
	assert(pin.selected and pin.glow[1].shown)
	Near(pin.glow[1].color[2], 1)
	Equal(a.playerLocationState.peers[row.name], nil)
	a.rows.map = {}
	a:RefreshPlayerLocationPins()
	Equal(a.playerMapSelection, nil)
	assert(not pin.frame:IsVisible())
	a.rows.map = { row }
	a:RefreshPlayerLocationPins()
	assert(not pin.selected and pin.glow[1].shown)
	Near(pin.glow[1].color[2], 0.12)
end)

local function FindMenuFixture()
	local a = ClusterFixture(1)
	local row = a.rows.map[1]
	a.playerLocationState = { peers = { [row.name] = row } }
	function a:IsSelfSender(name) return name == self.selfName end
	function a:IsGroupedSender(name) return name == self.grouped end
	function a:IsPlayerLookingForQuestPartners() return false end
	function a:ShouldRequestPartyJoin() return false end
	function a:PopulatePlayerNotesMenu() end
	function a:PopulatePartyFocusMenu() end
	function a:Print(message) self.lastMessage = message end
	function a:RefreshPlayerLocationPins() self.refreshes = (self.refreshes or 0) + 1 end
	a.API.OpenPlayerLocationMap = function(mapID)
		a.openedMaps = (a.openedMaps or 0) + 1
		a.openedMapID = mapID
		return true
	end
	return a, row
end

local function FindMenuAction(a, name)
	local buttons = {}
	local root = {
		CreateTitle = function() end,
		CreateButton = function(_, label, callback) buttons[label] = callback end,
	}
	assert(a:PopulateChatLogSpeakerMenu(root, a.tooltipParent, name))
	return buttons["Find on Map"]
end

Register("Find on Map menu requires a fresh eligible public location even when private diagnostic coordinates exist", function()
	for _, scenario in ipairs({ "public", "privateOnly", "withdrawn", "minimapOnly", "expired", "ignored", "grouped", "self", "disabled", "partyOnly", "restricted" }) do
		local a, row = FindMenuFixture()
		local diagnostic = Row(row.name)
		diagnostic.developerOnly, diagnostic.publicLocationHidden = true, true
		a.isLocalDeveloper = true
		a.developerPlayerData = { [row.name] = diagnostic }
		if scenario == "privateOnly" then
			a.playerLocationState.peers[row.name] = nil
			a.rows.map = { diagnostic }
		elseif scenario == "withdrawn" then row.mask = 0
		elseif scenario == "minimapOnly" then row.mask = 2
		elseif scenario == "expired" then row.receivedAt = -30
		elseif scenario == "ignored" then a.ignored = row.name
		elseif scenario == "grouped" then a.grouped = row.name
		elseif scenario == "self" then a.selfName = row.name
		elseif scenario == "disabled" then a.clusterOptions.showPlayerLocations = false
		elseif scenario == "partyOnly" then a.clusterOptions.mapPartyOnly = true
		elseif scenario == "restricted" then a.blocked = true end
		Equal(FindMenuAction(a, row.name) ~= nil, scenario == "public")
		Equal(a.openedMaps, nil)
	end
end)

Register("Find on Map menu callback revalidates public consent and freshness before opening the map", function()
	local a, row = FindMenuFixture()
	local action = assert(FindMenuAction(a, row.name))
	action()
	Equal(a.openedMaps, 1)
	Equal(a.openedMapID, row.mapID)
	Equal(a.playerMapSelection.name, row.name)
	a:ClearPlayerMapSelection()
	row.mask = 0
	action()
	Equal(a.openedMaps, 1)
	Equal(a.playerMapSelection, nil)
	assert(a.lastMessage)
	row.mask, row.receivedAt = 3, -30
	action()
	Equal(a.openedMaps, 1)
	Equal(a.playerMapSelection, nil)
end)

Register("found player shares the status halo restores gold after selection and retires visibility when map closes", function()
	local a = Fixture()
	local found = Row("Found-Realm")
	function a:GetFindPlayerMapLocation() return found end
	a.playerMapSelection = { name = found.name, mapID = 1, expires = 120 }
	-- Normal filtered rows intentionally omit the selected non-LFQP player.
	a.rows.map = { Row("A-Realm"), Row("B-Realm", 0.501) }
	a:RefreshPlayerLocationPins()
	local selected, cluster = Pin(a, "map"), Pin(a, "map", 2)
	Equal(selected.name, "Found-Realm")
	assert(selected.selected and selected.glow[1].shown)
	assert(selected.frame.level > cluster.frame.level)
	Equal(#cluster.cluster.members, 2)
	local green = {}
	for index, glow in ipairs(selected.glow) do
		assert(glow.shown)
		Near(glow.color[1], 0.2)
		Near(glow.color[2], 1)
		green[index] = { width = glow.width, alpha = glow.color[4] }
	end
	-- Find can reveal a public player omitted by ordinary display filters.
	-- Clicking that selected dot must retain the Find override at every level.
	a.now = 105
	a.API.GetTime = function() return a.now end
	function a:GetLocationPinMapPosition(row) return row.x, row.y end
	function a:GetPlayerLocationMapNavigationTarget() return 2 end
	selected.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.openedMapID, 2)
	Equal(a.playerMapSelection.name, found.name)
	Equal(a.playerMapSelection.expires, 165)
	assert(not a.playerMapSelection.visibleOnly)
	assert(selected.selected and selected.frame:IsVisible())
	Equal(#a.menus, 0)
	a.now = 110
	selected.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.playerMapSelection.expires, 170)
	Equal(a.menus[1].name, found.name)
	Equal(a.menus[1].owner, selected.frame)
	local selection = a.playerMapSelection
	a.now = 115
	selected.frame.scripts.OnClick(nil, "RightButton")
	Equal(a.menus[2].name, found.name)
	Equal(a.playerMapSelection, selection)
	Equal(selection.expires, 170)
	-- Selection must override LFQP using the same regions, then return to
	-- gold without needing the occupant's identity or status to change.
	function a:IsPlayerLookingForQuestPartners(name) return name == found.name end
	a.rows.map = { found }
	a:RefreshPlayerLocationPins()
	Near(selected.glow[1].color[2], 1)
	a:ClearPlayerMapSelection()
	a:RefreshPlayerLocationPins()
	Equal(Pin(a, "map"), selected)
	assert(not selected.selected)
	for index, glow in ipairs(selected.glow) do
		assert(glow.shown)
		Near(glow.color[1], 1)
		Near(glow.color[2], 0.8)
		Near(glow.width, green[index].width)
		Near(glow.color[4], green[index].alpha)
	end
	a.playerMapSelection = { name = found.name, mapID = 1, expires = 120 }
	a.rows.map = { Row("A-Realm"), Row("B-Realm", 0.501) }
	a:RefreshPlayerLocationPins()
	Near(selected.glow[1].color[2], 1)
	local geometry = a.geometry.map
	local expires = a.playerMapSelection.expires
	-- A visible map may temporarily have no geometry while moving between
	-- levels. Keep the same deadline and restore the selected, unclustered dot.
	a.mapVisibleDuringTransition = true
	a.geometry.map = nil
	a:RefreshPlayerLocationPins()
	Equal(a.playerMapSelection.expires, expires)
	assert(not selected.frame:IsVisible())
	a.geometry.map = geometry
	function a:GetLocationPinMapPosition(row) return row.x, row.y end
	for _, mapID in ipairs({ 2, 1 }) do
		geometry.mapID = mapID
		a:RefreshPlayerLocationPins()
		Equal(a.playerMapSelection.expires, expires)
		Equal(Pin(a, "map"), selected)
		assert(selected.selected and selected.frame:IsVisible())
		Near(selected.glow[1].color[2], 1)
	end
	a.mapVisibleDuringTransition = nil
	a.geometry.map = nil
	a:RefreshPlayerLocationPins()
	Equal(a.playerMapSelection, nil)
	a.geometry.map = geometry
	a:RefreshPlayerLocationPins()
	assert(not selected.selected and not selected.glow[1].shown)
	Equal(#selected.cluster.members, 2)
end)

Register("location rendering expires delayed samples without renewing their original leases", function()
	local a = ClusterFixture(0)
	a.now = 699
	a.API.GetTime = function() return a.now end
	local old, recent = Row("Friend-Realm"), Row("Unrelated-Realm", 0.54)
	old.sampledAt, old.receivedAt, old.lifetime = 100, 300, 400
	recent.sampledAt, recent.receivedAt, recent.lifetime = 350, 350, 600
	a.playerLocationState = { peers = { [old.name] = old, [recent.name] = recent } }
	a.GetVisiblePlayerLocations = QuestTogether.GetVisiblePlayerLocations
	function a:IsSelfSender() return false end
	function a:IsGroupedSender() return false end
	a:RefreshPlayerLocationPins()
	for _, surface in ipairs({ "map", "minimap" }) do
		assert(Pin(a, surface).frame:IsVisible() and Pin(a, surface, 2).frame:IsVisible())
	end
	Equal(old.receivedAt, 300)
	Equal(old.lifetime, 400)
	a.now = 700
	Equal(a:GetFreshPlayerLocation(old.name, "map"), nil)
	a:RefreshPlayerLocationPins()
	Equal(a.playerLocationState.peers[old.name], nil)
	for _, surface in ipairs({ "map", "minimap" }) do
		Equal(Pin(a, surface).name, recent.name)
		assert(Pin(a, surface).frame:IsVisible() and not Pin(a, surface, 2).frame:IsVisible())
	end
	a.now = 950
	a:RefreshPlayerLocationPins()
	Equal(a.playerLocationState.peers[recent.name], nil)
	assert(not a.locationPinState.surfaces.map.frame:IsVisible())
	assert(not a.locationPinState.surfaces.minimap.frame:IsVisible())
end)

local function ClusterDimmingFixture()
	local a = ClusterFixture(0)
	VisualParty(a)
	a.API.GetTime = function() return 400 end
	a.rows.map = {
		Row("Friend-Realm"), Row("Leader-Realm", 0.501), Row("InnerOther-Realm", 0.502),
		Row("DistantA-Realm", 0.7), Row("DistantB-Realm", 0.701), Row("Solo-Realm", 0.9),
	}
	a.rows.minimap = { Row("Third-Realm"), Row("MiniOther-Realm", 0.501) }
	local selected = Row("Found-Realm", 0.8)
	function a:GetFindPlayerMapLocation() return selected end
	a.playerMapSelection = { name = selected.name, mapID = 1, expires = 420 }
	for _, rows in ipairs({ a.rows.map, a.rows.minimap, { selected } }) do
		for _, row in ipairs(rows) do row.sampledAt, row.lifetime = 100, 600 end
	end
	return a
end

local function MapClusterContaining(a, name)
	for _, pin in ipairs(VisibleMapPins(a)) do
		for _, row in ipairs(pin.cluster and pin.cluster.members or {}) do
			if row.name == name then return pin end
		end
	end
end

local function MapPlayerNamed(a, name)
	for _, pin in ipairs(VisibleMapPins(a)) do
		if pin.name == name then return pin end
	end
end

Register("expanded cluster shades the owned map below fully bright active dots without intercepting input", function()
	local a = ClusterDimmingFixture()
	a:RefreshPlayerLocationPins()
	local base = 1
	MapClusterContaining(a, "Friend-Realm").frame.scripts.OnClick(nil, "LeftButton")
	local active = assert(MapClusterContaining(a, "Friend-Realm"))
	local other = assert(MapClusterContaining(a, "DistantA-Realm"))
	local friend = assert(ExpandedPlayerPin(a, "Friend-Realm"))
	local leader = assert(ExpandedPlayerPin(a, "Leader-Realm"))
	local innerOther = assert(ExpandedPlayerPin(a, "InnerOther-Realm"))
	local solo, selected = assert(MapPlayerNamed(a, "Solo-Realm")), assert(MapPlayerNamed(a, "Found-Realm"))
	local surface = a.locationPinState.surfaces.map
	local shade, texture = FocusShade(a), assert(a.mapOverlayFocusState.texture)
	Equal(shade.allPoints, a.mapParent)
	Equal(shade.mouseEnabled, false)
	Equal(shade.mouseWheel, false)
	Equal(shade.scripts.OnClick, nil)
	Equal(texture.parent, shade)
	Equal(texture.allPoints, shade)
	Equal(texture.layer, "BACKGROUND")
	Equal(texture.color[1], 0)
	Equal(texture.color[2], 0)
	Equal(texture.color[3], 0)
	Near(texture.color[4], 0.22)
	assert(shade:IsVisible())
	assert(active.frame.level > shade.level)
	Near(active.frame.alpha, base)
	for _, pin in ipairs({ friend, leader, innerOther }) do
		assert(pin.frame.level > shade.level)
		Near(pin.frame.alpha, base)
		Near(pin.connector.alpha, pin.frame.alpha)
		Equal(pin.connector.parent, shade)
		Equal(pin.connector.layer, "OVERLAY")
		assert(pin.connector:IsVisible())
	end
	FocusedAboveShade(a, { active, friend, leader, innerOther }, { other, solo, selected })
	assert(selected.selected and selected.glow[1].shown)
	Equal(a.locationPinState.surfaces.minimap.clusterShade, nil)
	local miniParty, miniOther = Pin(a, "minimap"), Pin(a, "minimap", 2)
	Near(miniParty.frame.alpha, base)
	Near(miniOther.frame.alpha, base)
	friend.frame.scripts.OnEnter()
	Near(active.frame.alpha, base)
	Near(friend.frame.alpha, base)
	Near(leader.frame.alpha, base)
	Near(innerOther.frame.alpha, base * 0.45)
	assert(innerOther.connector.alpha < base)
	Near(other.frame.alpha, base * 0.45)
	Near(solo.frame.alpha, base * 0.45)
	Near(selected.frame.alpha, base * 0.45)
	FocusedAboveShade(a, { friend, leader }, { innerOther, other, solo, selected })
	Near(miniParty.frame.alpha, base)
	Near(miniOther.frame.alpha, base * 0.45)
	friend.frame.scripts.OnLeave()
	Near(innerOther.frame.alpha, base)
	Near(innerOther.connector.alpha, base)
	for _, pin in ipairs({ other, solo, selected }) do Near(pin.frame.alpha, base * 0.78) end
	FocusedAboveShade(a, { active, friend, leader, innerOther }, { other, solo, selected })
	miniOther.frame.scripts.OnEnter()
	FocusedAboveShade(a, { active, friend, leader, innerOther }, { other, solo, selected })
	miniOther.frame.scripts.OnLeave()
	Near(miniParty.frame.alpha, base)
	Near(miniOther.frame.alpha, base)
	active.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(shade.shown, false)
	for _, pin in ipairs(VisibleMapPins(a)) do Near(pin.frame.alpha, base) end
	local restoredSelected = assert(MapPlayerNamed(a, "Found-Realm"))
	assert(restoredSelected.frame.level > MapClusterContaining(a, "Friend-Realm").frame.level)
	AssertNoVisibleConnectors(a)
	local frameCount, regionCount = #a.frames, #a.regions
	MapClusterContaining(a, "Friend-Realm").frame.scripts.OnClick(nil, "LeftButton")
	Equal(surface.clusterShade, shade)
	Equal(a.mapOverlayFocusState.texture, texture)
	assert(shade:IsVisible())
	Equal(#a.frames, frameCount)
	Equal(#a.regions, regionCount)
end)

Register("map shade clears on close restrictions disabled clustering and addon disable and reuses its owned frame", function()
	for _, change in ipairs({ "hidden", "restricted", "clusteringOff", "disabled" }) do
		local a = ClusterDimmingFixture()
		a:RefreshPlayerLocationPins()
		MapClusterContaining(a, "Friend-Realm").frame.scripts.OnClick(nil, "LeftButton")
		local other = assert(MapClusterContaining(a, "DistantA-Realm"))
		local surface = a.locationPinState.surfaces.map
		local shade = assert(surface.clusterShade)
		FocusedAboveShade(a, { ExpandedPlayerPin(a) }, { other })
		if change == "hidden" then a.mapParent:Hide()
		elseif change == "restricted" then a.blocked = true
		elseif change == "clusteringOff" then a.clusterOptions.clusterPlayerLocations = false
		else a.isEnabled = false end
		a:RefreshPlayerLocationPins()
		Equal(a.playerLocationClusterExpansion, nil)
		Equal(a.locationPinState.surfaces.map.expandedClusterKey, nil)
		Equal(shade.shown, false)
		AssertNoVisibleConnectors(a)
		a.blocked, a.isEnabled = false, true
		a.clusterOptions.clusterPlayerLocations = true
		a.mapParent:Show()
		a:RefreshPlayerLocationPins()
		for _, pin in ipairs(VisibleMapPins(a)) do
			assert(not pin.expansion)
			Near(pin.frame.alpha, pin.baseAlpha)
		end
		for _, pin in ipairs(a.locationPinState.surfaces.minimap.pins) do
			if pin.frame:IsVisible() then Near(pin.frame.alpha, pin.baseAlpha) end
		end
		AssertNoVisibleConnectors(a)
		Equal(surface.clusterShade, shade)
		Equal(shade.shown, false)
		MapClusterContaining(a, "Friend-Realm").frame.scripts.OnClick(nil, "LeftButton")
		Equal(surface.clusterShade, shade)
		assert(shade:IsVisible())
		Equal(a.locationPinState.surfaces.minimap.clusterShade, nil)
	end
end)

Register("expanded map shade rises above native pin levels and restores the ordinary owned level on collapse", function()
	local a = ClusterFixture()
	a.geometry.map.pinFrameLevel = 2300
	a.rows.minimap = { Row("Mini-Realm") }
	a:RefreshPlayerLocationPins()
	local surface = a.locationPinState.surfaces.map
	local ordinaryLevel = surface.frame.level
	local minimapLevel = a.locationPinState.surfaces.minimap.frame.level
	local parentWrites = a.mapParent.writes
	assert(ordinaryLevel < 2300)
	Pin(a, "map").frame.scripts.OnClick(nil, "LeftButton")
	local shade = assert(surface.clusterShade)
	assert(surface.frame.level > shade.level, "the clipped marker host must rise above the shade")
	assert(shade.level > 2300)
	assert(Pin(a, "map").frame.level > shade.level)
	assert(ExpandedPlayerPin(a).frame.level > shade.level)
	Equal(a.locationPinState.surfaces.minimap.frame.level, minimapLevel)
	Equal(a.mapParent.writes, parentWrites)
	Pin(a, "map").frame.scripts.OnClick(nil, "LeftButton")
	Equal(surface.frame.level, ordinaryLevel)
	Equal(shade.shown, false)
	Equal(a.mapParent.writes, parentWrites)
	AssertNoVisibleConnectors(a)
end)

local function MapControlFixture(count)
	local a = WaypointFixture(ClusterFixture(count))
	a.db = { profile = {}, global = {} }
	for key, value in pairs(QuestTogether.DEFAULTS.profile) do a.db.profile[key] = value end
	a.db.profile.showWorldMapData = true
	a.db.profile.sharePlayerLocation = false
	a.db.profile.onlyShowQuestPartners = true
	a.sharingChanges = 0
	function a:OnPlayerLocationOptionsChanged() self.sharingChanges = self.sharingChanges + 1 end
	function a:OnNearbyLocationOptionsChanged() self.sharingChanges = self.sharingChanges + 1 end
	function a:BroadcastPlayerLocation() self.sharingChanges = self.sharingChanges + 1 end
	function a:BroadcastQuestPartnerStatus() self.sharingChanges = self.sharingChanges + 1 end
	function a:Print(message) self.lastMessage = message end
	return a
end

Register("owned map data button remains available without peers and follows the viewport across close and resize", function()
	local a = MapControlFixture(0)
	a.waypoints = {}
	a:RefreshPlayerLocationPins()
	a:RefreshQuestTogetherMapControl()
	local state = assert(a.mapDataControlState)
	local button = assert(state.button)
	assert(button:IsVisible())
	Equal(button.parent, a.mapParent)
	Equal(button.width, 26)
	Equal(button.height, 26)
	Equal(state.icon.width, 24)
	Near(state.icon.alpha, 1)
	assert(not state.hiddenMark:IsVisible())
	Equal(button.points[1][1], "TOPRIGHT")
	Equal(button.points[1][2], a.mapParent)
	Equal(button.points[1][3], "TOPRIGHT")
	Equal(button.points[1][4], -8)
	Equal(button.points[1][5], -8)
	assert(a:IsQuestTogetherMapDataShown("map") and a:IsQuestTogetherMapDataShown("minimap"))
	button.scripts.OnClick(button, "LeftButton")
	Equal(a.db.profile.showWorldMapData, false)
	assert(button:IsVisible())
	Near(state.icon.alpha, 1)
	assert(state.hiddenMark:IsVisible())
	assert(not a:IsQuestTogetherMapDataShown("map") and a:IsQuestTogetherMapDataShown("minimap"))
	Equal(a.db.profile.sharePlayerLocation, false)
	Equal(a.db.profile.onlyShowQuestPartners, true)
	Equal(a.sharingChanges, 0)
	local frames = #a.frames
	a.geometry.map.width, a.geometry.map.height = 800, 450
	a:RefreshQuestTogetherMapControl()
	Equal(a.mapDataControlState.button, button)
	Equal(button.points[1][2], a.mapParent)
	Equal(#a.frames, frames)
	a.mapParent:Hide()
	a:RefreshQuestTogetherMapControl()
	assert(not button:IsVisible())
	a.mapParent:Show()
	a:RefreshQuestTogetherMapControl()
	assert(button:IsVisible())
	Near(state.icon.alpha, 1)
	assert(state.hiddenMark:IsVisible())
	Equal(#a.frames, frames)
	button.scripts.OnClick(button, "LeftButton")
	Equal(a.db.profile.showWorldMapData, true)
	Near(state.icon.alpha, 1)
	assert(not state.hiddenMark:IsVisible())
	Equal(a.sharingChanges, 0)
	Equal(a.mapParent.writes, 2)
end)

Register("map data toggle clears map players expansion selection and waypoint hover while minimap data and preferences remain", function()
	local a = MapControlFixture(2)
	a.rows.minimap = { Row("Mini-Realm") }
	local selected = Row("Found-Realm", 0.8)
	function a:GetFindPlayerMapLocation() return selected end
	a.playerMapSelection = { name = selected.name, mapID = 1, expires = 120 }
	a:RefreshPlayerLocationPins()
	a:RefreshPartyWaypointPins()
	a:RefreshQuestTogetherMapControl()
	MapClusterContaining(a, "Peer001-Realm").frame.scripts.OnClick(nil, "LeftButton")
	local member = assert(ExpandedPlayerPin(a, "Peer001-Realm"))
	member.frame.scripts.OnEnter()
	local playerState, waypointState = a.locationPinState, a.partyWaypointPinState
	local interest = assert(a.playerDetailsState.interests[playerState])
	waypointState.surfaces.map.pins[1].frame.scripts.OnEnter()
	assert(waypointState.hovered and waypointState.tooltip:IsVisible())
	local mini = Pin(a, "minimap")
	local miniWaypoint = waypointState.surfaces.minimap.pins[1]
	local control = a.mapDataControlState
	control.button.scripts.OnClick(control.button, "LeftButton")
	Equal(a.db.profile.showWorldMapData, false)
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(a.playerMapSelection, nil)
	Equal(playerState.hovered, nil)
	Equal(a.playerDetailsState.interests[playerState], nil)
	assert(not interest.isCurrent())
	Equal(#VisibleMapPins(a), 0)
	Equal(playerState.surfaces.map.clusterShade.shown, false)
	Equal(waypointState.hovered, nil)
	assert(not waypointState.tooltip:IsVisible())
	assert(not waypointState.surfaces.map.frame:IsVisible())
	assert(mini.frame:IsVisible() and miniWaypoint.frame:IsVisible())
	assert(control.button:IsVisible())
	Near(control.icon.alpha, 1)
	assert(control.hiddenMark:IsVisible())
	Equal(a.db.profile.sharePlayerLocation, false)
	Equal(a.db.profile.onlyShowQuestPartners, true)
	Equal(a:GetOption("showPlayerLocations"), true)
	Equal(a:GetOption("clusterPlayerLocations"), true)
	Equal(a.sharingChanges, 0)
	a:UpdatePlayerDetailsInterests()
	Equal(#a.requests, 1)
	mini.frame.scripts.OnEnter()
	Equal(a.targetHover.name, "Mini-Realm")
	assert(a.targetHover.isCurrent())
	control.button.scripts.OnClick(control.button, "LeftButton")
	assert(a:IsQuestTogetherMapDataShown("map"))
	Near(control.icon.alpha, 1)
	assert(not control.hiddenMark:IsVisible())
	assert(MapClusterContaining(a, "Peer001-Realm"))
	assert(waypointState.surfaces.map.frame:IsVisible())
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(a.playerMapSelection, nil)
	Equal(Pin(a, "minimap"), mini)
	Equal(a.sharingChanges, 0)
end)

Register("map data button hides safely for restrictions disable and forbidden parents and rejects stale clicks", function()
	for _, change in ipairs({ "restricted", "disabled", "hidden", "forbidden" }) do
		local a = MapControlFixture(0)
		a.waypoints = {}
		a:RefreshQuestTogetherMapControl()
		local button = a.mapDataControlState.button
		if change == "restricted" then a.blocked = true
		elseif change == "disabled" then a.isEnabled = false
		elseif change == "hidden" then a.mapParent:Hide()
		else a.mapParent.forbidden = true end
		a:RefreshQuestTogetherMapControl()
		button.scripts.OnClick(button, "LeftButton")
		Equal(a.db.profile.showWorldMapData, true)
		if change ~= "forbidden" then assert(not button:IsVisible()) end
		a.blocked, a.isEnabled, a.mapParent.forbidden = false, true, false
		a.mapParent:Show()
		a:RefreshQuestTogetherMapControl()
		Equal(a.mapDataControlState.button, button)
		assert(button:IsVisible())
	end
end)

Register("Find on Map restores map data only after verified native navigation and keeps sharing preferences", function()
	local a = MapControlFixture(1)
	local row = a.rows.map[1]
	a.playerLocationState = { peers = { [row.name] = row } }
	function a:IsGroupedSender() return false end
	function a:IsSelfSender() return false end
	a.API.OpenPlayerLocationMap = function(mapID)
		Equal(mapID, row.mapID)
		return a.allowMapOpen == true
	end
	assert(a:SetOption("showWorldMapData", false))
	Equal(a:FindPlayerOnMap(row.name), false)
	Equal(a.db.profile.showWorldMapData, false)
	a.allowMapOpen = true
	assert(a:FindPlayerOnMap(row.name))
	Equal(a.db.profile.showWorldMapData, true)
	Equal(a.playerMapSelection.name, row.name)
	Equal(a.db.profile.sharePlayerLocation, false)
	Equal(a.db.profile.onlyShowQuestPartners, true)
	Equal(a.sharingChanges, 0)
	assert(a:SetOption("showWorldMapData", false))
	row.mask = 0
	Equal(a:FindPlayerOnMap(row.name), false)
	Equal(a.db.profile.showWorldMapData, false)
end)

Register("cluster clicks open more detailed maps before fanout while expanded paging and collapse stay direct", function()
	local a = ClusterFixture(20)
	a.navigationAction, a.navigationClicks = "navigate", 0
	function a:GetPlayerLocationClusterNavigationAction() return self.navigationAction end
	function a:TryNavigatePlayerLocationCluster(cluster, geometry)
		self.navigationClicks = self.navigationClicks + 1
		Equal(geometry, self.geometry.map)
		Equal(#cluster.members, 20)
		return self.navigationAction ~= "expand"
	end
	a:RefreshPlayerLocationPins()
	local cluster = Pin(a, "map")
	cluster.frame.scripts.OnEnter()
	assert(a.locationPinState.clusterTooltip.tooltipLabel.text:find("Click to open a more detailed map.", 1, true))
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.navigationClicks, 1)
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(ExpandedPlayerPin(a), nil)
	Equal(a.locationPinState.surfaces.map.clusterShade, nil)
	Equal(#a.requests, 0)
	a.navigationAction = "expand"
	cluster.frame.scripts.OnEnter()
	assert(a.locationPinState.clusterTooltip.tooltipLabel.text:find("Click to expand players.", 1, true))
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.navigationClicks, 2)
	assert(ExpandedPlayerPin(a))
	assert(a.locationPinState.surfaces.map.clusterShade:IsVisible())
	a.navigationAction = "navigate"
	cluster.frame.scripts.OnMouseWheel(nil, -1)
	Equal(cluster.cluster.expansionInfo.page, 2)
	Equal(a.navigationClicks, 2)
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(a.navigationClicks, 2)
	AssertNoVisibleConnectors(a)
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.navigationClicks, 3)
	Equal(a.playerLocationClusterExpansion, nil)
end)

Register("unavailable cluster navigation consumes the click without showing a premature expansion", function()
	local a = ClusterFixture()
	function a:GetPlayerLocationClusterNavigationAction() return "unavailable" end
	function a:TryNavigatePlayerLocationCluster()
		self.navigationClicks = (self.navigationClicks or 0) + 1
		return true
	end
	a:RefreshPlayerLocationPins()
	local cluster = Pin(a, "map")
	cluster.frame.scripts.OnEnter()
	assert(not a.locationPinState.clusterTooltip.tooltipLabel.text:find("Click to expand", 1, true))
	local frames = #a.frames
	cluster.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.navigationClicks, 1)
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(#VisibleMapPins(a), 1)
	Equal(#a.frames, frames)
	Equal(a.locationPinState.surfaces.map.clusterShade, nil)
end)

Register("stale hidden disabled and restricted cluster clicks cannot invoke the map navigation adapter", function()
	for _, change in ipairs({ "membership", "hidden", "dataOff", "disabled", "restricted" }) do
		local a = ClusterFixture()
		function a:TryNavigatePlayerLocationCluster()
			self.navigationClicks = (self.navigationClicks or 0) + 1
			return true
		end
		a:RefreshPlayerLocationPins()
		local click = Pin(a, "map").frame.scripts.OnClick
		if change == "membership" then a.rows.map = { Row("Replacement-Realm") }
		elseif change == "hidden" then a.mapParent:Hide()
		elseif change == "dataOff" then a.clusterOptions.showWorldMapData = false
		elseif change == "disabled" then a.isEnabled = false
		else a.blocked = true end
		click(nil, "LeftButton")
		Equal(a.navigationClicks, nil)
		Equal(a.playerLocationClusterExpansion, nil)
	end
end)

Register("map logo hover shows only its legend with map data visible or hidden", function()
	for _, mode in ipairs({ "empty", "hiddenData" }) do
		local a = MapControlFixture(mode == "empty" and 0 or 2)
		if mode == "empty" then a.waypoints = {} end
		if mode == "hiddenData" then assert(a:SetOption("showWorldMapData", false)) end
		a.geometry.map.pinFrameLevel = 2300
		a:RefreshPlayerLocationPins()
		a:RefreshPartyWaypointPins()
		a:RefreshQuestTogetherMapControl()
		local state = a.mapDataControlState
		NoFocusShade(a)
		state.button.scripts.OnEnter()
		local shade = state.shade
		assert(state.tip.tooltip:IsVisible())
		assert(state.tip.legendRows[1].frame:IsVisible())
		Near(state.icon.alpha, 1)
		assert(not shade or not shade:IsVisible())
		NoFocusShade(a)
		Equal(state.hiddenMark:IsVisible(), mode == "hiddenData")
		assert(state.tip.tooltipIntro.text:find(mode == "hiddenData" and "Click to show" or "Click to hide", 1, true))
		assert(not a.locationPinState or not next(a.locationPinState.surfaces))
		assert(not a.partyWaypointPinState or not a.partyWaypointPinState.surfaces.map)
		Equal(#a.requests, 0)
		Equal(a.sharingChanges, 0)
		local frames, regions = #a.frames, #a.regions
		state.button.scripts.OnLeave()
		NoFocusShade(a)
		assert(not shade or not shade:IsVisible())
		assert(not state.tip.tooltip:IsVisible())
		state.button.scripts.OnEnter()
		Equal(state.shade, shade)
		assert(not shade or not shade:IsVisible())
		Equal(#a.frames, frames)
		Equal(#a.regions, regions)
		state.button.scripts.OnHide()
		assert(not shade or not shade:IsVisible())
		NoFocusShade(a)
		Equal(a.mapParent.writes, 0)
	end
end)

Register("clicking the hovered map logo swaps marker visibility and the hidden mark without creating shade", function()
	local a = MapControlFixture(2)
	a.rows.minimap = { Row("Mini-Realm") }
	a:RefreshPlayerLocationPins()
	a:RefreshPartyWaypointPins()
	a:RefreshQuestTogetherMapControl()
	local state = a.mapDataControlState
	state.button.scripts.OnEnter()
	local mark = state.hiddenMark
	Equal(state.shade, nil)
	assert(not mark:IsVisible())
	local frames, regions = #a.frames, #a.regions
	state.button.scripts.OnClick(state.button, "LeftButton")
	assert(state.hovered and state.tip.tooltip:IsVisible())
	assert(state.tip.tooltipIntro.text:find("Click to show", 1, true))
	Equal(state.shade, nil)
	assert(mark:IsVisible())
	NoFocusShade(a)
	Near(state.icon.alpha, 1)
	Equal(#VisibleMapPins(a), 0)
	assert(Pin(a, "minimap").frame:IsVisible())
	state.button.scripts.OnClick(state.button, "LeftButton")
	Equal(state.shade, nil)
	assert(not mark:IsVisible())
	assert(state.tip.tooltipIntro.text:find("Click to hide", 1, true))
	NoFocusShade(a)
	Near(state.icon.alpha, 1)
	Equal(#a.frames, frames)
	Equal(#a.regions, regions)
	Equal(a.sharingChanges, 0)
end)

Register("map logo legend leaves existing map hover and expanded cluster shading unchanged", function()
	local a = MapControlFixture(0)
	VisualParty(a)
	a.API.GetTime = function() return 400 end
	a.geometry.map.pinFrameLevel = 2300
	a.rows.map = {
		Row("Friend-Realm"), Row("Leader-Realm", 0.501), Row("InnerOther-Realm", 0.502),
		Row("DistantA-Realm", 0.7), Row("DistantB-Realm", 0.701), Row("Solo-Realm", 0.9),
	}
	a.rows.minimap = { Row("Third-Realm"), Row("MiniOther-Realm", 0.501) }
	local selected = Row("Found-Realm", 0.8)
	function a:GetFindPlayerMapLocation() return selected end
	a.playerMapSelection = { name = selected.name, mapID = 1, expires = 420 }
	for _, rows in ipairs({ a.rows.map, a.rows.minimap, { selected } }) do
		for _, row in ipairs(rows) do row.sampledAt, row.lifetime = 100, 600 end
	end
	a:RefreshPlayerLocationPins()
	a:RefreshPartyWaypointPins()
	a:RefreshQuestTogetherMapControl()
	MapClusterContaining(a, "Friend-Realm").frame.scripts.OnClick(nil, "LeftButton")
	local surface, waypoints = a.locationPinState.surfaces.map, a.partyWaypointPinState.surfaces.map
	local ordinaryPlayerLevel, ordinaryWaypointLevel = surface.frame.level, waypoints.frame.level
	local miniSurface = a.locationPinState.surfaces.minimap
	local miniWaypointSurface = a.partyWaypointPinState.surfaces.minimap
	local miniLevel, miniWaypointLevel = miniSurface.frame.level, miniWaypointSurface.frame.level
	local friend = assert(ExpandedPlayerPin(a, "Friend-Realm"))
	friend.frame.scripts.OnEnter()
	local solo, inner = assert(MapPlayerNamed(a, "Solo-Realm")), assert(ExpandedPlayerPin(a, "InnerOther-Realm"))
	local base = solo.baseAlpha
	Near(base, 1)
	Near(solo.frame.alpha, base * 0.45)
	Near(inner.frame.alpha, base * 0.45)
	local shade = FocusedAboveShade(a, { friend, ExpandedPlayerPin(a, "Leader-Realm") }, { solo, inner })
	local shadeLevel = shade.level
	local control = a.mapDataControlState
	control.button.scripts.OnEnter()
	Equal(control.shade, nil)
	Equal(FocusShade(a), shade)
	Equal(shade.level, shadeLevel)
	FocusedAboveShade(a, { friend, ExpandedPlayerPin(a, "Leader-Realm") }, { solo, inner })
	assert(friend.connector:IsVisible())
	Near(friend.connector.alpha, base)
	assert(inner.connector.alpha < base)
	FocusedAboveShade(a, { friend }, waypoints.pins)
	Equal(miniSurface.frame.level, miniLevel)
	Equal(miniWaypointSurface.frame.level, miniWaypointLevel)
	Near(miniSurface.pins[2].frame.alpha, miniSurface.pins[2].baseAlpha * 0.45)
	Equal(#a.requests, 1)
	Equal(a.sharingChanges, 0)
	control.button.scripts.OnLeave()
	Equal(FocusShade(a), shade)
	Equal(surface.frame.level, ordinaryPlayerLevel)
	Equal(waypoints.frame.level, ordinaryWaypointLevel)
	FocusedAboveShade(a, { friend, ExpandedPlayerPin(a, "Leader-Realm") }, { solo, inner })
	assert(inner.connector.alpha < base)
	Equal(a.playerMapSelection.name, selected.name)
	assert(a.playerLocationClusterExpansion)
	-- A waypoint refresh must not undo the active player's marker fading.
	a:RefreshPartyWaypointPins()
	FocusedAboveShade(a, { friend }, waypoints.pins)
	-- A later waypoint hover wins across feature owners. The old player leave
	-- must not clear it, and one shared shade returns to expanded baseline.
	local waypoint = waypoints.pins[1]
	waypoint.frame.scripts.OnEnter()
	Equal(FocusShade(a), shade)
	FocusedAboveShade(a, waypoints.pins, { friend, inner, solo })
	friend.frame.scripts.OnLeave()
	a:RefreshPlayerLocationPins()
	FocusedAboveShade(a, waypoints.pins, { friend, inner, solo })
	waypoint.frame.scripts.OnLeave()
	Near(solo.frame.alpha, base * 0.78)
	FocusedAboveShade(a, { MapClusterContaining(a, "Friend-Realm"), friend, inner }, { solo })
	Near(inner.connector.alpha, base)
	Equal(a.mapParent.writes, 0)
end)

Register("map logo legend retires on lost currentness and stale callbacks cannot toggle data", function()
	for _, change in ipairs({ "hidden", "restricted", "disabled", "forbidden", "newParent" }) do
		local a = MapControlFixture(2)
		a:RefreshQuestTogetherMapControl()
		local control = a.mapDataControlState
		control.button.scripts.OnEnter()
		assert(control.tip.tooltip:IsVisible())
		Equal(control.shade, nil)
		if change == "hidden" then a.mapParent:Hide()
		elseif change == "restricted" then a.blocked = true
		elseif change == "disabled" then a.isEnabled = false
		elseif change == "forbidden" then a.mapParent.forbidden = true
		else a.geometry.map.parent = Frame(a) end
		NoFocusShade(a)
		control.button.scripts.OnEnter()
		control.button.scripts.OnClick(control.button, "LeftButton")
		Equal(a.db.profile.showWorldMapData, true)
		a:RefreshQuestTogetherMapControl()
		Equal(control.hovered, nil)
		assert(not control.tip.tooltip:IsVisible())
		Equal(control.shade, nil)
		a.blocked, a.isEnabled, a.mapParent.forbidden = false, true, false
		a.mapParent:Show()
		a:RefreshQuestTogetherMapControl()
		NoFocusShade(a)
		Equal(control.shade, nil)
		assert(control.button:IsVisible())
		control.button.scripts.OnEnter()
		Equal(control.shade, nil)
		assert(control.tip.tooltip:IsVisible())
	end
end)

local function NavigatingClusterFixture(count)
	local a = MapControlFixture(count)
	a.now, a.navigationCalls = 100, 0
	a.runtimeCoordinatorState, a.commsWorldGeneration = {}, 1
	a.API.GetTime = function() return a.now end
	function a:GetLocationPinMapPosition(row, target)
		local position = target == 2 and self.targetPositions and self.targetPositions[row.name]
		return position and position.x or row.x, position and position.y or row.y
	end
	function a:GetPlayerLocationClusterNavigationAction(_, geometry)
		return geometry.mapID == 1 and "navigate" or "expand", 2
	end
	function a:TryNavigatePlayerLocationCluster(cluster, geometry)
		self.navigationCalls = self.navigationCalls + 1
		if geometry.mapID ~= 1 then return false end
		local intent = assert(self:BeginPlayerLocationClusterNavigation(cluster, geometry, 2))
		self.lastNavigationIntent = intent
		intent.navigating = false
		if self.navigationFails then
			self:CancelPlayerLocationClusterNavigation(intent)
			return true
		end
		self.geometry.map.mapID = 2
		self.holdTargetRender = self.deferTargetRender == true
		return true
	end
	function a:RefreshPlayerLocationPins()
		-- Native navigation and display refresh are separate owned seams. Hold
		-- the latter to exercise invalidation before the target can consume it.
		if self.holdTargetRender then return false end
		return QuestTogether.RefreshPlayerLocationPins(self)
	end
	return a
end

Register("a surviving cluster automatically expands once after native map navigation and still pages and collapses normally", function()
	local a = NavigatingClusterFixture(20)
	a.rows.minimap = { Row("Mini-Realm") }
	a:RefreshPlayerLocationPins()
	local sourceKey = Pin(a, "map").cluster.key
	local mini = Pin(a, "minimap")
	Pin(a, "map").frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.navigationCalls, 1)
	Equal(a.geometry.map.mapID, 2)
	local expansion = assert(a.playerLocationClusterExpansion)
	Equal(expansion.key, sourceKey)
	Equal(expansion.geometry.mapID, 2)
	local center = assert(MapClusterContaining(a, "Peer001-Realm"))
	Equal(center.cluster.expansionInfo.page, 1)
	Equal(center.cluster.expansionInfo.total, 20)
	assert(ExpandedPlayerPin(a, "Peer001-Realm"))
	assert(a.locationPinState.surfaces.map.clusterShade:IsVisible())
	Equal(Pin(a, "minimap"), mini)
	assert(mini.frame:IsVisible())
	Equal(#a.requests, 0)
	for _, row in ipairs(a.rows.map) do Equal(row.mapID, 1); Near(row.x, 0.5); Near(row.y, 0.5) end
	a:RefreshPlayerLocationPins()
	Equal(a.playerLocationClusterExpansion, expansion)
	center.frame.scripts.OnMouseWheel(nil, -1)
	Equal(center.cluster.expansionInfo.page, 2)
	Equal(a.navigationCalls, 1)
	center.frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(a.navigationCalls, 1)
	a:RefreshPlayerLocationPins()
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(ExpandedPlayerPin(a), nil)
	AssertNoVisibleConnectors(a)
end)

Register("map navigation never expands a split or replaced cluster and cannot replay after its members return", function()
	for _, change in ipairs({ "split", "replaced" }) do
		local a = NavigatingClusterFixture(2)
		a.deferTargetRender = true
		a:RefreshPlayerLocationPins()
		Pin(a, "map").frame.scripts.OnClick(nil, "LeftButton")
		local original = a.rows.map
		if change == "split" then
			a.targetPositions = { [original[1].name] = { x = 0.25, y = 0.5 }, [original[2].name] = { x = 0.75, y = 0.5 } }
		else
			a.rows.map = { Row("ReplacementA-Realm"), Row("ReplacementB-Realm") }
		end
		a.holdTargetRender = false
		a:RefreshPlayerLocationPins()
		Equal(a.playerLocationClusterExpansion, nil)
		Equal(ExpandedPlayerPin(a), nil)
		Equal(#VisibleMapPins(a), change == "split" and 2 or 1)
		a.rows.map, a.targetPositions = original, nil
		a:RefreshPlayerLocationPins()
		Equal(a.playerLocationClusterExpansion, nil)
		Equal(ExpandedPlayerPin(a), nil)
		Equal(#VisibleMapPins(a), 1)
		Equal(a.navigationCalls, 1)
		AssertNoVisibleConnectors(a)
	end
end)

Register("pending map cluster expansion is canceled by view preference lifecycle profile and expiry changes", function()
	for _, change in ipairs({ "hidden", "dataOff", "clusteringOff", "disabled", "restricted", "profile", "otherMap", "sourceMap", "expired" }) do
		local a = NavigatingClusterFixture(2)
		a.deferTargetRender = true
		a:RefreshPlayerLocationPins()
		Pin(a, "map").frame.scripts.OnClick(nil, "LeftButton")
		assert(a.lastNavigationIntent)
		a.holdTargetRender = false
		if change == "hidden" then a.mapParent:Hide()
		elseif change == "dataOff" then assert(a:SetOption("showWorldMapData", false))
		elseif change == "clusteringOff" then a.clusterOptions.clusterPlayerLocations = false
		elseif change == "disabled" then a.isEnabled = false
		elseif change == "restricted" then a.blocked = true
		elseif change == "profile" then
			local profile = {}
			for key, value in pairs(a.db.profile) do profile[key] = value end
			a.db.profile = profile
		elseif change == "otherMap" then a.geometry.map.mapID = 3
		elseif change == "sourceMap" then a.geometry.map.mapID = 1
		else a.now = 103 end
		a:RefreshPlayerLocationPins()
		Equal(a.playerLocationClusterExpansion, nil)
		a.blocked, a.isEnabled = false, true
		a.mapParent:Show()
		a.db.profile.showWorldMapData, a.clusterOptions.clusterPlayerLocations = true, true
		a.geometry.map.mapID = 2
		a:RefreshPlayerLocationPins()
		Equal(a.playerLocationClusterExpansion, nil)
		Equal(ExpandedPlayerPin(a), nil)
		Equal(#VisibleMapPins(a), 1)
		AssertNoVisibleConnectors(a)
	end
end)

Register("failed native cluster navigation leaves no automatic expansion for a later map visit", function()
	local a = NavigatingClusterFixture(2)
	a.navigationFails = true
	a:RefreshPlayerLocationPins()
	Pin(a, "map").frame.scripts.OnClick(nil, "LeftButton")
	Equal(a.geometry.map.mapID, 1)
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(ExpandedPlayerPin(a), nil)
	a.geometry.map.mapID = 2
	a:RefreshPlayerLocationPins()
	Equal(a.playerLocationClusterExpansion, nil)
	Equal(ExpandedPlayerPin(a), nil)
	Equal(#VisibleMapPins(a), 1)
	AssertNoVisibleConnectors(a)
end)
