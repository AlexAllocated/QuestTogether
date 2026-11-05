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

local function CreateFocusDialog(self, key, title, confirmLabel, remember)
	local frame = rawget(self, key)
	if not frame then
		frame = self:CreateScrollDialog(620, 300, title)
		if not frame then
			return false
		end
		self[key] = frame
		-- Focus confirmation must remain above the nearby Party Objective
		-- Tracker and its indicator tooltip; every region here is QT-owned.
		frame:SetFrameStrata("TOOLTIP")
		frame:SetFrameLevel(200)
		frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.message:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
		frame.message:SetWidth(frame.contentWidth)
		frame.message:SetJustifyH("LEFT")
		frame.message:SetWordWrap(true)
		self:AddScrollDialogLabel(frame, frame.message)
		self:ConfigureWindowController(frame, {
			dismiss = function()
				local cancel = frame.cancelAction
				frame.confirmAction, frame.cancelAction, frame.focusChoice = nil, nil, nil
				if cancel then cancel() end
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
		frame.confirm:SetText(confirmLabel)
		frame.confirm:SetScript("OnClick", function()
			if self:IsWorkBlocked("foreign_frame_mutation") then
				return
			end
			local action = frame.confirmAction
			local checked = frame.remember and frame.remember:GetChecked() == true
			-- Accepting is not cancellation. Clear the old identity before hiding,
			-- because the callback may synchronously open another choice.
			frame.confirmAction, frame.cancelAction, frame.focusChoice = nil, nil, nil
			Close()
			if action then
				action(checked)
			end
		end)
		if remember then
			frame.remember = self:CreateOwnedWindowFrame("CheckButton", nil, frame, "MinimalCheckboxTemplate")
			frame.remember:SetSize(26, 26)
			frame.remember:SetPoint("BOTTOMLEFT", frame.contentInset, frame.contentBottom + 42)
			frame.remember.label = frame.remember:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			frame.remember.label:SetPoint("LEFT", frame.remember, "RIGHT", 6, 0)
			frame.remember.label:SetWidth(frame.contentWidth - 32)
			frame.remember.label:SetJustifyH("LEFT")
			frame.remember.label:SetWordWrap(true)
			frame.remember.label:SetText(L("Do not ask again"))
			self:AddScrollDialogLabel(frame, frame.remember.label)
		end
		frame.LayoutManagedWindow = function()
			frame.message:SetHeight(frame.message:GetStringHeight())
			local extra = frame.remember and math.max(26, frame.remember.label:GetStringHeight()) + 16 or 0
			frame:SetHeight(
				math.max(260, frame.contentTop + frame.message:GetStringHeight() + frame.contentBottom + 54 + extra)
			)
			self:FitScrollDialog(frame)
		end
	end
	return frame
end

local function SetFocusDialogChoice(self, frame, callback, cancel)
	if not frame or not self.LibChev.CanMutateOwnedRegion(frame) then return false end
	local choice, previousCancel = {}, frame.cancelAction
	frame.confirmAction, frame.cancelAction, frame.focusChoice = nil, nil, choice
	if previousCancel then previousCancel() end
	-- A retiring callback may itself have shown or dismissed a successor.
	if frame.focusChoice ~= choice then return false end
	frame.confirmAction, frame.cancelAction = callback, cancel
	return true
end

-- The warning is also used by the isolated compare controller. Preview callbacks
-- can only change that controller, never the live party navigation model.
function QuestTogether:ShowPartyFocusChangeDialog(name, callback, preview, liveNavigation, cancel)
	if self:IsWorkBlocked("foreign_frame_mutation") then return false end
	local key = preview and "partyFocusChangePreview" or "partyFocusChangeDialog"
	local frame = CreateFocusDialog(self, key, L("Stop following quest focus?"), L("Change focus"))
	if not SetFocusDialogChoice(self, frame, callback, cancel) then return false end
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

function QuestTogether:ShowPartyFocusFollowDialog(name, callback, cancel)
	if self:IsWorkBlocked("foreign_frame_mutation") then return false end
	local frame = CreateFocusDialog(self, "partyFocusFollowDialog", L("Follow quest focus?"), L("Follow quest focus"), true)
	if not SetFocusDialogChoice(self, frame, callback, cancel) then return false end
	frame.remember:SetChecked(false)
	frame.message:SetText(string.format(L("Follow %s's selected quests automatically when they are in your quest log. If you do not share their selected quest, following will wait for a shared quest."), name))
	frame:LayoutManagedWindow()
	self:ApplyScrollDialogTheme(frame)
	frame:Show()
	frame:Raise()
	return true
end

-- Clickable focus indicators request consent without changing the existing
-- direct context-menu action. Delayed choices belong to one profile/lifetime
-- and cannot replace a follow decision made while the dialog was open.
function QuestTogether:RequestPartyQuestFocusFollow(name)
	if not self:CanAccessValue(name) or type(name) ~= "string" then return false end
	name = self:NormalizeMemberName(name)
	local function Eligible()
		if not name or not self.isEnabled or self.isLoggingOut
			or self:IsWorkBlocked("foreign_frame_mutation") or self:IsRuntimeRestricted()
			or self:IsSelfSender(name) or not self:IsGroupedSender(name) or self:IsIgnoredPlayerName(name)
			or self:WouldPartyQuestFollowCycle(name) then return false end
		local peer = self:GetPartyNavigationPeer(name)
		return peer and type(peer.questID) == "number" and peer.questID > 0
	end
	if not Eligible() or not self.db or type(self.db.profile) ~= "table" then return false end
	local function NativeFocus()
		local getter = self.API and self.API.GetActiveTrackedQuestID
		if type(getter) ~= "function" then return nil end
		local ok, value = pcall(getter)
		if not ok or not self:CanAccessValue(value) then return nil end
		local id = value == nil and 0 or self:SafeToNumber(value)
		return id and id >= 0 and id <= 1000000000 and id == math.floor(id) and id or nil
	end
	local nativeFocus = NativeFocus()
	if nativeFocus == nil then return false end
	local profile, profileKey = self.db.profile, self.activeProfileKey
	local lifetime, state = self:GetDeferredWorkStateStore(), rawget(self, "partyNavigationState")
	local following, followToken = state and state.following, state and state.followToken
	local controller = self:GetPartyFocusController()
	local choice = controller.choice
	local request = {}
	self.partyFocusFollowRequest = request
	local function NativeChoiceCurrent()
		local current = NativeFocus()
		if current == nil then return false end
		if current == nativeFocus then return true end
		-- Continuing the same follow may advance native focus without a new
		-- user choice. Only accept the controller's settled applied destination;
		-- an unprocessed manual selection or waiting/resuming follow cannot qualify.
		return following ~= nil and not state.checkExternal and not state.waiting and not state.resuming
			and current == state.expectedQuest
	end
	local function Current()
		return self.partyFocusFollowRequest == request and self.db and self.db.profile == profile
			and self.activeProfileKey == profileKey and self:GetDeferredWorkStateStore() == lifetime
			and rawget(self, "partyNavigationState") == state
			and state.following == following and state.followToken == followToken
			and rawget(self, "partyFocusController") == controller and controller:IsActive()
			and controller.choice == choice and Eligible() and NativeChoiceCurrent()
	end
	local function Cancel()
		if self.partyFocusFollowRequest == request then self.partyFocusFollowRequest = nil end
	end
	local function Accept(remember)
		if not Current() then Cancel(); return false end
		Cancel()
		if not self:FollowPartyQuestFocus(name) then return false end
		if remember == true and self.db.profile == profile and self.activeProfileKey == profileKey then
			self:SetOption("skipPartyFocusFollowConfirmation", true)
		end
		return true
	end
	if profile.skipPartyFocusFollowConfirmation == true then
		local previous = rawget(self, "partyFocusFollowDialog")
		if previous then self:DismissManagedWindow(previous, "replace") end
		return Accept(false)
	end
	if not self:ShowPartyFocusFollowDialog(name, Accept, Cancel) then Cancel(); return false end
	return true
end

function QuestTogether:CancelPartyQuestFocusFollowRequest()
	self.partyFocusFollowRequest = nil
	local frame = rawget(self, "partyFocusFollowDialog")
	if frame then self:DismissManagedWindow(frame, "profile") end
end
