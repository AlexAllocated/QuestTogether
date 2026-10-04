local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether
local LibChev = QuestTogether.LibChev
local MAX_PINS, MAX_LOCATION_ROWS, DOT_SIZE = 128, 512, 12
local PARTNER_DOT_SIZE = 16

local function PinSize(addon, name)
	return addon:IsPlayerLookingForQuestPartners(name)
		and PARTNER_DOT_SIZE or DOT_SIZE
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

function QuestTogether:GetPlayerLocationPriorityDistance(row, origin)
	if not origin or row.mask == 0 then return math.huge end
	local continent, north, west = self:GetLocationPinWorldPosition(row.mapID, row.x, row.y)
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
		local ratio = art.scale / viewport.scale
		return {
			parent = parent,
			mapID = mapID,
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
	local mapID = ID(self, API(self, C_Minimap, "GetUiMapID"))
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
function QuestTogether:ProjectPlayerLocationPin(surface, row, geometry)
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
	local dotSize = PinSize(self, row.name)
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

local function Mutable(region)
	return LibChev.CanMutateOwnedRegion(region)
end
local function Guard(addon, region)
	return not addon:IsRuntimeRestricted() and Mutable(region)
end
local function Call(addon, region, name, ...)
	if not Guard(addon, region) then
		error("location pin region unavailable", 0)
	end
	return region[name](region, ...)
end

local function New(addon, kind, parent)
	if addon:IsRuntimeRestricted() or (parent and not addon:CanAccessForeignFrame(parent)) then
		error("location pin parent unavailable", 0)
	end
	local frame = addon:CreateLocationPinFrame(kind, nil, parent)
	if not Guard(addon, frame) then
		error("location pin frame unavailable", 0)
	end
	return frame
end

local function RetryCleanup(addon, state)
	for region in pairs(state.pending) do
		if Mutable(region) and pcall(region.Hide, region) then
			state.pending[region] = nil
		end
	end
	if not next(state.pending) and Mutable(state.wake) then
		state.wake:SetScript("OnUpdate", nil)
		state.cleanupArmed = false
	end
end

local function Hide(addon, state, region)
	if not region then
		return
	end
	-- Hiding an owned, nonprotected region is safe during combat. Layout and
	-- rendering remain blocked; forbidden/protected descendants are deferred.
	if Mutable(region) and pcall(region.Hide, region) then
		state.pending[region] = nil
		return
	end
	state.pending[region] = true
	if not state.cleanupArmed and Mutable(state.wake) then
		state.cleanupArmed = true
		local elapsed = 0
		state.wake:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + (Number(addon, delta) or 0)
			if elapsed >= 0.25 then
				elapsed = 0
				RetryCleanup(addon, state)
			end
		end)
	end
end

local function State(addon)
	local state = rawget(addon, "locationPinState")
	if not state then
		state = { surfaces = {}, pending = {} }
		state.wake = New(addon, "Frame")
		addon.locationPinState = state
	end
	return state
end

local function HideTooltip(addon, state)
	state.hovered = nil
	Hide(addon, state, state.tooltip)
end

local function HideSurface(addon, state, surface)
	if not surface then
		return
	end
	for _, pin in ipairs(surface.pins) do
		pin.name = nil
	end
	Hide(addon, state, surface.frame)
	if state.hovered and state.hovered.surface == surface.name then
		HideTooltip(addon, state)
	end
end

function QuestTogether:HidePlayerLocationPins()
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
	if not addon.isEnabled or addon:IsRuntimeRestricted() or not pin.name or not Guard(addon, pin.frame) then
		return nil
	end
	local geometry = addon:GetLocationPinSurface(pin.surface)
	if not geometry or geometry.parent ~= pin.parent or geometry.mapID ~= pin.mapID then
		return nil
	end
	local rows = addon:GetVisiblePlayerLocations(pin.surface)
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

function QuestTogether:OpenLocationPinPlayerMenu(frame, name)
	if not self.isEnabled or self:IsRuntimeRestricted() or not Guard(self, frame) or self:IsIgnoredPlayerName(name) then
		return false
	end
	return self:ShowChatLogSpeakerMenu(frame, name)
end

local function Color(addon, classFile)
	local color = addon:SafeTrimString(addon:GetClassColorCode(classFile), "")
	local r, g, b = color:match("^|c%x%x(%x%x)(%x%x)(%x%x)$")
	if r then
		return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
	end
	return 1, 1, 1
end

local function Text(addon, value, fallback)
	local text = addon:SafeTrimString(value, "")
	if text == "" then
		text = fallback or L("Unknown")
	end
	return text:gsub("|", "||")
end

local function Tooltip(addon, state, pin, row)
	local parent = addon:GetLocationPinTooltipParent()
	if not addon:CanAccessForeignFrame(parent, true) or not Guard(addon, pin.frame) then
		return
	end
	local tooltip = state.tooltip
	if not tooltip then
		tooltip = New(addon, "Frame", parent)
		Call(addon, tooltip, "Hide")
		state.tooltip = tooltip
		Call(addon, tooltip, "SetFrameStrata", "TOOLTIP")
		Call(addon, tooltip, "SetClampedToScreen", true)
		local background = Call(addon, tooltip, "CreateTexture", nil, "BACKGROUND")
		Call(addon, background, "SetAllPoints")
		Call(addon, background, "SetColorTexture", 0.03, 0.03, 0.04, 0.97)
		state.tooltipTitle = Call(addon, tooltip, "CreateFontString", nil, "OVERLAY", "GameFontNormalLarge")
		Call(addon, state.tooltipTitle, "SetPoint", "TOPLEFT", 14, -12)
		Call(addon, state.tooltipTitle, "SetWidth", 272)
		Call(addon, state.tooltipTitle, "SetJustifyH", "LEFT")
		Call(addon, state.tooltipTitle, "SetWordWrap", true)
		local divider = Call(addon, tooltip, "CreateTexture", nil, "BORDER")
		state.tooltipDivider = divider
		Call(addon, divider, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -8)
		Call(addon, divider, "SetSize", 272, 1)
		state.tooltipFaction = Call(addon, tooltip, "CreateTexture", nil, "ARTWORK")
		Call(addon, state.tooltipFaction, "SetPoint", "TOPRIGHT", -14, -12)
		Call(addon, state.tooltipFaction, "SetSize", 18, 18)
		Call(addon, state.tooltipFaction, "SetAlpha", 0.65)
		state.tooltipLabel = Call(addon, tooltip, "CreateFontString", nil, "OVERLAY", "GameFontHighlight")
		Call(addon, state.tooltipLabel, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -18)
		Call(addon, state.tooltipLabel, "SetWidth", 272)
		Call(addon, state.tooltipLabel, "SetJustifyH", "LEFT")
		Call(addon, state.tooltipLabel, "SetWordWrap", true)
		Call(addon, state.tooltipLabel, "SetSpacing", 3)
	end
	local classColor = addon:GetClassColorCode(row.classFile)
	local r, g, b = Color(addon, row.classFile)
	Call(addon, state.tooltipDivider, "SetColorTexture", r, g, b, 0.6)
	local factionTexture = row.faction == "Alliance" and "Interface\\TargetingFrame\\UI-PVP-Alliance"
		or row.faction == "Horde" and "Interface\\TargetingFrame\\UI-PVP-Horde"
	if factionTexture then
		Call(addon, state.tooltipFaction, "SetTexture", factionTexture)
		Call(addon, state.tooltipFaction, "Show")
	else
		Call(addon, state.tooltipFaction, "Hide")
	end
	Call(addon, state.tooltipTitle, "SetWidth", factionTexture and 246 or 272)
	Call(addon, state.tooltipTitle, "SetText", classColor .. Text(addon, row.name) .. "|r")
	local text = string.format(L("Level %s %s %s"),
		Number(addon, row.level) and tostring(row.level) or L("Unknown"),
		Text(addon, row.race),
		classColor .. Text(addon, row.className, Text(addon, row.classFile)) .. "|r")
	if addon:SupportsWarMode() == true and type(row.warMode) == "boolean" then
		text = text .. L("\nWar Mode: ") .. (row.warMode and L("On") or L("Off"))
	end
	if addon:IsPlayerLookingForQuestPartners(row.name) then
		text = text .. "\n" .. L("\n|cff40ff40Looking for Questing Partners|r"):gsub("|cff40ff40", "|cffffd200")
		local questID, sourceTitle = addon:GetPlayerPartnerQuestID(row.name)
		if questID then
			text = text .. "|cffffd200" .. L("\nTracked quest: ") .. Text(addon, addon:GetLocalizedQuestTitle(questID) or sourceTitle or addon:GetQuestTitle(questID)) .. "|r"
		end
	end
	local now = addon.API and addon.API.GetTime and Number(addon, addon.API.GetTime())
	local receivedAt = Number(addon, row.receivedAt)
	if now and receivedAt and now >= receivedAt + 30 then
		text = text .. "\n|cff909090" .. L("\nLast update: ") .. math.floor(now - receivedAt) .. L(" seconds ago") .. "|r"
	end
	text = text .. "\n\n|cff909090" .. L("QT Version") .. ": " .. Text(addon, addon:GetPlayerAddonVersion(row.name)) .. "|r"
	Call(addon, state.tooltipLabel, "SetText", text)
	local height = Positive(addon, Call(addon, state.tooltipLabel, "GetStringHeight"))
	local titleHeight = Positive(addon, Call(addon, state.tooltipTitle, "GetStringHeight"))
	if not height or not titleHeight then
		HideTooltip(addon, state)
		return
	end
	Call(addon, tooltip, "SetSize", 300, titleHeight + height + 46)
	Call(addon, tooltip, "ClearAllPoints")
	if pin.chatLink then
		local x, y = addon:GetChatLogTooltipCursorPosition(parent)
		if not x or not y then HideTooltip(addon, state); return end
		Call(addon, tooltip, "SetPoint", "BOTTOMLEFT", parent, "BOTTOMLEFT", x + 12, y + 12)
	else
		Call(addon, tooltip, "SetPoint", "BOTTOMLEFT", pin.frame, "TOPRIGHT", 6, 6)
	end
	Call(addon, tooltip, "Show")
	state.pending[tooltip] = nil
	state.hovered = pin
end

-- The same owned tooltip renderer serves dots and QT speaker links. Keep their
-- hover state separate so refreshing map pins cannot dismiss a chat tooltip.
function QuestTogether:GetChatLogTooltipCursorPosition(parent)
	local x, y = Native(self, GetCursorPosition)
	x, y = Number(self, x), Number(self, y)
	local scale = Positive(self, Method(self, parent, "GetEffectiveScale"))
	if x and y and scale then return x / scale, y / scale end
end

function QuestTogether:GetChatLogPlayerTooltipRow(name)
	if self:IsSelfSender(name) and not self:IsRuntimeRestricted() then
		local ok, row = pcall(self.ReadLocalPlayerLocation, self)
		if ok and type(row) == "table" then
			row.name = name
			return row
		end
		return { name = name }
	end
	local state = rawget(self, "playerLocationState")
	local row = state and state.peers and state.peers[name]
	return row or { name = name }
end

function QuestTogether:HideChatLogPlayerTooltip()
	local state = rawget(self, "chatLogPlayerTooltipState")
	if state then HideTooltip(self, state) end
end

function QuestTogether:UpdateChatLogPlayerTooltip()
	local state = rawget(self, "chatLogPlayerTooltipState")
	if not state then return end
	RetryCleanup(self, state)
	local pin = state.hovered
	if not pin then return end
	if not self.isEnabled or self:IsRuntimeRestricted() or self:IsIgnoredPlayerName(pin.name)
		or Method(self, pin.frame, "IsShown") ~= true then
		self:HideChatLogPlayerTooltip()
		return
	end
	local row = self:GetChatLogPlayerTooltipRow(pin.name)
	if not pcall(Tooltip, self, state, pin, row) then self:HideChatLogPlayerTooltip() end
end

function QuestTogether:ShowChatLogPlayerTooltip(frame, link)
	self:HideChatLogPlayerTooltip()
	if not self.isEnabled or self:IsRuntimeRestricted() or not self:CanAccessForeignFrame(frame, true) then return false end
	link = self:SafeTrimString(link, "")
	local kind, name = link:match("^([^:]+):(.+)$")
	if kind ~= self.chatLogLinkType then return false end
	name = self:NormalizeMemberName(name)
	if not name or self:IsIgnoredPlayerName(name) then return false end
	local state = rawget(self, "chatLogPlayerTooltipState") or { pending = {} }
	self.chatLogPlayerTooltipState = state
	state.hovered = { frame = frame, name = name, chatLink = true }
	self:UpdateChatLogPlayerTooltip()
	return state.hovered ~= nil
end

-- Public event callbacks avoid replacing chat scripts or writing onto chat frames.
function QuestTogether:RegisterChatLogHoverCallbacks(enter, leave)
	if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then return false end
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", enter, self)
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", leave, self)
	return true
end

function QuestTogether:InitializeChatLogPlayerTooltips()
	if rawget(self, "chatLogHoverCallbacksInstalled") then return end
	self.chatLogHoverCallbacksInstalled = self:RegisterChatLogHoverCallbacks(function(_, frame, link)
		self:ShowChatLogPlayerTooltip(frame, link)
	end, function()
		self:HideChatLogPlayerTooltip()
	end)
end

local function CreatePin(addon, state, surface)
	local pin = { frame = New(addon, "Button", surface.frame), surface = surface.name }
	Call(addon, pin.frame, "Hide")
	Call(addon, pin.frame, "SetSize", DOT_SIZE, DOT_SIZE)
	Call(addon, pin.frame, "RegisterForClicks", "LeftButtonUp", "RightButtonUp")
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
	Call(addon, pin.frame, "SetScript", "OnClick", function(_, button)
		if button ~= "LeftButton" and button ~= "RightButton" then
			return
		end
		local ok, row = pcall(FreshRow, addon, pin)
		HideTooltip(addon, state)
		if ok and row then
			pcall(addon.OpenLocationPinPlayerMenu, addon, pin.frame, row.name)
		end
	end)
	Call(addon, pin.frame, "SetScript", "OnEnter", function()
		local ok, row = pcall(FreshRow, addon, pin)
		if ok and row then
			if not pcall(Tooltip, addon, state, pin, row) then
				HideTooltip(addon, state)
			end
		end
	end)
	Call(addon, pin.frame, "SetScript", "OnLeave", function()
		if state.hovered == pin then
			HideTooltip(addon, state)
		end
	end)
	return pin
end

local function RefreshSurface(addon, state, name, rows)
	local surface = state.surfaces[name]
	if #rows == 0 then
		HideSurface(addon, state, surface)
		return false
	end
	local geometry = addon:GetLocationPinSurface(name)
	if not geometry then
		HideSurface(addon, state, surface)
		return false
	end
	if not surface then
		surface = { name = name, frame = New(addon, "Frame", geometry.parent), pins = {} }
		state.surfaces[name] = surface
		Call(addon, surface.frame, "Hide")
		Call(addon, surface.frame, "EnableMouse", false)
		Call(addon, surface.frame, "SetClipsChildren", true)
	end
	if surface.parent ~= geometry.parent then
		HideSurface(addon, state, surface)
		Call(addon, surface.frame, "SetParent", geometry.parent)
		Call(addon, surface.frame, "ClearAllPoints")
		Call(addon, surface.frame, "SetAllPoints", geometry.parent)
		surface.parent = geometry.parent
	end
	local parentLevel = Number(addon, Method(addon, geometry.parent, "GetFrameLevel"))
	if not parentLevel then
		HideSurface(addon, state, surface)
		return false
	end
	Call(addon, surface.frame, "SetFrameLevel", parentLevel + 50)
	if #rows > MAX_PINS then
		local origin = name == "minimap" and geometry or addon:GetPlayerLocationPriorityOrigin()
		rows = addon:PrioritizePlayerLocationRows(rows, origin)
	end
	local count = 0
	-- Off-map peers do not consume the visible pin budget. Bound projection
	-- work separately to the model's maximum number of candidate rows.
	for index = 1, math.min(MAX_LOCATION_ROWS, #rows) do
		if count >= MAX_PINS then
			break
		end
		local row = rows[index]
		local x, y = addon:ProjectPlayerLocationPin(name, row, geometry)
		if x and y and type(row.name) == "string" and row.name ~= "" then
			count = count + 1
			local pin = surface.pins[count]
			if not pin then
				pin = CreatePin(addon, state, surface)
				surface.pins[count] = pin
			end
			if state.hovered == pin and pin.name ~= row.name then
				HideTooltip(addon, state)
			end
			pin.name, pin.parent, pin.mapID = row.name, geometry.parent, geometry.mapID
			local r, g, b = Color(addon, row.classFile)
			Call(addon, pin.texture, "SetColorTexture", r, g, b, 1)
			local size = PinSize(addon, row.name)
			if pin.size ~= size then
				local looking = size == PARTNER_DOT_SIZE
				Call(addon, pin.border, "SetColorTexture", 0, 0, 0, looking and 0 or 1)
				for _, glow in ipairs(pin.glow) do
					Call(addon, glow, looking and "Show" or "Hide")
				end
				Call(addon, pin.frame, "SetSize", size, size)
				pin.size = size
			end
			Call(addon, pin.frame, "ClearAllPoints")
			Call(addon, pin.frame, "SetPoint", "CENTER", surface.frame, "TOPLEFT", x, -y)
			Call(addon, pin.frame, "Show")
			state.pending[pin.frame] = nil
		end
	end
	for index = count + 1, #surface.pins do
		local pin = surface.pins[index]
		pin.name = nil
		Hide(addon, state, pin.frame)
		if state.hovered == pin then
			HideTooltip(addon, state)
		end
	end
	if count == 0 then
		HideSurface(addon, state, surface)
		return false
	end
	Call(addon, surface.frame, "Show")
	state.pending[surface.frame] = nil
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
	-- Most updates have no visible peers. Avoid creating UI or querying native
	-- map geometry until the model has something this surface may display.
	if #rows.map == 0 and #rows.minimap == 0 then
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
	return visible
end
