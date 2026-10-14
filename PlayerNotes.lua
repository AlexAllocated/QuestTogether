-- Personal annotations never enter peer records, profiles, or communications.
local QT = _G.QuestTogether
local L = QT.Translate
local MAX_BYTES = 1024

function QT:GetPlayerNoteIdentity(name)
	name = self:SafeTrimString(name, "")
	if name == "" or #name > 120 or name:find("[%c|,:]") then
		return nil
	end
	name = self:NormalizeMemberName(name)
	if not name or #name > 160 then
		return nil
	end
	return name
end

local function Store(addon, create)
	local global = addon.db and addon.db.global
	if type(global) ~= "table" then
		return nil
	end
	local namespace = addon.API.GetPlayerNotesNamespace and addon.API.GetPlayerNotesNamespace()
	if type(namespace) ~= "string" or namespace == "" then
		return nil
	end
	if type(global.playerNotes) ~= "table" then
		if not create then
			return nil
		end
		global.playerNotes = {}
	end
	if type(global.playerNotes[namespace]) ~= "table" then
		if not create then
			return nil
		end
		global.playerNotes[namespace] = {}
	end
	return global.playerNotes[namespace]
end

function QT:GetPlayerNote(name)
	local identity, store = self:GetPlayerNoteIdentity(name), Store(self, false)
	local value = identity and store and store[identity]
	return type(value) == "string" and #value <= MAX_BYTES and value or nil
end

function QT:SetPlayerNote(name, text)
	local identity = self:GetPlayerNoteIdentity(name)
	if not identity or not self:CanAccessValue(text) or type(text) ~= "string" or #text > MAX_BYTES then
		return false
	end
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%c", function(character)
		return (character == "\n" or character == "\t") and character or ""
	end)
	text = self:SafeTrimString(text, "")
	local store = Store(self, true)
	if not store then
		return false
	end
	store[identity] = text ~= "" and text or nil
	local drafts = rawget(self, "playerNoteDrafts")
	if drafts then
		drafts[identity] = nil
	end
	return true
end

function QT:GetPlayerNoteTooltipText(name)
	local note = self:GetPlayerNote(name)
	if not note then
		return nil
	end
	-- A note is plain text, including any pasted WoW links or texture markup.
	-- Keep the tooltip compact; the editor always retains the complete note.
	if #note > 280 then
		local last = 280
		while last > 0 and note:byte(last + 1) and note:byte(last + 1) >= 128 and note:byte(last + 1) < 192 do
			last = last - 1
		end
		note = note:sub(1, last) .. "…"
	end
	return L("Private note") .. ": " .. note:gsub("|", "||")
end

function QT:PopulatePlayerNotesMenu(menu, name)
	local identity = self:GetPlayerNoteIdentity(name)
	if not identity then
		return false
	end
	menu:CreateButton(self:GetPlayerNote(identity) and L("Edit private note") or L("Add private note"), function()
		self:OpenPlayerNote(identity)
	end)
	return true
end

local function Guard(addon, frame)
	return not addon:IsWorkBlocked("foreign_frame_mutation") and addon:CanMutateOwnedUI(frame)
end

function QT:OpenPlayerNote(name)
	local identity = self:GetPlayerNoteIdentity(name)
	if not identity or self:IsWorkBlocked("foreign_frame_mutation") or not Store(self, true) then
		return false
	end
	local frame = rawget(self, "playerNoteWindow")
	if not frame then
		frame = self:CreateScrollDialog(580, 350, L("Private player note"))
		if not frame then
			return false
		end
		self.playerNoteWindow = frame
		frame.playerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.playerLabel:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
		frame.playerLabel:SetWidth(frame.contentWidth)
		frame.playerLabel:SetJustifyH("LEFT")
		self:AddScrollDialogLabel(frame, frame.playerLabel)
		frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		frame.hint:SetPoint("TOPLEFT", frame.playerLabel, "BOTTOMLEFT", 0, -10)
		frame.hint:SetWidth(frame.contentWidth)
		frame.hint:SetJustifyH("LEFT")
		frame.hint:SetText(
			L(
				"Only you can see these notes. Shared across your characters; never sent to other players or in diagnostics."
			)
		)
		self:AddScrollDialogLabel(frame, frame.hint)
		frame.scroll = self:CreateOwnedWindowFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
		frame.scroll:SetPoint("TOPLEFT", frame.hint, "BOTTOMLEFT", 0, -16)
		frame.scroll:SetSize(frame.contentWidth - 28, 130)
		frame.box = self:CreateOwnedWindowFrame("EditBox", nil, frame.scroll)
		frame.box:SetMultiLine(true)
		frame.box:SetAutoFocus(false)
		frame.box:SetFontObject("ChatFontNormal")
		frame.box:SetTextInsets(8, 8, 8, 8)
		frame.box:SetWidth(frame.contentWidth - 28)
		frame.box:SetHeight(130)
		frame.box:SetMaxBytes(MAX_BYTES)
		frame.scroll:SetScrollChild(frame.box)
		self:AddScrollDialogLabel(frame, frame.box)
		local background = frame.scroll:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetColorTexture(0.5, 0.5, 0.5, 0.18)
		local function Button(label, offset)
			local button = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelButtonTemplate")
			button:SetPoint("BOTTOMRIGHT", -frame.contentInset - offset, frame.contentBottom)
			button:SetSize(110, 24)
			button:SetText(label)
			return button
		end
		frame.cancel = Button(L("Cancel"), 0)
		frame.save = Button(L("Save"), 118)
		frame.delete = Button(L("Delete note"), 236)
		frame.LayoutManagedWindow = function()
			frame:SetHeight(
				frame.contentTop
					+ frame.playerLabel:GetStringHeight()
					+ frame.hint:GetStringHeight()
					+ 10
					+ 16
					+ 130
					+ 24
					+ 24
					+ frame.contentBottom
			)
			self:FitScrollDialog(frame)
		end
		self:ConfigureWindowController(frame, {
			suspend = function()
				if self.LibChev.CanMutateOwnedRegion(frame.box) then
					frame.box:ClearFocus()
				end
			end,
			dismiss = function()
				local drafts = rawget(self, "playerNoteDrafts")
				if drafts and frame.identity then
					drafts[frame.identity] = nil
				end
				frame.noteSession, frame.identity = nil, nil
			end,
		})
	end
	for _, region in ipairs({
		frame,
		frame.box,
		frame.playerLabel,
		frame.hint,
		frame.scroll,
		frame.save,
		frame.delete,
		frame.cancel,
	}) do
		if not Guard(self, region) then
			return false
		end
	end
	if not self:ApplyScrollDialogTheme(frame) then
		return false
	end
	frame.identity = identity
	local session = {}
	frame.noteSession = session
	local function Current(control)
		return frame.noteSession == session
			and Guard(self, frame)
			and Guard(self, frame.box)
			and Guard(self, frame.scroll)
			and (not control or Guard(self, control))
			and frame:IsVisible()
	end
	local function ScrollToCursor()
		if not Current() then
			return
		end
		local _, fontHeight = frame.box:GetFont()
		fontHeight = self:SafeToNumber(fontHeight)
		local lines = self:SafeToNumber(frame.box:GetNumLines())
		local height = self:SafeToNumber(frame.scroll:GetHeight())
		if
			not fontHeight
			or fontHeight <= 0
			or fontHeight > 128
			or not lines
			or lines < 0
			or lines > MAX_BYTES + 1
			or not height
			or height <= 0
		then
			return
		end
		local contentHeight = math.max(height, math.max(1, lines) * fontHeight + 16)
		if self:SafeToNumber(frame.box:GetHeight()) ~= contentHeight then
			frame.box:SetHeight(contentHeight)
		end
		frame.scroll:UpdateScrollChildRect()
		local nativeRange = self:SafeToNumber(frame.scroll:GetVerticalScrollRange())
		local scroll = self:SafeToNumber(frame.scroll:GetVerticalScroll())
		if not nativeRange or not scroll then
			return
		end
		local range = math.max(0, math.min(nativeRange, contentHeight - height))
		if session.cursorTop and session.cursorHeight then
			local top = math.max(0, math.min(session.cursorTop, contentHeight - session.cursorHeight))
			if top < scroll then
				scroll = top
			elseif top + session.cursorHeight > scroll + height then
				scroll = top + session.cursorHeight - height
			end
		end
		frame.scroll:SetVerticalScroll(math.max(0, math.min(range, scroll)))
	end
	local function Cancel(control)
		if Current(control) then
			self:DismissManagedWindow(frame, "cancel")
		end
	end
	frame.escapeAction = Cancel
	frame.box:SetScript("OnEscapePressed", Cancel)
	frame.box:SetScript("OnCursorChanged", function(box, _, y, _, height)
		if not Current(box) then
			return
		end
		y, height = self:SafeToNumber(y), self:SafeToNumber(height)
		-- Blizzard's ScrollingEdit_OnCursorChanged supplies a negative vertical
		-- offset from the edit box's top, plus the cursor line's height.
		if not y or not height or height <= 0 or height > 128 or math.abs(y) > (MAX_BYTES + 1) * 128 + 16 then
			return
		end
		session.cursorTop, session.cursorHeight = -y, height
		ScrollToCursor()
	end)
	frame.box:SetScript("OnTextChanged", function(box, userInput)
		if not Current(box) then
			return
		end
		if userInput == true then
			self.playerNoteDrafts = rawget(self, "playerNoteDrafts") or {}
			self.playerNoteDrafts[identity] = self:SafeToString(box:GetText(), "")
		end
		ScrollToCursor()
	end)
	frame.cancel:SetScript("OnClick", Cancel)
	frame.save:SetScript("OnClick", function()
		if Current(frame.save) and self:SetPlayerNote(identity, self:SafeToString(frame.box:GetText(), "")) then
			self:DismissManagedWindow(frame, "save")
		end
	end)
	frame.delete:SetScript("OnClick", function()
		if Current(frame.delete) and self:SetPlayerNote(identity, "") then
			self:DismissManagedWindow(frame, "delete")
		end
	end)
	frame.playerLabel:SetText(identity:gsub("|", "||"))
	local drafts = rawget(self, "playerNoteDrafts")
	frame.box:SetText(drafts and drafts[identity] or self:GetPlayerNote(identity) or "")
	frame.scroll:SetVerticalScroll(0)
	frame:LayoutManagedWindow()
	frame:Show()
	frame:Raise()
	ScrollToCursor()
	frame.box:SetFocus()
	return true
end
