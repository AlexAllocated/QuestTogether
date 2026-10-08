local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate

function QuestTogether:ShowDiscordLinkDialog(url)
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return false
	end
	local frame = rawget(self, "discordLinkDialog")
	if not frame then
		frame = self:CreateScrollDialog(660, 280, L("QuestTogether Discord — Feedback & Support"))
		if not frame then
			return false
		end
		self.discordLinkDialog = frame
		local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		hint:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
		hint:SetWidth(frame.contentWidth)
		hint:SetText(L("Press Ctrl+C to copy this address, then open it in your browser."))
		self:AddScrollDialogLabel(frame, hint)
		frame.box = self:CreateOwnedWindowFrame("EditBox", nil, frame)
		frame.box:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -20)
		frame.box:SetSize(frame.contentWidth, 32)
		frame.LayoutManagedWindow = function()
			frame:SetHeight(frame.contentTop + hint:GetStringHeight() + 20 + 32 + 24 + 24 + frame.contentBottom)
			self:FitScrollDialog(frame)
		end
		frame:LayoutManagedWindow()
		frame.box:SetAutoFocus(false)
		frame.box:SetFontObject("ChatFontNormal")
		frame.box:SetTextInsets(8, 8, 4, 4)
		self:AddScrollDialogLabel(frame, frame.box)
		local field = frame.box:CreateTexture(nil, "BACKGROUND")
		field:SetAllPoints()
		field:SetColorTexture(0.5, 0.5, 0.5, 0.18)
		local function Close()
			self:DismissManagedWindow(frame)
		end
		frame.box:SetScript("OnEscapePressed", Close)
		frame.box:SetScript("OnEditFocusGained", function(box)
			if not self:IsWorkBlocked("foreign_frame_mutation") and self.LibChev.CanMutateOwnedRegion(box) then
				box:HighlightText()
			end
		end)
		frame.box:SetScript("OnTextChanged", function(box, userInput)
			if
				self:CanAccessValue(userInput)
				and userInput == true
				and not self:IsWorkBlocked("foreign_frame_mutation")
				and self.LibChev.CanMutateOwnedRegion(box)
			then
				box:SetText(frame.url)
				box:HighlightText()
			end
		end)
		self:ConfigureWindowController(frame, {
			suspend = function()
				if self.LibChev.CanMutateOwnedRegion(frame.box) then
					frame.box:ClearFocus()
				end
			end,
		})
		frame.close = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.close:SetPoint("BOTTOMRIGHT", -frame.contentInset, frame.contentBottom)
		frame.close:SetSize(110, 24)
		frame.close:SetText(L("Close"))
		frame.close:SetScript("OnClick", Close)
	end
	if not self:ApplyScrollDialogTheme(frame) or not self.LibChev.CanMutateOwnedRegion(frame.box) then
		return false
	end
	frame.url = url
	frame.box:SetText(url)
	frame:Show()
	frame:Raise()
	frame.box:SetFocus()
	frame.box:HighlightText()
	return true
end

function QuestTogether:ShowDialogPreview(kind)
	if self:IsWorkBlocked("foreign_frame_mutation") then
		self:Print(L("Dialog previews are unavailable while UI restrictions are active."))
		return false
	end
	if kind == "unfollow" then
		return self:ShowPartyFocusChangeDialog(L("Example Player"), function() end, true)
	end
	if kind == "focus" then
		return self:ShowPartyFocusMissingDialog(
			{ name = L("Example Player"), questID = 1, title = L("Example Quest") },
			true
		)
	end
	if kind == "partychat" then
		return self:ShowPartyChatReminderPreview()
	end
	if kind == "discord" then
		return self:OpenDiscordSupport()
	end
	if kind == "bubble" then
		return self:ShowPersonalBubbleSettingsPreview()
	end
	local frame
	if kind == "share" then
		frame = self:CreatePartyQuestSharePrompt(true)
		if not frame then
			return false
		end
		frame.always:SetChecked(false)
		frame.message:SetText(
			string.format(
				L("%s would like you to share\n[%s]\nwith the party."),
				L("Example Player"),
				L("Example Quest")
			)
		)
	elseif kind == "join" then
		frame = self:CreatePartyJoinPrompt(true)
		if not frame then
			return false
		end
		frame.friends:SetChecked(false)
		frame.lfg:SetChecked(false)
		frame.message:SetText(L("Example Player") .. L(" would like to join your party.\nSend an invitation?"))
	else
		self:PrintPreviewHelp()
		return false
	end
	frame:LayoutRequest()
	self:ApplyScrollDialogTheme(frame)
	frame:Show()
	return true
end

function QuestTogether:ClearPartyFocusMissingNotice()
	self.partyFocusMissingNotice = nil
	local frame = rawget(self, "partyFocusMissingDialog")
	if frame and self.LibChev.CanMutateOwnedRegion(frame) then
		frame:Hide()
	end
end

function QuestTogether:QueuePartyFocusMissingNotice(name, questID, title)
	local notice = { name = name, questID = questID, title = title }
	self.partyFocusMissingNotice = notice
	self:ScheduleDeferredWork("foreign_frame_mutation", "party_focus_missing", function()
		if self.isEnabled and rawget(self, "partyFocusMissingNotice") == notice then
			self:ShowPartyFocusMissingDialog(notice)
		end
	end, 0, "party focus missing quest")
end

function QuestTogether:ShowPartyFocusMissingDialog(notice, preview)
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return false
	end
	local key = preview and "partyFocusMissingPreview" or "partyFocusMissingDialog"
	local frame = rawget(self, key)
	if not frame then
		frame = self:CreateScrollDialog(650, 310, L("Quest following stopped"))
		if not frame then
			return false
		end
		self[key] = frame
		frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.message:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
		frame.message:SetWidth(frame.contentWidth)
		frame.message:SetJustifyH("LEFT")
		frame.message:SetWordWrap(true)
		self:AddScrollDialogLabel(frame, frame.message)
		self:ConfigureWindowController(frame, {
			dismiss = function()
				if not preview then
					self.partyFocusMissingNotice = nil
				end
			end,
		})
		local function Close()
			self:DismissManagedWindow(frame)
		end
		frame.escapeAction = Close
		frame.close = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelCloseButton")
		frame.close:SetPoint("TOPRIGHT", -12, -8)
		frame.close:SetScript("OnClick", Close)
		frame.open = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.open:SetSize(240, 26)
		frame.open:SetPoint("BOTTOMRIGHT", -frame.contentInset, frame.contentBottom)
		frame.open:SetText(L("Open Party Quest Log"))
		frame.open:SetScript("OnClick", function()
			if self:IsWorkBlocked("foreign_frame_mutation") then
				return
			end
			if preview then
				self:OpenPartyQuestComparePreview()
			else
				self:OpenPartyQuestCompare()
			end
			Close()
		end)
		frame.LayoutManagedWindow = function()
			frame.message:SetHeight(frame.message:GetStringHeight())
			frame:SetHeight(
				math.max(280, frame.contentTop + frame.message:GetStringHeight() + frame.contentBottom + 54)
			)
			self:FitScrollDialog(frame)
		end
	end
	if not self.LibChev.CanMutateOwnedRegion(frame) or not self.LibChev.CanMutateOwnedRegion(frame.message) then
		return false
	end
	local title = preview and notice.title
		or self:GetLocalizedQuestTitle(notice.questID)
		or (notice.title and notice.title ~= "" and notice.title)
		or self:GetQuestTitle(notice.questID)
	frame.message:SetText(
		string.format(
			L(
				"%s is tracking %s, which you don't have. Following has stopped. Your current navigation is unchanged.\n\nOpen Party Quest Log to request the quest, then follow this player again."
			),
			notice.name,
			title
		) .. (preview and ("\n\n" .. L("Preview - no settings will change.")) or "")
	)
	frame:LayoutManagedWindow()
	self:ApplyScrollDialogTheme(frame)
	frame:Show()
	frame:Raise()
	return true
end

-- The warning is also used by the isolated compare controller. Preview callbacks
-- can only change that controller, never the live party navigation model.
function QuestTogether:ShowPartyFocusChangeDialog(name, callback, preview, liveNavigation)
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return false
	end
	local key = preview and "partyFocusChangePreview" or "partyFocusChangeDialog"
	local frame = rawget(self, key)
	if not frame then
		frame = self:CreateScrollDialog(620, 300, L("Stop following quest focus?"))
		if not frame then
			return false
		end
		self[key] = frame
		frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.message:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
		frame.message:SetWidth(frame.contentWidth)
		frame.message:SetJustifyH("LEFT")
		frame.message:SetWordWrap(true)
		self:AddScrollDialogLabel(frame, frame.message)
		self:ConfigureWindowController(frame, {
			dismiss = function()
				frame.confirmAction = nil
			end,
		})
		local function Close()
			self:DismissManagedWindow(frame)
		end
		frame.escapeAction = Close
		frame.close = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelCloseButton")
		frame.close:SetPoint("TOPRIGHT", -12, -8)
		frame.close:SetScript("OnClick", Close)
		frame.cancel = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.cancel:SetSize(160, 26)
		frame.cancel:SetPoint("BOTTOMLEFT", frame.contentInset, frame.contentBottom)
		frame.cancel:SetText(L("Cancel"))
		frame.cancel:SetScript("OnClick", Close)
		frame.confirm = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.confirm:SetSize(220, 26)
		frame.confirm:SetPoint("BOTTOMRIGHT", -frame.contentInset, frame.contentBottom)
		frame.confirm:SetText(L("Change focus"))
		frame.confirm:SetScript("OnClick", function()
			if self:IsWorkBlocked("foreign_frame_mutation") then
				return
			end
			local action = frame.confirmAction
			Close()
			if action then
				action()
			end
		end)
		frame.LayoutManagedWindow = function()
			frame.message:SetHeight(frame.message:GetStringHeight())
			frame:SetHeight(
				math.max(260, frame.contentTop + frame.message:GetStringHeight() + frame.contentBottom + 54)
			)
			self:FitScrollDialog(frame)
		end
	end
	if not self.LibChev.CanMutateOwnedRegion(frame) then
		return false
	end
	frame.confirmAction = callback
	frame.message:SetText(
		string.format(L("Changing focus will stop following %s. Continue?"), name)
			.. (
				preview
					and ("\n\n" .. (liveNavigation and L("Preview - quest focus changes affect your navigation.") or L(
						"Preview - no settings will change."
					)))
				or ""
			)
	)
	frame:LayoutManagedWindow()
	self:ApplyScrollDialogTheme(frame)
	frame:Show()
	frame:Raise()
	return true
end
