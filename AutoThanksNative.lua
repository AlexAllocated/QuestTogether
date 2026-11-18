-- SPDX-License-Identifier: GPL-3.0-only
-- Native aura provenance and directed emotes. No Blizzard state is modified.
local QT = _G.QuestTogether
local GRATITUDE = { thank = true, bow = true, applaud = true }
local MAX_AURAS = 256

-- The factory accepts private functions so native contracts can be exercised
-- offline without replacing client globals or shared C_* tables.
function QT:CreateAutoThanksNativeAdapter(native)
	local addon = self
	local function Accessible(value)
		return addon:CanAccessValue(value)
	end
	local function Text(value, limit)
		return Accessible(value) and type(value) == "string" and #value > 0
			and #value <= limit and value:find("%S") and not value:find("[%c|]") and value or nil
	end
	local function PlayerGUID(value)
		local guid = Text(value, 48)
		return guid and guid:match("^Player%-%d+%-%x+$") and guid or nil
	end
	local function Function(value)
		return Accessible(value) and type(value) == "function"
	end
	local function Call(fn, ...)
		if not Function(fn) then return false end
		return pcall(fn, ...)
	end
	local function Ready()
		if addon.isRunningTests or addon.isLoggingOut or addon.isLeavingWorld or not addon.isEnabled
			or addon.suppressLocalAnnouncementDisplayDuringTests then return false end
		local ok, enabled = Call(addon.GetOption, addon, "autoThankBuffs")
		if not ok or not Accessible(enabled) or enabled ~= true then return false end
		local restricted
		ok, restricted = Call(addon.IsRuntimeRestricted, addon)
		if not ok or not Accessible(restricted) or restricted ~= false then return false end
		ok, restricted = Call(addon.IsRuntimeRestrictionTypeActive, addon, "chat")
		return ok and Accessible(restricted) and restricted == false
	end
	local function OwnGUID()
		local ok, guid = Call(native.UnitGUID, "player")
		return ok and PlayerGUID(guid) or nil
	end
	local function RegionalNames()
		local getter = native.RegionalUniqueNamesEnabled
		if not Accessible(getter) then return nil end
		if getter == nil then return false end
		local ok, regional = Call(getter)
		if ok and Accessible(regional) and type(regional) == "boolean" then return regional end
	end
	local function UnitIdentity(unit, ownGUID)
		if not Text(unit, 128) then return nil, nil, false end
		local ok, player = Call(native.UnitIsPlayer, unit)
		if not ok or not Accessible(player) or type(player) ~= "boolean" then return nil, nil, false end
		if not player then return nil, nil, true end
		local guid
		ok, guid = Call(native.UnitGUID, unit)
		if not ok or not Accessible(guid) then return nil, nil, false end
		guid = PlayerGUID(guid)
		if not guid or guid == ownGUID then return nil, nil, true end
		local name
		ok, name = Call(addon.GetUnitFullName, addon, unit)
		if not ok or not Accessible(name) then return nil, nil, false end
		return guid, Text(name, 128), true
	end
	local function GUIDName(guid)
		local ok, _, _, _, _, _, name, realm = Call(native.GetPlayerInfoByGUID, guid)
		if not ok or not Text(name, 128) or not Accessible(realm) then return nil end
		local regional = RegionalNames()
		if regional == nil then return nil end
		if regional then
			-- The GUID API's seventh result is documented as realmName, not
			-- surname. Require a complete returned regional identity instead
			-- of guessing how to combine an ambiguous first name and realm.
			ok, name = Call(addon.NormalizeMemberName, addon, name)
			name = ok and Text(name, 128) or nil
			return name and name:match("^%S+ +%S") and name or nil
		end
		if type(realm) ~= "string" or #realm > 128 or realm:find("[%c|]") then return nil end
		if realm ~= "" then name = name .. "-" .. realm end
		ok, name = Call(addon.NormalizeMemberName, addon, name)
		return ok and Text(name, 128) or nil
	end
	local function ResolvedUnit(guid)
		local getter = native.UnitTokenFromGUID
		if not Accessible(getter) then return nil, false end
		if getter == nil then return nil, true end
		local ok, unit = Call(getter, guid)
		if not ok or not Accessible(unit) then return nil, false end
		if unit == nil then return nil, true end
		unit = Text(unit, 128)
		return unit, unit ~= nil
	end
	local function ReadAuras()
		if not Ready() or not Function(native.GetAuraDataByIndex) then return nil end
		local ownGUID = OwnGUID()
		if not ownGUID then return nil end
		local rows, seen = {}, {}
		for index = 1, MAX_AURAS + 1 do
			local ok, aura = Call(native.GetAuraDataByIndex, "player", index, "HELPFUL")
			if not ok or not Accessible(aura) then return nil end
			if aura == nil then return rows end
			if index > MAX_AURAS or not addon:CanAccessTable(aura) then return nil end
			local id, helpful, duration, source = aura.auraInstanceID, aura.isHelpful, aura.duration, aura.sourceUnit
			if not Accessible(id) or not Accessible(helpful) or not Accessible(duration)
				or not Accessible(source) then return nil end
			if type(id) ~= "number" or id <= 0 or id == math.huge or id ~= math.floor(id)
				or seen[id] or type(helpful) ~= "boolean" then return nil end
			seen[id] = true
			if helpful then
				if duration ~= nil and (type(duration) ~= "number" or duration ~= duration
					or duration < 0 or duration == math.huge) then return nil end
				if source ~= nil and not Text(source, 128) then return nil end
				local guid, name, complete, unit
				if source then
					guid, name, complete = UnitIdentity(source, ownGUID)
					if not complete then return nil end
					if guid then unit = source end
				end
				if source == nil and Function(native.GetAuraCasterGUID) then
					local caster
					ok, caster = Call(native.GetAuraCasterGUID, "player", id)
					if not ok or not Accessible(caster) then return nil end
					guid = PlayerGUID(caster)
					if guid == ownGUID then guid = nil end
					if guid then
						local resolved, resolvedComplete = ResolvedUnit(guid)
						if not resolvedComplete then return nil end
						if resolved then
							local resolvedGUID, resolvedName
							resolvedGUID, resolvedName, complete = UnitIdentity(resolved, ownGUID)
							if not complete then return nil end
							if resolvedGUID == guid then unit, name = resolved, resolvedName end
						end
						name = name or GUIDName(guid)
					end
				end
				-- Keep unresolved instances in the baseline. Late identification
				-- alone must not turn an existing buff into a new social action.
				rows[#rows + 1] = { id = id, guid = guid, unit = unit, duration = duration, name = name }
			end
		end
	end
	local function Target(guid, unit, name)
		if not Ready() or not PlayerGUID(guid) or not Accessible(unit) or not Accessible(name) then return nil end
		if unit ~= nil and not Text(unit, 128) then return nil end
		if name ~= nil and not Text(name, 128) then return nil end
		local ownGUID = OwnGUID()
		if not ownGUID or guid == ownGUID then return nil end
		if unit then
			local currentGUID, currentName, complete = UnitIdentity(unit, ownGUID)
			if not complete then return nil end
			if currentGUID == guid and currentName then return currentName end
		end
		local resolved, resolvedComplete = ResolvedUnit(guid)
		if not resolvedComplete then return nil end
		if resolved then
			local currentGUID, currentName, complete = UnitIdentity(resolved, ownGUID)
			if not complete then return nil end
			if currentGUID == guid and currentName then return currentName end
		end
		local currentName = GUIDName(guid)
		if currentName and (name == nil or name == currentName) then return currentName end
	end
	local function Perform(token, target)
		if not Ready() or not Text(token, 16) or not GRATITUDE[token] or not Text(target, 128) then return false end
		-- A failed friend-list read is not evidence that the recipient is
		-- allowed. Preserve the shared wrapper's semantics elsewhere.
		local ok, ignored = Call(native.IsOnIgnoredList, target)
		if not ok or not Accessible(ignored) or ignored ~= false then return false end
		local perform = native.PerformEmote
		if not Function(perform) then perform = native.DoEmote end
		-- Native docs and the native chat parser disagree about the returned
		-- boolean. Report only a nonthrowing attempt, never confirmed delivery.
		ok = Call(perform, token:upper(), target)
		return ok
	end
	return {
		GetAutoThanksAuras = function()
			local ok, rows = pcall(ReadAuras)
			return ok and rows or nil
		end,
		GetAutoThanksTarget = function(guid, unit, name)
			local ok, target = pcall(Target, guid, unit, name)
			return ok and target or nil
		end,
		PerformAutoThanks = function(token, target)
			local ok, attempted = pcall(Perform, token, target)
			return ok and attempted == true
		end,
	}
end

local function Capability(namespace, key)
	if not QT:CanAccessTable(namespace) then return nil end
	local ok, fn = pcall(function() return namespace[key] end)
	if ok and QT:CanAccessValue(fn) and type(fn) == "function" then return fn end
end

local adapter = QT:CreateAutoThanksNativeAdapter({
	GetAuraDataByIndex = Capability(C_UnitAuras, "GetAuraDataByIndex"),
	GetAuraCasterGUID = Capability(C_UnitAuras, "GetAuraCasterGUID"),
	UnitGUID = UnitGUID,
	UnitIsPlayer = UnitIsPlayer,
	UnitTokenFromGUID = UnitTokenFromGUID,
	GetPlayerInfoByGUID = GetPlayerInfoByGUID,
	RegionalUniqueNamesEnabled = RegionalUniqueNamesEnabled,
	IsOnIgnoredList = Capability(C_FriendList, "IsOnIgnoredList"),
	PerformEmote = Capability(C_ChatInfo, "PerformEmote"),
	DoEmote = DoEmote,
})
for name, fn in pairs(adapter) do QT.API[name] = fn end
