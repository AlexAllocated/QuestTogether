local QuestTogether = _G.QuestTogether
local ICON = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon"
local DEFAULT_ANGLE = 225

-- All state and scripts belong to our own frames. Minimap is only a guarded
-- parent/anchor; do not hook its scripts or add fields to Blizzard frames.
function QuestTogether:GetMinimapAnchor()
	return self.API.GetMinimapAnchor and self.API.GetMinimapAnchor() or nil
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
		self:Print("Opening the quest journal is unavailable while restricted.")
		return false
	end
	if
		not self.API.CanOpenQuestJournalWindow
		or self.API.CanOpenQuestJournalWindow() ~= true
		or not self.API.OpenQuestJournalWindow
		or self.API.OpenQuestJournalWindow() ~= true
	then
		self:Print("Unable to open your quest journal on this client.")
		return false
	end
	return true
end

function QuestTogether:PopulateMinimapMenu(rootDescription)
	rootDescription:CreateButton("Settings", function()
		if not self:IsRuntimeRestricted() then
			self:OpenOptionsWindow()
		end
	end)
	local compare = rootDescription:CreateButton("Compare Party Quests", function()
		if self.isEnabled and not self:IsRuntimeRestricted() then
			self:OpenPartyQuestCompare()
		end
	end)
	compare:SetEnabled(self.isEnabled == true)
	local journal = rootDescription:CreateButton("Open Quest Journal", function()
		self:OpenQuestJournalFromMinimap()
	end)
	journal:SetEnabled(self.API.CanOpenQuestJournalWindow and self.API.CanOpenQuestJournalWindow() == true or false)
	rootDescription:CreateButton("Patch Notes", function()
		if not self:IsRuntimeRestricted() then
			self:OpenReleaseNotes()
		end
	end)
	self:PopulateChatLogDestinationMenu(rootDescription)
	rootDescription:CreateButton("Hide Minimap Icon", function()
		if self:IsRuntimeRestricted() then
			return
		end
		if self:SetOption("showMinimapButton", false) then
			self:RefreshOptionsWindow()
			self:Print(
				"Minimap icon hidden. Re-enable it in Settings > Miscellaneous > Show minimap icon (/qt options)."
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

function QuestTogether:HideMinimapTooltip()
	local tooltip = rawget(self, "minimapTooltip")
	if self:CanAccessForeignFrame(tooltip) then
		tooltip:Hide()
	end
end

function QuestTogether:ShowMinimapTooltip(button)
	if self:IsRuntimeRestricted() or rawget(self, "minimapDragState") or not self:CanAccessForeignFrame(button) then
		return
	end
	local tooltip = rawget(self, "minimapTooltip")
	if tooltip and not self:CanAccessForeignFrame(tooltip) then
		return
	end
	if not tooltip then
		tooltip = self:CreateMinimapUIFrame("Frame", nil, button, "BackdropTemplate")
		tooltip:SetFrameStrata("TOOLTIP")
		tooltip:SetClampedToScreen(true)
		tooltip:SetSize(220, 64)
		tooltip:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
		})
		tooltip:SetBackdropColor(0.04, 0.05, 0.07, 0.95)
		tooltip:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 0, -4)
		local title = tooltip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 10, -10)
		title:SetText("QuestTogether")
		local hint = tooltip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("TOPLEFT", 10, -28)
		hint:SetText("Left or right click for menu\nDrag to move")
		self.minimapTooltip = tooltip
	end
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
	local border = button:CreateTexture(nil, "OVERLAY")
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
			self:ShowMinimapMenu(button)
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
		self:StopMinimapButtonDrag(true)
		self:HideMinimapTooltip()
	end)
	button:SetScript("OnShow", function()
		self:PositionMinimapButton()
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
