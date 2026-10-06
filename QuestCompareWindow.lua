local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether
local VISIBLE_ROWS, ROW_HEIGHT = 11, 42
local MEMBER_ROW_HEIGHT, OBJECTIVE_ROW_HEIGHT = 24, 26
local DETAIL_BOTTOM_PADDING = 10
local function CompareRowHeight(rows, index)
	local row, previous, following = rows[index], rows[index - 1], rows[index + 1]
	local firstDetail = row.kind and (not previous or not previous.kind or previous.questId ~= row.questId)
	local lastDetail = row.kind and (not following or not following.kind or following.questId ~= row.questId)
	local height = row.kind == "member" and (row.hint and row.hint ~= "" and 34 or MEMBER_ROW_HEIGHT)
		or row.kind == "objective" and OBJECTIVE_ROW_HEIGHT or ROW_HEIGHT
	return height + (firstDetail and 6 or 0) + (lastDetail and DETAIL_BOTTOM_PADDING or 0)
end
local QUEST_WIDTH, MEMBER_WIDTH, ACTION_WIDTH = 350, 130, 160
local COLUMN_WIDTH = MEMBER_WIDTH - 4
local function ColumnLeft(index)
	return QUEST_WIDTH + (index - 1) * MEMBER_WIDTH - 4
end
local MIN_WIDTH = 780
local function MinimumWidth(memberCount)
	return math.max(MIN_WIDTH, QUEST_WIDTH + math.min(memberCount, 5) * MEMBER_WIDTH + ACTION_WIDTH + 62)
end
local COLORS = {
	Have = { 0.24, 0.20, 0.14 },
	Ready = { 0.12, 0.38, 0.18 },
	Missing = { 0.55, 0.25, 0.06 },
	Loading = { 0.38, 0.32, 0.24 },
	Unknown = { 0.38, 0.32, 0.24 },
}

local DARK_COLORS = {
	Have = { 0.86, 0.86, 0.84 },
	Ready = { 0.40, 0.90, 0.48 },
	Missing = { 1, 0.68, 0.30 },
	Loading = { 0.68, 0.70, 0.73 },
	Unknown = { 0.68, 0.70, 0.73 },
}

local function MemberColor(addon, classFile, brightness)
	-- Use the existing access-checked class-color adapter, never raw registries.
	local code = addon:GetClassColorCode(classFile)
	brightness = addon:GetOption("lightMode") ~= true and 1 or brightness or 0.48
	return tonumber(code:sub(5, 6), 16) / 255 * brightness,
		tonumber(code:sub(7, 8), 16) / 255 * brightness,
		tonumber(code:sub(9, 10), 16) / 255 * brightness
end

local CORNER_RADIUS = 6
local CORNER_FILL = "Interface\\AddOns\\QuestTogether\\Media\\PanelCornerFill"
local CORNER_BORDER = "Interface\\AddOns\\QuestTogether\\Media\\PanelCornerBorder"
local CORNER_UV = { { 0, 0.5, 0, 0.5 }, { 0.5, 1, 0, 0.5 }, { 0, 0.5, 0.5, 1 }, { 0.5, 1, 0.5, 1 } }
local function ShowPanel(region, shown)
	region.panelShown = shown
	region[shown and "Show" or "Hide"](region)
	for _, part in ipairs(region.panelParts or {}) do
		part[shown and part.panelActive and "Show" or "Hide"](part)
	end
end
local function ColorPanel(region, ...)
	region:SetColorTexture(...)
	for index, part in ipairs(region.panelParts or {}) do
		if index <= 2 then
			part:SetColorTexture(...)
		else
			part:SetVertexColor(...)
		end
	end
end
local function LayoutPanel(region, parent, layer, sublevel, x, y, width, height, roundedTop, roundedBottom)
	local radius = (roundedTop or roundedBottom) and CORNER_RADIUS or 0
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", x + radius, -y)
	region:SetSize(width - radius * 2, height)
	if radius > 0 and not region.panelParts then
		region.panelParts = {}
		for index = 1, 6 do
			local part = parent:CreateTexture(nil, layer, nil, sublevel)
			region.panelParts[index] = part
			if index > 2 then
				part:SetTexture(CORNER_FILL)
				part:SetTexCoord(unpack(CORNER_UV[index - 2]))
			end
		end
	end
	for index, part in ipairs(region.panelParts or {}) do
		part:ClearAllPoints()
		part.panelActive = radius > 0 and (index <= 2 or (index <= 4 and roundedTop) or (index >= 5 and roundedBottom))
		if index <= 2 then
			local top = roundedTop and radius or 0
			part:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (index == 1 and 0 or width - radius), -y - top)
			part:SetSize(math.max(1, radius), height - top - (roundedBottom and radius or 0))
		else
			local right, bottom = index % 2 == 0, index >= 5
			part:SetPoint(
				"TOPLEFT",
				parent,
				"TOPLEFT",
				x + (right and width - radius or 0),
				-y - (bottom and height - radius or 0)
			)
			part:SetSize(CORNER_RADIUS, CORNER_RADIUS)
		end
	end
	ShowPanel(region, region.panelShown ~= false)
end

local function LayoutDetailsPanel(row, width, details, first, last, expanded, dark)
	local height = row:GetHeight()
	local left, right = details and 28 or 0, details and 14 or 0
	local top, bottom = details and first and 6 or 0, details and last and 6 or 0
	-- Each pooled row supplies one slice of the same inset panel. Only the
	-- true section edges get end caps; scrolling clips the panel naturally.
	local roundTop, roundBottom = details and first, details and last
	LayoutPanel(
		row.paper,
		row,
		"BACKGROUND",
		-1,
		left,
		top,
		width - left - right,
		height - top - bottom,
		roundTop,
		roundBottom
	)
	LayoutPanel(
		row.background,
		row,
		"BACKGROUND",
		0,
		left,
		top,
		width - left - right,
		height - top - bottom,
		roundTop,
		roundBottom
	)
	LayoutPanel(
		row.hover,
		row,
		"BORDER",
		0,
		left,
		top,
		width - left - right,
		height - top - bottom,
		roundTop,
		roundBottom
	)
	if dark then
		ColorPanel(row.paper, 0.10, 0.12, 0.15, details and 0.98 or 0.6)
	else
		ColorPanel(row.paper, 1, 0.94, 0.79, details and 0.85 or 0.35)
	end
	if details or expanded then
		ShowPanel(row.paper, true)
	else
		ShowPanel(row.paper, false)
	end
	for _, edge in ipairs(row.panelEdges) do
		edge:Hide()
		edge:ClearAllPoints()
		if dark then
			edge:SetColorTexture(0.64, 0.58, 0.42, 0.65)
		else
			edge:SetColorTexture(0.32, 0.22, 0.10, 0.65)
		end
	end
	if details then
		for i, x in ipairs({ left, width - right - 1 }) do
			local edge = row.panelEdges[i]
			edge:SetPoint("TOPLEFT", row, "TOPLEFT", x, -top - (roundTop and CORNER_RADIUS or 0))
			edge:SetSize(
				1,
				height - top - bottom - (roundTop and CORNER_RADIUS or 0) - (roundBottom and CORNER_RADIUS or 0)
			)
			edge:Show()
		end
	end
	if (details and first) or expanded then
		row.panelEdges[3]:SetPoint("TOPLEFT", row, "TOPLEFT", left + (roundTop and CORNER_RADIUS or 0), -top)
		row.panelEdges[3]:SetSize(width - left - right - (roundTop and CORNER_RADIUS * 2 or 0), 1)
		row.panelEdges[3]:Show()
	end
	if (details and last) or expanded then
		row.panelEdges[4]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left + (roundBottom and CORNER_RADIUS or 0), bottom)
		row.panelEdges[4]:SetSize(width - left - right - (roundBottom and CORNER_RADIUS * 2 or 0), 1)
		row.panelEdges[4]:Show()
	end
	if (roundTop or roundBottom) and not row.panelCorners then
		row.panelCorners = {}
		for index = 1, 4 do
			local corner = row:CreateTexture(nil, "ARTWORK")
			corner:SetTexture(CORNER_BORDER)
			corner:SetTexCoord(unpack(CORNER_UV[index]))
			corner:SetSize(CORNER_RADIUS, CORNER_RADIUS)
			row.panelCorners[index] = corner
		end
	end
	for index, corner in ipairs(row.panelCorners or {}) do
		corner:ClearAllPoints()
		local rightSide, bottomSide = index % 2 == 0, index > 2
		corner:SetPoint(
			"TOPLEFT",
			row,
			"TOPLEFT",
			rightSide and width - right - CORNER_RADIUS or left,
			bottomSide and -height + bottom + CORNER_RADIUS or -top
		)
		if dark then
			corner:SetVertexColor(0.64, 0.58, 0.42, 0.65)
		else
			corner:SetVertexColor(0.32, 0.22, 0.10, 0.65)
		end
		corner[((bottomSide and roundBottom) or (not bottomSide and roundTop)) and "Show" or "Hide"](corner)
	end
	row.accent:ClearAllPoints()
	row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", details and left + 3 or 0, -top)
	row.accent:SetSize(3, height - top - bottom)
	return top, bottom
end

local function Label(parent, x, y, width, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetWidth(width)
	label:SetJustifyH("LEFT")
	label:SetText(text or "")
	return label
end

local function Button(addon, parent, x, y, width, text, callback)
	local button = addon:CreatePartyQuestUIFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	button:SetSize(width, 24)
	button:SetText(text)
	button:SetScript("OnClick", callback)
	return button
end

local function NativeTexture(parent, template, layer, width, height)
	-- Match libchev's debug window with texture-only native artwork. These
	-- regions are ours; no Blizzard frame scripts or shared frame state.
	local texture = parent:CreateTexture(nil, layer, template)
	texture:ClearAllPoints()
	if width and height then
		texture:SetSize(width, height)
	end
	return texture
end

local function Window(addon, width, height, title, parchment)
	if not parchment then return addon:CreateScrollDialog(width, height, title) end
	local frame = addon:CreatePartyQuestUIFrame("Frame", nil, addon:GetPartyQuestUIParent())
	frame:Hide()
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetFlattensRenderLayers(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if addon:IsWorkBlocked("foreign_frame_mutation") then
			return
		end
		addon:StartWindowDrag(self)
	end)
	frame:SetScript("OnDragStop", function(self)
		addon:StopWindowDrag(self)
	end)
	frame.parchment = NativeTexture(frame, nil, "BACKGROUND")
	frame.parchment:SetPoint("TOPLEFT", -16, 12)
	frame.parchment:SetPoint("BOTTOMRIGHT", 16, -12)
	frame.parchment:SetTexture(addon:GetScrollWindowTheme().texture)
	frame.title = Label(
		frame,
		parchment and 50 or 16,
		-5,
		width - (parchment and 100 or 70),
		title,
		parchment and "GameFontNormalLarge" or "GameFontNormal"
	)
	if parchment then
		frame.title:SetTextColor(0.22, 0.13, 0.06)
		local logo = NativeTexture(frame, nil, "ARTWORK", 26, 26)
		logo:SetPoint("TOPLEFT", 18, 0)
		frame.title:ClearAllPoints()
		frame.title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
		frame.title:SetHeight(30)
		frame.title:SetJustifyV("MIDDLE")
		frame.title:SetMaxLines(1)
		logo:SetTexture(
			addon.NAMEPLATE_PLAYER_ICON_TEXTURE or "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon"
		)
	end
	return frame
end

local function Checkbox(addon, parent, x, y, text, callback)
	local check = addon:CreatePartyQuestUIFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	check:SetSize(26, 26)
	check.label = Label(check, 30, -7, (parent.contentWidth or (parent:GetWidth() - 48)) - 26, text)
	if parent.themeLabels then addon:AddScrollDialogLabel(parent, check.label) end
	check:SetScript("OnClick", callback)
	return check
end

local function Slider(addon, parent, vertical)
	local slider = addon:CreatePartyQuestUIFrame("Slider", nil, parent)
	slider:Hide()
	slider:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	slider:EnableMouse(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0.15, 0.18, 0.23, 0.8)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(vertical and 12 or 30, vertical and 30 or 12)
	thumb:SetColorTexture(0.55, 0.65, 0.8, 1)
	slider:SetThumbTexture(thumb)
	return slider
end

-- These factories are addon-owned seams for live-safe UI fixtures.
function QuestTogether:CreatePartyQuestUIFrame(...)
	return CreateFrame(...)
end

function QuestTogether:GetPartyQuestUIParent()
	return UIParent
end

-- QT owns these buttons and textures; use Blizzard's ordinary mini quest POI
-- artwork without registering remote quests with Blizzard's POI button mixins.
local function FocusAtlas(texture, atlas, fallback)
	if not texture.SetAtlas or not pcall(texture.SetAtlas, texture, atlas) then
		texture:SetTexture(fallback)
	end
end
local function CreateFocusButton(addon, row, column)
	local button = addon:CreatePartyQuestUIFrame("Button", nil, row)
	button:SetSize(26, 26)
	button:SetPoint("TOPLEFT", ColumnLeft(column) + COLUMN_WIDTH - 31, -8)
	button.normal = button:CreateTexture(nil, "BACKGROUND")
	button.pushed = button:CreateTexture(nil, "BACKGROUND")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	for _, texture in ipairs({ button.normal, button.pushed, button.highlight }) do texture:SetAllPoints() end
	button.icon:SetSize(16, 16)
	button.icon:SetPoint("CENTER")
	button:SetNormalTexture(button.normal)
	button:SetPushedTexture(button.pushed)
	button:SetHighlightTexture(button.highlight)
	FocusAtlas(button.highlight, "UI-QuestPoi-InnerGlow", "Interface\\Buttons\\UI-Common-MouseHilight")
	local function Current()
		return row.data and not row.data.kind and row.session == addon.partyQuestCompareSession
	end
	local function Leave() addon:HideSettingsTooltip(button) end
	button:SetScript("OnLeave", Leave)
	button:SetScript("OnHide", Leave)
	button:SetScript("OnEnter", function()
		if not Current() then return end
		local hint = button.localPlayer and L("Click to focus this quest.")
			or (button.selected and L("Click to follow this player's quest focus.") or L("This player is not focusing this quest."))
		if not button.localPlayer and not button.knownFocus then hint = addon:GetPartyFocusLabel(button.memberName) end
		addon:ShowSettingsTooltip(button, button.memberName, hint)
	end)
	button:SetScript("OnClick", function()
		Leave()
		if Current() and button.clickable and not addon:IsWorkBlocked("foreign_frame_mutation") then
			addon:SelectPartyQuestFocus(button.memberName, row.data.questId)
		end
	end)
	return button
end
local function PaintFocusButton(button, selected, complete)
	button.selected = selected
	local suffix = selected and "-SuperTracked" or ""
	FocusAtlas(button.normal, "UI-QuestPoi-QuestNumber" .. suffix, "Interface\\Buttons\\UI-Quickslot2")
	FocusAtlas(button.pushed, "UI-QuestPoi-QuestNumber-Pressed" .. suffix, "Interface\\Buttons\\UI-Quickslot-Depress")
	FocusAtlas(button.icon, complete and "UI-QuestIcon-TurnIn-Normal"
		or (selected and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow"),
		"Interface\\GossipFrame\\ActiveQuestIcon")
end

local function DrawCompareRows(self, frame, session, rows, width, actionX)
	local dark = self:GetOption("lightMode") ~= true
	local colors = dark and DARK_COLORS or COLORS
	local focusIDs = {}
	for i, member in ipairs(session.members) do
		focusIDs[i] = self.GetPartyQuestFocusID and self:GetPartyQuestFocusID(member.name)
	end
	for i, row in ipairs(frame.rows) do
		local slot = frame.visibleRows[i]
		local data = slot and rows[slot.index]
		if row.data ~= data then self:HideSettingsTooltip(row) end
		row.data = data
		row.session = session
		if not data then
			row:Hide()
			row.clip:Hide()
		else
			row:Show()
			row.clip:Show()
			row:SetWidth(width)
			row:SetHeight(CompareRowHeight(rows, slot.index))
			local expanded = not data.kind and session.expandedQuestIds and session.expandedQuestIds[data.questId]
			local previous, following = rows[slot.index - 1], rows[slot.index + 1]
			local first = not previous or not previous.kind or previous.questId ~= data.questId
			local last = not following or not following.kind or following.questId ~= data.questId
			local top, bottom = LayoutDetailsPanel(row, width, data.kind ~= nil, first, last, expanded, dark)
			row.expander:SetTextColor(dark and 0.92 or 0.4, dark and 0.78 or 0.25, dark and 0.45 or 0.08)
			row.expander:SetText(data.kind and "" or (expanded and "-" or "+"))
			row.title:SetText(data.title)
			ShowPanel(row.hover, false)
			ColorPanel(row.hover, dark and 1 or 0.35, dark and 1 or 0.24, dark and 1 or 0.10, 0.08)
			row.title:ClearAllPoints()
			local indent = data.kind == "objective" and 64 or data.kind == "member" and 48 or 28
			local own = session.byName[session.playerName]
			local journalVisible = not data.kind and own and own.entries[data.questId] ~= nil
			local titleTop = data.kind == "member" and (data.hint and data.hint ~= "" and 9 or 4)
				or data.kind == "objective" and 3 or 5
			row.title:SetPoint("TOPLEFT", indent, -titleTop - top)
			row.title:SetWidth(data.kind and (actionX - indent - 16) or (QUEST_WIDTH - (journalVisible and 66 or 36)))
			if journalVisible then
				row.journal:SetEnabled(not self:IsWorkBlocked("foreign_frame_mutation"))
				row.journal:Show()
			else
				row.journal:Hide()
			end
			row.partySummary:SetText(data.partySummary or "")
			row.partySummary:SetTextColor(unpack(colors[data.partySummaryState or "Unknown"]))
			if data.kind then
				row.accent:Hide()
				local r, g, b = MemberColor(self, data.classFile)
				ColorPanel(row.background, r, g, b, 0.20)
			else
				if expanded then
					row.accent:SetColorTexture(0.46, 0.30, 0.08, 1)
					row.accent:Show()
				else
					row.accent:Hide()
				end
				ColorPanel(
					row.background,
					dark and 1 or 0.4,
					dark and 0.85 or 0.28,
					dark and 0.55 or 0.12,
					expanded and 0.16 or (slot.index % 2 == 0 and 0.055 or 0.015)
				)
			end
			if data.fraction then
				local barWidth = actionX - 80
				row.progressTrack:ClearAllPoints()
				row.progressTrack:SetPoint("TOPLEFT", 64, -22 - top)
				row.progressFill:ClearAllPoints()
				row.progressFill:SetPoint("TOPLEFT", 64, -22 - top)
				row.progressTrack:SetWidth(barWidth)
				row.progressTrack:SetColorTexture(
					dark and 0.75 or 0.3,
					dark and 0.78 or 0.2,
					dark and 0.8 or 0.08,
					dark and 0.22 or 0.15
				)
				row.progressTrack:Show()
				row.progressFill:SetWidth(math.max(1, barWidth * data.fraction))
				if dark then
					row.progressFill:SetColorTexture(
						data.complete and 0.40 or 0.86,
						data.complete and 0.90 or 0.65,
						data.complete and 0.48 or 0.32,
						0.9
					)
				else
					row.progressFill:SetColorTexture(
						data.complete and 0.12 or 0.50,
						data.complete and 0.38 or 0.32,
						0.12,
						0.85
					)
				end
				if data.fraction > 0 then
					row.progressFill:Show()
				else
					row.progressFill:Hide()
				end
			else
				row.progressTrack:Hide()
				row.progressFill:Hide()
			end
			if data.kind == "member" then
				row.title:SetTextColor(MemberColor(self, data.classFile, 0.32))
			elseif dark then
				row.title:SetTextColor(0.93, 0.92, 0.88)
			elseif data.kind == "objective" then
				row.title:SetTextColor(0.23, 0.17, 0.10)
			else
				row.title:SetTextColor(0.18, 0.12, 0.06)
			end
			for j, status in ipairs(data.cells) do
				if not row.cells[j] then
					row.cells[j] =
						Label(row, QUEST_WIDTH + (j - 1) * MEMBER_WIDTH, -12, MEMBER_WIDTH - 40, "", "GameFontHighlight")
					row.cellShades[j] = row:CreateTexture(nil, "BORDER")
					row.cellShades[j]:SetPoint("TOPLEFT", ColumnLeft(j), 0)
					row.cellShades[j]:SetSize(COLUMN_WIDTH, ROW_HEIGHT - 1)
				end
				local r, g, b = MemberColor(self, session.members[j].classFile)
				row.cellShades[j]:SetColorTexture(r, g, b, 0.20)
				row.cellShades[j]:Show()
				row.cells[j]:SetText(L(status))
				row.cells[j]:SetTextColor(unpack(colors[status]))
				row.cells[j]:Show()
				if not row.focusCells[j] then row.focusCells[j] = CreateFocusButton(self, row, j) end
				local button, member = row.focusCells[j], session.members[j]
				button.memberName, button.localPlayer = member.name, member.isLocal
				button.knownFocus = focusIDs[j] ~= nil and focusIDs[j] >= 0
				local selected = focusIDs[j] == data.questId
				button.clickable = member.isLocal or (selected and session.mode ~= "target")
				PaintFocusButton(button, selected, status == "Ready")
				if status == "Have" or status == "Ready" then button:Show() else button:Hide() end
			end
			for j = #data.cells + 1, #row.cells do
				row.cells[j]:Hide()
				row.cellShades[j]:Hide()
				if row.focusCells[j] then row.focusCells[j]:Hide() end
			end
			row.action:ClearAllPoints()
			row.action:SetPoint("TOPLEFT", actionX, -9)
			row.action:SetHeight(24)
			row.hint:SetMaxLines(2)
			row.hint:ClearAllPoints()
			row.hint:SetHeight(data.kind and (row:GetHeight() - top - bottom - 4) or (ROW_HEIGHT - 8))
			local status, waiting = self:GetPartyQuestShareStatus(data.questId)
			if data.kind then
				status, waiting = nil, false
			end
			row.hint:SetTextColor(unpack(data.complete and colors.Ready or colors.Have))
			if data.action and not waiting then
				local cooldown = data.action == "request"
						and self.GetPartyQuestShareRequestCooldown
						and self:GetPartyQuestShareRequestCooldown(data.owner)
					or 0
				local coolingDown = cooldown > 0
				row.action:SetText(
					coolingDown and L("Please wait") or (data.action == "share" and L("Share") or L("Request Share"))
				)
				row.action:SetEnabled(not coolingDown and not self:IsWorkBlocked("quest_share"))
				row.action:Show()
				if status and status ~= "" then
					-- Keep terminal feedback visible below a retry action, without
					-- increasing row height or changing the scroll pool's geometry.
					row.action:ClearAllPoints()
					row.action:SetPoint("TOPLEFT", actionX, -1)
					row.action:SetSize(ACTION_WIDTH - 12, 22)
					row.hint:SetPoint("TOPLEFT", actionX, -24)
					row.hint:SetSize(ACTION_WIDTH - 12, 18)
					row.hint:SetMaxLines(1)
					row.hint:SetText(L(status))
					row.hint:Show()
				else
					row.action:SetWidth(ACTION_WIDTH - 12)
					row.hint:Hide()
				end
			else
				row.action:Hide()
				if data.kind == "member" then
					-- Center two-line notices beside the name instead of crowding
					-- the panel's top edge with a fixed top-aligned text box.
					row.hint:SetPoint("LEFT", row.title, "RIGHT", 16, 0)
					row.hint:SetHeight(28)
				else
					row.hint:SetPoint("TOPLEFT", actionX, (data.kind and -2 or -4) - top)
				end
				row.hint:SetWidth(ACTION_WIDTH - (data.kind and 28 or 8))
				row.hint:SetText(L(status or data.hint or ""))
				row.hint:Show()
			end
		end
	end
end

local function DetailHeights(rows)
	local heights = {}
	for index, row in ipairs(rows) do
		if row.kind then
			heights[row.questId] = (heights[row.questId] or 0) + CompareRowHeight(rows, index)
		end
	end
	return heights
end

local function CompareHeight(frame)
	local height = 0
	for index in ipairs(frame.displayRows) do
		height = height + CompareRowHeight(frame.displayRows, index)
	end
	for id, full in pairs(DetailHeights(frame.displayRows)) do
		local transition = frame.expansions and frame.expansions[id]
		if transition then
			height = height - full + math.min(full, transition.reveal)
		end
	end
	return height
end

function QuestTogether:CapturePartyQuestScrollAnchor()
	local frame, session = rawget(self, "partyQuestCompareWindow"), rawget(self, "partyQuestCompareSession")
	if not frame or not session or frame.displaySession ~= session then return end
	local pixels, y, anchor = session.scrollPixels or 0, 0
	for i, row in ipairs(frame.displayRows or {}) do
		if not row.kind and y <= pixels then anchor = { questId = row.questId, offset = pixels - y } end
		y = y + CompareRowHeight(frame.displayRows, i)
	end
	return anchor
end

local function RestoreScrollAnchor(session, rows)
	local anchor = session.restoreAnchor
	if not anchor then return end
	local y = 0
	for i, row in ipairs(rows) do
		if not row.kind and row.questId == anchor.questId then session.scrollPixels = y + anchor.offset; break end
		y = y + CompareRowHeight(rows, i)
	end
	for _, member in ipairs(session.members) do
		if member.state == "loading" or member.objectiveRequestQuestId then return end
	end
	session.restoreAnchor = nil
end

local function ScrollCompare(self, frame, session, pixels, force)
	if
		self.partyQuestCompareSession ~= session
		or frame.displaySession ~= session
		or self:IsWorkBlocked("foreign_frame_mutation")
	then
		return
	end
	local rows = frame.displayRows
	local heights, seen = DetailHeights(rows), {}
	local maximum = math.max(0, CompareHeight(frame) - frame.rowsViewport:GetHeight())
	pixels = math.max(0, math.min(pixels, maximum))
	local visible, keys, y = {}, {}, 0
	for index, data in ipairs(rows) do
		local fullHeight = CompareRowHeight(rows, index)
		local height = fullHeight
		if data.kind then
			local id = data.questId
			local transition = frame.expansions and frame.expansions[id]
			local reveal = transition and transition.reveal or heights[id]
			height = math.max(0, math.min(fullHeight, reveal - (seen[id] or 0)))
			seen[id] = (seen[id] or 0) + fullHeight
		end
		if height > 0 and y + height > pixels and y < pixels + frame.rowsViewport:GetHeight() then
			visible[#visible + 1] = { index = index, top = y, height = height }
			keys[#keys + 1] = index
		end
		y = y + height
	end
	local origin = visible[1] and visible[1].top or 0
	session.scrollPixels, session.offset = pixels, visible[1] and visible[1].index - 1 or 0
	frame.visibleRows = visible
	for i, row in ipairs(frame.rows) do
		local slot = visible[i]
		if slot then
			row.clip:ClearAllPoints()
			row.clip:SetPoint("TOPLEFT", frame.rowsContent, "TOPLEFT", 0, -(slot.top - origin))
			row.clip:SetSize(frame.content:GetWidth(), math.max(0.01, slot.height))
		end
	end
	local key = table.concat(keys, ",")
	if force or frame.drawnKey ~= key then
		DrawCompareRows(self, frame, session, rows, frame.content:GetWidth(), frame.content:GetWidth() - ACTION_WIDTH)
		frame.drawnKey = key
	end
	frame.rowsViewport:SetVerticalScroll(pixels - origin)
	frame.scrolling = true
	frame.vertical:SetMinMaxValues(0, maximum)
	frame.vertical:SetValue(pixels)
	frame.scrolling = false
	if maximum > 0 then
		frame.vertical:Show()
	else
		frame.vertical:Hide()
	end
end

local function StopExpansion(frame)
	frame.expansions, frame.animateExpansion, frame.expansionGeneration = nil, nil, nil
	if frame.expansionAnimator then
		frame.expansionAnimator:SetScript("OnUpdate", nil)
	end
end

local function AnimateExpansions(self, frame, session)
	local transitions, generation = frame.expansions, {}
	frame.expansionGeneration = generation
	frame.expansionAnimator:SetScript("OnUpdate", function(_, elapsed)
		if frame.expansions ~= transitions or frame.expansionGeneration ~= generation then
			return
		end
		if self.partyQuestCompareSession ~= session or frame.displaySession ~= session then
			StopExpansion(frame)
			return
		end
		if self:IsWorkBlocked("foreign_frame_mutation") then
			return
		end
		local remove, finished = {}, false
		for id, transition in pairs(transitions) do
			transition.elapsed = math.min(0.18, transition.elapsed + math.min(elapsed, 0.1))
			local t = transition.elapsed / 0.18
			transition.reveal = transition.from + (transition.target - transition.from) * t * t * (3 - 2 * t)
			if t >= 1 then
				if transition.closingRows then
					remove[id] = true
				end
				transitions[id], finished = nil, true
			end
		end
		if next(remove) then
			local rows = {}
			for _, row in ipairs(frame.displayRows) do
				if not (row.kind and remove[row.questId]) then
					rows[#rows + 1] = row
				end
			end
			frame.displayRows = rows
		end
		if not next(transitions) then
			StopExpansion(frame)
		end
		ScrollCompare(self, frame, session, session.scrollPixels or 0, finished)
	end)
end

local function PrepareExpansions(self, frame, session, rows)
	if self:GetOption("reduceMotion") then
		StopExpansion(frame); frame.displayRows = rows; return
	end
	local intent = frame.animateExpansion
	frame.animateExpansion = nil
	local transitions = frame.expansions or {}
	local full, oldFull = DetailHeights(rows), DetailHeights(frame.displayRows or {})
	local roots, oldDetails = {}, {}
	for _, row in ipairs(rows) do
		if not row.kind then
			roots[row.questId] = true
		end
	end
	for _, row in ipairs(frame.displayRows or {}) do
		if row.kind then
			oldDetails[row.questId] = oldDetails[row.questId] or {}
			local list = oldDetails[row.questId]
			list[#list + 1] = row
		end
	end
	if intent and intent.session == session and roots[intent.questId] then
		local id = intent.questId
		local opening = session.expandedQuestIds and session.expandedQuestIds[id]
		local old = transitions[id]
		local from = old and old.reveal or (opening and 0 or oldFull[id] or 0)
		transitions[id] = {
			from = from,
			reveal = from,
			target = opening and (full[id] or 0) or 0,
			elapsed = 0,
			closingRows = not opening and oldDetails[id] or nil,
		}
	end
	for id, transition in pairs(transitions) do
		if not roots[id] then
			transitions[id] = nil
		elseif not transition.closingRows and transition.target ~= (full[id] or 0) then
			transition.from, transition.elapsed, transition.target = transition.reveal, 0, full[id] or 0
		end
	end
	local display = {}
	for _, row in ipairs(rows) do
		display[#display + 1] = row
		local transition = transitions[row.questId]
		if not row.kind and transition and transition.closingRows then
			for _, detail in ipairs(transition.closingRows) do
				display[#display + 1] = detail
			end
		end
	end
	frame.displayRows = display
	if next(transitions) then
		frame.expansions = transitions
		AnimateExpansions(self, frame, session)
	else
		StopExpansion(frame)
	end
end

local function StopCompareScroll(frame)
	frame.wheelTarget, frame.wheelSession = nil, nil
	frame:SetScript("OnUpdate", nil)
end

local function WheelCompare(self, frame, delta)
	local session = self.partyQuestCompareSession
	if not session or frame.displaySession ~= session or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	session.restoreAnchor = nil
	local maximum = math.max(0, CompareHeight(frame) - frame.rowsViewport:GetHeight())
	frame.wheelTarget =
		math.max(0, math.min(maximum, (frame.wheelTarget or session.scrollPixels or 0) - delta * ROW_HEIGHT * 1.5))
	if self:GetOption("reduceMotion") then
		local target = frame.wheelTarget
		StopCompareScroll(frame); ScrollCompare(self, frame, session, target); return
	end
	frame.wheelSession = session
	frame:SetScript("OnUpdate", function(_, elapsed)
		if self.partyQuestCompareSession ~= session or frame.displaySession ~= session then
			StopCompareScroll(frame)
			return
		end
		if self:IsWorkBlocked("foreign_frame_mutation") then
			return
		end
		if frame.wheelTarget == nil then
			return
		end
		local current = session.scrollPixels or 0
		local target = math.min(frame.wheelTarget, math.max(0, CompareHeight(frame) - frame.rowsViewport:GetHeight()))
		frame.wheelTarget = target
		local nextValue = current + (target - current) * (1 - math.exp(-18 * math.min(elapsed, 0.1)))
		local done = math.abs(target - nextValue) < 0.5
		ScrollCompare(self, frame, session, done and target or nextValue)
		if done then
			StopCompareScroll(frame)
		end
	end)
end

function QuestTogether:CreatePartyQuestCompareWindow()
	if self.partyQuestCompareWindow then
		return self.partyQuestCompareWindow
	end
	local parent = self:GetPartyQuestUIParent()
	if not self:CanAccessForeignFrame(parent) then
		return nil
	end
	local width = math.max(MIN_WIDTH, math.min(1280, parent:GetWidth() * 0.94))
	local frame = Window(self, width, 720, L("Party Quest Log"), true)
	-- Use the ordinary panel layer; HIGH also covers client quest-log panels.
	-- Top-level focus can reorder this window within MEDIUM.
	frame:SetFrameStrata("MEDIUM")
	local scale = math.min(1, parent:GetHeight() * 0.94 / 690, parent:GetWidth() * 0.94 / width)
	frame:SetScale(scale)
	self.partyQuestCompareWindow = frame
	frame.expansionAnimator = self:CreatePartyQuestUIFrame("Frame", nil, frame)
	frame.summary = Label(frame, 20, -47, width - 40, "", "GameFontHighlight")
	frame.searchLabel = Label(frame, 20, -80, 65, L("Search:"), "GameFontHighlight")
	frame.search = self:CreatePartyQuestUIFrame("EditBox", nil, frame, "InputBoxTemplate")
	frame.search:SetPoint("TOPLEFT", 88, -74)
	frame.search:SetSize(math.max(100, math.min(300, width - 500)), 26)
	frame.search:SetAutoFocus(false)
	frame.search:SetMaxLetters(96)
	frame.search:SetScript("OnTextChanged", function(edit)
		if not frame.rendering then
			self:SetPartyQuestCompareFilter("search", edit:GetText())
		end
	end)
	frame.search:SetScript("OnEscapePressed", function(edit)
		edit:ClearFocus()
	end)
	frame.search:SetScript("OnEnterPressed", function(edit)
		edit:ClearFocus()
	end)
	frame.filter = Button(self, frame, width - 386, -74, 124, L("Filters"), function(button)
		self:ShowPartyQuestCompareFilters(button)
	end)
	frame.reset = Button(self, frame, width - 250, -74, 100, L("Reset"), function()
		self:ResetPartyQuestCompareFilters()
	end)
	frame.activeFilters = Label(frame, 20, -111, width - 62, "", "GameFontHighlight")
	frame.activeFilters:SetMaxLines(1)
	frame.refresh = Button(self, frame, width - 140, -72, 112, L("Refresh"), function()
		self:RefreshPartyRoster()
		self:RefreshPartyQuestCompare()
	end)
	local close = self:CreatePartyQuestUIFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close = close
	close:SetPoint("TOPRIGHT", 2, 1)
	close:SetScript("OnClick", function()
		-- An explicitly closed child may already be invisible with UIParent,
		-- in which case Hide does not dispatch another OnHide callback.
		self:CancelPartyQuestCompare()
		frame:Hide()
	end)
	frame:SetScript("OnHide", function(hiddenFrame)
		StopCompareScroll(frame)
		StopExpansion(frame)
		if frame.resizing then
			frame:StopMovingOrSizing()
			frame.resizing = nil
		end
		-- Parent visibility changes must not leave a still-shown window with
		-- stale rows and no session when the parent becomes visible again.
		if not hiddenFrame:IsShown() then
			self:CancelPartyQuestCompare()
		end
	end)

	frame.viewport = self:CreatePartyQuestUIFrame("ScrollFrame", nil, frame)
	frame.viewport:SetPoint("TOPLEFT", 20, -140)
	frame.viewport:SetSize(width - 62, VISIBLE_ROWS * ROW_HEIGHT + 54)
	frame.content = self:CreatePartyQuestUIFrame("Frame", nil, frame.viewport)
	frame.content:SetSize(QUEST_WIDTH + ACTION_WIDTH, VISIBLE_ROWS * ROW_HEIGHT + 54)
	frame.viewport:SetScrollChild(frame.content)
	frame.questHeader = Label(frame.content, 4, 0, QUEST_WIDTH - 8, L("QUEST"), "GameFontNormal")
	frame.rowsViewport = self:CreatePartyQuestUIFrame("ScrollFrame", nil, frame.content)
	frame.rowsViewport:SetPoint("TOPLEFT", 0, -54)
	frame.rowsViewport:SetSize(QUEST_WIDTH + ACTION_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
	frame.rowsContent = self:CreatePartyQuestUIFrame("Frame", nil, frame.rowsViewport)
	frame.rowsContent:SetSize(QUEST_WIDTH + ACTION_WIDTH, (VISIBLE_ROWS * 2 + 2) * ROW_HEIGHT)
	frame.rowsViewport:SetScrollChild(frame.rowsContent)
	frame.headers, frame.headerAccents, frame.rows = {}, {}, {}
	frame.headerCrowns = {}
	frame.focusButtons, frame.headerStatuses = {}, {}
	frame.followStatus = Label(frame.content, 4, -18, QUEST_WIDTH - 130, "", "GameFontHighlightSmall")
	frame.followStatus:SetHeight(34)
	frame.stopFollowing = Button(self, frame.content, QUEST_WIDTH - 124, -22, 116, L("Stop following"), function()
		self:StopPartyQuestFollow()
	end)
	frame.stopFollowing:Hide()
	local function EnsureRows(count)
		for i = #frame.rows + 1, count do
			local clip = self:CreatePartyQuestUIFrame("ScrollFrame", nil, frame.rowsContent)
			local row = self:CreatePartyQuestUIFrame("Frame", nil, clip)
			row.clip = clip
			clip:SetScrollChild(row)
			row:SetSize(QUEST_WIDTH + ACTION_WIDTH, ROW_HEIGHT)
			row.paper = row:CreateTexture(nil, "BACKGROUND", nil, -1)
			row.panelEdges = {}
			for edge = 1, 4 do
				row.panelEdges[edge] = row:CreateTexture(nil, "ARTWORK")
				row.panelEdges[edge]:SetColorTexture(0.32, 0.22, 0.10, 0.65)
			end
			row.background = row:CreateTexture(nil, "BACKGROUND")
			row.background:SetAllPoints()
			ColorPanel(row.background, 1, 1, 1, i % 2 == 0 and 0.055 or 0.015)
			row.expander = Label(row, 6, -8, 18, "", "GameFontNormalLarge")
			row.expander:SetTextColor(0.4, 0.25, 0.08)
			row.title = Label(row, 28, -5, QUEST_WIDTH - 36, "", "GameFontHighlightLarge")
			row.partySummary = Label(row, 28, -25, QUEST_WIDTH - 36, "", "GameFontHighlight")
			row.partySummary:SetMaxLines(1)
			row.accent = row:CreateTexture(nil, "ARTWORK")
			row.accent:SetPoint("TOPLEFT", 8, 0)
			row.accent:SetSize(2, ROW_HEIGHT)
			row.accent:SetColorTexture(0.46, 0.30, 0.12, 0.5)
			row.progressTrack = row:CreateTexture(nil, "ARTWORK")
			row.progressTrack:SetPoint("TOPLEFT", 44, -32)
			row.progressTrack:SetHeight(3)
			row.progressTrack:SetColorTexture(0.3, 0.2, 0.08, 0.15)
			row.progressFill = row:CreateTexture(nil, "OVERLAY")
			row.progressFill:SetPoint("TOPLEFT", 44, -32)
			row.progressFill:SetHeight(3)
			row.hover = row:CreateTexture(nil, "BORDER")
			row.hover:SetAllPoints()
			ColorPanel(row.hover, 0.35, 0.24, 0.10, 0.08)
			ShowPanel(row.hover, false)
			row:SetScript("OnMouseUp", function(_, button)
				if
					button == "LeftButton"
					and row.data
					and not row.data.kind
					and row.session == self.partyQuestCompareSession
				then
					frame.animateExpansion = { session = self.partyQuestCompareSession, questId = row.data.questId }
					self:TogglePartyQuestObjectives(row.data.questId)
				end
			end)
			row.title:SetMaxLines(1)
			row.journal = self:CreatePartyQuestUIFrame("Button", nil, row)
			row.journal:SetSize(22, 22)
			row.journal:SetPoint("TOPLEFT", QUEST_WIDTH - 32, -4)
			row.journal:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			local journalIcon = row.journal:CreateTexture(nil, "ARTWORK")
			journalIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
			journalIcon:SetSize(18, 18)
			journalIcon:SetPoint("CENTER")
			row.journal:SetScript("OnEnter", function()
				if row.data and not row.data.kind and row.session == self.partyQuestCompareSession then
					self:ShowSettingsTooltip(row.journal, L("Open in Quest Log"), row.data.title)
				end
			end)
			local function HideJournalTooltip() self:HideSettingsTooltip(row.journal) end
			row.journal:SetScript("OnLeave", HideJournalTooltip)
			row.journal:SetScript("OnHide", HideJournalTooltip)
			row.journal:SetScript("OnClick", function()
				HideJournalTooltip()
				if row.data and not row.data.kind and row.session == self.partyQuestCompareSession then
					self:OpenPartyQuestJournal(row.data.questId)
				end
			end)
			row:EnableMouse(true)
			row:SetScript("OnEnter", function()
				if row.data then
					ShowPanel(row.hover, true)
					self:ShowSettingsTooltip(row, row.data.title or "", row.data.hint or "")
				end
			end)
			row:SetScript("OnLeave", function()
				ShowPanel(row.hover, false)
				self:HideSettingsTooltip(row)
			end)
			row:SetScript("OnHide", function() self:HideSettingsTooltip(row) end)
			row.cells, row.cellShades, row.focusCells = {}, {}, {}
			row.action = Button(self, row, QUEST_WIDTH, -9, ACTION_WIDTH - 12, "", function()
				local data = row.data
				if not data or row.session ~= self.partyQuestCompareSession then
					return
				end
				if data.action == "share" then
					self:SharePartyDiffQuest(data.questId)
				elseif data.action == "request" then
					self:RequestPartyQuestShare(data.questId, data.owner)
				end
			end)
			row.hint = Label(row, QUEST_WIDTH, -7, ACTION_WIDTH - 8, "", "GameFontHighlight")
			row.hint:SetMaxLines(2)
			row.hint:SetHeight(ROW_HEIGHT - 8)
			row.hint:SetJustifyV("MIDDLE")
			frame.rows[i] = row
		end
	end
	EnsureRows(VISIBLE_ROWS * 2 + 2)
	frame.vertical = Slider(self, frame, true)
	frame.vertical:SetPoint("TOPRIGHT", -18, -194)
	frame.vertical:SetSize(16, VISIBLE_ROWS * ROW_HEIGHT)
	frame.vertical:SetMinMaxValues(0, 0)
	frame.vertical:SetValueStep(1)
	frame.vertical:SetObeyStepOnDrag(true)
	frame.vertical:SetValue(0)
	frame.vertical:SetScript("OnValueChanged", function(_, value)
		local session = self.partyQuestCompareSession
		if session and not frame.rendering and not frame.scrolling then
			session.restoreAnchor = nil
			StopCompareScroll(frame)
			ScrollCompare(self, frame, session, value)
		end
	end)
	frame.viewport:EnableMouseWheel(true)
	frame.viewport:SetScript("OnMouseWheel", function(_, delta)
		WheelCompare(self, frame, delta)
	end)
	frame.rowsViewport:EnableMouseWheel(true)
	frame.rowsViewport:SetScript("OnMouseWheel", function(_, delta)
		WheelCompare(self, frame, delta)
	end)
	frame.horizontal = Slider(self, frame, false)
	frame.horizontal:SetPoint("TOPLEFT", 26, -618)
	frame.horizontal:SetSize(width - 70, 16)
	frame.horizontal:SetMinMaxValues(0, 0)
	frame.horizontal:SetValue(0)
	frame.horizontal:SetValueStep(1)
	frame.horizontal:SetScript("OnValueChanged", function(_, value)
		frame.viewport:SetHorizontalScroll(value)
	end)
	for _, text in ipairs({
		frame.summary,
		frame.searchLabel,
		frame.activeFilters,
		frame.questHeader,
	}) do
		text:SetTextColor(0.27, 0.19, 0.10)
	end
	-- Layout changes use the cached display model, so dragging never performs
	-- quest reads or starts communication. Grow the reusable row pool only as needed.
	function frame:Layout()
		local w, h = self:GetWidth(), self:GetHeight()
		local rowsHeight = math.max(42, h - 234)
		self.title:SetWidth(w - 100)
		self.summary:SetWidth(w - 40)
		self.search:SetWidth(math.max(100, math.min(300, w - 500)))
		for _, control in ipairs({ { self.filter, 386 }, { self.reset, 250 }, { self.refresh, 140 } }) do
			control[1]:ClearAllPoints()
			control[1]:SetPoint("TOPLEFT", w - control[2], -74)
		end
		self.activeFilters:SetWidth(w - 62)
		self.viewport:SetSize(w - 62, rowsHeight + 54)
		self.content:SetHeight(rowsHeight + 54)
		self.rowsViewport:SetHeight(rowsHeight)
		local capacity = 2 * math.ceil(rowsHeight / ROW_HEIGHT) + 2
		EnsureRows(capacity)
		self.rowsContent:SetHeight(#self.rows * ROW_HEIGHT)
		self.vertical:SetHeight(rowsHeight)
		self.horizontal:ClearAllPoints()
		self.horizontal:SetPoint("BOTTOMLEFT", 26, 18)
		self.horizontal:SetWidth(w - 70)
	end
	local screenWidth, screenHeight = parent:GetWidth(), parent:GetHeight()
	frame:SetResizable(true)
	function frame:UpdateResizeBounds(memberCount)
		local minimum = MinimumWidth(memberCount)
		screenWidth, screenHeight = parent:GetWidth(), parent:GetHeight()
		local currentScale = self:GetScale()
		if self.minimumWidth == minimum and self.boundsWidth == screenWidth and self.boundsHeight == screenHeight and self.boundsScale == currentScale then
			return
		end
		self.minimumWidth = minimum
		-- A growing party must still fit on a small display. Do not increase
		-- the scale again on departure and unexpectedly enlarge the window.
		scale = math.min(self:GetScale() or scale, screenWidth * 0.94 / minimum, screenHeight * 0.94 / self:GetHeight())
		self:SetScale(scale)
		self.boundsWidth, self.boundsHeight, self.boundsScale = screenWidth, screenHeight, scale
		local maxWidth = math.max(minimum, math.min(1600, screenWidth * 0.98 / scale))
		local maxHeight = math.max(500, math.min(1100, screenHeight * 0.98 / scale))
		if type(self.SetResizeBounds) == "function" then
			self:SetResizeBounds(minimum, 500, maxWidth, maxHeight)
		else
			self:SetMinResize(minimum, 500)
			self:SetMaxResize(maxWidth, maxHeight)
		end
		if self:GetWidth() < minimum then
			self:SetSize(minimum, self:GetHeight())
		end
	end
	frame:UpdateResizeBounds(self.partyQuestCompareSession and #self.partyQuestCompareSession.members or 1)
	frame.resizeGrip = self:CreatePartyQuestUIFrame("Button", nil, frame)
	frame.resizeGrip:SetSize(24, 24)
	frame.resizeGrip:SetPoint("BOTTOMRIGHT", -1, 0)
	frame.resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	frame.resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	frame.resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	frame.resizeGrip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" or self:IsWorkBlocked("foreign_frame_mutation") then
			return
		end
		frame.resizing = true
		-- Match PanelResizeButtonMixin: preserve the cursor-to-grip offset.
		frame:StartSizing("BOTTOMRIGHT", true)
	end)
	frame.resizeGrip:SetScript("OnMouseUp", function()
		if frame.resizing then
			frame:StopMovingOrSizing()
			frame.resizing = nil
			self:SaveWindowLayout(frame)
			self:ApplyWindowLayout(frame)
		end
	end)
	frame:SetScript("OnSizeChanged", function()
		if self:IsWorkBlocked("foreign_frame_mutation") then
			if frame.resizing then
				frame:StopMovingOrSizing()
				frame.resizing = nil
			end
			self:QueuePartyQuestCompareRender()
			return
		end
		frame:Layout()
		local session = self.partyQuestCompareSession
		if not session or frame.displaySession ~= session then
			return
		end
		local contentWidth =
			math.max(frame.viewport:GetWidth(), QUEST_WIDTH + #session.members * MEMBER_WIDTH + ACTION_WIDTH)
		frame.content:SetWidth(contentWidth)
		frame.rowsViewport:SetWidth(contentWidth)
		frame.rowsContent:SetWidth(contentWidth)
		local maximum = math.max(0, contentWidth - frame.viewport:GetWidth())
		frame.horizontal:SetMinMaxValues(0, maximum)
		frame.horizontal:SetValue(math.min(frame.horizontal:GetValue(), maximum))
		if maximum > 0 then
			frame.horizontal:Show()
		else
			frame.horizontal:Hide()
		end
		ScrollCompare(self, frame, session, session.scrollPixels or 0, true)
	end)
	frame:Layout()
	self:RegisterManagedWindow(frame, "partyQuestLog", frame.minimumWidth, 500)
	return frame
end

function QuestTogether:QueuePartyQuestCompareRender()
	local session = self.partyQuestCompareSession
	if not session then
		return
	end
	self:ScheduleDeferredWork("foreign_frame_mutation", "party_compare_render", function()
		if self.partyQuestCompareSession == session then
			self:RenderPartyQuestCompare()
		end
	end, 0.05, "party compare render")
end

function QuestTogether:QueuePartyQuestTitleRefresh(rows)
	local session, api = self.partyQuestCompareSession, self.API or {}
	if
		not session
		or session.titleRefreshPending
		or type(api.RequestLocalizedQuestTitle) ~= "function"
		or type(api.GetLocalizedQuestTitle) ~= "function"
	then
		return
	end
	local now = self:SafeToNumber(api.GetTime and api.GetTime()) or 0
	for _, row in ipairs(rows) do
		local attempt = session.titleRequests and session.titleRequests[row.questId]
		-- Work through titles beyond the ten-per-30-second load budget. Give each
		-- title two attempts and one final cache read; failed IDs cannot poll forever.
		if row.needsLocalTitle and (not attempt or attempt.count < 2 or now < attempt.time + 5) then
			session.titleRefreshPending = true
			self:ScheduleDeferredWork("quest_snapshot_refresh", "party_compare_titles", function()
				session.titleRefreshPending = nil
				if self.partyQuestCompareSession == session then
					self:RenderPartyQuestCompare()
				end
			end, 30, "party compare titles")
			return
		end
	end
end

function QuestTogether:RenderPartyQuestCompare()
	local frame, session = self.partyQuestCompareWindow, self.partyQuestCompareSession
	if not frame or not session or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	frame:UpdateResizeBounds(#session.members)
	frame:Layout()
	local theme = self:GetScrollWindowTheme()
	local dark = theme.dark
	frame.parchment:SetVertexColor(unpack(theme.tint))
	frame.title:SetTextColor(unpack(theme.heading))
	for _, label in ipairs({
		frame.summary,
		frame.searchLabel,
		frame.activeFilters,
		frame.questHeader,
	}) do
		label:SetTextColor(unpack(theme.muted))
	end
	local quests = self:BuildPartyQuestDiffRows()
	local rows = self:BuildPartyQuestCompareDisplayRows(quests)
	-- The isolated debug preview supplies its own title and has no mode.
	if session.mode then
		frame.title:SetText(session.mode == "target" and L("Compare Quests") or L("Party Quest Log"))
	end
	local width = math.max(frame.viewport:GetWidth(), QUEST_WIDTH + #session.members * MEMBER_WIDTH + ACTION_WIDTH)
	local actionX = width - ACTION_WIDTH
	frame.rendering = true
	local filters = self:GetPartyQuestCompareFilters()
	local filterCount, filterLabel = self:GetPartyQuestCompareFilterLabel()
	frame.filter:SetText(filterCount > 0 and string.format(L("Filters (%d)"), filterCount) or L("Filters"))
	frame.activeFilters:SetText(filterLabel ~= "" and filterLabel or L("All quests · Any progress · Any action"))
	frame.reset:SetEnabled(filterCount > 0 or filters.search ~= "")
	if frame.search:GetText() ~= filters.search then
		frame.search:SetText(filters.search)
	end
	frame.content:SetWidth(width)
	frame.rowsViewport:SetWidth(width)
	frame.rowsContent:SetWidth(width)
	if frame.displaySession ~= session then
		StopCompareScroll(frame)
		StopExpansion(frame)
	end
	frame.displaySession = session
	if self:GetOption("reduceMotion") then StopCompareScroll(frame) end
	RestoreScrollAnchor(session, rows)
	PrepareExpansions(self, frame, session, rows)
	local ready = 0
	local leaderName = session.mode ~= "target" and self:GetPartyQuestLeaderName() or nil
	for i, member in ipairs(session.members) do
		if member.state == "ready" then
			ready = ready + 1
		end
		if not frame.headers[i] then
			frame.headers[i] = Label(frame.content, 0, 0, MEMBER_WIDTH - 6, "", "GameFontNormal")
			frame.headerAccents[i] = frame.content:CreateTexture(nil, "ARTWORK")
			frame.headerAccents[i]:SetSize(COLUMN_WIDTH, 3)
			frame.headerAccents[i]:SetPoint("TOPLEFT", ColumnLeft(i), -48)
			frame.headerCrowns[i] = frame.content:CreateTexture(nil, "OVERLAY")
			frame.headerCrowns[i]:SetTexture("Interface\\AddOns\\QuestTogether\\Media\\PartyLeader")
			frame.headerCrowns[i]:SetSize(16, 12)
			frame.headerCrowns[i]:SetPoint("TOPLEFT", ColumnLeft(i) + 8, -7)
		end
		local header = frame.headers[i]
		local isLeader = member.name == leaderName
		if isLeader then frame.headerCrowns[i]:Show() else frame.headerCrowns[i]:Hide() end
		local r, g, b = MemberColor(self, member.classFile)
		header:SetTextColor(r, g, b)
		frame.headerAccents[i]:SetColorTexture(r, g, b, 1)
		frame.headerAccents[i]:Show()
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", ColumnLeft(i) + (isLeader and 28 or 8), -6)
		header:SetHeight(16)
		header:SetMaxLines(1)
		header:SetJustifyV("TOP")
		header:SetText(member.isLocal and L("You") or member.name)
		if not frame.headerStatuses[i] then
			frame.headerStatuses[i] = Label(frame.content, 0, 0, COLUMN_WIDTH - 16, "", "GameFontHighlightSmall")
		end
		local status = frame.headerStatuses[i]
		status:ClearAllPoints()
		status:SetPoint("TOPLEFT", ColumnLeft(i) + 8, -23)
		status:SetHeight(14)
		status:SetMaxLines(1)
		status:SetTextColor(unpack(theme.muted))
		status:SetText(self:GetPartyQuestSnapshotLabel(member))
		status:Show()
		if not frame.focusButtons[i] then
			local button = self:CreatePartyQuestUIFrame("Button", nil, frame.content)
			frame.focusButtons[i] = button
			-- Decoration stays beneath the existing header text. The transparent
			-- button owns input and the small downward menu arrow.
			button.paper = frame.content:CreateTexture(nil, "BACKGROUND")
			button.paper:SetAllPoints(button)
			button.hover = frame.content:CreateTexture(nil, "BORDER")
			button.hover:SetAllPoints(button)
			ShowPanel(button.hover, false)
			button.arrow = {}
			for line = 1, 5 do
				local strip = button:CreateTexture(nil, "ARTWORK")
				strip:SetSize(11 - line * 2, 1)
				strip:SetPoint("TOPRIGHT", button, "TOPRIGHT", -5 - line, -9 - line)
				button.arrow[line] = strip
			end
			local function Leave()
				if QuestTogether.LibChev.CanMutateOwnedRegion(button.hover) then
					ShowPanel(button.hover, false)
				end
				self:HideSettingsTooltip(button)
			end
			button:SetScript("OnEnter", function()
				if
					not button.navClickable
					or self.partyQuestCompareSession ~= button.navSession
					or self:IsWorkBlocked("foreign_frame_mutation")
				then
					return
				end
				ShowPanel(button.hover, true)
				local member = button.navSession.byName[button.navName]
				self:ShowSettingsTooltip(button, button.navName,
					(member and self:GetPartyQuestSnapshotLabel(member) or "") .. "\n"
					.. (button.navSession.mode ~= "target" and self:GetPartyFocusLabel(button.navName) .. "\n" or "")
					.. L("Click for refresh and quest focus options."))
			end)
			button:SetScript("OnLeave", Leave)
			button:SetScript("OnHide", function()
				Leave()
				if QuestTogether.LibChev.CanMutateOwnedRegion(button.paper) then
					ShowPanel(button.paper, false)
				end
			end)
			button:SetScript("OnClick", function()
				Leave()
				if
					self.partyQuestCompareSession ~= button.navSession or self:IsWorkBlocked("foreign_frame_mutation")
				then
					return
				end
				self:CreatePartyQuestFilterMenu(button, function(_, root)
					if self.partyQuestCompareSession == button.navSession then
						root:CreateTitle(button.navName)
						root:CreateButton(L("Refresh this player"), function() self:RefreshPartyQuestCompareMember(button.navName) end)
						root:CreateDivider()
						self:PopulatePartyFocusMenu(root, button.navName)
					end
				end)
			end)
		end
		local button = frame.focusButtons[i]
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", ColumnLeft(i), 0)
		button:SetSize(COLUMN_WIDTH, 46)
		button.navSession, button.navName = session, member.name
		local clickable = not member.isLocal
		button.navClickable = clickable
		button:SetEnabled(clickable)
		header:SetWidth(COLUMN_WIDTH - (clickable and 30 or 16) - (isLeader and 20 or 0))
		LayoutPanel(button.paper, frame.content, "BACKGROUND", 0, ColumnLeft(i), 0, COLUMN_WIDTH, 46, true, false)
		LayoutPanel(button.hover, frame.content, "BORDER", 0, ColumnLeft(i), 0, COLUMN_WIDTH, 46, true, false)
		ColorPanel(button.paper, r, g, b, dark and 0.14 or 0.10)
		ColorPanel(button.hover, r, g, b, dark and 0.22 or 0.16)
		for _, strip in ipairs(button.arrow) do
			strip:SetColorTexture(r, g, b, 1)
		end
		if clickable then
			button:Show()
			ShowPanel(button.paper, true)
		else
			button:Hide()
			ShowPanel(button.paper, false)
		end
		header:Show()
	end
	for i = #session.members + 1, #frame.headers do
		frame.headers[i]:Hide()
		frame.headerStatuses[i]:Hide()
		frame.headerAccents[i]:Hide()
		frame.headerCrowns[i]:Hide()
		frame.focusButtons[i]:Hide()
	end

	local followingText = session.mode ~= "target" and self.GetPartyFollowingText and self:GetPartyFollowingText() or ""
	frame.followStatus:SetText(followingText)
	frame.followStatus:SetTextColor(unpack(theme.body))
	if followingText ~= "" then
		frame.stopFollowing:Show()
	else
		frame.stopFollowing:Hide()
	end

	local maxHorizontal = math.max(0, width - frame.viewport:GetWidth())
	local horizontalOffset = math.max(0, math.min(frame.horizontal:GetValue(), maxHorizontal))
	frame.horizontal:SetMinMaxValues(0, maxHorizontal)
	frame.horizontal:SetValue(horizontalOffset)
	frame.viewport:SetHorizontalScroll(horizontalOffset)
	if maxHorizontal > 0 then
		frame.horizontal:Show()
	else
		frame.horizontal:Hide()
	end

	frame.summary:SetText(
		string.format(
			L("%d of %d quests · %d/%d snapshots received"),
			#quests,
			session.totalQuests or #quests,
			ready,
			#session.members
		)
	)
	local message = session.message
	if
		not message
		and session.mode
		and session.byName[session.playerName].state == "loading"
		and self:IsMapTooltipSensitiveStateActive()
	then
		message = L("Close the world map to finish loading quests.")
	elseif not message and session.mode == "target" and not self:IsGroupedSender(session.targetName) then
		message = L("Join a party together to share quests. The selected player needs QuestTogether to respond.")
	elseif not message and #rows == 0 then
		message = (filterCount > 0 or filters.search ~= "")
				and L("No quests match. Try another search or reset the filters.")
			or L("No quests to display.")
	elseif not message and #session.members == 1 then
		message = L("Join a party to compare quests. Party members need QuestTogether to respond.")
	end
	frame.statusMessage = message
	if message then
		frame.summary:SetText(message)
	end
	ScrollCompare(self, frame, session, session.scrollPixels or 0, true)
	frame.rendering = false
	self:QueuePartyQuestTitleRefresh(session.unfilteredQuests or quests)
end

local function LayoutRequestPrompt(addon, frame)
	frame.message:SetHeight(frame.message:GetStringHeight())
	local y = frame.contentTop + frame.message:GetStringHeight() + 24
	if frame.preview then
		if not frame.previewNote then
			frame.previewNote = Label(frame, frame.contentInset, -y, frame.contentWidth, L("Preview - no settings will change."))
			addon:AddScrollDialogLabel(frame, frame.previewNote, "muted")
		end
		frame.previewNote:ClearAllPoints()
		frame.previewNote:SetPoint("TOPLEFT", frame.contentInset, -y)
		y = y + frame.previewNote:GetStringHeight() + 14
	end
	for _, check in ipairs(frame.preferences) do
		check:ClearAllPoints()
		check:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.contentInset - 4, -y)
		check.label:SetWordWrap(true)
		check.label:SetHeight(check.label:GetStringHeight())
		y = y + math.max(26, check.label:GetStringHeight() + 8) + 12
	end
	frame:SetHeight(y + 12 + 24 + frame.contentBottom)
	addon:FitScrollDialog(frame)
end

local function DismissPreview(addon, frame)
	if frame.preview then
		if addon.LibChev.CanMutateOwnedRegion(frame) then frame:Hide() end
		return true
	end
	return false
end

function QuestTogether:CreatePartyQuestSharePrompt(preview)
	local key = preview and "partyQuestSharePreviewPrompt" or "partyQuestSharePrompt"
	if rawget(self, key) then return self[key] end
	local parent = self:GetPartyQuestUIParent()
	if not self:CanAccessForeignFrame(parent) then
		return nil
	end
	local frame = Window(self, 520, 260, L("QuestTogether · Share request"))
	if not frame then return nil end
	frame.preview = preview
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetScale(math.min(1, parent:GetWidth() * 0.94 / 520, parent:GetHeight() * 0.94 / 260))
	frame.message = Label(frame, frame.contentInset, -frame.contentTop, frame.contentWidth, "", "GameFontHighlight")
	self:AddScrollDialogLabel(frame, frame.message)
	frame.message:SetHeight(64)
	frame.always = Checkbox(self, frame, frame.contentInset - 4, -152, L("Always allow party share requests"))
	frame.preferences = { frame.always }
	frame.share = Button(self, frame, 264, -222, 105, L("Share"), function()
		if DismissPreview(self, frame) then return end
		self:ConfirmPartyQuestShare(frame.request, frame.always:GetChecked() == true, false)
	end)
	frame.decline = Button(self, frame, 379, -222, 105, L("Decline"), function()
		if DismissPreview(self, frame) then return end
		if frame.request then
			self:FinishPartyQuestShare(frame.request, "declined")
		end
	end)
	frame.share:ClearAllPoints()
	frame.share:SetPoint("BOTTOMRIGHT", -frame.contentInset - 115, frame.contentBottom)
	frame.decline:ClearAllPoints()
	frame.decline:SetPoint("BOTTOMRIGHT", -frame.contentInset, frame.contentBottom)
	frame.LayoutRequest = function() LayoutRequestPrompt(self, frame) end
	frame.close = self:CreatePartyQuestUIFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -12, -8)
	frame.close:SetScript("OnClick", function()
		if self.LibChev.CanMutateOwnedRegion(frame) then frame:Hide() end
		if not frame.preview then
			if frame.always then self:FinishPartyQuestShare(frame.request, "declined")
			else self:FinishPartyJoin(frame.request, "declined") end
		end
	end)

	self[key] = frame
	return frame
end

-- Clearing a retired prompt is owned teardown, not permission to show the
-- next request or invoke a native share/invite while restricted.
function QuestTogether:HideRetiredPartyRequestPrompt(frame, request)
	if frame and (not request or frame.request ~= request) then
		frame.request = nil
		if self.LibChev.CanMutateOwnedRegion(frame) then
			frame:Hide()
		end
	end
end

function QuestTogether:QueuePartyQuestSharePrompt()
	if not self.partyQuestShareState then
		return
	end
	self:HideRetiredPartyRequestPrompt(
		self.partyQuestSharePrompt,
		self.isEnabled and self:GetNextPartyQuestShareRequest() or nil
	)
	self:ScheduleDeferredWork("foreign_frame_mutation", "party_share_prompt", function()
		self:RenderPartyQuestSharePrompt()
	end, 0, "party share prompt")
end

function QuestTogether:RenderPartyQuestSharePrompt()
	local request = self.isEnabled and self:GetNextPartyQuestShareRequest() or nil
	local frame = self.partyQuestSharePrompt
	self:HideRetiredPartyRequestPrompt(frame, request)
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	if not request then
		return
	end
	frame = frame or self:CreatePartyQuestSharePrompt()
	if not self.LibChev.CanMutateOwnedRegion(frame) then
		return
	end
	if frame.request ~= request then
		frame.request = request
		frame.always:SetChecked(false)
		frame.message:SetText(
			string.format(
				L("%s would like you to share\n[%s]\nwith the party."),
				request.sender,
				self:GetQuestTitle(request.questId)
			)
		)
	end
	frame:LayoutRequest()
	self:ApplyScrollDialogTheme(frame)
	frame:Show()
end

function QuestTogether:CreatePartyJoinPrompt(preview)
	local key = preview and "partyJoinPreviewPrompt" or "partyJoinPrompt"
	if rawget(self, key) then return self[key] end
	local parent = self:GetPartyQuestUIParent()
	if not self:CanAccessForeignFrame(parent) then
		return nil
	end
	local frame = Window(self, 580, 316, L("QuestTogether · Join request"))
	if not frame then return nil end
	frame.preview = preview
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetScale(math.min(1, parent:GetWidth() * 0.94 / 580, parent:GetHeight() * 0.94 / 316))
	frame.message = Label(frame, frame.contentInset, -frame.contentTop, frame.contentWidth, "", "GameFontHighlight")
	self:AddScrollDialogLabel(frame, frame.message)
	frame.message:SetHeight(65)
	local function Preference(y, text)
		local check = self:CreatePartyQuestUIFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
		check:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
		check:SetSize(26, 26)
		local label = Label(check, 30, -4, frame.contentWidth - 26, text)
		check.label = label
		self:AddScrollDialogLabel(frame, label)
		label:SetHeight(40)
		return check
	end
	frame.friends = Preference(-140, L("Automatically invite friends who request to join"))
	frame.lfg = Preference(-188, L("Automatically invite others while looking for partners"))
	frame.preferences = { frame.friends, frame.lfg }
	frame.invite = Button(self, frame, 172, -278, 180, L("Send Invitation"), function()
		if DismissPreview(self, frame) then return end
		self:ConfirmPartyJoin(frame.request, frame.friends:GetChecked() == true, frame.lfg:GetChecked() == true, false)
	end)
	frame.decline = Button(self, frame, 362, -278, 180, L("Decline"), function()
		if DismissPreview(self, frame) then return end
		self:FinishPartyJoin(frame.request, "declined")
	end)
	frame.invite:ClearAllPoints()
	frame.invite:SetPoint("BOTTOMRIGHT", -frame.contentInset - 190, frame.contentBottom)
	frame.decline:ClearAllPoints()
	frame.decline:SetPoint("BOTTOMRIGHT", -frame.contentInset, frame.contentBottom)
	frame.LayoutRequest = function() LayoutRequestPrompt(self, frame) end
	frame.close = self:CreatePartyQuestUIFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -12, -8)
	frame.close:SetScript("OnClick", function()
		if self.LibChev.CanMutateOwnedRegion(frame) then frame:Hide() end
		if not frame.preview then
			if frame.always then self:FinishPartyQuestShare(frame.request, "declined")
			else self:FinishPartyJoin(frame.request, "declined") end
		end
	end)

	self[key] = frame
	return frame
end

function QuestTogether:RenderPartyJoinPrompt()
	local request = self.isEnabled and self:GetNextPartyJoinRequest() or nil
	local frame = rawget(self, "partyJoinPrompt")
	self:HideRetiredPartyRequestPrompt(frame, request)
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	if not request then
		return
	end
	frame = frame or self:CreatePartyJoinPrompt()
	if not self.LibChev.CanMutateOwnedRegion(frame) then
		return
	end
	if frame.request ~= request then
		frame.request = request
		frame.friends:SetChecked(self:GetOption("autoInviteFriends") == true)
		frame.lfg:SetChecked(self:GetOption("autoInviteWhileLFG") == true)
		frame.message:SetText(request.sender .. L(" would like to join your party.\nSend an invitation?"))
	end
	frame:LayoutRequest()
	self:ApplyScrollDialogTheme(frame)
	frame:Show()
end

function QuestTogether:RenderPartyChatReminder(request)
	local inset = self.SCROLL_DIALOG_INSET
	local bodyWidth = 520 - inset * 2
	local buttonWidth = (bodyWidth - 12) / 2
	local frameKey = request and request.preview and "partyChatReminderPreviewFrame" or "partyChatReminderFrame"
	local frame = rawget(self, frameKey)
	self:HideRetiredPartyRequestPrompt(frame, request)
	if not request or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	local parent = self:GetPartyQuestUIParent()
	if not self:CanAccessForeignFrame(parent) then
		return
	end
	local function Dimension(method)
		local getter = self:GetAccessibleFrameMember(parent, method)
		if type(getter) ~= "function" then
			return nil
		end
		local ok, value = pcall(getter, parent)
		value = ok and self:SafeToNumber(value) or nil
		return value and value > 0 and value or nil
	end
	local width, parentHeight = Dimension("GetWidth"), Dimension("GetHeight")
	if not width or not parentHeight then
		return
	end
	if not frame then
		frame = Window(self, 520, 300, L("QuestTogether · Party chat announcements"))
		if not frame then return end
		self[frameKey] = frame
		frame:SetFrameStrata("FULLSCREEN_DIALOG")
		frame:SetFrameLevel(200)

		frame.heading = Label(frame, inset, -frame.contentTop, bodyWidth, L("Share updates with your party?"), "GameFontNormalLarge")
		frame.heading:SetWordWrap(true)
		frame.preview = Label(frame, inset, -94, bodyWidth, "", "GameFontHighlightSmall")
		frame.preview:SetTextColor(0.65, 0.65, 0.65)
		frame.message = Label(
			frame,
			inset,
			-116,
			bodyWidth,
			L(
				"Your quest updates can also appear in party chat, so party members without QuestTogether can follow along."
			),
			"GameFontHighlight"
		)
		frame.message:SetWordWrap(true)
		frame.memberPanel = NativeTexture(frame, nil, "BACKGROUND")
		frame.memberPanel:SetColorTexture(0, 0, 0, 0.3)
		frame.memberLabel = Label(frame, inset + 12, 0, bodyWidth - 24, L("QT hasn't been detected for:"), "GameFontNormalSmall")
		frame.members = Label(frame, inset + 12, 0, bodyWidth - 24, "", "GameFontHighlight")
		frame.members:SetWordWrap(true)
		frame.hint = Label(
			frame,
			inset,
			0,
			bodyWidth,
			L('Change this anytime in Settings under "Where to Announce".'),
			"GameFontHighlightSmall"
		)
		frame.hint:SetTextColor(0.7, 0.7, 0.7)
		frame.hint:SetWordWrap(true)
		frame.remember = Checkbox(self, frame, inset - 4, -210, L("Don't remind me again"))
		frame.remember.label:SetWidth(bodyWidth - 26)
		frame.keep = Button(self, frame, inset, -260, buttonWidth, L("Keep enabled"), function()
			if self.LibChev.CanMutateOwnedRegion(frame.remember) then
				self:AcknowledgePartyChatReminder(frame.request, frame.remember:GetChecked() == true, false)
			end
		end)
		frame.disable = Button(self, frame, inset + buttonWidth + 12, -260, buttonWidth, L("Turn off announcements"), function()
			if self.LibChev.CanMutateOwnedRegion(frame.remember) then
				self:AcknowledgePartyChatReminder(frame.request, frame.remember:GetChecked() == true, true)
			end
		end)
		frame.close = self:CreatePartyQuestUIFrame("Button", nil, frame, "UIPanelCloseButton")
		frame.close:SetPoint("TOPRIGHT", -12, -8)
		frame.close:SetScript("OnClick", function()
			-- Safe dismissal remains available during combat. A restricted close
			-- does not acknowledge or save preferences; the reminder resumes later.
			if self.LibChev.CanMutateOwnedRegion(frame) then
				frame:Hide()
			end
			if self.LibChev.CanMutateOwnedRegion(frame.remember) then
				self:AcknowledgePartyChatReminder(frame.request, frame.remember:GetChecked() == true, false)
			end
		end)
		for _, region in ipairs({ frame.heading, frame.memberLabel }) do self:AddScrollDialogLabel(frame, region, "heading") end
		for _, region in ipairs({ frame.preview, frame.hint }) do self:AddScrollDialogLabel(frame, region, "muted") end
		for _, region in ipairs({ frame.message, frame.members }) do self:AddScrollDialogLabel(frame, region) end

		frame:SetScript("OnDragStart", function()
			if not self:IsWorkBlocked("foreign_frame_mutation") and self.LibChev.CanMutateOwnedRegion(frame) then
				self:StartWindowDrag(frame)
			end
		end)
		frame:SetScript("OnDragStop", function()
			if self.LibChev.CanMutateOwnedRegion(frame) then
				self:StopWindowDrag(frame)
			end
		end)
	end
	if not self.LibChev.CanMutateOwnedRegion(frame) then
		return
	end
	if frame.request ~= request then
		frame.request = request
		frame.remember:SetChecked(false)
		frame.preview:SetText(request.preview and L("Preview - no settings will change.") or "")
		frame.members:SetText(table.concat(request.names, "\n"):gsub("|", "||"))
		-- Lay out each wrapped section from its actual height. No fixed blank
		-- message area, and long translations/member names grow the dialog.
		local function Place(region, x, y)
			region:ClearAllPoints()
			region:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
		end
		local headingHeight = frame.heading:GetStringHeight()
		Place(frame.preview, inset, frame.contentTop + headingHeight + 8)
		local headerBottom =
			frame.contentTop + headingHeight + (request.preview and frame.preview:GetStringHeight() + 8 or 0)
		local y = headerBottom + 18
		Place(frame.message, inset, y)
		y = y + frame.message:GetStringHeight() + 16
		Place(frame.memberPanel, inset, y)
		Place(frame.memberLabel, inset + 12, y + 10)
		Place(frame.members, inset + 12, y + 10 + frame.memberLabel:GetStringHeight() + 6)
		local panelHeight = 20 + frame.memberLabel:GetStringHeight() + 6 + frame.members:GetStringHeight()
		frame.memberPanel:SetSize(bodyWidth, panelHeight)
		y = y + panelHeight + 14
		Place(frame.hint, inset, y)
		y = y + frame.hint:GetStringHeight() + 14
		Place(frame.remember, inset - 4, y)
		frame.remember.label:SetWordWrap(true)
		frame.remember.label:SetHeight(frame.remember.label:GetStringHeight())
		y = y + math.max(26, frame.remember.label:GetStringHeight() + 8) + 12
		Place(frame.keep, inset, y + 24)
		Place(frame.disable, inset + buttonWidth + 12, y + 24)
		frame:SetHeight(y + 24 + 24 + frame.contentBottom)
		self:FitScrollDialog(frame)
	end
	frame:Show()
end
