-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local Access = QuestTogether.NativeAccess
local CanAccessForeignValue, CanAccessForeignTable = Access.Value, Access.Table
local SafeText = Access.Text
local tostring = SafeText

QuestTogether:RegisterNativeAPI("ui", {
	Delay = function(seconds, callback)
		C_Timer.After(seconds, callback)
	end,
	GetEditModeManagerFrame = function()
		return EditModeManagerFrame
	end,
	LoadEditMode = function()
		local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
		if type(loader) ~= "function" then
			return false
		end
		local ok, loaded = pcall(loader, "Blizzard_EditMode")
		return ok and CanAccessForeignValue(loaded) and loaded == true
	end,
	ShowUIPanel = function(frame)
		if not QuestTogether:CanAccessForeignFrame(frame) or type(ShowUIPanel) ~= "function" then
			return false
		end
		return pcall(ShowUIPanel, frame)
	end,
	GetCVar = function(cvarName)
		if
			not CanAccessForeignValue(cvarName)
			or type(cvarName) ~= "string"
			or cvarName == ""
			or not CanAccessForeignTable(C_CVar)
		then
			return nil, false
		end
		local getter = C_CVar.GetCVar
		if not CanAccessForeignValue(getter) or type(getter) ~= "function" then
			return nil, false
		end
		local ok, value = pcall(getter, cvarName)
		if not ok or not CanAccessForeignValue(value) then
			return nil, false
		end
		-- A missing CVar returns nil successfully. Keep it distinguishable from
		-- a failed or inaccessible read when callers select a legacy fallback.
		return value, true
	end,
	GetInstanceInfo = function()
		if type(GetInstanceInfo) ~= "function" then
			return nil
		end
		local ok, name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID, instanceGroupSize =
			pcall(GetInstanceInfo)
		if not ok then
			return nil
		end
		return {
			name = name,
			instanceType = instanceType,
			difficultyID = difficultyID,
			difficultyName = difficultyName,
			maxPlayers = maxPlayers,
			dynamicDifficulty = dynamicDifficulty,
			isDynamic = isDynamic,
			instanceMapID = instanceMapID,
			instanceGroupSize = instanceGroupSize,
		}
	end,
	InCombatLockdown = function()
		if InCombatLockdown then
			return InCombatLockdown() and true or false
		end
		return false
	end,
	CanCallProtectedFunctions = function(frame)
		if not CanAccessForeignValue(frame) then
			return false
		end
		local actions = C_RestrictedActions
		if actions ~= nil then
			if not CanAccessForeignTable(actions) then
				return false
			end
			local check = actions.CheckAllowProtectedFunctions
			if not CanAccessForeignValue(check) then
				return false
			end
			if check ~= nil then
				if type(check) ~= "function" then
					return false
				end
				local ok, allowed = pcall(check, frame, true)
				return ok and CanAccessForeignValue(allowed) and allowed == true
			end
		end
		-- Older clients expose only combat lockdown. Missing or unreadable
		-- permission is never an authorization to modify a secure button.
		if not CanAccessForeignValue(InCombatLockdown) or type(InCombatLockdown) ~= "function" then
			return false
		end
		local ok, locked = pcall(InCombatLockdown)
		return ok and CanAccessForeignValue(locked) and locked == false
	end,
	Random = function(low, high)
		return math.random(low, high)
	end,
	GetTime = function()
		return GetTime()
	end,
	ProfileMilliseconds = function()
		if type(debugprofilestop) ~= "function" then
			return nil
		end
		local ok, value = pcall(debugprofilestop)
		return ok and QuestTogether:SafeToNumber(value) or nil
	end,
	GetServerTime = function()
		if type(GetServerTime) ~= "function" then
			return nil
		end
		local ok, value = pcall(GetServerTime)
		return ok and QuestTogether:SafeToNumber(value) or nil
	end,
	ReloadUI = function()
		if type(ReloadUI) ~= "function" then
			return false
		end
		local ok = pcall(ReloadUI)
		return ok and true or false
	end,
	IsModifiedClick = function(action)
		if type(IsModifiedClick) ~= "function" then
			return false
		end
		local ok, modified = pcall(IsModifiedClick, action)
		return ok and modified and true or false
	end,
	GetNamePlateForUnit = function(unitToken)
		if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
			return nil
		end
		if type(unitToken) ~= "string" or unitToken == "" then
			return nil
		end

		local ok, namePlateFrameBase = pcall(C_NamePlate.GetNamePlateForUnit, unitToken, false)
		if not ok or not CanAccessForeignValue(namePlateFrameBase) then
			return nil
		end
		return namePlateFrameBase
	end,
	GetNamePlates = function()
		if not (C_NamePlate and C_NamePlate.GetNamePlates) then
			return {}
		end

		local ok, rawNameplates = pcall(C_NamePlate.GetNamePlates, false)
		if not ok or not CanAccessForeignTable(rawNameplates) then
			return {}
		end

		local nameplates = {}
		local okCopy = pcall(function()
			for _, frame in pairs(rawNameplates) do
				if CanAccessForeignValue(frame) then
					nameplates[#nameplates + 1] = frame
				end
			end
		end)
		if not okCopy then
			return {}
		end
		return nameplates
	end,
	GetMinimapAnchor = function()
		return Minimap
	end,
	IsPartyQuestKeyboardInputBlocked = function(frame)
		if
			QuestTogether.IsGamepadActionPanelOpen and QuestTogether:IsGamepadActionPanelOpen()
			or QuestTogether.IsGamepadWindowFocused and QuestTogether:IsGamepadWindowFocused(frame)
		then
			return true
		end
		if not QuestTogether:CanMutateOwnedUI(frame) or QuestTogether:IsRuntimeRestricted() then
			return true
		end
		if type(GetCurrentKeyBoardFocus) ~= "function" then
			return true
		end
		local ok, focus = pcall(GetCurrentKeyBoardFocus)
		if not ok or not CanAccessForeignValue(focus) or focus ~= nil then
			return true
		end
		if Menu and type(Menu.GetManager) == "function" then
			local managerOK, manager = pcall(Menu.GetManager)
			if not managerOK or not CanAccessForeignTable(manager) then
				return true
			end
			if type(manager.IsAnyMenuOpen) ~= "function" then
				return true
			end
			local menuOK, opened = pcall(manager.IsAnyMenuOpen, manager)
			if not menuOK or not CanAccessForeignValue(opened) or opened == true then
				return true
			end
		end
		return false
	end,
	IsMouseOverPartyQuestWindow = function(frame)
		if not QuestTogether:CanMutateOwnedUI(frame) then
			return false
		end
		local fn = QuestTogether:GetAccessibleFrameMember(frame, "IsMouseOver")
		if type(fn) ~= "function" then
			return false
		end
		local ok, over = pcall(fn, frame)
		return ok and CanAccessForeignValue(over) and over == true
	end,
	OpenKeyBindings = function()
		if
			QuestTogether:IsWorkBlocked("foreign_frame_mutation")
			or not Settings
			or type(Settings.OpenToCategory) ~= "function"
		then
			return false
		end
		local id = QuestTogether:SafeToNumber(Settings.KEYBINDINGS_CATEGORY_ID)
		if not id then
			return false
		end
		return pcall(Settings.OpenToCategory, id, "QuestTogether")
	end,
	GetPlayerNameplatePreviewClassColor = function()
		local getClass, colors = UnitClass, RAID_CLASS_COLORS
		if not CanAccessForeignValue(getClass) or type(getClass) ~= "function" or not CanAccessForeignTable(colors) then
			return nil
		end
		local ok, _, class = pcall(getClass, "player")
		if
			not ok
			or not CanAccessForeignValue(class)
			or type(class) ~= "string"
			or #class == 0
			or #class > 32
			or not class:match("^[A-Z]+$")
		then
			return nil
		end
		-- Match Blizzard's own class palette, never an addon's custom override.
		-- Return only checked components; no shared color table escapes.
		local readOK, r, g, b = pcall(function()
			local color = colors[class]
			if not CanAccessForeignTable(color) then
				return nil
			end
			local red, green, blue =
				QuestTogether:SafeToNumber(color.r),
				QuestTogether:SafeToNumber(color.g),
				QuestTogether:SafeToNumber(color.b)
			if
				not red
				or not green
				or not blue
				or red < 0
				or red > 1
				or green < 0
				or green > 1
				or blue < 0
				or blue > 1
			then
				return nil
			end
			return red, green, blue
		end)
		if readOK then
			return r, g, b
		end
		return nil
	end,
	OpenNativeFriendlyNameplateSettings = function()
		if QuestTogether:IsWorkBlocked("foreign_frame_mutation") or not CanAccessForeignTable(Settings) then
			return false
		end
		local open = Settings.OpenToCategory
		if not CanAccessForeignValue(open) or type(open) ~= "function" then
			return false
		end
		local id = QuestTogether:SafeToNumber(Settings.NAMEPLATE_OPTIONS_CATEGORY_ID)
		if not id or id <= 0 or id % 1 ~= 0 then
			return false
		end
		-- Blizzard owns category selection and scrolling to its localized label.
		-- A missing label still allows opening the native Nameplates category.
		local label = UNIT_NAMEPLATES_FRIENDLY_PLAYER_SHOW_ONLY_NAME
		if not CanAccessForeignValue(label) or type(label) ~= "string" or label == "" then
			label = nil
		end
		local opened = pcall(open, id, label)
		return opened
	end,
	GetPlayerNotesNamespace = function()
		local region = "default"
		if type(GetCurrentRegion) == "function" then
			local ok, value = pcall(GetCurrentRegion)
			local number = ok and QuestTogether:SafeToNumber(value)
			if number then
				region = tostring(number)
			end
		end
		local project = QuestTogether:SafeToNumber(WOW_PROJECT_ID) or 0
		return tostring(project)
			.. ":"
			.. region
			.. ":"
			.. (QuestTogether:UsesRegionalPlayerNames() and "regional" or "realm")
	end,
	GetHintCapabilities = function()
		-- Read capabilities, never the player's current quest, party or map.
		local function Has(object, ...)
			if not CanAccessForeignTable(object) then
				return false
			end
			for index = 1, select("#", ...) do
				local value = object[select(index, ...)]
				if not CanAccessForeignValue(value) or type(value) ~= "function" then
					return false
				end
			end
			return true
		end
		local focus = Has(C_SuperTrack, "IsSuperTrackingQuest", "GetSuperTrackedQuestID", "SetSuperTrackedQuestID")
		local waypoint = Has(C_Map, "GetUserWaypoint", "SetUserWaypoint") and Has(UiMapPoint, "CreateFromCoordinates")
		local nativeNavigation = waypoint
			and Has(C_Map, "CanSetUserWaypointOnMap")
			and Has(C_SuperTrack, "SetSuperTrackedUserWaypoint")
		local navigation = nativeNavigation or Has(TomTom, "AddWaypoint")
		local editMode = QuestTogether.API.GetEditModeManagerFrame()
		local hud = QuestTogether:CanAccessForeignFrame(editMode)
			and type(QuestTogether:GetAccessibleFrameMember(editMode, "CanEnterEditMode")) == "function"
		if not hud and Has(C_AddOns, "GetAddOnInfo") then
			local ok, name = pcall(C_AddOns.GetAddOnInfo, "Blizzard_EditMode")
			hud = ok and CanAccessForeignValue(name) and type(name) == "string" and name == "Blizzard_EditMode"
		end
		local retail = CanAccessForeignValue(WOW_PROJECT_ID)
			and CanAccessForeignValue(WOW_PROJECT_MAINLINE)
			and WOW_PROJECT_MAINLINE ~= nil
			and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
			and not QuestTogether:UsesRegionalPlayerNames()
		return {
			menu = Has(MenuUtil, "CreateContextMenu"),
			sharing = QuestTogether.API.CanShareQuests(),
			details = QuestTogether.API.CanOpenQuestDetails(),
			journal = QuestTogether.API.CanOpenQuestJournal(),
			focus = focus,
			waypoint = waypoint,
			navigation = navigation,
			navigationFocus = navigation and focus,
			hud = hud,
			nameplates = Has(C_NamePlate, "GetNamePlateForUnit"),
			worldQuests = retail and Has(C_QuestLog, "IsWorldQuest"),
			bonusObjectives = retail and Has(C_TaskQuest, "GetQuestInfoByQuestID"),
			layers = QuestTogether:UsesRegionalPlayerNames(),
			chains = retail or QuestTogether:UsesRegionalPlayerNames(),
			retail = retail == true,
			warMode = QuestTogether:SupportsWarMode() == true,
		}
	end,
	CreateContextMenu = function(ownerFrame, generator)
		if QuestTogether.IsNativeGamepadMode and QuestTogether:IsNativeGamepadMode() then
			return QuestTogether.ShowGamepadContextMenu
					and QuestTogether:ShowGamepadContextMenu(ownerFrame, generator) == true
				or false
		end
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return false
		end
		if not CanAccessForeignValue(ownerFrame) then
			return false
		end
		ownerFrame = ownerFrame or UIParent
		if not QuestTogether:CanAccessForeignFrame(ownerFrame) then
			return false
		end
		local ok, menu = pcall(MenuUtil.CreateContextMenu, ownerFrame, generator)
		return ok and CanAccessForeignValue(menu) and menu ~= nil
	end,
	LoadTestSuite = function()
		local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
		if type(loader) ~= "function" then
			return false, "Addon loading is unavailable."
		end
		local metadata = QuestTogether.API.GetAddOnMetadata
		local version = metadata("QuestTogether_Tests", "Version")
		if type(version) ~= "string" or version == "" or version ~= metadata("QuestTogether", "Version") then
			return false, "QuestTogether and its test companion must be the same version."
		end
		local ok, loaded, reason = pcall(loader, "QuestTogether_Tests")
		if not ok or not QuestTogether:CanAccessValue(loaded) or loaded ~= true then
			return false, ok and QuestTogether:CanAccessValue(reason) and type(reason) == "string" and reason or nil
		end
		return true
	end,
	IsAddOnLoaded = function(requestedAddonName)
		if C_AddOns and C_AddOns.IsAddOnLoaded then
			local ok, isLoaded = pcall(C_AddOns.IsAddOnLoaded, requestedAddonName)
			return ok and isLoaded and true or false
		end
		local ok, isLoaded = pcall(IsAddOnLoaded, requestedAddonName)
		return ok and isLoaded and true or false
	end,
	GetAddOnMetadata = function(requestedAddonName, fieldName)
		if C_AddOns and C_AddOns.GetAddOnMetadata then
			local ok, metadata = pcall(C_AddOns.GetAddOnMetadata, requestedAddonName, fieldName)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(metadata) then
				return nil
			end
			return metadata
		end
		if type(GetAddOnMetadata) == "function" then
			local ok, metadata = pcall(GetAddOnMetadata, requestedAddonName, fieldName)
			if not ok then
				return nil
			end
			if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(metadata) then
				return nil
			end
			return metadata
		end
		return nil
	end,
})
