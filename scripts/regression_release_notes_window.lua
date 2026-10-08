-- This module runs in /qt test too: all regions and adapters are private.
local QuestTogether = _G.QuestTogether
local activeFixtures
local function Register(name, callback, options)
	QuestTogether:RegisterTest(name, function()
		activeFixtures = {}
		local ok, err = pcall(callback)
		local fixtures = activeFixtures
		activeFixtures = nil
		for _, fixture in ipairs(fixtures) do
			assert((fixture.invalidCalls or 0) == 0, "a swallowed error hid an unsafe release notes UI call")
		end
		if not ok then
			error(err, 0)
		end
	end, options)
end
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Region(addon, parent, kind)
	return QuestTogether:CreateTestUIRegion(addon, parent, kind)
end

local function Fixture()
	local addon = setmetatable(
		{ options = {}, regions = {}, frames = {}, settingsOpened = 0 },
		{ __index = QuestTogether }
	)
	addon.parent = Region(addon, nil, "Parent")
	addon.parent.width, addon.parent.height = 1920, 1080
	function addon:GetOption(key)
		return self.options[key]
	end
	function addon:GetReleaseNotesUIParent()
		return self.parent
	end
	function addon:CreateReleaseNotesUIFrame(kind, name, parent, template)
		if name or template or self.blocked or parent:IsForbidden() then
			self.invalidCalls = (self.invalidCalls or 0) + 1
			error("unsafe frame creation")
		end
		local frame = Region(self, parent, kind)
		self.frames[#self.frames + 1] = frame
		self.regions[#self.regions + 1] = frame
		return frame
	end
	addon.GetOwnedUIParent = addon.GetReleaseNotesUIParent
	addon.CreateOwnedWindowFrame = addon.CreateReleaseNotesUIFrame
	function addon:GetWindowDragCursor() return 600, 500 end
	function addon:IsRuntimeRestricted()
		return self.blocked == true
	end
	function addon:OpenOptionsWindow()
		self.settingsOpened = self.settingsOpened + 1
		if self.settingsThrows then
			error("fixture settings unavailable")
		end
		return self.settingsResult ~= false
	end
	function addon:OpenDiscordSupport()
		self.discordOpened = (self.discordOpened or 0) + 1
		return self.discordResult ~= false
	end
	activeFixtures[#activeFixtures + 1] = addon
	return addon
end

local function Notes(count)
	local items = {}
	for index = 1, count or 2 do
		items[index] = "Improvement " .. index .. ": quest progress is easier to follow with your party."
	end
	return {
		version = "5.9.2",
		welcome = "Quest progress and celebrations for your party.",
		sections = {
			{ title = "Latest changes", items = items },
		},
	}
end

Register("release notes window sizes to content and reuses only owned frames", function()
	local a = Fixture()
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	local frame, frameCount = a.releaseNotesWindow, #a.frames
	assert(frame:IsVisible())
	Equal(frame.title.text, "QuestTogether 5.9.2")
	Equal(frame.headerLogo.texture, "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon")
	Equal(frame.logo, nil)
	Equal(frame.labels[1].points[1][3], 0)
	Equal(frame.labels[1].text, "Welcome to QuestTogether")
	Equal(frame.labels[3].text, "Latest changes")
	assert(frame.labels[4].text:find("Improvement 1", 1, true))
	Equal(frame.slider.shown, false)
	Equal(frame.maximumScroll, 0)
	Equal(a.parent.writes, 0)
	Equal(next(a.parent.scripts), nil)
	local firstHeight = frame.height
	assert(a:RenderReleaseNotesWindow(Notes(40), "5.10.0", false))
	Equal(a.releaseNotesWindow, frame)
	Equal(#a.frames, frameCount)
	Equal(frame.labels[1].text, "What's new")
	assert(frame.height > firstHeight and frame.maximumScroll > 0 and frame.slider.shown)
	assert(frame.height * frame.scale < a.parent.height)
	assert(a:RenderReleaseNotesWindow(Notes(1), "5.10.0", false))
	Equal(frame.slider.shown, false)
	Equal(frame.labels[5].shown, false)
	Equal(frame.scroll.offset, 0)
	Equal(frame.slider.value, 0)
	frame.settings.scripts.OnClick({})
	Equal(a.settingsOpened, 1)
	Equal(frame:IsVisible(), false)
	assert(a:RenderReleaseNotesWindow(Notes(1), "5.10.0", false))
	frame.close.scripts.OnClick({})
	Equal(frame:IsVisible(), false)
	Equal(frame.discord.label.text, "Join our Discord")
end)

Register("release notes browse history by page or dated picker and reopen at latest", function()
	local a = Fixture()
	a.hasLoggedIn, a.db = true, { global = {} }
	a.GetAddonVersion = function()
		return "5.9.2"
	end
	a.releaseNotes = Notes(2)
	a.releaseNotesDates = { ["5.9.2"] = "2026-09-27" }
	local older, oldest = Notes(40), Notes(1)
	older.version, oldest.version = "5.9.1", "5.9.0"
	older.sections[1].illustration = "quest-partners"
	a.releaseNotesHistory = {
		{ version = older.version, date = "2026-09-27", locales = { enUS = older } },
		{ version = oldest.version, date = "2026-09-26", locales = { enUS = oldest } },
	}
	assert(a:OpenReleaseNotes())
	local frame = a.releaseNotesWindow
	Equal(a.releaseNotesBrowser.index, 1)
	Equal(frame.navigation[4].enabled, false)
	Equal(frame.navigation[5].enabled, false)
	Equal(#frame.navigation, 5)
	assert(frame.navigation[1].enabled)
	for _, index in ipairs({ 1, 2, 4, 5 }) do
		local button = frame.navigation[index]
		for _, method in ipairs({ "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture" }) do
			Equal(button.buttonTextures[method].texture, button.buttonTextures.SetNormalTexture.texture)
		end
	end
	frame.navigation[1].buttonState = "PUSHED"
	frame.navigation[1].scripts.OnClick({})
	Equal(a.releaseNotesBrowser.index, 3)
	Equal(frame.navigation[1].enabled, false)
	Equal(frame.navigation[1].buttonState, "NORMAL")
	Equal(frame.navigation[1].buttonStateLocked, false)
	Equal(frame.navigation[2].enabled, false)
	frame.navigation[5].buttonState = "PUSHED"
	frame.navigation[5].scripts.OnClick({})
	Equal(frame.navigation[5].buttonState, "NORMAL")
	Equal(frame.navigation[5].enabled, false)
	Equal(a.releaseNotesBrowser.index, 1)
	frame.navigation[2].scripts.OnClick({})
	Equal(frame.title.text, "QuestTogether 5.9.1")
	Equal(frame.navigation[5].enabled, true)
	assert(frame.maximumScroll > 0 and frame.partnerExamples.shown)
	frame.scroll.scripts.OnMouseWheel({}, -10)
	assert(frame.scrollOffset > 0)
	frame.navigation[2].scripts.OnClick({})
	Equal(a.releaseNotesBrowser.index, 3)
	Equal(frame.navigation[2].enabled, false)
	Equal(frame.scrollOffset, 0)
	Equal(frame.partnerExamples.shown, false)
	Equal(a:ShowReleaseNotesPage(4), false)
	Equal(a:ShowReleaseNotesPage(0), false)
	Equal(a:ShowReleaseNotesPage(1.5), false)
	frame.navigation[3].scripts.OnClick({})
	assert(a.releaseNotesBrowser.history)
	Equal(frame.logo, nil)
	assert(frame.historyRows[3].date.text:find("2026-09-26", 1, true))
	frame.historyRows[2].scripts.OnClick({})
	Equal(a.releaseNotesBrowser.index, 2)
	Equal(a.releaseNotesBrowser.history, false)
	Equal(frame.headerLogo.shown, true)
	Equal(frame.historyRows[2].shown, false)
	Equal(a.db.global.releaseNotesSeenVersion, "5.9.2")
	local frames = #a.frames
	frame.navigation[3].scripts.OnClick({})
	frame.navigation[3].scripts.OnClick({})
	Equal(#a.frames, frames)
	frame.navigation[5].scripts.OnClick({})
	Equal(a.releaseNotesBrowser.index, 1)
	Equal(frame.navigation[5].enabled, false)
	frame.navigation[3].scripts.OnClick({})
	Equal(frame.navigation[5].enabled, true)
	frame.navigation[5].scripts.OnClick({})
	Equal(a.releaseNotesBrowser.history, false)
	Equal(frame.navigation[5].enabled, false)
	frame.navigation[2].scripts.OnClick({})
	frame.close.scripts.OnClick({})
	assert(a:OpenReleaseNotes())
	Equal(a.releaseNotesBrowser.index, 1)
	Equal(a.releaseNotesBrowser.history, false)
	-- Retained UI callbacks must respect restrictions and never acknowledge history.
	a.blocked = true
	frame.navigation[2].scripts.OnClick({})
	frame.historyRows[3].scripts.OnClick({})
	Equal(a.releaseNotesBrowser.index, 1)
	Equal(a:ShowReleaseNotesPage(2), false)
	a.blocked = false
end)

Register("release notes settings action keeps the welcome visible when settings cannot open", function()
	local a = Fixture()
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	local frame = a.releaseNotesWindow
	a.settingsResult = false
	frame.settings.scripts.OnClick({})
	assert(frame:IsVisible())
	a.settingsThrows = true
	frame.settings.scripts.OnClick({})
	assert(frame:IsVisible())
	a.settingsThrows, a.settingsResult = false, true
	frame.settings.scripts.OnClick({})
	Equal(frame:IsVisible(), false)
	Equal(a.settingsOpened, 3)
end)

Register("release notes overflow scrolling clamps and resets when reopened", function()
	local a = Fixture()
	a.parent.width, a.parent.height = 480, 340
	assert(a:RenderReleaseNotesWindow(Notes(40), "5.9.2", false))
	local frame = a.releaseNotesWindow
	assert(frame.height * frame.scale <= a.parent.height)
	assert(frame.width * frame.scale <= a.parent.width)
	frame.scroll.scripts.OnMouseWheel({}, -2)
	Equal(frame.scroll.offset, 72)
	Equal(frame.slider.value, 72)
	frame.slider.scripts.OnValueChanged({}, frame.maximumScroll + 100)
	Equal(frame.scroll.offset, frame.maximumScroll)
	frame.slider.scripts.OnMouseWheel({}, 10000)
	Equal(frame.scroll.offset, 0)
	frame.slider.scripts.OnValueChanged({}, math.huge)
	Equal(frame.scroll.offset, 0)
	frame.slider.scripts.OnValueChanged({}, 100)
	assert(a:RenderReleaseNotesWindow(Notes(40), "5.9.2", false))
	Equal(frame.scroll.offset, 0)
	Equal(frame.slider.value, 0)
end)

Register("release notes Discord button opens support and dismisses only after success", function()
	local a = Fixture()
	assert(a:RenderReleaseNotesWindow(Notes(), "5.10.0", false))
	local frame = a.releaseNotesWindow
	a.discordResult = false
	frame.discord.scripts.OnClick({})
	assert(frame:IsVisible())
	a.blocked = true
	frame.discord.scripts.OnClick({})
	Equal(a.discordOpened, 1)
	a.blocked, a.discordResult = false, true
	frame.discord.scripts.OnClick({})
	Equal(a.discordOpened, 2)
	Equal(frame:IsVisible(), false)
end)

Register("release notes only confirms actual visibility and retries unavailable layout", function()
	local a = Fixture()
	a.parent.shown = false
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	assert(a.releaseNotesWindow:IsShown())
	Equal(a.releaseNotesWindow:IsVisible(), false)
	a.parent.shown = true
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	a.measureUnavailable = true
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(a.releaseNotesWindow:IsShown(), false)
	a.measureUnavailable = false
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	local b = Fixture()
	b.parent.width = 0
	Equal(b:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(#b.frames, 0)
	b.parent.width = math.huge
	Equal(b:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(#b.frames, 0)
	b.parent.width = 800
	assert(b:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
end)

Register("release notes stale callbacks and rendering respect restrictions and quarantine", function()
	for _, boundary in ipairs({ "restricted", "forbidden", "protected" }) do
		local a = Fixture()
		assert(a:RenderReleaseNotesWindow(Notes(40), "5.9.2", false))
		local frame = a.releaseNotesWindow
		if boundary == "restricted" then
			a.blocked = true
		else
			a.parent[boundary] = true
		end
		local writes = 0
		for _, region in ipairs(a.regions) do
			writes = writes + region.writes
		end
		frame.close.scripts.OnClick({})
		frame.settings.scripts.OnClick({})
		frame.scroll.scripts.OnMouseWheel({}, -1)
		frame.slider.scripts.OnValueChanged({}, 36)
		Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false), false)
		Equal(a.settingsOpened, 0)
		local after = 0
		for _, region in ipairs(a.regions) do
			after = after + region.writes
		end
		if boundary == "restricted" then assert(after > writes, "owned teardown should hide and stop descendants")
		else Equal(after, writes) end
		Equal(frame.shown, boundary ~= "restricted")
		a.blocked, a.parent.forbidden, a.parent.protected = false, false, false
		assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false))
	end
	local a = Fixture()
	a.blocked = true
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(#a.frames, 0)
	a.blocked, a.parent.forbidden = false, true
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(#a.frames, 0)
end)

Register("release notes rejects an individually forbidden cached label without touching it", function()
	local a = Fixture()
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false))
	local label = a.releaseNotesWindow.labels[4]
	label.forbidden = true
	local writes = label.writes
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false), false)
	Equal(label.writes, writes)
	Equal(a.releaseNotesWindow:IsShown(), false)
	label.forbidden = false
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false))
end)

Register("release notes interrupted construction remains hidden and retries safely", function()
	local a = Fixture()
	a.failTextureCreate = true
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	local partial = a.releaseNotesWindow
	assert(partial and not partial:IsShown() and not partial.ready)
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	assert(a.releaseNotesWindow ~= partial and a.releaseNotesWindow.ready)
	Equal(partial:IsShown(), false)
	Equal(a.parent.writes, 0)
end)

Register("settings chat destination selection rejects restrictions without changing or replaying the choice", function()
	local a = Fixture()
	a.db = { profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile) }
	a.opens, a.closes, a.refreshes = 0, 0, 0
	a.API = {
		Delay = function()
			error("a blocked settings choice must not be queued")
		end,
	}
	function a:GetResolvedChatLogDestination()
		return self.db.profile.chatLogDestination
	end
	function a:EnsureQuestLogChatFrame()
		self.opens = self.opens + 1
		return {}
	end
	function a:ApplyMainChatFontSizeToChatFrame() end
	function a:CloseQuestLogChatFrame()
		self.closes = self.closes + 1
	end
	function a:RefreshOptionsWindow()
		self.refreshes = self.refreshes + 1
	end
	for _, transition in ipairs({ { "main", "separate" }, { "separate", "main" } }) do
		a.db.profile.chatLogDestination = transition[1]
		a.blocked = true
		local opens, closes, refreshes = a.opens, a.closes, a.refreshes
		Equal(a:ApplyOptionsDropdownSelection("chatLogDestination", transition[2]), false)
		Equal(a.db.profile.chatLogDestination, transition[1])
		Equal(a.opens, opens)
		Equal(a.closes, closes)
		Equal(a.refreshes, refreshes)
		a.blocked = false
		Equal(a.db.profile.chatLogDestination, transition[1], "unblocking does not replay a rejected choice")
		assert(a:ApplyOptionsDropdownSelection("chatLogDestination", transition[2]))
		Equal(a.db.profile.chatLogDestination, transition[2])
		Equal(a.refreshes, refreshes + 1)
		Equal(a.opens, opens + (transition[2] == "separate" and 1 or 0))
		Equal(a.closes, closes + (transition[2] == "main" and 1 or 0))
	end
	-- Ordinary preference-only dropdown edits retain their existing behavior.
	a.blocked = true
	assert(a:ApplyOptionsDropdownSelection("showProgressFor", "party_only"))
	Equal(a.db.profile.showProgressFor, "party_only")
end)

Register("release notes visual examples occupy scroll space and hide when absent", function()
	local a = Fixture()
	local notes = Notes(8)
	assert(a:RenderReleaseNotesWindow(notes, "5.13.0", false))
	local frame = a.releaseNotesWindow
	local initialHeight = frame.content.height
	notes.sections[1].illustration = "quest-partners"
	assert(a:RenderReleaseNotesWindow(notes, "5.13.0", false))
	assert(frame.partnerExamples.shown)
	Equal(#frame.partnerExamples.columns, 2)
	assert(frame.content.height >= initialHeight + 120)
	local count = #a.regions
	assert(a:RenderReleaseNotesWindow(notes, "5.13.0", false))
	Equal(#a.regions, count)
	notes.sections[1].illustration = nil
	assert(a:RenderReleaseNotesWindow(notes, "5.13.0", false))
	assert(not frame.partnerExamples.shown)
end)

Register("release notes screenshots match client names resize reuse and hide on other pages", function()
	for _, regional in ipairs({ false, true }) do
		local a = Fixture()
		function a:UsesRegionalPlayerNames() return regional end
		local notes = Notes()
		notes.sections[1].illustration = "party-quest-log"
		notes.sections[2] = { title = "Objectives", items = { "Expand progress." }, illustration = "party-quest-objectives" }
		assert(a:RenderReleaseNotesWindow(notes, "6.4.0", false))
		local frame = a.releaseNotesWindow
		local asset = regional and "PartyQuestLogForever" or "PartyQuestLogRetail"
		local screenshot = frame.releaseScreenshots[asset]
		assert(screenshot and screenshot.shown)
		assert(screenshot.texture:find(asset, 1, true))
		local expectedRatio = regional and 899 / 1560 or 898 / 1564
		assert(math.abs(screenshot.height / screenshot.width - expectedRatio) < 0.0001)
		Equal(frame.releaseScreenshots.PartyQuestObjectivesForever ~= nil, regional)
		local count = #a.regions
		frame.userWidth = 900
		assert(a:RenderReleaseNotesWindow(notes, "6.4.0", false))
		Equal(#a.regions, count)
		assert(math.abs(screenshot.height / screenshot.width - expectedRatio) < 0.0001)
		assert(a:RenderReleaseNotesWindow(Notes(), "6.3.1", false))
		for _, image in pairs(frame.releaseScreenshots) do assert(not image.shown) end
		screenshot.forbidden = true
		local writes = screenshot.writes
		Equal(a:RenderReleaseNotesWindow(notes, "6.4.0", false), false)
		Equal(screenshot.writes, writes)
	end
end)

Register("release notes visual examples quarantine forbidden regions and recover", function()
	local a = Fixture()
	local notes = Notes()
	notes.sections[1].illustration = "quest-partners"
	assert(a:RenderReleaseNotesWindow(notes, "5.13.0", false))
	local gallery = a.releaseNotesWindow.partnerExamples
	gallery.forbidden = true
	local writes = gallery.writes
	Equal(a:RenderReleaseNotesWindow(notes, "5.13.0", false), false)
	Equal(gallery.writes, writes)
	gallery.forbidden = false
	assert(a:RenderReleaseNotesWindow(notes, "5.13.0", false))
	assert(gallery.shown)
end)

local function LatestVisibleNotes(locale)
	local notes = QuestTogether.releaseNotesByLocale[locale] or QuestTogether.releaseNotes
	if #notes.sections == 0 then
		local entry = QuestTogether.releaseNotesHistory[1]
		notes = entry.locales[locale] or entry.locales.enUS
	end
	return notes
end

Register("release notes render translated content with owned controls in every locale", function()
	local previous = QuestTogether.localizationTestLocale
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		QuestTogether.localizationTestLocale = locale
		local a = Fixture()
		local notes = LatestVisibleNotes(locale)
		assert(a:RenderReleaseNotesWindow(notes, notes.version, false))
		Equal(a.releaseNotesWindow.labels[1].text, QuestTogether.TranslateForLocale("What's new", locale))
		Equal(a.releaseNotesWindow.labels[2].text, notes.welcome)
		Equal(a.releaseNotesWindow.discord.label.text, QuestTogether.TranslateForLocale("Join our Discord", locale))
	end
	QuestTogether.localizationTestLocale = previous
end)

Register("client locale renders current notes and window navigation", function()
	assert(QuestTogether.localizationTestLocale == nil)
	local locale = QuestTogether:GetEventLocale()
	local a = Fixture()
	local notes = LatestVisibleNotes(locale)
	assert(a:RenderReleaseNotesWindow(notes, notes.version, false))
	Equal(a.releaseNotesWindow.labels[1].text, QuestTogether.TranslateForLocale("What's new", locale))
	Equal(a.releaseNotesWindow.labels[2].text, notes.welcome)
	Equal(a.releaseNotesWindow.discord.label.text, QuestTogether.TranslateForLocale("Join our Discord", locale))
end, { locale = "client" })

Register("release notes share the scroll theme without resetting browsing or acknowledging versions", function()
	local a = Fixture()
	local notes = Notes(40)
	notes.sections[1].illustration = "quest-partners"
	assert(a:RenderReleaseNotesWindow(notes, "6.2.3", false))
	local frame = a.releaseNotesWindow
	Equal(frame.strata, "MEDIUM")
	Equal(frame.parchmentPieces[1].texture, a:GetScrollWindowTheme().texture)
	Equal(frame.parchmentPieces[1].vertexColor[1], 0.14)
	Equal(frame.title.font, "GameFontNormalLarge")
	Equal(frame.headerLogo.texture, "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon")
	frame.scroll.scripts.OnMouseWheel({}, -3)
	local offset, count, heading = frame.scrollOffset, #a.regions, frame.labels[1].text
	a.releaseNotesBrowser = { index = 2, history = false }
	a.db = { global = { releaseNotesSeenVersion = "6.2.3" } }
	function a:ScheduleDeferredWork(kind, key, callback)
		Equal(kind, "foreign_frame_mutation")
		Equal(key, "release_notes_theme")
		self.themeUpdate = callback
	end
	a.options.lightMode = true
	a:QueueReleaseNotesThemeRefresh()
	a.themeUpdate()
	Equal(frame.parchmentPieces[1].vertexColor[1], 1)
	assert(frame.labels[1].textColor[1] < 0.3)
	assert(frame.labels[2].textColor[1] < 0.3)
	for _, label in ipairs(frame.partnerExamples.themeLabels) do
		assert(label.textColor[1] < 0.3)
	end
	Equal(frame.labels[1].text, heading)
	Equal(frame.scrollOffset, offset)
	Equal(a.releaseNotesBrowser.index, 2)
	Equal(a.db.global.releaseNotesSeenVersion, "6.2.3")
	Equal(#a.regions, count)
	a.options.lightMode = false
	a:QueueReleaseNotesThemeRefresh()
	a.blocked = true
	a.themeUpdate()
	Equal(frame.parchmentPieces[1].vertexColor[1], 1)
	a.blocked = false
	a.themeUpdate()
	Equal(frame.parchmentPieces[1].vertexColor[1], 0.14)
	assert(frame.labels[2].textColor[1] > 0.8)
	frame:Hide()
	a.options.lightMode = true
	a:QueueReleaseNotesThemeRefresh()
	a.themeUpdate()
	Equal(frame.shown, false)
	local retired = a.themeUpdate
	a.releaseNotesWindow = nil
	a.releaseNotesBrowser = nil
	assert(a:RenderReleaseNotesWindow(notes, "6.2.3", false))
	local writes = frame.parchmentPieces[1].writes
	retired()
	Equal(frame.parchmentPieces[1].writes, writes)
end)

Register("release notes resizing preserves pages and scroll while fixed rolls contain controls", function()
	local a = Fixture()
	a.db = { global = { releaseNotesSeenVersion = "6.2.3" } }
	assert(a:RenderReleaseNotesWindow(Notes(40), "6.2.3", false))
	local f = a.releaseNotesWindow
	Equal(#f.parchmentPieces, 9)
	Equal(f.parchmentPieces[2].height, 48)
	Equal(f.parchmentPieces[8].height, 40)
	Equal(f.logo, nil)
	assert(f.headerLogo.height + 11 <= 48)
	assert(f.settings.height + 8 <= 40 and f.discord.height + 8 <= 40)
	f.scroll.scripts.OnMouseWheel({}, -4)
	local offset, count = f.scrollOffset, #a.regions
	f.dragHandle.scripts.OnDragStart({})
	assert(f.dragging)
	f.dragHandle.scripts.OnDragStop({})
	Equal(f.dragging, nil)
	count = #a.regions -- the drag driver is allocated once on first pickup
	local originalWidth, originalHeight = f.width, f.height
	f.resizeGrip.scripts.OnMouseDown({}, "LeftButton")
	assert(f.sizing)
	Equal(f.sizingPoint, "BOTTOMRIGHT")
	Equal(f.sizingFromMouse, true)
	Equal(f.resizeArmedOnStart, true)
	Equal(f.userWidth, originalWidth)
	Equal(f.userHeight, originalHeight)
	Equal(f.width, originalWidth)
	Equal(f.height, originalHeight)
	f:SetSize(520, 380)
	Equal(f.width, 520)
	Equal(f.height, 380)
	Equal(f.scrollOffset, offset)
	Equal(f.scroll.height, 380 - 108 - 56)
	Equal(#a.regions, count)
	Equal(f.rendering, nil)
	f.resizeGrip.scripts.OnMouseUp({})
	Equal(f.sizing, nil)
	assert(a:RenderReleaseNotesWindow(Notes(1), "6.2.2", false))
	Equal(f.width, 520)
	Equal(f.height, 380)
	Equal(f.scrollOffset, 0)
	Equal(a.db.global.releaseNotesSeenVersion, "6.2.3")
	f.resizeGrip.scripts.OnMouseDown({}, "LeftButton")
	a.blocked = true
	local writes = f.writes
	f.scripts.OnSizeChanged({}, 700, 500)
	Equal(f.writes, writes)
	f.close.scripts.OnClick({})
	Equal(f.sizing, nil)
	Equal(f.resizing, nil)
	a.blocked = false
end)

Register("release notes reflow on reset profile restore and smaller display without reopening", function()
	local a = Fixture()
	a.db = { profile = {}, global = { releaseNotesSeenVersion = "6.2.3" } }
	function a:Print() end
	local notes = Notes(40)
	assert(a:RenderReleaseNotesWindow(notes, "6.2.2", false))
	local f = a.releaseNotesWindow
	f.scroll.scripts.OnMouseWheel({}, -4)
	local offset = f.scrollOffset
	a.db.profile.windowLayouts = { releaseNotes = { width = 520, height = 380, x = 0.85, y = 0.8 } }
	a:RefreshManagedWindowLayouts()
	Equal(f.width, 520)
	Equal(f.height, 380)
	Equal(f.scroll.width, 520 - 76)
	Equal(f.scroll.height, 380 - 164)
	Equal(f.slider.height, f.scroll.height)
	Equal(f.scrollOffset, offset)
	Equal(f.notes, notes)
	Equal(f.version, "6.2.2")
	assert(f:IsShown())
	f:Hide()
	a:ResetWindowLayouts()
	Equal(f.width, 700)
	Equal(f.height, 650)
	Equal(f.scroll.height, 650 - 164)
	Equal(f.scrollOffset, offset)
	assert(not f:IsShown(), "reset must not reopen dismissed notes")
	a.parent.width, a.parent.height = 640, 400
	a:DISPLAY_SIZE_CHANGED()
	Equal(f.scroll.width, f.width - 76)
	Equal(f.scroll.height, f.height - 164)
	Equal(f.slider.height, f.scroll.height)
	assert(f.height * f.scale <= a.parent.height and f.width * f.scale <= a.parent.width)
	assert(not f:IsShown())
	Equal(a.db.global.releaseNotesSeenVersion, "6.2.3")
end)

Register("release history uses reusable themed list rows with separate version date and title", function()
	local a = Fixture()
	local notes = Notes(2)
	local older = Notes(2)
	older.sections[1].title = string.rep("Long translated release title ", 8)
	a.releaseNotesBrowser = {
		index = 1,
		history = true,
		entries = {
			{ version = "6.2.3", date = "2026-10-06", notes = notes },
			{ version = "6.2.2", date = "2026-10-05", notes = older },
		},
	}
	assert(a:RenderReleaseNotesWindow(notes, "6.2.3", false))
	local f = a.releaseNotesWindow
	Equal(f.historyRows[1].version.text, "6.2.3")
	Equal(f.historyRows[1].date.text, "2026-10-06")
	Equal(f.historyRows[1].label.text, "Latest changes")
	assert(f.historyRows[2].height > f.historyRows[1].height)
	for _, region in ipairs(a.regions) do
		if region.parent == f.historyRows[1] then
			Equal(region.template, nil)
		end
	end
	local count = #a.regions
	a.options.lightMode = true
	assert(a:RenderReleaseNotesWindow(notes, "6.2.3", false))
	Equal(#a.regions, count)
	assert(f.historyRows[1].label.textColor[1] < 0.3)
end)

Register("party quest guide screenshots retain aspect ratio across clients and clear on reuse", function()
	for _, regional in ipairs({ false, true }) do
		local a = Fixture()
		function a:UsesRegionalPlayerNames() return regional end
		local notes = Notes()
		notes.sections = {
			{ title = "Overview", items = { "Guide" }, illustration = "party-quest-overview" },
			{ title = "Following", items = { "Guide" }, illustration = "party-quest-following" },
			{ title = "Warning", items = { "Guide" }, illustration = "party-quest-focus-warning" },
		}
		assert(a:RenderReleaseNotesWindow(notes, "6.5.3", false))
		local frame = a.releaseNotesWindow
		for asset, ratio in pairs({ PartyQuestOverviewForever = 635 / 1465,
			PartyQuestFollowingForever = 199 / 1198, PartyQuestFocusWarningForever = 540 / 1824 }) do
			local image = frame.releaseScreenshots[asset]
			assert(image and image.shown and math.abs(image.height / image.width - ratio) < 0.0001)
		end
		assert(a:RenderReleaseNotesWindow(Notes(), "6.5.2", false))
		for _, image in pairs(frame.releaseScreenshots) do assert(not image.shown) end
	end
end)
