-- Private addon-owned snapshots and transports only; never change live APIs.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Fixture()
	local addon = setmetatable({
		isInitialized = true,
		isEnabled = true,
		isLoggingOut = false,
		isLeavingWorld = false,
		isRunningTests = false,
		suppressLocalAnnouncementDisplayDuringTests = false,
		db = { profile = { enabled = true } },
		options = { autoThankBuffs = true },
		time = 100,
		auras = {},
		players = {},
		unitGUIDs = {},
		ignored = {},
		emotes = {},
		lookups = {},
		randomCalls = {},
		delay = 2,
		emoteChoice = 1,
	}, { __index = QT })
	addon.API = {
		GetTime = function()
			if addon.clockUnavailable then
				return nil
			end
			return addon.time
		end,
		Random = function(low, high)
			addon.randomCalls[#addon.randomCalls + 1] = { low, high }
			if low == 2000 and high == 4000 then
				return addon.delay * 1000
			end
			Equal(low, 1)
			Equal(high, 3)
			return addon.emoteChoice
		end,
		GetAutoThanksAuras = function()
			if addon.aurasUnavailable then
				return nil
			end
			local snapshot = {}
			for index, aura in ipairs(addon.auras) do
				snapshot[index] = {
					id = aura.id,
					guid = aura.guid,
					unit = aura.unit,
					name = aura.name,
					duration = aura.duration,
				}
			end
			return snapshot
		end,
		GetAutoThanksTarget = function(guid, unit, name)
			addon.lookups[#addon.lookups + 1] = { guid = guid, unit = unit, name = name }
			if addon.beforeTarget then
				addon:beforeTarget()
			end
			if unit and addon.unitGUIDs[unit] ~= guid then
				return nil
			end
			return addon.players[guid]
		end,
		PerformAutoThanks = function(emote, target)
			assert(type(target) == "string" and target ~= "", "auto-thanks must always be directed")
			local token = string.upper(emote)
			assert(token == "THANK" or token == "BOW" or token == "APPLAUD", "unexpected thanks emote")
			addon.emotes[#addon.emotes + 1] = { emote = token, target = target, time = addon.time }
			return addon.rejectEmote ~= true
		end,
	}
	function addon:GetOption(key)
		return self.options[key]
	end
	function addon:IsRuntimeRestricted()
		return self.restricted == true
	end
	function addon:IsRuntimeRestrictionTypeActive(kind)
		return kind == "chat" and self.chatRestricted == true
	end
	function addon:IsIgnoredPlayerName(name)
		return self.ignored[name] == true
	end
	function addon:Debugf() end
	function addon:Buff(id, caster, duration, unit)
		caster = caster or 1
		local guid = "Player-1-ABC" .. caster
		local name = "Benefactor" .. caster .. "-Realm"
		self.players[guid] = name
		if unit then
			self.unitGUIDs[unit] = guid
		end
		return { id = id, guid = guid, name = name, unit = unit, duration = duration or 600 }
	end
	function addon:Scan(...)
		self.auras = { ... }
		self:UNIT_AURA(nil, "player")
		self:UpdateAutoThanks()
	end
	function addon:Tick(seconds)
		self.time = self.time + (seconds or 0)
		self:UpdateAutoThanks()
	end
	addon:InitializeAutoThanks()
	return addon
end

local function Ready()
	local addon = Fixture()
	addon:Scan()
	return addon
end

QT:RegisterTest("auto thanks observes initial auras without thanking their casters", function()
	local addon = Fixture()
	local existing = addon:Buff(1)
	addon:Scan(existing)
	addon:Tick(5)
	Equal(#addon.emotes, 0)
	existing.duration = 1800
	addon:Scan(existing)
	addon:Tick(5)
	Equal(#addon.emotes, 0)
	addon:Scan(existing, addon:Buff(2, 2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
	Equal(addon.emotes[1].target, "Benefactor2-Realm")
end)

QT:RegisterTest("auto thanks waits for its randomized delay and keeps the exact caster target", function()
	for _, delay in ipairs({ 2, 3, 4 }) do
		local addon = Ready()
		addon.delay = delay
		local aura = addon:Buff(1, 1, 600, "party1")
		addon:Scan(aura)
		Equal(#addon.emotes, 0)
		addon:Tick(delay - 0.1)
		Equal(#addon.emotes, 0)
		addon.currentTarget = "SomeoneElse-Realm"
		addon:Tick(0.1)
		Equal(#addon.emotes, 1)
		Equal(addon.emotes[1].target, "Benefactor1-Realm")
		Equal(addon.emotes[1].time, 100 + delay)
		local lookup = addon.lookups[#addon.lookups]
		Equal(lookup.guid, aura.guid)
		Equal(lookup.unit, "party1")
		Equal(lookup.name, aura.name)
		local sampledDelay = false
		for _, call in ipairs(addon.randomCalls) do
			if call[1] == 2000 and call[2] == 4000 then
				sampledDelay = true
			end
		end
		assert(sampledDelay, "each candidate needs a randomized delay")
	end
end)

QT:RegisterTest("auto thanks chooses only the three friendly emotes", function()
	local choices = {}
	for choice = 1, 3 do
		local addon = Ready()
		addon.emoteChoice = choice
		addon:Scan(addon:Buff(1))
		addon:Tick(2)
		Equal(#addon.emotes, 1)
		choices[addon.emotes[1].emote] = true
	end
	assert(choices.THANK and choices.BOW and choices.APPLAUD)
end)

QT:RegisterTest("auto thanks ignores short and permanent auras and accepts a sixty second buff", function()
	for _, duration in ipairs({ 0, 1, 59, 59.9, 60 }) do
		local addon = Ready()
		addon:Scan(addon:Buff(1, 1, duration))
		addon:Tick(4)
		Equal(#addon.emotes, duration >= 60 and 1 or 0)
	end
end)

QT:RegisterTest("auto thanks observes only aura changes on the local player", function()
	local addon = Ready()
	addon.auras = { addon:Buff(1) }
	for _, unit in ipairs({ "target", "party1", "pet" }) do
		addon:UNIT_AURA(nil, unit)
		addon:Tick(5)
	end
	Equal(#addon.emotes, 0)
	addon:UNIT_AURA(nil, "player")
	addon:Tick(0)
	addon:Tick(2)
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks never treats an existing instance refresh as a new buff", function()
	local addon = Ready()
	local aura = addon:Buff(1, 1, 30)
	addon:Scan(aura)
	addon:Tick(5)
	aura.duration = 600
	addon:Scan(aura)
	addon:Tick(5)
	Equal(#addon.emotes, 0)
end)

QT:RegisterTest("auto thanks merges simultaneous buffs without postponing the first thanks", function()
	local addon = Ready()
	local first, second = addon:Buff(1), addon:Buff(2)
	addon:Scan(first)
	addon:Tick(1)
	addon:Scan(first, second)
	addon:Scan(first, second)
	addon:Tick(1)
	Equal(#addon.emotes, 1)
	addon:Tick(20)
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks requires a qualifying aura to remain when the delay ends", function()
	local addon = Ready()
	addon:Scan(addon:Buff(1))
	addon:Scan()
	addon:Tick(2)
	Equal(#addon.emotes, 0)
end)

QT:RegisterTest("auto thanks keeps a merged thanks while another new buff from that caster remains", function()
	local addon = Ready()
	local first, second = addon:Buff(1), addon:Buff(2)
	addon:Scan(first)
	addon:Tick(1)
	addon:Scan(first, second)
	addon:Scan(second)
	addon:Tick(1)
	Equal(#addon.emotes, 1)
	Equal(addon.emotes[1].time, 102)
end)

QT:RegisterTest("auto thanks rereads auras before sending even when no removal event arrives", function()
	for _, unreadable in ipairs({ false, true }) do
		local addon = Ready()
		local aura = addon:Buff(1)
		addon:Scan(aura)
		if unreadable then
			addon.aurasUnavailable = true
		else
			addon.auras = {}
		end
		addon:Tick(2)
		Equal(#addon.emotes, 0)
	end
end)

QT:RegisterTest("auto thanks suppresses a caster for five minutes after a successful thanks", function()
	local addon = Ready()
	addon:Scan(addon:Buff(1))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
	addon:Tick(299)
	addon:Scan(addon:Buff(2))
	addon:Tick(1)
	Equal(#addon.emotes, 1)
	addon:Scan(addon:Buff(3))
	addon:Tick(2)
	Equal(#addon.emotes, 2)
end)

QT:RegisterTest("auto thanks drops new candidates during the global cooldown", function()
	local addon = Ready()
	addon:Scan(addon:Buff(1))
	addon:Tick(2)
	addon:Tick(14)
	addon:Scan(addon:Buff(2, 2))
	addon:Tick(5)
	Equal(#addon.emotes, 1)
	addon:Scan(addon:Buff(2, 2), addon:Buff(3, 3))
	addon:Tick(2)
	Equal(#addon.emotes, 2)
	Equal(addon.emotes[2].target, "Benefactor3-Realm")
end)

QT:RegisterTest("auto thanks holds at most four different pending casters", function()
	local accepted = 0
	for survivor = 1, 5 do
		local addon = Ready()
		local buffs = {}
		for caster = 1, 5 do
			buffs[caster] = addon:Buff(caster, caster)
		end
		addon:Scan((unpack or table.unpack)(buffs))
		for caster = 1, 5 do
			if caster ~= survivor then
				addon.players[buffs[caster].guid] = nil
			end
		end
		addon:Tick(2)
		for _ = 1, 4 do
			addon:Tick(0)
		end
		assert(#addon.emotes <= 1)
		accepted = accepted + #addon.emotes
	end
	Equal(accepted, 4)
end)

QT:RegisterTest("auto thanks expires delayed work instead of thanking much later", function()
	local addon = Ready()
	addon:Scan(addon:Buff(1))
	addon:Tick(11)
	Equal(#addon.emotes, 0)
	addon:Tick(30)
	Equal(#addon.emotes, 0)
end)

QT:RegisterTest("auto thanks never guesses an unknown caster from a later aura refresh", function()
	local addon = Ready()
	local aura = addon:Buff(1)
	local guid = aura.guid
	aura.guid, aura.unit, aura.name = nil, nil, nil
	addon:Scan(aura)
	addon:Tick(4)
	Equal(#addon.emotes, 0)
	aura.guid, aura.name = guid, "Benefactor1-Realm"
	addon:Scan(aura)
	addon:Tick(4)
	Equal(#addon.emotes, 0)
	addon:Scan(aura, addon:Buff(2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks discards pending work and rebaselines after unreadable auras", function()
	local addon = Ready()
	local aura = addon:Buff(1)
	addon:Scan(aura)
	addon.aurasUnavailable = true
	addon:Scan(aura)
	addon:Tick(2)
	Equal(#addon.emotes, 0)
	addon.aurasUnavailable = false
	addon:Scan(aura)
	addon:Tick(4)
	Equal(#addon.emotes, 0)
	addon:Scan(aura, addon:Buff(2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks revalidates delayed caster identities without using a recycled token", function()
	for _, recycle in ipairs({ false, true }) do
		local addon = Ready()
		local aura = addon:Buff(1, 1, 600, "nameplate1")
		addon:Scan(aura)
		if recycle then
			addon.unitGUIDs.nameplate1 = "Player-1-SOMEONEELSE"
		else
			addon.players[aura.guid] = nil
		end
		addon:Tick(2)
		Equal(#addon.emotes, 0)
		addon:Tick(20)
		Equal(#addon.emotes, 0)
	end
end)

QT:RegisterTest("auto thanks does not address ignored players or assume an unreadable ignore list is clear", function()
	for _, state in ipairs({ "ignored", "unavailable", "unknown" }) do
		local addon = Ready()
		local aura = addon:Buff(1)
		addon:Scan(aura)
		if state == "ignored" then
			addon.ignored[aura.name] = true
		elseif state == "unavailable" then
			function addon:IsIgnoredPlayerName()
				error("ignore list unavailable")
			end
		else
			function addon:IsIgnoredPlayerName()
				return nil
			end
		end
		addon:Tick(2)
		Equal(#addon.emotes, 0)
	end
end)

QT:RegisterTest("auto thanks resets pending work and baseline when its option is disabled", function()
	local addon = Ready()
	local aura = addon:Buff(1)
	addon:Scan(aura)
	addon.options.autoThankBuffs = false
	addon:Tick(2)
	Equal(#addon.emotes, 0)
	addon.options.autoThankBuffs = true
	addon:InitializeAutoThanks()
	addon:Scan(aura)
	addon:Tick(4)
	Equal(#addon.emotes, 0)
	addon:Scan(aura, addon:Buff(2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks clears delayed work across restricted or inactive lifetimes", function()
	for _, field in ipairs({
		"restricted",
		"chatRestricted",
		"isLoggingOut",
		"isLeavingWorld",
		"isRunningTests",
		"suppressLocalAnnouncementDisplayDuringTests",
		"isEnabled",
	}) do
		local addon = Ready()
		local aura = addon:Buff(1)
		addon:Scan(aura)
		addon[field] = field ~= "isEnabled"
		addon:Tick(2)
		Equal(#addon.emotes, 0)
		addon[field] = field == "isEnabled"
		if field ~= "restricted" and field ~= "chatRestricted" then
			addon:InitializeAutoThanks()
		end
		addon:Scan(aura)
		addon:Tick(4)
		Equal(#addon.emotes, 0)
		addon:Scan(aura, addon:Buff(2))
		addon:Tick(2)
		Equal(#addon.emotes, 1)
	end
end)

QT:RegisterTest("auto thanks cannot carry pending emotes into a different profile", function()
	local addon = Ready()
	local aura = addon:Buff(1)
	addon:Scan(aura)
	addon.db.profile = { enabled = true }
	addon:Tick(2)
	Equal(#addon.emotes, 0)
	addon:InitializeAutoThanks()
	addon:Scan(aura)
	addon:Tick(4)
	Equal(#addon.emotes, 0)
	addon:Scan(aura, addon:Buff(2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks immediately forgets pending buffs when aura events are restricted", function()
	local addon = Ready()
	addon:Scan(addon:Buff(1))
	addon.restricted = true
	addon:UNIT_AURA(nil, "player")
	addon.restricted = false
	addon:Tick(2)
	Equal(#addon.emotes, 0)
	addon:Scan(addon:Buff(2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks combat suspension discards pending buffs and preserves cooldowns", function()
	local pending = Ready()
	local aura = pending:Buff(1)
	pending:Scan(aura)
	pending:PLAYER_REGEN_DISABLED()
	pending:Tick(2)
	Equal(#pending.emotes, 0)

	local addon = Ready()
	addon:Scan(addon:Buff(1))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
	addon:PLAYER_REGEN_DISABLED()
	addon:Scan(addon:Buff(1))
	addon:Tick(3)
	addon:Scan(addon:Buff(2, 2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
	addon:Tick(20)
	addon:Scan(addon:Buff(3))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
	addon:Scan(addon:Buff(4, 3))
	addon:Tick(2)
	Equal(#addon.emotes, 2)
end)

QT:RegisterTest("auto thanks rechecks its lifetime after resolving the directed target", function()
	for _, change in ipairs({ "reset", "profile", "restriction" }) do
		local addon = Ready()
		addon:Scan(addon:Buff(1))
		function addon:beforeTarget()
			if change == "reset" then
				self:ResetAutoThanks()
			elseif change == "profile" then
				self.db.profile = { enabled = true }
			else
				self.restricted = true
			end
		end
		addon:Tick(2)
		Equal(#addon.emotes, 0)
	end
end)

QT:RegisterTest("auto thanks abandons a send when its ignore lookup resets the lifetime", function()
	local addon = Ready()
	addon:Scan(addon:Buff(1))
	function addon:IsIgnoredPlayerName()
		self:ResetAutoThanks()
		return false
	end
	addon:Tick(2)
	Equal(#addon.emotes, 0)
end)

QT:RegisterTest("auto thanks abandons a send when random emote selection resets the lifetime", function()
	local addon = Ready()
	addon:Scan(addon:Buff(1))
	addon.API.Random = function(low, high)
		Equal(low, 1)
		Equal(high, 3)
		addon:ResetAutoThanks()
		return 1
	end
	addon:Tick(2)
	Equal(#addon.emotes, 0)
end)

QT:RegisterTest("auto thanks never retries failed emote attempts as a burst", function()
	local addon = Ready()
	addon.rejectEmote = true
	addon:Scan(addon:Buff(1), addon:Buff(2, 2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
	addon:Scan(addon:Buff(3, 3))
	for _ = 1, 20 do
		addon:Tick(1)
	end
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks explicit reset discards pending work and baselines current auras", function()
	local addon = Ready()
	local aura = addon:Buff(1)
	addon:Scan(aura)
	addon:ResetAutoThanks()
	addon:InitializeAutoThanks()
	addon:Scan(aura)
	addon:Tick(4)
	Equal(#addon.emotes, 0)
	addon:Scan(aura, addon:Buff(2))
	addon:Tick(2)
	Equal(#addon.emotes, 1)
end)

QT:RegisterTest("auto thanks rejects delayed work after a clock rollback or unavailable clock", function()
	for _, unavailable in ipairs({ false, true }) do
		local addon = Ready()
		local aura = addon:Buff(1)
		addon:Scan(aura)
		addon.clockUnavailable = unavailable
		if not unavailable then
			addon.time = 50
		end
		addon:Tick(0)
		Equal(#addon.emotes, 0)
		addon.clockUnavailable, addon.time = false, 110
		addon:Scan(aura)
		addon:Tick(4)
		Equal(#addon.emotes, 0)
		addon:Scan(aura, addon:Buff(2))
		addon:Tick(2)
		Equal(#addon.emotes, 1)
	end
end)

_G.QuestTogether:RecordTestModule("scripts/regression_auto_thanks.lua")
