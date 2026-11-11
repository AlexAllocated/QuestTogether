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
		return self.hover, self.hoverBlock, self.hoverNative
	end
	function a:GetQuestFocusNativeTooltip()
		return self.nativeTooltip
	end
	function a:GetQuestFocusHoverEventRegistry()
		return self.hoverEvents
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

QT:RegisterTest("remote focus headings and objectives sanitize markup while preserving wire observations", function()
	local peer = QT:CreateTestPartyQuestCompareFixture({})
	local accepted
	local ok, id = peer:RequestQuestCompare("Friend-Realm", {
		objectiveQuestId = 42, onEntry = function(entry) accepted = entry end, onDone = function() end,
	})
	assert(ok)
	local title = "|cffff0000|Hquest:42:0|h[결속]|h|r|TIcon:128:128|t|Aatlas:128:128|a"
	local objective = "|cffff0000|Hquest:42:0|h[任務: 1/8]|h|r|TIcon:128:128|t|Aatlas:128:128|a"
	local wire = assert(peer:EncodeCommRecord("QCRS", {
		requestId = id, snapshotId = "focus-markup", revision = "focus-markup-v1", count = 1, objectiveQuestId = 42,
		entries = { { questId = 42, questTitle = title, isPushable = true, objectiveCount = 1,
			objectives = { { questId = 42, objectiveIndex = 1, text = objective, kind = "item",
				current = 1, required = 8, finished = false } } } },
	}))
	local decoded = assert(peer:DecodeCommRecord("QCRS", wire))
	assert(peer:HandleQuestCompareResponse(decoded, "Friend-Realm"))
	local a = Fixture()
	function a:GetLocalizedQuestTitle() end
	function a:BuildQuestCompareResponseEntries() return {} end
	a:UpdateQuestFocusWindow()
	a:Drain()
	local receiver = assert(a.sent[1]).receiver
	receiver.onEntry(accepted)
	receiver.onDone()
	a:Drain()
	Equal(a.questFocusWindow.heading.text, "[결속]")
	local found = false
	for _, row in ipairs(a.questFocusWindow.rows) do
		if row.title.text:find("任務", 1, true) then
			Equal(row.title.text, "[任務: 1/8]")
			found = true
		end
	end
	assert(found)
	Equal(accepted.questTitle, title)
	Equal(accepted.objectives[1].text, objective)
	Equal(assert(peer:EncodeCommRecord("QCRS", decoded)), wire)
	function a:GetLocalizedQuestTitle() return "|cffffffffLocal quest|r" end
	Equal(a:GetQuestFocusTitle(a.questFocusState), "Local quest")
	function a:GetLocalizedQuestTitle() return "|TIcon:128:128|t" end
	Equal(a:GetQuestFocusTitle(a.questFocusState), "[결속]")
end)
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
		local rows = a:BuildQuestFocusRows(state)
		Equal(rows[1].status, nil)
		Equal(rows[1].questStatus, "Have")
		Equal(rows[3].questStatus, "Have")
		Equal(frame.rows[1].statusIcon:GetAtlas(), "Quest-In-Progress-Icon-yellow")
		Equal(frame.rows[3].statusIcon:GetAtlas(), "Quest-In-Progress-Icon-yellow")
		Equal(frame.rows[2].statusIcon:IsShown(), false)
		Equal(frame.rows[2].statusSymbol:IsShown(), false)
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
	a:UpdateQuestFocusWindow()
	a:Drain()
	local frame = a.questFocusWindow
	Equal(frame.strata, "LOW", "normal windows and item tooltips must cover the HUD")
	assert(frame.panel:GetFrameLevel() > frame:GetFrameLevel())
	assert(frame.rows[1]:GetFrameLevel() > frame.panel:GetFrameLevel())
	function frame:EnableMouse(enabled)
		self:Check()
		self.mouseEnabled = enabled
	end
	a.manager = a:CreateTestUIRegion(a)
	function a.manager:SaveLayouts() end
	function a.manager:IsEditModeActive()
		return self.active
	end
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(frame.strata, "LOW", "Edit Mode controls must remain above the tracker")
	Equal(frame.mouseEnabled, true)
	assert(frame.Selection:IsShown())
	Equal(frame.Selection.isSelected, false)
	Equal(frame.Selection.system:GetSystemName(), "Party Objective Tracker")
	Equal(frame.editControls, nil)
	frame.scripts.OnMouseDown(frame, "LeftButton")
	assert(frame.editControls:IsShown())
	Equal(frame.editControls.strata, "DIALOG")
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
	Equal(frame.strata, "LOW", "dismissing settings does not exit Edit Mode")
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
	Equal(frame.strata, "LOW", "leaving Edit Mode must not raise the HUD above other windows")
	Equal(frame.mouseEnabled, false, "the HUD must not capture normal tracker clicks")
	Equal(a.questFocusEditBaseline, nil)
	Equal(frame.Selection:IsShown(), false)
	a.db.profile = { questTrackerMode = "both", questFocusOpacity = 90 }
	a:UpdateQuestFocusWindow()
	a:Drain()
	Equal(frame:GetWidth(), 340)
	Equal(frame.background[1].textureColor[4], 0.9)
	Equal(frame.strata, "LOW", "saved-layout restoration must preserve ordinary HUD ordering")
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
	for _, name in ipairs({ "statusIcon", "statusSymbol" }) do
		local region = frame.rows[1][name]
		local writes = region.writes
		region.forbidden = true
		a:QueueQuestFocusRefresh()
		a:Drain()
		Equal(region.writes, writes, "restricted status art must not be repainted")
		Equal(a.invalidCalls, nil)
		region.forbidden = false
	end
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

QT:RegisterTest("tracker snapping follows native geometry and controls manual movement without disabling size sliders", function()
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
	Anchor("TOPRIGHT", 900, 800)
	local border = a:CreateTestUIRegion(a, tracker)
	tracker.NineSlice = border
	border.left, border.top = 870, 800
	border:SetSize(275, 500)
	local borderWrites = border.writes
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 870, 800)
	Equal(border.writes, borderWrites, "outer bounds are read-only")
	border.left, tracker.left = 70, 100
	a:UpdateQuestFocusWindow()
	Anchor("TOPLEFT", 345, 800)
	tracker.scale = 1.5
	a:UpdateQuestFocusWindow()
	Anchor("TOPLEFT", 517.5, 1200)
	tracker.NineSlice, tracker.scale = nil, 1
	tracker.left = 100
	a:UpdateQuestFocusWindow()
	Anchor("TOPLEFT", 340, 800)
	frame:SetWidth(420)
	a:SaveWindowLayout(frame)
	Equal(a.db.profile.windowLayouts.questFocus.width, 420)
	tracker.left, tracker.scale = 500, 1.5
	a:UpdateQuestFocusWindow()
	a:Drain()
	Anchor("TOPRIGHT", 750, 1200)
	Equal(tracker.writes, writes, "docking must never mutate Blizzard's tracker")
	a.root:SetScale(0.64)
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 750, 1200)
	a.root:SetScale(1)
	a:UpdateQuestFocusWindow()
	tracker.forbidden = true
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 750, 1200)
	tracker.forbidden = false
	a.restricted = true
	tracker.left = 100
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 750, 1200)
	a.restricted = false
	a:SetOption("questTrackerSnapToBlizzard", false)
	a:UpdateQuestFocusWindow()
	Anchor("TOPRIGHT", 750, 1200)
	a.manager = a:CreateTestUIRegion(a)
	a:UpdateQuestFocusWindow(); a:Drain()
	a:SelectQuestFocusWindow()
	local panel = frame.editControls
	local checkbox = panel.SnapCheckbox.Checkbox
	Equal(checkbox:GetChecked(), false)
	assert(frame.grip:IsShown())
	function a:GetWindowDragCursor() return 600, 500 end
	frame.scripts.OnDragStart()
	Equal(frame.dragging, true)
	frame.scripts.OnDragStop()
	frame.grip.scripts.OnMouseDown(frame.grip, "LeftButton")
	Equal(frame.resizing, true)
	frame.grip.scripts.OnMouseUp()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", a.root, "BOTTOMLEFT", 300, 400)
	a:SaveWindowLayout(frame)
	checkbox:SetChecked(true); checkbox.scripts.OnClick(checkbox); a:Drain()
	Anchor("TOPLEFT", 510, 1200)
	Equal(frame.grip:IsShown(), false)
	frame.grip.scripts.OnMouseDown(frame.grip, "LeftButton")
	Equal(frame.resizing, nil, "stale resize callbacks cannot resize a snapped tracker")
	panel.WidthSlider.change(480); panel.HeightSlider.change(700); a:Drain()
	Equal(frame:GetWidth(), 480)
	Equal(frame:GetHeight(), 700)
	Anchor("TOPLEFT", 510, 1200)
	frame.scripts.OnDragStart(); a:Drain()
	Equal(frame.dragging, true)
	Equal(a:IsQuestTrackerSnapped(), false, "dragging away disables snap")
	assert(frame.grip:IsShown())
	frame.scripts.OnDragStop()
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:IsQuestTrackerSnapped(), false)
	assert(frame.grip:IsShown())
	panel.ResetButton.scripts.OnClick(); a:Drain()
	Equal(a:IsQuestTrackerSnapped(), true)
	Equal(frame.grip:IsShown(), false)
	Anchor("TOPLEFT", 510, 1200)
	panel.SaveButton.scripts.OnClick(); a:Drain()
	checkbox:SetChecked(false); checkbox.scripts.OnClick(checkbox); a:Drain()
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:IsQuestTrackerSnapped(), true)
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
	Equal(frame.editControls.HeightSlider.settingData.settingName, "Max height")
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
		Equal(rows[1].questStatus, "Ready")
		Equal(rows[2].questStatus, "Ready")
		local icon, symbol = a.questFocusWindow.rows[1].statusIcon, a.questFocusWindow.rows[1].statusSymbol
		Equal(icon:GetAtlas(), "UI-QuestIcon-TurnIn-Normal")
		Equal(icon:IsShown(), true)
		Equal(symbol:IsShown(), false)
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
		Equal(a:BuildQuestFocusRows(state)[1].questStatus, "Completed")
		Equal(icon.texture, "Interface\\Buttons\\UI-CheckBox-Check")
		Equal(icon:GetAtlas(), nil, "completed history must discard the previous turn-in atlas")
		Equal(icon:IsShown(), true)
		a:ObserveLocalQuestFocusProgress({ questId = 42, eventType = "QUEST_ACCEPTED" })
		a:Drain()
		Equal(a:BuildQuestFocusRows(state)[1].title, "Loading your quest progress…")
		Equal(a:BuildQuestFocusRows(state)[1].questStatus, "Loading")
		Equal(icon:IsShown(), false)
		Equal(symbol:IsShown(), true)
		Equal(symbol:GetText(), "...")
		member.state = "unknown"
		member.objectiveDetails[42].state = "unknown"
		Equal(a:BuildQuestFocusRows(state)[1].title, "Your quest status is not available yet.")
		a:QueueQuestFocusRefresh(); a:Drain()
		Equal(a:BuildQuestFocusRows(state)[1].questStatus, "Unknown")
		Equal(symbol:GetText(), "?")
	end
)

QT:RegisterTest("POT status icons retain known readiness while details load and clear reused objective rows", function()
	local a = Fixture()
	a.localObjectives = {}
	function a:BuildQuestCompareResponseEntries(id)
		return { { questId = id, questTitle = "Delivery quest", objectives = self.localObjectives } }
	end
	a:UpdateQuestFocusWindow(); a:Drain()
	local state, frame = a.questFocusState, a.questFocusWindow
	local member, reused = state.members[2], frame.rows[2]
	Equal(reused.statusSymbol:GetText(), "...")
	Equal(reused.statusSymbol:IsShown(), true)
	-- The accepted summary already establishes readiness; the separate
	-- objective request is still pending and must not erase that evidence.
	member.entries[42], member.state = { questId = 42, isComplete = true }, "ready"
	member.objectiveDetails[42].state = "loading"
	a:QueueQuestFocusRefresh(); a:Drain()
	local rows = a:BuildQuestFocusRows(state)
	Equal(rows[2].status, "Loading")
	Equal(rows[2].questStatus, "Ready")
	Equal(reused.statusIcon:GetAtlas(), "UI-QuestIcon-TurnIn-Normal")
	Equal(reused.statusIcon:IsShown(), true)
	Equal(reused.statusSymbol:IsShown(), false)
	a.localObjectives = { { text = "Local objective", objectiveIndex = 1, current = 1, required = 8 } }
	a:QueueQuestFocusRefresh(true); a:Drain()
	Equal(frame.rows[2], reused)
	Equal(a:BuildQuestFocusRows(state)[2].kind, "objective")
	Equal(reused.statusIcon:IsShown(), false)
	Equal(reused.statusSymbol:IsShown(), false)
	Equal(reused.progressTrack:GetWidth(), frame.body:GetWidth() - 26)
	Equal(frame.rows[3].statusIcon:GetAtlas(), "UI-QuestIcon-TurnIn-Normal")
	Equal(a.invalidCalls, nil)
end)

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

QT:RegisterTest("focus and hover retains the active quest when unrelated waypoint state is unavailable", function()
	local a = Fixture()
	a.GetPartyQuestFocusID = QT.GetPartyQuestFocusID
	a.API.GetActiveTrackedQuestID = function() return a.focus end
	a.API.GetPartyNavigationNativeState = function() error("unreadable waypoint") end
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState.id, 42)
	a.hover = 99
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState.id, 99)
	a.hover = nil
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState.id, 42)
	a.focus = nil
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState, nil, "no active native focus must still hide the window")
	Equal(a.questFocusWindow:IsShown(), false)
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
	local placementMenu = panel.TooltipPlacementDropdown.Dropdown
	Equal(#placementMenu.entries, 3)
	Equal(placementMenu.entries[1].text, "Top")
	assert(placementMenu.entries[1].selected())
	placementMenu.entries[2].choose(); a:Drain()
	Equal(a:GetQuestTrackerTooltipPlacement(), "bottom")
	assert(panel:IsShown(), "switching displayed quest must not close the mode editor")
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "hidden")
	Equal(a:GetQuestTrackerTooltipPlacement(), "top")
	assert(panel:IsShown())
	panel.ResetButton.scripts.OnClick(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "hover")
	Equal(a:GetQuestTrackerTooltipPlacement(), "top")
	menu.entries[2].choose(); a:Drain()
	placementMenu.entries[3].choose(); a:Drain()
	panel.SaveButton.scripts.OnClick(); a:Drain()
	menu.entries[3].choose(); a:Drain()
	placementMenu.entries[1].choose(); a:Drain()
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "focus")
	Equal(a:GetQuestTrackerTooltipPlacement(), "side")
	local oldChoice = menu.entries[1].choose
	local oldPlacement = placementMenu.entries[2].choose
	a.db.profile = { questTrackerMode = "both", questFocusOpacity = 75 }
	oldChoice(); oldPlacement(); a:Drain()
	Equal(a:GetQuestTrackerMode(), "both", "old menus cannot change another profile")
	Equal(a:GetQuestTrackerTooltipPlacement(), "top", "stale placement menu cannot change another profile")
end)

QT:RegisterTest("quest tracker solo option follows actual grouping and keeps Edit Mode reachable", function()
	local a = Fixture()
	a.partyMemberOrder = { "Me" }
	a:ApplyDefaults(a.db.profile, QT.DEFAULTS.profile)
	Equal(a:GetOption("questTrackerHideSolo"), true)
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(a.questFocusState, nil, "new profiles hide the tracker while solo")
	a:SetOption("questTrackerHideSolo", false)
	a:ApplyDefaults(a.db.profile, QT.DEFAULTS.profile)
	Equal(a:GetOption("questTrackerHideSolo"), false, "saved choices survive default application")
	a:UpdateQuestFocusWindow(); a:Drain()
	assert(a.questFocusWindow:IsShown(), "solo display remains available when opted in")
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
	local hideTooltip = panel.HideTooltipCheckbox.Checkbox
	Equal(hideTooltip:GetChecked(), true)
	hideTooltip:SetChecked(false); hideTooltip.scripts.OnClick(hideTooltip); a:Drain()
	Equal(a:GetOption("questTrackerHideBlizzardTooltip"), false)
	checkbox:SetChecked(false); checkbox.scripts.OnClick(checkbox); a:Drain()
	Equal(a:GetOption("questTrackerHideSolo"), false)
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:GetOption("questTrackerHideSolo"), true)
	Equal(a:GetOption("questTrackerHideBlizzardTooltip"), true)
	panel.ResetButton.scripts.OnClick(); a:Drain()
	Equal(a:GetOption("questTrackerHideSolo"), true)
	Equal(a:GetOption("questTrackerHideBlizzardTooltip"), true)
	Equal(panel.ResetButton.enabled, false, "default tooltip visibility must not leave Reset enabled")
	hideTooltip:SetChecked(false); hideTooltip.scripts.OnClick(hideTooltip); a:Drain()
	Equal(panel.ResetButton.enabled, true, "show-both is a resettable nondefault choice")
	panel.ResetButton.scripts.OnClick(); a:Drain()
	Equal(a:GetOption("questTrackerHideBlizzardTooltip"), true)
	Equal(panel.ResetButton.enabled, false)
	panel.SaveButton.scripts.OnClick(); a:Drain()
	checkbox:SetChecked(false); checkbox.scripts.OnClick(checkbox); a:Drain()
	panel.RevertButton.scripts.OnClick(); a:Drain()
	Equal(a:GetOption("questTrackerHideSolo"), true)
end)

local function TooltipFixture()
	local a = Fixture()
	-- Geometry cases explicitly opt into showing both tooltips; new profiles
	-- hide the matching native tooltip instead.
	a.db.profile.questTrackerHideBlizzardTooltip = false
	a.root.top = 900
	a.hover = 42
	a.hoverBlock = a:CreateTestUIRegion(a, a.root)
	a.hoverBlock.id = 42
	a.hoverBlock.left, a.hoverBlock.top = 900, 650
	a.hoverBlock:SetSize(240, 80)
	a.hoverNative = true
	a.nativeTracker = a:CreateTestUIRegion(a, a.root)
	a.nativeTracker.left, a.nativeTracker.top = 900, 800
	a.nativeTracker:SetSize(240, 500)
	a.nativeTooltip = a:CreateTestUIRegion(a, a.root)
	local tip = a.nativeTooltip
	tip.left, tip.top = 550, 650
	tip:SetSize(300, 180)
	function tip:GetOwner() return self.tooltipOwner end
	tip.tooltipOwner = a.hoverBlock
	return a, tip
end

QT:RegisterTest("POT docks to matching native quest tooltips and restores its ordinary anchor without saving hover geometry", function()
	local a, tip = TooltipFixture()
	local writes = tip.writes
	a:UpdateQuestFocusWindow(); a:Drain()
	local frame = a.questFocusWindow
	local function Anchor(point, x, y)
		local p, relative, rp, px, py = frame:GetPoint(1)
		Equal(p, point); Equal(relative, a.root); Equal(rp, "BOTTOMLEFT")
		Equal(px, x); Equal(py, y)
	end
	Equal(a:GetQuestTrackerTooltipPlacement(), "top")
	Equal(frame.strata, "LOW", "quest-tooltip docking must not raise POT over other windows")
	Anchor("TOPLEFT", 850 - frame.panel:GetWidth(), 650 + frame.panel:GetHeight())
	assert(frame.panel:GetHeight() < 250 and frame:GetHeight() == 600,
		"top placement must use compact visible content, not the configured maximum")
	tip.top = 895
	a:UpdateQuestFocusWindow(); a:Drain()
	Anchor("TOPLEFT", 850 - frame.panel:GetWidth(), 715)
	a:SetOption("questTrackerTooltipPlacement", "bottom"); tip.top = 650; a:Drain()
	Anchor("TOPLEFT", 850 - frame.panel:GetWidth(), 470)
	tip.top = 190
	a:UpdateQuestFocusWindow(); a:Drain()
	Anchor("TOPLEFT", 850 - frame.panel:GetWidth(), 190 + frame.panel:GetHeight())
	-- Mixed scales must still align the actual right edges in screen space.
	a.root:SetScale(0.8); tip.scale, tip.top = 1.25, 500
	a:UpdateQuestFocusWindow(); a:Drain()
	local _, _, _, mixedX, mixedY = frame:GetPoint(1)
	local fs, ts = frame:GetEffectiveScale(), tip:GetEffectiveScale()
	assert(math.abs((mixedX + frame.panel:GetWidth()) * fs - (tip.left + tip:GetWidth()) * ts) < 0.001)
	assert(math.abs(mixedY * fs - (tip.top - tip:GetHeight()) * ts) < 0.001)
	a.root:SetScale(1); tip.scale, tip.top = 1, 650
	a:SetOption("questTrackerTooltipPlacement", "side"); a:Drain()
	Anchor("TOPLEFT", 206, 650)
	Equal(tip.writes, writes, "show-both docking only reads native UI")
	Equal(a.db.profile.windowLayouts, nil, "hover docking must not persist a new placement")
	tip.left, tip.top = 50, 190
	a:UpdateQuestFocusWindow()
	local _, _, _, x, y = frame:GetPoint(1)
	Equal(x, 354, "left edge flips POT to the right")
	assert(y >= frame.panel:GetHeight(), "visible content stays above the screen bottom")
	Equal(frame:GetHeight(), 600, "maximum height survives transient docking")
	tip.left, tip.top, tip.scale = 400, 500, 1.5
	a:UpdateQuestFocusWindow()
	Anchor("TOPLEFT", 256, 750)
	tip:Hide()
	a:UpdateQuestFocusWindow(); a:Drain()
	Anchor("TOPRIGHT", 900, 800)
	Equal(frame.questTooltipDocked, nil)
	Equal(frame.strata, "LOW", "undocking must retain ordinary HUD ordering")
	-- The same quest can be both hovered and focused: it must undock even
	-- though no model/revision change forces a render.
	tip:Show(); tip.scale, tip.left, tip.top = 1, 550, 650
	a:UpdateQuestFocusWindow(); a:Drain()
	a.hover = nil
	a:UpdateQuestFocusWindow(); a:Drain()
	Anchor("TOPRIGHT", 900, 800)
	Equal(a.questFocusState.id, 42)
	a.hover = 42
	a:UpdateQuestFocusWindow(); a:Drain()
	a:SetOption("questTrackerSnapToBlizzard", false); a:Drain()
	Equal(frame.questTooltipDocked, nil, "manual placement is respected")
	local before = { frame:GetPoint(1) }
	tip.left = 200
	a:UpdateQuestFocusWindow()
	local after = { frame:GetPoint(1) }
	for i = 1, 5 do Equal(after[i], before[i]) end
end)

QT:RegisterTest("POT native tooltip suppression cannot hide unrelated pooled protected or restricted UI", function()
	-- The hide preference never replaces the rules deciding whether POT can
	-- present this quest. Exercise the real update path for each exclusion.
	for _, configure in ipairs({
		function(a) a.db.profile.questTrackerMode = "hidden" end,
		function(a) a.db.profile.questTrackerMode = "focus"; a.focus = nil end,
		function(a) a.db.profile.questTrackerMode = "focus"; a.focus = 84 end,
		function(a) a.db.profile.questTrackerMode = "hover"; a.hover = nil end,
		function(a) a.focus, a.hover = nil, nil end,
		function(a) a.db.profile.questTrackerHideSolo = true; a.partyMemberOrder = { "Me" } end,
		function(a) a.manager = a:CreateTestUIRegion(a) end,
	}) do
		local gated, native = TooltipFixture()
		gated.db.profile.questTrackerHideBlizzardTooltip = true
		configure(gated)
		gated:UpdateQuestFocusWindow(); gated:Drain()
		Equal(native:IsShown(), true, "native tooltip must remain when POT is not presenting that hover")
	end
	local a, tip = TooltipFixture()
	a:SetOption("questTrackerHideBlizzardTooltip", true)
	-- A child button can share a quest ancestor while its tooltip is an item.
	tip.tooltipOwner = a:CreateTestUIRegion(a, a.hoverBlock)
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip:IsShown(), true)
	tip.tooltipOwner = a.hoverBlock
	a.hoverNative = false -- bonus/world reward headers are not quest progress
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip:IsShown(), true)
	a.hoverNative = true
	a.hoverBlock.id = 99
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip:IsShown(), true, "recycled quest owner must not qualify")
	a.hoverBlock.id = 42
	tip.protected = true
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip:IsShown(), true)
	assert(a.questFocusWindow.questTooltipDocked, "unsafe hiding falls back to show-both layout")
	tip.protected, tip.forbidden = false, true
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip.shown, true)
	tip.forbidden = false
	a.restricted = true
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip:IsShown(), true)
	a.restricted = false
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip:IsShown(), false)
	Equal(a.questFocusWindow:IsShown(), true)
	Equal(a.invalidCalls, nil)
	tip:Show()
	a.questFocusWindow.panel:Hide()
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip:IsVisible(), true, "a shown POT frame with invisible content must not suppress the native tooltip")
	a.questFocusWindow.panel:Show()
	local stale = a.questFocusState
	a.db.profile = { questTrackerMode = "both", questTrackerHideBlizzardTooltip = true }
	a:UpdateQuestTrackerTooltipAnchor(a.questFocusWindow, stale)
	Equal(tip:IsShown(), true, "an obsolete profile must not hide a native tooltip before the next render")
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip:IsShown(), false, "the current visible POT still replaces its matching tooltip")
	tip:Show()
	a.db.profile.questTrackerMode = "hidden"
	a:UpdateQuestTrackerTooltipAnchor(a.questFocusWindow, a.questFocusState)
	Equal(tip:IsShown(), true, "changing display mode must take effect before any queued render")
	-- Blizzard owns the next Show; disable/leave must never resurrect it.
	local writes = tip.writes
	a.isEnabled = false
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(tip.writes, writes)
	Equal(a.questFocusWindow:IsShown(), false)
end)

QT:RegisterTest("POT tooltip placement uses vertical fallback or bounded scale without overlap", function()
	local screen = { left = 0, right = 800, top = 700, bottom = 0 }
	local tip = { left = 250, right = 650, top = 300, bottom = 100 }
	local topX, topY, topScale = QT:PlaceQuestTrackerAtTooltip(screen, tip, 340, 220, 4)
	Equal(topX + 340, tip.right)
	Equal(topY - 220, tip.top)
	Equal(topScale, 1)
	-- Opposite vertical edge wins over a perfectly usable side when the
	-- configured edge has no room, without shrinking a full-size alternative.
	tip.left, tip.right, tip.top, tip.bottom = 500, 750, 650, 450
	local belowX, belowY, belowScale = QT:PlaceQuestTrackerAtTooltip(screen, tip, 340, 220, 4, nil, "top")
	Equal(belowX + 340, tip.right); Equal(belowY, tip.bottom); Equal(belowScale, 1)
	tip.top, tip.bottom = 250, 50
	local aboveX, aboveY, aboveScale = QT:PlaceQuestTrackerAtTooltip(screen, tip, 340, 220, 4, nil, "bottom")
	Equal(aboveX + 340, tip.right); Equal(aboveY - 220, tip.top); Equal(aboveScale, 1)
	tip.left, tip.right, tip.top, tip.bottom = 0, 180, 300, 100
	local edgeX, edgeY = QT:PlaceQuestTrackerAtTooltip(screen, tip, 340, 220, 4)
	Equal(edgeX, 0, "screen bounds take priority when right alignment cannot fit")
	Equal(edgeY - 220, tip.top)
	tip.left, tip.right, tip.top, tip.bottom = 250, 650, 300, 100
	local x, y, factor = QT:PlaceQuestTrackerAtTooltip(screen, tip, 340, 220, 4, nil, "side")
	Equal(factor, 1)
	assert(x >= 0 and x + 340 <= screen.right)
	assert(y - 220 >= tip.top + 4, "narrow screens put POT above the tooltip")
	tip.left, tip.right, tip.top, tip.bottom = 350, 750, 650, 50
	x, y, factor = QT:PlaceQuestTrackerAtTooltip(screen, tip, 500, 400, 4, nil, "side")
	assert(factor >= 0.6 and factor < 1)
	assert(x >= 0 and x + 500 * factor <= tip.left - 4)
	assert(y <= screen.top and y - 400 * factor >= screen.bottom)
	tip.left, tip.right, tip.top, tip.bottom = 0, 800, 700, 0
	Equal(QT:PlaceQuestTrackerAtTooltip(screen, tip, 340, 200, 4, nil, "side"), nil, "no unreadably tiny fallback")
	tip.left, tip.right, tip.top, tip.bottom = 10, 310, 500, 320
	local source = { left = 320, right = 550, top = 550, bottom = 400 }
	x, y, factor = QT:PlaceQuestTrackerAtTooltip(screen, tip, 340, 220, 4, source, "side")
	Equal(factor, 1)
	assert(y <= source.bottom - 4 or y - 220 >= source.top + 4, "never cover the hovered native row")
	tip.left, tip.right = 850, 1200
	x, y, factor = QT:PlaceQuestTrackerAtTooltip(screen, tip, 340, 220, 4, nil, "side")
	assert(x >= screen.left and x + 340 * factor <= screen.right, "offscreen tooltips cannot drag POT offscreen")
end)

QT:RegisterTest("native quest hover events coalesce and revalidate after leave disable and edit mode", function()
	local a, tip = TooltipFixture()
	a.hoverEvents = a:CreateTestUIRegion(a)
	a:UpdateQuestFocusWindow(); a:Drain()
	local events, frame = a.hoverEvents, a.questFocusWindow
	for _ = 1, 3 do events:TriggerEvent("OnQuestBlockHeader.OnEnter") end
	Equal(#a.jobs, 1)
	a.hover = nil
	a:Drain()
	Equal(frame.questTooltipDocked, nil)
	a.hover = 42
	events:TriggerEvent("OnQuestBlockHeader.OnEnter")
	a.isEnabled = false
	a:ResetQuestFocusWindow(); a:Drain()
	Equal(frame:IsShown(), false)
	a.isEnabled = true
	a.manager = a:CreateTestUIRegion(a)
	a:UpdateQuestFocusWindow(); a:Drain()
	Equal(frame.questTooltipDocked, nil, "Edit Mode retains normal full placement bounds")
	Equal(tip:IsShown(), true)
end)

_G.QuestTogether:RecordTestModule("scripts/regression_quest_focus.lua")
