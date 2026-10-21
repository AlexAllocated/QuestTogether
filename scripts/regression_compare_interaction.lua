-- Private fixture UI only: these checks are also safe in a running client.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end
local function Open(count)
	local entries = {}
	for id = 1, count or 24 do
		entries[id] = { questId = id, questTitle = string.format("Quest %02d", id), isPushable = true }
	end
	local addon = QT:CreateTestPartyQuestCompareFixture(entries)
	addon.options.reduceMotion = true
	function addon:ShowSettingsTooltip(_, title, text) self.tooltip = { title, text } end
	function addon:HideSettingsTooltip() self.tooltip = nil end
	addon:OpenPartyQuestCompare()
	addon:RenderPartyQuestCompare()
	addon.partyQuestCompareWindow.keyboardInput:RunScript("OnUpdate", 0.016)
	return addon, addon.partyQuestCompareWindow, addon.partyQuestCompareSession
end
local function Key(frame, key)
	local input = frame.keyboardInput:IsVisible() and frame.keyboardInput or frame
	input:RunScript("OnKeyDown", key)
	local propagated = input.propagate
	input:RunScript("OnKeyUp", key)
	return propagated
end

QT:RegisterTest("party log opens with list focus and only captures navigation keys", function()
	local a, frame, session = Open()
	Equal(frame.keyboardButton, nil)
	Equal(frame.keyboardSession, session)
	Equal(session.keyboardQuestId, 1)
	Equal(Key(frame, "DOWN"), false)
	Equal(session.keyboardQuestId, 2)
	Equal(frame.propagate, true)
	Equal(Key(frame, "END"), false)
	Equal(session.keyboardQuestId, 24)
	assert(session.scrollPixels > 0)
	Equal(frame.rows[1].clip.points[1][1], "TOPLEFT")
	Equal(Key(frame, "HOME"), false)
	Equal(session.keyboardQuestId, 1)
	Equal(session.scrollPixels, 0)
	Key(frame, "PAGEDOWN")
	assert(session.keyboardQuestId > 2 and session.keyboardQuestId < 24)
	Key(frame, "PAGEUP")
	Equal(session.keyboardQuestId, 1)
	Equal(Key(frame, "W"), true)
	Equal(frame.keyboardSession, nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log keyboard capture retires when restrictions begin before key release", function()
	local a, frame = Open()
	frame.keyboardInput:RunScript("OnKeyDown", "DOWN")
	Equal(frame.keyboardInput.propagate, false)
	a.blocked = true
	frame.keyboardInput:RunScript("OnKeyUp", "DOWN")
	Equal(frame.keyboardSession, nil)
	Equal(frame.keyboardInput:IsShown(), false)
	Equal(frame.propagate, true)
	Equal(a.invalidCalls, nil)
	a.blocked = false
	frame.rows[1]:RunScript("OnMouseUp", "LeftButton")
	Equal(frame.keyboardInput.propagate, true)
	frame.keyboardInput:RunScript("OnKeyDown", "UP")
	a.blocked = true
	frame:RunScript("OnEvent", "PLAYER_REGEN_DISABLED")
	Equal(frame.keyboardInput:IsShown(), false)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log keyboard focus releases for edit focus menus outside clicks and hide", function()
	local a, frame, session = Open()
	frame.search:SetFocus()
	Equal(frame.keyboardSession, nil)
	Equal(Key(frame, "DOWN"), true)
	frame.search:RunScript("OnEnterPressed")
	Equal(frame.search:HasFocus(), false)
	Equal(frame.keyboardSession, session)
	a.keyboardBlocked = true
	Equal(Key(frame, "DOWN"), true)
	Equal(frame.keyboardSession, nil)
	a.keyboardBlocked = false
	frame.rows[1]:RunScript("OnMouseUp", "LeftButton")
	a.mouseOverWindow = true
	frame:RunScript("OnEvent", "GLOBAL_MOUSE_DOWN")
	Equal(frame.keyboardSession, session)
	a.mouseOverWindow = false
	frame:RunScript("OnEvent", "GLOBAL_MOUSE_DOWN")
	Equal(frame.keyboardSession, nil)
	a:RenderPartyQuestCompare()
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	Equal(frame.keyboardSession, nil) -- incoming data must not reclaim focus
	frame.rows[1]:RunScript("OnMouseUp", "LeftButton")
	Equal(frame.keyboardSession, session)
	frame:Hide()
	Equal(frame.keyboardSession, nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log Escape dismisses focused list and retired callbacks cannot navigate", function()
	local a, frame, session = Open()
	Equal(Key(frame, "ESCAPE"), false)
	Equal(frame.keyboardSession, nil)
	Equal(frame:IsShown(), false)
	Equal(a.partyQuestCompareSession, nil)
	Key(frame, "DOWN")
	Equal(session.keyboardQuestId, 1)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log keyboard expansion and paging use current animated root geometry", function()
	local a, frame, session = Open()
	Key(frame, "RIGHT")
	Equal(session.expandedQuestIds[1], true)
	a:RenderPartyQuestCompare()
	Equal(frame.navigationRows[1].questId, 1)
	assert(frame.navigationRows[2].top > 42)
	Key(frame, "DOWN")
	Equal(session.keyboardQuestId, 2)
	Key(frame, "UP")
	Key(frame, "LEFT")
	Equal(session.expandedQuestIds[1], nil)
	a:RenderPartyQuestCompare()
	Equal(frame.navigationRows[2].top, 42)
	Key(frame, "ENTER")
	Equal(session.expandedQuestIds[1], true)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log keyboard actions recheck window session and restriction ownership", function()
	local a, frame, session = Open()
	local actions = {}
	function a:CreatePartyQuestFilterMenu(anchor, generate)
		Equal(anchor.data.questId, session.keyboardQuestId)
		generate(nil, {
			CreateTitle = function() end,
			CreateButton = function(_, label, callback) actions[#actions + 1] = callback end,
		})
		return true
	end
	Equal(Key(frame, "SPACE"), false)
	Equal(frame.keyboardSession, nil)
	Equal(frame.keyboardInput:IsShown(), false)
	assert(#actions > 0)
	frame.search:SetFocus()
	frame.search:RunScript("OnTabPressed")
	Equal(Key(frame, "MENU"), false)
	Equal(frame.keyboardSession, nil)
	a.blocked = true
	actions[1]()
	Equal(session.expandedQuestIds[1], nil)
	Key(frame, "DOWN")
	Equal(a.invalidCalls, nil)
	a.blocked = false
	frame:Hide()
	actions[1]()
	Equal(session.expandedQuestIds[1], nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log opening focus cannot survive outside clicks or a replaced session", function()
	local a, frame, session = Open()
	Equal(Key(frame, "TAB"), false)
	Equal(frame.search:HasFocus(), true)
	Equal(frame.keyboardSession, nil)
	frame.search:RunScript("OnTabPressed")
	Equal(frame.keyboardSession, session)
	frame.search:SetFocus()
	frame.rows[2]:RunScript("OnMouseUp", "LeftButton")
	Equal(frame.search:HasFocus(), false)
	Equal(session.keyboardQuestId, 2)
	Equal(frame.keyboardSession, session)
	a:RequestPartyQuestKeyboardFocus(frame)
	a.mouseOverWindow = false
	frame:RunScript("OnEvent", "GLOBAL_MOUSE_DOWN")
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	Equal(frame.keyboardSession, nil)
	Equal(frame.keyboardFocusPending, nil)
	a:RequestPartyQuestKeyboardFocus(frame)
	a.partyQuestCompareSession = {}
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	Equal(frame.keyboardSession, nil)
	Equal(frame.keyboardInput:IsShown(), false)
	a.partyQuestCompareSession = session
	a:RequestPartyQuestKeyboardFocus(frame)
	frame.search:SetFocus()
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	Equal(frame.keyboardSession, nil)
	Equal(frame.search:HasFocus(), true)
	frame.search:ClearFocus()
	a.QueuePartyQuestCompareRender = QT.QueuePartyQuestCompareRender
	a:OpenPartyQuestCompare()
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	Equal(frame.keyboardSession, nil) -- wait for the new session's first render
	a:RenderPartyQuestCompare()
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	Equal(frame.keyboardSession, a.partyQuestCompareSession)
	assert(frame.keyboardSession ~= session)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("collapsed party columns retain roster comparison data and restore their width", function()
	local a, frame, session = Open(3)
	local member = session.members[2]
	local entries, count, before = member.entries, #session.members, a:BuildPartyQuestDiffRows()
	local wide, columnWidth = frame.memberColumnsWidth, frame.columns[2].width
	frame.horizontalOffset = 9999
	frame.columnToggles[2]:Click()
	Equal(session.collapsedPlayers[member.name], true)
	a:RenderPartyQuestCompare()
	assert(frame.memberColumnsWidth < wide)
	assert(frame.columns[2].width < columnWidth)
	Equal(frame.headerAccents[2]:GetWidth(), frame.columns[2].width)
	Equal(frame.rows[1].cellShades[2]:GetWidth(), frame.columns[2].width)
	Equal(frame.rows[1].cellTooltips[2]:IsShown(), true)
	frame.rows[1].cellTooltips[2]:RunScript("OnEnter")
	Equal(a.tooltip[1], member.name)
	assert(a.tooltip[2] ~= "")
	Equal(#session.members, count)
	Equal(member.entries, entries)
	Equal(a:BuildPartyQuestDiffRows()[1].partySummary, before[1].partySummary)
	Equal(a:BuildPartyQuestDiffRows()[1].cells[2], before[1].cells[2])
	assert(frame.horizontalOffset <= frame.horizontal.qtScrollMaximum)
	a:RestorePartyQuestColumns(session)
	a:RenderPartyQuestCompare()
	Equal(frame.memberColumnsWidth, wide)
	Equal(frame.columns[2].width, columnWidth)
	Equal(frame.rows[1].cellTooltips[2]:IsShown(), false)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("compact quest states use font-independent markers and retain full labels when recycled", function()
	local states = { "Have", "Ready", "Completed", "Missing", "Absent", "Loading", "Unknown" }
	local a, frame, session = Open(#states)
	local member, originalRows = session.members[2], a.BuildPartyQuestDiffRows
	local reverse = false
	function a:BuildPartyQuestDiffRows()
		local rows = originalRows(self)
		for index, row in ipairs(rows) do
			row.cells[2] = states[reverse and (#states + 1 - index) or index]
		end
		return rows
	end
	local markers = {}
	for pass = 1, 2 do
		reverse = pass == 2
		a:SetPartyQuestColumnCollapsed(member.name, true, session)
		a:RenderPartyQuestCompare()
		Equal(frame.columnToggles[2]:GetText(), "+")
		for index = 1, #states do
			local state = states[reverse and (#states + 1 - index) or index]
			local row = frame.rows[index]
			local marker = row.cells[2]:GetText()
			assert(marker ~= "" and not marker:find("[\128-\255]"), "compact state depends on a font glyph: " .. state)
			if state == "Ready" or state == "Completed" then
				assert(marker:match("^|TInterface\\[^|]+:16:16|t$"), "completion state needs native icon markup")
				assert(row.cells[2]:GetWidth() >= 16)
			end
			if pass == 1 then markers[state] = marker else Equal(marker, markers[state]) end
			Equal(row.focusCells[2]:IsShown(), state == "Have" or state == "Ready")
			row.cellTooltips[2]:RunScript("OnEnter")
			Equal(a.tooltip[1], member.name)
			Equal(a.tooltip[2], QT.Translate(state == "Absent" and "Not in log" or state))
		end
		assert(markers.Ready ~= markers.Completed and markers.Completed ~= markers.Missing)
		a:SetPartyQuestColumnCollapsed(member.name, false, session)
		a:RenderPartyQuestCompare()
		Equal(frame.columnToggles[2]:GetText(), "-")
		for index = 1, #states do
			local state = states[reverse and (#states + 1 - index) or index]
			Equal(frame.rows[index].cells[2]:GetText(), QT.Translate(state == "Absent" and "Not in log" or state))
			Equal(frame.rows[index].cellTooltips[2]:IsShown(), false)
		end
	end
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("column choices follow player identities across roster reordering and drop departed players", function()
	local a, frame, session = Open(2)
	local name = session.members[2].name
	a:SetPartyQuestColumnCollapsed(name, true, session)
	session.members[1], session.members[2] = session.members[2], session.members[1]
	local columns = a:GetPartyQuestCompareColumns(session)
	Equal(columns[1].collapsed, true)
	Equal(columns[2].collapsed, false)
	table.remove(session.members, 1)
	a:GetPartyQuestCompareColumns(session)
	Equal(session.collapsedPlayers[name], nil)
	Equal(a:SetPartyQuestColumnCollapsed(name, true, session), false)
	Equal(a:SetPartyQuestColumnCollapsed(session.members[1].name, true, {}), false)
	a.blocked = true
	Equal(a:SetPartyQuestColumnCollapsed(session.members[1].name, true, session), false)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("compact party header menu actions expire with their captured session", function()
	local a, frame, session = Open(2)
	local actions = {}
	function a:CreatePartyQuestFilterMenu(_, generate)
		local menu = { CreateDivider = function() end, CreateTitle = function() end }
		function menu:CreateButton(_, callback) actions[#actions + 1] = callback end
		generate(nil, menu)
		return true
	end
	frame.focusButtons[1]:Click()
	Equal(#actions, 2)
	frame:Hide()
	actions[1]()
	Equal(session.collapsedPlayers[session.playerName], nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("compact columns retain small-screen bounds and keyboard selection follows filtered roots", function()
	local a, frame, session = Open(24)
	a:GetOwnedUIParent():SetSize(720, 540)
	for _, member in ipairs(session.members) do a:SetPartyQuestColumnCollapsed(member.name, true, session) end
	a:RenderPartyQuestCompare()
	assert(frame:GetWidth() * frame:GetScale() <= 720 * 0.94 + 0.01)
	assert(frame:GetHeight() * frame:GetScale() <= 540 * 0.94 + 0.01)
	Equal(frame.columns[2].left, frame.columns[1].left + frame.columns[1].width + 4)
	Key(frame, "END")
	Equal(session.keyboardQuestId, 24)
	a:SetPartyQuestCompareFilter("search", "Quest 01")
	a:RenderPartyQuestCompare()
	Equal(session.keyboardQuestId, 1)
	Equal(frame.navigationRows[1].questId, 1)
	a:OpenPartyQuestCompare()
	a:RenderPartyQuestCompare()
	assert(a.partyQuestCompareSession ~= session)
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	Equal(frame.keyboardSession, a.partyQuestCompareSession)
	Equal(frame.keyboardInput:IsShown(), true)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("remote column menus include personal notes and player share feedback stays off quest rows", function()
	local a, frame = Open(2)
	local noteTarget
	function a:PopulatePlayerNotesMenu(_, name) noteTarget = name end
	function a:PopulatePartyFocusMenu() end
	function a:GetLatestQuestShareResultText(name)
		return name == "Friend-Realm" and "Latest share result: Quest log full" or nil
	end
	function a:CreatePartyQuestFilterMenu(_, generate)
		generate(nil, { CreateTitle = function() end, CreateDivider = function() end, CreateButton = function() end })
		return true
	end
	frame.focusButtons[2]:RunScript("OnEnter")
	assert(a.tooltip[2]:find("Latest share result: Quest log full", 1, true))
	frame.focusButtons[2]:Click()
	Equal(noteTarget, "Friend-Realm")
	for _, row in ipairs(frame.rows) do
		assert(not row.hint:GetText():find("Latest share result:", 1, true))
	end
	Equal(a.invalidCalls, nil)
end)
