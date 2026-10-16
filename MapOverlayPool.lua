-- Own surface hosts and recycled markers. Projection, identity, interaction and
-- artwork stay with each overlay feature; this module never reads player data.
local QT = _G.QuestTogether

local function FocusState(addon)
	local state = rawget(addon, "mapOverlayFocusState")
	if not state then
		state = { surfaces = {}, sequence = 0 }
		addon.mapOverlayFocusState = state
	end
	return state
end

local function SameGeometry(a, b)
	if not a or not b then return false end
	for _, key in ipairs({ "parent", "mapID", "width", "height", "canvasLeft", "canvasTop", "canvasWidth", "canvasHeight" }) do
		if a[key] ~= b[key] then return false end
	end
	return true
end

function QT:AcquireMapOverlayShade(geometry)
	local state = FocusState(self)
	if not state.shade then
		state.shade = self:CreateOwnedUIFrame(self.CreateLocationPinFrame, "Frame", geometry.parent)
		self:CallOwnedUI(state.shade, "Hide")
		self:CallOwnedUI(state.shade, "EnableMouse", false)
		self:CallOwnedUI(state.shade, "EnableMouseWheel", false)
		self:CallOwnedUI(state.shade, "SetClipsChildren", true)
		state.texture = self:CallOwnedUI(state.shade, "CreateTexture", nil, "BACKGROUND")
		self:CallOwnedUI(state.texture, "SetAllPoints", state.shade)
		self:CallOwnedUI(state.texture, "SetColorTexture", 0, 0, 0, 0.22)
	end
	if state.parent ~= geometry.parent then
		self:HideOwnedUI(state.shade)
		self:CallOwnedUI(state.shade, "SetParent", geometry.parent)
		self:CallOwnedUI(state.shade, "ClearAllPoints")
		self:CallOwnedUI(state.shade, "SetAllPoints", geometry.parent)
		state.parent = geometry.parent
	end
	return state.shade
end

local function RefreshFocus(addon, state)
	local pending
	for surface in pairs(state.surfaces) do
		if surface.mapFocus then pending = true; break end
	end
	local geometry = pending and addon.isEnabled and not addon:IsRuntimeRestricted()
		and addon:IsQuestTogetherMapDataShown("map") and addon:GetLocationPinSurface("map")
	local active
	for surface in pairs(state.surfaces) do
		local focus = surface.mapFocus
		if focus then
			local valid = geometry and SameGeometry(geometry, focus.geometry)
				and addon:CanMutateOwnedUI(surface.frame) and addon:CallOwnedUI(surface.frame, "IsVisible") == true
			if valid and focus.isCurrent then
				local ok, current = pcall(focus.isCurrent)
				valid = ok and current == true
			end
			if not valid then surface.mapFocus = nil
			elseif not active or focus.priority > active.priority
				or (focus.priority == active.priority and focus.sequence > active.sequence) then active = focus end
		end
	end
	state.active = active
	local shadeLevel
	if active then
		local getter = addon:GetAccessibleFrameMember(geometry.parent, "GetFrameLevel")
		local ok, level
		if type(getter) == "function" then ok, level = pcall(getter, geometry.parent) end
		level = ok and addon:SafeToNumber(level)
		if level then
			shadeLevel = math.max(level + 60, (addon:SafeToNumber(geometry.pinFrameLevel) or 0) + 1)
			local shade = addon:AcquireMapOverlayShade(geometry)
			addon:CallOwnedUI(shade, "SetFrameLevel", shadeLevel)
			addon:CallOwnedUI(shade, "Show")
		else state.active, active = nil, nil end
	end
	if not active then addon:HideOwnedUI(state.shade) end
	for surface in pairs(state.surfaces) do
		-- Raise the clipped host as well as its children. A high child level
		-- alone cannot keep its artwork above a sibling shade when the client
		-- renders that artwork together with its parent.
		local hostLevel = active and shadeLevel + 1 or surface.baseLevel
		if hostLevel then addon:CallOwnedUI(surface.frame, "SetFrameLevel", hostLevel) end
		for _, pin in ipairs(surface.pins) do
			if addon:CanMutateOwnedUI(pin.frame) then
				local focused = active and active.pins[pin.frame]
				local alpha = active and not focused and (active.kind == "hover" and 0.45 or 0.78) or 1
				addon:CallOwnedUI(pin.frame, "SetAlpha", (pin.baseAlpha or 1) * alpha)
				local offset = pin.mapLevelOffset or 1
				local level = hostLevel and hostLevel + offset + (focused and 8 or 0)
				if level then addon:CallOwnedUI(pin.frame, "SetFrameLevel", level) end
				for _, region in ipairs(pin.focusDecorations or {}) do
					addon:CallOwnedUI(region, "SetAlpha", active and not focused and 0.45 or 1)
				end
			end
		end
	end
	return active ~= nil
end

function QT:RefreshMapOverlayFocus()
	local state = rawget(self, "mapOverlayFocusState")
	if not state or state.refreshing then return false end
	state.refreshing = true
	local ok, active = pcall(RefreshFocus, self, state)
	state.refreshing = nil
	if not ok then state.active = nil; self:HideOwnedUI(state.shade) end
	return ok and active == true
end

-- Features describe only current owned frames. The pool owns priority, shared
-- darkening and frame levels; it never needs player, party or waypoint data.
function QT:SetMapOverlayFocus(surface, geometry, focus)
	if not surface or surface.name ~= "map" then return end
	if not focus and not surface.mapFocus then
		-- Reapply another feature's hover, or finish restoring a shade/host
		-- whose cleanup was blocked while its native parent was forbidden.
		local state = rawget(self, "mapOverlayFocusState")
		if state and (state.active or state.shade) then self:RefreshMapOverlayFocus() end
		return
	end
	local state = FocusState(self)
	state.surfaces[surface] = true
	local previous = surface.mapFocus
	if focus then
		if previous and previous.kind == focus.kind and previous.key == focus.key then
			focus.sequence = previous.sequence
		else state.sequence = state.sequence + 1; focus.sequence = state.sequence end
		focus.priority = focus.kind == "hover" and 2 or 1
		focus.geometry = {}
		for key, value in pairs(geometry) do focus.geometry[key] = value end
	end
	surface.mapFocus = focus
	self:RefreshMapOverlayFocus()
end

function QT:AcquireMapOverlaySurface(state, name, geometry, levelOffset, retire)
	local surface = state.surfaces[name]
	if not surface then
		surface = {
			name = name,
			frame = self:CreateOwnedUIFrame(self.CreateLocationPinFrame, "Frame", geometry.parent),
			pins = {},
		}
		state.surfaces[name] = surface
		self:CallOwnedUI(surface.frame, "Hide")
		self:CallOwnedUI(surface.frame, "EnableMouse", false)
		self:CallOwnedUI(surface.frame, "SetClipsChildren", true)
	end
	if surface.parent ~= geometry.parent then
		if retire then
			retire(surface)
		end
		self:CallOwnedUI(surface.frame, "SetParent", geometry.parent)
		self:CallOwnedUI(surface.frame, "ClearAllPoints")
		self:CallOwnedUI(surface.frame, "SetAllPoints", geometry.parent)
		surface.parent = geometry.parent
	end
	local getter = self:GetAccessibleFrameMember(geometry.parent, "GetFrameLevel")
	local ok, level
	if type(getter) == "function" then
		ok, level = pcall(getter, geometry.parent)
	end
	level = ok and self:SafeToNumber(level)
	if not level then
		if retire then
			retire(surface)
		end
		return nil
	end
	self:CallOwnedUI(surface.frame, "SetFrameLevel", level + levelOffset)
	surface.baseLevel = level + levelOffset
	if name == "map" then
		if not SameGeometry(surface.geometry, geometry) then
			surface.geometryGeneration = (surface.geometryGeneration or 0) + 1
			surface.geometry = {}
			for key, value in pairs(geometry) do surface.geometry[key] = value end
		end
		FocusState(self).surfaces[surface] = true
	end
	return surface
end

function QT:AcquireMapOverlayPin(surface, index, create)
	local pin = surface.pins[index]
	if not pin then
		pin = create(surface)
		surface.pins[index] = pin
	end
	return pin
end

function QT:ReleaseMapOverlayPins(surface, activeCount, retire)
	for index = activeCount + 1, #surface.pins do
		local pin = surface.pins[index]
		if retire then
			retire(pin)
		end
		self:HideOwnedUI(pin.frame)
	end
end
