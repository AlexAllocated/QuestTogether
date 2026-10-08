local QuestTogether = _G.QuestTogether
local LibChev = QuestTogether.LibChev

QuestTogether.runtimeRestrictionTypes = QuestTogether.runtimeRestrictionTypes
	or {
		combat = true,
		encounter = true,
		challenge = true,
		pvp = true,
		map = true,
	}

if not QuestTogether.GetDeferredWorkStateStore then
	QuestTogether.deferredWorkState = QuestTogether.deferredWorkState or {
		generations = {},
		entries = {},
	}
end

QuestTogether.runtimeWorkDelayByClass = QuestTogether.runtimeWorkDelayByClass
	or {
		quest_log_drain = 0,
		task_area_refresh = 0.1,
		quest_snapshot_refresh = 1,
		nameplate_quest_refresh = 0,
		nameplate_refresh = 0,
		nameplate_tint_refresh = 0.05,
		nameplate_tooltip_resolve = 0,
		waypoint_mutation = 0.2,
	}

local function SafeText(value, fallback)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, fallback or "")
	end

	local ok, textValue = pcall(tostring, value)
	if ok then
		return textValue
	end

	return fallback or ""
end

function QuestTogether:IsRuntimeRestrictionTypeActive(restrictionType)
	local restrictionTypes = Enum and Enum.AddOnRestrictionType
	local restrictedActions = _G.C_RestrictedActions
	if not (restrictionTypes and restrictedActions and restrictedActions.GetAddOnRestrictionState) then
		return false
	end

	local restrictionEnum = nil
	local normalizedType = type(restrictionType) == "string" and string.lower(restrictionType) or nil
	if normalizedType == "combat" then
		restrictionEnum = restrictionTypes.Combat
	elseif normalizedType == "encounter" then
		restrictionEnum = restrictionTypes.Encounter
	elseif normalizedType == "challenge" then
		restrictionEnum = restrictionTypes.ChallengeMode
	elseif normalizedType == "pvp" then
		restrictionEnum = restrictionTypes.PvPMatch
	elseif normalizedType == "map" then
		restrictionEnum = restrictionTypes.Map
	elseif normalizedType == "chat" then
		restrictionEnum = restrictionTypes.Chat
	end

	if restrictionEnum == nil then
		return false
	end

	local ok, state = pcall(restrictedActions.GetAddOnRestrictionState, restrictionEnum)
	local numericState = ok and self:SafeToNumber(state) or nil
	-- Activating is dispatched before enforcement. Do not flush work into the
	-- boundary while it is being raised, or assume an unreadable state is safe.
	return numericState ~= 0
end

function QuestTogether:IsRuntimeRestricted()
	if self.API and self.API.InCombatLockdown and self.API.InCombatLockdown() then
		return true
	end

	for restrictionType in pairs(self.runtimeRestrictionTypes or {}) do
		if self:IsRuntimeRestrictionTypeActive(restrictionType) then
			return true
		end
	end

	return false
end

function QuestTogether:IsMapTooltipSensitiveStateActive()
	if not (self and self.API and type(self.API.IsWorldMapVisible) == "function") then
		return false
	end

	local ok, isVisible = pcall(self.API.IsWorldMapVisible)
	-- Unknown visibility is not permission to read map-sensitive tooltip data.
	if not ok or not self:CanAccessValue(isVisible) or type(isVisible) ~= "boolean" then
		return true
	end
	return isVisible
end

function QuestTogether:CreateMapWorkWakeFrame()
	-- No foreign parent, hooks, callback registry, or protected template. This
	-- frame observes visibility through the existing read-only API wrapper.
	return CreateFrame("Frame")
end

function QuestTogether:StopMapWorkWakeup()
	local frame = rawget(self, "mapWorkWakeFrame")
	if frame then
		frame:SetScript("OnUpdate", nil)
	end
	self.mapWorkWakeState = nil
end

function QuestTogether:EnsureMapWorkWakeup()
	if not self.isEnabled then
		return
	end
	local workState = self:GetDeferredWorkStateStore()
	if rawget(self, "mapWorkWakeState") == workState then
		return
	end
	local frame = rawget(self, "mapWorkWakeFrame")
	if not frame then
		frame = self:CreateMapWorkWakeFrame()
		self.mapWorkWakeFrame = frame
	end
	self.mapWorkWakeState = workState
	local elapsedSinceCheck = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		if rawget(self, "mapWorkWakeState") ~= workState then
			return
		end
		if not self.isEnabled or self:GetDeferredWorkStateStore() ~= workState or not next(workState.entries) then
			self:StopMapWorkWakeup()
			return
		end
		elapsedSinceCheck = elapsedSinceCheck + (self:SafeToNumber(elapsed) or 0)
		if elapsedSinceCheck < 0.2 then
			return
		end
		elapsedSinceCheck = 0
		if not self:IsMapTooltipSensitiveStateActive() then
			self:StopMapWorkWakeup()
			-- Every work class rechecks its own combat/encounter/frame policy.
			self:FlushDeferredWork("WORLD_MAP_CLOSED")
		end
	end)
end

function QuestTogether:IsWorkBlocked(workClass)
	if workClass == "waypoint_mutation" then
		return self:IsRuntimeRestricted()
	end

	if workClass == "foreign_frame_mutation" then
		return self:IsRuntimeRestricted()
	end

	if
		workClass == "nameplate_tooltip_resolve"
		or workClass == "nameplate_quest_refresh"
		or workClass == "nameplate_refresh"
		or workClass == "nameplate_tint_refresh"
	then
		if self:IsMapTooltipSensitiveStateActive() then
			return true
		end
		-- Ordinary open-world combat does not prohibit readable unit tooltip
		-- data or our unprotected overlays. Keep other restriction contexts
		-- blocked; each frame operation still checks its own protection state.
		for restrictionType in pairs(self.runtimeRestrictionTypes or {}) do
			if restrictionType ~= "combat" and self:IsRuntimeRestrictionTypeActive(restrictionType) then
				return true
			end
		end
		return false
	end

	if workClass == "quest_log_drain" or workClass == "task_area_refresh" or workClass == "quest_snapshot_refresh"
		or workClass == "quest_share" then
		if self:IsMapTooltipSensitiveStateActive() then
			return true
		end
		return self:IsRuntimeRestricted()
	end

	return self:IsRuntimeRestricted()
end

local function WorkPolicy(owner, options)
	options = options or {}
	local delay = owner.API and owner.API.Delay
	return {
		getState = function()
			return owner:GetDeferredWorkStateStore()
		end,
		enabled = function()
			return (not options.owner or options.owner.active ~= false)
				and (options.lifetime == "cleanup" or owner.isEnabled == true)
		end,
		blocked = function(workClass)
			local blocked = owner:IsWorkBlocked(workClass)
			if blocked and owner:IsMapTooltipSensitiveStateActive() then
				owner:EnsureMapWorkWakeup()
			end
			return blocked
		end,
		delay = type(delay) == "function" and delay or nil,
		defaultDelay = function(workClass)
			return owner.runtimeWorkDelayByClass[workClass] or 0
		end,
		invoke = function(workClass, key, reason, callback)
			local ok, err
			if owner.RunGuardedCallback then
				ok, err = owner:RunGuardedCallback("work:" .. workClass, callback)
			else
				ok, err = LibChev.GuardCall(callback)
			end
			if not ok then
				owner:Debugf(
					"runtime",
					"work_failed class=%s key=%s reason=%s error=%s",
					workClass,
					SafeText(key),
					SafeText(reason),
					SafeText(err)
				)
			end
		end,
	}
end

-- QT owns timing/lifetime policy; LibChev owns keyed coalescing and guarded
-- dispatch. A zero debounce is immediate; nextFrame always uses the timer seam.
function QuestTogether:NewRuntimeWorkOwner()
	return { active = true }
end

function QuestTogether:CancelRuntimeWorkOwner(owner)
	if not owner then return end
	owner.active = false
	local state = self:GetDeferredWorkStateStore()
	for key, entry in pairs(state.entries) do
		if entry.owner == owner then state.entries[key], state.generations[key] = nil, nil end
	end
end

function QuestTogether:IsRuntimeWorkPending(workClass, key)
	return self:GetDeferredWorkStateStore().entries[LibChev.WorkKey(workClass, key)] ~= nil
end

function QuestTogether:CancelRuntimeWork(workClass, key)
	local state = self:GetDeferredWorkStateStore()
	local workKey = LibChev.WorkKey(workClass, key)
	state.entries[workKey], state.generations[workKey] = nil, nil
end

function QuestTogether:ScheduleRuntimeWork(workClass, key, callback, options)
	options = options or {}
	if type(callback) ~= "function" or (options.owner and options.owner.active == false) then return false end
	local state = self:GetDeferredWorkStateStore()
	local workKey = LibChev.WorkKey(workClass, key)
	local mode = options.mode or "debounce"
	assert(mode == "immediate" or mode == "nextFrame" or mode == "bounded" or mode == "debounce", "invalid work mode")
	local pending = state.entries[workKey]
	if (mode == "bounded" or options.coalesce) and pending and pending.owner == options.owner then
		pending.reason = options.reason or pending.reason
		return true
	end
	local policy = WorkPolicy(self, options)
	local dispatch = function() return callback() end
	local delay = options.delay
	if mode == "nextFrame" then
		-- LibChev deliberately treats zero as inline. Select its timer branch
		-- while passing zero to the client timer (which runs on a later frame).
		local timer = self.API and self.API.Delay
		if type(timer) ~= "function" then return false end
		delay = 0.000001
		policy.delay = function(_, run) timer(0, run) end
	elseif mode == "immediate" then
		policy.allowImmediateWhenDisabled = options.allowImmediateWhenDisabled == true
		local ran = LibChev.RunOrDeferWork(policy, workClass, key, dispatch, delay, options.reason)
		local entry = state.entries[workKey]
		if entry and entry.callback == dispatch then entry.owner, entry.policy = options.owner, policy end
		return ran
	end
	local queued = LibChev.ScheduleWork(policy, workClass, key, dispatch, delay, options.reason)
	local entry = state.entries[workKey]
	if entry and entry.callback == dispatch then entry.owner, entry.policy = options.owner, policy end
	return queued
end

function QuestTogether:ScheduleDeferredWork(workClass, key, callback, delaySeconds, reason)
	return self:ScheduleRuntimeWork(workClass, key, callback, { delay = delaySeconds, reason = reason })
end

function QuestTogether:ScheduleBoundedRefreshWork(workClass, key, callback, delaySeconds, reason)
	return self:ScheduleRuntimeWork(workClass, key, callback, { mode = "bounded", delay = delaySeconds, reason = reason })
end

function QuestTogether:RunOrDeferWork(workClass, key, callback, delaySeconds, reason)
	return self:ScheduleRuntimeWork(workClass, key, callback, {
		mode = "immediate", delay = delaySeconds, reason = reason,
		allowImmediateWhenDisabled = workClass == "waypoint_mutation",
	})
end

function QuestTogether:FlushDeferredWork(reason)
	local state = self:GetDeferredWorkStateStore()
	local pending = {}
	for key, entry in pairs(state.entries) do pending[#pending + 1] = { key, entry } end
	for _, pair in ipairs(pending) do
		if self:GetDeferredWorkStateStore() ~= state then break end
		local key, entry = pair[1], pair[2]
		local policy = entry.policy or WorkPolicy(self)
		if state.entries[key] == entry and entry.delayElapsed and policy.enabled() and not policy.blocked(entry.workClass) then
			state.entries[key], state.generations[key] = nil, nil
			policy.invoke(entry.workClass, entry.key, reason or entry.reason, entry.callback)
		end
	end
	return self.isEnabled == true
end

function QuestTogether:ADDON_RESTRICTION_STATE_CHANGED()
	self:ScheduleAnnouncementChannelOrder()
	self:FlushDeferredWork("ADDON_RESTRICTION_STATE_CHANGED")
end

function QuestTogether:ScheduleQuestLogTaskDrain(reason)
	return self:ScheduleDeferredWork("quest_log_drain", "quest_log_drain", function()
		if self.DrainQueuedQuestLogTasks then
			self:DrainQueuedQuestLogTasks()
		end
	end, 0, reason or "quest_log_drain")
end

function QuestTogether:ScheduleTaskAreaRefreshWork(shouldAnnounce, delaySeconds, reason)
	if shouldAnnounce then
		self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", true)
	end

	return self:ScheduleDeferredWork("task_area_refresh", "task_area_refresh", function()
		local announce = self:GetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false) and true or false
		self:SetRuntimeFlag("pendingScheduledTaskAreaRefreshShouldAnnounce", false)
		if self.RefreshTaskAreaStates then
			self:RefreshTaskAreaStates(announce)
		end
	end, delaySeconds, reason or "task_area_refresh")
end

function QuestTogether:ScheduleQuestStateRefreshWork(reason, delaySeconds)
	return self:ScheduleBoundedRefreshWork("quest_snapshot_refresh", "quest_snapshot_refresh", function()
		self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
		if self.RebuildQuestSnapshotStore then
			local snapshot = self:RebuildQuestSnapshotStore()
			if self.ReconcileQuestTracking then self:ReconcileQuestTracking(snapshot) end
		end
		if self.RefreshNameplatesForQuestStateChange then
			self:RefreshNameplatesForQuestStateChange(reason)
		end
	end, delaySeconds, reason or "quest_snapshot_refresh")
end

function QuestTogether:ScheduleNameplatePresentationRefresh(reason, delaySeconds)
	return self:ScheduleDeferredWork("nameplate_refresh", "visible_nameplates", function()
		if self.RefreshVisibleNameplates then
			self:RefreshVisibleNameplates(reason)
		end
	end, delaySeconds, reason or "nameplate_refresh")
end

function QuestTogether:GetNameplateWorkOwner(unitToken)
	local state = self:GetNameplateStateStore()
	state.workOwnersByUnitToken = state.workOwnersByUnitToken or {}
	local owner = state.workOwnersByUnitToken[unitToken]
	if not owner or owner.active == false then
		owner = self:NewRuntimeWorkOwner()
		state.workOwnersByUnitToken[unitToken] = owner
	end
	return owner
end

function QuestTogether:RetireNameplateWork(unitToken)
	local state = self:GetNameplateStateStore()
	local owners = state.workOwnersByUnitToken
	if owners then self:CancelRuntimeWorkOwner(owners[unitToken]); owners[unitToken] = nil end
	state.identityGenerationByUnitToken[unitToken] = (state.identityGenerationByUnitToken[unitToken] or 0) + 1
end

function QuestTogether:ScheduleNameplateTooltipResolution(unitToken, unitGuid, delaySeconds, reason)
	if not self:IsNameplateUnitToken(unitToken) then
		return false
	end
	local resolvedUnitToken = unitToken
	if not self:CanAccessValue(unitGuid) or type(unitGuid) ~= "string" or unitGuid == "" then
		unitGuid = nil
	end
	local generations = self:GetNameplateStateStore().identityGenerationByUnitToken
	local generation = generations[unitToken]
	local workKey = resolvedUnitToken
	if unitGuid then
		workKey = unitGuid
	end

	return self:ScheduleRuntimeWork("nameplate_tooltip_resolve", workKey, function()
		if self:GetNameplateStateStore().identityGenerationByUnitToken ~= generations or generations[unitToken] ~= generation then
			return
		end
		if not self.ResolveNameplateQuestStateForUnitToken then
			return
		end
		self:ResolveNameplateQuestStateForUnitToken(resolvedUnitToken, unitGuid, reason)
	end, { mode = (not delaySeconds or delaySeconds == 0) and "nextFrame" or "debounce",
		delay = delaySeconds, owner = self:GetNameplateWorkOwner(unitToken), reason = reason or "nameplate_tooltip_resolve" })
end
