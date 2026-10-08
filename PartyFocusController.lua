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
	s.following, s.expectedQuest, s.attempt, s.followStatus, s.checkExternal, s.resuming = nil, nil, nil, nil, nil, nil
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
	s.following, s.attempt, s.expectedQuest = name, nil, a.currentQuest() or 0
	s.checkExternal, s.resuming, s.followToken = nil, nil, {}
	a.save(name)
	a.clearMissing()
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
	local peer = a.peer(s.following)
	if not peer or peer.questID < 0 then
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
		if not s.following or s.checkExternal then
			return
		end
	end
	local before, status = s.followStatus
	if peer.questID == 0 then
		status, s.attempt = L("No focused quest"), nil
	else
		local owned = a.owns(peer.questID)
		if owned == false then
			local name = s.following
			self:Stop()
			a.missing(name, peer.questID, peer.title)
			return
		elseif owned ~= true then
			return
		elseif a.currentQuest() == peer.questID then
			s.attempt, s.expectedQuest = peer.questID, peer.questID
		else
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
		if s.resuming and native.questID >= 0 then
			s.expectedQuest, s.resuming = native.questID, nil
		end
		if s.checkExternal and native.questID >= 0 then
			s.checkExternal = nil
			if s.following and native.questID ~= s.expectedQuest then
				local previous = a.questID(s.expectedQuest)
				if previous and (native.questID > 0 or native.questCleared == true) then
					if a.blocked() then
						s.checkExternal = true
						return nil
					end
					s.applying = true
					local restored, applied = pcall(a.setQuest, previous)
					s.applying = nil
					if restored and applied == true then
						self:Request(a.ownName(), native.questID)
						return self:ObserveNative()
					end
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
function Controller:Request(name, questID)
	local a = self.adapter
	if not self:IsActive() or a.blocked() then
		return false
	end
	local following, token = self:GetTarget()
	local choice = {}
	self.choice = choice
	if following and following ~= name then
		return a.confirm(following, function()
			local current, currentToken = self:GetTarget()
			if not self:IsActive() or current ~= following or currentToken ~= token or self.choice ~= choice then
				return false
			end
			self:Reconcile()
			if self:GetTarget() ~= following then
				return false
			end
			return self:Select(name, questID)
		end)
	end
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
