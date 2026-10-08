-- Own surface hosts and recycled markers. Projection, identity, interaction and
-- artwork stay with each overlay feature; this module never reads player data.
local QT = _G.QuestTogether

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
