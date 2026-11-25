-- SPDX-License-Identifier: GPL-3.0-only
-- Native aura observations only; no network event can request an emote.
local QT = _G.QuestTogether
local EMOTES = { "thank", "bow", "applaud" }
local MAX_AURAS, MAX_PENDING, MAX_COOLDOWNS = 256, 4, 64
local CASTER_COOLDOWN, GLOBAL_COOLDOWN, EXPIRY = 300, 15, 10

local function Number(a, value)
	local n = a:SafeToNumber(value)
	if n and n == n and n >= 0 and n < math.huge then
		return n
	end
end
local function Text(a, value, limit)
	if
		a:CanAccessValue(value)
		and type(value) == "string"
		and #value > 0
		and #value <= limit
		and not value:find("[%z\1-\31\127]")
	then
		return value
	end
end
local function Call(a, method, ...)
	local fn = a.API and a.API[method]
	if type(fn) ~= "function" then
		return
	end
	local ok, value = pcall(fn, ...)
	if ok then
		return value
	end
end
local function Active(a)
	return a.isEnabled
		and not a.isLoggingOut
		and not a.isLeavingWorld
		and not a.isRunningTests
		and not a.suppressLocalAnnouncementDisplayDuringTests
		and a:GetOption("autoThankBuffs") == true
end
local function Restricted(a)
	return a:IsRuntimeRestricted() or a:IsRuntimeRestrictionTypeActive("chat")
end
local function Snapshot(a)
	local rows = Call(a, "GetAutoThanksAuras")
	if not a:CanAccessTable(rows) or type(rows) ~= "table" or #rows > MAX_AURAS then
		return
	end
	local byID, ordered = {}, {}
	for i = 1, #rows do
		local row = rows[i]
		if not a:CanAccessTable(row) or type(row) ~= "table" then
			return
		end
		local id = Number(a, row.id)
		if not id or id == 0 or id ~= math.floor(id) or byID[id] then
			return
		end
		local guid = Text(a, row.guid, 64)
		if guid and not guid:match("^Player%-%d+%-%x+$") then
			guid = nil
		end
		local clean = {
			id = id,
			guid = guid,
			duration = Number(a, row.duration),
			unit = Text(a, row.unit, 40),
			name = Text(a, row.name, 120),
		}
		byID[id], ordered[#ordered + 1] = clean, clean
	end
	return byID, ordered
end
local function ClearObservation(s)
	s.baseline, s.pending, s.dirty = nil, {}, true
end
local function Random(a, low, high)
	local value = Number(a, Call(a, "Random", low, high))
	if value and value >= low and value <= high and value == math.floor(value) then
		return value
	end
	return low
end
local function PendingAura(s, pending)
	local found
	for id in pairs(pending.ids) do
		local aura = s.baseline and s.baseline[id]
		if aura and aura.guid == pending.guid and aura.duration and aura.duration >= 60 then
			if not found or id < found.id then
				found = aura
			end
		else
			pending.ids[id] = nil
		end
	end
	return found
end

function QT:ResetAutoThanks()
	self.autoThanksState = nil
end
function QT:SuspendAutoThanks()
	local s = rawget(self, "autoThanksState")
	if s then
		ClearObservation(s)
	end
end
function QT:PLAYER_REGEN_DISABLED()
	self:DismissManagedWindowsForCombat()
	self:SuspendAutoThanks()
end
function QT:InitializeAutoThanks()
	self:ResetAutoThanks()
	if not Active(self) then
		return false
	end
	self.autoThanksState = { profile = self.db and self.db.profile, pending = {}, cooldowns = {}, dirty = true }
	return true
end
function QT:UNIT_AURA(_, unit)
	if not self:CanAccessValue(unit) or unit ~= "player" then
		return
	end
	local s = rawget(self, "autoThanksState")
	if s then
		if Restricted(self) then
			ClearObservation(s)
		else
			s.dirty = true
		end
	end
end
function QT:UpdateAutoThanks()
	local s = rawget(self, "autoThanksState")
	if not s then
		return
	end
	if not Active(self) or s.profile ~= (self.db and self.db.profile) then
		self:ResetAutoThanks()
		return
	end
	local now = Number(self, Call(self, "GetTime"))
	if not now or s.lastTime and now < s.lastTime then
		ClearObservation(s)
		s.cooldowns, s.nextAllowed, s.lastTime = {}, nil, now
		return
	end
	s.lastTime = now
	if Restricted(self) then
		ClearObservation(s)
		return
	end
	local cooldownCount = 0
	for guid, untilTime in pairs(s.cooldowns) do
		if now >= untilTime then
			s.cooldowns[guid] = nil
		else
			cooldownCount = cooldownCount + 1
		end
	end
	if s.dirty then
		s.dirty = false
		local current, ordered = Snapshot(self)
		if not current then
			-- A later complete sample is a silent baseline, never a set of new buffs.
			s.baseline, s.pending = nil, {}
			return
		end
		local previous = s.baseline
		s.baseline = current
		if previous and (not s.nextAllowed or now >= s.nextAllowed) and cooldownCount < MAX_COOLDOWNS then
			local pendingCount = 0
			for _ in pairs(s.pending) do
				pendingCount = pendingCount + 1
			end
			for _, row in ipairs(ordered) do
				if
					not previous[row.id]
					and row.guid
					and row.duration
					and row.duration >= 60
					and not s.cooldowns[row.guid]
				then
					local pending = s.pending[row.guid]
					if pending then
						pending.ids[row.id] = true
					elseif pendingCount < MAX_PENDING then
						s.pending[row.guid] = {
							id = row.id,
							ids = { [row.id] = true },
							guid = row.guid,
							due = now + Random(self, 2000, 4000) / 1000,
							expires = now + EXPIRY,
						}
						pendingCount = pendingCount + 1
					end
				end
			end
		end
	end
	local candidate
	for guid, pending in pairs(s.pending) do
		if now > pending.expires or not PendingAura(s, pending) then
			s.pending[guid] = nil
		elseif
			now >= pending.due
			and (
				not candidate
				or pending.due < candidate.due
				or pending.due == candidate.due and pending.id < candidate.id
			)
		then
			candidate = pending
		end
	end
	if not candidate then
		return
	end
	s.pending[candidate.guid] = nil
	if s.nextAllowed and now < s.nextAllowed or s.cooldowns[candidate.guid] then
		return
	end
	-- One fresh scan at action time handles a lost/coalesced removal event or
	-- newly inaccessible aura data. It never creates more gratitude candidates.
	local current = Snapshot(self)
	if not current then
		ClearObservation(s)
		return
	end
	s.baseline = current
	local aura = PendingAura(s, candidate)
	if not aura then
		return
	end
	-- Tokens can be recycled during the pause. Native identity is checked again
	-- without changing the player's selected target or retaining foreign tables.
	local target = Text(self, Call(self, "GetAutoThanksTarget", candidate.guid, aura.unit, aura.name), 120)
	if
		not target
		or rawget(self, "autoThanksState") ~= s
		or s.profile ~= (self.db and self.db.profile)
		or not Active(self)
		or Restricted(self)
	then
		return
	end
	local checked, ignored = pcall(self.IsIgnoredPlayerName, self, target)
	if not checked or not self:CanAccessValue(ignored) or ignored ~= false then
		return
	end
	local emote = EMOTES[Random(self, 1, #EMOTES)]
	if
		rawget(self, "autoThanksState") ~= s
		or s.profile ~= (self.db and self.db.profile)
		or not Active(self)
		or Restricted(self)
	then
		return
	end
	-- Reserve the cooldown before crossing the native boundary. Failed attempts
	-- are never retried as a burst of social actions.
	s.nextAllowed, s.cooldowns[candidate.guid] = now + GLOBAL_COOLDOWN, now + CASTER_COOLDOWN
	s.pending = {}
	-- Retain only bounded outcome fields, never recipient identities or native
	-- error text. A nonthrowing call is not proof of visible emote delivery.
	s.attempts = math.min((s.attempts or 0) + 1, 1000000)
	s.lastAttempt, s.lastEmote = now, emote
	local ok, attempted, outcome = pcall(self.API.PerformAutoThanks, emote, target)
	s.lastResult = ok and (Text(self, outcome, 64) or (attempted == true and "attempted" or "not_attempted")) or "adapter_error"
end
