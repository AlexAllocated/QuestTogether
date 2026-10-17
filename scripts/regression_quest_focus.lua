-- Actual owned view/model with private native seams; never touch the live HUD.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local function Fixture()
	local a = setmetatable({
		isEnabled = true,
		db = { profile = { questTrackerMode = "both", questFocusOpacity = 75 } },
		partyMemberOrder = { "Me", "Friend" },
		jobs = {},
		sent = {},
		now = 10,
		focus = 42,
		runtimeStateStore = {},
	}, { __index = QT })
	a.API = {
		IsInGroup = function() return #a.partyMemberOrder > 1 end,
		GetTime = function()
			return a.now
		end,
		Delay = function(_, callback)
			a.jobs[#a.jobs + 1] = callback
		end,
	}
	function a:GetOption(key)
		return self.db.profile[key]
	end
	function a:SetOption(key, value)
		self.db.profile[key] = value
		self:QueueQuestFocusRefresh()
	end
	function a:SetOptions(values)
		for key, value in pairs(values) do self:SetOption(key, value) end
	end
	function a:IsRuntimeRestricted()
		return self.restricted == true
	end
	function a:IsWorkBlocked(workClass)
		return workClass ~= "quest_focus_presentation" and self.restricted == true
	end
	function a:IsMapTooltipSensitiveStateActive()
		return false
	end
	function a:RunGuardedCallback(_, callback)
		callback()
		return true
	end
	function a:NormalizeMemberName(name)
		return name
	end
	function a:IsIgnoredPlayerName(name)
		return name == self.ignored
	end
	function a:GetPlayerFullName()
		return "Me"
	end
	function a:GetPlayerClassFile()
		return "MAGE"
	end
	function a:GetGroupedSenderClassFile()
		return "WARRIOR"
	end
	function a:IsGroupedSender(name)
		for _, n in ipairs(self.partyMemberOrder) do
			if n == name then
				return true
			end
		end
		return false
	end
	function a:GetClassColorCode()
		return "|cffffffff"
	end
	function a:GetHoveredTrackerQuestID()
		return self.hover
	end
	function a:GetPartyQuestFocusID()
		return self.focus
	end
	function a:GetLocalizedQuestTitle(id)
		return "Focused quest " .. id
	end
	function a:BuildQuestCompareResponseEntries(id)
		self.localReads = (self.localReads or 0) + 1
		return {
			{
				questId = id,
				questTitle = "Local quest",
				objectives = {
					{ text = "Local objective", current = self.count or 1, required = 8, objectiveIndex = 1 },
				},
			},
		}
	end
	function a:RequestQuestCompare(name, receiver)
		self.sent[#self.sent + 1] = { name = name, receiver = receiver }
		return true, tostring(#self.sent)
	end
	function a:GetQuestFocusEditManager()
		return self.manager
	end
	function a:GetQuestTrackerAnchorFrame()
		return self.nativeTracker
	end
	function a:BindQuestFocusEditCallbacks(manager)
		self.bound = manager
	end
	function a:Drain()
		for _ = 1, 20 do
			if not next(self.jobs) then
				return
			end
			local jobs = self.jobs
			self.jobs = {}
			for _, callback in pairs(jobs) do
				callback()
			end
		end
		error("focus render must settle")
	end
	a.root = QT:CreateTestUIRegion(a)
	a.root:SetSize(1200, 900)
	function a:GetOwnedUIParent()
		return self.root
	end
	function a:CreateOwnedWindowFrame(kind, _, parent, template)
		return self:ApplyTestUITemplate(self:CreateTestUIRegion(self, parent, kind), template)
	end
	function a:ConfigureHUDEditSlider(frame, data, callback)
		frame.change, frame.settingData = callback, data
		frame.Label = frame.Label or frame:CreateFontString()
		frame.Label:SetText(data.settingName)
		frame.Slider = frame.Slider or self:CreateTestUIRegion(self, frame)
		frame.Slider.RightText = frame.Slider.RightText or frame.Slider:CreateFontString()
	end
	function a:DeselectPersonalBubbleAnchor()
		self.bubbleDeselected = true
	end
	return a
end
QT:RegisterTest(
	"focus HUD follows native focus and shares immediate remote progress while local reads stay event driven",
	function()
		local a = Fixture()
		a:UpdateQuestFocusWindow()
		a:Drain()
		local frame, state = a.questFocusWindow, a.questFocusState
		Equal(frame:IsShown(), true)
		Equal(frame.heading.text, "Focused quest 42")
		Equal(#a.sent, 1)
		for _ = 1, 10 do
			a:UpdateQuestFocusWindow()
		end
		Equal(a.localReads, 1)
		local receiver = a.sent[1].receiver
		receiver.onEntry({
			questId = 42,
			objectives = { { objectiveIndex = 1, text = "Bandanas: 1/8", current = 1, required = 8 } },
		})
		receiver.onDone()
		a:Drain()
		Equal(state.members[2].objectiveDetails[42].objectives[1].current, 1)
		local track = frame.rows[4].progressTrack
		Equal(frame.rows[4].progressFill:GetWidth(), track:GetWidth() / 8)
		Equal(frame.rows[3].background.textureColor[4], 0.25)
		for _, row in ipairs(frame.rows) do
			for _, edge in ipairs(row.panelEdges) do
				Equal(edge:IsShown(), false)
			end
			Equal(row.panelCorners, nil)
		end
		a:ObservePartyQuestProgress({
			questId = 42,
			eventType = "QUEST_PROGRESS",
			text = "Bandanas: 7/8",
			occurredAt = 20,
			eventFacts = a:BuildAnnouncementFacts("QUEST_PROGRESS", 1, "item", false, 7, 8),
		}, "Friend", { session = "s", sequence = 1 })
		a:Drain()
		assert(frame.rows[4].title.text:find("7/8", 1, true))
		Equal(frame.rows[4].progressFill:GetWidth(), track:GetWidth() * 7 / 8)
		Equal(#a.sent, 1)
		a.count = 5
		a:QueueQuestFocusRefresh(true)
		a:Drain()
		Equal(state.members[1].objectiveDetails[42].objectives[1].current, 5)
		a.focus = 43
		a:UpdateQuestFocusWindow()
		a:Drain()
		Equal(a.questFocusState.id, 43)
		receiver.onEntry({ questId = 42, questTitle = "Late" })
		receiver.onDone()
		a:Drain()
		Equal(frame.heading.text, "Focused quest 43")
		a.focus = nil
		a:UpdateQuestFocusWindow()
		a:Drain()
		Equal(frame:IsShown(), false)
		Equal(next(a.partyQuestProgress), nil)
	end
)
QT:RegisterTest("focus HUD edit layout restores per profile and opacity affects only rounded background", function()
	local a = Fixture()
	a.manager = a:CreateTestUIRegion(a)
	function a.manager:SaveLayouts() end
	function a.manager:IsEditModeActive()
		return self.active
	end
	a:UpdateQuestFocusWindow()
	a:Drain()
	local frame = a.questFocusWindow
	assert(frame.Selection:IsShown())
	Equal(frame.Selection.isSelected, false)
	Equal(frame.Selection.system:GetSystemName(), "Quest Tracker")
	Equal(frame.editControls, nil)
	frame.scripts.OnMouseDown(frame, "LeftButton")
	assert(frame.editControls:IsShown())
	Equal(a.bubbleDeselected, true)
	Equal(frame.Selection.isSelected, true)
	Equal(frame.editControls.SaveButton.enabled, false)
	Equal(frame.editControls.RevertButton.enabled, false)
	Equal(a.bound, a.manager)
	frame.editControls.WidthSlider.change(500)
	frame.editControls.HeightSlider.change(220)
	frame.editControls.OpacitySlider.change(40)
	a:Drain()
	Equal(frame.editControls.SaveButton.enabled, true)
	Equal(frame.editControls.RevertButton.enabled, true)
	Equal(a.db.profile.windowLayouts.questFocus.width, 500)
	Equal(frame.background[1].textureColor[4], 0.4)
	Equal(frame.background[4].vertexColor[4], 0.4)
	a:RevertQuestFocusEditLayout()
	a:Drain()
	Equal(frame:GetWidth(), 340)
	Equal(a:GetQuestFocusOpacity(), 75)
	frame.editControls.WidthSlider.change(440)
	a:CaptureQuestFocusEditLayout()
	frame.editControls.WidthSlider.change(460)
	a:RevertQuestFocusEditLayout()
	a:Drain()
	Equal(frame:GetWidth(), 440)
	frame.editControls.ResetButton.scripts.OnClick()
	a:Drain()
	Equal(frame:GetWidth(), 340)
	Equal(a:GetQuestFocusOpacity(), 75)
	frame.editControls.RevertButton.scripts.OnClick()
	a:Drain()
	Equal(frame:GetWidth(), 440)
	frame.editControls.CloseButton.scripts.OnClick()
	a:Drain()
	Equal(frame.editControls:IsShown(), false)
	Equal(frame.Selection.isSelected, false)
	assert(frame.Selection:IsShown())
	a:UpdateQuestFocusWindow()
	Equal(frame.editControls:IsShown(), false)
	frame.scripts.OnMouseDown(frame, "LeftButton")
	Equal(frame.editControls:IsShown(), true)
	a.db.profile.lightMode = true
	a:QueueQuestFocusRefresh()
	a:Drain()
	Equal(frame.background[1].textureColor[1], 0.94)
	Equal(frame.rows[1].title.textColor[1], 0.32)
	for _, light in ipairs({ false, true }) do
		a.db.profile.lightMode = light
		a:SetOption("questFocusOpacity", 0)
		a:Drain()
		Equal(frame.background[1].textureColor[4], 0)
		local tintAlpha = frame.rows[1].background.textureColor[4]
		Equal(tintAlpha, 0.25)
		local paperAlpha = frame.rows[1].paper.textureColor[4]
		Equal(paperAlpha, 0)
		assert(math.abs(tintAlpha + paperAlpha * (1 - tintAlpha) - 0.25) < 0.00001)
		Equal(frame.rows[1].title.textColor[1], 1)
		Equal(frame.rows[2].title.textColor[1], 0.93)
		Equal(frame.heading.textColor[1], 1)
		for _, sample in ipairs({ { 25, 0.25 }, { 50, 0.25 }, { 75, 0.25 }, { 100, 0.25 } }) do
			a:SetOption("questFocusOpacity", sample[1])
			a:Drain()
			Equal(frame.background[1].textureColor[4], sample[1] / 100)
			Equal(frame.rows[1].background.textureColor[4], sample[2])
		end
	end
	a.manager:Hide()
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(frame.editControls:IsShown(), false)
	Equal(a.questFocusEditBaseline, nil)
	Equal(frame.Selection:IsShown(), false)
	a.db.profile = { questTrackerMode = "both", questFocusOpacity = 90 }
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(frame:GetWidth(), 340)
	Equal(frame.background[1].textureColor[4], 0.9)
end)
QT:RegisterTest("focus HUD restriction disable and ignored roster changes cannot resurrect obsolete views", function()
	local a = Fixture()
	a:UpdateQuestFocusWindow()
	a:Drain()
	local frame, reply = a.questFocusWindow, a.sent[1].receiver
	a.restricted = true
	a.count = 6
	a:QueueQuestFocusRefresh(true)
	a:Drain()
	Equal(a.localReads, 1)
	a:ObserveLocalQuestFocusProgress({
		questId = 42,
		eventType = "QUEST_PROGRESS",
		text = "Local objective: 6/8",
		eventFacts = a:BuildAnnouncementFacts("QUEST_PROGRESS", 1, "item", false, 6, 8),
	})
	a:Drain()
	assert(frame.rows[2].title.text:find("6/8", 1, true))
	Equal(frame.rows[2].progressFill:GetWidth(), frame.rows[2].progressTrack:GetWidth() * 6 / 8)
	frame.rows[2].progressFill.forbidden = true
	a:QueueQuestFocusRefresh()
	a:Drain()
	Equal(a.invalidCalls, nil)
	frame.rows[2].progressFill.forbidden = false
	Equal(a.localReads, 1)
	frame.forbidden = true
	a:QueueQuestFocusRefresh()
	a:Drain()
	Equal(a.invalidCalls, nil)
	frame.forbidden = false
	a.restricted = false
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(a.localReads, 2)
	a.ignored = "Friend"
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(#a.questFocusState.members, 1)
	reply.onDone()
	a:Drain()
	Equal(#a.questFocusState.members, 1)
	a.restricted = true
	a.db.profile.questTrackerMode = "hidden"
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(frame:IsShown(), false)
	a.restricted = false
	a.db.profile.questTrackerMode = "both"
	a:UpdateQuestFocusWindow()
	a.isEnabled = false
	a:ResetQuestFocusWindow()
	a:Drain()
	Equal(frame:IsShown(), false)
end)

QT:RegisterTest("focus HUD construction and resize callbacks never reenter native scrollbar creation", function()
	local a = Fixture()
	local create, bars = a.CreateOwnedWindowFrame, 0
	function a:CreateOwnedWindowFrame(kind, name, parent, template)
		if template == "MinimalScrollBar" then
			bars = bars + 1
			Equal(bars, 1, "refresh must not create a second HUD during construction")
			-- Native frame validation may deliver layout callbacks inside CreateFrame.
			self:QueueQuestFocusRefresh()
		end
		return create(self, kind, name, parent, template)
	end
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(bars, 1)
	local frame = a.questFocusWindow
	for _ = 1, 5 do
		a:QueueQuestFocusRefresh()
	end
	Equal(#a.jobs, 1, "refresh bursts must coalesce into one next-frame render")
	frame:SetSize(400, 200)
	a:Drain()
	Equal(a.questFocusWindow, frame)
	Equal(bars, 1)
	Equal(frame:GetWidth(), 400)
	Equal(frame.body:GetWidth(), 400 - 24)
	Equal(frame.rows[1]:GetWidth(), frame.body:GetWidth())
	local track = frame.rows[2].progressTrack
	Equal(track:GetWidth(), frame.body:GetWidth() - 26)
	frame:SetSize(600, 120)
	a:Drain()
	assert(frame.maximum > 0)
	Equal(frame.body:GetWidth(), 600 - 36)
	Equal(track:GetWidth(), frame.body:GetWidth() - 26)
	frame:SetHeight(800)
	a:Drain()
	Equal(frame.maximum, 0)
	Equal(frame.body:GetWidth(), 600 - 24)
	Equal(frame.rows[1]:GetWidth(), frame.body:GetWidth())
end)

QT:RegisterTest("tracker default docking follows native side and scale without overriding custom positions", function()
	local a = Fixture()
	a.nativeTracker = a:CreateTestUIRegion(a, a.root)
	local tracker = a.nativeTracker
	tracker:SetSize(240, 500)
	tracker.left, tracker.top = 900, 800
	local writes = tracker.writes
	a:UpdateQuestFocusWindow()
	a:Drain()
	local frame = a.questFocusWindow
	local function Anchor(point, x, y)
		local p, relative, rp, px, py = frame:GetPoint(1)
		Equal(p, point)
		Equal(relative, a.root)
		Equal(rp, "BOTTOMLEFT")
		Equal(px, x)
		Equal(py, y)
	end
	Anchor("TOPRIGHT", 892, 800)
	tracker.left = 100
	a:UpdateQuestFocusWindow()
	Anchor("TOPLEFT", 348, 800)
	frame:SetWidth(420)
	a:SaveWindowLayout(frame)
	Equal(a.db.profile.windowLayouts.questFocus.autoAnchor, true)
	tracker.left, tracker.scale = 500, 1.5
	a:UpdateQuestFocusWindow()
	a:Drain()
	Anchor("TOPRIGHT", 742, 1200)
	Equal(tracker.writes, writes, "docking must never mutate Blizzard's tracker")
	tracker.forbidden = true
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 742, 1200)
	tracker.forbidden = false
	a.restricted = true
	tracker.left = 100
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 742, 1200)
	a.restricted = false
	frame.customPositionProfile = a.db.profile
	a:SaveWindowLayout(frame)
	Equal(a.db.profile.windowLayouts.questFocus.autoAnchor, false)
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 742, 1200)
	a.db.profile.windowLayouts.questFocus = { width = 420, height = 600, x = 0.4, y = 0.5 }
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 742, 1200) -- Pre-existing saved positions remain custom.
	a.db.profile.windowLayouts.questFocus = nil
	a:UpdateQuestFocusWindow()
	Anchor("TOPLEFT", 518, 1200)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("tracker content shrinks below its saved maximum and Edit Mode retains full placement bounds", function()
	local a = Fixture()
	a:UpdateQuestFocusWindow()
	a:Drain()
	local frame = a.questFocusWindow
	Equal(frame:GetHeight(), 600)
	assert(frame.panel:GetHeight() < 600)
	Equal(frame.maximum, 0)
	local initialHeight = frame.panel:GetHeight()
	local reply = a.sent[1].receiver
	local objectives = {}
	for i = 1, 20 do
		objectives[i] = { objectiveIndex = i, text = "A long objective that needs room to wrap across the tracker width", current = i, required = 25 }
	end
	reply.onEntry({ questId = 42, objectives = objectives })
	reply.onDone()
	a:Drain()
	Equal(frame.panel:GetHeight(), 600)
	assert(frame.maximum > 0)
	frame.offset = frame.maximum
	a.manager = a:CreateTestUIRegion(a)
	a.manager:Show()
	a:UpdateQuestFocusWindow()
	a:Drain()
	a:SelectQuestFocusWindow()
	frame.editControls.HeightSlider.change(420)
	a:Drain()
	Equal(frame.panel:GetHeight(), 420)
	Equal(a.db.profile.windowLayouts.questFocus.height, 420)
	Equal(frame.editControls.HeightSlider.settingData.settingName, "Maximum height")
	a.ignored = "Friend"
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(frame.panel:GetHeight(), 420, "Edit Mode shows the full maximum even with little content")
	a.manager:Hide()
	a:UpdateQuestFocusWindow()
	a:Drain()
	assert(frame.panel:GetHeight() <= initialHeight)
	Equal(frame:GetHeight(), 420)
	Equal(a.db.profile.windowLayouts.questFocus.height, 420)
	Equal(frame.offset, 0)
	Equal(frame.maximum, 0)
	Equal(frame.panel.points[1][2], frame)
	Equal(frame.panel.points[1][3], "TOPLEFT")
	a:ApplyWindowLayout(frame, true)
	a:Drain()
	assert(frame.panel:GetHeight() < 420)
	Equal(frame:GetHeight(), 420)
end)

QT:RegisterTest(
	"quest status without objective counters is shared by HUD and PQL for local and remote members",
	function()
		local a = Fixture()
		function a:BuildQuestCompareResponseEntries(id)
			return { { questId = id, questTitle = "Delivery quest", isComplete = true } }
		end
		a:UpdateQuestFocusWindow()
		a:Drain()
		local state = a.questFocusState
		local remote = a.sent[1].receiver
		remote.onEntry({ questId = 42, isComplete = true, objectives = {} })
		remote.onDone()
		a:Drain()
		local rows = a:BuildQuestFocusRows(state)
		Equal(#rows, 2)
		Equal(rows[1].title, "You are ready to turn in this quest.")
		Equal(rows[2].title, "Friend is ready to turn in this quest.")
		a.partyQuestCompareSession = { members = state.members, expandedQuestIds = { [42] = true } }
		local pql = a:BuildPartyQuestCompareDisplayRows({ { questId = 42, cells = { "Ready", "Ready" } } })
		Equal(pql[2].hint, "Ready")
		Equal(pql[3].hint, "Ready")
		local member = state.members[1]
		member.entries[42].isComplete = false
		Equal(a:BuildQuestFocusRows(state)[1].title, "You are still working on this quest.")
		a:ObserveLocalQuestFocusProgress({ questId = 42, eventType = "QUEST_READY_TO_TURN_IN" })
		a:Drain()
		Equal(member.entries[42].isComplete, true)
		Equal(a:BuildQuestFocusRows(state)[1].title, "You are ready to turn in this quest.")
		a:ObserveLocalQuestFocusProgress({ questId = 42, eventType = "QUEST_COMPLETED" })
		a:Drain()
		Equal(member.entries[42], nil)
		Equal(a:BuildQuestFocusRows(state)[1].title, "You have completed this quest.")
		a:ObserveLocalQuestFocusProgress({ questId = 42, eventType = "QUEST_ACCEPTED" })
		a:Drain()
		Equal(a:BuildQuestFocusRows(state)[1].title, "Loading your quest progress…")
		member.state = "unknown"
		member.objectiveDetails[42].state = "unknown"
		Equal(a:BuildQuestFocusRows(state)[1].title, "Your quest status is not available yet.")
	end
)

QT:RegisterTest("tracker hover previews another quest without changing focus and retires late replies", function()
	local a = Fixture()
	a:UpdateQuestFocusWindow()
	a:Drain()
	local frame = a.questFocusWindow
	a.hover = 99
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(a.questFocusState.id, 99)
	Equal(a.focus, 42)
	local reply = a.sent[#a.sent].receiver
	a.hover = nil
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(a.questFocusState.id, 42)
	reply.onEntry({ questId = 99, questTitle = "Late hovered quest" })
	reply.onDone()
	a:Drain()
	Equal(frame.heading.text, "Focused quest 42")
	a.focus = nil
	a:UpdateQuestFocusWindow()
	Equal(frame:IsShown(), false)
	a.hover = 99
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(frame:IsShown(), true)
	Equal(a.questFocusState.id, 99)
	a.hover = nil
	a:UpdateQuestFocusWindow()
	Equal(frame:IsShown(), false)
	Equal(next(a.partyQuestProgress), nil)
end)

QT:RegisterTest("native tracker hover identifies only visible readable quest blocks through their children", function()
	local a = Fixture()
	local module = a:CreateTestUIRegion(a, a.root)
	local block = a:CreateTestUIRegion(a, module)
	block.parentModule, block.id = module, 42
	local header = a:CreateTestUIRegion(a, block)
	function a:GetQuestFocusHoverSources()
		return { header }, { quest = module }
	end
	a.GetHoveredTrackerQuestID = QT.GetHoveredTrackerQuestID
	Equal(a:GetHoveredTrackerQuestID(), 42)
	block.id = 43
	Equal(a:GetHoveredTrackerQuestID(), 43)
	block.parentModule = a:CreateTestUIRegion(a, a.root)
	Equal(a:GetHoveredTrackerQuestID(), nil)
	block.parentModule = module
	block:Hide()
	Equal(a:GetHoveredTrackerQuestID(), nil)
	block:Show()
	block.forbidden = true
	Equal(a:GetHoveredTrackerQuestID(), nil)
	block.forbidden = false
	a.restricted = true
	function a:GetQuestFocusHoverSources()
		error("restricted read")
	end
	Equal(a:GetHoveredTrackerQuestID(), nil)
end)

QT:RegisterTest("quest tracker preserves full Forever and Retail party identities in headers and statuses", function()
	for _, name in ipairs({ "Mira Frostbrook", "Mira-MoonGuard" }) do
		local a = Fixture()
		a.partyMemberOrder = { "Me", name }
		a:UpdateQuestFocusWindow()
		a:Drain()
		local reply = a.sent[1].receiver
		reply.onEntry({ questId = 42, objectives = { { text = "Supplies", current = 1, required = 8, objectiveIndex = 1 } } })
		reply.onDone()
		a:Drain()
		Equal(a:BuildQuestFocusRows(a.questFocusState)[3].title, name)
		local member = a.questFocusState.members[2]
		member.objectiveDetails[42].objectives = {}
		member.entries[42].isComplete = true
		Equal(a:BuildQuestFocusRows(a.questFocusState)[3].title, name .. " is ready to turn in this quest.")
	end
end)

QT:RegisterTest("quest tracker display modes choose focus hover and hidden without retaining obsolete requests", function()
	local a = Fixture()
	Equal(a:GetQuestTrackerMode(), "both")
	a.hover = 84
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState.id, 84)
	a:SetOption("questTrackerMode", "focus"); a:Drain()
	Equal(a.questFocusState.id, 42)
	a:SetOption("questTrackerMode", "hover"); a:Drain()
	Equal(a.questFocusState.id, 84)
	a.hover = nil
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState, nil)
	a:SetOption("questTrackerMode", "both")
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState.id, 42)
	local stale = a.sent[#a.sent].receiver
	a:SetOption("questTrackerMode", "hidden"); a:Drain()
	Equal(a.questFocusState, nil)
	Equal(a.questFocusWindow:IsShown(), false)
	stale.onEntry({ questId = 42, objectives = {} }); stale.onDone(); a:Drain()
	Equal(a.questFocusState, nil)
	a.manager = a:CreateTestUIRegion(a)
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState.id, nil)
	assert(a.questFocusWindow:IsShown())
	a:SelectQuestFocusWindow()
	local panel = a.questFocusWindow.editControls
	local menu = panel.ModeDropdown.Dropdown
	Equal(#menu.entries, 4)
	Equal(menu.entries[1].text, "Hidden")
	assert(menu.entries[1].selected())
	menu.entries[4].choose(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "both")
	Equal(a.questFocusState.id, 42)
	assert(panel:IsShown(), "switching displayed quest must not close the mode editor")
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "hidden")
	assert(panel:IsShown())
	panel.ResetButton.scripts.OnClick(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "both")
	menu.entries[2].choose(); a:Drain()
	panel.SaveButton.scripts.OnClick(); a:Drain()
	menu.entries[3].choose(); a:Drain()
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "focus")
	local oldChoice = menu.entries[1].choose
	a.db.profile = { questTrackerMode = "both", questFocusOpacity = 75 }
	oldChoice(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "both", "old menus cannot change another profile")
end)

QT:RegisterTest("quest tracker solo option follows actual grouping and keeps Edit Mode reachable", function()
	local a = Fixture()
	a.partyMemberOrder = { "Me" }
	a:UpdateQuestFocusWindow(); a:Drain()
	assert(a.questFocusWindow:IsShown(), "solo display is enabled by default")
	a:SetOption("questTrackerHideSolo", true); a:Drain()
	Equal(a.questFocusState, nil)
	Equal(a.questFocusWindow:IsShown(), false)
	a.partyMemberOrder = { "Me", "Friend" }
	a:UpdateQuestFocusWindow(); a:Drain()
	assert(a.questFocusWindow:IsShown())
	local stale = a.sent[#a.sent].receiver
	a.restricted = true
	a.partyMemberOrder = { "Me" }
	a:UpdateQuestFocusWindow(); a:Drain()
	stale.onEntry({ questId = 42, objectives = {} }); stale.onDone(); a:Drain()
	Equal(a.questFocusState, nil)
	a.restricted = false
	a.manager = a:CreateTestUIRegion(a)
	a:UpdateQuestFocusWindow(); a:Drain()
	assert(a.questFocusWindow:IsShown())
	a:SelectQuestFocusWindow()
	local panel = a.questFocusWindow.editControls
	local checkbox = panel.HideSoloCheckbox.Checkbox
	Equal(checkbox:GetChecked(), true)
	checkbox:SetChecked(false); checkbox.scripts.OnClick(checkbox); a:Drain()
	Equal(a:GetOption("questTrackerHideSolo"), false)
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:GetOption("questTrackerHideSolo"), true)
	panel.ResetButton.scripts.OnClick(); a:Drain()
	Equal(a:GetOption("questTrackerHideSolo"), false)
	panel.SaveButton.scripts.OnClick(); a:Drain()
	checkbox:SetChecked(true); checkbox.scripts.OnClick(checkbox); a:Drain()
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:GetOption("questTrackerHideSolo"), false)
end)
