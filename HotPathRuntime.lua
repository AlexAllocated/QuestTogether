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

local function WorkPolicy(owner)
	local delay = owner.API and owner.API.Delay
	return {
		getState = function()
			return owner:GetDeferredWorkStateStore()
		end,
		enabled = function()
			return owner.isEnabled == true
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

function QuestTogether:ScheduleDeferredWork(workClass, key, callback, delaySeconds, reason)
	return LibChev.ScheduleWork(WorkPolicy(self), workClass, key, callback, delaySeconds, reason)
end

function QuestTogether:ScheduleBoundedRefreshWork(workClass, key, callback, delaySeconds, reason)
	local state = self:GetDeferredWorkStateStore()
	local pending = state.entries[LibChev.WorkKey(workClass, key)]
	if pending then
		-- Read current state when the original deadline arrives. Preserve the
		-- settling delay, but never push it out indefinitely during a burst.
		pending.reason = reason or pending.reason
		return true
	end
	return self:ScheduleDeferredWork(workClass, key, callback, delaySeconds, reason)
end

function QuestTogether:RunOrDeferWork(workClass, key, callback, delaySeconds, reason)
	local policy = WorkPolicy(self)
	-- Explicit clicks on existing waypoint links remain usable while QT is disabled.
	-- Background/deferred work still requires the enabled lifetime.
	policy.allowImmediateWhenDisabled = workClass == "waypoint_mutation"
	return LibChev.RunOrDeferWork(policy, workClass, key, callback, delaySeconds, reason)
end

function QuestTogether:FlushDeferredWork(reason)
	return LibChev.FlushWork(WorkPolicy(self), reason)
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

function QuestTogether:ScheduleNameplateTooltipResolution(unitToken, unitGuid, delaySeconds, reason)
	if not self:IsNameplateUnitToken(unitToken) then
		return false
	end
	local resolvedUnitToken = unitToken
	if not self:CanAccessValue(unitGuid) or type(unitGuid) ~= "string" or unitGuid == "" then
		unitGuid = nil
	end
	local generations = self.nameplateRefreshGenerationByUnitToken
	local generation = generations[unitToken]
	local workKey = resolvedUnitToken
	if unitGuid then
		workKey = unitGuid
	end

	return self:ScheduleDeferredWork("nameplate_tooltip_resolve", workKey, function()
		if self.nameplateRefreshGenerationByUnitToken ~= generations or generations[unitToken] ~= generation then
			return
		end
		if not self.ResolveNameplateQuestStateForUnitToken then
			return
		end
		self:ResolveNameplateQuestStateForUnitToken(resolvedUnitToken, unitGuid, reason)
	end, delaySeconds, reason or "nameplate_tooltip_resolve")
end
