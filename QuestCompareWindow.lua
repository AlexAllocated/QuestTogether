local QuestTogether = _G.QuestTogether
local VISIBLE_ROWS, ROW_HEIGHT = 13, 28
local QUEST_WIDTH, MEMBER_WIDTH, ACTION_WIDTH = 300, 108, 172
local COLORS = {
	Have = { 0.75, 0.85, 1 },
	Ready = { 0.35, 1, 0.55 },
	Missing = { 1, 0.7, 0.3 },
	Loading = { 0.65, 0.65, 0.65 },
	Unknown = { 0.65, 0.65, 0.65 },
}

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

local function TiledBackground(parent, file)
	local texture = NativeTexture(parent, nil, "BACKGROUND")
	texture:SetAllPoints()
	texture:SetTexture(file, "REPEAT", "REPEAT")
	texture:SetHorizTile(true)
	texture:SetVertTile(true)
end

local function Window(addon, width, height, title)
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
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	TiledBackground(frame, "Interface\\FrameGeneral\\UI-Background-Marble")
	local topLeft = NativeTexture(frame, "UI-Frame-TopLeftCorner", "OVERLAY", 33, 33)
	topLeft:SetPoint("TOPLEFT", -6, 1)
	local topRight = NativeTexture(frame, "UI-Frame-TopCornerRight", "OVERLAY", 33, 33)
	topRight:SetPoint("TOPRIGHT", 0, 1)
	local bottomLeft = NativeTexture(frame, "UI-Frame-BotCornerLeft", "BORDER", 14, 14)
	bottomLeft:SetPoint("BOTTOMLEFT", -6, -5)
	local bottomRight = NativeTexture(frame, "UI-Frame-BotCornerRight", "BORDER", 11, 11)
	bottomRight:SetPoint("BOTTOMRIGHT", 0, -5)
	for _, edge in ipairs({
		{ "_UI-Frame-TitleTile", "TOPLEFT", topLeft, "TOPRIGHT", "TOPRIGHT", topRight, "TOPLEFT", 256, 28 },
		{ "_UI-Frame-Bot", "BOTTOMLEFT", bottomLeft, "BOTTOMRIGHT", "BOTTOMRIGHT", bottomRight, "BOTTOMLEFT", 256, 9 },
		{ "!UI-Frame-LeftTile", "TOPLEFT", topLeft, "BOTTOMLEFT", "BOTTOMLEFT", bottomLeft, "TOPLEFT", 16, 256 },
		{ "!UI-Frame-RightTile", "TOPRIGHT", topRight, "BOTTOMRIGHT", "BOTTOMRIGHT", bottomRight, "TOPRIGHT", 10, 256 },
	}) do
		local texture = NativeTexture(frame, edge[1], "BORDER", edge[8], edge[9])
		texture:SetPoint(edge[2], edge[3], edge[4])
		texture:SetPoint(edge[5], edge[6], edge[7])
	end
	local titleBackground = NativeTexture(frame, "_UI-Frame-TitleTileBg", "BACKGROUND", 256, 18)
	titleBackground:SetPoint("TOPLEFT", 2, -1)
	titleBackground:SetPoint("TOPRIGHT", -25, -1)
	frame.title = Label(frame, 16, -5, width - 70, title, "GameFontNormal")
	return frame
end

local function Checkbox(addon, parent, x, y, text, callback)
	local check = addon:CreatePartyQuestUIFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	check:SetSize(26, 26)
	Label(check, 30, -7, 340, text)
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

function QuestTogether:CreatePartyQuestCompareWindow()
	if self.partyQuestCompareWindow then
		return self.partyQuestCompareWindow
	end
	local parent = self:GetPartyQuestUIParent()
	if not self:CanAccessForeignFrame(parent) then
		return nil
	end
	local width = math.min(1180, parent:GetWidth() * 0.94)
	local frame = Window(self, width, 590, "Party Quest Compare")
	frame:SetScale(math.min(1, parent:GetHeight() * 0.94 / 590))
	self.partyQuestCompareWindow = frame
	frame.summary = Label(frame, 20, -47, width - 40, "")
	frame.filter = Checkbox(self, frame, 16, -69, "Hide quests I don't have", function(check)
		self:SetOption("compareHideOtherQuests", check:GetChecked() == true)
		if self.partyQuestCompareSession then
			self.partyQuestCompareSession.offset = 0
		end
		self:QueuePartyQuestCompareRender()
	end)
	frame.refresh = Button(self, frame, width - 140, -72, 112, "Refresh", function()
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
		-- Parent visibility changes must not leave a still-shown window with
		-- stale rows and no session when the parent becomes visible again.
		if not hiddenFrame:IsShown() then
			self:CancelPartyQuestCompare()
		end
	end)

	frame.viewport = self:CreatePartyQuestUIFrame("ScrollFrame", nil, frame)
	frame.viewport:SetPoint("TOPLEFT", 20, -110)
	frame.viewport:SetSize(width - 62, VISIBLE_ROWS * ROW_HEIGHT + 40)
	frame.content = self:CreatePartyQuestUIFrame("Frame", nil, frame.viewport)
	frame.content:SetSize(QUEST_WIDTH + ACTION_WIDTH, VISIBLE_ROWS * ROW_HEIGHT + 40)
	frame.viewport:SetScrollChild(frame.content)
	frame.questHeader = Label(frame.content, 4, 0, QUEST_WIDTH - 8, "QUEST", "GameFontNormalSmall")
	frame.headers, frame.rows = {}, {}
	for i = 1, VISIBLE_ROWS do
		local row = self:CreatePartyQuestUIFrame("Frame", nil, frame.content)
		row:SetPoint("TOPLEFT", 0, -36 - (i - 1) * ROW_HEIGHT)
		row:SetSize(QUEST_WIDTH + ACTION_WIDTH, ROW_HEIGHT)
		row.background = row:CreateTexture(nil, "BACKGROUND")
		row.background:SetAllPoints()
		row.background:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.055 or 0.015)
		row.title = Label(row, 4, -6, QUEST_WIDTH - 12, "")
		row.title:SetMaxLines(1)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function()
			if row.data then
				frame.detail:SetText(
					row.data.title
						.. " (#"
						.. row.data.questId
						.. ")"
						.. (row.data.owner and (" — Request from " .. row.data.owner) or "")
				)
			end
		end)
		row.cells = {}
		row.action = Button(self, row, QUEST_WIDTH, -2, ACTION_WIDTH - 12, "", function()
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
		row.hint = Label(row, QUEST_WIDTH, -7, ACTION_WIDTH - 8, "")
		row.hint:SetMaxLines(2)
		row.hint:SetHeight(ROW_HEIGHT - 2)
		row.hint:SetJustifyV("MIDDLE")
		frame.rows[i] = row
	end
	frame.vertical = Slider(self, frame, true)
	frame.vertical:SetPoint("TOPRIGHT", -18, -146)
	frame.vertical:SetSize(16, VISIBLE_ROWS * ROW_HEIGHT)
	frame.vertical:SetMinMaxValues(0, 0)
	frame.vertical:SetValueStep(1)
	frame.vertical:SetObeyStepOnDrag(true)
	frame.vertical:SetValue(0)
	frame.vertical:SetScript("OnValueChanged", function(_, value)
		local session = self.partyQuestCompareSession
		if session and not frame.rendering then
			session.offset = math.floor(value + 0.5)
			self:RenderPartyQuestCompare()
		end
	end)
	frame.viewport:EnableMouseWheel(true)
	frame.viewport:SetScript("OnMouseWheel", function(_, delta)
		frame.vertical:SetValue(frame.vertical:GetValue() - delta * 3)
	end)
	frame.horizontal = Slider(self, frame, false)
	frame.horizontal:SetPoint("TOPLEFT", 26, -520)
	frame.horizontal:SetSize(width - 70, 16)
	frame.horizontal:SetMinMaxValues(0, 0)
	frame.horizontal:SetValue(0)
	frame.horizontal:SetValueStep(20)
	frame.horizontal:SetScript("OnValueChanged", function(_, value)
		frame.viewport:SetHorizontalScroll(value)
	end)
	frame.detail = Label(
		frame,
		20,
		-543,
		width - 40,
		"Ready = ready to turn in. Unknown = no complete snapshot; use Refresh to retry."
	)
	frame.footer = Label(frame, 20, -566, width - 40, "")
	return frame
end

function QuestTogether:QueuePartyQuestCompareRender()
	if not self.partyQuestCompareSession then
		return
	end
	self:ScheduleDeferredWork("foreign_frame_mutation", "party_compare_render", function()
		self:RenderPartyQuestCompare()
	end, 0.05, "party compare render")
end

function QuestTogether:RenderPartyQuestCompare()
	local frame, session = self.partyQuestCompareWindow, self.partyQuestCompareSession
	if not frame or not session or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	local rows = self:BuildPartyQuestDiffRows()
	-- The isolated debug preview supplies its own title and has no mode.
	if session.mode then
		frame.title:SetText(session.mode == "target" and "Compare Quests" or "Party Quest Compare")
	end
	local width = QUEST_WIDTH + #session.members * MEMBER_WIDTH + ACTION_WIDTH
	local actionX = width - ACTION_WIDTH
	frame.rendering = true
	frame.filter:SetChecked(self:GetOption("compareHideOtherQuests") == true)
	frame.content:SetWidth(width)
	local ready = 0
	for i, member in ipairs(session.members) do
		if member.state == "ready" then
			ready = ready + 1
		end
		if not frame.headers[i] then
			frame.headers[i] = Label(frame.content, 0, 0, MEMBER_WIDTH - 6, "", "GameFontNormalSmall")
		end
		local header = frame.headers[i]
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", QUEST_WIDTH + (i - 1) * MEMBER_WIDTH, 0)
		header:SetHeight(32)
		header:SetText(
			(member.isLocal and "You" or member.name)
				.. "\n"
				.. (member.state == "ready" and "Synced" or member.state == "loading" and "Loading…" or "No snapshot")
		)
		header:Show()
	end
	for i = #session.members + 1, #frame.headers do
		frame.headers[i]:Hide()
	end
	local maxOffset = math.max(0, #rows - VISIBLE_ROWS)
	session.offset = math.min(session.offset or 0, maxOffset)
	frame.vertical:SetMinMaxValues(0, maxOffset)
	frame.vertical:SetValue(session.offset)
	if maxOffset > 0 then
		frame.vertical:Show()
	else
		frame.vertical:Hide()
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
	for i, row in ipairs(frame.rows) do
		local data = rows[session.offset + i]
		row.data = data
		row.session = session
		if not data then
			row:Hide()
		else
			row:Show()
			row:SetWidth(width)
			row.title:SetText(data.title)
			for j, status in ipairs(data.cells) do
				if not row.cells[j] then
					row.cells[j] = Label(row, QUEST_WIDTH + (j - 1) * MEMBER_WIDTH, -6, MEMBER_WIDTH - 6, "")
				end
				row.cells[j]:SetText(status)
				row.cells[j]:SetTextColor(unpack(COLORS[status]))
				row.cells[j]:Show()
			end
			for j = #data.cells + 1, #row.cells do
				row.cells[j]:Hide()
			end
			row.action:ClearAllPoints()
			row.action:SetPoint("TOPLEFT", actionX, -2)
			row.hint:ClearAllPoints()
			local status, waiting = self:GetPartyQuestShareStatus(data.questId)
			if data.action and not waiting then
				local cooldown = data.action == "request"
						and self.GetPartyQuestShareRequestCooldown
						and self:GetPartyQuestShareRequestCooldown(data.owner)
					or 0
				local coolingDown = cooldown > 0
				row.action:SetText(
					coolingDown and "Please wait" or (data.action == "share" and "Share" or "Request Share")
				)
				row.action:SetEnabled(not coolingDown and not self:IsWorkBlocked("quest_share"))
				row.action:Show()
				if status and status ~= "" then
					-- Keep terminal feedback visible beside a retry action, without
					-- increasing row height or changing the scroll pool's geometry.
					row.action:SetWidth(96)
					row.hint:SetPoint("TOPLEFT", actionX + 100, -1)
					row.hint:SetWidth(ACTION_WIDTH - 104)
					row.hint:SetText(status)
					row.hint:Show()
				else
					row.action:SetWidth(ACTION_WIDTH - 12)
					row.hint:Hide()
				end
			else
				row.action:Hide()
				row.hint:SetPoint("TOPLEFT", actionX, -1)
				row.hint:SetWidth(ACTION_WIDTH - 8)
				row.hint:SetText(status or data.hint or "")
				row.hint:Show()
			end
		end
	end
	frame.summary:SetText(
		string.format(
			"%d quests shown · %d/%d snapshots received · Refresh to update quests",
			#rows,
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
		message = "Close the world map to finish loading quests."
	elseif not message and session.mode == "target" and not self:IsGroupedSender(session.targetName) then
		message = "Join a party together to share quests. The selected player needs QuestTogether to respond."
	elseif not message and #rows == 0 then
		message = self:GetOption("compareHideOtherQuests") == true
				and "No quests to display. Uncheck ‘Hide quests I don't have’ to include other players' quests."
			or "No quests to display."
	elseif not message and #session.members == 1 then
		message = "Join a party to compare quests. Party members need QuestTogether to respond."
	end
	frame.footer:SetText(
		message
			or string.format(
				"Showing %d–%d of %d · Shareability does not guarantee another player's eligibility.",
				math.min(#rows, session.offset + 1),
				math.min(#rows, session.offset + VISIBLE_ROWS),
				#rows
			)
	)
	frame.rendering = false
end

function QuestTogether:CreatePartyQuestSharePrompt()
	if self.partyQuestSharePrompt then
		return self.partyQuestSharePrompt
	end
	local parent = self:GetPartyQuestUIParent()
	if not self:CanAccessForeignFrame(parent) then
		return nil
	end
	local frame = Window(self, 460, 224, "QuestTogether · Share request")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetScale(math.min(1, parent:GetWidth() * 0.94 / 460, parent:GetHeight() * 0.94 / 224))
	frame.message = Label(frame, 20, -56, 420, "")
	frame.message:SetHeight(64)
	frame.always = Checkbox(self, frame, 16, -130, "Always allow party share requests")
	Button(self, frame, 210, -182, 105, "Share", function()
		self:ConfirmPartyQuestShare(frame.request, frame.always:GetChecked() == true, false)
	end)
	Button(self, frame, 325, -182, 105, "Decline", function()
		if frame.request then
			self:FinishPartyQuestShare(frame.request, "declined")
		end
	end)
	self.partyQuestSharePrompt = frame
	return frame
end

function QuestTogether:QueuePartyQuestSharePrompt()
	if not self.partyQuestShareState then
		return
	end
	self:ScheduleDeferredWork("foreign_frame_mutation", "party_share_prompt", function()
		self:RenderPartyQuestSharePrompt()
	end, 0, "party share prompt")
end

function QuestTogether:RenderPartyQuestSharePrompt()
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	local request = self:GetNextPartyQuestShareRequest()
	local frame = self.partyQuestSharePrompt
	if not request then
		if frame then
			frame.request = nil
			frame:Hide()
		end
		return
	end
	frame = frame or self:CreatePartyQuestSharePrompt()
	if not frame then
		return
	end
	if frame.request ~= request then
		frame.request = request
		frame.always:SetChecked(false)
		frame.message:SetText(
			request.sender
				.. " would like you to share\n["
				.. self:GetQuestTitle(request.questId)
				.. "]\nwith the party."
		)
	end
	frame:Show()
end
