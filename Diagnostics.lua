-- Diagnostics read addon-owned snapshots. They never inspect live nameplates,
-- tooltip tables, or quest data to fill a report during a restricted state.
local QuestTogether = _G.QuestTogether
local LibChev = QuestTogether.LibChev

local function Count(entries)
	local count = 0
	for _ in pairs(entries or {}) do
		count = count + 1
	end
	return count
end

function QuestTogether:RunGuardedCallback(context, callback, ...)
	return LibChev.GuardCall(callback, function(detail)
		self:RecordDiagnosticError(context, detail)
	end, ...)
end

function QuestTogether:GetDiagnosticEnvironment()
	return LibChev.ReadEnvironment({ GetBuildInfo = GetBuildInfo, GetLocale = GetLocale })
end

function QuestTogether:BuildDiagnosticReport(questId)
	local environment = self:GetDiagnosticEnvironment()
	local runtime = self:EnsureRuntimeStateStore()
	local report = LibChev.DiagnosticReport("QuestTogether", self:GetAddonVersion(), environment)
	local function Add(label, value)
		report:Add(label, value)
	end
	Add("enabled", self.isEnabled == true)
	Add("leavingWorld", self.isLoggingOut == true)
	Add("profile", self.activeProfileKey)
	Add("runtimeRestricted", self:IsRuntimeRestricted())
	Add("mapVisible", self:IsMapTooltipSensitiveStateActive())
	for _, restriction in ipairs({ "combat", "encounter", "challenge", "pvp", "map", "chat" }) do
		Add("restriction." .. restriction, self:IsRuntimeRestrictionTypeActive(restriction))
	end
	for _, option in ipairs({
		"showChatBubbles",
		"hideMyOwnChatBubbles",
		"showChatLogs",
		"showProgressFor",
		"announceProgress",
		"chatLogDestination",
		"nameplateQuestIconEnabled",
		"nameplateQuestHealthColorEnabled",
	}) do
		Add("option." .. option, self:GetOption(option))
	end
	Add("snapshot.generation", runtime.questSnapshot.generation)
	Add("snapshot.quests", Count(runtime.questSnapshot.byQuestID))
	Add("snapshot.unreadableRow", runtime.questSnapshot.lastUnreadableRow or "none")
	Add("trackedQuests", Count(self:GetPlayerTracker()))
	Add("queuedQuestCallbacks", #(self.onQuestLogUpdate or {}))
	Add("pendingAcceptances", Count(self.pendingQuestAcceptances))
	Add("pendingRemovals", Count(self.pendingQuestRemovals))
	Add("retiredQuests", Count(self.retiredQuestIds))
	Add("worldAreas", Count(runtime.taskArea.worldByQuestID))
	Add("bonusAreas", Count(runtime.taskArea.bonusByQuestID))
	Add("activeBubbles", Count(runtime.nameplate.bubbleStateByFrame))
	Add("pendingVisualCleanup", self.pendingNameplateVisualCleanup == true)
	local pending = runtime.runtime.deferredWorkState.entries
	Add("deferredWork", Count(pending))
	local keys = {}
	for key in pairs(pending) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for index = 1, math.min(#keys, 20) do
		local entry = pending[keys[index]]
		Add("deferred." .. keys[index], entry.reason or "pending")
	end
	local comms = self.GetCommsDiagnostics and self:GetCommsDiagnostics() or {}
	for _, key in ipairs({
		"sentRoutes",
		"failedRoutes",
		"invalidMessages",
		"receivedMessages",
		"duplicateMessages",
		"acceptedAnnouncements",
		"suppressedAnnouncements",
		"lastFailure",
	}) do
		Add("comms." .. key, comms[key] or 0)
	end
	Add("log.lines", #self:GetDebugLogStore())
	Add("log.limit", self.DEBUG_LOG_MAX_LINES)
	Add("log.dropped", self.diagnosticDroppedLogLines or 0)
	Add("errors.count", self.diagnosticErrorCount or 0)
	Add("errors.last", self.diagnosticLastError or "none")
	local id = self:NormalizeQuestID(questId)
	if id then
		local tracked = self:GetPlayerTracker()[id]
		Add("quest.id", id)
		Add("quest.tracked", tracked ~= nil)
		Add("quest.retired", (self.retiredQuestIds and self.retiredQuestIds[id]) ~= nil)
		if tracked then
			Add("quest.title", tracked.title)
			Add("quest.complete", tracked.isComplete)
			Add("quest.ready", tracked.isReadyForTurnIn)
			for index = 1, 20 do
				if tracked.objectives and tracked.objectives[index] then
					Add("objective." .. index, tracked.objectives[index])
					Add("value." .. index, tracked.objectiveValues and tracked.objectiveValues[index])
				end
			end
		end
	end
	return report:Text()
end

function QuestTogether:BuildDiagnosticExport(questId)
	local report = self:BuildDiagnosticReport(questId)
	local heading = "\n\nRecent events (older entries may be omitted; /qt dump shows the full history):\n"
	-- The common copy window is bounded. Retain the newest events instead of
	-- filling its budget with the oldest lines and dropping the failure itself.
	local remaining = 32768 - #report - #heading
	if remaining <= 0 then
		return report
	end
	local entries, tail = self:GetDebugLogStore(), {}
	for index = #entries, 1, -1 do
		local text = self:GetDebugLogEntryDisplayText(entries[index])
		local cost = #text + (#tail > 0 and 1 or 0)
		if cost > remaining then
			break
		end
		tail[#tail + 1] = text
		remaining = remaining - cost
	end
	local lines = {}
	for index = #tail, 1, -1 do
		lines[#lines + 1] = tail[index]
	end
	return report .. heading .. table.concat(lines, "\n")
end

function QuestTogether:ShowDiagnostics(questId)
	local text = self:BuildDiagnosticExport(questId)
	if
		not LibChev.OpenReportWindow(self, text, {
			title = "QuestTogether Diagnostics",
			parent = UIParent,
			createFrame = CreateFrame,
			restricted = function()
				return self:IsRuntimeRestricted()
			end,
			canMutate = LibChev.CanMutateOwnedRegion,
		})
	then
		self:Print("Diagnostics window unavailable while restricted; /qt dump retains the event history.")
	end
end

function QuestTogether:RecordDiagnosticError(context, errorValue)
	local detail = self:SafeToString(errorValue, "<inaccessible>")
	self.diagnosticErrorCount = (self.diagnosticErrorCount or 0) + 1
	self.diagnosticLastError = self:SafeToString(context, "unknown") .. ": " .. string.sub(detail, 1, 1200)
	-- Keep repeated engine failures from burying the events leading up to them.
	if self.diagnosticErrorCount <= 5 or self.diagnosticErrorCount % 100 == 0 then
		self:Debug(self.diagnosticLastError, "ERROR")
	end
end

function QuestTogether:ADDON_ACTION_BLOCKED(event, addon, action)
	if not self:CanAccessValue(addon) or addon ~= self.addonName then
		return
	end
	self:RecordDiagnosticError(event, action)
end

QuestTogether.ADDON_ACTION_FORBIDDEN = QuestTogether.ADDON_ACTION_BLOCKED
