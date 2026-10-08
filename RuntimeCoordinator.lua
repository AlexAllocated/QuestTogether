-- One addon-owned periodic lifetime; individual feature stores do not own the clock.
local QT = _G.QuestTogether
local UPDATE_INTERVAL = 0.2
-- One owner for periodic publication. Share this tick's addon-owned location
-- sample with nearby streams; never retain it across frames or privacy changes.
function QT:UpdatePlayerCommunications()
	self:UpdatePartyQuestCompareFreshness()
	self:UpdatePlayerPhaseObservations()
	if self.UpdateQTPlayerPresence then
		self:UpdateQTPlayerPresence()
	end
	local sample
	if rawget(self, "geographicCommsState") then
		sample = self:UpdateGeographicComms()
	else
		self:BroadcastPlayerLocation()
	end
	self:UpdateNearbyStreams(sample)
	self:DrainTransport()
end

function QT:CreateRuntimeCoordinatorFrame()
	return CreateFrame("Frame")
end

function QT:InitializeRuntimeCoordinator()
	if not self.isEnabled or not self.hasLoggedIn then
		return false
	end
	local state = {}
	self.runtimeCoordinatorState = state
	local frame = rawget(self, "runtimeCoordinatorFrame")
	if not frame then
		frame = self:CreateRuntimeCoordinatorFrame()
		self.runtimeCoordinatorFrame = frame
	end
	if not self.LibChev.CanMutateOwnedRegion(frame) then
		return false
	end
	local elapsed, animationElapsed = 0, 0
	frame:SetScript("OnUpdate", function(_, delta)
		if rawget(self, "runtimeCoordinatorState") ~= state or not self.isEnabled then
			return
		end
		local step = self:SafeToNumber(delta) or 0
		if step < 0 or step > 1000 then
			step = 0
		end
		elapsed, animationElapsed = elapsed + step, animationElapsed + step
		if animationElapsed >= 1 / 30 then
			animationElapsed = 0
			self:RefreshNearbyStreamPins()
		end
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		self:UpdatePartyNavigation()
		self:RefreshPartyWaypointPins()
		self:UpdatePlayerCommunications()
		self:PrunePlayerLocations()
		self:RefreshPlayerLocationPins()
		self:UpdatePlayerTooltipBadge()
		self:UpdateChatLogPlayerTooltip()
	end)
	-- First update uses the same paced path as recovery and movement.
	return true
end

function QT:ResetRuntimeCoordinator()
	self:ResetPartyNavigation()
	self:HideChatLogPlayerTooltip()
	self:HidePlayerTooltipBadge()
	self.runtimeCoordinatorState = nil
	self:ResetNearbyStreams()
	self:ResetPlayerPhases()
	local frame = rawget(self, "runtimeCoordinatorFrame")
	if frame and self.LibChev.CanMutateOwnedRegion(frame) then
		frame:SetScript("OnUpdate", nil)
	end
	if self.HidePlayerLocationPins then
		self:HidePlayerLocationPins()
	end
end
