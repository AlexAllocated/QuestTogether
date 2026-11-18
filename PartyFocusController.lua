-- Quest focus policy shared by live party navigation and the isolated preview.
-- All native, persistence, notification and party access is supplied explicitly.
local QT = _G.QuestTogether
local L = QT.Translate
local Controller = {}
Controller.__index = Controller
-- Acceptance is synchronous, but native tracking notifications may be delivered
-- on a later frame. Match one accepted quest, never every selection in a grace
-- period. A short settlement also allows tracking to arrive before acceptance.
local ACCEPTANCE_SECONDS = 2
local TRACKING_SETTLE_SECONDS = 0.2
function QT:CreatePartyFocusController(adapter)
	return setmetatable({ adapter = adapter }, Controller)
end
function Controller:IsActive()
	return self.adapter.active()
end
function Controller:IsAutomaticLocked()
	local a = self.adapter
	if not self.automaticMode or not a.automaticTarget then return false end
	local governed, leader, usable = a.automaticTarget()
	return governed and usable and leader == self:GetTarget() and not self:WouldCycle(leader)
end
function Controller:ReconcileAutomatic()
	local a = self.adapter
	if self.reconcilingAutomatic or not a.automaticTarget or not self:IsActive() or a.loggingOut() or a.restricted() then return end
	self.reconcilingAutomatic = true
	local governed, leader, usable = a.automaticTarget()
	if governed then
		if not self.automaticMode or self.automaticLeader ~= leader then
			self:Stop(true)
			if a.dismissChoices then a.dismissChoices() end
		end
		self.automaticMode, self.automaticLeader = true, leader
		if usable and not self:WouldCycle(leader) then
			if self:GetTarget() ~= leader then self:Follow(leader, true) end
		elseif self:GetTarget() then
			-- The option retains intent while native/local focus remains usable.
			self:Stop(true)
		end
	elseif self.automaticMode then
		self:Stop(true)
		self.automaticMode, self.automaticLeader = nil, nil
	end
	self.reconcilingAutomatic = nil
end
function Controller:Trace(event, questID)
	if self.adapter.trace then self.adapter.trace(event, questID or 0) end
end
function Controller:GetAcceptances(state, now)
	local accepted = self.acceptances
	if not accepted then return end
	if not now or not state.following or accepted.state ~= state or accepted.token ~= state.followToken then
		self.acceptances = nil
		return
	end
	for questID, at in pairs(accepted.quests) do
		-- A matching notification received while restricted remains eligible when
		-- sampling resumes. Unused tickets still expire; a later event cannot
		-- revive an old pickup. All fields here belong to this controller.
		local pending = state.checkExternal and self.trackingAt and now >= self.trackingAt
			and math.abs(self.trackingAt - at) <= ACCEPTANCE_SECONDS
		if now < at or (now - at > ACCEPTANCE_SECONDS and not pending) then
			accepted.quests[questID], accepted.count = nil, accepted.count - 1
			self:Trace("acceptance_expired", questID)
		end
	end
	if accepted.count == 0 then
		self.acceptances = nil
		return
	end
	return accepted
end
function Controller:GetTarget()
	local s = self.adapter.peek()
	if s and s.following then
		return s.following, s.followToken
	end
end
function Controller:Stop(force)
	if not force and self.adapter.automaticTarget then
		local governed = self.adapter.automaticTarget()
		if governed then
			if self.adapter.explainAutomatic then self.adapter.explainAutomatic() end
			return false
		end
	end
	self.choice = nil
	self.acceptances, self.trackingAt, self.trackingStartedAt = nil, nil, nil
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
	self.acceptances, self.trackingAt, self.trackingStartedAt = nil, nil, nil
end
function Controller:Resume()
	self.choice = nil
	self.acceptances, self.trackingAt, self.trackingStartedAt = nil, nil, nil
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
function Controller:Follow(name, automatic)
	local a = self.adapter
	if not automatic and a.automaticTarget and a.automaticTarget() then
		if a.explainAutomatic then a.explainAutomatic() end
		return false
	end
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
	self.acceptances, self.trackingAt, self.trackingStartedAt = nil, nil, nil
	s.following, s.attempt, s.expectedQuest = name, nil, a.currentQuest() or 0
	s.checkExternal, s.resuming, s.waiting, s.followToken = nil, nil, nil, {}
	a.save(name)
	a.publish()
	self:Apply()
	a.changed()
	return true
end
function Controller:Reconcile()
	self:ReconcileAutomatic()
	local a, s = self.adapter, self.adapter.peek()
	if not s or not s.following or a.loggingOut() then
		return
	end
	if not a.member(s.following) or a.ignored(s.following) or a.groupInvalid() then
		self:Stop(true)
	end
end
function Controller:Apply()
	self:ReconcileAutomatic()
	local a, s = self.adapter, self.adapter.peek()
	if not self:IsActive() or not s or not s.following then
		return
	end
	if not a.member(s.following) or a.ignored(s.following) or a.raid() or self:WouldCycle(s.following) then
		self:Stop(true)
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
					if a.onApplied then a.onApplied(peer.questID) end
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
function Controller:OnQuestAccepted(questID)
	local a, s = self.adapter, self.adapter.peek()
	questID = a.questID(questID)
	local now = a.now and a.now()
	if not self:IsActive() or not s or not s.following or a.loggingOut()
		or not questID or questID <= 0 or not now then return end
	if self.choice then self:Trace("acceptance_during_choice", questID); return end
	local accepted = self:GetAcceptances(s, now)
	if not accepted then
		accepted = { state = s, token = s.followToken, quests = {}, count = 0 }
		self.acceptances = accepted
	end
	-- Several quests may be accepted across frames while only one takes focus.
	-- Duplicate events cannot extend a ticket's lifetime.
	if not accepted.quests[questID] and accepted.count < 32 then
		accepted.quests[questID], accepted.count = now, accepted.count + 1
		self:Trace("accepted", questID)
	end
end
function Controller:OnTrackingChanged()
	local a, s = self.adapter, self.adapter.peek()
	if self:IsActive() and s and s.following and not s.applying and not s.resuming then
		self.trackingAt = a.now and a.now()
		if not s.checkExternal then self.trackingStartedAt = self.trackingAt end
		self:Trace("tracking_changed")
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
	if self:IsActive() and self:IsAutomaticLocked() then
		self.choice, self.acceptances = nil, nil
		s.checkExternal, s.resuming = nil, nil
		local peer = a.peer(s.following)
		if peer and native.questID ~= peer.questID then s.attempt = nil end
		return native
	end
	if self:IsActive() then
		if s.following and self.observedQuestID ~= native.questID then
			self.observedQuestID = native.questID
			self:Trace("native_observed", native.questID)
		end
		local now = a.now and a.now()
		local accepted = self:GetAcceptances(s, now)
		local acceptedAt = accepted and accepted.quests[native.questID]
		local recentAcceptance = acceptedAt and now >= acceptedAt and now - acceptedAt <= ACCEPTANCE_SECONDS
		local pendingAcceptance = acceptedAt and s.checkExternal and self.trackingAt
			and now >= self.trackingAt and math.abs(acceptedAt - self.trackingAt) <= ACCEPTANCE_SECONDS
		if acceptedAt and not self.choice and native.questID ~= s.expectedQuest and (recentAcceptance or pendingAcceptance) then
			-- An unchanged early sample must not consume this evidence. Once the
			-- accepted quest becomes readable, match it even if its notification
			-- was coalesced or arrived before that sample. Only this exact quest's
			-- ticket is consumed; other pickups keep their original deadlines.
			accepted.quests[native.questID], accepted.count = nil, accepted.count - 1
			if accepted.count == 0 then self.acceptances = nil end
			s.checkExternal, s.attempt = nil, nil
			self:Trace("acceptance_matched", native.questID)
			return native
		end
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
				if not self:Request(a.ownName(), native.questID, true) then self:Stop(true) end
				return native
			end
		end
		if s.resuming and native.questID >= 0 then
			s.expectedQuest, s.resuming = native.questID, nil
		end
		if s.checkExternal and native.questID >= 0 then
			if s.following and native.questID ~= s.expectedQuest and now and self.trackingStartedAt
				and now >= self.trackingStartedAt and now - self.trackingStartedAt < TRACKING_SETTLE_SECONDS then
				-- Do not show a manual-choice prompt before a synchronous acceptance
				-- callback has had a chance to identify this native transition.
				return nil
			end
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
					if not self:Request(a.ownName(), native.questID, true) then self:Stop(true) end
					return native
				end
				self:Stop(true)
			end
		end
	end
	return native
end
function Controller:Select(name, questID)
	self:ReconcileAutomatic()
	if self:IsAutomaticLocked() then return false end
	local a = self.adapter
	if not self:IsActive() or a.restricted() then
		return false
	end
	if name == a.ownName() then
		if questID ~= 0 and a.owns(questID) ~= true then
			return false
		end
		if (a.currentQuest() or 0) == questID then
			self:Stop(true)
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
			self:Stop(true)
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
	self:ReconcileAutomatic()
	if self:IsAutomaticLocked() then return false end
	local a = self.adapter
	if not self:IsActive() or a.blocked() then
		return false
	end
	self.acceptances = nil
	self:Trace(nativeOverride and "native_choice" or "explicit_choice", questID)
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
