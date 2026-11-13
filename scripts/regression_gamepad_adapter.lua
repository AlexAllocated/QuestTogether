-- Offline lifecycle checks only. These doubles model selected native contracts;
-- they do not model WoW taint, protected APIs, cursor geometry, or physical input.
-- Unlike r4's double, IsShown does not imply visibility and Hide dispatches
-- OnHide only across a visible -> invisible transition. Native manager removal
-- does not directly clear navigation: that work belongs to navigation OnHide.
local fixture = "GamepadIntegration.lua"

local function newHarness(options)
	options = options or {}
	local h = {
		options = options,
		timers = {},
		frames = {},
		named = {},
		reports = {},
		calls = {},
		callFrames = {},
		now = 1,
		mode = true,
		combat = false,
		hides = 0,
		shows = 0,
		hiddenFocuses = 0,
		navHideEvents = 0,
		apiCounts = { registrations = 0, footers = 0, menus = 0, dropdowns = 0 },
	}
	local env = setmetatable({}, { __index = _G })
	env._G = env
	local function noop() end
	env.print = noop
	local function call(name, frame)
		assert(not h.combat, "Native write during combat: " .. name)
		h.calls[#h.calls + 1] = name
		h.callFrames[#h.callFrames + 1] = frame or false
	end
	local function registry()
		local object = { callbacks = {} }
		function object:RegisterCallback(event, callback, owner)
			h.apiCounts.registrations = h.apiCounts.registrations + 1
			self.callbacks[event] = self.callbacks[event] or {}
			self.callbacks[event][owner or callback] = callback
		end
		function object:UnregisterCallback(event, owner)
			if self.callbacks[event] then
				self.callbacks[event][owner] = nil
			end
		end
		function object:TriggerEvent(event, ...)
			for owner, callback in pairs(self.callbacks[event] or {}) do
				callback(owner, ...)
			end
		end
		return object
	end
	env.EventRegistry = registry()
	local nav = registry()
	local manager = { members = {}, returnFrames = {}, lastButtons = {} }
	h.manager, h.nav = manager, nav
	env.SmartNavigation, env.SmartNavigationSecureHelper = nav, {}
	env.PromptedBindingFooterMixin = {}
	for _, name in ipairs({
		"AddStandardSelectPrompt",
		"AddStandardBackPrompt",
		"Finalize",
		"IsBindingGroupRequired",
		"ShowAndActivateBindings",
		"HideAndDeactivateBindings",
	}) do
		env.PromptedBindingFooterMixin[name] = function()
			error("Adapter must use footer instances")
		end
	end
	env.SMART_NAV_INPUT_DIRECTION =
		{ UP = { dirKey = "up" }, DOWN = { dirKey = "down" }, LEFT = { dirKey = "left" }, RIGHT = { dirKey = "right" } }
	env.SmartNavigation_MarkFrameIgnored = function(frame)
		call("MarkIgnored", frame)
	end
	env.SmartNavigation_ClearIgnoreStatus = function(frame)
		call("ClearIgnore", frame)
	end
	env.SmartNavigation_AddJumpNavigationOverride = function(frame)
		call("JumpOverride", frame)
	end
	env.GamepadMode = { FrameControlsManager = manager }
	local methods = {}
	function methods:Hide()
		if not self.shown then
			return
		end
		-- Native panel registration installs an OnHide path. Calling own Hide before
		-- removing registration is already unsafe, even if cleanup follows later.
		assert(not manager.members[self], "Owned Hide before native unregister: " .. (self.name or "anonymous"))
		local wasVisible = self:IsVisible()
		-- An already invisible subtree has no new OnHide/cursor-anchor transition.
		local anchor = wasVisible and nav:IsShown() and nav.anchor
		while anchor do
			assert(anchor ~= self, "Owned child Hide before native cursor reanchor")
			anchor = anchor.parent
		end
		h.hides = h.hides + 1
		self.shown = false
		if wasVisible then
			if self.scripts.OnHide then
				self.scripts.OnHide(self)
			end
			for _, hook in ipairs(self.hooks.OnHide or {}) do
				hook(self)
			end
		end
	end
	function methods:Show()
		if self.shown then
			return
		end
		h.shows = h.shows + 1
		self.shown = true
		if self:IsVisible() then
			if self.scripts.OnShow then
				self.scripts.OnShow(self)
			end
			for _, hook in ipairs(self.hooks.OnShow or {}) do
				hook(self)
			end
		end
	end
	function methods:IsShown()
		return self.shown
	end
	function methods:IsVisible()
		return self.shown and (not self.parent or not self.parent.IsVisible or self.parent:IsVisible())
	end
	function methods:IsForbidden()
		return false
	end
	function methods:IsProtected()
		return false
	end
	function methods:GetName()
		return self.name
	end
	function methods:GetParent()
		return self.parent
	end
	function methods:GetObjectType()
		return self.kind
	end
	function methods:SetScript(event, callback)
		assert(
			event ~= "OnKeyDown"
				and event ~= "OnKeyUp"
				and event ~= "OnGamePadButtonDown"
				and event ~= "OnGamePadButtonUp",
			"Fixture introduced raw keyboard/gamepad input handling"
		)
		self.scripts[event] = callback
	end
	function methods:GetScript(event)
		return self.scripts[event]
	end
	function methods:HookScript(event, callback)
		self.hooks[event] = self.hooks[event] or {}
		table.insert(self.hooks[event], callback)
	end
	function methods:RegisterEvent(event)
		self.events[event] = true
	end
	function methods:CreateFontString()
		return {
			SetPoint = noop,
			SetWidth = noop,
			SetText = function(self, text)
				self.text = text
			end,
		}
	end
	function methods:SetText(text)
		self.text = text
	end
	function methods:SetFrameLevel(level)
		self.level = level
	end
	function methods:GetFrameLevel()
		return self.level or 1
	end
	function methods:SetFrameStrata(strata)
		self.strata = strata
	end
	function methods:GetFrameStrata()
		return self.strata or "MEDIUM"
	end
	function methods:IsEnabled()
		return self.enabled ~= false
	end
	function methods:Enable()
		self.enabled = true
	end
	function methods:Disable()
		self.enabled = false
	end
	function methods:SetEnabled(value)
		self.enabled = value
	end
	function methods:Click()
		if self.enabled ~= false and self.scripts.OnClick then
			self.scripts.OnClick(self, "LeftButton")
		end
	end
	for _, name in ipairs({
		"SetSize",
		"SetPoint",
		"SetBackdrop",
		"SetBackdropColor",
		"SetBackdropBorderColor",
		"SetClampedToScreen",
		"SetToplevel",
		"EnableMouse",
		"SetMovable",
		"RegisterForDrag",
		"RegisterForClicks",
	}) do
		methods[name] = noop
	end
	function env.CreateFrame(kind, name, parent, template)
		if kind == "DropdownButton" or (template and template:find("Dropdown", 1, true)) then
			h.apiCounts.dropdowns = h.apiCounts.dropdowns + 1
			error("Owned-panel fixture must not create native dropdown controls")
		end
		assert(not name or not h.named[name], "Duplicate named frame")
		local frame = setmetatable(
			{ kind = kind, name = name, parent = parent, scripts = {}, hooks = {}, events = {}, shown = true },
			{ __index = methods }
		)
		h.frames[#h.frames + 1] = frame
		if name then
			h.named[name] = frame
		end
		return frame
	end
	env.UIParent = env.CreateFrame("Frame", "UIParent")
	env.C_Timer = {
		After = function(delay, callback)
			h.timers[#h.timers + 1] = { callback = callback, due = h.now + delay }
		end,
	}
	env.GetTime = function()
		return h.now
	end
	env.issecure = function()
		return false
	end
	env.issecretvalue = function()
		return false
	end
	env.canaccessvalue = function()
		return true
	end
	env.issecurevariable = function()
		return true
	end
	env.InCombatLockdown = function()
		return h.combat
	end
	env.GetBuildInfo = function()
		return options.version or "1.60.1", options.build or "70888"
	end
	env.Enum = { AddOnRestrictionType = { Combat = 1 } }
	env.C_RestrictedActions = {
		IsAddOnRestrictionActive = function()
			return h.combat
		end,
	}
	env.C_EventUtils = {
		IsEventValid = function()
			return true
		end,
	}
	h.transitions = {}
	env.InputUtil = {
		IsGamepadUIEnabled = function()
			return h.mode
		end,
		RegisterForInterfaceTransitions = function(owner)
			if options.failTransitions then
				error("Injected transition registration failure")
			end
			if options.securityOnTransitions then
				h:event("ADDON_ACTION_FORBIDDEN", "QuestTogether")
			end
			h.transitions[owner] = h.transitions[owner] or {}
		end,
		RegisterGamepadInit = function(owner, callback)
			assert(h.transitions[owner], "Transition owner was not registered")
			h.transitions[owner].init = callback
			-- Native registration immediately invokes Init for the current style.
			if h.mode then
				callback()
			end
		end,
		RegisterGamepadUninit = function(owner, callback)
			assert(h.transitions[owner], "Transition owner was not registered")
			h.transitions[owner].uninit = callback
		end,
	}
	nav.bindingActive, nav.rightStickScrolling = false, false
	env.SlashCmdList = {}
	env.DEFAULT_CHAT_FRAME = { AddMessage = noop }
	env.FRAME_ACTION_BACK, env.FRAME_ACTION_CLOSE = "Back", "Close"
	function nav:GetActiveFrame()
		return self.active
	end
	function nav:GetCurrentButton()
		return self.button
	end
	function nav:IsShown()
		return self.shown == true
	end
	function nav:IsVisible()
		return self:IsShown() and env.UIParent:IsVisible()
	end
	function nav:Hide()
		local wasVisible = self:IsVisible()
		self.shown = false
		if wasVisible then
			-- Native SmartNavigation.OnHide334 clears activeInfo, and339
			-- deactivates navigation. No visible transition means no rerun.
			h.navHideEvents = h.navHideEvents + 1
			self.active, self.button, self.bindingActive, self.rightStickScrolling = nil, nil, false, false
		end
	end
	function nav:RefreshButtonGroups(frame)
		call("RefreshButtonGroups", frame)
	end
	function nav:SetScrollFrameForFrame(frame, scroll)
		call("SetScrollFrameForFrame", frame)
		frame.scrollTarget = scroll
		if self.active == frame then self.rightStickScrolling = scroll ~= nil end
	end
	function nav:SetGridHeightCompensation()
		call("SetGridHeightCompensation")
	end
	function nav:SetTargetButtonForFrame(frame, button)
		call("SetTargetButtonForFrame", frame)
		-- The authored target API must never promote an inactive panel.
		if self.active ~= frame or options.rejectTarget then
			return
		end
		self.button, self.anchor = button, button
		manager.lastButtons[frame] = button
		if button and button.OnSmartNavSelect then
			button:OnSmartNavSelect()
		end
		self:TriggerEvent("SelectedButtonUpdated")
	end
	function env.SmartNavigation_MarkFrameIgnoredContainerFrame(frame)
		call("MarkIgnoredContainer", frame)
		if options.securityOnMark then
			h.setupFailureMark = { writes = #h.calls, hides = h.hides, frames = #h.frames }
			h:event("ADDON_ACTION_FORBIDDEN", "QuestTogether")
		end
	end
	local function focus(frame, keepNavigation)
		if frame then
			assert(frame:IsShown(), "Native focus must reject explicitly hidden frames")
			if not frame:IsVisible() then
				h.hiddenFocuses = h.hiddenFocuses + 1
			end
		end
		if nav.active then
			manager.lastButtons[nav.active] = nav.button
		end
		if manager.active and manager.active.UnfocusGamepad then
			manager.active:UnfocusGamepad()
		end
		manager.active, manager.focusedFrame, manager.isUIFocused = frame, frame, frame ~= nil
		if not keepNavigation then
			nav.active, nav.button = frame, manager.lastButtons[frame]
			if nav.button then
				nav.anchor = nav.button
			end
			nav.shown = frame ~= nil
			nav.rightStickScrolling = frame ~= nil and frame.scrollTarget ~= nil
		end
		nav.bindingActive = nav.active ~= nil
		if frame and frame.FocusGamepad then
			frame:FocusGamepad()
		end
		env.EventRegistry:TriggerEvent("Gamepad.RefreshFrameFocus")
	end
	h.focus = focus
	function manager:GetActiveFrame()
		return self.active
	end
	function manager:IsUIFocused()
		return self.active ~= nil
	end
	function manager:GetShownFrameCount()
		local count = 0
		for _ in pairs(self.members) do
			count = count + 1
		end
		return count
	end
	local function register(frame, popup)
		call(popup and "HandlePopupShown" or "FrameShown", frame)
		if options.rejectRegister then
			return false
		end
		if manager.members[frame] then
			return false
		end
		if popup then
			manager.returnFrames[frame] = manager.active
		end
		manager.members[frame] = true
		focus(frame, options.navMismatch)
		if options.securityOnRegister then
			h:event("ADDON_ACTION_FORBIDDEN", "QuestTogether")
		end
		if options.failAfterInsert then
			error("Injected failure after native insertion")
		end
		return true
	end
	function manager:FrameShown(frame)
		return register(frame, false)
	end
	function manager:HandlePopupShown(frame)
		register(frame, true)
	end
	function manager:FrameHidden(frame)
		call("FrameHidden", frame)
		if options.failUnregister then
			error("Injected unregister failure")
		end
		if options.rejectUnregister then
			return false
		end
		if not self.members[frame] then
			return false
		end
		self.members[frame] = nil
		local previous = self.returnFrames[frame]
		self.returnFrames[frame] = nil
		if self.active == frame and not options.retainDetachedFocus then
			if previous and self.members[previous] then
				focus(previous)
			else
				if self.active.UnfocusGamepad then
					self.active:UnfocusGamepad()
				end
				self.active, self.focusedFrame, self.isUIFocused = nil, nil, false
				-- FCM FrameHidden542-544 hides navigation, whose OnHide owns
				-- clearing activeInfo. Do not grant a magical focus(nil).
				nav:Hide()
			end
		end
		if options.securityOnUnregister then
			h:event("ADDON_ACTION_FORBIDDEN", "QuestTogether")
		end
		if options.hideParentAfterUnregister then
			options.hideParentAfterUnregister = nil
			h:parentVisibility(false, "children-first")
		end
		return true
	end
	function manager:HandlePopupHide()
		error("Use boolean-returning FrameHidden for verified popup removal")
	end
	env.GamepadSharedUtility = {
		CreatePromptedBindingFooter = function(frame)
			h.apiCounts.footers = h.apiCounts.footers + 1
			call("CreatePromptedBindingFooter", frame)
			if options.securityOnFooter then
				h.setupFailureMark = { writes = #h.calls, hides = h.hides, frames = #h.frames }
				h:event("ADDON_ACTION_FORBIDDEN", "QuestTogether")
			end
			local footer = {
				AddStandardSelectPrompt = noop,
				AddStandardBackPrompt = noop,
				Finalize = noop,
				IsBindingGroupRequired = function()
					return options.requiredFooterBindings or false
				end,
				ShowAndActivateBindings = function(self)
					assert(
						not self.bindings and not self:IsBindingGroupRequired(),
						"Visual footer attempted custom binding activation"
					)
				end,
				HideAndDeactivateBindings = function(self)
					assert(
						not self.bindings and not self:IsBindingGroupRequired(),
						"Visual footer attempted custom binding deactivation"
					)
				end,
			}
			if options.footerHasBindings then
				footer.bindings = {}
			end
			return footer
		end,
	}
	local function forbiddenMenu()
		h.apiCounts.menus = h.apiCounts.menus + 1
		error("Owned-panel fixture must not call a native Menu API")
	end
	env.MenuUtil = setmetatable({}, {
		__index = function()
			return forbiddenMenu
		end,
	})
	env.Menu = setmetatable({}, {
		__index = function()
			return forbiddenMenu
		end,
	})
	env.QuestTogether = {
		LibChev = {
			CanMutateOwnedRegion = function(frame)
				return frame and frame.owned ~= false
			end,
			WeakKeys = function()
				return {}
			end,
		},
		IsRuntimeRestricted = function()
			return h.combat
		end,
		GetOption = function()
			return options.savedEnabled
		end,
		CanAccessForeignFrame = function(_, frame)
			return frame and not frame.forbidden
		end,
		RecordDiagnosticError = function(_, category, reason)
			h.reports[#h.reports + 1] = reason
		end,
		StopWindowDrag = noop,
		SaveWindowLayout = noop,
		SafeToNumber = function(_, value)
			return tonumber(value)
		end,
	}
	function h:flush()
		local pending = self.timers
		self.timers = {}
		for _, timer in ipairs(pending) do
			self.now = math.max(self.now, timer.due)
			timer.callback()
		end
		assert(#self.timers < 10, "Unbounded callback scheduling")
	end
	function h:flushAll()
		for _ = 1, 12 do
			if #self.timers == 0 then
				return
			end
			self:flush()
		end
		error("Callback queue did not quiesce")
	end
	function h:runNextTimer()
		local timer = assert(table.remove(self.timers, 1), "No timer to run")
		self.now = math.max(self.now, timer.due)
		timer.callback()
	end
	function h:command(value)
		env.SlashCmdList.QTNATIVEGAMEPADPROBE(value)
		self:flush()
	end
	function h:event(event, ...)
		for _, frame in ipairs(self.frames) do
			if frame.events[event] then
				frame.scripts.OnEvent(frame, event, ...)
			end
		end
	end
	function h:modeOff(cleanReset)
		self.mode = false
		if cleanReset then
			-- Explicit model of native high-priority reset before normal callbacks.
			manager.members, manager.returnFrames, manager.lastButtons = {}, {}, {}
			manager.active, manager.focusedFrame, manager.isUIFocused = nil, nil, false
			nav.active, nav.button, nav.bindingActive, nav.rightStickScrolling, nav.shown =
				nil, nil, false, false, false
			local residue = self.options.modeResetResidue
			if residue == "manager" then
				manager.active = env.UIParent
			end
			if residue == "navigation" then
				nav.active = env.UIParent
			end
			if residue == "selection" then
				nav.button = env.UIParent
			end
			if residue == "binding" then
				nav.bindingActive = true
			end
			if residue == "scrolling" then
				nav.rightStickScrolling = true
			end
			if residue == "members" then
				manager.members[env.UIParent] = true
			end
		end
		for _, callbacks in pairs(self.transitions) do
			if callbacks.uninit then
				callbacks.uninit()
			end
		end
	end
	function h:modeOn()
		self.mode = true
		for _, callbacks in pairs(self.transitions) do
			if callbacks.init then
				callbacks.init()
			end
		end
	end
	function h:parentVisibility(shown, order)
		env.UIParent.shown = shown
		local function notifyParent()
			env.EventRegistry:TriggerEvent(shown and "UI.TopLevelParentShown" or "UI.TopLevelParentHidden")
		end
		local function notifyChildren()
			-- This deliberately supplies both possible observer orders. It models
			-- inherited visibility notification, not engine/native OnHide behavior.
			for _, frame in ipairs(self.frames) do
				if
					frame.parent == env.UIParent
					and frame.name
					and frame.name:find("Adapter", 1, true)
					and frame.shown
				then
					local event = shown and "OnShow" or "OnHide"
					if frame.scripts[event] then
						frame.scripts[event](frame)
					end
					for _, hook in ipairs(frame.hooks[event] or {}) do
						hook(frame)
					end
				end
			end
		end
		if order == "children-first" then
			notifyChildren()
			notifyParent()
		else
			notifyParent()
			notifyChildren()
		end
	end
	function h:button(text)
		for _, frame in ipairs(self.frames) do
			if frame.kind == "Button" and frame.text == text then
				return frame
			end
		end
		error("Missing owned button: " .. text)
	end
	function h:click(text)
		self.now = self.now + 1
		local button = self:button(text)
		assert(button:IsVisible(), "Attempted normal click on hidden button: " .. text)
		self.nav.button = button
		button:Click()
		self:flushAll()
		return button
	end
	function h:count(key)
		return (env.QuestTogetherNativeGamepadProbeDB.counts or {})[key] or 0
	end
	function h:report()
		return env.QuestTogetherNativeGamepadProbe:BuildReport()
	end
	function h:load(path)
		path = path or fixture
		local chunk, message
		if _VERSION == "Lua 5.1" then
			chunk, message = loadfile(path)
			assert(chunk, message)
			setfenv(chunk, env)
		else
			chunk, message = loadfile(path, "t", env)
			assert(chunk, message)
		end
		chunk()
	end
	h.env = env
	h:load("OwnedUI.lua")
	h:load("WindowController.lua")
	h:load()
	h.qt = env.QuestTogether
	h.qt:InitializeGamepadIntegration()
	h:flushAll()
	return h
end

local function panel(h, role, parent, policy)
	local frame = h.env.CreateFrame("Frame", "Adapter" .. role, h.env.UIParent)
	frame:Hide()
	local button = h.env.CreateFrame("Button", nil, frame)
	local settings = { role = role, kind = parent and "popup" or "window", defaultFocus = button }
	for key, value in pairs(policy or {}) do
		settings[key] = value
	end
	h.qt:ConfigureWindowController(frame, { gamepad = settings })
	frame:Show()
	return frame, button
end
local function present(h, frame, parent)
	assert(h.qt:PresentGamepadWindow(frame, { userInitiated = true, parent = parent }), "Presentation failed")
	assert(h.qt:IsGamepadActionCurrent(frame), "Presentation not current")
end
local function failed(h, frames)
	assert(h.qt:GetGamepadIntegrationStatus().failed, "Missing failure latch")
	local calls, hides = #h.calls, h.hides
	for _, frame in ipairs(frames or {}) do
		frame:Hide()
		h.qt:HideOwnedUI(frame)
		h.qt:SuspendGamepadWindow(frame, "test")
		h.qt:PresentGamepadWindow(frame, "user")
		h.qt:RefreshGamepadNavigation(frame)
	end
	h.qt:SetGamepadIntegrationEnabled(false)
	h.qt:InitializeGamepadIntegration()
	h:flushAll()
	assert(#h.calls == calls and h.hides == hides, "Failure allowed later native writes or owned hiding")
end

-- Add explicit helper feature doubles. No fallback noop may satisfy capability.
-- The source requires only read-only checks of these methods, never invocation.
local rawHarness = newHarness
newHarness = function(options)
	local h = rawHarness(options)
	local function forbiddenHelperCall()
		error("Adapter directly invoked secure helper")
	end
	for _, name in ipairs({
		"WrapFunction",
		"SetSecureValue",
		"SecureCallOptionalFunction",
		"IsSecureOrOutOfCombatRestriction",
	}) do
		h.env.SmartNavigationSecureHelper[name] = forbiddenHelperCall
	end
	if options and options.missingNativeMethod then h.nav.GetCurrentButton = nil end
	if options and options.insecureNativeWrapper then
		h.env.issecurevariable = function(_, name) return name ~= "FrameHidden" end
	end
	h.qt:InitializeGamepadIntegration()
	h:flushAll()
	local expectedAvailable = not options or ((not options.version or options.version == "1.60.1")
		and (not options.build or tostring(options.build) == "70888" or tostring(options.build) == "70938")
		and not options.missingNativeMethod and not options.insecureNativeWrapper)
	assert(
		h.qt:GetGamepadIntegrationStatus().available
			== expectedAvailable,
		"Explicit native contract availability mismatch"
	)
	return h
end

do
	local h = newHarness()
	local root, first = panel(h, "Root")
	local writes = #h.calls
	assert(not h.qt:PresentGamepadWindow(root, { userInitiated = false }))
	assert(not h.qt:PresentGamepadWindow(root, "automatic"))
	assert(#h.calls == writes, "Automatic presentation registered")
	present(h, root)
	local popup, cancel = panel(h, "Popup", root)
	present(h, popup, root)
	assert(h.nav.button == cancel)
	assert(h.qt:HideOwnedUI(popup))
	assert(not popup:IsShown() and h.nav.active == root and h.nav.button == first)
	root:Hide() -- Raw library close must pass through the owned interception.
	assert(not root:IsShown() and h.manager:GetShownFrameCount() == 0 and h.nav.active == nil)
	assert(not h.qt:GetGamepadIntegrationStatus().failed)
	root:Show()
	present(h, root)
	local count = #h.calls
	h.qt:InitializeGamepadIntegration()
	h:flushAll()
	assert(#h.calls == count, "Repeated init wrote native state")
	print(
		"PASS: explicit registration, default cancel, popup return, raw owned Hide interception, initialization idempotence"
	)
end

do
	local h = newHarness()
	local root = panel(h, "Root")
	present(h, root)
	local child = panel(h, "Child", root)
	present(h, child, root)
	local confirm = panel(h, "Confirm", child)
	present(h, confirm, child)
	local writes, hides = #h.calls, h.hides
	h:parentVisibility(false, "children-first")
	h:flushAll()
	assert(#h.calls == writes and h.hides == hides, "Ancestor hide initiated cleanup")
	h:parentVisibility(true)
	h:flushAll()
	assert(not root:IsShown() and not child:IsShown() and not confirm:IsShown())
	assert(
		h.nav.active == nil and h.manager:GetShownFrameCount() == 0 and not h.qt:GetGamepadIntegrationStatus().failed
	)
	print("PASS: inherited hide waits for visibility, retires descendants before parent, and never re-registers")
end

do
	local h = newHarness()
	local root = panel(h, "Root")
	present(h, root)
	local completions = 0
	h.qt:ConfigureWindowController(root, {
		dismiss = function()
			completions = completions + 1
			root:Show()
			assert(h.qt:PresentGamepadWindow(root, "user"))
		end,
	})
	h.combat = true
	local writes = #h.calls
	h.qt:DismissManagedWindow(root, "replace")
	h:flushAll()
	assert(completions == 0 and #h.calls == writes and root:IsShown())
	h.combat = false
	h:event("PLAYER_REGEN_ENABLED")
	h:flushAll()
	assert(
		completions == 1 and root:IsShown() and h.qt:IsGamepadActionCurrent(root),
		"Replacement presentation was retired"
	)
	print("PASS: combat retirement defers dismissal callback and preserves same-frame replacement")
end

do
	local h = newHarness()
	local root = panel(h, "Root")
	present(h, root)
	h:modeOff(true)
	h:flushAll()
	assert(not root:IsShown() and not h.qt:GetGamepadIntegrationStatus().failed)
	local writes = #h.calls
	h:modeOn()
	h:flushAll()
	assert(not root:IsShown() and #h.calls == writes, "Mode restoration automatically reopened")
	local h2 = newHarness({ modeResetResidue = "binding" })
	local bad = panel(h2, "Root")
	present(h2, bad)
	h2:modeOff(true)
	failed(h2, { bad })
	print("PASS: high-priority native mode reset is verified; restoration stays manual; incomplete reset stops")
end

for _, option in ipairs({ "failAfterInsert", "navMismatch", "rejectRegister", "rejectTarget", "securityOnRegister" }) do
	local opts = { [option] = true }
	local h = newHarness(opts)
	local root = panel(h, "Root")
	assert(not h.qt:PresentGamepadWindow(root, "user"), option)
	failed(h, { root })
end
for _, option in ipairs({ "failUnregister", "rejectUnregister", "retainDetachedFocus", "securityOnUnregister" }) do
	local h = newHarness()
	local root = panel(h, "Root")
	present(h, root)
	h.options[option] = true
	h.qt:HideOwnedUI(root)
	failed(h, { root })
end
print(
	"PASS: partial registration, focus split, ignored target, cleanup faults and synchronous security events stop all subsequent writes/hides"
)

do
	local h = newHarness()
	local root = panel(h, "Root")
	present(h, root)
	root:Hide()
	h:event("ADDON_ACTION_FORBIDDEN", "QuestTogether")
	failed(h, { root })
	local h2 = newHarness()
	local passive = panel(h2, "Passive")
	local fake = setmetatable({}, { __index = h2.qt })
	local writes = #h2.calls
	assert(not fake:IsNativeGamepadMode())
	assert(not fake:ConfigureGamepadWindow(passive, {}))
	assert(not fake:PresentGamepadWindow(passive, "user"))
	assert(not fake:MarkGamepadContainer(passive))
	assert(not fake:InitializeGamepadIntegration())
	assert(#h2.calls == writes, "In-game test receiver reached real native state")
	h2.qt.isRunningTests = true
	assert(not h2.qt:IsNativeGamepadMode())
	assert(not h2.qt:ConfigureGamepadWindow(passive, {}))
	assert(not h2.qt:PresentGamepadWindow(passive, "user"))
	assert(not h2.qt:InitializeGamepadIntegration())
	assert(#h2.calls == writes, "Synchronous live-test singleton reached native state")
	h2.qt.isRunningTests = nil
	print(
		"PASS: late errors remain observed; inherited fixtures and synchronous live-test singleton cannot reach native integration"
	)
end

do
	local h = newHarness()
	local root = panel(h, "Root")
	present(h, root)
	local seen
	h.qt:RegisterGamepadObserver({}, function(snapshot)
		seen = snapshot
	end)
	assert(seen.uiFocused and seen.frame == root)
	h.manager.isUIFocused = false
	h.env.EventRegistry:TriggerEvent("Gamepad.RefreshFrameFocus")
	assert(not seen.uiFocused and not seen.manager and not seen.button)
	local manager, active, button = h.qt:GetNativeGamepadFocus()
	assert(manager == nil and active == nil and button == nil)
	h.manager.isUIFocused = true
	h.nav.shown = false
	h.env.EventRegistry:TriggerEvent("Gamepad.RefreshFrameFocus")
	assert(
		seen.uiFocused and seen.manager == root and not seen.frame and not seen.button,
		"Custom native focus was lost"
	)
	print("PASS: read-only observers distinguish world focus from native custom-panel focus")
end
do
	local h = newHarness({ savedEnabled = false })
	local frame = h.env.CreateFrame("Frame", "AdapterDisabled", h.env.UIParent)
	local original = frame.Hide
	h.qt:ConfigureGamepadWindow(frame, { role = "disabled" })
	assert(frame.Hide == original and not frame.SmartNavigationCloseHandler)
	local writes = #h.calls
	assert(not h.qt:PresentGamepadWindow(frame, "user"))
	assert(#h.calls == writes and h.qt:GetGamepadIntegrationStatus().enabled == false)
	for _, client in ipairs({ { "1.60.1", "99999" }, { "1.60.2", "99999" }, { "1.60.1", "70939" } }) do
		local unsupported = newHarness({ version = client[1], build = client[2] })
		local status = unsupported.qt:GetGamepadIntegrationStatus()
		assert(status.clientVersion == client[1] and status.clientBuild == client[2])
		assert(not status.supportedBuild and status.unavailableReason == "unsupported_build")
		assert(not status.failed and not status.reloadRequired and status.registered == 0)
		local before = #unsupported.frames
		unsupported.qt:InitializeGamepadIntegration()
		assert(#unsupported.frames == before and unsupported.apiCounts.registrations == 0)
		local f = unsupported.env.CreateFrame("Frame", "AdapterUnsupported", unsupported.env.UIParent)
		local hide = f.Hide
		unsupported.qt:ConfigureGamepadWindow(f, { role = "unsupported" })
		assert(f.Hide == hide and not f.SmartNavigationCloseHandler)
		assert(not unsupported.qt:PresentGamepadWindow(f, "user") and #unsupported.calls == 0)
	end
	print(
		"PASS: saved disable is respected at initialization; unsupported builds install no hooks/listeners/native calls"
	)
end

do
	for _, build in ipairs({ "70888", "70938" }) do
		local supported = newHarness({ build = build })
		local ready = supported.qt:GetGamepadIntegrationStatus()
		assert(ready.clientVersion == "1.60.1" and ready.clientBuild == build and ready.supportedBuild)
		assert(ready.available and ready.unavailableReason == "none")
		local frame = panel(supported, "SupportedBuild")
		present(supported, frame)
		assert(supported.qt:HideOwnedUI(frame) and not frame:IsShown())
		for option, reason in pairs({ missingNativeMethod = "native_missing_functions",
			insecureNativeWrapper = "native_security_wrapper_unavailable" }) do
			local h = newHarness({ build = build, [option] = true })
			local status = h.qt:GetGamepadIntegrationStatus()
			assert(status.clientVersion == "1.60.1" and status.clientBuild == build and status.supportedBuild)
			assert(not status.available and status.unavailableReason == reason, option)
			assert(not status.failed and not status.reloadRequired and status.registered == 0)
			assert(#h.calls == 0 and h.apiCounts.registrations == 0 and h.apiCounts.footers == 0)
		end
	end
	local h = newHarness({ version = string.rep("9", 4096) })
	local status = h.qt:GetGamepadIntegrationStatus()
	assert(status.clientVersion == "unknown" and status.unavailableReason == "unsupported_build")
	assert(#h.calls == 0 and h.apiCounts.registrations == 0)
	print("PASS: bounded gamepad availability diagnostics distinguish build, missing APIs and insecure wrappers without native writes")
end

do
	local h = newHarness()
	local root = panel(h, "Root")
	present(h, root)
	local child = panel(h, "Child", root)
	present(h, child, root)
	h.options.hideParentAfterUnregister = true
	local writes, hides = #h.calls, h.hides
	h.qt:HideOwnedUI(child)
	assert(#h.calls == writes + 1 and h.hides == hides)
	h:parentVisibility(true)
	h:flushAll()
	assert(not root:IsShown() and not child:IsShown() and not h.qt:GetGamepadIntegrationStatus().failed)
	local after = #h.calls
	h:flushAll()
	assert(#h.calls == after, "Retried a completed native unregister")
	print("PASS: visibility loss during unregister pauses own Hide and does not repeat native detach")
end
do
	local h = newHarness()
	local root = panel(h, "Root")
	present(h, root)
	local child = panel(h, "Child", root)
	present(h, child, root)
	local dismisses = 0
	h.qt:ConfigureWindowController(child, {
		dismiss = function()
			dismisses = dismisses + 1
			h.qt:DismissManagedWindow(root)
		end,
	})
	child:Hide()
	assert(dismisses == 1 and not root:IsShown() and not child:IsShown())
	local removed = 0
	for _, call in ipairs(h.calls) do
		if call == "FrameHidden" then
			removed = removed + 1
		end
	end
	assert(removed == 2 and not h.qt:GetGamepadIntegrationStatus().failed)
	print("PASS: dismissal during owned Hide queues parent retirement without recursive duplicate detachment")
end
do
	local h = newHarness()
	local root, safe = panel(h, "Root")
	present(h, root)
	local container = h.env.CreateFrame("Frame", nil, root)
	local selected = h.env.CreateFrame("Button", nil, container)
	assert(h.qt:RefreshGamepadNavigation(root, selected))
	assert(not pcall(container.Hide, container), "Offline anchor trap did not detect unsafe child hide")
	assert(not h.qt:PrepareGamepadControlHide(root, selected), "Fallback inside hidden subtree was accepted")
	assert(h.qt:PrepareGamepadControlHide(container, safe))
	assert(h.nav.button == safe and h.nav.anchor == safe)
	container:Hide()
	local native = h.env.CreateFrame("Frame", nil, h.env.UIParent)
	native.owned = false
	local target = h.env.CreateFrame("Button", nil, native)
	local replacement = h.env.CreateFrame("Button", nil, native)
	h.manager:FrameShown(native)
	h.nav:SetTargetButtonForFrame(native, target)
	local writes = #h.calls
	assert(not h.qt:PrepareGamepadControlHide(target))
	assert(#h.calls == writes)
	assert(h.qt:PrepareGamepadControlHide(target, replacement))
	assert(h.nav.active == native and h.nav.button == replacement)
	target:Hide()
	local unused = h.env.CreateFrame("Button", nil, native)
	writes = #h.calls
	assert(h.qt:PrepareGamepadControlHide(unused) and #h.calls == writes)
	local u = newHarness({ version = "1.60.2" })
	local mouse = panel(u, "Mouse")
	local child = u.env.CreateFrame("Button", nil, mouse)
	assert(u.qt:PrepareGamepadControlHide(child) and #u.calls == 0)
	print(
		"PASS: child-hide seam parks synchronously, rejects unsafe fallback, handles existing foreign panel, and leaves unrelated/mouse-only controls inert"
	)
end
do
	local h = newHarness()
	local root, selected = panel(h, "HideVisibility")
	present(h, root)
	-- Native map canvas focus hides the cursor with SelectButton(nil), without
	-- hiding SmartNavigation or necessarily clearing its previous anchor.
	h.nav.button = nil
	local writes = #h.calls
	assert(not h.qt:PrepareGamepadControlHide(selected), "Visible old cursor anchor accepted with nil selection")
	assert(#h.calls == writes)
	assert(h.qt:HideOwnedUI(root))
	h.nav.shown, h.nav.button, h.nav.anchor = true, nil, selected
	writes = #h.calls
	assert(h.qt:PrepareGamepadControlHide(selected), "Previously registered invisible subtree rejected")
	selected:Hide()
	assert(#h.calls == writes, "Invisible child hide mutated native focus")
	local hidden = h.env.CreateFrame("Frame", nil, h.env.UIParent)
	hidden:Hide()
	local fresh = h.env.CreateFrame("Button", nil, hidden)
	assert(h.qt:PrepareGamepadControlHide(fresh), "Fresh invisible child rejected")
	fresh:Hide()
	assert(#h.calls == writes)
	for _, getter in ipairs({
		function() error("Unavailable visibility") end,
		function() return nil end,
		function() return "false" end,
	}) do
		fresh.IsVisible = getter
		assert(not h.qt:PrepareGamepadControlHide(fresh), "Unproven hidden state accepted")
	end
	fresh.IsVisible = function() return false end
	h.env.canaccessvalue = function(value) return value ~= false end
	assert(not h.qt:PrepareGamepadControlHide(fresh), "Inaccessible hidden state accepted")
	h.env.canaccessvalue = function() return true end
	h.combat = true
	assert(not h.qt:PrepareGamepadControlHide(fresh), "Invisible control bypassed restrictions")
	h.combat = false
	fresh.owned = false
	assert(not h.qt:PrepareGamepadControlHide(fresh), "Invisible foreign control accepted")
	assert(#h.calls == writes)
	print("PASS: proven invisible children are safe while nil selection, unknown visibility, foreign ownership and restrictions remain guarded")
end
do
	-- Run the real action renderer, managed-window lifecycle and native adapter
	-- together. Renderer-only fixtures stubbed the hide guard and missed this seam.
	local h = newHarness()
	local a, env = h.qt, h.env
	a.Translate = function(text) return text end
	a.db = { profile = {} }
	function a:IsWorkBlocked() return h.combat end
	function a:GetOption(key) if key == "windowScale" then return 100 end end
	function a:GetAccessibleFrameMember(frame, key) return frame and frame[key] end
	function a:CanAccessTable(value) return type(value) == "table" end
	function a:CanAccessValue() return true end
	function a:Debug(text) error(text) end
	function a:RecordTestModule() end
	env.UIParent.children = {}
	function env.UIParent:GetWidth() return 1280 end
	function env.UIParent:GetHeight() return 900 end
	function env.UIParent:GetEffectiveScale() return 1 end
	h:load("scripts/ui_fixture.lua")
	local frameOwner = {}
	function a:CreateOwnedWindowFrame(kind, name, parent)
		local frame = self:CreateTestUIRegion(frameOwner, parent, kind)
		frame.name = name
		function frame:IsEnabled() return self.enabled ~= false end
		-- Retain the adapter harness's native-anchor trap on effective hiding.
		local hide = frame.Hide
		function frame:Hide()
			if self:IsVisible() then
				assert(not h.manager.members[self], "Menu Hide preceded native unregister")
				local anchor = h.nav:IsShown() and h.nav.anchor
				while anchor do
					assert(anchor ~= self, "Menu subtree hid the native cursor anchor")
					anchor = anchor.parent
				end
			end
			hide(self)
		end
		return frame
	end
	h:load("WindowTheme.lua")
	h:load("WindowLayout.lua")
	h:load("GamepadActions.lua")
	local map = env.CreateFrame("Frame", nil, env.UIParent)
	map.owned, map.children = false, {}
	local mapControl = env.CreateFrame("Button", nil, map)
	mapControl.owned = false
	function map:FocusGamepad()
		-- Native HandlePanelOpen first selects an eligible map control before
		-- invoking FocusGamepad. Include its anchor change in this panel double.
		h.nav.anchor = mapControl
		-- Match WorldMapMixin:FocusMap -> HideCursor's nil selection while the
		-- native navigation region remains shown (its alpha, not visibility, changes).
		h.nav.button, h.nav.bindingActive = nil, false
	end
	h.manager:FrameShown(map)
	local pin = a:CreateOwnedWindowFrame("Button", nil, map)
	local activated = 0
	local function Generate(_, root)
		for index = 1, 40 do
			root:CreateButton("Member action " .. index, function() activated = activated + 1 end)
		end
	end
	for attempt = 1, 2 do
		assert(h.nav:IsShown() and h.nav:IsVisible() and h.nav.button == nil)
		assert(a:ShowGamepadContextMenu(pin, Generate, function() return true end), "Map menu rejected on attempt " .. attempt)
		h:flushAll()
		local menu = a.gamepadActions.frames[1]
		assert(a:IsGamepadActionCurrent(menu) and h.nav.button == menu.back)
		assert(#menu.actionPages > 1 and menu.previous:IsVisible() and menu.next:IsVisible())
		h.nav:SetTargetButtonForFrame(menu, menu.next)
		menu.next:Click()
		assert(menu.page == 2 and h.nav.button == menu.back, "Pagination failed to reanchor a visible selected footer")
		h.nav:SetTargetButtonForFrame(menu, menu.previous)
		menu.previous:Click()
		assert(menu.page == 1 and h.nav.button == menu.back)
		menu.back:Click()
		h:flushAll()
		assert(not a.gamepadActions and not menu:IsShown() and not a:IsGamepadWindowRegistered(menu),
			"Menu close: state=" .. tostring(a.gamepadActions ~= nil) .. " shown=" .. tostring(menu:IsShown())
				.. " registered=" .. tostring(a:IsGamepadWindowRegistered(menu)) .. " failure=" .. tostring(a:GetGamepadIntegrationStatus().failure))
		assert(h.manager.active == map and h.nav.active == map and h.nav.button == nil, "Menu Back did not restore map canvas")
		assert(not a:GetGamepadIntegrationStatus().failed and activated == 0 and #h.reports == 0)
	end
	assert(#a.gamepadActionFrames == 1 and h.apiCounts.menus == 0 and h.apiCounts.dropdowns == 0)
	print("PASS: actual owned action menus open, paginate, return to map canvas and reopen with the real adapter")
end
for _, option in ipairs({ "failTransitions", "securityOnTransitions" }) do
	local h = newHarness({ [option] = true })
	assert(h.qt:GetGamepadIntegrationStatus().failed, "Partial observer registration was not latched")
	local registrations = h.apiCounts.registrations
	h.qt:InitializeGamepadIntegration()
	h:event("ADDON_LOADED")
	h:flushAll()
	assert(h.apiCounts.registrations == registrations and #h.calls == 0, "Partial observer registration was retried")
end
print(
	"PASS: thrown and synchronous security failures during observer registration stop subsequent attachment and retries"
)
do
	local h = newHarness()
	local root = panel(h, "ObserverRoot", nil, {
		onSelection = function()
			assert(not h.qt:GetGamepadIntegrationStatus().failed, "Selection callback continued after observer failure")
		end,
	})
	present(h, root)
	local seen, badCalls = {}, 0
	assert(h.qt:RegisterGamepadObserver({}, function(snapshot)
		seen[#seen + 1] = snapshot.available
		if #seen > 1 and seen[#seen - 1] == false then
			assert(snapshot.available == false, "Stale available snapshot followed failure")
		end
	end))
	assert(not h.qt:RegisterGamepadObserver({}, function()
		badCalls = badCalls + 1
		error("Injected observer failure")
	end))
	local status = h.qt:GetGamepadIntegrationStatus()
	assert(status.failed and status.failure == "observer_callback" and status.reloadRequired)
	assert(badCalls == 1 and seen[#seen] == false and #h.reports == 1)
	h.env.EventRegistry:TriggerEvent("Gamepad.RefreshFrameFocus")
	assert(badCalls == 1 and #h.reports == 1, "Failing observer survived or failure recurred")
	assert(not h.qt:RegisterGamepadObserver({}, function()
		error("Failure-state observer error")
	end))
	assert(#h.reports == 1, "Failure notification recursively latched another error")
	failed(h, { root })
	print(
		"PASS: observer exception removes subscriber, latches one bounded failure, publishes unavailable state and stops later native writes/hides"
	)
end
do
	local h = newHarness()
	local attempts, pending = 0, true
	function h.qt:IsDefaultGamepadLauncherPending() return pending end
	function h.qt:TryInstallDefaultGamepadLauncher() attempts = attempts + 1 end
	h:event("UPDATE_MACROS")
	h:event("ACTIONBAR_SLOT_CHANGED")
	h:flushAll()
	assert(attempts == 0, "Launcher ran before entering the world")
	h:event("PLAYER_ENTERING_WORLD")
	h:event("UPDATE_MACROS")
	h:event("CURSOR_CHANGED")
	h:flushAll()
	assert(attempts == 1, "World entry and native data events were not coalesced")
	h.combat = true
	h:event("CURSOR_CHANGED")
	h:flushAll()
	assert(attempts == 1, "Launcher ran during combat")
	h.combat = false
	h:event("PLAYER_REGEN_ENABLED")
	h:flushAll()
	assert(attempts == 2)
	h:event("PLAYER_ENTERING_WORLD")
	h:event("PLAYER_LEAVING_WORLD")
	h:flushAll()
	assert(attempts == 2, "Queued launcher work survived world departure")
	h:event("PLAYER_ENTERING_WORLD")
	h.qt:SetGamepadIntegrationEnabled(false)
	h:flushAll()
	assert(attempts == 2, "Queued launcher work ignored navigation disable")
	h.qt:SetGamepadIntegrationEnabled(true)
	h:event("CURSOR_CHANGED")
	h:flushAll()
	assert(attempts == 3)
	pending = false
	h:event("CURSOR_CHANGED")
	h:event("UPDATE_MACROS")
	h:event("ACTIONBAR_SLOT_CHANGED")
	assert(#h.timers == 0, "Completed launcher kept scheduling native work")
	local macroChecks, slotChecks, waitingSlot = 0, 0, false
	function h.qt:OnGamepadLauncherMacroUpdate() macroChecks = macroChecks + 1; pending = true end
	function h.qt:OnGamepadLauncherSlotUpdate() slotChecks = slotChecks + 1; if waitingSlot then pending = true end end
	h:event("ACTIONBAR_SLOT_CHANGED"); h:flushAll()
	assert(attempts == 3 and slotChecks == 1, "Unbinding a surviving macro scheduled placement")
	h:event("UPDATE_MACROS"); h:event("UPDATE_MACROS"); h:flushAll()
	assert(macroChecks == 2 and attempts == 4, "Macro deletion did not coalesce into one check")
	pending, waitingSlot = false, true
	h:event("ACTIONBAR_SLOT_CHANGED"); h:flushAll()
	assert(attempts == 5 and slotChecks == 2, "An emptied slot did not resume missing-macro setup")
	print("PASS: default launcher waits for world entry, coalesces native events, defers combat, cancels on departure/disable and becomes idle")
end

do
	local h = newHarness()
	h:load("GamepadWindows.lua")
	local frame = h.env.CreateFrame("Frame", "AdapterNotes", h.env.UIParent)
	frame.close = h.env.CreateFrame("Button", nil, frame)
	frame.scroll = h.env.CreateFrame("ScrollFrame", nil, frame)
	assert(h.qt:PresentStandardGamepadWindow(frame, "release_notes", nil, frame.close, frame.scroll, "automatic"))
	assert(h.nav.button == frame.close and frame.scrollTarget == frame.scroll and h.nav.rightStickScrolling,
		"Full-content window did not enable native right-stick scrolling")
	local popup = panel(h, "NotesPopup", frame)
	present(h, popup, frame)
	assert(not h.nav.rightStickScrolling, "Notes scrolling leaked into a popup")
	popup:Hide()
	assert(h.nav.active == frame and h.nav.rightStickScrolling, "Returning to notes lost scrolling")
	frame:SmartNavigationCloseHandler()
	h:flushAll()
	assert(not frame:IsShown() and not h.nav.rightStickScrolling and not h.nav.bindingActive,
		"Back left the notes window or its input active")
	assert(not h.qt:GetGamepadIntegrationStatus().failed)
	assert(h.qt:PresentStandardGamepadWindow(frame, "release_notes", nil, frame.close, frame.scroll, "automatic") == false,
		"Automatic focus resurrected closed notes")
	frame:Show()
	assert(h.qt:PresentStandardGamepadWindow(frame, "release_notes", nil, frame.close, frame.scroll))
	frame:Hide()
	local other = h.env.CreateFrame("Frame", "AdapterOther", h.env.UIParent)
	assert(not h.qt:PresentStandardGamepadWindow(other, "notes", nil, nil, nil, "automatic"),
		"Automatic focus escaped patch-notes policy")
	print("PASS: automatic patch notes opt in to focus/scrolling, return from popups and release input on Back; other windows stay passive")
end
print("OFFLINE ONLY: no WoW taint, protected API, physical input, cursor geometry or production live proof")
