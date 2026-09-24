local QuestTogether = _G.QuestTogether

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

local function BuildDeferredWorkKey(workClass, key)
	return tostring(workClass or "work") .. "::" .. tostring(key or "global")
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
	elseif normalizedType == "chat" then
		restrictionEnum = restrictionTypes.Chat
	elseif normalizedType == "map" then
		restrictionEnum = restrictionTypes.Map
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
	return ok and isVisible and true or false
end

function QuestTogether:IsWorkBlocked(workClass)
	if workClass == "waypoint_mutation" then
		return self:IsRuntimeRestricted()
	end

	if workClass == "foreign_frame_mutation" then
		return self:IsRuntimeRestricted()
	end

	if workClass == "nameplate_tooltip_resolve" then
		if self:IsMapTooltipSensitiveStateActive() then
			return true
		end
		return self:IsRuntimeRestricted()
	end

	if workClass == "quest_log_drain" or workClass == "task_area_refresh" or workClass == "quest_snapshot_refresh" then
		if self:IsMapTooltipSensitiveStateActive() then
			return true
		end
		return self:IsRuntimeRestricted()
	end

	if
		workClass == "nameplate_quest_refresh"
		or workClass == "nameplate_refresh"
		or workClass == "nameplate_tint_refresh"
	then
		return self:IsRuntimeRestricted()
	end

	return self:IsRuntimeRestricted()
end

function QuestTogether:ScheduleDeferredWork(workClass, key, callback, delaySeconds, reason)
	if type(callback) ~= "function" then
		return false
	end

	local state = self:GetDeferredWorkStateStore()
	local workKey = BuildDeferredWorkKey(workClass, key)
	local generation = (state.generations[workKey] or 0) + 1
	state.generations[workKey] = generation

	local entry = {
		workClass = workClass,
		key = key,
		callback = callback,
		delaySeconds = delaySeconds,
		reason = reason,
		generation = generation,
	}
	state.entries[workKey] = entry

	local delayFn = self.API and self.API.Delay
	local hasDelayFn = type(delayFn) == "function"
	local scheduledDelay = delaySeconds
	if scheduledDelay == nil then
		scheduledDelay = self.runtimeWorkDelayByClass[workClass] or 0
	end

	local function runEntry()
		-- Timers retain the old store after disable/profile resets. Checking only
		-- its generation lets those callbacks run again after a later enable.
		if self:GetDeferredWorkStateStore() ~= state then
			return
		end
		local liveEntry = state.entries[workKey]
		if liveEntry ~= entry or liveEntry.generation ~= generation then
			return
		end
		if not self.isEnabled then
			return
		end
		if self:IsWorkBlocked(workClass) then
			-- Keep the latest entry parked until an explicit flush or later enqueue retries it.
			-- Immediate Delay stubs in tests would otherwise recurse indefinitely here.
			return
		end

		state.entries[workKey] = nil
		state.generations[workKey] = nil
		local ok, err
		if self.RunGuardedCallback then
			ok, err = self:RunGuardedCallback("work:" .. workClass, callback)
		else
			ok, err = pcall(callback)
		end
		if not ok then
			self:Debugf(
				"runtime",
				"work_failed class=%s key=%s reason=%s error=%s",
				workClass,
				SafeText(key),
				SafeText(reason),
				SafeText(err)
			)
		end
	end

	if not hasDelayFn or scheduledDelay <= 0 then
		runEntry()
		return true
	end

	delayFn(scheduledDelay, runEntry)
	return true
end

function QuestTogether:RunOrDeferWork(workClass, key, callback, delaySeconds, reason)
	if type(callback) ~= "function" then
		return false
	end

	if self:IsWorkBlocked(workClass) then
		self:ScheduleDeferredWork(workClass, key, callback, delaySeconds, reason)
		return false
	end

	-- Immediate work supersedes the same parked request too.
	local state = self:GetDeferredWorkStateStore()
	local workKey = BuildDeferredWorkKey(workClass, key)
	state.entries[workKey] = nil
	state.generations[workKey] = nil
	callback()
	return true
end

function QuestTogether:FlushDeferredWork(reason)
	local state = self:GetDeferredWorkStateStore()
	if not state or not self.isEnabled then
		return false
	end

	local pendingEntries = {}
	for workKey, entry in pairs(state.entries or {}) do
		pendingEntries[#pendingEntries + 1] = {
			workKey = workKey,
			entry = entry,
		}
	end

	for index = 1, #pendingEntries do
		local pending = pendingEntries[index]
		local workKey = pending and pending.workKey or nil
		local entry = pending and pending.entry or nil
		if self:GetDeferredWorkStateStore() ~= state then
			break
		end
		if state.entries[workKey] ~= entry then
			-- An earlier callback replaced or consumed this entry while flushing.
		elseif entry and type(entry.callback) == "function" then
			self:ScheduleDeferredWork(entry.workClass, entry.key, entry.callback, 0, reason or entry.reason)
		else
			state.entries[workKey] = nil
		end
	end

	return true
end

function QuestTogether:ADDON_RESTRICTION_STATE_CHANGED()
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
	return self:ScheduleDeferredWork("quest_snapshot_refresh", "quest_snapshot_refresh", function()
		self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
		if self.RebuildQuestSnapshotStore then
			self:RebuildQuestSnapshotStore()
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
	local resolvedUnitToken = type(unitToken) == "string" and unitToken or "unknown"
	local workKey = resolvedUnitToken
	if type(unitGuid) == "string" and unitGuid ~= "" then
		workKey = unitGuid
	end

	return self:ScheduleDeferredWork("nameplate_tooltip_resolve", workKey, function()
		if not self.ResolveNameplateQuestStateForUnitToken then
			return
		end
		self:ResolveNameplateQuestStateForUnitToken(resolvedUnitToken, unitGuid, reason)
	end, delaySeconds, reason or "nameplate_tooltip_resolve")
end
