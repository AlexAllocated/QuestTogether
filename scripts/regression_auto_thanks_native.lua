-- SPDX-License-Identifier: GPL-3.0-only
-- Native contract fixtures only; no game globals, shared tables, or live output.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local OWN, FRIEND, OTHER = "Player-1-AA", "Player-2-BB", "Player-3-CC"

local function Fixture()
	local h = { secret = {}, inaccessibleTable = {}, auras = {}, casters = {},
		units = { player = OWN, party1 = FRIEND }, names = { party1 = "Friend-Realm" },
		guidNames = {}, emotes = {}, reads = 0, identityReads = 0, options = { autoThankBuffs = true } }
	local a = { isEnabled = true }
	function a:CanAccessValue(value) return value ~= h.secret end
	function a:CanAccessTable(value)
		return type(value) == "table" and value ~= h.secret and value ~= h.inaccessibleTable
	end
	function a:GetOption(key) return h.options[key] end
	function a:IsRuntimeRestricted() return h.restricted or false end
	function a:IsRuntimeRestrictionTypeActive(kind) Equal(kind, "chat"); return h.chatRestricted or false end
	function a:GetUnitFullName(unit) return h.names[unit] end
	function a:NormalizeMemberName(name)
		if h.regional then return (name:gsub("-", " ")) end
		return name:find("-", 1, true) and name or name .. "-Realm"
	end
	local n = {
		GetAuraDataByIndex = function(unit, index, filter)
			Equal(unit, "player"); Equal(filter, "HELPFUL")
			h.reads = h.reads + 1
			return h.auras[index]
		end,
		GetAuraCasterGUID = function(unit, id) Equal(unit, "player"); return h.casters[id] end,
		UnitGUID = function(unit) h.identityReads = h.identityReads + 1; return h.units[unit] end,
		UnitIsPlayer = function(unit)
			local guid = h.units[unit]
			return type(guid) == "string" and guid:match("^Player%-") ~= nil
		end,
		UnitTokenFromGUID = function(guid)
			for unit, current in pairs(h.units) do if current == guid then return unit end end
		end,
		GetPlayerInfoByGUID = function(guid)
			local info = h.guidNames[guid]
			if info then return "Mage", "MAGE", "Human", "Human", 2, info.name, info.realm end
		end,
		RegionalUniqueNamesEnabled = function() return h.regional or false end,
		IsOnIgnoredList = function() return false end,
		PerformEmote = function(token, target)
			h.emotes[#h.emotes + 1] = { token = token, target = target }
			return false
		end,
	}
	h.addon, h.native = a, n
	h.api = QT.CreateAutoThanksNativeAdapter(a, n)
	function h:Aura(id, source)
		local row = { auraInstanceID = id, isHelpful = true, duration = 1800, sourceUnit = source }
		self.auras[#self.auras + 1] = row
		return row
	end
	return h
end

QT:RegisterTest("auto thanks native snapshots copy helpful player provenance", function()
	local h = Fixture()
	local raw = h:Aura(1, "party1")
	local rows = assert(h.api.GetAutoThanksAuras())
	Equal(#rows, 1); Equal(rows[1].id, 1); Equal(rows[1].guid, FRIEND)
	Equal(rows[1].unit, "party1"); Equal(rows[1].name, "Friend-Realm"); Equal(rows[1].duration, 1800)
	raw.duration, raw.auraInstanceID = 90, 2
	Equal(rows[1].duration, 1800); Equal(rows[1].id, 1)
	Equal(h.api.GetAutoThanksTarget(FRIEND, "party1", "Friend-Realm"), "Friend-Realm")
	Equal(h.units.party1, FRIEND)
end, { offline = true })

QT:RegisterTest("auto thanks native excludes self NPC pet and malformed caster identities", function()
	local h = Fixture()
	h.units.npc, h.units.pet, h.units.bad = "Creature-0-12", "Pet-0-23", "Player-not-valid"
	for id, unit in ipairs({ "player", "npc", "pet", "bad" }) do
		h:Aura(id, unit)
		-- An explicit source is authoritative; never reinterpret its rejected
		-- identity as a different player through an optional fallback.
		h.casters[id] = OTHER
	end
	local rows = assert(h.api.GetAutoThanksAuras())
	Equal(#rows, 4)
	for _, row in ipairs(rows) do Equal(row.guid, nil); Equal(row.unit, nil) end
	Equal(h.api.GetAutoThanksTarget(OWN, "player", nil), nil)
	Equal(h.api.GetAutoThanksTarget("Creature-0-12", "npc", nil), nil)
end, { offline = true })

QT:RegisterTest("auto thanks native rejects inaccessible aura fields and foreign tables", function()
	for _, field in ipairs({ "auraInstanceID", "isHelpful", "duration", "sourceUnit" }) do
		local h = Fixture(); h:Aura(1, "party1")[field] = h.secret
		Equal(h.api.GetAutoThanksAuras(), nil)
	end
	for _, kind in ipairs({ "secret", "inaccessibleTable" }) do
		local h = Fixture(); h.auras[1] = h[kind]
		Equal(h.api.GetAutoThanksAuras(), nil)
	end
	local h = Fixture()
	h.auras[1] = setmetatable({}, { __index = function() error("unreadable field") end })
	Equal(h.api.GetAutoThanksAuras(), nil)
end, { offline = true })

QT:RegisterTest("auto thanks native rejects secret unit results without exposing them", function()
	local h = Fixture(); h:Aura(1, "party1")
	h.native.UnitIsPlayer = function() return h.secret end
	Equal(h.api.GetAutoThanksAuras(), nil)
	Equal(h.api.GetAutoThanksTarget(FRIEND, "party1", nil), nil)
	h = Fixture(); h:Aura(1, "party1")
	h.native.UnitGUID = function(unit) return unit == "player" and OWN or h.secret end
	Equal(h.api.GetAutoThanksAuras(), nil)
	Equal(h.api.GetAutoThanksTarget(FRIEND, "party1", nil), nil)
	h = Fixture(); h:Aura(1, nil); h.casters[1] = h.secret
	Equal(h.api.GetAutoThanksAuras(), nil)
	h = Fixture(); h:Aura(1, "party1"); h.units.player = h.secret
	Equal(h.api.GetAutoThanksAuras(), nil)
	h = Fixture(); h:Aura(1, nil); h.casters[1] = OTHER
	h.guidNames[OTHER] = { name = "Stranger", realm = "Realm" }
	h.native.UnitTokenFromGUID = function() return h.secret end
	Equal(h.api.GetAutoThanksAuras(), nil)
	Equal(h.api.GetAutoThanksTarget(OTHER, nil, nil), nil)
end, { offline = true })

QT:RegisterTest("auto thanks native preserves unresolved instances and empty snapshots", function()
	local h = Fixture()
	Equal(#assert(h.api.GetAutoThanksAuras()), 0)
	h:Aura(1, nil).duration = nil
	h.native.GetAuraCasterGUID = nil
	local rows = assert(h.api.GetAutoThanksAuras())
	Equal(#rows, 1); Equal(rows[1].id, 1); Equal(rows[1].guid, nil); Equal(rows[1].duration, nil)
	h:Aura(2, nil).isHelpful = false
	Equal(#assert(h.api.GetAutoThanksAuras()), 1)
end, { offline = true })

QT:RegisterTest("auto thanks native caster GUID resolves drive by players without a token", function()
	local h = Fixture(); h:Aura(1, nil); h.casters[1] = OTHER
	h.guidNames[OTHER] = { name = "Stranger", realm = "OtherRealm" }
	local row = assert(h.api.GetAutoThanksAuras())[1]
	Equal(row.guid, OTHER); Equal(row.unit, nil); Equal(row.name, "Stranger-OtherRealm")
	Equal(h.api.GetAutoThanksTarget(OTHER, nil, row.name), row.name)
	h.guidNames[OTHER].name = "Different"
	Equal(h.api.GetAutoThanksTarget(OTHER, nil, row.name), nil)
	h.guidNames[OTHER] = nil
	Equal(h.api.GetAutoThanksTarget(OTHER, nil, row.name), nil)
	h.casters[1] = OWN; Equal(assert(h.api.GetAutoThanksAuras())[1].guid, nil)
end, { offline = true })

QT:RegisterTest("auto thanks native prefers verified unit identity after GUID lookup", function()
	local h = Fixture(); h:Aura(1, nil); h.casters[1] = FRIEND
	local row = assert(h.api.GetAutoThanksAuras())[1]
	Equal(row.guid, FRIEND); Equal(row.unit, "party1"); Equal(row.name, "Friend-Realm")
	Equal(h.api.GetAutoThanksTarget(FRIEND, nil, nil), "Friend-Realm")
	h.native.UnitTokenFromGUID = function() return "player" end
	Equal(h.api.GetAutoThanksTarget(FRIEND, nil, nil), nil)
	row = assert(h.api.GetAutoThanksAuras())[1]
	Equal(row.guid, FRIEND); Equal(row.unit, nil)
end, { offline = true })

QT:RegisterTest("auto thanks native Forever GUID names require a complete regional identity", function()
	local h = Fixture(); h.regional = true; h:Aura(1, nil); h.casters[1] = OTHER
	h.guidNames[OTHER] = { name = "Stranger", realm = "ClassicBetaPvE" }
	Equal(assert(h.api.GetAutoThanksAuras())[1].name, nil)
	Equal(h.api.GetAutoThanksTarget(OTHER, nil, nil), nil)
	for _, name in ipairs({ "Stranger Surname", "Stranger-Surname" }) do
		h.guidNames[OTHER].name = name
		Equal(h.api.GetAutoThanksTarget(OTHER, nil, nil), "Stranger Surname")
	end
	h.guidNames[OTHER].name = h.secret
	Equal(h.api.GetAutoThanksTarget(OTHER, nil, nil), nil)
	h.guidNames[OTHER].name = "Stranger Surname"
	h.native.RegionalUniqueNamesEnabled = h.secret
	Equal(h.api.GetAutoThanksTarget(OTHER, nil, nil), nil)
	h.names.party1 = "Friend Surname"
	Equal(h.api.GetAutoThanksTarget(FRIEND, "party1", nil), "Friend Surname")
end, { offline = true })

QT:RegisterTest("auto thanks native never directs an emote to a recycled unit token", function()
	local h = Fixture(); h:Aura(1, "party1")
	local row = assert(h.api.GetAutoThanksAuras())[1]
	h.units.party1, h.names.party1 = OTHER, "Other-Realm"
	Equal(h.api.GetAutoThanksTarget(row.guid, row.unit, row.name), nil)
	h.units.focus, h.names.focus = FRIEND, "Friend-Realm"
	Equal(h.api.GetAutoThanksTarget(row.guid, row.unit, row.name), "Friend-Realm")
	Equal(h.units.party1, OTHER); Equal(h.units.focus, FRIEND); Equal(#h.emotes, 0)
end, { offline = true })

QT:RegisterTest("auto thanks native bounds snapshots and rejects malformed duplicate identifiers", function()
	local h = Fixture()
	for id = 1, 256 do h:Aura(id, nil) end
	Equal(#assert(h.api.GetAutoThanksAuras()), 256); Equal(h.reads, 257)
	h:Aura(257, nil); h.reads = 0
	Equal(h.api.GetAutoThanksAuras(), nil); Equal(h.reads, 257)
	for _, value in ipairs({ 0, -1, 1.5, math.huge, "1" }) do
		h = Fixture(); h:Aura(value, nil); Equal(h.api.GetAutoThanksAuras(), nil)
	end
	h = Fixture(); h:Aura(1, nil); h:Aura(1, nil)
	Equal(h.api.GetAutoThanksAuras(), nil)
	for _, value in ipairs({ -1, math.huge, "1800" }) do
		h = Fixture(); h:Aura(1, nil).duration = value; Equal(h.api.GetAutoThanksAuras(), nil)
	end
end, { offline = true })

QT:RegisterTest("auto thanks native respects tests profile options lifecycle and restrictions", function()
	for _, flag in ipairs({ "isRunningTests", "suppressLocalAnnouncementDisplayDuringTests", "isLoggingOut", "isLeavingWorld" }) do
		local h = Fixture(); h.addon[flag] = true
		Equal(h.api.GetAutoThanksAuras(), nil); Equal(h.api.GetAutoThanksTarget(FRIEND, "party1", nil), nil)
		Equal(h.api.PerformAutoThanks("thank", "Friend-Realm"), false)
		Equal(h.reads, 0); Equal(h.identityReads, 0); Equal(#h.emotes, 0)
	end
	for _, state in ipairs({ "disabled", "option", "restricted", "chat", "unknownRestriction", "unknownOption" }) do
		local h = Fixture()
		if state == "disabled" then h.addon.isEnabled = false
		elseif state == "option" then h.options.autoThankBuffs = false
		elseif state == "restricted" then h.restricted = true
		elseif state == "chat" then h.chatRestricted = true
		elseif state == "unknownRestriction" then h.restricted = h.secret
		elseif state == "unknownOption" then h.options.autoThankBuffs = h.secret end
		Equal(h.api.GetAutoThanksAuras(), nil); Equal(h.api.GetAutoThanksTarget(FRIEND, "party1", nil), nil)
		Equal(h.api.PerformAutoThanks("thank", "Friend-Realm"), false)
		Equal(h.reads, 0); Equal(h.identityReads, 0); Equal(#h.emotes, 0)
	end
end, { offline = true })

QT:RegisterTest("auto thanks native emits only allowed explicit gratitude attempts", function()
	local h = Fixture()
	for _, token in ipairs({ "thank", "bow", "applaud" }) do assert(h.api.PerformAutoThanks(token, "Friend-Realm")) end
	Equal(#h.emotes, 3); Equal(h.emotes[1].token, "THANK"); Equal(h.emotes[1].target, "Friend-Realm")
	for _, token in ipairs({ "THANK", "mountspecial", "", "thank\n" }) do
		Equal(h.api.PerformAutoThanks(token, "Friend-Realm"), false)
	end
	for _, target in ipairs({ "", " ", "Friend\nRealm", "|Hplayer:Friend|h", h.secret }) do
		Equal(h.api.PerformAutoThanks("thank", target), false)
	end
	Equal(h.api.PerformAutoThanks("thank", nil), false); Equal(#h.emotes, 3)
	h.native.PerformEmote = function() error("native rejection") end
	Equal(h.api.PerformAutoThanks("thank", "Friend-Realm"), false)
	h.native.PerformEmote, h.native.DoEmote = nil, nil
	Equal(h.api.PerformAutoThanks("thank", "Friend-Realm"), false)
	h.native.DoEmote = function(token, target) Equal(token, "THANK"); Equal(target, "Friend-Realm") end
	assert(h.api.PerformAutoThanks("thank", "Friend-Realm"))
end, { offline = true })

QT:RegisterTest("auto thanks native requires a complete not ignored result before emitting", function()
	for _, state in ipairs({ "ignored", "error", "missing", "secret", "nil" }) do
		local h = Fixture()
		if state == "missing" then h.native.IsOnIgnoredList = nil
		else
			h.native.IsOnIgnoredList = function(target)
				Equal(target, "Friend-Realm")
				if state == "error" then error("friend list unavailable") end
				if state == "secret" then return h.secret end
				if state == "ignored" then return true end
			end
		end
		Equal(h.api.PerformAutoThanks("thank", "Friend-Realm"), false)
		Equal(#h.emotes, 0)
	end
	local h = Fixture()
	h.native.IsOnIgnoredList = function(target) Equal(target, "Friend-Realm"); return false end
	assert(h.api.PerformAutoThanks("thank", "Friend-Realm"))
	Equal(#h.emotes, 1)
end, { offline = true })

_G.QuestTogether:RecordTestModule("scripts/regression_auto_thanks_native.lua")
