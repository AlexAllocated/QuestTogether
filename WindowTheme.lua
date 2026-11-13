local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
QuestTogether.SCROLL_DIALOG_INSET = 48
local TEXTURE = "Interface\\AddOns\\QuestTogether\\Media\\QuestCompareScroll"
local DARK = {
	dark = true,
	texture = TEXTURE,
	tint = { 0.14, 0.17, 0.21 },
	heading = { 1, 0.85, 0.55 },
	body = { 0.93, 0.92, 0.88 },
	muted = { 0.88, 0.85, 0.76 },
}
local LIGHT = {
	dark = false,
	texture = TEXTURE,
	tint = { 1, 1, 1 },
	heading = { 0.22, 0.13, 0.06 },
	body = { 0.23, 0.17, 0.10 },
	muted = { 0.27, 0.19, 0.10 },
}

function QuestTogether:GetScrollWindowTheme()
	return self:GetOption("lightMode") == true and LIGHT or DARK
end

function QuestTogether:UsesClassicMenuArtwork()
	-- The audited style getter returns constants only; do not create a native
	-- menu or retain its table merely to discover the client's loaded artwork.
	local mixin = MenuStyle1Mixin
	if not self:CanAccessTable(mixin) then return false end
	local ok, getter = pcall(function() return mixin.GetInset end)
	if not ok or not self:CanAccessValue(getter) or type(getter) ~= "function" then return false end
	local read, inset = pcall(getter, mixin)
	if not read or not self:CanAccessTable(inset) then return false end
	local values, left, top, right, bottom = pcall(function()
		return self:SafeToNumber(inset.left), self:SafeToNumber(inset.top), self:SafeToNumber(inset.right), self:SafeToNumber(inset.bottom)
	end)
	return values and left == 16 and top == 10 and right == 16 and bottom == 10
end

-- Visual equivalents of Blizzard's dropdowns on a plain QT-owned Button.
-- No DropdownButton intrinsic, menu mixin, native scripts, or input bindings.
function QuestTogether:CreateOwnedDropdownButton(parent, style, classic)
	local button = self:CreateOwnedWindowFrame("Button", nil, parent)
	if not self:CanMutateOwnedUI(button) then return nil end
	local settings = style == "settings"
	button.dropdownStyle, button.dropdownClassic = settings and "settings" or "standard", classic == true
	button:EnableMouse(true)
	button:RegisterForClicks("LeftButtonUp")
	button:SetMotionScriptsWhileDisabled(true)
	button.Background = button:CreateTexture(nil, "BACKGROUND")
	button.Arrow = button:CreateTexture(nil, "OVERLAY")
	button.Text = button:CreateFontString(nil, "OVERLAY", settings and "GameFontNormal"
		or classic and "GameFontHighlightSmall" or "GameFontHighlight")
	button.Text:SetWordWrap(false)
	button:SetFontString(button.Text)
	if settings then
		button.Background:SetPoint("TOPLEFT", -7, 7)
		button.Background:SetPoint("BOTTOMRIGHT", 7, -7)
		button.Arrow:SetAtlas("common-dropdown-c-button-hover-arrow", true)
		button.Arrow:SetPoint("BOTTOM", 0, -5)
		button.Text:SetJustifyH("CENTER"); button.Text:SetHeight(20)
	else
		button.Background:SetPoint("TOPLEFT", classic and -9 or -8, classic and 8 or 7)
		button.Background:SetPoint("BOTTOMRIGHT", 8, -9)
		button.Arrow:SetPoint("RIGHT", classic and -1 or 1, classic and 0 or -3)
		button.Text:SetJustifyH(classic and "RIGHT" or "LEFT"); button.Text:SetHeight(10)
		button.Text:SetPoint("TOPRIGHT", button.Arrow, "LEFT")
		button.Text:SetPoint("TOPLEFT", classic and 9 or 8, classic and -7 or -8)
	end
	local function Refresh()
		if self:IsWorkBlocked("foreign_frame_mutation") or not self:CanMutateOwnedUI(button) then return end
		local enabled, over, down = button:IsEnabled(), button.dropdownOver, button.dropdownDown
		if not enabled then down, over = false, false; button.dropdownDown, button.dropdownOver = false, false end
		if settings then
			local suffix = not enabled and "-disabled" or down and over and "-pressedhover-1"
				or over and "-hover-1" or down and "-pressed-1" or button.dropdownMenuOpen and "-open" or ""
			button.Background:SetAtlas("common-dropdown-c-button" .. suffix)
			button.Arrow:SetShown(over == true); button.Arrow:SetDesaturated(not enabled)
			button.Text:ClearAllPoints()
			button.Text:SetPoint("LEFT", down and 15 or 13, down and -1 or 0)
			button.Text:SetPoint("RIGHT", down and -11 or -13, down and -1 or 0)
		else
			local suffix = not enabled and "-disabled" or down and over and "-pressedhover"
				or over and "-hover" or down and "-pressed" or (not classic and button.dropdownMenuOpen) and "-open" or ""
			button.Background:SetAtlas(classic and (button:GetWidth() <= 100 and "common-dropdown-classic-textholder-small"
				or "common-dropdown-classic-textholder") or "common-dropdown-textholder")
			button.Arrow:SetAtlas((classic and "common-dropdown-classic-a-buttonDown" or "common-dropdown-a-button") .. suffix, true)
			button.Arrow:Show()
		end
		if not enabled then button.Text:SetTextColor(0.5, 0.5, 0.5)
		elseif settings then button.Text:SetTextColor(1, 0.82, 0)
		else button.Text:SetTextColor(1, 1, 1) end
	end
	button.RefreshVisualState = Refresh
	function button:SetOwnedMenuOpen(open)
		self.dropdownMenuOpen = open == true
		Refresh()
	end
	button:SetScript("OnEnter", function() button.dropdownOver = button:IsEnabled() == true; Refresh() end)
	button:SetScript("OnLeave", function() button.dropdownOver = false; Refresh() end)
	button:SetScript("OnMouseDown", function(_, key)
		if key == "LeftButton" and button:IsEnabled() then button.dropdownDown = true; Refresh() end
	end)
	button:SetScript("OnMouseUp", function() button.dropdownDown = false; Refresh() end)
	button:SetScript("OnEnable", Refresh)
	button:SetScript("OnDisable", function() button.dropdownDown, button.dropdownOver = false, false; Refresh() end)
	button:SetScript("OnHide", function()
		button.dropdownOver, button.dropdownDown, button.dropdownMenuOpen = false, false, false
		Refresh()
	end)
	button:SetScript("OnShow", Refresh)
	button:SetScript("OnSizeChanged", Refresh)
	Refresh()
	return button
end

function QuestTogether:ApplyOwnedMenuArtwork(frame, style, classic)
	if not self:CanMutateOwnedUI(frame) then return end
	local background = frame.menuBackground or frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	frame.menuBackground = background
	background:ClearAllPoints()
	if classic then
		background:SetAtlas(style == "settings" and "common-dropdown-classic-b-bg" or "common-dropdown-classic-bg")
		background:SetPoint("TOPLEFT", -3, style == "settings" and 1 or 3)
		background:SetPoint("BOTTOMRIGHT", 3, -4); background:SetAlpha(1)
		frame.menuUnderlay = frame.menuUnderlay or frame:CreateTexture(nil, "BACKGROUND", nil, -7)
		frame.menuUnderlay:SetColorTexture(0, 0, 0, 0.8)
		frame.menuUnderlay:ClearAllPoints()
		frame.menuUnderlay:SetPoint("TOPLEFT", background, "TOPLEFT", style == "settings" and 7 or 6, style == "settings" and -4 or -6)
		frame.menuUnderlay:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", style == "settings" and -8 or -6, style == "settings" and 8 or 6)
		frame.menuUnderlay:Show()
	else
		if frame.menuUnderlay then frame.menuUnderlay:Hide() end
		background:SetAtlas(style == "settings" and "common-dropdown-c-bg" or "common-dropdown-bg")
		background:SetPoint("TOPLEFT", style == "settings" and -17 or -10, style == "settings" and 12 or 3)
		background:SetPoint("BOTTOMRIGHT", style == "settings" and 17 or 10, style == "settings" and -22 or -3)
		background:SetAlpha(style == "settings" and 1 or 0.925)
	end
end

-- Use the rendered position and physical cursor delta. Native StartMoving can
-- reanchor scaled/attached windows on pickup and leave the cursor offset.
function QuestTogether:GetWindowDragCursor()
	if type(GetCursorPosition) ~= "function" then return nil end
	local ok, x, y = pcall(GetCursorPosition)
	if not ok then return nil end
	return self:SafeToNumber(x), self:SafeToNumber(y)
end

local function DragDimension(addon, region, method)
	local getter = addon:GetAccessibleFrameMember(region, method)
	if type(getter) ~= "function" then return nil end
	local ok, value = pcall(getter, region)
	return ok and addon:SafeToNumber(value) or nil
end

function QuestTogether:StopWindowDrag(frame, skipSave)
	local wasDragging = frame.dragging
	frame.windowDrag, frame.dragging = nil, nil
	local driver = frame.windowDragDriver
	if driver and self.LibChev.CanMutateOwnedRegion(driver) then
		driver:SetScript("OnUpdate", nil)
		if driver:IsShown() then driver:Hide() end
	end
	if wasDragging and not skipSave then self:SaveWindowLayout(frame) end
end

function QuestTogether:StartWindowDrag(frame)
	if self:IsWorkBlocked("foreign_frame_mutation") or not self.LibChev.CanMutateOwnedRegion(frame) then return false end
	local root = self:GetOwnedUIParent()
	if not self:CanAccessForeignFrame(root) then return false end
	local scale = DragDimension(self, frame, "GetEffectiveScale")
	local rootScale = DragDimension(self, root, "GetEffectiveScale")
	local left, top = DragDimension(self, frame, "GetLeft"), DragDimension(self, frame, "GetTop")
	local rootLeft, rootBottom = DragDimension(self, root, "GetLeft"), DragDimension(self, root, "GetBottom")
	local cursorX, cursorY = self:GetWindowDragCursor()
	if not scale or scale <= 0 or not rootScale or rootScale <= 0 or not left or not top
		or not rootLeft or not rootBottom or not cursorX or not cursorY then return false end
	local driver = frame.windowDragDriver
	if not driver then
		driver = self:CreateOwnedWindowFrame("Frame", nil, frame)
		if not self.LibChev.CanMutateOwnedRegion(driver) then return false end
		frame.windowDragDriver = driver
		driver:SetScript("OnHide", function() self:StopWindowDrag(frame) end)
	end
	if not self.LibChev.CanMutateOwnedRegion(driver) then return false end
	local drag = { scale = scale, rootScale = rootScale }
	local previousX, previousY = cursorX, cursorY
	frame.windowDrag, frame.dragging = drag, true
	driver:SetScript("OnUpdate", function()
		if frame.windowDrag ~= drag or self:IsWorkBlocked("foreign_frame_mutation")
			or not self.LibChev.CanMutateOwnedRegion(frame) or not self:CanAccessForeignFrame(root)
			or DragDimension(self, frame, "GetEffectiveScale") ~= scale
			or DragDimension(self, root, "GetEffectiveScale") ~= rootScale then
			self:StopWindowDrag(frame)
			return
		end
		local x, y = self:GetWindowDragCursor()
		if not x or not y then self:StopWindowDrag(frame); return end
		if x == previousX and y == previousY then return end
		previousX, previousY = x, y
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", root, "BOTTOMLEFT",
			left + (x - cursorX - rootLeft * rootScale) / scale,
			top + (y - cursorY - rootBottom * rootScale) / scale)
	end)
	driver:Show()
	return true
end

function QuestTogether:RefreshWindowThemes()
	self:QueueQuestFocusRefresh()
	self:QueueScrollDialogThemeRefresh()
	self:QueueReleaseNotesThemeRefresh()
	self:QueuePartyQuestCompareRender()
	local preview = self.partyQuestComparePreview
	if preview and preview.partyQuestCompareSession then
		self:ScheduleDeferredWork("foreign_frame_mutation", "party_compare_preview_theme", function()
			if self.partyQuestComparePreview == preview then
				preview:QueuePartyQuestCompareRender()
			end
		end, 0, "party compare preview theme")
	end
end

-- QT-owned dialog chrome. Fixed-size rolls keep the artwork crisp on small
-- prompts, while the center stretches with translated content.
function QuestTogether:ApplyScrollDialogTheme(frame)
	if self:IsWorkBlocked("foreign_frame_mutation") or not self.LibChev.CanMutateOwnedRegion(frame) then return false end
	local theme = self:GetScrollWindowTheme()
	for _, piece in ipairs(frame.scrollPieces or {}) do
		if self.LibChev.CanMutateOwnedRegion(piece) then piece:SetVertexColor(unpack(theme.tint)) end
	end
	for _, item in ipairs(frame.themeLabels or {}) do
		if self.LibChev.CanMutateOwnedRegion(item.region) then item.region:SetTextColor(unpack(theme[item.role])) end
	end
	if frame.memberPanel and self.LibChev.CanMutateOwnedRegion(frame.memberPanel) then
		frame.memberPanel:SetColorTexture(0, 0, 0, theme.dark and 0.22 or 0.08)
	end
	return true
end

function QuestTogether:AddScrollDialogLabel(frame, region, role)
	frame.themeLabels[#frame.themeLabels + 1] = { region = region, role = role or "body" }
	self:ApplyScrollDialogTheme(frame)
end

function QuestTogether:DecorateScrollDialog(frame, title)
	if self:IsWorkBlocked("foreign_frame_mutation") or not self.LibChev.CanMutateOwnedRegion(frame) then return false end
	frame.scrollPieces, frame.themeLabels = {}, {}
	local xs, ys = { 0, 32 / 1024, 992 / 1024, 1 }, { 0, 36 / 512, 476 / 512, 1 }
	for row = 1, 3 do
		for column = 1, 3 do
			local piece = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
			frame.scrollPieces[#frame.scrollPieces + 1] = piece
			piece:SetTexture(self:GetScrollWindowTheme().texture)
			piece:SetTexCoord(xs[column], xs[column + 1], ys[row], ys[row + 1])
			local side = column == 1 and "LEFT" or "RIGHT"
			if row == 2 then
				if column == 2 then
					piece:SetPoint("TOPLEFT", frame, "TOPLEFT", 32, -48)
					piece:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 40)
				else
					piece:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, -48)
					piece:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 40)
					piece:SetWidth(32)
				end
			else
				local edge = row == 1 and "TOP" or "BOTTOM"
				if column == 2 then
					piece:SetPoint(edge .. "LEFT", frame, edge .. "LEFT", 32, 0)
					piece:SetPoint(edge .. "RIGHT", frame, edge .. "RIGHT", -32, 0)
				else
					piece:SetPoint(edge .. side, frame, edge .. side, 0, 0)
					piece:SetWidth(32)
				end
				piece:SetHeight(row == 1 and 48 or 40)
			end
		end
	end
	frame.logo = frame:CreateTexture(nil, "ARTWORK")
	frame.logo:SetTexture(self.NAMEPLATE_PLAYER_ICON_TEXTURE or "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon")
	frame.logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -10)
	frame.logo:SetSize(28, 28)
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("LEFT", frame.logo, "RIGHT", 10, 0)
	frame.title:SetWidth(frame:GetWidth() - 110)
	frame.title:SetHeight(32)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetJustifyV("MIDDLE")
	frame.title:SetMaxLines(1)
	frame.title:SetText(title)
	self:AddScrollDialogLabel(frame, frame.title, "heading")
	local registry = rawget(self, "scrollDialogs")
	if not registry then registry = setmetatable({}, { __mode = "k" }); self.scrollDialogs = registry end
	registry[frame] = true
	return true
end

function QuestTogether:CreateScrollDialog(width, height, title)
	local parent = self:GetOwnedUIParent()
	if self:IsWorkBlocked("foreign_frame_mutation") or not self:CanAccessForeignFrame(parent) then return nil end
	local frame = self:CreateOwnedWindowFrame("Frame", nil, parent)
	if not self.LibChev.CanMutateOwnedRegion(frame) then return nil end
	frame:Hide()
	frame:SetSize(width, height)
	frame.contentInset = self.SCROLL_DIALOG_INSET
	frame.contentWidth = width - frame.contentInset * 2
	frame.contentTop, frame.contentBottom = 76, 64
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetFlattensRenderLayers(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function()
		if not self:IsWorkBlocked("foreign_frame_mutation") and self.LibChev.CanMutateOwnedRegion(frame) then self:StartWindowDrag(frame) end
	end)
	frame:SetScript("OnDragStop", function()
		if self.LibChev.CanMutateOwnedRegion(frame) then self:StopWindowDrag(frame) end
	end)
	self:DecorateScrollDialog(frame, title)
	self:FitScrollDialog(frame)
	self:RegisterManagedWindow(frame)
	self:ConfigureWindowController(frame, { theme = function() self:ApplyScrollDialogTheme(frame) end })
	return frame
end

function QuestTogether:QueueScrollDialogThemeRefresh()
	self:ScheduleRuntimeWork("foreign_frame_mutation", "scroll_dialog_themes", function()
		for frame in pairs(rawget(self, "scrollDialogs") or {}) do self:ApplyScrollDialogTheme(frame) end
	end, { lifetime = "ui", delay = 0, reason = "scroll dialog themes" })
end

function QuestTogether:FitScrollDialog(frame)
	if self:IsWorkBlocked("foreign_frame_mutation") or not self.LibChev.CanMutateOwnedRegion(frame) then return false end
	local parent = self:GetOwnedUIParent()
	if not self:CanAccessForeignFrame(parent) then return false end
	local sizes = {}
	for _, method in ipairs({ "GetWidth", "GetHeight" }) do
		local getter = self:GetAccessibleFrameMember(parent, method)
		if type(getter) ~= "function" then return false end
		local ok, value = pcall(getter, parent)
		value = ok and self:SafeToNumber(value) or nil
		if not value or value <= 0 then return false end
		sizes[#sizes + 1] = value
	end
	frame:SetScale(math.min(self:GetWindowScale(), sizes[1] * 0.94 / frame:GetWidth(), sizes[2] * 0.94 / frame:GetHeight()))
	return true
end

-- Rounded fill made from non-overlapping pieces: low opacity stays uniform at
-- the corners and seams. The existing QT panel asset supplies only the curve.
function QuestTogether:CreateRoundedWindowBackground(frame)
	local pieces = {}
	for i = 1, 7 do pieces[i] = frame:CreateTexture(nil, "BACKGROUND") end
	local corners = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
	local uv = { {0,.5,0,.5}, {.5,1,0,.5}, {0,.5,.5,1}, {.5,1,.5,1} }
	for i, point in ipairs(corners) do
		pieces[i + 3]:SetTexture("Interface\\AddOns\\QuestTogether\\Media\\PanelCornerFill")
		pieces[i + 3]:SetTexCoord(unpack(uv[i]))
		pieces[i + 3]:SetSize(8, 8)
		pieces[i + 3]:SetPoint(point, frame, point)
	end
	pieces[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, 0)
	pieces[1]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 0)
	pieces[2]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -8)
	pieces[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 8)
	pieces[2]:SetWidth(8)
	pieces[3]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -8)
	pieces[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 8)
	pieces[3]:SetWidth(8)
	return pieces
end
function QuestTogether:ColorRoundedWindowBackground(pieces, color, alpha)
	for i, texture in ipairs(pieces) do
		if i <= 3 then texture:SetColorTexture(color[1], color[2], color[3], alpha)
		else texture:SetVertexColor(color[1], color[2], color[3], alpha) end
	end
end

-- Class accents/text use the same contrast in every themed QT window.
function QuestTogether:GetWindowClassColor(classFile, lightBrightness)
	local code = self:GetClassColorCode(classFile)
	local brightness = self:GetOption("lightMode") ~= true and 1 or lightBrightness or 0.48
	return tonumber(code:sub(5, 6), 16) / 255 * brightness,
		tonumber(code:sub(7, 8), 16) / 255 * brightness,
		tonumber(code:sub(9, 10), 16) / 255 * brightness
end
