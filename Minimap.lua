local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether
local ICON = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon"
local DEFAULT_ANGLE = 225

-- All state and scripts belong to our own frames. Minimap is only a guarded
-- parent/anchor; do not hook its scripts or add fields to Blizzard frames.
function QuestTogether:GetMinimapAnchor()
	return self.API.GetMinimapAnchor and self.API.GetMinimapAnchor() or nil
end

function QuestTogether:IsMinimapShiftKeyDown()
	if self:IsRuntimeRestricted() or not self:CanAccessValue(IsShiftKeyDown)
		or type(IsShiftKeyDown) ~= "function" then return false end
	local ok, down = pcall(IsShiftKeyDown)
	return ok and self:CanAccessValue(down) and down == true
end

function QuestTogether:BuildMinimapTooltipStatus()
	local function OnOff(key)
		return self:GetOption(key) and "|cff66dd88" .. L("On") .. "|r" or "|cffaaaaaa" .. L("Off") .. "|r"
	end
	local count
	if not self:IsRuntimeRestricted() and self.API.GetTrackedQuestCount then
		local ok, value = pcall(self.API.GetTrackedQuestCount)
		count = ok and self:SafeToNumber(value) or nil
		if count and (count < 0 or count > 20000 or count ~= math.floor(count)) then count = nil end
	end
	local scope = self:GetOption("showQTChat") == false and L("Off")
		or self:GetOption("qtChatScope") == "zone_only" and L("Zone Only") or L("Global")
	local lines = {
		L("QT Version") .. ": " .. self:SafeTrimString(self:GetAddonVersion(), L("Unknown")):gsub("|", "||"),
		L("Looking for Questing Partners") .. ": " .. OnOff("lookingForQuestPartners"),
		L("QT Chat Scope") .. ": " .. scope,
		L("Tracked quests") .. ": " .. (count and tostring(count) or L("Unknown")),
		string.format(L("Nearby Range: %d%% of zone"), self:GetNearbyAnnouncementRange()),
		L("Share my location") .. ": " .. OnOff("sharePlayerLocation"),
	}
	if not self.isEnabled then table.insert(lines, 1, "|cffffaa66" .. L("QuestTogether disabled.") .. "|r") end
	return table.concat(lines, "\n") .. "\n\n|cffaaaaaa" .. L("Left or right click for menu\nShift-click to toggle looking for partners\nDrag to move") .. "|r"
end

function QuestTogether:RefreshMinimapTooltipStatus()
	local tooltip = rawget(self, "minimapTooltip")
	if self:IsRuntimeRestricted() or not self.LibChev.CanMutateOwnedRegion(tooltip)
		or not self.LibChev.CanMutateOwnedRegion(tooltip.qtStatus) then return end
	tooltip.qtStatus:SetText(self:BuildMinimapTooltipStatus())
	local height = self:SafeToNumber(tooltip.qtStatus:GetStringHeight())
	if height and height > 0 then tooltip:SetSize(310, height + 42) end
end

function QuestTogether:CreateMinimapUIFrame(...)
	return CreateFrame(...)
end

function QuestTogether:GetMinimapCursorPosition()
	if type(GetCursorPosition) ~= "function" then
		return nil
	end
	local ok, x, y = pcall(GetCursorPosition)
	if ok then
		return self:SafeToNumber(x), self:SafeToNumber(y)
	end
end

function QuestTogether:GetMinimapShapeName()
	if type(GetMinimapShape) == "function" then
		local ok, shape = pcall(GetMinimapShape)
		if ok then
			return self:SafeTrimString(shape, "ROUND")
		end
	end
	return "ROUND"
end

local function ReadNumbers(addon, frame, methodName)
	local method = addon:GetAccessibleFrameMember(frame, methodName)
	if type(method) ~= "function" then
		return nil
	end
	local ok, first, second = pcall(method, frame)
	if ok then
		return addon:SafeToNumber(first), addon:SafeToNumber(second)
	end
end

function QuestTogether:GetMinimapButtonOffset(angle, width, height, shape)
	angle = self:SafeToNumber(angle) or DEFAULT_ANGLE
	width, height = self:SafeToNumber(width), self:SafeToNumber(height)
	if not width or not height or width <= 0 or height <= 0 then
		return nil
	end
	local x, y = math.cos(math.rad(angle % 360)), math.sin(math.rad(angle % 360))
	if shape == "SQUARE" then
		local edge = math.max(math.abs(x), math.abs(y))
		x, y = x / edge, y / edge
	end
	return x * (width / 2 + 8), y * (height / 2 + 8)
end

function QuestTogether:PositionMinimapButton(angle)
	local button = rawget(self, "minimapButton")
	local anchor = self:GetMinimapAnchor()
	if
		not button
		or self:IsRuntimeRestricted()
		or not self:CanAccessForeignFrame(anchor)
		or not self:CanAccessForeignFrame(button)
	then
		return false
	end
	local width = ReadNumbers(self, anchor, "GetWidth")
	local height = ReadNumbers(self, anchor, "GetHeight")
	local x, y = self:GetMinimapButtonOffset(
		angle or self:GetOption("minimapButtonPosition"),
		width,
		height,
		self:GetMinimapShapeName()
	)
	if not x then
		return false
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", anchor, "CENTER", x, y)
	return true
end

function QuestTogether:OpenQuestJournalFromMinimap()
	if self:IsRuntimeRestricted() then
		self:Print(L("Opening the quest journal is unavailable while restricted."))
		return false
	end
	if
		not self.API.CanOpenQuestJournalWindow
		or self.API.CanOpenQuestJournalWindow() ~= true
		or not self.API.OpenQuestJournalWindow
		or self.API.OpenQuestJournalWindow() ~= true
	then
		self:Print(L("Unable to open your quest journal on this client."))
		return false
	end
	return true
end

function QuestTogether:PopulateMinimapMenu(rootDescription)
	rootDescription:CreateButton(L("Settings"), function()
		if not self:IsRuntimeRestricted() then
			self:OpenOptionsWindow()
		end
	end)
	local compare = rootDescription:CreateButton(L("Compare Party Quests"), function()
		if self.isEnabled and not self:IsRuntimeRestricted() then
			self:OpenPartyQuestCompare()
		end
	end)
	compare:SetEnabled(self.isEnabled == true)
	local journal = rootDescription:CreateButton(L("Open Quest Journal"), function()
		self:OpenQuestJournalFromMinimap()
	end)
	journal:SetEnabled(self.API.CanOpenQuestJournalWindow and self.API.CanOpenQuestJournalWindow() == true or false)
	rootDescription:CreateButton(L("Patch Notes"), function()
		if not self:IsRuntimeRestricted() then
			self:OpenReleaseNotes()
		end
	end)
	rootDescription:CreateCheckbox(L("Looking for Questing Partners"), function()
		return self:GetOption("lookingForQuestPartners") == true
	end, function()
		if not self:IsRuntimeRestricted() then self:HandleQuestPartnerCommand("toggle") end
	end)
	local chat = rootDescription:CreateButton(L("Send QT chat message"), function()
		if self.isEnabled and not self:IsRuntimeRestricted() and self.API.OpenQTChatComposer then
			self.API.OpenQTChatComposer()
		end
	end)
	chat:SetEnabled(self.isEnabled == true and type(self.API.OpenQTChatComposer) == "function")
	self:PopulateChatLogDestinationMenu(rootDescription)
	rootDescription:CreateButton(L("Hide Minimap Icon"), function()
		if self:IsRuntimeRestricted() then
			return
		end
		if self:SetOption("showMinimapButton", false) then
			self:RefreshOptionsWindow()
			self:Print(
				L("Minimap icon hidden. Re-enable it in Settings > General > Show minimap icon (/qt options).")
			)
		end
	end)
end

function QuestTogether:ShowMinimapMenu(button)
	if self:IsRuntimeRestricted() or not self:CanAccessForeignFrame(button) then
		return false
	end
	if not self.API.CreateContextMenu then
		return false
	end
	return self.API.CreateContextMenu(button, function(_, rootDescription)
		self:PopulateMinimapMenu(rootDescription)
	end) == true
end

function QuestTogether:GetMinimapTooltipParent()
	return UIParent
end

local function IsTooltipAnchorVisible(addon, frame)
	local isVisible = addon:GetAccessibleFrameMember(frame, "IsVisible")
	if type(isVisible) ~= "function" then
		return false
	end
	local ok, visible = pcall(isVisible, frame)
	return ok and addon:CanAccessValue(visible) and visible == true
end

local function CanShowMinimapTooltip(addon, button)
	return not addon:IsRuntimeRestricted()
		and not rawget(addon, "minimapDragState")
		and addon:GetOption("showMinimapButton") ~= false
		and IsTooltipAnchorVisible(addon, button)
end

function QuestTogether:HideMinimapTooltip()
	local tooltip = rawget(self, "minimapTooltip")
	self.minimapTooltipPendingHide = tooltip and true or nil
	if self.LibChev.CanMutateOwnedRegion(tooltip) then
		tooltip:SetScript("OnUpdate", nil)
		tooltip:Hide()
		self.minimapTooltipPendingHide = nil
	end
end

function QuestTogether:ShowMinimapTooltip(button)
	if not CanShowMinimapTooltip(self, button) then
		self:HideMinimapTooltip()
		return
	end
	local tooltip = rawget(self, "minimapTooltip")
	if tooltip and not self.LibChev.CanMutateOwnedRegion(tooltip) then
		return
	end
	if not tooltip then
		local parent = self:GetMinimapTooltipParent()
		if not IsTooltipAnchorVisible(self, parent) then
			return
		end
		-- Keep the tooltip outside the minimap's render hierarchy. The button is
		-- only an anchor, so minimap layers cannot place it behind other UI.
		tooltip = self:CreateMinimapUIFrame("Frame", nil, parent, "BackdropTemplate")
		if not self.LibChev.CanMutateOwnedRegion(tooltip) then
			return
		end
		tooltip:Hide()
		tooltip:SetFrameStrata("TOOLTIP")
		tooltip:SetFrameLevel(100)
		tooltip:SetClampedToScreen(true)
		tooltip:SetSize(310, 200)
		tooltip:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
		})
		tooltip:SetBackdropColor(0.04, 0.05, 0.07, 0.95)
		local title = tooltip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 10, -10)
		title:SetText("QuestTogether")
		local hint = tooltip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tooltip.qtStatus = hint
		hint:SetPoint("TOPLEFT", 10, -28)
		hint:SetWidth(290)
		hint:SetJustifyH("LEFT")
		hint:SetWordWrap(true)
		hint:SetSpacing(3)
		self.minimapTooltip = tooltip
	end
	self:RefreshMinimapTooltipStatus()
	tooltip:ClearAllPoints()
	tooltip:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 0, -4)
	-- An independent parent no longer hides this frame when the minimap hides
	-- or becomes quarantined. Check that boundary only while the tooltip is up.
	local elapsedSinceCheck = 0
	local elapsedSinceStatus = 0
	tooltip:SetScript("OnUpdate", function(_, elapsed)
		elapsedSinceCheck = elapsedSinceCheck + elapsed
		elapsedSinceStatus = elapsedSinceStatus + elapsed
		if elapsedSinceCheck < 0.1 then
			return
		end
		elapsedSinceCheck = 0
		if rawget(self, "minimapTooltipPendingHide") or not CanShowMinimapTooltip(self, button) then
			self:HideMinimapTooltip()
		elseif elapsedSinceStatus >= 1 then
			elapsedSinceStatus = 0
			self:RefreshMinimapTooltipStatus()
		end
	end)
	self.minimapTooltipPendingHide = nil
	tooltip:Show()
end

function QuestTogether:StopMinimapButtonDrag(cancelled)
	local button = rawget(self, "minimapButton")
	local state = rawget(self, "minimapDragState")
	self.minimapDragState = nil
	-- A foreign parent can quarantine our child too. Cancel the owned state
	-- even when removing the script must wait until the button is accessible.
	if self:CanAccessForeignFrame(button) then
		button:SetScript("OnUpdate", nil)
	end
	if
		not cancelled
		and state
		and self.db
		and self.db.profile == state.profile
		and state.angle
		and not self:IsRuntimeRestricted()
		and self:CanAccessForeignFrame(button)
		and self:CanAccessForeignFrame(self:GetMinimapAnchor())
	then
		self:SetOption("minimapButtonPosition", state.angle)
	end
end

function QuestTogether:UpdateMinimapButtonDrag()
	local button = rawget(self, "minimapButton")
	local state = rawget(self, "minimapDragState")
	if not state then
		if self:CanAccessForeignFrame(button) then
			button:SetScript("OnUpdate", nil)
		end
		return
	end
	local anchor = self:GetMinimapAnchor()
	if
		self:IsRuntimeRestricted()
		or not self:CanAccessForeignFrame(button)
		or not self.db
		or self.db.profile ~= state.profile
		or self:GetOption("showMinimapButton") == false
		or not self:CanAccessForeignFrame(anchor)
	then
		self:StopMinimapButtonDrag(true)
		return
	end
	local cx, cy = ReadNumbers(self, anchor, "GetCenter")
	local scale = ReadNumbers(self, anchor, "GetEffectiveScale")
	local px, py = self:GetMinimapCursorPosition()
	px, py = self:SafeToNumber(px), self:SafeToNumber(py)
	if not cx or not cy or not scale or scale <= 0 or not px or not py then
		self:StopMinimapButtonDrag(true)
		return
	end
	local dx, dy = px / scale - cx, py / scale - cy
	if dx == 0 and dy == 0 then
		return
	end
	-- Lua 5.1/5.2 and the clients differ in atan2 availability.
	local angle
	if dx == 0 then
		angle = dy > 0 and math.pi / 2 or -math.pi / 2
	else
		angle = math.atan(dy / dx)
		if dx < 0 then
			angle = angle + math.pi
		end
	end
	angle = math.deg(angle) % 360
	if self:PositionMinimapButton(angle) then
		state.angle = angle
	else
		self:StopMinimapButtonDrag(true)
	end
end

function QuestTogether:StartMinimapButtonDrag(button)
	if self:IsRuntimeRestricted() or not self.db or not self:CanAccessForeignFrame(button) then
		return
	end
	self:HideMinimapTooltip()
	self.minimapDragState = { profile = self.db.profile }
	self.minimapSuppressClick = true
	button:SetScript("OnUpdate", function()
		self:UpdateMinimapButtonDrag()
	end)
	self:UpdateMinimapButtonDrag()
end

function QuestTogether:RefreshMinimapPartnerGlow(hidden)
	local button = rawget(self, "minimapButton")
	if not button or not self.LibChev.CanMutateOwnedRegion(button) then return false end
	local looking = not hidden and self.isEnabled and not self.isLoggingOut
		and self:GetOption("showMinimapButton") ~= false
		and self:GetOption("lookingForQuestPartners") == true
	-- Turning the glow off is safe on our owned regions even during restrictions.
	-- Creation/layout waits for the launcher's existing recovery events.
	if looking and self:IsRuntimeRestricted() then return false end
	local glow = button.qtRingGlow
	if not glow and not looking then return true end
	if not glow then
		glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
		button.qtRingGlow = glow
		glow:SetTexture("Interface\\AddOns\\QuestTogether\\Media\\MinimapPartnerRing")
		glow:SetSize(44, 44)
		glow:SetPoint("CENTER", button, "CENTER", 0, 0)
		glow:SetBlendMode("ADD")
		button.qtRingPulse = self:CreateQTPlayerGlowPulse(glow, 0.3, 0.7)
	end
	if not self.LibChev.CanMutateOwnedRegion(glow) then return false end
	local pulse = button.qtRingPulse
	if looking then
		glow:Show()
		if pulse and not pulse:IsPlaying() then pulse:Play() end
	else
		if pulse then pulse:Stop() end
		glow:Hide()
	end
	return true
end

function QuestTogether:CreateMinimapButton(anchor)
	local button = self:CreateMinimapUIFrame("Button", "QuestTogetherMinimapButton", anchor)
	self.minimapButton = button
	button:Hide()
	button:SetSize(32, 32)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(24, 24)
	icon:SetPoint("CENTER", 0, 0)
	icon:SetTexture(ICON)
	button.qtLogoTexture = icon
	local border = button:CreateTexture(nil, "OVERLAY")
	button.qtBorderTexture = border
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT", 0, 0)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	button:SetScript("OnMouseDown", function()
		self.minimapSuppressClick = nil
	end)
	button:SetScript("OnClick", function(_, mouseButton)
		if self.minimapSuppressClick then
			self.minimapSuppressClick = nil
			return
		end
		if mouseButton == "LeftButton" or mouseButton == "RightButton" then
			self:HideMinimapTooltip()
			if self:IsRuntimeRestricted() or not self:CanAccessForeignFrame(button) then return end
			if self:IsMinimapShiftKeyDown() then
				self:HandleQuestPartnerCommand("toggle")
			else
				self:ShowMinimapMenu(button)
			end
		end
	end)
	button:SetScript("OnEnter", function()
		self:ShowMinimapTooltip(button)
	end)
	button:SetScript("OnLeave", function()
		self:HideMinimapTooltip()
	end)
	button:SetScript("OnDragStart", function()
		self:StartMinimapButtonDrag(button)
	end)
	button:SetScript("OnDragStop", function()
		self:StopMinimapButtonDrag(false)
	end)
	button:SetScript("OnHide", function()
		self:RefreshMinimapPartnerGlow(true)
		self:StopMinimapButtonDrag(true)
		self:HideMinimapTooltip()
	end)
	button:SetScript("OnShow", function()
		self:PositionMinimapButton()
		self:RefreshMinimapPartnerGlow()
	end)
	return button
end

function QuestTogether:RefreshMinimapButton()
	if not self.hasLoggedIn or not self.db or self:IsRuntimeRestricted() then
		return false
	end
	self:StopMinimapButtonDrag(true)
	if self:GetOption("showMinimapButton") == false then
		local button = rawget(self, "minimapButton")
		if self:CanAccessForeignFrame(button) then
			button:Hide()
		end
		self:HideMinimapTooltip()
		return true
	end
	local anchor = self:GetMinimapAnchor()
	if not self:CanAccessForeignFrame(anchor) then
		return false
	end
	local button = rawget(self, "minimapButton") or self:CreateMinimapButton(anchor)
	if not self:CanAccessForeignFrame(button) then
		return false
	end
	if not self:PositionMinimapButton() then
		button:Hide()
		return false
	end
	button:Show()
	self:RefreshMinimapPartnerGlow()
	return true
end

function QuestTogether:InitializeMinimapLauncher()
	local anchor = self:GetMinimapAnchor()
	if
		not self.hasLoggedIn
		or not self:CanAccessValue(anchor)
		or (type(anchor) ~= "table" and type(anchor) ~= "userdata")
	then
		return
	end
	local events = rawget(self, "minimapLauncherFrame")
	if not events then
		events = self:CreateMinimapUIFrame("Frame")
		self.minimapLauncherFrame = events
		events:SetScript("OnEvent", function()
			self:RefreshMinimapButton()
		end)
		-- The launcher stays available when runtime quest announcements are off.
		-- These events also retry deferred visibility/position changes safely.
		for _, event in ipairs({
			"PLAYER_ENTERING_WORLD",
			"PLAYER_REGEN_ENABLED",
			"ADDON_RESTRICTION_STATE_CHANGED",
			"UI_SCALE_CHANGED",
			"DISPLAY_SIZE_CHANGED",
			"EDIT_MODE_LAYOUTS_UPDATED",
		}) do
			pcall(events.RegisterEvent, events, event)
		end
	end
	self:RefreshMinimapButton()
end
