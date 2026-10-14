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
		frame.field = self:CreateOwnedWindowFrame("Frame", nil, frame)
		frame.field:SetPoint("TOPLEFT", frame.hint, "BOTTOMLEFT", 0, -16)
		frame.field:SetSize(frame.contentWidth - 28, 130)
		frame.field:EnableMouse(true)
		frame.scroll = self:CreateOwnedWindowFrame("ScrollFrame", nil, frame.field, "UIPanelScrollFrameTemplate")
		frame.scroll:SetPoint("TOPLEFT", frame.field, "TOPLEFT", 0, -8)
		frame.scroll:SetSize(frame.contentWidth - 28, 114)
		frame.scroll:HookScript("OnScrollRangeChanged", function()
			if frame.RefreshNoteScrollRange then frame.RefreshNoteScrollRange() end
		end)
		frame.box = self:CreateOwnedWindowFrame("EditBox", nil, frame.scroll)
		frame.box:SetMultiLine(true)
		frame.box:SetAutoFocus(false)
		frame.box:SetFontObject("ChatFontNormal")
		frame.box:SetJustifyH("LEFT")
		frame.box:SetJustifyV("TOP")
		frame.box:SetBlinkSpeed(0.5)
		-- Vertical insets on a multiline edit box can continually invalidate its
		-- native caret layout. Keep that padding outside the scrolling viewport.
		frame.box:SetTextInsets(8, 8, 0, 0)
		frame.box:SetPoint("TOPLEFT", frame.scroll, "TOPLEFT")
		frame.box:SetWidth(frame.contentWidth - 28)
		-- Like Blizzard's InputScrollFrameTemplate, leave multiline height to
		-- the native editor. A viewport-sized minimum fights its text layout
		-- every frame and can prevent the native caret from being positioned.
		frame.box:SetHeight(1)
		frame.box:SetMaxBytes(MAX_BYTES)
		frame.scroll:SetScrollChild(frame.box)
		self:AddScrollDialogLabel(frame, frame.box)
		local background = frame.field:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetColorTexture(0.5, 0.5, 0.5, 0.18)
		-- Show the native edit box's actual keyboard focus independently of its
		-- blinking caret. These edges belong to QT, not to a shared template.
		frame.focusEdges = {}
		for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local texture = frame.field:CreateTexture(nil, "OVERLAY")
			if edge == "TOP" or edge == "BOTTOM" then
				texture:SetPoint(edge .. "LEFT", frame.field, edge .. "LEFT")
				texture:SetPoint(edge .. "RIGHT", frame.field, edge .. "RIGHT")
				texture:SetHeight(1)
			else
				texture:SetPoint("TOP" .. edge, frame.field, "TOP" .. edge)
				texture:SetPoint("BOTTOM" .. edge, frame.field, "BOTTOM" .. edge)
				texture:SetWidth(1)
			end
			texture:SetColorTexture(0.75, 0.64, 0.42, 0.65)
			texture:Hide()
			frame.focusEdges[#frame.focusEdges + 1] = texture
		end
		frame.HideNoteFocus = function()
			for _, edge in ipairs(frame.focusEdges) do self:HideOwnedUI(edge) end
		end
		frame.scroll:EnableMouse(true)
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
				frame:HideNoteFocus()
				if self.LibChev.CanMutateOwnedRegion(frame.box) then
					frame.box:ClearFocus()
				end
			end,
			dismiss = function()
				frame:HideNoteFocus()
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
		frame.field,
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
	frame.box:ClearFocus()
	frame.identity = identity
	local session = {}
	frame.noteSession = session
	local function Current(control)
		return frame.noteSession == session
			and Guard(self, frame)
			and Guard(self, frame.box)
			and Guard(self, frame.field)
			and Guard(self, frame.scroll)
			and (not control or Guard(self, control))
			and frame:IsVisible()
	end
	local function ScrollToCursor(followCursor)
		if not Current() or session.adjustingScroll then
			return
		end
		local probe = frame.noteCursorProbeCounters
		if probe then probe.layoutCalls = (probe.layoutCalls or 0) + 1 end
		local height = self:SafeToNumber(frame.scroll:GetHeight())
		local nativeRange = self:SafeToNumber(frame.scroll:GetVerticalScrollRange())
		local scroll = self:SafeToNumber(frame.scroll:GetVerticalScroll())
		if
			not height
			or height <= 0
			or not nativeRange
			or not scroll
		then
			return
		end
		session.adjustingScroll = true
		if followCursor then session.followCursor = true end
		local previousScroll = scroll
		local range = math.max(0, nativeRange)
		if session.followCursor and session.cursorTop and session.cursorHeight then
			local top = math.max(0, session.cursorTop)
			if top < scroll then
				scroll = top
			elseif top + session.cursorHeight > scroll + height then
				scroll = top + session.cursorHeight - height
			end
		end
		scroll = math.max(0, math.min(range, scroll))
		-- Cursor callbacks can precede the native scroll-range update. Keep
		-- only the latest cursor target until that update makes it visible.
		if session.cursorTop and session.cursorHeight
			and session.cursorTop >= scroll
			and session.cursorTop + session.cursorHeight <= scroll + height then
			session.followCursor = nil
		end
		if scroll ~= previousScroll then
			if probe then probe.scrollWrites = (probe.scrollWrites or 0) + 1 end
			frame.scroll:SetVerticalScroll(scroll)
		end
		session.adjustingScroll = nil
	end
	frame.RefreshNoteScrollRange = function() ScrollToCursor() end
	local function Cancel(control)
		if Current(control) then
			self:DismissManagedWindow(frame, "cancel")
		end
	end
	local function Focus()
		if Current() then frame.box:SetFocus() end
	end
	frame.scroll:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then Focus() end
	end)
	frame.field:SetScript("OnMouseDown", frame.scroll:GetScript("OnMouseDown"))
	frame.box:SetScript("OnEditFocusGained", function(box)
		if not Current(box) or not box:HasFocus() then return end
		for _, edge in ipairs(frame.focusEdges) do
			if Guard(self, edge) then self:CallOwnedUI(edge, "Show") end
		end
		ScrollToCursor(true)
	end)
	frame.box:SetScript("OnEditFocusLost", function()
		if frame.noteSession == session then frame:HideNoteFocus() end
	end)
	frame.escapeAction = Cancel
	frame.box:SetScript("OnEscapePressed", Cancel)
	frame.box:SetScript("OnCursorChanged", function(box, x, y, width, height)
		if not Current(box) then
			return
		end
		local probe = frame.noteCursorProbeCounters
		if probe then
			probe.cursorEvents = (probe.cursorEvents or 0) + 1
			probe.cursorX, probe.cursorY = self:SafeToNumber(x), self:SafeToNumber(y)
			probe.cursorW, probe.cursorH = self:SafeToNumber(width), self:SafeToNumber(height)
		end
		x, y, height = self:SafeToNumber(x), self:SafeToNumber(y), self:SafeToNumber(height)
		-- Blizzard's ScrollingEdit_OnCursorChanged supplies a negative vertical
		-- offset from the edit box's top, plus the cursor line's height.
		if not x or not y or not height or height <= 0 or height > 128
			or math.abs(x) > (MAX_BYTES + 1) * 128 or math.abs(y) > (MAX_BYTES + 1) * 128 then
			return
		end
		-- Layout notifications can repeat without the user moving the caret.
		-- Do not undo manual scrolling or restart native layout for those events.
		if session.cursorX == x and session.cursorTop == -y and session.cursorHeight == height then return end
		session.cursorX, session.cursorTop, session.cursorHeight = x, -y, height
		ScrollToCursor(true)
	end)
	frame.box:SetScript("OnTextChanged", function(box, userInput)
		if not Current(box) then
			return
		end
		local probe = frame.noteCursorProbeCounters
		if probe then probe.textEvents = (probe.textEvents or 0) + 1 end
		if userInput == true then
			self.playerNoteDrafts = rawget(self, "playerNoteDrafts") or {}
			self.playerNoteDrafts[identity] = self:SafeToString(box:GetText(), "")
		end
		ScrollToCursor(userInput == true)
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
	-- SetText can deliver cursor metrics while the dialog is hidden. Reset the
	-- real native caret after Show so it starts inside the visible viewport.
	frame.box:SetCursorPosition(0)
	frame.box:SetFocus()
	return true
end
