local QT = _G.QuestTogether
local Presenter = {}
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

local function Groups(addon)
	local groups = {
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
		{ key = "area", option = "compareQuestArea", title = L("Quest area"), choices = {
			{ "all", L("All areas") }, { "current", L("Current area") }, { "unknown", L("Unknown area") },
		} },
		{ key = "level", option = "compareQuestLevel", title = L("Quest level"), choices = {
			{ "all", L("All levels") }, { "below", L("At or below my level") },
			{ "above", L("Above my level") }, { "unknown", L("Unknown level") },
		} },
		{ key = "sort", option = "compareQuestSort", title = L("Sort quests"), choices = {
			{ "all", L("Missing quests first") }, { "low", L("Lowest level first") },
			{ "high", L("Highest level first") }, { "title", L("Quest title") },
		} },
	}
	local session = addon and addon.partyQuestCompareSession
	local context = session and session.questAreaContext or {}
	local areas = {}
	for id, name in pairs(context.areas or {}) do areas[#areas + 1] = { "map:" .. id, name } end
	table.sort(areas, function(a, b) return a[2] == b[2] and a[1] < b[1] or a[2] < b[2] end)
	for _, choice in ipairs(areas) do groups[4].choices[#groups[4].choices + 1] = choice end
	return groups
end

local function IsMapFilter(value)
	if type(value) == "string" then
		local id = tonumber(value:match("^map:(%d+)$"))
		if id and id > 0 and id <= 1000000 and value == "map:" .. id then return true end
	end
	return false
end

function QT:IsPartyQuestCompareFilterValue(key, value)
	if key == "area" and IsMapFilter(value) then return true end
	for _, group in ipairs(Groups(self)) do
		if group.key == key then
			for _, choice in ipairs(group.choices) do if choice[1] == value then return true end end
		end
	end
	return false
end

function Presenter:GetPartyQuestCompareFilters()
	local filters = { search = self.partyQuestCompareSession and self.partyQuestCompareSession.search or "" }
	for _, group in ipairs(Groups(self)) do
		local value = self:GetOption(group.option)
		filters[group.key] = group.key == "area" and IsMapFilter(value) and value or "all"
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

function Presenter:SetPartyQuestCompareFilter(key, value)
	local session = self.partyQuestCompareSession
	if not session then
		return
	end
	if key == "search" then
		session.search = value
	else
		for _, group in ipairs(Groups(self)) do
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
	if key ~= "sort" then
		if self.CancelPartyQuestObjectiveRequests then self:CancelPartyQuestObjectiveRequests(session) end
		session.expandedQuestIds = {}
	end
	self:QueuePartyQuestCompareRender()
end

function Presenter:ResetPartyQuestCompareFilters()
	for _, group in ipairs(Groups(self)) do
		self:SetOption(group.option, "all")
	end
	self:SetOption("compareHideOtherQuests", false)
	self:SetPartyQuestCompareFilter("search", "")
end

function Presenter:GetPartyQuestCompareFilterLabel()
	local filters, labels = self:GetPartyQuestCompareFilters(), {}
	for _, group in ipairs(Groups(self)) do
		for _, choice in ipairs(group.choices) do
			if choice[1] ~= "all" and filters[group.key] == choice[1] then
				labels[#labels + 1] = choice[2]
			end
		end
	end
	local context = self.partyQuestCompareSession and self.partyQuestCompareSession.questAreaContext
	if filters.area == "current" and context and context.name then
		for i, label in ipairs(labels) do if label == L("Current area") then labels[i] = label .. ": " .. context.name end end
	elseif filters.area:match("^map:") then
		local id = tonumber(filters.area:match("%d+"))
		if not context or not context.areas[id] then labels[#labels + 1] = L("Quest area") .. ": " .. id end
	end
	return #labels, table.concat(labels, " · ")
end

function QT:CreatePartyQuestFilterMenu(owner, generator)
	return self.API.CreateContextMenu(owner, generator)
end

function Presenter:ShowPartyQuestCompareFilters(owner)
	local session = self.partyQuestCompareSession
	if not session or self:IsWorkBlocked("foreign_frame_mutation") then
		return false
	end
	return self:CreatePartyQuestFilterMenu(owner, function(_, root)
		for _, group in ipairs(Groups(self)) do
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
		local capability = session.chains and session.chains.capability
		if capability and (capability.kind == "questiedb" or capability.kind == "retail") then
			for _, setting in ipairs({
				{ "compareGroupByChain", L("Group by chain") },
				{ "compareHideFutureQuestNames", L("Hide future quest names") },
			}) do
				local option, label = setting[1], setting[2]
				root:CreateCheckbox(label, function() return self:GetOption(option) == true end, function()
					if self.partyQuestCompareSession == session then
						self:SetOption(option, not self:GetOption(option))
						self:QueuePartyQuestCompareRender()
					end
				end)
			end
			if capability and capability.state ~= "ready" and capability.explanation then
				root:CreateTitle(capability.explanation)
			end
		end
		if not self:IsPartyQuestCompareBackgroundSynced(session) then
			root:CreateCheckbox(L("Auto-refresh while open"), function() return self:GetOption("compareAutoRefresh") == true end,
				function() self:SetOption("compareAutoRefresh", not self:GetOption("compareAutoRefresh")) end)
		end

		root:CreateButton(L("Reset filters"), function()
			if self.partyQuestCompareSession == session then
				self:ResetPartyQuestCompareFilters()
			end
		end)
	end)
end

function Presenter:FilterPartyQuestCompareRows(rows)
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
			elseif cell == "Missing" or cell == "Absent" or cell == "Unavailable" then
				missing = missing + 1
			elseif cell == "Completed" then
				-- Completed history is known, but it is neither an active quest
				-- nor a quest ready for turn-in.
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
		local action = filters.action == "all" or (row.action == filters.action
			and not (row.shareReadiness and row.shareReadiness.disabled and row.shareReadiness.state ~= "checking"))
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
		local context = session.questAreaContext or {}
		local area = filters.area == "all" or (filters.area == "unknown" and not row.questAreaMapID)
			or (filters.area == "current" and context.mapID and row.questAreaMapID == context.mapID)
			or (row.questAreaMapID and filters.area == "map:" .. row.questAreaMapID)
		local level = filters.level == "all" or (filters.level == "unknown" and not row.questLevel)
			or (row.questLevel and context.playerLevel and (
				(filters.level == "below" and row.questLevel <= context.playerLevel)
				or (filters.level == "above" and row.questLevel > context.playerLevel)))
		if ownership and progress and action and matches and area and level then
			result[#result + 1] = row
		end
	end
	local function Less(a, b)
		if filters.sort == "low" or filters.sort == "high" then
			if (a.questLevel ~= nil) ~= (b.questLevel ~= nil) then return a.questLevel ~= nil end
			if a.questLevel and a.questLevel ~= b.questLevel then
				if filters.sort == "low" then return a.questLevel < b.questLevel end
				return a.questLevel > b.questLevel
			end
		elseif filters.sort == "all" and (a.missing > 0) ~= (b.missing > 0) then return a.missing > 0 end
		if a.title ~= b.title then return a.title < b.title end
		return a.questId < b.questId
	end
	table.sort(rows, Less)
	table.sort(result, Less)
	session.totalQuests, session.unfilteredQuests = #rows, rows
	return result
end

_G.QuestTogether:RegisterPartyQuestPresentation(Presenter)
