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
	self:ScheduleDeferredWork("foreign_frame_mutation", "scroll_dialog_themes", function()
		for frame in pairs(rawget(self, "scrollDialogs") or {}) do self:ApplyScrollDialogTheme(frame) end
	end, 0, "scroll dialog themes")
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
