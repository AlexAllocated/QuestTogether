local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether
local MAX_PINS, MAX_LOCATION_ROWS, DOT_SIZE = 128, 512, 12
local GLOW_DOT_SIZE = 16
local MARKER_GLOW_SCALE = 1.15

local function HasLocationGlow(addon, name, row)
	return addon:IsPlayerLookingForQuestPartners(name)
		or (row and row.developerOnly and (row.publicLocationHidden or row.lookingForQuestPartners))
end

local function PinSize(addon, name, row)
	if addon:IsVerifiedDeveloper(name) or addon:IsVerifiedVIP(name) then return 18 end
	return HasLocationGlow(addon, name, row) and GLOW_DOT_SIZE or DOT_SIZE
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

local function DescendantLocationPath(addon, info, mapID, parents, mapTypes)
	local path, seen = {}, {}
	for _ = 1, 16 do
		if not addon:CanAccessTable(info) then return nil end
		local child, parent = ID(addon, info.mapID), Number(addon, info.parentMapID)
		if not child or child > 1000000 or seen[child] then return nil end
		local mapType = Number(addon, info.mapType)
		if mapType and mapType >= 0 and mapType <= 6 and mapType == math.floor(mapType) then mapTypes[child] = mapType end
		if child == mapID then return path end
		if not parent or parent < 0 or parent > 1000000 or parent ~= math.floor(parent) then return nil end
		if parents[child] ~= nil and parents[child] ~= parent then return nil end
		parents[child] = parent
		path[#path + 1] = child
		if parent == mapID then return path end
		if parent == 0 then return path end
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

local function DeepestLocationMap(addon, members, mapID, positions, getter)
	local parents, mapTypes, footprints, candidates, queued = {}, {}, {}, { mapID }, { [mapID] = true }
	local sourceInfo = API(addon, C_Map, "GetMapInfo", mapID)
	if not addon:CanAccessTable(sourceInfo) or ID(addon, sourceInfo.mapID) ~= mapID then return nil end
	local sourcePath = DescendantLocationPath(addon, sourceInfo, nil, parents, mapTypes)
	if not sourcePath then return nil end
	local sourceAncestors = {}
	for _, ancestor in ipairs(sourcePath) do sourceAncestors[ancestor] = true end
	local function Add(info)
		local path = DescendantLocationPath(addon, info, nil, parents, mapTypes)
		if not path then return false end
		for index = #path, 1, -1 do
			local candidate = path[index]
			if not sourceAncestors[candidate] and not queued[candidate] then
				if #candidates >= 32 then return false end
				queued[candidate], candidates[#candidates + 1] = true, candidate
			end
		end
		return true
	end
	local function Descends(child, ancestor)
		for _ = 1, 16 do
			child = parents[child]
			if child == ancestor then return true end
			if not child or child == 0 then return false end
		end
		return false
	end
	local function Footprint(candidate)
		if footprints[candidate] == nil then
			local width, height = addon:GetLocationPinMapWorldSize(candidate)
			local continent = addon:GetLocationPinWorldPosition(candidate, 0.5, 0.5)
			local area = width and height and Positive(addon, width * height)
			footprints[candidate] = area and continent and { area = area, continent = continent } or false
		end
		return footprints[candidate]
	end
	local function Smaller(candidate, previous)
		local previousType, candidateType = mapTypes[previous], mapTypes[candidate]
		-- Cosmic/world overviews combine several physical continents. Their
		-- center's instance and numeric size do not describe the whole map.
		-- Verified descent to a more detailed native map is authoritative here.
		if previousType and previousType <= 1 and candidateType and candidateType > previousType
			and Descends(candidate, previous) then return true end
		local a, b = Footprint(candidate), Footprint(previous)
		if a and b then return a.continent == b.continent and a.area < b.area end
		-- World/cosmic maps may have no meaningful geographic size. Only a
		-- verified hierarchy descent is safe when footprints cannot be compared.
		return Descends(candidate, previous)
	end
	-- A member's own map can identify city art that native hit testing on the
	-- continent prefers to represent with its surrounding zone instead.
	for _, row in ipairs(members) do
		local source = ID(addon, row.mapID)
		if source and not sourceAncestors[source] and not queued[source] then
			local info = API(addon, C_Map, "GetMapInfo", source)
			if not addon:CanAccessTable(info) or ID(addon, info.mapID) ~= source or not Add(info) then return nil end
		end
	end
	local best, index, reads = mapID, 1, 0
	while index <= #candidates do
		local candidate = candidates[index]
		local projected = candidate == mapID and positions
		if candidate ~= mapID and Smaller(candidate, mapID) then
			projected = ClusterPositionsOnMap(addon, members, candidate)
			local footprint = Footprint(candidate)
			if projected and footprint and (not mapTypes[candidate] or mapTypes[candidate] > 1) then
				for _, row in ipairs(members) do
					if addon:GetCachedPlayerLocationWorldPosition(row) ~= footprint.continent then projected = nil; break end
				end
			end
			if projected and Smaller(candidate, best) then best = candidate end
		end
		if projected then
			local queried = {}
			for _, position in ipairs(projected) do
				queried[position.x] = queried[position.x] or {}
				if not queried[position.x][position.y] then
					reads = reads + 1
					if reads > MAX_LOCATION_ROWS * 16 then return nil end
					queried[position.x][position.y] = true
					local ok, info = pcall(getter, candidate, position.x, position.y)
					if not ok or not addon:CanAccessValue(info) or (info ~= nil and not Add(info)) then return nil end
				end
			end
		end
		index = index + 1
	end
	return best
end

-- Resolve the smallest native map containing every member, including overlapping
-- sibling zone/city maps. Candidates come only from native hits/member maps and
-- their ancestors; a smaller verified footprint prevents sideways/upward loops.
-- This read-only query also supports an individual Find before the map opens.
function QuestTogether:GetPlayerLocationMapNavigationTarget(members, mapID)
	mapID = ID(self, mapID)
	if not self.isEnabled or self:IsRuntimeRestricted() or not mapID or mapID > 1000000
		or type(members) ~= "table" or #members < 1 or #members > MAX_LOCATION_ROWS then return nil end
	local positions, x, y = ClusterPositionsOnMap(self, members, mapID)
	if not positions or not self:CanAccessTable(C_Map) then return nil end
	local getter = C_Map.GetMapInfoAtPosition
	if not self:CanAccessValue(getter) or type(getter) ~= "function" then return nil end
	return DeepestLocationMap(self, members, mapID, positions, getter), x, y
end

local function SameMapGeometry(current, previous)
	if not current or not previous or current.mapID ~= previous.mapID or current.parent ~= previous.parent then return false end
	for _, key in ipairs({ "width", "height", "canvasLeft", "canvasTop", "canvasWidth", "canvasHeight" }) do
		if current[key] ~= previous[key] then return false end
	end
	return true
end

function QuestTogether:GetPlayerLocationClusterNavigationAction(cluster, geometry)
	if not self.isEnabled or self:IsWorkBlocked("foreign_frame_mutation")
		or type(cluster) ~= "table" or type(cluster.members) ~= "table" or #cluster.members < 2
		or #cluster.members > MAX_LOCATION_ROWS or type(geometry) ~= "table" then return "unavailable" end
	local map = WorldMapFrame
	if not self:CanAccessForeignFrame(map, true) or Method(self, map, "IsVisible") ~= true then return "unavailable" end
	local current = self:GetLocationPinSurface("map")
	if not SameMapGeometry(current, geometry) then return "unavailable" end
	local mapID = ID(self, current.mapID)
	if not mapID or mapID > 1000000 then return "unavailable" end
	local target, x, y = self:GetPlayerLocationMapNavigationTarget(cluster.members, mapID)
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

local FreshRow, CurrentCluster

local function UpdateMapFocus(addon, state)
	local surface = state.surfaces and state.surfaces.map
	if not surface then return end
	local hovered = state.hovered
	local clusterHovered = state.clusterTooltip and state.clusterTooltip.hovered
	if not (hovered and hovered.surface == "map") and not clusterHovered and not surface.expandedClusterKey then
		addon:SetMapOverlayFocus(surface, nil, nil)
		return
	end
	local geometry = addon:GetLocationPinSurface("map")
	if not geometry or not addon.isEnabled or addon:IsRuntimeRestricted()
		or not addon:IsQuestTogetherMapDataShown("map") then
		addon:SetMapOverlayFocus(surface, nil, nil)
		return
	end
	local focus, player, partyKey, clusterKey
	if hovered and hovered.surface == "map" and state.mapHoverGeneration == surface.geometryGeneration and FreshRow(addon, hovered) then
		player = hovered.name
		local info = addon:GetPlayerPartyVisualInfo(player)
		partyKey = info and info.key
		local generation = hovered.presentationGeneration
		focus = { kind = "hover", key = "player:" .. player .. ":" .. tostring(generation), pins = {},
			isCurrent = function()
				return state.hovered == hovered and hovered.name == player
					and state.mapHoverGeneration == surface.geometryGeneration
					and hovered.presentationGeneration == generation and FreshRow(addon, hovered) ~= nil
			end }
	elseif clusterHovered and state.clusterHoverGeneration == surface.geometryGeneration and CurrentCluster(addon, clusterHovered) then
		clusterKey = clusterHovered.cluster.key
		focus = { kind = "hover", key = "cluster:" .. clusterKey, pins = {},
			isCurrent = function()
				return state.clusterTooltip and state.clusterTooltip.hovered == clusterHovered
					and state.clusterHoverGeneration == surface.geometryGeneration
					and clusterHovered.cluster and clusterHovered.cluster.key == clusterKey
					and CurrentCluster(addon, clusterHovered) ~= nil
			end }
	elseif surface.expandedClusterKey then
		clusterKey = surface.expandedClusterKey
		focus = { kind = "expanded", key = clusterKey, pins = {},
			isCurrent = function()
				local current = addon:GetLocationPinSurface("map")
				if not current or surface.expandedClusterKey ~= clusterKey then return false end
				local markers = addon:GetPlayerLocationMapMarkers(addon:GetVisiblePlayerLocations("map"), current, MAX_PINS)
				local _, expanded = addon:GetPlayerLocationClusterExpansion(markers, current)
				return expanded ~= nil and expanded.key == clusterKey
			end }
	end
	if focus then
		local function Matches(name)
			if name == player then return true end
			local info = partyKey and name and addon:GetPlayerPartyVisualInfo(name)
			return info and info.key == partyKey or false
		end
		for _, pin in ipairs(surface.pins) do
			local focused
			if clusterKey then
				focused = (pin.cluster and pin.cluster.key == clusterKey)
					or (pin.expansion and surface.expandedClusterKey == clusterKey)
			else
				focused = pin.name and Matches(pin.name)
				if pin.cluster and partyKey then
					for _, member in ipairs(pin.cluster.members) do
						if Matches(member.name) then focused = true; break end
					end
				end
			end
			if focused then focus.pins[pin.frame] = true end
		end
	end
	addon:SetMapOverlayFocus(surface, geometry, focus)
end

local function HoverHighlights(addon, state)
	if not state.surfaces or addon:IsRuntimeRestricted() then return end
	local hoveredName = state.hovered and state.hovered.name
	local hovered = hoveredName and addon:GetPlayerPartyVisualInfo(hoveredName)
	local key = hovered and hovered.key
	for _, surface in pairs(state.surfaces) do
		for _, pin in ipairs(surface.pins) do
			if (pin.name or pin.cluster) and Guard(addon, pin.frame) then
				local info = pin.name and addon:GetPlayerPartyVisualInfo(pin.name)
				local same = key and info and info.key == key
				local focused = pin.name == hoveredName or same
				local dim = surface.name == "minimap" and pin.name and hoveredName and not focused
				local alpha = (pin.baseAlpha or 1) * (dim and 0.45 or 1)
				if surface.name == "minimap" then Call(addon, pin.frame, "SetAlpha", alpha) end
				Call(addon, pin.partyBadge, info and info.size and info.size > 1 and "Show" or "Hide")
				Call(addon, pin.partyOutline, same and "Show" or "Hide")
				Call(addon, pin.partyCrown, same and pin.name == hovered.leader and "Show" or "Hide")
			end
		end
	end
	UpdateMapFocus(addon, state)
end

local function HideTooltip(addon, state)
	if state.clusterTooltip then addon:HidePlayerTooltipPresentation(state.clusterTooltip) end
	addon:HidePlayerTooltipPresentation(state)
	HoverHighlights(addon, state)
end

local function HideSurface(addon, state, surface)
	if not surface then
		return
	end
	surface.expandedClusterKey = nil
	addon:SetMapOverlayFocus(surface, nil, nil)
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

FreshRow = function(addon, pin)
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
		local selected = addon:GetSelectedPlayerMapLocation()
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

local function ActivatePlayerMapPin(addon, pin, row)
	if pin.surface ~= "map" or addon:IsWorkBlocked("foreign_frame_mutation") then return false end
	local geometry = addon:GetLocationPinSurface("map")
	if not geometry or geometry.parent ~= pin.parent or geometry.mapID ~= pin.mapID then return false end
	local view = {}
	for key, value in pairs(geometry) do view[key] = value end
	local observed = { name = row.name, mapID = row.mapID, x = row.x, y = row.y }
	local target = addon:GetPlayerLocationMapNavigationTarget({ observed }, view.mapID)
	-- Native map queries can run callbacks. Never act on a recycled pin, moved
	-- observation, changed view, or permission withdrawn during the lookup.
	local current = FreshRow(addon, pin)
	if not current or current.name ~= observed.name or current.mapID ~= observed.mapID
		or current.x ~= observed.x or current.y ~= observed.y
		or not SameMapGeometry(addon:GetLocationPinSurface("map"), view)
		or addon:IsWorkBlocked("foreign_frame_mutation") then return false end
	-- Find can reveal a public player excluded by the normal display filter.
	-- Re-clicking that selected marker must retain the Find visibility policy.
	local selection = rawget(addon, "playerMapSelection")
	local visibleOnly = not (pin.selected and selection and selection.name == observed.name and not selection.visibleOnly)
	if not addon:SelectPlayerMapLocation(observed, visibleOnly) then return false end
	local opened = false
	if target and target ~= view.mapID then
		addon:ClearPlayerLocationClusterExpansion()
		opened = Native(addon, addon.API.OpenPlayerLocationMap, target) == true
	end
	addon:RefreshPlayerLocationPins()
	if target == view.mapID then
		-- Selection moves the player outside any cluster and can recycle the
		-- clicked frame. Anchor the menu to the freshly rendered selected pin.
		local state = rawget(addon, "locationPinState")
		local surface = state and state.surfaces and state.surfaces.map
		if not surface or not SameMapGeometry(addon:GetLocationPinSurface("map"), view)
			or addon:IsWorkBlocked("foreign_frame_mutation") then return false end
		for _, selected in ipairs(surface.pins) do
			if selected.selected and selected.name == observed.name then
				local fresh = FreshRow(addon, selected)
				if fresh and fresh.mapID == observed.mapID and fresh.x == observed.x and fresh.y == observed.y then
					return addon:OpenLocationPinPlayerMenu(selected.frame, fresh.name, selected)
				end
				return false
			end
		end
	end
	return opened
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
	if pin.surface == "map" and state.mapHoverGeneration ~= state.surfaces.map.geometryGeneration then
		HideTooltip(addon, state)
		return false
	end
	if state.clusterTooltip then addon:HidePlayerTooltipPresentation(state.clusterTooltip) end
	state.onHoverChanged = function() HoverHighlights(addon, state) end
	return addon:PresentPlayerTooltip(state, pin, row)
end

CurrentCluster = function(addon, pin)
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
	if not cluster or state.clusterHoverGeneration ~= state.surfaces.map.geometryGeneration
		or Method(addon, addon:GetPlayerTooltipPresentationParent(), "IsVisible") ~= true then
		HideTooltip(addon, state)
		return false
	end
	addon:HidePlayerTooltipPresentation(state)
	HoverHighlights(addon, state)
	local _, expanded, info = addon:GetPlayerLocationClusterExpansion(markers, geometry)
	local active = expanded and expanded.key == cluster.key
	local lines = {}
	local first = active and info.first or 1
	local last = active and info.last or #cluster.members
	local members = addon:BuildPlayerLocationClusterTooltipMembers(cluster.members, first, last, 6)
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
	UpdateMapFocus(addon, state)
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

local MARKER_GLOW_COLORS = {
	partners = { 1, 0.8, 0.15 },
	hidden = { 1, 0.12, 0.12 },
	selected = { 0.2, 1, 0.25 },
}

-- One halo for all player-marker states, including tooltip dots. Only its
-- color changes; the four layers share their geometry, opacity and blend mode.
function QuestTogether:CreatePlayerMarkerGlow(frame, anchor)
	local glow = {}
	for index = 1, 4 do
		local texture = Call(self, frame, "CreateTexture", nil, "BACKGROUND")
		Call(self, texture, "SetPoint", "CENTER", anchor or frame, "CENTER", 0, 0)
		Call(self, texture, "SetBlendMode", "ADD")
		local mask = Call(self, frame, "CreateMaskTexture")
		Call(self, mask, "SetAllPoints", texture)
		Call(self, mask, "SetTexture", "Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		Call(self, texture, "AddMaskTexture", mask)
		Call(self, texture, "Hide")
		glow[index] = texture
	end
	return glow
end

function QuestTogether:SetPlayerMarkerGlow(glow, kind, diameter)
	if glow.kind == kind and glow.diameter == diameter then return end
	local color = MARKER_GLOW_COLORS[kind]
	for index, texture in ipairs(glow) do
		local size = (diameter - (index - 1) * 2) * MARKER_GLOW_SCALE
		Call(self, texture, "SetSize", size, size)
		if color then Call(self, texture, "SetColorTexture", color[1], color[2], color[3], 0.06 + index * 0.07) end
		Call(self, texture, color and "Show" or "Hide")
	end
	glow.kind, glow.diameter = kind, diameter
end

-- Shared artwork for live pins and inert legend samples. Callers own the
-- frame, interaction, identity and party emphasis; this only creates regions.
function QuestTogether:CreatePlayerLocationSymbol(frame)
	local addon, pin = self, { frame = frame }
	Call(addon, pin.frame, "Hide")
	Call(addon, pin.frame, "SetSize", DOT_SIZE, DOT_SIZE)
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
	pin.glow = addon:CreatePlayerMarkerGlow(pin.frame)
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
	return pin
end

function QuestTogether:ApplyPlayerLocationSymbol(pin, style)
	local addon = self
	local r, g, b = style.r or 1, style.g or 1, style.b or 1
	local cluster = style.clusterCount ~= nil and style.clusterCount > 0
	local private, developer, looking = style.private, style.developer, style.looking
	local special = not cluster and (developer or style.vip)
	-- An active find highlight temporarily replaces red/gold rather than
	-- stacking halos; ending selection restores the underlying status color.
	local glowKind = style.selected and "selected" or private and "hidden" or looking and "partners" or nil
	local size = style.size or (cluster and 24 or special and 18 or glowKind and GLOW_DOT_SIZE or DOT_SIZE)
	Call(addon, pin.phaseIcon, style.phase and "Show" or "Hide")
	Call(addon, pin.texture, "SetColorTexture", r, g, b, 1)
	Call(addon, pin.developerGear, "SetVertexColor", r, g, b, 1)
	Call(addon, pin.developerGear, "SetTexture", PARTY_MEDIA .. (developer and "DeveloperGear" or "VIPStar"))
	Call(addon, pin.developerGear, special and "Show" or "Hide")
	Call(addon, pin.texture, special and "Hide" or "Show")
	Call(addon, pin.border, special and "Hide" or "Show")
	if pin.size ~= size or pin.private ~= private or pin.looking ~= looking
		or pin.symbolDeveloper ~= developer or pin.symbolCluster ~= cluster or pin.symbolGlowKind ~= glowKind then
		Call(addon, pin.border, "SetColorTexture", cluster and 0.8 or 0, cluster and 0.65 or 0, cluster and 0.25 or 0, glowKind and 0 or 1)
		Call(addon, pin.frame, "SetSize", size, size)
		Call(addon, pin.border, "SetSize", cluster and size or DOT_SIZE, cluster and size or DOT_SIZE)
		Call(addon, pin.texture, "SetSize", cluster and size - 3 or DOT_SIZE - 3, cluster and size - 3 or DOT_SIZE - 3)
		pin.size, pin.private, pin.looking = size, private, looking
		pin.symbolDeveloper, pin.symbolCluster, pin.symbolGlowKind = developer, cluster, glowKind
	end
	Call(addon, pin.count, "SetText", cluster and tostring(style.clusterCount) or "")
	Call(addon, pin.count, cluster and "Show" or "Hide")
	addon:SetPlayerMarkerGlow(pin.glow, glowKind, special and 24 or GLOW_DOT_SIZE)
end

local function CreatePin(addon, state, surface)
	local pin = addon:CreatePlayerLocationSymbol(New(addon, "Button", surface.frame))
	pin.surface = surface.name
	Call(addon, pin.frame, "RegisterForClicks", "LeftButtonUp", "RightButtonUp")
	pin.isCurrent = function() return FreshRow(addon, pin) ~= nil end
	Call(addon, pin.frame, "SetScript", "OnClick", function(_, button)
		if button ~= "LeftButton" and button ~= "RightButton" then
			return
		end
		if pin.cluster then OpenCluster(addon, state, pin); return end
		local ok, row = pcall(FreshRow, addon, pin)
		HideTooltip(addon, state)
		if ok and row then
			if pin.surface == "map" and button == "LeftButton" then
				pcall(ActivatePlayerMapPin, addon, pin, row)
			elseif button == "RightButton" then
				pcall(addon.OpenLocationPinPlayerMenu, addon, pin.frame, row.name, pin)
			end
		end
	end)
	Call(addon, pin.frame, "SetScript", "OnEnter", function()
		if pin.cluster then
			state.clusterHoverGeneration = surface.geometryGeneration
			if not pcall(ClusterTooltip, addon, state, pin) then HideTooltip(addon, state) end
			return
		end
		local ok, row = pcall(FreshRow, addon, pin)
		if ok and row then
			if pin.surface == "map" then state.mapHoverGeneration = surface.geometryGeneration end
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
		-- Map-level changes can briefly lack canvas geometry while the map
		-- remains open. Hide the stale pins without losing the selected player.
		if name == "map" and Native(addon, addon.API.IsWorldMapVisible) ~= true then addon:ClearPlayerMapSelection() end
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
	if surface.expandedClusterKey then
		-- Connectors share the single map-focus layer. Its owner handles hover
		-- precedence and falls back to the expanded cluster on pointer leave.
		surface.clusterShade = addon:AcquireMapOverlayShade(geometry)
	end
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
		pin.mapLevelOffset = levelOffset
		if level then Call(addon, pin.frame, "SetFrameLevel", level + levelOffset) end
		pin.baseAlpha = 1
		Call(addon, pin.frame, "SetAlpha", pin.baseAlpha)
		local r, g, b = 0.16, 0.13, 0.06
		if row then r, g, b = Color(addon, row.classFile) end
		addon:ApplyPlayerLocationSymbol(pin, {
			r = r, g = g, b = b,
			size = cluster and 24 or PinSize(addon, row.name, row),
			clusterCount = cluster and #cluster or nil,
			looking = row and HasLocationGlow(addon, row.name, row) == true,
			private = row and row.developerOnly and row.publicLocationHidden,
			developer = row and addon:IsVerifiedDeveloper(row.name) == true,
			vip = row and addon:IsVerifiedVIP(row.name) == true,
			selected = pin.selected,
			phase = row and addon:GetPlayerPhaseStatus(row.name) == "different",
		})
		Call(addon, pin.frame, "EnableMouseWheel", cluster ~= nil and marker.expansionInfo ~= nil and marker.expansionInfo.pages > 1)
		if marker.expanded then
			if not pin.connector then
				-- Connections remain legible above the shade and below member dots.
				pin.connector = Call(addon, surface.clusterShade, "CreateLine", nil, "OVERLAY")
				pin.focusDecorations = { pin.connector }
				Call(addon, pin.connector, "SetThickness", 1)
				Call(addon, pin.connector, "SetColorTexture", 0.8, 0.7, 0.45, 0.65)
			end
			Call(addon, pin.connector, "SetStartPoint", "TOPLEFT", surface.frame, marker.sourceX, -marker.sourceY)
			Call(addon, pin.connector, "SetEndPoint", "TOPLEFT", surface.frame, marker.x, -marker.y)
			Call(addon, pin.connector, "Show")
		elseif pin.connector then Hide(addon, state, pin.connector) end
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
	HoverHighlights(self, state)
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
