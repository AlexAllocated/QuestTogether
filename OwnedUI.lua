-- Operations on QT-owned regions only. Foreign parents are read through the
-- addon boundary; hide/stop teardown has a lifetime independent of enablement.
local QT = _G.QuestTogether
local Lib = QT.LibChev

function QT:CanMutateOwnedUI(region, teardown)
	return (teardown or not self:IsRuntimeRestricted()) and Lib.CanMutateOwnedRegion(region)
end

function QT:CallOwnedUI(region, method, ...)
	if not self:CanMutateOwnedUI(region) then
		error("owned UI region unavailable", 0)
	end
	if method == "Show" then
		self:CancelOwnedUICleanup(region)
	end
	return region[method](region, ...)
end

function QT:CreateOwnedUIFrame(factory, kind, parent, template)
	if self:IsRuntimeRestricted() or (parent and not self:CanAccessForeignFrame(parent)) then
		error("owned UI parent unavailable", 0)
	end
	local frame = factory(self, kind, nil, parent, template)
	if not self:CanMutateOwnedUI(frame) then
		error("owned UI frame unavailable", 0)
	end
	return frame
end

function QT:GetOwnedUIParent()
	return UIParent
end
function QT:CreateOwnedWindowFrame(...)
	return CreateFrame(...)
end
-- Parentless, unprotected observer: no layout, foreign parent or secure template.
function QT:CreateOwnedUICleanupFrame()
	return CreateFrame("Frame")
end

function QT:GetOwnedUICleanupState()
	local state = rawget(self, "ownedUICleanupState")
	if not state then
		state = { pending = {} }
		self.ownedUICleanupState = state
	end
	return state
end

local function StopDriver(state)
	if state.driver and Lib.CanMutateOwnedRegion(state.driver) then
		state.driver:SetScript("OnUpdate", nil)
	end
	state.armed = nil
end

function QT:CancelOwnedUICleanup(region)
	local state = rawget(self, "ownedUICleanupState")
	if not state then
		return
	end
	state.pending[region] = nil
	if not next(state.pending) then
		StopDriver(state)
	end
end

local function TryCleanup(addon, state, region, entry)
	if state.pending[region] ~= entry then
		return
	end
	local ok, allowed
	if entry.canMutate then
		ok, allowed = pcall(entry.canMutate, region)
	else
		ok, allowed = true, addon:CanMutateOwnedUI(region, true)
	end
	if not ok or not allowed then
		return
	end
	local cleaned, done = pcall(entry.cleanup, region)
	if cleaned and done ~= false and state.pending[region] == entry then
		state.pending[region] = nil
		if entry.complete then
			local completed, err = pcall(entry.complete, region)
			if not completed and addon.RecordDiagnosticError then
				addon:RecordDiagnosticError("owned_ui_cleanup", err)
			end
		end
	end
end

function QT:FlushOwnedUICleanup()
	local state = rawget(self, "ownedUICleanupState")
	if not state then
		return true
	end
	if state.flushing then
		return false
	end
	state.flushing = true
	local pending = {}
	for region, entry in pairs(state.pending) do
		pending[#pending + 1] = { region, entry }
	end
	for _, pair in ipairs(pending) do
		TryCleanup(self, state, pair[1], pair[2])
	end
	state.flushing = nil
	if not next(state.pending) then
		StopDriver(state)
		return true
	end
	return false
end

function QT:QueueOwnedUICleanup(region, cleanup, complete, canMutate)
	if not region then
		return true
	end
	local state = self:GetOwnedUICleanupState()
	state.pending[region] =
		{ cleanup = cleanup or function(frame)
			frame:Hide()
		end, complete = complete, canMutate = canMutate }
	-- Queueing N retired markers must not retry the previous N markers each
	-- time. Attempt this entry once; the shared driver retries the batch.
	if not state.flushing then
		state.flushing = true
		TryCleanup(self, state, region, state.pending[region])
		state.flushing = nil
	end
	if not next(state.pending) then
		StopDriver(state)
		return true
	end
	if not state.armed then
		state.driver = state.driver or self:CreateOwnedUICleanupFrame()
		if Lib.CanMutateOwnedRegion(state.driver) then
			state.armed = true
			local elapsed = 0
			state.driver:SetScript("OnUpdate", function(_, delta)
				elapsed = elapsed + (self:SafeToNumber(delta) or 0)
				if elapsed >= 0.25 then
					elapsed = 0
					self:FlushOwnedUICleanup()
				end
			end)
		end
	end
	return state.pending[region] == nil
end

function QT:HideOwnedUI(region)
	return self:QueueOwnedUICleanup(region)
end
