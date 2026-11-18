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
		frame = self:CreateScrollDialog(720, 620, L("Welcome to QuestTogether"))
		if not frame then return false end
		self.presetWindow = frame
		local function Label(parent, font, text)
			local label = parent:CreateFontString(nil, "OVERLAY", font)
			label:SetJustifyH("LEFT"); label:SetWordWrap(true); label:SetText(text)
			self:AddScrollDialogLabel(frame, label)
			return label
		end
		frame.intro = Label(frame, "GameFontHighlight", L("Choose how much QuestTogether you want to see. Every choice is a set of ordinary settings you can change later."))
		frame.intro:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
		frame.intro:SetWidth(frame.contentWidth)
		frame.cards = {}
		for index, preset in ipairs(self:GetPresetDefinitions()) do
			local card = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Button", frame)
			card.id, card.baseTitle = preset.id, preset.title
			card:SetWidth(frame.contentWidth)
			card.fill = card:CreateTexture(nil, "BACKGROUND"); card.fill:SetAllPoints()
			card:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			card.title = Label(card, "GameFontNormal", preset.title)
			card:SetFontString(card.title)
			card.title:SetPoint("TOPLEFT", 18, -10); card.title:SetWidth(frame.contentWidth - 36)
			card.description = Label(card, "GameFontHighlight", preset.description)
			card.description:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
			card.description:SetWidth(frame.contentWidth - 36)
			card:SetScript("OnClick", function()
				if Ready(self, frame) then frame.selected = card.id; frame:LayoutManagedWindow() end
			end)
			frame.cards[index] = card
		end
		frame.future = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "CheckButton", frame, "UICheckButtonTemplate")
		frame.future:SetSize(26, 26)
		frame.future.label = Label(frame.future, "GameFontHighlight", L("Use this preset for new characters"))
		frame.future.label:SetPoint("LEFT", frame.future, "RIGHT", 4, 0)
		frame.future.label:SetWidth(frame.contentWidth - 40)
		frame.hint = Label(frame, "GameFontHighlightSmall", L("Only feature settings change. Layouts, bindings and personal data stay yours. Open WoW Options > AddOns > QuestTogether to customize or change presets."))
		frame.hint:SetWidth(frame.contentWidth)
		frame.close = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Button", frame, "UIPanelCloseButton")
		frame.close:SetPoint("TOPRIGHT", -16, -7); frame.close:SetSize(26, 26)
		frame.close:SetScript("OnClick", function() self:ClosePresetWindow() end)
		frame.apply = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Button", frame, "UIPanelButtonTemplate")
		frame.apply:SetPoint("BOTTOMRIGHT", -frame.contentInset, frame.contentBottom - 28)
		frame.apply:SetSize(240, 28)
		frame.apply:SetScript("OnClick", function()
			if Ready(self, frame) and self:ApplyPreset(frame.selected, frame.future:GetChecked() == true) then
				self:ClosePresetWindow(true)
			end
		end)
		frame.LayoutManagedWindow = function()
			if not self:CanMutateOwnedUI(frame) then return end
			local y = frame.contentTop + frame.intro:GetStringHeight() + 16
			for _, card in ipairs(frame.cards) do
				local height = math.max(64, card.title:GetStringHeight() + card.description:GetStringHeight() + 25)
				card:SetPoint("TOPLEFT", frame.contentInset, -y); card:SetHeight(height)
				card.fill:SetColorTexture(0.72, 0.55, 0.18, card.id == frame.selected and 0.32 or 0.08)
				card.title:SetText((card.id == frame.selected and "|TInterface\\Buttons\\UI-CheckBox-Check:14|t " or "") .. card.baseTitle)
				y = y + height + 8
			end
			frame.future:SetPoint("TOPLEFT", frame.contentInset, -y)
			y = y + math.max(32, frame.future.label:GetStringHeight() + 8)
			frame.hint:SetPoint("TOPLEFT", frame.contentInset, -y)
			frame:SetHeight(y + frame.hint:GetStringHeight() + frame.contentBottom + 20)
			self:FitScrollDialog(frame); self:ApplyScrollDialogTheme(frame)
		end
		self:GuardGamepadWindowActions(frame, {frame.apply, frame.future, unpack(frame.cards)})
		local inherited = frame:GetScript("OnKeyDown")
		frame:SetScript("OnKeyDown", function(_, key)
			if not Ready(self, frame) or (self.API.IsPartyQuestKeyboardInputBlocked and self.API.IsPartyQuestKeyboardInputBlocked(frame)) then return end
			frame:SetPropagateKeyboardInput(true)
			if key == "ESCAPE" then if inherited then inherited(frame, key) end; return end
			local index = 1
			for i, card in ipairs(frame.cards) do if card.id == frame.selected then index = i; break end end
			if key == "UP" or key == "DOWN" or key == "LEFT" or key == "RIGHT" then
				index = math.max(1, math.min(#frame.cards, index + ((key == "UP" or key == "LEFT") and -1 or 1)))
				frame.selected = frame.cards[index].id; frame:LayoutManagedWindow()
			elseif key == "SPACE" then frame.future:SetChecked(not frame.future:GetChecked())
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
	frame.profile, frame.finishDefault = self.db.profile, nil
	frame.selected = self:IsWelcomeSetupPending() and "full" or self:GetMatchingPreset() or "full"
	frame.future:SetChecked(self:IsWelcomeSetupPending())
	frame.apply:SetText(self:IsWelcomeSetupPending() and L("Start questing") or L("Apply preset"))
	frame:LayoutManagedWindow(); frame:Show(); frame:Raise()
	self:PresentStandardGamepadWindow(frame, "welcome", function() self:ClosePresetWindow() end,
		frame.cards[1], nil, self:IsWelcomeSetupPending() and "automatic" or "user")
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
