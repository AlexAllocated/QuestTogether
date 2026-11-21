-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether

function QuestTogether:CreateTomTomWaypoint(mapID, coordX, coordY)
	if self:IsPartyFocusChangeLocked() then
		return false
	end
	local numericMapID = self:SafeToNumber(mapID)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericMapID or not numericX or not numericY then
		return false
	end

	if not (self.API and self.API.IsAddOnLoaded and self.API.IsAddOnLoaded("TomTom")) then
		return false
	end

	local tomTom = _G.TomTom
	if not self:CanAccessTable(tomTom) then
		return false
	end
	local addWaypoint = tomTom.AddWaypoint
	if not self:CanAccessValue(addWaypoint) or type(addWaypoint) ~= "function" then
		return false
	end

	-- TomTom may reject waypoint creation during transient map states; keep fallback path alive.
	local ok = pcall(addWaypoint, tomTom, numericMapID, numericX / 100, numericY / 100, {
		title = string.format("QuestTogether %.1f, %.1f", numericX, numericY),
		from = "QuestTogether/ping",
	})
	return ok and true or false
end

function QuestTogether:CreateBlizzardWaypoint(mapID, coordX, coordY)
	if self:IsPartyFocusChangeLocked() then
		return false
	end
	local numericMapID = self:SafeToNumber(mapID)
	local numericX = self:SafeToNumber(coordX)
	local numericY = self:SafeToNumber(coordY)
	if not numericMapID or not numericX or not numericY then
		return false
	end
	-- Disabled runtime has no restriction-release wakeups, and enabling resets
	-- its deferred lifetime. Reject a blocked click instead of accepting work
	-- that cannot run. Unrestricted explicit clicks remain available.
	if self.isEnabled ~= true and self.IsWorkBlocked and self:IsWorkBlocked("waypoint_mutation") then
		return false
	end

	local function applyWaypoint()
		if self:IsPartyFocusChangeLocked() then
			return false
		end
		if not (self.API and self.API.CanSetUserWaypointOnMap and self.API.CanSetUserWaypointOnMap(numericMapID)) then
			return false
		end

		local point = self.API.CreateUiMapPoint
			and self.API.CreateUiMapPoint(numericMapID, numericX / 100, numericY / 100)
		if not point then
			return false
		end

		if not self.API.SetUserWaypoint then
			return false
		end
		local ok, wasSet = pcall(self.API.SetUserWaypoint, point)
		if not ok or not self:CanAccessValue(wasSet) or wasSet ~= true then
			return false
		end
		if self.API.SetSuperTrackedUserWaypoint then
			pcall(self.API.SetSuperTrackedUserWaypoint, true)
		end
		return true
	end

	if self.RunOrDeferWork then
		self:SetPendingWaypointIntent({
			mapID = numericMapID,
			coordX = numericX,
			coordY = numericY,
		})
		local applied = false
		local ranNow = self:RunOrDeferWork("waypoint_mutation", "user_waypoint", function()
			local pending = self.GetRuntimeWorkStateStore and self:GetRuntimeWorkStateStore().pendingWaypointIntent
				or nil
			self:SetPendingWaypointIntent(nil)
			if pending then
				applied = applyWaypoint()
			end
		end, 0.2, "CreateBlizzardWaypoint")
		if not ranNow then
			return true
		end
		return applied
	end

	return applyWaypoint()
end

function QuestTogether:OpenPingWaypoint(mapID, coordX, coordY)
	if self:IsPartyFocusChangeLocked() then
		return false
	end
	-- Explicit coordinate navigation also ends following when TomTom handles it.
	self:StopPartyQuestFollow()
	if self:CreateTomTomWaypoint(mapID, coordX, coordY) then
		return true
	end

	return self:CreateBlizzardWaypoint(mapID, coordX, coordY)
end
