-- Quest focus policy shared by live party navigation and the isolated preview.
-- All native, persistence, notification and party access is supplied explicitly.
local QT = _G.QuestTogether
local L = QT.Translate
local Controller = {}
Controller.__index = Controller
function QT:CreatePartyFocusController(adapter)
	return setmetatable({ adapter = adapter }, Controller)
end
function Controller:IsActive()
	return self.adapter.active()
end
function Controller:GetTarget()
	local s = self.adapter.peek()
	if s and s.following then
		return s.following, s.followToken
	end
end
function Controller:Stop()
	self.choice = nil
	local a, s = self.adapter, self.adapter.peek()
	a.save(nil)
	if not s or not s.following then
		return false
	end
	s.following, s.expectedQuest, s.attempt, s.followStatus, s.checkExternal, s.resuming, s.waiting = nil, nil, nil, nil, nil, nil, nil
	a.publish()
	a.changed()
	return true
end
function Controller:Suspend()
	self.choice = nil
end
function Controller:Resume()
	self.choice = nil
	local s = self.adapter.peek()
	if not s then
		return
	end
	if s and s.following then
		s.attempt, s.checkExternal, s.resuming = nil, nil, true
	end
	self.adapter.publish()
end
function Controller:WouldCycle(name)
	local a, seen = self.adapter, {}
	for _ = 1, 5 do
		if name == a.ownName() or seen[name] then
			return true
		end
		seen[name] = true
		local peer = a.peer(name)
		if not peer or not peer.following or peer.following == "" then
			return false
		end
		name = peer.following
	end
	return true
end
function Controller:Follow(name)
	local a = self.adapter
	name = a.normalize(name)
	local peer = name and a.peer(name)
	if
		not self:IsActive()
		or a.restricted()
		or not peer
		or peer.questID < 0
		or name == a.ownName()
		or self:WouldCycle(name)
	then
		return false
	end
	local s = a.state()
	self.choice = nil
	s.following, s.attempt, s.expectedQuest = name, nil, a.currentQuest() or 0
	s.checkExternal, s.resuming, s.waiting, s.followToken = nil, nil, nil, {}
	a.save(name)
	a.publish()
	self:Apply()
	a.changed()
	return true
end
function Controller:Reconcile()
	local a, s = self.adapter, self.adapter.peek()
	if not s or not s.following or a.loggingOut() then
		return
	end
	if not a.member(s.following) or a.ignored(s.following) or a.groupInvalid() then
		self:Stop()
	end
end
function Controller:Apply()
	local a, s = self.adapter, self.adapter.peek()
	if not self:IsActive() or not s or not s.following then
		return
	end
	if not a.member(s.following) or a.ignored(s.following) or a.raid() or self:WouldCycle(s.following) then
		self:Stop()
		return
	end
	-- Native selection already changed before its tracking event reached us.
	-- Keep that choice visible while the user decides whether to stop following.
	if self.choice then
		if s.checkExternal then self:ObserveNative() end
		return
	end
	local peer = a.peer(s.following)
	if not peer or peer.questID < 0 then
		s.waiting, s.attempt = true, nil
		local status = peer and L("Focus not shared or unavailable") or L("Waiting for quest focus")
		if s.followStatus ~= status then
			s.followStatus = status
			a.changed()
		end
		return
	end
	if a.restricted() then
		return
	end
	if s.resuming then
		self:ObserveNative()
		if s.resuming then
			return
		end
	end
	if s.checkExternal then
		self:ObserveNative()
		if not s.following or s.checkExternal or self.choice then
			return
		end
	end
	local before, status = s.followStatus
	if peer.questID == 0 then
		status, s.attempt, s.waiting = L("No focused quest"), nil, true
	else
		local owned = a.owns(peer.questID)
		if owned == false then
			-- Follow the person, not a single compatible quest. Keep the native
			-- destination until their focus becomes eligible, including when we
			-- acquire this same quest without receiving another peer update.
			status, s.attempt, s.waiting = L("Waiting for a shared quest"), nil, true
		elseif owned ~= true then
			s.waiting, s.attempt = true, nil
			return
		elseif a.currentQuest() == peer.questID then
			s.attempt, s.expectedQuest, s.waiting = peer.questID, peer.questID, nil
		else
			s.waiting = nil
			if s.attempt ~= peer.questID then
				s.attempt, s.expectedQuest, s.applying = peer.questID, peer.questID, true
				local ok, applied = pcall(a.setQuest, peer.questID)
				s.applying = nil
				if not ok or applied ~= true then
					s.expectedQuest, s.followStatus = nil, L("Unable to track this quest")
				else
					s.followStatus = nil
					a.publish()
				end
			end
			status = s.followStatus
		end
	end
	if before ~= status then
		s.followStatus = status
		a.changed()
	end
end
function Controller:OnTrackingChanged()
	local a, s = self.adapter, self.adapter.peek()
	if self:IsActive() and s and s.following and not s.applying and not s.resuming then
		s.checkExternal = true
	end
	a.publish()
	a.changed()
end
function Controller:ObserveNative()
	local a = self.adapter
	if a.restricted() then
		return nil
	end
	local ok, native = pcall(a.native)
	if not ok or not a.readable(native) then
		return nil
	end
	local s = a.state()
	if self:IsActive() then
		local choice = self.choice
		if choice and choice.nativeOverride and native.questID >= 0 then
			if native.questID == choice.questID then
				s.checkExternal = nil
				return native
			elseif native.questID == s.expectedQuest then
				-- Selecting the followed quest again retires the old prompt.
				self.choice, s.checkExternal, s.attempt = nil, nil, nil
				return native
			elseif native.questID > 0 or native.questCleared == true then
				if a.blocked() then s.checkExternal = true; return nil end
				s.checkExternal = nil
				if not self:Request(a.ownName(), native.questID, true) then self:Stop() end
				return native
			end
		end
		if s.resuming and native.questID >= 0 then
			s.expectedQuest, s.resuming = native.questID, nil
		end
		if s.checkExternal and native.questID >= 0 then
			s.checkExternal = nil
			if s.following and native.questID ~= s.expectedQuest then
				local previous = a.questID(s.expectedQuest)
				local peer = a.peer(s.following)
				local shared = peer and peer.questID > 0 and a.owns(peer.questID) == true
				if s.waiting or not shared or not previous or (previous > 0 and a.owns(previous) ~= true) then
					-- Native auto-selection on acceptance/turn-in can arrive before
					-- Apply sees the updated quest log. No valid sync is being
					-- overridden: retain follow intent and adopt this local baseline.
					s.expectedQuest, s.attempt = native.questID, nil
					return native
				end
				if previous and (native.questID > 0 or native.questCleared == true) then
					if a.blocked() then
						s.checkExternal = true
						return nil
					end
					if not self:Request(a.ownName(), native.questID, true) then self:Stop() end
					return native
				end
				self:Stop()
			end
		end
	end
	return native
end
function Controller:Select(name, questID)
	local a = self.adapter
	if not self:IsActive() or a.restricted() then
		return false
	end
	if name == a.ownName() then
		if questID ~= 0 and a.owns(questID) ~= true then
			return false
		end
		if (a.currentQuest() or 0) == questID then
			self:Stop()
			self:OnTrackingChanged()
			return true
		end
		local s = a.peek()
		if s then
			s.applying = true
		end
		local ok, applied = pcall(a.setQuest, questID)
		if s then
			s.applying = nil
		end
		if ok and applied == true then
			self:Stop()
			self:OnTrackingChanged()
			return true
		end
		return false
	end
	local peer = a.peer(name)
	if not peer or peer.questID ~= questID then
		return false
	end
	return self:Follow(name)
end
function Controller:Request(name, questID, nativeOverride)
	local a = self.adapter
	if not self:IsActive() or a.blocked() then
		return false
	end
	local following, token = self:GetTarget()
	local state = a.peek()
	local choice = { questID = questID, nativeOverride = nativeOverride == true }
	self.choice = choice
	if following and following ~= name then
		local function Retire()
			if self.choice == choice then
				self.choice, state.attempt = nil, nil
			end
		end
		local function Current()
			local current, currentToken = self:GetTarget()
			if not self:IsActive() or a.loggingOut() or a.peek() ~= state
				or current ~= following or currentToken ~= token or self.choice ~= choice then
				return false
			end
			self:Reconcile()
			if self:GetTarget() ~= following then return false end
			if state.checkExternal then self:ObserveNative() end
			return self.choice == choice and not state.checkExternal
		end
		local function Cancel()
			if not Current() then Retire(); return false end
			self.choice = nil
			state.attempt, state.checkExternal = nil, nil
			self:Apply()
			return true
		end
		local opened = a.confirm(following, function()
			if not Current() then Retire(); return false end
			local selected = self:Select(name, questID)
			-- A quest may disappear or restrictions may begin while the dialog
			-- is open. Its closing must not leave periodic following suspended.
			if not selected then Cancel() end
			return selected
		end, Cancel)
		if not opened and self.choice == choice then self.choice = nil end
		return opened
	end
	self.choice = nil
	return self:Select(name, questID)
end

-- Exactly one controller owns native focus. Releasing a preview establishes a
-- fresh live baseline through the controller API, not by editing its state.
function QT:AcquirePartyFocusController(controller)
	local previous = rawget(self, "nativePartyFocusOwner") or rawget(self, "partyFocusController")
	if previous and previous ~= controller then
		previous:Suspend()
	end
	self.nativePartyFocusOwner = controller
end
function QT:ReleasePartyFocusController(controller)
	if rawget(self, "nativePartyFocusOwner") ~= controller then
		return false
	end
	self.nativePartyFocusOwner = nil
	self:GetPartyFocusController():Resume()
	return true
end
