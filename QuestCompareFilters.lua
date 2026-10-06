local QT = _G.QuestTogether
local L = QT.Translate

-- Lua 5.1's string.lower only folds ASCII. Cover the cased alphabets used by
-- WoW locales without depending on a live-client string helper in the preview.
local UPPER =
	"ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞŸŒŠŽẞАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
local LOWER =
	"àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿœšžßабвгдеёжзийклмнопрстуфхцчшщъыьэюя"
local folded, utf8 = {}, "[%z\1-\127\194-\244][\128-\191]*"
local lowerCharacters = LOWER:gmatch(utf8)
for upper in UPPER:gmatch(utf8) do
	folded[upper] = lowerCharacters()
end
local function Fold(text)
	return (text:lower():gsub(utf8, folded))
end

local function Groups()
	return {
		{
			key = "ownership",
			option = "compareQuestOwnership",
			title = L("Quest ownership"),
			choices = {
				{ "all", L("All quests") },
				{ "mine", L("Quests I have") },
				{ "missing", L("Quests I don't have") },
				{ "shared", L("Everyone has the quest") },
				{ "someoneMissing", L("Someone is missing the quest") },
			},
		},
		{
			key = "progress",
			option = "compareQuestProgress",
			title = L("Party progress"),
			choices = {
				{ "all", L("Any progress") },
				{ "ready", L("Everyone ready") },
				{ "someReady", L("Someone is ready") },
				{ "active", L("In progress") },
				{ "unknown", L("Incomplete data") },
			},
		},
		{
			key = "action",
			option = "compareQuestAction",
			title = L("Available action"),
			choices = {
				{ "all", L("Any action") },
				{ "share", L("Can share") },
				{ "request", L("Can request share") },
			},
		},
	}
end

function QT:GetPartyQuestCompareFilters()
	local filters = { search = self.partyQuestCompareSession and self.partyQuestCompareSession.search or "" }
	for _, group in ipairs(Groups()) do
		local value = self:GetOption(group.option)
		filters[group.key] = "all"
		for _, choice in ipairs(group.choices) do
			if choice[1] == value then
				filters[group.key] = value
			end
		end
	end
	-- Preserve the old checkbox preference until changed through the new menu.
	if filters.ownership == "all" and self:GetOption("compareHideOtherQuests") == true then
		filters.ownership = "mine"
	end
	return filters
end

function QT:SetPartyQuestCompareFilter(key, value)
	local session = self.partyQuestCompareSession
	if not session then
		return
	end
	if key == "search" then
		session.search = value
	else
		for _, group in ipairs(Groups()) do
			if key == group.key then
				for _, choice in ipairs(group.choices) do
					if choice[1] == value then
						self:SetOption(group.option, value)
						if key == "ownership" then
							self:SetOption("compareHideOtherQuests", value == "mine")
						end
					end
				end
			end
		end
	end
	session.offset, session.scrollPixels, session.restoreAnchor = 0, 0, nil
	if self.partyQuestCompareWindow then
		local frame = self.partyQuestCompareWindow
		frame.wheelTarget, frame.expansions, frame.animateExpansion = nil, nil, nil
		frame:SetScript("OnUpdate", nil)
		if frame.expansionAnimator then
			frame.expansionAnimator:SetScript("OnUpdate", nil)
		end
	end
	if self.CancelPartyQuestObjectiveRequests then
		self:CancelPartyQuestObjectiveRequests(session)
	end
	session.expandedQuestIds = {}
	self:QueuePartyQuestCompareRender()
end

function QT:ResetPartyQuestCompareFilters()
	for _, group in ipairs(Groups()) do
		self:SetOption(group.option, "all")
	end
	self:SetOption("compareHideOtherQuests", false)
	self:SetPartyQuestCompareFilter("search", "")
end

function QT:GetPartyQuestCompareFilterLabel()
	local filters, labels = self:GetPartyQuestCompareFilters(), {}
	for _, group in ipairs(Groups()) do
		for _, choice in ipairs(group.choices) do
			if choice[1] ~= "all" and filters[group.key] == choice[1] then
				labels[#labels + 1] = choice[2]
			end
		end
	end
	return #labels, table.concat(labels, " · ")
end

function QT:CreatePartyQuestFilterMenu(owner, generator)
	return self.API.CreateContextMenu(owner, generator)
end

function QT:ShowPartyQuestCompareFilters(owner)
	local session = self.partyQuestCompareSession
	if not session or self:IsWorkBlocked("foreign_frame_mutation") then
		return false
	end
	return self:CreatePartyQuestFilterMenu(owner, function(_, root)
		for _, group in ipairs(Groups()) do
			local submenu = root:CreateButton(group.title)
			for _, choice in ipairs(group.choices) do
				local key, value = group.key, choice[1]
				submenu:CreateCheckbox(choice[2], function()
					return self:GetPartyQuestCompareFilters()[key] == value
				end, function()
					if self.partyQuestCompareSession == session then
						self:SetPartyQuestCompareFilter(key, value)
					end
				end)
			end
		end
		root:CreateDivider()
		root:CreateCheckbox(L("Auto-refresh while open"), function() return self:GetOption("compareAutoRefresh") == true end,
			function() self:SetOption("compareAutoRefresh", not self:GetOption("compareAutoRefresh")) end)

		root:CreateButton(L("Reset filters"), function()
			if self.partyQuestCompareSession == session then
				self:ResetPartyQuestCompareFilters()
			end
		end)
	end)
end

function QT:FilterPartyQuestCompareRows(rows)
	local session, filters, result = self.partyQuestCompareSession, self:GetPartyQuestCompareFilters(), {}
	local own = session.byName[session.playerName]
	local search = Fold(filters.search):match("^%s*(.-)%s*$")
	for _, row in ipairs(rows) do
		local have, ready, missing, active, unknown = 0, 0, 0, 0, 0
		for i, member in ipairs(session.members) do
			local cell = row.cells[i]
			if member.state ~= "ready" then
				unknown = unknown + 1
			elseif cell == "Ready" then
				have, ready = have + 1, ready + 1
			elseif cell == "Have" then
				have, active = have + 1, active + 1
			elseif cell == "Missing" then
				missing = missing + 1
			else
				unknown = unknown + 1
			end
		end
		local ownership = filters.ownership == "all"
			or (filters.ownership == "mine" and own.entries[row.questId] ~= nil)
			or (filters.ownership == "missing" and own.state == "ready" and not own.entries[row.questId])
			or (filters.ownership == "shared" and have == #session.members)
			or (filters.ownership == "someoneMissing" and missing > 0)
		local progress = filters.progress == "all"
			or (filters.progress == "ready" and ready == #session.members)
			or (filters.progress == "someReady" and ready > 0)
			or (filters.progress == "active" and active > 0)
			or (filters.progress == "unknown" and unknown > 0)
		local action = filters.action == "all" or row.action == filters.action
		local matches = search == ""
			or tostring(row.questId):find(search, 1, true)
			or Fold(row.title):find(search, 1, true)
		if not matches then
			-- Search both the displayed local title and peers' source-language titles.
			for _, member in ipairs(session.members) do
				local entry = member.entries[row.questId]
				if entry and entry.questTitle and Fold(entry.questTitle):find(search, 1, true) then
					matches = true
					break
				end
			end
		end
		if ownership and progress and action and matches then
			result[#result + 1] = row
		end
	end
	session.totalQuests, session.unfilteredQuests = #rows, rows
	return result
end
