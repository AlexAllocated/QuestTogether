-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Services = QuestTogether.NameplateServices
function QuestTogether:ForEachVisibleNamePlate(callback)
	if type(callback) ~= "function" or not (self.API and type(self.API.GetNamePlates) == "function") then
		return
	end

	local nameplates = self.API.GetNamePlates()
	if not self:CanAccessTable(nameplates) then
		return
	end

	for _, frame in pairs(nameplates) do
		if self:CanAccessForeignFrame(frame) then
			callback(frame)
		end
	end
end

function QuestTogether:FindVisiblePlayerNameplateForSender(senderGUID, senderName)
	if self.IsWorkBlocked and self:IsWorkBlocked("foreign_frame_mutation") then
		return nil
	end

	local normalizedSenderName = self:NormalizeMemberName(senderName)
	local matchedFrame = nil

	self:ForEachVisibleNamePlate(function(frame)
		if matchedFrame or not frame then
			return
		end
		local unitFrame, memberReadable = self:GetAccessibleFrameMember(frame, "UnitFrame")
		if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
			return
		end

		local unitToken = Services.Access.ResolveNameplateUnitToken(frame, unitFrame)
		if not unitToken or not self:IsNameplateUnitToken(unitToken) then
			return
		end
		if not self:IsNameplateUnitPlayer(unitToken) then
			return
		end

		local unitGUID = self:GetNameplateUnitGuid(unitToken)
		local fullUnitName = self:GetUnitFullName(unitToken)
		local normalizedUnitName = fullUnitName and self:NormalizeMemberName(fullUnitName) or nil

		if self:DoesResolvedUnitIdentityMatchSender(unitGUID, normalizedUnitName, senderGUID, normalizedSenderName) then
			matchedFrame = frame
			return
		end
	end)

	return matchedFrame
end

function QuestTogether:DoesResolvedUnitIdentityMatchSender(
	unitGUID,
	normalizedUnitName,
	senderGUID,
	normalizedSenderName
)
	local hasUnitGUID = type(unitGUID) == "string" and unitGUID ~= ""
	local hasSenderGUID = type(senderGUID) == "string" and senderGUID ~= ""

	-- If both sides expose a GUID, a mismatch is definitive. Falling back to the
	-- name here can attach an announcement to an unrelated recycled nameplate.
	if hasUnitGUID and hasSenderGUID and unitGUID ~= senderGUID then
		return false
	end

	if normalizedSenderName then
		return normalizedUnitName ~= nil and normalizedUnitName == normalizedSenderName
	end

	return hasUnitGUID and hasSenderGUID and unitGUID == senderGUID
end

function QuestTogether:DoesUnitTokenMatchSender(unitToken, senderGUID, senderName)
	if type(unitToken) ~= "string" or unitToken == "" then
		return false
	end
	if not self.API.UnitExists or not self.API.UnitExists(unitToken) then
		return false
	end
	if not self:IsNameplateUnitPlayer(unitToken) then
		return false
	end

	local unitGUID = nil
	if self.API.UnitGUID then
		local okGuid, guidValue = pcall(self.API.UnitGUID, unitToken)
		if okGuid and not self:IsSecretValue(guidValue) then
			unitGUID = guidValue
		end
	end
	local normalizedSenderName = self:NormalizeMemberName(senderName)

	local fullUnitName = self:GetUnitFullName(unitToken)

	local normalizedUnitName = fullUnitName and self:NormalizeMemberName(fullUnitName) or nil
	return self:DoesResolvedUnitIdentityMatchSender(unitGUID, normalizedUnitName, senderGUID, normalizedSenderName)
end

function QuestTogether:FindNearbyPlayerUnitTokenForSender(senderGUID, senderName)
	local candidateUnits = {
		"target",
		"mouseover",
		"focus",
	}

	for _, unitToken in ipairs(candidateUnits) do
		if self:DoesUnitTokenMatchSender(unitToken, senderGUID, senderName) then
			return unitToken
		end
	end

	return nil
end

function QuestTogether:RefreshNameplateAugmentation()
	self:MaybeAnnounceNameplateCapabilityContextChange()
	self:RefreshActiveAnnouncementBubbles()

	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self:ClearNameplateQuestDetectionCache()
		wipe(self:GetNameplateStateStore().questStateByUnitToken)
		wipe(self:GetNameplateStateStore().questGuidByUnitToken)
		self:ForEachVisibleNamePlate(function(frame)
			self:HideNameplateIcon(frame)
		end)
		return
	end

	self:ForEachVisibleNamePlate(function(frame)
		self:RefreshNameplateIcon(frame)
	end)
end

-- Mirrors Plater.UpdateAllPlates() (Plater.lua:6681-6692): refresh all visible plates
-- against the current quest cache without rebuilding quest-log title inputs.
function QuestTogether:RefreshVisibleNameplates(_reason)
	self:ClearNameplateResolvedQuestState()
	self:RefreshNameplateAugmentation()
	return true
end

function QuestTogether:RefreshNameplatesForQuestStateChange(_reason)
	self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
	self:RebuildNameplateQuestTextCache()
	self:ClearNameplateQuestDetectionCache()
	self:ClearNameplateResolvedQuestState()
	self:RefreshNameplateAugmentation()
	return true
end

function QuestTogether:InvalidateNameplateQuestState(reason)
	-- These are addon-owned caches. Retire stale positives immediately, even
	-- when rebuilding the quest log must wait for a restricted context to end.
	self:ClearNameplateQuestDetectionCache()
	self:ClearNameplateResolvedQuestState()
	self:ScheduleBoundedRefreshWork("nameplate_quest_refresh", "quest_relevance", function()
		-- This work class permits readable structured unit tooltips in ordinary
		-- combat. Map/encounter/PvP restrictions and per-frame guards still apply.
		-- Health events may have repopulated the cache before new quest tooltip
		-- lines arrived, so the delayed pass must discard that interim evidence.
		self:ClearNameplateQuestDetectionCache()
		self:RefreshVisibleNameplates(reason)
	end, Services.Access.QUEST_STATE_SETTLE_SECONDS, reason)
end

function QuestTogether:ScheduleDeferredNameplateQuestStateRefresh(reason, delaySeconds)
	self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", true)
	self:ScheduleQuestStateRefreshWork(reason, delaySeconds or Services.Access.QUEST_STATE_SETTLE_SECONDS)
end

function QuestTogether:ScheduleNameplateContextRefresh(reason, delaySeconds)
	if
		self:GetRuntimeFlag("nameplateQuestTextCacheSuppressed", false)
		and not self:IsNameplateAugmentationBlockedInCurrentContext()
	then
		-- Instance policy discarded the known quest text. Presentation alone
		-- cannot recover it, even with readable outdoor tooltips. Reuse the
		-- guarded snapshot work and coalesce world/zone events until it runs.
		if not self:GetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false) then
			self:ScheduleDeferredNameplateQuestStateRefresh(reason, delaySeconds)
		end
		return
	end
	self:ScheduleNameplatePresentationRefresh(reason, delaySeconds)
end

function QuestTogether:ScheduleFullNameplateRefresh(delaySeconds)
	self:ScheduleNameplatePresentationRefresh("ScheduleFullNameplateRefresh", delaySeconds)
end

function QuestTogether:OnNameplateAdded(unitToken)
	if not self.isEnabled then
		return
	end

	if not self:IsNameplateUnitToken(unitToken) then
		return
	end
	self:RetireNameplateWork(unitToken)
	self:GetNameplateStateStore().refreshGenerationByUnitToken[unitToken] = (
		self:GetNameplateStateStore().refreshGenerationByUnitToken[unitToken] or 0
	) + 1
	self:GetNameplateStateStore().refreshPendingByUnitToken[unitToken] = nil
	self:ClearNameplateTooltipResolveRetryCount(unitToken)
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		self:ForgetResolvedNameplateQuestState(unitToken)
		local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, false)
		if namePlateFrameBase then
			-- Nameplate frames are recycled across zone and instance transitions.
			-- In blocked contexts like arenas, clear any stale quest visuals immediately.
			self:HideNameplateIcon(namePlateFrameBase)
			self:HideAnnouncementBubble(namePlateFrameBase)
		end
		return
	end

	local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, false)

	self:ForgetResolvedNameplateQuestState(unitToken)

	if namePlateFrameBase then
		-- Nameplate frames are recycled. Clear any stale icon/tint immediately so visuals
		-- from a previous unit cannot carry over before the live refresh resolves.
		self:HideNameplateIcon(namePlateFrameBase)
		self:HideAnnouncementBubble(namePlateFrameBase)
		self:RefreshNameplateIcon(namePlateFrameBase)
		return
	end

	self:ScheduleNameplateRefresh(unitToken)
end

function QuestTogether:OnNameplateRemoved(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	self:ForgetResolvedNameplateQuestState(unitToken)
	self:ClearNameplateTooltipResolveRetryCount(unitToken)
	self:GetNameplateStateStore().refreshPendingByUnitToken[unitToken] = nil
	-- Never reuse a generation after a token is removed and assigned again.
	self:RetireNameplateWork(unitToken)
	self:GetNameplateStateStore().refreshGenerationByUnitToken[unitToken] = (
		self:GetNameplateStateStore().refreshGenerationByUnitToken[unitToken] or 0
	) + 1
	self:GetNameplateStateStore().healthTintRefreshPendingByUnitToken[unitToken] = nil

	local namePlateFrameBase = self.API and self.API.GetNamePlateForUnit and self.API.GetNamePlateForUnit(unitToken)
		or nil
	if namePlateFrameBase then
		self:HideNameplateIcon(namePlateFrameBase)
		self:HideAnnouncementBubble(namePlateFrameBase)
	end
	for icon, info in pairs(self.qtPlayerIconStateByFrame or {}) do
		if info.unitToken == unitToken then
			self:HideQTPlayerIcon(icon)
		end
	end
	-- The public lookup may already be empty by NAME_PLATE_UNIT_REMOVED.
	-- Find playback through addon-owned state, without reading the old frame.
	for bubble, state in pairs(self:GetNameplateStateStore().bubbleStateByFrame) do
		if state.unitToken == unitToken then
			self:StopAndHideAnnouncementBubblePlayback(bubble)
		end
	end
end

function QuestTogether:TryInstallNameplateHooks()
	if self.nameplateHooksInstalled then
		return
	end

	-- Avoid secure add/remove hooks into Blizzard's nameplate setup path. The one safe hook we
	-- do want is the global options-update pass, so we can reapply our quest visuals after
	-- Blizzard restyles all visible nameplates.
	if
		not self.nameplateOptionsHookInstalled
		and type(hooksecurefunc) == "function"
		and type(NamePlateDriverMixin) == "table"
		and type(NamePlateDriverMixin.UpdateNamePlateOptions) == "function"
	then
		hooksecurefunc(NamePlateDriverMixin, "UpdateNamePlateOptions", function()
			QuestTogether:ScheduleFullNameplateRefresh(0.05)
		end)
		self.nameplateOptionsHookInstalled = true
	end

	self.nameplateHooksInstalled = true
end

function QuestTogether:HandleNameplateEvent(eventName, ...)
	if self.pendingNameplateVisualCleanup then
		self:RetryPendingNameplateVisualCleanup()
	end
	if not self.isEnabled then
		return
	end
	if eventName == "NAME_PLATE_UNIT_ADDED" then
		self:OnNameplateAdded(...)
	elseif eventName == "NAME_PLATE_UNIT_REMOVED" then
		self:OnNameplateRemoved(...)
	elseif eventName == "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED" then
		local unitToken, isBehindCamera = ...
		if self:IsNameplateUnitToken(unitToken) and self:CanAccessValue(isBehindCamera) and isBehindCamera == false then
			self:ClearNameplateTooltipResolveRetryCount(unitToken)
			self:ScheduleNameplateRefresh(unitToken)
		end
	elseif eventName == "PLAYER_TARGET_CHANGED" then
		self:RefreshNameplateForUnitAlias("target")
	elseif eventName == "UNIT_NAME_UPDATE" then
		local unitToken = ...
		if self:IsNameplateUnitToken(unitToken) then
			self:ScheduleNameplateRefresh(unitToken)
		end
	elseif eventName == "UNIT_AURA" then
		local unitToken = ...
		if self:IsNameplateUnitToken(unitToken) and self:GetNameplatePlayerIconStyle() == "left" then
			-- Only existing player logos need this layout update. Do not turn
			-- every NPC aura tick into quest detection/tooltip work. Defer until
			-- Blizzard has laid out the buffs, and coalesce same-frame events.
			for _, info in pairs(self.qtPlayerIconStateByFrame or {}) do
				if info.unitToken == unitToken then
					if
						not self:IsRuntimeWorkPending("nameplate_refresh", unitToken)
						and self:IsNameplateUnitPlayer(unitToken)
					then
						self:ScheduleNameplateRefresh(unitToken)
					end
					break
				end
			end
		end
	elseif eventName == "UPDATE_MOUSEOVER_UNIT" then
		self:RefreshNameplateForUnitAlias("mouseover")
	elseif eventName == "PLAYER_ENTERING_WORLD" then
		self:ScheduleNameplateContextRefresh("PLAYER_ENTERING_WORLD", 1)
	elseif
		eventName == "ZONE_CHANGED_NEW_AREA"
		or eventName == "ZONE_CHANGED_INDOORS"
		or eventName == "ZONE_CHANGED"
	then
		self:ScheduleNameplateContextRefresh(eventName, 0)
	elseif eventName == "PLAYER_REGEN_DISABLED" or eventName == "PLAYER_REGEN_ENABLED" then
		if eventName == "PLAYER_REGEN_ENABLED" then
			self:TryInstallPersonalBubbleEditModeHooks()
		end
		self:ScheduleNameplatePresentationRefresh(eventName, 0)
	elseif
		eventName == "QUEST_LOG_UPDATE"
		or eventName == "QUEST_REMOVED"
		or eventName == "QUEST_ACCEPTED"
		or eventName == "QUEST_ACCEPT_CONFIRM"
		or eventName == "QUEST_COMPLETE"
		or eventName == "QUEST_POI_UPDATE"
		or eventName == "QUEST_QUERY_COMPLETE"
		or eventName == "QUEST_DETAIL"
		or eventName == "QUEST_FINISHED"
		or eventName == "QUEST_GREETING"
	then
		self:InvalidateNameplateQuestState(eventName)
		self:ScheduleQuestStateRefreshWork(eventName, Services.Access.QUEST_STATE_SETTLE_SECONDS)
	elseif eventName == "DISPLAY_SIZE_CHANGED" then
		self:ScheduleFullNameplateRefresh(0.05)
	elseif eventName == "CVAR_UPDATE" then
		local cvarName = ...
		if Services.Access.SafeFindPlain(string.lower(Services.Access.SafeText(cvarName, "")), "nameplate") then
			self:ScheduleFullNameplateRefresh(0.05)
		end
	elseif
		eventName == "UNIT_HEALTH"
		or eventName == "UNIT_MAXHEALTH"
		or eventName == "UNIT_CONNECTION"
		or eventName == "UNIT_THREAT_LIST_UPDATE"
		or eventName == "UNIT_THREAT_SITUATION_UPDATE"
		or eventName == "UNIT_FACTION"
		or eventName == "UNIT_FLAGS"
	then
		-- Combat threat styling can swap the live health-fill texture on Blizzard nameplates.
		-- Re-anchor our overlay on the same unit-token events so the tint survives combat.
		local unitToken = ...
		if self:IsNameplateUnitToken(unitToken) then
			self:HideTapDeniedNameplateVisuals(unitToken)
			if eventName == "UNIT_FACTION" or eventName == "UNIT_FLAGS" then
				-- Refresh both decorations when ownership changes, including when
				-- a previously denied tap becomes eligible again.
				self:ScheduleNameplateRefresh(unitToken)
			else
				self:ScheduleNameplateHealthTintRefresh(unitToken, nil, true)
			end
		end
	elseif eventName == "UNIT_QUEST_LOG_CHANGED" then
		self:InvalidateNameplateQuestState(eventName)
		self:ScheduleQuestStateRefreshWork(eventName, Services.Access.QUEST_STATE_SETTLE_SECONDS)
	end
end

function QuestTogether:EnableNameplateAugmentation()
	self:SetRuntimeFlag("nameplateQuestTextCacheSuppressed", false)
	if not self.nameplateEventFrame then
		self.nameplateEventFrame = CreateFrame("Frame")
		self.nameplateRegisteredEvents = self.nameplateRegisteredEvents or {}
		self.nameplateEventFrame:SetScript("OnEvent", function(_, eventName, ...)
			if self.RunGuardedCallback then
				local ok, err =
					self:RunGuardedCallback("nameplate:" .. eventName, self.HandleNameplateEvent, self, eventName, ...)
				if not ok and type(geterrorhandler) == "function" then
					geterrorhandler()(err)
				end
			else
				self:HandleNameplateEvent(eventName, ...)
			end
		end)
	end

	local function RegisterNameplateEvent(addon, eventName)
		-- Event availability differs by client build; keep registration best-effort.
		local ok = pcall(addon.nameplateEventFrame.RegisterEvent, addon.nameplateEventFrame, eventName)
		if ok then
			addon.nameplateRegisteredEvents[eventName] = true
		else
			addon.nameplateRegisteredEvents[eventName] = nil
		end
	end

	self:TryInstallNameplateHooks()
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_ADDED")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_REMOVED")
	RegisterNameplateEvent(self, "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED")
	RegisterNameplateEvent(self, "PLAYER_TARGET_CHANGED")
	RegisterNameplateEvent(self, "UPDATE_MOUSEOVER_UNIT")
	RegisterNameplateEvent(self, "QUEST_LOG_UPDATE")
	RegisterNameplateEvent(self, "QUEST_REMOVED")
	RegisterNameplateEvent(self, "QUEST_ACCEPTED")
	RegisterNameplateEvent(self, "QUEST_ACCEPT_CONFIRM")
	RegisterNameplateEvent(self, "QUEST_COMPLETE")
	RegisterNameplateEvent(self, "QUEST_POI_UPDATE")
	RegisterNameplateEvent(self, "QUEST_QUERY_COMPLETE")
	RegisterNameplateEvent(self, "QUEST_DETAIL")
	RegisterNameplateEvent(self, "QUEST_FINISHED")
	RegisterNameplateEvent(self, "QUEST_GREETING")
	RegisterNameplateEvent(self, "UNIT_QUEST_LOG_CHANGED")
	RegisterNameplateEvent(self, "UNIT_HEALTH")
	RegisterNameplateEvent(self, "UNIT_MAXHEALTH")
	RegisterNameplateEvent(self, "UNIT_CONNECTION")
	RegisterNameplateEvent(self, "UNIT_NAME_UPDATE")
	RegisterNameplateEvent(self, "UNIT_AURA")
	RegisterNameplateEvent(self, "UNIT_THREAT_LIST_UPDATE")
	RegisterNameplateEvent(self, "UNIT_THREAT_SITUATION_UPDATE")
	RegisterNameplateEvent(self, "UNIT_FACTION")
	RegisterNameplateEvent(self, "UNIT_FLAGS")
	RegisterNameplateEvent(self, "PLAYER_ENTERING_WORLD")
	RegisterNameplateEvent(self, "ZONE_CHANGED_NEW_AREA")
	RegisterNameplateEvent(self, "ZONE_CHANGED_INDOORS")
	RegisterNameplateEvent(self, "ZONE_CHANGED")
	RegisterNameplateEvent(self, "PLAYER_REGEN_DISABLED")
	RegisterNameplateEvent(self, "PLAYER_REGEN_ENABLED")
	RegisterNameplateEvent(self, "ADDON_RESTRICTION_STATE_CHANGED")
	RegisterNameplateEvent(self, "DISPLAY_SIZE_CHANGED")
	RegisterNameplateEvent(self, "CVAR_UPDATE")
	self:ScheduleDeferredNameplateQuestStateRefresh(
		"EnableNameplateAugmentation",
		Services.Access.QUEST_STATE_SETTLE_SECONDS
	)
end

function QuestTogether:QueueNameplateVisualCleanup(visual, kind)
	local state = self:GetNameplateStateStore()
	state.pendingVisualCleanupByFrame = state.pendingVisualCleanupByFrame or {}
	state.pendingVisualCleanupByFrame[visual] = kind
	self.pendingNameplateVisualCleanup = true
	self:QueueOwnedUICleanup(visual, function(region)
		if kind == "bubble" then
			return self:StopAndHideAnnouncementBubblePlayback(region, "teardown")
		end
		region:Hide()
	end, function()
		state.pendingVisualCleanupByFrame[visual] = nil
		self.pendingNameplateVisualCleanup = next(state.pendingVisualCleanupByFrame) ~= nil
	end, Services.Access.CanMutateFrame)
end

function QuestTogether:CancelNameplateVisualCleanup(visual)
	self:CancelOwnedUICleanup(visual)
	local state = self.runtimeStateStore and self.runtimeStateStore.nameplate
	local pending = state and state.pendingVisualCleanupByFrame
	if pending then
		pending[visual] = nil
		self.pendingNameplateVisualCleanup = next(pending) ~= nil
	end
end

function QuestTogether:RetryPendingNameplateVisualCleanup()
	self:FlushOwnedUICleanup()
	local pending = self:GetNameplateStateStore().pendingVisualCleanupByFrame
	self.pendingNameplateVisualCleanup = pending ~= nil and next(pending) ~= nil
	return not self.pendingNameplateVisualCleanup
end

function QuestTogether:HideAllNameplateVisuals()
	-- Capture the disabled lifetime once. Subsequent events retry only failed
	-- handles, so one quarantined frame cannot hide unrelated current visuals.
	for _, bubble in pairs(self:GetNameplateStateStore().bubbleByUnitFrame) do
		self:QueueNameplateVisualCleanup(bubble, "bubble")
	end
	for _, icon in pairs(self:GetNameplateStateStore().iconByUnitFrame) do
		self:QueueNameplateVisualCleanup(icon, "icon")
	end
	for _, overlay in pairs(self:GetNameplateStateStore().healthOverlayByUnitFrame) do
		for _, texture in pairs(overlay) do
			self:QueueNameplateVisualCleanup(texture, "texture")
		end
	end
	return self:RetryPendingNameplateVisualCleanup()
end

function QuestTogether:DisableNameplateAugmentation()
	self:SetRuntimeFlag("nameplateQuestTextCacheSuppressed", false)
	self.pendingNameplateVisualCleanup = not self:HideAllNameplateVisuals()
	self.qtPlayerIconStateByFrame = nil
	if self.pendingNameplateVisualCleanup then
		self:Debug("visual_cleanup deferred until restrictions end", "nameplate")
	end
	if not self.nameplateEventFrame then
		return
	end

	for eventName in pairs(self.nameplateRegisteredEvents or {}) do
		-- Unregister should never break disable flow if an event was already invalidated.
		pcall(self.nameplateEventFrame.UnregisterEvent, self.nameplateEventFrame, eventName)
	end
	if self.nameplateRegisteredEvents then
		wipe(self.nameplateRegisteredEvents)
	end
	-- Hide our icon overlays and clear cached quest objective state.
	self:ClearNameplateQuestDetectionCache()
	self:SetRuntimeFlag("pendingDeferredNameplateQuestStateRefresh", false)
	self:SetRuntimeFlag("deferredNameplateQuestStateRefreshGeneration", 0)
	self:ForEachVisibleNamePlate(function(frame)
		self:HideNameplateIcon(frame)
	end)
	if self.ResetNameplateStateStore then
		self:ResetNameplateStateStore()
	end
end
