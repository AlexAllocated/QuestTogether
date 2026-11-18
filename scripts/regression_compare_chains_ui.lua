-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
-- Contract-level UI fixtures use prepared rows only: no provider or engine input.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
local function Open(expanded)
	local a = QT:CreateTestPartyQuestCompareFixture({
		[1] = { questId = 1, questTitle = "Known quest", isPushable = true },
		[2] = { questId = 2, questTitle = "Other quest", isPushable = true },
	})
	a.options.reduceMotion = true
	a.chainFixtureOpen, a.chainFixtureInstance, a.chainFixtureAvailable = expanded ~= false, "chain:fixture", true
	a.chainFixtureGrouped = true
	a.chainFixtureOrigin = "quest:1"
	function a:ShowSettingsTooltip(owner, title, text) self.tooltip, self.tooltipOwner = { title, text }, owner end
	function a:HideSettingsTooltip(owner)
		if not owner or owner == self.tooltipOwner then self.tooltip, self.tooltipOwner = nil, nil end
	end
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows = {}
		if self.chainFixtureGrouped then
			rows[1] = { rowId = "chainGroup:1", kind = "chainGroup", groupId = 1, chainGroupId = 1,
				title = "Related quests", cells = {}, selectable = true, expanded = not self.chainFixtureGroupCollapsed }
		end
		for _, row in ipairs(roots) do
			row.rowId = "quest:" .. row.questId
			row.chainAvailable = self.chainFixtureAvailable
			row.chainExpanded = self.chainFixtureOpen and row.rowId == self.chainFixtureOrigin
			row.chainGroupId, row.chainGroupMember, row.chainGroupEnd = nil, nil, nil
		end
		if self.chainFixtureGrouped and self.chainFixtureGroupCollapsed then rows[#rows + 1] = roots[2]; return rows end
		rows[#rows + 1] = roots[1]
		if self.chainFixtureObjectives then
			rows[#rows + 1] = { rowId = "quest:1:member", kind = "member", questId = 1, title = "Player", cells = {} }
			rows[#rows + 1] = { rowId = "quest:1:objective", kind = "objective", questId = 1, title = "Objective", cells = {}, fraction = 0.5 }
		end
		if self.chainFixtureOpen then
			rows[#rows + 1] = { rowId = self.chainFixtureInstance .. ":notice", kind = "chainNotice", title = "Partial quest chain information", cells = {}, chainInstanceId = self.chainFixtureInstance }
			for id = 1, 30 do
				rows[#rows + 1] = { rowId = self.chainFixtureInstance .. ":quest:" .. id, kind = "chainStep", questId = id,
					title = id == 1 and "Known quest" or "Quest name hidden", cells = { id == 1 and "Have" or "Unknown", "Absent" },
					selectable = true, chainInstanceId = self.chainFixtureInstance, depth = id % 3,
					spoilerHidden = id ~= 1,
					memberPrerequisiteText = { "Known prerequisites met", "Prerequisites unknown" } }
			end
			rows[#rows + 1] = { rowId = self.chainFixtureInstance .. ":more:later", kind = "chainMore", title = "Show later quests", cells = {}, selectable = true, direction = "later", chainInstanceId = self.chainFixtureInstance }
		end
		if self.chainFixtureGrouped then
			for index = 2, #rows do rows[index].chainGroupId, rows[index].chainGroupMember = 1, true end
			rows[#rows].chainGroupEnd = true
		end
		rows[#rows + 1] = roots[2]
		return rows
	end
	function a:TogglePartyQuestChain(id, origin)
		self.toggledChain, self.chainToggles = { id, origin }, (self.chainToggles or 0) + 1
		self.chainFixtureOpen = not (self.chainFixtureOpen and self.chainFixtureOrigin == origin)
		self.chainFixtureOrigin = origin
		self.partyQuestCompareSession.chains.instance = self.partyQuestCompareSession.chains.instance + 1
		self:RenderPartyQuestCompare()
		return true
	end
	function a:ClosePartyQuestChain()
		if not self.chainFixtureOpen then return false end
		self.chainFixtureOpen = false
		self.partyQuestCompareSession.chains.instance = self.partyQuestCompareSession.chains.instance + 1
		return true, self.chainFixtureOrigin
	end
	function a:TogglePartyQuestChainGroup(id) self.toggledGroup = id; return true end
	function a:ExpandPartyQuestChain(direction) self.expandedDirection = direction; return true end
	function a:GetPartyQuestChainActions(row)
		return { { label = "Find quest giver", action = function() self.actedOn = row.rowId end } }
	end
	a:OpenPartyQuestCompare(); a:RenderPartyQuestCompare()
	local frame = a.partyQuestCompareWindow
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	return a, frame, a.partyQuestCompareSession
end
local function Key(frame, key) frame.keyboardInput:RunScript("OnKeyDown", key); frame.keyboardInput:RunScript("OnKeyUp", key) end
local function Row(frame, rowID)
	for _, row in ipairs(frame.rows) do if row.data and row.data.rowId == rowID then return row end end
end

local function CenteredChain()
	local a, frame, session = Open(false)
	a.chainFixtureGrouped = false
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows, instance = {}, self.chainFixtureInstance
		if not roots[1] then return rows end
		for id = 10, 16 do
			rows[#rows + 1] = { rowId = "quest:" .. id, questId = id, title = "Unrelated quest", cells = {} }
		end
		local root = roots[1]
		root.rowId, root.chainAvailable, root.chainExpanded = "quest:1", true, self.chainFixtureOpen
		root.chainAnchor, root.chainInstanceId, root.depth = self.chainFixtureOpen or nil, self.chainFixtureOpen and instance or nil, 0
		local function Step(id)
			rows[#rows + 1] = { rowId = instance .. ":quest:" .. id, kind = "chainStep", questId = id,
				title = "Related quest", cells = { "Completed", "Absent" }, chainInstanceId = instance, depth = 0, selectable = true }
		end
		if self.chainFixtureOpen then
			for id = 101, 100 + (self.earlierCount or 30) do Step(id) end
		end
		rows[#rows + 1] = root
		if self.chainFixtureObjectives then
			rows[#rows + 1] = { rowId = "quest:1:objective", kind = "objective", questId = 1,
				title = "Objective", cells = {}, chainInstanceId = root.chainInstanceId }
		end
		if self.chainFixtureOpen then for id = 201, 230 do Step(id) end end
		roots[2].rowId = "quest:2"; rows[#rows + 1] = roots[2]
		return rows
	end
	local toggle = a.TogglePartyQuestChain
	function a:TogglePartyQuestChain(id, origin)
		session.chains.rootQuestID = not self.chainFixtureOpen and id or nil
		return toggle(self, id, origin)
	end
	a:RenderPartyQuestCompare()
	return a, frame, session
end

local function TickChain(frame, elapsed)
	local update = frame.chainAnimator:GetScript("OnUpdate")
	if update then update(frame.chainAnimator, elapsed or 0.1) end
end
local function FinishChain(frame)
	for _ = 1, 3 do TickChain(frame) end
	Equal(frame.chainExpansion, nil)
end
local function Near(actual, expected)
	assert(math.abs(actual - expected) < 0.001, tostring(actual) .. " differs from " .. tostring(expected))
end

QT:RegisterTest("chain animation clips both sides outward while retaining the origin and objective geometry", function()
	local a, frame, session = CenteredChain()
	a.options.reduceMotion = false
	a.chainFixtureObjectives, session.expandedQuestIds[1] = true, true
	a:RenderPartyQuestCompare()
	local offset = a:CapturePartyQuestScrollAnchor("quest:1").offset
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(frame.chainExpansion.reveal, 0)
	assert(Row(frame, "quest:1") and Row(frame, "quest:1:objective"))
	for _, row in ipairs(frame.navigationRows) do assert(row.data.kind ~= "chainStep") end
	local build = a.BuildPartyQuestDiffRows
	function a:BuildPartyQuestDiffRows() error("animation rebuilt quest snapshots") end
	TickChain(frame, 0.05)
	assert(frame.chainExpansion.reveal > 0 and frame.chainExpansion.reveal < 1)
	Near(a:CapturePartyQuestScrollAnchor("quest:1").offset, offset)
	local before, after = false, false
	for _, row in ipairs(frame.navigationRows) do
		before = before or row.questId == 130
		after = after or row.questId == 201
	end
	assert(before and after, "context should open on both sides of the retained quest")
	a.blocked = true
	local paused = frame.chainExpansion.reveal
	TickChain(frame, 0.05); Equal(frame.chainExpansion.reveal, paused)
	a.blocked = false
	FinishChain(frame)
	Near(a:CapturePartyQuestScrollAnchor("quest:1").offset, offset)
	a.BuildPartyQuestDiffRows = build
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain animation reverses smoothly and closing remnants cannot receive input", function()
	local a, frame, session = CenteredChain()
	a.options.reduceMotion = false
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton"); FinishChain(frame)
	local offset = a:CapturePartyQuestScrollAnchor("quest:1").offset
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(frame.chainExpansion.target, 0)
	local ghost
	for _, row in ipairs(frame.rows) do
		if row.data and row.data.chainClosing then
			ghost = row
			Equal(row.session, nil); Equal(a:IsPartyQuestSelectableRow(row.data), false)
			assert(not row.journal:IsShown() and not row.action:IsShown())
			for _, control in ipairs(row.cellTooltips or {}) do assert(not control:IsShown()) end
		end
	end
	assert(ghost)
	local selected = session.keyboardRowId
	ghost:RunScript("OnMouseUp", "LeftButton"); ghost.journal:RunScript("OnClick")
	Equal(session.keyboardRowId, selected)
	for _, row in ipairs(frame.navigationRows) do assert(not row.data.chainClosing) end
	TickChain(frame, 0.05)
	Near(a:CapturePartyQuestScrollAnchor("quest:1").offset, offset)
	local from, retired = frame.chainExpansion.reveal, frame.chainAnimator:GetScript("OnUpdate")
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(frame.chainExpansion.from, from); Equal(frame.chainExpansion.target, 1)
	retired(frame.chainAnimator, 0.1); Equal(frame.chainExpansion.reveal, from)
	FinishChain(frame)
	for _, row in ipairs(frame.displayRows) do assert(not row.chainClosing) end
	a:ScrollPartyQuestCompareToRow(frame, "chain:fixture:quest:101")
	assert(Row(frame, "chain:fixture:quest:101"))
	a:ScrollPartyQuestCompareToRow(frame, "quest:1")
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton"); FinishChain(frame)
	assert(Row(frame, "quest:1")); Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain animation retires for filters session changes hide and reduced motion", function()
	for _, change in ipairs({ "filter", "session", "hide", "motion", "retire", "profile" }) do
		local a, frame, session = CenteredChain()
		a.options.reduceMotion = false
		Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
		TickChain(frame, 0.05)
		local retired = frame.chainAnimator:GetScript("OnUpdate")
		if change == "filter" then a:SetPartyQuestCompareFilter("search", "does not match"); a:RenderPartyQuestCompare()
		elseif change == "session" then a:RefreshPartyQuestCompare(); a:RenderPartyQuestCompare()
		elseif change == "hide" then frame.close:RunScript("OnClick")
		elseif change == "retire" then session.chains.retired = true; TickChain(frame, 0.05)
		elseif change == "profile" then a.db.profile = {}; TickChain(frame, 0.05)
		else a.options.reduceMotion = true; a:RenderPartyQuestCompare() end
		Equal(frame.chainExpansion, nil)
		retired(frame.chainAnimator, 0.1); Equal(frame.chainExpansion, nil)
		Equal(frame.chainAnimator:GetScript("OnUpdate"), nil)
		Equal(a.invalidCalls, nil)
	end
	local a, frame = CenteredChain()
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(frame.chainExpansion, nil)
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(frame.chainExpansion, nil)
	for _, row in ipairs(frame.displayRows) do assert(not row.chainClosing) end
end)

QT:RegisterTest("chain animation cancels old wheel momentum only when toggled", function()
	local a, frame = CenteredChain()
	a.options.reduceMotion = false
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton"); FinishChain(frame)
	frame.viewport:RunScript("OnMouseWheel", -1); frame:RunScript("OnUpdate", 0.016)
	assert(frame.wheelTarget and frame:GetScript("OnUpdate"))
	local offset = a:CapturePartyQuestScrollAnchor("quest:1").offset
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(frame.wheelTarget, nil); Equal(frame:GetScript("OnUpdate"), nil)
	TickChain(frame, 0.05)
	Near(a:CapturePartyQuestScrollAnchor("quest:1").offset, offset)
	frame.viewport:RunScript("OnMouseWheel", -1)
	local target = frame.wheelTarget
	a:RenderPartyQuestCompare(); Equal(frame.wheelTarget, target)
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(frame.wheelTarget, nil); Equal(frame:GetScript("OnUpdate"), nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain animation suspension discards closing remnants before resumed scrolling", function()
	local a, frame = CenteredChain()
	a.options.reduceMotion = false
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton"); FinishChain(frame)
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton"); TickChain(frame, 0.05)
	assert(frame.chainExpansion and frame.chainExpansion.closing)
	a:GetWindowController(frame).hooks.suspend()
	Equal(frame.chainExpansion, nil)
	for _, row in ipairs(frame.displayRows) do assert(not row.chainClosing) end
	a:ScrollPartyQuestCompareToRow(frame, "quest:1")
	for _, row in ipairs(frame.rows) do assert(not row.data or not row.data.chainClosing) end
	Equal(frame.chainAnimator:GetScript("OnUpdate"), nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI keeps the retained origin onscreen through ancestors arriving and collapse", function()
	local a, frame, session = CenteredChain()
	a.chainFixtureObjectives, session.expandedQuestIds[1] = true, true
	a:RenderPartyQuestCompare()
	a:SelectPartyQuestKeyboardRow(frame, { rowId = "quest:1", questId = 1 }, "chain")
	local offset = a:CapturePartyQuestScrollAnchor("quest:1").offset
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	assert(Row(frame, "quest:1")); Equal(a:CapturePartyQuestScrollAnchor("quest:1").offset, offset)
	Equal(session.keyboardRowId, "quest:1"); Equal(session.keyboardRole, "chain")
	local occurrences = 0
	for _, row in ipairs(frame.navigationRows) do if row.questId == 1 then occurrences = occurrences + 1 end end
	Equal(occurrences, 1)
	-- An asynchronously extended provider result must not move the clicked row.
	a.earlierCount = 60; a:RenderPartyQuestCompare()
	assert(Row(frame, "quest:1")); Equal(a:CapturePartyQuestScrollAnchor("quest:1").offset, offset)
	Key(frame, "UP"); Equal(session.keyboardRowId, "chain:fixture:quest:160")
	Key(frame, "DOWN"); Equal(session.keyboardRowId, "quest:1")
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	assert(Row(frame, "quest:1")); Equal(a:CapturePartyQuestScrollAnchor("quest:1").offset, offset)
	Equal(session.expandedQuestIds[1], true); assert(Row(frame, "quest:1:objective"))
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI outline covers earlier origin objectives and later rows but never unrelated rows", function()
	local a, frame, session = CenteredChain()
	a.chainFixtureObjectives, session.expandedQuestIds[1] = true, true
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	local root, detail = assert(Row(frame, "quest:1")), assert(Row(frame, "quest:1:objective"))
	Equal(root.title.points[1][2], 40); Equal(root.partySummary.points[1][2], 40)
	for _, row in ipairs({ root, detail }) do
		assert(row.chainEdges[1]:IsShown() and row.chainEdges[2]:IsShown())
		Equal(row.chainEdges[3]:IsShown(), false); Equal(row.chainEdges[4]:IsShown(), false)
		Equal(row.chainEdges[1]:GetHeight(), row:GetHeight())
	end
	local columnX = root.cellShades[1].points[1][2]
	a:ScrollPartyQuestCompareToRow(frame, "chain:fixture:quest:101")
	local first = assert(Row(frame, "chain:fixture:quest:101"))
	assert(first.chainEdges[3]:IsShown()); Equal(first.chainEdges[4]:IsShown(), false)
	Equal(first.cellShades[1].points[1][2], columnX)
	a:ScrollPartyQuestCompareToRow(frame, "quest:2")
	local last, unrelated = assert(Row(frame, "chain:fixture:quest:230")), assert(Row(frame, "quest:2"))
	assert(last.chainEdges[4]:IsShown()); Equal(last.chainEdges[3]:IsShown(), false)
	for _, edge in ipairs(unrelated.chainEdges) do Equal(edge:IsShown(), false) end
	a:ScrollPartyQuestCompareToRow(frame, "quest:1")
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	for _, edge in ipairs(Row(frame, "quest:1").chainEdges) do Equal(edge:IsShown(), false) end
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI objective closing animation inherits the current section outline", function()
	local a, frame, session = CenteredChain()
	a.options.reduceMotion = false
	local build = a.BuildPartyQuestCompareDisplayRows
	function a:BuildPartyQuestCompareDisplayRows(roots)
		self.chainFixtureObjectives = session.expandedQuestIds[1] == true
		return build(self, roots)
	end
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Row(frame, "quest:1"):RunScript("OnMouseUp", "LeftButton"); a:RenderPartyQuestCompare()
	for _ = 1, 3 do frame.expansionAnimator:RunScript("OnUpdate", 0.1) end
	assert(Row(frame, "quest:1:objective"))
	Row(frame, "quest:1"):RunScript("OnMouseUp", "LeftButton"); a:RenderPartyQuestCompare()
	assert(frame.expansions[1].closingRows)
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	local closing = assert(Row(frame, "quest:1:objective"))
	Equal(closing.data.chainInstanceId, nil)
	for _, edge in ipairs(closing.chainEdges) do Equal(edge:IsShown(), false) end
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	closing = assert(Row(frame, "quest:1:objective"))
	Equal(closing.data.chainInstanceId, a.chainFixtureInstance)
	assert(closing.chainEdges[1]:IsShown() and closing.chainEdges[2]:IsShown())
	for _ = 1, 3 do frame.expansionAnimator:RunScript("OnUpdate", 0.1) end
	Equal(Row(frame, "quest:1:objective"), nil)
	assert(Row(frame, "quest:1")); Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI group boundaries indent only members and survive scrolling collapse and ungrouping", function()
	local a, frame, session = Open()
	a.chainFixtureObjectives, session.expandedQuestIds[1] = true, true
	a:RenderPartyQuestCompare()
	local heading, root = assert(Row(frame, "chainGroup:1")), assert(Row(frame, "quest:1"))
	Equal(heading.title.points[1][2], 28); Equal(root.title.points[1][2], 46)
	Equal(root.expander.points[1][2], 24); Equal(root.partySummary.points[1][2], 46)
	assert(heading.groupRail:IsShown() and root.groupRail:IsShown()); Equal(root.groupEnd:IsShown(), false)
	local columnX = root.cellShades[1].points[1][2]
	for _, id in ipairs({ "quest:1:member", "quest:1:objective" }) do
		local detail = assert(Row(frame, id))
		assert(detail.groupRail:IsShown()); Equal(detail.groupRail:GetHeight(), detail:GetHeight())
		Equal(detail.groupEnd:IsShown(), false)
	end
	local objective = Row(frame, "quest:1:objective")
	Equal(objective.title.points[1][2], 82); Equal(objective.progressTrack.points[1][2], 82)
	local step = assert(Row(frame, "chain:fixture:quest:1"))
	Equal(step.title.points[1][2], 72); Equal(step.branch.points[1][2], 57)
	assert(step.groupRail:IsShown()); Equal(step.cellShades[1].points[1][2], columnX)
	a:ScrollPartyQuestCompareToRow(frame, "quest:2")
	local last, unrelated = assert(Row(frame, "chain:fixture:more:later")), assert(Row(frame, "quest:2"))
	assert(last.groupRail:IsShown() and last.groupEnd:IsShown())
	Equal(last.groupEnd.points[1][3], 1 - last:GetHeight())
	Equal(unrelated.title.points[1][2], 28); Equal(unrelated.expander.points[1][2], 6)
	Equal(unrelated.cellShades[1].points[1][2], columnX)
	Equal(unrelated.groupRail:IsShown(), false); Equal(unrelated.groupEnd:IsShown(), false)
	a.chainFixtureGroupCollapsed = true; a:RenderPartyQuestCompare()
	heading, unrelated = assert(Row(frame, "chainGroup:1")), assert(Row(frame, "quest:2"))
	Equal(heading.groupRail:IsShown(), false); Equal(heading.groupEnd:IsShown(), false)
	Equal(unrelated.groupRail:IsShown(), false); Equal(unrelated.title.points[1][2], 28)
	a.chainFixtureGroupCollapsed, a.chainFixtureGrouped = false, false
	a:RenderPartyQuestCompare(); a:ScrollPartyQuestCompareToRow(frame, "quest:1")
	root = assert(Row(frame, "quest:1"))
	Equal(root.title.points[1][2], 28); Equal(root.expander.points[1][2], 6)
	Equal(root.groupRail:IsShown(), false); Equal(root.groupEnd:IsShown(), false)
	Equal(Row(frame, "quest:1:objective").progressTrack.points[1][2], 64)
	Equal(session.expandedQuestIds[1], true)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI keyboard traverses distinct quest instances and offscreen branch controls", function()
	local a, frame, session = Open()
	Equal(session.keyboardRowId, "chainGroup:1")
	Key(frame, "ENTER"); Equal(a.toggledGroup, 1)
	Key(frame, "DOWN"); Equal(session.keyboardRowId, "quest:1")
	Key(frame, "RIGHT"); Equal(session.keyboardRole, "chain")
	Key(frame, "ENTER"); Equal(a.chainFixtureOpen, false); Equal(a.toggledChain[2], "quest:1")
	Key(frame, "ENTER"); Equal(a.chainFixtureOpen, true); Equal(a.chainToggles, 2)
	Key(frame, "LEFT"); Equal(session.keyboardRole, "quest")
	Key(frame, "ENTER"); Equal(session.expandedQuestIds[1], true)
	Key(frame, "DOWN"); Equal(session.keyboardRowId, "chain:fixture:quest:1")
	for id = 2, 30 do Key(frame, "DOWN"); Equal(session.keyboardRowId, "chain:fixture:quest:" .. id) end
	assert(session.scrollPixels > 0)
	assert(Row(frame, session.keyboardRowId):IsVisible())
	Key(frame, "DOWN"); Equal(session.keyboardRowId, "chain:fixture:more:later")
	Key(frame, "ENTER"); Equal(a.expandedDirection, "later")
	Key(frame, "ESCAPE")
	Equal(a.chainFixtureOpen, false); Equal(session.keyboardRowId, "quest:1")
	Equal(frame:IsShown(), true); Equal(session.expandedQuestIds[1], true)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI step actions use spoiler-safe cached text and per-member prerequisite tooltips", function()
	local a, frame, session = Open()
	local target = "chain:fixture:quest:1"
	a:SelectPartyQuestKeyboardRow(frame, { rowId = target, questId = 1 })
	a:ScrollPartyQuestCompareToRow(frame, target)
	local row = assert(Row(frame, target))
	Equal(row.branch:IsShown(), true)
	Equal(row.cells[1]:GetText(), QT.Translate("In progress"))
	row.cellTooltips[2]:RunScript("OnEnter")
	Equal(a.tooltip[1], "[?] Known quest")
	assert(a.tooltip[2]:find("|cffffd100" .. session.members[2].name .. "|r\nNot in log\n\n", 1, true))
	assert(a.tooltip[2]:find("Prerequisites unknown", 1, true))
	assert(not a.tooltip[2]:find("Known prerequisites met", 1, true))
	local labels, callbacks = {}, {}
	function a:CreatePartyQuestFilterMenu(_, generate)
		generate(nil, { CreateTitle = function(_, label) labels[#labels + 1] = label end,
			CreateButton = function(_, label, callback) labels[#labels + 1] = label; callbacks[#callbacks + 1] = callback end })
		return true
	end
	Key(frame, "ENTER")
	Equal(labels[1], "[?] Known quest"); Equal(labels[2], "Find quest giver")
	callbacks[1](); Equal(a.actedOn, target)
	a.actedOn = nil; a.chainFixtureInstance = "chain:replacement"; a:RenderPartyQuestCompare()
	callbacks[1](); Equal(a.actedOn, nil)
	Equal(session.expandedQuestIds[1], nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI preserves independent objective geometry and uses no provider reads while scrolling", function()
	local a, frame, session = Open()
	function a:GetQuestChainGraph() error("layout queried provider") end
	function a:GetQuestChainQuestInfo() error("hover queried provider") end
	function a:GetQuestChainStarterLocations() error("scroll queried provider") end
	a:RenderPartyQuestCompare()
	local selected = a:GetPartyQuestKeyboardTarget(frame.navigationRows, "chain:fixture:quest:1")
	assert(selected and selected.data.kind == "chainStep")
	a:ScrollPartyQuestCompareToRow(frame, "chain:fixture:quest:30")
	Row(frame, "chain:fixture:quest:30"):RunScript("OnEnter")
	Equal(a.tooltip[1], "[?] Quest name hidden")
	Equal(#frame.navigationRows, 34) -- Notices remain readable but do not trap direction navigation.
	a:SelectPartyQuestKeyboardRow(frame, { rowId = "quest:1", questId = 1 }, "chain")
	a:ScrollPartyQuestCompareToRow(frame, "quest:1")
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(a.chainFixtureOpen, false); Equal(frame:IsShown(), true)
	Equal(#frame.navigationRows, 3)
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(a.chainFixtureOpen, true); Equal(#frame.navigationRows, 34)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("quest hover tooltips distinguish same names and recycled chain steps without revealing titles", function()
	local a, frame = Open()
	function a:GetQuestChainQuestInfo() error("tooltips must not query provider names") end
	function a:GetLocalizedQuestTitle() error("tooltips must preserve the row's spoiler policy") end
	local function Check(control, id, title)
		control:RunScript("OnEnter")
		assert(a.tooltip and a.tooltip[2]:find(QT.Translate("Quest ID") .. ": " .. id .. "|r", 1, true))
		if title then Equal(a.tooltip[1], title) end
		control:RunScript("OnLeave")
		Equal(a.tooltip, nil)
	end
	local root = assert(Row(frame, "quest:1"))
	Check(root, 1, "[?] Known quest")
	Check(root.chain, 1, QT.Translate("Close chain"))
	Check(root.journal, 1, QT.Translate("Open in Quest Log"))
	Check(root.focusCells[1], 1)
	local first = assert(Row(frame, "chain:fixture:quest:1"))
	Check(first, 1, "[?] Known quest")
	Check(first.cellTooltips[2], 1, "[?] Known quest")
	Check(first.focusCells[1], 1)
	local second = assert(Row(frame, "chain:fixture:quest:2"))
	second.data.title = "Known quest"
	Check(second, 2, "[?] Known quest")
	Check(second.cellTooltips[2], 2, "[?] Known quest")
	a:ScrollPartyQuestCompareToRow(frame, "chain:fixture:quest:30")
	local last = assert(Row(frame, "chain:fixture:quest:30"))
	Check(last, 30, "[?] Quest name hidden")
	Check(last.cellTooltips[1], 30, "[?] Quest name hidden")
	a:ScrollPartyQuestCompareToRow(frame, "quest:1")
	Check(assert(Row(frame, "quest:1")), 1, "[?] Known quest")
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("quest hover tooltips retire child owners before pooled rows represent another quest", function()
	local a, frame = Open()
	for _, role in ipairs({ "title", "chain", "journal", "focus", "status" }) do
		local rowID = role == "status" and "chain:fixture:quest:1" or "quest:1"
		a:ScrollPartyQuestCompareToRow(frame, rowID)
		local row = assert(Row(frame, rowID))
		local control = role == "title" and row or role == "focus" and row.focusCells[1]
			or role == "status" and row.cellTooltips[2] or row[role]
		control:RunScript("OnEnter")
		Equal(a.tooltipOwner, control)
		assert(a.tooltip[2]:find("Quest ID: 1|r", 1, true))
		a:ScrollPartyQuestCompareToRow(frame, "chain:fixture:quest:30")
		Equal(a.tooltip, nil)
		Equal(a.tooltipOwner, nil)
	end
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI shows cached quest levels and difficulty colors while future titles stay muted", function()
	local a, frame = Open()
	local build = a.BuildPartyQuestCompareDisplayRows
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows = build(self, roots)
		for _, data in ipairs(rows) do
			if data.questId then
				data.questLevel = 20 + data.questId
				data.questGroupRecommended = data.questId == 1
				data.questDifficultyColor = { r = 1, g = 0.5, b = 0.25 }
			end
		end
		return rows
	end
	for _, light in ipairs({ false, true }) do
		a.options.lightMode = light
		a:RenderPartyQuestCompare()
		local root, future = assert(Row(frame, "quest:1")), assert(Row(frame, "chain:fixture:quest:2"))
		Equal(root.title:GetText(), "[21+] Known quest")
		root:RunScript("OnEnter"); Equal(a.tooltip[1], "[21+] Known quest")
		Equal(root.title.textColor[1], light and 0.5 or 1); Equal(root.title.textColor[2], light and 0.25 or 0.5)
		Equal(future.title:GetText(), "[22] Quest name hidden")
		Equal(future.title.textColor[1], light and 0.42 or 0.64)
		Equal(future.title.textColor[1], future.title.textColor[2])
		future:RunScript("OnEnter")
		Equal(a.tooltip[1], "[22] Quest name hidden")
		future.cellTooltips[2]:RunScript("OnEnter")
		Equal(a.tooltip[1], "[22] Quest name hidden")
		assert(a.tooltip[2]:find(future.cellTooltips[2].memberName, 1, true))
		a:ScrollPartyQuestCompareToRow(frame, "chain:fixture:quest:30")
		a:ScrollPartyQuestCompareToRow(frame, "quest:1")
		root = assert(Row(frame, "quest:1"))
		Equal(root.title.textColor[1], light and 0.5 or 1); Equal(root.title.textColor[2], light and 0.25 or 0.5)
	end
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI owned and completed member tooltips do not inherit another players prerequisites", function()
	local a, frame = Open()
	local build = a.BuildPartyQuestCompareDisplayRows
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows = build(self, roots)
		for _, row in ipairs(rows) do
			if row.kind == "chainStep" and row.questId == 1 then
				row.cells, row.hint = { "Absent", self.testOwnedStatus }, nil
				row.memberPrerequisiteText = { "Prerequisites not met", "" }
				row.prerequisiteText = "Prerequisites not met"
			end
		end
		return rows
	end
	for _, status in ipairs({ "Have", "Ready", "Completed" }) do
		a.testOwnedStatus = status; a:RenderPartyQuestCompare()
		local row = assert(Row(frame, "chain:fixture:quest:1"))
		row.cellTooltips[2]:RunScript("OnEnter")
		Equal(a.tooltip[1], row.cellTooltips[2].memberName)
		Equal(row.cellTooltips[2].prerequisiteText, nil)
		assert(a.tooltip[2]:find(status == "Have" and "In progress" or status, 1, true))
		assert(a.tooltip[2]:find("Quest ID: 1", 1, true)); assert(not a.tooltip[2]:find("Prerequisites", 1, true))
		row.cellTooltips[1]:RunScript("OnEnter")
		Equal(a.tooltip[1], "[?] Known quest")
		assert(a.tooltip[2]:find("Prerequisites not met", 1, true))
		row:RunScript("OnEnter"); assert(not a.tooltip[2]:find("Prerequisites", 1, true))
	end
end)

QT:RegisterTest("chain UI share readiness keeps one summary before prerequisite sections", function()
	local a, frame, session = Open(false)
	local friend = session.members[2]
	local recipient = { name = friend.name }
	local readiness = { action = "share", recipients = { recipient }, byName = { [friend.name] = recipient } }
	function a:GetPartyQuestShareReadiness() return readiness end
	for _, example in ipairs({
		{ state = "blocked", result = "blocked", label = "Prerequisites not met" },
		{ state = "unknown", result = "unknown", label = "Eligibility unknown", omitted = "Prerequisites unknown" },
		{ state = "missing", result = "met", label = "No known blockers", omitted = "Known prerequisites met" },
		{ state = "checking", result = "unknown", label = "Checking eligibility", omitted = "Prerequisites unknown" },
	}) do
		recipient.state, recipient.requirementState = example.state, example.result
		recipient.requirements = { state = example.result, requirements = {} }
		a:RenderPartyQuestCompare()
		local control = assert(Row(frame, "quest:1")).cellTooltips[2]
		control:RunScript("OnEnter")
		Equal(a.tooltip[1], "[?] Known quest")
		local text = a.tooltip[2]
		local start = assert(text:find(example.label, 1, true))
		assert(not text:find(example.label, start + #example.label, true))
		if example.omitted then assert(not text:find(example.omitted, 1, true)) end
		assert(text:find(example.label .. "\n\n", 1, true))
		assert(text:find("Other availability conditions may apply.", 1, true))
	end
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI unavailable cells retain reasons in compact columns and clear recycled state", function()
	local a, frame, session = Open()
	local build = a.BuildPartyQuestCompareDisplayRows
	a.testUnavailable = true
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows = build(self, roots)
		for _, data in ipairs(rows) do
			if data.kind == "chainStep" and data.questId == 1 then
				data.cells[2] = self.testUnavailable and "Unavailable" or "Absent"
				data.memberPrerequisiteText[2] = self.testUnavailable
					and "No longer obtainable\n\nCannot be met\n  Level exceeds the maximum of 19." or "Prerequisites unknown"
			end
		end
		return rows
	end
	local target, member = "chain:fixture:quest:1", session.members[2].name
	local pooledCount, control = #frame.rows, Row(frame, target).cellTooltips[2]
	for _, light in ipairs({ false, true }) do
		a.options.lightMode = light
		for _, collapsed in ipairs({ false, true }) do
			a:SetPartyQuestColumnCollapsed(member, collapsed, session)
			a:RenderPartyQuestCompare()
			local row = assert(Row(frame, target))
			Equal(row.cellTooltips[2], control)
			Equal(row.cells[2]:GetText(), collapsed and "x" or QT.Translate("Unavailable"))
			Equal(row.cells[2].textColor[1], light and 0.54 or 0.91)
			Equal(row.cells[2].textColor[2], light and 0.18 or 0.49)
			Equal(row.focusCells[2]:IsShown(), false)
			control:RunScript("OnEnter")
			Equal(a.tooltip[1], "[?] Known quest")
			assert(a.tooltip[2]:find("Unavailable\n\nNo longer obtainable", 1, true))
			assert(a.tooltip[2]:find("Level exceeds the maximum of 19.", 1, true))
		end
	end
	a.testUnavailable = false
	a:RenderPartyQuestCompare()
	local row = assert(Row(frame, target))
	Equal(row.cellTooltips[2], control); Equal(row.cells[2]:GetText(), "?")
	control:RunScript("OnEnter")
	assert(a.tooltip[2]:find("Not in log\n\nPrerequisites unknown", 1, true))
	assert(not a.tooltip[2]:find("Unavailable", 1, true)); assert(not a.tooltip[2]:find("maximum", 1, true))
	a:ScrollPartyQuestCompareToRow(frame, "chain:fixture:quest:30")
	Equal(a.tooltip, nil)
	a:ScrollPartyQuestCompareToRow(frame, target)
	row = assert(Row(frame, target))
	row.cellTooltips[2]:RunScript("OnEnter")
	assert(a.tooltip[2]:find("Not in log\n\nPrerequisites unknown", 1, true))
	assert(not a.tooltip[2]:find("Unavailable", 1, true))
	Equal(#frame.rows, pooledCount); Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI permanent share blockers show one unavailable label and the exact reason", function()
	local a, frame, session = Open(false)
	local friend = session.members[2]
	local requirement = { kind = "max_level", state = "blocked", value = 19, permanent = true }
	local result = { state = "blocked", permanentlyBlocked = true, requirements = { requirement } }
	local recipient = { name = friend.name, state = "blocked", requirementState = "blocked", requirements = result }
	local readiness = { action = "share", disabled = true, state = "blocked", recipients = { recipient }, byName = { [friend.name] = recipient } }
	function a:GetPartyQuestShareReadiness() return readiness end
	local build = a.BuildPartyQuestCompareDisplayRows
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows = build(self, roots)
		for _, data in ipairs(rows) do
			if data.rowId == "quest:1" then data.cells[2] = result.permanentlyBlocked and "Unavailable" or "Missing" end
		end
		return rows
	end
	a:RenderPartyQuestCompare()
	local row = assert(Row(frame, "quest:1"))
	Equal(row.hint:GetText(), QT.Translate("Unavailable"))
	row.cellTooltips[2]:RunScript("OnEnter")
	local text = a.tooltip[2]
	local first = assert(text:find("Unavailable", 1, true))
	assert(not text:find("Unavailable", first + #"Unavailable", true))
	assert(text:find("Cannot be met", 1, true)); assert(text:find("Level exceeds the maximum of 19.", 1, true))
	result.permanentlyBlocked, requirement.permanent = nil, nil
	a:RenderPartyQuestCompare()
	row = assert(Row(frame, "quest:1"))
	Equal(row.hint:GetText(), "Maximum level: 19")
	row.cellTooltips[2]:RunScript("OnEnter")
	assert(a.tooltip[2]:find("Maximum level: 19", 1, true)); assert(not a.tooltip[2]:find("Unavailable", 1, true))
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI toggle labels follow expansion and stale menu actions cannot reverse later choices", function()
	local a, frame = Open(false)
	Equal(Row(frame, "quest:1").chainIcon.texture, "Interface\\AddOns\\QuestTogether\\Media\\QuestChain.tga")
	local function Menu()
		local row, actions = assert(Row(frame, "quest:1")), {}
		a:PopulatePartyQuestContextMenu(frame, { rowId = row.data.rowId, questId = 1, data = row.data }, {
			CreateTitle = function() end,
			CreateButton = function(_, label, callback) actions[label] = callback end,
		})
		return actions
	end
	Row(frame, "quest:1").chain:RunScript("OnEnter")
	Equal(a.tooltip[1], QT.Translate("View chain"))
	local closedMenu = Menu()
	assert(closedMenu[QT.Translate("View chain")]); Equal(closedMenu[QT.Translate("Close chain")], nil)
	closedMenu[QT.Translate("View chain")]()
	Equal(a.chainFixtureOpen, true); Equal(a.chainToggles, 1)
	closedMenu[QT.Translate("View chain")]()
	Equal(a.chainFixtureOpen, true); Equal(a.chainToggles, 1)
	Row(frame, "quest:1").chain:RunScript("OnEnter")
	Equal(a.tooltip[1], QT.Translate("Close chain"))
	local openMenu = Menu()
	assert(openMenu[QT.Translate("Close chain")]); Equal(openMenu[QT.Translate("View chain")], nil)
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(a.chainFixtureOpen, false); Equal(a.chainToggles, 2)
	openMenu[QT.Translate("Close chain")]()
	Equal(a.chainFixtureOpen, false); Equal(a.chainToggles, 2)
	Menu()[QT.Translate("View chain")]()
	Equal(a.chainFixtureOpen, true); Equal(a.chainToggles, 3)
	local previousInstanceMenu = Menu()
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Row(frame, "quest:1").chain:RunScript("OnClick", "LeftButton")
	Equal(a.chainFixtureOpen, true); Equal(a.chainToggles, 5)
	previousInstanceMenu[QT.Translate("Close chain")]()
	Equal(a.chainFixtureOpen, true); Equal(a.chainToggles, 5)
	Menu()[QT.Translate("Close chain")]()
	Equal(a.chainFixtureOpen, false); Equal(a.chainToggles, 6)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI hides unsupported chain affordances without changing ordinary quest actions", function()
	local a, frame = Open()
	a.chainFixtureOpen, a.chainFixtureAvailable = false, false
	a:RenderPartyQuestCompare()
	local row = assert(Row(frame, "quest:1"))
	Equal(row.chain:IsShown(), false); Equal(row.journal:IsShown(), true)
	local labels = {}
	a:PopulatePartyQuestContextMenu(frame, { rowId = row.data.rowId, questId = 1, data = row.data }, {
		CreateTitle = function() end,
		CreateButton = function(_, label) labels[label] = true end,
	})
	Equal(labels[QT.Translate("View chain")], nil)
	Equal(labels[QT.Translate("Expand or collapse quest")], true)
	Equal(labels[QT.Translate("Open in Quest Log")], true)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI objective closing animation retains the duplicate chain step", function()
	local a, frame, session = Open()
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows = { roots[1] }
		if session.expandedQuestIds[1] then
			rows[#rows + 1] = { kind = "objective", rowId = "quest:1:objective:1", questId = 1,
				title = "Known objective", cells = {} }
		end
		rows[#rows + 1] = { kind = "chainStep", rowId = "chain:animation:quest:1", questId = 1,
			title = "Known quest", cells = { "Have", "Absent" }, selectable = true, chainInstanceId = "chain:animation" }
		rows[#rows + 1] = roots[2]
		return rows
	end
	a:RenderPartyQuestCompare()
	a.options.reduceMotion = false
	local function Finish()
		for _ = 1, 3 do frame.expansionAnimator:RunScript("OnUpdate", 0.1) end
	end
	Row(frame, "quest:1"):RunScript("OnMouseUp", "LeftButton"); a:RenderPartyQuestCompare(); Finish()
	assert(Row(frame, "quest:1:objective:1"))
	Row(frame, "quest:1"):RunScript("OnMouseUp", "LeftButton"); a:RenderPartyQuestCompare(); Finish()
	Equal(session.expandedQuestIds[1], nil)
	assert(Row(frame, "chain:animation:quest:1"))
	Equal(#frame.navigationRows, 3)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain UI Escape after a menu returns to the chain origin before closing the log", function()
	local a, frame, session = Open()
	a:SelectPartyQuestKeyboardRow(frame, { rowId = "chain:fixture:quest:1", questId = 1 })
	a:SetPartyQuestKeyboardNavigation(frame, false)
	a.keyboardBlocked = true -- The open menu retains Escape; its owner must not also close.
	frame:RunScript("OnKeyDown", "ESCAPE")
	Equal(a.chainFixtureOpen, true); Equal(frame:IsShown(), true)
	a.keyboardBlocked = false
	frame:RunScript("OnKeyDown", "ESCAPE")
	Equal(a.chainFixtureOpen, false); Equal(frame:IsShown(), true)
	Equal(session.keyboardRowId, "quest:1")
	frame:RunScript("OnKeyDown", "ESCAPE")
	Equal(frame:IsShown(), false)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain loading rings explain discovery without becoming keyboard or mouse actions", function()
	local a, frame, session = Open()
	local build = a.BuildPartyQuestCompareDisplayRows
	a.fixtureChainLoading = true
	a.options.reduceMotion = false
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows = build(self, roots)
		for _, data in ipairs(rows) do
			if data.rowId == "quest:2" then
				data.chainLoading = self.fixtureChainLoading
				data.chainAvailable = self.fixtureChainAvailable == true
				data.chainExpanded = self.fixtureChainExpanded == true
			end
		end
		return rows
	end
	a:RenderPartyQuestCompare(); a:ScrollPartyQuestCompareToRow(frame, "quest:2")
	local row = assert(Row(frame, "quest:2"))
	local button, dots = row.chain, row.chainDots
	Equal(button:IsShown(), true); Equal(button:IsEnabled(), false); Equal(button.motionScriptsWhileDisabled, true)
	Equal(row.chainIcon:IsShown(), false); Equal(#dots, 8)
	for _, dot in ipairs(dots) do assert(dot:IsShown()) end
	button:RunScript("OnEnter"); Equal(a.tooltip[1], QT.Translate("Loading quest chain information"))
	button:RunScript("OnClick", "LeftButton"); Equal(a.chainToggles, nil)
	for _, control in ipairs(a:GetPartyQuestRowControls(frame, row.data)) do assert(control.button ~= button) end
	assert(button:GetScript("OnUpdate"))
	button:RunScript("OnUpdate", 0.09); Equal(button.loadingStep, 1)
	a.options.reduceMotion = true; a:RenderPartyQuestCompare()
	Equal(button:GetScript("OnUpdate"), nil); assert(dots[1]:IsShown())
	a.options.reduceMotion = false; a:RenderPartyQuestCompare()
	assert(button:GetScript("OnUpdate"))
	-- A known open section keeps its close action even while discovery continues.
	a.fixtureChainAvailable, a.fixtureChainExpanded = true, true
	a:RenderPartyQuestCompare()
	Equal(button.loading, nil); Equal(button:GetScript("OnUpdate"), nil)
	Equal(row.chainIcon:IsShown(), true); Equal(button:IsEnabled(), true)
	for _, dot in ipairs(dots) do Equal(dot:IsShown(), false) end
	button:RunScript("OnEnter"); Equal(a.tooltip[1], QT.Translate("Close chain"))
	a.fixtureChainAvailable, a.fixtureChainExpanded = false, false
	a:RenderPartyQuestCompare(); assert(button:GetScript("OnUpdate"))
	-- Scrolling reuses this pool; a retired spinner must not keep running there.
	a:ScrollPartyQuestCompareToRow(frame, "quest:1")
	Equal(button:GetScript("OnUpdate"), nil); Equal(button.loading, nil)
	for _, dot in ipairs(dots) do Equal(dot:IsShown(), false) end
	a:ScrollPartyQuestCompareToRow(frame, "quest:2")
	row = assert(Row(frame, "quest:2")); button = row.chain
	assert(button:GetScript("OnUpdate"))
	a.fixtureChainLoading = false; a:RenderPartyQuestCompare()
	Equal(button:IsShown(), false); Equal(button:GetScript("OnUpdate"), nil)
	a.fixtureChainLoading = true; a:RenderPartyQuestCompare()
	assert(button:GetScript("OnUpdate"))
	frame:Hide()
	Equal(button:GetScript("OnUpdate"), nil); Equal(button.loading, nil)
	for _, dot in ipairs(row.chainDots) do Equal(dot:IsShown(), false) end
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("chain loading rings stop on retirement and rebind when their session state changes", function()
	for _, change in ipairs({ "retired", "profile", "disabled", "logout", "session", "replacement" }) do
		local a, frame, session = Open(false)
		a.options.reduceMotion = false
		local build = a.BuildPartyQuestCompareDisplayRows
		function a:BuildPartyQuestCompareDisplayRows(roots)
			local rows = build(self, roots)
			for _, data in ipairs(rows) do
				if data.rowId == "quest:1" then data.chainAvailable, data.chainLoading = false, true end
			end
			return rows
		end
		a:RenderPartyQuestCompare()
		local row = assert(Row(frame, "quest:1"))
		local button = row.chain
		local stale = assert(button:GetScript("OnUpdate"))
		button:RunScript("OnUpdate", 0.09); Equal(button.loadingStep, 1)
		if change == "retired" then a:RetirePartyQuestChains()
		elseif change == "profile" then a.db = { profile = {} }
		elseif change == "disabled" then a.isEnabled = false
		elseif change == "logout" then a.isLoggingOut = true
		elseif change == "session" then a.partyQuestCompareSession = {}
		else
			local replacement = {}; for key, value in pairs(session.chains) do replacement[key] = value end
			session.chains = replacement
			a:RenderPartyQuestCompare()
			local current = assert(button:GetScript("OnUpdate"))
			assert(current ~= stale)
			stale(button, 0.09)
			Equal(button:GetScript("OnUpdate"), current); Equal(button.loadingStep, 0)
			button:RunScript("OnUpdate", 0.09); Equal(button.loadingStep, 1)
			a:RetirePartyQuestChains()
		end
		button:RunScript("OnUpdate", 0.09)
		Equal(button:GetScript("OnUpdate"), nil); Equal(button.loading, nil); Equal(button.loadingStep, nil)
		for _, dot in ipairs(row.chainDots) do Equal(dot:IsShown(), false) end
		Equal(a.invalidCalls, nil)
	end
end)

_G.QuestTogether:RecordTestModule("scripts/regression_compare_chains_ui.lua")
