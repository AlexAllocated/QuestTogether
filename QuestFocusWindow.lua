-- Compact, QT-owned HUD. The shared objective store owns remote detail; this
-- view owns only interests, local presentation and saved geometry.
local QT = _G.QuestTogether
local L = QT.Translate
local Style = QT.QuestProgressStyle

function QT:QueueQuestFocusRefresh(localChanged)
	local state = rawget(self, "questFocusState")
	if not state then
		return
	end
	state.dirty = true
	if localChanged then
		state.localDirty = true
	end
	-- Native construction and layout can invoke size callbacks synchronously.
	-- Zero-delay deferred work runs inline; render only after that stack unwinds.
	self:ScheduleRuntimeWork("quest_focus_presentation", "quest_focus_render", function()
		if self.isEnabled and rawget(self, "questFocusState") == state then
			self:UpdateQuestFocusWindow()
		end
	end, { mode = "nextFrame", coalesce = true, reason = "quest focus progress" })
end

function QT:ObserveLocalQuestFocusProgress(event)
	local state = rawget(self, "questFocusState")
	if not self.isEnabled or not state or state.id ~= self:NormalizeQuestID(event.questId) then
		return
	end
	local member = state.members[1]
	if
		event.senderName
		and event.senderName ~= ""
		and self:NormalizeMemberName(event.senderName) ~= (member and member.name)
	then
		return
	end
	local detail = member and member.isLocal and member.objectiveDetails[state.id]
	if detail and self:ApplyPartyQuestProgressEvent(detail, event) then
		member.state = detail.state
		member.entries[state.id] = detail.entry
		self:QueueQuestFocusRefresh()
	end
end

function QT:ResetQuestFocusWindow(keepEditSelection)
	if not keepEditSelection then self:DeselectQuestFocusWindow() end
	local state = rawget(self, "questFocusState")
	self.questFocusState = nil
	for _, member in ipairs(state and state.members or {}) do
		self:ReleasePartyQuestProgress(member)
	end
	local frame = rawget(self, "questFocusWindow")
	if frame then
		frame.offset = 0
		self:HideOwnedUI(frame)
	end
end

function QT:GetQuestFocusMembers()
	local own = self:NormalizeMemberName(self:GetPlayerFullName())
	local names = own and { own } or {}
	for _, name in ipairs(self.partyMemberOrder or {}) do
		if name ~= own and self:IsGroupedSender(name) and not self:IsIgnoredPlayerName(name) then
			names[#names + 1] = name
		end
	end
	return names, own
end

-- Read-only observation of Blizzard's tracker. Never replace its scripts or
-- change supertracking just to preview another quest in our own HUD.
function QT:GetQuestFocusHoverSources()
	local foci = type(GetMouseFoci) == "function" and GetMouseFoci() or {}
	return foci,
		{
			quest = QuestObjectiveTracker,
			campaign = CampaignQuestObjectiveTracker,
			world = WorldQuestObjectiveTracker,
			bonus = BonusObjectiveTracker,
		}
end

function QT:GetHoveredTrackerQuestID()
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return nil
	end
	local ok, foci, modules = pcall(self.GetQuestFocusHoverSources, self)
	if not ok or not self:CanAccessValue(foci) or type(foci) ~= "table" then
		return nil
	end
	for i = 1, math.min(#foci, 8) do
		local frame = foci[i]
		for _ = 1, 12 do
			if not self:CanAccessForeignFrame(frame, true) then
				break
			end
			local module = self:GetAccessibleFrameMember(frame, "parentModule")
			if module then
				for _, allowed in pairs(modules) do
					if module == allowed and self:CanAccessForeignFrame(module, true) then
						return self:NormalizeQuestID(self:GetAccessibleFrameMember(frame, "id"))
					end
				end
			end
			local parent = self:GetAccessibleFrameMember(frame, "GetParent")
			if type(parent) ~= "function" then
				break
			end
			local read, value = pcall(parent, frame)
			if not read or not self:CanAccessValue(value) or value == frame then
				break
			end
			frame = value
		end
	end
end

function QT:UpdateQuestFocusWindow()
	if not self.isEnabled or self.isLoggingOut then
		self:ResetQuestFocusWindow()
		return
	end
	if self:IsWorkBlocked("foreign_frame_mutation") or self:IsWorkBlocked("quest_snapshot_refresh") then
		local state = rawget(self, "questFocusState")
		if self:GetQuestTrackerMode() == "hidden"
			or (state and (state.profile ~= self.db.profile or state.mode ~= self:GetQuestTrackerMode())) then
			self:ResetQuestFocusWindow()
			return
		end
		-- Departures/ignores retire immediately, even while native focus reads
		-- are blocked. A later safe update rebuilds any new roster membership.
		for i = #(state and state.members or {}), 1, -1 do
			local member = state.members[i]
			if
				not member.isLocal and (not self:IsGroupedSender(member.name) or self:IsIgnoredPlayerName(member.name))
			then
				self:ReleasePartyQuestProgress(member)
				table.remove(state.members, i)
				state.roster, state.dirty = nil, true
			end
		end
		if state and state.dirty then
			self:RenderQuestFocusWindow(state, true)
		end
		return
	end
	self:UpdateQuestFocusEditMode()
	local editing = self.questFocusEditing == true
	local mode = self:GetQuestTrackerMode()
	if mode == "hidden" and not editing then
		self:ResetQuestFocusWindow()
		return
	end
	local names, own = self:GetQuestFocusMembers()
	local id
	if mode == "hover" or mode == "both" then id = self:GetHoveredTrackerQuestID() end
	if not id and (mode == "focus" or mode == "both") then
		id = own and self:NormalizeQuestID(self:GetPartyQuestFocusID(own))
	end
	if not id and not editing then
		self:ResetQuestFocusWindow()
		return
	end
	local roster = table.concat(names, "\n")
	local state = rawget(self, "questFocusState")
	if not state or state.id ~= id or state.roster ~= roster or state.profile ~= self.db.profile or state.mode ~= mode then
		self:ResetQuestFocusWindow(editing and state and state.profile == self.db.profile)
		state = { id = id, mode = mode, roster = roster, profile = self.db.profile, members = {}, localDirty = true, dirty = true }
		self.questFocusState = state
		for _, name in ipairs(names) do
			local member = {
				name = name,
				isLocal = name == own,
				entries = {},
				objectiveDetails = {},
				state = "loading",
				supportsObjectives = true,
			}
			member.classFile = member.isLocal and self:GetPlayerClassFile() or self:GetGroupedSenderClassFile(name)
			state.members[#state.members + 1] = member
			if id and not member.isLocal then
				local function Updated(detail)
					if rawget(self, "questFocusState") ~= state then
						return
					end
					member.objectiveDetails[id], member.state = detail, detail.state
					member.entries[id] = detail.entry
					self:QueueQuestFocusRefresh()
				end
				local detail = self:AcquirePartyQuestProgress(name, id, member, Updated, true, function()
					return rawget(self, "questFocusState") == state
						and self:GetQuestTrackerMode() == state.mode and state.mode ~= "hidden"
				end)
				if detail then
					Updated(detail)
				end
			end
		end
	end
	if state.localDirty and id then
		local entries = self:BuildQuestCompareResponseEntries(id)
		local member = state.members[1]
		if member then
			local entry = entries and entries[1]
			member.entries[id], member.state = entry, entries and "ready" or "unknown"
			member.objectiveDetails[id] = {
				questId = id,
				state = member.state,
				entry = entry,
				hasEntry = entries ~= nil,
				objectives = entry and entry.objectives,
			}
		end
		state.localDirty, state.dirty = false, true
	end
	if state.editing ~= editing then
		state.editing, state.dirty = editing, true
	end
	if state.dirty or state.restrictedPresentation then
		self:RenderQuestFocusWindow(state)
	end
end

function QT:GetQuestFocusStatusSentence(status, member)
	local own = member.isLocal
	if status == "Ready" then
		return own and L("You are ready to turn in this quest.")
			or string.format(L("%s is ready to turn in this quest."), member.name)
	elseif status == "In progress" then
		return own and L("You are still working on this quest.")
			or string.format(L("%s is still working on this quest."), member.name)
	elseif status == "Completed" then
		return own and L("You have completed this quest.")
			or string.format(L("%s has completed this quest."), member.name)
	elseif status == "Missing" or status == "Not in log" then
		return own and L("You do not have this quest in your quest log.")
			or string.format(L("%s does not have this quest in their quest log."), member.name)
	elseif status == "Loading" then
		return own and L("Loading your quest progress…")
			or string.format(L("Loading quest progress for %s…"), member.name)
	elseif status == "Unknown" then
		return own and L("Your quest status is not available yet.")
			or string.format(L("Quest status for %s is not available yet."), member.name)
	end
end

function QT:BuildQuestFocusRows(state)
	local rows = {}
	if not state.id then
		rows[1] = { kind = "member", title = L("Focus a quest to show your party's objective progress here.") }
		return rows
	end
	for _, member in ipairs(state.members) do
		local index = #rows + 1
		self:AppendPartyQuestObjectiveRows(rows, member, state.id)
		local row = rows[index]
		local sentence = self:GetQuestFocusStatusSentence(row.status, member)
		if sentence then
			row.title, row.hint = sentence, nil
		end
	end
	return rows
end

function QT:GetQuestFocusTitle(state)
	local title = state.id and self:GetLocalizedQuestTitle(state.id)
	if title then
		return title
	end
	for _, member in ipairs(state.members) do
		local entry = state.id and member.entries[state.id]
		if entry and entry.questTitle then
			return entry.questTitle
		end
	end
	return L("Quest Tracker")
end

function QT:CreateQuestFocusWindow()
	local frame = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Frame", self:GetOwnedUIParent())
	frame:Hide()
	frame:SetSize(340, 300)
	frame:SetFrameStrata("LOW")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(240, 120, 720, 800)
	frame.background = self:CreateRoundedWindowBackground(frame)
	frame.heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.heading:SetPoint("TOPLEFT", 12, -12)
	frame.heading:SetJustifyH("LEFT")
	frame.heading:SetJustifyV("TOP")
	frame.heading:SetMaxLines(2)
	frame.heading:SetHeight(36)
	frame.heading:SetWordWrap(true)
	frame.viewport = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "ScrollFrame", frame)
	frame.viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
	frame.body = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Frame", frame.viewport)
	frame.body:SetSize(300, 1)
	frame.viewport:SetScrollChild(frame.body)
	frame.rows, frame.offset = {}, 0
	local function Scroll(value)
		if not self:CanMutateOwnedUI(frame) then
			return
		end
		frame.offset = math.max(0, math.min(frame.maximum or 0, value))
		frame.viewport:SetVerticalScroll(frame.offset)
		self:UpdateOwnedScrollBar(frame.bar, frame.offset, frame.maximum or 0, frame.viewport:GetHeight(), 30)
	end
	frame.bar = self:CreateOwnedScrollBar(self.CreateOwnedWindowFrame, frame, false, Scroll)
	frame.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -40)
	frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 12)
	frame.bar:SetWidth(12)
	frame.viewport:SetScript("OnSizeChanged", function()
		self:QueueQuestFocusRefresh()
	end)
	frame.viewport:EnableMouseWheel(true)
	frame.viewport:SetScript("OnMouseWheel", function(_, delta)
		Scroll(frame.offset - delta * 30)
	end)
	frame:SetScript("OnSizeChanged", function()
		self:QueueQuestFocusRefresh()
	end)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			self:SelectQuestFocusWindow()
		end
	end)
	frame:SetScript("OnDragStart", function()
		if self.questFocusEditing and not self:IsWorkBlocked("foreign_frame_mutation") then
			self:SelectQuestFocusWindow()
			self:StartWindowDrag(frame)
		end
	end)
	frame:SetScript("OnDragStop", function()
		self:StopWindowDrag(frame)
		self:QueueQuestFocusRefresh()
	end)
	frame.grip = self:CreateOwnedUIFrame(self.CreateOwnedWindowFrame, "Button", frame)
	frame.grip:SetSize(18, 18)
	frame.grip:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	frame.grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and self.questFocusEditing and not self:IsWorkBlocked("foreign_frame_mutation") then
			self:SelectQuestFocusWindow()
			frame.resizing = true
			frame:StartSizing("BOTTOMRIGHT")
		end
	end)
	frame.grip:SetScript("OnMouseUp", function()
		if not frame.resizing then
			return
		end
		frame:StopMovingOrSizing()
		frame.resizing = nil
		self:SaveWindowLayout(frame)
		self:QueueQuestFocusRefresh()
	end)
	frame.LayoutManagedWindow = function()
		self:QueueQuestFocusRefresh()
	end
	self:RegisterManagedWindow(frame, "questFocus", 240, 120, { x = 0.78, y = 0.6 })
	frame:EnableKeyboard(false)
	self.questFocusWindow = frame
	return frame
end

local function CreateDetailRow(addon, parent)
	local row = addon:CreateOwnedWindowFrame("Frame", nil, parent)
	row:EnableMouse(false)
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(true)
	row.paper = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.hover = row:CreateTexture(nil, "BORDER")
	row.accent = row:CreateTexture(nil, "ARTWORK")
	row.panelEdges = {}
	for i = 1, 4 do
		row.panelEdges[i] = row:CreateTexture(nil, "ARTWORK")
	end
	row.progressTrack = row:CreateTexture(nil, "ARTWORK")
	row.progressFill = row:CreateTexture(nil, "OVERLAY")
	row.progressTrack:SetHeight(3)
	row.progressFill:SetHeight(3)
	return row
end

local function CanUseDetailRow(addon, row)
	local usable = addon.LibChev.CanMutateOwnedRegion
	for _, region in ipairs({
		row,
		row.title,
		row.paper,
		row.background,
		row.hover,
		row.accent,
		row.progressTrack,
		row.progressFill,
	}) do
		if not usable(region) then
			return false
		end
		for _, part in ipairs(region.panelParts or {}) do
			if not usable(part) then
				return false
			end
		end
	end
	for _, regions in ipairs({ row.panelEdges, row.panelCorners or {} }) do
		for _, region in ipairs(regions) do
			if not usable(region) then
				return false
			end
		end
	end
	return true
end

function QT:RenderQuestFocusWindow(state, restricted)
	if rawget(self, "questFocusState") ~= state then
		return
	end
	local frame = rawget(self, "questFocusWindow")
	if not frame and not restricted then
		frame = self:CreateQuestFocusWindow()
	end
	if not frame then
		return
	end
	-- Updating known text in our unprotected HUD requires no quest/native UI
	-- reads. Keep creation of the window and native scrollbar/edit controls out
	-- of restricted callbacks; forbidden/protected owned descendants still defer.
	local function Usable(region)
		return self.LibChev.CanMutateOwnedRegion(region)
	end
	for _, region in ipairs({ frame, frame.body, frame.viewport, frame.heading, frame.grip }) do
		if not Usable(region) then
			return
		end
	end
	for _, region in ipairs(frame.rows) do
		if not CanUseDetailRow(self, region) then
			return
		end
	end
	for _, region in ipairs(frame.background) do
		if not Usable(region) then
			return
		end
	end
	state.dirty, state.restrictedPresentation = false, restricted == true
	local theme = self:GetScrollWindowTheme()
	self:ColorRoundedWindowBackground(
		frame.background,
		theme.dark and theme.tint or { 0.94, 0.88, 0.73 },
		self:GetQuestFocusOpacity() / 100
	)
	frame.heading:SetWidth(frame:GetWidth() - 24)
	if not restricted then
		state.title = self:GetQuestFocusTitle(state)
	end
	frame.heading:SetText(state.title or L("Quest Tracker"))
	-- Transparent HUD text sits over the world, even with the light theme.
	local opacity = self:GetQuestFocusOpacity() / 100
	local brightText = theme.dark or opacity < 0.65
	frame.heading:SetTextColor(unpack(brightText and { 1, 0.85, 0.55 } or theme.heading))
	frame.heading:SetShadowColor(0, 0, 0, brightText and 1 or 0)
	frame.heading:SetShadowOffset(1, -1)
	local top = math.max(18, math.min(36, frame.heading:GetStringHeight())) + 22
	frame.viewport:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -top)
	if not restricted then
		frame.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -top)
	end
	local rows = self:BuildQuestFocusRows(state)
	-- Keep native frame construction outside restricted updates. Existing rows
	-- still receive new counts and bars immediately while in combat.
	if restricted and #rows > #frame.rows then
		state.dirty = true
		return
	end
	local style = Style
	local sectionOpacity = math.max(0.1, opacity)
	local function LayoutRows(width)
		frame.body:SetWidth(width)
		local y = 0
		for i, data in ipairs(rows) do
			local row = frame.rows[i]
			if not row then
				row = CreateDetailRow(self, frame.body)
				frame.rows[i] = row
			end
			local member = data.kind == "member"
			local following = rows[i + 1]
			local last = not following or following.kind == "member"
			if member and i > 1 then
				y = y + 8
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 0, -y)
			row:SetWidth(width)
			local inset, padding = member and 10 or 16, member and 8 or 4
			row.title:ClearAllPoints()
			row.title:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -padding)
			row.title:SetWidth(width - inset - 10)
			local text = data.title or ""
			if data.hint and (member or not text:gsub("%s+", ""):find(data.hint:gsub("%s+", ""), 1, true)) then
				text = text .. "  " .. data.hint
			end
			row.title:SetText(text)
			local textHeight = math.max(14, row.title:GetStringHeight())
			local height = padding + textHeight + (data.fraction and 8 or 4) + (last and 8 or 0)
			row:SetHeight(height)
			style.LayoutDetailsPanel(row, width, true, member, last, false, theme.dark, true, sectionOpacity, true)
			local r, g, b = self:GetWindowClassColor(data.classFile)
			style.ColorPanel(row.background, r, g, b, math.max(0.1, 0.20 * opacity))
			style.ShowPanel(row.hover, false)
			row.accent:Hide()
			style.LayoutProgressBar(row, data, theme.dark, inset, padding + textHeight + 3, width - inset - 10)
			if member and data.classFile then
				row.title:SetTextColor(self:GetWindowClassColor(data.classFile, brightText and 1 or 0.32))
			else
				row.title:SetTextColor(unpack(brightText and { 0.93, 0.92, 0.88 } or theme.body))
			end
			row.title:SetShadowColor(0, 0, 0, brightText and 1 or 0)
			row.title:SetShadowOffset(1, -1)
			row:Show()
			y = y + height
		end
		return y
	end
	-- Measure at the full inner width first. Only overflowing content needs a
	-- scrollbar gutter; remeasure wrapped text and bars at that narrower width.
	local width = math.max(100, frame:GetWidth() - 24)
	local extent = math.max(1, frame:GetHeight() - top - 12)
	local y = LayoutRows(width)
	local gutter = y > extent and 12 or 0
	if gutter > 0 then
		y = LayoutRows(width - gutter)
	end
	frame.viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12 - gutter, 12)
	for i = #rows + 1, #frame.rows do
		frame.rows[i]:Hide()
	end
	frame.body:SetHeight(math.max(1, y))
	frame.maximum = math.max(0, y - extent)
	frame.offset = math.min(frame.offset, frame.maximum)
	frame.viewport:SetVerticalScroll(frame.offset)
	if not restricted then
		self:UpdateOwnedScrollBar(frame.bar, frame.offset, frame.maximum, math.max(1, frame:GetHeight() - top - 12), 30)
	end
	local editing = state.editing and not restricted
	if not editing then
		self:StopWindowInteraction(frame)
	end
	self:RefreshQuestFocusSelection(frame, editing)
	frame:EnableMouse(editing)
	frame.grip[editing and "Show" or "Hide"](frame.grip)
	if not restricted then
		frame:Show()
		self:RefreshQuestFocusEditControls(frame, editing)
	elseif frame.editControls then
		self:HideOwnedUI(frame.editControls)
	end
end
