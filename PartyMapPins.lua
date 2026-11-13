-- World-map group artwork only. Native unit tokens position these markers, so
-- neither exposed coordinates nor another party member running QT are required.
-- This is deliberately separate from public location observations and minimap
-- pins: it cannot publish a location or establish QT/VIP identity.
local QT = _G.QuestTogether
local MEDIA = "Interface\\AddOns\\QuestTogether\\Media\\"

local function Call(a, frame, method, ...) return a:CallOwnedUI(frame, method, ...) end
local function ClearHover(a, state)
	if state then a:HidePlayerTooltipPresentation(state.tip) end
end

function QT:GetPartyMapMarkerStyle(row)
	local color = self:SafeTrimString(self:GetClassColorCode(row.classFile), "")
	local r, g, b = color:match("^|c%x%x(%x%x)(%x%x)(%x%x)$")
	r, g, b = r and tonumber(r, 16) / 255 or 1, g and tonumber(g, 16) / 255 or 1, b and tonumber(b, 16) / 255 or 1
	local developer = self:IsVerifiedDeveloper(row.name)
	local vip = not developer and self:IsVerifiedVIP(row.name)
	return developer and MEDIA .. "DeveloperGear" or vip and MEDIA .. "VIPStar" or "WhiteCircle-RaidBlips",
		(developer or vip) and 18 or 12, r, g, b
end

function QT:HidePartyMapPins()
	local state = rawget(self, "partyMapPinState")
	if not state then return end
	if state.retiring then return end
	ClearHover(self, state)
	-- The native adapter accepts restoration while restricted through the
	-- audited primitive-only secure delegate. No native layout is called here.
	local context = state.context
	state.signature, state.rows, state.anchor = nil, nil, nil
	if not state.frame then return end
	state.retiring = true
	-- Reuse the shared cleanup lifetime, including after QT is disabled. Keep
	-- the restoration handle across a forbidden native frame or partial failure.
	self:QueueOwnedUICleanup(state.frame, function(frame)
		local restored = not context or self:SetPartyMapNativeVisibility(context, context.showParty, context.showRaid)
		-- If native restoration fails, retire stale identity artwork anyway.
		-- Keep the restoration handle; a failed handoff must not revive a VIP
		-- texture on a recycled party token or leave its tooltip actionable.
		frame:Hide()
		if not restored then return false end
		if state.context == context then state.context = nil end
		state.retiring = nil
		return true
	end)
end

local function Fail(a, state)
	a:HidePartyMapPins()
	if state.failed then return end
	state.failed = true
	a:RecordDiagnosticError("party_map", "Party marker replacement stopped; native markers restored where available. Reload to retry.")
end

local function Eligible(a)
	return a.isEnabled and not a.isLoggingOut and not a:IsRuntimeRestricted()
		and a:GetOption("showPlayerLocations") == true and a:IsQuestTogetherMapDataShown("map")
end

function QT:RetireUnavailablePartyMapPins()
	local state = rawget(self, "partyMapPinState")
	if state and state.context and not state.retiring and
		(not Eligible(self) or not self:IsPartyMapNativeContextCurrent(state.context)) then self:HidePartyMapPins() end
end

local function Refresh(a)
	local state = rawget(a, "partyMapPinState")
	if not Eligible(a) or (state and state.failed) then a:HidePartyMapPins(); return false end
	if state and state.retiring then return false end
	-- Do not sample forty raid identities while the world map is closed.
	local context = a:GetPartyMapNativeContext()
	local rows = context and a:GetPartyMapRoster()
	if not rows or #rows == 0 then context = nil end
	if state and state.context and context and state.context.pin == context.pin then
		-- A native map filter may have changed since takeover. Restore its latest
		-- policy instead of reviving categories the player has just hidden.
		state.context = context
	end
	if not context or (not context.showParty and not context.showRaid) then a:HidePartyMapPins(); return false end
	if state and state.context and (state.context.pin ~= context.pin or state.parent ~= context.parent) then
		a:HidePartyMapPins()
		if state.retiring then return false end
	end
	if not state then
		state = { tip = {} }
		a.partyMapPinState = state
	end
	if not state.frame then
		state.frame = a:CreateOwnedUIFrame(a.CreateLocationPinFrame, "UnitPositionFrame", context.parent)
		Call(a, state.frame, "Hide")
		Call(a, state.frame, "EnableMouse", false)
		Call(a, state.frame, "EnableMouseWheel", false)
		-- No Blizzard mixin, native pool, callback table or selection registration.
	end
	if state.parent ~= context.parent then
		Call(a, state.frame, "SetParent", context.parent)
		Call(a, state.frame, "ClearAllPoints")
		Call(a, state.frame, "SetAllPoints", context.parent)
		state.parent = context.parent
	end
	if state.frameLevel ~= context.frameLevel then
		Call(a, state.frame, "SetFrameLevel", math.max(1, context.frameLevel - 1))
		state.frameLevel = context.frameLevel
	end
	local signature, admitted = { tostring(context.mapID), tostring(context.canvasScale) }, {}
	for _, row in ipairs(rows) do
		local visible = row.inSubgroup and context.showParty or not row.inSubgroup and context.showRaid
		if visible then
			local texture, size, r, g, b = a:GetPartyMapMarkerStyle(row)
			admitted[#admitted + 1] = { row = row, texture = texture, size = size, r = r, g = g, b = b }
			for _, value in ipairs({ row.unit, row.name, texture, tostring(size), tostring(r), tostring(g), tostring(b) }) do
				signature[#signature + 1] = value
			end
		end
	end
	signature = table.concat(signature, "\n")
	if #admitted == 0 then a:HidePartyMapPins(); return false end
	if state.signature ~= signature then
		ClearHover(a, state)
		Call(a, state.frame, "SetUiMapID", context.mapID)
		Call(a, state.frame, "ClearUnits")
		for _, marker in ipairs(admitted) do
			local size = marker.size / context.canvasScale
			Call(a, state.frame, "AddUnit", marker.row.unit, marker.texture, size, size,
				marker.r, marker.g, marker.b, 1, 7, false)
		end
		Call(a, state.frame, "FinalizeUnits")
		state.signature = signature
	end
	state.rows = {}
	for _, marker in ipairs(admitted) do state.rows[marker.row.unit] = marker.row end
	if Call(a, state.frame, "IsShown") ~= true then Call(a, state.frame, "Show") end
	-- Assign before attempting suppression so a partial failure can restore both
	-- original categories. The local player's native arrow/ping is never changed.
	state.context = context
	if not a:SetPartyMapNativeVisibility(context, false, false) then Fail(a, state); return false end
	return true
end

function QT:RefreshPartyMapPins()
	local ok, shown = pcall(Refresh, self)
	if not ok then
		local state = rawget(self, "partyMapPinState")
		if state then Fail(self, state) end
	end
	return ok and shown == true
end

-- Mouse-over comes from the same native unit-position renderer, rather than
-- Lua coordinate estimates. Require canvas input ownership so a covering
-- character window, item tooltip, or another QT marker wins normally.
function QT:GetPartyMapMouseOverUnits(frame, context)
	if not Eligible(self) or not self:CanMutateOwnedUI(frame) then return nil end
	local ok, foci = pcall(function() return GetMouseFoci() end)
	if not ok or not self:CanAccessTable(foci) then return nil end
	local focus = foci[1]
	if not self:CanAccessValue(focus) then return nil end
	local viewport = context.surface.parent
	if focus ~= context.parent and focus ~= viewport then return nil end
	local units = { Call(self, frame, "GetMouseOverUnits") }
	if #units > 40 then return nil end
	local result = {}
	for _, unit in ipairs(units) do
		if not self:CanAccessValue(unit) or type(unit) ~= "string" then return nil end
		result[#result + 1] = unit
	end
	return result
end

function QT:GetPartyMapPresentationStatus()
	local state = rawget(self, "partyMapPinState")
	return {
		active = state ~= nil and state.context ~= nil and not state.retiring,
		restorationPending = state ~= nil and state.retiring == true,
		failed = state ~= nil and state.failed == true,
		hoverFailed = state ~= nil and state.hoverFailed == true,
	}
end

function QT:UpdatePartyMapHover()
	local state = rawget(self, "partyMapPinState")
	if not state or not state.context or state.retiring or state.hoverFailed then return end
	if not Eligible(self) then self:HidePartyMapPins(); return end
	local ok = pcall(function()
		if Call(self, state.frame, "IsVisible") ~= true then self:HidePartyMapPins(); return end
		local units = self:GetPartyMapMouseOverUnits(state.frame, state.context)
		local row
		for _, unit in ipairs(units or {}) do
			local current = state.rows and state.rows[unit]
			if current and self:IsPartyMapRowCurrent(current) and not self:IsIgnoredPlayerName(current.name)
				and (not row or current.name < row.name) then row = current end
		end
		if not row then ClearHover(self, state); return end
		local parent = self:GetPlayerTooltipPresentationParent()
		local x, y = self:GetChatLogTooltipCursorPosition(parent)
		if not x or not y then ClearHover(self, state); return end
		local anchor = state.anchor
		if not anchor or anchor.name ~= row.name or anchor.unit ~= row.unit then
			ClearHover(self, state)
			anchor = { frame = state.frame, name = row.name, unit = row.unit, surface = "map", presentationGeneration = 1 }
			local name, unit = row.name, row.unit
			anchor.isCurrent = function()
				local current = state.rows and state.rows[unit]
				return state.anchor == anchor and Eligible(self) and state.context ~= nil and current and current.name == name
					and self:IsPartyMapRowCurrent(current)
			end
			state.anchor = anchor
		end
		anchor.cursorPosition = { x = x, y = y }
		self:PresentPlayerTooltip(state.tip, anchor, row)
	end)
	if not ok then
		ClearHover(self, state)
		state.hoverFailed = true
		self:RecordDiagnosticError("party_map_hover", "Party marker tooltip stopped after an unexpected UI failure; reload to retry.")
	end
end
