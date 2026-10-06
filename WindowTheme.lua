local QuestTogether = _G.QuestTogether
local TEXTURE = "Interface\\AddOns\\QuestTogether\\Media\\QuestCompareScroll"
local DARK = {
	dark = true,
	texture = TEXTURE,
	tint = { 0.14, 0.17, 0.21 },
	heading = { 1, 0.85, 0.55 },
	body = { 0.93, 0.92, 0.88 },
	muted = { 0.88, 0.85, 0.76 },
}
local LIGHT = {
	dark = false,
	texture = TEXTURE,
	tint = { 1, 1, 1 },
	heading = { 0.22, 0.13, 0.06 },
	body = { 0.23, 0.17, 0.10 },
	muted = { 0.27, 0.19, 0.10 },
}

function QuestTogether:GetScrollWindowTheme()
	return self:GetOption("lightMode") == true and LIGHT or DARK
end

function QuestTogether:RefreshWindowThemes()
	self:QueueReleaseNotesThemeRefresh()
	self:QueuePartyQuestCompareRender()
	local preview = self.partyQuestComparePreview
	if preview and preview.partyQuestCompareSession then
		self:ScheduleDeferredWork("foreign_frame_mutation", "party_compare_preview_theme", function()
			if self.partyQuestComparePreview == preview then
				preview:QueuePartyQuestCompareRender()
			end
		end, 0, "party compare preview theme")
	end
end
