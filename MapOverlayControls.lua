-- The world-map switch owns presentation only. It never changes discovery,
-- sharing, player filters, minimap markers, or accepted peer observations.
local QT = _G.QuestTogether
local L = QT.Translate
local function Call(a, frame, method, ...) return a:CallOwnedUI(frame, method, ...) end
local function RefreshMarkers(a)
	a:RefreshPlayerLocationPins()
	a:RefreshPartyWaypointPins()
end

function QT:IsQuestTogetherMapDataShown(surface)
	return surface ~= "map" or self:GetOption("showWorldMapData") ~= false
end

function QT:ToggleQuestTogetherMapData()
	if not self.isEnabled or self:IsRuntimeRestricted() then return false end
	return self:SetOption("showWorldMapData", not self:IsQuestTogetherMapDataShown("map"))
end

function QT:HideQuestTogetherMapControl()
	local state = rawget(self, "mapDataControlState")
	if not state then return end
	local hovered = state.hovered
	state.hovered = nil
	self:HideOwnedUI(state.shade)
	self:HidePlayerTooltipPresentation(state.tip)
	self:HideOwnedUI(state.button)
	if hovered then RefreshMarkers(self) end
end

local function Current(a, state)
	if rawget(a, "mapDataControlState") ~= state or not a.isEnabled or a:IsRuntimeRestricted()
		or not a:CanMutateOwnedUI(state.button) or Call(a, state.button, "IsVisible") ~= true then return false end
	local geometry = a:GetLocationPinSurface("map")
	return geometry ~= nil and geometry.parent == state.parent
end

function QT:GetQuestTogetherMapHighlightLevel(geometry)
	local state = rawget(self, "mapDataControlState")
	if not state or not state.hovered or not geometry or state.parent ~= geometry.parent
		or not Current(self, state) then return nil end
	return state.highlightLevel
end

local function RefreshShade(a, state, geometry, level)
	if not state.hovered then a:HideOwnedUI(state.shade); return end
	if not state.shade then
		state.shade = a:CreateOwnedUIFrame(a.CreateLocationPinFrame, "Frame", state.button)
		Call(a, state.shade, "EnableMouse", false)
		Call(a, state.shade, "EnableMouseWheel", false)
		local texture = Call(a, state.shade, "CreateTexture", nil, "BACKGROUND")
		Call(a, texture, "SetAllPoints")
		Call(a, texture, "SetColorTexture", 0, 0, 0, 0.35)
	end
	Call(a, state.shade, "ClearAllPoints")
	Call(a, state.shade, "SetAllPoints", geometry.parent)
	Call(a, state.shade, "SetFrameLevel", level)
	Call(a, state.shade, "Show")
end


local function Tooltip(a, state)
	if not Current(a, state) then a:HidePlayerTooltipPresentation(state.tip); return end
	a:RenderPlayerTooltip(state.tip, state.anchor, {
		title = L("QuestTogether map data"),
		text = a:IsQuestTogetherMapDataShown("map")
			and L("Click to hide QuestTogether markers on the world map. Minimap markers and location sharing stay unchanged.")
			or L("Click to show QuestTogether markers on the world map. Minimap markers and location sharing stay unchanged."),
		color = { 1, 0.82, 0 }, members = {},
	})
end

local function Refresh(a)
	if not a.isEnabled or a:IsRuntimeRestricted() then a:HideQuestTogetherMapControl(); return false end
	local geometry = a:GetLocationPinSurface("map")
	if not geometry or geometry.width < 42 or geometry.height < 42 then
		a:HideQuestTogetherMapControl()
		return false
	end
	local getter = a:GetAccessibleFrameMember(geometry.parent, "GetFrameLevel")
	local ok, level
	if type(getter) == "function" then ok, level = pcall(getter, geometry.parent) end
	level = ok and a:SafeToNumber(level)
	if not level then a:HideQuestTogetherMapControl(); return false end
	local state = rawget(a, "mapDataControlState")
	if not state then
		state = { tip = {} }
		a.mapDataControlState = state
		local button = a:CreateOwnedUIFrame(a.CreateLocationPinFrame, "Button", geometry.parent)
		state.button, state.anchor = button, { frame = button }
		Call(a, button, "Hide")
		Call(a, button, "SetSize", 26, 26)
		Call(a, button, "RegisterForClicks", "LeftButtonUp")
		local icon = Call(a, button, "CreateTexture", nil, "ARTWORK")
		state.icon = icon
		Call(a, icon, "SetTexture", a.NAMEPLATE_PLAYER_ICON_TEXTURE)
		Call(a, icon, "SetSize", 24, 24)
		Call(a, icon, "SetPoint", "CENTER")
		Call(a, button, "SetScript", "OnClick", function(_, mouseButton)
			if mouseButton == "LeftButton" and Current(a, state) then a:ToggleQuestTogetherMapData() end
		end)
		Call(a, button, "SetScript", "OnEnter", function()
			if Current(a, state) then
				state.hovered = true
				a:RefreshQuestTogetherMapControl()
				RefreshMarkers(a)
			end
		end)
		local function Leave()
			local hovered = state.hovered
			state.hovered = nil
			a:HideOwnedUI(state.shade)
			a:HidePlayerTooltipPresentation(state.tip)
			if hovered then RefreshMarkers(a) end
		end
		Call(a, button, "SetScript", "OnLeave", Leave)
		Call(a, button, "SetScript", "OnHide", Leave)
	end
	if state.parent ~= geometry.parent then
		a:HideQuestTogetherMapControl()
		Call(a, state.button, "SetParent", geometry.parent)
		Call(a, state.button, "ClearAllPoints")
		Call(a, state.button, "SetPoint", "TOPRIGHT", geometry.parent, "TOPRIGHT", -8, -8)
		state.parent = geometry.parent
	end
	local nativeLevel = a:SafeToNumber(geometry.pinFrameLevel) or 0
	local shadeLevel = math.max(level + 60, nativeLevel + 1)
	state.highlightLevel = shadeLevel + 1
	Call(a, state.button, "SetFrameLevel", shadeLevel + 16)
	Call(a, state.icon, "SetAlpha", a:IsQuestTogetherMapDataShown("map") and 1 or 0.35)
	Call(a, state.button, "Show")
	RefreshShade(a, state, geometry, shadeLevel)
	if state.hovered then Tooltip(a, state) end
	return true
end

function QT:RefreshQuestTogetherMapControl()
	local ok, shown = pcall(Refresh, self)
	if not ok then self:HideQuestTogetherMapControl() end
	return ok and shown == true
end
