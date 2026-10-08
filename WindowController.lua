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
		controller.hooks[action] = callback
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
		self:HideOwnedUI(frame)
		Invoke(controller, "dismiss", reason or "close")
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
