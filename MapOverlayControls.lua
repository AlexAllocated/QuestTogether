-- The world-map switch owns presentation only. It never changes discovery,
-- sharing, player filters, minimap markers, or accepted peer observations.
local QT = _G.QuestTogether
local L = QT.Translate
local function Call(a, frame, method, ...) return a:CallOwnedUI(frame, method, ...) end

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
	state.hovered = nil
	self:HidePlayerTooltipPresentation(state.tip)
	self:HideOwnedUI(state.button)
end

local function Current(a, state)
	if rawget(a, "mapDataControlState") ~= state or not a.isEnabled or a:IsRuntimeRestricted()
		or not a:CanMutateOwnedUI(state.button) or Call(a, state.button, "IsVisible") ~= true then return false end
	local geometry = a:GetLocationPinSurface("map")
	return geometry ~= nil and geometry.parent == state.parent
end

local function CreateHiddenMark(a, state)
	local marker = a:CreateOwnedUIFrame(a.CreateLocationPinFrame, "Frame", state.button)
	state.hiddenMark, state.hiddenMarkLines, state.hiddenMarkOutlines = marker, {}, {}
	Call(a, marker, "EnableMouse", false)
	Call(a, marker, "EnableMouseWheel", false)
	Call(a, marker, "SetSize", 14, 14)
	Call(a, marker, "SetPoint", "BOTTOMRIGHT", state.icon, "BOTTOMRIGHT", 2, -2)
	-- An outlined red X stays readable over the logo and any map background.
	for index = 1, 2 do
		for layer = 1, 2 do
			local line = Call(a, marker, "CreateLine", nil, layer == 1 and "BACKGROUND" or "OVERLAY")
			local parts = layer == 1 and state.hiddenMarkOutlines or state.hiddenMarkLines
			parts[index] = line
			Call(a, line, "SetColorTexture", layer == 1 and 0 or 1, layer == 1 and 0 or 0.12, layer == 1 and 0 or 0.12, 1)
			Call(a, line, "SetThickness", layer == 1 and 5 or 3)
			Call(a, line, "SetStartPoint", "BOTTOMLEFT", marker, 2, index == 1 and 2 or 12)
			Call(a, line, "SetEndPoint", "BOTTOMLEFT", marker, 12, index == 1 and 12 or 2)
		end
	end
	Call(a, marker, "Hide")
end


local function MapLegend()
	return {
		{ kind = "player", label = L("QT players (class color)") },
		{ kind = "partners", label = L("Looking for Questing Partners") },
		{ kind = "selected", label = L("Selected player") },
		{ kind = "phase", label = L("Likely different layer (experimental)") },
		{ kind = "cluster", label = L("Nearby players grouped on the map") },
		{ kind = "party", label = L("In a party"), gapBefore = 8 },
		{ kind = "partyHover", label = L("Party members and leader (on hover)") },
		{ kind = "waypoint", label = L("Shared party waypoint") },
		{ kind = "partySize", label = L("Party size in tooltips") },
		{ kind = "dimmed", label = L("Other markers dim during focus"), gapBefore = 8 },
		{ kind = "hidden", label = L("QT world-map markers hidden") },
	}
end

-- These are the live marker primitives, with illustrative state only. No peer
-- observations, developer identity, subscriptions or hover interest are changed.
local function DrawLegendSample(a, item, entry)
	if item.sampleKind == entry.kind then return end
	for _, frame in ipairs(item.sampleObjects or {}) do a:HideOwnedUI(frame) end
	item.sampleObjects = {}
	local function Remember(region)
		item.sampleObjects[#item.sampleObjects + 1] = region
		return region
	end
	local function Symbol(style, x)
		style = style or {}
		if not style.r then style.r, style.g, style.b = 0.25, 0.78, 0.92 end
		local frame = Remember(a:CreateOwnedUIFrame(a.CreateLocationPinFrame, "Frame", item.sampleFrame))
		Call(a, frame, "EnableMouse", false)
		Call(a, frame, "SetPoint", "CENTER", item.sampleFrame, "CENTER", x or 0, 0)
		local symbol = a:CreatePlayerLocationSymbol(frame)
		a:ApplyPlayerLocationSymbol(symbol, style)
		Call(a, frame, "Show")
		return symbol
	end
	local function Texture(name, x, size)
		local texture = Remember(Call(a, item.sampleFrame, "CreateTexture", nil, "ARTWORK"))
		Call(a, texture, "SetTexture", "Interface\\AddOns\\QuestTogether\\Media\\" .. name)
		Call(a, texture, "SetPoint", "CENTER", item.sampleFrame, "CENTER", x or 0, 0)
		Call(a, texture, "SetSize", size or 20, size or 20)
		return texture
	end
	local kind = entry.kind
	if kind == "player" or kind == "partners" then
		Symbol({ looking = kind == "partners" }, -14)
		Texture(kind == "partners" and "QuestTogetherPartnerIcon" or "QuestTogetherIcon", 14)
	elseif kind == "cluster" then
		Symbol({ clusterCount = 3, r = 0.16, g = 0.13, b = 0.06 })
	elseif kind == "party" then
		Call(a, Symbol().partyBadge, "Show")
	elseif kind == "partyHover" then
		local member = Symbol(nil, -14)
		local leader = Symbol({ r = 1, g = 1, b = 1 }, 14)
		Call(a, member.partyOutline, "Show")
		Call(a, leader.partyOutline, "Show")
		Call(a, leader.partyCrown, "Show")
	elseif kind == "waypoint" then
		local texture = Texture("PartyWaypoint")
		Call(a, texture, "SetSize", 22, 26)
		Call(a, texture, "SetVertexColor", 0.25, 0.78, 0.92, 1)
	elseif kind == "partySize" then
		local group = { tooltip = item.sampleFrame }
		a:LayoutPlayerTooltipPartyGroup(group, 1, item.sampleFrame, -26, 58, 26, "legend", 3, 1, 3)
		Remember(group.partyGroups[1].frame)
	elseif kind == "dimmed" then
		Symbol(nil, -14)
		Call(a, Symbol(nil, 14).frame, "SetAlpha", 0.45)
	elseif kind == "hidden" then
		local sample = { button = item.sampleFrame, icon = Texture("QuestTogetherIcon", 0, 24) }
		CreateHiddenMark(a, sample)
		Call(a, Remember(sample.hiddenMark), "Show")
	else
		Symbol({ selected = kind == "selected", phase = kind == "phase" })
	end
	item.sampleKind = entry.kind
end

local function Tooltip(a, state)
	if not Current(a, state) then a:HidePlayerTooltipPresentation(state.tip); return end
	a:RenderPlayerTooltip(state.tip, state.anchor, {
		title = L("Map legend"),
		introText = a:IsQuestTogetherMapDataShown("map") and L("Click to hide map markers.") or L("Click to show map markers."),
		text = "|cff909090" .. L("Minimap markers and location sharing stay unchanged.") .. "|r",
		legend = MapLegend(), drawLegendSample = DrawLegendSample, maxWidth = 304,
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
		CreateHiddenMark(a, state)
		Call(a, button, "SetScript", "OnClick", function(_, mouseButton)
			if mouseButton == "LeftButton" and Current(a, state) then a:ToggleQuestTogetherMapData() end
		end)
		Call(a, button, "SetScript", "OnEnter", function()
			if Current(a, state) then
				state.hovered = true
				a:RefreshQuestTogetherMapControl()
			end
		end)
		local function Leave()
			state.hovered = nil
			a:HidePlayerTooltipPresentation(state.tip)
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
	local controlLevel = math.max(level + 60, nativeLevel + 1) + 16
	Call(a, state.button, "SetFrameLevel", controlLevel)
	Call(a, state.icon, "SetAlpha", 1)
	Call(a, state.hiddenMark, "SetFrameLevel", controlLevel + 1)
	Call(a, state.hiddenMark, a:IsQuestTogetherMapDataShown("map") and "Hide" or "Show")
	Call(a, state.button, "Show")
	if state.hovered then Tooltip(a, state) end
	return true
end

function QT:RefreshQuestTogetherMapControl()
	local ok, shown = pcall(Refresh, self)
	if not ok then self:HideQuestTogetherMapControl() end
	return ok and shown == true
end
