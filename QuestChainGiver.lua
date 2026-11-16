-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
-- A view-owned location preview. Browsing never installs a user waypoint or
-- changes the followed quest; map geometry uses the existing overlay owner.
local QT = _G.QuestTogether
local function Call(a, frame, method, ...) return a:CallOwnedUI(frame, method, ...) end
local function Hide(a, state)
	if not state then return end
	state.selection = nil
	local surface = state.surfaces.map
	if surface then
		for _, pin in ipairs(surface.pins) do pin.mapAnchor = nil; a:HideOwnedUI(pin.frame) end
		a:HideOwnedUI(surface.frame)
	end
end
function QT:HideQuestChainGiver()
	local state = rawget(self, "questChainGiverState")
	if state then state.generation = state.generation + 1; Hide(self, state) end
end
function QT:RefreshQuestChainGiver()
	local state = rawget(self, "questChainGiverState")
	local selected = state and state.selection
	if not selected then return false end
	if self:IsRuntimeRestricted() or not self.isEnabled or not selected.isCurrent()
		or not self:IsQuestTogetherMapDataShown("map") then Hide(self, state); return false end
	local geometry = self:GetLocationPinSurface("map")
	if not geometry then Hide(self, state); return false end
	local surface = self:AcquireMapOverlaySurface(state, "map", geometry, 58)
	if not surface then Hide(self, state); return false end
	if not surface.refreshMapGeometry then
		surface.canShowMapGeometry = function()
			local current = state.selection
			return current ~= nil and current.isCurrent()
		end
		surface.refreshMapGeometry = function() self:RefreshQuestChainGiver() end
		surface.hideMapGeometry = function() Hide(self, state) end
		surface.invalidateMapGeometry = function()
			if not state.selection or not state.selection.isCurrent() then Hide(self, state) end
		end
	end
	local x, y = self:ProjectPlayerLocationPin("map", selected, geometry, 28)
	if not x or not y then
		self:ReleaseMapOverlayPins(surface, 0)
		self:HideOwnedUI(surface.frame)
		return false
	end
	local pin = self:AcquireMapOverlayPin(surface, 1, function(host)
		local frame = self:CreateOwnedUIFrame(self.CreateLocationPinFrame, "Frame", host.frame)
		Call(self, frame, "EnableMouse", false)
		Call(self, frame, "SetSize", 28, 28)
		local texture = Call(self, frame, "CreateTexture", nil, "ARTWORK")
		Call(self, texture, "SetAllPoints")
		Call(self, texture, "SetTexture", "Interface\\GossipFrame\\AvailableQuestIcon")
		local label = Call(self, frame, "CreateFontString", nil, "OVERLAY", "GameFontNormal")
		Call(self, label, "SetPoint", "LEFT", frame, "RIGHT", 4, 0)
		Call(self, label, "SetWidth", 200)
		Call(self, label, "SetJustifyH", "LEFT")
		return { frame = frame, label = label, surface = "map" }
	end)
	Call(self, pin.label, "SetText", selected.name)
	Call(self, pin.frame, "ClearAllPoints")
	Call(self, pin.frame, "SetPoint", "CENTER", surface.frame, "TOPLEFT", x, -y)
	self:SetMapOverlayPinGeometry(pin, geometry, x, y, 28)
	Call(self, pin.frame, "Show")
	Call(self, surface.frame, "Show")
	return true
end
function QT:ShowQuestChainGiver(location, isCurrent)
	if type(location) ~= "table" or type(isCurrent) ~= "function" or not isCurrent()
		or self:IsWorkBlocked("foreign_frame_mutation") or not self.isEnabled
		or not self:IsQuestTogetherMapDataShown("map") then return false end
	local id = self:NormalizeQuestID(location.mapID)
	local x, y = self:SafeToNumber(location.x), self:SafeToNumber(location.y)
	if not id or not x or not y or x < 0 or x > 1 or y < 0 or y > 1
		or not self.API.GetMapInfo(id) or not self.API.OpenQuestChainMap(id) then return false end
	local state = rawget(self, "questChainGiverState")
	if not state then state = { surfaces = {}, generation = 0 }; self.questChainGiverState = state end
	Hide(self, state)
	state.generation = state.generation + 1
	local generation = state.generation
	state.selection = { mapID = id, x = x, y = y, name = self:SafeToString(location.name, ""), isCurrent = isCurrent }
	self:ScheduleRuntimeWork("foreign_frame_mutation", "quest_chain_giver", function()
		if state.generation == generation and state.selection then self:RefreshQuestChainGiver() end
	end, { mode = "nextFrame", lifetime = "ui" })
	return true
end
