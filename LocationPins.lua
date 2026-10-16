local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether
local MAX_PINS, MAX_LOCATION_ROWS, DOT_SIZE = 128, 512, 12
local PARTNER_DOT_SIZE = 16

local function HasLocationGlow(addon, name, row)
	return addon:IsPlayerLookingForQuestPartners(name)
		or (row and row.developerOnly and (row.publicLocationHidden or row.lookingForQuestPartners))
end

local function PinSize(addon, name, row)
	if addon:IsVerifiedDeveloper(name) then return 18 end
	return HasLocationGlow(addon, name, row) and PARTNER_DOT_SIZE or DOT_SIZE
end

local function Native(addon, fn, ...)
	if addon:IsRuntimeRestricted() or not addon:CanAccessValue(fn) or type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then
		return a, b, c, d
	end
end

local function API(addon, namespace, name, ...)
	if not addon:CanAccessTable(namespace) then
		return nil
	end
	return Native(addon, namespace[name], ...)
end

local function Method(addon, frame, name, ...)
	return Native(addon, addon:GetAccessibleFrameMember(frame, name), frame, ...)
end

local function Number(addon, value)
	return addon:SafeToNumber(value)
end
local function Positive(addon, value)
	value = Number(addon, value)
	return value and value > 0 and value or nil
end
local function ID(addon, value)
	value = Positive(addon, value)
	return value and value == math.floor(value) and value or nil
end
local function Normalized(addon, value)
	value = Number(addon, value)
	return value and value >= 0 and value <= 1 and value or nil
end

local function XY(addon, vector)
	if not addon:CanAccessTable(vector) then
		return nil
	end
	local x, y = Native(addon, vector.GetXY, vector)
	return Number(addon, x), Number(addon, y)
end

-- All native access is behind addon-owned seams. UI tests use private frames
-- and primitive geometry; native return-shape tests run only in a subprocess.
function QuestTogether:CreateLocationPinFrame(...)
	return CreateFrame(...)
end

function QuestTogether:GetLocationPinTooltipParent()
	return UIParent
end

function QuestTogether:GetLocationPinMinimapShape()
	if not self:CanAccessValue(GetMinimapShape) then
		return nil
	end
	if GetMinimapShape == nil then
		return "ROUND"
	end
	local shape = self:SafeTrimString(Native(self, GetMinimapShape), "")
	if shape == "ROUND" or shape == "SQUARE" then
		return shape
	end
end

function QuestTogether:GetLocationPinWorldPosition(mapID, x, y)
	mapID, x, y = ID(self, mapID), Normalized(self, x), Normalized(self, y)
	if not mapID or not x or not y then
		return nil
	end
	local vector = Native(self, CreateVector2D, x, y)
	if not self:CanAccessTable(vector) then
		return nil
	end
	local continent, world = API(self, C_Map, "GetWorldPosFromMapPos", mapID, vector)
	continent = Number(self, continent)
	local north, west = XY(self, world)
	if continent and continent >= 0 and north and west then
		return continent, north, west
	end
end

function QuestTogether:GetLocationPinMapWorldSize(mapID)
	mapID = ID(self, mapID)
	if not mapID then return nil end
	local width, height = API(self, C_Map, "GetMapWorldSize", mapID)
	width, height = Positive(self, width), Positive(self, height)
	if width and height then return width, height end
	-- Some Classic clients omit the size API. Use half-map points rather than
	-- the 1/1 corner, which is inaccurate on some maps (HereBeDragons precedent).
	local instance, north, west = self:GetLocationPinWorldPosition(mapID, 0, 0)
	local centerInstance, centerNorth, centerWest = self:GetLocationPinWorldPosition(mapID, 0.5, 0.5)
	if instance and instance == centerInstance and north and west and centerNorth and centerWest then
		width, height = math.abs(west - centerWest) * 2, math.abs(north - centerNorth) * 2
		if width > 0 and height > 0 then return width, height end
	end
end

-- Distance ranking uses world coordinates, not map pixels or the viewed map
-- center. Read-only adapters also work when location sharing is turned off.
function QuestTogether:GetPlayerLocationPriorityOrigin()
	if self:IsRuntimeRestricted() then return nil end
	local mapID = ID(self, Native(self, self.API.GetBestMapForUnit, "player"))
	if not mapID then return nil end
	local position = Native(self, self.API.GetPlayerMapPosition, mapID, "player")
	if not self:CanAccessTable(position) then return nil end
	local x, y = Normalized(self, position.x), Normalized(self, position.y)
	if not x or not y then return nil end
	local continent, north, west = self:GetLocationPinWorldPosition(mapID, x, y)
	if continent and north and west then return { continent = continent, north = north, west = west } end
end

function QuestTogether:GetCachedPlayerLocationWorldPosition(row)
	if self:IsRuntimeRestricted() then return nil end
	local cache = rawget(self, "locationPriorityCache")
	if not cache then cache = setmetatable({}, { __mode = "k" }); self.locationPriorityCache = cache end
	local saved = cache[row]
	if saved and saved.mapID == row.mapID and saved.x == row.x and saved.y == row.y then
		return saved.continent, saved.north, saved.west
	end
	local continent, north, west = self:GetLocationPinWorldPosition(row.mapID, row.x, row.y)
	-- Do not cache a transient native failure; successful coordinates are fixed
	-- for this map and position and need not be projected for every admission.
	if continent and north and west then
		cache[row] = { mapID = row.mapID, x = row.x, y = row.y, continent = continent, north = north, west = west }
	end
	return continent, north, west
end

function QuestTogether:GetPlayerLocationPriorityDistance(row, origin)
	if not origin or row.mask == 0 then return math.huge end
	local continent, north, west = self:GetCachedPlayerLocationWorldPosition(row)
	if continent ~= origin.continent or not north or not west then return math.huge end
	return (north - origin.north)^2 + (west - origin.west)^2
end

function QuestTogether:PrioritizePlayerLocationRows(rows, origin)
	local ranked = {}
	for i = 1, math.min(MAX_LOCATION_ROWS, #rows) do
		local row = rows[i]
		ranked[i] = { row = row, distance = self:GetPlayerLocationPriorityDistance(row, origin) }
	end
	table.sort(ranked, function(a, b)
		if a.distance ~= b.distance then return a.distance < b.distance end
		return a.row.name < b.row.name
	end)
	local result = {}
	for i, entry in ipairs(ranked) do result[i] = entry.row end
	return result
end

function QuestTogether:GetLocationPinMapPosition(row, targetMapID)
	if row.mapID == targetMapID then
		return Normalized(self, row.x), Normalized(self, row.y)
	end
	local continent, north, west = self:GetLocationPinWorldPosition(row.mapID, row.x, row.y)
	if not continent then
		return nil
	end
	local vector = Native(self, CreateVector2D, north, west)
	if not self:CanAccessTable(vector) then
		return nil
	end
	local actualMapID, position = API(self, C_Map, "GetMapPosFromWorldPos", continent, vector, targetMapID)
	if ID(self, actualMapID) ~= targetMapID then
		return nil
	end
	local x, y = XY(self, position)
	return Normalized(self, x), Normalized(self, y)
end

function QuestTogether:AreLocationPinMapLayersCompatible(sourceMapID, targetMapID)
	if sourceMapID == targetMapID then
		return true
	end
	if self:IsRuntimeRestricted() or not self:CanAccessTable(C_Map) then
		return false
	end
	local getter = C_Map.GetMapGroupID
	if not self:CanAccessValue(getter) or type(getter) ~= "function" then
		return false
	end
	local sourceOK, sourceGroup = pcall(getter, sourceMapID)
	local targetOK, targetGroup = pcall(getter, targetMapID)
	if not sourceOK or not targetOK or not self:CanAccessValue(sourceGroup) or not self:CanAccessValue(targetGroup) then
		return false
	end
	if (sourceGroup ~= nil and not ID(self, sourceGroup)) or (targetGroup ~= nil and not ID(self, targetGroup)) then
		return false
	end
	-- Blizzard's floor picker uses map groups. World X/Y has no altitude, so
	-- projecting between two floors in the same group would invent a location.
	return sourceGroup == nil or targetGroup == nil or sourceGroup ~= targetGroup
end

local function Rect(addon, frame)
	if not addon:CanAccessForeignFrame(frame, true) then
		return nil
	end
	local left, bottom, width, height = Method(addon, frame, "GetRect")
	left, bottom = Number(addon, left), Number(addon, bottom)
	width, height = Positive(addon, width), Positive(addon, height)
	local scale = Positive(addon, Method(addon, frame, "GetEffectiveScale"))
	if left and bottom and width and height and scale then
		return { left = left, top = bottom + height, width = width, height = height, scale = scale }
	end
end

function QuestTogether:GetViewedQuestTogetherMapID()
	if self:IsRuntimeRestricted() or not self:CanAccessForeignFrame(WorldMapFrame, true) then return nil end
	if Method(self, WorldMapFrame, "IsShown") ~= true then return nil end
	return ID(self, Method(self, WorldMapFrame, "GetMapID"))
end

local function DescendantLocationPath(addon, info, mapID, parents)
	local path, seen = {}, {}
	for _ = 1, 16 do
		if not addon:CanAccessTable(info) then return nil end
		local child, parent = ID(addon, info.mapID), Number(addon, info.parentMapID)
		if not child or child > 1000000 or seen[child] then return nil end
		if child == mapID then return path end
		if not parent or parent < 0 or parent > 1000000 or parent ~= math.floor(parent) then return nil end
		if parents[child] ~= nil and parents[child] ~= parent then return nil end
		parents[child] = parent
		path[#path + 1] = child
		if parent == mapID then return path end
		if parent == 0 then return {} end
		seen[child] = true
		if parents[parent] ~= nil then
			info = { mapID = parent, parentMapID = parents[parent] }
		else
			info = API(addon, C_Map, "GetMapInfo", parent)
			if not addon:CanAccessTable(info) or ID(addon, info.mapID) ~= parent then return nil end
		end
	end
	return nil
end

local function ClusterPositionsOnMap(addon, members, mapID)
	local positions, x, y = {}, 0, 0
	for _, row in ipairs(members) do
		if not addon:AreLocationPinMapLayersCompatible(row.mapID, mapID) then return nil end
		local px, py = addon:GetLocationPinMapPosition(row, mapID)
		px, py = Normalized(addon, px), Normalized(addon, py)
		if not px or not py then return nil end
		positions[#positions + 1] = { x = px, y = py }
		x, y = x + px, y + py
	end
	return positions, x / #members, y / #members
end

local function DeepestClusterMap(addon, members, mapID, positions, getter)
	local target, seen, parents = mapID, { [mapID] = true }, {}
	for _ = 1, 16 do
		local common
		for _, position in ipairs(positions) do
			local ok, info = pcall(getter, target, position.x, position.y)
			if not ok or not addon:CanAccessValue(info) then return nil end
			local path = {}
			if info ~= nil then path = DescendantLocationPath(addon, info, target, parents) end
			if not path then return nil end
			if not common then common = path else
				local present, shared = {}, {}
				for _, child in ipairs(path) do present[child] = true end
				for _, child in ipairs(common) do if present[child] then shared[#shared + 1] = child end end
				common = shared
			end
			if #common == 0 then return target end
		end
		local child = common and common[1]
		if not child or seen[child] then return nil end
		positions = ClusterPositionsOnMap(addon, members, child)
		if not positions then return nil end
		seen[child], target = true, child
	end
	return nil
end

-- Resolve the deepest native descendant containing every actual member, rather
-- than the count marker's inset position or a centroid across a zone boundary.
-- Native reads and ancestry walks are bounded; no cursor or foreign state changes.
function QuestTogether:GetPlayerLocationClusterNavigationAction(cluster, geometry)
	if not self.isEnabled or self:IsWorkBlocked("foreign_frame_mutation")
		or type(cluster) ~= "table" or type(cluster.members) ~= "table" or #cluster.members < 2
		or #cluster.members > MAX_LOCATION_ROWS or type(geometry) ~= "table" then return "unavailable" end
	local map = WorldMapFrame
	if not self:CanAccessForeignFrame(map, true) or Method(self, map, "IsVisible") ~= true then return "unavailable" end
	local current = self:GetLocationPinSurface("map")
	if not current or current.mapID ~= geometry.mapID or current.parent ~= geometry.parent then return "unavailable" end
	for _, key in ipairs({ "width", "height", "canvasLeft", "canvasTop", "canvasWidth", "canvasHeight" }) do
		if current[key] ~= geometry[key] then return "unavailable" end
	end
	local mapID = ID(self, current.mapID)
	if not mapID or mapID > 1000000 then return "unavailable" end
	local positions, x, y = ClusterPositionsOnMap(self, cluster.members, mapID)
	if not positions then return "unavailable" end
	if not self:CanAccessTable(C_Map) then return "unavailable" end
	local getter = C_Map.GetMapInfoAtPosition
	if not self:CanAccessValue(getter) or type(getter) ~= "function" then return "unavailable" end
	local target = DeepestClusterMap(self, cluster.members, mapID, positions, getter)
	if not target then return "unavailable" end
	if target ~= mapID then
		local setter = self:GetAccessibleFrameMember(map, "SetMapID")
		return type(setter) == "function" and "navigate" or "unavailable", target, x, y
	end
	return "expand", nil, x, y
end

-- False means there is no more detailed child map here. Canvas magnification
-- never changes the decision; unavailable or declined navigation consumes click.
function QuestTogether:TryNavigatePlayerLocationCluster(cluster, geometry)
	self:ClearPlayerLocationClusterExpansion()
	local action, target = self:GetPlayerLocationClusterNavigationAction(cluster, geometry)
	if action == "expand" then return false end
	if action == "navigate" then
		local map = WorldMapFrame
		if self:IsWorkBlocked("foreign_frame_mutation") or not self:CanAccessForeignFrame(map, true)
			or Method(self, map, "IsVisible") ~= true then return true end
		local method = self:GetAccessibleFrameMember(map, "SetMapID")
		if type(method) ~= "function" then return true end
		local intent = self:BeginPlayerLocationClusterNavigation(cluster, geometry, target)
		if not intent then return true end
		local ok, result = pcall(method, map, target)
		intent.navigating = false
		if not ok or not self:CanAccessValue(result) or result == false or not self.isEnabled
			or self:IsWorkBlocked("foreign_frame_mutation") or ID(self, Method(self, map, "GetMapID")) ~= target
			or Method(self, map, "IsVisible") ~= true then self:CancelPlayerLocationClusterNavigation(intent) end
	end
	return true
end

function QuestTogether:GetLocationPinSurface(surface)
	if self:IsRuntimeRestricted() then
		return nil
	end
	if surface == "map" then
		local map = WorldMapFrame
		if not self:CanAccessForeignFrame(map, true) then
			return nil
		end
		local mapID = ID(self, Method(self, map, "GetMapID"))
		local parent = Method(self, map, "GetCanvasContainer")
		local canvas = Method(self, map, "GetCanvas")
		local viewport, art = Rect(self, parent), Rect(self, canvas)
		if not mapID or not viewport or not art then
			return nil
		end
		local levels = Method(self, map, "GetPinFrameLevelsManager")
		local pinFrameLevel = Number(self,
			API(self, levels, "GetValidFrameLevel", levels, "PIN_FRAME_LEVEL_TOPMOST", 10000))
		if pinFrameLevel and (pinFrameLevel < 0 or pinFrameLevel > 10000 or pinFrameLevel ~= math.floor(pinFrameLevel)) then
			pinFrameLevel = nil
		end
		local ratio = art.scale / viewport.scale
		return {
			parent = parent,
			mapID = mapID,
			pinFrameLevel = pinFrameLevel,
			width = viewport.width,
			height = viewport.height,
			canvasLeft = art.left * ratio - viewport.left,
			canvasTop = viewport.top - art.top * ratio,
			canvasWidth = art.width * ratio,
			canvasHeight = art.height * ratio,
		}
	end
	if surface ~= "minimap" then
		return nil
	end
	local parent = self:GetMinimapAnchor()
	local bounds = Rect(self, parent)
	local minimapMap = API(self, C_Minimap, "GetUiMapID")
	if not self:CanAccessValue(minimapMap) then
		return nil
	end
	-- GetUiMapID is nullable: the terrain minimap need not have a HybridMinimap
	-- UI map. Use the player's current map in that case, but never substitute
	-- for an explicitly supplied invalid or restricted map ID.
	if minimapMap == nil then
		minimapMap = Native(self, self.API.GetBestMapForUnit, "player")
	end
	local mapID = ID(self, minimapMap)
	local radius = Positive(self, API(self, C_Minimap, "GetViewRadius"))
	if not bounds or not mapID or not radius then
		return nil
	end
	local player = API(self, C_Map, "GetPlayerMapPosition", mapID, "player")
	local px, py = XY(self, player)
	local continent, north, west = self:GetLocationPinWorldPosition(mapID, px, py)
	if not continent then
		return nil
	end
	local rotated = API(self, C_CVar, "GetCVarBool", "rotateMinimap")
	if not self:CanAccessValue(rotated) or type(rotated) ~= "boolean" then
		return nil
	end
	local facing = 0
	if rotated then
		-- HybridMinimap deliberately ignores the rotation CVar while showing
		-- its north-up canvas. Read the native override; never guess a heading.
		local ignored = API(self, C_Minimap, "IsRotateMinimapIgnored")
		if not self:CanAccessValue(ignored) or type(ignored) ~= "boolean" then
			return nil
		end
		if not ignored then
			facing = Number(self, Native(self, GetPlayerFacing))
			if facing == nil then
				return nil
			end
		end
	end
	local shape = self:GetLocationPinMinimapShape()
	-- Unknown third-party masks must not place markers outside their artwork.
	if shape ~= "ROUND" and shape ~= "SQUARE" then
		return nil
	end
	return {
		parent = parent,
		mapID = mapID,
		width = bounds.width,
		height = bounds.height,
		radius = radius,
		continent = continent,
		north = north,
		west = west,
		facing = facing,
		shape = shape,
	}
end

-- Returns pixel offsets from the visible surface's TOPLEFT. Map geometry is
-- the current canvas rect, so zoom/pan require no hooks or map pin registry.
function QuestTogether:ProjectPlayerLocationPin(surface, row, geometry, markerSize)
	if
		not self:CanAccessTable(row)
		or not geometry
		or not ID(self, row.mapID)
		or not Normalized(self, row.x)
		or not Normalized(self, row.y)
	then
		return nil
	end
	if not self:AreLocationPinMapLayersCompatible(row.mapID, geometry.mapID) then
		return nil
	end
	local dotSize = markerSize or PinSize(self, row.name, row)
	local x, y
	if surface == "map" then
		local nx, ny = self:GetLocationPinMapPosition(row, geometry.mapID)
		if not nx or not ny then
			return nil
		end
		x = geometry.canvasLeft + nx * geometry.canvasWidth
		y = geometry.canvasTop + ny * geometry.canvasHeight
	else
		local continent, north, west = self:GetLocationPinWorldPosition(row.mapID, row.x, row.y)
		if continent ~= geometry.continent or not north or not west then
			return nil
		end
		-- Native world X points north and Y west. Facing grows counterclockwise
		-- from north; rotate the view so the player's facing direction is up.
		local east, up = geometry.west - west, north - geometry.north
		local cosine, sine = math.cos(geometry.facing), math.sin(geometry.facing)
		local horizontal = (east * cosine + up * sine) / geometry.radius
		local vertical = (up * cosine - east * sine) / geometry.radius
		local margin = dotSize / math.min(geometry.width, geometry.height)
		local limit = 1 - margin
		if limit <= 0 then
			return nil
		end
		if geometry.shape == "ROUND" then
			if horizontal * horizontal + vertical * vertical > limit * limit then
				return nil
			end
		elseif geometry.shape == "SQUARE" then
			if math.max(math.abs(horizontal), math.abs(vertical)) > limit then
				return nil
			end
		else
			return nil
		end
		x, y = (horizontal + 1) * geometry.width / 2, (1 - vertical) * geometry.height / 2
	end
	local half = dotSize / 2
	if x < half or y < half or x > geometry.width - half or y > geometry.height - half then
		return nil
	end
	return x, y
end

local function Guard(addon, region) return addon:CanMutateOwnedUI(region) end
local function Call(addon, region, method, ...) return addon:CallOwnedUI(region, method, ...) end

local function New(addon, kind, parent)
	return addon:CreateOwnedUIFrame(addon.CreateLocationPinFrame, kind, parent)
end

local function RetryCleanup(addon) addon:FlushOwnedUICleanup() end
local function Hide(addon, state, region)
	addon:HideOwnedUI(region)
end
local function State(addon)
	local state = rawget(addon, "locationPinState")
	if not state then
		state = { surfaces = {} }
		addon.locationPinState = state
	end
	return state
end

local PARTY_MEDIA = "Interface\\AddOns\\QuestTogether\\Media\\"
local function PartyTexture(addon, frame, name, width, height, point, relative, relativePoint, x, y)
	local texture = Call(addon, frame, "CreateTexture", nil, "OVERLAY")
	Call(addon, texture, "SetTexture", PARTY_MEDIA .. name)
	Call(addon, texture, "SetSize", width, height)
	Call(addon, texture, "SetPoint", point, relative, relativePoint, x, y)
	Call(addon, texture, "Hide")
	return texture
end

local function PartyHighlights(addon, state)
	if not state.surfaces or addon:IsRuntimeRestricted() then return end
	local hovered = state.hovered and addon:GetPlayerPartyVisualInfo(state.hovered.name)
	local key = hovered and hovered.key
	for _, surface in pairs(state.surfaces) do
		for _, pin in ipairs(surface.pins) do
			if (pin.name or pin.cluster) and Guard(addon, pin.frame) then
				local info = pin.name and addon:GetPlayerPartyVisualInfo(pin.name)
				local same = key and info and info.key == key
				-- Older peers can also be identified by a fetched current roster,
				-- but never override a conflicting explicit party advertisement.
				if pin.name and key and (not info or not info.key) and hovered.members then
					for _, member in ipairs(hovered.members) do
						if member.name == pin.name and (not info or info.size ~= 0) then same = true end
					end
				end
				local dim = pin.name and key and not same and not pin.selected and not surface.highlightingQT
				local alpha = (pin.baseAlpha or 1) * (dim and 0.45 or 1)
				Call(addon, pin.frame, "SetAlpha", alpha)
				if pin.connector then Call(addon, pin.connector, "SetAlpha", alpha) end
				Call(addon, pin.partyBadge, info and info.size and info.size > 1 and "Show" or "Hide")
				Call(addon, pin.partyOutline, same and "Show" or "Hide")
				Call(addon, pin.partyCrown, same and pin.name == hovered.leader and "Show" or "Hide")
			end
		end
	end
end

local function HideTooltip(addon, state)
	if state.clusterTooltip then addon:HidePlayerTooltipPresentation(state.clusterTooltip) end
	addon:HidePlayerTooltipPresentation(state)
	PartyHighlights(addon, state)
end

local function HideSurface(addon, state, surface)
	if not surface then
		return
	end
	surface.expandedClusterKey = nil
	surface.highlightingQT = nil
	if surface.clusterShade then Hide(addon, state, surface.clusterShade) end
	for _, pin in ipairs(surface.pins) do
		pin.name, pin.cluster, pin.selected, pin.expansion = nil, nil, nil, nil
		pin.presentationGeneration = (pin.presentationGeneration or 0) + 1
	end
	if surface.name == "map" then addon:ClearPlayerLocationClusterExpansion() end
	Hide(addon, state, surface.frame)
	if surface.name == "map" and state.clusterTooltip and state.clusterTooltip.hovered then
		addon:HidePlayerTooltipPresentation(state.clusterTooltip)
	end
	if state.hovered and state.hovered.surface == surface.name then
		HideTooltip(addon, state)
	end
end

function QuestTogether:HidePlayerLocationPins()
	self:HideLocationTargetButton()
	self:ClearPlayerMapSelection()
	self:ClearPlayerLocationClusterExpansion()
	local state = rawget(self, "locationPinState")
	if not state then
		return
	end
	for _, surface in pairs(state.surfaces) do
		HideSurface(self, state, surface)
	end
	HideTooltip(self, state)
	RetryCleanup(self, state)
end

local function FreshRow(addon, pin)
	if not addon.isEnabled or addon:IsRuntimeRestricted() or not pin.name or not Guard(addon, pin.frame)
		or not addon:IsQuestTogetherMapDataShown(pin.surface)
		or Method(addon, pin.frame, "IsVisible") ~= true then
		return nil
	end
	local geometry = addon:GetLocationPinSurface(pin.surface)
	if not geometry or geometry.parent ~= pin.parent or geometry.mapID ~= pin.mapID then
		return nil
	end
	local rows = addon:GetVisiblePlayerLocations(pin.surface)
	if pin.expansion then
		local markers = addon:GetPlayerLocationMapMarkers(rows, geometry, MAX_PINS)
		local dots, _, info = addon:GetPlayerLocationClusterExpansion(markers, geometry)
		if not info or info.token ~= pin.expansion.token or info.page ~= pin.expansion.page then return nil end
		for _, dot in ipairs(dots) do
			if dot.row.name == pin.name then return dot.row end
		end
		return nil
	end
	if pin.surface == "map" and pin.selected then
		local selected = addon:GetSelectedPlayerMapLocation(geometry.mapID)
		if selected and selected.name == pin.name then return selected end
	end
	for index = 1, math.min(MAX_LOCATION_ROWS, #rows) do
		local row = rows[index]
		if
			row.name == pin.name
			and not addon:IsIgnoredPlayerName(row.name)
			and addon:ProjectPlayerLocationPin(pin.surface, row, geometry)
		then
			return row
		end
	end
end

function QuestTogether:OpenLocationPinPlayerMenu(frame, name, pin)
	if not self.isEnabled or self:IsRuntimeRestricted() or not Guard(self, frame) or self:IsIgnoredPlayerName(name) then
		return false
	end
	local firstAction
	if pin and pin.surface == "minimap" then
		firstAction = function(root)
			self:PopulateLocationTargetMenu(root, name, function()
				local row = FreshRow(self, pin)
				return row ~= nil and row.name == name
			end)
		end
	end
	return self:ShowChatLogSpeakerMenu(frame, name, firstAction)
end

local function Color(addon, classFile)
	local color = addon:SafeTrimString(addon:GetClassColorCode(classFile), "")
	local r, g, b = color:match("^|c%x%x(%x%x)(%x%x)(%x%x)$")
	if r then
		return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
	end
	return 1, 1, 1
end

local function Tooltip(addon, state, pin, row)
	if state.clusterTooltip then addon:HidePlayerTooltipPresentation(state.clusterTooltip) end
	state.onHoverChanged = function() PartyHighlights(addon, state) end
	return addon:PresentPlayerTooltip(state, pin, row)
end

local function CurrentCluster(addon, pin)
	if not addon.isEnabled or addon:IsRuntimeRestricted() or not Guard(addon, pin.frame)
		or not addon:IsQuestTogetherMapDataShown("map")
		or Method(addon, pin.frame, "IsVisible") ~= true or not pin.cluster then return nil end
	local geometry = addon:GetLocationPinSurface("map")
	if not geometry or geometry.mapID ~= pin.mapID or geometry.parent ~= pin.parent then return nil end
	local markers = addon:GetPlayerLocationMapMarkers(addon:GetVisiblePlayerLocations("map"), geometry, MAX_PINS)
	for _, marker in ipairs(markers) do
		if marker.members and marker.key == pin.cluster.key then return marker, geometry, markers end
	end
end

local function ClusterTooltip(addon, state, pin)
	local cluster, geometry, markers = CurrentCluster(addon, pin)
	if not cluster or Method(addon, addon:GetPlayerTooltipPresentationParent(), "IsVisible") ~= true then
		HideTooltip(addon, state)
		return false
	end
	addon:HidePlayerTooltipPresentation(state)
	PartyHighlights(addon, state)
	local _, expanded, info = addon:GetPlayerLocationClusterExpansion(markers, geometry)
	local active = expanded and expanded.key == cluster.key
	local lines, members = {}, {}
	local first = active and info.first or 1
	local last = math.min(active and info.last or #cluster.members, first + 5)
	for index = first, last do
		local member = addon:BuildPlayerTooltipMember(cluster.members[index], { shortName = true, usesQT = true })
		if member then members[#members + 1] = member end
	end
	if #cluster.members > #members then
		lines[#lines + 1] = string.format(L("…and %d more"), #cluster.members - #members)
	end
	local navigation = not active and addon:GetPlayerLocationClusterNavigationAction(cluster, geometry)
	if active then lines[#lines + 1] = L("Click to collapse. Hover a player for details.")
	elseif navigation == "expand" then lines[#lines + 1] = L("Click to expand players.")
	elseif navigation == "navigate" then lines[#lines + 1] = L("Click to open a more detailed map.") end
	if active and info.pages > 1 then
		lines[#lines + 1] = string.format(L("Scroll to browse players (%d/%d)."), info.page, info.pages)
	end
	state.clusterTooltip = state.clusterTooltip or {}
	addon:RenderPlayerTooltip(state.clusterTooltip, pin, {
		title = string.format(L("%d players"), #cluster.members),
		text = table.concat(lines, "\n"), color = { 1, 0.82, 0 }, members = members,
	})
	return true
end

local function OpenCluster(addon, state, pin, pageDelta)
	local cluster, geometry, markers = CurrentCluster(addon, pin)
	if not cluster then return false end
	local wasHovered = state.clusterTooltip and state.clusterTooltip.hovered == pin
	if pageDelta then
		if not addon:ChangePlayerLocationClusterPage(cluster, geometry, pageDelta) then return false end
	else
		local _, expanded = addon:GetPlayerLocationClusterExpansion(markers, geometry)
		if (not expanded or expanded.key ~= cluster.key) and addon:TryNavigatePlayerLocationCluster(cluster, geometry) then
			HideTooltip(addon, state)
			addon:RefreshPlayerLocationPins()
			return true
		end
		addon:TogglePlayerLocationClusterExpansion(cluster, geometry)
	end
	HideTooltip(addon, state)
	addon:RefreshPlayerLocationPins()
	if wasHovered then
		local surface = state.surfaces.map
		for _, current in ipairs(surface and surface.pins or {}) do
			if current.cluster and current.cluster.key == cluster.key then
				ClusterTooltip(addon, state, current)
				break
			end
		end
	end
	return true
end

local function CreatePin(addon, state, surface)
	local pin = { frame = New(addon, "Button", surface.frame), surface = surface.name }
	Call(addon, pin.frame, "Hide")
	Call(addon, pin.frame, "SetSize", DOT_SIZE, DOT_SIZE)
	Call(addon, pin.frame, "RegisterForClicks", "LeftButtonUp", "RightButtonUp")
	pin.isCurrent = function() return FreshRow(addon, pin) ~= nil end
	for _, layer in ipairs({ "BACKGROUND", "ARTWORK" }) do
		local texture = Call(addon, pin.frame, "CreateTexture", nil, layer)
		Call(addon, texture, "SetPoint", "CENTER")
		Call(
			addon,
			texture,
			"SetSize",
			layer == "BACKGROUND" and DOT_SIZE or DOT_SIZE - 3,
			layer == "BACKGROUND" and DOT_SIZE or DOT_SIZE - 3
		)
		Call(addon, texture, "SetColorTexture", 0, 0, 0, 1)
		local mask = Call(addon, pin.frame, "CreateMaskTexture")
		Call(addon, mask, "SetAllPoints", texture)
		Call(
			addon,
			mask,
			"SetTexture",
			"Interface\\CharacterFrame\\TempPortraitAlphaMask",
			"CLAMPTOBLACKADDITIVE",
			"CLAMPTOBLACKADDITIVE"
		)
		Call(addon, texture, "AddMaskTexture", mask)
		if layer == "ARTWORK" then
			pin.texture = texture
		else
			pin.border = texture
		end
	end
	-- Nested translucent circles soften outward into a halo. Reuse these owned
	-- regions for every occupant of the pin; no animation or extra timer needed.
	pin.glow = {}
	for index = 1, 4 do
		local texture = Call(addon, pin.frame, "CreateTexture", nil, "BACKGROUND")
		Call(addon, texture, "SetPoint", "CENTER")
		Call(addon, texture, "SetSize", PARTNER_DOT_SIZE - (index - 1) * 2, PARTNER_DOT_SIZE - (index - 1) * 2)
		Call(addon, texture, "SetColorTexture", 1, 0.8, 0.15, 0.06 + index * 0.07)
		Call(addon, texture, "SetBlendMode", "ADD")
		local mask = Call(addon, pin.frame, "CreateMaskTexture")
		Call(addon, mask, "SetAllPoints", texture)
		Call(addon, mask, "SetTexture", "Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		Call(addon, texture, "AddMaskTexture", mask)
		Call(addon, texture, "Hide")
		pin.glow[index] = texture
	end
	pin.selectionGlow = {}
	for index = 1, 4 do
		local texture = Call(addon, pin.frame, "CreateTexture", nil, "BACKGROUND")
		Call(addon, texture, "SetPoint", "CENTER")
		Call(addon, texture, "SetSize", 30 - index * 2, 30 - index * 2)
		Call(addon, texture, "SetColorTexture", 0.2, 1, 0.25, 0.1 + index * 0.06)
		Call(addon, texture, "SetBlendMode", "ADD")
		local mask = Call(addon, pin.frame, "CreateMaskTexture")
		Call(addon, mask, "SetAllPoints", texture)
		Call(addon, mask, "SetTexture", "Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		Call(addon, texture, "AddMaskTexture", mask)
		Call(addon, texture, "Hide")
		pin.selectionGlow[index] = texture
	end
	pin.developerGear = Call(addon, pin.frame, "CreateTexture", nil, "ARTWORK")
	Call(addon, pin.developerGear, "SetTexture", PARTY_MEDIA .. "DeveloperGear")
	Call(addon, pin.developerGear, "SetPoint", "CENTER")
	Call(addon, pin.developerGear, "SetSize", 18, 18)
	Call(addon, pin.developerGear, "Hide")
	pin.count = Call(addon, pin.frame, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
	Call(addon, pin.count, "SetPoint", "CENTER")
	Call(addon, pin.count, "Hide")
	pin.phaseIcon = Call(addon, pin.frame, "CreateTexture", nil, "OVERLAY")
	Call(addon, pin.phaseIcon, "SetTexture", "Interface\\TargetingFrame\\UI-PhasingIcon")
	Call(addon, pin.phaseIcon, "SetTexCoord", 0.15625, 0.84375, 0.15625, 0.84375)
	Call(addon, pin.phaseIcon, "SetSize", 12, 12)
	Call(addon, pin.phaseIcon, "SetPoint", "CENTER", pin.texture, "TOPLEFT", -1, 1)
	Call(addon, pin.phaseIcon, "Hide")
	pin.partyOutline = PartyTexture(addon, pin.frame, "PartyHighlight", 16, 16, "CENTER", pin.texture, "CENTER", 0, 0)
	pin.partyBadge = PartyTexture(addon, pin.frame, "PartyBadge", 10, 10, "CENTER", pin.texture, "BOTTOMRIGHT", 0, 0)
	pin.partyCrown = PartyTexture(addon, pin.frame, "PartyLeader", 12, 9, "BOTTOM", pin.texture, "TOP", 0, -1)
	Call(addon, pin.frame, "SetScript", "OnClick", function(_, button)
		if button ~= "LeftButton" and button ~= "RightButton" then
			return
		end
		if pin.cluster then OpenCluster(addon, state, pin); return end
		local ok, row = pcall(FreshRow, addon, pin)
		HideTooltip(addon, state)
		if ok and row and (pin.surface ~= "minimap" or button == "RightButton") then
			pcall(addon.OpenLocationPinPlayerMenu, addon, pin.frame, row.name, pin)
		end
	end)
	Call(addon, pin.frame, "SetScript", "OnEnter", function()
		if pin.cluster then
			if not pcall(ClusterTooltip, addon, state, pin) then HideTooltip(addon, state) end
			return
		end
		local ok, row = pcall(FreshRow, addon, pin)
		if ok and row then
			addon:RequestPlayerPhaseComparison(row.name)
			if not pcall(Tooltip, addon, state, pin, row) then
				HideTooltip(addon, state)
			end
			if pin.surface == "minimap" then
				local name = row.name
				addon:ShowLocationTargetButton(pin.frame, name, function()
					local current = FreshRow(addon, pin)
					return current ~= nil and current.name == name
				end, function()
					local current = FreshRow(addon, pin)
					if current and current.name == name then Tooltip(addon, state, pin, current) end
				end, function() HideTooltip(addon, state) end, function(button)
					HideTooltip(addon, state)
					if button == "RightButton" then addon:OpenLocationPinPlayerMenu(pin.frame, name, pin) end
				end)
			end
		end
	end)
	Call(addon, pin.frame, "SetScript", "OnLeave", function()
		if state.hovered == pin or (state.clusterTooltip and state.clusterTooltip.hovered == pin) then
			HideTooltip(addon, state)
		end
	end)
	Call(addon, pin.frame, "SetScript", "OnMouseWheel", function(_, delta)
		if pin.cluster and type(delta) == "number" and delta ~= 0 then
			OpenCluster(addon, state, pin, delta > 0 and -1 or 1)
		end
	end)
	return pin
end

local function UpdateClusterShade(addon, state, surface, level)
	if not surface.expandedClusterKey or not level then
		if surface.clusterShade then Hide(addon, state, surface.clusterShade) end
		return
	end
	if not surface.clusterShade then
		local shade = New(addon, "Frame", surface.frame)
		surface.clusterShade = shade
		Call(addon, shade, "Hide")
		Call(addon, shade, "SetAllPoints", surface.frame)
		Call(addon, shade, "EnableMouse", false)
		Call(addon, shade, "EnableMouseWheel", false)
		local texture = Call(addon, shade, "CreateTexture", nil, "BACKGROUND")
		surface.clusterShadeTexture = texture
		Call(addon, texture, "SetAllPoints", shade)
		Call(addon, texture, "SetColorTexture", 0, 0, 0, 0.22)
	end
	-- Shade the visible map and ordinary markers without intercepting input.
	-- The active cluster and its member buttons sit above this owned layer.
	Call(addon, surface.clusterShadeTexture, "SetAlpha", surface.highlightingQT and 0 or 1)
	Call(addon, surface.clusterShade, "SetFrameLevel", level + 2)
	Call(addon, surface.clusterShade, "Show")
end

local function RefreshSurface(addon, state, name, rows)
	local surface = state.surfaces[name]
	if not addon:IsQuestTogetherMapDataShown(name) then
		if name == "map" then addon:ClearPlayerMapSelection() end
		HideSurface(addon, state, surface)
		return false
	end
	if #rows == 0 and not (name == "map" and rawget(addon, "playerMapSelection")) then
		HideSurface(addon, state, surface)
		return false
	end
	local geometry = addon:GetLocationPinSurface(name)
	if not geometry then
		if name == "map" then addon:ClearPlayerMapSelection() end
		HideSurface(addon, state, surface)
		return false
	end
	surface = addon:AcquireMapOverlaySurface(state, name, geometry, 50, function(old) HideSurface(addon, state, old) end)
	if not surface then return false end
	if name == "minimap" and #rows > MAX_PINS then
		rows = addon:PrioritizePlayerLocationRows(rows, geometry)
	end
	local markers
	surface.expandedClusterKey = nil
	if name == "map" then
		markers = addon:GetPlayerLocationMapMarkers(rows, geometry, MAX_PINS)
		addon:ConsumePlayerLocationClusterNavigation(markers, geometry)
		local dots, cluster, info = addon:GetPlayerLocationClusterExpansion(markers, geometry)
		if dots then
			surface.expandedClusterKey = cluster.key
			-- Keep the open cluster and every member on its page ahead of the
			-- display cap. Selected players remain independent actual positions.
			local expanded = { cluster }
			cluster.expansionInfo = info
			for _, dot in ipairs(dots) do
				dot.expansionInfo = info
				expanded[#expanded + 1] = dot
			end
			for _, marker in ipairs(markers) do
				if marker ~= cluster then expanded[#expanded + 1] = marker end
			end
			markers = expanded
		end
	else
		markers = {}
		-- Nearby targets remain individual buttons with the original click rules.
		for index = 1, math.min(MAX_LOCATION_ROWS, #rows) do
			if #markers >= MAX_PINS then break end
			local row = rows[index]
			local x, y = addon:ProjectPlayerLocationPin(name, row, geometry)
			if x and y and type(row.name) == "string" and row.name ~= "" then
				markers[#markers + 1] = { row = row, x = x, y = y, key = row.name }
			end
		end
	end
	local level = Number(addon, Call(addon, surface.frame, "GetFrameLevel"))
	local nativePinLevel = Number(addon, geometry.pinFrameLevel)
	local highlightLevel = name == "map" and addon:GetQuestTogetherMapHighlightLevel(geometry)
	surface.highlightingQT = highlightLevel ~= nil and highlightLevel ~= false
	if level and highlightLevel then
		level = math.max(level, highlightLevel)
		Call(addon, surface.frame, "SetFrameLevel", level)
	end
	if level and surface.expandedClusterKey and nativePinLevel then
		-- Blizzard pin groups can sit thousands of levels above the canvas.
		-- Raise only our owned overlay; the ordinary pool level returns on collapse.
		level = math.max(level, nativePinLevel + 1)
		Call(addon, surface.frame, "SetFrameLevel", level)
	end
	UpdateClusterShade(addon, state, surface, level)
	local count = math.min(MAX_PINS, #markers)
	for index = 1, count do
		local marker = markers[index]
		local row, cluster = marker.row, marker.members
		local pin = addon:AcquireMapOverlayPin(surface, index, function(host) return CreatePin(addon, state, host) end)
		local previousKey = pin.cluster and pin.cluster.key or pin.name
		local expansion = marker.expanded and marker.expansionInfo or nil
		local changed = previousKey ~= marker.key or (pin.expansion and not expansion)
			or (expansion and (not pin.expansion or pin.expansion.token ~= expansion.token or pin.expansion.page ~= expansion.page))
		if changed then
			if state.hovered == pin or (state.clusterTooltip and state.clusterTooltip.hovered == pin) then HideTooltip(addon, state) end
			pin.presentationGeneration = (pin.presentationGeneration or 0) + 1
		end
		pin.expansion = expansion and { token = expansion.token, page = expansion.page } or nil
		pin.name, pin.parent, pin.mapID = row and row.name, geometry.parent, geometry.mapID
		pin.cluster, pin.selected = cluster and marker or nil, marker.selected == true
		local levelOffset = marker.expanded and 4 or marker.expansionInfo and 3
			or (pin.selected and not surface.expandedClusterKey and 5) or 1
		if level then Call(addon, pin.frame, "SetFrameLevel", level + levelOffset) end
		pin.baseAlpha = row and addon:GetPlayerLocationOpacity(row) or 0.45
		if cluster then
			for _, member in ipairs(cluster) do pin.baseAlpha = math.max(pin.baseAlpha, addon:GetPlayerLocationOpacity(member)) end
		end
		Call(addon, pin.frame, "SetAlpha", pin.baseAlpha)
		Call(addon, pin.phaseIcon, row and addon:GetPlayerPhaseStatus(row.name) == "different" and "Show" or "Hide")
		local r, g, b = 0.16, 0.13, 0.06
		if row then r, g, b = Color(addon, row.classFile) end
		Call(addon, pin.texture, "SetColorTexture", r, g, b, 1)
		local private = row and row.developerOnly and row.publicLocationHidden
		local developer = row and addon:IsVerifiedDeveloper(row.name) == true
		Call(addon, pin.developerGear, "SetVertexColor", r, g, b, 1)
		Call(addon, pin.developerGear, developer and "Show" or "Hide")
		Call(addon, pin.texture, developer and "Hide" or "Show")
		Call(addon, pin.border, developer and "Hide" or "Show")
		local looking = row and HasLocationGlow(addon, row.name, row) == true
		local size = cluster and 24 or PinSize(addon, row.name, row)
		if pin.size ~= size or pin.private ~= private or pin.looking ~= looking then
			Call(addon, pin.border, "SetColorTexture", cluster and 0.8 or 0, cluster and 0.65 or 0, cluster and 0.25 or 0, looking and 0 or 1)
			for glowIndex, glow in ipairs(pin.glow) do
				local glowSize = (developer and 24 or PARTNER_DOT_SIZE) - (glowIndex - 1) * 2
				Call(addon, glow, "SetSize", glowSize, glowSize)
				Call(addon, glow, "SetColorTexture", 1, private and 0.12 or 0.8, private and 0.12 or 0.15, 0.06 + glowIndex * 0.07)
				Call(addon, glow, looking and "Show" or "Hide")
			end
			Call(addon, pin.frame, "SetSize", size, size)
			Call(addon, pin.border, "SetSize", cluster and size or DOT_SIZE, cluster and size or DOT_SIZE)
			Call(addon, pin.texture, "SetSize", cluster and size - 3 or DOT_SIZE - 3, cluster and size - 3 or DOT_SIZE - 3)
			pin.size, pin.private, pin.looking = size, private, looking
		end
		Call(addon, pin.frame, "EnableMouseWheel", cluster ~= nil and marker.expansionInfo ~= nil and marker.expansionInfo.pages > 1)
		if marker.expanded then
			if not pin.connector then
				-- Connections remain legible above the shade and below member dots.
				pin.connector = Call(addon, surface.clusterShade, "CreateLine", nil, "OVERLAY")
				Call(addon, pin.connector, "SetThickness", 1)
				Call(addon, pin.connector, "SetColorTexture", 0.8, 0.7, 0.45, 0.65)
			end
			Call(addon, pin.connector, "SetStartPoint", "TOPLEFT", surface.frame, marker.sourceX, -marker.sourceY)
			Call(addon, pin.connector, "SetEndPoint", "TOPLEFT", surface.frame, marker.x, -marker.y)
			Call(addon, pin.connector, "Show")
		elseif pin.connector then Hide(addon, state, pin.connector) end
		Call(addon, pin.count, "SetText", cluster and tostring(#cluster) or "")
		Call(addon, pin.count, cluster and "Show" or "Hide")
		for _, glow in ipairs(pin.selectionGlow) do Call(addon, glow, pin.selected and "Show" or "Hide") end
		if cluster then
			Call(addon, pin.partyBadge, "Hide")
			Call(addon, pin.partyOutline, "Hide")
			Call(addon, pin.partyCrown, "Hide")
		end
		Call(addon, pin.frame, "ClearAllPoints")
		Call(addon, pin.frame, "SetPoint", "CENTER", surface.frame, "TOPLEFT", marker.x, -marker.y)
		Call(addon, pin.frame, "Show")
	end
	addon:ReleaseMapOverlayPins(surface, count, function(pin)
		pin.name, pin.cluster, pin.selected, pin.expansion = nil, nil, nil, nil
		pin.presentationGeneration = (pin.presentationGeneration or 0) + 1
		if pin.connector then Hide(addon, state, pin.connector) end
		if state.hovered == pin or (state.clusterTooltip and state.clusterTooltip.hovered == pin) then HideTooltip(addon, state) end
	end)
	if count == 0 then
		HideSurface(addon, state, surface)
		return false
	end
	Call(addon, surface.frame, "Show")
	return true
end

function QuestTogether:RefreshPlayerLocationPins()
	if not self.isEnabled or self:IsRuntimeRestricted() then
		self:HidePlayerLocationPins()
		return false
	end
	local rows = {}
	for _, surface in ipairs({ "map", "minimap" }) do
		local ok, result = pcall(self.GetVisiblePlayerLocations, self, surface)
		rows[surface] = ok and self:CanAccessTable(result) and result or {}
	end
	local selected = self:GetSelectedPlayerMapLocation()
	-- Most updates have no visible peers. Avoid creating UI or querying native
	-- map geometry until the model has something this surface may display.
	if #rows.map == 0 and #rows.minimap == 0 and not selected then
		self:HidePlayerLocationPins()
		return false
	end
	local ok, state = pcall(State, self)
	if not ok then
		return false
	end
	RetryCleanup(self, state)
	local visible = false
	for _, name in ipairs({ "map", "minimap" }) do
		local success, shown = pcall(RefreshSurface, self, state, name, rows[name])
		if not success then
			HideSurface(self, state, state.surfaces[name])
		end
		visible = visible or (success and shown == true)
	end
	if state.hovered then
		local valid, row = pcall(FreshRow, self, state.hovered)
		if not valid or not row or not pcall(Tooltip, self, state, state.hovered, row) then
			HideTooltip(self, state)
		end
	end
	if state.clusterTooltip and state.clusterTooltip.hovered then
		if not pcall(ClusterTooltip, self, state, state.clusterTooltip.hovered) then HideTooltip(self, state) end
	end
	PartyHighlights(self, state)
	return visible
end

-- Move only existing streamed minimap pins at animation cadence. No new frames,
-- world-map rebuilds, tooltip updates, or writes to Blizzard-owned UI here.
function QuestTogether:RefreshNearbyStreamPins()
	local streams, state = rawget(self, "nearbyStreamState"), rawget(self, "locationPinState")
	local surface = state and state.surfaces.minimap
	if not streams or not next(streams.wanted) or not surface then return end
	if not self.isEnabled or self:IsRuntimeRestricted() or self:GetOption("showPlayerLocations") ~= true then
		HideSurface(self, state, surface)
		return
	end
	local ok = pcall(function()
		local geometry = self:GetLocationPinSurface("minimap")
		if not geometry or geometry.parent ~= surface.parent then
			HideSurface(self, state, surface)
			return
		end
		local locations = rawget(self, "playerLocationState")
		for _, pin in ipairs(surface.pins) do
			if pin.name and streams.wanted[pin.name] then
				local row = locations and locations.peers[pin.name]
				if not row or row.mask < 2 or not self:ShouldShowPlayerLocation(pin.name) then
					Hide(self, state, pin.frame)
				else
					row = self:GetNearbyStreamPosition(row, true)
					local x, y = self:ProjectPlayerLocationPin("minimap", row, geometry)
					if x and y then
						Call(self, pin.frame, "ClearAllPoints")
						Call(self, pin.frame, "SetPoint", "CENTER", surface.frame, "TOPLEFT", x, -y)
					else Hide(self, state, pin.frame) end
				end
			end
		end
	end)
	if not ok then HideSurface(self, state, surface) end
end
