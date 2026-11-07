-- QT owns this catalog, playback policy and handles. Native sound settings and
-- other addons' audio are untouched. No delayed notification queue is retained.
local QT = _G.QuestTogether
local L = QT.Translate
local definitions = {
	{ key = "attention", sound = "chime", enabled = true, volume = 60, cooldown = 1, priority = 2 },
	{ key = "focus", sound = "selection", enabled = true, volume = 40, cooldown = 0.75 },
	{ key = "waypoint", sound = "spellbook", volume = 50, cooldown = 2 },
	{ key = "questReady", sound = "completion", volume = 50, cooldown = 3 },
	{ key = "questTurnIn", sound = "scroll", volume = 50, cooldown = 3 },
	{ key = "objectiveProgress", sound = "progress", volume = 30, cooldown = 5 },
	{ key = "chat", sound = "chime", volume = 40, cooldown = 2 },
	{ key = "shareResult", sound = "scroll", volume = 40, cooldown = 2 },
}
local sounds = { scroll = true, spellbook = true, selection = true, chime = true, progress = true, completion = true }
local byKey, settings = {}, { audioEnabled = true, audioVolume = 50, audioMuteInCombat = false, audioInterval = 0.75 }
for _, cue in ipairs(definitions) do
	local prefix = "audio" .. cue.key:sub(1, 1):upper() .. cue.key:sub(2)
	cue.enabledKey, cue.volumeKey, cue.soundKey = prefix .. "Enabled", prefix .. "Volume", prefix .. "Sound"
	settings[cue.enabledKey], settings[cue.volumeKey], settings[cue.soundKey] = cue.enabled == true, cue.volume, cue.sound
	byKey[cue.key] = cue
end
for key, value in pairs(settings) do QT.DEFAULTS.profile[key] = value end

function QT:GetAudioCueCatalog()
	local labels = {
		{ L("Requests and confirmations"), L("A QuestTogether dialog needs your attention.") },
		{ L("Automatic quest focus changes"), L("The player you follow changes your focused quest.") },
		{ L("Party waypoints"), L("A party member shares a new waypoint.") },
		{ L("Party quests ready to turn in"), L("A party member finishes the objectives for a quest.") },
		{ L("Party quest turn-ins"), L("A party member turns in a quest.") },
		{ L("Party objective progress"), L("A party member makes progress on a quest objective.") },
		{ L("Incoming QuestTogether chat"), L("A new QuestTogether chat message passes your display filters.") },
		{ L("Quest sharing results"), L("A player accepts or declines a quest you shared, or the share cannot complete.") },
	}
	local result = {}
	for i, cue in ipairs(definitions) do
		result[i] = { key = cue.key, label = labels[i][1], description = labels[i][2],
			enabledKey = cue.enabledKey, volumeKey = cue.volumeKey, soundKey = cue.soundKey }
	end
	return result
end
function QT:GetAudioSoundOptions()
	return {
		{ value = "scroll", text = L("Parchment") },
		{ value = "spellbook", text = L("Arcane shimmer") },
		{ value = "selection", text = L("Focus chime") },
		{ value = "chime", text = L("Gentle bell") },
		{ value = "progress", text = L("Soft pluck") },
		{ value = "completion", text = L("Quest flourish") },
	}
end
function QT:IsAudioSetting(key) return settings[key] ~= nil end
function QT:ValidateAudioSetting(key, value)
	local default = settings[key]
	if type(default) == "boolean" then
		if type(value) == "boolean" then return value end
		return
	end
	if type(default) == "string" then return type(value) == "string" and sounds[value] and value or nil end
	local n = self:SafeToNumber(value)
	if not n or n ~= n or math.abs(n) == math.huge then return end
	if key == "audioInterval" then
		if n >= 0.25 and n <= 3 then return math.floor(n * 4 + 0.5) / 4 end
	elseif n >= 0 and n <= 100 then return math.floor(n + 0.5) end
end
function QT:GetAudioVolume(key)
	return self:ValidateAudioSetting(key, self:GetOption(key)) or settings[key] or 50
end
function QT:GetAudioSound(key)
	local cue = byKey[key]
	if not cue then return end
	return self:ValidateAudioSetting(cue.soundKey, self:GetOption(cue.soundKey)) or cue.sound
end
function QT:ResetAudioSettings()
	return self:SetOptions(self:DeepCopy(settings))
end

-- Test runners replace QT's API table. These extra guards also prevent a live
-- fixture that copied the real adapters from playing or stopping real audio.
QT.API.SupportsAudioVolume = function() return type(PlaySoundFile) == "function" end
QT.API.PlayAudioFile = function(path)
	if QT.isRunningTests or type(PlaySoundFile) ~= "function" then return false end
	return PlaySoundFile(path, "SFX")
end
QT.API.StopAudioFile = function(handle)
	if QT.isRunningTests or type(StopSound) ~= "function" then return false end
	StopSound(handle)
	return true
end
function QT:SupportsAudioVolume()
	local getter = self.API and self.API.SupportsAudioVolume
	if type(getter) ~= "function" then return false end
	local ok, supported = pcall(getter)
	return ok and self:CanAccessValue(supported) and supported == true
end
local function Now(a)
	local getter = a.API and a.API.GetTime
	if type(getter) ~= "function" then return end
	local ok, value = pcall(getter)
	local n = ok and a:SafeToNumber(value)
	if n and n == n and math.abs(n) ~= math.huge then return n end
end
local function CombatMuted(a)
	if a:GetOption("audioMuteInCombat") ~= true then return false end
	local getter = a.API and a.API.InCombatLockdown
	if type(getter) ~= "function" then return true end
	local ok, value = pcall(getter)
	return not ok or not a:CanAccessValue(value) or value ~= false
end
function QT:StopQTAudio()
	local state = rawget(self, "audioState")
	if not state or not state.handle then return end
	local handle = state.handle
	state.handle = nil
	local stop = self.API and self.API.StopAudioFile
	if type(stop) == "function" then pcall(stop, handle) end
end
function QT:ResetQTAudio()
	self:StopQTAudio()
	self.audioState = nil
end
function QT:InitializeQTAudio()
	self:ResetQTAudio()
	self.audioState = { profile = self.db and self.db.profile, identities = {}, playedAt = {}, counters = {} }
end
function QT:UpdateQTAudio()
	local state = rawget(self, "audioState")
	if not state then return end
	if not self.isEnabled or self.isLoggingOut or self.isLeavingWorld
		or state.profile ~= (self.db and self.db.profile) then self:ResetQTAudio(); return end
	if self:GetOption("audioEnabled") ~= true or CombatMuted(self) then self:StopQTAudio() end
end
function QT:ApplyAudioSettings(profileChanged)
	if profileChanged then
		self:ResetQTAudio()
		if self.isEnabled and not self.isLoggingOut and not self.isLeavingWorld then self:InitializeQTAudio() end
	else self:StopQTAudio() end
	if self.RefreshAudioWindow then self:RefreshAudioWindow() end
end

local function Play(a, key, identity, preview)
	local cue, state = byKey[key], rawget(a, "audioState")
	if not cue or not state or not a.isEnabled or a.isLoggingOut or a.isLeavingWorld
		or state.profile ~= (a.db and a.db.profile) then return false end
	if not preview and identity ~= nil then
		if state.identities[key] == identity then return false end
		state.identities[key] = identity
	end
	if a:GetOption("audioEnabled") ~= true or CombatMuted(a)
		or (not preview and a:GetOption(cue.enabledKey) ~= true) then return false end
	local gain = a:GetAudioVolume("audioVolume") * a:GetAudioVolume(cue.volumeKey) / 100
	if gain <= 0 then return false end
	-- Files encode the same master at 1% increments; zero never calls native
	-- playback, while positive combined gain always has an audible file level.
	local level = math.max(1, math.min(100, math.floor(gain + 0.5)))
	local now = Now(a)
	if not now then return false end
	local priority = cue.priority or 1
	local interval = a:GetAudioVolume("audioInterval")
	if (preview and state.previewAt and now - state.previewAt < 0.15)
		or (not preview and state.playedAt[key] and now - state.playedAt[key] < cue.cooldown)
		or (not preview and state.lastAt and now - state.lastAt < interval and priority <= (state.priority or 1)) then
		state.counters.suppressed = (state.counters.suppressed or 0) + 1
		return false
	end
	local play = a.API and a.API.PlayAudioFile
	if type(play) ~= "function" then return false end
	a:StopQTAudio()
	local path = "Interface\\AddOns\\QuestTogether\\Media\\Audio\\" .. a:GetAudioSound(key) .. "\\" .. string.format("%03d", level) .. ".ogg"
	local ok, accepted, handle = pcall(play, path)
	if not ok or not a:CanAccessValue(accepted) or accepted ~= true then
		state.counters.failed = (state.counters.failed or 0) + 1
		return false
	end
	local h = a:SafeToNumber(handle)
	if h and h == h and h > 0 and h < math.huge then state.handle = h end
	state.lastAt, state.priority = now, priority
	if preview then state.previewAt = now else state.playedAt[key] = now end
	state.counters.played = (state.counters.played or 0) + 1
	return true
end
function QT:PlayAudioCue(key, identity) return Play(self, key, identity, false) end
function QT:PreviewAudioCue(key)
	if not rawget(self, "audioState") and self.isEnabled then self:InitializeQTAudio() end
	return Play(self, key, nil, true)
end

function QT:ObservePartyAnnouncementAudio(event, sender)
	if not event or not self:IsGroupedSender(sender) or self:IsSelfSender(sender) or self:IsIgnoredPlayerName(sender) then return end
	local cue = event.eventType == "QUEST_READY_TO_TURN_IN" and "questReady"
		or event.eventType == "QUEST_COMPLETED" and "questTurnIn"
		or event.eventType == "QUEST_PROGRESS" and "objectiveProgress"
	if not cue then return end
	-- Delayed events can still repair party progress without announcing an old
	-- milestone as if it just happened. Never queue a cue while time is unknown.
	local now = self:GetAnnouncementServerTime()
	local stamp = self:SafeToNumber(event.occurredAt)
	if not now or not stamp then return end
	local age = now - stamp
	if age >= -1 and age <= 30 then self:PlayAudioCue(cue) end
end
