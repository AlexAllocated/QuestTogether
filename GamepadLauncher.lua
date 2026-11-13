-- Normal action-bar setup, not a controller binding override. A surviving
-- launcher is never remapped. Deleting the macro permits setup in an empty
-- default slot again; the native owner schedules bounded macro-change checks.
local QT = _G.QuestTogether
-- The same Blizzard book icon used by PQL's quest-journal button. A loose
-- addon texture can produce an iconless macro that native pickup refuses.
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local BODY = "/qt pql"
local status, busy, stopped, finished = "waiting", false, false, false

local function Accessible(value)
	return not (issecretvalue and issecretvalue(value)) and (not canaccessvalue or canaccessvalue(value))
end
local function Read(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, a, b, c = pcall(fn, ...)
	if not ok or not Accessible(a) or not Accessible(b) or not Accessible(c) then return false end
	return true, a, b, c
end
local function Integer(value, maximum)
	return type(value) == "number" and value >= 0 and value <= maximum and value == math.floor(value)
end
local function ResolveIcon()
	-- Resolve the shipped asset instead of persisting a client-local loose ID.
	local resolver = GetFileIDFromPath or (C_UIFileAsset and C_UIFileAsset.GetFileID)
	local ok, id = Read(resolver, ICON)
	if ok and Integer(id, 2147483647) and id > 0 then return id end
end
local function IsLauncherIcon(icon, id)
	return (id ~= nil and icon == id) or icon == ICON or icon == ICON .. ".blp"
end
local function HasActionAPI()
	return C_ActionBar and C_ActionBar.HasAction or HasAction
end
local function SetStatus(value)
	status = value
	if value == "installed" or value == "occupied" or value == "macro_limit" or value == "macro_name_conflict"
		or value == "cancelled" or value == "installing" or value == "already_checked"
		or value:match("failed$") or value:match("unverified$") or value:match("cancelled$") then finished = true end
	return value
end
local function CanInstall()
	if rawget(QT, "isRunningTests") or not QT.isInitialized or QT.isLoggingOut or QT:IsRuntimeRestricted() then
		return false
	end
	local native = QT:GetGamepadIntegrationStatus()
	if not native or not native.available or not native.worldReady or not native.enabled or native.failed or not QT:IsNativeGamepadMode() then
		return false
	end
	local ok, combat = Read(InCombatLockdown)
	if not ok or combat ~= false then return false end
	local loggedIn
	ok, loggedIn = Read(IsLoggedIn)
	return ok and loggedIn == true
end
local function CursorEmpty()
	local ok, kind = Read(GetCursorInfo)
	return ok and kind == nil
end
local function SlotEmpty(slot)
	local ok, kind, id = Read(GetActionInfo, slot)
	local hasOK, has = Read(HasActionAPI(), slot)
	if not ok or not hasOK or type(has) ~= "boolean" then return nil end
	-- Native gamepad editing explicitly treats macro ID zero as a deleted
	-- macro's stale slot entry. It must be cleared before ordinary placement.
	if kind == "macro" and id == 0 then return true, true end
	return kind == nil and has == false
end
local function DefaultBindings()
	if not C_KeyBindings or not Enum or not Enum.BindingContext then return "waiting_api" end
	local context = Enum.BindingContext.GamepadModeInGameCore
	if not Accessible(context) or type(context) ~= "number" then return "waiting_api" end
	for _, binding in ipairs({
		{ "PADLTRIGGER", "GAMEPADLEFTMOD" }, { "PADRTRIGGER", "GAMEPADRIGHTMOD" },
		{ "PADDUP", "GAMEPADACTIONBUTTON2" },
	}) do
		local ok, action = Read(C_KeyBindings.GetBindingByKey, binding[1], context)
		if not ok or type(action) ~= "string" or action == "" then return "waiting_bindings" end
		if action ~= binding[2] then return "custom_bindings" end
	end
	return "default"
end
local function MacroLimits()
	local limits = Constants and Constants.MacroConsts
	if not limits or not Accessible(limits) then return end
	local accountMax, characterMax = limits.MAX_ACCOUNT_MACROS, limits.MAX_CHARACTER_MACROS
	if not Accessible(accountMax) or not Accessible(characterMax)
		or not Integer(accountMax, 1000) or not Integer(characterMax, 1000) then return end
	local ok, account, character = Read(GetNumMacros)
	if not ok or not Integer(account, accountMax) or not Integer(character, characterMax) then return end
	return accountMax, characterMax, account, character
end
local function ScanMacros()
	local base, limit, account, character = MacroLimits()
	if not base then return end
	local names, entries = {}, {}
	for _, range in ipairs({ { 1, account }, { base + 1, base + character } }) do
		for index = range[1], range[2] do
			local ok, name, icon, body = Read(GetMacroInfo, index)
			if not ok or type(name) ~= "string" then return end
			names[name] = true
			entries[#entries + 1] = { index = index, name = name, icon = icon, body = body }
		end
	end
	return names, entries, character < limit, account + character
end
local function ExistingLauncher(record, entries)
	record = type(record) == "table" and record or nil
	for _, macro in ipairs(entries) do
		if (record and record.macroName == macro.name)
			or (not (record and record.macroName) and (macro.name == "QT PQL" or macro.name:match("^QT PQL [2-9]$")))
			or macro.body == BODY then return macro end
	end
end
local function RememberMacro(record, macro, count)
	record.schema, record.macroName, record.observed, record.macroCount = 3, macro.name, true, count
	record.recreatePending, record.retired = nil, nil
end
local function FindMacro(name, icon)
	local base, _, _, character = MacroLimits()
	if not base then return end
	for index = base + 1, base + character do
		local ok, currentName, currentIcon, body = Read(GetMacroInfo, index)
		if not ok then return end
		if currentName == name and currentIcon == icon and body == BODY then return index end
	end
end
local function DropOwnCursor(index, macro)
	if not CanInstall() then return end
	local ok, kind, cursorIndex = Read(GetCursorInfo)
	local macroOK, name, icon, body = Read(GetMacroInfo, index)
	if ok and kind == "macro" and cursorIndex == index and macroOK
		and name == macro.name and icon == macro.icon and body == BODY then pcall(ClearCursor) end
end
local function Install()
	if not CanInstall() or not QT.db or type(QT.db.global) ~= "table" then return SetStatus("waiting") end
	for _, fn in ipairs({ "GetActionInfo", "GetCursorInfo", "ClearCursor", "GetNumMacros", "GetMacroInfo", "CreateMacro", "PickupMacro", "PlaceAction" }) do
		if type(_G[fn]) ~= "function" then return SetStatus("waiting_api") end
	end
	if type(HasActionAPI()) ~= "function" then return SetStatus("waiting_api") end
	local ok, guid = Read(UnitGUID, "player")
	local regionOK, region = Read(GetCurrentRegion)
	if not ok or type(guid) ~= "string" or not guid:match("^Player%-")
		or not regionOK or not Integer(region, 100) or region == 0 then return SetStatus("waiting_identity") end
	local key = "forever:" .. region .. ":" .. guid
	local ledger = QT.db.global.gamepadLauncherCharacters
	local previous = type(ledger) == "table" and ledger[key] or nil
	local names, entries, hasCapacity, macroCount = ScanMacros()
	if not names then return SetStatus("waiting_macros") end
	if type(ledger) ~= "table" then ledger = {}; QT.db.global.gamepadLauncherCharacters = ledger end
	local existing = ExistingLauncher(type(previous) == "table" and previous or nil, entries)
	if existing then
		local record = type(previous) == "table" and previous or {}
		RememberMacro(record, existing, macroCount)
		record.status = "macro_present"; ledger[key] = record
		finished = true
		return SetStatus(record.status)
	end
	if type(previous) == "table" and previous.schema == 3 and (previous.retired or not previous.observed) then
		-- A failed creation is not a deletion. Never turn unrelated macro events
		-- into repeated retries of a native failure or an initial occupied slot.
		finished = true
		return SetStatus(previous.status or "already_checked")
	end
	if type(previous) == "table" and previous.observed and not previous.recreatePending
		and (type(previous.macroCount) ~= "number" or macroCount >= previous.macroCount) then
		-- No public stable macro ID exists. A rename plus content edit at the
		-- same count is ambiguous, so preserve customization instead of guessing.
		previous.status, previous.retired = "macro_customized", true
		finished = true
		return SetStatus(previous.status)
	end
	local util = GamepadActionBarBindingUtil
	if not util or not C_GamepadUI or not C_KeyBindings or not Enum or not Enum.BindingContext then
		return SetStatus("waiting_api")
	end
	local slot
	ok, slot = Read(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, 1, 26)
	local validOK, valid = Read(C_GamepadUI.IsValidGamepadActionStorageSlotIndex, slot)
	if not ok or not Integer(slot, 10000) or slot == 0 or not validOK or valid ~= true then
		return SetStatus("waiting_storage")
	end
	local empty, staleMacro = SlotEmpty(slot)
	if empty == nil then return SetStatus("waiting_storage") end
	if not CursorEmpty() then return SetStatus("waiting_cursor") end
	local bindings = DefaultBindings()
	if bindings ~= "default" then return SetStatus(bindings) end
	-- Do not mark occupancy until world entry and readable native storage agree.
	local record = { status = empty and "installing" or "occupied", schema = 3, observed = false }
	if not empty then
		if type(previous) == "table" then
			record = previous
			record.status, record.recreatePending, record.observed = "waiting_slot", true, true
		end
		ledger[key] = record; finished = true
		return SetStatus(record.status)
	end
	if staleMacro and type(PickupAction) ~= "function" then return SetStatus("waiting_api") end
	local iconID = ResolveIcon()
	if not iconID then return SetStatus("waiting_icon") end
	if not hasCapacity then
		record.status = "macro_limit"; ledger[key] = record; return SetStatus(record.status)
	end
	local name
	for suffix = 1, 9 do
		local candidate = suffix == 1 and "QT PQL" or "QT PQL " .. suffix
		if not names[candidate] then name = candidate; break end
	end
	if not name then record.status = "macro_name_conflict"; ledger[key] = record; return SetStatus(record.status) end
	-- Persist intent before mutation. Uncertain creation outcomes cannot retry
	-- until an actual launcher has been observed and then deleted.
	ledger[key] = record
	local global, profile = QT.db.global, QT.db.profile
	local function Current()
		if not CanInstall() or not QT.db or QT.db.global ~= global or QT.db.profile ~= profile then return false end
		if global.gamepadLauncherCharacters ~= ledger or ledger[key] ~= record or record.status ~= "installing" then return false end
		local identityOK, currentGUID = Read(UnitGUID, "player")
		local currentRegionOK, currentRegion = Read(GetCurrentRegion)
		local slotOK, currentSlot = Read(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, 1, 26)
		return identityOK and currentGUID == guid and currentRegionOK and currentRegion == region
			and slotOK and currentSlot == slot and DefaultBindings() == "default"
	end
	local function Finish(value)
		record.status = value
		return SetStatus(value)
	end
	if not Current() or not CursorEmpty() or SlotEmpty(slot) ~= true then return Finish("cancelled") end
	local freshNames, freshEntries = ScanMacros()
	if not freshNames then return Finish("cancelled") end
	if ExistingLauncher(previous, freshEntries) or freshNames[name] then return Finish("cancelled") end
	if staleMacro then
		local stillEmpty, stillStale = SlotEmpty(slot)
		if not Current() or not CursorEmpty() or stillEmpty ~= true or not stillStale then return Finish("cancelled") end
		local cleared = Read(PickupAction, slot)
		local afterEmpty, afterStale = SlotEmpty(slot)
		-- A foreign cursor or a changed slot is never cleared/overwritten.
		if not cleared or not CursorEmpty() or afterEmpty ~= true or afterStale then return Finish("stale_slot_unverified") end
	end
	local macro
	do
		if not Current() or not CursorEmpty() or SlotEmpty(slot) ~= true then return Finish("cancelled") end
		local index
		ok, index = Read(CreateMacro, name, iconID, BODY, true)
		if not ok or not Integer(index, 2000) or index == 0 then return Finish("macro_creation_failed") end
		local readOK, savedName, savedIcon, savedBody = Read(GetMacroInfo, index)
		if not readOK or savedName ~= name or savedBody ~= BODY
			or not IsLauncherIcon(savedIcon, iconID) then return Finish("macro_creation_unverified") end
		macro = { name = name, icon = savedIcon }
		local _, _, account, character = MacroLimits()
		RememberMacro(record, macro, account and character and account + character)
	end
	-- Macro indices compact when other macros are removed. Resolve the exact
	-- contents again after creation/callbacks, never trust an old saved index.
	local index = FindMacro(macro.name, macro.icon)
	if not index or not Current() or not CursorEmpty() or SlotEmpty(slot) ~= true then return Finish("cancelled") end
	local pickupOK = Read(PickupMacro, index)
	local cursorOK, kind, cursorIndex = Read(GetCursorInfo)
	if not pickupOK or not cursorOK or kind ~= "macro" or cursorIndex ~= index then
		DropOwnCursor(index, macro)
		return Finish("pickup_failed")
	end
	if not Current() or SlotEmpty(slot) ~= true or FindMacro(macro.name, macro.icon) ~= index then
		DropOwnCursor(index, macro)
		return Finish("cancelled")
	end
	local placed = Read(PlaceAction, slot)
	DropOwnCursor(index, macro) -- Never clear another action displaced onto the cursor.
	local actionOK, actionKind, actionIndex = Read(GetActionInfo, slot)
	if not placed or not actionOK or actionKind ~= "macro" or actionIndex ~= index
		or FindMacro(macro.name, macro.icon) ~= index then return Finish("placement_unverified") end
	return Finish("installed")
end

function QT:TryInstallDefaultGamepadLauncher()
	if self ~= QT or busy or stopped or finished or rawget(QT, "isRunningTests") then return false end
	busy = true
	local ok, result = pcall(Install)
	busy = false
	if not ok then status, stopped = "failed", true end
	if not ok or status:match("failed$") or status:match("unverified$") then
		if not self.gamepadLauncherFailureLogged then
			self.gamepadLauncherFailureLogged = true
			self:RecordDiagnosticError("gamepad_launcher", status)
		end
	end
	return ok and result == "installed"
end
function QT:GetGamepadLauncherStatus()
	return { status = status }
end
function QT:IsDefaultGamepadLauncherPending()
	return not busy and not stopped and not finished
end
function QT:OnGamepadLauncherMacroUpdate()
	if self == QT and not busy and not stopped and not rawget(QT, "isRunningTests") then finished = false end
end
function QT:OnGamepadLauncherSlotUpdate()
	if self == QT and status == "waiting_slot" and not busy and not stopped and not rawget(QT, "isRunningTests") then finished = false end
end
