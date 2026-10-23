local QT = _G.QuestTogether
local L = QT.Translate
local function Guard(a, frame) return a:CanMutateOwnedUI(frame) end
local function Call(a, frame, method, ...) return a:CallOwnedUI(frame, method, ...) end
local function New(a, kind, parent) return a:CreateOwnedUIFrame(a.CreateLocationPinFrame, kind, parent) end
local function Hide(a, frame) a:HideOwnedUI(frame) end
local UpdateFocus
local function HideSurface(a, s, surface)
	if not surface then
		return
	end
	a:SetMapOverlayFocus(surface, nil, nil)
	for _, pin in ipairs(surface.pins) do
		pin.mapAnchor = nil
		pin.names = {}
		if s.hovered == pin then
			s.hovered = nil
			Hide(a, s.tooltip)
		end
		Hide(a, pin.frame)
	end
	Hide(a, surface.frame)
end
function QT:HidePartyWaypointPins()
	local s = rawget(self, "partyWaypointPinState")
	if not s then
		return
	end
	s.hovered = nil
	Hide(self, s.tooltip)
	for _, surface in pairs(s.surfaces) do
		HideSurface(self, s, surface)
	end
end
local function Color(a, name)
	return a:GetClassColorCode(a:GetGroupedSenderClassFile(name)) or "|cffffffff"
end

local function Current(a, s, pin)
	if not a.isEnabled or a:IsRuntimeRestricted() or not a:IsQuestTogetherMapDataShown(pin.surface)
		or not Guard(a, pin.frame) or Call(a, pin.frame, "IsVisible") ~= true then return false end
	local surface = s.surfaces[pin.surface]
	local geometry = a:GetLocationPinSurface(pin.surface)
	if not surface or not geometry or geometry.parent ~= pin.parent or geometry.mapID ~= pin.mapID then return false end
	if s.hovered == pin and (s.hoverGeneration ~= pin.presentationGeneration
		or (pin.surface == "map" and s.hoverMapGeneration ~= surface.geometryGeneration)) then return false end
	local peer = pin.name and a:GetPartyNavigationPeer(pin.name)
	local source = pin.source
	return peer ~= nil and source ~= nil and peer.mapID == source.mapID and peer.x == source.x and peer.y == source.y
end

UpdateFocus = function(a, s)
	local surface, pin = s.surfaces.map, s.hovered
	if not surface then return end
	if not pin or pin.surface ~= "map" then a:SetMapOverlayFocus(surface, nil, nil); return end
	local geometry = a:GetLocationPinSurface("map")
	local focus
	if geometry and pin and pin.surface == "map" and Current(a, s, pin) then
		local names, generation = {}, pin.presentationGeneration
		for _, name in ipairs(pin.names) do names[name] = true end
		focus = { kind = "hover", key = "waypoint:" .. pin.signature .. ":" .. tostring(generation), pins = {},
			isCurrent = function()
				return s.hovered == pin and pin.presentationGeneration == generation and Current(a, s, pin)
			end }
		for _, candidate in ipairs(surface.pins) do
			if names[candidate.name] then focus.pins[candidate.frame] = true end
		end
	end
	a:SetMapOverlayFocus(surface, geometry, focus)
end

local function Tooltip(a, s, pin)
	if not Current(a, s, pin) then Hide(a, s.tooltip); return false end
	local lines = {}
	for _, name in ipairs(pin.names) do
		local p = a:GetPartyNavigationPeer(name)
		if p and p.mapID > 0 then
			local ok, info = pcall(a.API.GetMapInfo, p.mapID)
			local zone = ok and a:CanAccessTable(info) and a:SafeTrimString(info.name, "") or ""
			lines[#lines + 1] = Color(a, name) .. name:gsub("|", "") .. "|r"
			lines[#lines + 1] = string.format(L("%s · %.1f, %.1f"), zone, p.x * 100, p.y * 100)
		end
	end
	if #lines == 0 then
		Hide(a, s.tooltip)
		return
	end
	if not s.tooltip then
		local tip = New(a, "Frame", a:GetLocationPinTooltipParent())
		s.tooltip = tip
		Call(a, tip, "Hide")
		Call(a, tip, "SetFrameStrata", "TOOLTIP")
		Call(a, tip, "SetClampedToScreen", true)
		local bg = Call(a, tip, "CreateTexture", nil, "BACKGROUND")
		Call(a, bg, "SetAllPoints")
		Call(a, bg, "SetColorTexture", 0.03, 0.04, 0.05, 0.96)
		s.label = Call(a, tip, "CreateFontString", nil, "OVERLAY", "GameFontHighlight")
		Call(a, s.label, "SetPoint", "TOPLEFT", 12, -10)
		Call(a, s.label, "SetWidth", 260)
		Call(a, s.label, "SetJustifyH", "LEFT")
	end
	Call(a, s.label, "SetText", table.concat(lines, "\n"))
	local height = a:SafeToNumber(Call(a, s.label, "GetStringHeight"))
	if not height then
		Hide(a, s.tooltip)
		return
	end
	Call(a, s.tooltip, "SetSize", 284, height + 20)
	Call(a, s.tooltip, "ClearAllPoints")
	Call(a, s.tooltip, "SetPoint", "BOTTOMLEFT", pin.frame, "TOPRIGHT", 6, 4)
	Call(a, s.tooltip, "Show")
	return true
end
local function CreatePin(a, s, surface)
	local pin = { frame = New(a, "Button", surface.frame), names = {}, surface = surface.name }
	Call(a, pin.frame, "SetSize", 22, 26)
	pin.texture = Call(a, pin.frame, "CreateTexture", nil, "ARTWORK")
	Call(a, pin.texture, "SetAllPoints")
	Call(a, pin.texture, "SetTexture", "Interface\\AddOns\\QuestTogether\\Media\\PartyWaypoint")
	Call(a, pin.frame, "SetScript", "OnEnter", function()
		if Current(a, s, pin) then
			s.hovered = pin
			s.hoverGeneration, s.hoverMapGeneration = pin.presentationGeneration, surface.geometryGeneration
			local ok, shown = pcall(Tooltip, a, s, pin)
			if not ok or not shown then s.hovered = nil; Hide(a, s.tooltip) end
			UpdateFocus(a, s)
		end
	end)
	Call(a, pin.frame, "SetScript", "OnLeave", function()
		if s.hovered == pin then
			s.hovered = nil
			Hide(a, s.tooltip)
			UpdateFocus(a, s)
		end
	end)
	Call(a, pin.frame, "SetScript", "OnClick", function()
		if not Guard(a, pin.frame) or not a:IsQuestTogetherMapDataShown(pin.surface) then
			return
		end
		local names = {}
		for i, name in ipairs(pin.names) do
			names[i] = name
		end
		a:CreatePartyQuestFilterMenu(pin.frame, function(_, root)
			if a:IsRuntimeRestricted() or not a:IsQuestTogetherMapDataShown(pin.surface) then
				return
			end
			for _, name in ipairs(names) do
				local p = a:GetPartyNavigationPeer(name)
				if p and p.mapID > 0 then
					root:CreateTitle(Color(a, name) .. name .. "|r")
					root:CreateButton(L("Navigate here"), function()
						if a:IsQuestTogetherMapDataShown(pin.surface) then a:NavigateToPartyWaypoint(name) end
					end)
				end
			end
		end)
	end)
	return pin
end
local function Surface(a, s, name, rows)
	local surface = s.surfaces[name]
	if not a:IsQuestTogetherMapDataShown(name) then HideSurface(a, s, surface); return end
	local g = #rows > 0 and a:GetLocationPinSurface(name)
	if not g then
		HideSurface(a, s, surface)
		return
	end
	surface = a:AcquireMapOverlaySurface(s, name, g, 55, function(old) HideSurface(a, s, old) end)
	if not surface then return end
	if name == "map" and not surface.refreshMapGeometry then
		surface.canShowMapGeometry = function() return a:GetOption("showPartyWaypoints") == true end
		surface.refreshMapGeometry = function() a:RefreshPartyWaypointPins("map") end
		surface.hideMapGeometry = function() HideSurface(a, s, surface) end
		surface.invalidateMapGeometry = function()
			if s.hovered and s.hovered.surface == "map" then s.hovered = nil; Hide(a, s.tooltip) end
			if surface.mapFocus then a:SetMapOverlayFocus(surface, nil, nil) end
		end
	end
	local placed = {}
	for _, row in ipairs(rows) do
		local x, y = a:ProjectPlayerLocationPin(name, row, g, 26)
		if x and y then
			placed[#placed + 1] = { name = row.name, x = x, y = y, source = { mapID = row.mapID, x = row.x, y = row.y } }
		end
	end
	for index, row in ipairs(placed) do
		local pin = a:AcquireMapOverlayPin(surface, index, function(host) return CreatePin(a, s, host) end)
		pin.names = {}
		for _, other in ipairs(placed) do
			if math.abs(other.x - row.x) <= 22 and math.abs(other.y - row.y) <= 26 then
				pin.names[#pin.names + 1] = other.name
			end
		end
		local signature = row.name .. ":" .. row.source.mapID .. ":" .. row.source.x .. ":" .. row.source.y
			.. ":" .. table.concat(pin.names, "\n")
		if pin.signature ~= signature then pin.presentationGeneration = (pin.presentationGeneration or 0) + 1 end
		pin.name, pin.source, pin.signature = row.name, row.source, signature
		pin.parent, pin.mapID = g.parent, g.mapID
		pin.mapLevelOffset = 1
		if surface.baseLevel then Call(a, pin.frame, "SetFrameLevel", surface.baseLevel + 1) end
		local color = Color(a, row.name)
		local r, green, b = color:match("^|c%x%x(%x%x)(%x%x)(%x%x)$")
		Call(
			a,
			pin.texture,
			"SetVertexColor",
			r and tonumber(r, 16) / 255 or 1,
			green and tonumber(green, 16) / 255 or 1,
			b and tonumber(b, 16) / 255 or 1,
			1
		)
		Call(a, pin.frame, "ClearAllPoints")
		Call(a, pin.frame, "SetPoint", "CENTER", surface.frame, "TOPLEFT", row.x, -row.y)
		a:SetMapOverlayPinGeometry(pin, g, row.x, row.y, 26)
		Call(a, pin.frame, "Show")
	end
	a:ReleaseMapOverlayPins(surface, #placed, function(pin)
		pin.names = {}
		pin.name, pin.source = nil, nil
		if s.hovered == pin then s.hovered = nil; Hide(a, s.tooltip) end
	end)
	Call(a, surface.frame, #placed > 0 and "Show" or "Hide")
end
function QT:RefreshPartyWaypointPins(onlySurface)
	local mapOnly = onlySurface == "map"
	if not self.isEnabled or self:IsRuntimeRestricted() then
		if mapOnly then
			local s = rawget(self, "partyWaypointPinState")
			if s then HideSurface(self, s, s.surfaces.map) end
		else self:HidePartyWaypointPins() end
		return
	end
	local rows = self:GetPartyWaypointRows()
	local s = rawget(self, "partyWaypointPinState")
	if not s and #rows == 0 then
		return
	end
	if not s then
		s = { surfaces = {} }
		self.partyWaypointPinState = s
	end
	for _, name in ipairs(mapOnly and { "map" } or { "map", "minimap" }) do
		local ok = pcall(Surface, self, s, name, rows)
		if not ok and s.surfaces[name] then
			HideSurface(self, s, s.surfaces[name])
		end
	end
	if s.hovered and (not mapOnly or s.hovered.surface == "map") then
		local ok, shown = pcall(Tooltip, self, s, s.hovered)
		if not ok or not shown then s.hovered = nil; Hide(self, s.tooltip) end
	end
	UpdateFocus(self, s)
end
