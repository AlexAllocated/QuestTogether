-- Private/addon-owned locale data only; never replaces GetLocale or other globals.
local QT = _G.QuestTogether
QT:RegisterTest("localization falls back and preserves separate Spanish locales without changing the client", function()
	local translate = QT.TranslateForLocale
	assert(translate("Settings", "xxXX") == "Settings")
	assert(translate("not in any dictionary", "deDE") == "not in any dictionary")
	assert(QT.localizations.esMX ~= QT.localizations.esES)
	assert(translate("Settings", "esMX") == QT.localizations.esMX["Settings"])
	assert(translate("Settings", "enGB") == "Settings")
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		assert(translate("Settings", locale) ~= "Settings")
		assert(type(translate("Settings", locale)) == "string")
	end
end)
QT:RegisterTest("localization keeps quest status and sharing model values language independent", function()
	local previous = QT.localizationTestLocale
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		QT.localizationTestLocale = locale
		assert(QT:GetQuestCompareShareableToYouLabel(true) == "Yes")
		assert(QT:GetQuestCompareShareableToYouLabel(false) == "No")
		assert(QT:GetQuestCompareRemoteStatusLabel(true) == "Complete")
		assert(QT:GetChatLogDestinationLabel("main") == QT.TranslateForLocale("Main Chat Window", locale))
		local a = setmetatable({
			GetQuestStatusLabel = function()
				return "Ready to Turn In"
			end,
		}, { __index = QT })
		assert(a:GetQuestStatusAnnouncementEventType(1) == "QUEST_READY_TO_TURN_IN")
	end
	QT.localizationTestLocale = previous
end)
QT:RegisterTest("localized patch notes preserve released version and section structure", function()
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		local notes = QT.releaseNotesByLocale[locale]
		assert(notes.version == QT.releaseNotes.version)
		assert(notes.welcome ~= QT.releaseNotes.welcome)
		assert(#notes.sections == #QT.releaseNotes.sections)
		for i, section in ipairs(notes.sections) do
			assert(#section.items == #QT.releaseNotes.sections[i].items)
			assert(section.illustration == QT.releaseNotes.sections[i].illustration)
		end
	end
end)

QT:RegisterTest("Latin American Spanish keeps its native locale in events and patch notes", function()
	local a = setmetatable({
		localizationTestLocale = "esMX",
		releaseNotes = QT.releaseNotes,
		releaseNotesByLocale = QT.releaseNotesByLocale,
		GetAddonVersion = function()
			return QT.releaseNotes.version
		end,
	}, { __index = QT })
	assert(a:GetEventLocale() == "esMX")
	local facts = a:BuildAnnouncementFacts("QUEST_ACCEPTED")
	local packet = a:EncodeAnnouncementPayload({
		eventType = "QUEST_ACCEPTED",
		senderName = "Friend-Realm",
		questId = "12345",
		text = QT.TranslateForLocale("Quest Accepted: ", "esMX") .. "Una misión",
		eventFacts = facts,
	})
	local received = assert(a:DecodeAnnouncementPayload(packet))
	assert(a:DecodeAnnouncementFacts(received.eventFacts).locale == "esMX")
	assert(a:GetCurrentReleaseNotes() == QT.releaseNotesByLocale.esMX)
	assert(a:GetCurrentReleaseNotes() ~= QT.releaseNotesByLocale.esES)
	a.localizationTestLocale = "enUS"
	function a:GetLocalizedQuestTitle()
		return nil
	end
	assert(a:LocalizeAnnouncementEvent(received) == "Quest Accepted: Una misión")
	function a:GetLocalizedQuestTitle()
		return "A quest"
	end
	assert(a:LocalizeAnnouncementEvent(received) == "Quest Accepted: A quest")
end)

-- These cases run in the selected client locale, not the English behavior-test
-- policy. CI runs them in every supported locale; /qt test uses the live locale.
local function ClientLocale()
	assert(QT.localizationTestLocale == nil, "presentation tests must retain the client locale")
	return QT:GetEventLocale()
end

QT:RegisterTest("client locale translates automatic warnings and capability notices", function()
	local locale = ClientLocale()
	local function T(key) return QT.TranslateForLocale(key, locale) end
	local output = {}
	QT.PrintChatLogRaw = function(_, text) output[#output + 1] = text end
	QT.GetDefaultAnnouncementIconChatTag = function() return "" end
	QT:PrintChatLogWarningMessage(T("Quest status unavailable."))
	QT:PrintChatLogInfoMessage(T("Full QuestTogether functionality is available again."))
	assert(output[1] == "|cffff8800" .. T("Warning:") .. "|r |cffffd200" .. T("Quest status unavailable.") .. "|r")
	assert(output[2] == "|cff33ff99" .. T("Info:") .. "|r |cffffd200" .. T("Full QuestTogether functionality is available again.") .. "|r")
	QT.isEnabled = true
	QT.GetOption = function(_, key) return key == "nameplateQuestIconEnabled" end
	QT.IsNameplateAugmentationBlockedInCurrentContext = function() return true end
	local report = QT:GetNameplateCapabilityNoticeReport()
	assert(report.lines[1] == "|cffffd200" .. T("Quest Plates") .. ": |r|cffff4444" .. T("unavailable") .. "|r")
	QT.IsNameplateAugmentationBlockedInCurrentContext = function() return false end
	report = QT:GetNameplateCapabilityNoticeReport()
	assert(report.lines[1] == "|cffffd200" .. T("Quest Plates") .. ": |r|cff33ff99" .. T("available") .. "|r")
end, { locale = "client" })

QT:RegisterTest("client locale renders event classes and locally resolved quest tooltips", function()
	local locale = ClientLocale()
	local function T(key) return QT.TranslateForLocale(key, locale) end
	local sourceLocale = locale == "deDE" and "frFR" or "deDE"
	QT.API.GetLocalizedQuestTitle = function() return "Native title " .. locale end
	QT.GetQuestSnapshot = function() return nil end
	QT.GetQuestStatusLabel = function() return "Not Started" end
	QT.GetQuestShareableStatusLabel = function() return "Unknown" end
	for _, row in ipairs({
		{ "QUEST_ACCEPTED", "Quest Accepted: " }, { "QUEST_REMOVED", "Quest Removed: " },
		{ "QUEST_COMPLETED", "Quest Completed: " }, { "QUEST_READY_TO_TURN_IN", "Ready to Turn In: " },
		{ "WORLD_QUEST_ENTERED", "World Quest Entered: " }, { "WORLD_QUEST_LEFT", "Left World Quest: " },
		{ "WORLD_QUEST_COMPLETED", "World Quest Completed: " },
		{ "BONUS_OBJECTIVE_ENTERED", "Bonus Objective Entered: " }, { "BONUS_OBJECTIVE_LEFT", "Left Bonus Objective: " },
		{ "BONUS_OBJECTIVE_COMPLETED", "Bonus Objective Completed: " },
	}) do
		local event = { eventType = row[1], questId = 12345, text = "Sent title", eventFacts = "1:" .. sourceLocale .. ":q:::" }
		assert(QT:LocalizeAnnouncementEvent(event) == T(row[2]) .. "Native title " .. locale)
		assert(event.text == "Sent title")
	end
	for _, kind in ipairs({ "QUEST_PROGRESS", "WORLD_QUEST_PROGRESS", "BONUS_OBJECTIVE_PROGRESS" }) do
		local event = { eventType = kind, questId = 12345, text = "Source progress", eventFacts = "1:" .. sourceLocale .. ":c:2:3:8" }
		assert(QT:LocalizeAnnouncementEvent(event) == "Native title " .. locale .. " — " .. string.format(T("Objective %d: %d/%d"), 2, 3, 8))
	end
	assert(QT:LocalizeAnnouncementEvent({ eventType = "SCAN_STATUS", text = "Source count", eventFacts = "1:" .. sourceLocale .. ":s::17:" }) == string.format(T("Quests monitored by QuestTogether: %d"), 17))
	assert(QT:LocalizeAnnouncementEvent({ eventType = "PLAYER_LEVEL_UP", text = "Source level", eventFacts = "1:" .. sourceLocale .. ":l::13:" }) == T("Level ") .. "13")
	assert(QT:LocalizeAnnouncementEvent({ eventType = "LOOKING_FOR_QUEST_PARTNERS" }) == T("Looking for questing partners") .. " :)")
	local row = QT:GetChatLogQuestTooltipRow(12345, "[Sent title]")
	assert(row.name == "Native title " .. locale)
	assert(row.questText:find(T("Your quest status") .. ": " .. T("Not Started"), 1, true))
	assert(row.questText:find(T("Shareable") .. ": " .. T("Unknown"), 1, true))
end, { locale = "client" })

QT:RegisterTest("client locale renders minimap menus tooltip and settings status", function()
	local locale = ClientLocale()
	local function T(key) return QT.TranslateForLocale(key, locale) end
	QT.isEnabled = true
	QT.GetAddonVersion = function() return "6.1.2" end
	QT.GetAvailableAddonUpdate = function() return nil end
	QT.db.profile.qtChatScope = "zone_only"
	local root = { labels = {} }
	function root:CreateButton(label)
		self.labels[#self.labels + 1] = label
		return { SetEnabled = function() end }
	end
	root.CreateCheckbox = root.CreateButton
	function root:CreateDivider() end
	QT:PopulateMinimapMenu(root)
	for i, key in ipairs({ "Looking for Questing Partners", "Settings", "Compare Party Quests", "Open Quest Journal", "Patch Notes", "Send QT chat message" }) do
		assert(root.labels[i] == T(key), key)
	end
	local tooltip = QT:BuildMinimapTooltipStatus()
	assert(tooltip:find(T("QT Chat Scope") .. ": " .. T("Zone Only"), 1, true))
	assert(tooltip:find(T("Looking for Questing Partners"), 1, true))
	local groups = QT:GetHomeStatusGroups()
	assert(groups[1].title == T("General"))
	assert(groups[1].text:find(T("Version") .. ": 6.1.2", 1, true))
	assert(groups[4].title == T("Quest Sharing"))
end, { locale = "client" })
