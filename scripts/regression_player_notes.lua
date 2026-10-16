-- Private SavedVariables and frame fixtures only; safe to run in a live client.
local QT = _G.QuestTogether
-- Forever's native line metrics are fractional even when GetFont returns 14.
local NATIVE_LINE_HEIGHT = 14 + 1 / 6
local function Fixture(global)
	local a = setmetatable(
		{ isEnabled = true, db = { global = global or {}, profile = {} }, region = "US", runtimeStateStore = {} },
		{ __index = QT }
	)
	a.API = {
		GetPlayerNotesNamespace = function()
			return a.region
		end,
		GetRealmName = function()
			return "Home Realm"
		end,
		RegionalUniqueNamesEnabled = function()
			return a.regional == true
		end,
		GetTime = function()
			return 100
		end,
	}
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	function a:IsWorkBlocked()
		return self.blocked == true
	end
	function a:GetOption(key)
		return key == "windowScale" and 100 or false
	end
	function a:Publish()
		error("private notes must never be published")
	end
	function a:Emit()
		error("private notes must never be announced")
	end
	function a:Request()
		error("private notes must never be requested")
	end
	function a:Respond()
		error("private notes must never be shared")
	end
	a.parent = QT:CreateTestUIRegion(a)
	a.parent:SetSize(1024, 768)
	a.noteEditors, a.notePendingRanges = {}, {}
	function a:GetOwnedUIParent()
		return self.parent
	end
	function a:CreateOwnedWindowFrame(kind, _, parent, template)
		local frame = self:ApplyTestUITemplate(self:CreateTestUIRegion(self, parent, kind), template)
		if kind == "EditBox" then
			self.noteEditors[#self.noteEditors + 1] = frame
			local setHeight = frame.SetHeight
			function frame:SetHeight(value)
				setHeight(self, value)
				self.noteHeightWrites = (self.noteHeightWrites or 0) + 1
				self.noteLayoutPending = true
			end
			function frame:SetText(value)
				self:Check()
				self.text = value
				self.noteLayoutPending = true
				self:RunScript("OnTextChanged", false)
			end
			function frame:SetJustifyH(value)
				self:Check()
				self.justifyH = value
			end
			function frame:SetJustifyV(value)
				self:Check()
				self.justifyV = value
			end
			function frame:SetBlinkSpeed(value)
				self:Check()
				self.blinkSpeed = value
			end
			function frame:SetTextInsets(left, right, top, bottom)
				self:Check()
				self.textInsets = { left, right, top, bottom }
			end
			function frame:SetCursorPosition(value)
				self:Check()
				assert(value >= 0 and value <= #self:GetText())
				self.cursorPosition = value
				local _, newlines = self:GetText():sub(1, value):gsub("\n", "")
				self:RunScript("OnCursorChanged", self.textInsets[1], -self.textInsets[3] - newlines * NATIVE_LINE_HEIGHT,
					1, NATIVE_LINE_HEIGHT)
			end
			function frame:GetFont()
				self:CheckRead()
				return "FixtureFont", 14, ""
			end
			function frame:GetNumLines()
				local columns = math.max(1, math.floor((self:GetWidth() - self.textInsets[1] - self.textInsets[2]) / 7))
				local count = 0
				for line in (self:GetText() .. "\n"):gmatch("(.-)\n") do
					count = count + math.max(1, math.ceil(#line / columns))
				end
				return count
			end
		elseif kind == "ScrollFrame" then
			function frame:UpdateScrollChildRect()
				self:Check()
				self.noteRectWrites = (self.noteRectWrites or 0) + 1
				self.child.noteLayoutPending = true
			end
			function frame:GetVerticalScrollRange()
				return self.noteNativeRange or 0
			end
			function frame:GetVerticalScroll()
				self:CheckRead()
				return self.verticalScroll or 0
			end
		end
		return frame
	end
	function a:CreateOwnedUICleanupFrame()
		return self:CreateTestUIRegion({})
	end
	function a:StepNoteLayout()
		local function SetRange(scroll, range)
			if range ~= (scroll.noteNativeRange or 0) then
				scroll.noteNativeRange = range
				scroll:RunScript("OnScrollRangeChanged", 0, range)
			end
		end
		local ranges = self.notePendingRanges
		self.notePendingRanges = {}
		for scroll, range in pairs(ranges) do SetRange(scroll, range) end
		local pending = {}
		for _, box in ipairs(self.noteEditors) do
			if box.noteLayoutPending then pending[#pending + 1] = box end
		end
		for _, box in ipairs(pending) do
			box.noteLayoutPending = nil
			-- The engine owns multiline height. An addon SetHeight in either
			-- callback dirties layout again for the next frame, never this one.
			box.height = box:GetNumLines() * NATIVE_LINE_HEIGHT + box.textInsets[3] + box.textInsets[4]
			box.noteNativeLayouts = (box.noteNativeLayouts or 0) + 1
			local scroll, range = box.parent, math.max(0, box.height - box.parent:GetHeight())
			box:RunScript("OnTextChanged", false)
			box:SetCursorPosition(math.min(box.cursorPosition or 0, #box:GetText()))
			if self.deferNoteScrollRange then self.notePendingRanges[scroll] = range else SetRange(scroll, range) end
		end
		return #pending
	end
	return a
end

QT:RegisterTest("private player notes preserve full identity across characters profiles and regions", function()
	local global, a = {}, nil
	a = Fixture(global)
	assert(a:SetPlayerNote("Alice", "Helpful questing companion"))
	assert(a:GetPlayerNote("Alice-HomeRealm") == "Helpful questing companion")
	assert(a:GetPlayerNote("Alice-OtherRealm") == nil)
	local other = Fixture(global)
	assert(other:GetPlayerNote("Alice") == "Helpful questing companion")
	other.db.profile = { unrelated = true }
	assert(other:GetPlayerNote("Alice") == "Helpful questing companion")
	other.region = "EU"
	assert(other:GetPlayerNote("Alice") == nil)
	a.regional = true
	assert(a:SetPlayerNote("Alice-Windrunner", "Regional identity"))
	assert(a:GetPlayerNote("Alice Windrunner") == "Regional identity")
	assert(a:GetPlayerNote("Alice Stormrunner") == nil)
	assert(a:SetPlayerNote("Alice Windrunner", "   "))
	assert(a:GetPlayerNote("Alice Windrunner") == nil)
end)

QT:RegisterTest("private notes reject invalid input retain full text and safely render markup and unicode", function()
	local a = Fixture()
	assert(not a:SetPlayerNote("|Hplayer:Alice|h", "bad"))
	assert(not a:SetPlayerNote("Alice", {}))
	assert(not a:SetPlayerNote("Alice", string.rep("x", 1025)))
	local note = " |Hitem:1|h[Text]|h\n" .. string.rep("中", 150)
	assert(a:SetPlayerNote("Alice", note))
	assert(a:GetPlayerNote("Alice") == note:sub(2))
	local display = a:GetPlayerNoteTooltipText("Alice")
	assert(display:find("||Hitem:1||h", 1, true))
	assert(display:sub(-3) == "…")
	local withoutEnding = display:sub(1, -4)
	assert(withoutEnding:sub(-3) == "中", "tooltip truncated inside UTF-8 character")
	a.db.global.playerNotes.US["Alice-HomeRealm"] = { corrupt = true }
	assert(a:GetPlayerNote("Alice") == nil)
	assert(a:SetPlayerNote("Alice", "Restored\0 value"))
	assert(a:GetPlayerNote("Alice") == "Restored value")
end)

QT:RegisterTest(
	"private note editor preserves drafts during suspension and separates save cancel and delete",
	function()
		local a = Fixture()
		assert(a:OpenPlayerNote("Alice"))
		local frame = a.playerNoteWindow
		assert(frame.box.multiLine and frame.box.maxBytes == 1024 and frame.box.focus)
		frame.box:SetText("First draft")
		frame.box:RunScript("OnTextChanged", true)
		a.parent:Hide()
		assert(not frame.box.focus)
		a.parent:Show()
		assert(a:OpenPlayerNote("Bob"))
		assert(frame.box:GetText() == "")
		assert(a:OpenPlayerNote("Alice"))
		assert(frame.box:GetText() == "First draft")
		frame.save:Click()
		assert(a:GetPlayerNote("Alice") == "First draft" and not frame:IsShown())
		assert(a:OpenPlayerNote("Alice"))
		frame.box:SetText("Discard me")
		frame.box:RunScript("OnTextChanged", true)
		frame.cancel:Click()
		assert(a:OpenPlayerNote("Alice"))
		assert(frame.box:GetText() == "First draft")
		a.blocked = true
		frame.delete:Click()
		assert(a:GetPlayerNote("Alice") == "First draft" and not a:OpenPlayerNote("Bob"))
		a.blocked = false
		frame.delete:Click()
		assert(a:GetPlayerNote("Alice") == nil)
		assert((a.invalidCalls or 0) == 0)
	end
)

QT:RegisterTest("private notes never enter developer diagnostic reports", function()
	QT.API.GetPlayerNotesNamespace = function()
		return "fixture"
	end
	assert(QT:SetPlayerNote("Someone-Realm", "PRIVATE_NOTE_SENTINEL_9347"))
	local report = QT:BuildDeveloperDiagnosticSnapshot()
	assert(not report:find("PRIVATE_NOTE_SENTINEL_9347", 1, true))
	assert(not report:find("playerNotes", 1, true))
end)

QT:RegisterTest("private notes menus and tooltip labels follow the client locale", function()
	local a, menu = Fixture(), { entries = {} }
	function menu:CreateButton(text, callback)
		self.entries[#self.entries + 1] = { text, callback }
	end
	assert(a:PopulatePlayerNotesMenu(menu, "Alice"))
	assert(menu.entries[1][1] == QT.Translate("Add private note"))
	assert(a:SetPlayerNote("Alice", "My note"))
	assert(a:PopulatePlayerNotesMenu(menu, "Alice"))
	assert(menu.entries[2][1] == QT.Translate("Edit private note"))
	assert(a:GetPlayerNoteTooltipText("Alice") == QT.Translate("Private note") .. ": My note")
end, { locale = "client" })

QT:RegisterTest("private note explicit close discards drafts while inherited hiding preserves them", function()
	local a = Fixture()
	assert(a:SetPlayerNote("Alice", "Saved text"))
	assert(a:OpenPlayerNote("Alice"))
	local frame = a.playerNoteWindow
	frame.box:SetText("Uncommitted draft")
	frame.box:RunScript("OnTextChanged", true)
	local identity = frame.identity
	local session = frame.noteSession
	a.parent:Hide()
	assert(frame:IsShown() and not frame:IsVisible())
	assert(frame.noteSession == session and a.playerNoteDrafts[identity] == "Uncommitted draft")
	frame.save:Click()
	frame.delete:Click()
	assert(a:GetPlayerNote("Alice") == "Saved text", "hidden editor must not accept actions")
	a.parent:Show()
	a:DismissManagedWindow(frame, "close")
	assert(frame.noteSession == nil and frame.identity == nil and a.playerNoteDrafts[identity] == nil)
	assert(a:OpenPlayerNote("Alice") and frame.box:GetText() == "Saved text")
	frame.box:SetText("Another draft")
	frame.box:RunScript("OnTextChanged", true)
	frame:Hide()
	assert(frame.noteSession == nil and a.playerNoteDrafts[identity] == nil)
	assert(a:GetPlayerNote("Alice") == "Saved text")
	assert((a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("retired note editor callbacks cannot modify a new player or closed session", function()
	local a = Fixture()
	assert(a:SetPlayerNote("Alice", "Alice saved"))
	assert(a:SetPlayerNote("Bob", "Bob saved"))
	assert(a:OpenPlayerNote("Alice"))
	local frame = a.playerNoteWindow
	local save, delete, cancel =
		frame.save:GetScript("OnClick"), frame.delete:GetScript("OnClick"), frame.cancel:GetScript("OnClick")
	local changed, escape = frame.box:GetScript("OnTextChanged"), frame.box:GetScript("OnEscapePressed")
	assert(a:OpenPlayerNote("Bob"))
	frame.box:SetText("Bob draft")
	frame.box:RunScript("OnTextChanged", true)
	local session = frame.noteSession
	save()
	delete()
	cancel()
	changed(frame.box, true)
	escape()
	assert(frame.noteSession == session and frame:IsVisible())
	assert(a:GetPlayerNote("Alice") == "Alice saved" and a:GetPlayerNote("Bob") == "Bob saved")
	assert(a.playerNoteDrafts[frame.identity] == "Bob draft")
	local closedSave = frame.save:GetScript("OnClick")
	frame.cancel:Click()
	closedSave()
	assert(a:GetPlayerNote("Bob") == "Bob saved" and frame.noteSession == nil)
	assert((a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("private note editor grows for long text and keeps the cursor in a bounded viewport", function()
	local a = Fixture()
	assert(a:OpenPlayerNote("Alice"))
	local frame = a.playerNoteWindow
	local note = string.rep("abcdefghijklmno\n", 64)
	assert(#note == 1024)
	frame.box:SetText(note)
	frame.box:RunScript("OnTextChanged", true)
	a:StepNoteLayout()
	local height = frame.scroll:GetHeight()
	assert(frame.box:GetHeight() > height)
	frame.box:RunScript("OnCursorChanged", 0, -896, 1, 14)
	local scroll = frame.scroll:GetVerticalScroll()
	assert(scroll > 0 and scroll <= frame.scroll:GetVerticalScrollRange())
	assert(scroll <= 896 and scroll + height >= 910, "end cursor must remain fully visible after paste")
	frame.box:RunScript("OnCursorChanged", 0, -14, 1, 14)
	assert(frame.scroll:GetVerticalScroll() <= 14, "moving cursor upward must scroll back")
	frame.box:RunScript("OnCursorChanged", 0, -500, 1, 14)
	assert(frame.scroll:GetVerticalScroll() > 0)
	frame.box:SetText("Short")
	frame.box:RunScript("OnTextChanged", true)
	a:StepNoteLayout()
	assert(frame.box:GetHeight() == NATIVE_LINE_HEIGHT and frame.scroll:GetVerticalScroll() == 0)
	assert(a:GetPlayerNote("Alice") == nil and a.playerNoteDrafts[frame.identity] == "Short")
	local cursor = frame.box:GetScript("OnCursorChanged")
	local writes = frame.scroll.writes
	cursor(frame.box, 0, -math.huge, 1, 14)
	cursor(frame.box, 0, {}, 1, 14)
	cursor(frame.box, 0, -500, 1, 0)
	assert(frame.scroll.writes == writes, "invalid cursor metrics must never affect layout")
	assert(a:OpenPlayerNote("Bob"))
	writes = frame.scroll.writes
	cursor(frame.box, 0, -500, 1, 14)
	assert(frame.scroll.writes == writes, "retired editor must not scroll the current note")
	assert((a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("private note native caret starts visible and focus styling follows actual editor focus", function()
	local a = Fixture()
	assert(a:SetPlayerNote("Alice", string.rep("A saved line\n", 64)))
	assert(a:OpenPlayerNote("Alice"))
	a:StepNoteLayout()
	local frame = a.playerNoteWindow
	assert(frame.box.justifyH == "LEFT" and frame.box.justifyV == "TOP" and frame.box.blinkSpeed == 0.5)
	assert(frame.box.points[1][1] == "TOPLEFT" and frame.box.points[1][2] == frame.scroll)
	assert(frame.box.cursorPosition == 0 and frame.box:HasFocus())
	assert(frame.scroll:GetVerticalScroll() == 0 and frame.noteSession.cursorTop == 0)
	local focusCheck = 0
	local function EdgesShown(expected)
		focusCheck = focusCheck + 1
		for _, edge in ipairs(frame.focusEdges) do
			assert(edge:IsShown() == expected, "unexpected focus outline at check " .. focusCheck)
		end
	end
	EdgesShown(true)
	frame.box:ClearFocus()
	EdgesShown(false)
	frame.scroll:RunScript("OnMouseDown", "RightButton")
	assert(not frame.box:HasFocus())
	frame.scroll:RunScript("OnMouseDown", "LeftButton")
	assert(frame.box:HasFocus())
	EdgesShown(true)
	frame.box:SetCursorPosition(#frame.box:GetText())
	assert(frame.scroll:GetVerticalScroll() > 0)
	frame.cancel:Click()
	EdgesShown(false)
	assert(a:OpenPlayerNote("Alice"))
	assert(frame.box.cursorPosition == 0 and frame.scroll:GetVerticalScroll() == 0)
	EdgesShown(true)
	a.parent:Hide()
	assert(not frame.box:HasFocus())
	EdgesShown(false)
	a.parent:Show()
	assert(not frame.box:HasFocus(), "restoring Alt+Z must not steal keyboard focus")
	EdgesShown(false)
	frame.scroll:RunScript("OnMouseDown", "LeftButton")
	EdgesShown(true)
	local focus, blur, mouse = frame.box:GetScript("OnEditFocusGained"), frame.box:GetScript("OnEditFocusLost"),
		frame.scroll:GetScript("OnMouseDown")
	assert(a:OpenPlayerNote("Bob"))
	assert(frame.box:GetText() == "" and frame.box.cursorPosition == 0 and frame.box:HasFocus())
	blur(frame.box)
	EdgesShown(true)
	frame.box:ClearFocus()
	focus(frame.box)
	mouse(frame.scroll, "LeftButton")
	assert(not frame.box:HasFocus())
	EdgesShown(false)
	a.blocked = true
	frame.scroll:RunScript("OnMouseDown", "LeftButton")
	assert(not frame.box:HasFocus())
	assert((a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("private note idle cursor notifications preserve manual scroll without relayout", function()
	local a = Fixture()
	assert(a:SetPlayerNote("Alice", string.rep("A saved line\n", 64)))
	assert(a:OpenPlayerNote("Alice"))
	a:StepNoteLayout()
	local frame = a.playerNoteWindow
	assert(frame.box.textInsets[3] == 0 and frame.box.textInsets[4] == 0,
		"multiline caret layout must not have vertical text insets")
	assert(frame.scroll:GetHeight() > 0 and frame.scroll:GetHeight() < frame.field:GetHeight(),
		"caret padding belongs outside the native edit box")
	assert(frame.scroll.points[1][2] == frame.field and frame.scroll.points[1][5] < 0)
	for _, edge in ipairs(frame.focusEdges) do assert(edge.points[1][2] == frame.field) end
	frame.box:RunScript("OnCursorChanged", 8, -700, 1, 14)
	assert(frame.scroll:GetVerticalScroll() > 0)
	frame.scroll:SetVerticalScroll(0) -- The player wheels away from the caret.
	local scrollWrites, boxWrites = frame.scroll.writes, frame.box.writes
	local counters = {}
	frame.noteCursorProbeCounters = counters
	for _ = 1, 30 do frame.box:RunScript("OnCursorChanged", 8, -700, 1, 14) end
	assert(counters.cursorEvents == 30 and counters.layoutCalls == nil,
		"opt-in diagnostics must count idle native events without causing layout")
	assert(counters.cursorX == 8 and counters.cursorY == -700 and counters.cursorW == 1 and counters.cursorH == 14)
	frame.noteCursorProbeCounters = nil
	assert(frame.scroll:GetVerticalScroll() == 0, "idle native layout must not undo manual scrolling")
	assert(frame.scroll.writes == scrollWrites and frame.box.writes == boxWrites,
		"unchanged cursor metrics must not write layout")
	frame.box:RunScript("OnTextChanged", false)
	assert(frame.scroll.writes == scrollWrites and frame.box.writes == boxWrites,
		"unchanged content must not force native layout or scrolling")
	frame.box:RunScript("OnCursorChanged", 16, -700, 1, 14) -- A real horizontal move on the hidden line.
	assert(frame.scroll:GetVerticalScroll() > 0, "real horizontal movement must reveal the caret")
	assert(frame.scroll.writes == scrollWrites + 1 and frame.box.writes == boxWrites,
		"revealing the caret should change only scroll offset")
	frame.box:RunScript("OnCursorChanged", 8, 0, 1, 14)
	assert(frame.scroll:GetVerticalScroll() == 0)
	scrollWrites, boxWrites = frame.scroll.writes, frame.box.writes
	frame.box:RunScript("OnCursorChanged", 16, 0, 1, 14)
	assert(frame.scroll.writes == scrollWrites and frame.box.writes == boxWrites,
		"a visible real cursor move must not submit a no-op layout write")
	local setScroll, layoutCallbacks = frame.scroll.SetVerticalScroll, 0
	function frame.scroll:SetVerticalScroll(value)
		setScroll(self, value)
		layoutCallbacks = layoutCallbacks + 1
		assert(layoutCallbacks <= 1, "nested native cursor layout must not recurse")
		frame.box:RunScript("OnCursorChanged", 17, -700, 1, 14)
	end
	frame.box:RunScript("OnCursorChanged", 16, -700, 1, 14)
	assert(layoutCallbacks == 1 and frame.noteSession.cursorX == 17 and not frame.noteSession.adjustingScroll)
	frame.scroll.SetVerticalScroll = setScroll
	frame.box:ClearFocus()
	frame.field:RunScript("OnMouseDown", "LeftButton")
	assert(frame.box:HasFocus(), "the external padding still belongs to the clickable editor")
	assert((a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("private note native multiline height settles without a viewport minimum feedback loop", function()
	local a = Fixture()
	assert(a:OpenPlayerNote("Alice"))
	local frame = a.playerNoteWindow
	local counters = {}
	frame.noteCursorProbeCounters = counters
	assert(frame.box.noteHeightWrites == 1, "only initial EditBox height is addon-owned")
	assert(a:StepNoteLayout() == 1)
	for _ = 1, 30 do
		assert(a:StepNoteLayout() == 0, "QT must not dirty native layout on every idle frame")
	end
	assert(frame.box:GetHeight() == NATIVE_LINE_HEIGHT and frame.box:GetHeight() < frame.scroll:GetHeight())
	assert(frame.box.noteHeightWrites == 1 and frame.scroll.noteRectWrites == nil)
	assert(counters.textEvents == 1 and counters.cursorEvents == 1)
	assert(counters.boxHeightWrites == nil and counters.scrollRectWrites == nil)
	frame.box:SetText("One line")
	frame.box:RunScript("OnTextChanged", true)
	assert(a:StepNoteLayout() == 1 and a:StepNoteLayout() == 0)
	assert(frame.box:GetHeight() == NATIVE_LINE_HEIGHT and frame.box.noteHeightWrites == 1)
	assert(a.playerNoteDrafts[frame.identity] == "One line" and a:GetPlayerNote("Alice") == nil)
	assert((a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("private note cursor waits for delayed native range and short text clamps afterward", function()
	local a = Fixture()
	a.deferNoteScrollRange = true
	assert(a:OpenPlayerNote("Alice"))
	a:StepNoteLayout()
	a:StepNoteLayout()
	local frame = a.playerNoteWindow
	local text = string.rep("A saved line\n", 64)
	frame.box:SetText(text)
	frame.box:RunScript("OnTextChanged", true)
	frame.box:SetCursorPosition(#text)
	assert(frame.scroll:GetVerticalScrollRange() == 0 and frame.scroll:GetVerticalScroll() == 0)
	assert(a:StepNoteLayout() == 1)
	assert(frame.box:GetHeight() > frame.scroll:GetHeight() and frame.scroll:GetVerticalScrollRange() == 0)
	assert(a:StepNoteLayout() == 0)
	local scroll, top = frame.scroll:GetVerticalScroll(), 64 * NATIVE_LINE_HEIGHT
	assert(scroll > 0 and scroll <= frame.scroll:GetVerticalScrollRange())
	assert(scroll <= top and scroll + frame.scroll:GetHeight() + 0.001 >= top + NATIVE_LINE_HEIGHT,
		"delayed native range must reveal the full final caret line")
	frame.box:SetText("Short")
	frame.box:RunScript("OnTextChanged", true)
	assert(a:StepNoteLayout() == 1 and frame.box:GetHeight() == NATIVE_LINE_HEIGHT)
	assert(a:StepNoteLayout() == 0)
	assert(frame.scroll:GetVerticalScroll() == 0 and frame.scroll:GetVerticalScrollRange() == 0)
	assert(frame.box.noteHeightWrites == 1 and frame.scroll.noteRectWrites == nil)
	assert((a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("private note callbacks guard independently forbidden editor regions", function()
	for _, key in ipairs({ "box", "field", "scroll", "save", "delete", "cancel" }) do
		local a = Fixture()
		assert(a:SetPlayerNote("Alice", "Keep me"))
		assert(a:OpenPlayerNote("Alice"))
		local frame = a.playerNoteWindow
		local callback = (key == "delete" and frame.delete or key == "cancel" and frame.cancel or frame.save):GetScript(
			"OnClick"
		)
		local cursor, changed = frame.box:GetScript("OnCursorChanged"), frame.box:GetScript("OnTextChanged")
		frame[key].forbidden = true
		callback(key == "cancel" and frame.cancel or nil)
		if key == "box" or key == "field" or key == "scroll" then
			cursor(frame.box, 0, -500, 1, 14)
			changed(frame.box, true)
		end
		assert(a:GetPlayerNote("Alice") == "Keep me" and frame.noteSession ~= nil)
		assert((a.invalidCalls or 0) == 0, key)
	end
end)
