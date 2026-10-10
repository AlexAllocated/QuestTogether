-- Private fixtures only: this module also runs inside a live /qt test session.
local QuestTogether = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Near(actual, expected)
	assert(type(actual) == "number" and math.abs(actual - expected) < 0.00001)
end

local function Frame(parent)
	local frame = { parent = parent, shown = true, scripts = {}, events = {}, textures = {}, points = {}, layouts = 0 }
	function frame:IsForbidden()
		return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
	end
	function frame:IsProtected()
		return self.protected == true or (self.parent and self.parent:IsProtected()) or false
	end
	function frame:CheckAccess(mutate)
		if self:IsForbidden() or (mutate and self:IsProtected()) then
			self.unsafeCalls = (self.unsafeCalls or 0) + 1
			error("unsafe minimap fixture access")
		end
		if mutate then
			self.mutations = (self.mutations or 0) + 1
		end
	end
	function frame:IsShown()
		self:CheckAccess()
		return self.shown
	end
	function frame:IsVisible()
		self:CheckAccess()
		return self.shown and (not self.parent or self.parent:IsVisible())
	end
	function frame:SetScript(name, callback)
		self:CheckAccess(true)
		self.scripts[name] = callback
	end
	function frame:EnableMouse() self:CheckAccess(true) end
	function frame:HookScript(name, callback)
		self:CheckAccess(true)
		local old = self.scripts[name]
		self.scripts[name] = function(...)
			if old then old(...) end
			callback(...)
		end
	end
	function frame:RegisterEvent(name)
		self:CheckAccess(true)
		self.events[name] = true
	end
	function frame:Show()
		self:CheckAccess(true)
		local changed = not self.shown
		self.shown = true
		if changed and self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end
	function frame:Hide()
		self:CheckAccess(true)
		local changed = self.shown
		self.shown = false
		if changed and self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
	end
	function frame:SetSize(width, height)
		self:CheckAccess(true)
		self.width, self.height = width, height
	end
	function frame:SetWidth(width) self:CheckAccess(true); self.width = width end
	function frame:SetJustifyH() self:CheckAccess(true) end
	function frame:SetWordWrap() self:CheckAccess(true) end
	function frame:SetSpacing() self:CheckAccess(true) end
	function frame:GetStringHeight()
		self:CheckAccess()
		local _, lines = (self.text or ""):gsub("\n", "")
		return (lines + 1) * 14
	end
	function frame:GetWidth()
		self:CheckAccess()
		return self.width
	end
	function frame:GetHeight()
		self:CheckAccess()
		return self.height
	end
	function frame:GetCenter()
		self:CheckAccess()
		return self.cx, self.cy
	end
	function frame:GetEffectiveScale()
		self:CheckAccess()
		return self.scale
	end
	function frame:SetPoint(...)
		self:CheckAccess(true)
		self.layouts = self.layouts + 1
		self.points[#self.points + 1] = { ... }
	end
	function frame:ClearAllPoints()
		self:CheckAccess(true)
		self.points = {}
	end
	function frame:SetFrameStrata(value)
		self:CheckAccess(true)
		self.strata = value
	end
	function frame:SetFrameLevel(value)
		self:CheckAccess(true)
		self.level = value
	end
	function frame:RegisterForClicks(...)
		self:CheckAccess(true)
		self.clicks = { ... }
	end
	function frame:RegisterForDrag(...)
		self:CheckAccess(true)
		self.drags = { ... }
	end
	function frame:SetHighlightTexture(value)
		self:CheckAccess(true)
		self.highlight = value
	end
	function frame:SetClampedToScreen(value)
		self:CheckAccess(true)
		self.clamped = value
	end
	function frame:SetBackdrop(value)
		self:CheckAccess(true)
		self.backdrop = value
	end
	function frame:SetBackdropColor(...)
		self:CheckAccess(true)
		self.color = { ... }
	end
	function frame:SetTexture(value)
		self:CheckAccess(true)
		self.texture = value
	end
	function frame:SetTexCoord(...) self:CheckAccess(true); self.texCoord = { ... } end
	function frame:SetVertexColor(...) self:CheckAccess(true); self.vertexColor = { ... } end
	function frame:SetBlendMode(value) self:CheckAccess(true); self.blend = value end
	function frame:CreateAnimationGroup()
		self:CheckAccess(true)
		local group = { animations = {}, plays = 0, stops = 0 }
		function group:SetLooping(value) self.looping = value end
		function group:CreateAnimation(kind)
			local animation = { kind = kind }
			for _, field in ipairs({ "Order", "FromAlpha", "ToAlpha", "Duration", "Smoothing" }) do
				animation["Set" .. field] = function(self, value) self[field] = value end
			end
			self.animations[#self.animations + 1] = animation
			return animation
		end
		function group:IsPlaying() return self.playing == true end
		function group:Play() self.playing = true; self.plays = self.plays + 1 end
		function group:Stop() self.playing = false; self.stops = self.stops + 1 end
		return group
	end
	function frame:SetText(value)
		self:CheckAccess(true)
		self.text = value
	end
	function frame:CreateTexture()
		self:CheckAccess(true)
		local texture = Frame(self)
		self.textures[#self.textures + 1] = texture
		return texture
	end
	function frame:CreateFontString()
		self:CheckAccess(true)
		return Frame(self)
	end
	return frame
end

local function Menu()
	local menu = { entries = {} }
	function menu:CreateButton(label, callback)
		local entry = { label = label, callback = callback, enabled = true }
		function entry:SetEnabled(value)
			self.enabled = value
		end
		self.entries[#self.entries + 1] = entry
		return entry
	end
	function menu:CreateCheckbox(label, isSelected, callback)
		local entry = self:CreateButton(label, callback)
		entry.isSelected = isSelected
		return entry
	end
	function menu:CreateDivider()
		self.entries[#self.entries + 1] = { divider = true }
	end
	return menu
end

local function Fixture()
	local addon = setmetatable({
		hasLoggedIn = true,
		isEnabled = true,
		db = { profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile) },
		frames = {},
		messages = {},
		menus = {},
		settings = 0,
		compares = 0,
		journals = 0,
	}, { __index = QuestTogether })
	function addon:AnnounceQuestPartnerSearch() end
	function addon:IsMinimapShiftKeyDown() return self.shift == true end
	local anchor = Frame()
	anchor.width, anchor.height, anchor.cx, anchor.cy, anchor.scale = 140, 140, 100, 200, 2
	addon.anchor, addon.cursorX, addon.cursorY = anchor, 200, 556
	addon.tooltipParent = Frame()
	function addon:GetMinimapTooltipParent()
		return self.tooltipParent
	end
	function addon:GetOwnedUIParent()
		return self.tooltipParent
	end
	addon.API = {
		OpenQTChatComposer = function()
			addon.chatDrafts = (addon.chatDrafts or 0) + 1
			return true
		end,
		GetMinimapAnchor = function()
			return addon.anchor
		end,
		CanOpenQuestJournalWindow = function()
			return addon.journalAvailable ~= false
		end,
		OpenQuestJournalWindow = function()
			addon.journals = addon.journals + 1
			return addon.journalSucceeds ~= false
		end,
		CreateContextMenu = function(owner, generator)
			local menu = Menu()
			menu.owner = owner
			generator(owner, menu)
			addon.menus[#addon.menus + 1] = menu
			return true
		end,
	}
	function addon:CreateMinimapUIFrame(kind, name, parent)
		local frame = Frame(parent)
		frame.kind, frame.name = kind, name
		self.frames[#self.frames + 1] = frame
		return frame
	end
	function addon:CreateOwnedUICleanupFrame() return Frame() end
	function addon:GetMinimapCursorPosition()
		return self.cursorX, self.cursorY
	end
	function addon:GetMinimapShapeName()
		return self.shape or "ROUND"
	end
	function addon:IsWorkBlocked(workClass)
		return self.blocked == true or (self.mapOpen and workClass == "nameplate_refresh")
	end
	function addon:IsRuntimeRestricted()
		return self.blocked == true
	end
	function addon:CanAccessValue(value)
		return value ~= self.unreadable
	end
	function addon:Print(message)
		self.messages[#self.messages + 1] = message
	end
	function addon:OpenOptionsWindow()
		self.settings = self.settings + 1
	end
	function addon:OpenPartyQuestCompare()
		self.compares = self.compares + 1
	end
	function addon:OpenReleaseNotes()
		self.notes = (self.notes or 0) + 1
	end
	-- The existing menu reports visible chat windows, not only the saved option.
	function addon:GetResolvedChatLogDestination()
		return self.separateOpened and "separate" or "main"
	end
	function addon:EnsureQuestLogChatFrame()
		self.separateOpened = true
	end
	function addon:CloseQuestLogChatFrame()
		self.separateOpened = false
	end
	function addon:RefreshOptionsWindow() end
	return addon
end

QuestTogether:RegisterTest("quick menu uses the native menu API without requiring a visible minimap icon", function()
	for _, missing in ipairs({ true, false }) do
		local a = Fixture()
		if missing then
			assert(rawget(a, "minimapButton") == nil)
		else
			a:InitializeMinimapLauncher()
			a:SetOption("showMinimapButton", false)
			assert(not a.minimapButton:IsVisible())
		end
		local count = #a.frames
		assert(a:OpenQuickMenu())
		Equal(#a.menus, 1)
		local menu = a.menus[1]
		Equal(menu.owner, a.tooltipParent)
		assert(menu.owner:IsVisible())
		Equal(#a.frames, count)
		if not missing then assert(not a.minimapButton:IsVisible()) end
		Equal(#menu.entries, 9)
		Equal(menu.entries[1].label, "Looking for Questing Partners")
		Equal(menu.entries[3].label, "Party Quest Log")
		Equal(menu.entries[4].label, "Open Quest Log")
		Equal(menu.entries[6].label, "Settings")
		Equal(menu.entries[7].label, "Patch Notes")
		Equal(menu.entries[8].label, "Move QuestTogether Logs to Separate Window")
		Equal(menu.entries[9].label, "Hide Minimap Icon")
		assert(menu.entries[2].divider and menu.entries[5].divider)
		for _, index in ipairs({ 3, 4, 6, 7 }) do menu.entries[index].callback() end
		Equal(a.compares, 1)
		Equal(a.journals, 1)
		Equal(a.settings, 1)
		Equal(a.notes, 1)
	end
end)

QuestTogether:RegisterTest("quick menu retires its tooltip and guards restricted or forbidden entry", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	a:ShowMinimapTooltip(a.minimapButton)
	local tooltip = a.minimapTooltip
	assert(tooltip:IsShown())
	assert(a:OpenQuickMenu())
	assert(not tooltip:IsShown() and tooltip.scripts.OnUpdate == nil)
	local hidden = 0
	function a:HideMinimapTooltip() hidden = hidden + 1 end
	a.blocked = true
	assert(not a:OpenQuickMenu())
	Equal(hidden, 0)
	Equal(#a.menus, 1)
	a.blocked = false
	a.tooltipParent.forbidden = true
	assert(not a:OpenQuickMenu())
	Equal(#a.menus, 1)
	Equal(a.tooltipParent.unsafeCalls, nil)
	a.tooltipParent.forbidden = false
	a.isEnabled = false
	assert(a:OpenQuickMenu())
	Equal(#a.menus, 2)
	Equal(a.menus[2].entries[3].enabled, false)
	a.menus[2].entries[6].callback()
	Equal(a.settings, 1)
end)

QuestTogether:RegisterTest(
	"minimap creates one owned launcher with the scroll texture and exact menu actions",
	function()
		local a = Fixture()
		a:InitializeMinimapLauncher()
		a:InitializeMinimapLauncher()
		Equal(#a.frames, 2)
		local button = a.minimapButton
		assert(button.shown and button.parent == a.anchor)
		Equal(button.textures[1].texture, "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon")
		Equal(a.anchor.layouts, 0)
		Equal(next(a.anchor.scripts), nil)
		Equal(button.clicks[1], "LeftButtonUp")
		Equal(button.clicks[2], "RightButtonUp")
		for _, click in ipairs({ "LeftButton", "RightButton" }) do
			button.scripts.OnClick(button, click)
		end
		Equal(#a.menus, 1)
		Equal(a.compares, 1)
		local entries = a.menus[1].entries
		Equal(#entries, 9)
		Equal(entries[1].label, "Looking for Questing Partners")
		Equal(entries[1].isSelected(), false)
		assert(entries[2].divider)
		Equal(entries[3].label, "Party Quest Log")
		Equal(entries[4].label, "Open Quest Log")
		assert(entries[5].divider)
		Equal(entries[6].label, "Settings")
		Equal(entries[7].label, "Patch Notes")
		Equal(entries[8].label, "Move QuestTogether Logs to Separate Window")
		Equal(entries[9].label, "Hide Minimap Icon")
		for _, index in ipairs({ 3, 4, 6, 7, 8 }) do
			entries[index].callback()
		end
		Equal(a.settings, 1)
		Equal(a.compares, 2)
		Equal(a.journals, 1)
		Equal(a.notes, 1)
		Equal(a.chatDrafts, nil)
		Equal(a:GetOption("chatLogDestination"), "separate")
		assert(a.separateOpened)
		local menu = Menu()
		a:PopulateMinimapMenu(menu)
		Equal(menu.entries[8].label, "Move QuestTogether Logs to Main Window")
		menu.entries[8].callback()
		Equal(a:GetOption("chatLogDestination"), "main")
		Equal(a.separateOpened, false)
	end
)

QuestTogether:RegisterTest("minimap stale menu actions recheck restrictions and disabled compare", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	a:ShowMinimapMenu(a.minimapButton)
	local menu = a.menus[1]
	a.blocked = true
	for _, index in ipairs({ 1, 3, 4, 6, 7 }) do
		menu.entries[index].callback()
	end
	Equal(a.chatDrafts, nil)
	menu.entries[8].callback()
	local messages = #a.messages
	menu.entries[9].callback()
	Equal(#a.messages, messages)
	Equal(a:GetOption("showMinimapButton"), true)
	assert(a.minimapButton.shown)
	Equal(a:GetOption("chatLogDestination"), "main")
	Equal(a.separateOpened, nil)
	Equal(a.settings + a.compares + a.journals, 0)
	Equal(a.notes, nil)
	Equal(a:ShowMinimapMenu(a.minimapButton), false)
	Equal(#a.menus, 1)
	a.blocked, a.isEnabled = false, false
	menu.entries[3].callback()
	Equal(a.compares, 0)
	local disabled = Menu()
	a:PopulateMinimapMenu(disabled)
	Equal(disabled.entries[3].enabled, false)
	assert(disabled.entries[7].enabled and disabled.entries[4].enabled)
	disabled.entries[6].callback()
	disabled.entries[7].callback()
	Equal(a.notes, 1)
	disabled.entries[4].callback()
	Equal(a.settings, 1)
	Equal(a.journals, 1)
	a.journalAvailable = false
	menu.entries[4].callback()
	Equal(a.journals, 1)
	local unavailable = Menu()
	a:PopulateMinimapMenu(unavailable)
	Equal(unavailable.entries[4].enabled, false)
	a.journalAvailable, a.journalSucceeds = true, false
	Equal(a:OpenQuestJournalFromMinimap(), false)
	Equal(a.journals, 2)
end)

QuestTogether:RegisterTest("minimap partner shortcut toggles the current saved value and rechecks restrictions", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	a:ShowMinimapMenu(a.minimapButton)
	local entry = a.menus[1].entries[1]
	Equal(entry.isSelected(), false)
	entry.callback()
	Equal(a:GetOption("lookingForQuestPartners"), true)
	Equal(entry.isSelected(), true)
	assert(a.messages[1]:find("On", 1, true))
	-- Reusing a menu must toggle the current setting, not its opening value.
	a:SetOption("lookingForQuestPartners", false)
	entry.callback()
	Equal(a:GetOption("lookingForQuestPartners"), true)
	a.blocked = true
	entry.callback()
	Equal(a:GetOption("lookingForQuestPartners"), true)
	Equal(#a.messages, 2)
	a.blocked, a.isEnabled = false, false
	entry.callback()
	Equal(a:GetOption("lookingForQuestPartners"), false)
	entry.callback()
	assert(a.messages[#a.messages]:find("paused", 1, true))
end)

QuestTogether:RegisterTest("minimap shift clicks toggle partners while normal and dragged clicks keep their behavior", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	local click = a.minimapButton.scripts.OnClick
	click(nil, "LeftButton")
	click(nil, "RightButton")
	Equal(#a.menus, 1)
	Equal(a.compares, 1)
	a.shift = true
	click(nil, "LeftButton")
	Equal(a:GetOption("lookingForQuestPartners"), true)
	click(nil, "RightButton")
	Equal(a:GetOption("lookingForQuestPartners"), false)
	Equal(#a.menus, 1)
	Equal(a.compares, 1)
	a.minimapSuppressClick = true
	click(nil, "LeftButton")
	Equal(a:GetOption("lookingForQuestPartners"), false)
	a.shift = false
	a.minimapSuppressClick = true
	click(nil, "LeftButton")
	Equal(a.compares, 1)
	a.blocked = true
	click(nil, "LeftButton")
	Equal(a:GetOption("lookingForQuestPartners"), false)
	a.blocked, a.anchor.forbidden = false, true
	click(nil, "LeftButton")
	Equal(a:GetOption("lookingForQuestPartners"), false)
	Equal(#a.menus, 1)
	Equal(a.compares, 1)
end)

QuestTogether:RegisterTest("minimap left click closes an open quest log or preview before reopening", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	local window = Frame()
	window:Hide()
	a.partyQuestCompareWindow = window
	function a:OpenPartyQuestCompare()
		self.compares = self.compares + 1
		self.partyQuestCompareSession = {}
		window:Show()
	end
	function a:CancelPartyQuestCompare()
		self.partyQuestCompareSession = nil
	end
	local click = a.minimapButton.scripts.OnClick
	click(nil, "LeftButton")
	assert(window:IsShown() and a.partyQuestCompareSession)
	click(nil, "RightButton")
	Equal(#a.menus, 1)
	assert(window:IsShown())
	click(nil, "LeftButton")
	assert(not window:IsShown())
	Equal(a.partyQuestCompareSession, nil)
	Equal(a.compares, 1)
	click(nil, "LeftButton")
	Equal(a.compares, 2)
	assert(window:IsShown())
	a.blocked = true
	click(nil, "LeftButton")
	assert(window:IsShown())
	a.blocked = false
	click(nil, "LeftButton")
	local preview = { partyQuestCompareWindow = Frame(), partyQuestCompareSession = {} }
	function preview:CancelPartyQuestCompare() self.partyQuestCompareSession = nil end
	a.partyQuestComparePreview = preview
	click(nil, "LeftButton")
	assert(not preview.partyQuestCompareWindow:IsShown())
	Equal(preview.partyQuestCompareSession, nil)
	Equal(a.compares, 2)
	click(nil, "LeftButton")
	Equal(a.compares, 3)
	assert(window:IsShown())
end)

QuestTogether:RegisterTest("minimap tooltip refreshes status without reading quest counts or recreating frames", function()
	local a = Fixture()
	function a:GetAddonVersion() return "5.16.7" end
	local reads = 0
	a.GetMonitoredQuestCount = function() reads = reads + 1; return 6 end
	a:InitializeMinimapLauncher()
	a:ShowMinimapTooltip(a.minimapButton)
	local tooltip = a.minimapTooltip
	local frames = #a.frames
	local text = tooltip.qtStatus.text
	for _, part in ipairs({ "QT Version: 5.16.7", "QT Chat Scope: Global", "Nearby Range: 25%", "Left-click to toggle Party Quest Log", "Right-click for menu", "Shift-click", "Share my location", "Looking for Questing Partners" }) do
		assert(text:find(part, 1, true), part)
	end
	a.db.profile.qtChatScope = "zone_only"
	a.db.profile.lookingForQuestPartners = true
	tooltip.scripts.OnUpdate(nil, 1)
	Equal(tooltip.qtStatus.text:find("Tracked quests:", 1, true), nil)
	assert(tooltip.qtStatus.text:find("QT Chat Scope: Zone Only", 1, true))
	assert(tooltip.qtStatus.text:find("Looking for Questing Partners: |cff66dd88On", 1, true))
	a.db.profile.showQTChat = false
	a.isEnabled = false
	tooltip.scripts.OnUpdate(nil, 1)
	assert(tooltip.qtStatus.text:find("QT Chat Scope: Off", 1, true))
	assert(tooltip.qtStatus.text:find("QuestTogether disabled.", 1, true))
	Equal(tooltip.qtStatus.text:find("Tracked quests:", 1, true), nil)
	Equal(#a.frames, frames)
	Equal(reads, 0)
	a.blocked = true
	tooltip.scripts.OnUpdate(nil, 1)
	Equal(reads, 0)
	Equal(tooltip.shown, false)
end)

QuestTogether:RegisterTest("settings help preserves control hooks reuses one tooltip and hides on close or restriction", function()
	local a = Fixture()
	function a:GetSettingsTooltipParent() return self.tooltipParent end
	function a:CreateSettingsTooltipFrame(parent) return self:CreateMinimapUIFrame("Frame", nil, parent) end
	local owner, other = Frame(a.tooltipParent), Frame(a.tooltipParent)
	local entered = 0
	owner:SetScript("OnEnter", function() entered = entered + 1 end)
	a:AttachSettingsTooltip(owner, "Setting", "Plain language help")
	a:AttachSettingsTooltip(other, "Other setting", "Other help")
	owner.scripts.OnEnter()
	local tooltip = a.settingsTooltip
	Equal(entered, 1)
	Equal(tooltip.text.text, "Plain language help")
	Equal(tooltip.strata, "TOOLTIP")
	Equal(tooltip.parent, a.tooltipParent)
	Equal(tooltip.shown, true)
	other.scripts.OnEnter()
	owner.scripts.OnLeave() -- A delayed leave must not hide the next control's help.
	Equal(tooltip.text.text, "Other help")
	Equal(tooltip.shown, true)
	other:Hide()
	Equal(tooltip.shown, false)
	owner.scripts.OnEnter()
	a.blocked = true
	tooltip.scripts.OnUpdate(nil, 0.1)
	Equal(tooltip.shown, false)
	owner.scripts.OnEnter()
	Equal(tooltip.shown, false)
	a.blocked = false
	owner.forbidden = true
	owner.scripts.OnEnter()
	Equal(tooltip.shown, false)
	Equal(owner.unsafeCalls, nil)
	Equal(#a.frames, 1)
end)

QuestTogether:RegisterTest(
	"minimap hide shortcut saves visibility and explains how to restore it in settings",
	function()
		local a = Fixture()
		local refreshed = 0
		function a:RefreshOptionsWindow()
			refreshed = refreshed + 1
		end
		a:InitializeMinimapLauncher()
		a:ShowMinimapMenu(a.minimapButton)
		a:ShowMinimapTooltip(a.minimapButton)
		a.menus[1].entries[9].callback()
		Equal(a:GetOption("showMinimapButton"), false)
		Equal(a.minimapButton.shown, false)
		Equal(a.minimapTooltip.shown, false)
		Equal(refreshed, 1)
		Equal(#a.messages, 1)
		assert(a.messages[1]:find("Settings > General > Show minimap icon", 1, true))
		assert(a.messages[1]:find("/qt options", 1, true))
		-- Restoring through the same option used by the settings checkbox reuses the button.
		assert(a:SetOption("showMinimapButton", true))
		assert(a.minimapButton.shown)
		Equal(#a.frames, 3)
		Equal(#a.messages, 1)
		function a:SetOption()
			return false
		end
		a.menus[1].entries[9].callback()
		Equal(#a.messages, 1)
		Equal(refreshed, 1)
	end
)

QuestTogether:RegisterTest("minimap initial hidden or restricted state recovers without runtime enable", function()
	local a = Fixture()
	a.hasLoggedIn = false
	a:InitializeMinimapLauncher()
	Equal(#a.frames, 0)
	a.hasLoggedIn, a.isEnabled, a.blocked = true, false, true
	a:InitializeMinimapLauncher()
	Equal(#a.frames, 1)
	Equal(rawget(a, "minimapButton"), nil)
	assert(a.minimapLauncherFrame.events.PLAYER_REGEN_ENABLED)
	assert(a.minimapLauncherFrame.events.ADDON_RESTRICTION_STATE_CHANGED)
	a:SetOption("showMinimapButton", false)
	a.blocked = false
	a.minimapLauncherFrame.scripts.OnEvent()
	Equal(rawget(a, "minimapButton"), nil)
	a:SetOption("showMinimapButton", true)
	assert(a.minimapButton.shown)
	local layouts = a.minimapButton.layouts
	a.blocked = true
	a:SetOption("showMinimapButton", false)
	assert(a.minimapButton.shown)
	Equal(a.minimapButton.layouts, layouts)
	a.blocked = false
	a.minimapLauncherFrame.scripts.OnEvent()
	Equal(a.minimapButton.shown, false)
	a:SetOption("showMinimapButton", true)
	assert(a.minimapButton.shown)
	Equal(#a.frames, 2)
end)

QuestTogether:RegisterTest("minimap invalid anchor geometry stays hidden and recovers on layout events", function()
	local a = Fixture()
	a.anchor.width = 0
	a:InitializeMinimapLauncher()
	Equal(a.minimapButton.shown, false)
	Equal(a.minimapButton.layouts, 0)
	a.anchor.width = 140
	a.minimapLauncherFrame.scripts.OnEvent()
	assert(a.minimapButton.shown)
	local button, layouts = a.minimapButton, a.minimapButton.layouts
	a.anchor.forbidden = true
	Equal(a:PositionMinimapButton(0), false)
	Equal(button.layouts, layouts)
	-- A caught getter error must still fail this test after production returns.
	Equal(a.anchor.unsafeCalls, nil)
	Equal(button.unsafeCalls, nil)
	a.anchor.forbidden, a.anchor.height = false, "unavailable"
	Equal(a:RefreshMinimapButton(), false)
	Equal(button.shown, false)
	a.anchor.height = 200
	a.minimapLauncherFrame.scripts.OnEvent()
	assert(button.shown)
end)

QuestTogether:RegisterTest("minimap offsets follow round and square edges and reject unreadable dimensions", function()
	local a = Fixture()
	local x, y = a:GetMinimapButtonOffset(0, 140, 140, "ROUND")
	Near(x, 78)
	Near(y, 0)
	x, y = a:GetMinimapButtonOffset(90, 140, 200, "ROUND")
	Near(x, 0)
	Near(y, 108)
	x, y = a:GetMinimapButtonOffset(45, 140, 140, "SQUARE")
	Near(x, 78)
	Near(y, 78)
	x, y = a:GetMinimapButtonOffset(-90, 140, 140, "ROUND")
	Near(x, 0)
	Near(y, -78)
	Equal(a:GetMinimapButtonOffset(0, -1, 140), nil)
	Equal(a:GetMinimapButtonOffset(0, math.huge, 140), nil)
	a.unreadable = 140
	Equal(a:GetMinimapButtonOffset(0, 140, 140), nil)
end)

QuestTogether:RegisterTest(
	"minimap drag uses effective scale saves each quadrant and suppresses release clicks",
	function()
		local a = Fixture()
		a:InitializeMinimapLauncher()
		local button = a.minimapButton
		for _, item in ipairs({ { 356, 400, 0 }, { 200, 556, 90 }, { 44, 400, 180 }, { 200, 244, 270 } }) do
			a.cursorX, a.cursorY = item[1], item[2]
			button.scripts.OnMouseDown()
			button.scripts.OnDragStart()
			assert(button.scripts.OnUpdate)
			button.scripts.OnUpdate()
			button.scripts.OnDragStop()
			Near(a:GetOption("minimapButtonPosition"), item[3])
			Equal(button.scripts.OnUpdate, nil)
			button.scripts.OnClick(button, "LeftButton")
			Equal(#a.menus, 0)
			Equal(a.compares, 0)
		end
		button.scripts.OnMouseDown()
		button.scripts.OnClick(button, "RightButton")
		Equal(#a.menus, 1)
	end
)

QuestTogether:RegisterTest("minimap interrupted drags cannot save a stale angle or touch restricted layout", function()
	for _, interruption in ipairs({ "restricted", "profile", "hidden", "scale", "cursor", "forbidden", "width" }) do
		local a = Fixture()
		a:InitializeMinimapLauncher()
		local button, profile = a.minimapButton, a.db.profile
		a:StartMinimapButtonDrag(button)
		Near(a.minimapDragState.angle, 90)
		local layouts = button.layouts
		if interruption == "restricted" then
			a.blocked = true
		elseif interruption == "profile" then
			a.db.profile = QuestTogether:DeepCopy(profile)
		elseif interruption == "hidden" then
			a.db.profile.showMinimapButton = false
		elseif interruption == "scale" then
			a.anchor.scale = 0
		elseif interruption == "cursor" then
			a.unreadable = a.cursorY
		elseif interruption == "forbidden" then
			a.anchor.forbidden = true
		elseif interruption == "width" then
			a.anchor.width = 0
		end
		a:UpdateMinimapButtonDrag()
		a:StopMinimapButtonDrag(false)
		Equal(rawget(a, "minimapDragState"), nil)
		Equal(button.layouts, layouts)
		Equal(profile.minimapButtonPosition, 225)
		Equal(a.db.profile.minimapButtonPosition, 225)
		if interruption == "forbidden" then
			a:HideMinimapTooltip()
			a:SetOption("showMinimapButton", false)
			a.anchor.forbidden = false
			a:RefreshMinimapButton()
		end
		Equal(button.scripts.OnUpdate, nil)
		Equal(a.anchor.unsafeCalls, nil)
		Equal(button.unsafeCalls, nil)
	end
end)

QuestTogether:RegisterTest(
	"minimap profile refresh applies visibility and position without recreating frames",
	function()
		local a = Fixture()
		a:InitializeMinimapLauncher()
		local button = a.minimapButton
		a:StartMinimapButtonDrag(button)
		a.db.profile = { showMinimapButton = false, minimapButtonPosition = 0 }
		a:RefreshMinimapButton()
		Equal(button.shown, false)
		Equal(button.scripts.OnUpdate, nil)
		a.db.profile = { showMinimapButton = true, minimapButtonPosition = 180 }
		a:RefreshMinimapButton()
		assert(button.shown)
		Near(button.points[1][4], -78)
		Near(button.points[1][5], 0)
		Equal(#a.frames, 2)
		Equal(a:SetOption("showMinimapButton", "false"), false)
		Equal(a:SetOption("minimapButtonPosition", math.huge), false)
		assert(a:SetOption("minimapButtonPosition", -90))
		Near(a:GetOption("minimapButtonPosition"), 270)
	end
)

QuestTogether:RegisterTest("minimap tooltip is addon owned reused and hidden for drags and clicks", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	local button = a.minimapButton
	button.scripts.OnEnter()
	local tooltip = a.minimapTooltip
	assert(tooltip.shown and tooltip.parent == a.tooltipParent)
	button.scripts.OnLeave()
	Equal(tooltip.shown, false)
	button.scripts.OnEnter()
	Equal(a.minimapTooltip, tooltip)
	Equal(#a.frames, 3)
	button.scripts.OnClick(button, "LeftButton")
	Equal(tooltip.shown, false)
	button.scripts.OnEnter()
	button.scripts.OnDragStart()
	Equal(tooltip.shown, false)
	button.scripts.OnEnter()
	Equal(tooltip.shown, false)
	button:Hide()
	Equal(button.scripts.OnUpdate, nil)
	Equal(a:GetOption("minimapButtonPosition"), 225)
end)

QuestTogether:RegisterTest("home settings refresh minimap visibility after profile switches", function()
	local checkbox = {
		SetChecked = function(self, value)
			self.checked = value
		end,
	}
	QuestTogether.optionsFrame = {}
	QuestTogether.homeControls = { showMinimapButton = checkbox }
	QuestTogether.db.profile.showMinimapButton = true
	QuestTogether:RefreshHomeWindow()
	Equal(checkbox.checked, true)
	QuestTogether.db.profile = { showMinimapButton = false }
	QuestTogether:RefreshHomeWindow()
	Equal(checkbox.checked, false)
end)

QuestTogether:RegisterTest("minimap forbidden parents recover through the independent launcher frame", function()
	local a = Fixture()
	a.anchor.forbidden = true
	a:InitializeMinimapLauncher()
	Equal(#a.frames, 1)
	Equal(a.minimapLauncherFrame.parent, nil)
	Equal(rawget(a, "minimapButton"), nil)
	a.anchor.forbidden = false
	a.minimapLauncherFrame.scripts.OnEvent()
	a:ShowMinimapTooltip(a.minimapButton)
	local tooltip = a.minimapTooltip
	a:StartMinimapButtonDrag(a.minimapButton)
	a.anchor.forbidden = true
	a:UpdateMinimapButtonDrag()
	Equal(rawget(a, "minimapDragState"), nil)
	a:HideMinimapTooltip()
	a:ShowMinimapTooltip(a.minimapButton)
	a:SetOption("showMinimapButton", false)
	Equal(tooltip.shown, false)
	a.anchor.forbidden = false
	a.minimapLauncherFrame.scripts.OnEvent()
	Equal(a.minimapButton.shown, false)
	Equal(a.minimapButton.scripts.OnUpdate, nil)
	Equal(a:GetOption("minimapButtonPosition"), 225)
	Equal(a.anchor.unsafeCalls, nil)
	Equal(a.minimapButton.unsafeCalls, nil)
	Equal(tooltip.unsafeCalls, nil)
end)

QuestTogether:RegisterTest("minimap drag release rechecks restrictions before the next animation tick", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	a:StartMinimapButtonDrag(a.minimapButton)
	Near(a.minimapDragState.angle, 90)
	a.blocked = true
	-- Restriction can start between the last OnUpdate and OnDragStop.
	a:StopMinimapButtonDrag(false)
	Equal(a:GetOption("minimapButtonPosition"), 225)
	Equal(rawget(a, "minimapDragState"), nil)
end)

QuestTogether:RegisterTest(
	"minimap tooltip uses independent tooltip draw order instead of the minimap hierarchy",
	function()
		local a = Fixture()
		a:InitializeMinimapLauncher()
		local button = a.minimapButton
		button.scripts.OnEnter()
		local tooltip = a.minimapTooltip
		Equal(tooltip.parent, a.tooltipParent)
		Equal(tooltip.strata, "TOOLTIP")
		Equal(tooltip.level, 100)
		Equal(tooltip.points[1][2], button)
		Equal(a.anchor.mutations, nil)
		Equal(a.tooltipParent.mutations, nil)
		button:Hide()
		Equal(tooltip.shown, false)
		Equal(tooltip.scripts.OnUpdate, nil)
		button.scripts.OnEnter()
		Equal(tooltip.shown, false)
	end
)

QuestTogether:RegisterTest(
	"independent minimap tooltip hides when its anchor or runtime becomes unavailable",
	function()
		for _, boundary in ipairs({ "hidden", "forbidden", "unreadable", "restricted", "option" }) do
			local a = Fixture()
			a:InitializeMinimapLauncher()
			a.minimapButton.scripts.OnEnter()
			local tooltip = a.minimapTooltip
			if boundary == "hidden" then
				a.anchor.shown = false
			elseif boundary == "forbidden" then
				a.anchor.forbidden = true
			elseif boundary == "unreadable" then
				a.unreadable = {}
				a.minimapButton.IsVisible = function()
					return a.unreadable
				end
			elseif boundary == "restricted" then
				a.blocked = true
			else
				a.db.profile.showMinimapButton = false
			end
			-- The tooltip no longer inherits visibility or quarantine from the anchor.
			tooltip.scripts.OnUpdate(tooltip, 0.2)
			Equal(tooltip.shown, false)
			Equal(tooltip.scripts.OnUpdate, nil)
			Equal(a.anchor.unsafeCalls, nil)
			Equal(a.minimapButton.unsafeCalls, nil)
			Equal(tooltip.unsafeCalls, nil)
		end
	end
)

QuestTogether:RegisterTest("minimap tooltip checks its independent parent and quarantined owned frame", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	a.tooltipParent.forbidden = true
	a.minimapButton.scripts.OnEnter()
	Equal(rawget(a, "minimapTooltip"), nil)
	Equal(#a.frames, 2)
	Equal(a.tooltipParent.unsafeCalls, nil)
	a.tooltipParent.forbidden = false
	a.tooltipParent.shown = false
	a.minimapButton.scripts.OnEnter()
	Equal(rawget(a, "minimapTooltip"), nil)
	Equal(#a.frames, 2)
	a.tooltipParent.shown = true
	a.minimapButton.scripts.OnEnter()
	local tooltip = a.minimapTooltip
	for _, boundary in ipairs({ "forbidden", "protected" }) do
		tooltip[boundary] = true
		local mutations = tooltip.mutations
		a:HideMinimapTooltip()
		a:ShowMinimapTooltip(a.minimapButton)
		Equal(tooltip.mutations, mutations)
		Equal(tooltip.unsafeCalls, nil)
		tooltip[boundary] = false
		-- A hide requested during quarantine must finish after access returns,
		-- even while the launcher remains hovered and otherwise eligible.
		local cleanup = a:GetOwnedUICleanupState()
		cleanup.driver.scripts.OnUpdate(cleanup.driver, 0.3)
		Equal(tooltip.shown, false)
		Equal(tooltip.scripts.OnUpdate, nil)
		Equal(cleanup.pending[tooltip], nil)
		a.minimapButton.scripts.OnEnter()
		assert(tooltip.shown)
		Equal(#a.frames, 3)
	end
end)

QuestTogether:RegisterTest("minimap partner glow follows status visibility and restrictions with a reused pulse", function()
	local a = Fixture()
	a:InitializeMinimapLauncher()
	local button = a.minimapButton
	a.mapOpen = true -- launcher glow does not inspect map/nameplate data
	Equal(button.qtRingGlow, nil)
	a:SetOption("lookingForQuestPartners", true)
	Equal(button.qtRingGlow ~= nil, true)
	local pulse = button.qtRingPulse
	assert(pulse:IsPlaying())
	Equal(pulse.looping, "REPEAT")
	Equal(pulse.animations[1].Duration, 0.7)
	Equal(pulse.animations[1].FromAlpha, 0.3)
	Equal(pulse.animations[1].ToAlpha, 1)
	Equal(pulse.animations[2].FromAlpha, 1)
	Equal(pulse.animations[2].ToAlpha, 0.3)
	Equal(button.qtRingGlow.points[1][2], button)
	Equal(button.qtLogoTexture.width, 24)
	local textures, plays = #button.textures, pulse.plays
	a:RefreshMinimapButton()
	Equal(#button.textures, textures)
	Equal(pulse.plays, plays)
	a:SetOption("lookingForQuestPartners", false)
	assert(not pulse:IsPlaying() and not button.qtRingGlow.shown)
	a.blocked = true
	a:SetOption("lookingForQuestPartners", true)
	assert(not pulse:IsPlaying())
	a.blocked = false
	a.minimapLauncherFrame.scripts.OnEvent(nil, "PLAYER_REGEN_ENABLED")
	assert(pulse:IsPlaying())
	a:SetOption("showMinimapButton", false)
	assert(not pulse:IsPlaying())
	a:SetOption("showMinimapButton", true)
	assert(pulse:IsPlaying())
	a.isEnabled = false
	a:RefreshMinimapPartnerGlow()
	assert(not pulse:IsPlaying())
	a.isEnabled = true
	a:RefreshMinimapPartnerGlow()
	assert(pulse:IsPlaying())
	a.anchor.forbidden = true
	Equal(a:RefreshMinimapPartnerGlow(), false)
	Equal(button.unsafeCalls, nil)
	a.anchor.forbidden = false
	a.blocked = true
	a:SetOption("lookingForQuestPartners", false)
	assert(not pulse:IsPlaying())
	Equal(#button.textures, textures)
end)
