-- Private UI and native-adapter doubles only. No engine input or global patching.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
local function Fixture(count, mode)
	local entries = {}
	for id = 1, count or 32 do entries[id] = { questId = id, questTitle = string.format("Quest %02d", id), isPushable = true } end
	local a = QT:CreateTestPartyQuestCompareFixture(entries)
	a.options.reduceMotion, a.nativeMode = true, mode ~= false
	a.nativePolicies, a.nativeRegistered, a.nativeDirections, a.nativeIgnored = {}, {}, {}, {}
	a.nativePresents, a.nativeRefreshes = 0, 0
	local create = a.CreateOwnedWindowFrame
	function a:CreateOwnedWindowFrame(...)
		local frame = create(self, ...)
		function frame:IsEnabled() return self.enabled end
		return frame
	end
	function a:IsNativeGamepadMode() return self.nativeMode end
	function a:ConfigureGamepadWindow(frame, policy) self.nativePolicies[frame] = policy; return true end
	function a:IsGamepadWindowFocused(frame) return self.nativeMode and self.nativeFrame == frame and not self.blocked end
	function a:IsGamepadWindowRegistered(frame) return self.nativeRegistered[frame] == true end
	function a:IsGamepadActionCurrent(frame) return self:IsGamepadWindowFocused(frame) and self.nativeRegistered[frame] == true end
	function a:GetNativeGamepadFocus() return self.nativeFrame, self.nativeFrame, self.nativeButton end
	function a:SelectNative(frame, button)
		if self.nativeButton == button then return end -- Native SelectButton skips recycled identical pointers.
		self.nativeButton = button
		local policy = self.nativePolicies[frame]
		if policy.onSelection then policy.onSelection(frame, button) end
	end
	function a:PresentGamepadWindow(frame, intent)
		Equal(intent, "user")
		if not self.nativeMode then return false end
		self.nativePresents, self.nativeFrame, self.nativeRegistered[frame] = self.nativePresents + 1, frame, true
		local policy = assert(self.nativePolicies[frame])
		if policy.onFocus then policy.onFocus(frame, true) end
		self:SelectNative(frame, type(policy.defaultFocus) == "function" and policy.defaultFocus(frame) or policy.defaultFocus)
		return true
	end
	function a:RefreshGamepadNavigation(frame, target)
		self.nativeRefreshes = self.nativeRefreshes + 1
		if self.failNativeRefresh then return false end
		if target and self:IsGamepadWindowFocused(frame) then self:SelectNative(frame, target) end
		return true
	end
	function a:PrepareGamepadControlHide(control, fallback)
		local selected = self.nativeButton
		while selected do
			if selected == control then return self:RefreshGamepadNavigation(self.nativeFrame, fallback) end
			selected = selected:GetParent()
		end
		return true
	end
	function a:SetGamepadDirectionOverride(button, direction, callback)
		self.nativeDirections[button] = self.nativeDirections[button] or {}
		self.nativeDirections[button][direction] = callback
		return true
	end
	function a:SetGamepadControlIgnored(button, ignored) self.nativeIgnored[button] = ignored; return true end
	function a:MarkGamepadContainer() return true end
	function a:HideGamepadWindow(frame, complete)
		if not self.nativeRegistered[frame] then return false end
		local function Finish()
			self.nativeRegistered[frame] = nil
			if self.nativeFrame == frame then self.nativeFrame, self.nativeButton = nil, nil end
			frame:Hide()
			if complete then complete() end
		end
		if self.delayNativeHide then self.finishNativeHide = Finish; return true, false end
		Finish(); return true, true
	end
	function a:ShowSettingsTooltip(owner, title, text)
		self.tooltip = { owner = owner, title = title, text = text }
		self.tooltipShows = (self.tooltipShows or 0) + 1
	end
	function a:HideSettingsTooltip(owner)
		if not owner or self.tooltip and self.tooltip.owner == owner then self.tooltip = nil end
	end
	return a
end
local function Open(count, mode)
	local a = Fixture(count, mode)
	a:OpenPartyQuestCompare()
	a:RenderPartyQuestCompare()
	local frame = a.partyQuestCompareWindow
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	return a, frame, a.partyQuestCompareSession
end
local function Find(frame, questId, role, player)
	for button, identity in pairs(frame.gamepadNavigation.byButton) do
		if identity.questId == questId and identity.role == role and identity.player == player then return button end
	end
	error("missing materialized control " .. tostring(questId) .. ":" .. role)
end
local function Move(a, frame, direction)
	local target = assert(a.nativeDirections[a.nativeButton])[direction]()
	if target ~= true then a:SelectNative(frame, target) end
	return target
end
local function Selected(a, frame) return frame.gamepadNavigation.byButton[a.nativeButton] end

QT:RegisterTest("party log native navigation owns input only while its panel is focused", function()
	local a, frame, session = Open()
	Equal(a.nativePresents, 1)
	Equal(frame.keyboardSession, nil)
	Equal(Selected(a, frame).questId, 1)
	a.nativeFrame = nil -- An unavailable adapter/native foreign owner must not globally disable keyboard.
	a:RequestPartyQuestKeyboardFocus(frame)
	frame.keyboardInput:RunScript("OnUpdate", 0.016)
	Equal(frame.keyboardSession, session)
	a.nativeMode = false
	Equal(a:IsPartyQuestGamepadInputOwned(), false)
	local b, mouseFrame, mouseSession = Open(3, false)
	Equal(b.nativePresents, 0)
	Equal(mouseFrame.keyboardSession, mouseSession)
	Equal(a.invalidCalls, nil); Equal(b.invalidCalls, nil)
end)

QT:RegisterTest("party log native directions materialize virtual roots and retain shared expansion geometry", function()
	local a, frame, session = Open(40)
	local first = a.nativeButton
	first.OnSmartNavClick(first)
	Equal(session.expandedQuestIds[1], true) -- Select expands, the QT menu binding opens actions.
	a:RenderPartyQuestCompare()
	assert(frame.navigationRows[2].top > 42)
	for id = 2, 40 do Move(a, frame, "DOWN"); Equal(Selected(a, frame).questId, id) end
	assert(session.scrollPixels > 0)
	Equal(Move(a, frame, "DOWN"), true)
	for id = 39, 1, -1 do Move(a, frame, "UP"); Equal(Selected(a, frame).questId, id) end
	Move(a, frame, "UP"); Equal(Selected(a, frame).role, "player")
	Move(a, frame, "UP"); Equal(Selected(a, frame).role, "filter")
	Equal(a.nativeIgnored[frame.vertical], true)
	Equal(a.nativeIgnored[frame.horizontal], true)
	Equal(a.nativeIgnored[frame.search.clearButton], true)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log semantic focus survives root reordering and materializes its selected quest", function()
	local a, frame = Open(40)
	for _ = 1, 20 do Move(a, frame, "DOWN") end
	Equal(Selected(a, frame).questId, 21)
	local priorButton = a.nativeButton
	a.nativePolicies[frame].onFocus(frame, false)
	a.nativeFrame = {} -- An owned action panel temporarily takes native focus.
	local build = a.BuildPartyQuestDiffRows
	function a:BuildPartyQuestDiffRows()
		local rows = build(self)
		local reversed = {}; for i = #rows, 1, -1 do reversed[#reversed + 1] = rows[i] end
		return reversed
	end
	a:RenderPartyQuestCompare()
	a.nativeFrame = frame
	a.nativeButton = nil
	a:SelectNative(frame, priorButton) -- Native may report its old pool pointer before FocusGamepad.
	a.nativePolicies[frame].onFocus(frame, true)
	Equal(Move(a, frame, "DOWN"), true) -- Held navigation cannot act on that transient pool identity.
	a:Advance(0)
	Equal(Selected(a, frame).questId, 21)
	Equal(Selected(a, frame).role, "quest")
	assert(a:ActivatePartyQuestGamepadControl(frame, a.nativeButton))
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log player and action controls share navigation and reject recycled action identity", function()
	local a, frame, session = Open(4)
	local build = a.BuildPartyQuestDiffRows
	local changed = false
	function a:BuildPartyQuestDiffRows()
		local rows = build(self)
		rows[1].action, rows[1].owner = "share", changed and "Changed-Realm" or "Original-Realm"
		return rows
	end
	a:RenderPartyQuestCompare()
	local action = Find(frame, 1, "action")
	Equal(a.nativePresents, 1)
	Equal(frame.gamepadNavigation.focused, true)
	Equal(frame.gamepadNavigation.parked, nil)
	Equal(frame.gamepadNavigation.updating, nil)
	Equal(frame.gamepadNavigation.restoreWanted, nil)
	a:SelectNative(frame, action)
	local shares = 0
	function a:SharePartyDiffQuest(id) Equal(id, 1); shares = shares + 1 end
	assert(frame.gamepadNavigation.armed, "action selection must arm its semantic identity")
	Equal(frame.gamepadNavigation.armed.role, "action")
	assert(a:ActivatePartyQuestGamepadControl(frame, action), "current action must dispatch")
	Equal(shares, 1)
	local identity = frame.gamepadNavigation.byButton[action]
	identity.row.data.owner = "Unrendered-Realm"
	action.OnSmartNavClick(action); Equal(shares, 1)
	identity.row.data.owner = identity.owner
	changed = true
	a:RenderPartyQuestCompare()
	Equal(a.nativeButton, action)
	a.nativePolicies[frame].onSelection(frame, action) -- A redundant native notification is not new consent.
	action.OnSmartNavClick(action); Equal(shares, 1)
	Move(a, frame, "LEFT"); Move(a, frame, "RIGHT")
	action.OnSmartNavClick(action); Equal(shares, 2)
	local member = session.members[2].name
	a:SelectNative(frame, Find(frame, nil, "column", member))
	a.nativeButton.OnSmartNavClick(a.nativeButton)
	a:RenderPartyQuestCompare()
	Equal(session.collapsedPlayers[member], true)
	Equal(Selected(a, frame).player, member)
	Equal(Selected(a, frame).role, "column")
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log redraw parks the native anchor before hiding a row and aborts failed parking", function()
	local a, frame = Open(4)
	local row = a.nativeButton
	local hidden = false
	row:HookScript("OnHide", function() assert(a.nativeButton ~= row, "native cursor remained anchored to a hidden row"); hidden = true end)
	a:SetPartyQuestCompareFilter("search", "No matching quest")
	a:RenderPartyQuestCompare()
	Equal(hidden, true)
	Equal(a.nativeButton, frame.search)
	a:SetPartyQuestCompareFilter("search", "")
	a:RenderPartyQuestCompare()
	a:SelectNative(frame, Find(frame, 1, "quest"))
	local writes = frame.rows[1].writes
	a.failNativeRefresh = true
	a:RenderPartyQuestCompare()
	Equal(frame.rows[1].writes, writes)
	Equal(frame.gamepadNavigation.parked, nil)
	Equal(a.nativeButton, frame.rows[1])
	a.blocked = true
	Equal(a:ActivatePartyQuestGamepadControl(frame, a.nativeButton), false)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log contextual native actions revalidate session restriction and row availability", function()
	local a, frame, session = Open(4)
	local context = assert(a:GetPartyQuestGamepadContext())
	local callbacks = {}
	context.populate({ CreateTitle = function() end, CreateButton = function(_, _, callback) callbacks[#callbacks + 1] = callback end })
	assert(#callbacks > 0)
	a.blocked = true; callbacks[1](); Equal(session.expandedQuestIds[1], nil)
	a.blocked = false
	a.partyQuestCompareSession = {}; callbacks[1](); Equal(session.expandedQuestIds[1], nil)
	a.partyQuestCompareSession = session
	a.db = { profile = {} }; callbacks[1](); Equal(session.expandedQuestIds[1], nil)
	a.db = nil
	frame.navigationRows = {}; callbacks[1](); Equal(session.expandedQuestIds[1], nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("request prompts register only on explicit presentation and preserve a chosen pending request", function()
	local a = Fixture(3)
	local first = { key = "first", sender = "Friend-Realm", questId = 1, order = 1, expires = 200 }
	local chosen = { key = "chosen", sender = "Friend-Realm", questId = 2, order = 2, expires = 200 }
	a.partyQuestShareState = { incoming = { first = first, chosen = chosen } }
	local frame = a:RenderPartyQuestSharePrompt()
	Equal(frame.request, first); Equal(a.nativePresents, 0)
	Equal(a:RenderPartyQuestSharePrompt(chosen), frame)
	Equal(frame.request, chosen)
	Equal(a.nativePolicies[frame].defaultFocus, frame.decline)
	a:PresentGamepadWindow(frame, "user")
	a:RenderPartyQuestSharePrompt()
	Equal(frame.request, chosen); Equal(a.nativePresents, 1)
	Equal(a:RenderPartyQuestSharePrompt({ key = "chosen", sender = chosen.sender, expires = 200 }), nil)
	Equal(frame.request, chosen)
	a.partyQuestShareState.incoming.chosen = nil
	a.delayNativeHide = true
	Equal(a:RenderPartyQuestSharePrompt(), nil)
	Equal(frame.request, nil); Equal(frame.requestRetiring, true)
	Equal(a:RenderPartyQuestSharePrompt(first), nil)
	a.finishNativeHide()
	Equal(frame.requestRetiring, nil)
	Equal(a:RenderPartyQuestSharePrompt(), frame)
	Equal(frame.request, first); Equal(a.nativePresents, 1)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("party log native presentation refreshes highlights and a recycled cell tooltip without pointer movement", function()
	local a, frame, session = Open(3)
	a:Advance(0)
	Equal(frame.rows[1].keyboardHighlight:IsShown(), true)
	Equal(frame.rows[2].keyboardHighlight:IsShown(), false)
	Equal(a.tooltip.title, "Quest 01")
	local member = session.members[1].name
	a:SetPartyQuestColumnCollapsed(member, true, session)
	a:RenderPartyQuestCompare()
	local status = Find(frame, 1, "status", member)
	a:SelectNative(frame, status)
	a:Advance(0)
	Equal(a.tooltip.owner, status)
	Equal(a.tooltip.text, "Have")
	local shows = a.tooltipShows
	a.nativePolicies[frame].onSelection(frame, status)
	a:Advance(0)
	Equal(a.tooltipShows, shows)
	status.questStatus = "Completed"
	a:RefreshPartyQuestGamepad(frame) -- Same native pointer: the double emits no selection/enter callback.
	a:Advance(0)
	Equal(a.nativeButton, status)
	Equal(a.tooltip.text, "Completed")
	Move(a, frame, "DOWN")
	a:Advance(0)
	Equal(frame.rows[1].keyboardHighlight:IsShown(), false)
	Equal(frame.rows[2].keyboardHighlight:IsShown(), true)
	Equal(a.tooltip.owner, a.nativeButton)
	Equal(a.tooltip.text, "Have")
	a.nativePolicies[frame].onFocus(frame, false)
	a.nativeFrame = nil
	a:Advance(0)
	Equal(frame.rows[2].keyboardHighlight:IsShown(), false)
	Equal(a.tooltip, nil)
	Equal(a.invalidCalls, nil)
end)

QT:RegisterTest("explicit join prompt selection checks incoming identity profile roster and expiry", function()
	local a = Fixture(1)
	a.db, a.partyRosterFingerprint = { profile = {} }, "roster"
	function a:CanAcceptPartyJoin() return true end
	local request = { sender = "New-Realm", created = 90, expires = 200, profile = a.db.profile, roster = "roster" }
	a.partyJoinState = { incoming = { [request.sender] = request } }
	local frame = assert(a:RenderPartyJoinPrompt(request))
	Equal(frame.request, request); Equal(a.nativePresents, 0)
	Equal(a.nativePolicies[frame].defaultFocus, frame.decline)
	request.profile = {}; Equal(a:RenderPartyJoinPrompt(request), nil)
	request.profile = a.db.profile; request.roster = "stale"; Equal(a:RenderPartyJoinPrompt(request), nil)
	request.roster = "roster"; request.expires = 100; Equal(a:RenderPartyJoinPrompt(request), nil)
	Equal(a.invalidCalls, nil)
end)

_G.QuestTogether:RecordTestModule("scripts/regression_compare_gamepad.lua")
