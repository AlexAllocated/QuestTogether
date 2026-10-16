-- OFFLINE ONLY. Not listed in the addon TOC; never load this in a live client.
-- Run: lua scripts/location_client_profiles.lua . retail (or forever).
local root, client = arg[1] or ".", arg[2] or "retail"
assert(client == "retail" or client == "forever", "expected retail or forever")
local file = assert(io.open(root .. "/scripts/test.lua"))
local harness = file:read("*a")
file:close()
-- Reuse only the offline environment setup, before any addon modules load.
harness = assert(harness:match("^(.-)local clientChecks ="))
assert((loadstring or load)(harness))()
local secret, inaccessible, inaccessibleReads = {}, {}, 0
setmetatable(inaccessible, {
	__index = function()
		inaccessibleReads = inaccessibleReads + 1
		error("unreadable")
	end,
})
issecretvalue = function(value)
	return value == secret
end
canaccessvalue = function(value)
	return value ~= inaccessible
end
canaccesstable = function(value)
	return value ~= inaccessible
end
local namespace = {}
-- Exercise the same dependency graph as the client; no second hand-maintained
-- module list can silently omit a new boundary adapter or service.
GetLocale = function() return "enUS" end
for line in io.lines(root .. "/QuestTogether.toc") do
	local name = line:match("^%s*(.-)%s*$")
	if name ~= "" and not name:match("^#") then
		assert(name:match("%.lua$"), "unsupported manifest entry: " .. name)
		assert(loadfile(root .. "/" .. name:gsub("\\", "/")))("QuestTogether", namespace)
	end
end
local addon = QuestTogether
addon.isEnabled = true
addon.db = { profile = { showPlayerLocations = true } }
addon.API.RegionalUniqueNamesEnabled = function()
	return client == "forever"
end
addon.API.GetTime = function()
	return 100
end
local partnerName = addon:NormalizeMemberName(client == "forever" and "Partner Othername" or "Partner-Realm")
local partnerStatus = { looking = false, receivedAt = 100 }
addon.qtPlayerPresenceState = { peers = {}, questPartners = { [partnerName] = partnerStatus } }
local restricted, rotated, ignoredRotation, facing = false, false, false, math.pi / 2
function addon:IsRuntimeRestricted()
	return restricted
end
local function Near(a, b)
	assert(type(a) == "number" and math.abs(a - b) < 0.00001, tostring(a) .. " vs " .. tostring(b))
end
local function Vector(x, y)
	return {
		x = x,
		y = y,
		GetXY = function(self)
			return self.x, self.y
		end,
	}
end
CreateVector2D = Vector
local forbiddenReads, frameReads = 0, 0
local function ReadFrame(frame)
	frameReads = frameReads + 1
	if frame.forbidden then
		forbiddenReads = forbiddenReads + 1
		error("forbidden native frame read")
	end
end
local function Frame(left, bottom, width, height, scale)
	return {
		IsForbidden = function(self)
			return self.forbidden == true
		end,
		IsShown = function(self)
			ReadFrame(self)
			return self.hidden ~= true
		end,
		IsVisible = function(self)
			ReadFrame(self)
			return self.hidden ~= true and self.visible ~= false
		end,
		GetRect = function(self)
			ReadFrame(self)
			return left, bottom, width, height
		end,
		GetEffectiveScale = function(self)
			ReadFrame(self)
			return scale
		end,
	}
end
local viewport, canvas = Frame(100, 200, 800, 600, 1), Frame(-250, 50, 1000, 500, 2)
local displayedMapID = 1
WorldMapFrame = Frame(0, 0, 1000, 800, 1)
function WorldMapFrame:GetMapID()
	ReadFrame(self)
	return displayedMapID
end
function WorldMapFrame:GetCanvasContainer()
	ReadFrame(self)
	return viewport
end
function WorldMapFrame:GetCanvas()
	ReadFrame(self)
	return canvas
end
local nativePinLevel, pinLevelReads = 2307, 0
local pinLevels
pinLevels = {
	GetValidFrameLevel = function(self, key, index)
		assert(self == pinLevels and key == "PIN_FRAME_LEVEL_TOPMOST")
		assert(index == 10000, "the topmost range must use its final pin, not its first")
		pinLevelReads = pinLevelReads + 1
		return nativePinLevel
	end,
}
local currentPinLevels = pinLevels
function WorldMapFrame:GetPinFrameLevelsManager()
	ReadFrame(self)
	return currentPinLevels
end
Minimap = Frame(0, 0, 200, 200, 0.8)
local shape = "ROUND"
GetMinimapShape = function()
	return shape
end
GetPlayerFacing = function()
	return facing
end
-- The native minimap map ID is nullable (ordinary terrain need not use a
-- HybridMinimap UI map). Do not assume it always equals the player's map.
local radius, minimapMap = 100, nil
local playerMap, playerMapReads = 1, 0
C_CVar = {
	GetCVarBool = function(key)
		assert(key == "rotateMinimap")
		return rotated
	end,
}
C_Minimap = {
	GetViewRadius = function()
		return radius
	end,
	GetUiMapID = function()
		return minimapMap
	end,
	IsRotateMinimapIgnored = function()
		return ignoredRotation
	end,
}
local wrongMap, worldUnavailable, badWorld, conversions, sameFloorGroup = false, false, nil, 0, false
C_Map = {
	GetBestMapForUnit = function(unit)
		assert(unit == "player")
		playerMapReads = playerMapReads + 1
		return playerMap
	end,
	GetMapGroupID = function()
		return sameFloorGroup and 7 or nil
	end,
	GetPlayerMapPosition = function(mapID, unit)
		assert((mapID == 1 or mapID == 2) and unit == "player")
		return Vector(0.5, 0.5)
	end,
	GetWorldPosFromMapPos = function(mapID, position)
		assert(mapID == 1 or mapID == 2 or mapID == 3)
		conversions = conversions + 1
		if worldUnavailable then
			return nil
		end
		return mapID == 3 and 1 or 0, badWorld or Vector(1000 - position.y * 1000, 2000 - position.x * 2000)
	end,
	GetMapPosFromWorldPos = function(continent, position, target)
		assert(target == 1 and continent == 0)
		assert(type(position.GetXY) == "function", "native vector constructor required")
		return wrongMap and 2 or target, Vector((2000 - position.y) / 2000, (1000 - position.x) / 1000)
	end,
}
local g = assert(addon:GetLocationPinSurface("map"))
Near(g.canvasLeft, -600)
Near(g.canvasTop, -300)
Near(g.canvasWidth, 2000)
Near(g.canvasHeight, 1000)
assert(g.pinFrameLevel == nativePinLevel and pinLevelReads == 1)
for _, level in ipairs({ 0, 10000 }) do
	nativePinLevel = level
	assert(addon:GetLocationPinSurface("map").pinFrameLevel == level)
end
for _, level in ipairs({ secret, inaccessible, -1, 10001, 2000.5, math.huge, -math.huge }) do
	nativePinLevel = level
	assert(addon:GetLocationPinSurface("map").pinFrameLevel == nil)
end
nativePinLevel = 2307
for _, manager in ipairs({ secret, inaccessible, {} }) do
	currentPinLevels = manager
	local reads = pinLevelReads
	assert(addon:GetLocationPinSurface("map").pinFrameLevel == nil)
	assert(pinLevelReads == reads and inaccessibleReads == 0)
end
currentPinLevels = nil
assert(addon:GetLocationPinSurface("map").pinFrameLevel == nil)
currentPinLevels = pinLevels
local levelsGetter = WorldMapFrame.GetPinFrameLevelsManager
WorldMapFrame.GetPinFrameLevelsManager = nil
assert(addon:GetLocationPinSurface("map").pinFrameLevel == nil)
WorldMapFrame.GetPinFrameLevelsManager = levelsGetter
local validLevelGetter = pinLevels.GetValidFrameLevel
pinLevels.GetValidFrameLevel = secret
assert(addon:GetLocationPinSurface("map").pinFrameLevel == nil)
pinLevels.GetValidFrameLevel = inaccessible
assert(addon:GetLocationPinSurface("map").pinFrameLevel == nil)
pinLevels.GetValidFrameLevel = validLevelGetter

-- Use the real guarded adapter with native-shaped map operations. The marker
-- is deliberately offset; each member must be projected independently at every
-- level, and only their deepest shared child map may be opened.
local cluster = { key = "A\nB", x = 12, y = 12, members = {
	{ name = "A", mapID = 1, x = 0.4, y = 0.6 }, { name = "B", mapID = 1, x = 0.6, y = 0.6 },
} }
local magnificationReads = 0
local positionInfo, ancestorInfo, nativeActions = nil, { [1] = { mapID = 1, parentMapID = 0 } }, {}
local positionResolver, invalidProjection
local positionReads, ancestryReads = 0, 0
local ordinaryMapProjection = C_Map.GetMapPosFromWorldPos
local ordinaryWorldProjection, ordinaryWorldSize = C_Map.GetWorldPosFromMapPos, C_Map.GetMapWorldSize
local navigationMapBounds = { [2] = { left = 0.2, width = 0.6 }, [3] = { left = 0.3, width = 0.4 } }
local function NavigationBounds(mapID)
	if navigationMapBounds[mapID] then return navigationMapBounds[mapID] end
	local width = 0.2 + 0.8 / 2^(mapID - 1)
	return { left = (1 - width) / 2, width = width }
end
C_Map.GetWorldPosFromMapPos = function(mapID, position)
	conversions = conversions + 1
	if worldUnavailable then return nil end
	local bounds = NavigationBounds(mapID)
	return 0, Vector(1000 - position.y * 1000, 2000 - (bounds.left + position.x * bounds.width) * 2000)
end
C_Map.GetMapWorldSize = function(mapID) return NavigationBounds(mapID).width * 2000, 1000 end
C_Map.GetMapPosFromWorldPos = function(continent, position, target)
	assert(continent == 0 and type(position.GetXY) == "function")
	local x, y = (2000 - position.y) / 2000, (1000 - position.x) / 1000
	local bounds = NavigationBounds(target)
	x = (x - bounds.left) / bounds.width
	if invalidProjection == target then x = 2 end
	return target, Vector(x, y)
end
local function PositionInfo(mapID, px, py)
	positionReads = positionReads + 1
	local bounds = NavigationBounds(mapID)
	local originalX = px * bounds.width + bounds.left
	assert(math.abs(originalX - 0.4) < 0.00001 or math.abs(originalX - 0.6) < 0.00001,
		"look up real members, not the centroid or marker inset")
	Near(py, 0.6)
	if positionResolver then return positionResolver(mapID, originalX) end
	return mapID == 1 and positionInfo or nil
end
C_Map.GetMapInfoAtPosition = PositionInfo
C_Map.GetMapInfo = function(mapID)
	ancestryReads = ancestryReads + 1
	return ancestorInfo[mapID]
end
function WorldMapFrame:IsZoomingIn() magnificationReads = magnificationReads + 1; return true end
function WorldMapFrame:IsAtMaxZoom() magnificationReads = magnificationReads + 1; return false end
function WorldMapFrame:SetMapID(mapID)
	ReadFrame(self)
	local intent = rawget(addon, "playerLocationClusterNavigation")
	assert(intent and intent.targetMapID == mapID and intent.key == cluster.key,
		"the expansion intent must exist before synchronous native callbacks")
	nativeActions[#nativeActions + 1] = { "navigate", mapID }
	displayedMapID = mapID
end
function WorldMapFrame:PanAndZoomTo(px, py)
	ReadFrame(self)
	nativeActions[#nativeActions + 1] = { "zoom", px, py }
	error("cluster navigation must never magnify the current map")
end
positionInfo = { mapID = 2, parentMapID = 1 }
local action, target, centerX, centerY = addon:GetPlayerLocationClusterNavigationAction(cluster, g)
assert(action == "navigate" and target == 2 and #nativeActions == 0)
Near(centerX, 0.5)
Near(centerY, 0.6)
assert(addon:TryNavigatePlayerLocationCluster(cluster, g))
assert(#nativeActions == 1 and nativeActions[1][1] == "navigate" and displayedMapID == 2)
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "unavailable", "stale map geometry cannot navigate")
displayedMapID = 1
positionInfo = { mapID = 3, parentMapID = 2 }
ancestorInfo[2] = { mapID = 2, parentMapID = 1 }
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "navigate", "strict descendants may skip an intermediate map")
for _, info in ipairs({ { mapID = 1, parentMapID = 0 } }) do
	positionInfo = info
	assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "expand", "same or ancestor map must never navigate backward")
end
positionInfo = nil
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "expand")
assert(not addon:TryNavigatePlayerLocationCluster(cluster, g) and #nativeActions == 1)
assert(magnificationReads == 0, "canvas zoom state must not delay expansion or trigger pixel magnification")

positionResolver = function(mapID)
	if mapID < 4 then return { mapID = mapID + 1, parentMapID = mapID } end
end
action, target = addon:GetPlayerLocationClusterNavigationAction(cluster, g)
assert(action == "navigate" and target == 4, "one click must skip directly through all shared child levels")
assert(addon:TryNavigatePlayerLocationCluster(cluster, g))
assert(#nativeActions == 2 and nativeActions[2][2] == 4 and displayedMapID == 4,
	"open only the final map, never each intermediate map")
displayedMapID = 1

navigationMapBounds[3], navigationMapBounds[4] = { left = 0.3, width = 0.2 }, { left = 0.5, width = 0.2 }
positionResolver = function(mapID, px)
	if mapID == 1 then return { mapID = 2, parentMapID = 1 } end
	if mapID == 2 then return { mapID = px < 0.5 and 3 or 4, parentMapID = 2 } end
end
action, target = addon:GetPlayerLocationClusterNavigationAction(cluster, g)
assert(action == "navigate" and target == 2, "split subzones must stop at the shared containing zone")
displayedMapID = 2
local zoneGeometry = assert(addon:GetLocationPinSurface("map"))
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, zoneGeometry) == "expand",
	"already on the deepest shared zone: expand without selecting one member's subzone")
displayedMapID = 1

-- GetMapInfoAtPosition can itself skip intermediate maps. Intersect verified
-- ancestry, so two different returned subzones still find their common zone.
ancestorInfo[2] = { mapID = 2, parentMapID = 1 }
positionResolver = function(mapID, px)
	if mapID == 1 or mapID == 2 then return { mapID = px < 0.5 and 3 or 4, parentMapID = 2 } end
end
action, target = addon:GetPlayerLocationClusterNavigationAction(cluster, g)
assert(action == "navigate" and target == 2, "different descendants can share a skipped intermediate map")
local crowded = { members = {} }
for index = 1, 512 do crowded.members[index] = { mapID = 1, x = 0.4, y = 0.6 } end
crowded.members[512].x = 0.6
local ancestryStart = ancestryReads
action, target = addon:GetPlayerLocationClusterNavigationAction(crowded, g)
assert(action == "navigate" and target == 2)
assert(ancestryReads - ancestryStart == 2, "source and shared native ancestry must each be read once, not once per member")
navigationMapBounds[2], navigationMapBounds[3] = { left = 0.2, width = 0.3 }, { left = 0.5, width = 0.3 }
positionResolver = function(mapID, px)
	if mapID == 1 then return { mapID = px < 0.5 and 2 or 3, parentMapID = 1 } end
end
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "expand",
	"a cluster crossing zone boundaries must stay on the current map")
assert(addon:GetPlayerLocationClusterNavigationAction(crowded, g) == "expand",
	"the final member of a full cluster must still prevent choosing the wrong zone")
crowded.members[513] = crowded.members[1]
local crowdedReads = positionReads
assert(addon:GetPlayerLocationClusterNavigationAction(crowded, g) == "unavailable" and positionReads == crowdedReads,
	"oversized clusters must not silently truncate the containment check")
positionResolver = function(mapID, px)
	if mapID == 1 and px < 0.5 then return { mapID = 2, parentMapID = 1 } end
end
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "expand",
	"a member outside every child prevents moving the cluster into a child")

navigationMapBounds[2], navigationMapBounds[3], navigationMapBounds[4] = nil, nil, nil
positionResolver = function(mapID) return { mapID = mapID + 1, parentMapID = mapID } end
local readLimitStart = positionReads
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "unavailable")
assert(positionReads - readLimitStart <= 32, "unbounded native hierarchies must not loop")
positionResolver = nil
positionInfo = { mapID = 2, parentMapID = 1 }
invalidProjection = 2
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "expand",
	"a child must actually contain every projected member")
invalidProjection, sameFloorGroup = nil, true
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "expand",
	"world coordinates cannot invent a member's location on another floor")
sameFloorGroup = false

for _, info in ipairs({ secret, inaccessible, { mapID = secret }, { mapID = 1000001 },
	{ mapID = 2, parentMapID = secret }, { mapID = 2, parentMapID = 2 } }) do
	positionInfo = info
	ancestorInfo[2] = { mapID = 2, parentMapID = 2 }
	assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "unavailable")
	assert(addon:TryNavigatePlayerLocationCluster(cluster, g) and #nativeActions == 2)
end
positionInfo = nil
for _, getter in ipairs({ secret, inaccessible, function() error("native navigation unavailable") end }) do
	C_Map.GetMapInfoAtPosition = getter
	assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "unavailable")
end
C_Map.GetMapInfoAtPosition = nil
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "unavailable")
C_Map.GetMapInfoAtPosition = PositionInfo
local mapSetter = WorldMapFrame.SetMapID
positionInfo = { mapID = 2, parentMapID = 1 }
WorldMapFrame.SetMapID = nil
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "unavailable")
WorldMapFrame.SetMapID = mapSetter
positionInfo = nil
local savedX = cluster.members[1].x
cluster.members[1].x = secret
assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "unavailable")
cluster.members[1].x = savedX
for _, field in ipairs({ "mapID", "canvasLeft", "canvasWidth", "width" }) do
	local stale = {}
	for key, value in pairs(g) do stale[key] = value end
	stale[field] = stale[field] + 1
	assert(addon:GetPlayerLocationClusterNavigationAction(cluster, stale) == "unavailable")
end
for _, boundary in ipairs({ "forbidden", "hidden", "invisible", "restricted", "disabled" }) do
	local reads = positionReads
	if boundary == "forbidden" then WorldMapFrame.forbidden = true
	elseif boundary == "hidden" then WorldMapFrame.hidden = true
	elseif boundary == "invisible" then WorldMapFrame.visible = false
	elseif boundary == "restricted" then restricted = true
	else addon.isEnabled = false end
	assert(addon:GetPlayerLocationClusterNavigationAction(cluster, g) == "unavailable")
	assert(addon:TryNavigatePlayerLocationCluster(cluster, g))
	assert(positionReads == reads and #nativeActions == 2)
	WorldMapFrame.forbidden, WorldMapFrame.hidden, WorldMapFrame.visible = false, false, true
	restricted, addon.isEnabled = false, true
end
positionInfo = { mapID = 2, parentMapID = 1 }
for _, mode in ipairs({ "consume", "decline", "throw", "unchanged", "wrong-map", "consume-then-throw", "consume-then-restrict" }) do
	local callbackConsumed = false
	WorldMapFrame.SetMapID = function(self, mapID)
		ReadFrame(self)
		local intent = rawget(addon, "playerLocationClusterNavigation")
		assert(intent and intent.targetMapID == mapID and intent.navigating)
		if mode == "decline" then return false end
		if mode == "throw" then error("native navigation failed") end
		if mode == "unchanged" then return end
		if mode == "wrong-map" then displayedMapID = 3; return end
		displayedMapID = mapID
		local targetGeometry = assert(addon:GetLocationPinSurface("map"))
		local targetMarker = { key = cluster.key, members = cluster.members, x = 400, y = 300 }
		assert(addon:ConsumePlayerLocationClusterNavigation({ targetMarker }, targetGeometry),
			"synchronous native map notification must see and consume the intent")
		callbackConsumed = true
		assert(rawget(addon, "playerLocationClusterNavigation") == nil)
		if mode == "consume-then-throw" then error("native failure after callback") end
		if mode == "consume-then-restrict" then restricted = true end
	end
	assert(addon:TryNavigatePlayerLocationCluster(cluster, g))
	assert(callbackConsumed == (mode:find("consume", 1, true) == 1),
		"a swallowed native callback failure must not masquerade as a tested rollback")
	assert(rawget(addon, "playerLocationClusterNavigation") == nil)
	if mode == "consume" then
		assert(addon.playerLocationClusterExpansion and addon.playerLocationClusterExpansion.key == cluster.key,
			"successful native return must preserve the synchronous auto-expansion")
	else
		assert(rawget(addon, "playerLocationClusterExpansion") == nil,
			"failed or blocked native navigation must retire its own consumed expansion")
	end
	addon:ClearPlayerLocationClusterExpansion()
	displayedMapID, restricted = 1, false
end
WorldMapFrame.SetMapID = mapSetter

-- Forever's Tirisfal Glades (18) and Undercity (998) are sibling zone maps
-- under Eastern Kingdoms (13). Art hierarchy cannot decide which contains all
-- players: the surrounding zone covers the city, while the city is smaller.
navigationMapBounds[13] = { left = 0, width = 1 }
navigationMapBounds[18] = { left = 0.3, width = 0.4 }
navigationMapBounds[998] = { left = 0.5, width = 0.15 }
ancestorInfo[13] = { mapID = 13, parentMapID = 1, mapType = 2 }
ancestorInfo[18] = { mapID = 18, parentMapID = 13, mapType = 3 }
ancestorInfo[998] = { mapID = 998, parentMapID = 13, mapType = 3 }
local function GeographicRow(name, mapID, wx)
	local bounds = NavigationBounds(mapID)
	return { name = name, mapID = mapID, x = (wx - bounds.left) / bounds.width, y = 0.6 }
end
local mixedCity = { key = "A\nB\nC", members = {
	GeographicRow("A", 18, 0.4), GeographicRow("B", 998, 0.6), GeographicRow("C", 998, 0.6),
} }
C_Map.GetMapInfoAtPosition = function(mapID, px)
	local bounds = NavigationBounds(mapID)
	local wx = bounds.left + px * bounds.width
	if mapID == 1 then return ancestorInfo[13] end
	if mapID == 13 or mapID == 18 then return wx < 0.5 and ancestorInfo[18] or ancestorInfo[998] end
	return ancestorInfo[998]
end
for _, source in ipairs({ 1, 13 }) do
	displayedMapID = source
	action, target = addon:GetPlayerLocationClusterNavigationAction(mixedCity, addon:GetLocationPinSurface("map"))
	assert(action == "navigate" and target == 18, "Tirisfal must contain the surrounding-zone player and both city players")
end
local allCity = { key = "A\nB", members = { GeographicRow("A", 998, 0.6), GeographicRow("B", 998, 0.6) } }
for _, source in ipairs({ 1, 13, 18 }) do
	displayedMapID = source
	action, target = addon:GetPlayerLocationClusterNavigationAction(allCity, addon:GetLocationPinSurface("map"))
	assert(action == "navigate" and target == 998, "all city players should open Undercity, including from sibling Tirisfal")
end
displayedMapID = 18
assert(addon:GetPlayerLocationClusterNavigationAction(mixedCity, addon:GetLocationPinSurface("map")) == "expand",
	"a mixed zone/city cluster already in Tirisfal must not jump sideways or upward")
displayedMapID = 998
assert(addon:GetPlayerLocationClusterNavigationAction(allCity, addon:GetLocationPinSurface("map")) == "expand")

displayedMapID = 18
local cityFromZone = { key = "A\nB", members = { GeographicRow("A", 18, 0.6), GeographicRow("B", 18, 0.6) } }
local cityBounds = navigationMapBounds[998]
for _, bounds in ipairs({ { left = 0.3, width = 0.4 }, { left = 0.25, width = 0.5 } }) do
	navigationMapBounds[998] = bounds
	assert(addon:GetPlayerLocationClusterNavigationAction(cityFromZone, addon:GetLocationPinSurface("map")) == "expand",
		"equal or larger sibling maps must not cause sideways or upward navigation")
end
navigationMapBounds[998] = cityBounds
local zoneBounds = navigationMapBounds[18]
navigationMapBounds[18], navigationMapBounds[998] = { left = 0.25, width = 0.5 }, { left = 0.5, width = 0.125 }
local onCityBorder = { members = { GeographicRow("A", 18, 0.5), GeographicRow("B", 18, 0.625) } }
action, target = addon:GetPlayerLocationClusterNavigationAction(onCityBorder, addon:GetLocationPinSurface("map"))
assert(action == "navigate" and target == 998, "inclusive normalized map borders still contain all members")
onCityBorder.members[2] = GeographicRow("B", 18, 0.62501)
assert(addon:GetPlayerLocationClusterNavigationAction(onCityBorder, addon:GetLocationPinSurface("map")) == "expand",
	"a member even slightly beyond the city border prevents choosing the city")
navigationMapBounds[18], navigationMapBounds[998] = zoneBounds, cityBounds
sameFloorGroup = true
assert(addon:GetPlayerLocationClusterNavigationAction(cityFromZone, addon:GetLocationPinSurface("map")) == "expand",
	"overlapping map art cannot invent a member's floor")
sameFloorGroup = false
local geographicWorldProjection, geographicWorldSize = C_Map.GetWorldPosFromMapPos, C_Map.GetMapWorldSize
C_Map.GetWorldPosFromMapPos = function(mapID, position)
	local continent, point = geographicWorldProjection(mapID, position)
	return mapID == 998 and 1 or continent, point
end
assert(addon:GetPlayerLocationClusterNavigationAction(cityFromZone, addon:GetLocationPinSurface("map")) == "expand",
	"smaller art in a different world instance is not a valid containing map")
C_Map.GetWorldPosFromMapPos = geographicWorldProjection
worldUnavailable = true
assert(addon:GetPlayerLocationClusterNavigationAction(cityFromZone, addon:GetLocationPinSurface("map")) == "expand",
	"unavailable world geometry cannot authorize a sibling-map jump")
worldUnavailable = false
C_Map.GetMapWorldSize = nil
action, target = addon:GetPlayerLocationClusterNavigationAction(cityFromZone, addon:GetLocationPinSurface("map"))
assert(action == "navigate" and target == 998, "half-map world projection supplies the native size API fallback")
C_Map.GetMapWorldSize = geographicWorldSize
displayedMapID = 1
C_Map.GetWorldPosFromMapPos = function(mapID, position)
	if mapID == 1 then return nil end
	return geographicWorldProjection(mapID, position)
end
action, target = addon:GetPlayerLocationClusterNavigationAction(allCity, addon:GetLocationPinSurface("map"))
assert(action == "navigate" and target == 998, "world maps without geographic size retain verified hierarchy descent")
C_Map.GetWorldPosFromMapPos = geographicWorldProjection
displayedMapID = 1
assert(forbiddenReads == 0 and inaccessibleReads == 0 and magnificationReads == 0)
C_Map.GetMapPosFromWorldPos = ordinaryMapProjection
C_Map.GetWorldPosFromMapPos, C_Map.GetMapWorldSize = ordinaryWorldProjection, ordinaryWorldSize
local x, y = addon:ProjectPlayerLocationPin("map", { mapID = 1, x = 0.5, y = 0.6 }, g)
Near(x, 400)
Near(y, 300)
-- With the native canvas offset/scale, this dot is seven pixels inside the
-- viewport: the normal six-pixel radius fits, but the gold eight-pixel one does not.
local edgeRow = { name = partnerName, mapID = 1, x = 0.3035, y = 0.6 }
Near(addon:ProjectPlayerLocationPin("map", edgeRow, g), 7)
partnerStatus.looking = true
assert(addon:ProjectPlayerLocationPin("map", edgeRow, g) == nil, "clip the complete gold glow at the map edge")
partnerStatus.looking = false
local before = conversions
addon:GetLocationPinMapPosition({ mapID = 1, x = 0.5, y = 0.5 }, 1)
assert(conversions == before, "same map needs no world conversion")
x, y = addon:GetLocationPinMapPosition({ mapID = 2, x = 0.2, y = 0.3 }, 1)
Near(x, 0.2)
Near(y, 0.3)
wrongMap = true
assert(addon:GetLocationPinMapPosition({ mapID = 2, x = 0.2, y = 0.3 }, 1) == nil)
wrongMap, worldUnavailable = false, true
assert(addon:GetLocationPinMapPosition({ mapID = 2, x = 0.2, y = 0.3 }, 1) == nil)
worldUnavailable = false
sameFloorGroup = true
assert(addon:ProjectPlayerLocationPin("map", { mapID = 2, x = 0.5, y = 0.6 }, g) == nil)
sameFloorGroup = false
for _, frame in ipairs({ WorldMapFrame, viewport, canvas, Minimap }) do
	frame.forbidden = true
	local reads = pinLevelReads
	assert(addon:GetLocationPinSurface(frame == Minimap and "minimap" or "map") == nil)
	assert(pinLevelReads == reads, "forbidden geometry must not query pin levels")
	-- Assertions inside native fakes may be swallowed by production pcall.
	-- Check persistent counters outside that boundary after every scenario.
	assert(forbiddenReads == 0, "a swallowed error hid a forbidden native read")
	frame.forbidden = false
end
viewport.hidden = true
assert(addon:GetLocationPinSurface("map") == nil)
viewport.hidden = false

g = assert(addon:GetLocationPinSurface("minimap"))
assert(g.mapID == 1 and playerMapReads > 0, "ordinary minimap uses the player's current map when no UI map exists")
assert(g.continent == 0, "world instance zero is valid")
x, y = addon:ProjectPlayerLocationPin("minimap", { mapID = 1, x = 0.525, y = 0.5 }, g)
Near(x, 150)
Near(y, 100)
-- A hybrid minimap's explicit map/floor remains authoritative. Unreadable or
-- invalid IDs must fail closed rather than falling back to another floor.
before = playerMapReads
minimapMap = 2
g = assert(addon:GetLocationPinSurface("minimap"))
assert(g.mapID == 2 and playerMapReads == before)
for _, invalid in ipairs({ secret, inaccessible, 0, -1, "invalid" }) do
	minimapMap = invalid
	assert(addon:GetLocationPinSurface("minimap") == nil)
	assert(playerMapReads == before, "invalid explicit minimap map must not trigger a fallback")
end
minimapMap = nil
for _, invalid in ipairs({ secret, inaccessible, 0, -1, "invalid" }) do
	playerMap = invalid
	assert(addon:GetLocationPinSurface("minimap") == nil)
end
playerMap = nil
assert(addon:GetLocationPinSurface("minimap") == nil, "no dots when neither map ID is available")
playerMap = 1
local minimapMapGetter = C_Minimap.GetUiMapID
C_Minimap.GetUiMapID = nil
assert(addon:GetLocationPinSurface("minimap").mapID == 1, "clients without a hybrid map getter use the player's map")
C_Minimap.GetUiMapID = minimapMapGetter
g = assert(addon:GetLocationPinSurface("minimap"))
edgeRow = { name = partnerName, mapID = 1, x = 0.5465, y = 0.5 }
Near(addon:ProjectPlayerLocationPin("minimap", edgeRow, g), 193)
partnerStatus.looking = true
assert(addon:ProjectPlayerLocationPin("minimap", edgeRow, g) == nil, "clip the complete gold glow at the minimap edge")
partnerStatus.looking = false
rotated = true
g = assert(addon:GetLocationPinSurface("minimap"))
x, y = addon:ProjectPlayerLocationPin("minimap", { mapID = 1, x = 0.475, y = 0.5 }, g)
Near(x, 100)
Near(y, 50)
ignoredRotation = true
g = assert(addon:GetLocationPinSurface("minimap"))
x, y = addon:ProjectPlayerLocationPin("minimap", { mapID = 1, x = 0.525, y = 0.5 }, g)
Near(x, 150)
Near(y, 100)
ignoredRotation, facing = false, secret
assert(addon:GetLocationPinSurface("minimap") == nil, "unreadable heading must not become north-up")
facing, rotated = math.pi / 2, false
radius = 200
g = assert(addon:GetLocationPinSurface("minimap"))
x, y = addon:ProjectPlayerLocationPin("minimap", { mapID = 1, x = 0.525, y = 0.5 }, g)
Near(x, 125)
Near(y, 100)
radius = secret
assert(addon:GetLocationPinSurface("minimap") == nil)
radius, shape = 100, "UNKNOWN"
assert(addon:GetLocationPinSurface("minimap") == nil)
shape = "ROUND"
local shapeGetter = GetMinimapShape
GetMinimapShape = function()
	error("shape temporarily unavailable")
end
assert(addon:GetLocationPinSurface("minimap") == nil)
GetMinimapShape = nil
assert(addon:GetLocationPinSurface("minimap"), "native minimap defaults to round without a custom shape provider")
GetMinimapShape = shapeGetter
badWorld = inaccessible
assert(addon:GetLocationPinSurface("minimap") == nil)
assert(inaccessibleReads == 0)
badWorld = Vector(secret, 500)
assert(addon:GetLocationPinSurface("minimap") == nil)
badWorld = nil
local getter = C_Minimap.GetViewRadius
C_Minimap.GetViewRadius = nil
assert(addon:GetLocationPinSurface("minimap") == nil, "missing modern geometry omits marker")
C_Minimap.GetViewRadius = getter
local origin = assert(addon:GetPlayerLocationPriorityOrigin())
assert(origin.continent == 0 and origin.north == 500 and origin.west == 1000)
Near(addon:GetPlayerLocationPriorityDistance({ mapID = 1, x = 0.51, y = 0.5, mask = 3 }, origin), 400)
assert(addon:GetPlayerLocationPriorityDistance({ mapID = 3, x = 0.5, y = 0.5, mask = 3 }, origin) == math.huge)
badWorld = Vector(secret, 500)
assert(addon:GetPlayerLocationPriorityOrigin() == nil)
badWorld = nil
restricted = true
local reads, nativeFrameReads = conversions, frameReads
local nativePinLevelReads = pinLevelReads
before = playerMapReads
assert(addon:GetLocationPinSurface("minimap") == nil and addon:GetLocationPinSurface("map") == nil)
assert(addon:GetPlayerLocationPriorityOrigin() == nil)
assert(conversions == reads)
assert(frameReads == nativeFrameReads, "restricted geometry must not read native frames")
assert(pinLevelReads == nativePinLevelReads, "restricted geometry must not read native pin levels")
assert(playerMapReads == before, "restricted geometry must not query a fallback map")
assert(forbiddenReads == 0)
assert(inaccessibleReads == 0)
print(
	"location native contracts "
		.. client
		.. ": PASS (projection, scale, pan, native pin layering and child navigation, cross-map, nullable minimap map, LFG glow edges, radius, rotation override, secrecy, unavailable APIs)"
)
