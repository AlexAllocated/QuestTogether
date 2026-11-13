-- Observe native selection without invoking its hover scripts or changing the
-- focused quest. POT still owns its ordinary mode, party and tooltip policy.
local QT = _G.QuestTogether

function QT:InitializeGamepadTracker()
	self:ResetGamepadTracker()
	if not self.RegisterGamepadObserver then return end
	local state = {}
	self.gamepadTracker = state
	self:RegisterGamepadObserver(state, function(snapshot)
		if rawget(self, "gamepadTracker") ~= state then return end
		local changed = state.frame ~= snapshot.frame or state.button ~= snapshot.button
			or state.available ~= snapshot.available or state.uiFocused ~= snapshot.uiFocused
		state.frame, state.button = snapshot.frame, snapshot.button
		state.available, state.uiFocused = snapshot.available, snapshot.uiFocused
		if changed then
			state.mouseX, state.mouseY = self:GetPlayerLocationHoverCursorPosition()
			state.mouseOwnsHover = nil
			self:QueueQuestFocusRefresh()
		end
	end)
end

function QT:ResetGamepadTracker()
	local state = rawget(self, "gamepadTracker")
	self.gamepadTracker = nil
	if state and self.UnregisterGamepadObserver then self:UnregisterGamepadObserver(state) end
end

function QT:GetGamepadTrackerQuestHover(modules)
	local state = rawget(self, "gamepadTracker")
	if not state or not state.available or not state.uiFocused or not self:IsNativeGamepadMode()
		or self:IsWorkBlocked("foreign_frame_mutation") then return end
	local x, y = self:GetPlayerLocationHoverCursorPosition()
	if x and y and state.mouseX and (x ~= state.mouseX or y ~= state.mouseY) then
		state.mouseOwnsHover = true
	end
	if state.mouseOwnsHover then return end
	-- The selected control may be a pooled POI button or a header child. Resolve
	-- its current ancestors on every presentation pass; never cache its quest ID.
	local id, block, native = self:ResolveQuestTrackerHoverFrame(state.button, modules)
	return id, block, native, true
end
