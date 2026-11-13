-- PQL owns logical selection and virtual-row materialization. The shared adapter
-- owns native registration, binding lifetime and the selected-frame pointer.
local QT = _G.QuestTogether
local DIRECTIONS = { "UP", "DOWN", "LEFT", "RIGHT" }
local OWNED_TOOLTIP_ROLES = { quest = true, journal = true, status = true, focus = true, player = true, column = true }

local function Mode(addon)
	return addon.IsNativeGamepadMode and addon:IsNativeGamepadMode() == true
end
local function Current(addon, frame)
	return Mode(addon) and not addon:IsWorkBlocked("foreign_frame_mutation")
		and addon:CanMutateOwnedUI(frame) and frame:IsVisible()
		and frame.displaySession and frame.displaySession == addon.partyQuestCompareSession
end
local function Copy(value)
	if not value then return end
	return { session = value.session, questId = value.questId, role = value.role,
		player = value.player, action = value.action, owner = value.owner }
end
local function Same(a, b, action)
	return a and b and a.session == b.session and a.questId == b.questId
		and a.role == b.role and a.player == b.player
		and (not action or (a.action == b.action and a.owner == b.owner))
end
local function Enabled(button)
	return button and button:IsVisible() and (not button.IsEnabled or button:IsEnabled())
end
local function Find(state, wanted)
	for button, identity in pairs(state.byButton) do
		if Same(identity, wanted) and Enabled(button) then return button end
	end
end
local function FindQuest(state, questId, role, player)
	local desired = { session = state.session, questId = questId, role = role, player = player }
	return Find(state, desired) or Find(state, { session = state.session, questId = questId, role = "quest" })
end
local function FirstQuest(frame, state)
	for _, row in ipairs(frame.rows) do
		local identity = state.byButton[row]
		if identity and identity.questId and Enabled(row) then return row end
	end
	return Enabled(frame.search) and frame.search or frame.close
end
local function Position(list, button)
	for i, candidate in ipairs(list) do if candidate == button then return i end end
end

function QT:IsPartyQuestGamepadInputOwned()
	local frame = self.partyQuestCompareWindow
	return frame and self.IsGamepadWindowFocused and self:IsGamepadWindowFocused(frame) == true or false
end

function QT:QueuePartyQuestGamepadPresentation(frame)
	local state = frame and frame.gamepadNavigation
	if not state or state.presentationPending then return end
	state.presentationPending = true
	self.API.Delay(0, function()
		state.presentationPending = nil
		if self:IsWorkBlocked("foreign_frame_mutation") or not self:CanMutateOwnedUI(frame) then return end
		local button, identity
		if state.focused and not state.restoreWanted and not state.parked and Current(self, frame)
			and self:IsGamepadWindowFocused(frame) then
			local _, _, selected = self:GetNativeGamepadFocus()
			if Same(state.selected, state.byButton[selected]) and Enabled(selected) then
				button, identity = selected, state.byButton[selected]
			end
		end
		for _, row in ipairs(frame.rows) do
			local data = row.data
			local highlighted = data and not data.kind and row.session == self.partyQuestCompareSession
				and ((identity and identity.questId == data.questId)
					or (frame.keyboardSession == row.session and row.session.keyboardQuestId == data.questId))
			if highlighted then row.keyboardHighlight:Show() else row.keyboardHighlight:Hide() end
		end
		-- Refresh only QT-authored handlers. Calling a template/native OnEnter
		-- here would claim a mouse transition that did not happen.
		if state.presentationOwner then
			local leave = state.presentationOwner:GetScript("OnLeave")
			if leave then leave(state.presentationOwner) end
			state.presentationOwner = nil
		end
		if identity and OWNED_TOOLTIP_ROLES[identity.role] then
			local enter = button:GetScript("OnEnter")
			if enter then enter(button); state.presentationOwner = button end
		end
	end)
end

function QT:ParkPartyQuestGamepadSelection(frame)
	local state = frame and frame.gamepadNavigation
	if not state or not Mode(self) then return true end
	local status = self.GetGamepadIntegrationStatus and self:GetGamepadIntegrationStatus()
	if status and status.failed and self:IsGamepadWindowRegistered(frame) then return false end
	if not self:IsGamepadWindowFocused(frame) or state.parked then return true end
	-- Hiding a selected pooled child also hides the native cursor anchored to
	-- it. Move that anchor onto an always-visible owned control before redraw.
	state.parking = true
	local ok = self:PrepareGamepadControlHide(frame.content, frame.close)
	state.parking = nil
	state.parked = ok == true or nil
	return ok == true
end

function QT:ActivatePartyQuestGamepadControl(frame, button)
	local state = frame.gamepadNavigation
	if not state or not Current(self, frame) or not self:IsGamepadActionCurrent(frame)
		or not Enabled(button) or not Same(state.armed, state.byButton[button], true) then return false end
	local _, _, selected = self:GetNativeGamepadFocus()
	if selected ~= button then return false end
	local identity = state.byButton[button]
	local row = identity.row
	if row and (row.session ~= identity.session or not row.data or row.data.kind or row.data.questId ~= identity.questId
		or (identity.role == "action" and (row.data.action ~= identity.action or row.data.owner ~= identity.owner))) then return false end
	local script = button:GetScript(identity.role == "quest" and "OnMouseUp" or "OnClick")
	if not script then return false end
	script(button, "LeftButton")
	return true
end

local function Bind(addon, frame, state, button, identity)
	state.byButton[button] = identity
	if not state.configured[button] then
		local installed = true
		for _, direction in ipairs(DIRECTIONS) do
			local key = direction
			installed = addon:SetGamepadDirectionOverride(button, key, function()
				return addon:MovePartyQuestGamepadSelection(frame, button, key)
			end) and installed
		end
		if installed then state.configured[button] = true end
		if identity.role ~= "search" then
			button.OnSmartNavClick = function(control) addon:ActivatePartyQuestGamepadControl(frame, control) end
		end
	end
	addon:SetGamepadControlIgnored(button, false)
end

local function Collect(addon, frame, state)
	state.byButton, state.toolbar, state.headers, state.rows = {}, {}, {}, {}
	local session = frame.displaySession
	local function Add(button, role, questId, player, data, list, row)
		if not button then return end
		if not Enabled(button) then addon:SetGamepadControlIgnored(button, true); return end
		Bind(addon, frame, state, button, { session = session, role = role, questId = questId,
			player = player, action = data and data.action, owner = data and data.owner, row = row })
		if list then list[#list + 1] = button end
	end
	for _, role in ipairs({ "close", "search", "filter", "reset", "refresh", "stopFollowing" }) do
		Add(frame[role], role, nil, nil, nil, state.toolbar)
	end
	for index, button in ipairs(frame.focusButtons) do
		local name = session.members[index] and session.members[index].name
		if name then
			Add(button, "player", nil, name, nil, state.headers)
			Add(frame.columnToggles[index], "column", nil, name, nil, state.headers)
		end
	end
	for _, row in ipairs(frame.rows) do
		local data = row.data
		local logical = row.session == session and data and not data.kind and Enabled(row)
		addon:SetGamepadControlIgnored(row, not logical)
		if logical then
			local list = {}; state.rows[data.questId] = list
			Add(row, "quest", data.questId, nil, nil, list, row)
			Add(row.journal, "journal", data.questId, nil, nil, list, row)
			for index, member in ipairs(session.members) do
				Add(row.cellTooltips and row.cellTooltips[index], "status", data.questId, member.name, nil, list, row)
				Add(row.focusCells[index], "focus", data.questId, member.name, nil, list, row)
			end
			Add(row.action, "action", data.questId, nil, data, list, row)
		end
	end
	-- Scroll frames contain only a materialized slice. Explicit direction
	-- overrides handle every exit; never associate these with right-stick scroll.
	for _, control in ipairs({ frame.resizeGrip, frame.vertical, frame.horizontal }) do
		if control then addon:SetGamepadControlIgnored(control, true) end
	end
	-- The template's clear button hides itself during activation. Reset already
	-- exposes clearing the search without anchoring native focus to that child.
	if frame.search.clearButton then addon:SetGamepadControlIgnored(frame.search.clearButton, true) end
end

function QT:RefreshPartyQuestGamepad(frame)
	local state = frame and frame.gamepadNavigation
	if not state or not Current(self, frame) then return end
	if state.updating then return end
	state.updating = true
	local session, old = frame.displaySession, state.selected
	if state.session ~= session then state.session, state.selected, state.armed = session, nil, nil; old = nil end
	Collect(self, frame, state)
	local focused = self:IsGamepadWindowFocused(frame)
	local target = old and Find(state, old)
	-- Structural refreshes preserve the selected quest through sorting, resize
	-- and expansion. A mouse-wheel scroll intentionally changes the visible slice.
	if old and old.questId and not target and (frame.rendering or state.restoreWanted) and not state.materializing then
		state.materializing = true
		self:ScrollPartyQuestCompareToQuest(frame, old.questId)
		state.materializing = nil
		Collect(self, frame, state)
		target = Find(state, old)
	end
	if focused and not state.materializing then
		target = target or FirstQuest(frame, state)
		local identity = state.byButton[target]
		state.selected = Copy(identity)
		-- Reusing the same physical frame does not emit native selection callbacks.
		-- A changed quest/action must not inherit permission from the old selection.
		if not Same(state.armed, identity, true) then state.armed = nil end
	end
	state.updating = nil
	state.parked = nil
	self:RefreshGamepadNavigation(frame, focused and not state.materializing and target or nil)
	if frame.gamepadPresentSession == session then
		frame.gamepadPresentSession = nil
		if not self:PresentGamepadWindow(frame, "user") and not self:IsGamepadWindowFocused(frame) then
			self:RequestPartyQuestKeyboardFocus(frame)
		end
	end
	self:QueuePartyQuestGamepadPresentation(frame)
end

function QT:MovePartyQuestGamepadSelection(frame, button, direction)
	local state = frame.gamepadNavigation
	if not state or not state.focused or state.restoreWanted or not Current(self, frame)
		or not self:IsGamepadActionCurrent(frame) then return true end
	local identity = state.byButton[button]
	if not identity or identity.session ~= self.partyQuestCompareSession then return true end
	local target
	if identity.questId and (direction == "UP" or direction == "DOWN") then
		local nextRow = self:GetPartyQuestKeyboardTarget(frame.navigationRows, identity.questId, direction, frame.rowsViewport:GetHeight())
		if nextRow and nextRow.questId ~= identity.questId then
			state.materializing = true
			self:ScrollPartyQuestCompareToQuest(frame, nextRow.questId)
			state.materializing = nil
			target = FindQuest(state, nextRow.questId, identity.role, identity.player)
		elseif direction == "UP" then target = state.headers[1] or frame.filter end
	elseif identity.questId then
		local list = state.rows[identity.questId] or {}
		local index = Position(list, button)
		if index then target = list[index + (direction == "LEFT" and -1 or 1)] end
	else
		local header = identity.role == "player" or identity.role == "column"
		local list = header and state.headers or state.toolbar
		if direction == "LEFT" or direction == "RIGHT" then
			local index = Position(list, button)
			if index then target = list[index + (direction == "LEFT" and -1 or 1)] end
		elseif direction == "DOWN" then
			target = not header and state.headers[1] or FirstQuest(frame, state)
		elseif header then target = frame.filter end
	end
	if not target or not Enabled(target) then return true end
	self:RevealPartyQuestGamepadControl(frame, state.byButton[target])
	state.selected, state.armed = Copy(state.byButton[target]), Copy(state.byButton[target])
	-- This refresh does not select: the native directional callback selects its
	-- returned frame, including when the pool reused the same frame identity.
	self:RefreshGamepadNavigation(frame)
	self:QueuePartyQuestGamepadPresentation(frame)
	return target
end

function QT:RequestPartyQuestGamepadFocus(frame)
	if not frame or not Mode(self) then return false end
	self:ConfigurePartyQuestGamepadNavigation(frame)
	frame.gamepadPresentSession = self.partyQuestCompareSession
	self:SetPartyQuestKeyboardNavigation(frame, false)
	if frame.displaySession == self.partyQuestCompareSession then self:RefreshPartyQuestGamepad(frame) end
	return true
end

function QT:ConfigurePartyQuestGamepadNavigation(frame)
	if frame.gamepadNavigation or not self.ConfigureGamepadWindow then return end
	local state = { configured = {}, byButton = {}, toolbar = {}, headers = {}, rows = {} }
	frame.gamepadNavigation = state
	self:ConfigureGamepadWindow(frame, {
		role = "compare", kind = "window", footer = true,
		defaultFocus = function() return FirstQuest(frame, state) end,
		close = function() self:DismissManagedWindow(frame, "gamepad") end,
		onSelection = function(_, button)
			if not state.focused or state.parking or state.parked or state.updating or state.restoreWanted or not Current(self, frame) then return end
			local identity = state.byButton[button]
			if identity then
				local changed = state.nativeButton ~= button or not Same(state.selected, identity, true)
				state.selected = Copy(identity)
				if state.nativeButton ~= button then state.armed = Copy(identity) end
				state.nativeButton = button
				if changed then self:QueuePartyQuestGamepadPresentation(frame) end
			end
		end,
		onFocus = function(_, focused)
			state.focused = focused == true
			state.nativeButton, state.armed = nil, nil
			local token, session = {}, frame.displaySession
			state.focusToken, state.restoreWanted = token, nil
			self:QueuePartyQuestGamepadPresentation(frame)
			if not focused then return end
			if not state.selected then return end
			state.restoreWanted = Copy(state.selected)
			-- Native resumes its saved physical button during this callback. Wait
			-- until that dispatch ends before restoring our logical row/control.
			self.API.Delay(0, function()
				if state.focusToken ~= token then return end
				if not Current(self, frame) or frame.displaySession ~= session or not self:IsGamepadActionCurrent(frame) then
					state.restoreWanted = nil; return
				end
				state.selected = Copy(state.restoreWanted)
				self:RefreshPartyQuestGamepad(frame)
				state.restoreWanted = nil
				local _, _, button = self:GetNativeGamepadFocus()
				if Same(state.selected, state.byButton[button], true) then
					state.nativeButton, state.armed = button, Copy(state.selected)
				end
				self:QueuePartyQuestGamepadPresentation(frame)
			end)
		end,
	})
end

function QT:GetPartyQuestGamepadContext()
	local frame = self.partyQuestCompareWindow
	local state = frame and frame.gamepadNavigation
	if not state or not Current(self, frame) or not self:IsGamepadWindowFocused(frame) then return end
	local identity = Copy(state.selected)
	local button = identity and Find(state, identity)
	if not button then return end
	local session = frame.displaySession
	if identity.questId then
		for _, selected in ipairs(frame.navigationRows) do
			if selected.questId == identity.questId then
				return { owner = button, populate = function(root)
					if self.partyQuestCompareSession == session and Current(self, frame) then
						self:PopulatePartyQuestContextMenu(frame, selected, root)
					end
				end }
			end
		end
	elseif identity.player then
		return { owner = button, populate = function(root)
			if self.partyQuestCompareSession == session and Current(self, frame) then
				self:PopulatePartyQuestPlayerMenu(frame, session, identity.player, root)
			end
		end }
	end
end
