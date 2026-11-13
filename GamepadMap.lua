-- Read-only crosshair observation. QT markers never join Blizzard's pin click
-- list: its gamepad map click also navigates the underlying map unconditionally.
local QT = _G.QuestTogether

local function Read(addon, frame, method)
	local fn = addon:GetAccessibleFrameMember(frame, method)
	if type(fn) ~= "function" then return end
	local ok, a, b = pcall(fn, frame)
	if ok and addon:CanAccessValue(a) and addon:CanAccessValue(b) then return a, b end
end

local function Number(addon, value)
	local number = addon:SafeToNumber(value)
	if number and number == number and math.abs(number) ~= math.huge then return number end
end

function QT:InitializeGamepadMap()
	self:ResetGamepadMap()
	local state = {}
	self.gamepadMap = state
	if self.RegisterGamepadObserver then
		self:RegisterGamepadObserver(state, function(snapshot)
			if rawget(self, "gamepadMap") ~= state then return end
			state.available = snapshot.available == true
			if not state.available then self:ClearPlayerLocationGamepadHover() end
		end)
	end
end

function QT:ResetGamepadMap()
	local state = rawget(self, "gamepadMap")
	self.gamepadMap = nil
	if state and self.UnregisterGamepadObserver then self:UnregisterGamepadObserver(state) end
	if self.ClearPlayerLocationGamepadHover then self:ClearPlayerLocationGamepadHover() end
end

function QT:GetGamepadMapNativeFrames()
	return WorldMapFrame, SoftCursor
end

function QT:GetGamepadMapCursor()
	local state = rawget(self, "gamepadMap")
	if not state or not state.available or not self.IsNativeGamepadMode or not self:IsNativeGamepadMode() or not self.GetNativeGamepadFocus
		or not self.isEnabled or self.isLoggingOut or self:IsRuntimeRestricted()
		or not self:IsQuestTogetherMapDataShown("map") then return end
	local map, cursorFrame = self:GetGamepadMapNativeFrames()
	local manager, active = self:GetNativeGamepadFocus()
	if manager ~= map or (active and active ~= map) or not self:CanAccessForeignFrame(map, true)
		or Read(self, map, "IsVisible") ~= true or Read(self, map, "IsCanvasGamepadFocus") ~= true
		or not self:CanAccessForeignFrame(cursorFrame, true) or Read(self, cursorFrame, "IsVisible") ~= true then return end
	local geometry = self:GetLocationPinSurface("map")
	if not geometry then return end
	local nx, ny = Read(self, map, "GetNormalizedGamepadCursorPosition")
	nx, ny = Number(self, nx), Number(self, ny)
	if not nx or not ny then return end
	local x = geometry.canvasLeft + nx * geometry.canvasWidth
	local y = geometry.canvasTop + ny * geometry.canvasHeight
	if x < 0 or y < 0 or x > geometry.width or y > geometry.height then return end
	local left, top = Number(self, Read(self, geometry.parent, "GetLeft")), Number(self, Read(self, geometry.parent, "GetTop"))
	local parentScale = Number(self, Read(self, geometry.parent, "GetEffectiveScale"))
	local tooltipScale = Number(self, Read(self, self:GetPlayerTooltipPresentationParent(), "GetEffectiveScale"))
	if not left or not top or not parentScale or parentScale <= 0 or not tooltipScale or tooltipScale <= 0 then return end
	return { mapID = geometry.mapID, parent = geometry.parent, x = x, y = y,
		cursorX = (left + x) * parentScale / tooltipScale,
		cursorY = (top - y) * parentScale / tooltipScale, geometry = geometry,
		moving = Read(self, map, "HasGamepadCursorInput") == true }
end

function QT:GetGamepadMapMarkerKey(pin)
	if pin.cluster and type(pin.cluster.key) == "string" then return "cluster:" .. pin.cluster.key end
	if type(pin.name) == "string" then return "player:" .. pin.name end
end

function QT:FindGamepadMapMarker(cursor)
	local state = rawget(self, "locationPinState")
	local surface = state and state.surfaces and state.surfaces.map
	if not surface or surface.parent ~= cursor.parent or surface.geometryUnavailable then return end
	local chosen, bestDistance, bestKey
	local geometry = cursor.geometry
	for index = 1, math.min(#surface.pins, 128) do
		local pin = surface.pins[index]
		local anchor, key = pin.mapAnchor, self:GetGamepadMapMarkerKey(pin)
		if anchor and key and pin.mapID == cursor.mapID and pin.parent == cursor.parent
			and Read(self, pin.frame, "IsVisible") == true then
			local x = geometry.canvasLeft + anchor.x * geometry.canvasWidth
			local y = geometry.canvasTop + anchor.y * geometry.canvasHeight
			local distance = (x - cursor.x)^2 + (y - cursor.y)^2
			local radius = math.max(12, (pin.size or 12) / 2)
			if distance <= radius^2 and (not chosen or distance < bestDistance
				or (distance == bestDistance and key < bestKey)) then
				chosen, bestDistance, bestKey = pin, distance, key
			end
		end
	end
	return chosen
end

function QT:NotifyGamepadMapMouseInput(clicked)
	local state = rawget(self, "gamepadMap")
	if not state then return end
	local x, y = self:GetPlayerLocationHoverCursorPosition()
	if clicked or (x and y and state.mouseX and (x ~= state.mouseX or y ~= state.mouseY)) then
		state.mouseOwnsHover = true
		self:ClearPlayerLocationGamepadHover()
	end
end

-- Called by the existing per-frame map/hover observer, with no independent pump.
function QT:UpdateGamepadMapHover()
	local state = rawget(self, "gamepadMap")
	if not state then return end
	local cursor = self:GetGamepadMapCursor()
	if not cursor then
		state.cursor, state.mouseOwnsHover = nil, nil
		self:ClearPlayerLocationGamepadHover()
		return
	end
	local previous = state.cursor
	local moved = not previous or previous.parent ~= cursor.parent or previous.mapID ~= cursor.mapID
		or previous.cursorX ~= cursor.cursorX or previous.cursorY ~= cursor.cursorY
	local mouseX, mouseY = self:GetPlayerLocationHoverCursorPosition()
	if not previous or (moved and cursor.moving) then state.mouseOwnsHover = nil
	elseif mouseX and mouseY and state.mouseX and (mouseX ~= state.mouseX or mouseY ~= state.mouseY) then
		state.mouseOwnsHover = true
	end
	state.mouseX, state.mouseY, state.cursor = mouseX, mouseY, cursor
	if state.mouseOwnsHover then self:ClearPlayerLocationGamepadHover(); return end
	-- Preserve the reading subject while players move beneath a still crosshair.
	-- A map change, recycled subject, expiry or actual crosshair movement reselects.
	if not moved and self:IsPlayerLocationGamepadHoverCurrent() then return end
	local pins = rawget(self, "locationPinState")
	local surface = pins and pins.surfaces and pins.surfaces.map
	local generation = surface and surface.gamepadGeneration
	if not moved and state.empty and state.generation == generation then return end
	state.generation = generation
	local pin = self:FindGamepadMapMarker(cursor)
	state.empty = pin == nil
	if pin then self:PresentPlayerLocationGamepadHover(pin, cursor.cursorX, cursor.cursorY)
	else self:ClearPlayerLocationGamepadHover() end
end
