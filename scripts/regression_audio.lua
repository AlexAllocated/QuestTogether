-- Real QT policy, private playback adapters: never invoke the live sound engine.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local function Fixture()
	local a = setmetatable({ isEnabled = true, now = 10, plays = {}, stops = {},
		db = { profile = QT:DeepCopy(QT.DEFAULTS.profile) } }, { __index = QT })
	function a:GetOption(key) return self.db.profile[key] end
	function a:IsSelfSender(name) return name == "Me" end
	function a:IsGroupedSender(name) return name == "Friend" end
	function a:IsIgnoredPlayerName() return self.ignored == true end
	function a:RefreshAudioWindow() end
	a.API = {
		GetTime = function() return a.now end,
		GetServerTime = function() return 1800000000 + math.floor(a.now) end,
		InCombatLockdown = function() return a.combat == true end,
		SupportsAudioVolume = function() return true end,
		PlayAudioFile = function(path)
			a.plays[#a.plays + 1] = path
			if a.fail then return false end
			return true, #a.plays
		end,
		StopAudioFile = function(handle) a.stops[#a.stops + 1] = handle end,
	}
	a:InitializeQTAudio()
	return a
end
local function Ends(value, suffix) assert(value:sub(-#suffix) == suffix, value) end

QT:RegisterTest("audio settings validate false zero sound choices and preserve nonaudio preferences on reset", function()
	local a = Fixture()
	Equal(a:ValidateSetting("audioEnabled", false), false)
	Equal(a:ValidateSetting("audioVolume", 0), 0)
	Equal(a:ValidateSetting("audioFocusSound", "spellbook"), "spellbook")
	Equal(a:ValidateSetting("audioFocusSound", "../other"), nil)
	Equal(a:ValidateSetting("audioVolume", -1), nil)
	Equal(a:ValidateSetting("audioVolume", math.huge), nil)
	Equal(a:ValidateSetting("audioInterval", 0), nil)
	Equal(a:ValidateSetting("audioInterval", 0.75), 0.75)
	function a:SetOptions(values)
		for key, value in pairs(values) do
			assert(self:IsAudioSetting(key)); self.db.profile[key] = value
		end
		return true
	end
	a.db.profile.lightMode = true
	a.db.profile.audioEnabled = false
	a.db.profile.audioFocusSound = "scroll"
	assert(a:ResetAudioSettings())
	Equal(a:GetOption("lightMode"), true)
	Equal(a:GetOption("audioEnabled"), true)
	Equal(a:GetAudioSound("focus"), "selection")
	local enabled = 0
	for _, cue in ipairs(a:GetAudioCueCatalog()) do
		if a:GetOption(cue.enabledKey) then enabled = enabled + 1 end
	end
	Equal(enabled, 2, "only attention and focus sounds start enabled")
end)

QT:RegisterTest("audio playback uses owned gain files and never emits sound at zero volume", function()
	local a = Fixture()
	assert(a:PlayAudioCue("attention", {}))
	Ends(a.plays[1], "\\chime\\030.ogg")
	a.now = 12
	assert(a:PlayAudioCue("focus", 42))
	Ends(a.plays[2], "\\selection\\020.ogg")
	Equal(a.stops[1], 1, "only the previous QT handle is stopped")
	a.db.profile.audioVolume = 0
	a.now = 14
	Equal(a:PlayAudioCue("focus", 43), false)
	Equal(#a.plays, 2)
	a.db.profile.audioVolume, a.db.profile.audioFocusVolume = 5, 5
	assert(a:PlayAudioCue("focus", 44))
	Ends(a.plays[3], "\\selection\\001.ogg")
	a.now = 16
	a.db.profile.audioVolume, a.db.profile.audioFocusVolume = 100, 100
	a.db.profile.audioFocusSound = "spellbook"
	assert(a:PlayAudioCue("focus", 45))
	Ends(a.plays[4], "\\spellbook\\100.ogg")
	a:ResetQTAudio()
	Equal(a.stops[#a.stops], 4)
	Equal(a:PlayAudioCue("attention", {}), false, "teardown must not lazily restart automatic audio")
end)

QT:RegisterTest("audio suppresses repeats and bursts while attention can preempt a lower priority cue", function()
	local a = Fixture()
	local request = {}
	assert(a:PlayAudioCue("focus", 42))
	a.now = 10.1
	assert(a:PlayAudioCue("attention", request), "a real prompt can interrupt a focus cue")
	Equal(a.stops[1], 1)
	a.now = 12
	Equal(a:PlayAudioCue("attention", request), false, "repainting the same request stays silent")
	assert(a:PlayAudioCue("attention", {}))
	a.now = 12.2
	Equal(a:PlayAudioCue("focus", 43), false)
	a.now = 15
	Equal(a:PlayAudioCue("focus", 43), false, "dropped notifications must not catch up later")
	assert(a:PlayAudioCue("focus", 44))
	a.db.profile.audioObjectiveProgressEnabled = true
	for i = 1, 100 do a.now = a.now + 0.01; a:PlayAudioCue("objectiveProgress") end
	assert(#a.plays <= 5, "a burst is not a playback queue")
	Equal(a.audioState.pending, nil)
end)

QT:RegisterTest("audio mute profile disable logout and unavailable playback do not leak or replay handles", function()
	local a = Fixture()
	assert(a:PlayAudioCue("focus", 42))
	a.db.profile.audioMuteInCombat, a.combat = true, true
	a:UpdateQTAudio()
	Equal(a.stops[1], 1)
	Equal(a:PlayAudioCue("attention", {}), false)
	a.combat = false
	a.db.profile.audioEnabled = false
	Equal(a:PreviewAudioCue("attention"), false)
	a.db.profile.audioEnabled = true
	a.now = 20
	assert(a:PlayAudioCue("attention", {}))
	local oldProfile = a.db.profile
	a.db.profile = a:DeepCopy(oldProfile)
	Equal(a:PlayAudioCue("focus", 43), false)
	a:ApplyAudioSettings(true)
	Equal(a.audioState.profile, a.db.profile)
	assert(a:PlayAudioCue("focus", 43))
	a.isEnabled = false
	a:UpdateQTAudio()
	Equal(a.audioState, nil)
	Equal(a:PreviewAudioCue("attention"), false)
	a.isEnabled = true
	a:InitializeQTAudio()
	a.isLoggingOut = true
	Equal(a:PlayAudioCue("focus", 44), false)
	a:UpdateQTAudio()
	Equal(a.audioState, nil)
	a.isLoggingOut = false
	a:InitializeQTAudio()
	a.API.PlayAudioFile = nil
	Equal(a:PlayAudioCue("focus", 45), false)
end)

QT:RegisterTest("audio preview honors master volume and combat mute but can audition disabled events", function()
	local a = Fixture()
	Equal(a:GetOption("audioQuestReadyEnabled"), false)
	assert(a:PreviewAudioCue("questReady"))
	Ends(a.plays[1], "\\completion\\025.ogg")
	Equal(a:PreviewAudioCue("questReady"), false, "rapid preview clicks are bounded")
	a.now = 10.2
	a.db.profile.audioQuestReadySound = "scroll"
	assert(a:PreviewAudioCue("questReady"))
	Ends(a.plays[2], "\\scroll\\025.ogg")
	Equal(a.stops[1], 1)
	a.db.profile.audioQuestReadyVolume = 0
	a.now = 11
	Equal(a:PreviewAudioCue("questReady"), false)
	a.db.profile.audioQuestReadyVolume = 50
	a.combat, a.db.profile.audioMuteInCombat = true, true
	Equal(a:PreviewAudioCue("questReady"), false)
	a.combat = false
	a.fail = true
	Equal(a:PreviewAudioCue("questReady"), false)
	Equal(a.audioState.handle, nil)
	Equal(a.audioState.counters.failed, 1)
end)

QT:RegisterTest("party audio accepts fresh remote milestones and rejects stale unknown future and unrelated events", function()
	local a = Fixture()
	a.db.profile.audioQuestReadyEnabled = true
	local function Ready(age)
		return { eventType = "QUEST_READY_TO_TURN_IN", occurredAt = a.API.GetServerTime() - (age or 0) }
	end
	a:ObservePartyAnnouncementAudio(Ready(), "Me")
	a:ObservePartyAnnouncementAudio(Ready(), "Stranger")
	a.ignored = true
	a:ObservePartyAnnouncementAudio(Ready(), "Friend")
	Equal(#a.plays, 0)
	a.ignored = false
	a:ObservePartyAnnouncementAudio(Ready(), "Friend")
	Equal(#a.plays, 1)
	a.now = 20
	a:ObservePartyAnnouncementAudio({ eventType = "QUEST_ACCEPTED", occurredAt = a.API.GetServerTime() }, "Friend")
	a:ObservePartyAnnouncementAudio({ eventType = "QUEST_PROGRESS", occurredAt = a.API.GetServerTime() }, "Friend")
	Equal(#a.plays, 1, "frequent progress stays silent by default")
	for _, age in ipairs({ 31, 600, -2, math.huge }) do
		a:ObservePartyAnnouncementAudio(Ready(age), "Friend")
	end
	a:ObservePartyAnnouncementAudio({ eventType = "QUEST_READY_TO_TURN_IN" }, "Friend")
	Equal(#a.plays, 1, "unknown or stale timestamps do not announce old milestones")
	a:ObservePartyAnnouncementAudio(Ready(30), "Friend")
	Equal(#a.plays, 2, "freshness uses source time and permits the 30-second delivery boundary")
	a.now = 25
	a:ObservePartyAnnouncementAudio(Ready(-1), "Friend")
	Equal(#a.plays, 3, "second-resolution clocks allow one second of skew")
	local event = Ready()
	a.API.GetServerTime = function() return nil end
	a.now = 30
	a:ObservePartyAnnouncementAudio(event, "Friend")
	Equal(#a.plays, 3, "an unavailable local server clock fails quiet")
end)

_G.QuestTogether:RecordTestModule("scripts/regression_audio.lua")
