-- QT supplies private stores, SavedVariables migration, and domain policies.
-- libchev owns the console, filters, commands, and test-result presentation.
local QuestTogether = _G.QuestTogether
local LibChev = QuestTogether.LibChev

function QuestTogether:NormalizeDebugLogStoreEntries(entries)
	entries = type(entries) == "table" and entries or {}
	local chars = 0
	for index = 1, #entries do
		local entry = entries[index]
		if type(entry) ~= "table" then
			entry = { text = LibChev.Text(entry, ""), category = self.DEBUG_DEFAULT_CATEGORY }
			entries[index] = entry
		else
			entry.text = LibChev.Text(entry.text, "")
			entry.category = LibChev.Category(entry.category, self.DEBUG_DEFAULT_CATEGORY)
		end
		chars = chars + #entry.text
	end
	self.debugLogTextLengthSum = chars
	self.debugLogStoreNormalized = true
	return entries
end

function QuestTogether:GetDebugLogStore()
	if type(self.debugLogLines) ~= "table" then
		self.debugLogLines = {}
		self.debugLogStoreNormalized = false
	end
	if not self.debugLogStoreNormalized then
		self:NormalizeDebugLogStoreEntries(self.debugLogLines)
	end
	return self.debugLogLines
end

function QuestTogether:GetDebugController()
	-- Private fixtures inherit addon methods, never the live controller/view.
	local existing = rawget(self, "debugController")
	if existing then
		return existing
	end
	local owner = self
	local controller = LibChev.NewDebugController({
		addonName = "QuestTogether",
		failureDetails = true,
		getLog = function()
			return {
				entries = owner:GetDebugLogStore(),
				chars = owner.debugLogTextLengthSum or 0,
				sequence = owner.diagnosticLogSequence or 0,
				dropped = owner.diagnosticDroppedLogLines or 0,
			}
		end,
		commitLog = function(store)
			owner.debugLogLines = store.entries
			owner.debugLogTextLengthSum = store.chars
			owner.diagnosticLogSequence = store.sequence
			owner.diagnosticDroppedLogLines = store.dropped
			owner.debugLogStoreNormalized = true
		end,
		limits = { maxLines = owner.DEBUG_LOG_MAX_LINES, maxChars = owner.DEBUG_LOG_MAX_CHARS },
		clock = function()
			return owner.API and type(owner.API.GetTime) == "function" and owner.API.GetTime() or nil
		end,
		getFilters = function()
			local settings = owner.db and owner.db.global
			return settings and settings.debugLogCategoryFilter or "ALL",
				settings and settings.debugLogSearchFilter or ""
		end,
		setFilters = function(category, search)
			if owner.db and owner.db.global then
				owner.db.global.debugLogCategoryFilter = category
				owner.db.global.debugLogSearchFilter = search
			end
		end,
		getTests = function()
			return owner.tests or {}
		end,
		testOptions = function()
			return owner:GetDebugTestOptions()
		end,
		beforeTests = function()
			if not owner.isInitialized then
				owner:OnInitialize()
			end
			local token = {
				isRunningTests = owner.isRunningTests,
				suppress = owner.suppressLocalAnnouncementDisplayDuringTests,
			}
			owner.isRunningTests = true
			owner.suppressLocalAnnouncementDisplayDuringTests = true
			return token
		end,
		afterTests = function(token)
			if token then
				owner.isRunningTests = token.isRunningTests
				owner.suppressLocalAnnouncementDisplayDuringTests = token.suppress
			end
		end,
		getVersion = function()
			return owner:GetAddonVersion()
		end,
		getEnvironment = function()
			return owner:GetDiagnosticEnvironment()
		end,
		buildReport = function(questId)
			return owner:BuildDiagnosticReport(questId)
		end,
		print = function(text)
			owner:Print(text)
		end,
		reload = function()
			if owner.API and type(owner.API.ReloadUI) == "function" then
				owner.API.ReloadUI()
			end
		end,
		ui = {
			parent = UIParent,
			createFrame = CreateFrame,
			restricted = function()
				return owner:IsRuntimeRestricted()
			end,
			canMutate = LibChev.CanMutateOwnedRegion,
		},
	})
	self.debugController = controller
	return controller
end

-- Keep domain call sites stable; generic behavior has a single shared owner.
local forwards = {
	ClearDebugLog = "ClearLog",
	ClearDebugWindow = "Clear",
	RemoveDebugLogEntriesByCategory = "RemoveCategory",
	IsDebugWindowShowingAllCategory = "IsShowingAll",
	DoesDebugLogCategoryHaveEntries = "HasCategory",
	GetDebugLogCategoryFilter = "GetCategory",
	SetDebugLogCategoryFilter = "SetCategory",
	GetDebugLogSearchFilter = "GetSearch",
	SetDebugLogSearchFilter = "SetSearch",
	GetDebugLogPrefixFilter = "GetSearch",
	SetDebugLogPrefixFilter = "SetSearch",
	GetDebugLogEntryDisplayText = "EntryText",
	GetDebugLogAvailableCategories = "GetCategories",
	ShouldIncludeDebugLogEntry = "Matches",
	GetFilteredDebugLogEntries = "GetEntries",
	GetDebugLogText = "GetText",
	GetDebugLogMetrics = "GetMetrics",
	BeginDebugLogBatchUpdate = "BeginBatch",
	EndDebugLogBatchUpdate = "EndBatch",
	RequestDebugLogWindowRefresh = "Refresh",
	RefreshCopyableWindow = "Refresh",
	ShowDebugWindow = "ShowLog",
}
for publicName, sharedName in pairs(forwards) do
	local method = sharedName
	QuestTogether[publicName] = function(self, ...)
		local controller = self:GetDebugController()
		return controller[method](controller, ...)
	end
end

function QuestTogether:NormalizeDebugCategory(category)
	return LibChev.Category(category, self.DEBUG_DEFAULT_CATEGORY)
end

function QuestTogether:Debug(message, category)
	self:GetDebugController():Append(message, category)
	return true
end

function QuestTogether:Debugf(category, formatString, ...)
	if formatString == nil then
		formatString, category = category, nil
	end
	if formatString == nil then
		return false
	end
	self:GetDebugController():Appendf(category, formatString, ...)
	return true
end

function QuestTogether:DebugState(category, label, value)
	self:GetDebugController():AppendState(category, label, value)
	return true
end

function QuestTogether:LogDebugLine(line, options)
	return self:GetDebugController():Append(line, type(options) == "table" and options.category or nil)
end

function QuestTogether:AppendDebugLogLine(line)
	return self:LogDebugLine(line)
end

function QuestTogether:AppendDebugLogLines(lines, options)
	self:BeginDebugLogBatchUpdate()
	for _, line in ipairs(lines or {}) do
		self:LogDebugLine(line, options)
	end
	self:EndDebugLogBatchUpdate()
end
