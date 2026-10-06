local QT = _G.QuestTogether
local L = QT.Translate
local Lib = QT.LibChev
local function Guard(a, frame)
	return not a:IsRuntimeRestricted() and Lib.CanMutateOwnedRegion(frame)
end
local function Call(a, frame, method, ...)
	if not Guard(a, frame) then
		error("party waypoint region unavailable", 0)
	end
	return frame[method](frame, ...)
end
local function New(a, kind, parent)
	if a:IsRuntimeRestricted() or not a:CanAccessForeignFrame(parent) then
		error("party waypoint parent unavailable", 0)
	end
	local f = a:CreateLocationPinFrame(kind, nil, parent)
	if not Guard(a, f) then
		error("party waypoint frame unavailable", 0)
	end
	return f
end
local function Hide(f)
	if Lib.CanMutateOwnedRegion(f) then
		f:Hide()
	end
end
local function HideSurface(s, surface)
	if not surface then
		return
	end
	for _, pin in ipairs(surface.pins) do
		pin.names = {}
		if s.hovered == pin then
			s.hovered = nil
			Hide(s.tooltip)
		end
		Hide(pin.frame)
	end
	Hide(surface.frame)
end
function QT:HidePartyWaypointPins()
	local s = rawget(self, "partyWaypointPinState")
	if not s then
		return
	end
	s.hovered = nil
	Hide(s.tooltip)
	for _, surface in pairs(s.surfaces) do
		HideSurface(s, surface)
	end
end
local function Color(a, name)
	return a:GetClassColorCode(a:GetGroupedSenderClassFile(name)) or "|cffffffff"
end
local function Tooltip(a, s, pin)
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
		Hide(s.tooltip)
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
		Hide(s.tooltip)
		return
	end
	Call(a, s.tooltip, "SetSize", 284, height + 20)
	Call(a, s.tooltip, "ClearAllPoints")
	Call(a, s.tooltip, "SetPoint", "BOTTOMLEFT", pin.frame, "TOPRIGHT", 6, 4)
	Call(a, s.tooltip, "Show")
end
local function CreatePin(a, s, surface)
	local pin = { frame = New(a, "Button", surface.frame), names = {} }
	Call(a, pin.frame, "SetSize", 22, 26)
	pin.texture = Call(a, pin.frame, "CreateTexture", nil, "ARTWORK")
	Call(a, pin.texture, "SetAllPoints")
	Call(a, pin.texture, "SetTexture", "Interface\\AddOns\\QuestTogether\\Media\\PartyWaypoint")
	Call(a, pin.frame, "SetScript", "OnEnter", function()
		if Guard(a, pin.frame) then
			s.hovered = pin
			pcall(Tooltip, a, s, pin)
		end
	end)
	Call(a, pin.frame, "SetScript", "OnLeave", function()
		if s.hovered == pin then
			s.hovered = nil
			Hide(s.tooltip)
		end
	end)
	Call(a, pin.frame, "SetScript", "OnClick", function()
		if not Guard(a, pin.frame) then
			return
		end
		local names = {}
		for i, name in ipairs(pin.names) do
			names[i] = name
		end
		a:CreatePartyQuestFilterMenu(pin.frame, function(_, root)
			if a:IsRuntimeRestricted() then
				return
			end
			for _, name in ipairs(names) do
				local p = a:GetPartyNavigationPeer(name)
				if p and p.mapID > 0 then
					root:CreateTitle(Color(a, name) .. name .. "|r")
					root:CreateButton(L("Navigate here"), function()
						a:NavigateToPartyWaypoint(name)
					end)
				end
			end
		end)
	end)
	return pin
end
local function Surface(a, s, name, rows)
	local surface = s.surfaces[name]
	local g = #rows > 0 and a:GetLocationPinSurface(name)
	if not g then
		HideSurface(s, surface)
		return
	end
	if not surface then
		surface = { frame = New(a, "Frame", g.parent), pins = {} }
		s.surfaces[name] = surface
		Call(a, surface.frame, "EnableMouse", false)
		Call(a, surface.frame, "SetClipsChildren", true)
	end
	if surface.parent ~= g.parent then
		Call(a, surface.frame, "SetParent", g.parent)
		Call(a, surface.frame, "ClearAllPoints")
		Call(a, surface.frame, "SetAllPoints", g.parent)
		surface.parent = g.parent
	end
	local getter = a:GetAccessibleFrameMember(g.parent, "GetFrameLevel")
	local ok, level
	if type(getter) == "function" then
		ok, level = pcall(getter, g.parent)
	end
	level = ok and a:SafeToNumber(level)
	if not level then
		HideSurface(s, surface)
		return
	end
	Call(a, surface.frame, "SetFrameLevel", level + 55)
	local placed = {}
	for _, row in ipairs(rows) do
		local x, y = a:ProjectPlayerLocationPin(name, row, g, 26)
		if x and y then
			placed[#placed + 1] = { name = row.name, x = x, y = y }
		end
	end
	for index, row in ipairs(placed) do
		local pin = surface.pins[index]
		if not pin then
			pin = CreatePin(a, s, surface)
			surface.pins[index] = pin
		end
		pin.names = {}
		for _, other in ipairs(placed) do
			if math.abs(other.x - row.x) <= 22 and math.abs(other.y - row.y) <= 26 then
				pin.names[#pin.names + 1] = other.name
			end
		end
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
		Call(a, pin.frame, "Show")
	end
	for i = #placed + 1, #surface.pins do
		surface.pins[i].names = {}
		Hide(surface.pins[i].frame)
	end
	Call(a, surface.frame, #placed > 0 and "Show" or "Hide")
end
function QT:RefreshPartyWaypointPins()
	if not self.isEnabled or self:IsRuntimeRestricted() then
		self:HidePartyWaypointPins()
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
	for _, name in ipairs({ "map", "minimap" }) do
		local ok = pcall(Surface, self, s, name, rows)
		if not ok and s.surfaces[name] then
			HideSurface(s, s.surfaces[name])
		end
	end
	if
		s.hovered
		and (not Guard(self, s.hovered.frame) or #s.hovered.names == 0 or not pcall(Tooltip, self, s, s.hovered))
	then
		s.hovered = nil
		Hide(s.tooltip)
	end
end
