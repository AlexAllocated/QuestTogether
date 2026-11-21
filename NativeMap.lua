-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local Access = QuestTogether.NativeAccess
local CanAccessForeignValue, CanAccessForeignTable = Access.Value, Access.Table

QuestTogether:RegisterNativeAPI("map", {
	GetPlayerMapID = function(unitToken)
		if not (C_Map and C_Map.GetBestMapForUnit) then
			return nil
		end

		local normalizedUnitToken = type(unitToken) == "string" and unitToken ~= "" and unitToken or "player"
		local ok, mapID = pcall(C_Map.GetBestMapForUnit, normalizedUnitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapID) then
			return nil
		end
		local numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
		if not numericMapID or numericMapID <= 0 then
			return nil
		end
		return math.floor(numericMapID + 0.5)
	end,
	IsWorldMapVisible = function()
		local frame = WorldMapFrame
		if not CanAccessForeignValue(frame) then
			return true
		end
		if not frame then
			return false
		end
		local isShown = QuestTogether:GetAccessibleFrameMember(frame, "IsShown")
		if type(isShown) ~= "function" then
			-- Forbidden/unreadable map state must not permit sensitive reads.
			return true
		end
		local okShown, shown = pcall(isShown, frame)
		if not okShown or not CanAccessForeignValue(shown) or type(shown) ~= "boolean" then
			return true
		end
		return shown
	end,
	CanOpenPlayerLocationMap = function()
		return CanAccessForeignTable(C_Map)
			and CanAccessForeignValue(C_Map.OpenWorldMap)
			and type(C_Map.OpenWorldMap) == "function"
			and QuestTogether:CanAccessForeignFrame(WorldMapFrame)
	end,
	OpenPlayerLocationMap = function(mapID)
		local id = QuestTogether:SafeToNumber(mapID)
		if
			not id
			or id <= 0
			or id > 2147483647
			or id ~= math.floor(id)
			or QuestTogether:IsWorkBlocked("foreign_frame_mutation")
			or not QuestTogether.API.CanOpenPlayerLocationMap()
		then
			return false
		end
		-- The engine dispatches WORLD_MAP_OPEN to Blizzard's own handler. Do
		-- not call the Lua OpenWorldMap/SetMapID helpers from QT: they can
		-- taint reused native pins and break later map opens in combat.
		local ok = pcall(C_Map.OpenWorldMap, id)
		if not ok or not QuestTogether:CanAccessForeignFrame(WorldMapFrame, true) then
			return false
		end
		local getter = QuestTogether:GetAccessibleFrameMember(WorldMapFrame, "GetMapID")
		if type(getter) ~= "function" then
			return false
		end
		local readOK, currentID = pcall(getter, WorldMapFrame)
		return readOK and QuestTogether:SafeToNumber(currentID) == id
	end,
	GetBestMapForUnit = function(unitToken)
		if C_Map and C_Map.GetBestMapForUnit then
			local ok, mapID = pcall(C_Map.GetBestMapForUnit, unitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(mapID) then
				return nil
			end
			return mapID
		end
		return nil
	end,
	GetMapInfo = function(mapID)
		if C_Map and C_Map.GetMapInfo then
			local ok, mapInfo = pcall(C_Map.GetMapInfo, mapID)
			if not ok or not CanAccessForeignTable(mapInfo) then
				return nil
			end

			local sanitizedInfo = {}
			for _, key in ipairs({ "mapType", "parentMapID" }) do
				local value = CanAccessForeignValue(mapInfo[key]) and QuestTogether:SafeToNumber(mapInfo[key])
				if value and value >= 0 and value <= 1000000 and value == math.floor(value) then
					sanitizedInfo[key] = value
				end
			end
			local numericMapID = CanAccessForeignValue(mapInfo.mapID)
					and QuestTogether
					and QuestTogether.SafeToNumber
					and QuestTogether:SafeToNumber(mapInfo.mapID)
				or nil
			if not numericMapID then
				numericMapID = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(mapID) or nil
			end
			if numericMapID and numericMapID > 0 then
				sanitizedInfo.mapID = math.floor(numericMapID + 0.5)
			end

			local mapName = mapInfo.name
			if CanAccessForeignValue(mapName) then
				if type(mapName) == "string" and mapName ~= "" then
					sanitizedInfo.name = mapName
				end
			end

			return sanitizedInfo
		end
		return nil
	end,
	GetPlayerMapPosition = function(mapID, unitToken)
		if C_Map and C_Map.GetPlayerMapPosition then
			local ok, mapPosition = pcall(C_Map.GetPlayerMapPosition, mapID, unitToken)
			if not ok or not CanAccessForeignValue(mapPosition) then
				return nil
			end
			local positionType = type(mapPosition)
			if
				(positionType ~= "table" and positionType ~= "userdata")
				or (positionType == "table" and not CanAccessForeignTable(mapPosition))
			then
				return nil
			end

			local rawX = mapPosition.x
			local rawY = mapPosition.y
			if not CanAccessForeignValue(rawX) or not CanAccessForeignValue(rawY) then
				return nil
			end
			if rawX == nil or rawY == nil then
				local getXY = mapPosition.GetXY
				if CanAccessForeignValue(getXY) and type(getXY) == "function" then
					local okXY, xValue, yValue = pcall(getXY, mapPosition)
					if okXY and CanAccessForeignValue(xValue) and CanAccessForeignValue(yValue) then
						rawX = rawX or xValue
						rawY = rawY or yValue
					end
				end
			end

			local numericX = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawX) or nil
			local numericY = QuestTogether and QuestTogether.SafeToNumber and QuestTogether:SafeToNumber(rawY) or nil
			if numericX == nil or numericY == nil then
				return nil
			end

			return {
				x = numericX,
				y = numericY,
			}
		end
		return nil
	end,
	GetTooltipDataForHyperlink = function(hyperlink)
		if C_TooltipInfo and C_TooltipInfo.GetHyperlink and type(hyperlink) == "string" and hyperlink ~= "" then
			local ok, tooltipData = pcall(C_TooltipInfo.GetHyperlink, hyperlink)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tooltipData) then
				return nil
			end
			return tooltipData
		end
		return nil
	end,
	GetTooltipDataForUnit = function(unitToken)
		if C_TooltipInfo and C_TooltipInfo.GetUnit then
			local ok, tooltipData = pcall(C_TooltipInfo.GetUnit, unitToken)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(tooltipData) then
				return nil
			end
			return tooltipData
		end
		return nil
	end,
	SurfaceTooltipDataArgs = function(tooltipData)
		-- SurfaceArgs writes into Blizzard's tables. The tooltip reader already
		-- understands nested args; leave foreign data untouched.
		return CanAccessForeignTable(tooltipData) and tooltipData or nil
	end,
	IsWarModeFeatureEnabled = function()
		if not CanAccessForeignTable(C_PvP) then
			return nil
		end
		local getter = C_PvP.IsWarModeFeatureEnabled
		if not CanAccessForeignValue(getter) or type(getter) ~= "function" then
			return nil
		end
		local ok, enabled = pcall(getter)
		if ok and CanAccessForeignValue(enabled) and type(enabled) == "boolean" then
			return enabled
		end
		return nil
	end,
	IsWarModeActive = function()
		if not CanAccessForeignTable(C_PvP) then
			return nil
		end
		local getter = C_PvP.IsWarModeActive
		if not CanAccessForeignValue(getter) or type(getter) ~= "function" then
			return nil
		end
		-- Desired is a preference and can differ from the player's current mode.
		local ok, active = pcall(getter)
		if ok and CanAccessForeignValue(active) and type(active) == "boolean" then
			return active
		end
		return nil
	end,
	CreateUiMapPoint = function(mapID, x, y)
		if UiMapPoint and UiMapPoint.CreateFromCoordinates then
			return UiMapPoint.CreateFromCoordinates(mapID, x, y)
		end
		return nil
	end,
	CanSetUserWaypointOnMap = function(mapID)
		if C_Map and C_Map.CanSetUserWaypointOnMap then
			local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
			return ok and CanAccessForeignValue(canSet) and canSet == true
		end
		return false
	end,
	SetUserWaypoint = function(point)
		if C_Map and C_Map.SetUserWaypoint then
			local ok, result = pcall(C_Map.SetUserWaypoint, point)
			return ok and CanAccessForeignValue(result) and result == true
		end
		return false
	end,
	SetSuperTrackedUserWaypoint = function(shouldSuperTrack)
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			local ok, result = pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, shouldSuperTrack)
			return ok and result or nil
		end
		return nil
	end,
})
