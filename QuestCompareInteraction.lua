-- Presentation-only state: narrowing a column never changes the roster or
-- the snapshots used to compare, share, or calculate party progress.
local QT = _G.QuestTogether
local FULL_WIDTH, COMPACT_WIDTH = 130, 64

function QT:GetPartyQuestCompareColumns(session)
	local columns, retained, width = {}, {}, 0
	for index, member in ipairs(session and session.members or {}) do
		local collapsed = session.collapsedPlayers and session.collapsedPlayers[member.name] == true
		local size = collapsed and COMPACT_WIDTH or FULL_WIDTH
		columns[index] = { left = 346 + width, width = size - 4, collapsed = collapsed }
		if collapsed then retained[member.name] = true end
		width = width + size
	end
	if session then session.collapsedPlayers = retained end
	return columns, width
end

function QT:SetPartyQuestColumnCollapsed(name, collapsed, expectedSession)
	local session = self.partyQuestCompareSession
	if not session or (expectedSession and session ~= expectedSession)
		or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	local found = false
	for _, member in ipairs(session.members) do
		if member.name == name then found = true; break end
	end
	if not found then return false end
	session.collapsedPlayers = session.collapsedPlayers or {}
	session.collapsedPlayers[name] = collapsed == true or nil
	self:QueuePartyQuestCompareRender()
	return true
end

function QT:RestorePartyQuestColumns(expectedSession)
	local session = self.partyQuestCompareSession
	if not session or (expectedSession and session ~= expectedSession)
		or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	session.collapsedPlayers = {}
	self:QueuePartyQuestCompareRender()
	return true
end

-- Roots and their current pixel positions come from the window's existing
-- layout pass, including animated detail heights. No second geometry model.
-- A quest can occur both in the active union and in an open chain. Physical
-- pool slots and quest IDs cannot identify a selection across those instances.
function QT:GetPartyQuestRowIdentity(row)
	if not row then return nil end
	return row.rowId or (row.questId and "quest:" .. row.questId)
end

function QT:IsPartyQuestSelectableRow(row)
	return row and (row.selectable == true or not row.kind) or false
end

function QT:GetPartyQuestRowControlRole(row)
	return row.kind == "chainGroup" and "group" or row.kind == "chainStep" and "step"
		or row.kind == "chainMore" and "more" or row.kind == "chainClose" and "closeChain" or "quest"
end

function QT:GetPartyQuestKeyboardTarget(rows, rowID, key, pageHeight)
	if not rows or #rows == 0 then return nil end
	if self.ResolvePartyQuestChainRowID then rowID = self:ResolvePartyQuestChainRowID(rowID) end
	local index = 1
	for i, row in ipairs(rows) do
		if self:GetPartyQuestRowIdentity(row) == rowID or (type(rowID) == "number" and row.questId == rowID) then index = i; break end
	end
	if key == "HOME" then index = 1
	elseif key == "END" then index = #rows
	elseif key == "UP" then index = math.max(1, index - 1)
	elseif key == "DOWN" then index = math.min(#rows, index + 1)
	elseif key == "PAGEUP" or key == "PAGEDOWN" then
		local direction = key == "PAGEUP" and -1 or 1
		local target = rows[index].top + direction * math.max(42, pageHeight or 42)
		local nextIndex = math.max(1, math.min(#rows, index + direction))
		while nextIndex > 1 and nextIndex < #rows
			and ((direction > 0 and rows[nextIndex].top < target)
				or (direction < 0 and rows[nextIndex].top > target)) do
			nextIndex = nextIndex + direction
		end
		index = nextIndex
	end
	return rows[index]
end

-- The same ordered controls serve keyboard and native navigation. This reads
-- only already-materialized UI; metadata work belongs to the session service.
function QT:GetPartyQuestRowControls(frame, selected)
	local list, session = {}, frame.displaySession
	for _, row in ipairs(frame.rows or {}) do
		if row.session == session and row.data and row:IsVisible()
			and self:GetPartyQuestRowIdentity(row.data) == self:GetPartyQuestRowIdentity(selected) then
			local function Add(button, role, player)
				if button and button:IsVisible() and (not button.IsEnabled or button:IsEnabled()) then
					list[#list + 1] = { button = button, role = role, player = player }
				end
			end
			Add(row, self:GetPartyQuestRowControlRole(row.data))
			Add(row.chain, "chain")
			Add(row.journal, "journal")
			for index, member in ipairs(session.members) do
				Add(row.cellTooltips and row.cellTooltips[index], "status", member.name)
				Add(row.focusCells[index], "focus", member.name)
			end
			Add(row.action, "action")
			break
		end
	end
	return list
end

function QT:SelectPartyQuestKeyboardRow(frame, selected, role, player)
	local session = self.partyQuestCompareSession
	if not session or frame.displaySession ~= session then return false end
	session.keyboardRowId, session.keyboardQuestId = self:GetPartyQuestRowIdentity(selected), selected and selected.questId
	session.keyboardRole, session.keyboardPlayer = role, player
	if self.SetPartyQuestChainSelection then self:SetPartyQuestChainSelection(selected and (selected.data or selected)) end
	return true
end

function QT:ActivatePartyQuestListRow(frame, data)
	local session = self.partyQuestCompareSession
	if not session or frame.displaySession ~= session or not self:IsPartyQuestSelectableRow(data)
		or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	if data.kind == "chainClose" then
		return self:BackPartyQuestCompare(frame, self:IsPartyQuestGamepadInputOwned() and "gamepad" or "escape")
	elseif data.kind == "chainGroup" then
		return self.TogglePartyQuestChainGroup and self:TogglePartyQuestChainGroup(data.groupId)
	elseif data.kind == "chainMore" then
		return self.ExpandPartyQuestChain and self:ExpandPartyQuestChain(data.direction)
	elseif data.kind == "chainStep" then
		return self:ShowPartyQuestKeyboardMenu(frame, { rowId = self:GetPartyQuestRowIdentity(data), questId = data.questId, data = data })
	end
	frame.animateExpansion = { session = session, questId = data.questId }
	self:TogglePartyQuestObjectives(data.questId)
	return true
end

function QT:BackPartyQuestCompare(frame, source)
	if self:IsWorkBlocked("foreign_frame_mutation") or frame.displaySession ~= self.partyQuestCompareSession then return false end
	-- Owned context menus normally receive Back themselves; keep this ordering
	-- when their owner dispatches a close during the same native input turn.
	if rawget(self, "gamepadActions") and self.CloseGamepadActions then self:CloseGamepadActions(); return true end
	local session = self.partyQuestCompareSession
	local identity = frame.gamepadNavigation and frame.gamepadNavigation.selected
	local selectedID = source == "gamepad" and identity and identity.rowId or session and (session.keyboardRowId or session.keyboardQuestId)
	local selected = self:GetPartyQuestKeyboardTarget(frame.navigationRows, selectedID)
	if selected and selected.data and (selected.data.chainInstanceId or session.chains and selected.questId == session.chains.rootQuestID) and self.ClosePartyQuestChain then
		local closed, origin = self:ClosePartyQuestChain()
		if closed then
			session.keyboardRowId, session.keyboardRole, session.keyboardPlayer = origin, nil, nil
			if frame.gamepadNavigation then
				frame.gamepadNavigation.selected = { session = session, rowId = origin, role = "quest" }
				frame.gamepadNavigation.armed = nil
			end
			self:RenderPartyQuestCompare()
			if origin then self:ScrollPartyQuestCompareToRow(frame, origin) end
			return true
		end
	end
	self:DismissManagedWindow(frame, source)
	return true
end

function QT:UpdatePartyQuestKeyboardPresentation(frame)
	local session = self.partyQuestCompareSession
	if not session or frame.displaySession ~= session or self:IsWorkBlocked("foreign_frame_mutation") then return end
	local active = frame.keyboardSession == session
	local selected = active and self:GetPartyQuestKeyboardTarget(frame.navigationRows, session.keyboardRowId)
	local target, role
	for _, control in ipairs(selected and self:GetPartyQuestRowControls(frame, selected) or {}) do
		if not target or control.role == session.keyboardRole and control.player == session.keyboardPlayer then
			target, role = control.button, control.role
		end
	end
	for _, row in ipairs(frame.rows or {}) do
		row.keyboardHighlight:ClearAllPoints()
		row.keyboardHighlight:SetAllPoints(row)
		if target and row.data and self:GetPartyQuestRowIdentity(row.data) == session.keyboardRowId then
			row.keyboardHighlight:SetAllPoints(target)
			row.keyboardHighlight:Show()
		elseif active then row.keyboardHighlight:Hide() end
	end
	if frame.keyboardPresentationOwner ~= target or frame.keyboardPresentationData ~= (selected and selected.data) then
		local previous = frame.keyboardPresentationOwner
		if previous then local leave = previous:GetScript("OnLeave"); if leave then leave(previous) end end
		frame.keyboardPresentationOwner, frame.keyboardPresentationData = target, selected and selected.data
		if target and role ~= "quest" and role ~= "group" and role ~= "more" then
			local enter = target:GetScript("OnEnter"); if enter then enter(target) end
		end
	end
end
