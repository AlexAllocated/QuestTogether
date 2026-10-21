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

function QuestTogether:BuildDiagnosticReport(questId, extraFields)
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
	Add("comms.trafficSeconds", math.max(0, (comms.trafficObservedAt or 0) - (comms.trafficStartedAt or 0)))
	local trafficCommands = {}
	for command in pairs(comms.traffic or {}) do
		trafficCommands[#trafficCommands + 1] = command
	end
	table.sort(trafficCommands)
	for _, command in ipairs(trafficCommands) do
		local bucket = comms.traffic[command]
		for _, key in ipairs({
			"queued",
			"queuedBytes",
			"sent",
			"sentBytes",
			"failed",
			"failedBytes",
			"throttled",
			"received",
			"receivedBytes",
			"duplicate",
			"duplicateBytes",
		}) do
			Add("comms.traffic." .. command .. "." .. key, bucket[key] or 0)
		end
	end
	for _, key in ipairs({ "announcementAgeSamples", "announcementAgeUnknown" }) do
		Add("comms." .. key, comms[key] or 0)
	end
	for _, key in ipairs({ "announcementAgeLast", "announcementAgeMax" }) do
		Add("comms." .. key, comms[key] or "unknown")
	end
	Add(
		"comms.announcementAgeMean",
		(comms.announcementAgeSamples or 0) > 0 and comms.announcementAgeTotal / comms.announcementAgeSamples
			or "unknown"
	)
	for _, group in ipairs({
		{ "transport", self:GetTransportMetrics() },
		{ "communication", self:GetCommunicationMetrics() },
		{ "transfer", self:GetCommTransferMetrics() },
		{ "authentication", self:GetDeveloperCommunicationMetrics() },
		{ "developerAnnouncements", self:GetDeveloperAnnouncementMetrics() },
		{ "vip", self:GetVIPCommunicationMetrics() },
	}) do
		for key, value in pairs(group[2] or {}) do
			if type(value) == "number" or type(value) == "string" then
				Add("comms." .. group[1] .. "." .. key, value)
			end
		end
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
	for _, field in ipairs(extraFields or {}) do
		Add(field[1], field[2])
	end
	return report:Text()
end

function QuestTogether:BuildDiagnosticExport(questId)
	return self:GetDebugController():BuildDiagnosticExport(questId)
end

function QuestTogether:ShowDiagnostics(questId)
	return self:GetDebugController():ShowDiagnostics(questId)
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

-- Opt-in, local-only capture of the QT note editor's native caret. Never read
-- note text, player identity, font-string text, or unrelated/native UI trees.
local CURSOR_CAPTURE_SECONDS, CURSOR_SAMPLE_INTERVAL = 3, 0.2
local CURSOR_SAMPLE_LIMIT, CURSOR_REPORT_LIMIT = 16, 16384
local CURSOR_COUNTERS = {
	"cursorEvents", "textEvents", "layoutCalls", "boxHeightWrites", "scrollRectWrites", "scrollWrites",
	"cursorX", "cursorY", "cursorW", "cursorH",
}

local function CursorValue(addon, value)
	if not addon:CanAccessValue(value) then return "inaccessible" end
	local kind = type(value)
	if kind == "number" then
		local number = addon:SafeToNumber(value)
		return number and string.format("%.3f", number) or "invalid"
	elseif kind == "boolean" then
		return value and "true" or "false"
	elseif kind == "string" then
		return (value:sub(1, 120):gsub("[%c]", " "))
	end
	return kind == "nil" and "nil" or "unavailable"
end

local function CursorMethod(addon, region, method)
	if not LibChev.CanMutateOwnedRegion(region) then return nil end
	local ok, callback = pcall(function() return region[method] end)
	if ok and addon:CanAccessValue(callback) and type(callback) == "function" then return callback end
end

local function CursorRead(addon, region, method)
	local callback = CursorMethod(addon, region, method)
	if not callback then return "unavailable" end
	-- Fixed return slots bound work and retained data even for unexpected APIs.
	local ok, first, second, third, fourth = pcall(callback, region)
	if not ok then return "error" end
	local values = {
		CursorValue(addon, first), CursorValue(addon, second), CursorValue(addon, third), CursorValue(addon, fourth),
	}
	while #values > 1 and values[#values] == "nil" do values[#values] = nil end
	return table.concat(values, ",")
end

local function CursorRegionLine(addon, region, label, extra)
	local fields = { label }
	for _, pair in ipairs({
		{ "shown", "IsShown" }, { "visible", "IsVisible" }, { "alpha", "GetAlpha" },
		{ "effectiveAlpha", "GetEffectiveAlpha" }, { "rect", "GetRect" },
		{ "size", "GetSize" }, { "points", "GetNumPoints" }, { "layer", "GetDrawLayer" },
		{ "effectiveFlatten", "GetEffectivelyFlattensRenderLayers" },
	}) do
		fields[#fields + 1] = pair[1] .. "=" .. CursorRead(addon, region, pair[2])
	end
	for _, pair in ipairs(extra or {}) do
		fields[#fields + 1] = pair[1] .. "=" .. CursorRead(addon, region, pair[2])
	end
	return table.concat(fields, " ")
end

local function CursorSnapshot(addon, probe)
	local frame, lines = probe.window, {}
	lines[#lines + 1] = CursorRegionLine(addon, frame.box, "box", {
		{ "focus", "HasFocus" }, { "blink", "GetBlinkSpeed" }, { "font", "GetFont" },
		{ "insets", "GetTextInsets" }, { "height", "GetHeight" }, { "lines", "GetNumLines" },
		{ "cursor", "GetCursorPosition" }, { "textColor", "GetTextColor" },
	})
	lines[#lines + 1] = CursorRegionLine(addon, frame.scroll, "scroll", {
		{ "height", "GetHeight" }, { "offset", "GetVerticalScroll" }, { "range", "GetVerticalScrollRange" },
	})
	lines[#lines + 1] = CursorRegionLine(addon, frame, "dialog", {
		{ "ignoreParentAlpha", "IsIgnoringParentAlpha" }, { "topLevel", "IsToplevel" },
		{ "scale", "GetScale" }, { "effectiveScale", "GetEffectiveScale" },
		{ "flattenRenderLayers", "GetFlattensRenderLayers" },
	})
	local callback = CursorMethod(addon, frame.box, "GetRegions")
	if callback then
		local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(callback, frame.box)
		if ok then
			local regions = { r1, r2, r3, r4, r5, r6, r7, r8 }
			for index = 1, 8 do
				local region = regions[index]
				if addon:CanAccessValue(region) and region and CursorRead(addon, region, "GetObjectType") == "Texture" then
					lines[#lines + 1] = CursorRegionLine(addon, region, "texture." .. index, {
						{ "texture", "GetTexture" }, { "color", "GetVertexColor" },
					})
				end
			end
		else
			lines[#lines + 1] = "regions=error"
		end
	else
		lines[#lines + 1] = "regions=unavailable"
	end
	return lines
end

local function CursorCounters(addon, probe)
	local counters = { "counters" }
	for index, key in ipairs(CURSOR_COUNTERS) do
		local value = probe.counters[key]
		if index <= 6 and value == nil then value = 0 end
		counters[#counters + 1] = key .. "=" .. CursorValue(addon, value)
	end
	return table.concat(counters, " ")
end

function QuestTogether:CancelPlayerNoteCursorDiagnostics()
	local probe = rawget(self, "playerNoteCursorProbe")
	if not probe then return end
	self.playerNoteCursorProbe = nil
	if probe.window.noteCursorProbeCounters == probe.counters then
		probe.window.noteCursorProbeCounters = nil
	end
	-- This parentless observer is QT-owned and unprotected. Teardown must work
	-- after the editor hides or the runtime enters a restricted state.
	if probe.driver and LibChev.CanMutateOwnedRegion(probe.driver) then probe.driver:SetScript("OnUpdate", nil) end
end

local function CursorProbeCurrent(addon, probe)
	return rawget(addon, "playerNoteCursorProbe") == probe
		and rawget(addon, "playerNoteWindow") == probe.window
		and addon.isEnabled == true and addon.isLoggingOut ~= true
		and not addon:IsWorkBlocked("foreign_frame_mutation")
		and probe.window.noteSession == probe.session
		and LibChev.CanMutateOwnedRegion(probe.window)
		and LibChev.CanMutateOwnedRegion(probe.window.box)
		and LibChev.CanMutateOwnedRegion(probe.window.scroll)
		and CursorRead(addon, probe.window, "IsVisible") == "true"
		and CursorRead(addon, probe.window.box, "IsVisible") == "true"
end

local function CursorAddLine(probe, text)
	local remaining = CURSOR_REPORT_LIMIT - probe.bytes
	if remaining <= 1 then probe.truncated = true; return end
	if #text + 1 > remaining then
		probe.truncated = true
		text = text:sub(1, remaining - 1)
	end
	probe.lines[#probe.lines + 1] = text
	probe.bytes = probe.bytes + #text + 1
end

local function CursorSample(addon, probe)
	if probe.samples >= CURSOR_SAMPLE_LIMIT then return end
	probe.samples = probe.samples + 1
	local snapshot, previous, nextLines, changed = CursorSnapshot(addon, probe), probe.lastLines or {}, {}, {}
	snapshot[#snapshot + 1] = CursorCounters(addon, probe)
	for _, line in ipairs(snapshot) do
		local key = line:match("^([%w%.]+)")
		nextLines[key] = line
		if line ~= previous[key] then changed[#changed + 1] = line end
	end
	local removed = {}
	for key in pairs(previous) do
		if not nextLines[key] then removed[#removed + 1] = key end
	end
	table.sort(removed)
	for _, key in ipairs(removed) do changed[#changed + 1] = key .. "=not returned" end
	if #changed > 0 then
		probe.changes = probe.changes + 1
		CursorAddLine(probe, string.format("sample=%d elapsed=%.3f\n%s", probe.samples, probe.elapsed, table.concat(changed, "\n")))
	end
	probe.lastLines = nextLines
end

function QuestTogether:CapturePlayerNoteCursorDiagnostics()
	self:CancelPlayerNoteCursorDiagnostics()
	local frame = rawget(self, "playerNoteWindow")
	if not frame or not frame.noteSession then return false, "Open a private player note first." end
	local probe = {
		window = frame, session = frame.noteSession, counters = {}, elapsed = 0, nextSample = CURSOR_SAMPLE_INTERVAL,
		samples = 0, changes = 0, bytes = 0, lines = {},
	}
	self.playerNoteCursorProbe = probe
	if not CursorProbeCurrent(self, probe) then self:CancelPlayerNoteCursorDiagnostics(); return false, "Note editor unavailable." end
	local driver = rawget(self, "playerNoteCursorProbeDriver")
	if not driver then
		driver = self:CreateOwnedUICleanupFrame()
		self.playerNoteCursorProbeDriver = driver
	end
	probe.driver = driver
	if not LibChev.CanMutateOwnedRegion(driver) then self:CancelPlayerNoteCursorDiagnostics(); return false, "Capture unavailable." end
	frame.noteCursorProbeCounters = probe.counters
	CursorAddLine(probe, "QuestTogether note cursor capture schema=1; local only; no note content or player identity")
	CursorAddLine(probe, "version=" .. CursorValue(self, self:GetAddonVersion()))
	local environment = self:GetDiagnosticEnvironment()
	for _, key in ipairs({ "version", "build", "interface", "locale" }) do
		CursorAddLine(probe, "client." .. key .. "=" .. CursorValue(self, environment[key]))
	end
	driver:SetScript("OnUpdate", function(_, elapsed)
		if not CursorProbeCurrent(self, probe) then
			if rawget(self, "playerNoteCursorProbe") == probe then self:CancelPlayerNoteCursorDiagnostics() end
			return
		end
		if not probe.started then
			-- Let slash-command cleanup finish before restoring focus once.
			-- All later samples observe without touching caret or layout.
			local focus = CursorMethod(self, frame.box, "SetFocus")
			if not focus or not pcall(focus, frame.box) then self:CancelPlayerNoteCursorDiagnostics(); return end
			probe.started = true
			CursorSample(self, probe)
			return
		end
		elapsed = self:SafeToNumber(elapsed)
		if not elapsed or elapsed < 0 then self:CancelPlayerNoteCursorDiagnostics(); return end
		probe.elapsed = probe.elapsed + elapsed
		if probe.elapsed + 0.000001 >= probe.nextSample then
			CursorSample(self, probe)
			probe.nextSample = probe.elapsed + CURSOR_SAMPLE_INTERVAL
		end
		if probe.elapsed + 0.000001 >= CURSOR_CAPTURE_SECONDS then
			local summary = string.format("\ncomplete samples=%d changes=%d truncated=%s\n%s", probe.samples, probe.changes, tostring(probe.truncated == true), CursorCounters(self, probe))
			local report = table.concat(probe.lines, "\n"):sub(1, CURSOR_REPORT_LIMIT - #summary) .. summary
			self:CancelPlayerNoteCursorDiagnostics()
			self:GetDebugController():ShowReport(report, "Note cursor diagnostics")
		end
	end)
	return true
end
