-- Lifecycle of QT windows. Inherited invisibility suspends interaction;
-- dismissal retires the request/session even when the parent is already hidden.
local QT = _G.QuestTogether
local Lib = QT.LibChev

local function Invoke(controller, action, ...)
	local callback = controller.hooks[action]
	if callback then
		return callback(...)
	end
end

-- Combat's restriction event arrives before enforcement. Close synchronously;
-- scheduling this work for the next frame misses the native teardown window.
function QT:IsCombatWindowCloseEvent(event, kind, newState)
	if event == "PLAYER_REGEN_DISABLED" then return true end
	local types, states = Enum and Enum.AddOnRestrictionType, Enum and Enum.AddOnRestrictionState
	return event == "ADDON_RESTRICTION_STATE_CHANGED" and types and states
		and types.Combat ~= nil and states.Activating ~= nil
		and Lib.CanAccess(kind) and Lib.CanAccess(newState)
		and kind == types.Combat and newState == states.Activating or false
end

function QT:DismissManagedWindowsForCombat()
	if self == QT and rawget(self, "isRunningTests") == true then return end
	if rawget(self, "closingWindowsForCombat") then return end
	self.closingWindowsForCombat = true
	local ok, err = pcall(function()
		-- Native popups must be retired before their parent can be hidden.
		if self.DismissGamepadWindowsForCombat then self:DismissGamepadWindowsForCombat() end
		local pending = {}
		for frame in pairs(rawget(self, "windowControllers") or {}) do
			if Lib.CanMutateOwnedRegion(frame) and frame:IsShown() then pending[#pending + 1] = frame end
		end
		for _, frame in ipairs(pending) do
			if Lib.CanMutateOwnedRegion(frame) and frame:IsShown() then
				local controller = self:GetWindowController(frame)
				if controller and controller.hooks.combat then
					self:StopWindowInteraction(frame)
					Invoke(controller, "combat")
				else
					self:DismissManagedWindow(frame, "combat")
				end
			end
		end
	end)
	self.closingWindowsForCombat = nil
	if not ok and self.RecordDiagnosticError then self:RecordDiagnosticError("combat_windows", err) end
end

-- Window cleanup outlives feature enablement: the debug console can be opened
-- with QT disabled, and clients without native gamepad support need it too.
function QT:EnsureWindowCombatObserver()
	if self ~= QT or rawget(self, "isRunningTests") == true or self.windowCombatObserver then return end
	local observer = self:CreateOwnedUICleanupFrame()
	observer:SetScript("OnEvent", function(_, event, kind, newState)
		if self:IsCombatWindowCloseEvent(event, kind, newState) then self:DismissManagedWindowsForCombat() end
	end)
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "ADDON_RESTRICTION_STATE_CHANGED" }) do
		pcall(observer.RegisterEvent, observer, event)
	end
	self.windowCombatObserver = observer
end

function QT:GetWindowController(frame)
	local controllers = rawget(self, "windowControllers")
	return controllers and controllers[frame]
end

function QT:StopWindowInteraction(frame)
	self:StopWindowDrag(frame)
	if frame.resizing and Lib.CanMutateOwnedRegion(frame) then
		frame:StopMovingOrSizing()
		frame.resizing = nil
		self:SaveWindowLayout(frame)
	end
end

function QT:ConfigureWindowController(frame, hooks)
	QT.EnsureWindowCombatObserver(self)
	self.windowControllers = rawget(self, "windowControllers") or Lib.WeakKeys()
	local controller = self.windowControllers[frame]
	if not controller then
		controller = { frame = frame, hooks = {} }
		self.windowControllers[frame] = controller
		local function Hook(event, callback)
			if type(frame.HookScript) == "function" then
				frame:HookScript(event, callback)
			else
				local prior = type(frame.GetScript) == "function" and frame:GetScript(event)
				frame:SetScript(event, function(...)
					if prior then
						prior(...)
					end
					callback(...)
				end)
			end
		end
		Hook("OnHide", function()
			self:StopWindowInteraction(frame)
			Invoke(controller, "suspend")
			if Lib.CanMutateOwnedRegion(frame) and not frame:IsShown() and not controller.dismissed then
				controller.dismissed = true
				Invoke(controller, "dismiss", "hide")
			end
		end)
		Hook("OnShow", function()
			controller.dismissed = nil
			self:CancelOwnedUICleanup(frame)
			Invoke(controller, "resume")
		end)
	end
	for action, callback in pairs(hooks or {}) do
		if action == "gamepad" then
			if self.ConfigureGamepadWindow then
				self:ConfigureGamepadWindow(frame, callback)
			end
		else
			controller.hooks[action] = callback
		end
	end
	return controller
end

function QT:DismissManagedWindow(frame, reason)
	local controller = self:GetWindowController(frame) or self:ConfigureWindowController(frame)
	self:StopWindowInteraction(frame)
	if not controller.dismissed then
		controller.dismissed = true
		-- A request's dismissal may synchronously show its successor on this
		-- same frame. Retire the old presentation before invoking that callback.
		if self.IsGamepadWindowRegistered and self:IsGamepadWindowRegistered(frame) then
			self:HideOwnedUI(frame, function()
				Invoke(controller, "dismiss", reason or "close")
			end)
		else
			-- Preserve ordinary dismissal outside the cleanup queue's flushing
			-- scope: callbacks can synchronously retire their own child regions.
			self:HideOwnedUI(frame)
			Invoke(controller, "dismiss", reason or "close")
		end
		return
	end
	self:HideOwnedUI(frame)
end

function QT:RefreshManagedWindow(frame, restore)
	local controller = self:GetWindowController(frame)
	if not self:CanMutateOwnedUI(frame) then
		return false
	end
	if controller then
		Invoke(controller, "theme")
	end
	return self:ApplyWindowLayout(frame, restore)
end

-- Request identity belongs to the prompt controller, not to a checkbox shape.
function QT:ConfigureRequestPrompt(frame, decline)
	return self:ConfigureWindowController(frame, {
		dismiss = function(reason)
			local request = frame.request
			if reason ~= "hide" and request and not frame.preview then
				decline(request)
			end
		end,
	})
end
