-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
-- Contract-level UI fixtures use prepared rows only: no provider or engine input.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
local function Open()
	local a = QT:CreateTestPartyQuestCompareFixture({
		[1] = { questId = 1, questTitle = "Known quest", isPushable = true },
		[2] = { questId = 2, questTitle = "Other quest", isPushable = true },
	})
	a.options.reduceMotion = true
	a.chainFixtureOpen, a.chainFixtureInstance, a.chainFixtureAvailable = true, "chain:fixture", true
	function a:ShowSettingsTooltip(_, title, text) self.tooltip = { title, text } end
	function a:HideSettingsTooltip() self.tooltip = nil end
	function a:BuildPartyQuestCompareDisplayRows(roots)
		local rows = { { rowId = "chainGroup:1", kind = "chainGroup", groupId = 1, title = "Related quests", cells = {}, selectable = true, expanded = true } }
		for _, row in ipairs(roots) do row.rowId = "quest:" .. row.questId; row.chainAvailable = self.chainFixtureAvailable end
		rows[#rows + 1] = roots[1]
		if self.chainFixtureOpen then
			rows[#rows + 1] = { rowId = self.chainFixtureInstance .. ":close", kind = "chainClose", title = "Close chain", cells = {}, selectable = true, chainInstanceId = self.chainFixtureInstance }
			rows[#rows + 1] = { rowId = self.chainFixtureInstance .. ":notice", kind = "chainNotice", title = "Partial quest chain information", cells = {}, chainInstanceId = self.chainFixtureInstance }
			for id = 1, 30 do
				rows[#rows + 1] = { rowId = self.chainFixtureInstance .. ":quest:" .. id, kind = "chainStep", questId = id,
					title = id == 1 and "Known quest" or "Future quest", cells = { id == 1 and "Have" or "Unknown", "Absent" },
					selectable = true, chainInstanceId = self.chainFixtureInstance, depth = id % 3,
					memberPrerequisiteText = { "Known prerequisites met", "Prerequisites unknown" } }
			end
			rows[#rows + 1] = { rowId = self.chainFixtureInstance .. ":more:later", kind = "chainMore", title = "Show later quests", cells = {}, selectable = true, direction = "later", chainInstanceId = self.chainFixtureInstance }
		end
		rows[#rows + 1] = roots[2]
		return rows
	end
	function a:OpenPartyQuestChain(id, origin) self.opened = { id, origin }; return true end
	function a:ClosePartyQuestChain() self.chainFixtureOpen = false; return true, "quest:1" end
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

QT:RegisterTest("chain UI keyboard traverses distinct quest instances and offscreen branch controls", function()
	local a, frame, session = Open()
	Equal(session.keyboardRowId, "chainGroup:1")
	Key(frame, "ENTER"); Equal(a.toggledGroup, 1)
	Key(frame, "DOWN"); Equal(session.keyboardRowId, "quest:1")
	Key(frame, "RIGHT"); Equal(session.keyboardRole, "chain")
	Key(frame, "ENTER"); Equal(a.opened[2], "quest:1")
	Key(frame, "LEFT"); Equal(session.keyboardRole, "quest")
	Key(frame, "ENTER"); Equal(session.expandedQuestIds[1], true)
	Key(frame, "DOWN"); Equal(session.keyboardRowId, "chain:fixture:close")
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
	assert(a.tooltip[2]:find("Prerequisites unknown", 1, true))
	assert(not a.tooltip[2]:find("Known prerequisites met", 1, true))
	local labels, callbacks = {}, {}
	function a:CreatePartyQuestFilterMenu(_, generate)
		generate(nil, { CreateTitle = function(_, label) labels[#labels + 1] = label end,
			CreateButton = function(_, label, callback) labels[#labels + 1] = label; callbacks[#callbacks + 1] = callback end })
		return true
	end
	Key(frame, "ENTER")
	Equal(labels[1], "Known quest"); Equal(labels[2], "Find quest giver")
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
	Equal(a.tooltip[1], "Future quest")
	Equal(#frame.navigationRows, 35) -- Notices remain readable but do not trap direction navigation.
	a:SelectPartyQuestKeyboardRow(frame, { rowId = "chain:fixture:close" })
	a:ScrollPartyQuestCompareToRow(frame, "chain:fixture:close")
	Row(frame, "chain:fixture:close"):RunScript("OnMouseUp", "LeftButton")
	Equal(a.chainFixtureOpen, false); Equal(frame:IsShown(), true)
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
	a.options.reduceMotion = false
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

_G.QuestTogether:RecordTestModule("scripts/regression_compare_chains_ui.lua")
