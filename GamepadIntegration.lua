-- Native Forever navigation, using the audited 70888/70938 wrappers. QT owns every
-- configured frame; native focus/binding tables and cursor anchors stay native.
local QT = _G.QuestTogether
local records, observers, owner = {}, {}, {}
local state = { generation = 0, order = {}, events = {} }
local Reconcile, Schedule, Notify, Retire

local function Accessible(value)
	return not (issecretvalue and issecretvalue(value)) and (not canaccessvalue or canaccessvalue(value))
end
local function Methods(object, names)
	if not object or not Accessible(object) then
		return false
	end
	for _, name in ipairs(names) do
		if type(object[name]) ~= "function" then
			return false
		end
	end
	return true
end
local function Manager()
	return GamepadMode and GamepadMode.FrameControlsManager
end
local function BuildDiagnostic(value)
	if not Accessible(value) then return "unknown" end
	if type(value) == "number" then
		if value ~= value or value < 0 or value > 999999999999 then return "unknown" end
		value = tostring(value)
	end
	if type(value) ~= "string" or #value > 32 or not value:match("^%d[%d%.]*$") then return "unknown" end
	return value
end
local function SupportedBuild()
	if state.supportedBuild ~= nil then
		return state.supportedBuild
	end
	if type(GetBuildInfo) ~= "function" then
		return false
	end
	local ok, version, build = pcall(GetBuildInfo)
	if not ok then return false end
	state.clientVersion, state.clientBuild = BuildDiagnostic(version), BuildDiagnostic(build)
	state.supportedBuild = Accessible(version)
		and Accessible(build)
		and version == "1.60.1"
		and (tostring(build) == "70888" or tostring(build) == "70938")
	return state.supportedBuild
end
local function AuthoredGeneration()
	if not SupportedBuild() then
		return false, "unsupported_build"
	end
	if
		not Methods(
			SmartNavigationSecureHelper,
			{ "WrapFunction", "SetSecureValue", "SecureCallOptionalFunction", "IsSecureOrOutOfCombatRestriction" }
		)
	then
		return false, "native_missing_functions"
	end
	-- No public generation constant exists in this source. The audited build,
	-- helper feature set and secure entrypoints together bound support. Never
	-- call WrapFunction/SetSecureValue or write the helper's attributes ourselves.
	if type(issecurevariable) ~= "function" then
		return false, "native_security_wrapper_unavailable"
	end
	for _, spec in ipairs({
		{ Manager(), "FrameShown", "FrameHidden", "HandlePopupShown" },
		{ SmartNavigation, "SetTargetButtonForFrame", "SetScrollFrameForFrame", "RefreshButtonGroups" },
	}) do
		if not spec[1] or not Accessible(spec[1]) then
			return false, "native_missing_functions"
		end
		for i = 2, #spec do
			local ok, secure = pcall(issecurevariable, spec[1], spec[i])
			if not ok or not Accessible(secure) or secure ~= true then
				return false, "native_security_wrapper_unavailable"
			end
		end
	end
	return true
end
local function Capable()
	if state.capable then
		return true
	end
	local authored, reason = AuthoredGeneration()
	state.capable = authored
		and Methods(
			Manager(),
			{ "FrameShown", "FrameHidden", "HandlePopupShown", "GetActiveFrame", "GetShownFrameCount" }
		)
		and Methods(SmartNavigation, {
			"SetTargetButtonForFrame",
			"SetScrollFrameForFrame",
			"RefreshButtonGroups",
			"GetActiveFrame",
			"GetCurrentButton",
			"IsShown",
			"IsVisible",
			"RegisterCallback",
		})
		and Methods(UIParent, { "IsShown", "IsVisible" })
		and Methods(
			InputUtil,
			{ "IsGamepadUIEnabled", "RegisterForInterfaceTransitions", "RegisterGamepadUninit", "RegisterGamepadInit" }
		)
		and Methods(C_Timer, { "After" })
		and Methods(EventRegistry, { "RegisterCallback" })
		and Methods(C_RestrictedActions, { "IsAddOnRestrictionActive" })
		and Enum
		and Enum.AddOnRestrictionType
		and Enum.AddOnRestrictionType.Combat
		and Methods(GamepadSharedUtility, { "CreatePromptedBindingFooter" })
		and Methods(PromptedBindingFooterMixin, {
			"AddStandardSelectPrompt",
			"AddStandardBackPrompt",
			"Finalize",
			"IsBindingGroupRequired",
			"ShowAndActivateBindings",
			"HideAndDeactivateBindings",
		})
		and type(SmartNavigation_MarkFrameIgnoredContainerFrame) == "function"
		and type(SmartNavigation_MarkFrameIgnored) == "function"
		and type(SmartNavigation_ClearIgnoreStatus) == "function"
		and type(SmartNavigation_AddJumpNavigationOverride) == "function"
		and SMART_NAV_INPUT_DIRECTION
		and Accessible(SMART_NAV_INPUT_DIRECTION)
	if state.capable then
		for _, name in ipairs({ "UP", "DOWN", "LEFT", "RIGHT" }) do
			local direction = SMART_NAV_INPUT_DIRECTION[name]
			if not Accessible(direction) or type(direction) ~= "table" or direction.dirKey ~= name:lower() then
				state.capable = false
				break
			end
		end
	end
	if state.capable then state.unavailableReason = nil
	else state.unavailableReason = reason or "native_missing_functions" end
	return state.capable
end
local function Restricted()
	return QT:IsRuntimeRestricted()
		or (InCombatLockdown and InCombatLockdown())
		or (
			C_RestrictedActions
			and Enum
			and Enum.AddOnRestrictionType
			and C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)
		)
end
local function Owned(frame)
	return frame and QT.LibChev.CanMutateOwnedRegion(frame)
end
local function Visible()
	return UIParent:IsShown() and UIParent:IsVisible()
end
local function AncestorsVisible(record)
	if not Visible() then
		return false
	end
	local parent = record.frame:GetParent()
	if not parent then
		return true
	end
	return Accessible(parent)
		and (not QT.CanAccessForeignFrame or QT:CanAccessForeignFrame(parent))
		and parent:IsShown()
		and parent:IsVisible()
end
local function Log(event, role)
	state.events[#state.events + 1] = { event = event, role = role or "", generation = state.generation }
	if #state.events > 64 then
		table.remove(state.events, 1)
	end
end
local function Fail(reason)
	if state.failed then
		return
	end
	state.failed, state.failure, state.reloadRequired = true, reason, true
	state.generation, state.scheduled = state.generation + 1, nil
	Log("stopped", reason)
	if QT.RecordDiagnosticError then
		QT:RecordDiagnosticError("native_gamepad", reason .. "; reload required")
	end
	if Notify then
		Notify()
	end
end
local function Native(method, target, ...)
	if state.failed or Restricted() then
		return false
	end
	if not AuthoredGeneration() then
		Fail("native_entrypoint_unavailable")
		return false
	end
	state.monitoring = true
	local ok, result = pcall(target[method], target, ...)
	if not ok then
		Fail(method)
		return false
	end
	if state.failed then
		return false
	end
	return true, result
end
local function Call(callback, ...)
	if type(callback) ~= "function" then
		return true
	end
	local ok = pcall(callback, ...)
	if not ok then
		Fail("owned_callback")
	end
	return ok and not state.failed
end

-- This remains independent of the QT setting/capability latch so controller
-- callers never fall back to a native context menu after integration stops.
function QT:IsNativeGamepadMode()
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	if not Methods(InputUtil, { "IsGamepadUIEnabled" }) then
		return false
	end
	local ok, enabled = pcall(InputUtil.IsGamepadUIEnabled)
	return ok and Accessible(enabled) and enabled == true
end
QT.GetNativeGamepadMode = QT.IsNativeGamepadMode

local function ReadFrame(frame)
	if not Accessible(frame) or not frame then
		return nil
	end
	if QT.CanAccessForeignFrame and not QT:CanAccessForeignFrame(frame) then
		return nil
	end
	return frame
end
function QT:GetNativeGamepadFocus()
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return nil, nil, nil
	end
	if not Capable() or Restricted() or not self:IsNativeGamepadMode() then
		return nil, nil, nil
	end
	local focused = Manager().isUIFocused
	if not Accessible(focused) or focused ~= true then
		return nil, nil, nil
	end
	local manager = ReadFrame(Manager():GetActiveFrame())
	if not SmartNavigation:IsShown() or not SmartNavigation:IsVisible() then
		return manager, nil, nil
	end
	return manager, ReadFrame(SmartNavigation:GetActiveFrame()), ReadFrame(SmartNavigation:GetCurrentButton())
end
local function Snapshot()
	local available = not state.failed
		and state.enabled
		and Capable()
		and not Restricted()
		and QT:IsNativeGamepadMode()
		and Visible()
	if not available then
		return { available = false, uiFocused = false }
	end
	local manager, frame, button = QT:GetNativeGamepadFocus()
	local focused = Manager().isUIFocused
	local uiFocused = Accessible(focused) and focused == true
	return {
		available = true,
		uiFocused = uiFocused,
		manager = uiFocused and manager or nil,
		frame = uiFocused and frame or nil,
		button = uiFocused and button or nil,
	}
end
Notify = function()
	local snapshot = Snapshot()
	local failedBefore = state.failed
	for subscriber, callback in pairs(observers) do
		-- Consumers receive a fresh QT table, never the native registry/payload.
		local ok = pcall(callback, {
			available = snapshot.available,
			uiFocused = snapshot.uiFocused,
			manager = snapshot.manager,
			frame = snapshot.frame,
			button = snapshot.button,
		})
		if not ok then
			observers[subscriber] = nil
			-- Remove the failing observer before publishing the stopped snapshot.
			-- Fail can notify the remaining observers; never continue this stale
			-- snapshot or recursively latch another failure during that delivery.
			if not state.failed then
				Fail("observer_callback")
			end
			return
		end
		if not failedBefore and state.failed then
			return
		end
	end
	local record = snapshot.frame and records[snapshot.frame]
	if record and record.registered and not record.retiring then
		Call(record.policy.onSelection, record.frame, snapshot.button)
	end
end
function QT:RegisterGamepadObserver(subscriber, callback)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	if subscriber == nil or type(callback) ~= "function" then
		return false
	end
	observers[subscriber] = callback
	self:InitializeGamepadIntegration()
	Notify()
	return not state.failed
end
function QT:UnregisterGamepadObserver(subscriber)
	if self == QT and rawget(QT, "isRunningTests") ~= true then
		observers[subscriber] = nil
	end
end
function QT:IsGamepadWindowFocused(frame)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local snapshot = Snapshot()
	return snapshot.available and snapshot.uiFocused and snapshot.manager == frame and snapshot.frame == frame
end
function QT:IsGamepadWindowRegistered(frame)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local record = records[frame]
	return record ~= nil and (record.attempted == true or record.registered == true or record.retiring == true)
end
function QT:IsGamepadActionCurrent(frame)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local record = records[frame]
	return record ~= nil
		and record.registered == true
		and not record.retiring
		and not state.failed
		and state.enabled
		and Owned(frame)
		and frame:IsVisible()
		and self:IsGamepadWindowFocused(frame)
end
local function Verify(frame, target, reason)
	local manager, active, selected = QT:GetNativeGamepadFocus()
	if manager ~= frame or active ~= frame or (target and selected ~= target) or not SmartNavigation:IsShown() then
		Fail("focus_mismatch_" .. reason)
		return false
	end
	return not state.failed
end
local function FooterHide(record)
	local footer = record.footer
	if state.failed then
		return false
	end
	if not footer then
		return true
	end
	if footer:IsBindingGroupRequired() or footer.bindings then
		Fail("footer_bindings")
		return false
	end
	return Call(footer.HideAndDeactivateBindings, footer)
end
local function Setup(record)
	if record.prepared then
		return true
	end
	state.monitoring = true
	local ok = pcall(SmartNavigation_MarkFrameIgnoredContainerFrame, record.frame)
	if not ok then
		Fail("container_setup")
	end
	if state.failed then
		return false
	end
	if record.policy.footer ~= false then
		local made, footer =
			pcall(GamepadSharedUtility.CreatePromptedBindingFooter, record.frame, "QuestTogether" .. record.role)
		if not made or state.failed then
			if not state.failed then
				Fail("footer_setup")
			end
			return false
		end
		if
			not Methods(footer, {
				"AddStandardSelectPrompt",
				"AddStandardBackPrompt",
				"Finalize",
				"IsBindingGroupRequired",
				"ShowAndActivateBindings",
				"HideAndDeactivateBindings",
			})
		then
			Fail("footer_contract")
			return false
		end
		if
			not Call(footer.AddStandardSelectPrompt, footer)
			or not Call(footer.AddStandardBackPrompt, footer)
			or not Call(footer.Finalize, footer)
		then
			return false
		end
		if footer:IsBindingGroupRequired() or footer.bindings then
			Fail("footer_bindings")
			return false
		end
		record.footer = footer
	end
	record.prepared = true
	return true
end
local function ResetComplete()
	local active, selected, focused =
		SmartNavigation:GetActiveFrame(), SmartNavigation:GetCurrentButton(), Manager():GetActiveFrame()
	local bindings, scrolling = SmartNavigation.bindingActive, SmartNavigation.rightStickScrolling
	local count = Manager():GetShownFrameCount()
	return Accessible(active)
		and Accessible(selected)
		and Accessible(focused)
		and Accessible(bindings)
		and Accessible(scrolling)
		and Accessible(count)
		and active == nil
		and selected == nil
		and focused == nil
		and bindings == false
		and scrolling == false
		and count == 0
end
local function RemoveOrder(record)
	for i = #state.order, 1, -1 do
		if state.order[i] == record then
			table.remove(state.order, i)
			return
		end
	end
end
local function Retained(record)
	local focused, active = Manager():GetActiveFrame(), SmartNavigation:GetActiveFrame()
	if not Accessible(focused) or not Accessible(active) then
		Fail("detach_focus_unreadable")
		return true
	end
	if focused == record.frame or active == record.frame then
		Log("retained_focus", record.role)
		Fail("detach_retained_focus_" .. record.role)
		return true
	end
	return false
end
local function Detach(record)
	if state.failed or Restricted() or not Owned(record.frame) or not AncestorsVisible(record) then
		return false
	end
	if record.modeReset and not ResetComplete() then
		Fail("mode_reset_changed_before_hide")
		return false
	end
	if record.attempted then
		if record.detachTried then
			Fail("repeated_detach")
			return false
		end
		record.detachTried = true
		local ok, removed = Native("FrameHidden", Manager(), record.frame)
		if not ok then
			return false
		end
		if removed ~= true then
			Fail("detach_unverified")
			return false
		end
		if Retained(record) then
			return false
		end
		record.attempted, record.registered = false, false
	end
	-- Recheck after every native callback: it can hide UIParent synchronously.
	if state.failed or Restricted() or not AncestorsVisible(record) then
		return false
	end
	if not FooterHide(record) or not AncestorsVisible(record) or Retained(record) then
		return false
	end
	if record.hideRequested then
		record.hiding = true
		local ok = pcall(record.hide, record.frame)
		record.hiding = false
		if not ok then
			Fail("owned_hide")
			return false
		end
	end
	if state.failed then
		return false
	end
	RemoveOrder(record)
	local complete = record.complete
	record.complete, record.retiring, record.hideRequested, record.modeReset = nil, nil, nil, nil
	record.parent, record.generation = nil, record.generation + 1
	Log("detached", record.role)
	if complete then
		Call(complete, record.frame)
	end
	Notify()
	return not state.failed
end
Retire = function(record, hide, complete)
	if state.failed then
		return false
	end
	if complete then
		record.complete = complete
	end
	record.retiring, record.hideRequested = true, record.hideRequested or hide
	record.generation = record.generation + 1
	-- Retire descendants first; independent windows retain native focus ordering.
	for _, child in ipairs(state.order) do
		local parent = child.parent
		while parent do
			if parent == record.frame then
				child.retiring, child.hideRequested = true, true
				child.generation = child.generation + 1
				break
			end
			parent = records[parent] and records[parent].parent
		end
	end
	Schedule()
	return true
end
Reconcile = function()
	if state.reconciling or state.failed or Restricted() or not Capable() or not Visible() then
		return
	end
	state.reconciling = true
	local ok = pcall(function()
		while true do
			local nextRecord
			for i = #state.order, 1, -1 do
				if state.order[i].retiring then
					nextRecord = state.order[i]
					break
				end
			end
			if not nextRecord or not Detach(nextRecord) then
				break
			end
		end
		if state.worldReady and state.enabled and not state.failed and QT.TryInstallDefaultGamepadLauncher
			and QT:IsDefaultGamepadLauncherPending() then
			QT:TryInstallDefaultGamepadLauncher()
		end
	end)
	state.reconciling = nil
	if not ok then
		Fail("reconcile")
	end
end
Schedule = function()
	if state.failed or not Methods(C_Timer, { "After" }) then
		return
	end
	if state.scheduled then
		return
	end
	local token = { generation = state.generation }
	state.scheduled = token
	C_Timer.After(0, function()
		if state.scheduled ~= token then
			return
		end
		state.scheduled = nil
		if state.failed or token.generation ~= state.generation then
			return
		end
		local ok = pcall(Reconcile)
		if not ok then
			Fail("reconcile")
		end
	end)
end

local function InstallOwnedHooks(record)
	if record.hooked then
		return
	end
	record.hooked = true
	local frame = record.frame
	-- Only explicitly configured QT frames get this interception. Library-owned
	-- QT close buttons and Escape paths also must unregister before C Hide.
	frame.Hide = function(region)
		if rawget(QT, "isRunningTests") == true then
			return false
		end
		if record.hiding then
			return record.hide(region)
		end
		local handled, done = QT:HideGamepadWindow(region)
		if handled then
			return done
		end
		return record.hide(region)
	end
	frame.SmartNavigationCloseHandler = function()
		if state.failed or record.retiring then
			return true
		end
		if not QT:IsGamepadActionCurrent(frame) then
			return true
		end
		if record.policy.close then
			Call(record.policy.close, frame, "gamepad_back")
		else
			QT:DismissManagedWindow(frame, "gamepad_back")
		end
		return true
	end
	frame.FocusGamepad = function()
		if state.failed then
			return
		end
		if record.footer then
			if record.footer:IsBindingGroupRequired() or record.footer.bindings then
				Fail("footer_bindings")
				return
			end
			if not Call(record.footer.ShowAndActivateBindings, record.footer) then
				return
			end
		end
		Call(record.policy.onFocus, frame, true)
		Notify()
	end
	frame.UnfocusGamepad = function()
		if state.failed then
			return
		end
		if not FooterHide(record) then
			return
		end
		Call(record.policy.onFocus, frame, false)
		Notify()
	end
	frame:HookScript("OnHide", function()
		if state.failed or record.hiding or not record.attempted then
			return
		end
		if not AncestorsVisible(record) then
			Retire(record, true)
			return
		end
		-- Direct hiding bypasses authored unregister. Do not compound it by retry.
		Fail("unexpected_hide_" .. record.role)
	end)
	frame:HookScript("OnShow", function()
		if record.retiring then
			Schedule()
		end -- Never register on inherited OnShow.
	end)
end
function QT:ConfigureGamepadWindow(frame, policy)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	if not Owned(frame) or type(policy) ~= "table" then
		return false
	end
	local record = records[frame]
	if record then
		record.policy = policy
	else
		record = {
			frame = frame,
			policy = policy,
			generation = 0,
			hide = frame.Hide,
			role = tostring(policy.role or "window"):gsub("[^%w_]", ""):sub(1, 48),
		}
		records[frame] = record
	end
	-- Unsupported clients keep only QT policy data: no frame hooks or method
	-- interception, native callbacks, footers or navigation registration.
	if state.enabled and Capable() then
		InstallOwnedHooks(record)
	end
	return true
end
function QT:PresentGamepadWindow(frame, intent)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local record = records[frame]
	local explicit = intent == "user" or (type(intent) == "table" and intent.userInitiated == true)
	if
		not explicit
		or not record
		or state.failed
		or not state.enabled
		or Restricted()
		or not self:IsNativeGamepadMode()
		or not Capable()
		or not Visible()
		or not Owned(frame)
		or not frame:IsVisible()
		or record.retiring
	then
		return false
	end
	self:InitializeGamepadIntegration()
	if not state.attached then
		return false
	end
	InstallOwnedHooks(record)
	if not Setup(record) then
		return false
	end
	if record.registered then
		return self:RefreshGamepadNavigation(frame)
	end
	local parent = type(intent) == "table" and intent.parent or nil
	if parent and not Verify(parent, nil, "popup_parent") then
		return false
	end
	if not parent and record.policy.kind == "popup" then
		parent = ReadFrame(Manager():GetActiveFrame())
	end
	record.parent, record.detachTried, record.modeReset = parent, nil, nil
	record.generation = record.generation + 1
	record.attempted, record.hadNative = true, true
	state.order[#state.order + 1] = record
	local ok, added
	if record.policy.kind == "popup" or parent then
		ok, added = Native("HandlePopupShown", Manager(), frame)
	else
		ok, added = Native("FrameShown", Manager(), frame, false, true)
	end
	if not ok then
		return false
	end
	if record.policy.kind ~= "popup" and not parent and added ~= true then
		Fail("registration_rejected")
		return false
	end
	if not Verify(frame, nil, record.role) then
		return false
	end
	record.registered = true
	local target = record.policy.defaultFocus
	if type(target) == "function" then
		local got, value = pcall(target, frame)
		if not got then
			Fail("default_focus")
			return false
		end
		target = value
	end
	if target then
		if not Owned(target) then
			Fail("default_focus_unavailable")
			return false
		end
		if
			not Native("SetTargetButtonForFrame", SmartNavigation, frame, target)
			or not Verify(frame, target, record.role .. "_target")
		then
			return false
		end
	end
	local scrollFrame = record.policy.scrollFrame
	if type(scrollFrame) == "function" then
		local got, value = pcall(scrollFrame, frame)
		if not got then
			Fail("scroll_target")
			return false
		end
		scrollFrame = value
	end
	if scrollFrame then
		if not Owned(scrollFrame) then
			Fail("scroll_target_unavailable")
			return false
		end
		if not Native("SetScrollFrameForFrame", SmartNavigation, frame, scrollFrame) then
			return false
		end
	end
	Log("registered", record.role)
	Notify()
	return not state.failed
end
function QT:RefreshGamepadNavigation(frame, target)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local record = records[frame]
	if
		not record
		or not record.registered
		or record.retiring
		or state.failed
		or not state.enabled
		or Restricted()
		or not self:IsNativeGamepadMode()
		or not Visible()
		or not Owned(frame)
		or not frame:IsVisible()
	then
		return false
	end
	if not Native("RefreshButtonGroups", SmartNavigation, frame) then
		return false
	end
	if target then
		if not Owned(target) or not self:IsGamepadWindowFocused(frame) then
			return false
		end
		if
			not Native("SetTargetButtonForFrame", SmartNavigation, frame, target)
			or not Verify(frame, target, "refresh")
		then
			return false
		end
	end
	return true
end

-- A hidden selected child can hide the cursor through its anchor and thereby
-- execute native OnHide outside the authored unregister wrapper. Park selection
-- before callers change the child's visibility. SetTargetButtonForFrame calls
-- SelectButton -> UpdateCursorPosition synchronously in the audited source.
local function Within(frame, ancestor)
	for _ = 1, 64 do
		if not frame then
			return false
		end
		if not Accessible(frame) or not ReadFrame(frame) then
			return nil
		end
		if frame == ancestor then
			return true
		end
		if not Methods(frame, { "GetParent" }) then
			return nil
		end
		local ok, parent = pcall(frame.GetParent, frame)
		if not ok or not Accessible(parent) then
			return nil
		end
		frame = parent
	end
	return nil
end
local function NeverRegisteredWindow(control)
	local frame = control
	for _ = 1, 64 do
		if not frame or frame == UIParent then
			return false
		end
		if not ReadFrame(frame) then
			return false
		end
		local record = records[frame]
		if record then
			return not record.hadNative and not record.attempted and not record.retiring
		end
		if not Methods(frame, { "GetParent" }) then
			return false
		end
		local ok, parent = pcall(frame.GetParent, frame)
		if not ok or not Accessible(parent) then
			return false
		end
		frame = parent
	end
	return false
end
function QT:PrepareGamepadControlHide(control, fallback)
	-- This is a pure permission result for isolated UI fixtures, not a native
	-- entrypoint for their mock regions or the synchronous /qt test singleton.
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return true
	end
	if not Owned(control) or state.failed then
		return false
	end
	if not self:IsNativeGamepadMode() then
		return true
	end
	if not Capable() then
		return NeverRegisteredWindow(control)
	end
	if Restricted() or not Visible() then
		return false
	end
	local readVisibility, controlVisible = pcall(function() return control:IsVisible() end)
	if not readVisibility or not Accessible(controlVisible) or type(controlVisible) ~= "boolean" then
		return false
	end
	-- Fresh and closed menu trees are already invisible. Hiding their children
	-- cannot trigger another visibility change beneath the native cursor. Map
	-- canvas focus legitimately leaves navigation shown with no selected button.
	if controlVisible == false then
		return true
	end
	if not SmartNavigation:IsShown() or not SmartNavigation:IsVisible() then
		return true
	end
	local selected = SmartNavigation:GetCurrentButton()
	local active, manager = SmartNavigation:GetActiveFrame(), Manager():GetActiveFrame()
	if not Accessible(selected) or not Accessible(active) or not Accessible(manager) then
		return false
	end
	if not selected then
		return false
	end -- A nil selection does not clear the old native anchor.
	local affected = Within(selected, control)
	if affected == false then
		return true
	end
	if affected == nil or not active or manager ~= active or not ReadFrame(active) then
		return false
	end
	local uiFocused = Manager().isUIFocused
	if not Accessible(uiFocused) or uiFocused ~= true then
		return false
	end
	local record = records[active]
	local candidates = { fallback }
	if record then
		local default = record.policy.defaultFocus
		if type(default) == "function" then
			local ok, value = pcall(default, active)
			default = ok and value or nil
		end
		-- Use fixed slots: a nil caller fallback must not truncate the candidates.
		candidates[2], candidates[3], candidates[4], candidates[5] = default, active.cancel, active.close, active.Close
	end
	for i = 1, 5 do
		local target = candidates[i]
		if
			Owned(target)
			and ReadFrame(target)
			and Methods(target, { "IsShown", "IsVisible" })
			and target:IsShown()
			and target:IsVisible()
			and Within(target, control) == false
			and Within(target, active) == true
			and (type(target.IsEnabled) ~= "function" or target:IsEnabled())
		then
			if not Native("SetTargetButtonForFrame", SmartNavigation, active, target) then
				return false
			end
			return Verify(active, target, "child_hide")
		end
	end
	return false
end
function QT:SuspendGamepadWindow(frame, reason)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local record = records[frame]
	if not record or not record.attempted then
		return true
	end
	Log("suspended", record.role)
	Retire(record, false)
	Reconcile()
	return not record.attempted and not state.failed
end
-- OwnedUI calls this before its ordinary Hide queue. A handled request owns
-- its completion callback through detachment, including combat/ancestor delay.
function QT:HideGamepadWindow(frame, complete)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local record = records[frame]
	if not record or not (record.attempted or record.retiring or (state.failed and record.hadNative)) then
		return false
	end
	if state.failed then
		return true, false
	end
	Retire(record, true, complete)
	Reconcile()
	return true, not record.retiring
end

local function OwnUtility(frame, fn, ...)
	if
		state.failed
		or not state.enabled
		or Restricted()
		or not Capable()
		or not Owned(frame)
		or type(fn) ~= "function"
	then
		return false
	end
	state.monitoring = true
	local ok = pcall(fn, frame, ...)
	if not ok then
		Fail("owned_navigation_metadata")
	end
	return ok and not state.failed
end
function QT:MarkGamepadContainer(frame)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	return OwnUtility(frame, SmartNavigation_MarkFrameIgnoredContainerFrame)
end
function QT:SetGamepadControlIgnored(frame, ignored)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	return OwnUtility(frame, ignored and SmartNavigation_MarkFrameIgnored or SmartNavigation_ClearIgnoreStatus)
end
function QT:SetGamepadDirectionOverride(frame, direction, callback)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local nativeDirection = SMART_NAV_INPUT_DIRECTION and SMART_NAV_INPUT_DIRECTION[direction]
	if
		not nativeDirection
		or (type(callback) ~= "function" and callback ~= true and callback ~= nil and not Owned(callback))
	then
		return false
	end
	return OwnUtility(frame, SmartNavigation_AddJumpNavigationOverride, nativeDirection, callback)
end

local function RetireAll(reason)
	Log("retire_all", reason)
	for _, record in ipairs(state.order) do
		Retire(record, true)
	end
	Notify()
end
local function Attach()
	if state.attached or state.failed or Restricted() or not Capable() then
		return
	end
	state.attached, state.monitoring = true, true
	if not Call(InputUtil.RegisterForInterfaceTransitions, owner) then
		return
	end
	if
		not Call(InputUtil.RegisterGamepadUninit, owner, function()
			if state.failed then
				return
			end
			if #state.order > 0 then
				if not ResetComplete() then
					Fail("mode_reset_unverified")
					return
				end
				for _, record in ipairs(state.order) do
					record.attempted, record.registered, record.modeReset = false, false, true
				end
				RetireAll("mode_exit")
			end
			Notify()
		end)
	then
		return
	end
	if not Call(InputUtil.RegisterGamepadInit, owner, function()
		Notify()
		Schedule()
	end) then
		return
	end
	if
		not Call(SmartNavigation.RegisterCallback, SmartNavigation, "SelectedButtonUpdated", function()
			if not state.failed then
				Notify()
			end
		end, owner)
	then
		return
	end
	if
		not Call(EventRegistry.RegisterCallback, EventRegistry, "Gamepad.RefreshFrameFocus", function()
			Notify()
		end, owner)
	then
		return
	end
	if
		not Call(EventRegistry.RegisterCallback, EventRegistry, "UI.TopLevelParentHidden", function()
			if not state.failed then
				RetireAll("parent_hidden")
			end
		end, owner)
	then
		return
	end
	if
		not Call(EventRegistry.RegisterCallback, EventRegistry, "UI.TopLevelParentShown", function()
			Schedule()
			Notify()
		end, owner)
	then
		return
	end
end
function QT:InitializeGamepadIntegration()
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	if state.enabled == nil then
		state.enabled = type(self.GetOption) ~= "function" or self:GetOption("nativeGamepadNavigation") ~= false
	end
	if not SupportedBuild() then
		return false
	end
	if not state.listener then
		local listener = CreateFrame("Frame")
		state.listener = listener
		for _, event in ipairs({
			"ADDON_LOADED",
			"PLAYER_ENTERING_WORLD",
			"PLAYER_LEAVING_WORLD",
			"CURSOR_CHANGED",
			"UPDATE_MACROS",
			"ACTIONBAR_SLOT_CHANGED",
			"PLAYER_REGEN_ENABLED",
			"PLAYER_REGEN_DISABLED",
			"ADDON_RESTRICTION_STATE_CHANGED",
			"ADDON_ACTION_BLOCKED",
			"ADDON_ACTION_FORBIDDEN",
		}) do
			if not C_EventUtils or C_EventUtils.IsEventValid(event) then
				listener:RegisterEvent(event)
			end
		end
		listener:SetScript("OnEvent", function(_, event, source)
			if event == "PLAYER_LEAVING_WORLD" then state.worldReady = false; return end
			if event == "PLAYER_ENTERING_WORLD" then state.worldReady = true end
			if event == "CURSOR_CHANGED" or event == "UPDATE_MACROS" or event == "ACTIONBAR_SLOT_CHANGED" then
				if event == "UPDATE_MACROS" and QT.OnGamepadLauncherMacroUpdate then QT:OnGamepadLauncherMacroUpdate() end
				if event == "ACTIONBAR_SLOT_CHANGED" and QT.OnGamepadLauncherSlotUpdate then QT:OnGamepadLauncherSlotUpdate() end
				if QT.IsDefaultGamepadLauncherPending and QT:IsDefaultGamepadLauncherPending() then Schedule() end
				return
			end
			if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
				if state.monitoring and Accessible(source) and source == "QuestTogether" then
					Fail("security_event")
				end
				return
			end
			if state.failed then
				return
			end
			if event == "ADDON_LOADED" then
				state.capable = nil
			end
			Attach()
			Schedule()
			Notify()
		end)
	end
	Attach()
	return state.attached == true and not state.failed
end
function QT:SetGamepadIntegrationEnabled(enabled)
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	state.enabled = enabled == true
	self:InitializeGamepadIntegration()
	if not state.enabled and not state.failed then
		RetireAll("disabled")
		Reconcile()
	end
	Notify()
end
function QT:GetGamepadIntegrationStatus()
	if self ~= QT or rawget(QT, "isRunningTests") == true then
		return false
	end
	local available = Capable() and true or false
	return {
		available = available,
		clientVersion = state.clientVersion or "unknown",
		clientBuild = state.clientBuild or "unknown",
		supportedBuild = SupportedBuild() == true,
		unavailableReason = available and "none" or state.unavailableReason or "native_missing_functions",
		worldReady = state.worldReady == true,
		enabled = state.enabled,
		failed = state.failed == true,
		reloadRequired = state.reloadRequired == true,
		failure = state.failure,
		registered = #state.order,
	}
end
