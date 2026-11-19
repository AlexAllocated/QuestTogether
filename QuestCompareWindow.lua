local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether
local VISIBLE_ROWS, ROW_HEIGHT = 11, 42
local MEMBER_ROW_HEIGHT, OBJECTIVE_ROW_HEIGHT = 24, 26
local DETAIL_BOTTOM_PADDING = 10
local CHAIN_GROUP_INDENT, CHAIN_GROUP_RAIL_X = 18, 16
local function ObjectiveDetail(row)
	return row and (row.kind == "member" or row.kind == "objective")
end
local function RowID(row) return QuestTogether:GetPartyQuestRowIdentity(row) end
local function Selectable(row) return QuestTogether:IsPartyQuestSelectableRow(row) end
local function QuestTitle(row)
	if row.kind and row.kind ~= "chainStep" then return row.title or "" end
	return "[" .. tostring(row.questLevel or "?") .. (row.questGroupRecommended and "+" or "") .. "] " .. (row.title or "")
end
local function LayoutChainSection(row, data, previous, following, width, indent, dark)
	for _, edge in ipairs(row.chainEdges) do edge:Hide() end
	local instance = data.chainInstanceId
	if not instance then return end
	local left, right, height = 4 + indent, width - 2, row:GetHeight()
	local r, g, b = dark and 0.78 or 0.48, dark and 0.62 or 0.32, dark and 0.30 or 0.12
	local function Edge(index, x, y, w, h)
		local edge = row.chainEdges[index]
		edge:ClearAllPoints(); edge:SetPoint("TOPLEFT", x, y)
		edge:SetSize(w, h); edge:SetColorTexture(r, g, b, 0.85); edge:Show()
	end
	-- Every pooled row draws its part of the same outline, including objective
	-- details and paging controls. Only real section ends receive a cap.
	Edge(1, left, 0, 2, height)
	Edge(2, right - 2, 0, 2, height)
	if not previous or previous.chainInstanceId ~= instance then Edge(3, left, 0, right - left, 2) end
	if not following or following.chainInstanceId ~= instance then Edge(4, left, 2 - height, right - left, 2) end
end
local function CompareRowHeight(rows, index)
	local row, previous, following = rows[index], rows[index - 1], rows[index + 1]
	local firstDetail = ObjectiveDetail(row) and (not ObjectiveDetail(previous) or previous.questId ~= row.questId)
	local lastDetail = ObjectiveDetail(row) and (not ObjectiveDetail(following) or following.questId ~= row.questId)
	local height = row.kind == "member" and (row.hint and row.hint ~= "" and 34 or MEMBER_ROW_HEIGHT)
		or row.kind == "objective" and OBJECTIVE_ROW_HEIGHT
		or (row.kind == "chainGroup" or row.kind == "chainMore") and 34
		or row.kind == "chainNotice" and 50 or ROW_HEIGHT
	return height + (firstDetail and 6 or 0) + (lastDetail and DETAIL_BOTTOM_PADDING or 0)
end
local QUEST_WIDTH, MEMBER_WIDTH, ACTION_WIDTH = 350, 130, 160
local COLUMN_WIDTH = MEMBER_WIDTH - 4
local function ColumnLeft(frame, index)
	return frame.columns[index].left
end
local function ColumnWidth(frame, index)
	return frame.columns[index].width
end
local function ContentWidth(frame)
	return math.max(frame.viewport:GetWidth(), QUEST_WIDTH + (frame.memberColumnsWidth or 0) + ACTION_WIDTH)
end
local MIN_WIDTH = 780
local function MinimumWidth(memberCount, columns)
	local width = 0
	for index = 1, math.min(memberCount, 5) do
		width = width + (columns and columns[index] and columns[index].width + 4 or MEMBER_WIDTH)
	end
	return math.max(MIN_WIDTH, QUEST_WIDTH + width + ACTION_WIDTH + 62)
end
local COLORS = {
	Have = { 0.24, 0.20, 0.14 },
	Completed = { 0.12, 0.38, 0.18 },
	Absent = { 0.38, 0.32, 0.24 },
	Ready = { 0.12, 0.38, 0.18 },
	Missing = { 0.55, 0.25, 0.06 },
	Unavailable = { 0.54, 0.18, 0.18 },
	Loading = { 0.38, 0.32, 0.24 },
	Unknown = { 0.38, 0.32, 0.24 },
}

local DARK_COLORS = {
	Have = { 0.86, 0.86, 0.84 },
	Completed = { 0.40, 0.90, 0.48 },
	Absent = { 0.68, 0.70, 0.73 },
	Ready = { 0.40, 0.90, 0.48 },
	Missing = { 1, 0.68, 0.30 },
	Unavailable = { 0.91, 0.49, 0.49 },
	Loading = { 0.68, 0.70, 0.73 },
	Unknown = { 0.68, 0.70, 0.73 },
}

-- Compact cells must not depend on optional font glyphs. Native artwork keeps
-- turn-in readiness distinct from completed history, even in a narrow column.
local COMPACT_STATUS = {
	Have = ".",
	Ready = "|TInterface\\GossipFrame\\ActiveQuestIcon:16:16|t",
	Completed = "|TInterface\\Buttons\\UI-CheckBox-Check:16:16|t",
	Missing = "-",
	Unavailable = "x",
	Absent = "?",
	Loading = "...",
	Unknown = "?",
}
local function StatusLabel(status)
	return L(status == "Absent" and "Not in log" or status)
end

local function RecipientReadinessLabel(recipient)
	if not recipient then return L("Eligibility unknown") end
	local state = recipient.state
	if state == "have" then return L("Have")
	elseif state == "ready" then return L("Ready")
	elseif state == "completed" then return L("Completed")
	elseif state == "checking" then return L("Checking eligibility")
	elseif state == "blocked" then
		local result = recipient.requirements or {}
		if result.permanentlyBlocked then return L("Unavailable") end
		local requirements = result.requirements
		local blockersOnly = not requirements or #requirements == 0
		if blockersOnly then requirements = result.blockers or {} end
		for _, requirement in ipairs(requirements) do
			if requirement.state == "blocked" or blockersOnly then
				if requirement.kind == "class" then return L("Different class")
				elseif requirement.kind == "race" then return L("Different race")
				elseif requirement.kind == "level" and requirement.value then return string.format(L("Requires level %d"), requirement.value)
				elseif requirement.kind == "max_level" and requirement.value then return string.format(L("Maximum level: %d"), requirement.value) end
			end
		end
		return L("Prerequisites not met")
	elseif state == "missing" and recipient.requirementState == "met" then return L("No known blockers") end
	return L("Eligibility unknown")
end

local function ShareReadinessSummary(readiness, full)
	if not readiness then return nil end
	local recipients, counts = readiness.recipients or {}, {}
	if #recipients == 1 then return RecipientReadinessLabel(recipients[1]) end
	if readiness.disabled and readiness.state == "checking" and not full then return L("Checking eligibility") end
	if readiness.disabled and not full then return L("No eligible recipients") end
	for _, recipient in ipairs(recipients) do
		local state = recipient.state
		-- Missing from the log is distinct from having checked prerequisites.
		if state == "missing" and recipient.requirementState ~= "met" then state = "unknown" end
		counts[state] = (counts[state] or 0) + 1
	end
	local parts = {}
	for _, entry in ipairs({ { "missing", L("%d missing") }, { "checking", L("%d checking") },
		{ "unknown", L("%d unknown") }, { "blocked", L("%d blocked") }, { "completed", L("%d completed") } }) do
		if (counts[entry[1]] or 0) > 0 then parts[#parts + 1] = string.format(entry[2], counts[entry[1]]) end
	end
	if #parts == 1 and not full then
		if (counts.checking or 0) > 0 then return L("Checking eligibility") end
		if (counts.unknown or 0) > 0 then return L("Eligibility unknown") end
		if (counts.missing or 0) > 0 then return L("No known blockers") end
	end
	if (full or #parts == 0) and ((counts.have or 0) + (counts.ready or 0)) > 0 then
		parts[#parts + 1] = string.format(L("Already have it: %d"), (counts.have or 0) + (counts.ready or 0))
	end
	return #parts > 0 and table.concat(parts, " · ") or L("Eligibility unknown")
end

local function RecipientReadinessText(addon, recipient, statusText)
	local text = RecipientReadinessLabel(recipient)
	if recipient and recipient.state ~= "have" and recipient.state ~= "ready" and recipient.state ~= "completed"
		and recipient.requirements and addon.DescribePartyQuestChainRequirements then
		local requirements = addon:DescribePartyQuestChainRequirements(recipient.requirements, nil, true)
		if text == statusText then return requirements end
		text = text .. "\n\n" .. requirements
	end
	return text
end

local function ShareReadinessTooltip(addon, data)
	local readiness = data.shareReadiness
	if not readiness then return nil end
	local parts = { data.action == "request" and string.format(L("Ask %s to share this quest."), data.owner or "")
		or L("Sharing sends this quest to the whole party.") }
	if #(readiness.recipients or {}) > 1 then parts[#parts + 1] = ShareReadinessSummary(readiness, true) end
	local recipients = {}
	for _, recipient in ipairs(readiness.recipients or {}) do recipients[#recipients + 1] = recipient end
	local priority = { blocked = 1, missing = 2, checking = 3, unknown = 4, completed = 5, ready = 6, have = 6 }
	table.sort(recipients, function(a, b)
		local first, second = priority[a.state] or 4, priority[b.state] or 4
		return first == second and (a.name or "") < (b.name or "") or first < second
	end)
	for index = 1, math.min(#recipients, 8) do
		local recipient = recipients[index]
		-- Party summaries stay bounded even when each player has a long list of
		-- prerequisites. The player's own cell retains the complete explanation.
		local text = #recipients == 1 and RecipientReadinessText(addon, recipient) or RecipientReadinessLabel(recipient)
		parts[#parts + 1] = (recipient.name or "") .. ": " .. text
	end
	if #recipients > 8 then parts[#parts + 1] = string.format(L("And %d more players."), #recipients - 8) end
	parts[#parts + 1] = L("World of Warcraft checks whether each player can accept the quest.")
	return table.concat(parts, "\n\n")
end

local function MemberColor(addon, classFile, brightness)
	return addon:GetWindowClassColor(classFile, brightness)
end

local Style = QuestTogether.QuestProgressStyle
local ShowPanel, ColorPanel, LayoutPanel, LayoutDetailsPanel = Style.ShowPanel, Style.ColorPanel, Style.LayoutPanel, Style.LayoutDetailsPanel

local function Label(parent, x, y, width, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetWidth(width)
	label:SetJustifyH("LEFT")
	label:SetText(text or "")
	return label
end

local function Button(addon, parent, x, y, width, text, callback)
	local button = addon:CreateOwnedWindowFrame("Button", nil, parent, "UIPanelButtonTemplate")
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
	local frame = addon:CreateOwnedWindowFrame("Frame", nil, addon:GetOwnedUIParent())
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
	local check = addon:CreateOwnedWindowFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
	check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	check:SetSize(26, 26)
	check.label = Label(check, 30, -7, (parent.contentWidth or (parent:GetWidth() - 48)) - 26, text)
	if parent.themeLabels then addon:AddScrollDialogLabel(parent, check.label) end
	check:SetScript("OnClick", callback)
	return check
end

-- These factories are addon-owned seams for live-safe UI fixtures.
function QuestTogether:CreatePartyQuestUIFrame(...)
	return self:CreateOwnedWindowFrame(...)
end

function QuestTogether:GetPartyQuestUIParent()
	return self:GetOwnedUIParent()
end

-- QT owns these buttons and textures; use Blizzard's ordinary mini quest POI
-- artwork without registering remote quests with Blizzard's POI button mixins.
local FocusAtlas = Style.SetAtlas
local function CreateFocusButton(addon, row, column)
	local button = addon:CreateOwnedWindowFrame("Button", nil, row)
	button:SetSize(26, 26)
	if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
	button:SetPoint("TOPLEFT", QUEST_WIDTH + (column - 1) * MEMBER_WIDTH + COLUMN_WIDTH - 35, -8)
	button.normal = button:CreateTexture(nil, "BACKGROUND")
	button.pushed = button:CreateTexture(nil, "BACKGROUND")
	-- Match Blizzard's POI Display frame: the symbol must render above native
	-- normal/pushed button textures regardless of their draw-layer ordering.
	button.display = addon:CreateOwnedWindowFrame("Frame", nil, button)
	button.display:SetAllPoints()
	button.display:SetFrameLevel(button:GetFrameLevel() + 1)
	button.display:EnableMouse(false)
	button.icon = button.display:CreateTexture(nil, "OVERLAY")
	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	for _, texture in ipairs({ button.normal, button.pushed, button.highlight }) do texture:SetAllPoints() end
	button.icon:SetSize(16, 16)
	button.icon:SetPoint("CENTER")
	button:SetNormalTexture(button.normal)
	button:SetPushedTexture(button.pushed)
	button:SetHighlightTexture(button.highlight)
	FocusAtlas(button.highlight, "UI-QuestPoi-InnerGlow", "Interface\\Buttons\\UI-Common-MouseHilight")
	local function Current()
		return row.data and (not row.data.kind or row.data.kind == "chainStep") and row.session == addon.partyQuestCompareSession
	end
	local function Leave() addon:HideSettingsTooltip(button) end
	button:SetScript("OnLeave", Leave)
	button:SetScript("OnHide", Leave)
	button:SetScript("OnEnter", function()
		if not Current() then return end
		local hint = button.localPlayer and L("Click to focus this quest.")
			or (button.selected and L("Click to follow this player's quest focus.") or L("This player is not focusing this quest."))
		if not button.localPlayer and not button.knownFocus then hint = addon:GetPartyFocusLabel(button.memberName) end
		if button.muted and button.clickable then
			hint = hint .. "\n\n" .. string.format(L("Changing focus will stop following %s."), button.following)
		end
		addon:ShowSettingsTooltip(button, button.memberName,
			addon:AppendQuestIDToTooltipText(row.data.questId, StatusLabel(button.questStatus or "Unknown") .. "\n" .. hint))
	end)
	button:SetScript("OnClick", function()
		Leave()
		if Current() and button.clickable and not addon:IsWorkBlocked("foreign_frame_mutation") then
			addon:RequestPartyQuestFocus(button.memberName, row.data.questId)
		end
	end)
	return button
end
local function PaintFocusButton(button, selected, complete, muted)
	button.selected = selected
	local suffix = selected and "-SuperTracked" or ""
	FocusAtlas(button.normal, "UI-QuestPoi-QuestNumber" .. suffix, "Interface\\Buttons\\UI-Quickslot2")
	FocusAtlas(button.pushed, "UI-QuestPoi-QuestNumber-Pressed" .. suffix, "Interface\\Buttons\\UI-Quickslot-Depress")
	FocusAtlas(button.icon, complete and "UI-QuestIcon-TurnIn-Normal"
		or (selected and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow"),
		"Interface\\GossipFrame\\ActiveQuestIcon")
	for _, texture in ipairs({ button.normal, button.pushed, button.icon }) do
		if texture.SetDesaturated then texture:SetDesaturated(muted) end
		local shade = muted and 0.55 or 1
		texture:SetVertexColor(shade, shade, shade, 1)
	end
end

local function StopChainLoading(row)
	row.chain:SetScript("OnUpdate", nil)
	row.chain.loading, row.chain.loadingElapsed, row.chain.loadingStep = nil, nil, nil
	row.chain.loadingSession, row.chain.loadingChains, row.chain.loadingProfile = nil, nil, nil
	row.chain.loadingGeneration = nil
	for _, dot in ipairs(row.chainDots) do dot:Hide() end
end

local function PaintChainLoading(row)
	for index, dot in ipairs(row.chainDots) do
		local distance = (index - 1 - (row.chain.loadingStep or 0)) % #row.chainDots
		dot:SetAlpha(0.2 + (7 - distance) / 7 * 0.8)
	end
end

local function SetChainLoading(addon, row, loading, dark)
	if not loading then StopChainLoading(row); row.chainIcon:Show(); return end
	local button = row.chain
	local session, profile = row.session, addon.db and addon.db.profile
	local chains = session and session.chains
	if button.loadingSession ~= session or button.loadingChains ~= chains or button.loadingProfile ~= profile then StopChainLoading(row) end
	button.loadingSession, button.loadingChains, button.loadingProfile = session, chains, profile
	button.loading = true
	button.loadingElapsed, button.loadingStep = button.loadingElapsed or 0, button.loadingStep or 0
	row.chainIcon:Hide()
	for _, dot in ipairs(row.chainDots) do
		dot:SetColorTexture(dark and 1 or 0.55, dark and 0.82 or 0.38, dark and 0.24 or 0.16)
		dot:Show()
	end
	PaintChainLoading(row)
	if addon:GetOption("reduceMotion") then button:SetScript("OnUpdate", nil); return end
	if button:GetScript("OnUpdate") then return end
	local generation = {}
	button.loadingGeneration = generation
	button:SetScript("OnUpdate", function(_, elapsed)
		if button.loadingGeneration ~= generation then return end
		if not addon.isEnabled or addon.isLoggingOut or addon.partyQuestCompareSession ~= session or row.session ~= session
			or session.chains ~= chains or chains and chains.retired or (addon.db and addon.db.profile) ~= profile
			or not row.data or not row.data.chainLoading
			or row.data.chainExpanded or not button:IsVisible() then StopChainLoading(row); return end
		if addon:IsWorkBlocked("foreign_frame_mutation") then return end
		if addon:GetOption("reduceMotion") then button:SetScript("OnUpdate", nil); return end
		button.loadingElapsed = (button.loadingElapsed or 0) + math.min(elapsed, 0.25)
		if button.loadingElapsed < 0.08 then return end
		button.loadingStep = ((button.loadingStep or 0) + math.floor(button.loadingElapsed / 0.08)) % #row.chainDots
		button.loadingElapsed = button.loadingElapsed % 0.08
		PaintChainLoading(row)
	end)
end

local function DrawCompareRows(self, frame, session, rows, width, actionX)
	local dark = self:GetOption("lightMode") ~= true
	local colors = dark and DARK_COLORS or COLORS
	local followTarget = self.GetPartyQuestFollowTarget and self:GetPartyQuestFollowTarget()
	local focusIDs = {}
	for i, member in ipairs(session.members) do
		focusIDs[i] = self.GetPartyQuestFocusID and self:GetPartyQuestFocusID(member.name)
	end
	for i, row in ipairs(frame.rows) do
		local slot = frame.visibleRows[i]
		local data = slot and rows[slot.index]
		if row.data ~= data or row.session ~= session then
			self:HideSettingsTooltip(row)
			self:HideSettingsTooltip(row.journal)
			self:HideSettingsTooltip(row.chain)
			self:HideSettingsTooltip(row.action)
			for _, control in ipairs(row.focusCells or {}) do self:HideSettingsTooltip(control) end
			for _, control in ipairs(row.cellTooltips or {}) do self:HideSettingsTooltip(control) end
		end
		row.data = data
		row.session = session
		if not data then
			row:Hide()
			row.clip:Hide()
		else
			row:Show()
			row.clip:Show()
			row:SetWidth(width)
			if Selectable(data) and frame.keyboardSession == session and session.keyboardRowId == RowID(data) then
				row.keyboardHighlight:Show()
			else
				row.keyboardHighlight:Hide()
			end
			row:SetHeight(CompareRowHeight(rows, slot.index))
			local expanded = data.kind == "chainGroup" and data.expanded or not data.kind and session.expandedQuestIds and session.expandedQuestIds[data.questId]
			local previous, following = rows[slot.index - 1], rows[slot.index + 1]
			local groupIndent = data.chainGroupMember and CHAIN_GROUP_INDENT or 0
			local groupContinues = data.chainGroupId and following and following.chainGroupId == data.chainGroupId
				and following.chainGroupMember
			row.groupRail:Hide(); row.groupEnd:Hide()
			if data.chainGroupMember or (data.kind == "chainGroup" and groupContinues) then
				local railTop = data.kind == "chainGroup" and 26 or 0
				local r, g, b = dark and 0.66 or 0.45, dark and 0.53 or 0.31, dark and 0.30 or 0.12
				row.groupRail:ClearAllPoints(); row.groupRail:SetPoint("TOPLEFT", CHAIN_GROUP_RAIL_X, -railTop)
				row.groupRail:SetSize(1, row:GetHeight() - railTop)
				row.groupRail:SetColorTexture(r, g, b, 0.55); row.groupRail:Show()
				if data.chainGroupMember and not groupContinues then
					row.groupEnd:ClearAllPoints(); row.groupEnd:SetPoint("TOPLEFT", CHAIN_GROUP_RAIL_X, 1 - row:GetHeight())
					row.groupEnd:SetSize(CHAIN_GROUP_INDENT - 4, 1)
					row.groupEnd:SetColorTexture(r, g, b, 0.55); row.groupEnd:Show()
				end
			end
			local first = not ObjectiveDetail(previous) or previous.questId ~= data.questId
			local last = not ObjectiveDetail(following) or following.questId ~= data.questId
			local top, bottom = LayoutDetailsPanel(row, width, ObjectiveDetail(data), first, last, expanded, dark)
			LayoutChainSection(row, data, previous, following, width, groupIndent, dark)
			row.expander:SetTextColor(dark and 0.92 or 0.4, dark and 0.78 or 0.25, dark and 0.45 or 0.08)
			row.expander:SetText((not data.kind or data.kind == "chainGroup") and (expanded and "-" or "+") or "")
			row.expander:ClearAllPoints(); row.expander:SetPoint("TOPLEFT", 6 + groupIndent, -8)
			row.title:SetText(QuestTitle(data))
			ShowPanel(row.hover, false)
			ColorPanel(row.hover, dark and 1 or 0.35, dark and 1 or 0.24, dark and 1 or 0.10, 0.08)
			row.title:ClearAllPoints()
			local indent = data.kind == "objective" and 64 or data.kind == "member" and 48
				or (data.kind == "chainStep" or data.chainAnchor) and 40 + math.min(8, data.depth or 0) * 14 or 28
			indent = indent + groupIndent
			if data.chainAnchor then row.expander:ClearAllPoints(); row.expander:SetPoint("TOPLEFT", indent - 22, -8) end
			local chainRow = data.kind and data.kind:sub(1, 5) == "chain"
			local questRow = not data.kind or data.kind == "chainStep"
			local chainLoading = not data.kind and data.chainLoading == true and not data.chainExpanded and not data.chainAvailable
			local chainVisible = not data.kind and (data.chainAvailable == true or chainLoading) and self.TogglePartyQuestChain ~= nil
			row.branch:Hide(); row.branchStem:Hide()
			if data.kind == "chainStep" then
				row.branch:ClearAllPoints(); row.branch:SetPoint("TOPLEFT", indent - 15, -18)
				row.branch:SetSize(10, 1); row.branch:SetColorTexture(0.55, 0.42, 0.20, 0.65); row.branch:Show()
				row.branchStem:ClearAllPoints(); row.branchStem:SetPoint("TOPLEFT", indent - 15, 0)
				row.branchStem:SetSize(1, 19); row.branchStem:SetColorTexture(0.55, 0.42, 0.20, 0.65); row.branchStem:Show()
			end
			local own = session.byName[session.playerName]
			local journalVisible = questRow and own and own.entries[data.questId] ~= nil
			local titleTop = data.kind == "member" and (data.hint and data.hint ~= "" and 9 or 4)
				or data.kind == "objective" and 3 or 5
			row.title:SetPoint("TOPLEFT", indent, -titleTop - top)
			local controlsWidth = chainVisible and (journalVisible and 64 or 38) or journalVisible and 38 or 8
			row.title:SetWidth(questRow and math.max(80, QUEST_WIDTH - indent - controlsWidth) or (actionX - indent - 16))
			row.chain:ClearAllPoints()
			row.chain:SetPoint("TOPLEFT", QUEST_WIDTH - (journalVisible and 58 or 32), -4)
			if data.chainExpanded then row.chainIcon:SetVertexColor(1, 0.82, 0.24)
			else row.chainIcon:SetVertexColor(0.80, 0.80, 0.76) end
			SetChainLoading(self, row, chainVisible and chainLoading, dark)
			row.chain:SetEnabled(chainVisible and not chainLoading and not self:IsWorkBlocked("foreign_frame_mutation"))
			if chainVisible then row.chain:Show() else row.chain:Hide() end
			if journalVisible then
				row.journal:SetEnabled(not self:IsWorkBlocked("foreign_frame_mutation"))
				row.journal:Show()
			else
				row.journal:Hide()
			end
			row.partySummary:SetText(data.partySummary or "")
			local summaryIndent = data.chainAnchor and indent or 28 + groupIndent
			row.partySummary:ClearAllPoints(); row.partySummary:SetPoint("TOPLEFT", summaryIndent, -25)
			row.partySummary:SetWidth(QUEST_WIDTH - summaryIndent - 8)
			row.partySummary:SetTextColor(unpack(colors[data.partySummaryState or "Unknown"]))
			if ObjectiveDetail(data) then
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
					data.chainAnchor and 0.25 or (expanded or data.kind == "chainGroup") and 0.16
						or data.chainInstanceId and 0.12 or (chainRow and 0.08 or (slot.index % 2 == 0 and 0.055 or 0.015))
				)
			end
			Style.LayoutProgressBar(row, data, dark, 64 + groupIndent, 22 + top, actionX - 80 - groupIndent)
			if data.kind == "member" then
				row.title:SetTextColor(MemberColor(self, data.classFile, 0.32))
			elseif data.kind == "chainStep" and data.spoilerHidden then
				local shade = dark and 0.64 or 0.42
				row.title:SetTextColor(shade, shade, shade)
			elseif questRow and data.questDifficultyColor then
				local color = data.questDifficultyColor
				local shade = dark and 1 or 0.5
				row.title:SetTextColor(color.r * shade, color.g * shade, color.b * shade)
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
					row.cellShades[j]:SetPoint("TOPLEFT", ColumnLeft(frame, j), 0)
					row.cellShades[j]:SetSize(COLUMN_WIDTH, ROW_HEIGHT - 1)
				end
				local column = frame.columns[j]
				row.cellTooltips = row.cellTooltips or {}
				if not row.cellTooltips[j] then
					local control = self:CreateOwnedWindowFrame("Button", nil, row)
					control:SetScript("OnEnter", function()
						if row.session == self.partyQuestCompareSession and row.data
							and not self:IsWorkBlocked("foreign_frame_mutation")
							and QuestTogether.LibChev.CanMutateOwnedRegion(control) and control:IsVisible() then
							local text = control.chainStep and control.questStatus == "Have" and L("In progress") or StatusLabel(control.questStatus)
							local title = control.memberName
							if control.prerequisiteText then
								title = QuestTitle(row.data)
								text = "|cffffd100" .. control.memberName .. "|r\n" .. text .. control.prerequisiteText
							end
							self:ShowSettingsTooltip(control, title, self:AppendQuestIDToTooltipText(row.data.questId, text))
						end
					end)
					local function Leave() self:HideSettingsTooltip(control) end
					control:SetScript("OnLeave", Leave)
					control:SetScript("OnHide", Leave)
					control:SetScript("OnClick", function()
						if self:IsWorkBlocked("foreign_frame_mutation") or not QuestTogether.LibChev.CanMutateOwnedRegion(control)
							or not control:IsVisible() then return end
						if row.data and row.data.kind == "chainStep" then
							self:ShowPartyQuestKeyboardMenu(frame, { rowId = RowID(row.data), questId = row.data.questId,
								data = row.data, player = control.memberName })
						else
							local click = row:GetScript("OnMouseUp")
							if click then click(row, "LeftButton") end
						end
					end)
					row.cellTooltips[j] = control
				end
				local statusControl = row.cellTooltips[j]
				statusControl.memberName, statusControl.questStatus = session.members[j].name, status
				local statusText = data.kind == "chainStep" and status == "Have" and L("In progress") or StatusLabel(status)
				local prerequisite = data.memberPrerequisiteText and data.memberPrerequisiteText[j] or data.prerequisiteText
				statusControl.chainStep = data.kind == "chainStep"
				local needsQuest = status ~= "Have" and status ~= "Ready" and status ~= "Completed"
				if not needsQuest then prerequisite = nil
				elseif not data.kind then
					local readiness = data.shareReadiness and data.shareReadiness.byName
					local recipient = readiness and readiness[session.members[j].name]
						or self.GetPartyQuestMemberShareReadiness and self:GetPartyQuestMemberShareReadiness(session.members[j], data.questId)
					prerequisite = RecipientReadinessText(self, recipient, statusText)
				end
				statusControl.prerequisiteText = type(prerequisite) == "string" and prerequisite ~= "" and "\n\n" .. prerequisite or nil
				statusControl:ClearAllPoints()
				statusControl:SetPoint("TOPLEFT", column.left, 0)
				statusControl:SetSize(column.width - ((status == "Have" or status == "Ready") and 32 or 0), ROW_HEIGHT - 1)
				if column.collapsed or data.kind == "chainStep" or not data.kind and needsQuest then statusControl:Show() else statusControl:Hide() end
				row.cellShades[j]:ClearAllPoints()
				row.cellShades[j]:SetPoint("TOPLEFT", column.left, 0)
				row.cellShades[j]:SetSize(column.width, ROW_HEIGHT - 1)
				row.cells[j]:ClearAllPoints()
				row.cells[j]:SetPoint("TOPLEFT", column.left + 4, -12)
				row.cells[j]:SetWidth(column.width - ((status == "Have" or status == "Ready") and 36 or 8))
				local r, g, b = MemberColor(self, session.members[j].classFile)
				row.cellShades[j]:SetColorTexture(r, g, b, 0.20)
				row.cellShades[j]:Show()
				row.cells[j]:SetText(column.collapsed and (COMPACT_STATUS[status] or "?") or statusText)
				row.cells[j]:SetTextColor(unpack(colors[status] or colors.Unknown))
				row.cells[j]:Show()
				if not row.focusCells[j] then row.focusCells[j] = CreateFocusButton(self, row, j) end
				local button, member = row.focusCells[j], session.members[j]
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", column.left + column.width - 31, -8)
				button.questStatus = status
				button.memberName, button.localPlayer = member.name, member.isLocal
				button.knownFocus = focusIDs[j] ~= nil and focusIDs[j] >= 0
				local selected = focusIDs[j] == data.questId
				button.clickable = member.isLocal == true or selected
				button:SetEnabled(button.clickable)
				button.following = followTarget
				if followTarget then
					button.muted = not (selected and followTarget == member.name)
				else
					button.muted = not (member.isLocal or selected)
				end
				PaintFocusButton(button, selected, status == "Ready", button.muted)
				if status == "Have" or status == "Ready" then button:Show() else button:Hide() end
			end
			for j = #data.cells + 1, #row.cells do
				row.cells[j]:Hide()
				row.cellShades[j]:Hide()
				if row.focusCells[j] then row.focusCells[j]:Hide() end
				if row.cellTooltips and row.cellTooltips[j] then row.cellTooltips[j]:Hide() end
			end
			row.action:ClearAllPoints()
			row.action:SetPoint("TOPLEFT", actionX, -9)
			row.action:SetHeight(24)
			row.hint:SetMaxLines(2)
			row.hint:SetJustifyH(data.kind and "LEFT" or "CENTER")
			row.hint:ClearAllPoints()
			row.hint:SetHeight(data.kind and (row:GetHeight() - top - bottom - 4) or (ROW_HEIGHT - 8))
			local status, waiting
			if data.questId then status, waiting = self:GetPartyQuestShareStatus(data.questId) end
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
				row.action:SetEnabled(not coolingDown and not (data.shareReadiness and data.shareReadiness.disabled)
					and not self:IsWorkBlocked("quest_share"))
				row.action:Show()
				local summary = status and status ~= "" and L(status) or ShareReadinessSummary(data.shareReadiness)
				if summary and summary ~= "" then
					-- Terminal request feedback takes priority over preflight details;
					-- both fit below the action without changing pooled row geometry.
					row.action:ClearAllPoints()
					row.action:SetPoint("TOPLEFT", actionX, -1)
					row.action:SetSize(ACTION_WIDTH - 12, 22)
					row.hint:SetPoint("TOPLEFT", actionX, -24)
					row.hint:SetSize(ACTION_WIDTH - 12, 18)
					row.hint:SetMaxLines(1)
					row.hint:SetText(summary)
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
				row.hint:SetWidth(ACTION_WIDTH - (data.kind and 28 or 12))
				row.hint:SetText(L(status or data.hint or ""))
				row.hint:Show()
			end
			-- Closing rows are visual remnants only. Retire their receiver session
			-- before a recycled slot can accept mouse or native navigation input.
			row:EnableMouse(not data.chainClosing)
			if data.chainClosing then
				row.session = nil
				row.chain:Hide(); row.journal:Hide(); row.action:Hide()
				for _, control in ipairs(row.focusCells or {}) do control:Hide() end
				for _, control in ipairs(row.cellTooltips or {}) do control:Hide() end
			end
		end
	end
end

local function DetailHeights(rows)
	local heights = {}
	for index, row in ipairs(rows) do
		if ObjectiveDetail(row) then
			heights[row.questId] = (heights[row.questId] or 0) + CompareRowHeight(rows, index)
		end
	end
	return heights
end

-- Scroll range, anchors, clipping and navigation share the animated geometry.
-- A chain opens outwards from its retained log row; text is clipped, never scaled.
local function RowHeights(frame, rows)
	local heights, offsets, seen, totals = {}, {}, {}, { before = 0, after = 0 }
	local details, chain = DetailHeights(rows), frame.chainExpansion
	for index, data in ipairs(rows) do
		local height = CompareRowHeight(rows, index)
		if ObjectiveDetail(data) then
			local id, transition = data.questId, frame.expansions and frame.expansions[data.questId]
			local reveal = transition and transition.reveal or details[id]
			heights[index] = math.max(0, math.min(height, reveal - (seen[id] or 0)))
			seen[id] = (seen[id] or 0) + height
		else heights[index] = height end
		local side = chain and chain.sides[data]
		if side then totals[side] = totals[side] + heights[index] end
	end
	seen = { before = 0, after = 0 }
	for index, data in ipairs(rows) do
		local side = chain and chain.sides[data]
		if side then
			local full = heights[index]
			if side == "before" then
				heights[index] = math.max(0, math.min(full, seen[side] + full - totals[side] * (1 - chain.reveal)))
				offsets[index] = full - heights[index]
			else heights[index] = math.max(0, math.min(full, totals[side] * chain.reveal - seen[side])) end
			seen[side] = seen[side] + full
		end
	end
	return heights, offsets
end

local function CompareHeight(frame)
	local height = 0
	for _, value in ipairs(RowHeights(frame, frame.displayRows)) do height = height + value end
	return height
end

function QuestTogether:CapturePartyQuestScrollAnchor(rowID, visibleOnly)
	local frame, session = rawget(self, "partyQuestCompareWindow"), rawget(self, "partyQuestCompareSession")
	if not frame or not session or frame.displaySession ~= session then return end
	local pixels, y, anchor = session.scrollPixels or 0, 0
	local heights = RowHeights(frame, frame.displayRows or {})
	for i, row in ipairs(frame.displayRows or {}) do
		local height = heights[i]
		if height > 0 and Selectable(row) then
			if rowID and RowID(row) == rowID then
				if not visibleOnly or y + height > pixels and y < pixels + frame.rowsViewport:GetHeight() then
					return { rowId = rowID, questId = row.questId, offset = pixels - y }
				end
				return
			elseif not rowID and y <= pixels then
				anchor = { rowId = RowID(row), questId = row.questId, offset = pixels - y }
			end
		end
		y = y + height
	end
	return anchor
end

local function RestoreScrollAnchor(addon, session, rows, frame)
	local anchor = session.restoreAnchor
	if not anchor then return end
	local anchorRowId = addon.ResolvePartyQuestChainRowID and addon:ResolvePartyQuestChainRowID(anchor.rowId) or anchor.rowId
	local y, heights = 0, frame and RowHeights(frame, rows)
	for i, row in ipairs(rows) do
		if Selectable(row) and (anchorRowId and RowID(row) == anchorRowId or not anchor.rowId and row.questId == anchor.questId) then session.scrollPixels = y + anchor.offset; break end
		y = y + (heights and heights[i] or CompareRowHeight(rows, i))
	end
	for _, member in ipairs(session.members) do
		if member.state == "loading" or addon:HasPendingPartyQuestProgress(member) then return end
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
	if self.ParkPartyQuestGamepadSelection and not self:ParkPartyQuestGamepadSelection(frame) then return end
	local rows = frame.displayRows
	local heights, offsets = RowHeights(frame, rows)
	local maximum = math.max(0, CompareHeight(frame) - frame.rowsViewport:GetHeight())
	pixels = math.max(0, math.min(pixels, maximum))
	local visible, keys, y = {}, {}, 0
	frame.navigationRows = {}
	for index, data in ipairs(rows) do
		local height = heights[index]
		if height > 0 and Selectable(data) then
			frame.navigationRows[#frame.navigationRows + 1] = { rowId = RowID(data), questId = data.questId, top = y, height = height, data = data }
		end
		if height > 0 and y + height > pixels and y < pixels + frame.rowsViewport:GetHeight() then
			visible[#visible + 1] = { index = index, top = y, height = height, clipOffset = offsets[index] }
			keys[#keys + 1] = index
		end
			y = y + height
	end
	if frame.keyboardSession == session then
		local selected = self:GetPartyQuestKeyboardTarget(frame.navigationRows, session.keyboardRowId or session.keyboardQuestId)
		local id = RowID(selected)
		if session.keyboardRowId ~= id then self:SelectPartyQuestKeyboardRow(frame, selected); force = true
		else session.keyboardQuestId = selected and selected.questId end
	end
	local origin = visible[1] and visible[1].top or 0
	session.scrollPixels, session.offset = pixels, visible[1] and visible[1].index - 1 or 0
	frame.visibleRows = visible
	if self.SetPartyQuestCompletionInterest then
		local interested, included = {}, {}
		for _, slot in ipairs(visible) do
			local id = rows[slot.index].questId
			if id and not rows[slot.index].chainClosing and not included[id] then interested[#interested + 1], included[id] = id, true end
		end
		self:SetPartyQuestCompletionInterest(interested)
	end
	for i, row in ipairs(frame.rows) do
		local slot = visible[i]
		if slot then
			row.clip:ClearAllPoints()
			row.clip:SetPoint("TOPLEFT", frame.rowsContent, "TOPLEFT", 0, -(slot.top - origin))
			row.clip:SetSize(frame.content:GetWidth(), math.max(0.01, slot.height))
			row.clip:SetVerticalScroll(slot.clipOffset or 0)
		end
	end
	local key = table.concat(keys, ",")
	if force or frame.drawnKey ~= key then
		DrawCompareRows(self, frame, session, rows, frame.content:GetWidth(), frame.content:GetWidth() - ACTION_WIDTH)
		frame.drawnKey = key
	end
	frame.rowsViewport:SetVerticalScroll(pixels - origin)
	frame.scrolling = true
	self:UpdateOwnedScrollBar(frame.vertical, pixels, maximum, frame.rowsViewport:GetHeight(), ROW_HEIGHT)
	frame.scrolling = false
	if self.UpdatePartyQuestKeyboardPresentation then self:UpdatePartyQuestKeyboardPresentation(frame) end
	if self.RefreshPartyQuestGamepad then self:RefreshPartyQuestGamepad(frame) end
end

-- Keyboard and native directional navigation use this same logical geometry;
-- the ScrollFrame itself contains only the currently materialized row slice.
function QuestTogether:ScrollPartyQuestCompareToRow(frame, rowID)
	local session = self.partyQuestCompareSession
	if not session or frame.displaySession ~= session or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	if self.ResolvePartyQuestChainRowID then rowID = self:ResolvePartyQuestChainRowID(rowID) end
	for _, selected in ipairs(frame.navigationRows or {}) do
		if RowID(selected) == rowID or (type(rowID) == "number" and selected.questId == rowID) then
			frame.wheelTarget = nil
			frame:SetScript("OnUpdate", nil)
			local pixels, height = session.scrollPixels or 0, frame.rowsViewport:GetHeight()
			if selected.top < pixels then pixels = selected.top
			elseif selected.top + selected.height > pixels + height then pixels = selected.top + selected.height - height end
			ScrollCompare(self, frame, session, pixels, true)
			return true
		end
	end
	return false
end

function QuestTogether:ScrollPartyQuestCompareToQuest(frame, questID)
	return self:ScrollPartyQuestCompareToRow(frame, questID)
end

function QuestTogether:RevealPartyQuestGamepadControl(frame, identity)
	if not identity or self:IsWorkBlocked("foreign_frame_mutation") then return end
	local left, width
	if identity.player then
		for index, member in ipairs(frame.displaySession.members) do
			if member.name == identity.player then left, width = ColumnLeft(frame, index), ColumnWidth(frame, index); break end
		end
	elseif identity.role == "action" then left, width = frame.content:GetWidth() - ACTION_WIDTH, ACTION_WIDTH
	elseif identity.rowId or identity.questId then left, width = 0, QUEST_WIDTH end
	if not left then return end
	local offset, visible = frame.horizontalOffset or 0, frame.viewport:GetWidth()
	if left < offset then offset = left elseif left + width > offset + visible then offset = left + width - visible end
	local maximum = math.max(0, frame.content:GetWidth() - visible)
	frame.horizontalOffset = self:UpdateOwnedScrollBar(frame.horizontal, offset, maximum, visible, MEMBER_WIDTH)
	frame.viewport:SetHorizontalScroll(frame.horizontalOffset)
end

local function StopExpansion(frame)
	frame.expansions, frame.animateExpansion, frame.expansionGeneration = nil, nil, nil
	if frame.expansionAnimator and QuestTogether.LibChev.CanMutateOwnedRegion(frame.expansionAnimator) then
		frame.expansionAnimator:SetScript("OnUpdate", nil)
	end
end

local function StopChainExpansion(frame)
	frame.chainExpansion = nil
	local rows = {}
	for _, row in ipairs(frame.displayRows or {}) do if not row.chainClosing then rows[#rows + 1] = row end end
	frame.displayRows = rows
	if frame.chainAnimator and QuestTogether.LibChev.CanMutateOwnedRegion(frame.chainAnimator) then
		frame.chainAnimator:SetScript("OnUpdate", nil)
	end
end

local function ChainPresentation(rows, questID)
	local root, index, instance
	for i, row in ipairs(rows or {}) do
		if not row.kind and (questID and row.questId == questID or not questID and row.chainExpanded) then
			root, index, instance = row, i, row.chainInstanceId
			break
		end
	end
	if not root then return end
	local result = { questId = root.questId, before = {}, after = {}, sides = {} }
	for i, row in ipairs(rows) do
		if row.kind and row.kind:sub(1, 5) == "chain" and row.chainInstanceId
			and (not instance or row.chainInstanceId == instance) then
			local side = i < index and "before" or "after"
			result[side][#result[side] + 1], result.sides[row] = row, side
		end
	end
	return result
end

local function PrepareChainExpansion(self, frame, session, oldRows)
	local rows = frame.displayRows
	local current = ChainPresentation(rows)
	local rootID, previousID = current and current.questId, frame.chainExpandedQuestID
	frame.chainExpandedQuestID = rootID
	if self:GetOption("reduceMotion") or frame.chainDisplaySession ~= session then
		StopChainExpansion(frame); frame.chainDisplaySession = session; return
	end
	local transition, restarting = frame.chainExpansion, false
	local opening = rootID ~= nil
	local id = rootID or transition and transition.questId or previousID
	local old = id and ChainPresentation(oldRows, id)
	if not id or not ChainPresentation(rows, id) or opening and not next(current.sides) then
		StopChainExpansion(frame); return
	end
	if not transition or transition.questId ~= id then
		if opening and previousID == id and old and next(old.sides) then return end
		if not opening and (not old or not next(old.sides)) then StopChainExpansion(frame); return end
		transition = { questId = id, from = opening and 0 or 1, reveal = opening and 0 or 1,
			target = opening and 1 or 0, elapsed = 0 }
		restarting = true
	elseif transition.target ~= (opening and 1 or 0) then
		transition.from, transition.elapsed, transition.target = transition.reveal, 0, opening and 1 or 0
		restarting = true
	end
	if restarting then
		-- Momentum targets belong to the geometry before the toggle. Preserve
		-- wheel input received later during a normal presentation refresh.
		frame.wheelTarget, frame.wheelSession = nil, nil
		frame:SetScript("OnUpdate", nil)
	end
	transition.sides = {}
	if opening then
		transition.sides, transition.closing = current.sides, nil
	else
		if not transition.closing then
			transition.closing = { before = {}, after = {} }
			for _, side in ipairs({ "before", "after" }) do
				for _, row in ipairs(old and old[side] or {}) do
					local copy = {}
					for key, value in pairs(row) do copy[key] = value end
					copy.chainClosing, copy.selectable = true, false
					transition.closing[side][#transition.closing[side] + 1] = copy
				end
			end
		end
		local closingIDs = {}
		for _, side in ipairs({ "before", "after" }) do
			for _, row in ipairs(transition.closing[side]) do closingIDs[RowID(row)] = true end
		end
		if closingIDs[session.keyboardRowId] then
			session.keyboardRowId, session.keyboardQuestId, session.keyboardRole, session.keyboardPlayer = "quest:" .. id, id, "quest", nil
		end
		local navigation = frame.gamepadNavigation
		if navigation and navigation.selected and closingIDs[navigation.selected.rowId] then
			navigation.selected, navigation.armed = { session = session, rowId = "quest:" .. id, role = "quest" }, nil
		end
		local display, pending = {}, false
		local function Append(side)
			for _, row in ipairs(transition.closing[side]) do
				display[#display + 1], transition.sides[row] = row, side
			end
		end
		for _, row in ipairs(rows) do
			if pending and not (ObjectiveDetail(row) and row.questId == id) then Append("after"); pending = false end
			if not row.kind and row.questId == id then Append("before"); pending = true end
			display[#display + 1] = row
		end
		if pending then Append("after") end
		frame.displayRows = display
	end
	frame.chainExpansion = transition
	local generation = {}
	local chains, profile = session.chains, self.db and self.db.profile
	transition.generation = generation
	frame.chainAnimator:SetScript("OnUpdate", function(_, elapsed)
		if frame.chainExpansion ~= transition or transition.generation ~= generation then return end
		if self.partyQuestCompareSession ~= session or frame.displaySession ~= session or not self.isEnabled or self.isLoggingOut
			or session.chains ~= chains or chains and chains.retired or (self.db and self.db.profile) ~= profile then
			StopChainExpansion(frame); return
		end
		if self:IsWorkBlocked("foreign_frame_mutation") then return end
		local anchor = self:CapturePartyQuestScrollAnchor("quest:" .. id, true) or self:CapturePartyQuestScrollAnchor()
		transition.elapsed = math.min(0.18, transition.elapsed + math.min(elapsed, 0.1))
		local t = self:GetOption("reduceMotion") and 1 or transition.elapsed / 0.18
		transition.reveal = transition.from + (transition.target - transition.from) * t * t * (3 - 2 * t)
		if t >= 1 then
			local display = {}
			for _, row in ipairs(frame.displayRows) do if not row.chainClosing then display[#display + 1] = row end end
			frame.displayRows = display
			StopChainExpansion(frame)
		end
		session.restoreAnchor = anchor
		RestoreScrollAnchor(self, session, frame.displayRows, frame)
		ScrollCompare(self, frame, session, session.scrollPixels or 0, true)
	end)
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
				if not (ObjectiveDetail(row) and remove[row.questId]) then
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
		if ObjectiveDetail(row) then
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
				-- The retained animation follows the current row's section, even
				-- when a chain is opened or closed before the animation finishes.
				detail.chainInstanceId = row.chainInstanceId
				detail.chainGroupId, detail.chainGroupMember = row.chainGroupId, row.chainGroupMember
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
	if QuestTogether.LibChev.CanMutateOwnedRegion(frame) then frame:SetScript("OnUpdate", nil) end
end

function QuestTogether:SetPartyQuestKeyboardNavigation(frame, active)
	local session = self.partyQuestCompareSession
	if active and (not session or frame.displaySession ~= session
		or (self.IsPartyQuestGamepadInputOwned and self:IsPartyQuestGamepadInputOwned())
		or self:IsWorkBlocked("foreign_frame_mutation")
		or not QuestTogether.LibChev.CanMutateOwnedRegion(frame) or not frame:IsVisible()
		or not self.API.IsPartyQuestKeyboardInputBlocked or self.API.IsPartyQuestKeyboardInputBlocked(frame)) then
		return false
	end
	local wasActive = frame.keyboardSession ~= nil or frame.keyboardFocusPending ~= nil
	frame.keyboardFocusPending = nil
	frame.keyboardSession = active and session or nil
	if wasActive and not active and frame.keyboardInput then self:HideOwnedUI(frame.keyboardInput) end
	if not self:IsWorkBlocked("foreign_frame_mutation") and QuestTogether.LibChev.CanMutateOwnedRegion(frame) then
		if active and frame.keyboardInput then
			self:CancelOwnedUICleanup(frame.keyboardInput)
			frame.keyboardInput:SetPropagateKeyboardInput(true)
			frame.keyboardInput:Show()
		end
		if session and frame.displaySession == session then
			if active then
				local selected = self:GetPartyQuestKeyboardTarget(frame.navigationRows, session.keyboardRowId or session.keyboardQuestId)
				self:SelectPartyQuestKeyboardRow(frame, selected, session.keyboardRole, session.keyboardPlayer)
			end
			ScrollCompare(self, frame, session, session.scrollPixels or 0, true)
		end
	end
	return true
end

function QuestTogether:PopulatePartyQuestContextMenu(frame, selected, root)
	local session, questID = self.partyQuestCompareSession, selected and selected.questId
	local profile, rowID = self.db and self.db.profile, RowID(selected)
	if not session or frame.displaySession ~= session or not rowID or self:IsWorkBlocked("foreign_frame_mutation")
		or not QuestTogether.LibChev.CanMutateOwnedRegion(frame) or not frame:IsVisible() then return false end
	local chainExpanded = selected.data and selected.data.chainExpanded == true
	local chainInstance = session.chains and session.chains.instance
	local function Current(action, owner)
		if self.partyQuestCompareSession ~= session or frame.displaySession ~= session
			or (self.db and self.db.profile) ~= profile
			or not QuestTogether.LibChev.CanMutateOwnedRegion(frame) or not frame:IsVisible()
			or self:IsWorkBlocked("foreign_frame_mutation") then return false end
		for _, entry in ipairs(frame.navigationRows or {}) do
			if RowID(entry) == rowID then
				if action == "chain" then
					return entry.data.chainAvailable == true and (entry.data.chainExpanded == true) == chainExpanded
						and (not chainInstance or session.chains and session.chains.instance == chainInstance)
				end
				return not action or (entry.data.action == action and entry.data.owner == owner)
			end
		end
		return false
	end
	if not Current() then return false end
	local data = selected.data
	root:CreateTitle(QuestTitle(data))
	if not data.kind then
		root:CreateButton(L("Expand or collapse quest"), function()
			if Current() then self:TogglePartyQuestObjectives(questID) end
		end)
		if data.chainAvailable == true and self.TogglePartyQuestChain then
			root:CreateButton(chainExpanded and L("Close chain") or L("View chain"), function()
				if Current("chain") then self:TogglePartyQuestChain(questID, rowID); self:RequestPartyQuestKeyboardFocus(frame) end
			end)
		end
	elseif data.kind == "chainGroup" or data.kind == "chainMore" then
		root:CreateButton(data.title, function()
			if Current() then self:ActivatePartyQuestListRow(frame, data); self:RequestPartyQuestKeyboardFocus(frame) end
		end)
	end
	if (data.kind == "chainStep" or data.chainAnchor) and self.GetPartyQuestChainActions then
		for _, descriptor in ipairs(self:GetPartyQuestChainActions(data, selected.player) or {}) do
			local action = descriptor.action
			local choice = root:CreateButton(descriptor.label, function()
				if Current() and not descriptor.disabled and type(action) == "function" then action() end
			end)
			if choice and choice.SetEnabled then choice:SetEnabled(not descriptor.disabled) end
		end
	end
	local own = session.byName and session.byName[session.playerName]
	if not data.kind and questID and own and own.entries and own.entries[questID] then
		root:CreateButton(L("Open in Quest Log"), function()
			if Current() then self:OpenPartyQuestJournal(questID) end
		end)
	end
	if not data.kind and data.action then
		local action, owner = data.action, data.owner
		local choice = root:CreateButton(action == "share" and L("Share") or L("Request Share"), function()
			if not Current(action, owner) then return end
			local readiness = self.GetPartyQuestShareReadiness and self:GetPartyQuestShareReadiness(questID, action, owner)
			if readiness and readiness.disabled then return end
			if action == "share" then self:SharePartyDiffQuest(questID)
			else self:RequestPartyQuestShare(questID, owner) end
		end)
		if choice and choice.SetEnabled then choice:SetEnabled(not (data.shareReadiness and data.shareReadiness.disabled)) end
	end
	return true
end

function QuestTogether:ShowPartyQuestKeyboardMenu(frame, selected)
	local session, rowID = self.partyQuestCompareSession, RowID(selected)
	if not session or frame.displaySession ~= session or not rowID then return false end
	self:SetPartyQuestKeyboardNavigation(frame, false)
	local anchor = frame.rowsViewport
	for _, row in ipairs(frame.rows) do
		if row.session == session and row.data and RowID(row.data) == rowID and row:IsVisible() then
			anchor = row
			break
		end
	end
	return self:CreatePartyQuestFilterMenu(anchor, function(_, root)
		if self.partyQuestCompareSession == session then self:PopulatePartyQuestContextMenu(frame, selected, root) end
	end)
end

function QuestTogether:PopulatePartyQuestPlayerMenu(frame, session, name, root)
	local profile = self.db and self.db.profile
	local function Current()
		return self.partyQuestCompareSession == session and frame.displaySession == session
			and (self.db and self.db.profile) == profile
			and session.byName[name] and QuestTogether.LibChev.CanMutateOwnedRegion(frame) and frame:IsVisible()
			and not self:IsWorkBlocked("foreign_frame_mutation")
	end
	if not Current() then return false end
	root:CreateTitle(name)
	local collapsed = session.collapsedPlayers and session.collapsedPlayers[name]
	root:CreateButton(collapsed and L("Expand player column") or L("Collapse player column"), function()
		if Current() then self:SetPartyQuestColumnCollapsed(name, not collapsed, session) end
	end)
	root:CreateButton(L("Restore all player columns"), function()
		if Current() then self:RestorePartyQuestColumns(session) end
	end)
	root:CreateDivider()
	if not session.byName[name].isLocal then
		root:CreateButton(L("Refresh this player"), function()
			if Current() then self:RefreshPartyQuestCompareMember(name) end
		end)
		self:PopulatePartyFocusMenu(root, name)
		if self.PopulatePlayerNotesMenu then self:PopulatePlayerNotesMenu(root, name) end
	end
	return true
end

function QuestTogether:RequestPartyQuestKeyboardFocus(frame)
	if not self.partyQuestCompareSession or self:IsWorkBlocked("foreign_frame_mutation")
		or (self.IsPartyQuestGamepadInputOwned and self:IsPartyQuestGamepadInputOwned())
		or not QuestTogether.LibChev.CanMutateOwnedRegion(frame) or not frame:IsVisible() then return end
	self:SetPartyQuestKeyboardNavigation(frame, false)
	frame.keyboardFocusPending = self.partyQuestCompareSession
	self:CancelOwnedUICleanup(frame.keyboardInput)
	frame.keyboardInput:SetPropagateKeyboardInput(true)
	frame.keyboardInput:Show()
end

function QuestTogether:ConfigurePartyQuestKeyboardNavigation(frame)
	-- Only this child captures navigation keys. Hiding an ordinary owned frame
	-- retires input during combat without changing a restricted input attribute.
	local input = self:CreateOwnedWindowFrame("Frame", nil, frame)
	frame.keyboardInput = input
	input:SetAllPoints(frame)
	input:SetFrameLevel(frame:GetFrameLevel() + 20)
	input:EnableKeyboard(true)
	input:SetPropagateKeyboardInput(true)
	input:Hide()
	-- Defer opening focus until the first render and the slash-command/menu
	-- click that opened us have finished. Outside clicks and hide cancel it.
	frame:HookScript("OnShow", function() self:RequestPartyQuestKeyboardFocus(frame) end)
	frame.search:HookScript("OnEditFocusGained", function() self:SetPartyQuestKeyboardNavigation(frame, false) end)
	frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function(_, event)
		if (frame.keyboardSession or frame.keyboardFocusPending) and (event == "PLAYER_REGEN_DISABLED"
			or (event == "GLOBAL_MOUSE_DOWN"
				and (not self.API.IsMouseOverPartyQuestWindow or not self.API.IsMouseOverPartyQuestWindow(frame)))) then
			self:SetPartyQuestKeyboardNavigation(frame, false)
		end
	end)
	local inherited = frame:GetScript("OnKeyDown")
	frame:SetScript("OnKeyDown", function(_, key)
		if not frame.keyboardSession and not self:IsWorkBlocked("foreign_frame_mutation")
			and not (self.IsPartyQuestGamepadInputOwned and self:IsPartyQuestGamepadInputOwned())
			and QuestTogether.LibChev.CanMutateOwnedRegion(frame)
			and not (self.API.IsPartyQuestKeyboardInputBlocked and self.API.IsPartyQuestKeyboardInputBlocked(frame)) then
			if inherited then inherited(frame, key) end
		end
	end)
	input:SetScript("OnKeyDown", function(_, key)
		local session = self.partyQuestCompareSession
		if self:IsWorkBlocked("foreign_frame_mutation") or not QuestTogether.LibChev.CanMutateOwnedRegion(frame)
			or (self.IsPartyQuestGamepadInputOwned and self:IsPartyQuestGamepadInputOwned()) then
			self:SetPartyQuestKeyboardNavigation(frame, false)
			return
		end
		input:SetPropagateKeyboardInput(true)
		if self.API.IsPartyQuestKeyboardInputBlocked and self.API.IsPartyQuestKeyboardInputBlocked(frame) then
			self:SetPartyQuestKeyboardNavigation(frame, false)
			return
		end
		if not frame.keyboardSession then
			return
		end
		if not session or frame.keyboardSession ~= session or frame.displaySession ~= session or not frame:IsVisible() then
			self:SetPartyQuestKeyboardNavigation(frame, false)
			return
		end
		if key == "ESCAPE" then
			input:SetPropagateKeyboardInput(false)
			self:BackPartyQuestCompare(frame, "escape")
			return
		elseif key == "TAB" then
			input:SetPropagateKeyboardInput(false)
			frame.search:SetFocus()
			return
		end
		local moves = key == "UP" or key == "DOWN" or key == "HOME" or key == "END"
			or key == "PAGEUP" or key == "PAGEDOWN"
		local selected = self:GetPartyQuestKeyboardTarget(frame.navigationRows, session.keyboardRowId or session.keyboardQuestId,
			moves and key or nil, frame.rowsViewport:GetHeight())
		if not selected then return end
		if moves then
			self:SelectPartyQuestKeyboardRow(frame, selected, session.keyboardRole, session.keyboardPlayer)
			StopCompareScroll(frame)
			self:ScrollPartyQuestCompareToRow(frame, RowID(selected))
		elseif key == "LEFT" or key == "RIGHT" or key == "ENTER" or key == "NUMPADENTER" then
			local controls = self:GetPartyQuestRowControls(frame, selected)
			local position = 1
			for index, control in ipairs(controls) do
				if control.role == session.keyboardRole and control.player == session.keyboardPlayer then position = index; break end
			end
			if key == "LEFT" or key == "RIGHT" then
				position = math.max(1, math.min(#controls, position + (key == "LEFT" and -1 or 1)))
				local control = controls[position]
				if control then
					self:SelectPartyQuestKeyboardRow(frame, selected, control.role, control.player)
					self:RevealPartyQuestGamepadControl(frame, { rowId = RowID(selected), role = control.role, player = control.player })
					self:UpdatePartyQuestKeyboardPresentation(frame)
				end
			else
				local control = controls[position]
				if control then
					local script = control.button:GetScript(position == 1 and "OnMouseUp" or "OnClick")
					if script then script(control.button, "LeftButton") end
				end
			end
		elseif key == "SPACE" or key == "MENU" or key == "APPS" then
			self:ShowPartyQuestKeyboardMenu(frame, { rowId = RowID(selected), questId = selected.questId,
				data = selected.data, player = session.keyboardPlayer })
		else
			-- Movement, chat, and other bindings remain untouched.
			self:SetPartyQuestKeyboardNavigation(frame, false)
			return
		end
		input:SetPropagateKeyboardInput(false)
	end)
	input:SetScript("OnKeyUp", function()
		if self:IsWorkBlocked("foreign_frame_mutation") then
			self:SetPartyQuestKeyboardNavigation(frame, false)
		elseif QuestTogether.LibChev.CanMutateOwnedRegion(input) then
			input:SetPropagateKeyboardInput(true)
		end
	end)
	input:SetScript("OnUpdate", function()
		if self:IsWorkBlocked("foreign_frame_mutation") or (self.IsPartyQuestGamepadInputOwned and self:IsPartyQuestGamepadInputOwned()) then
			self:SetPartyQuestKeyboardNavigation(frame, false)
		elseif frame.keyboardFocusPending then
			local expected = frame.keyboardFocusPending
			if self.partyQuestCompareSession ~= expected or not frame:IsVisible() then
				self:SetPartyQuestKeyboardNavigation(frame, false)
			elseif frame.displaySession == expected then
				self:SetPartyQuestKeyboardNavigation(frame, false)
				self:SetPartyQuestKeyboardNavigation(frame, true)
			end
		elseif frame.keyboardSession and self.API.IsPartyQuestKeyboardInputBlocked(frame) then
			self:SetPartyQuestKeyboardNavigation(frame, false)
		end
	end)
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
	local parent = self:GetOwnedUIParent()
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
	frame.expansionAnimator = self:CreateOwnedWindowFrame("Frame", nil, frame)
	frame.chainAnimator = self:CreateOwnedWindowFrame("Frame", nil, frame)
	frame.summary = Label(frame, 20, -47, width - 40, "", "GameFontHighlight")
	frame.searchLabel = Label(frame, 20, -80, 65, L("Search:"), "GameFontHighlight")
	frame.search = self:CreateOwnedWindowFrame("EditBox", nil, frame, "SearchBoxTemplate")
	frame.search:SetPoint("TOPLEFT", 88, -74)
	frame.search:SetSize(math.max(100, math.min(300, width - 500)), 26)
	frame.search:SetAutoFocus(false)
	frame.search:SetMaxLetters(96)
	frame.search:HookScript("OnTextChanged", function(edit)
		if not frame.rendering then
			self:SetPartyQuestCompareFilter("search", edit:GetText())
		end
	end)
	local function FocusList(edit)
		if self:IsWorkBlocked("foreign_frame_mutation") or not QuestTogether.LibChev.CanMutateOwnedRegion(edit) then return end
		edit:ClearFocus()
		self:SetPartyQuestKeyboardNavigation(frame, true)
	end
	frame.search:HookScript("OnEscapePressed", FocusList)
	frame.search:HookScript("OnEnterPressed", FocusList)
	frame.search:HookScript("OnTabPressed", FocusList)
	frame.filter = Button(self, frame, width - 386, -74, 124, L("Filters"), function(button)
		self:SetPartyQuestKeyboardNavigation(frame, false)
		self:ShowPartyQuestCompareFilters(button)
	end)
	frame.reset = Button(self, frame, width - 250, -74, 100, L("Reset"), function()
		self:ResetPartyQuestCompareFilters()
	end)
	frame.activeFilters = Label(frame, 20, -111, width - 62, "", "GameFontHighlight")
	frame.activeFilters:SetMaxLines(1)
	frame.chainProviderNotice = self:CreateOwnedWindowFrame("Frame", nil, frame)
	frame.chainProviderNotice:SetPoint("TOPLEFT", 20, -132)
	frame.chainProviderNotice:SetHeight(70)
	frame.chainProviderNotice.background = frame.chainProviderNotice:CreateTexture(nil, "BACKGROUND")
	frame.chainProviderNotice.background:SetAllPoints()
	frame.chainProviderNotice.title = Label(frame.chainProviderNotice, 10, -7, width - 82,
		L("Quest chains need QuestieDB"), "GameFontNormal")
	frame.chainProviderNotice.body = Label(frame.chainProviderNotice, 10, -26, width - 82,
		L("Install and enable QuestieDB for WoW Forever in your addon manager, then restart WoW. QuestTogether's other features work without it."), "GameFontHighlightSmall")
	frame.chainProviderNotice.body:SetHeight(40)
	frame.chainProviderNotice.body:SetJustifyV("TOP")
	frame.chainProviderNotice:Hide()
	frame.refresh = Button(self, frame, width - 140, -72, 112, L("Refresh"), function()
		self:RefreshPartyRoster()
		self:RefreshPartyQuestCompare()
	end)
	local close = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close = close
	close:SetPoint("TOPRIGHT", 2, 1)
	close:SetScript("OnClick", function() self:DismissManagedWindow(frame) end)
	self:ConfigureWindowController(frame, {
		dismiss = function() self:CancelPartyQuestCompare() end,
		suspend = function()
			self:SetPartyQuestKeyboardNavigation(frame, false)
			StopCompareScroll(frame); StopExpansion(frame); StopChainExpansion(frame)
			self:StopOwnedScrollBar(frame.vertical); self:StopOwnedScrollBar(frame.horizontal)
		end,
		theme = function()
			if self.partyQuestCompareSession then self:RenderPartyQuestCompare() end
		end,
	})

	frame.viewport = self:CreateOwnedWindowFrame("ScrollFrame", nil, frame)
	frame.viewport:SetPoint("TOPLEFT", 20, -140)
	frame.viewport:SetSize(width - 62, VISIBLE_ROWS * ROW_HEIGHT + 54)
	frame.content = self:CreateOwnedWindowFrame("Frame", nil, frame.viewport)
	frame.content:SetSize(QUEST_WIDTH + ACTION_WIDTH, VISIBLE_ROWS * ROW_HEIGHT + 54)
	frame.viewport:SetScrollChild(frame.content)
	frame.questHeader = Label(frame.content, 4, 0, QUEST_WIDTH - 8, L("QUEST"), "GameFontNormal")
	frame.rowsViewport = self:CreateOwnedWindowFrame("ScrollFrame", nil, frame.content)
	frame.rowsViewport:SetPoint("TOPLEFT", 0, -54)
	frame.rowsViewport:SetSize(QUEST_WIDTH + ACTION_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
	frame.rowsContent = self:CreateOwnedWindowFrame("Frame", nil, frame.rowsViewport)
	frame.rowsContent:SetSize(QUEST_WIDTH + ACTION_WIDTH, (VISIBLE_ROWS * 2 + 2) * ROW_HEIGHT)
	frame.rowsViewport:SetScrollChild(frame.rowsContent)
	frame.headers, frame.headerAccents, frame.rows = {}, {}, {}
	frame.headerCrowns, frame.columnToggles = {}, {}
	frame.columns, frame.memberColumnsWidth = self:GetPartyQuestCompareColumns(self.partyQuestCompareSession)
	frame.focusButtons, frame.headerStatuses = {}, {}
	frame.followStatus = Label(frame.content, 4, -18, QUEST_WIDTH - 130, "", "GameFontHighlightSmall")
	frame.followStatus:SetHeight(34)
	frame.stopFollowing = Button(self, frame.content, QUEST_WIDTH - 124, -22, 116, L("Stop following"), function()
		self:StopPartyQuestFollow()
	end)
	frame.stopFollowing:HookScript("OnEnter", function()
		if self:GetAutomaticLeaderFocusTarget() then
			self:ShowSettingsTooltip(frame.stopFollowing, L("Stop following"), L("Turn off Automatically follow the party leader's quest focus in QT settings to stop following or choose another person."))
		end
	end)
	frame.stopFollowing:HookScript("OnLeave", function() self:HideSettingsTooltip(frame.stopFollowing) end)
	frame.stopFollowing:HookScript("OnHide", function() self:HideSettingsTooltip(frame.stopFollowing) end)
	frame.stopFollowing:Hide()
	local function EnsureRows(count)
		for i = #frame.rows + 1, count do
			local clip = self:CreateOwnedWindowFrame("ScrollFrame", nil, frame.rowsContent)
			local row = self:CreateOwnedWindowFrame("Frame", nil, clip)
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
			row.branch = row:CreateTexture(nil, "ARTWORK")
			row.branchStem = row:CreateTexture(nil, "ARTWORK")
			row.groupRail = row:CreateTexture(nil, "ARTWORK")
			row.groupEnd = row:CreateTexture(nil, "ARTWORK")
			row.chainEdges = {}
			for edge = 1, 4 do row.chainEdges[edge] = row:CreateTexture(nil, "OVERLAY") end
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
			row.keyboardHighlight = row:CreateTexture(nil, "OVERLAY")
			row.keyboardHighlight:SetAllPoints()
			row.keyboardHighlight:SetColorTexture(0.95, 0.72, 0.20, 0.18)
			row.keyboardHighlight:Hide()
			row.hover = row:CreateTexture(nil, "BORDER")
			row.hover:SetAllPoints()
			ColorPanel(row.hover, 0.35, 0.24, 0.10, 0.08)
			ShowPanel(row.hover, false)
			row:SetScript("OnMouseUp", function(_, button)
				if
					button == "LeftButton"
					and row.data
					and Selectable(row.data)
					and row.session == self.partyQuestCompareSession
				then
					if self:IsWorkBlocked("foreign_frame_mutation") or not QuestTogether.LibChev.CanMutateOwnedRegion(frame)
						or not row:IsVisible() then return end
					frame.search:ClearFocus()
					self:SelectPartyQuestKeyboardRow(frame, row.data)
					self:SetPartyQuestKeyboardNavigation(frame, true)
					self:ActivatePartyQuestListRow(frame, row.data)
				end
			end)
			row.title:SetMaxLines(1)
			row.journal = self:CreateOwnedWindowFrame("Button", nil, row)
			row.journal:SetSize(22, 22)
			row.journal:SetPoint("TOPLEFT", QUEST_WIDTH - 32, -4)
			row.journal:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			local journalIcon = row.journal:CreateTexture(nil, "ARTWORK")
			journalIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
			journalIcon:SetSize(18, 18)
			journalIcon:SetPoint("CENTER")
			row.journal:SetScript("OnEnter", function()
				if row.data and (not row.data.kind or row.data.kind == "chainStep") and row.session == self.partyQuestCompareSession then
					self:ShowSettingsTooltip(row.journal, L("Open in Quest Log"), self:AppendQuestIDToTooltipText(row.data.questId, QuestTitle(row.data)))
				end
			end)
			local function HideJournalTooltip() self:HideSettingsTooltip(row.journal) end
			row.journal:SetScript("OnLeave", HideJournalTooltip)
			row.journal:SetScript("OnHide", HideJournalTooltip)
			row.journal:SetScript("OnClick", function()
				if row.session ~= self.partyQuestCompareSession or not row.data or row.data.chainClosing then return end
				self:SetPartyQuestKeyboardNavigation(frame, false)
				HideJournalTooltip()
				if row.data and (not row.data.kind or row.data.kind == "chainStep") and row.session == self.partyQuestCompareSession then
					self:OpenPartyQuestJournal(row.data.questId)
				end
			end)
			row.chain = self:CreateOwnedWindowFrame("Button", nil, row)
			row.chain:SetSize(22, 22)
			row.chain:SetPoint("TOPLEFT", QUEST_WIDTH - 58, -4)
			if row.chain.SetMotionScriptsWhileDisabled then row.chain:SetMotionScriptsWhileDisabled(true) end
			row.chain:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			local chainIcon = row.chain:CreateTexture(nil, "ARTWORK")
			chainIcon:SetTexture("Interface\\AddOns\\QuestTogether\\Media\\QuestChain.tga")
			chainIcon:SetSize(18, 18); chainIcon:SetPoint("CENTER")
			row.chainIcon = chainIcon
			row.chainDots = {}
			for index = 1, 8 do
				local angle = (index - 1) * math.pi / 4
				local dot = row.chain:CreateTexture(nil, "ARTWORK")
				dot:SetSize(3, 3); dot:SetPoint("CENTER", math.sin(angle) * 6, math.cos(angle) * 6)
				dot:Hide(); row.chainDots[index] = dot
			end
			row.chain:SetScript("OnEnter", function()
				if row.data and row.session == self.partyQuestCompareSession then
					self:ShowSettingsTooltip(row.chain, row.chain.loading and L("Loading quest chain information")
						or row.data.chainExpanded and L("Close chain") or L("View chain"),
						self:AppendQuestIDToTooltipText(row.data.questId, QuestTitle(row.data)))
				end
			end)
			local function HideChainTooltip() self:HideSettingsTooltip(row.chain) end
			row.chain:SetScript("OnLeave", HideChainTooltip)
			row.chain:SetScript("OnHide", function() HideChainTooltip(); StopChainLoading(row) end)
			row.chain:SetScript("OnClick", function()
				HideChainTooltip()
				if row.session == self.partyQuestCompareSession and row.data and not row.data.kind and row.data.chainAvailable == true
					and row.chain:IsVisible() and not self:IsWorkBlocked("foreign_frame_mutation") and self.TogglePartyQuestChain then
					self:TogglePartyQuestChain(row.data.questId, RowID(row.data))
				end
			end)

			row:EnableMouse(true)
			row:SetScript("OnEnter", function()
				if row.data and row.session == self.partyQuestCompareSession then
					ShowPanel(row.hover, true)
					self:ShowSettingsTooltip(row, QuestTitle(row.data), self:AppendQuestIDToTooltipText(row.data.questId, row.data.hint or ""))
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
				if not data or not data.action or row.session ~= self.partyQuestCompareSession
					or frame.displaySession ~= row.session or not row:IsVisible()
					or self:IsWorkBlocked("quest_share") or self:IsWorkBlocked("foreign_frame_mutation")
					or not QuestTogether.LibChev.CanMutateOwnedRegion(row.action) then
					return
				end
				if not row.action:IsVisible() or (row.action.IsEnabled and not row.action:IsEnabled())
					or (data.shareReadiness and data.shareReadiness.disabled) then
					-- A click queued before pending/eligibility feedback arrived may
					-- only refresh that explanation, never send another request.
					self:QueuePartyQuestCompareRender()
					return
				end
				local readiness = self.GetPartyQuestShareReadiness and self:GetPartyQuestShareReadiness(data.questId, data.action, data.owner)
				if readiness and readiness.disabled then self:QueuePartyQuestCompareRender(); return end
				if data.action == "share" then
					self:SharePartyDiffQuest(data.questId)
				elseif data.action == "request" then
					self:RequestPartyQuestShare(data.questId, data.owner)
				end
			end)
			if row.action.SetMotionScriptsWhileDisabled then row.action:SetMotionScriptsWhileDisabled(true) end
			row.action:SetScript("OnEnter", function()
				if row.session ~= self.partyQuestCompareSession or not row.data or not row.data.action
					or not row.action:IsVisible() or self:IsWorkBlocked("foreign_frame_mutation")
					or not QuestTogether.LibChev.CanMutateOwnedRegion(row.action) then return end
				local text = ShareReadinessTooltip(self, row.data)
				if text then
					self:ShowSettingsTooltip(row.action, row.data.action == "share" and L("Share") or L("Request Share"),
						self:AppendQuestIDToTooltipText(row.data.questId, text))
				end
			end)
			local function HideActionTooltip() self:HideSettingsTooltip(row.action) end
			row.action:SetScript("OnLeave", HideActionTooltip)
			row.action:SetScript("OnHide", HideActionTooltip)
			row.hint = Label(row, QUEST_WIDTH, -7, ACTION_WIDTH - 8, "", "GameFontHighlight")
			row.hint:SetMaxLines(2)
			row.hint:SetHeight(ROW_HEIGHT - 8)
			row.hint:SetJustifyV("MIDDLE")
			frame.rows[i] = row
		end
	end
	EnsureRows(VISIBLE_ROWS * 2 + 2)
	frame.vertical = self:CreateOwnedScrollBar(self.CreateOwnedWindowFrame, frame, false, function(value)
		local session = self.partyQuestCompareSession
		if session and not frame.rendering and not frame.scrolling then
			session.restoreAnchor = nil
			StopCompareScroll(frame)
			-- Preserve the previous one-pixel thumb step. Percentage round trips
			-- must not leave a row visible at 125.999999 instead of 126 pixels.
			ScrollCompare(self, frame, session, math.floor(value + 0.5))
		end
	end)
	frame.vertical:SetPoint("TOPRIGHT", -18, -194)
	frame.vertical:SetSize(16, VISIBLE_ROWS * ROW_HEIGHT)
	frame.viewport:EnableMouseWheel(true)
	frame.viewport:SetScript("OnMouseWheel", function(_, delta)
		WheelCompare(self, frame, delta)
	end)
	frame.rowsViewport:EnableMouseWheel(true)
	frame.rowsViewport:SetScript("OnMouseWheel", function(_, delta)
		WheelCompare(self, frame, delta)
	end)
	frame.horizontal = self:CreateOwnedScrollBar(self.CreateOwnedWindowFrame, frame, true, function(value)
		frame.horizontalOffset = value
		frame.viewport:SetHorizontalScroll(value)
	end)
	frame.horizontal:SetPoint("TOPLEFT", 26, -618)
	frame.horizontal:SetSize(width - 70, 25)
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
		local noticeHeight = self.chainProviderNotice:IsShown() and 78 or 0
		local rowsHeight = math.max(42, h - 234 - noticeHeight)
		self.title:SetWidth(w - 100)
		self.summary:SetWidth(w - 40)
		self.search:SetWidth(math.max(100, math.min(300, w - 500)))
		for _, control in ipairs({ { self.filter, 386 }, { self.reset, 250 }, { self.refresh, 140 } }) do
			control[1]:ClearAllPoints()
			control[1]:SetPoint("TOPLEFT", w - control[2], -74)
		end
		self.activeFilters:SetWidth(w - 62)
		self.chainProviderNotice:SetWidth(w - 62)
		self.chainProviderNotice.title:SetWidth(w - 82)
		self.chainProviderNotice.body:SetWidth(w - 82)
		self.viewport:ClearAllPoints()
		self.viewport:SetPoint("TOPLEFT", 20, -140 - noticeHeight)
		self.vertical:ClearAllPoints()
		self.vertical:SetPoint("TOPRIGHT", -18, -194 - noticeHeight)
		self.viewport:SetSize(w - 62, rowsHeight + 54)
		self.content:SetHeight(rowsHeight + 54)
		self.rowsViewport:SetHeight(rowsHeight)
		local capacity = 2 * math.ceil(rowsHeight / ROW_HEIGHT) + 2
		EnsureRows(capacity)
		self.rowsContent:SetHeight(#self.rows * ROW_HEIGHT)
		self.vertical:SetHeight(rowsHeight)
		self.horizontal:ClearAllPoints()
		self.horizontal:SetPoint("BOTTOMLEFT", 26, 12)
		self.horizontal:SetWidth(w - 70)
	end
	local screenWidth, screenHeight = parent:GetWidth(), parent:GetHeight()
	frame:SetResizable(true)
	function frame:UpdateResizeBounds(memberCount)
		local minimum = MinimumWidth(memberCount, self.columns)
		screenWidth, screenHeight = parent:GetWidth(), parent:GetHeight()
		local currentScale = self:GetScale()
		if self.minimumWidth == minimum and self.boundsWidth == screenWidth and self.boundsHeight == screenHeight and self.boundsScale == currentScale then
			return
		end
		self.minimumWidth = minimum
		-- A growing party must still fit on a small display. Do not increase
		-- the scale again on departure and unexpectedly enlarge the window.
		scale = math.min(self:GetScale() or scale, screenWidth * 0.94 / math.max(minimum, self:GetWidth()), screenHeight * 0.94 / self:GetHeight())
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
	frame.resizeGrip = self:CreateOwnedWindowFrame("Button", nil, frame)
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
			ContentWidth(frame)
		frame.content:SetWidth(contentWidth)
		frame.rowsViewport:SetWidth(contentWidth)
		frame.rowsContent:SetWidth(contentWidth)
		local maximum = math.max(0, contentWidth - frame.viewport:GetWidth())
		frame.horizontalOffset = self:UpdateOwnedScrollBar(frame.horizontal, frame.horizontalOffset or 0, maximum, frame.viewport:GetWidth(), MEMBER_WIDTH)
		frame.viewport:SetHorizontalScroll(frame.horizontalOffset)
		ScrollCompare(self, frame, session, session.scrollPixels or 0, true)
	end)
	frame:Layout()
	frame.escapeAction = function() self:BackPartyQuestCompare(frame, "escape") end
	self:RegisterManagedWindow(frame, "partyQuestLog", frame.minimumWidth, 500)
	self:ConfigurePartyQuestKeyboardNavigation(frame)
	if self.ConfigurePartyQuestGamepadNavigation then self:ConfigurePartyQuestGamepadNavigation(frame) end
	return frame
end

function QuestTogether:QueuePartyQuestCompareRender()
	local session = self.partyQuestCompareSession
	if not session then
		return
	end
	if self.QueuePartyQuestChainRefresh then self:QueuePartyQuestChainRefresh() end
	self:ScheduleDeferredWork("foreign_frame_mutation", "party_compare_render", function()
		if self.partyQuestCompareSession == session then
			self:RenderPartyQuestCompare()
		end
	end, 0.05, "party compare render")
end

function QuestTogether:OnPartyQuestTitleChanged(questID)
	local session, frame = self.partyQuestCompareSession, rawget(self, "partyQuestCompareWindow")
	local function Current()
		if not self.isEnabled or self.isLoggingOut or not session or not frame
			or self.partyQuestCompareSession ~= session or rawget(self, "partyQuestCompareWindow") ~= frame then
			return false
		end
		for _, member in ipairs(session.members) do
			if member.entries[questID] then return true end
		end
		return false
	end
	if not Current() then return false end
	-- A title can become available after polling has stopped or another surface
	-- has filled the shared cache. Coalesce those changes without reopening UI.
	return self:ScheduleDeferredWork("foreign_frame_mutation", "party_compare_title_changed", function()
		if Current() and self:CanMutateOwnedUI(frame) and frame:IsShown() then
			self:RenderPartyQuestCompare()
		end
	end, 0.05, "party compare titles")
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
	if self.ParkPartyQuestGamepadSelection and not self:ParkPartyQuestGamepadSelection(frame) then return end
	local chainRoot = session.chains and session.chains.rootQuestID
	if frame.displaySession == session and not session.restoreAnchor then
		local origin = chainRoot or frame.chainAnchorQuestID
		if origin then
			-- Keep the actual log row under the cursor as ancestors arrive above
			-- it. If the reader has scrolled away, preserve their reading position.
			session.restoreAnchor = self:CapturePartyQuestScrollAnchor("quest:" .. origin, true)
				or self:CapturePartyQuestScrollAnchor()
		end
	end
	frame.chainAnchorQuestID = chainRoot
	frame.columns, frame.memberColumnsWidth = self:GetPartyQuestCompareColumns(session)
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
	local capability = session.chains and session.chains.capability
	local missingProvider = capability and capability.kind == "questiedb"
		and capability.state == "unavailable" and capability.reason == "provider_missing" or false
	local notice = frame.chainProviderNotice
	if notice:IsShown() ~= missingProvider then
		if missingProvider then notice:Show() else notice:Hide() end
		frame:Layout()
	end
	notice.title:SetTextColor(unpack(theme.heading))
	notice.body:SetTextColor(unpack(theme.body))
	notice.background:SetColorTexture(0.65, 0.48, 0.18, dark and 0.16 or 0.12)
	-- The isolated debug preview supplies its own title and has no mode.
	if session.mode then
		frame.title:SetText(session.mode == "target" and L("Compare Quests") or L("Party Quest Log"))
	end
	local width = ContentWidth(frame)
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
		if frame.keyboardSession then self:SetPartyQuestKeyboardNavigation(frame, false) end
		StopCompareScroll(frame)
		StopExpansion(frame)
		StopChainExpansion(frame)
	end
	frame.displaySession = session
	if self:GetOption("reduceMotion") then StopCompareScroll(frame) end
	local oldRows = frame.displayRows
	PrepareExpansions(self, frame, session, rows)
	PrepareChainExpansion(self, frame, session, oldRows)
	RestoreScrollAnchor(self, session, frame.displayRows, frame)
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
			frame.headerAccents[i]:SetPoint("TOPLEFT", ColumnLeft(frame, i), -48)
			frame.headerCrowns[i] = frame.content:CreateTexture(nil, "OVERLAY")
			frame.headerCrowns[i]:SetTexture("Interface\\AddOns\\QuestTogether\\Media\\PartyLeader")
			frame.headerCrowns[i]:SetSize(16, 12)
			frame.headerCrowns[i]:SetPoint("TOPLEFT", ColumnLeft(frame, i) + 8, -7)
		end
		local column, columnWidth = frame.columns[i], ColumnWidth(frame, i)
		frame.headerAccents[i]:ClearAllPoints()
		frame.headerAccents[i]:SetPoint("TOPLEFT", column.left, -48)
		frame.headerAccents[i]:SetWidth(columnWidth)
		frame.headerCrowns[i]:ClearAllPoints()
		frame.headerCrowns[i]:SetPoint("TOPLEFT", column.left + 8, -7)
		local header = frame.headers[i]
		local isLeader = member.name == leaderName and not column.collapsed
		if isLeader then frame.headerCrowns[i]:Show() else frame.headerCrowns[i]:Hide() end
		local r, g, b = MemberColor(self, member.classFile)
		header:SetTextColor(r, g, b)
		frame.headerAccents[i]:SetColorTexture(r, g, b, 1)
		frame.headerAccents[i]:Show()
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", ColumnLeft(frame, i) + (isLeader and 28 or 8), -6)
		header:SetHeight(16)
		header:SetMaxLines(1)
		header:SetJustifyV("TOP")
		header:SetText(member.isLocal and L("You") or member.name)
		if not frame.headerStatuses[i] then
			frame.headerStatuses[i] = Label(frame.content, 0, 0, COLUMN_WIDTH - 16, "", "GameFontHighlightSmall")
		end
		local status = frame.headerStatuses[i]
		status:ClearAllPoints()
		status:SetPoint("TOPLEFT", ColumnLeft(frame, i) + 8, -23)
		status:SetHeight(14)
		status:SetMaxLines(1)
		status:SetTextColor(unpack(theme.muted))
		status:SetWidth(columnWidth - 30)
		status:SetText(self:GetPartyQuestSnapshotLabel(member))
		status:Show()
		if not frame.focusButtons[i] then
			local button = self:CreateOwnedWindowFrame("Button", nil, frame.content)
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
				local shareResult = self.GetLatestQuestShareResultText and self:GetLatestQuestShareResultText(button.navName)
				local text = (member and self:GetPartyQuestSnapshotLabel(member) or "") .. "\n"
					.. (button.navSession.mode ~= "target" and self:GetPartyFocusLabel(button.navName) .. "\n" or "")
					.. (shareResult and shareResult .. "\n" or "")
					.. L("Click for player column and quest focus options.")
				local focusID = button.navSession.mode ~= "target" and self.GetPartyQuestFocusID and self:GetPartyQuestFocusID(button.navName)
				self:ShowSettingsTooltip(button, button.navName, self:AppendQuestIDToTooltipText(focusID, text))
			end)
			button:SetScript("OnLeave", Leave)
			button:SetScript("OnHide", function()
				Leave()
				-- The paper is a sibling of the button so it stays below the
				-- header text. Parent hiding must preserve its own shown state.
				if not button:IsShown() and QuestTogether.LibChev.CanMutateOwnedRegion(button.paper) then
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
				self:SetPartyQuestKeyboardNavigation(frame, false)
				local expectedSession, name = button.navSession, button.navName
				local function Current()
					return self.partyQuestCompareSession == expectedSession and frame.displaySession == expectedSession
						and QuestTogether.LibChev.CanMutateOwnedRegion(frame) and frame:IsVisible()
						and not self:IsWorkBlocked("foreign_frame_mutation")
				end
				if not Current() then return end
				self:CreatePartyQuestFilterMenu(button, function(_, root)
					if Current() then self:PopulatePartyQuestPlayerMenu(frame, expectedSession, name, root) end
				end)
			end)
		end
		local button = frame.focusButtons[i]
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", ColumnLeft(frame, i), 0)
		button:SetSize(columnWidth, 46)
		button.navSession, button.navName = session, member.name
		button.navLocal = member.isLocal
		local clickable = true
		button.navClickable = clickable
		button:SetEnabled(clickable)
		header:SetWidth(columnWidth - 30 - (isLeader and 20 or 0))
		LayoutPanel(button.paper, frame.content, "BACKGROUND", 0, ColumnLeft(frame, i), 0, columnWidth, 46, true, false)
		LayoutPanel(button.hover, frame.content, "BORDER", 0, ColumnLeft(frame, i), 0, columnWidth, 46, true, false)
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
		if not frame.columnToggles[i] then
			local toggle = Button(self, button, 0, 0, 20, "", function(control)
				if self.partyQuestCompareSession == control.columnSession and frame.displaySession == control.columnSession
					and QuestTogether.LibChev.CanMutateOwnedRegion(frame) and frame:IsVisible() then
					local collapsed = control.columnSession.collapsedPlayers and control.columnSession.collapsedPlayers[control.columnName]
					self:SetPartyQuestColumnCollapsed(control.columnName, not collapsed, control.columnSession)
				end
			end)
			toggle:SetHeight(18)
			toggle:SetScript("OnEnter", function(control)
				if self.partyQuestCompareSession ~= control.columnSession or self:IsWorkBlocked("foreign_frame_mutation")
					or not QuestTogether.LibChev.CanMutateOwnedRegion(control) or not control:IsVisible() then return end
				local member = control.columnSession.byName[control.columnName]
				self:ShowSettingsTooltip(control, control.columnName, (member and self:GetPartyQuestSnapshotLabel(member) or "")
					.. "\n" .. (control.collapsed and L("Expand player column") or L("Collapse player column")))
			end)
			local function LeaveToggle() self:HideSettingsTooltip(toggle) end
			toggle:SetScript("OnLeave", LeaveToggle)
			toggle:SetScript("OnHide", LeaveToggle)
			frame.columnToggles[i] = toggle
		end
		local toggle = frame.columnToggles[i]
		toggle.columnSession, toggle.columnName, toggle.collapsed = session, member.name, column.collapsed
		toggle:ClearAllPoints()
		toggle:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
		toggle:SetText(column.collapsed and "+" or "-")
		toggle:Show()
		header:Show()
	end
	for i = #session.members + 1, #frame.headers do
		frame.headers[i]:Hide()
		frame.headerStatuses[i]:Hide()
		frame.headerAccents[i]:Hide()
		frame.headerCrowns[i]:Hide()
		frame.focusButtons[i]:Hide()
		if frame.columnToggles[i] then frame.columnToggles[i]:Hide() end
		-- Hiding an already-invisible button does not fire OnHide. Retire its
		-- sibling artwork explicitly when the roster shrinks while UI is hidden.
		ShowPanel(frame.focusButtons[i].paper, false)
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
	frame.horizontalOffset = self:UpdateOwnedScrollBar(frame.horizontal, frame.horizontalOffset or 0, maxHorizontal, frame.viewport:GetWidth(), MEMBER_WIDTH)
	frame.viewport:SetHorizontalScroll(frame.horizontalOffset)

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
		addon:HideOwnedUI(frame)
		return true
	end
	return false
end

function QuestTogether:CreatePartyQuestSharePrompt(preview)
	local key = preview and "partyQuestSharePreviewPrompt" or "partyQuestSharePrompt"
	if rawget(self, key) then return self[key] end
	local parent = self:GetOwnedUIParent()
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
	frame.LayoutManagedWindow = frame.LayoutRequest
	frame.close = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -12, -8)
	self:ConfigureRequestPrompt(frame, function(request) self:FinishPartyQuestShare(request, "declined") end)
	frame.close:SetScript("OnClick", function() self:DismissManagedWindow(frame) end)
	frame.requestKind = "share"
	if self.ConfigureGamepadWindow and not preview then
		self:ConfigureGamepadWindow(frame, { role = "share_request", kind = "popup", footer = true,
			defaultFocus = frame.decline, close = function() self:DismissManagedWindow(frame, "gamepad") end })
		if self.GuardGamepadWindowActions then self:GuardGamepadWindowActions(frame, { frame.share, frame.decline, frame.close }) end
	end

	self[key] = frame
	return frame
end

-- Clearing a retired prompt is owned teardown, not permission to show the
-- next request or invoke a native share/invite while restricted.
function QuestTogether:IsPartyRequestPromptCurrent(request, kind)
	if not request or not self.isEnabled or self.API.GetTime() >= request.expires
		or self:IsIgnoredPlayerName(request.sender) then return false end
	if kind == "share" then
		local state = self.partyQuestShareState
		return state and state.incoming[request.key] == request and self:IsGroupedSender(request.sender) or false
	elseif kind == "join" then
		local state = rawget(self, "partyJoinState")
		return state and state.incoming[request.sender] == request and self.API.GetTime() >= request.created
			and request.profile == (self.db and self.db.profile) and request.roster == self.partyRosterFingerprint
			and self:CanAcceptPartyJoin(request.sender) or false
	end
	return false
end

function QuestTogether:HideRetiredPartyRequestPrompt(frame, request)
	if frame and frame.requestRetiring then return false end
	if frame and frame.requestPinned and self:IsPartyRequestPromptCurrent(frame.requestPinned, frame.requestKind) then
		return true
	end
	if frame and (not request or frame.request ~= request) then
		frame.request = nil
		frame.requestPinned = nil
		if self.IsGamepadWindowRegistered and self:IsGamepadWindowRegistered(frame) then
			frame.requestRetiring = true
			self:HideOwnedUI(frame, function()
				frame.requestRetiring = nil
				-- A successor may render automatically, but never inherits native
				-- registration or the previous request's confirmation identity.
				if frame.requestKind == "share" then self:QueuePartyQuestSharePrompt()
				elseif frame.requestKind == "join" then self:QueuePartyJoinPrompt() end
			end)
			return not frame.requestRetiring
		end
		self:HideOwnedUI(frame)
	end
	return true
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

function QuestTogether:RenderPartyQuestSharePrompt(requestedRecord)
	if requestedRecord and not self:IsPartyRequestPromptCurrent(requestedRecord, "share") then return end
	local frame = self.partyQuestSharePrompt
	local pinned = frame and frame.requestPinned
	local request = requestedRecord or (pinned and self:IsPartyRequestPromptCurrent(pinned, "share") and pinned)
		or (self.isEnabled and self:GetNextPartyQuestShareRequest() or nil)
	if requestedRecord and frame then frame.requestPinned = nil end
	if not self:HideRetiredPartyRequestPrompt(frame, request) then return end
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	if not request then
		return
	end
	frame = frame or self:CreatePartyQuestSharePrompt()
	if not QuestTogether.LibChev.CanMutateOwnedRegion(frame) then
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
	if requestedRecord then frame.requestPinned = requestedRecord end
	frame:LayoutRequest()
	self:ApplyScrollDialogTheme(frame)
	frame:Show()
	self:PlayPromptAttentionAudio(frame, request, frame.preview)
	return frame
end

function QuestTogether:CreatePartyJoinPrompt(preview)
	local key = preview and "partyJoinPreviewPrompt" or "partyJoinPrompt"
	if rawget(self, key) then return self[key] end
	local parent = self:GetOwnedUIParent()
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
		local check = self:CreateOwnedWindowFrame("CheckButton", nil, frame, "MinimalCheckboxTemplate")
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
	frame.LayoutManagedWindow = frame.LayoutRequest
	frame.close = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -12, -8)
	self:ConfigureRequestPrompt(frame, function(request) self:FinishPartyJoin(request, "declined") end)
	frame.close:SetScript("OnClick", function() self:DismissManagedWindow(frame) end)
	frame.requestKind = "join"
	if self.ConfigureGamepadWindow and not preview then
		self:ConfigureGamepadWindow(frame, { role = "join_request", kind = "popup", footer = true,
			defaultFocus = frame.decline, close = function() self:DismissManagedWindow(frame, "gamepad") end })
		if self.GuardGamepadWindowActions then self:GuardGamepadWindowActions(frame, { frame.invite, frame.decline, frame.close }) end
	end

	self[key] = frame
	return frame
end

function QuestTogether:RenderPartyJoinPrompt(requestedRecord)
	if requestedRecord and not self:IsPartyRequestPromptCurrent(requestedRecord, "join") then return end
	local frame = rawget(self, "partyJoinPrompt")
	local pinned = frame and frame.requestPinned
	local request = requestedRecord or (pinned and self:IsPartyRequestPromptCurrent(pinned, "join") and pinned)
		or (self.isEnabled and self:GetNextPartyJoinRequest() or nil)
	if requestedRecord and frame then frame.requestPinned = nil end
	if not self:HideRetiredPartyRequestPrompt(frame, request) then return end
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	if not request then
		return
	end
	frame = frame or self:CreatePartyJoinPrompt()
	if not QuestTogether.LibChev.CanMutateOwnedRegion(frame) then
		return
	end
	if frame.request ~= request then
		frame.request = request
		frame.friends:SetChecked(self:GetOption("autoInviteFriends") == true)
		frame.lfg:SetChecked(self:GetOption("autoInviteWhileLFG") == true)
		frame.message:SetText(request.sender .. L(" would like to join your party.\nSend an invitation?"))
	end
	if requestedRecord then frame.requestPinned = requestedRecord end
	frame:LayoutRequest()
	self:ApplyScrollDialogTheme(frame)
	frame:Show()
	self:PlayPromptAttentionAudio(frame, request, frame.preview)
	return frame
end

function QuestTogether:RenderPartyChatReminder(request)
	local inset = self.SCROLL_DIALOG_INSET
	local bodyWidth = 520 - inset * 2
	local buttonWidth = (bodyWidth - 12) / 2
	local frameKey = request and request.preview and "partyChatReminderPreviewFrame" or "partyChatReminderFrame"
	local frame = rawget(self, frameKey)
	local state = rawget(self, "partyChatReminderState")
	local remember = false
	-- Discovery may replace the displayed member list without ending this
	-- prompt. Preserve its unfinished choice only across that visible redraw,
	-- never across a dismissal, preview, profile change, or reminder reset.
	if request and not request.preview and state and state.request == request and request.profile == state.profile
		and state.profile == (self.db and self.db.profile)
		and frame and frame.reminderState == state and frame.request
		and not frame.request.preview and frame.request.profile == request.profile
		and self.LibChev.CanMutateOwnedRegion(frame) and self.LibChev.CanMutateOwnedRegion(frame.remember)
		and frame:IsShown() then
		remember = frame.remember:GetChecked() == true
	end
	if not self:HideRetiredPartyRequestPrompt(frame, request) then return end
	if not request or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	local parent = self:GetOwnedUIParent()
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
		frame.close = self:CreateOwnedWindowFrame("Button", nil, frame, "UIPanelCloseButton")
		frame.close:SetPoint("TOPRIGHT", -12, -8)
		frame.close:SetScript("OnClick", function()
			-- Safe dismissal remains available during combat. A restricted close
			-- does not acknowledge or save preferences; the reminder resumes later.
			self:HideOwnedUI(frame)
			if self.LibChev.CanMutateOwnedRegion(frame.remember) then
				self:AcknowledgePartyChatReminder(frame.request, frame.remember:GetChecked() == true, false)
			end
		end)
		if self.ConfigureGamepadWindow and not request.preview then
			self:ConfigureGamepadWindow(frame, { role = "party_chat_reminder", kind = "popup", footer = true,
				defaultFocus = frame.close, close = function() frame.close:GetScript("OnClick")(frame.close) end })
			if self.GuardGamepadWindowActions then self:GuardGamepadWindowActions(frame, { frame.keep, frame.disable, frame.close }) end
		end
		for _, region in ipairs({ frame.heading, frame.memberLabel }) do self:AddScrollDialogLabel(frame, region, "heading") end
		for _, region in ipairs({ frame.preview, frame.hint }) do self:AddScrollDialogLabel(frame, region, "muted") end
		for _, region in ipairs({ frame.message, frame.members }) do self:AddScrollDialogLabel(frame, region) end

		frame.LayoutManagedWindow = function()
			if not frame.request then return end
			-- Lay out each wrapped section from its actual height. No fixed blank
			-- message area, and long translations/member names grow the dialog.
			local function Place(region, x, y)
				region:ClearAllPoints()
				region:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
			end
			local headingHeight = frame.heading:GetStringHeight()
			Place(frame.preview, inset, frame.contentTop + headingHeight + 8)
			local headerBottom =
				frame.contentTop + headingHeight + (frame.request.preview and frame.preview:GetStringHeight() + 8 or 0)
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

		frame:SetScript("OnDragStart", function()
			if not self:IsWorkBlocked("foreign_frame_mutation") and QuestTogether.LibChev.CanMutateOwnedRegion(frame) then
				self:StartWindowDrag(frame)
			end
		end)
		frame:SetScript("OnDragStop", function()
			if QuestTogether.LibChev.CanMutateOwnedRegion(frame) then
				self:StopWindowDrag(frame)
			end
		end)
	end
	if not QuestTogether.LibChev.CanMutateOwnedRegion(frame) then
		return
	end
	if frame.request ~= request then
		frame.request = request
		frame.reminderState = not request.preview and state or nil
		frame.remember:SetChecked(remember)
		frame.preview:SetText(request.preview and L("Preview - no settings will change.") or "")
		frame.members:SetText(table.concat(request.names, "\n"):gsub("|", "||"))
		frame:LayoutManagedWindow()
	end
	frame:Show()
	self:PlayPromptAttentionAudio(frame, request, request.preview)
	return frame
end
