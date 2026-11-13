-- Standalone offline boundary checks. Never load this through /qt test: this
-- sandbox substitutes native globals and cannot prove actual WoW taint safety,
-- physical controller mappings, action-page display, or icon rendering.
-- Usage: lua scripts/regression_gamepad_launcher.lua [repository-root]
local root = arg[1] or "."
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local ICON_ID = 133469 -- representative shipped texture ID, resolved by the native API
local BODY = "/qt pql"
local unpackValues = unpack or table.unpack

local function Harness()
	local h = {
		calls = {}, writes = {}, errors = {}, before = {}, after = {}, failures = {}, replacements = {},
		secret = {}, inaccessible = {}, account = {}, character = {}, actions = {},
		accountMax = 12, characterMax = 12, slot = 145, guid = "Player-1-1234", region = 1,
		iconID = ICON_ID,
		native = { available = true, enabled = true, worldReady = true }, mode = true, loggedIn = true,
		bindings = { PADLTRIGGER = "GAMEPADLEFTMOD", PADRTRIGGER = "GAMEPADRIGHTMOD", PADDUP = "GAMEPADACTIONBUTTON2" },
	}
	local env = setmetatable({}, { __index = _G })
	env._G = env
	local q = { db = { global = {}, profile = {} }, isInitialized = true }
	env.QuestTogether = q
	function q:IsRuntimeRestricted() return h.restricted == true end
	function q:GetGamepadIntegrationStatus() return h.native end
	function q:IsNativeGamepadMode() return h.mode end
	function q:RecordDiagnosticError(kind, reason)
		assert(kind == "gamepad_launcher")
		h.errors[#h.errors + 1] = reason
	end
	env.issecretvalue = function(value) return h.secret[value] == true end
	env.canaccessvalue = function(value) return not h.inaccessible[value] end
	local mutation = { CreateMacro = true, PickupMacro = true, PickupAction = true, PlaceAction = true, ClearCursor = true }
	local function API(name, body)
		return function(...)
			local args = { ... }
			h.calls[#h.calls + 1] = { name = name, args = args }
			if mutation[name] then h.writes[#h.writes + 1] = { name = name, args = args } end
			if h.before[name] then h.before[name](h, ...) end
			if h.failures[name] then error("injected " .. name .. " failure") end
			local a, b, c = (h.replacements[name] or body)(...)
			if h.after[name] then h.after[name](h, a, b, c, unpackValues(args)) end
			return a, b, c
		end
	end
	function h:count(name)
		local count = 0
		for _, call in ipairs(self.calls) do if call.name == name then count = count + 1 end end
		return count
	end
	function h:once(phase, name, callback)
		self[phase][name] = function(...)
			self[phase][name] = nil
			return callback(...)
		end
	end
	function h:macro(index)
		if type(index) ~= "number" then return end
		if index <= self.accountMax then return self.account[index] end
		return self.character[index - self.accountMax]
	end
	function h:addMacro(name, body, icon, account)
		local list = account and self.account or self.character
		local macro = { name = name, body = body or BODY, icon = icon or ICON }
		list[#list + 1] = macro
		return macro, (account and 0 or self.accountMax) + #list
	end
	function h:record()
		local ledger = q.db.global.gamepadLauncherCharacters
		return ledger and ledger["forever:" .. self.region .. ":" .. self.guid]
	end
	function h:status() return q:GetGamepadLauncherStatus().status end
	function h:updateMacros() q:OnGamepadLauncherMacroUpdate() end
	function h:updateSlot() q:OnGamepadLauncherSlotUpdate() end
	function h:deleteCharacterMacro(position, ghost)
		local index = self.accountMax + position
		table.remove(self.character, position)
		for slot, action in pairs(self.actions) do
			if action[1] == "macro" then
				if action[2] == index then self.actions[slot] = ghost and { "macro", 0 } or nil
				elseif action[2] > index then action[2] = action[2] - 1 end
			end
		end
	end
	function h:run(expected)
		local installed = q:TryInstallDefaultGamepadLauncher()
		assert(self:status() == expected, "expected " .. expected .. ", got " .. tostring(self:status()))
		assert(installed == (expected == "installed"), "unexpected installation return")
	end
	function h:untouched()
		assert(#self.writes == 0, "native state was mutated")
		assert(not self:record(), "transient prerequisite consumed the default assignment")
	end
	function h:noRetry(expected)
		local writes = #self.writes
		local function Check()
			assert(q:TryInstallDefaultGamepadLauncher() == false, "unchanged macro was automatically rebound")
			assert(self:status() == expected or self:status() == "macro_present" or self:status() == "macro_customized",
				"unexpected retry status: " .. tostring(self:status()))
		end
		Check()
		q.db.profile = { changed = true }
		Check()
		self:reload()
		Check()
		assert(#self.writes == writes, "saved attempt was reasserted on retry, profile change, or reload")
	end
	env.InCombatLockdown = API("InCombatLockdown", function() return h.combat == true end)
	env.IsLoggedIn = API("IsLoggedIn", function() return h.loggedIn end)
	env.UnitGUID = API("UnitGUID", function(unit) assert(unit == "player"); return h.guid end)
	env.GetCurrentRegion = API("GetCurrentRegion", function() return h.region end)
	env.GetCursorInfo = API("GetCursorInfo", function()
		if h.cursor then return h.cursor[1], h.cursor[2], h.cursor[3] end
	end)
	env.GetActionInfo = API("GetActionInfo", function(slot)
		assert(slot == h.slot, "accessed a different action slot")
		local action = h.actions[slot]
		if action then return action[1], action[2] end
	end)
	env.HasAction = API("HasAction", function(slot) assert(slot == h.slot); return h.actions[slot] ~= nil end)
	env.C_ActionBar = { HasAction = env.HasAction }
	env.GetFileIDFromPath = API("GetFileIDFromPath", function(path)
		assert(path == ICON)
		return h.iconID
	end)
	env.GetNumMacros = API("GetNumMacros", function() return #h.account, #h.character end)
	env.GetMacroInfo = API("GetMacroInfo", function(index)
		local macro = h:macro(index)
		if macro then return macro.name, macro.icon, macro.body end
	end)
	env.CreateMacro = API("CreateMacro", function(name, icon, body, perCharacter)
		assert(perCharacter == true, "must not create an account-wide macro")
		assert(#h.character < h.characterMax, "macro capacity exceeded")
		local _, index = h:addMacro(name, body, h.normalizedIcon or icon)
		return index
	end)
	env.PickupMacro = API("PickupMacro", function(index)
		assert(h:macro(index), "picked up a stale macro index")
		assert(not h.cursor, "picked up over an existing cursor")
		h.cursor = { "macro", index }
	end)
	env.PickupAction = API("PickupAction", function(slot)
		assert(slot == h.slot, "picked up outside the configured native storage slot")
		assert(not h.cursor, "picked up over an existing cursor")
		local action = h.actions[slot]
		h.actions[slot] = nil
		-- A deleted macro has no transferable action, but its empty native slot
		-- may still report the obsolete macro/0 record until PickupAction.
		if action and not (action[1] == "macro" and action[2] == 0) then h.cursor = action end
	end)
	env.PlaceAction = API("PlaceAction", function(slot)
		assert(slot == h.slot, "placed outside page 1 slot 26")
		assert(h.cursor and h.cursor[1] == "macro", "placed a foreign cursor")
		local oldAction = h.actions[slot]
		h.actions[slot], h.cursor = h.cursor, oldAction
	end)
	env.ClearCursor = API("ClearCursor", function() h.cursor = nil end)
	env.Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = h.accountMax, MAX_CHARACTER_MACROS = h.characterMax } }
	env.Enum = { BindingContext = { GamepadModeInGameCore = 17 } }
	env.GamepadActionBarBindingUtil = {
		GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID = API("StorageSlot", function(page, button)
			assert(page == 1 and button == 26, "requested a different page or crossbar position")
			return h.slot
		end),
		AssignActionToGamepadStandardSlot = function() error("helper clears an unverified cursor") end,
	}
	env.C_GamepadUI = {
		IsValidGamepadActionStorageSlotIndex = API("ValidStorage", function(slot) return slot == h.slot end),
	}
	env.C_KeyBindings = {
		GetBindingByKey = API("GetBindingByKey", function(key, context)
			assert(context == 17 and h.bindings[key] ~= nil, "unexpected binding lookup")
			return h.bindings[key]
		end),
	}
	for _, name in ipairs({ "SetBinding", "SetOverrideBinding", "SetOverrideBindingClick", "SaveBindings", "EditMacro", "DeleteMacro" }) do
		env[name] = function() error("unauthorized API: " .. name) end
	end
	h.qt, h.env = q, env
	function h:reload()
		local path = root .. "/GamepadLauncher.lua"
		local chunk
		if _VERSION == "Lua 5.1" then chunk = assert(loadfile(path)); setfenv(chunk, env)
		else chunk = assert(loadfile(path, "t", env)) end
		chunk()
	end
	h:reload()
	return h
end

local passed, failures = 0, {}
local function Test(name, callback)
	local ok, reason = pcall(callback)
	if ok then passed = passed + 1; print("PASS: " .. name)
	else failures[#failures + 1] = name .. ": " .. tostring(reason); print("FAIL: " .. failures[#failures]) end
end

Test("disabled, unsupported, restricted, uninitialized and live-test gates do not mutate state", function()
	for _, scenario in ipairs({ "disabled", "unsupported", "failed", "world", "mode", "restricted", "combat", "login", "init", "logout", "tests" }) do
		local h = Harness()
		if scenario == "disabled" then h.native.enabled = false
		elseif scenario == "unsupported" then h.native.available = false
		elseif scenario == "failed" then h.native.failed = true
		elseif scenario == "world" then h.native.worldReady = false
		elseif scenario == "mode" then h.mode = false
		elseif scenario == "restricted" then h.restricted = true
		elseif scenario == "combat" then h.combat = true
		elseif scenario == "login" then h.loggedIn = false
		elseif scenario == "init" then h.qt.isInitialized = false
		elseif scenario == "logout" then h.qt.isLoggingOut = true
		else h.qt.isRunningTests = true end
		h:run("waiting"); h:untouched()
	end
	local h = Harness()
	assert(h.qt.TryInstallDefaultGamepadLauncher({}) == false)
	h:untouched()
end)

Test("missing or inaccessible identity remains retryable", function()
	for _, scenario in ipairs({ "guid", "malformed", "region", "region_type", "secret", "error" }) do
		local h = Harness()
		if scenario == "guid" then h.guid = nil
		elseif scenario == "malformed" then h.guid = "Creature-1-1234"
		elseif scenario == "region" then h.region = 0
		elseif scenario == "region_type" then h.region = "1"
		elseif scenario == "secret" then h.secret[h.guid] = true
		else h.failures.UnitGUID = true end
		h:run("waiting_identity")
		assert(#h.writes == 0 and not h.qt.db.global.gamepadLauncherCharacters, scenario)
		h.guid, h.region, h.secret, h.failures = "Player-1-1234", 1, {}, {}
		h:run("installed")
	end
end)

Test("missing APIs and invalid storage fail closed without consuming the attempt", function()
	for _, name in ipairs({ "CreateMacro", "GetMacroInfo", "PlaceAction", "C_GamepadUI", "GamepadActionBarBindingUtil", "C_KeyBindings", "Enum" }) do
		local h = Harness(); h.env[name] = nil
		h:run("waiting_api"); h:untouched()
	end
	for _, value in ipairs({ -1, 0, 1.5, 10001, "145", {} }) do
		local h = Harness(); h.replacements.StorageSlot = function() return value end
		h:run("waiting_storage"); h:untouched()
	end
	local h = Harness(); h.replacements.ValidStorage = function() return false end
	h:run("waiting_storage"); h:untouched()
end)

Test("normal setup creates the character macro with Blizzard's journal icon in page 1 slot 26 only", function()
	local h = Harness()
	local unrelated = { "spell", 99 }; h.actions[999] = unrelated
	h:run("installed")
	assert(#h.character == 1 and #h.account == 0)
	local macro = h.character[1]
	assert(macro.name == "QT PQL" and macro.icon == ICON_ID and macro.body == BODY)
	assert(h.actions[h.slot][1] == "macro" and h.actions[h.slot][2] == h.accountMax + 1)
	assert(h.actions[999] == unrelated and h.cursor == nil)
	assert(h:count("CreateMacro") == 1 and h:count("PickupMacro") == 1 and h:count("PlaceAction") == 1)
	assert(h:count("ClearCursor") == 0 and #h.errors == 0)
	assert(h:record().status == "installed")
	local status = h.qt:GetGamepadLauncherStatus(); status.status = "changed"
	assert(h:status() == "installed", "status exposed mutable private state")
end)

Test("custom trigger or D-pad assignments are preserved; unreadable bindings can retry", function()
	for _, key in ipairs({ "PADLTRIGGER", "PADRTRIGGER", "PADDUP" }) do
		local h = Harness(); h.bindings[key] = "USER_CUSTOM_ACTION"
		h:run("custom_bindings"); h:untouched()
	end
	local h = Harness(); h.failures.GetBindingByKey = true
	h:run("waiting_bindings"); h:untouched()
	h.failures.GetBindingByKey = nil; h:run("installed")
end)

Test("occupied slots never create macros and remain authoritative after removal/reload/profile changes", function()
	for _, kind in ipairs({ "spell", "item", "macro" }) do
		local h = Harness(); local action = { kind, 42 }; h.actions[h.slot] = action
		h:run("occupied")
		assert(h.actions[h.slot] == action and #h.writes == 0)
		h.actions[h.slot] = nil; h:noRetry("occupied")
	end
end)

Test("inconsistent, failed or secret action reads cannot be treated as empty", function()
	for _, scenario in ipairs({ "has", "secret", "error" }) do
		local h = Harness()
		if scenario == "has" then h.replacements.HasAction = function() return 0 end
		elseif scenario == "secret" then
			local token = {}; h.secret[token] = true
			h.replacements.GetActionInfo = function() return token end
		else h.failures.GetActionInfo = true end
		h:run("waiting_storage"); h:untouched()
	end
	local h = Harness(); h.replacements.HasAction = function() return true end
	h:run("occupied"); assert(#h.writes == 0)
end)

Test("a busy or unreadable cursor is preserved and an empty cursor permits a later retry", function()
	for _, kind in ipairs({ "item", "macro", "spell" }) do
		local h = Harness(); local cursor = { kind, 77 }; h.cursor = cursor
		h:run("waiting_cursor"); h:untouched(); assert(h.cursor == cursor)
		h.cursor = nil; h:run("installed")
	end
	local h = Harness(); h.failures.GetCursorInfo = true
	h:run("waiting_cursor"); h:untouched()
	h.failures.GetCursorInfo = nil; h:run("installed")
end)

Test("an existing launcher macro is preserved without placement even when capacity is full", function()
	local h = Harness(); h.characterMax = 1; h.env.Constants.MacroConsts.MAX_CHARACTER_MACROS = 1
	local macro = h:addMacro("QT PQL 3")
	h:run("macro_present")
	assert(h.character[1] == macro and not h.actions[h.slot])
	assert(#h.writes == 0 and #h.character == 1)
end)

Test("existing account or character launchers preserve names body icon and chosen placement", function()
	for _, account in ipairs({ false, true }) do
		for _, identity in ipairs({ { "QT PQL", "/say custom" }, { "QT PQL 9", "/say custom" }, { "My journal", BODY } }) do
			local h = Harness()
			local macro, index = h:addMacro(identity[1], identity[2], "UserIcon", account)
			h.actions[999] = { "macro", index }
			h:run("macro_present")
			assert(#h.writes == 0 and not h.actions[h.slot] and h.actions[999][2] == index)
			assert(macro.name == identity[1] and macro.body == identity[2] and macro.icon == "UserIcon")
			h:noRetry("macro_present")
		end
	end
end)

Test("existing reserved names and exhausted character capacity are non-destructive", function()
	local h = Harness()
	for suffix = 1, 9 do h:addMacro(suffix == 1 and "QT PQL" or "QT PQL " .. suffix, "/say mine", ICON, true) end
	h:run("macro_present"); assert(#h.writes == 0)
	h:noRetry("macro_present")
	h = Harness(); h.characterMax = 1; h.env.Constants.MacroConsts.MAX_CHARACTER_MACROS = 1
	h:addMacro("Other", "/say mine")
	h:run("macro_limit"); assert(#h.writes == 0)
	h.character = {}; h:noRetry("macro_limit")
end)

Test("macro scan failures or inaccessible values remain retryable before mutation", function()
	for _, scenario in ipairs({ "count", "info", "body", "limits" }) do
		local h = Harness(); local macro = h:addMacro("Mine", "/say mine")
		if scenario == "count" then h.failures.GetNumMacros = true
		elseif scenario == "info" then h.failures.GetMacroInfo = true
		elseif scenario == "body" then h.inaccessible[macro.body] = true
		else h.inaccessible[h.env.Constants.MacroConsts] = true end
		h:run("waiting_macros"); h:untouched()
		h.failures, h.inaccessible = {}, {}; h:run("installed")
	end
end)

Test("creation exceptions or untrusted return values never retry an uncertain mutation", function()
	for _, scenario in ipairs({ "error", "nil", "zero", "secret" }) do
		local h = Harness()
		if scenario == "error" then h.failures.CreateMacro = true
		else
			h.replacements.CreateMacro = function(name, icon, body)
				h:addMacro(name, body, icon)
				if scenario == "zero" then return 0 end
				if scenario == "secret" then local token = {}; h.secret[token] = true; return token end
			end
		end
		h:run("macro_creation_failed")
		assert(h:count("PickupMacro") == 0 and h:count("PlaceAction") == 0 and #h.errors == 1)
		h.failures, h.replacements = {}, {}; h:noRetry("macro_creation_failed")
		assert(h:count("CreateMacro") == 1 and #h.errors == 1)
	end
end)

Test("created macro readback must match name/body and have a readable icon", function()
	for _, field in ipairs({ "name", "body", "icon", "secret" }) do
		local h = Harness()
		h:once("after", "CreateMacro", function()
			if field == "secret" then h.secret[h.character[1].body] = true
			else h.character[1][field] = field == "icon" and {} or "unexpected" end
		end)
		h:run("macro_creation_unverified")
		assert(h:count("PickupMacro") == 0 and h:count("PlaceAction") == 0)
		h.secret = {}; h:noRetry("macro_creation_unverified")
	end
	local h = Harness(); h.normalizedIcon = ICON .. ".blp"
	h:run("installed"); assert(h.character[1].icon == ICON .. ".blp")
	h = Harness(); h.normalizedIcon = 12345
	h:run("macro_creation_unverified"); assert(h:count("PlaceAction") == 0)
end)

Test("namespaced action reads work without deprecated globals and take precedence", function()
	local h = Harness(); h.env.HasAction = nil; h:run("installed")
	h = Harness(); h.env.HasAction = function() error("deprecated API was used") end
	h:run("installed")
	h = Harness(); h.env.C_ActionBar = nil; h:run("installed")
	h = Harness(); h.env.C_ActionBar = nil; h.env.HasAction = nil
	h:run("waiting_api"); h:untouched()
end)

Test("journal icon resolution requires a shipped ID and rejects loose or inaccessible IDs", function()
	for _, id in ipairs({ ICON_ID, 12345 }) do
		local h = Harness(); h.iconID = id; h:run("installed")
		assert(h.character[1].icon == id)
	end
	for _, id in ipairs({ -2925, 0, 1.5, -1.5, math.huge, -math.huge, "-2925", {} }) do
		local h = Harness(); h.iconID = id; h:run("waiting_icon"); h:untouched()
	end
	local h = Harness(); h.secret[ICON_ID] = true; h:run("waiting_icon"); h:untouched()
	h = Harness(); h.failures.GetFileIDFromPath = true; h:run("waiting_icon"); h:untouched()
	h = Harness(); h.env.C_UIFileAsset = { GetFileID = h.env.GetFileIDFromPath }; h.env.GetFileIDFromPath = nil
	h:run("installed")
end)

Test("changing the default icon never repairs or reasserts an earlier prototype's macro", function()
	for _, saved in ipairs({ "macro_creation_unverified", "macro_recovery_cancelled", "macro_recovery_unverified", "installed" }) do
		for _, manual in ipairs({ false, true }) do
			local h = Harness(); local macro, index = h:addMacro("QT PQL")
			macro.icon = manual and 134400 or nil
			local action = manual and { "macro", index } or nil; h.actions[h.slot] = action
			h.qt.db.global.gamepadLauncherCharacters = { ["forever:1:Player-1-1234"] = { status = saved } }
			h:run("macro_present"); assert(#h.writes == 0 and h.actions[h.slot] == action)
			assert(macro.icon == (manual and 134400 or nil))
			h:noRetry("macro_present")
		end
	end
end)

Test("creation callbacks observe saved intent and cannot reenter installation", function()
	local h = Harness()
	h:once("after", "CreateMacro", function()
		assert(h:record().status == "installing", "intent was not saved before mutation")
		h:updateMacros(); h:updateSlot()
		assert(h.qt:TryInstallDefaultGamepadLauncher() == false, "reentrant install was allowed")
	end)
	h:run("installed")
	assert(h:count("CreateMacro") == 1 and h:count("PickupMacro") == 1 and h:count("PlaceAction") == 1)
end)

Test("slot occupancy is rechecked before creation and again after creation callbacks", function()
	local h = Harness(); local external = { "spell", 987 }
	h.before.GetActionInfo = function()
		if h:count("GetActionInfo") == 2 then h.actions[h.slot] = external end
	end
	h:run("cancelled"); assert(#h.writes == 0 and h.actions[h.slot] == external)
	h.actions[h.slot] = nil; h:noRetry("cancelled")
	h = Harness()
	h:once("after", "CreateMacro", function() h.actions[h.slot] = external end)
	h:run("cancelled")
	assert(h.actions[h.slot] == external and h:count("CreateMacro") == 1)
	assert(h:count("PickupMacro") == 0 and h:count("PlaceAction") == 0)
	h.actions[h.slot] = nil; h:noRetry("cancelled")
end)

Test("restriction, mode and cursor changes during creation cancel without disturbing the cursor", function()
	for _, scenario in ipairs({ "restricted", "combat", "mode", "cursor" }) do
		local h = Harness(); local foreign = { "item", 887 }
		h:once("after", "CreateMacro", function()
			if scenario == "restricted" then h.restricted = true
			elseif scenario == "combat" then h.combat = true
			elseif scenario == "mode" then h.mode = false
			else h.cursor = foreign end
		end)
		h:run("cancelled")
		assert(h:count("PickupMacro") == 0 and h:count("PlaceAction") == 0 and h:count("ClearCursor") == 0)
		if scenario == "cursor" then assert(h.cursor == foreign) end
		h.restricted, h.combat, h.mode, h.cursor = false, false, true, nil
		h:noRetry("cancelled")
	end
end)

Test("new macro indices are resolved again after creation and readback callbacks", function()
	local h = Harness(); h:addMacro("Other", "/say mine")
	h:once("after", "CreateMacro", function()
		h:once("after", "GetMacroInfo", function() table.remove(h.character, 1) end)
	end)
	h:run("installed")
	assert(#h.character == 1 and h.character[1].name == "QT PQL" and h.actions[h.slot][2] == h.accountMax + 1)
end)

Test("pickup failures clear only a proven owned cursor and never place", function()
	local h = Harness(); h.failures.PickupMacro = true
	h:run("pickup_failed")
	assert(h:count("PlaceAction") == 0 and h:count("ClearCursor") == 0)
	h.failures = {}; h:noRetry("pickup_failed")
	h = Harness()
	h:once("after", "PickupMacro", function() error("pickup failed after setting own cursor") end)
	h:run("pickup_failed")
	assert(h:count("PlaceAction") == 0 and h:count("ClearCursor") == 1 and h.cursor == nil)
end)

Test("unexpected or unreadable pickup cursors are preserved", function()
	for _, scenario in ipairs({ "item", "foreign_macro", "unreadable" }) do
		local h = Harness(); local foreign = { scenario == "foreign_macro" and "macro" or "item", 999 }
		h:once("after", "PickupMacro", function()
			h.cursor = foreign
			if scenario == "unreadable" then h.failures.GetCursorInfo = true end
		end)
		h:run("pickup_failed")
		assert(h.cursor == foreign and h:count("ClearCursor") == 0 and h:count("PlaceAction") == 0)
		h.failures = {}; h:noRetry("pickup_failed")
	end
end)

Test("slot changes or macro index compaction during pickup cancel before placement", function()
	local h = Harness(); local external = { "item", 987 }
	h:once("after", "PickupMacro", function() h.actions[h.slot] = external end)
	h:run("cancelled")
	assert(h.actions[h.slot] == external and h:count("PlaceAction") == 0 and h.cursor == nil)
	assert(h:count("ClearCursor") == 1)
	h = Harness(); h:addMacro("Other", "/say mine")
	h:once("after", "CreateMacro", function() h:addMacro("Foreign", "/say foreign") end)
	h:once("after", "PickupMacro", function() table.remove(h.character, 1) end)
	h:run("cancelled")
	assert(h:count("PlaceAction") == 0 and h.character[1].name == "QT PQL")
	assert(h.cursor and h.cursor[2] == h.accountMax + 2 and h:macro(h.cursor[2]).name == "Foreign")
	assert(h:count("ClearCursor") == 0, "index compaction was mistaken for proof of cursor ownership")
end)

Test("identity, database, storage and mapping changes during mutation invalidate the attempt", function()
	for _, phase in ipairs({ "CreateMacro", "PickupMacro" }) do
		for _, scenario in ipairs({ "guid", "region", "profile", "global", "storage", "binding" }) do
			local h = Harness(); local global, profile = h.qt.db.global, h.qt.db.profile
			h:once("after", phase, function()
				if scenario == "guid" then h.guid = "Player-1-5678"
				elseif scenario == "region" then h.region = 2
				elseif scenario == "profile" then h.qt.db.profile = {}
				elseif scenario == "global" then h.qt.db.global = {}
				elseif scenario == "storage" then h.replacements.StorageSlot = function() return h.slot + 28 end
				else h.bindings.PADLTRIGGER = "USER_CUSTOM_ACTION" end
			end)
			h:run("cancelled")
			assert(h:count("PlaceAction") == 0, phase .. ":" .. scenario)
			if phase == "CreateMacro" then assert(h:count("PickupMacro") == 0) end
			h.guid, h.region, h.qt.db.global, h.qt.db.profile = "Player-1-1234", 1, global, profile
			h.replacements, h.bindings.PADLTRIGGER = {}, "GAMEPADLEFTMOD"
			h:noRetry("cancelled")
		end
	end
end)

Test("restriction during pickup prevents placement and cursor cleanup until a separate user action", function()
	local h = Harness()
	h:once("after", "PickupMacro", function() h.restricted = true end)
	h:run("cancelled")
	assert(h.cursor and h.cursor[1] == "macro" and h:count("PlaceAction") == 0 and h:count("ClearCursor") == 0)
	h.restricted = false; h:noRetry("cancelled")
	assert(h.cursor and h:count("ClearCursor") == 0, "later event modified the user's cursor")
end)

Test("placement failures and unverifiable readback are never retried", function()
	for _, scenario in ipairs({ "error", "noop", "post_error", "read_error", "secret" }) do
		local h = Harness()
		if scenario == "error" then h.failures.PlaceAction = true
		elseif scenario == "noop" then h.replacements.PlaceAction = function() end
		else h:once("after", "PlaceAction", function()
			if scenario == "post_error" then error("placement error after mutation")
			elseif scenario == "read_error" then h.failures.GetActionInfo = true
			else h.secret[h.actions[h.slot][2]] = true end
		end) end
		h:run("placement_unverified")
		assert(h:count("PlaceAction") == 1 and #h.errors == 1)
		h.failures, h.secret, h.replacements = {}, {}, {}; h:noRetry("placement_unverified")
	end
end)

Test("a foreign cursor returned by placement is preserved, including a displaced action", function()
	local h = Harness(); local foreign = { "item", 456 }
	h:once("after", "PlaceAction", function() h.cursor = foreign end)
	h:run("installed")
	assert(h.cursor == foreign and h:count("ClearCursor") == 0)
	h = Harness()
	-- A foreign hook between the final read and the native call cannot be made
	-- atomic by this addon. Do not destroy the displaced action on the cursor.
	h:once("before", "PlaceAction", function() h.actions[h.slot] = foreign end)
	h:run("installed")
	assert(h.cursor == foreign and h:count("ClearCursor") == 0)
end)

Test("unbinding moving or editing an existing launcher never reasserts its old placement", function()
	for _, scenario in ipairs({ "remove", "replace", "move", "body", "icon", "rename" }) do
		local h = Harness(); h:run("installed")
		if scenario == "remove" then h.actions[h.slot] = nil
		elseif scenario == "replace" then h.actions[h.slot] = { "spell", 42 }
		elseif scenario == "move" then h.actions[999], h.actions[h.slot] = h.actions[h.slot], nil
		elseif scenario == "body" then h.character[1].body = "/say my edited macro"
		elseif scenario == "icon" then h.character[1].icon = 134400
		else h.character[1].name = "My journal" end
		local action = h.actions[h.slot]
		h:updateMacros(); h:run("macro_present")
		h:noRetry("macro_present")
		assert(h.actions[h.slot] == action and h:count("CreateMacro") == 1)
		if scenario == "body" then assert(h.character[1].body == "/say my edited macro") end
		if scenario == "move" then assert(h.actions[999][2] == h.accountMax + 1) end
	end
end)

Test("a saved in-progress attempt is not permission to repair after reload", function()
	local h = Harness()
	h.qt.db.global.gamepadLauncherCharacters = { ["forever:1:Player-1-1234"] = { status = "installing", schema = 3, observed = false } }
	h:run("installing"); assert(#h.writes == 0)
	h:noRetry("installing")
end)

Test("definite launcher deletion recreates once on macro updates and after reload", function()
	for _, reload in ipairs({ false, true }) do
		local h = Harness(); h:run("installed")
		h:deleteCharacterMacro(1)
		if reload then h:reload() else h:updateMacros() end
		h:run("installed")
		assert(#h.character == 1 and h.character[1].body == BODY)
		assert(h:count("CreateMacro") == 2 and h:count("PlaceAction") == 2)
		for _ = 1, 4 do h:updateMacros(); h:run("macro_present") end
		assert(h:count("CreateMacro") == 2 and h:count("PlaceAction") == 2)
	end
	local h = Harness(); h:run("installed")
	for deletion = 1, 4 do
		h:deleteCharacterMacro(1); h:updateMacros(); h:run("installed")
		assert(h:count("CreateMacro") == deletion + 1 and #h.character == 1)
	end
end)

Test("deleting an adopted account launcher permits one character setup without touching other macros", function()
	local h = Harness()
	h:addMacro("My journal", BODY, "PersonalIcon", true)
	local other = h:addMacro("Other", "/say unchanged")
	h:run("macro_present")
	assert(#h.writes == 0)
	h.account = {}; h:updateMacros(); h:run("installed")
	assert(#h.account == 0 and #h.character == 2 and h.character[1] == other)
	assert(h.character[2].name == "QT PQL" and h:count("CreateMacro") == 1 and h:count("PlaceAction") == 1)
end)

Test("renamed then edited macros and ambiguous combined customization remain untouched", function()
	local h = Harness(); h:run("installed")
	h.character[1].name = "Personal journal"
	h:updateMacros(); h:run("macro_present")
	h.character[1].body, h.character[1].icon = "/say changed", "PersonalIcon"
	h:updateMacros(); h:run("macro_present")
	h:noRetry("macro_present")
	assert(h:count("CreateMacro") == 1 and h.character[1].body == "/say changed")
	h = Harness(); h:run("installed")
	h.character[1].name, h.character[1].body, h.character[1].icon = "Personal", "/say changed", "PersonalIcon"
	h.actions[h.slot] = nil
	h:updateMacros(); h:run("macro_customized")
	assert(h:count("CreateMacro") == 1 and h:count("PlaceAction") == 1)
	-- A later unrelated macro-count change must not reinterpret the retired
	-- ambiguous customization as proof that the original launcher was deleted.
	h.character = {}; h:updateMacros(); h:noRetry("macro_customized")
	h = Harness(); h:run("installed")
	h:record().macroCount = nil
	h:deleteCharacterMacro(1); h:updateMacros(); h:run("macro_customized")
	assert(h:count("CreateMacro") == 1 and h:count("PlaceAction") == 1,
		"missing observation metadata was treated as proof of macro deletion")
	h:noRetry("macro_customized")
	h = Harness(); h:run("installed")
	h.character[1].name, h.character[1].body = "Personal", "/say changed"
	h:updateMacros(); h:run("macro_customized")
	h.character[1].name = "QT PQL"
	h:updateMacros(); h:run("macro_present")
	assert(not h:record().retired, "positive recognition did not resume deletion tracking")
	h:deleteCharacterMacro(1); h:updateMacros(); h:run("installed")
	assert(h:count("CreateMacro") == 2 and h:count("PlaceAction") == 2)
end)

Test("deletion preserves occupied slots and installs only after a later empty-slot event", function()
	local h = Harness(); h:run("installed")
	h:deleteCharacterMacro(1)
	local foreign = { "spell", 99 }; h.actions[h.slot] = foreign
	h:updateMacros(); h:run("waiting_slot")
	assert(h.actions[h.slot] == foreign and h:count("CreateMacro") == 1 and #h.character == 0)
	for _ = 1, 4 do h.qt:TryInstallDefaultGamepadLauncher() end
	assert(h:count("CreateMacro") == 1 and h:count("PlaceAction") == 1)
	h.actions[h.slot] = nil; h:updateSlot(); h:run("installed")
	assert(h:count("CreateMacro") == 2 and h:count("PlaceAction") == 2)
	h = Harness(); h:run("installed"); h:deleteCharacterMacro(1)
	h.actions[h.slot] = foreign; h:updateMacros(); h:run("waiting_slot")
	h:reload(); h:run("waiting_slot")
	h.actions[h.slot] = nil; h:updateSlot(); h:run("installed")
	assert(h:count("CreateMacro") == 2)
end)

Test("legacy records adopt present macros or receive one fresh setup when absent", function()
	for _, status in ipairs({ "installed", "occupied", "installing", "macro_creation_unverified", "pickup_failed" }) do
		local h = Harness()
		h.qt.db.global.gamepadLauncherCharacters = { ["forever:1:Player-1-1234"] = { status = status } }
		h:run("installed")
		assert(h:count("CreateMacro") == 1 and h:record().schema == 3)
		h = Harness(); local macro = h:addMacro("Renamed journal", BODY, "PersonalIcon")
		h.qt.db.global.gamepadLauncherCharacters = { ["forever:1:Player-1-1234"] = { status = status } }
		h:run("macro_present")
		assert(#h.writes == 0 and h.character[1] == macro)
	end
end)

Test("failed fresh or replacement creation cannot loop through macro and slot events", function()
	for _, replacing in ipairs({ false, true }) do
		local h = Harness()
		if replacing then h:run("installed"); h:deleteCharacterMacro(1); h:updateMacros() end
		h.failures.CreateMacro = true; h:run("macro_creation_failed")
		local attempts = h:count("CreateMacro")
		h.failures.CreateMacro = nil
		for _ = 1, 5 do h:updateMacros(); h:updateSlot(); h:run("macro_creation_failed") end
		h:noRetry("macro_creation_failed")
		assert(h:count("CreateMacro") == attempts and #h.character == 0 and #h.errors == 1)
	end
end)

Test("deleted macro zero ghosts are cleared once before safe recreation", function()
	local h = Harness(); h:run("installed")
	h:deleteCharacterMacro(1, true); h:updateMacros(); h:run("installed")
	assert(h:count("PickupAction") == 1 and h:count("CreateMacro") == 2)
	assert(h.actions[h.slot][1] == "macro" and h.actions[h.slot][2] == h.accountMax + 1)
	assert(h.cursor == nil)
	for _, action in ipairs({ { "macro", 42 }, { "spell", 0 }, { "item", 0 } }) do
		h = Harness(); h:run("installed"); h:deleteCharacterMacro(1)
		h.actions[h.slot] = action; h:updateMacros(); h:run("waiting_slot")
		assert(h:count("PickupAction") == 0 and h.actions[h.slot] == action and h:count("CreateMacro") == 1)
	end
end)

Test("ghost cleanup respects restrictions busy cursors and displaced foreign actions", function()
	for _, scenario in ipairs({ "combat", "restricted", "cursor" }) do
		local h = Harness(); h:run("installed"); h:deleteCharacterMacro(1, true)
		local foreign = { "item", 88 }
		if scenario == "combat" then h.combat = true
		elseif scenario == "restricted" then h.restricted = true
		else h.cursor = foreign end
		h:updateMacros(); h.qt:TryInstallDefaultGamepadLauncher()
		assert(h:count("PickupAction") == 0 and h:count("CreateMacro") == 1)
		if scenario == "cursor" then assert(h.cursor == foreign) end
	end
	local h = Harness(); h:run("installed"); h:deleteCharacterMacro(1, true)
	local foreign = { "spell", 123 }
	h:once("before", "PickupAction", function() h.actions[h.slot] = foreign end)
	h:updateMacros(); h.qt:TryInstallDefaultGamepadLauncher()
	assert(h.cursor == foreign and h:count("ClearCursor") == 0)
	assert(h:count("CreateMacro") == 1 and h:count("PlaceAction") == 1)
	h:updateMacros(); h.qt:TryInstallDefaultGamepadLauncher()
	assert(h.cursor == foreign and h:count("ClearCursor") == 0)
end)

Test("failed ghost cleanup remains terminal and preserves unknown cursor contents", function()
	for _, scenario in ipairs({ "error", "noop", "post_error", "foreign_macro", "missing_api" }) do
		local h = Harness(); h:run("installed"); h:deleteCharacterMacro(1, true)
		if scenario == "error" then h.failures.PickupAction = true
		elseif scenario == "noop" then h.replacements.PickupAction = function() end
		elseif scenario == "missing_api" then h.env.PickupAction = nil
		else h:once("after", "PickupAction", function()
			if scenario == "post_error" then error("unknown native cleanup outcome") end
			h.cursor = { "macro", 77 }
		end) end
		h:updateMacros(); h:run(scenario == "missing_api" and "waiting_api" or "stale_slot_unverified")
		assert(h:count("CreateMacro") == 1 and h:count("PlaceAction") == 1 and h:count("ClearCursor") == 0)
		if scenario == "foreign_macro" then assert(h.cursor and h.cursor[2] == 77) end
		if scenario ~= "missing_api" then
			local attempts = h:count("PickupAction")
			h.failures, h.replacements = {}, {}
			h:updateMacros(); h:updateSlot(); h:noRetry("stale_slot_unverified")
			assert(h:count("PickupAction") == attempts)
		end
	end
end)

Test("macro deletion events still obey all native and runtime preflight gates", function()
	for _, scenario in ipairs({ "mode", "disabled", "world", "combat", "restricted", "login", "cursor" }) do
		local h = Harness(); h:run("installed"); h:deleteCharacterMacro(1)
		local foreign = { "item", 18 }
		if scenario == "mode" then h.mode = false
		elseif scenario == "disabled" then h.native.enabled = false
		elseif scenario == "world" then h.native.worldReady = false
		elseif scenario == "combat" then h.combat = true
		elseif scenario == "restricted" then h.restricted = true
		elseif scenario == "login" then h.loggedIn = false
		else h.cursor = foreign end
		h:updateMacros(); h.qt:TryInstallDefaultGamepadLauncher()
		assert(h:count("CreateMacro") == 1 and h:count("PlaceAction") == 1)
		if scenario == "cursor" then assert(h.cursor == foreign) end
		h.mode, h.native.enabled, h.native.worldReady, h.combat, h.restricted, h.loggedIn, h.cursor = true, true, true, false, false, true, nil
		h:updateMacros(); h:run("installed")
		assert(h:count("CreateMacro") == 2 and h:count("PlaceAction") == 2)
	end
end)

Test("unexpected owner exceptions fail-stop for the current session without repeated diagnostics", function()
	local h = Harness(); local original = h.qt.GetGamepadIntegrationStatus
	h.qt.GetGamepadIntegrationStatus = function() error("owner failure") end
	h:run("failed"); assert(#h.writes == 0 and #h.errors == 1)
	h.qt.GetGamepadIntegrationStatus = original
	h:run("failed"); assert(#h.writes == 0 and #h.errors == 1)
end)

print(string.format("Gamepad launcher offline checks: %d passed, %d failed", passed, #failures))
assert(#failures == 0, table.concat(failures, "\n"))
