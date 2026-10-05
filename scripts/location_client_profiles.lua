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
for _, name in ipairs({
	"Libs/libchev/libchev.lua",
	"Core.lua",
	"HotPathRuntime.lua",
	"Minimap.lua",
	"PartyState.lua",
	"PlayerPlates.lua",
	"LocationPins.lua",
}) do
	assert(loadfile(root .. "/" .. name))("QuestTogether", namespace)
end
local addon = QuestTogether
addon.isEnabled = true
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
WorldMapFrame = Frame(0, 0, 1000, 800, 1)
function WorldMapFrame:GetMapID()
	ReadFrame(self)
	return 1
end
function WorldMapFrame:GetCanvasContainer()
	ReadFrame(self)
	return viewport
end
function WorldMapFrame:GetCanvas()
	ReadFrame(self)
	return canvas
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
	assert(addon:GetLocationPinSurface(frame == Minimap and "minimap" or "map") == nil)
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
before = playerMapReads
assert(addon:GetLocationPinSurface("minimap") == nil and addon:GetLocationPinSurface("map") == nil)
assert(addon:GetPlayerLocationPriorityOrigin() == nil)
assert(conversions == reads)
assert(frameReads == nativeFrameReads, "restricted geometry must not read native frames")
assert(playerMapReads == before, "restricted geometry must not query a fallback map")
assert(forbiddenReads == 0)
assert(inaccessibleReads == 0)
print(
	"location native contracts "
		.. client
		.. ": PASS (projection, scale, pan, cross-map, nullable minimap map, LFG glow edges, radius, rotation override, secrecy, unavailable APIs)"
)
