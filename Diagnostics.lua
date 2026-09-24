-- Diagnostics read addon-owned snapshots. They never inspect live nameplates,
-- tooltip tables, or quest data to fill a report during a restricted state.
local QuestTogether = _G.QuestTogether

local function Count(entries)
	local count = 0
	for _ in pairs(entries or {}) do
		count = count + 1
	end
	return count
end

function QuestTogether:RunGuardedCallback(context, callback, ...)
	local arguments, count = { ... }, select("#", ...)
	local function Capture(err)
		local detail = self:SafeToString(err, "<inaccessible>")
		if type(debugstack) == "function" then
			local ok, stack = pcall(debugstack, 2, 12, 12)
			if ok then
				detail = detail .. "\n" .. self:SafeToString(stack, "<inaccessible>")
			end
		end
		self:RecordDiagnosticError(context, detail)
		return err
	end
	return xpcall(function()
		return callback((unpack or table.unpack)(arguments, 1, count))
	end, Capture)
end

function QuestTogether:GetDiagnosticEnvironment()
	local environment = {}
	if type(GetBuildInfo) == "function" then
		local ok, version, build, date, interface = pcall(GetBuildInfo)
		if ok then
			environment.version = self:SafeToString(version, "unknown")
			environment.build = self:SafeToString(build, "unknown")
			environment.interface = self:SafeToString(interface, "unknown")
		end
	end
	if type(GetLocale) == "function" then
		local ok, locale = pcall(GetLocale)
		if ok then
			environment.locale = self:SafeToString(locale, "unknown")
		end
	end
	return environment
end

function QuestTogether:BuildDiagnosticReport(questId)
	local environment = self:GetDiagnosticEnvironment()
	local runtime = self:EnsureRuntimeStateStore()
	local lines = {}
	local function Add(label, value)
		lines[#lines + 1] = label .. "=" .. self:SafeToString(value, "unknown")
	end
	Add("QuestTogether", self:GetAddonVersion())
	Add("client", environment.version)
	Add("build", environment.build)
	Add("interface", environment.interface)
	Add("locale", environment.locale)
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
	return table.concat(lines, "\n")
end

function QuestTogether:ShowDiagnostics(questId)
	local report = self:BuildDiagnosticReport(questId)
	self:ShowCopyableWindow({
		title = "QuestTogether Diagnostics",
		hint = "Copy this report and /qt dump when reporting a problem. Quest details use the existing cache.",
		text = report .. "\n\nRecent events:\n" .. self:GetDebugLogText("ALL", ""),
	})
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
