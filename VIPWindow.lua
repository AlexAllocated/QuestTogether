local QT = _G.QuestTogether
local L = QT.Translate

local function Safe(a, frame)
	return not a:IsWorkBlocked("foreign_frame_mutation") and a:CanMutateOwnedUI(frame)
end
local function ParentSize(a, method)
	local parent = a:GetOwnedUIParent()
	if not a:CanAccessForeignFrame(parent) then return nil end
	local getter = a:GetAccessibleFrameMember(parent, method)
	if type(getter) ~= "function" then return nil end
	local ok, value = pcall(getter, parent)
	value = ok and a:SafeToNumber(value)
	return value and value > 0 and value or nil
end
function QT:RefreshVIPWindow()
	local frame = rawget(self, "vipWindow")
	if not frame or not Safe(self, frame) or not frame:IsShown() then return end
	frame.status:SetText(self:GetVIPStatus())
	frame.display:SetChecked(self:IsVIPDisplayEnabled())
	if frame.activate then
		frame.activate:SetEnabled(self.isEnabled == true and frame.activation:GetText():find("%S") ~= nil)
	end
	if frame.LayoutManagedWindow then frame:LayoutManagedWindow() end
end
function QT:OpenVIPWindow()
	if self:IsWorkBlocked("foreign_frame_mutation") then return false end
	local frame = rawget(self, "vipWindow")
	if not frame then
		frame = self:CreateScrollDialog(875, 775, L("QuestTogether VIP"))
		if not frame then return false end
		self.vipWindow = frame
		frame.logo:SetTexture(self.PLAYER_VIP_ICON_TEXTURE)
		frame.scroll = self:CreateOwnedWindowFrame("ScrollFrame", nil, frame)
		frame.scroll:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
		frame.scroll:EnableMouseWheel(true)
		frame.content = self:CreateOwnedWindowFrame("Frame", nil, frame.scroll)
		frame.scroll:SetScrollChild(frame.content)
		local function Scroll(value)
			if not Safe(self, frame) then return end
			frame.scrollOffset = self:UpdateOwnedScrollBar(frame.scrollBar, value,
				frame.scrollMaximum or 0, frame.scroll:GetHeight(), 36) or 0
			frame.scroll:SetVerticalScroll(frame.scrollOffset)
		end
		frame.scrollBar = self:CreateOwnedScrollBar(self.CreateOwnedWindowFrame, frame, false, Scroll)
		frame.scrollBar:SetPoint("TOPLEFT", frame.scroll, "TOPRIGHT", 8, 0)
		frame.scroll:SetScript("OnMouseWheel", function(_, delta)
			Scroll((frame.scrollOffset or 0) - (self:SafeToNumber(delta) or 0) * 36)
		end)
		local previous, gap = nil, 12
		local rows = {}
		local function Anchor(region, extra)
			region:SetPoint("TOPLEFT", previous or frame.content, previous and "BOTTOMLEFT" or "TOPLEFT",
				0, previous and -(extra or gap) or 0)
			previous = region
			rows[#rows + 1] = region
		end
		local labels, textRows = {}, {}
		local function Label(value, heading)
			local label = frame.content:CreateFontString(nil, "OVERLAY", heading and "GameFontNormal" or "GameFontHighlight")
			label:SetWidth(frame.contentWidth)
			label:SetJustifyH("LEFT")
			label:SetWordWrap(true)
			label:SetText(value)
			Anchor(label)
			self:AddScrollDialogLabel(frame, label, heading and "heading" or nil)
			labels[#labels + 1] = label
			textRows[label] = true
			return label
		end
		Label(L("Stand out with a class-colored star player marker, gold-star QT chat and minimap icons, and a VIP label on your player tooltip."))
		frame.cosmetics = frame.content:CreateTexture(nil, "ARTWORK")
		frame.cosmetics:SetSize(frame.contentWidth, frame.contentWidth * 420 / 800)
		frame.cosmetics:SetTexture("Interface\\AddOns\\QuestTogether\\Media\\ReleaseNotes\\VIPCosmetics")
		frame.cosmetics:SetTexCoord(0, 800 / 1024, 0, 420 / 512)
		Anchor(frame.cosmetics)
		Label(L("Earn VIP"), true)
		Label(L("1. Share the QuestTogether download link below with friends, your guild, a relevant Discord, or on social media.\n\n2. Take a screenshot of your sent message or published post. It must show the QuestTogether link and enough context to see where you shared it. You may crop unrelated conversations or personal details."))
		Label(L("3. Send that screenshot in a Discord DM to @chevcast for review. Join the QuestTogether Discord server or send @chevcast a friend request first so your DM can get through. After approval, use the activation steps below."))
		local function Field(value, editable, bytes)
			local box = self:CreateOwnedWindowFrame("EditBox", nil, frame.content)
			box:SetSize(frame.contentWidth, 28)
			box:SetFontObject("ChatFontNormal")
			box:SetAutoFocus(false)
			box:SetMaxBytes(bytes or 512)
			box:SetTextInsets(8, 8, 0, 0)
			local bg = box:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(0.5, 0.5, 0.5, 0.2)
			Anchor(box)
			box:SetText(value)
			box:SetScript("OnEscapePressed", function() if Safe(self, box) then box:ClearFocus() end end)
			box:SetScript("OnEditFocusGained", function()
				if Safe(self, box) then
					box:HighlightText()
					local top = box.vipContentTop
					if top then
						local offset, visible = frame.scrollOffset or 0, frame.scroll:GetHeight()
						if top < offset then Scroll(top)
						elseif top + box:GetHeight() > offset + visible then Scroll(top + box:GetHeight() - visible) end
					end
				end
			end)
			if not editable then
				box:SetScript("OnTextChanged", function(_, userInput)
					if userInput and Safe(self, box) then box:SetText(box.copyValue or value); box:HighlightText() end
				end)
			end
			self:AddScrollDialogLabel(frame, box)
			return box
		end
		Label(L("Download link to share (Ctrl+C)"), true)
		frame.shareLink = Field("https://www.curseforge.com/wow/addons/questtogether", false, 128)
		frame.username = Field("@chevcast", false, 64)
		Label(L("After approval"), true)
		Label(L("Wait for @chevcast to confirm that VIP has been granted to your Discord account. The /qt claim command in Discord only works after that grant.\n\nThen copy your claim code with Ctrl+C and send it to @chevcast, or use /qt claim in the QT Discord server. Paste the private activation code you receive below and choose Activate VIP. Repeat on Retail or Forever to use the same reward there."))
		Label(L("Your claim code"), true)
		frame.claim = Field("", false)
		Label(L("Activation code"), true)
		frame.activation = Field("", true)
		frame.activation:SetScript("OnTextChanged", function()
			self:RefreshVIPWindow()
		end)
		frame.activation:SetScript("OnEnterPressed", function()
			if Safe(self, frame.activation) and frame.activation:GetText():find("%S") then
				self:ImportVIPActivation(frame.activation:GetText())
				frame.activation:SetText("")
				frame.activation:ClearFocus()
			end
		end)
		frame.status = Label("")
		Label(L("Your reward is permanent and shared across characters in this installation. Profile resets do not remove it. You can claim again after reinstalling. Keep activation codes private."))
		frame.display = self:CreateOwnedWindowFrame("CheckButton", nil, frame.content, "UICheckButtonTemplate")
		frame.display:SetSize(26, 26)
		Anchor(frame.display)
		local displayText = frame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		displayText:SetJustifyH("LEFT")
		displayText:SetPoint("LEFT", frame.display, "RIGHT", 5, 0)
		displayText:SetText(L("Show my VIP cosmetics"))
		self:AddScrollDialogLabel(frame, displayText)
		displayText:SetWordWrap(true)
		frame.display:SetScript("OnClick", function(box)
			if Safe(self, box) then self:SetVIPDisplayEnabled(box:GetChecked() == true) end
		end)
		local function Button(label, offset, action)
			local button = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelButtonTemplate")
			button:SetSize(190, 26)
			button:SetPoint("BOTTOMLEFT", frame.contentInset + offset, frame.contentBottom)
			button:SetText(label)
			button:SetScript("OnClick", function() if Safe(self, frame) then action() end end)
			return button
		end
		frame.discord = Button(L("Join QT Discord"), 0, function() self:OpenDiscordSupport() end)
		frame.activate = Button(L("Activate VIP"), 200, function()
			frame.activation:GetScript("OnEnterPressed")()
		end)
		frame.close = Button(L("Close"), 400, function() self:DismissManagedWindow(frame) end)
		frame.LayoutManagedWindow = function()
			if frame.layingOut or not Safe(self, frame) then return end
			local screenWidth, screenHeight = ParentSize(self, "GetWidth"), ParentSize(self, "GetHeight")
			if not screenWidth or not screenHeight then return end
			frame.layingOut = true
			local scale = math.min(self:GetWindowScale(), screenWidth * .94 / 520, screenHeight * .94 / 320)
			local maximumWidth, maximumHeight = math.max(520, screenWidth * .94 / scale), math.max(320, screenHeight * .94 / scale)
			frame:SetResizeBounds(520, 320, maximumWidth, maximumHeight)
			frame:SetSize(math.max(520, math.min(frame:GetWidth(), maximumWidth)), math.max(320, math.min(frame:GetHeight(), maximumHeight)))
			frame:SetScale(scale)
			frame.title:SetWidth(frame:GetWidth() - 110)
			local width = frame:GetWidth() - frame.contentInset * 2 - 20
			frame.contentWidth = width
			frame.scroll:SetSize(width, math.max(1, frame:GetHeight() - frame.contentTop - frame.contentBottom - 40))
			frame.scrollBar:SetHeight(frame.scroll:GetHeight())
			frame.cosmetics:SetSize(width, width * 420 / 800)
			for _, label in ipairs(labels) do label:SetWidth(width) end
			for _, box in ipairs({ frame.shareLink, frame.username, frame.claim, frame.activation }) do box:SetWidth(width) end
			displayText:SetWidth(width - 31)
			local height = 0
			for index, row in ipairs(rows) do
				row.vipContentTop = height
				height = height + (textRows[row] and row:GetStringHeight() or row:GetHeight()) + (index < #rows and gap or 0)
			end
			height = height + math.max(0, displayText:GetStringHeight() - 26) + 8
			frame.content:SetSize(width, height)
			frame.scrollMaximum = math.max(0, height - frame.scroll:GetHeight())
			Scroll(frame.scrollOffset or 0)
			local buttonWidth = (frame:GetWidth() - frame.contentInset * 2 - 20) / 3
			for index, button in ipairs({ frame.discord, frame.activate, frame.close }) do
				button:ClearAllPoints()
				button:SetPoint("BOTTOMLEFT", frame.contentInset + (index - 1) * (buttonWidth + 10), frame.contentBottom)
				button:SetWidth(buttonWidth)
			end
			frame.layingOut = nil
		end
		frame:SetResizable(true)
		frame.resizeGrip = self:CreateOwnedWindowFrame("Button", nil, frame)
		frame.resizeGrip:SetSize(24, 24)
		frame.resizeGrip:SetPoint("BOTTOMRIGHT", -14, 12)
		frame.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		frame.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
		frame.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		frame.resizeGrip:SetScript("OnMouseDown", function(_, button)
			if button == "LeftButton" and Safe(self, frame) then
				frame.resizing = true
				frame:StartSizing("BOTTOMRIGHT", true)
			end
		end)
		frame.resizeGrip:SetScript("OnMouseUp", function() self:StopWindowInteraction(frame) end)
		frame:SetScript("OnSizeChanged", frame.LayoutManagedWindow)
		self:ConfigureWindowController(frame, { suspend = function()
			self:StopOwnedScrollBar(frame.scrollBar)
			for _, box in ipairs({ frame.shareLink, frame.username, frame.claim, frame.activation }) do
				if Safe(self, box) then box:ClearFocus() end
			end
			if Safe(self, frame.activation) then frame.activation:SetText("") end
		end })
	end
	if not self:ApplyScrollDialogTheme(frame) or not Safe(self, frame) then return false end
	frame.claim.copyValue = self:GetVIPClaimCode()
	frame.claim:SetText(frame.claim.copyValue)
	frame.activation:SetText("")
	frame:Show()
	self:RefreshVIPWindow()
	frame:LayoutManagedWindow()
	frame:Raise()
	return true
end
