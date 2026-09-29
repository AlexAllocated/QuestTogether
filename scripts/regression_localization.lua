-- Private/addon-owned locale data only; never replaces GetLocale or other globals.
local QT = _G.QuestTogether
QT:RegisterTest("localization falls back and resolves Spanish aliases without changing the client", function()
	local translate = QT.TranslateForLocale
	assert(translate("Settings", "xxXX") == "Settings")
	assert(translate("not in any dictionary", "deDE") == "not in any dictionary")
	assert(translate("Settings", "esMX") == translate("Settings", "esES"))
	for _, locale in ipairs({ "deDE", "frFR", "esES", "ptBR", "ruRU" }) do
		assert(translate("Settings", locale) ~= "Settings")
		assert(type(translate("Settings", locale)) == "string")
	end
end)
QT:RegisterTest("localization keeps quest status and sharing model values language independent", function()
	local previous = QT.localizationTestLocale
	for _, locale in ipairs({ "deDE", "frFR", "esES", "ptBR", "ruRU" }) do
		QT.localizationTestLocale = locale
		assert(QT:GetQuestCompareShareableToYouLabel(true) == "Yes")
		assert(QT:GetQuestCompareShareableToYouLabel(false) == "No")
		assert(QT:GetQuestCompareRemoteStatusLabel(true) == "Complete")
		assert(QT:GetChatLogDestinationLabel("main") == QT.TranslateForLocale("Main Chat Window", locale))
		local a = setmetatable({GetQuestStatusLabel=function() return "Ready to Turn In" end}, {__index=QT})
		assert(a:GetQuestStatusAnnouncementEventType(1) == "QUEST_READY_TO_TURN_IN")
	end
	QT.localizationTestLocale = previous
end)
QT:RegisterTest("localized patch notes preserve released version and section structure", function()
	for _, locale in ipairs({ "deDE", "frFR", "esES", "ptBR", "ruRU" }) do
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
