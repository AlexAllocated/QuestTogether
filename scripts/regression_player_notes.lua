-- Private SavedVariables and frame fixtures only; safe to run in a live client.
local QT = _G.QuestTogether
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
	function a:GetOwnedUIParent()
		return self.parent
	end
	function a:CreateOwnedWindowFrame(kind, _, parent, template)
		local frame = self:ApplyTestUITemplate(self:CreateTestUIRegion(self, parent, kind), template)
		if kind == "EditBox" then
			function frame:GetFont()
				self:CheckRead()
				return "FixtureFont", 14, ""
			end
			function frame:GetNumLines()
				return self:GetStringHeight() / 14
			end
		elseif kind == "ScrollFrame" then
			function frame:UpdateScrollChildRect()
				self:Check()
			end
			function frame:GetVerticalScrollRange()
				return math.max(0, self.child:GetHeight() - self:GetHeight())
			end
			function frame:GetVerticalScroll()
				self:CheckRead()
				return self.verticalScroll or 0
			end
		end
		return frame
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
	assert(frame.box:GetHeight() == height and frame.scroll:GetVerticalScroll() == 0)
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

QT:RegisterTest("private note callbacks guard independently forbidden editor regions", function()
	for _, key in ipairs({ "box", "scroll", "save", "delete", "cancel" }) do
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
		if key == "box" or key == "scroll" then
			cursor(frame.box, 0, -500, 1, 14)
			changed(frame.box, true)
		end
		assert(a:GetPlayerNote("Alice") == "Keep me" and frame.noteSession ~= nil)
		assert((a.invalidCalls or 0) == 0, key)
	end
end)
