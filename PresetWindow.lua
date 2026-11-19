-- SPDX-License-Identifier: GPL-3.0-only
-- The setup window owns only selection and presentation. Applying a selection
-- uses the same settings transaction as individually editing its options.
local QT = _G.QuestTogether
local L = QT.Translate
local function Ready(a, frame)
	return not a:IsWorkBlocked("foreign_frame_mutation") and a.LibChev.CanMutateOwnedRegion(frame)
		and frame:IsShown() and frame.profile == a.db.profile
end
function QT:ClosePresetWindow(applied)
	local frame = rawget(self, "presetWindow")
	if not frame then return end
	if not applied and self:IsWelcomeSetupPending() then
		if self:IsRuntimeRestricted() then
			frame.finishDefault = true
			self:HideOwnedUI(frame)
			self:InitializePresetWelcome()
			return
		end
		if not self:ApplyPreset("full", true) then return end
	end
	self:DismissManagedWindow(frame, "close")
end
function QT:OpenPresetWindow()
	if self:IsWorkBlocked("foreign_frame_mutation") or not self:CanPresentReleaseNotes() then return false end
	local frame = rawget(self, "presetWindow")
	if not frame then
		frame = self:CreateScrollDialog(760, 730, L("Welcome to QuestTogether"))
		if not frame then return false end
		self.presetWindow = frame
		local function Label(parent, font, text, role)
			local label = parent:CreateFontString(nil, "OVERLAY", font)
			label:SetJustifyH("LEFT"); label:SetWordWrap(true); label:SetText(text)
			self:AddScrollDialogLabel(frame, label, role)
			return label
		end
		frame.intro = Label(frame, "GameFontHighlight", L("Choose how much QuestTogether you want to see. Every choice is a set of ordinary settings you can change later."))
		frame.intro:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
		frame.intro:SetWidth(frame.contentWidth)
		frame.scroll = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "ScrollFrame", frame)
		frame.scroll:EnableMouseWheel(true)
		frame.content = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Frame", frame.scroll)
		frame.scroll:SetScrollChild(frame.content)
		local function SyncScroll(value)
			if not self:CanMutateOwnedUI(frame) then return end
			value = self:SafeToNumber(value)
			if not value then return end
			frame.scrollOffset = self:UpdateOwnedScrollBar(frame.scrollBar, value,
				frame.scrollMaximum or 0, frame.scroll:GetHeight(), 36) or 0
			return frame.scrollOffset
		end
		local function Scroll(value)
			value = SyncScroll(value)
			if value then frame.scroll:SetVerticalScroll(value) end
		end
		frame.scrollBar = self:CreateOwnedScrollBar(self.CreateOwnedWindowFrame, frame, false, Scroll)
		frame.scrollBar:SetPoint("TOPLEFT", frame.scroll, "TOPRIGHT", 8, 0)
		frame.scroll:SetScript("OnVerticalScroll", function(_, value) SyncScroll(value) end)
		frame.scroll:SetScript("OnMouseWheel", function(_, delta)
			if Ready(self, frame) then Scroll((frame.scrollOffset or 0) - (self:SafeToNumber(delta) or 0) * 36) end
		end)
		local function Reveal(card)
			local offset, top = frame.scrollOffset or 0, card.listTop or 0
			if top < offset then Scroll(top)
			elseif top + card:GetHeight() > offset + frame.scroll:GetHeight() then
				Scroll(top + card:GetHeight() - frame.scroll:GetHeight())
			end
		end
		local function Details(card, open)
			if not Ready(self, frame) then return end
			frame.expandedPreset = open and card.id or nil
			frame:LayoutManagedWindow()
			Scroll(card.listTop)
			self:RefreshGamepadNavigation(frame, card.expand)
		end
		frame.cards = {}
		local guarded = {}
		for index, preset in ipairs(self:GetPresetDefinitions()) do
			local card = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Button", frame.content)
			card.id, card.baseTitle, card.summary = preset.id, preset.title, preset.description
			card.fill = card:CreateTexture(nil, "BACKGROUND"); card.fill:SetAllPoints()
			card:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			card.title = Label(card, "GameFontNormal", preset.title, "heading")
			card:SetFontString(card.title)
			card.title:SetPoint("TOPLEFT", 16, -12)
			card.description = Label(card, "GameFontHighlight", preset.scenario)
			card.description:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
			card.expand = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Button", card, "UIPanelButtonTemplate")
			card.expand:SetSize(190, 24)
			card.expand:SetPoint("BOTTOMLEFT", 16, 10)
			card.expand:SetScript("OnClick", function() Details(card, frame.expandedPreset ~= card.id) end)
			self:AttachSettingsTooltip(card, preset.title, preset.scenario .. "\n\n" .. L("Select this preset to prepare it. Your settings change only when you press Apply preset or Start questing."))
			self:AttachSettingsTooltip(card.expand, L("Settings"), L("Inspect every setting this preset applies. Expanding or closing this list does not select or apply the preset."))
			card.details = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Frame", frame.content)
			card.details.fill = card.details:CreateTexture(nil, "BACKGROUND"); card.details.fill:SetAllPoints()
			card.details.fill:SetColorTexture(0.5, 0.5, 0.5, 0.06)
			card.details:Hide()
			card:SetScript("OnClick", function()
				if Ready(self, frame) then frame.selected = card.id; frame:LayoutManagedWindow() end
			end)
			frame.cards[index] = card
			guarded[#guarded + 1], guarded[#guarded + 2] = card, card.expand
		end
		frame.future = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "CheckButton", frame, "UICheckButtonTemplate")
		frame.future:SetSize(26, 26)
		frame.future.label = Label(frame.future, "GameFontHighlight", L("Use this preset for new characters"))
		frame.future.label:SetPoint("LEFT", frame.future, "RIGHT", 4, 0)
		frame.future.label:SetWidth(frame.contentWidth - 40)
		self:AttachSettingsTooltip(frame.future, L("Use this preset for new characters"),
			L("Use the selected preset when a new character profile is created. Existing and copied profiles keep their settings. First-time setup always saves this default."))
		frame.hint = Label(frame, "GameFontHighlightSmall", L("Only feature settings change. Layouts, bindings and personal data stay yours. Open WoW Options > AddOns > QuestTogether to customize or change presets."))
		frame.hint:SetWidth(frame.contentWidth)
		frame.close = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Button", frame, "UIPanelCloseButton")
		frame.close:SetPoint("TOPRIGHT", -16, -7); frame.close:SetSize(26, 26)
		frame.close:SetScript("OnClick", function() self:ClosePresetWindow() end)
		frame.apply = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Button", frame, "UIPanelButtonTemplate")
		frame.apply:SetPoint("BOTTOMRIGHT", -frame.contentInset, frame.contentBottom - 28)
		frame.apply:SetSize(240, 28)
		self:AttachSettingsTooltip(frame.apply, L("Apply preset"),
			L("Apply the selected feature settings to your current profile. Layouts, bindings and personal data are kept. The checkbox above controls the default for future characters."))
		frame.apply:SetScript("OnClick", function()
			if Ready(self, frame) and self:ApplyPreset(frame.selected, frame.future:GetChecked() == true) then
				self:ClosePresetWindow(true)
			end
		end)
		local function LayoutDetails(card, width)
			if not card.detailRows then
				card.detailRows = {}
				card.detailSummary = Label(card.details, "GameFontHighlightSmall", card.summary)
				for _, group in ipairs(self:GetPresetSettingDetails(card.id)) do
					card.detailRows[#card.detailRows + 1] = { heading = Label(card.details, "GameFontNormal", group.title, "heading") }
					for _, entry in ipairs(group.entries) do
						local row = { key = entry.key, label = Label(card.details, "GameFontHighlightSmall", entry.label),
							value = Label(card.details, "GameFontHighlightSmall", entry.text, entry.value == false and "muted" or "body") }
						row.value:SetJustifyH("RIGHT")
						card.detailRows[#card.detailRows + 1] = row
					end
				end
			end
			card.detailSummary:ClearAllPoints(); card.detailSummary:SetPoint("TOPLEFT", 16, -12); card.detailSummary:SetWidth(width - 32)
			local y = card.detailSummary:GetStringHeight() + 16
			for _, row in ipairs(card.detailRows) do
				if row.heading then
					y = y + 12
					row.heading:ClearAllPoints(); row.heading:SetPoint("TOPLEFT", 16, -y); row.heading:SetWidth(width - 32)
					y = y + row.heading:GetStringHeight() + 8
				else
					row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT", 22, -y); row.label:SetWidth(width - 220)
					row.value:ClearAllPoints(); row.value:SetPoint("TOPRIGHT", -16, -y); row.value:SetWidth(166)
					y = y + math.max(row.label:GetStringHeight(), row.value:GetStringHeight()) + 8
				end
			end
			card.details:SetSize(width, y + 12)
			return y + 12
		end
		frame.LayoutManagedWindow = function()
			if not self:CanMutateOwnedUI(frame) then return end
			local hintBottom = frame.contentBottom + 12
			frame.hint:ClearAllPoints(); frame.hint:SetPoint("BOTTOMLEFT", frame.contentInset, hintBottom)
			local futureBottom = hintBottom + frame.hint:GetStringHeight() + 10
			frame.future:ClearAllPoints(); frame.future:SetPoint("BOTTOMLEFT", frame.contentInset, futureBottom)
			local top = frame.contentTop + frame.intro:GetStringHeight() + 12
			local height = frame:GetHeight() - top - futureBottom - math.max(28, frame.future.label:GetStringHeight()) - 14
			local width = frame.contentWidth - 20
			frame.scroll:ClearAllPoints(); frame.scroll:SetPoint("TOPLEFT", frame.contentInset, -top)
			frame.scroll:SetSize(width, math.max(100, height)); frame.scrollBar:SetHeight(frame.scroll:GetHeight())
			local y = 0
			for _, card in ipairs(frame.cards) do
				local selected = card.id == frame.selected
				card.title:SetText((selected and "|TInterface\\Buttons\\UI-CheckBox-Check:14|t " or "") .. card.baseTitle
					.. (card.id == "full" and " (" .. L("Default") .. ")" or ""))
				card.title:SetWidth(width - 32); card.description:SetWidth(width - 32)
				card.listTop = y
				card:ClearAllPoints(); card:SetPoint("TOPLEFT", 0, -y)
				card:SetSize(width, card.title:GetStringHeight() + card.description:GetStringHeight() + 62)
				card.fill:SetColorTexture(0.72, 0.55, 0.18, selected and 0.32 or 0.08)
				y = y + card:GetHeight()
				local open = frame.expandedPreset == card.id
				card.expand:SetText(open and L("Hide settings") or L("Show settings"))
				card.details:SetShown(open)
				if open then
					card.details:ClearAllPoints(); card.details:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
					y = y + LayoutDetails(card, width)
				end
				y = y + 8
			end
			frame.content:SetSize(width, y)
			frame.scrollMaximum = math.max(0, y - frame.scroll:GetHeight())
			Scroll(frame.scrollOffset or 0)
			self:FitScrollDialog(frame); self:ApplyScrollDialogTheme(frame)
		end
		guarded[#guarded + 1], guarded[#guarded + 2] = frame.apply, frame.future
		self:GuardGamepadWindowActions(frame, guarded)
		local inherited = frame:GetScript("OnKeyDown")
		frame:SetScript("OnKeyDown", function(_, key)
			if not Ready(self, frame) or (self.API.IsPartyQuestKeyboardInputBlocked and self.API.IsPartyQuestKeyboardInputBlocked(frame)) then return end
			frame:SetPropagateKeyboardInput(true)
			if key == "ESCAPE" then if inherited then inherited(frame, key) end; return end
			local index = 1
			for i, card in ipairs(frame.cards) do if card.id == frame.selected then index = i; break end end
			if key == "UP" or key == "DOWN" then
				index = math.max(1, math.min(#frame.cards, index + (key == "UP" and -1 or 1)))
				frame.selected = frame.cards[index].id; frame:LayoutManagedWindow(); Reveal(frame.cards[index])
			elseif key == "RIGHT" or key == "LEFT" then Details(frame.cards[index], key == "RIGHT")
			elseif key == "PAGEUP" or key == "PAGEDOWN" then
				Scroll((frame.scrollOffset or 0) + (key == "PAGEUP" and -1 or 1) * frame.scroll:GetHeight() * 0.8)
			elseif key == "SPACE" then
				if not self:IsWelcomeSetupPending() then frame.future:SetChecked(not frame.future:GetChecked()) end
			elseif key == "ENTER" or key == "NUMPADENTER" then frame.apply:Click()
			else return end
			frame:SetPropagateKeyboardInput(false)
		end)
		frame:HookScript("OnHide", function()
			if self:IsWelcomeSetupPending() and not self.isLoggingOut then self:InitializePresetWelcome(true) end
		end)
		self:ConfigureWindowController(frame, { theme = frame.LayoutManagedWindow,
			dismiss = function(reason)
				if self:IsWelcomeSetupPending() and reason ~= "hide" then self:ClosePresetWindow() end
			end,
		})
	end
	frame.profile, frame.finishDefault, frame.expandedPreset, frame.scrollOffset = self.db.profile, nil, nil, 0
	frame.selected = self:IsWelcomeSetupPending() and "full" or self:GetMatchingPreset() or "full"
	frame.future:SetChecked(self:IsWelcomeSetupPending())
	frame.future:SetEnabled(not self:IsWelcomeSetupPending())
	frame.apply:SetText(self:IsWelcomeSetupPending() and L("Start questing") or L("Apply preset"))
	frame:LayoutManagedWindow(); frame:Show(); frame:Raise()
	if self:IsNativeGamepadMode() then self:MarkGamepadContainer(frame.content) end
	self:PresentStandardGamepadWindow(frame, "welcome", function() self:ClosePresetWindow() end,
		frame.cards[1], frame.scroll, self:IsWelcomeSetupPending() and "automatic" or "user")
	return true
end
function QT:InitializePresetWelcome(deferred)
	if not self:IsWelcomeSetupPending() then return false end
	local wake = rawget(self, "presetWakeFrame")
	if not wake then wake = self:CreateReleaseNotesWakeFrame(); self.presetWakeFrame = wake end
	local elapsed = 0
	local function Try()
		if not self:IsWelcomeSetupPending() then
			wake:SetScript("OnUpdate", nil); wake:UnregisterAllEvents(); return
		end
		if self:IsRuntimeRestricted() or self.isLoggingOut or not self.hasLoggedIn then return end
		local frame = rawget(self, "presetWindow")
		local ok, result
		if frame and frame.finishDefault then ok, result = pcall(self.ApplyPreset, self, "full", true)
		else ok, result = pcall(self.OpenPresetWindow, self) end
		if not ok or result or not self:IsWelcomeSetupPending() then
			wake:SetScript("OnUpdate", nil); wake:UnregisterAllEvents()
			if not ok then self:RecordDiagnosticError("welcome", result) end
		end
	end
	wake:SetScript("OnEvent", Try)
	for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED"}) do pcall(wake.RegisterEvent, wake, event) end
	wake:SetScript("OnUpdate", function(_, dt) elapsed = elapsed + dt; if elapsed >= 0.5 then elapsed = 0; Try() end end)
	if not deferred then Try() end
	return true
end
